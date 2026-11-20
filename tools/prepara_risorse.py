"""Icone di merci e giacimenti rifatte con AI Playground (ADR-071).

Legge `AI-Playground/media/conversione_risorse/risultati/<ID>_<chiave>.png` (1024x1024 su grigio uniforme) e la coda
`_strumenti/coda.json` (ID -> icona originale) e scrive in `assets/rifatti/campmap/parchments/icons/` un PNG per icona,
con il nome che AssetLibrary.remade_path si aspetta dall'originale. Il fondo grigio raggiungibile dai bordi diventa
trasparente; i buchi interni grandi del colore del fondo (l'ansa del manico della brocca) pure, tranne dove il grigio fa
parte del soggetto (celle del favo). Il soggetto ritagliato sta in una tela di 8 volte l'originale (144x160), centrato.
Osso di balena e peltro non hanno un'icona nell'originale: prendono i nomi nuovi goods_whalebone e goods_pewter, a cui
punta data/ui/icone.cfg.

Uso: python tools/prepara_risorse.py [cartella conversione_risorse]   (senza argomento: ~/Documents/AI-Playground/media/...)
Scrive anche `foglio_risorse.png` nella cartella di conversione, per il confronto con gli originali.
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "rifatti", "campmap", "parchments", "icons")
CANVAS = (144, 160)          # 8 x 18x20 dell'originale
MARGIN = 4
TOL = 12                     # distanza massima dal grigio del fondo (per canale)
HOLE_MIN = 0.0015            # buchi interni del colore del fondo piu' grandi di questa frazione: trasparenti
KEEP_HOLES = {"M09"}         # il grigio dentro le celle del favo e' parte del disegno
NEW_NAMES = {"M23": "goods_whalebone", "M24": "goods_pewter"}


def shift_or(m):
    o = m.copy()
    o[1:] |= m[:-1]; o[:-1] |= m[1:]; o[:, 1:] |= m[:, :-1]; o[:, :-1] |= m[:, 1:]
    return o


def grow(seed, allowed):
    """Regione di `allowed` connessa a `seed` (4-vicinato), per dilatazioni successive."""
    cur = seed & allowed
    while True:
        nxt = shift_or(cur) & allowed
        if (nxt == cur).all():
            return cur
        # salti piu' lunghi per far prima: 8 dilatazioni per controllo
        for _ in range(7):
            nxt = shift_or(nxt) & allowed
        cur = nxt


def components(mask):
    """Etichette dei pezzi di `mask` (piccolo numero di pezzi: riempimento da un seme alla volta)."""
    lab = np.zeros(mask.shape, np.int32)
    left = mask.copy()
    k = 0
    while left.any():
        k += 1
        y, x = np.argwhere(left)[0]
        seed = np.zeros_like(mask); seed[y, x] = True
        reg = grow(seed, left)
        lab[reg] = k
        left &= ~reg
    return lab, k


def cut_grey(path, keep_holes):
    rgb = Image.open(path).convert("RGB")
    a = np.asarray(rgb).astype(np.int16)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)
    near = np.abs(a - bg).max(axis=2) <= TOL
    edge = np.zeros_like(near); edge[0] = edge[-1] = True; edge[:, 0] = edge[:, -1] = True
    back = grow(edge, near)
    if not keep_holes:
        holes = near & ~back
        if holes.any():
            lab, n = components(holes)
            for k in range(1, n + 1):
                if (lab == k).sum() >= HOLE_MIN * near.size:
                    back |= lab == k
    fg = ~back
    # via i pezzetti staccati (meno del 2% del pezzo maggiore)
    lab, n = components(fg)
    if n > 1:
        sizes = np.bincount(lab.ravel())[1:]
        fg = np.isin(lab, np.nonzero(sizes >= sizes.max() * 0.02)[0] + 1)
    mask = Image.fromarray((fg * 255).astype(np.uint8), "L")
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    out = rgb.convert("RGBA")
    out.putalpha(mask)
    return out.crop(mask.point(lambda v: 255 if v > 24 else 0).getbbox())


def place(img):
    box = (CANVAS[0] - 2 * MARGIN, CANVAS[1] - 2 * MARGIN)
    k = min(box[0] / img.width, box[1] / img.height)
    small = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    c = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    c.alpha_composite(small, ((CANVAS[0] - small.width) // 2, (CANVAS[1] - small.height) // 2))
    return c


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Documents/AI-Playground/media/conversione_risorse")
    queue = json.load(open(os.path.join(src, "_strumenti", "coda.json"), encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    done = []
    for it in queue:
        res = os.path.join(src, "risultati", os.path.basename(it["file"]))
        if not os.path.exists(res):
            print("manca", it["id"]); continue
        name = NEW_NAMES.get(it["id"], it["originale"].split(".")[0]).lower()
        icon = place(cut_grey(res, it["id"] in KEEP_HOLES))
        icon.save(os.path.join(OUT, name + ".png"))
        done.append((it, name, icon))
        print(it["id"], "->", name + ".png")
    # foglio di controllo: grande, alla misura della pergamena (27x30) e su pergamena scura
    cell = 170
    sheet = Image.new("RGB", (cell * 6, ((len(done) + 5) // 6) * (cell + 50)), (214, 196, 160))
    d = ImageDraw.Draw(sheet)
    for i, (it, name, icon) in enumerate(done):
        x, y = (i % 6) * cell + 8, (i // 6) * (cell + 50) + 6
        sheet.paste(icon.resize((108, 120), Image.LANCZOS), (x, y), icon.resize((108, 120), Image.LANCZOS))
        s = icon.resize((27, 30), Image.LANCZOS); sheet.paste(s, (x + 118, y + 10), s)
        s = icon.resize((20, 22), Image.LANCZOS); sheet.paste(s, (x + 122, y + 50), s)
        d.text((x, y + 124), f"{it['id']} {it['nome']}"[:24], fill=(40, 25, 10))
    sheet.save(os.path.join(src, "foglio_risorse.png"))


if __name__ == "__main__":
    main()
