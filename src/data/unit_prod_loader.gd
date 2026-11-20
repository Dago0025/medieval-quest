class_name UnitProdLoader
extends RefCounted
## Legge il file prod delle unità (MTW_XL_EARLY_UNIT_PROD11.TXT e simili).
##
## Formato: TSV a 52 colonne con campi tra virgolette (che possono contenere
## virgole e a capo). Le prime righe sono intestazioni; i dati iniziano dopo la
## riga "DATA START". Ogni riga è un'unità, una nave, una cavalcatura o un agente.
## Questa classe ospita anche i lettori condivisi con BuildingProdLoader
## (parse_tsv, parse_condition, split_list...).

const EXPECTED_COLUMNS := 52

const COL_NAME := 0
const COL_TYPE := 1
const COL_COST := 2
const COL_SUPPORT := 3
const COL_TIME := 4
const COL_HANDICAP := 5
const COL_STRENGTH := 6
const COL_MEN := 7
const COL_HONOUR_STEP := 8
const COL_GENERAL := 9
const COL_RULER := 11
const COL_REGION_ADV := 12
const COL_REQUIRES := 16
const COL_CLASSES := 17
const COL_MORAL := 18
const COL_PERIODS := 19
const COL_SCALABLE := 20
const COL_STATS := 21
const COL_INVISIBLE := 22
const COL_AI_CHOICES := 14
const COL_MOUNT := 25
const COL_LEADER_OF := 27
const COL_FACTIONS := 28
const COL_REGIONS := 29
const COL_CULTURES := 32
const COL_SHIP := 33
const COL_WEAPON := 48
const COL_MERCENARY := 49


## Tabella delle unità lette da un file.
class UnitTable:
	var column_names := PackedStringArray()   ## prima riga di intestazione
	var units: Array[UnitType] = []
	var errors := PackedStringArray()
	var _by_id := {}
	var _faction_cache := {}

	func add(u: UnitType) -> void:
		_faction_cache.clear()
		var key := u.id.to_upper()
		if _by_id.has(key):
			errors.append("Unità dichiarata due volte: %s" % u.id)
			return
		units.append(u)
		_by_id[key] = u

	func has_unit(unit_id: String) -> bool:
		return _by_id.has(unit_id.strip_edges().to_upper())

	func get_unit(unit_id: String) -> UnitType:
		return _by_id.get(unit_id.strip_edges().to_upper())

	func of_type(type_name: String) -> Array[UnitType]:
		var out: Array[UnitType] = []
		var key := type_name.strip_edges().to_upper()
		for u in units:
			if u.type_name == key:
				out.append(u)
		return out

	## Fanteria, cavalleria e artiglieria (non navi) che la fazione puo' reclutare secondo la colonna fazioni, nell'ordine del
	## file. Elenco memorizzato (fase 7: l'IA lo chiede a ogni anno); le altre condizioni (periodo, regione, cultura,
	## edifici) le controlla chi recluta.
	func land_for(faction_id: String) -> Array[UnitType]:
		return _for_faction(faction_id, false)

	## Navi che la fazione puo' reclutare secondo la colonna fazioni, nell'ordine del file.
	func ships_for(faction_id: String) -> Array[UnitType]:
		return _for_faction(faction_id, true)

	func _for_faction(faction_id: String, ships_only: bool) -> Array[UnitType]:
		var key := "%s|%s" % [faction_id.strip_edges().to_upper(), "N" if ships_only else "T"]
		if _faction_cache.has(key):
			var cached: Array = _faction_cache[key]
			var again: Array[UnitType] = []
			for item in cached:
				again.append(item)
			return again
		var out: Array[UnitType] = []
		for u in units:
			if not u.is_military() or u.is_ship() != ships_only or not u.recruitable_by(faction_id):
				continue
			out.append(u)
		_faction_cache[key] = out
		return out

	## Truppe e navi.
	func military() -> Array[UnitType]:
		var out: Array[UnitType] = []
		for u in units:
			if u.is_military():
				out.append(u)
		return out

	func ships() -> Array[UnitType]:
		return of_type(UnitType.SHIP)

	func mounts() -> Array[UnitType]:
		return of_type(UnitType.MOUNT)

	## Agenti e azioni strategiche (una voce ciascuno; Priest e Shaman hanno lo stesso tipo).
	func agents() -> Array[UnitType]:
		var out: Array[UnitType] = []
		for u in units:
			if u.is_agent():
				out.append(u)
		return out

	## Tipi distinti degli agenti, in ordine alfabetico.
	func agent_type_names() -> PackedStringArray:
		var seen := {}
		for u in agents():
			seen[u.type_name] = true
		var out := PackedStringArray(seen.keys())
		out.sort()
		return out


