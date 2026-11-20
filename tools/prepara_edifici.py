"""Icone degli edifici rifatte con l'IA locale: base dipinta + simbolo della bottega (ADR-060).

Uso:  python tools/prepara_edifici.py <cartella conversione_icone> [--fogli <cartella>] [--solo E001,E080]

La cartella conversione_icone (AI-Playground/media/conversione_icone) contiene:
- risultati/B###.png   le basi senza insegna (1024x768 su grigio uniforme), una per gruppo di edifici simili;
- risultati/S##.png    i simboli di cio' che l'edificio produce (1024x1024 su grigio uniforme);
- lotto/composizione.json  per ogni edificio E### la base, l'insegna dell'originale con il suo riquadro e il simbolo;
- indice.csv           il percorso originale di ogni E### e le copie identiche (alias) in altre cartelle di religione;
- _strumenti/tmp_B###.png  la base dell'originale (68x50) senza insegna: da qui l'ingombro della base nell'icona.

Per ogni edificio: fondo grigio scontornato, base posata nell'ingombro della base originale x4 (272x200, quattro volte
l'icona 68x50, in basso e al centro di quell'ingombro), simbolo nel riquadro dell'insegna originale x4 (senza ombra dal 15/11, piu'
piccolo, una sola lancia per il lanciaio). Ogni percorso originale (anche gli alias) riceve la sua copia in
assets/rifatti/campmap/review_panel/buildings/<cartella>/<nome>.png, che AssetLibrary.texture usa al posto
dell'immagine dell'installazione (ADR-043). Con --fogli scrive i fogli di confronto originale / rifatto.
"""
import csv
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

SCALE = 4
ICON = (68 * SCALE, 50 * SCALE)
TOL = 10              # distanza massima dal grigio del fondo (per canale)
SEAL = 5              # chiude le fessure strette prima di cercare il fondo raggiungibile dai bordi
HOLE_MIN = 0.0006     # buchi interni di fondo (manico, anello dell'ancora) piu' grandi di questa frazione: trasparenti
SYMBOL_KEEP = 0.12    # nei simboli si tengono i pezzi grandi almeno cosi' rispetto al maggiore (via i frammenti)
BASE_KEEP = 0.02
SYMBOL_GROW = 0.8     # misura del simbolo rispetto al riquadro dell'insegna originale (Federico 15/11: un po' piu' piccoli)
SYMBOL_MAX = (19, 24)  # tetto in pixel dell'icona 68x50: i riquadri larghi (mercanti, RETT) non gonfiano il simbolo
SYMBOL_SHADOW = False  # alone scuro attorno al simbolo: tolto il 15/11 («brutte e non necessarie»)
## Simboli di cui si tiene un solo pezzo, il piu' a sinistra tra i maggiori (il lanciaio ha due lance: ne basta una).
SYMBOL_SINGLE = {"S06"}
## Scritte dell'originale da rimettere sull'icona (i campi migliorati hanno la resa in basso: +20%, +60%, +80%; il livello 2
## della XL e' il disboscamento, senza scritta). Il dipinto della base non le ha: si scrivono qui.
CAPTIONS = {"E039": "+20%", "E040": "+60%", "E041": "+80%"}
CAPTION_FONT = "Alegreya-760-nitido.ttf"
CAPTION_ROOM = 48     # pixel (su 200) lasciati liberi in basso per la scritta
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "rifatti", "campmap", "review_panel", "buildings")


def cut_grey(path, keep, single=False):
    """Immagine RGBA ritagliata sul suo ingombro, con trasparente il grigio uniforme del fondo. Con `single` resta solo il
    pezzo piu' a sinistra tra quelli grandi almeno quanto `keep` del maggiore."""
    rgb = Image.open(path).convert("RGB")
    a = np.asarray(rgb).astype(np.int16)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)
    near = np.abs(a - bg).max(axis=2) <= TOL
    solid = ndimage.binary_closing(~near, structure=np.ones((SEAL, SEAL)), border_value=0)
    lab, n = ndimage.label(~solid)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    back = np.isin(lab, edge[edge > 0])
    # buchi interni grandi e uniformi del colore del fondo
    hl, hn = ndimage.label(near & ~back)
    if hn:
        sizes = ndimage.sum(np.ones_like(hl), hl, range(1, hn + 1))
        big = np.nonzero(sizes >= HOLE_MIN * near.size)[0] + 1
        back |= np.isin(hl, big)
    fg = ~back
    fl, fn = ndimage.label(fg)
    if fn > 1:
        sizes = ndimage.sum(fg, fl, range(1, fn + 1))
        kept = np.nonzero(sizes >= sizes.max() * keep)[0] + 1
        if single and len(kept) > 1:
            lefts = [np.nonzero(fl == k)[1].min() for k in kept]
            kept = [kept[int(np.argmin(lefts))]]
        fg = np.isin(fl, kept)
    mask = Image.fromarray((fg * 255).astype(np.uint8), "L")
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    out = rgb.convert("RGBA")
    out.putalpha(mask)
    return out.crop(mask.point(lambda v: 255 if v > 24 else 0).getbbox())


