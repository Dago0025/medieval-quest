"""Porta nel gioco le tavole degli eventi e le schermate di fine partita generate con AI Playground (richiesta di Federico
del 18/11/2026: niente piu' immagini del gioco originale). Prompt nei documenti del progetto claude.ai
`prompt/tavole_eventi.md` (codici T###) e `prompt/fine_partita.md` (codici F_...).

Dal 20/11/2026 le tavole fanno da sfondo alle finestre illustrate degli eventi (IllustratedModal): si generano in 16:9
(1344x768) e si tengono a 1280x720. Le scene dei nuovi avvisi (CampaignUiAlerts) sono in <media>/eventi/E_<TEMA>_NN.png
(prompt in <media>/eventi/PROMPT_EVENTI.md).

Uso:  python tools/prepara_tavole.py <cartella media di AI Playground> [--foglio anteprima.png]
Legge <media>/tavole/T###.png, <media>/eventi/E_*.png e <media>/fine_partita/F_*.png e scrive, come immagini rifatte
(ADR-043) che AssetLibrary usa al posto dell'originale:
- T###            -> assets/rifatti/campmap/epic__f###.png (1280x720, 16:9; la tavola 1 sarebbe epic.png)
- E_<TEMA>_NN     -> assets/eventi/<tema>/NN.png (1280x720, 16:9; serie propria del tema, EventArt.own_paths)
- F_FINE          -> assets/eventi/fine/01.png (1280x960 col nastro): tavola unica di fine partita per tutti (dal 20/11/2026)
- F_FN_<FAZIONE>  -> assets/rifatti/campmap/gameend/fn_<fazione>_win.png (schema precedente, 39 immagini)
- F_AUROR         -> assets/rifatti/campmap/gameend/vikings/fn_07_win.png (percorso di illustrazioni.cfg [fine])
- F_SCONFITTA_OCCIDENTE / _ORIENTE / _ISLAM -> game_end_westfactions / eastfactions / islam
Le schermate di fine partita ricevono in alto il nastro di pergamena dove il gioco scrive il titolo
(illustrazioni.cfg [fine] nastro = Rect2(212, 9, 216, 30) sull'immagine 640x480).
Poi tolgo da tools/originale_necessari.txt e da originale/ le immagini sostituite (lo fa Claude).
"""
import argparse
import os
import re

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "rifatti", "campmap")
SIZE = (640, 480)          # fine partita (4:3, col nastro del titolo)
WIDE = (1280, 720)
BIG = (1280, 960)          # tavola unica di fine partita         # tavole e scene degli avvisi (16:9, sfondo delle finestre)
EVENTS = os.path.join(ROOT, "assets", "eventi")
RIBBON = (212, 9, 216, 30)
DEFEAT = {"OCCIDENTE": "game_end_westfactions", "ORIENTE": "game_end_eastfactions", "ISLAM": "game_end_islam"}


BORDER_MAX = 50            # bordo piu' largo di cosi' (sull'immagine generata, 1376x768) = non e' il bordo ma il disegno


def _side_border(prof, limit):
    """Pixel da togliere su un lato: margine chiaro di carta, poi il filetto scuro della cornice disegnata (piu' 3 di
    sicurezza). None se il lato non ha questo bordo."""
    base = float(np.median(prof[:3]))
    if base < 150:
        return None
    for k in range(2, limit):
        if prof[k] < base - 45:
            j = k
            while j < k + 14 and prof[j] < base - 45:
                j += 1
            return j + 3
    return None


