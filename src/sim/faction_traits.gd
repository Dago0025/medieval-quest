class_name FactionTraits
extends RefCounted
## Tratti storici delle fazioni (ADR-089, richiesta di Federico del 17/11/2026): bonus e malus su reddito, costi,
## mantenimento, tempi, forza nelle battaglie, lealta', agenti e forze di partenza, letti da data/regole/tratti_fazioni.cfg.
## Valgono per chiunque guidi la fazione, giocatore o IA (parita', ADR-015). `Rules.new()` ha la tabella vuota: senza file
## ogni fattore vale 1 e nulla cambia. Nella modalita' Auror FN_DANISH (gli Auror) non ha tratti (`Scenario.apply_rules`).
## Valori PROVVISORI, da tarare giocando.

const DEFAULT_PATH := "res://data/regole/tratti_fazioni.cfg"

## Chiavi in percentuale (+20 = +20%).
const PERCENT_KEYS := [
	"agricoltura", "commercio", "miniere",
	"costo_truppe", "costo_cavalleria", "costo_navi", "costo_edifici",
	"mantenimento_truppe", "mantenimento_navi",
	"forza_fanteria", "forza_cavalleria", "forza_arcieri", "forza_artiglieria", "forza_navi",
	"tesoro_iniziale",
]
## Chiavi intere (anni, punti, stelle, pile).
const INT_KEYS := [
	"anni_navi", "anni_edifici", "lealta", "valore_emissari", "valore_spie", "valore_religiosi", "valore_reclute",
	"truppe_iniziali", "navi_iniziali",
]
const TEXT_KEYS := ["titolo", "titolo_en", "descrizione", "descrizione_en"]
## Chiavi in cui un valore negativo e' un vantaggio (costi, mantenimento, tempi).
const LOWER_IS_BETTER := [
	"costo_truppe", "costo_cavalleria", "costo_navi", "costo_edifici", "mantenimento_truppe", "mantenimento_navi",
	"anni_navi", "anni_edifici",
]
## Ordine delle righe nella descrizione: prima economia, poi forze, poi societa' e partenza.
const DESCRIPTION_ORDER := [
	"agricoltura", "commercio", "miniere", "tesoro_iniziale",
	"costo_truppe", "costo_cavalleria", "mantenimento_truppe", "costo_navi", "mantenimento_navi", "anni_navi",
	"costo_edifici", "anni_edifici",
	"forza_fanteria", "forza_cavalleria", "forza_arcieri", "forza_artiglieria", "forza_navi", "valore_reclute",
	"lealta", "valore_emissari", "valore_spie", "valore_religiosi",
	"truppe_iniziali", "navi_iniziali",
]

## FN_* -> {chiave: valore}; i testi restano stringhe.
var table := {}
var errors := PackedStringArray()


static func load_file(path: String = DEFAULT_PATH) -> FactionTraits:
	var t := FactionTraits.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		t.errors.append("Tratti delle fazioni non letti da %s (errore %d)" % [path, err])
		return t
	var aliases := {}
	for section in cfg.get_sections():
		var id := section.strip_edges().to_upper()
		if not id.begins_with("FN_"):
			continue
		var entry := {}
		for key in cfg.get_section_keys(section):
			var v: Variant = cfg.get_value(section, key)
			if key == "come":
				aliases[id] = str(v).strip_edges().to_upper()
			elif PERCENT_KEYS.has(key) or INT_KEYS.has(key):
				if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
					t.errors.append("%s: %s non e' un numero" % [id, key])
					continue
				entry[key] = int(v) if INT_KEYS.has(key) else float(v)
			elif TEXT_KEYS.has(key):
				entry[key] = str(v)
			else:
				t.errors.append("%s: chiave sconosciuta %s" % [id, key])
		t.table[id] = entry
	for id in aliases.keys():
		var source := str(aliases[id])
		if t.table.has(source):
			t.table[id] = (t.table[source] as Dictionary).duplicate()
		else:
			t.errors.append("%s: come=%s non esiste" % [id, source])
	return t


## Toglie i tratti di una fazione (modalita' Auror: gli Auror hanno i poteri di auror.cfg).
func drop(faction_id: String) -> void:
	table.erase(faction_id.strip_edges().to_upper())


func has_traits(faction_id: String) -> bool:
	return table.has(faction_id.strip_edges().to_upper())


## Tratti della fazione ({} se non ne ha).
func of(faction_id: String) -> Dictionary:
	return table.get(faction_id.strip_edges().to_upper(), {})


