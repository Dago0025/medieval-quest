"""Serie di ritratti nuovi che prende il posto di una cartella di ritratti dell'originale (ADR-044).

Uso:  python tools/prepara_serie_ritratti.py <religione> <ruolo> <immagine n. 1> [<immagine n. 2> ...] [--da N]

- religione: catholic, orthodox, muslim, pagan (come le cartelle di campmap/Portraits);
- ruolo: king, prince, princess, general;
- le immagini (verticali, senza cornice, per esempio i file di AI Playground) vanno date nell'ordine dei prompt:
  la prima diventa il numero N (--da, 1 se assente), la seconda N+1 e cosi' via.

Ogni immagine e' ritagliata e ridotta come i ritratti rifatti (384x568, la parte alta resta intera, vedi
prepara_rifatti.portrait) e salvata in assets/ritratti/<religione>/<ruolo>/<NN>.png. Quando la cartella ha almeno un
ritratto, PortraitArt sorteggia i personaggi di quella religione e di quel ruolo solo tra questi; per tornare ai
ritratti dell'installazione basta svuotarla.
"""
import os
import sys

from prepara_rifatti import portrait

RELIGIONS = ("catholic", "orthodox", "muslim", "pagan")
ROLES = ("king", "prince", "princess", "general", "pope", "admiral", "emissary", "spy", "assassin", "bishop", "cardinal",
         "priest", "inquisitor", "grand_inquisitor", "mullah", "ulama", "shaman")


def main():
    args = sys.argv[1:]
    start = 1
    if "--da" in args:
        i = args.index("--da")
        start = int(args[i + 1])
        del args[i:i + 2]
    if len(args) < 3 or args[0].lower() not in RELIGIONS or args[1].lower() not in ROLES:
        print(__doc__)
        sys.exit(2)
    religion, role, sources = args[0].lower(), args[1].lower(), args[2:]
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    folder = os.path.join(root, "assets", "ritratti", religion, role)
    os.makedirs(folder, exist_ok=True)
    for n, source in enumerate(sources, start):
        img = portrait(source)
        dest = os.path.join(folder, "%02d.png" % n)
        img.save(dest, optimize=True)
        print(os.path.relpath(dest, root), img.size, "<-", os.path.basename(source))


if __name__ == "__main__":
    main()
