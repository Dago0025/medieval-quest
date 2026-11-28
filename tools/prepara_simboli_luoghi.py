"""Medaglioni dei luoghi leggendari e simbolo della bussola della minimappa.

Legge simbolo e categoria di ogni luogo da data/luoghi/luoghi.cfg e scrive assets/luoghi/simboli/<simbolo>_<categoria>.png:
fondo per categoria (senza anello d'ottone dal 28/11/2026: ombra interna e filo scuro sull'orlo) (storico bruno, mitologico viola con alone, marino verde-azzurro) e simbolo. Il
simbolo e' quello dipinto (tools/simboli_dipinti/<simbolo>.png, richiesta di Federico del 27/11/2026) se c'e', altrimenti
quello disegnato a codice da tools/simboli_luoghi.py. Il gioco li mostra sui luoghi della mappa (SiteLayer).

Con --dipinti <cartella> importa prima le immagini generate con AI Playground (S_<simbolo>.png e S_bussola.png: un solo
oggetto al centro su fondo nero): le scontorna dal nero come tools/prepara_medaglioni.py e le salva in
tools/simboli_dipinti (fuori dal gioco, .gdignore); la bussola va in assets/ui/veste/bussola.png (solo il simbolo: ombra e alone
li disegna la barra, src/ui/original_hud.gd).

Uso: python tools/prepara_simboli_luoghi.py [--dipinti <cartella>] [--prova <foglio.jpg>] [cartella del progetto]
"""
import argparse
import glob
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from simboli_luoghi import SIMBOLI, medallion  # noqa: E402
from prepara_medaglioni import cut_out  # noqa: E402

SIZE = 88            # diametro del medaglione (il doppio della misura sullo schermo, 44 punti)
SOURCE = 384         # lato massimo del simbolo dipinto conservato
COMPASS = 128        # lato del simbolo della bussola
# Ritocchi per simbolo (come TWEAKS di prepara_medaglioni): luce, contrasto, colore, gamma; "nero" = soglia del fondo;
# "raggio" = quanto del raggio del disco occupa il simbolo (0.88 di norma senza anello, simboli_luoghi.REACH_NUDO).
TWEAKS = {
    "gorgo": {"raggio": 1.14},      # il gorgo e' gia' un tondo con un orlo d'oro: l'orlo esce dal disco e viene tagliato
    # soggetti larghi e bassi: col punto piu' lontano a 0.88 restano piccoli
    "piramidi": {"raggio": 0.98},
    "alghe": {"raggio": 0.96},
    "isola": {"raggio": 0.96},
    "monte": {"raggio": 0.96},
}


def import_painted(folder, root):
    out = os.path.join(HERE, "simboli_dipinti")
    os.makedirs(out, exist_ok=True)
    ignore = os.path.join(out, ".gdignore")
    if not os.path.exists(ignore):
        open(ignore, "w").close()
    n = 0
    for path in sorted(glob.glob(os.path.join(folder, "S_*.png"))):
        name = os.path.basename(path)[2:-4]
        tw = TWEAKS.get(name, {})
        art = cut_out(path, tw, black=int(tw.get("nero", 26)), seal=int(tw.get("chiusura", 0)))
        if name == "bussola":
            art.thumbnail((COMPASS, COMPASS), Image.LANCZOS)
            canvas = Image.new("RGBA", (COMPASS, COMPASS), (0, 0, 0, 0))
            canvas.alpha_composite(art, ((COMPASS - art.width) // 2, (COMPASS - art.height) // 2))
            canvas.save(os.path.join(root, "assets", "ui", "veste", "bussola.png"), optimize=True)
        else:
            if name not in SIMBOLI:
                print("ignorato (simbolo sconosciuto):", name)
                continue
            art.thumbnail((SOURCE, SOURCE), Image.LANCZOS)
            art.save(os.path.join(out, name + ".png"), optimize=True)
        n += 1
    print(n, "simboli dipinti importati")


def painted(sym):
    path = os.path.join(HERE, "simboli_dipinti", sym + ".png")
    return Image.open(path).convert("RGBA") if os.path.exists(path) else None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("root", nargs="?", default=os.path.join(HERE, ".."))
    ap.add_argument("--dipinti")
    ap.add_argument("--prova")
    args = ap.parse_args()
    root = args.root
    if args.dipinti:
        import_painted(args.dipinti, root)
    text = open(os.path.join(root, "data", "luoghi", "luoghi.cfg"), encoding="utf-8").read()
    used = set()
    for sec in re.split(r"\n\[", text):
        cat = re.search(r'^categoria="(\w+)"', sec, re.M)
        sym = re.search(r'^simbolo="(\w+)"', sec, re.M)
        if cat and sym:
            used.add((sym.group(1), cat.group(1)))
    out_dir = os.path.join(root, "assets", "luoghi", "simboli")
    os.makedirs(out_dir, exist_ok=True)
    done, n_painted = [], 0
    for sym, cat in sorted(used):
        if sym not in SIMBOLI:
            raise SystemExit("simbolo sconosciuto: " + sym)
        art = painted(sym)
        n_painted += art is not None
        img = medallion(sym, cat, SIZE, art=art, reach=TWEAKS.get(sym, {}).get("raggio"), anello=False)
        img.save(os.path.join(out_dir, f"{sym}_{cat}.png"))
        done.append(img)
    print(len(used), "medaglioni in", out_dir, "-", n_painted, "dipinti")
    if args.prova:
        # foglio di prova: misura piena e misure a schermo (44 e 34) su un fondo di mappa
        cols = 10
        rows = (len(done) + cols - 1) // cols
        w = done[0].width
        sheet = Image.new("RGBA", (cols * (w + 60) + 10, rows * (w + 10) + 10), (0xc8, 0xb4, 0x86, 255))
        for i, img in enumerate(done):
            x, y = 10 + (i % cols) * (w + 60), 10 + (i // cols) * (w + 10)
            sheet.alpha_composite(img, (x, y))
            k = img.width / SIZE
            for j, s in enumerate((44, 34)):
                small = img.resize((round(s * k), round(s * k)), Image.LANCZOS)
                sheet.alpha_composite(small, (x + w + 4, y + j * (round(44 * k) + 2)))
        sheet.convert("RGB").save(args.prova, quality=90)


if __name__ == "__main__":
    main()
