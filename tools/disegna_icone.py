"""Disegna a codice le icone e le pergamene dell'interfaccia che venivano ancora dall'originale (richiesta di Federico del
18/11/2026: non usare piu' nulla del gioco originale). Le scrive come immagini rifatte (ADR-043) in
`assets/rifatti/<percorso originale minuscolo>.png`, a 8 volte la misura dell'originale per le icone piccole (con le
mipmap del gioco restano nitide), cosi' AssetLibrary le usa al posto dell'originale senza toccare il codice.

Uso: python tools/disegna_icone.py [cartella del progetto]   (predefinita: la cartella sopra tools/)
Solo libreria standard + Pillow + numpy. Stile: oro sfumato con contorno bronzo come l'icona del Culto Imperiale.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

PROJECT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJECT, "assets", "rifatti")
SS = 4  # sovracampionamento del disegno

GOLD = [(255, 236, 160), (232, 186, 74), (176, 120, 30), (120, 74, 18)]
SILVER = [(250, 250, 250), (205, 208, 214), (150, 154, 162), (95, 98, 108)]
IVORY = [(255, 250, 232), (232, 222, 196), (186, 172, 140), (120, 108, 84)]
OUTLINE = (70, 40, 10, 255)


def save(img, original, frame=1):
    rel = original.lower()
    base = os.path.splitext(rel)[0]
    if frame > 1:
        base += "__f%02d" % frame
    path = os.path.join(OUT, base + ".png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return path


def gradient(size, colors, vertical=True):
    """Sfumatura metallica: chiaro in alto, scuro in basso, con un riflesso a un terzo."""
    w, h = size
    t = np.linspace(0.0, 1.0, h if vertical else w)
    stops = np.linspace(0.0, 1.0, len(colors))
    cols = np.array(colors, dtype=float)
    line = np.stack([np.interp(t, stops, cols[:, c]) for c in range(3)], axis=1)
    shine = np.exp(-((t - 0.28) ** 2) / 0.006)[:, None] * 40.0
    line = np.clip(line + shine, 0, 255)
    arr = np.repeat(line[:, None, :], w, axis=1) if vertical else np.repeat(line[None, :, :], h, axis=0)
    a = np.full(arr.shape[:2] + (1,), 255.0)
    return Image.fromarray(np.concatenate([arr, a], axis=2).astype(np.uint8), "RGBA")


class Canvas:
    """Disegno a misura `size` (pixel finali) con coordinate in unita' 0..100 su entrambi gli assi."""

    def __init__(self, size):
        self.size = size
        self.big = (size[0] * SS, size[1] * SS)
        self.img = Image.new("RGBA", self.big, (0, 0, 0, 0))

    def p(self, x, y):
        return (x / 100.0 * self.big[0], y / 100.0 * self.big[1])

    def pts(self, coords):
        return [self.p(x, y) for x, y in coords]

    def mask(self):
        return Image.new("L", self.big, 0)

    def fill(self, mask, colors, outline=True, stroke=3.0, shadow=True):
        """Riempie la maschera con la sfumatura, contorno scuro e ombra morbida."""
        if shadow:
            sh = mask.filter(ImageFilter.GaussianBlur(self.big[0] * 0.03))
            sh_img = Image.new("RGBA", self.big, (30, 18, 6, 0))
            sh_img.putalpha(sh.point(lambda v: int(v * 0.45)))
            off = Image.new("RGBA", self.big, (0, 0, 0, 0))
            off.alpha_composite(sh_img, (int(self.big[0] * 0.025), int(self.big[1] * 0.03)))
            self.img.alpha_composite(off)
        if outline:
            r = max(1, int(self.big[0] * stroke / 100.0))
            grown = mask.filter(ImageFilter.MaxFilter(r * 2 + 1))
            ol = Image.new("RGBA", self.big, OUTLINE)
            ol.putalpha(grown)
            self.img.alpha_composite(ol)
        body = gradient(self.big, colors)
        body.putalpha(mask)
        self.img.alpha_composite(body)

    def flat(self, mask, color):
        layer = Image.new("RGBA", self.big, color)
        layer.putalpha(ImageChops.multiply(mask, Image.new("L", self.big, color[3] if len(color) > 3 else 255)))
        self.img.alpha_composite(layer)

    def result(self):
        return self.img.resize(self.size, Image.LANCZOS)


