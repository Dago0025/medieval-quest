class_name Dharma
extends RefCounted
## Dharma dei popoli asiatici (richiesta di Federico del 22/11/2026): religione propria delle fazioni asiatiche della mappa
## del mondo, con la ruota del Dharma come simbolo. Dati in `data/religione_dharma.cfg`: fazioni, regioni di cultura
## DHARMA_CULTURE, edifici (tempio, monastero, grande pagoda) e agente (il monaco) costruiti dalla riga di un `modello` del
## prod con sopra i valori del file, come le unita' delle fazioni nuove (CultureUnits). Si aggiunge solo con la mappa del
## mondo (Scenario.load_buildings / load_units); la chiave delle province e' ProvinceState.DHARMA, il token REL_DHARMA.

const FILE := "res://data/religione_dharma.cfg"
const KEY := "DHARMA"
const TOKEN := "REL_DHARMA"
const CULTURE := "DHARMA_CULTURE"
const BUILDING_PREFIX := "edificio."
const AGENT_PREFIX := "agente."

static var _cfg: ConfigFile = null


static func reset() -> void:
	_cfg = null


## File esplicito (test); null torna a quello del progetto.
static func use_config(cfg: ConfigFile) -> void:
	_cfg = cfg


static func _ensure() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if FileAccess.file_exists(FILE) and _cfg.load(FILE) != OK:
			push_warning("Religione del Dharma non letta da %s" % FILE)
	return _cfg


static func _upper_list(key: String) -> PackedStringArray:
	var out := PackedStringArray()
	for v in _ensure().get_value("religione", key, []):
		out.append(str(v).strip_edges().to_upper())
	return out


## Fazioni che seguono il Dharma.
static func factions() -> PackedStringArray:
	return _upper_list("fazioni")


## Regioni di cultura DHARMA_CULTURE.
static func regions() -> PackedStringArray:
	return _upper_list("regioni")


## Famiglie degli edifici del Dharma, nell'ordine del file.
static func building_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in _ensure().get_sections():
		if s.begins_with(BUILDING_PREFIX):
			out.append(s.trim_prefix(BUILDING_PREFIX).to_upper())
	return out


## Id degli agenti del Dharma.
static func agent_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in _ensure().get_sections():
		if s.begins_with(AGENT_PREFIX):
			out.append(s.trim_prefix(AGENT_PREFIX))
	return out


## Agenti del modello che le fazioni del Dharma non reclutano (lo sciamano, sostituito dal monaco).
static func removed_agents() -> PackedStringArray:
	var out := PackedStringArray()
	for v in _ensure().get_value("religione", "agenti_tolti", []):
		out.append(str(v).strip_edges())
	return out


## Startpos del mondo: le fazioni del Dharma con SetReligion REL_DHARMA (e SetCulture DHARMA_CULTURE), le regioni
## dell'elenco con la cultura DHARMA_CULTURE in SetAttributes. Il resto del testo non cambia.
static func startpos_text(text: String) -> String:
	var facs := factions()
	var regs := regions()
	if facs.is_empty() and regs.is_empty():
		return text
	var lines := text.replace("\r\n", "\n").split("\n")   # testo misto: il mondo a capo semplice, le fazioni CRLF
	for i in lines.size():
		var line: String = lines[i]
		var cells := line.split("\t")
		if cells.size() < 3:
			continue
		var cmd := cells[0].strip_edges()
		var who := cells[1].strip_edges().to_upper()
		if cmd == "SetReligion::" and facs.has(who):
			cells[2] = TOKEN
		elif cmd == "SetCulture::" and facs.has(who):
			cells[2] = CULTURE
		elif cmd == "SetAttributes::" and regs.has(who) and cells.size() > 4 and cells[4].strip_edges().ends_with("_CULTURE"):
			cells[4] = CULTURE
		else:
			continue
		lines[i] = "\t".join(cells)
	return "\n".join(lines)


