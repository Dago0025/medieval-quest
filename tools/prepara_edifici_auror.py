"""Edifici, castelli e fortezza degli Auror (25/11/2026) dalle immagini di AI Playground.

Uso:  python tools/prepara_edifici_auror.py <media/auror_edifici> <media/conversione_icone> [--indice <file>] [--foglio <png>]

Le immagini (Edit by Prompt 2 sulle icone occidentali rifatte, prompt nel documento di progetto prompt/edifici_auror.md):
  AB###.png        base Auror della base occidentale B### (stessa inquadratura): come prepara_edifici, ogni edificio E### che
                   usa quella base riceve base Auror + il suo simbolo, in
                   assets/rifatti/campmap/review_panel/buildings/auror/<nome del livello>.png (272x200).
                   BuildingArt la sceglie per la religione IMPERIAL (Culto Imperiale, solo in modalita' Auror).
  AC_<GRADO>.png   castelli dello stile «auror» (CastleStyle): icona review_panel/buildings/auror/<grado>.png e pedina
                   pieces/buildings/auror/<grado>.png (stendardo e aste dell'originale, come prepara_castelli_mappa).
  AC_ATLANTIDE.png fortezza della regione natia (FortressArt): fortezza_auror.png, icona e pedina (gia' grigia: niente
                   stone_grey; prepara_fortezza_auror.atlantide schiarisce le ombre e ammorbidisce l'ombra a terra).
Con --indice si aggiungono a data/ui/indice_immagini.txt le voci campmap/review_panel/Buildings/Auror/<Nome>.BIF che mancano
(AssetLibrary trova le varianti solo nell'indice).
"""
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prepara_edifici as pe  # noqa: E402
from prepara_castelli_mappa import build  # noqa: E402
from prepara_fortezza_auror import atlantide, icon_from, piece_from  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "rifatti", "campmap")
TIERS = ["FORT", "KEEP", "CASTLE", "CITADEL", "FORTRESS"]
FOLDER = "auror"
INDEX_TAG = "rifatta-auror"


def save(img, *parts):
    d = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(d), exist_ok=True)
    img.save(d, optimize=True)
    return d


def buildings(src, icons):
    comp = json.load(open(os.path.join(icons, "lotto", "composizione.json"), encoding="utf-8"))
    alias = comp.get("alias_basi", {})
    paths = pe.original_paths(icons)
    res = os.path.join(icons, "risultati")
    bases, symbols, names, out = {}, {}, {}, []
    for eid, e in sorted(comp["edifici"].items()):
        bid = e["base"]
        img_id = alias.get(bid, bid)
        apath = os.path.join(src, "A" + img_id + ".png")
        if not os.path.isfile(apath):
            continue
        if img_id not in bases:
            bases[img_id] = pe.cut_grey(apath, pe.BASE_KEEP)
        sym, box = None, None
        concept = e.get("concetto")
        if e.get("insegna") and concept:
            if concept not in symbols:
                symbols[concept] = pe.cut_grey(os.path.join(res, concept + ".png"), pe.SYMBOL_KEEP, concept in pe.SYMBOL_SINGLE)
            sym, box = symbols[concept], e["bbox"]
        img = pe.compose(bases[img_id], pe.original_box(icons, bid), sym, box)
        for original in paths[eid]:
            name = os.path.basename(original)            # «armourers workshop» (senza .BIF)
            key = name.lower()
            if key in names:
                continue
            names[key] = name
            save(img, "review_panel", "buildings", FOLDER, key + ".png")
            out.append((name, img))
    return out


def castles(src):
    out = []
    for tier in TIERS:
        p = os.path.join(src, "AC_%s.png" % tier)
        if not os.path.isfile(p):
            continue
        icon = icon_from(pe.cut_grey(p, pe.BASE_KEEP))
        save(icon, "review_panel", "buildings", FOLDER, tier.lower() + ".png")
        _, piece = build(tier, p)
        save(piece, "pieces", "buildings", FOLDER, tier.lower() + ".png")
        out += [(tier, icon), (tier + " mappa", piece)]
    p = os.path.join(src, "AC_ATLANTIDE.png")
    if os.path.isfile(p):
        art, body = atlantide(p)
        icon = icon_from(art)
        _, piece = piece_from(art, body)
        save(icon, "review_panel", "buildings", "fortezza_auror.png")
        save(piece, "pieces", "buildings", "fortezza_auror.png")
        out += [("fortezza", icon), ("fortezza mappa", piece)]
    return out


def add_index(index, names):
    lines = open(index, encoding="utf-8-sig").read().splitlines()
    have = {l.split(";")[1].lower() for l in lines[1:] if ";" in l}
    added = 0
    with open(index, "a", encoding="utf-8", newline="\n") as f:
        if lines and not open(index, "rb").read().endswith(b"\n"):
            f.write("\n")
        for name in sorted(names):
            orig = "campmap/review_panel/Buildings/Auror/%s.BIF" % name
            if orig.lower() in have:
                continue
            f.write("03_Illustrazioni_Info;%s;03_Illustrazioni_Info/%s.png;68;50;1;%s\n" % (orig, orig, INDEX_TAG))
            added += 1
    return added


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(2)
    index = sheet = None
    if "--indice" in args:
        i = args.index("--indice"); index = args[i + 1]; del args[i:i + 2]
    if "--foglio" in args:
        i = args.index("--foglio"); sheet = args[i + 1]; del args[i:i + 2]
    src, icons = args[0], args[1]
    b = buildings(src, icons)
    c = castles(src)
    print("edifici", len(b), "castelli e fortezza", len(c))
    if index:
        print("voci aggiunte all'indice", add_index(index, [n for n, _ in b]))
    if sheet:
        items = b + c
        cols, cw, ch = 8, 272, 230
        rows = (len(items) + cols - 1) // cols
        sh = Image.new("RGBA", (cols * cw, rows * ch), (74, 52, 34, 255))
        from PIL import ImageDraw
        d = ImageDraw.Draw(sh)
        for i, (n, im) in enumerate(items):
            x, y = (i % cols) * cw, (i // cols) * ch
            t = im.copy(); t.thumbnail((cw - 8, ch - 30))
            sh.alpha_composite(t, (x + 4, y + ch - 24 - t.height))
            d.text((x + 6, y + ch - 20), n[:36], fill=(240, 225, 190))
        sh.convert("RGB").save(sheet)


if __name__ == "__main__":
    main()
