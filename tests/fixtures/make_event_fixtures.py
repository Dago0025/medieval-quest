"""Genera events_startpos.txt: il mondo di prova del Papato (papacy_startpos.txt) con in piu' la fazione inattiva FN_ORDA
(l'Orda d'Oro dei test) e le righe SetRegionUnfloodable / SetRegionUnquakeable (ID_NORD3, ID_SUD2; terremoti: solo ID_NORD3). Usa le stesse tabelle di
unita' ed edifici del Papato. Servono a tests/unit/event_world.gd e a test_sim_events.gd.
Uso: python3 -I make_event_fixtures.py   (scrive il file accanto allo script)
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(HERE, "papacy_startpos.txt"), encoding="latin-1", newline="") as f:
    text = f.read()
text = text.replace('DeclareFaction::\t"FN_PAPIST"\n', 'DeclareFaction::\t"FN_PAPIST"\nDeclareFaction::\t"FN_ORDA"\n', 1)
assert "FN_ORDA" in text
extra = "SetRegionUnfloodable:: ID_NORD3\nSetRegionUnfloodable:: ID_SUD2\nSetRegionUnquakeable:: ID_NORD3\n"
text = text.rstrip("\n") + "\n" + extra
with open(os.path.join(HERE, "events_startpos.txt"), "w", encoding="latin-1", newline="\n") as f:
    f.write(text)
print("scritto events_startpos.txt")
