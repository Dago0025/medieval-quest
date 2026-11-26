"""Carte e schede delle unita' esclusive degli Auror (ADR-074) dalle immagini approvate di AI Playground.

Uso:  python tools/prepara_unita_auror.py <cartella media di AI Playground> [--foglio <file.jpg>]

Per ogni sezione di data/unita_auror.cfg prende `immagine` (1024x1024 su grigio uniforme) e, con le stesse funzioni di
tools/prepara_unita.py (fondo e ombra tolti, figura in basso al centro), scrive:
  assets/rifatti/campmap/review_panel/units/<id>.png   carta 200x200 (4 volte la carta 50x50)
  assets/rifatti/campmap/info_pics/units/<id>.png      scheda 732x896 (figura sotto nome e dati)
Queste unita' non hanno originale: AssetLibrary.unit_card_path e unit_picture usano direttamente la versione rifatta.
"""
import configparser
import os
import sys

import tempfile

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prepara_unita as pu  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
CFG = os.path.join(HERE, "..", "data", "unita_auror.cfg")
OUT = os.path.join(HERE, "..", "assets", "rifatti", "campmap")


def sections():
    cp = configparser.ConfigParser(comment_prefixes=(";",), inline_comment_prefixes=None, strict=False)
    cp.optionxform = str
    with open(CFG, encoding="utf-8") as f:
        cp.read_file(f)
    for s in cp.sections():
        if s != "comune":
            yield s, cp[s].get("immagine", "").strip().strip('"')   # i cappellani non hanno immagine propria


def flatten_bg(src):
    """Fondi con vignettatura (piu' chiari dietro la figura): le zone grigie lisce collegate al bordo diventano grigio
    piatto prima del ritaglio, altrimenti pu.cut (che stima il fondo con un piano) ne lascia una chiazza grigia."""
    a = np.asarray(Image.open(src).convert("RGB")).astype(float)
    lum = a.mean(axis=2)
    sat = a.max(axis=2) - a.min(axis=2)
    m = ndimage.uniform_filter(lum, 7)
    std = np.sqrt(np.maximum(ndimage.uniform_filter(lum ** 2, 7) - m ** 2, 0))
    flat = (sat < 12) & (std < 3.5)
    lab, _ = ndimage.label(flat)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    bgm = np.isin(lab, edge[edge > 0])
    grey = np.median(a[bgm], axis=0)
    a[bgm] = grey
    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False).name
    Image.fromarray(a.astype(np.uint8)).save(tmp)
    return tmp


def sharpen(img, radius, percent):
    """Le immagini di ERNIE-Image (Pro 3 Image) hanno dettagli fini e morbidi: rimpicciolite a carta sembravano a
    risoluzione piu' bassa delle carte fatte col modello precedente. Una maschera di contrasto leggera dopo il
    ridimensionamento le riporta alla stessa nitidezza; l'alfa resta quello del ritaglio."""
    alpha = img.getchannel("A")
    out = img.convert("RGB").filter(ImageFilter.UnsharpMask(radius=radius, percent=percent, threshold=2)).convert("RGBA")
    out.putalpha(alpha)
    return out


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); sys.exit(2)
    sheet_path = None
    if "--foglio" in args:
        i = args.index("--foglio"); sheet_path = args[i + 1]; del args[i:i + 2]
    media = args[0]
    done = []
    for uid, name in sections():
        src = os.path.join(media, name) if name else ""
        if not name or not os.path.isfile(src):
            print("manca", uid, name); continue
        flat = flatten_bg(src)
        art = pu.cut(flat)
        os.remove(flat)
        card = sharpen(pu.card_from(art), 1.0, 120)
        for sub, img in (("review_panel/units", card), ("info_pics/units", sharpen(pu.sheet(art), 1.2, 80))):
            d = os.path.join(OUT, sub, uid.lower() + ".png")
            os.makedirs(os.path.dirname(d), exist_ok=True)
            img.save(d, optimize=True)
        done.append((uid, card))
    print("unita' preparate:", len(done))
    if sheet_path:
        sh = Image.new("RGBA", (len(done) * 208, 312), (60, 60, 60, 255))
        for k, (uid, card) in enumerate(done):
            for j, col in enumerate([(205, 185, 140, 255), (35, 28, 22, 255)]):
                tile = Image.new("RGBA", (200, 150 if j else 150), col)
                tile.alpha_composite(card.resize((150, 150), Image.LANCZOS), (25, 0))
                sh.alpha_composite(tile, (k * 208, j * 156))
        sh.convert("RGB").save(sheet_path, quality=85)


if __name__ == "__main__":
    main()
