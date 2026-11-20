"""Carte delle unita' e delle navi rifatte con l'IA locale (conversione_icone di AI Playground).

Uso:  python tools/prepara_unita.py <cartella conversione_icone> [ID ...] [--fogli <cartella>] [--schede]

Per ogni U### / N### di conversione_icone/indice.csv prende risultati/<file> (1024x1024 su grigio uniforme), toglie il
fondo grigio e l'ombra sul terreno, ritaglia la figura e la posa in basso al centro su 200x200 trasparente (4 volte la carta
50x50 di campmap/review_panel/Units o Ships). Scrive assets/rifatti/campmap/review_panel/<units|ships>/<nome>.png, che
AssetLibrary.texture usa al posto della carta dell'installazione (ADR-043). Con --fogli salva anche fogli di controllo
(originale, rifatto su pergamena, rifatto su scuro).
"""
import csv
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

CARD = (200, 200)
SHEET = (732, 896)      # 2 volte l'illustrazione 366x448 di Info_Pics
SHEET_TOP = 0.31        # sotto nome e dati della scheda (fino a ~130 su 448)
SHEET_BOTTOM = 0.985
SHEET_WIDTH = 0.92
GAME = os.environ.get("MTW_GAME_DIR", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "originale"))
INFO_PICS = [os.path.join(GAME, "_ASSET_EXPORT", "03_Illustrazioni_Info", "campmap", "Info_Pics"),
             os.path.expanduser("~/mnt/_ASSET_EXPORT/03_Illustrazioni_Info/campmap/Info_Pics")]
TOL = 14              # distanza dal grigio del fondo stimato (per canale)
SEAL = 5
SHADOW_SAT = 14       # ombra sul terreno: grigio quasi neutro...
SHADOW_DARK = 75      # ...piu' scuro del fondo al massimo di tanto...
SHADOW_GRAD = 7       # ...e liscio (le armature hanno spigoli e riflessi)
SHADOW_FROM = 0.55    # solo nella parte bassa dell'immagine
KEEP = 0.04           # pezzi staccati tenuti se grandi almeno cosi' rispetto al maggiore
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "rifatti", "campmap", "review_panel")


def background(a):
    """Fondo stimato pixel per pixel: piano interpolato dai bordi (i fondi dell'IA non sono perfettamente piatti)."""
    h, w, _ = a.shape
    ys, xs, vals = [], [], []
    for edge, yy, xx in ((a[0], np.zeros(w), np.arange(w)), (a[-1], np.full(w, h - 1), np.arange(w)),
                         (a[:, 0], np.arange(h), np.zeros(h)), (a[:, -1], np.arange(h), np.full(h, w - 1))):
        ys.append(yy); xs.append(xx); vals.append(edge)
    ys, xs, vals = np.concatenate(ys), np.concatenate(xs), np.concatenate(vals).astype(float)
    A = np.c_[np.ones_like(xs), xs, ys]
    coef, *_ = np.linalg.lstsq(A, vals, rcond=None)
    gy, gx = np.mgrid[0:h, 0:w]
    return coef[0] + coef[1] * gx[..., None] + coef[2] * gy[..., None]


def cut(path):
    rgb = Image.open(path).convert("RGB")
    a = np.asarray(rgb).astype(np.int16)
    h, w, _ = a.shape
    bg = background(a)
    diff = a - bg
    near = np.abs(diff).max(axis=2) <= TOL
    sat = a.max(axis=2) - a.min(axis=2)
    lum = a.mean(axis=2)
    dark = (bg.mean(axis=2) - lum)
    grad = ndimage.gaussian_filter(np.hypot(ndimage.sobel(lum, 0), ndimage.sobel(lum, 1)), 2) / 8
    rows = np.arange(h)[:, None] >= SHADOW_FROM * h
    shade = rows & (sat <= SHADOW_SAT) & (dark > 0) & (dark <= SHADOW_DARK) & (grad <= SHADOW_GRAD)
    bgish = near | shade
    solid = ndimage.binary_closing(~bgish, structure=np.ones((SEAL, SEAL)), border_value=0)
    lab, _ = ndimage.label(~solid)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    back = np.isin(lab, edge[edge > 0])
    hl, hn = ndimage.label(near & ~back)          # buchi interni del colore del fondo (tra gambe, redini...)
    if hn:
        sizes = ndimage.sum(np.ones_like(hl), hl, range(1, hn + 1))
        back |= np.isin(hl, np.nonzero(sizes >= 0.0004 * near.size)[0] + 1)
    fg = ~back
    fl, fn = ndimage.label(fg)
    if fn > 1:
        sizes = ndimage.sum(fg, fl, range(1, fn + 1))
        fg = np.isin(fl, np.nonzero(sizes >= sizes.max() * KEEP)[0] + 1)
    mask = Image.fromarray((fg * 255).astype(np.uint8), "L")
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    out = rgb.convert("RGBA")
    out.putalpha(mask)
    return out.crop(mask.point(lambda v: 255 if v > 24 else 0).getbbox())


