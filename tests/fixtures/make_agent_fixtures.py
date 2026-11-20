"""Genera agents_unit_prod.txt: la tabella di sim_unit_prod.txt piu' gli agenti della fase 5a (stesso formato, 52
colonne) per i test di agenti e diplomazia (test_sim_diplomacy/agents/missions.gd).
Uso: python3 -I make_agent_fixtures.py   (scrive il file accanto allo script)

Le unita' aggiunte (costo, anni, requisiti, tipo) sono inventate ma ricalcano gli agenti reali:
  Spy (SPY, 100, edificio CASTLE), Assassin (ASSASSIN, 200, CASTLE2), Bishop e Priest (BISHOP, PRIEST, CHURCH),
  Cardinal (CARDINAL, CHURCH), Inquisitor (INQUISITOR, CHURCH), Mullah (MULLAH, MOSQUE),
  Crusade (CRUSADE, 1000) e Jihad (JIHAD, 500): gli ultimi due non si reclutano nella fase 5a.
Il valore iniziale di un agente reclutato e' il livello costruito dell'edificio richiesto (Castle3 a ALTA = 3).
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
NCOLS = 52


def quote(v):
    v = str(v)
    return '"%s"' % v if ("," in v or "{" in v) else v


def unit(name, kind, cost, support, years, men, req="", periods="ALL_PERIODS",
         factions="ALL_FACTIONS", regions="", cultures="", ship=""):
    return {0: name, 1: kind, 2: cost, 3: support, 4: years, 7: men, 16: req,
            19: periods, 28: factions, 29: regions, 32: cultures, 33: ship}


UNITS = [
    unit("Spearmen", "INFANTRY", 100, 3, 1, 100),
    unit("Archers", "INFANTRY", 150, 5, 2, 60, req="{BOWYER}"),
    unit("Knights", "CAVALRY", 400, 10, 3, 40, req="{ {CASTLE3}, {CASTLE2, BOWYER2} }", periods="HIGH, LATE"),
    unit("Galley", "SHIP", 500, 20, 2, 1, req="{SHIPYARD1}", ship="1,5,5,3,50,Galley sunk"),
    unit("Nizari", "INFANTRY", 200, 4, 1, 60, factions="FN_BETA"),
    unit("Alpine", "INFANTRY", 120, 3, 1, 80, regions="ID_BASSA"),
    unit("GreekHoplite", "INFANTRY", 130, 4, 1, 90, cultures="ORTHODOX"),
    unit("Emissary", "EMISSARY", 0, 0, 1, 1),
    unit("Princess", "PRINCESS", 0, 0, 1, 1),
    unit("Camel", "MOUNT", 1, 1, 1, 1),
    unit("NoFactions", "INFANTRY", 90, 2, 1, 50, factions=""),
    # agenti della fase 5a
    unit("Spy", "SPY", 100, 0, 1, 1, req="{CASTLE}"),
    unit("Assassin", "ASSASSIN", 200, 0, 1, 1, req="{CASTLE2}"),
    unit("Bishop", "BISHOP", 100, 0, 1, 1, req="{CHURCH}"),
    unit("Priest", "PRIEST", 100, 0, 1, 1, req="{CHURCH}"),
    unit("Cardinal", "CARDINAL", 150, 0, 1, 1, req="{CHURCH}"),
    unit("Inquisitor", "INQUISITOR", 200, 0, 2, 1, req="{CHURCH}"),
    unit("Mullah", "MULLAH", 100, 0, 1, 1, req="{MOSQUE}", factions="FN_BETA"),
    unit("Crusade", "CRUSADE", 1000, 0, 4, 1, req="{CASTLE}"),
    unit("Jihad", "JIHAD", 500, 0, 2, 1, req="{CASTLE}", factions="FN_BETA"),
]

header = ["Name/Identifier", "Unit type", "Cost", "Support Cost", "Production time"]
lines = ["\t".join(header + [""] * (NCOLS - len(header)))]
lines.append("DATA START" + "\t" * (NCOLS - 1))
for r in UNITS:
    cells = [""] * NCOLS
    for col, val in r.items():
        cells[col] = quote(val)
    lines.append("\t".join(cells))
with open(os.path.join(HERE, "agents_unit_prod.txt"), "w", encoding="latin-1", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print("scritto agents_unit_prod.txt", len(UNITS), "righe")