def fit(img, box):
    k = min(box[0] / img.width, box[1] / img.height)
    return img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)


def shadow(img, radius=3, strength=0.75):
    """Alone scuro attorno al simbolo, per leggerlo sopra tetti e pietre."""
    pad = radius * 3
    alpha = Image.new("L", (img.width + 2 * pad, img.height + 2 * pad), 0)
    alpha.paste(img.getchannel("A"), (pad, pad))
    alpha = alpha.filter(ImageFilter.MaxFilter(radius * 2 - 1)).filter(ImageFilter.GaussianBlur(radius))
    alpha = alpha.point(lambda v: round(v * strength))
    out = Image.new("RGBA", alpha.size, (12, 8, 4, 0))
    out.putalpha(alpha)
    out.alpha_composite(img, (pad, pad))
    return out, pad


def original_box(src, base_id):
    """Ingombro della base nell'icona originale 68x50 (senza insegna), moltiplicato per SCALE."""
    path = os.path.join(src, "_strumenti", "tmp_%s.png" % base_id)
    if not os.path.exists(path):
        return (0, 0, ICON[0], ICON[1])
    box = Image.open(path).convert("RGBA").getchannel("A").point(lambda v: 255 if v > 0 else 0).getbbox()
    return tuple(v * SCALE for v in box) if box else (0, 0, ICON[0], ICON[1])


