"""Genera papacy_unit_prod.txt e papacy_build_prod.txt: le tabelle (stesso formato dei file reali, 52 e 28 colonne)
del mondo di prova del Papato (papacy_startpos.txt, usato da tests/unit/papacy_world.gd e da test_sim_papacy.gd e
test_sim_crusade.gd).
Uso: python3 -I make_papacy_fixtures.py   (scrive i file accanto allo script)

Unita' e edifici sono inventati ma ricalcano quelli reali: Crusade (1000, 4 anni, CHAPTER_HOUSE), Jihad (500, 2 anni,
RIBAT, solo FN_BETA), gli ordini militari (Templars, Hospitallers) con CHAPTER_HOUSE nei requisiti, i religiosi.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def quote(v):
    v = str(v)
    return '"%s"' % v if ("," in v or "{" in v) else v


def write(name, header, rows, ncols):
    lines = ["\t".join(header + [""] * (ncols - len(header)))]
    lines.append("DATA START" + "\t" * (ncols - 1))
    for r in rows:
        cells = [""] * ncols
        for col, val in r.items():
            cells[col] = quote(val)
        lines.append("\t".join(cells))
    with open(os.path.join(HERE, name), "w", encoding="latin-1", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("scritto", name, len(rows), "righe")


def unit(name, kind, cost, support, years, men, req="", periods="ALL_PERIODS",
         factions="ALL_FACTIONS", regions="", cultures=""):
    return {0: name, 1: kind, 2: cost, 3: support, 4: years, 7: men, 16: req,
            19: periods, 28: factions, 29: regions, 32: cultures}


UNITS = [
    unit("Spearmen", "INFANTRY", 100, 3, 1, 100),
    unit("Halberdiers", "INFANTRY", 200, 4, 1, 80, req="{CASTLE2}"),
    unit("Chevaliers", "CAVALRY", 400, 10, 2, 40, req="{CASTLE3}"),
    unit("Nizari", "INFANTRY", 250, 4, 1, 60, factions="FN_BETA"),
    unit("Templars", "CAVALRY", 500, 12, 3, 40, req="{CHAPTER_HOUSE}"),
    unit("Hospitallers", "CAVALRY", 450, 11, 3, 40, req="{CHAPTER_HOUSE}", factions="FN_ALPHA, FN_GAMMA"),
    unit("Catapult", "ARTILLERY", 900, 20, 3, 6, req="{CASTLE3}"),
    unit("Emissary", "EMISSARY", 0, 0, 1, 1),
    unit("Princess", "PRINCESS", 0, 0, 1, 1),
    unit("Bishop", "BISHOP", 100, 0, 1, 1, req="{CHURCH}"),
    unit("Priest", "PRIEST", 100, 0, 1, 1, req="{CHURCH}"),
    unit("Crusade", "CRUSADE", 1000, 0, 4, 1, req="{CHAPTER_HOUSE}"),
    unit("Jihad", "JIHAD", 500, 0, 2, 1, req="{RIBAT}", factions="FN_BETA"),
]
write("papacy_unit_prod.txt", ["Name/Identifier", "Unit type", "Cost", "Support Cost", "Production time"], UNITS, 52)


def build(fid, ups, kind, costs, times, req, religion="", factions=""):
    return {0: ups, 1: fid, 2: fid.title(), 3: kind, 4: costs, 5: times, 6: req, 14: religion, 19: factions}


BUILDINGS = [
    build("CASTLE", 3, "CASTLE, TROOP_PRODUCER", "400,1000,2000,4000", "4,8,12,16", "{},{CASTLE},{CASTLE2},{CASTLE3}"),
    build("CHURCH", 0, "AGENT_PRODUCER", "200", "2", "{}", religion="CATHOLIC, ORTHODOX"),
    build("MOSQUE", 0, "AGENT_PRODUCER", "200", "2", "{}", religion="MUSLIM"),
    build("CHAPTER_HOUSE", 0, "TROOP_PRODUCER", "600", "4", "{CASTLE2}", religion="CATHOLIC"),
    build("RIBAT", 0, "TROOP_PRODUCER", "400", "3", "{CASTLE}", religion="MUSLIM"),
]
write("papacy_build_prod.txt", ["Number of upgrades", "Name/Identifier", "Localised name", "Building type",
                                 "Cost  including upgrades", "Time to build including upgrades", "Building conditions"],
      BUILDINGS, 28)
