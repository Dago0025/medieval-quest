class_name WorldFactions
extends RefCounted
## Fazioni nuove della mappa del mondo (ADR-079): Giapponesi, Cinesi, Aztechi, Inca, Kanem e Cahokia (cultura del Mississippi; prima «Mississippiani»). Le loro righe
## dello startpos (data/mappa_mondo/fazioni_mondo.txt) si aggiungono a quello del mondo; costruiscono gli edifici e
## reclutano gli agenti della fazione `modello` di data/fazioni_mondo.cfg; truppe e navi sono le loro (ADR-116).

const FILE := "res://data/fazioni_mondo.cfg"
const STARTPOS := "res://data/mappa_mondo/fazioni_mondo.txt"

static var _cfg: ConfigFile = null


static func _ensure() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if FileAccess.file_exists(FILE) and _cfg.load(FILE) != OK:
			push_warning("Fazioni del mondo non leggibili: %s" % FILE)
	return _cfg


static func reset() -> void:
	_cfg = null


## Id delle fazioni nuove, nell'ordine del file.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in _ensure().get_sections():
		out.append(s.strip_edges().to_upper())
	return out


## Fazione dell'originale da cui la fazione nuova prende unita' ed edifici ("" se non e' una fazione nuova).
static func model_of(faction_id: String) -> String:
	var key := faction_id.strip_edges().to_upper()
	if not _ensure().has_section(key):
		return ""
	return str(_ensure().get_value(key, "modello", "")).strip_edges().to_upper()


## Fazione navale per l'IA (`navale = true`), anche se il profilo del suo comportamento non lo e' (Giapponesi, 18/11/2026).
static func naval(faction_id: String) -> bool:
	var key := faction_id.strip_edges().to_upper()
	return _ensure().has_section(key) and bool(_ensure().get_value(key, "navale", false))


## Righe dello startpos delle fazioni nuove ("" se il file manca).
static func startpos_text() -> String:
	return TextIO.read_latin1(STARTPOS) if FileAccess.file_exists(STARTPOS) else ""


## Ogni unita' arruolabile o capo della fazione modello lo diventa anche della fazione nuova. Le fazioni con unita' proprie
## (data/unita_mondo.cfg, ADR-116) prendono dal modello solo gli agenti (e le navi, se non ne hanno di proprie); non
## arruolano piu' le truppe ALL_FACTIONS (macchine d'assedio e artiglieria europee) e non hanno la sua unita' del capo.
static func add_to_units(table: UnitProdLoader.UnitTable) -> void:
	if table == null:
		return
	var own := CultureUnits.factions_with_units()
	for fid in ids():
		var model := model_of(fid)
		var has_own := own.has(fid)
		var own_ships := has_own and _has_own_ships(table, fid)
		for u in table.units:
			if CultureUnits.is_culture_unit(u.id):
				continue
			if has_own and u.is_military():
				if u.all_factions and not u.excluded_factions.has(fid):
					u.excluded_factions.append(fid)
				if not u.is_ship() or own_ships:
					continue
			if model == "":
				continue
			if not u.all_factions and u.factions.has(model) and not u.factions.has(fid):
				u.factions.append(fid)
			if not has_own and u.leader_of.has(model) and not u.leader_of.has(fid):
				u.leader_of.append(fid)
	table._faction_cache.clear()


static func _has_own_ships(table: UnitProdLoader.UnitTable, faction_id: String) -> bool:
	for u in table.units:
		if u.is_ship() and CultureUnits.is_culture_unit(u.id) and u.factions.has(faction_id):
			return true
	return false


## Ogni livello d'edificio riservato alla fazione modello vale anche per la fazione nuova.
static func add_to_buildings(table: BuildingProdLoader.BuildingTable) -> void:
	if table == null:
		return
	for fid in ids():
		var model := model_of(fid)
		if model == "":
			continue
		for fam in table.families:
			for lv in fam.levels:
				if lv.factions.has(model) and not lv.factions.has(fid):
					lv.factions.append(fid)
