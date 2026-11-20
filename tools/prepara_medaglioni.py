"""Medaglioni dei cinque pulsanti informativi della barra (veste nuova) dai simboli dipinti con l'IA locale.

Uso:  python tools/prepara_medaglioni.py <cartella dei simboli> [--prova <foglio.png>]

Per ogni pulsante (military, alliance, economy, spy, heirs) legge <cartella>/button_<nome>.png: un solo oggetto al
centro su fondo nero (Intel AI Playground, preset Pro Image). Lo scontorna dal nero partendo dai bordi (il nero chiuso
dentro la figura resta), lo posa su un disco scuro dentro un anello d'ottone uguale per tutti e scrive in
assets/ui/veste tre stati da 140x132 (4 volte il 35x33 dell'originale, cerchio di raggio 66 centrato):
- medaglione_<nome>.png          normale, fondo di noce scuro;
- medaglione_<nome>_sopra.png    col puntatore sopra, fondo rosso come nell'originale;
- medaglione_<nome>_premuto.png  premuto, rosso piu' cupo e simbolo abbassato.
Con --prova salva anche un foglio di confronto (misura piena e misura a schermo sul legno).
"""
import argparse
import os

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

NAMES = ["military", "alliance", "economy", "spy", "heirs"]
SIZE = (140, 132)
SS = 4                          # si disegna 4 volte piu' grande e si riduce: bordi morbidi
RADIUS = 66.0                   # raggio del medaglione a misura finale
RING = 5.5                      # spessore dell'anello d'ottone (Federico, 11/11: bordi meno pesanti e spessi)
SYMBOL = 50.0                   # distanza massima dal centro a cui arriva il simbolo
# Ritocchi per simbolo (richieste di Federico dell'11/11):
# - "ingrandimento": il simbolo e' piu' grande del disco e ne esce in basso, tagliato dall'anello (la spada: si vedono
#   bene pomo, elsa e il primo tratto di lama); l'estremo alto resta al suo posto;
# - "luce", "contrasto", "colore", "gamma": schiariscono un simbolo troppo scuro per il fondo (il mantello della spia).
TWEAKS = {
    "military": {"ingrandimento": 2.1},
    "spy": {"gamma": 0.62, "luce": 1.15, "colore": 1.25},
}
BLACK = 26                      # sotto questo valore (0-255) un punto collegato al bordo e' fondo

OUTLINE = np.array([0x12, 0x0b, 0x06], float)
BRASS_DARK = np.array([0x6e, 0x52, 0x1e], float)
BRASS = np.array([0xd9, 0xb3, 0x54], float)
BRASS_LIGHT = np.array([0xff, 0xee, 0xb4], float)
HALO = (0xf2, 0xd9, 0xa0, 255)
FIELDS = {                      # centro e orlo del disco per stato
    "": (np.array([0x3d, 0x2a, 0x1a], float), np.array([0x12, 0x0b, 0x06], float)),
    "_sopra": (np.array([0xa2, 0x2c, 0x20], float), np.array([0x4e, 0x10, 0x0c], float)),
    "_premuto": (np.array([0x7a, 0x1e, 0x16], float), np.array([0x36, 0x0a, 0x08], float)),
}


def relight(rgb, tweaks):
    """Schiarisce il simbolo: gamma sotto 1 apre le ombre, poi luce e saturazione."""
    gamma = float(tweaks.get("gamma", 1.0))
    if gamma != 1.0:
        rgb = rgb.point(lambda v: int(round(255.0 * (v / 255.0) ** gamma)))
    rgb = ImageEnhance.Brightness(rgb).enhance(float(tweaks.get("luce", 1.0)))
    rgb = ImageEnhance.Contrast(rgb).enhance(float(tweaks.get("contrasto", 1.0)))
    return ImageEnhance.Color(rgb).enhance(float(tweaks.get("colore", 1.0)))