def poly(c, coords):
    m = c.mask()
    ImageDraw.Draw(m).polygon(c.pts(coords), fill=255)
    return m


def ellipse(c, x0, y0, x1, y1):
    m = c.mask()
    ImageDraw.Draw(m).ellipse([*c.p(x0, y0), *c.p(x1, y1)], fill=255)
    return m


def rect(c, x0, y0, x1, y1, radius=0):
    m = c.mask()
    ImageDraw.Draw(m).rounded_rectangle([*c.p(x0, y0), *c.p(x1, y1)], radius=radius * c.big[0] / 100.0, fill=255)
    return m


def union(*masks):
    out = masks[0]
    for m in masks[1:]:
        out = ImageChops.lighter(out, m)
    return out


def minus(a, b):
    return ImageChops.subtract(a, b)


def star_points(cx, cy, r_out, r_in, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot + i * 180.0 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


# --- icone delle religioni (18x20 -> 144x160) ------------------------------------------------------------------------

ICON = (144, 160)


def latin_cross(c, x=50, top=8, bottom=94, arm_y=32, w=15, arm=64):
    return union(rect(c, x - w / 2, top, x + w / 2, bottom, 2), rect(c, x - arm / 2, arm_y - w / 2, x + arm / 2, arm_y + w / 2, 2))


def icon_catholic():
    c = Canvas(ICON)
    c.fill(latin_cross(c), GOLD)
    return c.result()


def icon_orthodox():
    c = Canvas(ICON)
    m = union(rect(c, 43, 6, 57, 95, 2), rect(c, 33, 16, 67, 26, 2), rect(c, 18, 36, 82, 48, 2),
              poly(c, [(26, 72), (74, 60), (74, 70), (26, 82)]))
    c.fill(m, GOLD)
    return c.result()


def icon_islam():
    c = Canvas(ICON)
    moon = minus(ellipse(c, 8, 18, 78, 82), ellipse(c, 26, 14, 92, 76))
    star = poly(c, star_points(72, 46, 17, 7))
    c.fill(union(moon, star), GOLD)
    return c.result()


def icon_pagan():
    c = Canvas(ICON)
    rays = []
    for i in range(12):
        a = math.radians(i * 30)
        a1, a2 = a - math.radians(9), a + math.radians(9)
        rays.append(poly(c, [(50 + 22 * math.cos(a1), 50 + 20 * math.sin(a1)), (50 + 46 * math.cos(a), 50 + 42 * math.sin(a)),
                            (50 + 22 * math.cos(a2), 50 + 20 * math.sin(a2))]))
    sun = union(ellipse(c, 24, 26, 76, 74), *rays)
    c.fill(sun, GOLD)
    inner = minus(ellipse(c, 33, 34, 67, 66), ellipse(c, 38, 39, 62, 61))
    c.flat(inner, (150, 92, 20, 200))
    return c.result()


def icon_heretic():
    c = Canvas(ICON)
    cross = latin_cross(c)
    crack = poly(c, [(40, 50), (62, 44), (46, 58), (66, 66), (60, 68), (38, 60), (54, 54), (36, 54)])
    c.fill(minus(cross, crack), SILVER)
    return c.result()


def icon_judaism():
    c = Canvas(ICON)
    star = union(poly(c, [(50, 6), (92, 74), (8, 74)]), poly(c, [(50, 94), (8, 26), (92, 26)]))
    c.fill(star, GOLD)
    inner = union(poly(c, [(50, 22), (79, 68), (21, 68)]), poly(c, [(50, 78), (21, 32), (79, 32)]))
    hollow = union(poly(c, [(50, 30), (72, 64), (28, 64)]), poly(c, [(50, 70), (28, 36), (72, 36)]))
    c.flat(minus(inner, hollow), (140, 90, 22, 210))
    return c.result()


def icon_excomm():
    c = Canvas(ICON)
    c.fill(latin_cross(c), SILVER, shadow=True)
    bar = poly(c, [(12, 20), (22, 10), (90, 82), (80, 92)])
    c.fill(bar, [(255, 120, 100), (210, 40, 30), (150, 20, 15), (90, 10, 8)], stroke=2.5, shadow=False)
    return c.result()


# --- attributi dei personaggi ------------------------------------------------------------------------------------------


def icon_acumen():  # chiave d'oro: buon governo e amministrazione
    c = Canvas(ICON)
    ring = minus(ellipse(c, 22, 6, 78, 46), ellipse(c, 36, 17, 64, 35))
    shaft = rect(c, 43, 38, 57, 92, 2)
    teeth = union(rect(c, 57, 70, 74, 78, 1), rect(c, 57, 82, 70, 90, 1))
    c.fill(union(ring, shaft, teeth), GOLD)
    return c.result()


def icon_dread():  # teschio d'avorio
    c = Canvas(ICON)
    head = union(ellipse(c, 14, 6, 86, 70), rect(c, 28, 50, 72, 86, 8))
    eyes = union(ellipse(c, 24, 36, 46, 58), ellipse(c, 54, 36, 76, 58))
    nose = poly(c, [(50, 58), (44, 70), (56, 70)])
    teeth = union(*[rect(c, x, 76, x + 2.5, 88) for x in (37, 45, 53, 61)])
    c.fill(minus(minus(minus(head, eyes), nose), teeth), IVORY)
    return c.result()


def crown_mask(c, top=18, base=78):
    m = poly(c, [(10, base), (10, 40), (28, 58), (36, top), (50, 50), (64, top), (72, 58), (90, 40), (90, base)])
    return union(m, rect(c, 8, base - 4, 92, base + 12, 3), ellipse(c, 30, top - 10, 42, top + 2), ellipse(c, 58, top - 10, 70, top + 2),
                 ellipse(c, 4, 33, 16, 45), ellipse(c, 84, 33, 96, 45))


def icon_influence():  # corona
    c = Canvas(ICON)
    c.fill(crown_mask(c), GOLD)
    for x in (26, 50, 74):
        c.flat(ellipse(c, x - 5, 77, x + 5, 87), (180, 20, 30, 255))
    return c.result()


def heater_shield(c, x0=12, y0=6, x1=88, y1=94):
    w = x1 - x0
    pts = [(x0, y0), (x1, y0), (x1, y0 + (y1 - y0) * 0.45)]
    for i in range(1, 12):
        t = i / 12.0
        pts.append((x1 - w / 2 * t, y0 + (y1 - y0) * (0.45 + 0.55 * math.sin(t * math.pi / 2))))
    pts.append(((x0 + x1) / 2, y1))
    for i in range(11, 0, -1):
        t = i / 12.0
        pts.append((x0 + w / 2 * t, y0 + (y1 - y0) * (0.45 + 0.55 * math.sin(t * math.pi / 2))))
    pts.append((x0, y0 + (y1 - y0) * 0.45))
    return poly(c, pts)


def icon_loyalty():  # scudo d'acciaio con bordo d'oro e croce
    c = Canvas(ICON)
    c.fill(heater_shield(c), GOLD)
    inner = heater_shield(c, 20, 13, 80, 86)
    c.fill(inner, [(120, 150, 210), (60, 90, 160), (35, 55, 110), (20, 30, 70)], outline=False, shadow=False)
    c.fill(union(rect(c, 45, 22, 55, 74, 1), rect(c, 30, 36, 70, 46, 1)), GOLD, stroke=1.5, shadow=False)
    return c.result()


def icon_piety():  # candela accesa
    c = Canvas(ICON)
    c.fill(rect(c, 36, 40, 64, 92, 3), IVORY)
    c.fill(union(rect(c, 22, 86, 78, 96, 3)), GOLD, shadow=False)
    flame = poly(c, [(50, 4), (60, 20), (62, 30), (56, 38), (50, 40), (44, 38), (38, 30), (40, 20)])
    c.fill(flame, [(255, 250, 200), (255, 210, 80), (240, 130, 30), (200, 70, 10)], stroke=1.5, shadow=False)
    return c.result()


def sword_mask(c, angle, length=86):
    """Spada lungo una diagonale: `angle` in gradi, centro 50,50."""
    m = Image.new("L", c.big, 0)
    d = ImageDraw.Draw(m)
    cx, cy = c.p(50, 50)
    u = c.big[0] / 100.0
    a = math.radians(angle)
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux

    def at(t, s):
        return (cx + ux * t * u + px * s * u, cy + uy * t * u + py * s * u)

    half = length / 2
    d.polygon([at(-half + 22, -6.5), at(half - 10, -6.5), at(half, 0), at(half - 10, 6.5), at(-half + 22, 6.5)], fill=255)  # lama
    d.polygon([at(-half + 16, -18), at(-half + 23, -18), at(-half + 23, 18), at(-half + 16, 18)], fill=255)  # guardia
    d.polygon([at(-half + 4, -4.5), at(-half + 17, -4.5), at(-half + 17, 4.5), at(-half + 4, 4.5)], fill=255)  # impugnatura
    r = 7.5 * u
    ex, ey = at(-half + 2, 0)
    d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=255)  # pomo
    return m


