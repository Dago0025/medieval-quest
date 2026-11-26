"""Bitmap delle regioni «da vedere» per lo shader della mappa del mondo (23/11/2026, richiesta di Federico: confini e fasce
dei proprietari meno frastagliati).

I confini vettoriali (confini.bin, confini_mondo.py) sono levigati, la bitmap delle regioni no: la fascia del colore del
proprietario, la provincia scelta, le regioni raggiungibili e la tinta della religione seguivano gli scalini di 2-4 pixel
della bitmap e uscivano dalla linea levigata. Qui i pixel vicini ai confini interni (terra-terra e mare-mare) vengono
riassegnati alla regione che sta dalla loro parte della polilinea levigata.

- Solo grafica: la logica del gioco (clic, pedine, adiacenze) continua a leggere regioni.png.
- Le coste non si toccano (polilinee terra-mare escluse): la costa resta quella dipinta sulla plancia.
- Un pixel cambia solo tra le due regioni della polilinea piu' vicina e solo entro STRISCIA pixel dal confine grezzo.

Uso: python3 regioni_vista.py <regioni.png> <confini.bin> <uscita.png> [sea_first]
Serve numpy, scipy, pillow. Da rifare quando cambiano regioni.png o confini.bin (passo 8b di LEGGIMI.md).
"""
import struct
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

MAGIC = 0x4D514231
KIND_LAND_LAND, KIND_SEA_SEA = 0, 2
STRISCIA = 6        # pixel: oltre la massima distanza tra scalini e polilinea levigata (Douglas-Peucker 4 + Chaikin)
PASSO = 0.5         # densita' dei punti campionati lungo le polilinee


def load_labels(path):
    Image.MAX_IMAGE_PIXELS = None
    rgb = np.asarray(Image.open(path).convert('RGB')).astype(np.int32)
    return rgb[..., 0] + 256 * rgb[..., 1]


def load_borders(path, kinds):
    out = []
    with open(path, 'rb') as f:
        magic, ver, w, h, n = struct.unpack('<IIIII', f.read(20))
        if magic != MAGIC or ver != 1:
            raise ValueError('confini non validi: %s' % path)
        for _ in range(n):
            ga, gb, kind, closed, m = struct.unpack('<HHBBI', f.read(10))
            pts = np.frombuffer(f.read(8 * m), '<f4').reshape(-1, 2).astype(np.float64)
            if kind in kinds and len(pts) >= 2:
                out.append((ga, gb, pts))
    return out


def sample(borders):
    """Punti lungo le polilinee ogni PASSO pixel, con la polilinea di appartenenza e la normale sinistra del tratto."""
    pts, ids, nor = [], [], []
    for i, (_a, _b, p) in enumerate(borders):
        seg = p[1:] - p[:-1]
        length = np.hypot(seg[:, 0], seg[:, 1])
        ok = length > 1e-6
        seg, length, start = seg[ok], length[ok], p[:-1][ok]
        if len(seg) == 0:
            continue
        count = np.maximum(1, np.ceil(length / PASSO).astype(np.int64))
        rep = np.repeat(np.arange(len(seg)), count)
        t = (np.arange(count.sum()) - np.repeat(np.cumsum(count) - count, count)) / np.repeat(count, count)
        pts.append(start[rep] + seg[rep] * t[:, None])
        unit = seg / length[:, None]
        nor.append(np.column_stack([-unit[:, 1], unit[:, 0]])[rep])
        ids.append(np.full(len(rep), i, np.int32))
    return np.vstack(pts), np.concatenate(ids), np.vstack(nor)


def build(labels, borders):
    h, w = labels.shape
    edge = np.zeros((h, w), bool)
    dx = labels[:, 1:] != labels[:, :-1]
    edge[:, 1:] |= dx
    edge[:, :-1] |= dx
    dy = labels[1:, :] != labels[:-1, :]
    edge[1:, :] |= dy
    edge[:-1, :] |= dy
    strip = ndimage.binary_dilation(edge, iterations=STRISCIA)
    ys, xs = np.nonzero(strip)
    raw = labels[ys, xs]

    spts, sid, snor = sample(borders)
    tree = cKDTree(spts)
    centers = np.column_stack([xs + 0.5, ys + 0.5])
    dist, idx = tree.query(centers, distance_upper_bound=STRISCIA + 1.0, workers=-1)
    found = np.isfinite(dist)
    ys, xs, raw, centers, idx = ys[found], xs[found], raw[found], centers[found], idx[found]
    pid = sid[idx]
    positive = ((centers - spts[idx]) * snor[idx]).sum(1) > 0.0

    ga = np.array([b[0] for b in borders], np.int32)
    gb = np.array([b[1] for b in borders], np.int32)
    is_a = raw == ga[pid]
    is_b = raw == gb[pid]
    mine = is_a | is_b
    # Da che parte sta il gruppo A di ogni polilinea: voto dei pixel grezzi (gli scalini sono una minoranza).
    agree = np.bincount(pid[mine], weights=(is_a[mine] == positive[mine]).astype(np.float64), minlength=len(borders))
    total = np.bincount(pid[mine], minlength=len(borders))
    a_positive = agree * 2 >= total
    new = np.where(positive == a_positive[pid], ga[pid], gb[pid])
    change = mine & (new != raw)
    out = labels.copy()
    out[ys[change], xs[change]] = new[change]
    return out, int(change.sum())


def main(src, borders_path, dst, sea_first=1024):
    labels = load_labels(src)
    borders = load_borders(borders_path, (KIND_LAND_LAND, KIND_SEA_SEA))
    out, changed = build(labels, borders)
    # le coste non cambiano: nessun pixel passa tra terra e mare
    land_before = (labels > 0) & (labels < sea_first)
    land_after = (out > 0) & (out < sea_first)
    assert np.array_equal(land_before, land_after), 'costa cambiata'
    rgb = np.zeros(out.shape + (3,), np.uint8)
    rgb[..., 0] = out & 255
    rgb[..., 1] = out >> 8
    Image.fromarray(rgb, 'RGB').save(dst, optimize=True)
    print('pixel riassegnati', changed, 'su', labels.size, '(%.3f%%)' % (100.0 * changed / labels.size))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3], *([int(sys.argv[4])] if len(sys.argv) > 4 else []))