def cut_out(path, tweaks=None, black=BLACK, seal=0):
    """Simbolo RGBA ritagliato sul suo ingombro: trasparente il nero raggiungibile dai bordi. `black` = soglia del fondo;
    `seal` (dispari, 0 = no) chiude prima le fessure strette tra le parti della figura, cosi' le ombre scure dentro (tra le
    gambe, sotto il mantello) non si collegano al fondo e non diventano buchi."""
    rgb = Image.open(path).convert("RGB")
    a = np.asarray(rgb, dtype=np.uint8)
    solid = Image.fromarray(np.where(a.max(axis=2) > black, 255, 0).astype(np.uint8), "L").copy()   # copia: scrivibile
    if seal:
        solid = solid.filter(ImageFilter.MaxFilter(seal)).filter(ImageFilter.MinFilter(seal))
    w, h = solid.size
    seeds = [(x, y) for x in range(0, w, 16) for y in (0, h - 1)] + [(x, y) for y in range(0, h, 16) for x in (0, w - 1)]
    for seed in seeds:
        if solid.getpixel(seed) == 0:
            ImageDraw.floodfill(solid, seed, 128)
    mask = Image.fromarray(np.where(np.asarray(solid) == 128, 0, 255).astype(np.uint8), "L")
    mask = mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1.5))   # via l'alone nero del bordo
    out = relight(rgb, tweaks or {}).convert("RGBA")
    out.putalpha(mask)
    return out.crop(mask.point(lambda v: 255 if v > 24 else 0).getbbox())


def fit(symbol, reach):
    """Il simbolo ridotto in modo che il suo punto piu' lontano dal centro dell'ingombro stia a `reach`."""
    alpha = np.asarray(symbol.getchannel("A"), dtype=float)
    ys, xs = np.nonzero(alpha > 128)
    cx, cy = symbol.width / 2.0, symbol.height / 2.0
    far = float(np.sqrt((xs + 0.5 - cx) ** 2 + (ys + 0.5 - cy) ** 2).max())
    k = reach / far
    return symbol.resize((max(1, round(symbol.width * k)), max(1, round(symbol.height * k))), Image.LANCZOS)