## Valore numerico di una chiave (0 se assente).
func value(faction_id: String, key: String) -> float:
	return float(of(faction_id).get(key, 0))


func int_value(faction_id: String, key: String) -> int:
	return int(of(faction_id).get(key, 0))


## Fattore di una chiave in percentuale: 1 + valore / 100 (mai sotto 0,05).
func factor(faction_id: String, key: String) -> float:
	return maxf(0.05, 1.0 + value(faction_id, key) / 100.0)


# --- economia ---------------------------------------------------------------------------------------------------------


func farm_factor(faction_id: String) -> float:
	return factor(faction_id, "agricoltura")


func trade_factor(faction_id: String) -> float:
	return factor(faction_id, "commercio")


func mine_factor(faction_id: String) -> float:
	return factor(faction_id, "miniere")


func start_treasury(faction_id: String, base: int) -> int:
	return roundi(float(base) * factor(faction_id, "tesoro_iniziale"))


# --- costi, tempi, mantenimento ---------------------------------------------------------------------------------------


## Prezzo di arruolamento di un'unita' per la fazione (truppe e navi; agenti, crociate e jihad al prezzo del file).
func unit_cost(faction_id: String, unit: UnitType) -> int:
	if unit == null:
		return 0
	var pct := _unit_cost_percent(faction_id, unit)
	if pct == 0.0:
		return unit.cost
	return maxi(1, roundi(float(unit.cost) * maxf(0.05, 1.0 + pct / 100.0)))


func _unit_cost_percent(faction_id: String, unit: UnitType) -> float:
	if unit.is_ship():
		return value(faction_id, "costo_navi")
	if not unit.is_military():
		return 0.0
	var pct := value(faction_id, "costo_truppe")
	if unit.is_cavalry():
		pct += value(faction_id, "costo_cavalleria")
	return pct


## Anni di arruolamento (navi: `anni_navi`), mai sotto 1.
func unit_years(faction_id: String, unit: UnitType) -> int:
	if unit == null:
		return 1
	var years := maxi(1, unit.build_time)
	if unit.is_ship():
		years += int_value(faction_id, "anni_navi")
	return maxi(1, years)


func building_cost(faction_id: String, lv: BuildingType.Level) -> int:
	if lv == null:
		return 0
	var pct := value(faction_id, "costo_edifici")
	if pct == 0.0:
		return lv.cost
	return maxi(1, roundi(float(lv.cost) * maxf(0.05, 1.0 + pct / 100.0)))


func building_years(faction_id: String, lv: BuildingType.Level) -> int:
	if lv == null:
		return 1
	return maxi(1, maxi(1, lv.build_time) + int_value(faction_id, "anni_edifici"))


## Fattore del mantenimento di un'unita' (navi o truppe).
func upkeep_factor(faction_id: String, unit: UnitType) -> float:
	if unit == null:
		return 1.0
	return factor(faction_id, "mantenimento_navi" if unit.is_ship() else "mantenimento_truppe")


# --- battaglie --------------------------------------------------------------------------------------------------------


## Vero per le unita' che tirano (archi, balestre, armi da fuoco): classe MISSILE o un proiettile.
static func is_missile(unit: UnitType) -> bool:
	if unit == null or unit.is_ship():
		return false
	if unit.unit_classes.has("MISSILE"):
		return true
	var p := unit.projectile.strip_edges().to_upper()
	return p != "" and p != "NONE"


## Fattore della forza di una pila nella risoluzione automatica (gli arcieri a cavallo sommano le due voci).
func strength_factor(faction_id: String, unit: UnitType) -> float:
	if unit == null or table.is_empty():
		return 1.0
	var pct := 0.0
	if unit.is_ship():
		pct = value(faction_id, "forza_navi")
	elif unit.is_artillery():
		pct = value(faction_id, "forza_artiglieria")
	else:
		if unit.is_cavalry():
			pct += value(faction_id, "forza_cavalleria")
		elif unit.is_infantry() and not is_missile(unit):
			pct += value(faction_id, "forza_fanteria")
		if is_missile(unit):
			pct += value(faction_id, "forza_arcieri")
	return maxf(0.05, 1.0 + pct / 100.0)


# --- province e agenti ------------------------------------------------------------------------------------------------


func loyalty_bonus(faction_id: String) -> int:
	return int_value(faction_id, "lealta")