## Aggiunge le famiglie degli edifici del Dharma alla tabella (dalla riga del modello) e la condizione propria alle famiglie
## di `alternative` (l'universita' con la grande pagoda al posto della cattedrale). Un modello che manca e' un errore.
static func append_buildings(table: BuildingProdLoader.BuildingTable) -> void:
	if table == null:
		return
	var cfg := _ensure()
	var index := table.families.size()
	for fid in building_ids():
		if table.has_family(fid):
			continue
		var s := BUILDING_PREFIX + fid
		var model := table.get_family(str(cfg.get_value(s, "modello", "")))
		if model == null:
			table.errors.append("Edificio del Dharma %s: modello %s non trovato" % [fid, cfg.get_value(s, "modello", "")])
			continue
		var cells := {
			BuildingProdLoader.COL_LEVELS: "0",
			BuildingProdLoader.COL_ID: fid,
			BuildingProdLoader.COL_LABEL: str(cfg.get_value(s, "etichetta", fid)),
			7: str(cfg.get_value(s, "etichetta", fid)),          # illustrazione della scheda: stesso nome dell'icona
			BuildingProdLoader.COL_RELIGION: KEY,
			BuildingProdLoader.COL_FACTIONS: "",
			BuildingProdLoader.COL_GLORY: "",
			BuildingProdLoader.COL_COST: str(int(cfg.get_value(s, "costo", 0))),
			BuildingProdLoader.COL_TIME: str(int(cfg.get_value(s, "tempo", 1))),
			BuildingProdLoader.COL_REQUIRES: str(cfg.get_value(s, "requisiti", "{}")),
			BuildingProdLoader.COL_TECH: str(int(cfg.get_value(s, "tecnologia", 0))),
			BuildingProdLoader.COL_UPGRADES: str(cfg.get_value(s, "miglioramenti", "")),
			BuildingProdLoader.COL_FAITH: str(cfg.get_value(s, "fede", "")),
			BuildingProdLoader.COL_INCOME: str(cfg.get_value(s, "rendita", "")),
			BuildingProdLoader.COL_HAPPINESS: str(cfg.get_value(s, "felicita", "")),
		}
		var b := BuildingProdLoader.build_row(ScenarioFilter.patch_row(model.raw, cells), index, table)
		if b == null:
			continue
		table.add(b)
		index += 1
	var alt: Variant = cfg.get_value("religione", "alternative", {})
	if typeof(alt) == TYPE_DICTIONARY:
		for family in alt:
			var fam := table.get_family(str(family))
			if fam == null:
				continue
			if not fam.religions.has(KEY):
				fam.religions.append(KEY)
			for group in UnitProdLoader.parse_condition(str(alt[family])):
				for lv in fam.levels:
					if not lv.requires.has(group):
						lv.requires.append(group)


## Aggiunge gli agenti del Dharma (dalla riga del modello: il monaco nasce dallo sciamano) e toglie alle fazioni del
## Dharma gli agenti pagani di `agenti_tolti`, che prendevano dalla fazione modello (WorldFactions.add_to_units).
static func append_units(table: UnitProdLoader.UnitTable) -> void:
	if table == null:
		return
	var cfg := _ensure()
	var facs := factions()
	var joined := ", ".join(facs)
	var index := table.units.size()
	for aid in agent_ids():
		if table.has_unit(aid):
			continue
		var s := AGENT_PREFIX + aid
		var model := table.get_unit(str(cfg.get_value(s, "modello", "")))
		if model == null:
			table.errors.append("Agente del Dharma %s: modello %s non trovato" % [aid, cfg.get_value(s, "modello", "")])
			continue
		var cells := {
			UnitProdLoader.COL_NAME: aid,
			UnitProdLoader.COL_REQUIRES: str(cfg.get_value(s, "requisiti", "")),
			UnitProdLoader.COL_FACTIONS: joined,
			51: joined,
			UnitProdLoader.COL_CULTURES: "",
			44: "%s(2)" % KEY,     # zelo dato alla religione della provincia
			45: "%s(3)" % KEY,     # conversione verso il Dharma
		}
		var u := UnitProdLoader.build_row(ScenarioFilter.patch_row(model.raw, cells), index, table)
		if u == null:
			continue
		table.add(u)
		index += 1
	for removed in removed_agents():
		var u := table.get_unit(removed)
		if u == null:
			continue
		for fid in facs:
			var at := u.factions.find(fid)
			if at >= 0:
				u.factions.remove_at(at)
	table._faction_cache.clear()
