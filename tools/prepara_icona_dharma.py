"""Icona del Dharma dei popoli asiatici (22/11/2026): la ruota del Dharma a otto raggi, disegnata qui in nero su bianco e
resa in oro con tools/prepara_icona_culto.py (144x160, come le altre icone rifatte delle religioni).

Uso:  python tools/prepara_icona_dharma.py <uscita.png> [--simbolo <simbolo.png>]
"""
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
S = 1200            # tela del simbolo
C = S / 2


def wheel():
    img = Image.new("L", (S, S), 255)
    d = ImageDraw.Draw(img)
    r_out, r_rim = 0.40 * S, 0.33 * S          # cerchione
    r_hub, r_hole = 0.10 * S, 0.045 * S        # mozzo
    d.ellipse([C - r_out, C - r_out, C + r_out, C + r_out], fill=0)
    d.ellipse([C - r_rim, C - r_rim, C + r_rim, C + r_rim], fill=255)
    for k in range(8):                          # otto raggi, piu' larghi verso il mozzo
        a = math.radians(22.5 + 45 * k)
        ca, sa = math.cos(a), math.sin(a)
        px, py = -sa, ca
        w_in, w_out = 0.030 * S, 0.016 * S
        r1, r2 = r_hub * 0.8, r_rim + 2
        pts = [(C + ca * r1 + px * w_in, C + sa * r1 + py * w_in), (C + ca * r2 + px * w_out, C + sa * r2 + py * w_out),
               (C + ca * r2 - px * w_out, C + sa * r2 - py * w_out), (C + ca * r1 - px * w_in, C + sa * r1 - py * w_in)]
        d.polygon(pts, fill=0)
        # pomello sul cerchione, fuori, all'estremita' di ogni raggio
        kx, ky, kr = C + ca * (r_out + 0.045 * S), C + sa * (r_out + 0.045 * S), 0.038 * S
        d.ellipse([kx - kr, ky - kr, kx + kr, ky + kr], fill=0)
        sx, sy = C + ca * (r_out + 0.01 * S), C + sa * (r_out + 0.01 * S)
        d.line([(sx, sy), (kx, ky)], fill=0, width=int(0.022 * S))
    d.ellipse([C - r_hub, C - r_hub, C + r_hub, C + r_hub], fill=0)
    d.ellipse([C - r_hole, C - r_hole, C + r_hole, C + r_hole], fill=255)
    return img


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); sys.exit(2)
    out = args[0]
    sym = args[args.index("--simbolo") + 1] if "--simbolo" in args else os.path.splitext(out)[0] + "_simbolo.png"
    wheel().save(sym)
    subprocess.check_call([sys.executable, os.path.join(HERE, "prepara_icona_culto.py"), sym, out])
    print(out)


if __name__ == "__main__":
    main()