def trim_border(im):
    """Toglie il bordo di carta col filetto che Flux disegna intorno alle tavole (richiesta di Federico del 20/11/2026:
    «togliere quel bordo intorno alle tavole, per farle aderire alle cornici»). Un lato senza bordo riconoscibile (o con
    una misura fuori scala) prende la mediana degli altri; con meno di due lati riconosciuti l'immagine resta intera."""
    g = np.asarray(im.convert("L"), dtype=np.float32)
    h, w = g.shape
    ys, xs = slice(h // 5, 4 * h // 5), slice(w // 5, 4 * w // 5)
    lx, ly = int(w * 0.06), int(h * 0.08)
    sides = [_side_border(g[ys, :lx + 20].mean(axis=0), lx),
             _side_border(g[ys, ::-1][:, :lx + 20].mean(axis=0), lx),
             _side_border(g[:ly + 20, xs].mean(axis=1), ly),
             _side_border(g[::-1, xs][:ly + 20].mean(axis=1), ly)]
    valid = [v for v in sides if v is not None and v <= BORDER_MAX]
    if len(valid) < 2:
        return im
    fill = int(np.median(valid))
    left, right, top, bottom = [v if v is not None and v <= BORDER_MAX else fill for v in sides]
    return im.crop((left, top, w - right, h - bottom))


def fit(path, size=SIZE):
    """Senza il bordo disegnato, ritaglio centrale alla proporzione di `size` e riduzione a quella misura."""
    im = trim_border(Image.open(path).convert("RGB"))
    w, h = im.size
    target = size[0] / size[1]
    if w / h > target:
        nw = int(h * target)
        im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    elif w / h < target:
        nh = int(w / target)
        im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    return im.resize(size, Image.LANCZOS)


def ribbon(im):
    """Nastro di pergamena con le code a coda di rondine, ombra morbida, dove il gioco scrive il titolo. Le misure di RIBBON
    sono sull'immagine 640x480: per immagini piu' grandi (4:3) si scala il disegno."""
    x, y, w, h = RIBBON
    size = im.size
    s = 4 * size[0] / SIZE[0]
    layer = Image.new("RGBA", (int(SIZE[0] * s), int(SIZE[1] * s)), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    tail = 22
    body = [(x * s, y * s), ((x + w) * s, y * s), ((x + w) * s, (y + h) * s), (x * s, (y + h) * s)]
    left = [((x - tail) * s, (y + 4) * s), ((x + 6) * s, (y + 4) * s), ((x + 6) * s, (y + h + 4) * s),
            ((x - tail) * s, (y + h + 4) * s), ((x - tail + 9) * s, (y + h / 2 + 4) * s)]
    right = [((x + w + tail) * s, (y + 4) * s), ((x + w - 6) * s, (y + 4) * s), ((x + w - 6) * s, (y + h + 4) * s),
             ((x + w + tail) * s, (y + h + 4) * s), ((x + w + tail - 9) * s, (y + h / 2 + 4) * s)]
    for poly, col in ((left, (176, 146, 96, 255)), (right, (176, 146, 96, 255)), (body, (226, 204, 156, 255))):
        d.polygon(poly, fill=col, outline=(92, 62, 30, 255), width=int(2 * s))
    layer = layer.resize(size, Image.LANCZOS)
    k = size[0] / SIZE[0]
    shadow = layer.split()[3].filter(ImageFilter.GaussianBlur(3 * k))
    base = im.convert("RGBA")
    sh = Image.new("RGBA", size, (0, 0, 0, 0))
    sh.putalpha(shadow.point(lambda v: int(v * 0.5)))
    base.alpha_composite(sh, (int(2 * k), int(3 * k)))
    base.alpha_composite(layer)
    return base.convert("RGB")


def fit_box(im, box):
    """Miniatura per il foglio di anteprima, senza deformare."""
    c = im.copy()
    c.thumbnail(box)
    return c


def destination(code):
    m = re.fullmatch(r"T(\d{1,3})", code)
    if m:
        n = int(m.group(1))
        return os.path.join(OUT, "epic.png" if n == 1 else "epic__f%02d.png" % n), False
    m = re.fullmatch(r"E_([A-Z_]+?)_(\d{1,2})", code)
    if m:
        return os.path.join(EVENTS, m.group(1).lower(), "%02d.png" % int(m.group(2))), False
    if code == "F_FINE":
        return os.path.join(EVENTS, "fine", "01.png"), True
    if code == "F_AUROR":
        return os.path.join(OUT, "gameend", "vikings", "fn_07_win.png"), True
    m = re.fullmatch(r"F_SCONFITTA_(\w+)", code)
    if m and m.group(1) in DEFEAT:
        return os.path.join(OUT, "gameend", DEFEAT[m.group(1)] + ".png"), True
    m = re.fullmatch(r"F_(FN_\w+)", code)
    if m:
        return os.path.join(OUT, "gameend", m.group(1).lower() + "_win.png"), True
    return "", False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("media")
    ap.add_argument("--foglio", default="")
    args = ap.parse_args()
    done = []
    for folder in ("tavole", "eventi", "fine_partita"):
        src = os.path.join(args.media, folder)
        if not os.path.isdir(src):
            continue
        for f in sorted(os.listdir(src)):
            code, ext = os.path.splitext(f)
            if ext.lower() not in (".png", ".jpg", ".jpeg", ".webp"):
                continue
            dst, needs_ribbon = destination(code.upper())
            if not dst:
                print("codice sconosciuto, salto:", f)
                continue
            im = fit(os.path.join(src, f), (BIG if code.upper() == "F_FINE" else SIZE) if needs_ribbon else WIDE)
            if needs_ribbon:
                im = ribbon(im)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            im.save(dst)
            done.append(im)
            print(code.upper(), "->", os.path.relpath(dst, ROOT))
    if args.foglio and done:
        cols = 6
        sheet = Image.new("RGB", (cols * 330, ((len(done) + cols - 1) // cols) * 250), (40, 30, 20))
        for i, im in enumerate(done):
            sheet.paste(fit_box(im, (320, 240)), ((i % cols) * 330 + 5, (i // cols) * 250 + 5))
        sheet.save(args.foglio)
    print("Fatto:", len(done), "immagini.")


if __name__ == "__main__":
    main()
