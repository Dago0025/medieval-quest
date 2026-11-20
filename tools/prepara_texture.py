"""Trasforma un'immagine dipinta (IA locale, Gemini, foto) in una texture ripetibile della veste nuova (ADR-027).

Uso:  python tools/prepara_texture.py <immagine> legno|pergamena [--larghezza 256] [--altezza 256] [--asse xy|x]
                                         [--zona x0,y0,x1,y1]

Ritaglia dal centro (o dalla zona indicata in frazioni 0-1) un rettangolo delle proporzioni chieste, lo porta alla misura
e sfuma i bordi con la copia traslata di mezzo lato, cosi' l'immagine combacia con se stessa. Con `--asse x` la rende
ripetibile solo in orizzontale: e' il caso delle assi di legno della barra, che e' piu' bassa della texture e non la
ripete mai in verticale (le fughe tra le assi restano nette). Scrive assets/ui/veste/<nome>.png, che
`OriginalHud` carica al posto delle tinte piatte. Va bene per materiali uniformi (legno, pergamena, pietra); cornici e
pulsanti con un disegno vanno ritagliati a nove parti, non resi ripetibili.
"""
import argparse
import os

import numpy as np
from PIL import Image


def seamless(img, axis="xy"):
    a = np.asarray(img, dtype=float)
    h, w_px = a.shape[0], a.shape[1]
    tx = np.abs(np.linspace(-1.0, 1.0, w_px, endpoint=False))[None, :]
    ty = np.abs(np.linspace(-1.0, 1.0, h, endpoint=False))[:, None]
    if axis == "x":
        shifted = np.roll(a, w_px // 2, axis=1)
        edge = np.broadcast_to(tx, (h, w_px))
    else:
        shifted = np.roll(a, (h // 2, w_px // 2), axis=(0, 1))
        edge = np.maximum(ty, tx)                        # 0 al centro, 1 sui bordi
    w = np.clip((edge - 0.5) / 0.4, 0.0, 1.0) ** 2       # vicino ai bordi vince la copia traslata (continua li')
    out = a * (1.0 - w[..., None]) + shifted * w[..., None]
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("immagine")
    p.add_argument("nome", choices=["legno", "pergamena"])
    p.add_argument("--larghezza", type=int, default=256)
    p.add_argument("--altezza", type=int, default=256)
    p.add_argument("--asse", choices=["xy", "x"], default="xy")
    p.add_argument("--zona", default="")
    args = p.parse_args()
    img = Image.open(args.immagine).convert("RGB")
    w, h = img.size
    if args.zona:
        x0, y0, x1, y1 = [float(v) for v in args.zona.split(",")]
        img = img.crop((int(x0 * w), int(y0 * h), int(x1 * w), int(y1 * h)))
        w, h = img.size
    ratio = args.larghezza / args.altezza
    cw, ch = (w, int(w / ratio)) if w / h <= ratio else (int(h * ratio), h)
    img = img.crop(((w - cw) // 2, (h - ch) // 2, (w - cw) // 2 + cw, (h - ch) // 2 + ch))
    img = img.resize((args.larghezza, args.altezza), Image.LANCZOS)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui", "veste", args.nome + ".png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    seamless(img, args.asse).save(out)
    print("scritta", os.path.normpath(out))


if __name__ == "__main__":
    main()