## `overrides` (scenario storico, ADR-068): nome dell'unita' in maiuscolo -> {colonna: valore} da rimettere prima di leggerla.
static func load_file(path: String, overrides: Dictionary = {}) -> UnitTable:
	return load_text(TextIO.read_latin1(path), overrides)


static func load_text(text: String, overrides: Dictionary = {}) -> UnitTable:
	var table := UnitTable.new()
	var rows := parse_tsv(text)
	var start := data_start(rows)
	if start < 0:
		table.errors.append("Marcatore DATA START non trovato")
		return table
	if start > 0:
		table.column_names = rows[0]
	var index := 0
	for r in range(start, rows.size()):
		var fields := rows[r]
		if not overrides.is_empty():
			var key := cell(fields, COL_NAME).to_upper()
			if overrides.has(key):
				fields = ScenarioFilter.patch_row(fields, overrides[key])
		var u := _build_unit(fields, index, table)
		index += 1
		if u != null:
			table.add(u)
	return table


## Unita' da una riga gia' divisa in campi (AurorUnits, ADR-074); null se la riga non ha nome.
static func build_row(f: PackedStringArray, index: int, table: UnitTable) -> UnitType:
	return _build_unit(f, index, table)


static func _build_unit(f: PackedStringArray, index: int, table: UnitTable) -> UnitType:
	var unit_id := cell(f, COL_NAME)
	if unit_id.is_empty():
		table.errors.append("Voce %d: nome vuoto" % index)
		return null
	if f.size() < EXPECTED_COLUMNS:
		table.errors.append("%s: %d colonne invece di %d" % [unit_id, f.size(), EXPECTED_COLUMNS])
	var u := UnitType.new(unit_id)
	u.index = index
	u.raw = f
	u.type_name = cell(f, COL_TYPE).to_upper()
	u.cost = int_cell(f, COL_COST, unit_id, table)
	u.support_cost = int_cell(f, COL_SUPPORT, unit_id, table)
	u.build_time = int_cell(f, COL_TIME, unit_id, table)
	u.honour_handicap = int_cell(f, COL_HANDICAP, unit_id, table)
	u.base_strength = int_cell(f, COL_STRENGTH, unit_id, table)
	u.men = int_cell(f, COL_MEN, unit_id, table)
	u.honour_step = int_cell(f, COL_HONOUR_STEP, unit_id, table)
	u.general_candidate = cell(f, COL_GENERAL).to_upper()
	u.ruler_advantage = cell(f, COL_RULER).to_upper()
	u.region_advantage = cell(f, COL_REGION_ADV).to_upper()
	u.requires = parse_condition(cell(f, COL_REQUIRES))
	u.unit_classes = split_list(cell(f, COL_CLASSES))
	var moral := cell(f, COL_MORAL)
	u.has_moral_bonus = not moral.is_empty()
	u.moral_bonus = int_cell(f, COL_MORAL, unit_id, table)
	u.periods = split_list(cell(f, COL_PERIODS))
	u.scalable = cell(f, COL_SCALABLE).to_upper() == "YES"
	u.stats = parse_stats(cell(f, COL_STATS))
	u.charge_bonus = u.stat_int("CHARGE_BONUS")
	u.melee_bonus = u.stat_int("MELEE_BONUS")
	u.defence_bonus = u.stat_int("DEFENCE_BONUS")
	u.armour_level = u.stat_int("ARMOUR_LEVEL")
	u.honour_level = u.stat_int("HONOUR_LEVEL")
	u.ammo = u.stat_int("AMMO")
	u.projectile = str(u.stats.get("PROJECTILE_TYPE", "")).to_upper()
	u.invisible = cell(f, COL_INVISIBLE).to_upper() == "YES"
	u.mount_type = cell(f, COL_MOUNT).to_upper()
	u.leader_of = split_list(cell(f, COL_LEADER_OF))
	for fac in split_list(cell(f, COL_FACTIONS)):
		if fac == "ALL_FACTIONS":
			u.all_factions = true
		else:
			u.factions.append(fac)
	u.regions = split_list(cell(f, COL_REGIONS))
	u.cultures = split_list(cell(f, COL_CULTURES))
	_read_ship(u, cell(f, COL_SHIP))
	if u.is_ship() and not u.is_ship_data:
		table.errors.append("%s: dati nave mancanti o non validi" % unit_id)
	var ai_groups := parse_weight_groups(cell(f, COL_AI_CHOICES))
	if not ai_groups.is_empty():
		u.ai_weights = ai_groups[0]
	u.weapon_type = cell(f, COL_WEAPON).to_upper()
	u.mercenary = cell(f, COL_MERCENARY).to_upper() == "YES"
	return u


