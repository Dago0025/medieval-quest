"""Texture di base della veste nuova (ADR-027), generate a calcolo e ripetibili senza giunte.

Uso:  python tools/genera_texture_base.py            (scrive assets/ui/veste/legno.png e pergamena.png)

Il rumore e' filtrato nel dominio delle frequenze, quindi ogni immagine combacia con se stessa su tutti i lati.
Sono un punto di partenza: `tools/prepara_texture.py` le sostituisce con immagini dipinte (IA locale o altro).
"""
import os
import sys

import numpy as np
from PIL import Image

SIZE = 256


def noise(rng, sx, sy):
    """Rumore periodico: sx, sy = lunghezza delle macchie in pixel lungo x e y."""
    white = rng.standard_normal((SIZE, SIZE))
    fy = np.fft.fftfreq(SIZE)[:, None]
    fx = np.fft.fftfreq(SIZE)[None, :]
    kernel = np.exp(-0.5 * ((fx * sx * 2 * np.pi) ** 2 + (fy * sy * 2 * np.pi) ** 2))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * kernel))
    out -= out.min()
    return out / out.max()


def ramp(values, stops):
    """Mappa valori 0-1 su una scala di colori [(posizione, (r, g, b)), ...]."""
    pos = np.array([s[0] for s in stops])
    cols = np.array([s[1] for s in stops], dtype=float)
    return np.stack([np.interp(values, pos, cols[:, k]) for k in range(3)], axis=-1)


def wood(seed=7):
    rng = np.random.default_rng(seed)
    long_grain = noise(rng, 60.0, 1.6)      # venature lunghe e sottili
    fine_grain = noise(rng, 18.0, 0.6)      # pori
    waves = noise(rng, 40.0, 14.0)          # chiazze larghe
    v = 0.55 * long_grain + 0.25 * fine_grain + 0.20 * waves
    v = (v - v.min()) / (v.max() - v.min())
    rgb = ramp(v, [(0.0, (30, 19, 11)), (0.35, (58, 38, 22)), (0.7, (86, 58, 34)), (1.0, (112, 78, 46))])
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")


def parchment(seed=11):
    rng = np.random.default_rng(seed)
    blotches = noise(rng, 34.0, 34.0)
    mottling = noise(rng, 6.0, 6.0)
    fibres = noise(rng, 14.0, 0.8)
    v = 0.55 * blotches + 0.25 * mottling + 0.20 * fibres
    v = (v - v.min()) / (v.max() - v.min())
    rgb = ramp(v, [(0.0, (214, 196, 156)), (0.5, (236, 224, 194)), (1.0, (247, 239, 218))])
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")


def main():
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui", "veste")
    os.makedirs(out, exist_ok=True)
    wood().save(os.path.join(out, "legno.png"))
    parchment().save(os.path.join(out, "pergamena.png"))
    print("scritte legno.png e pergamena.png in", os.path.normpath(out))


if __name__ == "__main__":
    sys.exit(main())
