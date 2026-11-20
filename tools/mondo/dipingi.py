"""Plancia dipinta del mondo in stile pergamena, con la tavolozza della MapTex originale (ADR-077).

Uso: python3 dipingi.py <cartella geo> <cartella out> [fattore di riduzione per le prove]
Ingressi in <out>: terra.npy, laghi.npy, fiumi.png. Uscita: <out>/finale/plancia.jpg
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

import proiezione as P
from fase1_regioni import sample_equirect

Image.MAX_IMAGE_PIXELS = None

# tavolozza campionata dalla MapTex originale
LUSH = np.array([158, 160, 116], np.float32)       # pianure verdi (Ungheria, Francia)
FOREST = np.array([128, 137, 92], np.float32)      # boschi (piu' scuri e verdi)
ARID = np.array([174, 152, 100], np.float32)       # Castiglia, Anatolia
DESERT = np.array([196, 180, 136], np.float32)     # Sahara, deserto siriaco
STEPPE = np.array([190, 180, 140], np.float32)
SNOW = np.array([222, 220, 208], np.float32)
SEA_OPEN = np.array([136, 154, 147], np.float32)
SEA_COAST = np.array([114, 136, 128], np.float32)
FOAM = np.array([176, 184, 166], np.float32)
INK = np.array([78, 70, 52], np.float32)
RIVER = np.array([104, 128, 124], np.float32)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _hash(ix, iy, seed):
    h = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF).astype(np.float32) / 65535.0


def value_noise(X, Y, cell, seed, wrap_w):
    """Rumore a valori su coordinate assolute (continuo tra le fasce, si richiude sul bordo del Pacifico)."""
    gx = X / cell
    gy = Y / cell
    ix = np.floor(gx).astype(np.int64)
    iy = np.floor(gy).astype(np.int64)
    fx = (gx - ix).astype(np.float32)
    fy = (gy - iy).astype(np.float32)
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    nwrap = max(1, int(round(wrap_w / cell)))
    ix0 = ix % nwrap
    ix1 = (ix + 1) % nwrap
    a = _hash(ix0, iy, seed)
    b = _hash(ix1, iy, seed)
    c = _hash(ix0, iy + 1, seed)
    d = _hash(ix1, iy + 1, seed)
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


def fractal(X, Y, cells, weights, seed, wrap_w):
    out = np.zeros(X.shape, np.float32)
    for k, (c, wt) in enumerate(zip(cells, weights)):
        out += wt * value_noise(X, Y, c, seed + k * 7, wrap_w)
    return out


def canal_mask(X, Y):
    """Canale di Atlantide: dalla citta' al mare verso sud (Crizia: cinquanta stadi fino al mare)."""
    import atlantide as A
    cx, cy = A.center_px()
    return (np.abs(X - cx) <= 1.3 * A.SCALE) & (Y > cy + A.RINGS[-1]) & A.land(X, Y)