def card(path):
    return card_from(cut(path))


def card_from(art):
    k = min((CARD[0] - 4) / art.width, (CARD[1] - 2) / art.height)
    art = art.resize((max(1, round(art.width * k)), max(1, round(art.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", CARD, (0, 0, 0, 0))
    out.alpha_composite(art, ((CARD[0] - art.width) // 2, CARD[1] - 1 - art.height))
    return out


def sheet(art):
    top, bottom = round(SHEET[1] * SHEET_TOP), round(SHEET[1] * SHEET_BOTTOM)
    k = min(SHEET[0] * SHEET_WIDTH / art.width, (bottom - top) / art.height)
    art = art.resize((max(1, round(art.width * k)), max(1, round(art.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", SHEET, (0, 0, 0, 0))
    out.alpha_composite(art, ((SHEET[0] - art.width) // 2, bottom - art.height))
    return out


def info_pic_exists(folder, stem):
    for base in INFO_PICS:
        d = os.path.join(base, folder)
        if os.path.isdir(d):
            return any(f.lower().startswith(stem.lower() + ".bif") for f in os.listdir(d))
    return True     # esportazione non trovata: si scrive comunque


def rows(src):
    with open(os.path.join(src, "indice.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f, delimiter=";"):
            if r["id"][:1] in ("U", "N"):
                yield r


def target(original):
    # originale come review_panel/Units/Arbalester.BIF.png o review_panel/Ships/Baggala.BIF__f01.png
    folder, name = original.split("/")[1], original.split("/")[2]
    stem = name.split(".BIF")[0]
    return os.path.join(OUT, folder.lower(), stem.lower() + ".png")


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); sys.exit(2)
    sheets = None
    schede = "--schede" in args
    if schede:
        args.remove("--schede")
    if "--fogli" in args:
        i = args.index("--fogli"); sheets = args[i + 1]; del args[i:i + 2]
    src, only = args[0], set(args[1:])
    done = []
    n_sheets = 0
    for r in rows(src):
        if only and r["id"] not in only:
            continue
        res = os.path.join(src, "risultati", os.path.basename(r["file"]))
        if not os.path.exists(res):
            print("manca", r["id"]); continue
        art = cut(res)
        img = card_from(art)
        dest = target(r["originale"])
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        img.save(dest, optimize=True)
        done.append((r, img))
        folder, stem = r["originale"].split("/")[1], r["originale"].split("/")[2].split(".BIF")[0]
        if schede and info_pic_exists(folder, stem):
            d = os.path.join(OUT, "..", "info_pics", folder.lower(), stem.lower() + ".png")
            os.makedirs(os.path.dirname(d), exist_ok=True)
            sheet(art).save(d, optimize=True)
            n_sheets += 1
    print("carte scritte:", len(done), "schede:", n_sheets)
    if sheets:
        exp = os.path.join(src, "..", "..", "..", "..", "Documents")  # non usato
        os.makedirs(sheets, exist_ok=True)
        per = 40
        for s in range(0, len(done), per):
            chunk = done[s:s + per]
            cols = 8
            sh = Image.new("RGBA", (cols * 3 * 104, ((len(chunk) + cols - 1) // cols) * 104), (60, 60, 60, 255))
            for k, (r, img) in enumerate(chunk):
                x, y = (k % cols) * 312, (k // cols) * 104
                for j, col in enumerate([(205, 185, 140, 255), (35, 28, 22, 255)]):
                    tile = Image.new("RGBA", (100, 100), col)
                    tile.alpha_composite(img.resize((100, 100), Image.LANCZOS))
                    sh.alpha_composite(tile, (x + 104 * (j + 1), y))
                o = os.path.join(src, "unita" if r["id"][0] == "U" else "navi", os.path.basename(r["file"]))
                if os.path.exists(o):
                    sh.alpha_composite(Image.open(o).convert("RGBA").resize((100, 100)), (x, y))
            sh.convert("RGB").save(os.path.join(sheets, "carte_%02d.jpg" % (s // per + 1)), quality=82)


if __name__ == "__main__":
    main()