## Stelle in piu' o in meno di un agente reclutato secondo il tipo.
func agent_bonus(faction_id: String, type_name: String) -> int:
	var t := type_name.strip_edges().to_upper()
	if t == AgentState.EMISSARY or t == AgentState.PRINCESS:
		return int_value(faction_id, "valore_emissari")
	if t == AgentState.SPY or t == AgentState.ASSASSIN:
		return int_value(faction_id, "valore_spie")
	if AgentState.RELIGIOUS_TYPES.has(t):
		return int_value(faction_id, "valore_religiosi")
	return 0


# --- descrizione (scelta della fazione) -------------------------------------------------------------------------------


func title(faction_id: String) -> String:
	var e := of(faction_id)
	return str(e.get("titolo_en", e.get("titolo", ""))) if Lang.is_english() else str(e.get("titolo", ""))


func description(faction_id: String) -> String:
	var e := of(faction_id)
	return str(e.get("descrizione_en", e.get("descrizione", ""))) if Lang.is_english() else str(e.get("descrizione", ""))


## Righe dei bonus e dei malus, nell'ordine di DESCRIPTION_ORDER: [{"testo", "bonus" (vero se e' un vantaggio)}].
func lines(faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := of(faction_id)
	for key in DESCRIPTION_ORDER:
		var v := float(e.get(key, 0))
		if v == 0.0:
			continue
		var good := v < 0.0 if LOWER_IS_BETTER.has(key) else v > 0.0
		out.append({"testo": line_text(key, v), "bonus": good})
	return out


## Testo di una riga: «Commercio +20%», «Navi: 1 anno in meno», «+2 navi alla partenza».
static func line_text(key: String, v: float) -> String:
	var n := int(v)
	var sg := "+" if v > 0.0 else "−"
	var pct := "%s%d%%" % [sg, absi(roundi(v))]
	match key:
		"agricoltura": return Lang.t("Agricoltura %s") % pct
		"commercio": return Lang.t("Commercio %s") % pct
		"miniere": return Lang.t("Miniere %s") % pct
		"tesoro_iniziale": return Lang.t("Tesoro iniziale %s") % pct
		"costo_truppe": return Lang.t("Costo delle truppe %s") % pct
		"costo_cavalleria": return Lang.t("Costo della cavalleria %s") % pct
		"costo_navi": return Lang.t("Costo delle navi %s") % pct
		"costo_edifici": return Lang.t("Costo degli edifici %s") % pct
		"mantenimento_truppe": return Lang.t("Mantenimento delle truppe %s") % pct
		"mantenimento_navi": return Lang.t("Mantenimento delle navi %s") % pct
		"forza_fanteria": return Lang.t("Forza della fanteria %s") % pct
		"forza_cavalleria": return Lang.t("Forza della cavalleria %s") % pct
		"forza_arcieri": return Lang.t("Forza di arcieri e balestrieri %s") % pct
		"forza_artiglieria": return Lang.t("Forza dell'artiglieria %s") % pct
		"forza_navi": return Lang.t("Forza delle flotte %s") % pct
		"anni_navi":
			return (Lang.t("Navi: %d anno in meno per costruirle") if absi(n) == 1 else Lang.t("Navi: %d anni in meno per costruirle")) % absi(n) if n < 0 \
				else (Lang.t("Navi: %d anno in più per costruirle") if n == 1 else Lang.t("Navi: %d anni in più per costruirle")) % n
		"anni_edifici":
			return (Lang.t("Edifici: %d anno in meno per costruirli") if absi(n) == 1 else Lang.t("Edifici: %d anni in meno per costruirli")) % absi(n) if n < 0 \
				else (Lang.t("Edifici: %d anno in più per costruirli") if n == 1 else Lang.t("Edifici: %d anni in più per costruirli")) % n
		"lealta": return Lang.t("Lealtà delle province %s") % ("%s%d" % [sg, absi(n)])
		"valore_emissari": return _stars(Lang.t("Emissari e principesse"), n)
		"valore_spie": return _stars(Lang.t("Spie e assassini"), n)
		"valore_religiosi": return _stars(Lang.t("Religiosi"), n)
		"valore_reclute": return Lang.t("Reclute già esperte (valore %d)") % n
		"truppe_iniziali": return Lang.t("+%d unità di truppe alla partenza") % n
		"navi_iniziali": return (Lang.t("+%d navi alla partenza") if n != 1 else Lang.t("+%d nave alla partenza")) % n
	return "%s %s" % [key, pct]


static func _stars(who: String, n: int) -> String:
	var sg := "+" if n > 0 else "−"
	return (Lang.t("%s: %s%d stella") if absi(n) == 1 else Lang.t("%s: %s%d stelle")) % [who, sg, absi(n)]
