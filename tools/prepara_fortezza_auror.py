"""Fortezza bianca degli Auror (ADR-076) dal dipinto di AI Playground: icona del castello e pedina della mappa.

Uso:  python tools/prepara_fortezza_auror.py <dipinto AIPG 1:1 su grigio> [--foglio <png>] [--uscita <cartella assets>]

Scrive (FortressArt li usa solo nella regione natia degli Auror, in modalita' Auror):
  assets/rifatti/campmap/review_panel/buildings/fortezza_auror.png   icona 272x200 (come le icone rifatte degli edifici)
  assets/rifatti/campmap/pieces/buildings/fortezza_auror.png         pedina: stendardo, aste e ombra del castello FORTRESS
                                                                     dell'originale (rossi e magenta chiave, ricolorati da
                                                                     PieceArt) con la fortezza dipinta al posto delle mura
Il dipinto si scontorna dal grigio come le basi degli edifici (prepara_edifici.cut_grey). Sulla mappa la pedina si disegna
FortressArt.MAP_SCALE volte piu' alta degli altri castelli.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prepara_edifici import cut_grey, BASE_KEEP  # noqa: E402
from prepara_castelli_mappa import EXPORT, body_box, unkey  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ICON_SIZE = (272, 200)
ICON_MARGIN = 6
GROW = 1.12            # la fortezza e' un poco piu' larga delle mura della fortezza originale


def icon_from(art):
    w, h = ICON_SIZE
    k = min((w - 2 * ICON_MARGIN) / art.width, (h - ICON_MARGIN) / art.height)
    small = art.resize((max(1, round(art.width * k)), max(1, round(art.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", ICON_SIZE, (0, 0, 0, 0))
    out.alpha_composite(small, ((w - small.width) // 2, h - small.height))
    return out


def piece_from(art, body=None):
    """Pedina: stendardo, aste e ombra chiave del FORTRESS originale con il dipinto al posto delle mura. `body` = (x0, x1)
    della fortezza nel dipinto, senza l'ombra a terra: la misura e il centro si prendono da li' (default: tutto il dipinto).
    La tela si allarga quanto serve, cosi' l'ombra a terra non resta mozzata."""
    orig = Image.open(os.path.join(EXPORT, "FORTRESS.Buf.png")).convert("RGBA")
    x0, top, x1, y1, plain = body_box(orig)
    a = np.asarray(orig).copy()
    body_mask = np.zeros(plain.shape, bool)
    body_mask[top:] = plain[top:]
    a[body_mask, 3] = 0                  # via le mura originali: restano stendardo, aste e ombra (pixel chiave)
    banner = Image.fromarray(a, "RGBA")
    bx0, bx1 = body if body else (0, art.width)
    w = round((x1 - x0) * GROW)
    k = w / max(1, bx1 - bx0)
    scaled = unkey(art.resize((max(1, round(art.width * k)), max(1, round(art.height * k))), Image.LANCZOS))
    foot = min(banner.height, y1 + 2)
    # coordinate della tela dello stendardo: centro delle mura originali = centro della fortezza dipinta
    ax = (x0 + x1) // 2 - round((bx0 + bx1) / 2 * k)
    ay = foot - scaled.height
    # tela simmetrica attorno allo stendardo: la pedina resta centrata sulla provincia come il FORTRESS originale
    side = max(0, -ax, ax + scaled.width - banner.width)
    left, right = -side, banner.width + side
    up = min(0, ay)
    canvas = Image.new("RGBA", (right - left, banner.height - up), (0, 0, 0, 0))
    canvas.alpha_composite(banner, (-left, -up))
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.alpha_composite(scaled, (ax - left, ay - up))
    canvas.alpha_composite(layer)
    return orig, canvas


STONE = 0.74           # 25/11: Federico vuole la fortezza piu' grigia; 1.0 = bianco del dipinto


def stone_grey(img, factor=STONE):
    """Pietra grigia al posto del bianco: i pixel poco saturi scendono di luminosita' (con una punta fredda), sfumando verso
    i colori (oro delle guglie, prati); i colori chiave della pedina (rosso, magenta, ciano) restano puri."""
    if factor >= 1.0:
        return img
    a = np.asarray(img.convert("RGBA")).astype(float)
    rgb = a[..., :3]
    hi, lo = rgb.max(-1), rgb.min(-1)
    sat = (hi - lo) / np.maximum(hi, 1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    keys = (((r >= hi * 0.7) & (g <= hi * 0.33) & (b <= hi * 0.33) & (hi >= 64))
            | ((r >= hi * 0.7) & (b >= hi * 0.7) & (g <= hi * 0.33)) | ((g >= hi * 0.7) & (b >= hi * 0.7) & (r <= hi * 0.33)))
    w = np.clip((0.22 - sat) / 0.12, 0, 1) * ((sat < 0.22) & ~keys & (a[..., 3] > 0))
    lum = rgb.mean(-1, keepdims=True)
    target = lum * factor * np.array([0.97, 0.99, 1.03]) + (rgb - lum) * 0.4
    a[..., :3] = (rgb * (1 - w[..., None]) + target * w[..., None]).clip(0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


## Fortezza di Atlantide grigia (AC_ATLANTIDE, 25/11 sera, Federico: «le ombre sono un po' troppo scure ... l'ombra a terra dal
## lato destro e' mozzata»): ombre della fortezza schiarite e ombra a terra resa semitrasparente, sfumata prima del bordo del
## dipinto (che la tagliava).
LIFT = 0.75            # quanto si schiariscono le ombre della fortezza (0 = come nel dipinto)
LIFT_TOP = 150         # luminosita' oltre la quale non si tocca nulla
GROUND = 0.85          # forza dell'ombra a terra (1.0 = come nel dipinto)
FADE = 70              # pixel del dipinto prima del bordo in cui l'ombra a terra sfuma a zero
SHADOW_RGB = np.array([14.0, 16.0, 22.0])


def lift_shadows(rgb):
    """Schiarisce i toni scuri senza toccare i chiari: luminosita' + LIFT * T * (l/T)^0.6 * (1-l/T)^1.6, colore invariato."""
    lum = rgb.mean(-1)
    t = np.clip(lum / LIFT_TOP, 0, 1)
    new = lum + LIFT * LIFT_TOP * t ** 0.6 * (1 - t) ** 1.6
    return np.clip(rgb * (new / np.maximum(lum, 1))[..., None], 0, 255)