def disc(state):
    """Anello e fondo del medaglione (RGBA a misura SS)."""
    w, h = SIZE[0] * SS, SIZE[1] * SS
    yy, xx = np.mgrid[0:h, 0:w]
    dx = (xx + 0.5) / SS - SIZE[0] / 2.0
    dy = (yy + 0.5) / SS - SIZE[1] / 2.0
    r = np.sqrt(dx * dx + dy * dy)
    ux, uy = dx / np.maximum(r, 1e-6), dy / np.maximum(r, 1e-6)
    light = -(ux * 0.55 + uy * 0.83)                 # luce dall'alto a sinistra: 1 verso la luce, -1 in ombra
    inner = RADIUS - 1.0 - RING                      # dove finisce l'ottone
    center, edge = FIELDS[state]
    t = np.clip(r / inner, 0.0, 1.0)[..., None] ** 1.6
    img = center * (1.0 - t) + edge * t
    # l'anello fa ombra sul fondo dal lato della luce, un filo di riflesso sul lato opposto
    rim = np.clip((r - (inner - 9.0)) / 9.0, 0.0, 1.0)
    img *= (1.0 - 0.55 * rim * np.clip(light, 0.0, 1.0))[..., None]
    img += (18.0 * rim * np.clip(-light, 0.0, 1.0))[..., None]
    # anello a mezzo tondo: la meta' esterna guarda fuori, quella interna guarda dentro
    p = np.clip((r - inner) / RING, 0.0, 1.0)
    tilt = np.cos(np.pi * (1.0 - p))                 # -1 sul bordo interno, +1 su quello esterno
    shade = np.clip(0.5 + 0.5 * tilt * light, 0.0, 1.0)
    dome = np.sin(np.pi * p)
    k = (0.12 + 0.88 * shade) * (0.5 + 0.5 * dome)
    if state == "_premuto":
        k *= 0.86
    brass = BRASS_DARK + (BRASS - BRASS_DARK) * np.clip(k * 1.3, 0.0, 1.0)[..., None]
    gloss = np.clip((shade - 0.8) / 0.2, 0.0, 1.0) * dome ** 3
    brass = brass + (BRASS_LIGHT - brass) * (0.55 * gloss)[..., None]
    ring = (r >= inner)[..., None]
    img = np.where(ring, brass, img)
    for line in (inner, RADIUS - 0.75):              # filo scuro tra fondo e ottone e orlo esterno
        d = np.clip(1.0 - np.abs(r - line) / 0.75, 0.0, 1.0)[..., None]
        img = img * (1.0 - d) + OUTLINE * d
    alpha = np.clip((RADIUS - r) * SS, 0.0, 1.0) * 255.0
    out = np.dstack([np.clip(img, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def medallion(symbol, state, tweaks=None):
    base = disc(state)
    art = fit(symbol, SYMBOL * SS)
    drop = 1.0 * SS if state == "_premuto" else 0.0
    top = base.height / 2.0 - art.height / 2.0
    zoom = float((tweaks or {}).get("ingrandimento", 1.0))
    if zoom != 1.0:                                  # piu' grande, con la cima ferma: il resto esce in basso
        art = art.resize((round(art.width * zoom), round(art.height * zoom)), Image.LANCZOS)
    pos = (round(base.width / 2.0 - art.width / 2.0), round(top + drop))
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    black = Image.new("RGBA", art.size, (0, 0, 0, 255))
    black.putalpha(art.getchannel("A").point(lambda v: int(v * 0.7)))
    shadow.paste(black, (pos[0] + SS, pos[1] + 2 * SS), black)
    shadow = shadow.filter(ImageFilter.GaussianBlur(1.6 * SS))
    # alone chiaro dietro il simbolo: stacca dal fondo anche le figure scure (il mantello della spia)
    halo = Image.new("RGBA", base.size, (0, 0, 0, 0))
    warm = Image.new("RGBA", art.size, HALO)
    warm.putalpha(art.getchannel("A").point(lambda v: int(v * 0.55)))
    halo.paste(warm, pos, warm)
    halo = halo.filter(ImageFilter.GaussianBlur(3.0 * SS))
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.alpha_composite(halo)
    layer.alpha_composite(shadow)
    cut = Image.new("RGBA", base.size, (0, 0, 0, 0))
    cut.paste(art, pos)                              # paste taglia cio' che esce dal foglio
    layer.alpha_composite(cut)
    # ombra e simbolo solo dentro il fondo, mai sopra l'ottone
    hole = Image.new("L", base.size, 0)
    c = (base.width / 2.0, base.height / 2.0)
    rad = (RADIUS - 1.0 - RING - 0.5) * SS
    ImageDraw.Draw(hole).ellipse([c[0] - rad, c[1] - rad, c[0] + rad, c[1] + rad], fill=255)
    kept = np.asarray(layer.getchannel("A"), float) * np.asarray(hole, float) / 255.0
    layer.putalpha(Image.fromarray(kept.astype(np.uint8), "L"))
    base.alpha_composite(layer)
    return base.resize(SIZE, Image.LANCZOS)


def proof(done, path):
    """Foglio di prova: sopra i tre stati a misura piena, sotto a 52x50 e 63x59 (schermi alti 900 e 1080) sul legno."""
    here = os.path.dirname(os.path.abspath(__file__))
    wood_path = os.path.join(here, "..", "assets", "ui", "veste", "legno.png")
    sheet = Image.new("RGBA", (20 + 150 * len(NAMES), 20 + 3 * 140 + 150), (0x2a, 0x1b, 0x10, 255))
    if os.path.exists(wood_path):
        wood = Image.open(wood_path).convert("RGBA")
        for x in range(0, sheet.width, wood.width):
            for y in range(0, sheet.height, wood.height):
                sheet.paste(wood, (x, y))
    low = 15 + 3 * 140 + 10
    for i, name in enumerate(NAMES):
        x = 15 + 150 * i
        for j, state in enumerate(FIELDS):
            sheet.alpha_composite(done[name + state], (x, 15 + 140 * j))
        sheet.alpha_composite(done[name].resize((52, 50), Image.LANCZOS), (x, low))
        sheet.alpha_composite(done[name].resize((63, 59), Image.LANCZOS), (x + 62, low))
        sheet.alpha_composite(done[name + "_sopra"].resize((52, 50), Image.LANCZOS), (x, low + 65))
        sheet.alpha_composite(done[name + "_premuto"].resize((52, 50), Image.LANCZOS), (x + 62, low + 65))
    sheet.convert("RGB").save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cartella")
    ap.add_argument("--prova")
    args = ap.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    dest = os.path.join(here, "..", "assets", "ui", "veste")
    done = {}
    for name in NAMES:
        tweaks = TWEAKS.get(name, {})
        symbol = cut_out(os.path.join(args.cartella, "button_%s.png" % name), tweaks)
        for state in FIELDS:
            img = medallion(symbol, state, tweaks)
            img.save(os.path.join(dest, "medaglione_%s%s.png" % (name, state)), optimize=True)
            done[name + state] = img
        print("medaglione_%s: simbolo %dx%d" % (name, symbol.width, symbol.height))
    if args.prova:
        proof(done, args.prova)


if __name__ == "__main__":
    main()
