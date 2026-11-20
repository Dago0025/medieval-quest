"""Fase 1: etichette delle regioni a mezza risoluzione, controllo dei confinanti europei e anteprima.

Uso: python3 fase1_regioni.py <regioni_mondo.txt> <EARLY_XL.TXT> <cartella geo> <cartella out>
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

import crescita
import definizioni
import proiezione as P

HALF = 2


def sample_equirect(img, lat, lon):
    """Campiona un'immagine equirettangolare (lon -180..180, lat 90..-90) con interpolazione bilineare."""
    h, w = img.shape[:2]
    fx = ((np.asarray(lon) + 180.0) % 360.0) / 360.0 * w - 0.5
    fy = (90.0 - np.asarray(lat)) / 180.0 * h - 0.5
    x0 = np.floor(fx).astype(np.int64)
    y0 = np.clip(np.floor(fy).astype(np.int64), 0, h - 1)
    tx = fx - x0
    ty = fy - np.floor(fy)
    x1 = (x0 + 1) % w
    x0 = x0 % w
    y1 = np.clip(y0 + 1, 0, h - 1)
    if img.ndim == 3:
        tx = tx[..., None]
        ty = ty[..., None]
    a = img[y0, x0] * (1 - tx) + img[y0, x1] * tx
    b = img[y1, x0] * (1 - tx) + img[y1, x1] * tx
    return a * (1 - ty) + b * ty


def grid_latlon(w, h, factor):
    xs = (np.arange(w) + 0.5) * factor
    ys = (np.arange(h) + 0.5) * factor
    X, Y = np.meshgrid(xs, ys)
    return P.to_latlon(X, Y)


def elevation_grid(geo, w, h, factor):
    Image.MAX_IMAGE_PIXELS = None
    elev = np.asarray(Image.open(os.path.join(geo, 'elev_bump_4k.jpg')).convert('L'), dtype=np.float32) / 255.0
    lat, lon = grid_latlon(w, h, factor)
    return sample_equirect(elev, lat, lon).astype(np.float32)


def downsample_mask(mask, f):
    h, w = mask.shape
    hh, ww = h // f, w // f
    m = mask[:hh * f, :ww * f].reshape(hh, f, ww, f).mean(axis=(1, 3))
    return m >= 0.5


def snap(passable, y, x, maxr=40):
    h, w = passable.shape
    y = int(np.clip(y, 0, h - 1))
    x = int(x) % w
    if passable[y, x]:
        return y, x
    for r in range(1, maxr):
        ys, xs = np.mgrid[-r:r + 1, -r:r + 1]
        ring = np.maximum(abs(ys), abs(xs)) == r
        cand = []
        for dy, dx in zip(ys[ring], xs[ring]):
            yy, xx = y + dy, (x + dx) % w
            if 0 <= yy < h and passable[yy, xx]:
                cand.append((dy * dy + dx * dx, yy, xx))
        if cand:
            cand.sort()
            return cand[0][1], cand[0][2]
    return None


