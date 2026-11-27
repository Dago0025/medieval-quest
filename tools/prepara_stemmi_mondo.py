"""Stemmi provvisori delle fazioni nuove della mappa del mondo (ADR-079), nello stesso formato degli stemmi dipinti
(136x160, scudo con bordo di metallo): sagoma presa da uno stemma esistente, campo colorato con pennellate e figura
semplice in rilievo. Da sostituire con stemmi dipinti in AI Playground.
Uso: python3 prepara_stemmi_mondo.py <stemma di riferimento.png> <cartella di uscita>
Riferimento usato: assets/stemmi/fn_almohad.png (sagoma comune a tutti gli stemmi provvisori)."""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4  # sovracampionamento


def shield_masks(ref):
    a = np.asarray(ref.convert('RGBA'))[..., 3] > 40
    img = Image.fromarray((a * 255).astype(np.uint8)).resize((ref.size[0] * S, ref.size[1] * S), Image.BILINEAR)
    outer = np.asarray(img) > 127
    inner = np.asarray(Image.fromarray((outer * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(4 * S + 1))) > 127
    return outer, inner


def noise(h, w, seed, scale):
    rng = np.random.default_rng(seed)
    n = rng.random((h // scale + 2, w // scale + 2)).astype(np.float32)
    n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255
    return n


def field(outer, inner, color, seed):
    h, w = outer.shape
    y = np.linspace(0, 1, h)[:, None]
    x = np.linspace(0, 1, w)[None, :]
    light = 1.08 - 0.25 * y - 0.12 * np.abs(x - 0.4)
    strokes = 0.88 + 0.16 * noise(h, w, seed, 40 * S // 4) + 0.06 * noise(h, w, seed + 1, 6)
    base = np.array(color, np.float32)[None, None, :] / 255
    rgb = np.clip(base * (light * strokes)[..., None], 0, 1)
    # bordo di metallo: grigio con riflesso
    rim_l = 0.42 + 0.35 * (1 - y) * (0.7 + 0.3 * noise(h, w, seed + 2, 10))
    rim = np.repeat(rim_l[..., None], 3, axis=2) * np.array([0.95, 0.96, 1.0])[None, None, :]
    rim = np.broadcast_to(rim, rgb.shape)
    out = np.where(inner[..., None], rgb, rim)
    alpha = outer.astype(np.float32)
    # filo scuro tra campo e bordo
    edge = inner & ~(np.asarray(Image.fromarray((inner * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(S + 1))) > 127)
    out[edge] *= 0.35
    return np.dstack([out, alpha])


def emboss(layer_mask, color, canvas, depth=2):
    """Figura in rilievo: ombra in basso a destra, luce in alto a sinistra, colore pieno."""
    m = layer_mask.astype(np.float32)
    sh = np.roll(np.roll(m, depth * S, 0), depth * S, 1)
    hl = np.roll(np.roll(m, -S, 0), -S, 1)
    rgb = canvas[..., :3]
    rgb[:] = rgb * (1 - 0.55 * np.clip(sh - m, 0, 1))[..., None]
    c = np.array(color, np.float32) / 255
    h, w = m.shape
    y = np.linspace(0, 1, h)[:, None]
    shade = (1.15 - 0.35 * y) * (0.92 + 0.12 * noise(h, w, 7, 8))
    fill = np.clip(c[None, None, :] * shade[..., None], 0, 1)
    rgb[:] = np.where(m[..., None] > 0.5, fill, rgb)
    rim = np.clip(m - np.roll(np.roll(m, S, 0), S, 1), 0, 1)
    rgb[:] = np.clip(rgb + 0.25 * rim[..., None], 0, 1)
    dark = np.clip(m - np.roll(np.roll(m, -S, 0), -S, 1), 0, 1)
    rgb[:] = rgb * (1 - 0.45 * dark)[..., None]


def shape(size, draw_fn):
    img = Image.new('L', size, 0)
    draw_fn(ImageDraw.Draw(img), size)
    return np.asarray(img) > 127


def centre(size, dy=0.0):
    w, h = size
    return w * 0.5, h * (0.43 + dy)


def disc(r, dy=0.0):
    def f(d, size):
        cx, cy = centre(size, dy)
        rr = r * size[0]
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=255)
    return f


def sun_rays(r_in, r_out, n, dy=0.0):
    def f(d, size):
        cx, cy = centre(size, dy)
        for k in range(n):
            a = 2 * math.pi * k / n - math.pi / 2
            a1, a2 = a - math.pi / n * 0.45, a + math.pi / n * 0.45
            p = [(cx + r_in * size[0] * math.cos(a1), cy + r_in * size[0] * math.sin(a1)),
                 (cx + r_out * size[0] * math.cos(a), cy + r_out * size[0] * math.sin(a)),
                 (cx + r_in * size[0] * math.cos(a2), cy + r_in * size[0] * math.sin(a2))]
            d.polygon(p, fill=255)
    return f


def pyramid(d, size):
    w, h = size
    cx, base = w * 0.5, h * 0.66
    steps, sw, sh = 5, w * 0.62, h * 0.075
    for i in range(steps):
        ww = sw * (1 - i / (steps + 0.6))
        d.rectangle([cx - ww / 2, base - (i + 1) * sh, cx + ww / 2, base - i * sh], fill=255)
    tw = sw * 0.22
    top = base - steps * sh
    d.rectangle([cx - tw / 2, top - sh * 1.3, cx + tw / 2, top], fill=255)
    d.polygon([(cx - tw * 0.7, top - sh * 1.3), (cx + tw * 0.7, top - sh * 1.3), (cx, top - sh * 2.4)], fill=255)


def maya_temple(d, size):
    """Tempio maya alla maniera di Tikal (27/11/2026): piramide stretta e alta, tempietto e cresta traforata in cima."""
    w, h = size
    cx, base = w * 0.5, h * 0.70
    steps, sw, sh = 7, w * 0.50, h * 0.055
    for i in range(steps):
        ww = sw * (1 - i / (steps + 2.2))
        d.rectangle([cx - ww / 2, base - (i + 1) * sh, cx + ww / 2, base - i * sh], fill=255)
    top = base - steps * sh
    tw = sw * 0.30
    d.rectangle([cx - tw / 2, top - sh * 1.6, cx + tw / 2, top], fill=255)
    cw = tw * 0.62
    d.rectangle([cx - cw / 2, top - sh * 3.3, cx + cw / 2, top - sh * 1.6], fill=255)
    d.rectangle([cx - cw * 0.12, top - sh * 2.9, cx + cw * 0.12, top - sh * 2.0], fill=0)


def pueblo_terraces(d, size):
    """Casa pueblo a terrazze (27/11/2026): quattro piani che arretrano verso destra, con porte e scale a pioli."""
    w, h = size
    left, base = w * 0.22, h * 0.68
    fh = h * 0.105
    widths = [0.56, 0.43, 0.30, 0.17]
    for i, f in enumerate(widths):
        x0 = left + (widths[0] - f) * w
        d.rectangle([x0, base - (i + 1) * fh, left + widths[0] * w, base - i * fh], fill=255)
    for i, f in enumerate(widths[:3]):
        x0 = left + (widths[0] - f) * w
        dx = x0 + w * 0.05
        d.rectangle([dx, base - (i + 1) * fh + fh * 0.35, dx + w * 0.035, base - i * fh - fh * 0.05], fill=0)
    lx = left + (widths[0] - widths[1]) * w - w * 0.06
    for k in (0, 1):
        x = lx + k * w * 0.05
        d.line([(x, base - fh * 2.4), (x, base - fh * 0.9)], fill=255, width=max(2, int(w * 0.012)))


def maya_stairs(d, size):
    w, h = size
    cx, base = w * 0.5, h * 0.70
    sw, sh = w * 0.11, h * 0.055 * 7
    d.rectangle([cx - sw / 2, base - sh, cx + sw / 2, base], fill=255)


def stairs(d, size):
    # scalinata frontale (piu' scura sulla piramide)
    w, h = size
    cx, base = w * 0.5, h * 0.66
    d.polygon([(cx - w * 0.06, base), (cx + w * 0.06, base), (cx + w * 0.035, base - h * 0.375), (cx - w * 0.035, base - h * 0.375)], fill=255)


def crescent(d, size):
    cx, cy = centre(size, 0.04)
    r = size[0] * 0.27
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    r2 = r * 0.82
    off = r * 0.38
    d.ellipse([cx - r2, cy - r2 - off, cx + r2, cy + r2 - off], fill=0)


def star(cx_f, cy_f, r_f, n=5):
    def f(d, size):
        cx, cy, r = size[0] * cx_f, size[1] * cy_f, size[0] * r_f
        pts = []
        for k in range(2 * n):
            a = math.pi * k / n - math.pi / 2
            rr = r if k % 2 == 0 else r * 0.42
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        d.polygon(pts, fill=255)
    return f


def ring_cross(d, size):
    cx, cy = centre(size)
    r = size[0] * 0.27
    t = size[0] * 0.05
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    d.ellipse([cx - r + t, cy - r + t, cx + r - t, cy + r - t], fill=0)
    a = r * 0.62
    d.rectangle([cx - a, cy - t * 0.8, cx + a, cy + t * 0.8], fill=255)
    d.rectangle([cx - t * 0.8, cy - a, cx + t * 0.8, cy + a], fill=255)


def yin(d, size):
    cx, cy = centre(size)
    r = size[0] * 0.26
    d.pieslice([cx - r, cy - r, cx + r, cy + r], 90, 270, fill=255)
    d.ellipse([cx - r / 2, cy - r, cx + r / 2, cy], fill=255)
    d.ellipse([cx - r / 2, cy, cx + r / 2, cy + r], fill=0)
    s = r * 0.13
    d.ellipse([cx - s, cy + r / 2 - s, cx + s, cy + r / 2 + s], fill=255)
    d.ellipse([cx - s, cy - r / 2 - s, cx + s, cy - r / 2 + s], fill=0)


def make(ref, spec, out_path, seed):
    outer, inner = shield_masks(ref)
    canvas = field(outer, inner, spec['field'], seed)
    size = (outer.shape[1], outer.shape[0])
    for fn, color in spec['figures']:
        m = shape(size, fn) & inner
        emboss(m, color, canvas)
    img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8), 'RGBA')
    img = img.resize(ref.size, Image.LANCZOS)
    img.save(out_path)


SPECS = {
    'fn_japanese': {'field': (236, 230, 216), 'figures': [(disc(0.25), (188, 30, 40))]},
    'fn_chinese': {'field': (214, 162, 32), 'figures': [(disc(0.275), (245, 238, 220)), (yin, (40, 30, 26))]},
    'fn_aztecs': {'field': (32, 150, 140), 'figures': [(pyramid, (214, 170, 60)), (stairs, (150, 60, 40))]},
    'fn_inca': {'field': (176, 34, 38), 'figures': [(sun_rays(0.2, 0.36, 16), (226, 176, 50)), (disc(0.2), (232, 186, 60))]},
    'fn_kanem': {'field': (40, 120, 60), 'figures': [(crescent, (230, 196, 90)), (star(0.5, 0.36, 0.085), (230, 196, 90))]},
    'fn_mississippians': {'field': (176, 110, 50), 'figures': [(ring_cross, (30, 24, 20))]},
    # ADR-088: Coreani, Mongoli, Chola, Khmer
    'fn_koreans': {'field': (30, 75, 140), 'figures': [(disc(0.25), (240, 236, 224)), (star(0.5, 0.5, 0.11), (30, 75, 140))]},
    'fn_mongols': {'field': (74, 134, 192), 'figures': [(sun_rays(0.13, 0.27, 12), (216, 180, 74)), (disc(0.13), (216, 180, 74))]},
    'fn_chola': {'field': (140, 28, 60), 'figures': [(sun_rays(0.2, 0.36, 12), (232, 192, 96)), (disc(0.2), (232, 192, 96))]},
    'fn_khmer': {'field': (106, 58, 138), 'figures': [(stairs, (224, 184, 80))]},
    # 27/11/2026: Maya (piramide giada su rosso cinabro) e Karakhanidi (mezzaluna d'oro su rosso bruno)
    'fn_maya': {'field': (193, 68, 14), 'figures': [(maya_temple, (58, 150, 140)), (maya_stairs, (30, 95, 116))]},
    # 27/11/2026: Pueblo (casa a terrazze color pietra su turchese, sole sopra)
    'fn_pueblo': {'field': (31, 122, 153), 'figures': [(pueblo_terraces, (216, 176, 122)), (sun_rays(0.045, 0.095, 8, -0.2), (232, 200, 106)), (disc(0.045, -0.2), (232, 200, 106))]},
    'fn_karakhanids': {'field': (123, 45, 38), 'figures': [(crescent, (232, 200, 106)), (sun_rays(0.045, 0.1, 8, -0.1), (232, 200, 106)), (disc(0.045, -0.1), (232, 200, 106))]},
}


if __name__ == '__main__':
    ref = Image.open(sys.argv[1])
    os.makedirs(sys.argv[2], exist_ok=True)
    for k, (name, spec) in enumerate(SPECS.items()):
        make(ref, spec, os.path.join(sys.argv[2], name + '.png'), 100 + k)
        print(name)
