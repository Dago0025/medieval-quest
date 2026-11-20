"""Cornice a nove parti dei pannelli della veste nuova (ADR-027/028): legno, filo d'ottone e pergamena, angoli stondati.

Uso:  python tools/genera_pannello.py     (legge assets/ui/veste/legno.png e pergamena.png, scrive pannello.png)

L'immagine e' MARGIN + 256 + MARGIN pixel per lato. La cornice visibile e' spessa FRAME pixel; tra FRAME e MARGIN c'e'
gia' pergamena, cosi' l'angolo interno stondato sta tutto nel pezzo d'angolo e il centro e' una piastrella intera: la
pergamena e' campionata in modo periodico su tutta l'immagine e i bordi di legno sono strisce rese ripetibili sul loro
asse, quindi `StyleBoxTexture` ripete centro e bordi senza giunte a ogni misura. Le forme sono disegnate a 4x e ridotte
(bordi morbidi). Va rilanciato dopo aver cambiato legno.png o pergamena.png.
"""
import os

import numpy as np
from PIL import Image, ImageDraw

MARGIN = 16      # margine della texture per StyleBoxTexture (UiTheme.FRAME_EDGE)
FRAME = 12       # spessore visibile della cornice
TILE = 256
SS = 4           # sovracampionamento delle forme
PAPER_FLAT = np.array([239.0, 228.0, 200.0])
OUTLINE = np.array([18.0, 11.0, 6.0])
BRASS = np.array([201.0, 162.0, 74.0])
BRASS_LIGHT = np.array([236.0, 206.0, 122.0])
BRASS_DARK = np.array([122.0, 92.0, 34.0])


def blend_axis(a, axis):
    """Rende ripetibile la striscia lungo `axis` (0 = verticale, 1 = orizzontale)."""
    n = a.shape[axis]
    shifted = np.roll(a, n // 2, axis=axis)
    t = np.abs(np.linspace(-1.0, 1.0, n, endpoint=False))
    w = np.clip((t - 0.5) / 0.4, 0.0, 1.0) ** 2
    w = w[None, :, None] if axis == 1 else w[:, None, None]
    return a * (1.0 - w) + shifted * w


def rounded(size, inset, radius):
    """Maschera 0-1 di un rettangolo stondato rientrato di `inset`, con i bordi morbidi."""
    big = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(big)
    d.rounded_rectangle([inset * SS, inset * SS, (size - inset) * SS - 1, (size - inset) * SS - 1], radius * SS, fill=255)
    return np.asarray(big.resize((size, size), Image.LANCZOS), dtype=float)[..., None] / 255.0


def disc(size, cx, cy, r):
    big = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(big).ellipse([(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS], fill=255)
    return np.asarray(big.resize((size, size), Image.LANCZOS), dtype=float)[..., None] / 255.0


def main():
    here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui", "veste")
    wood = np.asarray(Image.open(os.path.join(here, "legno.png")).convert("RGB"), dtype=float) * 0.72
    paper = np.asarray(Image.open(os.path.join(here, "pergamena.png")).convert("RGB").resize((TILE, TILE), Image.LANCZOS), dtype=float)
    paper = 0.5 * paper + 0.5 * PAPER_FLAT          # grana attenuata: il testo deve restare il protagonista
    size = TILE + 2 * MARGIN
    idx = (np.arange(size) - MARGIN) % TILE
    img = paper[np.ix_(idx, idx)]                    # pergamena periodica su tutta l'immagine
    horizontal = blend_axis(wood[40:40 + FRAME, :TILE], 1)[:, idx]
    vertical = blend_axis(np.rot90(wood[90:90 + FRAME, :TILE]), 0)[idx, :]
    frame = np.zeros_like(img)
    frame[:, :FRAME] = vertical
    frame[:, size - FRAME:] = vertical[:, ::-1]
    frame[:FRAME, :] = horizontal
    frame[size - FRAME:, :] = horizontal[::-1]

    def over(base, color, mask):
        return base * (1.0 - mask) + color * mask

    out = np.broadcast_to(OUTLINE, img.shape).copy()                 # contorno scuro
    out = over(out, frame, rounded(size, 1, 8))                      # legno
    out = over(out, OUTLINE, rounded(size, FRAME - 4, 6))
    out = over(out, BRASS_LIGHT, rounded(size, FRAME - 3, 5.5))      # filo d'ottone: luce, corpo
    out = over(out, BRASS, rounded(size, FRAME - 2.2, 5))
    out = over(out, BRASS_DARK, rounded(size, FRAME - 1, 4.5))
    out = over(out, img, rounded(size, FRAME, 4))                    # pergamena, angolo interno stondato
    for cx, cy in [(5.5, 5.5), (size - 5.5, 5.5), (5.5, size - 5.5), (size - 5.5, size - 5.5)]:
        out = over(out, OUTLINE, disc(size, cx, cy, 2.6))            # borchie agli angoli
        out = over(out, BRASS, disc(size, cx, cy, 1.9))
        out = over(out, BRASS_LIGHT, disc(size, cx - 0.5, cy - 0.5, 0.7))
    alpha = rounded(size, 0, 9)
    rgba = np.concatenate([np.clip(out, 0, 255), alpha * 255.0], axis=-1).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(os.path.join(here, "pannello.png"))
    print("scritta", os.path.normpath(os.path.join(here, "pannello.png")), (size, size))


if __name__ == "__main__":
    main()
