"""Pennacchio dell'ammiraglio per la carta della sua nave (ADR-062).

Uso:  python tools/prepara_pennacchio_ammiraglio.py <cartella conversione_icone>

L'originale non ha un distintivo per gli ammiragli: si parte dal drappo bianco del generale (assets/ui/veste/
pennacchio_noble.png, dipinto con l'IA locale), si toglie il sigillo ricopiando sopra il panno delle stesse colonne preso
piu' in basso (le pieghe del drappo sono verticali) e al suo posto si posa l'ancora dipinta dell'Ammiragliato
(conversione_icone/risultati/S19.png, il simbolo usato anche sulle icone degli edifici). Risultato:
assets/ui/veste/pennacchio_admiral.png, 112x248 come gli altri pennacchi (OriginalHud.pennant_texture).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

from prepara_edifici import cut_grey, fit, SYMBOL_KEEP

HERE = os.path.dirname(os.path.abspath(__file__))
VESTE = os.path.join(HERE, "..", "assets", "ui", "veste")
SEAL_ROWS = (60, 110)        # righe del sigillo nel pennacchio del generale (misurate: 64-106)
CLOTH_FROM = 112             # da qui in giu' il panno e' pulito
ANCHOR_BOX = (62, 62)
ANCHOR_CENTER = (56, 86)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    base = Image.open(os.path.join(VESTE, "pennacchio_noble.png")).convert("RGBA")
    a = np.asarray(base).copy()
    y0, y1 = SEAL_ROWS
    a[y0:y1] = a[CLOTH_FROM:CLOTH_FROM + (y1 - y0)]
    out = Image.fromarray(a, "RGBA")
    # raccordo morbido sui bordi della toppa
    soft = out.filter(ImageFilter.GaussianBlur(1.2))
    for y in (y0, y1):
        band = (0, y - 2, out.width, y + 2)
        out.paste(soft.crop(band), band[:2])
    anchor = fit(cut_grey(os.path.join(sys.argv[1], "risultati", "S19.png"), SYMBOL_KEEP), ANCHOR_BOX)
    out.alpha_composite(anchor, (ANCHOR_CENTER[0] - anchor.width // 2, ANCHOR_CENTER[1] - anchor.height // 2))
    # il drappo resta dentro il suo contorno
    out.putalpha(base.getchannel("A"))
    dest = os.path.join(VESTE, "pennacchio_admiral.png")
    out.save(dest, optimize=True)
    print(os.path.relpath(dest, os.path.join(HERE, "..")), out.size)


if __name__ == "__main__":
    main()