def run(defs_path, startpos_path, geo, out):
    defs = definizioni.load(defs_path)
    cmds = definizioni.startpos_commands(startpos_path)
    orig_pairs = definizioni.original_neighbours(cmds)
    land_full = np.load(os.path.join(out, 'terra.npy')).astype(bool)
    land = downsample_mask(land_full, HALF)
    h, w = land.shape
    elev = elevation_grid(geo, w, h, HALF)
    gy, gx = np.gradient(ndimage.gaussian_filter(elev, 1.5))
    grad = np.hypot(gx, gy)
    cost_land = 1.0 + 60.0 * grad + 2.5 * np.clip(elev - 0.35, 0, 1)
    cost_sea = np.ones_like(cost_land)
    np.save(os.path.join(out, 'elev_mezza.npy'), elev)

    index_of = {}
    for i, d in enumerate(defs):
        index_of[d.id] = i + 1
    speed = np.ones(len(defs) + 1, dtype=np.float64)
    for d in defs:
        speed[index_of[d.id]] = d.speed

    def seeds_for(kind_sea, passable):
        ys, xs, ls = [], [], []
        for d in defs:
            if d.is_sea != kind_sea:
                continue
            for (la, lo) in d.seeds:
                x, y = P.to_px(la, lo)
                s = snap(passable, y / HALF, x / HALF)
                if s is None:
                    print('SEME SENZA POSTO', d.id, la, lo)
                    continue
                ys.append(s[0]); xs.append(s[1]); ls.append(index_of[d.id])
        return np.array(ys, np.int64), np.array(xs, np.int64), np.array(ls, np.int32)

    sy, sx, sl = seeds_for(False, land)
    lab_land = crescita.grow(land, cost_land, sy, sx, sl, speed)
    water = ~land
    wy, wx, wl = seeds_for(True, water)
    lab_sea = crescita.grow(water, cost_sea, wy, wx, wl, speed)
    label = np.where(land, lab_land, lab_sea).astype(np.int32)
    # terra irraggiungibile (isole senza seme) e acque chiuse senza seme (laghi): etichetta della terra piu' vicina
    land_unset = land & (label == 0)
    water_unset = water & (label == 0)
    if land_unset.any() or water_unset.any():
        src = np.where(land, lab_land, 0)
        idx = ndimage.distance_transform_edt(src == 0, return_distances=False, return_indices=True)
        nearest = src[idx[0], idx[1]]
        label = np.where(land_unset | water_unset, nearest, label)
    np.save(os.path.join(out, 'etichette_mezza.npy'), label)
    json.dump({d.id: index_of[d.id] for d in defs}, open(os.path.join(out, 'indici_fase1.json'), 'w'), indent=0)

    # confinanti europei: confronto con SetNeighbours
    id_of = {v: k for k, v in index_of.items()}
    pairs = crescita.adjacency(label)
    old = {d.id for d in defs if not d.is_new}
    new_pairs = {tuple(sorted((id_of[a], id_of[b]))) for a, b in pairs}
    eu_found = {p for p in new_pairs if p[0] in old and p[1] in old}
    missing = sorted(orig_pairs - eu_found)
    extra = sorted(eu_found - orig_pairs)
    rep = ['confinanti originali %d, trovati tra regioni europee %d' % (len(orig_pairs), len(eu_found)),
           'MANCANTI (%d):' % len(missing)] + ['  %s - %s' % p for p in missing] + \
          ['IN PIU\' (%d):' % len(extra)] + ['  %s - %s' % p for p in extra]
    open(os.path.join(out, 'confinanti_fase1.txt'), 'w').write('\n'.join(rep))
    print('\n'.join(rep[:2]), len(missing), 'mancanti', len(extra), 'in piu\'')
    preview(label, defs, index_of, land, out)


def preview(label, defs, index_of, land, out, scale=2):
    rng = np.random.default_rng(7)
    n = label.max() + 1
    pal = rng.integers(60, 230, size=(n, 3)).astype(np.uint8)
    pal[0] = 0
    for d in defs:
        i = index_of[d.id]
        if d.is_sea:
            pal[i] = (pal[i] * 0.35 + np.array([20, 60, 140]) * 0.65).astype(np.uint8)
    img = pal[label]
    # confini
    edge = np.zeros(label.shape, bool)
    edge[:, 1:] |= label[:, 1:] != label[:, :-1]
    edge[1:, :] |= label[1:, :] != label[:-1, :]
    img[edge] = (img[edge] * 0.3).astype(np.uint8)
    im = Image.fromarray(img).resize((label.shape[1] // scale, label.shape[0] // scale), Image.NEAREST)
    im.save(os.path.join(out, 'anteprima_fase1.png'))


if __name__ == '__main__':
    run(*sys.argv[1:5])
