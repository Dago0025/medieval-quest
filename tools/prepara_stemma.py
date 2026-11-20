"""Stemma degli Auror da un'immagine dipinta in bianco e nero (IA locale).

Uso:  python tools/prepara_stemma.py <immagine> [--zona x0,y0,x1,y1]

Scrive in assets/stemmi:
- auror_grande.png: l'emblema intero, nero pieno su fondo trasparente (menu e pannelli grandi);
- auror.png: lo scudo d'argento bordato di nero con dentro la zona indicata (frazioni 0-1 dell'immagine; di
  default l'emblema quasi intero), per pedine, stendardi e barra, dove lo stemma e' alto poche decine di pixel.
Le fasce nere piene sul bordo alto e basso dell'immagine (difetti di generazione) vengono tolte.
"""
import argparse
import os

import numpy as np
from PIL import Image, ImageDraw

SHIELD = (136, 160)      # 4x dello scudo 34x40 dell'originale


def clean(path):
    g = np.asarray(Image.open(path).convert("L"), dtype=float)
    dark = g < 128
    for rows in (range(g.shape[0]), range(g.shape[0] - 1, -1, -1)):
        for y in rows:                                  # fasce nere piene partendo dal bordo
            if dark[y].mean() > 0.9:
                g[y] = 255.0
            else:
                edge = slice(y, y + 8) if rows.step in (None, 1) else slice(max(0, y - 7), y + 1)
                if rows.start != y:                     # qualche riga di sbavatura accanto alla fascia tolta
                    g[edge] = 255.0
                break
    limit = int(g.shape[0] * 0.10)                      # resti della fascia: righe quasi piene nel primo e ultimo decimo
    for y in list(range(limit)) + list(range(g.shape[0] - limit, g.shape[0])):
        if (g[y] < 128).mean() > 0.35:
            g[y] = 255.0
    return np.clip((g - 96.0) / 64.0, 0.0, 1.0)        # 0 = nero, 1 = bianco, bordo morbido


def shield_mask(size, inset):
    w, h = size
    big = Image.new("L", (w * 4, h * 4), 0)
    d = ImageDraw.Draw(big)
    i = inset * 4
    d.rectangle([i, i, w * 4 - 1 - i, h * 2], fill=255)
    d.ellipse([i, i, w * 4 - 1 - i, h * 4 - 1 - i], fill=255)
    return big.resize(size, Image.LANCZOS)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("immagine")
    p.add_argument("--zona", default="0.05,0.05,0.95,0.97")
    args = p.parse_args()
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "stemmi")
    white = clean(args.immagine)
    h, w = white.shape
    ys, xs = np.where(white < 0.5)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    alpha = ((1.0 - white) * 255.0).astype(np.uint8)
    big = Image.merge("RGBA", [Image.new("L", (w, h), 16)] * 3 + [Image.fromarray(alpha, "L")]).crop(box)
    big.save(os.path.join(out, "auror_grande.png"))
    x0, y0, x1, y1 = [float(v) for v in args.zona.split(",")]
    figure = Image.fromarray(alpha, "L").crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))
    sw, sh = SHIELD
    room = (sw - 22, sh - 44)
    scale = min(room[0] / figure.size[0], room[1] / figure.size[1])
    figure = figure.resize((max(1, int(figure.size[0] * scale)), max(1, int(figure.size[1] * scale))), Image.LANCZOS)
    shield = Image.new("RGBA", SHIELD, (0, 0, 0, 0))
    shield.paste(Image.new("RGBA", SHIELD, (16, 13, 10, 255)), (0, 0), shield_mask(SHIELD, 0))
    shield.paste(Image.new("RGBA", SHIELD, (255, 255, 255, 255)), (0, 0), shield_mask(SHIELD, 6))
    ink = Image.new("RGBA", figure.size, (16, 13, 10, 255))
    shield.paste(ink, ((sw - figure.size[0]) // 2, 16 + (room[1] - figure.size[1]) // 2), figure)
    shield.save(os.path.join(out, "auror.png"))
    print("scritti auror_grande.png", big.size, "e auror.png", SHIELD)


if __name__ == "__main__":
    main()