def icon_generalship():  # spade incrociate
    c = Canvas(ICON)
    c.fill(sword_mask(c, -45), SILVER, stroke=2.2)
    c.fill(sword_mask(c, -135), SILVER, stroke=2.2)
    return c.result()


def icon_happiness():  # coppa d'oro
    c = Canvas((120, 160))
    cup = poly(c, [(10, 8), (90, 8), (84, 30), (70, 46), (56, 52), (56, 72), (78, 86), (78, 94), (22, 94), (22, 86), (44, 72), (44, 52), (30, 46), (16, 30)])
    c.fill(cup, GOLD)
    c.flat(ellipse(c, 14, 4, 86, 14), (130, 20, 40, 220))
    return c.result()


def icon_zeal():  # fiamma
    c = Canvas((136, 160))
    flame = poly(c, [(50, 2), (62, 18), (74, 30), (84, 50), (82, 70), (70, 88), (50, 96), (30, 88), (18, 70), (18, 50), (28, 34), (36, 46), (40, 26)])
    c.fill(flame, [(255, 240, 160), (255, 180, 50), (230, 90, 20), (150, 30, 10)])
    core = poly(c, [(50, 40), (60, 56), (64, 72), (56, 86), (44, 86), (36, 72), (40, 56)])
    c.fill(core, [(255, 255, 230), (255, 230, 120), (255, 190, 60), (240, 150, 40)], outline=False, shadow=False)
    return c.result()


