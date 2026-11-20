"""Copia dall'installazione di Medieval: Total War i soli file del gioco originale che Medieval Quest usa ancora, nella
cartella `originale/` del progetto (non entra nel repository: e' contenuto del gioco originale).

Dal 18/11/2026 dati della campagna, testi, icone e pergamene sono del progetto (data/campagna, data/testi,
assets/rifatti); dall'originale restano solo la musica e i suoni elencati in data/ui/audio.cfg e le immagini elencate in
tools/originale_necessari.txt (tavole degli eventi, schermate di fine partita, pedine di riserva, poche icone), prese
dall'esportazione PNG `<gioco>/_ASSET_EXPORT`. Quando anche questi saranno rifatti, la cartella non servira' piu'.

Uso:
    python tools/copia_originale.py "C:/Program Files (x86)/Steam/steamapps/common/Total War Medieval 1 Gold"
I file gia' presenti con la stessa dimensione non si ricopiano.
"""
import os
import re
import shutil
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(PROJECT, "originale")
MUSIC_DIR = "Sounds/Music"
SFX_DIRS = ["Sounds/campmap", "Sounds/Frontend", "Sounds/GameEnd"]


def copy(src, dst, stats):
    if os.path.exists(dst) and os.path.getsize(dst) == os.path.getsize(src):
        stats["uguali"] += 1
        return
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    stats["copiati"] += 1


def main(game):
    stats = {"copiati": 0, "uguali": 0}
    missing = []
    export = os.path.join(game, "_ASSET_EXPORT")
    listed = os.path.join(PROJECT, "tools", "originale_necessari.txt")
    for rel in open(listed, encoding="utf-8").read().splitlines():
        if not rel.strip():
            continue
        src = os.path.join(export, rel)
        if os.path.isfile(src):
            copy(src, os.path.join(DEST, "_ASSET_EXPORT", rel), stats)
        else:
            missing.append("_ASSET_EXPORT/" + rel)
    audio = open(os.path.join(PROJECT, "data/ui/audio.cfg"), encoding="utf-8", errors="replace").read()
    wanted = {n.lower() for n in re.findall(r'"([^"]+\.wav)"', audio, re.I)}
    seen = set()
    for rel in [MUSIC_DIR] + SFX_DIRS:
        folder = os.path.join(game, rel)
        if not os.path.isdir(folder):
            continue
        for f in os.listdir(folder):
            if f.lower() in wanted:
                copy(os.path.join(folder, f), os.path.join(DEST, rel, f), stats)
                seen.add(f.lower())
    missing += sorted("suono " + n for n in wanted - seen)
    os.makedirs(DEST, exist_ok=True)
    open(os.path.join(DEST, ".gdignore"), "a").close()
    print("Cartella: %s\nCopiati %d file, %d gia' aggiornati." % (DEST, stats["copiati"], stats["uguali"]))
    if missing:
        print("Mancano nell'installazione:\n  " + "\n  ".join(missing))
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
