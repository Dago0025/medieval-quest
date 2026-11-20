"""Carte, freccia e pennacchi della barra (veste nuova) dalle immagini dipinte con l'IA locale.

Uso:  python tools/prepara_barra.py <cartella delle immagini> [--prova <foglio.png>]

Legge dalla cartella le immagini generate (un soggetto su fondo nero, Intel AI Playground, preset Pro Image), le
scontorna come i medaglioni (`prepara_medaglioni.cut_out`) e scrive in assets/ui/veste:
- carta_build.png, carta_trainunit.png   232x212: il disegno delle due carte ai lati dello stemma, su fondo di noce
  scuro (4 volte il riquadro 58x53 dentro la cornice d'ottone della carta), da button_build.png e button_trainunit.png;
- freccia.png                            64x208, punta in su, fondo trasparente (la freccia in giu' e' la stessa
  capovolta), da button_ipprev.png;
- pennacchio_king.png, _heir, _noble, _merc   112x248 (8 volte il 14x31 dell'originale), stendardo appeso in alto e
  centrato, fondo trasparente, da is_king_mon.png, is_heir_mon.png, is_noble_mon.png, is_merc_mon.png.
Le immagini che mancano si saltano. Con --prova salva un foglio di confronto.
"""
import argparse
import os

import numpy as np
from PIL import Image, ImageFilter

from prepara_medaglioni import HALO, cut_out

CARD = (232, 212)
ARROW = (64, 208)
PENNANT = (112, 248)
PENNANT_EDGE = 5                # contorno scuro attorno allo stendardo (punti a misura finale)
PENNANT_INK = (0x24, 0x17, 0x0d, 255)
CARD_CENTER = np.array([0x4a, 0x35, 0x22], float)
CARD_EDGE = np.array([0x17, 0x0f, 0x09], float)
# Carte: "margine" = bordo libero attorno alla scena (punti a misura finale); "ingrandimento" oltre la misura che la fa
# stare tutta, con "ancora" = lato che resta fermo (il resto esce dalla carta); "giu" sposta la scena in basso.
CARDS = {
    "build": {"sorgente": "button_build.png", "margine": 6, "ingrandimento": 1.15, "ancora": "destra", "giu": 6},
    "trainunit": {"sorgente": "button_trainunit.png", "margine": 5, "ingrandimento": 1.0, "ancora": "centro", "giu": 0},
}
# Pennacchi: si tiene il drappo con un mozzicone d'asta per lato ("asta", frazione della larghezza del drappo).
PENNANTS = {
    "king": {"sorgente": "is_king_mon.png", "asta": 0.07},
    "heir": {"sorgente": "is_heir_mon.png", "asta": 0.07},
    "noble": {"sorgente": "is_noble_mon.png", "asta": 0.07},
    "merc": {"sorgente": "is_merc_mon.png", "asta": 0.07},
}


def backdrop(size):
    """Fondo di noce scuro delle carte: piu' chiaro al centro, scuro ai bordi."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w]
    dx = (xx + 0.5 - w / 2.0) / (w / 2.0)
    dy = (yy + 0.5 - h * 0.55) / (h / 2.0)
    t = np.clip(np.sqrt(dx * dx + dy * dy) / 1.25, 0.0, 1.0)[..., None] ** 1.5
    img = CARD_CENTER * (1.0 - t) + CARD_EDGE * t
    return Image.fromarray(np.dstack([img, np.full((h, w), 255.0)]).astype(np.uint8), "RGBA")


def with_halo(art, canvas_size, pos, glow=0.5, blur=6.0):
    """Il soggetto sul foglio trasparente con un alone chiaro e un'ombra dietro."""
    layer = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    warm = Image.new("RGBA", art.size, HALO)
    warm.putalpha(art.getchannel("A").point(lambda v: int(v * glow)))
    halo = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    halo.paste(warm, pos, warm)
    layer.alpha_composite(halo.filter(ImageFilter.GaussianBlur(blur)))
    black = Image.new("RGBA", art.size, (0, 0, 0, 255))
    black.putalpha(art.getchannel("A").point(lambda v: int(v * 0.6)))
    shadow = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    shadow.paste(black, (pos[0] + 1, pos[1] + 3), black)
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur * 0.5)))
    cut = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    cut.paste(art, pos)
    layer.alpha_composite(cut)
    return layer


def card(symbol, opts):
    w, h = CARD
    m = float(opts.get("margine", 6))
    k = min((w - 2.0 * m) / symbol.width, (h - 2.0 * m) / symbol.height) * float(opts.get("ingrandimento", 1.0))
    art = symbol.resize((max(1, round(symbol.width * k)), max(1, round(symbol.height * k))), Image.LANCZOS)
    anchor = opts.get("ancora", "centro")
    if anchor == "destra":
        x = round(w - m - art.width)
    elif anchor == "sinistra":
        x = round(m)
    else:
        x = round((w - art.width) / 2.0)
    y = round((h - art.height) / 2.0 + float(opts.get("giu", 0)))
    out = backdrop(CARD)
    out.alpha_composite(with_halo(art, CARD, (x, y)))
    return out.convert("RGB")


