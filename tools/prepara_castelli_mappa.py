"""Castelli della mappa con i dipinti nuovi (ADR-061): stendardo e aste dell'originale, fortificazione dipinta.

Uso:  python tools/prepara_castelli_mappa.py <cartella conversione_icone> [--foglio <png>]

Il gioco disegna sulla plancia un castello per grado (PieceArt.CASTLE_PIECES: FORT, KEEP, CASTLE, CITADEL, FORTRESS da
campmap/pieces/buildings/*.Buf) e ne colora lo stendardo, che resta rosso puro con l'ombra magenta perche' PieceArt lo
ricolori con la fazione e lo riempia secondo la guarnigione. Qui si tiene dell'immagine originale la parte sopra le mura
(stendardo, aste, ombra) e al posto della fortificazione si posa il dipinto nuovo del livello base di ogni grado, largo come
la fortificazione originale e con il piede nello stesso punto. Le evoluzioni (cittadella con barbacane, torri dei cannoni...)
non cambiano il castello sulla mappa: resta quello del grado (richiesta di Federico). Risultato in
assets/rifatti/campmap/pieces/buildings/<nome>.png, alla stessa misura dell'originale (AssetLibrary.texture, ADR-043).
"""
import os
import sys

import numpy as np
from PIL import Image

from prepara_edifici import cut_grey, BASE_KEEP

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.environ.get("MTW_GAME_DIR", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "originale"))
EXPORT = os.path.join(GAME, "_ASSET_EXPORT", "04_Interfaccia_Campagna", "campmap", "pieces", "buildings")
OUT = os.path.join(HERE, "..", "assets", "rifatti", "campmap", "pieces", "buildings")
## grado -> (immagine dell'originale, base dipinta del livello base del grado: fort, keep, castle, citadel, fortress)
TIERS = [("FORT", "B021"), ("KEEP", "B035"), ("CASTLE", "B011"), ("CITADEL", "B014"), ("FORTRESS", "B024")]
WALL_ROW = 24          # una riga con piu' di tanti pixel opachi non chiave appartiene gia' alla fortificazione
GROW = 1.06            # il dipinto e' un poco piu' largo della fortificazione originale (il bordo del prato e' sfumato)


def is_key(px):
    r, g, b = int(px[0]), int(px[1]), int(px[2])
    red = r > 150 and g < 60 and b < 60
    magenta = r > 150 and b > 150 and g < 80
    return red or magenta


def body_box(img):
    """Ingombro della fortificazione: dalla prima riga larga sotto l'asta dello stendardo in giu', senza i pixel chiave."""
    a = np.asarray(img)
    opaque = a[..., 3] > 0
    red = (a[..., 0] > 150) & (a[..., 1] < 60) & (a[..., 2] < 60)
    magenta = (a[..., 0] > 150) & (a[..., 2] > 150) & (a[..., 1] < 80)
    plain = opaque & ~red & ~magenta
    start = int(np.nonzero(red.any(axis=1))[0][0]) + 5          # sotto l'asta orizzontale dello stendardo
    rows = np.nonzero(plain[start:].sum(axis=1) > WALL_ROW)[0]
    top = start + int(rows[0])
    ys, xs = np.nonzero(plain[top:])
    return int(xs.min()), top, int(xs.max()) + 1, top + int(ys.max()) + 1, plain


def unkey(art):
    """Il dipinto non deve avere pixel che PieceArt.key_of scambierebbe per i colori chiave (la bandierina rossa del forte
    diventerebbe lo stendardo della fazione): rossi e magenta saturi si spengono appena, quanto basta."""
    a = np.asarray(art).astype(np.float32)
    rgb = a[..., :3]
    hi = rgb.max(axis=2)
    lim = hi * 0.36
    lit = hi >= 0.2 * 255
    red = lit & (rgb[..., 0] >= hi * 0.7) & (rgb[..., 1] <= lim) & (rgb[..., 2] <= lim)
    mag = lit & (rgb[..., 0] >= hi * 0.7) & (rgb[..., 2] >= hi * 0.7) & (rgb[..., 1] <= lim)
    floor = hi * 0.4
    rgb[..., 1] = np.where(red | mag, np.maximum(rgb[..., 1], floor), rgb[..., 1])
    rgb[..., 2] = np.where(red, np.maximum(rgb[..., 2], floor), rgb[..., 2])
    a[..., :3] = rgb
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def build(name, base_png):
    orig = Image.open(os.path.join(EXPORT, name + ".Buf.png")).convert("RGBA")
    x0, top, x1, y1, plain = body_box(orig)
    a = np.asarray(orig).copy()
    # via la fortificazione originale: sotto `top` restano solo i pixel chiave (ombra magenta, coda dello stendardo)
    body = np.zeros(plain.shape, bool)
    body[top:] = plain[top:]
    a[body, 3] = 0
    out = Image.fromarray(a, "RGBA")
    art = cut_grey(base_png, BASE_KEEP)
    w = round((x1 - x0) * GROW)
    k = w / art.width
    art = unkey(art.resize((w, max(1, round(art.height * k))), Image.LANCZOS))   # dopo la riduzione: anche i bordi sfumati
    cx = (x0 + x1) // 2
    layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
    layer.alpha_composite(art, (max(0, cx - w // 2), max(0, min(out.height, y1 + 2) - art.height)))
    out.alpha_composite(layer)
    return orig, out


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    src = args[0]
    sheet_path = args[args.index("--foglio") + 1] if "--foglio" in args else None
    os.makedirs(OUT, exist_ok=True)
    pairs = []
    for name, base in TIERS:
        orig, img = build(name, os.path.join(src, "risultati", base + ".png"))
        dest = os.path.join(OUT, name.lower() + ".png")
        img.save(dest, optimize=True)
        print(os.path.relpath(dest, os.path.join(HERE, "..")), img.size)
        pairs.append((orig, img))
    if sheet_path:
        w = sum(o.width * 2 + 20 for o, _ in pairs)
        h = max(o.height for o, _ in pairs)
        sheet = Image.new("RGBA", (w, h), (178, 160, 120, 255))
        x = 0
        for o, n in pairs:
            sheet.alpha_composite(o, (x, h - o.height))
            sheet.alpha_composite(n, (x + o.width + 4, h - n.height))
            x += o.width * 2 + 20
        sheet.convert("RGB").save(sheet_path)


if __name__ == "__main__":
    main()
