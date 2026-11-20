"""Icona di Medieval Quest (finestra ed eseguibile) dallo stemma attuale degli Auror.

Uso:  python tools/prepara_icona.py <immagine dello stemma> [--zona x0,y0,x1,y1]

L'immagine e' la stessa usata da tools/prepara_stemma.py (AIPG_Image_00034_, scelta da Federico l'11/11): lo scudo
d'argento bordato di nero con il drago a tre teste si ricompone a 512x602 (stessa forma e proporzioni di auror.png, che
e' 136x160) per avere un'icona nitida anche a 256 pixel. Scrive in assets:
- icona.ico: 16, 24, 32, 48, 64, 128, 256 pixel (eseguibile Windows, export_presets.cfg e config/windows_native_icon);
- icona.png: 256x256 (icona della finestra, config/icon).
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prepara_stemma import clean, shield_mask  # noqa: E402

BIG = (512, 602)                     # stesse proporzioni di auror.png (136x160)
SIZES = [16, 24, 32, 48, 64, 128, 256]


def shield_image(path, zona):
    white = clean(path)
    h, w = white.shape
    alpha = ((1.0 - white) * 255.0).astype(np.uint8)
    x0, y0, x1, y1 = [float(v) for v in zona.split(",")]
    figure = Image.fromarray(alpha, "L").crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))
    k = BIG[0] / 136.0                # margini di prepara_stemma.py scalati
    sw, sh = BIG
    room = (int(sw - 22 * k), int(sh - 44 * k))
    scale = min(room[0] / figure.size[0], room[1] / figure.size[1])
    figure = figure.resize((max(1, int(figure.size[0] * scale)), max(1, int(figure.size[1] * scale))), Image.LANCZOS)
    shield = Image.new("RGBA", BIG, (0, 0, 0, 0))
    shield.paste(Image.new("RGBA", BIG, (16, 13, 10, 255)), (0, 0), shield_mask(BIG, 0))
    shield.paste(Image.new("RGBA", BIG, (255, 255, 255, 255)), (0, 0), shield_mask(BIG, int(round(6 * k))))
    ink = Image.new("RGBA", figure.size, (16, 13, 10, 255))
    shield.paste(ink, ((sw - figure.size[0]) // 2, int(16 * k) + (room[1] - figure.size[1]) // 2), figure)
    return shield


def square(img, size):
    """Lo scudo centrato in un quadrato trasparente di lato `size` (alto quasi quanto il quadrato)."""
    target_h = int(size * 0.96)
    target_w = max(1, int(round(img.size[0] * target_h / img.size[1])))
    small = img.resize((target_w, target_h), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(small, ((size - target_w) // 2, (size - target_h) // 2), small)
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("immagine")
    p.add_argument("--zona", default="0.05,0.05,0.95,0.97")
    args = p.parse_args()
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
    shield = shield_image(args.immagine, args.zona)
    frames = [square(shield, s) for s in SIZES]
    frames[-1].save(os.path.join(out, "icona.png"))
    frames[-1].save(os.path.join(out, "icona.ico"), sizes=[(s, s) for s in SIZES], append_images=frames[:-1])
    print("scritti icona.ico", SIZES, "e icona.png 256x256")


if __name__ == "__main__":
    main()