def icon_valour_unit():  # corona d'alloro
    c = Canvas((128, 136))
    leaves = []
    for side in (-1, 1):
        for i in range(7):
            theta = 100 + i * 23 if side < 0 else 80 - i * 23       # gradi, y verso il basso: 90 = in basso
            r = math.radians(theta)
            cx, cy = 50 + 34 * math.cos(r), 52 + 36 * math.sin(r)
            leaf = Image.new("L", c.big, 0)
            d = ImageDraw.Draw(leaf)
            x, y = c.p(cx, cy)
            rx, ry = c.big[0] * 0.11, c.big[1] * 0.05
            d.ellipse([x - rx, y - ry, x + rx, y + ry], fill=255)
            tangent = theta + 90 + (25 if side < 0 else -25)
            leaves.append(leaf.rotate(-tangent, center=(x, y), resample=Image.BICUBIC))
    c.fill(union(*leaves), GOLD, stroke=1.8)
    return c.result()


# --- stella del generale, scudo predefinito, sigillo --------------------------------------------------------------------


def general_star():
    c = Canvas((112, 112))
    c.fill(poly(c, star_points(50, 54, 46, 19)), GOLD, stroke=3.5)
    return c.result()


def default_shield(size):
    c = Canvas(size)
    c.fill(heater_shield(c, 6, 3, 94, 97), SILVER, stroke=2.5)
    inner = heater_shield(c, 14, 10, 86, 88)
    c.fill(inner, [(170, 170, 170), (135, 135, 138), (105, 105, 110), (80, 80, 86)], outline=False, shadow=False)
    return c.result()


