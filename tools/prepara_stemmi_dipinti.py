"""Stemmi delle fazioni nuove dipinti in AI Playground (28/11/2026, richiesta di Federico: rifare con l'IA gli stemmi
fatti solo a codice da tools/prepara_stemmi_mondo.py).

Uso:  python tools/prepara_stemmi_dipinti.py <cartella> [--solo FN_A,FN_B] [--foglio foglio.png]

Per ogni S_<FAZIONE>.png della cartella (scudo di fronte su fondo grigio chiaro uniforme, Pro 3 Image Turbo, 4 passi,
896x1152; prompt in specifiche/stemmi_fazioni_nuove.md del progetto): toglie il fondo e l'ombra a terra riempiendo dai
bordi, tiene lo scudo, lo ritaglia e lo mette in assets/stemmi/<fazione minuscola>.png a 136x160, centrato e appoggiato in
basso come gli stemmi dipinti dagli scudi dell'originale (tools/prepara_stemmi.py)."""
import argparse
import glob
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = (136, 160)
PAD = 2


def shield_mask(rgb):
    h, w, _ = rgb.shape
    border = np.concatenate([rgb[:8].reshape(-1, 3), rgb[-8:].reshape(-1, 3), rgb[:, :8].reshape(-1, 3), rgb[:, -8:].reshape(-1, 3)])
    bg = np.median(border, 0)
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    lum, blum = rgb.mean(-1), bg.mean()
    near = np.abs(rgb - bg).max(-1) < 30
    shadow = (sat < 0.12) & (lum > blum * 0.58) & (lum < blum * 1.08)   # ombra morbida sul fondo, non il bordo di ferro
    cand = Image.fromarray(((near | shadow) * 255).astype(np.uint8)).copy()   # copia: floodfill non agisce sulla vista dell'array
    for x in range(0, w, 16):
        for y in (0, h - 1):
            if cand.getpixel((x, y)) == 255:
                ImageDraw.floodfill(cand, (x, y), 128)
    for y in range(0, h, 16):
        for x in (0, w - 1):
            if cand.getpixel((x, y)) == 255:
                ImageDraw.floodfill(cand, (x, y), 128)
    outside = np.asarray(cand) == 128
    m = Image.fromarray(((~outside) * 255).astype(np.uint8))
    m = m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    return np.asarray(m)


def shield(path):
    rgb = np.asarray(Image.open(path).convert('RGB')).astype(float)
    a = shield_mask(rgb)
    ys, xs = np.nonzero(a > 128)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    im = Image.fromarray(np.dstack([rgb.astype(np.uint8), a])).crop((x0, y0, x1, y1)).convert('RGBa')
    w, h = SIZE[0] - 2 * PAD, SIZE[1] - 2 * PAD
    s = min(w / im.width, h / im.height)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    out = Image.new('RGBa', SIZE, (0, 0, 0, 0))
    out.paste(im, ((SIZE[0] - im.width) // 2, SIZE[1] - PAD - im.height))
    return out.convert('RGBA')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cartella')
    ap.add_argument('--solo', default='')
    ap.add_argument('--foglio', default='')
    args = ap.parse_args()
    only = set(x for x in args.solo.split(',') if x)
    done = []
    for p in sorted(glob.glob(os.path.join(args.cartella, 'S_FN_*.png'))):
        fid = os.path.basename(p)[2:-4]
        if only and fid not in only:
            continue
        im = shield(p)
        im.save(os.path.join(ROOT, 'assets', 'stemmi', fid.lower() + '.png'))
        done.append(im)
        print(fid)
    if args.foglio and done:
        cols = min(len(done), 8)
        sheet = Image.new('RGBA', (cols * 146, ((len(done) + cols - 1) // cols) * 170), (60, 60, 60, 255))
        for i, im in enumerate(done):
            sheet.alpha_composite(im, ((i % cols) * 146 + 5, (i // cols) * 170 + 5))
        sheet.save(args.foglio)


if __name__ == '__main__':
    main()