## Col. 33: "portata, attacco, difesa, velocità, forza, etichetta".
static func _read_ship(u: UnitType, text: String) -> void:
	if text.is_empty():
		return
	var parts := text.split(",")
	if parts.size() < 5:
		return
	for i in 5:
		if not parts[i].strip_edges().is_valid_int():
			return
	u.ship_range = parts[0].strip_edges().to_int()
	u.ship_attack = parts[1].strip_edges().to_int()
	u.ship_defence = parts[2].strip_edges().to_int()
	u.ship_speed = parts[3].strip_edges().to_int()
	u.ship_strength = parts[4].strip_edges().to_int()
	u.ship_sunk_label = ",".join(parts.slice(5)).strip_edges()
	u.is_ship_data = true


# --- Lettori condivisi con BuildingProdLoader -------------------------------


## Pesi dell'IA «COMPORTAMENTO(peso), COMPORTAMENTO(peso)...» (unit_prod col. 14, build_prod col. 9). Il testo puo' contenere
## piu' gruppi di fila (un gruppo per livello negli edifici, separati da spazi o a capo): un nuovo gruppo comincia quando un
## comportamento si ripete. Restituisce un Dictionary comportamento (maiuscolo) -> peso (float) per gruppo.
static func parse_weight_groups(text: String) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var re := RegEx.new()
	re.compile("([A-Za-z_][A-Za-z_0-9]*)\\s*\\(\\s*(-?[0-9]*\\.?[0-9]+)\\s*\\)")
	var current := {}
	for m in re.search_all(text):
		var key := m.get_string(1).to_upper()
		if current.has(key):
			groups.append(current)
			current = {}
		current[key] = m.get_string(2).to_float()
	if not current.is_empty():
		groups.append(current)
	return groups


