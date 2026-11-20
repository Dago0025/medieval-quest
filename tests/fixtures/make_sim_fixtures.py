"""Genera sim_unit_prod.txt e sim_build_prod.txt: tabelle piccole (stesso formato dei file
reali, 52 e 28 colonne) per i test della simulazione (test_sim_*.gd).
Uso: python3 -I make_sim_fixtures.py   (scrive i file accanto allo script)

Le unita' e gli edifici sono inventati ma ricalcano le famiglie reali (CASTLE, BOWYER,
IMPROVED_FARMLAND, MERCHANT, PORT, SHIPYARD, miniere...). I valori usati dai test:
vedi sim_startpos.txt e i commenti dei test.
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


# --- unita' (52 colonne) ----------------------------------------------------
# col: 0 nome, 1 tipo, 2 costo, 3 mantenimento, 4 anni, 7 uomini, 16 requisiti,
#      19 periodi, 28 fazioni, 29 regioni, 32 culture, 33 dati nave
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
]
write("sim_unit_prod.txt", ["Name/Identifier", "Unit type", "Cost", "Support Cost", "Production time"], UNITS, 52)


# --- edifici (28 colonne) ---------------------------------------------------
# col: 0 upgrade, 1 id, 2 etichette, 3 tipo, 4 costi, 5 tempi, 6 requisiti, 14 religione,
#      18 risorse, 19 fazioni, 22 rendita
def build(fid, ups, kind, costs, times, req, religion="", resources="", factions="", income=""):
    return {0: ups, 1: fid, 2: fid.title(), 3: kind, 4: costs, 5: times, 6: req,
            14: religion, 18: resources, 19: factions, 22: income}


BUILDINGS = [
    build("CASTLE", 3, "CASTLE, TROOP_PRODUCER", "400,1000,2000,4000", "4,8,12,16", "{},{CASTLE},{CASTLE2},{CASTLE3}"),
    build("BOWYER", 1, "TROOP_PRODUCER", "200,400", "2,4", "{CASTLE},{CASTLE2,BOWYER}"),
    build("IMPROVED_FARMLAND", 3, "FARM_INCOME", "600,1000,1500,2000", "2,4,6,8",
          "{},{IMPROVED_FARMLAND},{IMPROVED_FARMLAND2},{IMPROVED_FARMLAND3}", income="120,140,160,180"),
    build("MERCHANT", 3, "TRADING_POST", "800,1000,1200,1400", "2,4,6,8",
          "{CASTLE},{CASTLE2,MERCHANT},{CASTLE3,MERCHANT2},{CASTLE4,MERCHANT3}"),
    build("PORT", 0, "PORT", "750", "4", "{}"),
    build("SHIPYARD", 1, "SHIP_PRODUCER", "400,600", "2,3", "{PORT},{PORT,SHIPYARD}"),
    build("GOLD_MINE", 1, "LEV1_INCOME", "1000,1800", "2,4", "{},{GOLD_MINE}", resources="{ GOLD }", income="200, 400"),
    build("SALT_MINE", 1, "LEV1_INCOME", "250,400", "2,4", "{},{SALT_MINE}", resources="{ SALT }", income="50,100"),
    build("CHURCH", 0, "AGENT_PRODUCER", "200", "2", "{}", religion="CATHOLIC, ORTHODOX"),
    build("MOSQUE", 0, "AGENT_PRODUCER", "200", "2", "{}", religion="MUSLIM"),
    build("GUNSMITH", 0, "TROOP_PRODUCER", "400", "3", "{CASTLE}", factions="{FN_BETA}"),
    build("ARMOURER", 0, "NON_PRODUCER", "400", "3", "{{CASTLE2,BOWYER},{CASTLE4}}"),
    build("UNIVERSITY", 0, "NON_PRODUCER", "1000", "8", "{CASTLE3}"),
]
write("sim_build_prod.txt", ["Number of upgrades", "Name/Identifier", "Localised name", "Building type",
                              "Cost  including upgrades", "Time to build including upgrades", "Building conditions"],
      BUILDINGS, 28)