def wax_seal(hover=False):
    size = (160, 164)
    c = Canvas(size)
    rnd = random.Random(7)
    pts = []
    for i in range(48):
        a = math.radians(i * 7.5)
        r = 44 + rnd.uniform(-2.2, 2.2)
        pts.append((50 + r * math.cos(a), 50 + r * math.sin(a)))
    red = [(230, 70, 60), (170, 25, 22), (120, 12, 12), (70, 6, 6)]
    if hover:
        red = [(250, 110, 90), (200, 40, 32), (150, 20, 18), (95, 10, 10)]
    c.fill(poly(c, pts), red, stroke=1.2)
    ring = minus(ellipse(c, 14, 14, 86, 86), ellipse(c, 18, 18, 82, 82))
    c.flat(ring, (60, 4, 4, 170))
    # corona in rilievo al centro
    crown = Canvas(size)
    m = crown_mask(crown, top=34, base=62)
    m = m.resize(c.big).transform(c.big, Image.AFFINE, (1.6, 0, -0.3 * c.big[0], 0, 1.6, -0.32 * c.big[1]))
    dark = m.filter(ImageFilter.GaussianBlur(3))
    c.flat(ImageChops.offset(dark, 6, 6), (50, 3, 3, 200))
    c.flat(m, (215, 60, 52, 255) if hover else (185, 40, 34, 255))
    c.flat(ImageChops.subtract(m, ImageChops.offset(m, 5, 5)), (255, 150, 130, 160))
    return c.result()


# --- pergamene e cornici ---------------------------------------------------------------------------------------------


