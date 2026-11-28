"""Medaglioni dei luoghi leggendari per i mockup (disegnati a codice, 4x e poi ridotti)."""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 4  # sovracampionamento

INK = (238, 224, 186, 255)       # pergamena chiara per i simboli
FIRE = (222, 120, 52, 255)

CATEGORIE = {
    "storico":    {"disco": (46, 31, 20), "disco2": (78, 54, 34), "anello": "ottone"},
    "mitologico": {"disco": (40, 30, 66), "disco2": (78, 58, 118), "anello": "ottone"},
    "marino":     {"disco": (16, 50, 58), "disco2": (34, 92, 102), "anello": "ottone"},
}


def _radial(size, c1, c2):
    im = Image.new("RGBA", (size, size))
    px = im.load()
    r = size / 2
    for y in range(size):
        for x in range(size):
            d = min(1.0, math.hypot(x - r * 0.85, y - r * 0.75) / (r * 1.1))
            px[x, y] = tuple(int(c2[i] * (1 - d) + c1[i] * d) for i in range(3)) + (255,)
    return im


def _brass_ring(size, width):
    """Anello d'ottone con luce in alto a sinistra."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    r = size / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - r + 0.5, y - r + 0.5)
            if r - width <= d <= r:
                ang = math.atan2(y - r, x - r)
                l = 0.5 + 0.5 * math.cos(ang + 2.36)  # luce da alto-sinistra
                t = abs((d - (r - width / 2)) / (width / 2))
                l = l * (1 - 0.45 * t)
                base = (120, 86, 34)
                hi = (246, 214, 128)
                col = tuple(int(base[i] + (hi[i] - base[i]) * l) for i in range(3))
                a = 255
                if d > r - 1.2 * S:
                    a = int(255 * max(0, (r - d) / (1.2 * S)))
                px[x, y] = col + (a,)
    return im


def _painted(art, big, reach=None, edge=None):
    """Simbolo dipinto (RGBA scontornato) dentro il disco: il punto piu' lontano dal centro a REACH del raggio, con
    un'ombra morbida in basso a destra; tagliato al fondo, mai sopra l'ottone (`edge` = spessore del bordo escluso)."""
    import numpy as np
    a = np.asarray(art.getchannel("A"), dtype=float)
    ys, xs = np.nonzero(a > 128)
    cx, cy = art.width / 2.0, art.height / 2.0
    far = float(np.sqrt((xs + 0.5 - cx) ** 2 + (ys + 0.5 - cy) ** 2).max())
    k = (big / 2.0) * (reach or REACH) / far
    art = art.resize((max(1, round(art.width * k)), max(1, round(art.height * k))), Image.LANCZOS)
    pos = (round(big / 2.0 - art.width / 2.0), round(big / 2.0 - art.height / 2.0))
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    shade = Image.new("RGBA", art.size, (0, 0, 0, 255))
    shade.putalpha(art.getchannel("A").point(lambda v: int(v * 0.75)))
    layer.paste(shade, (pos[0] + S, pos[1] + 2 * S), shade)
    layer = layer.filter(ImageFilter.GaussianBlur(1.5 * S))
    top = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    top.paste(art, pos)
    layer.alpha_composite(top)
    hole = Image.new("L", (big, big), 0)
    inner = big / 2.0 - (int(big * 0.085) if edge is None else edge)
    c = big / 2.0
    ImageDraw.Draw(hole).ellipse((c - inner, c - inner, c + inner, c + inner), fill=255)
    kept = Image.fromarray((np.asarray(layer.getchannel("A"), float) * np.asarray(hole, float) / 255.0).astype("uint8"), "L")
    layer.putalpha(kept)
    return layer


REACH = 0.80   # quanto del raggio occupa il simbolo dipinto (l'anello comincia a 0.83)
REACH_NUDO = 0.88   # senza anello (28/11/2026): il simbolo arriva quasi al bordo del disco


def _rim(big):
    """Bordo senza anello (richiesta di Federico del 28/11/2026): il disco scurisce verso l'orlo e finisce con un filo
    scuro sottile, cosi' si stacca dalla mappa senza la cornice d'ottone."""
    import numpy as np
    yy, xx = np.mgrid[0:big, 0:big]
    r = big / 2.0
    d = np.hypot(xx + 0.5 - r, yy + 0.5 - r) / r
    shade = np.clip((d - 0.72) / 0.28, 0, 1) ** 1.6 * 120          # ombra interna verso l'orlo
    line = np.clip(1.0 - np.abs(d - (1.0 - 0.9 * S / r)) / (0.9 * S / r), 0, 1) * 200   # filo scuro sull'orlo
    alpha = np.where(d <= 1.0, np.maximum(shade, line), 0).astype("uint8")
    im = Image.new("RGBA", (big, big), (16, 10, 5, 0))
    im.putalpha(Image.fromarray(alpha, "L"))
    return im


def medallion(simbolo, categoria="storico", size=46, stato=None, scudo=None, art=None, reach=None, anello=True):
    """`art`: simbolo dipinto (RGBA scontornato, tools/simboli_dipinti) al posto di quello disegnato a codice.
    `anello=False`: niente anello d'ottone, il disco finisce con un'ombra interna e un filo scuro (_rim)."""
    big = size * S
    cat = CATEGORIE[categoria]
    disc = _radial(big, cat["disco"], cat["disco2"])
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, big - 1, big - 1), fill=255)
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    out.paste(disc, (0, 0), mask)
    # simbolo
    if art is not None:
        if anello:
            out.alpha_composite(_painted(art, big, reach))
        else:
            out.alpha_composite(_rim(big))
            out.alpha_composite(_painted(art, big, reach or REACH_NUDO, edge=1.5 * S))
    else:
        sym = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        SIMBOLI[simbolo](ImageDraw.Draw(sym), big)
        if not anello:
            out.alpha_composite(_rim(big))
        out.alpha_composite(sym)
    if anello:
        out.alpha_composite(_brass_ring(big, int(big * 0.085)))
    else:
        # il simbolo non esce dal disco
        clip = Image.new("L", (big, big), 0)
        ImageDraw.Draw(clip).ellipse((0, 0, big - 1, big - 1), fill=255)
        from PIL import ImageChops
        out.putalpha(ImageChops.multiply(out.getchannel("A"), clip))
    # alone per i mitologici
    canvas = Image.new("RGBA", (big + 24 * S, big + 24 * S), (0, 0, 0, 0))
    off = 12 * S
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((off + 2 * S, off + 4 * S, off + big + 2 * S, off + big + 4 * S), fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(3 * S))
    canvas.alpha_composite(shadow)
    if categoria == "mitologico":
        glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse((off - 5 * S, off - 5 * S, off + big + 5 * S, off + big + 5 * S), fill=(190, 160, 255, 120))
        glow = glow.filter(ImageFilter.GaussianBlur(5 * S))
        canvas.alpha_composite(glow)
    canvas.alpha_composite(out, (off, off))
    d = ImageDraw.Draw(canvas)
    if stato == "evento":  # sigillo di ceralacca col punto esclamativo
        cx, cy, rr = off + big - 4 * S, off + 5 * S, 9 * S
        d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=(150, 22, 18, 255), outline=(90, 10, 8, 255), width=S)
        d.rectangle((cx - 1.6 * S, cy - 5.5 * S, cx + 1.6 * S, cy + 1.5 * S), fill=(250, 230, 200, 255))
        d.ellipse((cx - 1.8 * S, cy + 3 * S, cx + 1.8 * S, cy + 6.4 * S), fill=(250, 230, 200, 255))
    img = canvas.resize((canvas.width // S, canvas.height // S), Image.LANCZOS)
    if scudo is not None:  # stemma del proprietario in basso a destra
        sh = scudo.copy()
        sh.thumbnail((18, 21), Image.LANCZOS)
        img.alpha_composite(sh, (img.width - sh.width - 6, img.height - sh.height - 6))
    if stato == "ignoto":
        g = img.convert("LA").convert("RGBA")
        a = img.getchannel("A").point(lambda v: int(v * 0.75))
        g.putalpha(a)
        img = g
    return img


# ---------------------------------------------------------------- simboli
def _w(big, k=0.045):
    return max(1, int(big * k))


def temple(d, b):
    c = INK
    d.polygon([(b * .24, b * .38), (b * .5, b * .22), (b * .76, b * .38)], fill=c)
    d.rectangle((b * .24, b * .40, b * .76, b * .44), fill=c)
    for i in range(5):
        x = b * (.28 + i * .11)
        d.rectangle((x, b * .47, x + b * .05, b * .70), fill=c)
    d.rectangle((b * .22, b * .72, b * .78, b * .77), fill=c)


def horse(d, b):
    c = INK
    d.rectangle((b * .25, b * .66, b * .75, b * .70), fill=c)          # pianale
    for x in (.31, .69):
        d.ellipse((b * (x - .06), b * .68, b * (x + .06), b * .80), outline=c, width=_w(b, .03))
    d.rounded_rectangle((b * .30, b * .40, b * .64, b * .56), radius=b * .05, fill=c)  # corpo
    for x in (.33, .41, .52, .60):
        d.rectangle((b * x, b * .55, b * (x + .04), b * .66), fill=c)
    d.polygon([(b * .56, b * .44), (b * .64, b * .20), (b * .72, b * .20), (b * .66, b * .46)], fill=c)  # collo
    d.polygon([(b * .64, b * .20), (b * .80, b * .27), (b * .78, b * .32), (b * .66, b * .29)], fill=c)  # muso
    d.polygon([(b * .30, b * .42), (b * .22, b * .58), (b * .26, b * .58)], fill=c)  # coda


def labyrinth(d, b):
    c = INK
    w = _w(b, .035)
    for i, k in enumerate((.25, .33, .41)):
        box = (b * k, b * k, b * (1 - k), b * (1 - k))
        d.rectangle(box, outline=c, width=w)
        gap = b * .06
        if i % 2 == 0:
            d.rectangle((b * .5 - gap / 2, box[1] - w, b * .5 + gap / 2, box[1] + w), fill=(0, 0, 0, 0))
        else:
            d.rectangle((b * .5 - gap / 2, box[3] - w, b * .5 + gap / 2, box[3] + w), fill=(0, 0, 0, 0))
    d.ellipse((b * .46, b * .46, b * .54, b * .54), fill=FIRE)


def colossus(d, b):
    c = INK
    d.ellipse((b * .45, b * .20, b * .55, b * .30), fill=c)           # testa
    d.polygon([(b * .42, b * .31), (b * .58, b * .31), (b * .56, b * .55), (b * .44, b * .55)], fill=c)
    d.line((b * .57, b * .33, b * .68, b * .17), fill=c, width=_w(b, .05))  # braccio con fiaccola
    d.ellipse((b * .65, b * .09, b * .73, b * .18), fill=FIRE)
    d.line((b * .43, b * .34, b * .36, b * .50), fill=c, width=_w(b, .05))
    d.line((b * .46, b * .54, b * .34, b * .76), fill=c, width=_w(b, .055))  # gambe divaricate
    d.line((b * .54, b * .54, b * .66, b * .76), fill=c, width=_w(b, .055))
    d.rectangle((b * .26, b * .76, b * .40, b * .80), fill=c)
    d.rectangle((b * .60, b * .76, b * .74, b * .80), fill=c)


def volcano(d, b, hell=False):
    c = INK
    d.polygon([(b * .18, b * .76), (b * .42, b * .38), (b * .58, b * .38), (b * .82, b * .76)], fill=c)
    d.polygon([(b * .42, b * .38), (b * .5, b * .45), (b * .58, b * .38)], fill=(0, 0, 0, 0))
    col = (210, 50, 30, 255) if hell else FIRE
    d.polygon([(b * .44, b * .37), (b * .40, b * .20), (b * .48, b * .28), (b * .50, b * .12), (b * .53, b * .27),
               (b * .60, b * .19), (b * .56, b * .37)], fill=col)
    d.line((b * .47, b * .40, b * .38, b * .60), fill=col, width=_w(b, .03))


def hekla(d, b):
    volcano(d, b, hell=True)


def whirlpool(d, b):
    c = INK
    pts = []
    for i in range(160):
        t = i / 159 * 4.2 * math.pi
        r = b * (.05 + .26 * i / 159)
        pts.append((b * .5 + r * math.cos(t), b * .52 + r * math.sin(t) * .8))
    d.line(pts, fill=c, width=_w(b, .035), joint="curve")
    d.polygon([(b * .16, b * .30), (b * .26, b * .18), (b * .30, b * .32)], fill=c)  # rupe di Scilla


def lyre(d, b):
    c = INK
    w = _w(b, .045)
    d.arc((b * .26, b * .18, b * .52, b * .70), 120, 270, fill=c, width=w)
    d.arc((b * .48, b * .18, b * .74, b * .70), 270, 60, fill=c, width=w)
    d.line((b * .30, b * .26, b * .70, b * .26), fill=c, width=w)
    d.rounded_rectangle((b * .34, b * .64, b * .66, b * .76), radius=b * .04, fill=c)
    for x in (.42, .5, .58):
        d.line((b * x, b * .27, b * x, b * .64), fill=c, width=max(1, w // 2))


def pyramids(d, b):
    c = INK
    d.polygon([(b * .16, b * .74), (b * .42, b * .30), (b * .68, b * .74)], fill=c)
    d.polygon([(b * .42, b * .30), (b * .52, b * .74), (b * .68, b * .74)], fill=(200, 180, 140, 255))
    d.polygon([(b * .56, b * .74), (b * .72, b * .46), (b * .86, b * .74)], fill=c)
    d.line((b * .14, b * .76, b * .86, b * .76), fill=c, width=_w(b, .03))


def lighthouse(d, b):
    c = INK
    d.polygon([(b * .36, b * .78), (b * .40, b * .44), (b * .60, b * .44), (b * .64, b * .78)], fill=c)
    d.rectangle((b * .42, b * .30, b * .58, b * .44), fill=c)
    d.ellipse((b * .44, b * .16, b * .56, b * .30), fill=FIRE)
    d.line((b * .30, b * .23, b * .40, b * .23), fill=FIRE, width=_w(b, .025))
    d.line((b * .60, b * .23, b * .70, b * .23), fill=FIRE, width=_w(b, .025))


def holy_cross(d, b):
    c = INK
    w = b * .06
    d.rectangle((b * .5 - w / 2, b * .18, b * .5 + w / 2, b * .80), fill=c)
    d.rectangle((b * .30, b * .38 - w / 2, b * .70, b * .38 + w / 2), fill=c)
    for cx, cy in ((.37, .27), (.63, .27), (.37, .57), (.63, .57)):
        r = b * .05
        d.rectangle((b * cx - r * .3, b * cy - r, b * cx + r * .3, b * cy + r), fill=c)
        d.rectangle((b * cx - r, b * cy - r * .3, b * cx + r, b * cy + r * .3), fill=c)


def arches(d, b):
    c = INK
    d.rectangle((b * .20, b * .30, b * .80, b * .74), fill=c)
    for row, (y0, y1) in enumerate(((.38, .52), (.58, .72))):
        for i in range(4):
            x0 = b * (.25 + i * .14)
            d.rounded_rectangle((x0, b * y0, x0 + b * .08, b * y1), radius=b * .04, fill=(0, 0, 0, 0))
    d.rectangle((b * .18, b * .26, b * .82, b * .30), fill=c)


def kraken(d, b):
    c = INK
    w = _w(b, .05)
    for i, x0 in enumerate((.24, .38, .52, .66)):
        pts = []
        for k in range(30):
            t = k / 29
            pts.append((b * (x0 + .06 * math.sin(t * 5 + i)), b * (.78 - t * .50)))
        d.line(pts, fill=c, width=w, joint="curve")
        d.ellipse((pts[-1][0] - w, pts[-1][1] - w, pts[-1][0] + w, pts[-1][1] + w), fill=c)
    for x in range(4):
        d.arc((b * (.14 + x * .18), b * .72, b * (.32 + x * .18), b * .84), 200, 340, fill=c, width=_w(b, .03))


def trilithon(d, b):
    c = INK
    for x0 in (.18, .54):
        d.rectangle((b * x0, b * .40, b * (x0 + .09), b * .74), fill=c)
        d.rectangle((b * (x0 + .19), b * .40, b * (x0 + .28), b * .74), fill=c)
        d.rectangle((b * (x0 - .02), b * .33, b * (x0 + .30), b * .39), fill=c)
    d.line((b * .14, b * .76, b * .86, b * .76), fill=c, width=_w(b, .03))


def tree(d, b):
    c = INK
    d.rectangle((b * .46, b * .48, b * .54, b * .80), fill=c)
    d.ellipse((b * .22, b * .18, b * .78, b * .56), fill=c)
    for x in (.36, .50, .64):
        d.line((b * .5, b * .78, b * x - (b * .12 if x < .5 else -b * .12 if x > .5 else 0), b * .82), fill=c, width=_w(b, .03))
    d.ellipse((b * .44, b * .30, b * .56, b * .42), fill=(0, 0, 0, 0))


def rampart(d, b):
    c = INK
    d.rectangle((b * .16, b * .46, b * .84, b * .74), fill=c)
    for i in range(6):
        x = b * (.16 + i * .12)
        d.rectangle((x, b * .36, x + b * .07, b * .46), fill=c)
    d.polygon([(b * .44, b * .74), (b * .44, b * .60), (b * .50, b * .54), (b * .56, b * .60), (b * .56, b * .74)], fill=(0, 0, 0, 0))


def hexes(d, b):
    c = INK
    r = b * .085
    for (cx, cy) in ((.35, .40), (.52, .40), (.69, .40), (.27, .55), (.44, .55), (.61, .55), (.35, .70), (.52, .70)):
        pts = [(b * cx + r * math.cos(math.pi / 3 * k), b * cy + r * math.sin(math.pi / 3 * k)) for k in range(6)]
        d.polygon(pts, fill=c)


def phantom_island(d, b):
    c = INK
    d.ellipse((b * .26, b * .44, b * .74, b * .66), fill=c)
    d.polygon([(b * .40, b * .50), (b * .50, b * .30), (b * .60, b * .50)], fill=c)
    for y in (.30, .38):
        d.arc((b * .14, b * y, b * .46, b * (y + .1)), 190, 350, fill=(200, 210, 220, 220), width=_w(b, .025))
        d.arc((b * .54, b * y, b * .86, b * (y + .1)), 190, 350, fill=(200, 210, 220, 220), width=_w(b, .025))
    for x in range(3):
        d.arc((b * (.22 + x * .2), b * .70, b * (.38 + x * .2), b * .80), 200, 340, fill=c, width=_w(b, .03))


def celtic_cross(d, b):
    c = INK
    w = b * .07
    d.ellipse((b * .34, b * .22, b * .66, b * .54), outline=c, width=_w(b, .04))
    d.rectangle((b * .5 - w / 2, b * .16, b * .5 + w / 2, b * .80), fill=c)
    d.rectangle((b * .26, b * .38 - w / 2, b * .74, b * .38 + w / 2), fill=c)
    d.rectangle((b * .40, b * .76, b * .60, b * .82), fill=c)


def athos(d, b):
    c = INK
    d.polygon([(b * .16, b * .76), (b * .46, b * .30), (b * .60, b * .48), (b * .66, b * .42), (b * .84, b * .76)], fill=c)
    w = b * .035
    d.rectangle((b * .46 - w / 2, b * .12, b * .46 + w / 2, b * .28), fill=FIRE)
    d.rectangle((b * .40, b * .17, b * .52, b * .17 + w), fill=FIRE)


def kaaba(d, b):
    c = INK
    d.polygon([(b * .26, b * .38), (b * .62, b * .30), (b * .78, b * .40), (b * .78, b * .74), (b * .42, b * .80), (b * .26, b * .72)], fill=c)
    d.line((b * .26, b * .48, b * .62, b * .42, b * .78, b * .50), fill=(60, 44, 30, 255), width=_w(b, .035))
    d.line((b * .62, b * .30, b * .62, b * .78), fill=(150, 130, 100, 255), width=_w(b, .015))


def ziggurat(d, b):
    c = INK
    for i, (x0, x1) in enumerate(((.16, .84), (.26, .74), (.36, .64), (.44, .56))):
        y1 = .78 - i * .13
        d.rectangle((b * x0, b * (y1 - .12), b * x1, b * y1), fill=c)
    d.line((b * .44, b * .14, b * .56, b * .22), fill=(60, 44, 30, 255), width=_w(b, .03))


def scallop(d, b):
    c = INK
    d.pieslice((b * .18, b * .20, b * .82, b * .84), 200, 340, fill=c)
    for k in range(7):
        ang = math.radians(205 + k * 21.5)
        d.line((b * .5, b * .52, b * .5 + b * .30 * math.cos(ang), b * .52 + b * .30 * math.sin(ang)), fill=(60, 44, 30, 255), width=_w(b, .02))
    d.polygon([(b * .40, b * .52), (b * .60, b * .52), (b * .56, b * .66), (b * .44, b * .66)], fill=c)


def great_wall(d, b):
    c = INK
    pts = [(b * .12, b * .70), (b * .30, b * .52), (b * .50, b * .62), (b * .70, b * .44), (b * .88, b * .54)]
    d.line(pts, fill=c, width=_w(b, .09), joint="curve")
    for (x, y) in pts[1:4]:
        d.rectangle((x - b * .06, y - b * .14, x + b * .06, y), fill=c)
        d.rectangle((x - b * .07, y - b * .17, x + b * .07, y - b * .13), fill=c)


def mountain(d, b):
    c = INK
    d.polygon([(b * .12, b * .76), (b * .42, b * .30), (b * .58, b * .30), (b * .88, b * .76)], fill=c)
    d.polygon([(b * .42, b * .30), (b * .58, b * .30), (b * .66, b * .42), (b * .58, b * .40), (b * .50, b * .46), (b * .42, b * .40), (b * .34, b * .42)], fill=(250, 248, 240, 255))


def towers(d, b):
    c = INK
    for (x, h) in ((.30, .40), (.5, .55), (.70, .40)):
        d.polygon([(b * (x - .09), b * .76), (b * (x - .05), b * (.76 - h * .6)), (b * x, b * (.76 - h)), (b * (x + .05), b * (.76 - h * .6)), (b * (x + .09), b * .76)], fill=c)
    d.rectangle((b * .16, b * .74, b * .84, b * .80), fill=c)


def lotus(d, b):
    c = INK
    for ang in (-60, -30, 0, 30, 60):
        a = math.radians(ang - 90)
        cx, cy = b * .5 + b * .16 * math.cos(a), b * .58 + b * .16 * math.sin(a)
        d.ellipse((cx - b * .08, cy - b * .16, cx + b * .08, cy + b * .16), fill=c)
    d.ellipse((b * .30, b * .62, b * .70, b * .74), fill=c)


def dome(d, b):
    c = INK
    d.pieslice((b * .28, b * .26, b * .72, b * .70), 180, 360, fill=c)
    d.rectangle((b * .28, b * .48, b * .72, b * .76), fill=c)
    d.line((b * .5, b * .16, b * .5, b * .27), fill=c, width=_w(b, .03))
    for x in (.18, .82):
        d.rectangle((b * (x - .03), b * .30, b * (x + .03), b * .76), fill=c)
    d.rounded_rectangle((b * .44, b * .58, b * .56, b * .76), radius=b * .05, fill=(60, 44, 30, 255))


def book(d, b):
    c = INK
    d.polygon([(b * .16, b * .32), (b * .48, b * .38), (b * .48, b * .76), (b * .16, b * .70)], fill=c)
    d.polygon([(b * .84, b * .32), (b * .52, b * .38), (b * .52, b * .76), (b * .84, b * .70)], fill=c)
    for k in range(3):
        y = .46 + k * .08
        d.line((b * .22, b * (y - .02), b * .42, b * y), fill=(60, 44, 30, 255), width=_w(b, .015))
        d.line((b * .58, b * y, b * .78, b * (y - .02)), fill=(60, 44, 30, 255), width=_w(b, .015))


def gem(d, b):
    c = INK
    d.polygon([(b * .26, b * .38), (b * .38, b * .24), (b * .62, b * .24), (b * .74, b * .38), (b * .5, b * .80)], fill=c)
    d.line((b * .26, b * .38, b * .74, b * .38), fill=(60, 44, 30, 255), width=_w(b, .02))
    d.line((b * .38, b * .24, b * .44, b * .38, b * .5, b * .80, b * .56, b * .38, b * .62, b * .24), fill=(60, 44, 30, 255), width=_w(b, .015))


def crown(d, b):
    c = INK
    d.polygon([(b * .20, b * .66), (b * .20, b * .38), (b * .34, b * .52), (b * .5, b * .30), (b * .66, b * .52), (b * .80, b * .38), (b * .80, b * .66)], fill=c)
    d.rectangle((b * .20, b * .66, b * .80, b * .74), fill=c)
    for x in (.20, .5, .80):
        y = .38 if x != .5 else .30
        d.ellipse((b * (x - .04), b * (y - .08), b * (x + .04), b * y), fill=c)


def step_pyramid(d, b):
    c = INK
    for i in range(5):
        x0, x1 = .14 + i * .07, .86 - i * .07
        y1 = .78 - i * .09
        d.rectangle((b * x0, b * (y1 - .09), b * x1, b * y1), fill=c)
    d.rectangle((b * .44, b * .20, b * .56, b * .34), fill=c)
    d.rectangle((b * .47, b * .40, b * .53, b * .78), fill=(60, 44, 30, 255))


def mound(d, b):
    c = INK
    d.polygon([(b * .10, b * .76), (b * .28, b * .46), (b * .72, b * .46), (b * .90, b * .76)], fill=c)
    d.polygon([(b * .40, b * .46), (b * .44, b * .32), (b * .56, b * .32), (b * .60, b * .46)], fill=c)
    d.polygon([(b * .42, b * .32), (b * .5, b * .22), (b * .58, b * .32)], fill=c)


def sun(d, b):
    c = INK
    d.ellipse((b * .34, b * .34, b * .66, b * .66), fill=c)
    for k in range(12):
        a = math.radians(k * 30)
        d.line((b * .5 + b * .20 * math.cos(a), b * .5 + b * .20 * math.sin(a), b * .5 + b * .32 * math.cos(a), b * .5 + b * .32 * math.sin(a)), fill=c, width=_w(b, .04))
    d.ellipse((b * .42, b * .44, b * .46, b * .48), fill=(60, 44, 30, 255))
    d.ellipse((b * .54, b * .44, b * .58, b * .48), fill=(60, 44, 30, 255))
    d.arc((b * .42, b * .46, b * .58, b * .60), 20, 160, fill=(60, 44, 30, 255), width=_w(b, .02))


def fountain(d, b):
    c = INK
    d.ellipse((b * .18, b * .62, b * .82, b * .80), fill=c)
    d.rectangle((b * .46, b * .40, b * .54, b * .66), fill=c)
    d.ellipse((b * .34, b * .36, b * .66, b * .46), fill=c)
    for x0, x1 in ((.40, .24), (.60, .76)):
        d.arc((min(b * x0, b * x1), b * .16, max(b * x0, b * x1) + b * .16, b * .66), 180 if x1 < x0 else 270, 270 if x1 < x0 else 360, fill=(200, 220, 230, 255), width=_w(b, .03))
    d.line((b * .5, b * .14, b * .5, b * .36), fill=(200, 220, 230, 255), width=_w(b, .03))


def city(d, b):
    c = INK
    for i, h in enumerate((.20, .30, .24, .36, .22, .28, .18)):
        x = .16 + i * .10
        d.rectangle((b * x, b * (.76 - h), b * (x + .07), b * .76), fill=c)
    d.rectangle((b * .14, b * .74, b * .86, b * .80), fill=c)


def weed(d, b):
    c = INK
    for i, x0 in enumerate((.26, .42, .58, .74)):
        pts = [(b * (x0 + .05 * math.sin(k * .7 + i)), b * (.80 - k * .055)) for k in range(10)]
        d.line(pts, fill=c, width=_w(b, .035), joint="curve")
        for k in (3, 6):
            px, py = pts[k]
            d.ellipse((px - b * .04, py - b * .02, px + b * .02, py + b * .02), fill=c)
    for x in range(3):
        d.arc((b * (.18 + x * .22), b * .74, b * (.40 + x * .22), b * .84), 200, 340, fill=c, width=_w(b, .025))


def terraces(d, b):
    c = INK
    d.polygon([(b * .12, b * .78), (b * .36, b * .26), (b * .46, b * .40), (b * .56, b * .30), (b * .88, b * .78)], fill=c)
    for k in range(4):
        y = .50 + k * .07
        d.line((b * (.30 - k * .03), b * y, b * (.72 + k * .03), b * y), fill=(60, 44, 30, 255), width=_w(b, .02))


def throne(d, b):
    c = (246, 214, 128, 255)
    d.rectangle((b * .32, b * .20, b * .68, b * .58), fill=c)
    d.polygon([(b * .32, b * .20), (b * .40, b * .10), (b * .5, b * .16), (b * .60, b * .10), (b * .68, b * .20)], fill=c)
    d.rectangle((b * .24, b * .56, b * .76, b * .64), fill=c)
    d.rectangle((b * .28, b * .64, b * .34, b * .80), fill=c)
    d.rectangle((b * .66, b * .64, b * .72, b * .80), fill=c)
    d.rectangle((b * .20, b * .42, b * .30, b * .58), fill=c)
    d.rectangle((b * .70, b * .42, b * .80, b * .58), fill=c)
    d.rectangle((b * .48, b * .26, b * .52, b * .50), fill=(60, 44, 30, 255))
    for y in (.32, .38, .44):
        d.rectangle((b * .42, b * y, b * .58, b * (y + .025)), fill=(60, 44, 30, 255))


SIMBOLI = {
    "tempio": temple, "cavallo": horse, "labirinto": labyrinth, "colosso": colossus, "vulcano": volcano,
    "hekla": hekla, "gorgo": whirlpool, "lira": lyre, "piramidi": pyramids, "faro": lighthouse,
    "croce": holy_cross, "arcate": arches, "kraken": kraken, "triliti": trilithon, "albero": tree,
    "vallo": rampart, "esagoni": hexes, "isola": phantom_island, "croce_celtica": celtic_cross, "athos": athos,
    "kaaba": kaaba, "ziggurat": ziggurat, "conchiglia": scallop, "muraglia": great_wall, "monte": mountain, "torri": towers,
    "loto": lotus, "cupola": dome, "libro": book, "gemma": gem, "corona": crown, "gradoni": step_pyramid, "tumulo": mound,
    "sole": sun, "fontana": fountain, "citta": city, "alghe": weed, "terrazze": terraces, "trono": throne,
}
