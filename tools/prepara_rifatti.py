"""Immagini dell'originale rifatte con l'IA locale: ritratti, icone degli edifici, illustrazioni delle unita'.

Uso:  python tools/prepara_rifatti.py <tipo> <immagine generata> <percorso originale> [<percorso originale> ...]

Tipi:
- ritratto   l'immagine (verticale, senza cornice) ritagliata al rapporto dei ritratti dell'originale (96x142, la parte
             alta resta intera) e ridotta a 384x568; la cornice la disegna il gioco (UiTheme.portrait);
- edificio   l'edificio su fondo nero scontornato e posato su 272x200 trasparente (4 volte l'icona 68x50);
- unita      la figura su fondo nero scontornata e posata in basso su 732x896 trasparente (2 volte la scheda 366x448),
             sotto il nastro del nome; la pergamena di fondo la mette il gioco;
- carta      la miniatura dell'unita' negli eserciti, nella barra e nelle finestre di arruolamento: figura scontornata,
             posata in basso su 200x200 trasparente (4 volte la carta 50x50 di campmap/review_panel/Units).

Ogni percorso originale (come nel manifesto dell'esportazione, per esempio campmap/Portraits/Catholic/King/king58.tga)
riceve la sua copia in assets/rifatti/<percorso in minuscolo, estensione .png>: AssetLibrary.texture la usa al posto
dell'immagine dell'installazione (ADR-043). Per togliere una sostituzione basta cancellare il file.
"""
import os
import sys

from PIL import Image

from prepara_medaglioni import cut_out

PORTRAIT = (384, 568)
BUILDING = (272, 200)
UNIT = (732, 896)
CARD = (200, 200)
UNIT_TOP = 0.31            # sotto il nastro del nome e i dati della scheda (fino a ~130 su 448), come la figura dell'originale
BLACK = 12                 # fondo: solo il nero vero (le ombre scure della figura restano)
SEAL = 15
UNIT_BOTTOM = 0.985


## Ritaglio stretto «dal petto in su» come i ritratti gia' in gioco (Federico 27/11/2026: le prove Auror con ERNIE mostravano tutto
## il busto): si tiene la parte alta e centrale, larga ZOOM della larghezza, partendo da ZOOM_TOP dell'altezza.
ZOOM = 0.76
ZOOM_TOP = 0.03


def portrait(path, zoom=False):
    img = Image.open(path).convert("RGB")
    ratio = PORTRAIT[0] / PORTRAIT[1]
    w, h = img.size
    if zoom:
        nw = round(w * ZOOM)
        nh = min(round(nw / ratio), h - round(h * ZOOM_TOP))
        x, y = (w - nw) // 2, round(h * ZOOM_TOP)
        img = img.crop((x, y, x + nw, y + nh))
        w, h = img.size
    if w / h > ratio:                                   # troppo larga: si tagliano i lati
        nw = round(h * ratio)
        img = img.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:                                               # troppo alta: si taglia in basso, la testa resta
        img = img.crop((0, 0, w, round(w / ratio)))
    return img.resize(PORTRAIT, Image.LANCZOS)


def fit(symbol, box):
    k = min(box[0] / symbol.width, box[1] / symbol.height)
    return symbol.resize((max(1, round(symbol.width * k)), max(1, round(symbol.height * k))), Image.LANCZOS)


def building(path):
    art = fit(cut_out(path, black=BLACK, seal=SEAL), (BUILDING[0] - 8, BUILDING[1] - 6))
    out = Image.new("RGBA", BUILDING, (0, 0, 0, 0))
    out.paste(art, ((BUILDING[0] - art.width) // 2, (BUILDING[1] - art.height) // 2))
    return out


def unit(path):
    top, bottom = round(UNIT[1] * UNIT_TOP), round(UNIT[1] * UNIT_BOTTOM)
    art = fit(cut_out(path, black=BLACK, seal=SEAL), (round(UNIT[0] * 0.92), bottom - top))
    out = Image.new("RGBA", UNIT, (0, 0, 0, 0))
    out.paste(art, ((UNIT[0] - art.width) // 2, bottom - art.height))
    return out


def card(path):
    art = fit(cut_out(path, black=BLACK, seal=SEAL), (CARD[0] - 4, CARD[1] - 2))
    out = Image.new("RGBA", CARD, (0, 0, 0, 0))
    out.paste(art, ((CARD[0] - art.width) // 2, CARD[1] - 1 - art.height))
    return out


def target(original):
    key = original.replace("\\", "/").lower()
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "..", "assets", "rifatti", os.path.splitext(key)[0] + ".png")


def main():
    if len(sys.argv) < 4 or sys.argv[1] not in ("ritratto", "edificio", "unita", "carta"):
        print(__doc__)
        sys.exit(2)
    kind, source, originals = sys.argv[1], sys.argv[2], sys.argv[3:]
    img = {"ritratto": portrait, "edificio": building, "unita": unit, "carta": card}[kind](source)
    for original in originals:
        dest = target(original)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        img.save(dest, optimize=True)
        print(os.path.relpath(dest, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")), img.size)


if __name__ == "__main__":
    main()
