"""Fortezza bianca degli Auror (ADR-076) dal dipinto di AI Playground: icona del castello e pedina della mappa.

Uso:  python tools/prepara_fortezza_auror.py <dipinto AIPG 1:1 su grigio> [--foglio <png>] [--uscita <cartella assets>]

Scrive (FortressArt li usa solo nella regione natia degli Auror, in modalita' Auror):
  assets/rifatti/campmap/review_panel/buildings/fortezza_auror.png   icona 272x200 (come le icone rifatte degli edifici)
  assets/rifatti/campmap/pieces/buildings/fortezza_auror.png         pedina: stendardo, aste e ombra del castello FORTRESS
                                                                     dell'originale (rossi e magenta chiave, ricolorati da
                                                                     PieceArt) con la fortezza dipinta al posto delle mura
Il dipinto si scontorna dal grigio come le basi degli edifici (prepara_edifici.cut_grey). Sulla mappa la pedina si disegna
FortressArt.MAP_SCALE volte piu' alta degli altri castelli.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prepara_edifici import cut_grey, BASE_KEEP  # noqa: E402
from prepara_castelli_mappa import EXPORT, body_box, unkey  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ICON_SIZE = (272, 200)
ICON_MARGIN = 6
GROW = 1.12            # la fortezza e' un poco piu' larga delle mura della fortezza originale


def icon_from(art):
    w, h = ICON_SIZE
    k = min((w - 2 * ICON_MARGIN) / art.width, (h - ICON_MARGIN) / art.height)
    small = art.resize((max(1, round(art.width * k)), max(1, round(art.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", ICON_SIZE, (0, 0, 0, 0))
    out.alpha_composite(small, ((w - small.width) // 2, h - small.height))
    return out


def piece_from(art):
    orig = Image.open(os.path.join(EXPORT, "FORTRESS.Buf.png")).convert("RGBA")
    x0, top, x1, y1, plain = body_box(orig)
    a = np.asarray(orig).copy()
    body = np.zeros(plain.shape, bool)
    body[top:] = plain[top:]
    a[body, 3] = 0                       # via le mura originali: restano stendardo, aste e ombra (pixel chiave)
    banner = Image.fromarray(a, "RGBA")
    w = round((x1 - x0) * GROW)
    scaled = unkey(art.resize((w, max(1, round(art.height * w / art.width))), Image.LANCZOS))
    foot = min(banner.height, y1 + 2)
    pad_top = max(0, scaled.height - foot)   # una montagna piu' alta del castello originale allarga la tela in alto
    cw = max(banner.width, w + 4)
    canvas = Image.new("RGBA", (cw, banner.height + pad_top), (0, 0, 0, 0))
    bx = (cw - banner.width) // 2
    canvas.alpha_composite(banner, (bx, pad_top))
    cx = bx + (x0 + x1) // 2
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.alpha_composite(scaled, (max(0, cx - w // 2), pad_top + foot - scaled.height))
    canvas.alpha_composite(layer)
    return orig, canvas


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    sheet = None
    out_root = os.path.join(HERE, "..", "assets")
    if "--foglio" in args:
        i = args.index("--foglio"); sheet = args[i + 1]; del args[i:i + 2]
    if "--uscita" in args:
        i = args.index("--uscita"); out_root = args[i + 1]; del args[i:i + 2]
    art = cut_grey(args[0], BASE_KEEP)
    icon = icon_from(art)
    orig, piece = piece_from(art)
    for sub, img in (("review_panel/buildings", icon), ("pieces/buildings", piece)):
        d = os.path.join(out_root, "rifatti", "campmap", sub, "fortezza_auror.png")
        os.makedirs(os.path.dirname(d), exist_ok=True)
        img.save(d, optimize=True)
        print(os.path.normpath(d), img.size)
    if sheet:
        w = icon.width + orig.width + piece.width + 40
        h = max(icon.height, piece.height)
        sh = Image.new("RGBA", (w, h), (178, 160, 120, 255))
        sh.alpha_composite(icon, (0, h - icon.height))
        sh.alpha_composite(orig, (icon.width + 20, h - orig.height))
        sh.alpha_composite(piece, (icon.width + orig.width + 40, h - piece.height))
        sh.convert("RGB").save(sheet)


if __name__ == "__main__":
    main()