def parchment(size, seed=1, burnt=True, alpha_edge=True):
    w, h = size
    rng = np.random.default_rng(seed)
    base = np.array([226, 207, 160], dtype=float)
    noise = np.zeros((h, w))
    for scale, amp in ((4, 18.0), (16, 10.0), (64, 6.0)):
        small = rng.normal(0, 1, (max(2, h // scale), max(2, w // scale)))
        img = Image.fromarray(((small - small.min()) / (np.ptp(small) + 1e-9) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        noise += (np.asarray(img, dtype=float) / 255.0 - 0.5) * amp
    fibers = Image.fromarray((rng.random((h, w // 6 + 1)) * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR).filter(ImageFilter.GaussianBlur(1))
    noise += (np.asarray(fibers, dtype=float) / 255.0 - 0.5) * 6.0
    yy, xx = np.mgrid[0:h, 0:w]
    dx = np.minimum(xx, w - 1 - xx) / (w * 0.5)
    dy = np.minimum(yy, h - 1 - yy) / (h * 0.5)
    edge = np.minimum(dx, dy)
    darken = np.clip(1.0 - edge / 0.22, 0, 1) ** 2 * (70.0 if burnt else 35.0)
    rgb = np.clip(base[None, None, :] + noise[:, :, None] - darken[:, :, None] * np.array([0.9, 1.1, 1.3]), 0, 255)
    a = np.full((h, w), 255.0)
    if alpha_edge:
        wobble = np.asarray(Image.fromarray((rng.random((h // 8 + 2, w // 8 + 2)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), dtype=float) / 255.0
        a = np.clip((edge - 0.012 - wobble * 0.02) / 0.012, 0, 1) * 255.0
    return Image.fromarray(np.dstack([rgb, a]).astype(np.uint8), "RGBA")


def divider(size=(301 * 2, 35 * 2)):
    c = Canvas(size)
    line = rect(c, 4, 46, 96, 54, 4)
    gem = poly(c, [(50, 10), (56, 50), (50, 90), (44, 50)])
    dots = union(ellipse(c, 37, 38, 41, 62), ellipse(c, 59, 38, 63, 62))
    c.fill(union(line, gem, dots), GOLD, stroke=1.0)
    return c.result()


def brass_frame(size=(329 * 2, 145 * 2)):
    c = Canvas(size)
    outer = rect(c, 0.5, 1, 99.5, 99, 2)
    inner = rect(c, 3, 7, 97, 93, 1)
    c.fill(minus(outer, inner), GOLD, stroke=0.6)
    return c.result()


# --- giacimenti dipinti a codice (legname, vigneti, piombo, stagno) e merci evidenziate --------------------------------
INK = (38, 28, 22, 255)


def _outlined(c, mask, colors, stroke=2.4):
    r = max(1, int(c.big[0] * stroke / 100.0))
    ol = Image.new("RGBA", c.big, INK)
    ol.putalpha(mask.filter(ImageFilter.MaxFilter(r * 2 + 1)))
    c.img.alpha_composite(ol)
    body = gradient(c.big, colors)
    body.putalpha(mask)
    c.img.alpha_composite(body)


def ore_pile(colors, seed):
    """Mucchio di pietre: poligoni irregolari dal basso verso l'alto, come le altre icone dei minerali."""
    c = Canvas(ICON)
    rnd = random.Random(seed)
    rows = [(84, 6, 6.5), (75, 6, 6.0), (66, 5, 6.0), (57, 4, 6.0), (48, 4, 5.5), (40, 3, 5.5), (32, 2, 5.5), (25, 1, 5.5)]
    for y, count, r in rows:
        width = count * r * 1.9
        for i in range(count):
            cx = 50 - width / 2 + r + i * r * 1.9 + rnd.uniform(-1.5, 1.5)
            cy = y + rnd.uniform(-2, 2)
            pts = []
            for k in range(6):
                a = math.radians(k * 60 + rnd.uniform(-18, 18))
                rr = r * rnd.uniform(1.0, 1.45)
                pts.append((cx + rr * math.cos(a), cy + rr * 0.85 * math.sin(a)))
            m = poly(c, pts)
            shade = rnd.uniform(-18, 18)
            cols = [tuple(int(max(0, min(255, v + shade))) for v in col) for col in colors]
            _outlined(c, m, cols, stroke=1.6)
            hi = poly(c, [pts[3], pts[4], (cx, cy)])
            c.flat(hi, (255, 255, 255, 60))
    return c.result()


def ore_forest():
    c = Canvas(ICON)
    _outlined(c, union(rect(c, 44, 60, 56, 94, 2), poly(c, [(38, 94), (62, 94), (56, 86), (44, 86)])),
              [(170, 120, 80), (130, 85, 50), (95, 60, 35), (70, 42, 25)])
    blobs = union(ellipse(c, 18, 26, 54, 62), ellipse(c, 44, 22, 84, 60), ellipse(c, 28, 6, 70, 44), ellipse(c, 12, 40, 46, 70),
                  ellipse(c, 52, 40, 88, 72))
    _outlined(c, blobs, [(150, 200, 90), (90, 150, 55), (55, 105, 40), (35, 70, 30)])
    for x, y in ((40, 22), (64, 34), (30, 50)):
        c.flat(ellipse(c, x - 7, y - 5, x + 7, y + 5), (200, 235, 140, 90))
    return c.result()


def ore_grapes():
    c = Canvas(ICON)
    leaf = poly(c, [(50, 14), (70, 4), (90, 14), (80, 22), (88, 32), (66, 30), (54, 22)])
    _outlined(c, leaf, [(170, 210, 100), (110, 165, 60), (70, 120, 40), (45, 85, 30)], stroke=1.8)
    _outlined(c, rect(c, 47, 10, 53, 28, 2), [(150, 110, 70), (120, 85, 50), (90, 60, 35), (70, 45, 25)], stroke=1.4)
    rnd = random.Random(3)
    rows = [(32, 4), (44, 5), (56, 4), (67, 3), (78, 2), (88, 1)]
    for y, n in rows:
        for i in range(n):
            cx = 50 + (i - (n - 1) / 2.0) * 13 + rnd.uniform(-1.5, 1.5)
            m = ellipse(c, cx - 8, y - 7.5, cx + 8, y + 7.5)
            _outlined(c, m, [(190, 130, 200), (130, 60, 140), (90, 30, 100), (60, 15, 70)], stroke=1.4)
            c.flat(ellipse(c, cx - 4, y - 5, cx - 1, y - 2), (255, 230, 255, 150))
    return c.result()


def highlighted(path):
    """Secondo fotogramma (evidenziato) di un'icona dipinta: piu' chiara e con un alone dorato."""
    im = Image.open(path).convert("RGBA")
    arr = np.asarray(im).astype(float)
    arr[..., :3] = np.clip(arr[..., :3] * 1.18 + 12, 0, 255)
    out = Image.fromarray(arr.astype(np.uint8), "RGBA")
    glow = im.split()[3].filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(5))
    halo = Image.new("RGBA", im.size, (255, 220, 120, 0))
    halo.putalpha(glow.point(lambda v: int(v * 0.55)))
    halo.alpha_composite(out)
    return halo


def main():
    written = []
    icons = {
        "campmap/parchments/icon_catholic.BIF": icon_catholic, "campmap/parchments/icon_orthodox.BIF": icon_orthodox,
        "campmap/parchments/icon_islam.BIF": icon_islam, "campmap/parchments/icon_pagan.BIF": icon_pagan,
        "campmap/parchments/icon_heretic.BIF": icon_heretic, "campmap/parchments/icon_judaism.BIF": icon_judaism,
        "campmap/parchments/icon_excomm.BIF": icon_excomm, "campmap/parchments/icon_acumen.BIF": icon_acumen,
        "campmap/parchments/icon_dread.BIF": icon_dread, "campmap/parchments/icon_influence.BIF": icon_influence,
        "campmap/parchments/icon_loyalty.BIF": icon_loyalty, "campmap/parchments/icon_piety.BIF": icon_piety,
        "campmap/parchments/icon_generalship.BIF": icon_generalship, "campmap/parchments/icon_happiness.BIF": icon_happiness,
        "campmap/parchments/icon_zeal.BIF": icon_zeal, "campmap/parchments/icon_valour_unit.BIF": icon_valour_unit,
        "campmap/general_star.BIF": general_star,
    }
    for original, fn in icons.items():
        written.append(save(fn(), original))
    written.append(save(icon_influence().resize((212, 224), Image.LANCZOS), "campmap/parchments/Icons/royalblood_crown.BIF"))
    written.append(save(default_shield((272, 320)), "campmap/shields/default_lge.BIF"))
    written.append(save(default_shield((144, 160)), "campmap/shields/Default_sml.BIF"))
    written.append(save(wax_seal(False), "campmap/Menu/seal.BIF", 1))
    written.append(save(wax_seal(True), "campmap/Menu/seal.BIF", 2))
    written.append(save(parchment((800, 600), 3, burnt=True, alpha_edge=False), "frontend_files/default_parchment_wide.tga"))
    written.append(save(parchment((321, 536), 5), "frontend_files/Main_Menu/parch322x536_no_border.BIF"))
    written.append(save(parchment((600, 560), 7), "frontend_files/wide_parchment_crop.BIF"))
    written.append(save(parchment((400, 130), 9, burnt=False), "campmap/TOOLTIP_BACK.BIF"))
    written.append(save(divider(), "campmap/parchments/divider region info.BIF"))
    written.append(save(brass_frame(), "frontend_files/mappic border.BIF"))
    written.append(save(ore_forest(), "campmap/parchments/Icons/ore_forest.BIF"))
    written.append(save(ore_grapes(), "campmap/parchments/Icons/ore_grapes.BIF"))
    written.append(save(ore_pile([(150, 155, 165), (95, 100, 112), (60, 64, 76), (35, 38, 48)], 11), "campmap/parchments/Icons/ore_lead.BIF"))
    written.append(save(ore_pile([(235, 238, 242), (190, 198, 206), (140, 150, 162), (95, 104, 118)], 23), "campmap/parchments/Icons/ore_tin.BIF"))
    for name in ("cotton", "fish", "glass", "linen", "pottery", "silk", "spice", "timber", "wool"):
        first = os.path.join(OUT, "campmap", "parchments", "icons", "goods_%s.png" % name)
        if os.path.exists(first):
            written.append(save(highlighted(first), "campmap/parchments/Icons/goods_%s.BIF" % name, 2))
    for p in written:
        print(os.path.relpath(p, PROJECT))


if __name__ == "__main__":
    main()
