"""Porti della plancia rifatti con l'IA locale (ADR-061): un dipinto per ognuno degli 8 orientamenti del molo.

Uso:  python tools/prepara_porti_mappa.py riferimenti <cartella conversione_icone>
      python tools/prepara_porti_mappa.py monta <cartella conversione_icone> [--foglio <png>]

Il porto della mappa e' campmap/ships/port.BIF: 8 fotogrammi 180x150, uno per orientamento del molo (SetPort, 0-7,
fotogramma = orientamento + 1; PieceArt.port_piece). `riferimenti` scrive in <conversione_icone>/porti/P01..P08.png i
fotogrammi dell'originale ingranditi su grigio uniforme (1024x768), da caricare in AI Playground (Edit by Prompt 2) con il
prompt di PROMPT_PORTI.md; i risultati vanno in risultati/P01..P08.png. `monta` li scontorna e li posa nell'ingombro del
fotogramma originale, al doppio della misura (360x300), in assets/rifatti/campmap/ships/port.png (fotogramma 1) e
port__f02.png ... port__f08.png (AssetLibrary.remade_path con il fotogramma). Manca un risultato: quel fotogramma resta
dell'originale.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

from prepara_edifici import fit, TOL

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.environ.get("MTW_GAME_DIR", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "originale"))
EXPORT = os.path.join(GAME, "_ASSET_EXPORT", "04_Interfaccia_Campagna", "campmap", "ships")
OUT = os.path.join(HERE, "..", "assets", "rifatti", "campmap", "ships")
FRAMES = 8
SCALE = 2
REF = (1024, 768)
GREY = (150, 152, 155)
SHADOW_SAT = 12        # ombra dipinta: grigio quasi neutro...
SHADOW_DEPTH = 75      # ...fino a tanto piu' scuro del fondo
SHADOW_GAIN = 1.6
SHADOW_MAX = 0.5


def original(k):
    return Image.open(os.path.join(EXPORT, "port.BIF__f%02d.png" % k)).convert("RGBA")


def references(src):
    folder = os.path.join(src, "porti")
    os.makedirs(folder, exist_ok=True)
    for k in range(1, FRAMES + 1):
        img = original(k)
        img = img.crop(img.getchannel("A").getbbox())
        img = fit(img, (round(REF[0] * 0.8), round(REF[1] * 0.8)))
        out = Image.new("RGBA", REF, GREY + (255,))
        out.alpha_composite(img, ((REF[0] - img.width) // 2, (REF[1] - img.height) // 2))
        out.convert("RGB").save(os.path.join(folder, "P%02d.png" % k))
    print("riferimenti in", folder)


def cut_port(path):
    """Come cut_grey, ma le ombre dipinte a terra (grigio neutro piu' scuro del fondo, attaccato al fondo) diventano
    un'ombra nera trasparente invece di una macchia grigia sulla mappa."""
    rgb = Image.open(path).convert("RGB")
    a = np.asarray(rgb).astype(np.int16)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)
    bgv = float(bg.mean())
    v = a.mean(axis=2)
    sat = a.max(axis=2) - a.min(axis=2)
    near = np.abs(a - bg).max(axis=2) <= TOL
    shadowish = (sat <= SHADOW_SAT) & (v < bgv) & (v > bgv - SHADOW_DEPTH)
    lab, n = ndimage.label(near | shadowish)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    outside = np.isin(lab, edge[edge > 0])
    solid = ndimage.binary_opening(~outside, structure=np.ones((3, 3)))
    fl, fn = ndimage.label(solid)
    if fn > 1:
        sizes = ndimage.sum(solid, fl, range(1, fn + 1))
        solid = np.isin(fl, np.nonzero(sizes >= sizes.max() * 0.02)[0] + 1)
    shadow = outside & ~near & shadowish
    obj = Image.fromarray((solid * 255).astype(np.uint8), "L").filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    shade = np.clip((bgv - v) / bgv * SHADOW_GAIN, 0.0, SHADOW_MAX) * shadow
    shade_l = Image.fromarray((shade * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(2.0))
    out = Image.new("RGBA", rgb.size, (0, 0, 0, 0))
    dark = Image.new("RGBA", rgb.size, (10, 8, 6, 0))
    dark.putalpha(shade_l)
    out.alpha_composite(dark)
    body = rgb.convert("RGBA")
    body.putalpha(obj)
    out.alpha_composite(body)
    return out.crop(out.getchannel("A").point(lambda x: 255 if x > 12 else 0).getbbox())


def mount(src, sheet_path=None):
    os.makedirs(OUT, exist_ok=True)
    pairs = []
    for k in range(1, FRAMES + 1):
        path = os.path.join(src, "risultati", "P%02d.png" % k)
        if not os.path.exists(path):
            print("manca P%02d: il fotogramma %d resta dell'originale" % (k, k))
            continue
        orig = original(k)
        x0, y0, x1, y1 = orig.getchannel("A").getbbox()
        box = (x0 * SCALE, y0 * SCALE, x1 * SCALE, y1 * SCALE)
        art = fit(cut_port(path), (box[2] - box[0], box[3] - box[1]))
        out = Image.new("RGBA", (orig.width * SCALE, orig.height * SCALE), (0, 0, 0, 0))
        out.alpha_composite(art, (box[0] + (box[2] - box[0] - art.width) // 2, box[1] + (box[3] - box[1] - art.height) // 2))
        name = "port.png" if k == 1 else "port__f%02d.png" % k
        out.save(os.path.join(OUT, name), optimize=True)
        print(name, out.size)
        pairs.append((orig.resize(out.size, Image.NEAREST), out))
    if sheet_path and pairs:
        w, h = pairs[0][1].size
        sheet = Image.new("RGBA", (len(pairs) * (w + 10), 2 * h + 10), (70, 110, 150, 255))
        for i, (o, n) in enumerate(pairs):
            sheet.alpha_composite(o, (i * (w + 10), 0))
            sheet.alpha_composite(n, (i * (w + 10), h + 10))
        sheet.convert("RGB").save(sheet_path)


def main():
    args = sys.argv[1:]
    if len(args) < 2 or args[0] not in ("riferimenti", "monta"):
        print(__doc__)
        sys.exit(2)
    if args[0] == "riferimenti":
        references(args[1])
    else:
        mount(args[1], args[args.index("--foglio") + 1] if "--foglio" in args else None)


if __name__ == "__main__":
    main()
