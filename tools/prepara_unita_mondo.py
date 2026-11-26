"""Carte e schede delle unita' delle fazioni nuove (ADR-116) dalle immagini approvate di AI Playground.

Uso:  python tools/prepara_unita_mondo.py <cartella con le immagini CODICE.png> [--foglio <file.jpg>]

Le immagini approvate si chiamano con il `codice` della sezione di data/unita_mondo.cfg (GU01.png, GN03.png...), come nei
documenti dei prompt, e stanno in una cartella per gruppo (per esempio AI-Playground/media/unita_giapponesi). Per ogni
unita' che ha l'immagine, con le stesse funzioni di tools/prepara_unita.py (fondo e ombra tolti, figura in basso al
centro) scrive:
  assets/rifatti/campmap/review_panel/units/<id>.png   carta 200x200 (4 volte la carta 50x50)
  assets/rifatti/campmap/info_pics/units/<id>.png      scheda 732x896 (figura sotto nome e dati)
AssetLibrary.unit_card_path e unit_picture usano la versione rifatta al posto del segnaposto del `modello`.
"""
import configparser
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prepara_unita as pu  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
CFG = os.path.join(HERE, "..", "data", "unita_mondo.cfg")
OUT = os.path.join(HERE, "..", "assets", "rifatti", "campmap")


def codes():
    cp = configparser.ConfigParser(comment_prefixes=(";",), inline_comment_prefixes=None, strict=False)
    cp.optionxform = str
    with open(CFG, encoding="utf-8-sig") as f:
        cp.read_file(f)
    out = {}
    for s in cp.sections():
        code = cp[s].get("codice", "").strip().strip('"')
        if code:
            out[code] = s
    return out


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); sys.exit(2)
    sheet_path = None
    if "--foglio" in args:
        i = args.index("--foglio"); sheet_path = args[i + 1]; del args[i:i + 2]
    folder = args[0]
    by_code = codes()
    done = []
    for name in sorted(os.listdir(folder)):
        stem, ext = os.path.splitext(name)
        if ext.lower() != ".png":
            continue
        uid = by_code.get(stem.upper())
        if uid is None:
            print("codice sconosciuto:", name); continue
        art = pu.cut(os.path.join(folder, name))
        card = pu.card_from(art)
        for sub, img in (("review_panel/units", card), ("info_pics/units", pu.sheet(art))):
            d = os.path.join(OUT, sub, uid.lower() + ".png")
            os.makedirs(os.path.dirname(d), exist_ok=True)
            img.save(d, optimize=True)
        done.append((uid, card))
    print("unita' preparate:", len(done))
    if sheet_path and done:
        sh = Image.new("RGBA", (len(done) * 208, 312), (60, 60, 60, 255))
        for k, (uid, card) in enumerate(done):
            for j, col in enumerate([(205, 185, 140, 255), (35, 28, 22, 255)]):
                tile = Image.new("RGBA", (200, 150), col)
                tile.alpha_composite(card.resize((150, 150), Image.LANCZOS), (25, 0))
                sh.alpha_composite(tile, (k * 208, j * 156))
        sh.convert("RGB").save(sheet_path, quality=85)


if __name__ == "__main__":
    main()
