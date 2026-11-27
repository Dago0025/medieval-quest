#!/usr/bin/env python3
"""Effetto seppia per lo sfondo del menu iniziale (richiesta di Federico del 27/11/2026: «troppo luminose le immagini,
applica un po' di effetto seppia, per avvicinarci alle vignette in gioco»).

Uso: python tools/seppia_sfondo.py <immagine> <uscita> [--forza 0.7] [--luce 0.85] [--vignetta 0.35]

- forza: quanto tono seppia sostituisce i colori (0 = originale, 1 = tutto seppia come le tavole degli eventi)
- luce: moltiplica la luminosita' (sotto 1 abbassa i bianchi bruciati del cielo)
- vignetta: scurimento dei bordi (0 = nessuno)
Il risultato e' ritagliato e scalato a 1920x1080.
"""
import argparse
from PIL import Image, ImageChops, ImageEnhance, ImageFilter, ImageOps

# rampa di toni presa dalle tavole in gioco: inchiostro bruno -> carta invecchiata
SCURO, MEDIO, CHIARO = (38, 27, 18), (142, 112, 78), (232, 218, 188)


def seppia(img, forza, luce, vignetta):
    img = img.convert("RGB")
    grigio = ImageOps.grayscale(img)
    grigio = ImageOps.autocontrast(grigio, cutoff=1)
    toni = ImageOps.colorize(grigio, black=SCURO, mid=MEDIO, white=CHIARO, midpoint=128)
    tenue = ImageEnhance.Color(img).enhance(0.45)                # colori originali spenti
    out = Image.blend(tenue, toni, forza)
    out = ImageEnhance.Brightness(out).enhance(luce)
    out = ImageEnhance.Contrast(out).enhance(1.05)
    if vignetta > 0:
        w, h = out.size
        m = Image.new("L", (w, h), 0)
        piccola = Image.radial_gradient("L").resize((w, h))       # 0 al centro, 255 ai bordi
        m = piccola.point(lambda v: int(255 - vignetta * max(0, v - 90) * 255 / 165))
        m = m.filter(ImageFilter.GaussianBlur(40))
        out = ImageChops.multiply(out, Image.merge("RGB", (m, m, m)))
    return ImageOps.fit(out, (1920, 1080), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ingresso")
    ap.add_argument("uscita")
    ap.add_argument("--forza", type=float, default=0.7)
    ap.add_argument("--luce", type=float, default=0.85)
    ap.add_argument("--vignetta", type=float, default=0.35)
    a = ap.parse_args()
    seppia(Image.open(a.ingresso), a.forza, a.luce, a.vignetta).save(a.uscita)


if __name__ == "__main__":
    main()
