"""Anteprima leggibile di una bitmap di etichette: colori, confini, nomi abbreviati al baricentro.
Uso: python3 anteprima.py <etichette.npy> <indici.json> <out.png> x0 y0 x1 y1 [scala]"""
import json
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def render(label, index_of, box, scale=1.0, sea_ids=None):
    x0, y0, x1, y1 = box
    lab = label[y0:y1, x0:x1]
    rng = np.random.default_rng(3)
    n = max(index_of.values()) + 2
    pal = rng.integers(110, 235, size=(n, 3)).astype(np.uint8)
    pal[0] = (40, 40, 40)
    id_of = {v: k for k, v in index_of.items()}
    for i, rid in id_of.items():
        if sea_ids and rid in sea_ids:
            pal[i] = (pal[i] * 0.25 + np.array([40, 90, 160]) * 0.75).astype(np.uint8)
    img = pal[lab]
    edge = np.zeros(lab.shape, bool)
    edge[:, 1:] |= lab[:, 1:] != lab[:, :-1]
    edge[1:, :] |= lab[1:, :] != lab[:-1, :]
    img[edge] = 20
    im = Image.fromarray(img)
    if scale != 1.0:
        im = im.resize((int(im.width * scale), int(im.height * scale)), Image.NEAREST)
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 11)
    except OSError:
        font = ImageFont.load_default()
    ys, xs = np.mgrid[0:lab.shape[0], 0:lab.shape[1]]
    for i in np.unique(lab):
        if i == 0:
            continue
        m = lab == i
        if m.sum() < 40:
            continue
        cy, cx = ys[m].mean() * scale, xs[m].mean() * scale
        name = id_of.get(int(i), '?').replace('ID_', '')[:14]
        d.text((cx - 3 * len(name), cy - 6), name, fill=(0, 0, 0), font=font)
    return im


if __name__ == '__main__':
    label = np.load(sys.argv[1])
    index_of = json.load(open(sys.argv[2]))
    box = tuple(int(v) for v in sys.argv[4:8])
    scale = float(sys.argv[8]) if len(sys.argv) > 8 else 1.0
    seas = set(json.load(open(sys.argv[9]))) if len(sys.argv) > 9 else None
    render(label, index_of, box, scale, seas).save(sys.argv[3])