def atlantide(path):
    """Dipinto scontornato della fortezza di Atlantide con ombre schiarite e ombra a terra morbida. Torna (immagine, (x0, x1)
    della fortezza senza l'ombra a terra)."""
    from scipy import ndimage
    import prepara_edifici as pe
    a = np.asarray(Image.open(path).convert("RGB")).astype(float)
    hgt, wid = a.shape[:2]
    bg = np.median(np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]]), axis=0)
    near = np.abs(a - bg).max(-1) <= pe.TOL
    lab, _ = ndimage.label(near)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    back = np.isin(lab, edge[edge > 0])
    # ombra a terra: zone lisce del colore del fondo ma piu' scure, attaccate al fondo
    ratio = a / bg
    k = ratio.mean(-1)
    dev = np.abs(ratio - k[..., None]).max(-1)
    lum = a.mean(-1)
    sd = np.sqrt(np.maximum(ndimage.uniform_filter(lum ** 2, 5) - ndimage.uniform_filter(lum, 5) ** 2, 0))
    flat = (k < 0.985) & (k > 0.2) & (dev < 0.05) & ~back
    seed_lab, _ = ndimage.label(flat & (sd < 3))
    touch = np.unique(seed_lab[ndimage.binary_dilation(back, np.ones((9, 9))) & (seed_lab > 0)])
    sizes = ndimage.sum(seed_lab > 0, seed_lab, touch)
    seed = np.isin(seed_lab, touch[sizes > 500])
    ground = np.zeros_like(seed)
    if seed.any():
        ys, xs = np.nonzero(seed)
        box = np.zeros_like(seed)
        box[max(0, ys.min() - 25):ys.max() + 26, max(0, xs.min() - 25):xs.max() + 26] = True
        ground = ndimage.binary_dilation(seed, iterations=25, mask=flat & (sd < 8) & box)
        # il bordo della penombra (gradiente forte, quindi non liscio) resta all'ombra, non alla fortezza
        ground = ndimage.binary_dilation(ground, iterations=4, mask=(dev < 0.06) & (k < 0.995) & ~back)
    soft = ndimage.binary_dilation(ground, iterations=12) & (back | ground)
    # fortezza: come prepara_edifici.cut_grey, senza l'ombra a terra
    solid = ndimage.binary_closing(~near & ~ground, structure=np.ones((pe.SEAL, pe.SEAL)), border_value=0)
    lab, _ = ndimage.label(~solid)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    fg = ~np.isin(lab, edge[edge > 0]) & ~ground
    fl, fn = ndimage.label(fg)
    if fn > 1:
        sizes = ndimage.sum(fg, fl, range(1, fn + 1))
        fg = np.isin(fl, np.nonzero(sizes >= sizes.max() * pe.BASE_KEEP)[0] + 1)
    mb = Image.fromarray((fg * 255).astype(np.uint8), "L").filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    mb = np.asarray(mb).astype(float) / 255
    # ombra a terra semitrasparente: sul fondo ridà il grigio del dipinto (piu' chiaro di GROUND), sfumata verso il bordo
    bgl, sl = bg.mean(), SHADOW_RGB.mean()
    alpha_s = np.clip((1 - k) * bgl / (bgl - sl), 0, 1) * soft * GROUND
    alpha_s[alpha_s < 0.02] = 0
    fade = np.clip((wid - 1 - np.arange(wid)) / FADE, 0, 1) ** 1.3
    alpha_s *= fade[None, :]
    alpha_s = ndimage.gaussian_filter(alpha_s, 1.5)
    rgb = lift_shadows(a)
    out_a = mb + alpha_s * (1 - mb)
    out_rgb = (rgb * mb[..., None] + SHADOW_RGB * (alpha_s * (1 - mb))[..., None]) / np.maximum(out_a, 1e-6)[..., None]
    out = np.dstack([out_rgb, out_a * 255]).clip(0, 255).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    bbox = Image.fromarray(out[..., 3]).point(lambda v: 255 if v > 6 else 0).getbbox()
    img = img.crop(bbox)
    xs = np.nonzero((mb > 0.1).any(axis=0))[0]
    return img, (int(xs.min()) - bbox[0], int(xs.max()) + 1 - bbox[0])


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    sheet = None
    out_root = os.path.join(HERE, "..", "assets")
    if "--foglio" in args:
        i = args.index("--foglio"); sheet = args[i + 1]; del args[i:i + 2]
    if "--uscita" in args:
        i = args.index("--uscita"); out_root = args[i + 1]; del args[i:i + 2]
    art = cut_grey(args[0], BASE_KEEP)
    icon = stone_grey(icon_from(art))
    orig, piece = piece_from(art)
    piece = stone_grey(piece)
    for sub, img in (("review_panel/buildings", icon), ("pieces/buildings", piece)):
        d = os.path.join(out_root, "rifatti", "campmap", sub, "fortezza_auror.png")
        os.makedirs(os.path.dirname(d), exist_ok=True)
        img.save(d, optimize=True)
        print(os.path.normpath(d), img.size)
    if sheet:
        w = icon.width + orig.width + piece.width + 40
        h = max(icon.height, piece.height)
        sh = Image.new("RGBA", (w, h), (178, 160, 120, 255))
        sh.alpha_composite(icon, (0, h - icon.height))
        sh.alpha_composite(orig, (icon.width + 20, h - orig.height))
        sh.alpha_composite(piece, (icon.width + orig.width + 40, h - piece.height))
        sh.convert("RGB").save(sheet)


if __name__ == "__main__":
    main()