def compose(base, base_box, symbol, symbol_box):
    out = Image.new("RGBA", ICON, (0, 0, 0, 0))
    x0, y0, x1, y1 = base_box
    art = fit(base, (x1 - x0, y1 - y0))
    out.alpha_composite(art, (x0 + (x1 - x0 - art.width) // 2, y1 - art.height))
    if symbol is not None:
        sx0, sy0, sx1, sy1 = [v * SCALE for v in symbol_box]
        w = min((sx1 - sx0) * SYMBOL_GROW, SYMBOL_MAX[0] * SCALE)
        h = min((sy1 - sy0) * SYMBOL_GROW, SYMBOL_MAX[1] * SCALE)
        sym = fit(symbol, (round(w), round(h)))
        sym, pad = shadow(sym) if SYMBOL_SHADOW else (sym, 0)
        cx, cy = (sx0 + sx1) / 2, (sy0 + sy1) / 2
        x = min(max(round(cx - sym.width / 2), -pad), ICON[0] - sym.width + pad)
        y = min(max(round(cy - sym.height / 2), -pad), ICON[1] - sym.height + pad)
        layer = Image.new("RGBA", (ICON[0] + 2 * pad, ICON[1] + 2 * pad), (0, 0, 0, 0))
        layer.alpha_composite(sym, (x + pad, y + pad))
        out.alpha_composite(layer.crop((pad, pad, pad + ICON[0], pad + ICON[1])))
    return out


def caption(img, text):
    """Scritta in basso a sinistra come nell'originale: chiara, con un contorno scuro, leggibile anche a 68x50."""
    from PIL import ImageFont
    font = ImageFont.truetype(os.path.join(HERE, "..", "assets", "fonts", CAPTION_FONT), 54)
    out = img.copy()
    d = ImageDraw.Draw(out)
    x0, y0, x1, y1 = d.textbbox((0, 0), text, font=font, stroke_width=4)
    x, y = (ICON[0] - (x1 - x0)) // 2 - x0, ICON[1] - 2 - y1
    d.text((x, y), text, font=font, fill=(246, 234, 200, 255), stroke_width=4, stroke_fill=(28, 18, 8, 255))
    return out


def original_paths(src):
    """E### -> percorsi originali (campmap/review_panel/Buildings/...), alias compresi."""
    paths = {}
    with open(os.path.join(src, "indice.csv"), encoding="utf-8") as f:
        for row in csv.reader(f, delimiter=";"):
            if not row or not row[0].startswith("E"):
                continue
            main = row[2][: -len(".BIF.png")]
            folder = os.path.dirname(main)
            items = ["campmap/" + main]
            for alias in (row[4].split(";") if len(row) > 4 and row[4].strip() else []):
                items.append("campmap/review_panel/Buildings/" + alias.strip())
            paths[row[0]] = items
            assert folder.startswith("review_panel/Buildings")
    return paths


def target(original):
    rel = original.replace("\\", "/").lower()
    assert rel.startswith("campmap/review_panel/buildings/")
    return os.path.join(OUT, rel[len("campmap/review_panel/buildings/"):] + ".png")


def sheets(src, done, folder):
    """Fogli di confronto: originale (ingrandito) e rifatto su fondo di pergamena scura, 24 edifici per foglio."""
    os.makedirs(folder, exist_ok=True)
    game = None
    for cand in (os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "originale"),):
        if os.path.isdir(cand):
            game = os.path.join(cand, "_ASSET_EXPORT", "03_Illustrazioni_Info")
    cw, ch, per = ICON[0] // 2, ICON[1] // 2, 24
    items = sorted(done.items())
    for k in range(0, len(items), per):
        part = items[k:k + per]
        cols = 4
        rows = (len(part) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * (2 * cw + 30), rows * (ch + 22)), (74, 52, 34, 255))
        d = ImageDraw.Draw(sheet)
        for i, (eid, (orig, img)) in enumerate(part):
            x, y = (i % cols) * (2 * cw + 30), (i // cols) * (ch + 22)
            if game:
                p = os.path.join(game, "campmap", orig + ".BIF.png")
                if os.path.exists(p):
                    o = Image.open(p).convert("RGBA").resize((cw, ch), Image.NEAREST)
                    sheet.alpha_composite(o, (x + 4, y + 2))
            sheet.alpha_composite(img.resize((cw, ch), Image.LANCZOS), (x + cw + 8, y + 2))
            d.text((x + 6, y + ch + 4), "%s %s" % (eid, os.path.basename(orig)[:28]), fill=(240, 225, 190))
        sheet.convert("RGB").save(os.path.join(folder, "foglio_edifici_%02d.png" % (k // per + 1)))


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    src = args[0]
    folder = args[args.index("--fogli") + 1] if "--fogli" in args else None
    only = set(args[args.index("--solo") + 1].split(",")) if "--solo" in args else None
    comp = json.load(open(os.path.join(src, "lotto", "composizione.json"), encoding="utf-8"))
    alias = comp.get("alias_basi", {})
    paths = original_paths(src)
    res = os.path.join(src, "risultati")
    bases, symbols, done, written, missing = {}, {}, {}, 0, []
    for eid, e in sorted(comp["edifici"].items()):
        if only and eid not in only:
            continue
        bid = e["base"]
        img_id = alias.get(bid, bid)
        bpath = os.path.join(res, img_id + ".png")
        if not os.path.exists(bpath):
            missing.append("%s (base %s)" % (eid, img_id))
            continue
        if img_id not in bases:
            bases[img_id] = cut_grey(bpath, BASE_KEEP)
        sym, box = None, None
        concept = e.get("concetto")
        if e.get("insegna") and concept:
            spath = os.path.join(res, concept + ".png")
            if not os.path.exists(spath):
                missing.append("%s (simbolo %s)" % (eid, concept))
                continue
            if concept not in symbols:
                symbols[concept] = cut_grey(spath, SYMBOL_KEEP, concept in SYMBOL_SINGLE)
            sym, box = symbols[concept], e["bbox"]
        bbox = original_box(src, bid)
        if eid in CAPTIONS:                       # la scritta sta sotto il disegno, come nell'originale
            bbox = (bbox[0], bbox[1], bbox[2], min(bbox[3], ICON[1] - CAPTION_ROOM))
        img = compose(bases[img_id], bbox, sym, box)
        if eid in CAPTIONS:
            img = caption(img, CAPTIONS[eid])
        for original in paths[eid]:
            dest = target(original)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            img.save(dest, optimize=True)
            written += 1
        done[eid] = (paths[eid][0][len("campmap/"):], img)
    print("edifici", len(done), "file scritti", written, "basi", len(bases), "simboli", len(symbols))
    for m in missing:
        print("manca", m)
    if folder:
        sheets(src, done, folder)


if __name__ == "__main__":
    main()