def main(geo, out, reduce=1, variant=None):
    """variant: None, oppure 'atlantide' (isola della modalita' Auror: ridipinge solo le fasce dell'isola su plancia.jpg)."""
    fin = os.path.join(out, 'finale')
    os.makedirs(fin, exist_ok=True)
    land = np.load(os.path.join(out, 'terra.npy')).astype(bool)
    lakes = np.load(os.path.join(out, 'laghi.npy')).astype(bool)
    rivers = np.asarray(Image.open(os.path.join(out, 'fiumi.png')), dtype=np.float32) / 255.0
    if reduce > 1:
        land = land[::reduce, ::reduce]
        lakes = lakes[::reduce, ::reduce]
        rivers = rivers[::reduce, ::reduce]
    H, W = land.shape
    row_range = None
    if variant == 'atlantide':
        import atlantide as A
        cx, cy = A.center_px()
        y_a, y_b = int(cy - A.RY * 1.6) - 60, int(cy + A.RY * 1.6) + 60
        x_a, x_b = int(cx - A.RX * 1.6), int(cx + A.RX * 1.6)
        yy, xx = np.mgrid[y_a:y_b, x_a:x_b]
        isl = A.land(xx + 0.5, yy + 0.5)
        wet = A.rings(xx + 0.5, yy + 0.5) | canal_mask(xx + 0.5, yy + 0.5)
        land[y_a:y_b, x_a:x_b] |= isl
        lakes[y_a:y_b, x_a:x_b] |= isl & wet
        row_range = (y_a // 384 * 384, y_b)
    water = ~land | lakes
    # distanze dalla costa (in pixel della piena risoluzione)
    d_water = ndimage.distance_transform_edt(water).astype(np.float32) * reduce   # nell'acqua: distanza dalla terra
    d_land = ndimage.distance_transform_edt(~water).astype(np.float32) * reduce   # sulla terra: distanza dall'acqua
    print('distanze pronte')
    elev_src = np.asarray(Image.open(os.path.join(geo, 'elev_bump_4k.jpg')).convert('L'), dtype=np.float32) / 255.0
    elev_src = ndimage.gaussian_filter(elev_src, 1.6)
    sat_src = np.asarray(Image.open(os.path.join(geo, '2_no_clouds_4k.jpg')).convert('RGB'), dtype=np.float32) / 255.0
    sat_src = ndimage.gaussian_filter(sat_src, (1.5, 1.5, 0))
    rng = np.random.default_rng(1066)
    if row_range is not None:
        result = np.asarray(Image.open(os.path.join(fin, 'plancia_base.jpg')).convert('RGB')).copy()
    else:
        result = np.zeros((H, W, 3), np.uint8)
    strip = 384
    margin = 4
    for y0 in range(0, H, strip):
        if row_range is not None and (y0 + strip <= row_range[0] or y0 >= row_range[1]):
            continue
        y1 = min(H, y0 + strip)
        ya, yb = max(0, y0 - margin), min(H, y1 + margin)
        ys = (np.arange(ya, yb) + 0.5) * reduce
        xs = (np.arange(W) + 0.5) * reduce
        X, Y = np.meshgrid(xs, ys)
        lat, lon = P.to_latlon(X, Y)
        elev = sample_equirect(elev_src, lat, lon).astype(np.float32)
        if variant == 'atlantide':
            elev = np.maximum(elev, A.relief(X, Y).astype(np.float32))
        sat = sample_equirect(sat_src, lat, lon).astype(np.float32)
        h, w = elev.shape
        # dettaglio frattale nei rilievi
        fn = fractal(X, Y, (40, 12, 4), (0.55, 0.3, 0.15), 11, W * reduce)
        relief = elev + (fn - 0.5) * 0.04 * smoothstep(0.2, 0.7, elev)
        gy, gx = np.gradient(relief * 230.0 / reduce)
        # luce da nord-ovest
        nx, ny, nz = -gx, -gy, np.ones_like(gx)
        norm = np.sqrt(nx * nx + ny * ny + nz * nz)
        shade = (nx * -0.6 + ny * -0.6 + nz * 0.53) / norm
        shade = np.clip(shade, -1, 1)
        # biomi dal colore satellitare
        r, g, b = sat[..., 0], sat[..., 1], sat[..., 2]
        bright = (r + g + b) / 3.0
        greenness = g - (r + b) * 0.5
        redness = r - b
        arid = smoothstep(0.08, 0.26, redness) * smoothstep(0.22, 0.45, bright)
        desert = smoothstep(0.38, 0.6, bright) * smoothstep(0.1, 0.3, redness)
        forest = smoothstep(0.0, 0.05, greenness) * (1 - smoothstep(0.18, 0.32, bright))
        alat = np.abs(lat)
        cold = np.maximum(smoothstep(56.0, 64.0, alat), smoothstep(0.55, 0.8, elev))
        snow = smoothstep(0.55, 0.78, bright) * (1 - smoothstep(0.06, 0.16, redness)) * cold
        snow = np.maximum(snow, smoothstep(0.82, 0.95, elev) * 0.8)
        steppe = smoothstep(0.25, 0.4, bright) * (1 - arid) * smoothstep(40, 50, alat) * (1 - forest)
        col = LUSH[None, None, :] * np.ones((h, w, 1), np.float32)
        col = col + (FOREST - col) * (forest * 0.8)[..., None]
        col = col + (STEPPE - col) * (steppe * 0.6)[..., None]
        col = col + (ARID - col) * arid[..., None]
        col = col + (DESERT - col) * desert[..., None]
        col = col + (SNOW - col) * snow[..., None]
        # rilievo: ombreggiatura e cime piu' chiare e brune
        mount = smoothstep(0.18, 0.6, elev)
        k = 0.14 + 0.5 * mount
        col *= (1.0 - k * 0.55 + k * shade)[..., None]
        col = col + (np.array([150, 128, 96], np.float32) - col) * (mount * 0.25)[..., None]
        # carta: macchie e grana
        paper = fractal(X, Y, (640, 160, 40, 10), (0.45, 0.3, 0.17, 0.08), 23, W * reduce)
        grain = rng.normal(0, 1, (h, w)).astype(np.float32)
        col *= (0.90 + 0.2 * paper)[..., None]
        col += (grain * 2.2)[..., None]
        # acqua
        dw = d_water[ya:yb]
        dl = d_land[ya:yb]
        wmask = water[ya:yb]
        sea = SEA_COAST + (SEA_OPEN - SEA_COAST) * smoothstep(1.5, 18.0, dw)[..., None]
        streak = fractal(X * 0.22, Y, (60, 18, 6), (0.5, 0.3, 0.2), 37, W * reduce * 0.22)
        sea = sea * (0.95 + 0.08 * paper + 0.05 * streak)[..., None] + (grain * 1.6)[..., None]
        foam = smoothstep(4.5, 1.5, dw) * wmask
        sea = sea + (FOAM - sea) * (foam * 0.55)[..., None]
        col = np.where(wmask[..., None], sea, col)
        # inchiostro della costa (lato terra, 1-2 px) e sabbia
        ink = smoothstep(2.2, 0.6, dl) * (~wmask)
        col = col + (INK - col) * (ink * 0.75)[..., None]
        sand = smoothstep(5.0, 2.0, dl) * (~wmask) * (1 - ink)
        col = col + (np.array([190, 176, 136], np.float32) - col) * (sand * 0.25)[..., None]
        # fiumi
        rv = rivers[ya:yb] * (~wmask)
        col = col + (RIVER - col) * (np.clip(rv * 1.2, 0, 1) * 0.6)[..., None]
        col = np.clip(col, 0, 255).astype(np.uint8)
        result[y0:y1] = col[y0 - ya:y0 - ya + (y1 - y0)]
        print('fascia', y0, '/', H, flush=True)
    name = 'plancia.jpg' if reduce == 1 else 'plancia_prova_%d.jpg' % reduce
    if variant == 'atlantide':
        name = 'plancia_auror_base.jpg'
    Image.fromarray(result).save(os.path.join(fin, name), quality=92)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1, sys.argv[4] if len(sys.argv) > 4 else None)