def arrow(symbol):
    k = min(ARROW[0] / symbol.width, ARROW[1] / symbol.height)
    art = symbol.resize((max(1, round(symbol.width * k)), max(1, round(symbol.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", ARROW, (0, 0, 0, 0))
    out.paste(art, (round((ARROW[0] - art.width) / 2.0), round((ARROW[1] - art.height) / 2.0)))
    return out


def cloth_columns(alpha):
    """Il tratto di colonne piu' largo occupato nella meta' bassa: il drappo (un'asta verticale accanto resta fuori)."""
    h = alpha.shape[0]
    used = (alpha[int(h * 0.45):int(h * 0.8)] > 128).any(axis=0)
    best, start = (0, 0), None
    for x in range(len(used) + 1):
        on = x < len(used) and used[x]
        if on and start is None:
            start = x
        elif not on and start is not None:
            if x - start > best[1] - best[0]:
                best = (start, x)
            start = None
    return best


def pennant(symbol, opts):
    alpha = np.asarray(symbol.getchannel("A"))
    x0, x1 = cloth_columns(alpha)
    stub = round((x1 - x0) * float(opts.get("asta", 0.07)))
    part = symbol.crop((max(0, x0 - stub), 0, min(symbol.width, x1 + stub), symbol.height))
    part = part.crop(part.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox())
    k = min((PENNANT[0] - 2.0 * PENNANT_EDGE) / part.width, (PENNANT[1] - 2.0 * PENNANT_EDGE) / part.height)
    art = part.resize((max(1, round(part.width * k)), max(1, round(part.height * k))), Image.LANCZOS)
    pos = (round((PENNANT[0] - art.width) / 2.0), PENNANT_EDGE)    # appeso in alto
    # contorno scuro: il drappo e' bianco e sta sopra carte e pergamena chiare, senza non si staccherebbe
    grown = Image.new("L", PENNANT, 0)
    grown.paste(art.getchannel("A"), pos)
    grown = grown.filter(ImageFilter.MaxFilter(2 * PENNANT_EDGE - 1)).filter(ImageFilter.GaussianBlur(0.8))
    out = Image.new("RGBA", PENNANT, PENNANT_INK)
    out.putalpha(grown)
    cut = Image.new("RGBA", PENNANT, (0, 0, 0, 0))
    cut.paste(art, pos)
    out.alpha_composite(cut)
    return out


def proof(done, path):
    here = os.path.dirname(os.path.abspath(__file__))
    wood_path = os.path.join(here, "..", "assets", "ui", "veste", "legno.png")
    sheet = Image.new("RGBA", (900, 560), (0x2a, 0x1b, 0x10, 255))
    if os.path.exists(wood_path):
        wood = Image.open(wood_path).convert("RGBA")
        for x in range(0, sheet.width, wood.width):
            for y in range(0, sheet.height, wood.height):
                sheet.paste(wood, (x, y))
    x = 15
    for name in ("carta_build", "carta_trainunit"):
        if name in done:
            img = done[name].convert("RGBA")
            sheet.alpha_composite(img, (x, 15))
            sheet.alpha_composite(img.resize((87, 80), Image.LANCZOS), (x, 240))      # schermo alto 900
            sheet.alpha_composite(img.resize((104, 95), Image.LANCZOS), (x + 100, 240))  # schermo alto 1080
            x += 250
    if "freccia" in done:
        sheet.alpha_composite(done["freccia"], (x, 15))
        sheet.alpha_composite(done["freccia"].resize((18, 60), Image.LANCZOS), (x, 240))
        sheet.alpha_composite(done["freccia"].resize((18, 60), Image.LANCZOS).transpose(Image.FLIP_TOP_BOTTOM), (x + 30, 240))
        x += 90
    x = 15
    for name in ("pennacchio_king", "pennacchio_heir", "pennacchio_noble", "pennacchio_merc"):
        if name in done:
            sheet.alpha_composite(done[name], (x, 345))
            for j, width in enumerate((17, 20, 26)):                                   # 11 punti a scala 1,5 - 1,8 - 2,4
                small = done[name].resize((width, round(width * PENNANT[1] / PENNANT[0])), Image.LANCZOS)
                sheet.alpha_composite(small, (x + 120 + 34 * j, 345))
            x += 225
    sheet.convert("RGB").save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cartella")
    ap.add_argument("--prova")
    args = ap.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    dest = os.path.join(here, "..", "assets", "ui", "veste")
    done = {}

    def source(name):
        path = os.path.join(args.cartella, name)
        return path if os.path.exists(path) else None

    for name, opts in CARDS.items():
        path = source(opts["sorgente"])
        if path:
            done["carta_" + name] = card(cut_out(path), opts)
    path = source("button_ipprev.png")
    if path:
        done["freccia"] = arrow(cut_out(path))
    for name, opts in PENNANTS.items():
        path = source(opts["sorgente"])
        if path:
            done["pennacchio_" + name] = pennant(cut_out(path), opts)
    for name, img in done.items():
        img.save(os.path.join(dest, name + ".png"), optimize=True)
        print(name, img.size)
    if args.prova:
        proof(done, args.prova)


if __name__ == "__main__":
    main()