## Divide un testo TSV in righe di campi. I campi tra virgolette possono
## contenere tab, a capo e virgolette doppie (""). Le righe vuote si saltano.
static func parse_tsv(text: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var lines := text.replace("\r", "").split("\n")
	var i := 0
	while i < lines.size():
		var record: String = lines[i]
		i += 1
		while record.count("\"") % 2 == 1 and i < lines.size():
			record += "\n" + lines[i]
			i += 1
		if record.strip_edges().is_empty():
			continue
		rows.append(_split_record(record))
	return rows


static func _split_record(record: String) -> PackedStringArray:
	var fields := PackedStringArray()
	var pending := ""
	var open := false
	for part in record.split("\t"):
		if open:
			pending += "\t" + part
			if pending.count("\"") % 2 == 0:
				fields.append(_unquote(pending))
				open = false
		elif part.begins_with("\"") and part.count("\"") % 2 == 1:
			pending = part
			open = true
		else:
			fields.append(_unquote(part))
	if open:
		fields.append(_unquote(pending))
	return fields


static func _unquote(field: String) -> String:
	if field.length() >= 2 and field.begins_with("\"") and field.ends_with("\""):
		return field.substr(1, field.length() - 2).replace("\"\"", "\"")
	return field


## Indice della prima riga dopo "DATA START", oppure -1.
static func data_start(rows: Array[PackedStringArray]) -> int:
	for r in rows.size():
		if rows[r].size() > 0 and rows[r][0].strip_edges().to_upper() == "DATA START":
			return r + 1
	return -1


## Campo senza spazi ai bordi; "" se la colonna non esiste.
static func cell(fields: PackedStringArray, col: int) -> String:
	if col < fields.size():
		return fields[col].strip_edges()
	return ""


## Intero di una colonna; vuoto = 0; testo non numerico = 0 con errore.
static func int_cell(fields: PackedStringArray, col: int, owner_id: String, table: UnitTable) -> int:
	var s := cell(fields, col)
	if s.is_empty():
		return 0
	if not s.is_valid_int():
		table.errors.append("%s: valore non intero in colonna %d: %s" % [owner_id, col, s])
		return 0
	return s.to_int()


## "a, b,,c" -> [A, B, C] (maiuscolo, senza vuoti).
static func split_list(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in s.split(","):
		var t := part.strip_edges()
		if not t.is_empty():
			out.append(t.to_upper())
	return out


## Divide sulle virgole fuori dalle graffe.
static func split_top(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var start := 0
	for i in s.length():
		var c: String = s[i]
		if c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
		elif c == "," and depth == 0:
			out.append(s.substr(start, i - start).strip_edges())
			start = i + 1
	out.append(s.substr(start).strip_edges())
	return out


## Vero se la prima graffa si chiude solo all'ultimo carattere.
static func is_wrapped(s: String) -> bool:
	if not (s.begins_with("{") and s.ends_with("}")):
		return false
	var depth := 0
	for i in s.length():
		var c: String = s[i]
		if c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0 and i < s.length() - 1:
				return false
	return true


## Lista tra graffe opzionali: "{ A, B }" e "A, B" -> [A, B].
static func unbrace_list(s: String) -> PackedStringArray:
	var t := s.strip_edges()
	if is_wrapped(t):
		t = t.substr(1, t.length() - 2)
	return split_list(t)


## Condizione sugli edifici. `{}` o vuoto -> []; `{ A, B }` -> [[A, B]] (AND);
## `{ {A,B},{C} }` -> [[A, B], [C]] (OR tra gruppi AND).
static func parse_condition(s: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var t := s.strip_edges()
	if is_wrapped(t):
		t = t.substr(1, t.length() - 2).strip_edges()
	if t.is_empty():
		return out
	if not t.contains("{"):
		out.append(split_list(t))
		return out
	var depth := 0
	var start := -1
	for i in t.length():
		var c: String = t[i]
		if c == "{":
			if depth == 0:
				start = i + 1
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0 and start >= 0:
				var group := split_list(t.substr(start, i - start))
				if not group.is_empty():
					out.append(group)
				start = -1
	return out


## Vero se almeno un gruppo ha tutti i suoi token in `have` (confronto letterale,
## senza regole "livello almeno n"). Condizione vuota = sempre vera.
static func condition_met(condition: Array[PackedStringArray], have: PackedStringArray) -> bool:
	if condition.is_empty():
		return true
	for group in condition:
		var ok := true
		for token in group:
			if not have.has(token):
				ok = false
				break
		if ok:
			return true
	return false


## "CHIAVE( n ), ALTRA( TESTO )" -> {CHIAVE: n, ALTRA: "TESTO"} (int, float o String).
static func parse_stats(s: String) -> Dictionary:
	var out := {}
	for piece in s.split(")"):
		var p := piece.strip_edges()
		if p.begins_with(","):
			p = p.substr(1).strip_edges()
		var open := p.find("(")
		if open <= 0:
			continue
		var key := p.substr(0, open).strip_edges()
		var value := p.substr(open + 1).strip_edges()
		if value.is_valid_int():
			out[key] = value.to_int()
		elif value.is_valid_float():
			out[key] = value.to_float()
		else:
			out[key] = value
	return out
