"""Carte degli agenti rifatte con l'IA locale (AI Playground, media/conversione_agenti).

Uso:  python tools/prepara_agenti.py <cartella conversione_agenti> [AG## ...] [--foglio <png>]

Per ogni voce di conversione_agenti/_strumenti/coda.json prende risultati/<file> (1024x1024 su grigio), toglie fondo e
ombra e posa la figura in basso al centro su 200x200 (4 volte la carta 50x50) con lo stesso taglio delle carte delle
unita' (tools/prepara_unita.py). Scrive assets/rifatti/campmap/review_panel/agents[/muslim|/pagan]/<nome>.png per la
sorgente e per le carte identiche (`uguali`: l'assassino pagano e' quello comune, le tre principesse sono una).
PieceArt.unit_card sceglie la cartella di cultura come per le pedine (AssetLibrary.unit_card_path con `culture`).
"""
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prepara_unita import cut, card_from  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "rifatti")


def target(original):
    # campmap/review_panel/Agents/MUSLIM/Spy.BIF -> assets/rifatti/campmap/review_panel/agents/muslim/spy.png
    return os.path.join(OUT, os.path.splitext(original.lower())[0] + ".png")


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); sys.exit(2)
    sheet = None
    if "--foglio" in args:
        i = args.index("--foglio"); sheet = args[i + 1]; del args[i:i + 2]
    src, only = args[0], set(args[1:])
    queue = json.load(open(os.path.join(src, "_strumenti", "coda.json"), encoding="utf-8"))
    done = []
    for it in queue:
        if only and it["id"] not in only:
            continue
        res = os.path.join(src, "risultati", os.path.basename(it["file"]))
        if not os.path.exists(res):
            print("manca", it["id"]); continue
        img = card_from(cut(res))
        for original in [it["sorgente"]] + it.get("uguali", []):
            dest = target(original)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            img.save(dest, optimize=True)
        done.append((it, img))
    print("carte scritte:", len(done))
    if sheet and done:
        cols = 5
        sh = Image.new("RGBA", (cols * 312, ((len(done) + cols - 1) // cols) * 104), (60, 60, 60, 255))
        for k, (it, img) in enumerate(done):
            x, y = (k % cols) * 312, (k // cols) * 104
            sh.alpha_composite(Image.open(os.path.join(src, it["file"])).convert("RGBA").resize((100, 100)), (x, y))
            for j, col in enumerate([(205, 185, 140, 255), (35, 28, 22, 255)]):
                tile = Image.new("RGBA", (100, 100), col)
                tile.alpha_composite(img.resize((100, 100), Image.LANCZOS))
                sh.alpha_composite(tile, (x + 104 * (j + 1), y))
        sh.convert("RGB").save(sheet, quality=85)


if __name__ == "__main__":
    main()
