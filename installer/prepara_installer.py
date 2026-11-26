"""Prepara e compila l'installer Windows di Medieval Quest con NSIS.

Uso:
    python installer/prepara_installer.py --versione 2026.11.20 [--exe "build/Medieval Quest.exe"]
        [--makensis makensis]

Crea installer/build/payload/ con:
  - Medieval Quest.exe (pck incorporato, da esporta.bat);
  (dal 26/11/2026 niente cartella originale/: immagini e audio sono tutti del progetto, quindi l'installer non contiene
  file del gioco originale);
  - Guida di gioco.html e Crediti e diritti.html (da docs/GUIDA_DI_GIOCO.md e CREDITI_E_DIRITTI.md);
  - LEGGIMI.txt, LICENSE.txt, LICENZE_TERZE_PARTI.txt (Godot Engine e caratteri);
poi compila installer/build/MedievalQuest-Setup-<versione>.exe.
Richiede Python 3 con il pacchetto `markdown` e NSIS 3 (makensis) su Windows o Linux.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys

import markdown

QUI = os.path.dirname(os.path.abspath(__file__))
PROGETTO = os.path.dirname(QUI)
NOME = "Medieval Quest"

GODOT_LICENZA = """Godot Engine (https://godotengine.org) - MIT License

Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Godot Engine includes third-party components under their own licenses, among
them FreeType: "Portions of this software are copyright (c) The FreeType
Project (www.freetype.org). All rights reserved." The complete list and texts
are at https://godotengine.org/license
"""

CSS = """body{font-family:Georgia,'Times New Roman',serif;max-width:860px;margin:2em auto;padding:0 1.2em;
line-height:1.55;color:#2b2118;background:#f6efe1}h1,h2,h3{color:#5a2e12}h1{border-bottom:2px solid #b08a4a}
table{border-collapse:collapse;margin:1em 0}td,th{border:1px solid #c8b48a;padding:.35em .7em;text-align:left}
th{background:#eadcbc}code{background:#eadcbc;padding:0 .25em;border-radius:3px}blockquote{border-left:4px solid #b08a4a;
margin-left:0;padding-left:1em;color:#5b4a36}a{color:#7a3b10}"""


def leggi(rel):
    with open(os.path.join(PROGETTO, rel), encoding="utf-8") as f:
        return f.read()


def scrivi(percorso, testo, bom=False):
    with open(percorso, "w", encoding="utf-8-sig" if bom else "utf-8", newline="\r\n") as f:
        f.write(testo)


def html(titolo, testo_md):
    # I link relativi del repository non esistono nella cartella installata: restano come testo.
    testo_md = re.sub(r"\[([^\]]+)\]\((?!https?://)[^)]+\)", r"\1", testo_md)
    corpo = markdown.markdown(testo_md, extensions=["tables"])
    return ("<!DOCTYPE html><html lang=\"it\"><head><meta charset=\"utf-8\"><title>%s</title><style>%s</style>"
            "</head><body>%s</body></html>" % (titolo, CSS, corpo))


def licenze_terze_parti():
    parti = [GODOT_LICENZA]
    for nome in ("OFL-Alegreya.txt", "OFL-Fondamento.txt"):
        parti.append("=" * 78 + "\n" + leggi(os.path.join("assets", "fonts", nome)))
    return "\n\n".join(parti)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--versione", required=True, help="versione nel formato A.B.C (es. 2026.11.20)")
    ap.add_argument("--exe", default=os.path.join(PROGETTO, "build", NOME + ".exe"))
    ap.add_argument("--makensis", default="makensis")
    a = ap.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", a.versione):
        sys.exit("Versione non valida: serve A.B.C")
    if not os.path.exists(a.exe):
        sys.exit("Non trovato: %s" % a.exe)

    build = os.path.join(QUI, "build")
    payload = os.path.join(build, "payload")
    shutil.rmtree(payload, ignore_errors=True)
    os.makedirs(payload)
    shutil.copy2(a.exe, os.path.join(payload, NOME + ".exe"))
    scrivi(os.path.join(payload, "Guida di gioco.html"), html("Medieval Quest - Guida di gioco", leggi("docs/GUIDA_DI_GIOCO.md")))
    scrivi(os.path.join(payload, "Crediti e diritti.html"), html("Medieval Quest - Crediti e diritti", leggi("CREDITI_E_DIRITTI.md")))
    scrivi(os.path.join(payload, "LEGGIMI.txt"), leggi("README.md"), bom=True)
    scrivi(os.path.join(payload, "LICENSE.txt"), leggi("LICENSE"), bom=True)
    scrivi(os.path.join(payload, "LICENZE_TERZE_PARTI.txt"), licenze_terze_parti(), bom=True)
    avviso = os.path.join(build, "avviso.txt")
    scrivi(avviso, leggi("installer/avviso.txt"), bom=True)   # NSIS Unicode legge l'UTF-8 solo con BOM

    uscita = os.path.join(build, "MedievalQuest-Setup-%s.exe" % a.versione)
    cmd = [a.makensis, "-V2", "-DVERSIONE=" + a.versione, "-DPAYLOAD=" + payload, "-DUSCITA=" + uscita,
           "-DICONA=" + os.path.join(PROGETTO, "assets", "icona.ico"), "-DAVVISO=" + avviso,
           os.path.join(QUI, "medieval_quest.nsi")]
    print(" ".join(cmd))
    subprocess.run(cmd, check=True)
    print("Installer: %s (%.0f MB)" % (uscita, os.path.getsize(uscita) / 1e6))


if __name__ == "__main__":
    main()
