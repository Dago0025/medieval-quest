"""Ritratti per cultura delle fazioni nuove (ADR-087): dalle cartelle di MTW/_ia_locale/ritratti alle serie del gioco.

Uso:  python tools/prepara_ritratti_culture.py <cartella ritratti> [--stretto]

--stretto: ritaglio dal petto in su come i ritratti gia' in gioco (prepara_rifatti.ZOOM), per i ritratti usciti con tutto il busto; le principesse no (Federico: vanno bene cosi').

Cerca in ogni sottocartella i file <CULTURA>-<RUOLO>-NN.png (codici dei documenti dei prompt del progetto MTW:
GIA-R-01, CIN-PS-03, KAN-SA-01...), li ritaglia come gli altri ritratti (prepara_rifatti.portrait, 384x568) e li salva
in assets/ritratti/<cultura>/<ruolo>/NN.png. Le cartelle di destinazione vengono svuotate prima, cosi' la serie
corrisponde sempre ai file archiviati.
"""
import os, re, sys
from prepara_rifatti import portrait

CULTURES = {"GIA": "japanese", "CIN": "chinese", "AZT": "aztec", "INC": "inca", "KAN": "kanem",
            "MIS": "mississippian", "COR": "korean", "MON": "mongol", "IND": "indian", "SEA": "southeast_asian",
            "AUR": "auror"}
ROLES = {"R": "king", "G": "general", "PR": "prince", "PS": "princess", "EM": "emissary", "SP": "spy",
         "AS": "assassin", "SA": "religious", "AM": "admiral"}
CODE = re.compile(r"^([A-Z]{3})-([A-Z]{1,2})-(\d\d)\.png$")


def main():
    args = [a for a in sys.argv[1:] if a != "--stretto"]
    stretto = "--stretto" in sys.argv[1:]
    if len(args) != 1:
        print(__doc__)
        sys.exit(2)
    src = args[0]
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    found = {}
    for folder, _, files in os.walk(src):
        for name in files:
            m = CODE.match(name)
            if m and m.group(1) in CULTURES and m.group(2) in ROLES:
                key = (CULTURES[m.group(1)], ROLES[m.group(2)])
                found.setdefault(key, []).append((int(m.group(3)), os.path.join(folder, name)))
    for (culture, role), items in sorted(found.items()):
        dest = os.path.join(root, "assets", "ritratti", culture, role)
        os.makedirs(dest, exist_ok=True)
        for old in os.listdir(dest):
            if old.endswith(".png"):
                os.remove(os.path.join(dest, old))
        for n, path in sorted(items):
            portrait(path, zoom=stretto and role != "princess").save(os.path.join(dest, "%02d.png" % n), optimize=True)
        print("%s/%s: %d" % (culture, role, len(items)))


if __name__ == "__main__":
    main()
