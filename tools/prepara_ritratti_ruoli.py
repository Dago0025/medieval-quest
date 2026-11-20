"""Ritratti di agenti, ammiragli e pontefici (ADR-059): dalle cartelle di MTW/_ia_locale/ritratti alle serie del gioco.

Uso:  python tools/prepara_ritratti_ruoli.py <cartella ritratti> [<ritratti_tutti.md>]

Per ogni gruppo di ritratti_tutti.md (C-EM, O-SA, M-UL, P-AM, C-PA...) prende i file <CODICE>-NN.png della sua cartella,
li ritaglia come gli altri ritratti (prepara_rifatti.portrait, 384x568) e li salva in
assets/ritratti/<religione>/<ruolo>/NN.png. Scrive anche data/ritratti_fazioni.cfg: per ogni ritratto le fazioni a cui
spetta, dalle annotazioni del documento («**C-EM-02** · Inglesi»), con i nomi italiani di data/fazioni.cfg; «tutti» = *.
PortraitArt sceglie prima tra i ritratti della fazione, poi tra quelli comuni; i ritratti riservati ai soli Auror
non escono per le altre fazioni.
"""
import os, re, sys
from prepara_rifatti import portrait

GROUPS = {   # codice -> (religione, ruolo, cartella)
    "C-EM": ("catholic", "emissary", "Cattolici emissari"), "C-SP": ("catholic", "spy", "Cattolici spie"),
    "C-AS": ("catholic", "assassin", "Cattolici assassini"), "C-VE": ("catholic", "bishop", "Cattolici vescovi"),
    "C-CA": ("catholic", "cardinal", "Cattolici cardinali"), "C-SA": ("catholic", "priest", "Cattolici sacerdoti"),
    "C-IN": ("catholic", "inquisitor", "Cattolici inquisitori"),
    "C-GI": ("catholic", "grand_inquisitor", "Cattolici grandi inquisitori"),
    "C-PA": ("catholic", "pope", "Cattolici pontefici"), "C-AM": ("catholic", "admiral", "Cattolici ammiragli"),
    "O-EM": ("orthodox", "emissary", "Ortodossi emissari"), "O-SP": ("orthodox", "spy", "Ortodossi spie"),
    "O-AS": ("orthodox", "assassin", "Ortodossi assassini"), "O-SA": ("orthodox", "priest", "Ortodossi sacerdoti"),
    "O-VE": ("orthodox", "bishop", "Ortodossi vescovi"), "O-AM": ("orthodox", "admiral", "Ortodossi ammiragli"),
    "M-EM": ("muslim", "emissary", "Musulmani emissari"), "M-SP": ("muslim", "spy", "Musulmani spie"),
    "M-AS": ("muslim", "assassin", "Musulmani assassini"), "M-UL": ("muslim", "mullah", "Musulmani ulema"),
    "M-IM": ("muslim", "ulama", "Musulmani imam"), "M-AM": ("muslim", "admiral", "Musulmani ammiragli"),
    "P-EM": ("pagan", "emissary", "Pagani e popoli dell'est emissari"), "P-SP": ("pagan", "spy", "Pagani e popoli dell'est spie"),
    "P-AS": ("pagan", "assassin", "Pagani e popoli dell'est assassini"),
    "P-SC": ("pagan", "shaman", "Pagani e popoli dell'est sciamani e sacerdoti"),
    "P-AM": ("pagan", "admiral", "Pagani e popoli dell'est ammiragli"),
}


def faction_ids(root):
    ids, section = {}, ""
    for line in open(os.path.join(root, "data", "fazioni.cfg"), encoding="utf-8"):
        line = line.strip()
        if line.startswith("["):
            section = line
        elif section == "[nomi]" and "=" in line:
            k, v = line.split("=", 1)
            ids[v.strip().strip('"').lower()] = k.strip()
    return ids


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(2)
    src = sys.argv[1]
    doc = sys.argv[2] if len(sys.argv) > 2 else os.path.join(src, "ritratti_tutti.md")
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    names = faction_ids(root)
    text = open(doc, encoding="utf-8").read()
    who = {}
    for code, k, note in re.findall(r"\*\*([A-Z]-[A-Z]+)-(\d+)\*\*([^\n—]*)—", text):
        note = note.strip().lstrip("·").strip()
        if not note:
            continue
        if note.lower().startswith("tutti"):
            who[(code, int(k))] = ["*"]
            continue
        out = []
        for part in note.split(","):
            n = re.sub(r"\(.*?\)", "", part).strip().lower()
            if n not in names:
                raise SystemExit("fazione sconosciuta in %s-%s: %r" % (code, k, part))
            out.append(names[n])
        who[(code, int(k))] = out
    cfg = ["; Fazioni a cui spetta ogni ritratto delle serie dei ruoli (generato da tools/prepara_ritratti_ruoli.py, ADR-059).",
           "; [religione/ruolo] NN = \"FN_A,FN_B\"; * = tutte; ritratti senza riga = comuni.", ""]
    total = 0
    for code, (rel, role, folder) in GROUPS.items():
        files = sorted(f for f in os.listdir(os.path.join(src, folder)) if re.fullmatch(code + r"-\d+\.png", f))
        dest = os.path.join(root, "assets", "ritratti", rel, role)
        os.makedirs(dest, exist_ok=True)
        lines = []
        for f in files:
            k = int(f[len(code) + 1:-4])
            portrait(os.path.join(src, folder, f)).save(os.path.join(dest, "%02d.png" % k), optimize=True)
            total += 1
            if (code, k) in who:
                lines.append('%02d="%s"' % (k, ",".join(who[(code, k)])))
        if lines:
            cfg += ["[%s/%s]" % (rel, role)] + lines + [""]
        print("%s -> assets/ritratti/%s/%s: %d" % (code, rel, role, len(files)))
    open(os.path.join(root, "data", "ritratti_fazioni.cfg"), "w", encoding="utf-8").write("\n".join(cfg))
    print("totale", total)


if __name__ == "__main__":
    main()
