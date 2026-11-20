"""Boschi disegnati sulla plancia: piccoli alberi a gruppi, come nella MapTex originale (ADR-077).

Uso: python3 alberi.py <cartella geo> <cartella out>   (modifica <out>/finale/plancia.jpg)
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

import proiezione as P
from fase1_regioni import sample_equirect

Image.MAX_IMAGE_PIXELS = None
SPACING = 7          # passo della griglia dei candidati (pixel)


def make_tree(size, canopy, dark, light, conifer=False):
    """Albero disegnato a 4x e ridotto (antialias): ombra, chioma, luce in alto a sinistra."""
    s = 4
    W, H = size[0] * s, size[1] * s
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = W // 2
    if conifer:
        d.polygon([(cx + 3 * s, H - 2 * s), (cx + 1 * s, 2 * s), (W - 1 * s, H - 2 * s)], fill=dark + (110,))
        d.polygon([(cx, 1 * s), (cx - 3.4 * s, H - 3 * s), (cx + 3.4 * s, H - 3 * s)], fill=canopy + (255,))
        d.polygon([(cx, 1 * s), (cx - 2.2 * s, H - 5 * s), (cx - 0.3 * s, H - 5 * s)], fill=light + (200,))
        d.rectangle([cx - 0.6 * s, H - 3 * s, cx + 0.6 * s, H - 1 * s], fill=(70, 55, 35, 255))
    else:
        d.ellipse([cx - 2 * s, H - 6 * s, cx + 4.5 * s, H - 1 * s], fill=dark + (100,))
        d.rectangle([cx - 0.6 * s, H - 4.5 * s, cx + 0.6 * s, H - 1.2 * s], fill=(70, 55, 35, 255))
        d.ellipse([cx - 3.6 * s, 1 * s, cx + 3.6 * s, H - 3.5 * s], fill=canopy + (255,))
        d.ellipse([cx - 2.6 * s, 1.8 * s, cx + 0.6 * s, H - 6.5 * s], fill=light + (210,))
        d.ellipse([cx - 3.6 * s, 1 * s, cx + 3.6 * s, H - 3.5 * s], outline=dark + (220,), width=s)
    return im.resize(size, Image.LANCZOS)


def main(geo, out, src='plancia_base.jpg', dst='plancia.jpg'):
    path = os.path.join(out, 'finale', dst)
    base = Image.open(os.path.join(out, 'finale', src)).convert('RGB')
    W, H = base.size
    land = np.load(os.path.join(out, 'terra.npy')).astype(bool)
    lakes = np.load(os.path.join(out, 'laghi.npy')).astype(bool)
    solid = land & ~lakes
    if 'auror' in dst:
        import atlantide as A
        cx, cy = A.center_px()
        hx, hy = A.HALF_BOX
        ya, yb, xa, xb = int(cy - hy), int(cy + hy), int(cx - hx), int(cx + hx)
        yy, xx = np.mgrid[ya:yb, xa:xb]
        solid[ya:yb, xa:xb] |= A.land(xx + 0.5, yy + 0.5) & ~A.rings(xx + 0.5, yy + 0.5)
    inland = ndimage.binary_erosion(solid, iterations=5)
    sat = np.asarray(Image.open(os.path.join(geo, '2_no_clouds_4k.jpg')).convert('RGB'), dtype=np.float32) / 255.0
    sat = ndimage.gaussian_filter(sat, (1.0, 1.0, 0))
    elev = np.asarray(Image.open(os.path.join(geo, 'elev_bump_4k.jpg')).convert('L'), dtype=np.float32) / 255.0
    rng = np.random.default_rng(1215)
    gy, gx = np.mgrid[SPACING // 2:H:SPACING, SPACING // 2:W:SPACING]
    jx = gx + rng.integers(-SPACING // 2, SPACING // 2 + 1, gx.shape)
    jy = gy + rng.integers(-SPACING // 2, SPACING // 2 + 1, gy.shape)
    jx = np.clip(jx, 0, W - 1)
    jy = np.clip(jy, 0, H - 1)
    ok = inland[jy, jx]
    lat, lon = P.to_latlon(jx + 0.5, jy + 0.5)
    c = sample_equirect(sat, lat, lon)
    e = sample_equirect(elev, lat, lon)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    bright = (r + g + b) / 3
    green = g - (r + b) * 0.5
    dens0 = np.clip((green - 0.09) / 0.05, 0, 1) * np.clip((0.56 - bright) / 0.12, 0, 1) * np.clip((0.75 - e) / 0.2, 0, 1)
    dens = dens0
    if 'auror' in dst:
        import atlantide as A
        dens = np.maximum(dens0, A.forest(jx + 0.5, jy + 0.5))
    # gruppi: rumore a bassa frequenza che dirada
    clump = ndimage.gaussian_filter(rng.random(gx.shape).astype(np.float32), 2.2, mode='wrap')
    clump = (clump - clump.min()) / (clump.max() - clump.min() + 1e-6)
    q = np.clip((clump - 0.56) / 0.1, 0, 1)
    p = np.clip(dens * 1.3, 0, 1) * q
    pick = ok & (rng.random(gx.shape) < p * 0.9)
    ys, xs, la = jy[pick], jx[pick], lat[pick]
    order = np.argsort(ys)   # da nord a sud: gli alberi piu' in basso coprono quelli dietro
    broad = [make_tree((9, 12), (96, 108, 58), (58, 64, 34), (138, 146, 88)),
             make_tree((8, 11), (104, 112, 60), (60, 66, 36), (146, 150, 92)),
             make_tree((10, 12), (88, 100, 54), (54, 60, 32), (128, 140, 84))]
    conif = [make_tree((8, 12), (78, 92, 56), (46, 56, 34), (120, 132, 86), True),
             make_tree((7, 11), (84, 98, 60), (48, 58, 36), (126, 138, 90), True)]
    tropic = [make_tree((10, 12), (74, 92, 46), (44, 56, 28), (112, 130, 72))]
    for k in order:
        x, y, a = int(xs[k]), int(ys[k]), abs(float(la[k]))
        if a > 50 + rng.random() * 8:
            t = conif[rng.integers(len(conif))]
        elif a < 15:
            t = tropic[0]
        else:
            t = broad[rng.integers(len(broad))] if rng.random() > 0.25 or a < 42 else conif[rng.integers(len(conif))]
        base.paste(t, (x - t.width // 2, y - t.height), t)
    base.save(path, quality=92)
    print('alberi', int(pick.sum()))


if __name__ == '__main__':
    main(*sys.argv[1:5])
