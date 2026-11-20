"""Genera ai_unit_prod.txt e ai_build_prod.txt: tabelle di prova per i test dell'IA (fase 7a) con i PESI per profilo
(unit_prod colonna 14, build_prod colonne 9 e 10). Pesi e costi sono inventati (nessuna riga dei file originali).
Uso: python3 -I make_ai_fixtures.py   (scrive i file accanto allo script)

Profili: i 20 nomi di SetBehaviour piu' i tre di stato. Per ogni unita'/edificio si dichiara un peso base e alcune eccezioni:
  Spearmen   100 per tutti
  Archers    400 per CATHOLIC_DEFENSIVE, 0 per CATHOLIC_EXPANSIONIST, 100 per gli altri
  Knights    400 per CATHOLIC_EXPANSIONIST, 0 per CATHOLIC_DEFENSIVE, 100 per gli altri
  Galley     200 per tutti
  Castle     100 per tutti (10 per POVERTY_STRICKEN)
  Farmland   400 per tutti (800 per POVERTY_STRICKEN)
  Merchant   300; Port 150; Shipyard 150; Bowyer 120; Church 100; Gold_Mine 350
  Tavern     0 per tutti (con un'influenza che non deve resuscitarla)
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PROFILES = [
    "POVERTY_STRICKEN", "DESPERATE_DEFENCE", "CATHOLIC_EXPANSIONIST", "CATHOLIC_NAVAL_EXPANSIONIST", "CATHOLIC_TRADER",
    "CATHOLIC_CRUSADER_TRADER", "CATHOLIC_EXPANSIONIST_CRUSADER", "CATHOLIC_DEFENSIVE_CRUSADER", "POPE", "CATHOLIC_DEFENSIVE",
    "CATHOLIC_ISOLATIONIST", "ORTHODOX_DEFENSIVE", "ORTHODOX_EXPANSIONIST", "ORTHODOX_STAGNANT", "MUSLIM_PEACEFUL",
    "MUSLIM_EXPANSIONIST", "MUSLIM_DEVOUT", "BARBARIAN_RAIDER", "REBELS", "CLOSE_TO_SUPPORT_LIMIT",
]


def group(base, overrides=None):
    overrides = overrides or {}
    parts = []
    for p in PROFILES:
        parts.append("%s(%s)" % (p, overrides.get(p, base)))
    return ", ".join(parts)


def quote(v):
    v = str(v)
    return '"%s"' % v if ("," in v or "{" in v or "(" in v) else v


# --- unita' (52 colonne come i file reali) ---
UCOLS = 52
units = [
    # nome, tipo, costo, mantenimento, anni, uomini, requisiti, periodi, fazioni, nave, pesi
    ("Spearmen", "INFANTRY", 100, 3, 1, 100, "", "", "", group(100)),
    ("Archers", "INFANTRY", 150, 5, 2, 60, "{BOWYER}", "", "", group(100, {"CATHOLIC_DEFENSIVE": 400, "CATHOLIC_EXPANSIONIST": 0})),
    ("Knights", "CAVALRY", 400, 10, 3, 40, "{CASTLE3}", "", "", group(100, {"CATHOLIC_EXPANSIONIST": 400, "CATHOLIC_DEFENSIVE": 0})),
    ("Galley", "SHIP", 500, 20, 2, 1, "{SHIPYARD1}", "", "1,5,5,3,50,Galley sunk", group(200)),
    ("Emissary", "EMISSARY", 0, 0, 1, 1, "", "", "", group(100)),
]
lines = ["\t".join(["Name/Identifier", "Unit type", "Cost", "Support Cost", "Production time"] + [""] * (UCOLS - 5))]
lines.append("DATA START" + "\t" * (UCOLS - 1))
for name, kind, cost, support, years, men, req, periods, ship, weights in units:
    c = [""] * UCOLS
    c[0], c[1], c[2], c[3], c[4], c[7] = name, kind, cost, support, years, men
    c[14] = quote(weights)
    c[16] = quote(req) if req else ""
    c[19] = "ALL_PERIODS"
    c[28] = "ALL_FACTIONS"
    c[33] = quote(ship) if ship else ""
    lines.append("\t".join(str(x) for x in c))
with open(os.path.join(HERE, "ai_unit_prod.txt"), "w", encoding="latin-1", newline="\n") as f:
    f.write("\n".join(lines) + "\n")

# --- edifici (28 colonne) ---
BCOLS = 28
# (livelli-1, id, tipo, costi, tempi, requisiti, pesi per livello (lista di gruppi), influenze per livello, religioni, risorse, rendite, felicita')
buildings = [
    (3, "CASTLE", "CASTLE, TROOP_PRODUCER", "400,1000,2000,4000", "4,8,12,16", "{},{CASTLE},{CASTLE2},{CASTLE3}",
     [group(100, {"POVERTY_STRICKEN": 10})] * 4, "", "", "", "", ""),
    (1, "BOWYER", "TROOP_PRODUCER", "200,400", "2,4", "{CASTLE},{CASTLE2,BOWYER}",
     [group(120)], "{},{CASTLE2(70)}", "", "", "", ""),
    (3, "IMPROVED_FARMLAND", "FARM_INCOME", "600,1000,1500,2000", "2,4,6,8", "{},{IMPROVED_FARMLAND},{IMPROVED_FARMLAND2},{IMPROVED_FARMLAND3}",
     [group(400, {"POVERTY_STRICKEN": 800})] * 4, "", "", "", "120,140,160,180", ""),
    (3, "MERCHANT", "TRADING_POST", "800,1000,1200,1400", "2,4,6,8", "{CASTLE},{CASTLE2,MERCHANT},{CASTLE3,MERCHANT2},{CASTLE4,MERCHANT3}",
     [group(300)] * 4, "", "", "", "", ""),
    (0, "PORT", "PORT", "750", "4", "{}", [group(150)], "", "", "", "", ""),
    (1, "SHIPYARD", "SHIP_PRODUCER", "400,600", "2,3", "{PORT},{PORT,SHIPYARD}",
     [group(150)], "", "", "", "", ""),
    (0, "TAVERN", "AGENT_PRODUCER", "500", "4", "{CASTLE}", [group(0)], "{CASTLE(100)}", "", "", "", ""),
    (0, "CHURCH", "AGENT_PRODUCER", "200", "2", "{}", [group(100)], "", "CATHOLIC, ORTHODOX", "", "", "2"),
    (1, "GOLD_MINE", "LEV1_INCOME", "1000,1800", "2,4", "{},{GOLD_MINE}", [group(350)], "", "", "{ GOLD }", "200,400", ""),
]
blines = ["\t".join(["Number of upgrades", "Name/Identifier", "Localised name", "Building type", "Cost", "Time", "Building conditions"] + [""] * (BCOLS - 7))]
blines.append("DATA START" + "\t" * (BCOLS - 1))
for ups, bid, kind, costs, times, req, weights, infl, religion, res, income, happy in buildings:
    c = [""] * BCOLS
    c[0], c[1], c[2], c[3] = ups, bid, bid.capitalize(), quote(kind)
    c[4], c[5], c[6] = quote(costs), quote(times), quote(req)
    c[9] = quote("\n    ".join(weights))
    c[10] = quote(infl) if infl else ""
    c[14] = quote(religion) if religion else ""
    c[18] = quote(res) if res else ""
    c[22] = quote(income) if income else ""
    c[23] = happy
    blines.append("\t".join(str(x) for x in c))
with open(os.path.join(HERE, "ai_build_prod.txt"), "w", encoding="latin-1", newline="\n") as f:
    f.write("\n".join(blines) + "\n")
print("scritti ai_unit_prod.txt (%d righe) e ai_build_prod.txt (%d righe)" % (len(units), len(buildings)))
