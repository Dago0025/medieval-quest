class_name BuildingProdLoader
extends RefCounted
## Legge il file prod degli edifici (MTW_XL_EARLY_BUILD_PROD13.TXT).
##
## TSV a 28 colonne, stesso formato del file unità (vedi UnitProdLoader, da cui
## prende il lettore TSV e quello delle condizioni). Una riga = una famiglia;
## la colonna 0 è il numero di upgrade (livelli = n + 1).
##
## Valori per livello: liste separate da virgola fuori dalle graffe. Regole:
## - una virgola finale in più è ignorata (MERCHANT);
## - un solo valore per più livelli vale per tutti (risorsa di METALSMITH e
##   delle miniere: ipotesi, il file non lo dice);
## - un valore in meno del necessario lascia il livello vuoto;
## - più valori dei livelli sono un errore.

const COL_LEVELS := 0
const COL_ID := 1
const COL_LABEL := 2
const COL_TYPE := 3
const COL_COST := 4
const COL_TIME := 5
const COL_REQUIRES := 6
const COL_AI_PREFS := 9
const COL_AI_INFLUENCE := 10
const COL_FRONTIER := 11
const COL_RELIGION := 14
const COL_UPGRADES := 16
const COL_TECH := 17
const COL_RESOURCES := 18
const COL_FACTIONS := 19
const COL_GLORY := 20
const COL_FAITH := 21
const COL_INCOME := 22
const COL_HAPPINESS := 23
const COL_MERCENARY := 24
const COL_MERC_HUB := 25
const COL_INVENTIONS := 26
const COL_CAPACITY := 27


## Tabella delle famiglie lette da un file.
class BuildingTable:
	var column_names := PackedStringArray()
	var families: Array[BuildingType] = []
	var errors := PackedStringArray()
	var _by_id := {}
	var _by_token := {}

	func add(b: BuildingType) -> void:
		if _by_id.has(b.id):
			errors.append("Famiglia dichiarata due volte: %s" % b.id)
			return
		families.append(b)
		_by_id[b.id] = b
		for lv in b.levels:
			_by_token[lv.token] = lv

	func has_family(family_id: String) -> bool:
		return _by_id.has(family_id.strip_edges().to_upper())

	func get_family(family_id: String) -> BuildingType:
		return _by_id.get(family_id.strip_edges().to_upper())

	func level_total() -> int:
		var n := 0
		for b in families:
			n += b.levels.size()
		return n

	## Livello a partire dal token (CASTLE7). Accetta anche NOME1 per il livello 1
	## (le unità usano per esempio SHIPYARD1). Null se sconosciuto.
	func resolve(token: String) -> BuildingType.Level:
		var key := token.strip_edges().to_upper()
		if _by_token.has(key):
			return _by_token[key]
		var parts := BuildingProdLoader.split_token(key)
		var fam: BuildingType = get_family(String(parts["family"]))
		if fam == null:
			return null
		return fam.get_level(int(parts["level"]))


## `overrides` (scenario storico, ADR-068): famiglia in maiuscolo -> {colonna: valore} da rimettere prima di leggerla.
static func load_file(path: String, overrides: Dictionary = {}) -> BuildingTable:
	return load_text(TextIO.read_latin1(path), overrides)


static func load_text(text: String, overrides: Dictionary = {}) -> BuildingTable:
	var table := BuildingTable.new()
	var rows := UnitProdLoader.parse_tsv(text)
	var start := UnitProdLoader.data_start(rows)
	if start < 0:
		table.errors.append("Marcatore DATA START non trovato")
		return table
	if start > 0:
		table.column_names = rows[0]
	var index := 0
	for r in range(start, rows.size()):
		var fields := rows[r]
		if not overrides.is_empty():
			var key := UnitProdLoader.cell(fields, COL_ID).to_upper()
			if overrides.has(key):
				fields = ScenarioFilter.patch_row(fields, overrides[key])
		var b := _build_family(fields, index, table)
		index += 1
		if b != null:
			table.add(b)
	return table


## "CASTLE10" -> {family: "CASTLE", level: 10}; "SHIPYARD" e "SHIPYARD1" -> livello 1.
static func split_token(token: String) -> Dictionary:
	var t := token.strip_edges().to_upper()
	var i := t.length()
	while i > 0 and t.substr(i - 1, 1).is_valid_int():
		i -= 1
	var level := 1
	if i < t.length():
		level = t.substr(i).to_int()
	return {"family": t.substr(0, i), "level": level}


static func _build_family(f: PackedStringArray, index: int, table: BuildingTable) -> BuildingType:
	var family_id := UnitProdLoader.cell(f, COL_ID).to_upper()
	if family_id.is_empty():
		table.errors.append("Voce %d: nome vuoto" % index)
		return null
	var upgrades_text := UnitProdLoader.cell(f, COL_LEVELS)
	if not upgrades_text.is_valid_int() or upgrades_text.to_int() < 0:
		table.errors.append("%s: numero di upgrade non valido: %s" % [family_id, upgrades_text])
		return null
	var count := upgrades_text.to_int() + 1
	var b := BuildingType.new(family_id)
	b.index = index
	b.raw = f
	b.types = UnitProdLoader.split_list(UnitProdLoader.cell(f, COL_TYPE))
	b.frontier = UnitProdLoader.cell(f, COL_FRONTIER).to_upper() == "YES"
	b.religions = UnitProdLoader.split_list(UnitProdLoader.cell(f, COL_RELIGION))
	b.mercenary_hub = UnitProdLoader.cell(f, COL_MERC_HUB).to_upper() == "YES"
	var labels := _levels(f, COL_LABEL, count, family_id, table)
	var costs := _levels(f, COL_COST, count, family_id, table)
	var times := _levels(f, COL_TIME, count, family_id, table)
	var conds := _levels(f, COL_REQUIRES, count, family_id, table)
	var ups := _levels(f, COL_UPGRADES, count, family_id, table)
	var techs := _levels(f, COL_TECH, count, family_id, table)
	var ress := _levels(f, COL_RESOURCES, count, family_id, table)
	var facs := _levels(f, COL_FACTIONS, count, family_id, table)
	var glories := _levels(f, COL_GLORY, count, family_id, table)
	var faiths := _levels(f, COL_FAITH, count, family_id, table)
	var incomes := _levels(f, COL_INCOME, count, family_id, table)
	var happys := _levels(f, COL_HAPPINESS, count, family_id, table)
	var mercs := _levels(f, COL_MERCENARY, count, family_id, table)
	var invs := _levels(f, COL_INVENTIONS, count, family_id, table)
	var caps := _levels(f, COL_CAPACITY, count, family_id, table)
	var weight_groups := UnitProdLoader.parse_weight_groups(UnitProdLoader.cell(f, COL_AI_PREFS))
	var influence_groups := parse_influence_groups(UnitProdLoader.cell(f, COL_AI_INFLUENCE))
	for i in count:
		var lv := BuildingType.Level.new()
		lv.family = family_id
		lv.level = i + 1
		lv.token = b.token(i + 1)
		lv.label = labels[i]
		lv.cost = _int(costs[i], family_id, "costo", table)
		lv.build_time = _int(times[i], family_id, "tempo", table)
		lv.requires = UnitProdLoader.parse_condition(conds[i])
		lv.upgrades = UnitProdLoader.unbrace_list(ups[i])
		lv.tech_level = _int(techs[i], family_id, "tech level", table)
		lv.resources = UnitProdLoader.unbrace_list(ress[i])
		lv.factions = UnitProdLoader.unbrace_list(facs[i])
		lv.glory_goals = UnitProdLoader.unbrace_list(glories[i])
		if not faiths[i].is_empty():
			lv.faith = faiths[i].to_float()
		lv.income = _int(incomes[i], family_id, "rendita", table)
		lv.happiness = _int(happys[i], family_id, "felicità", table)
		lv.mercenary_magnetism = _int(mercs[i], family_id, "magnetismo", table)
		for inv in UnitProdLoader.unbrace_list(invs[i]):
			if inv != "NONE":
				lv.inventions.append(inv)
		lv.capacity = _int(caps[i], family_id, "capacità", table)
		lv.ai_weights = _group_for_level(weight_groups, i, count)
		lv.ai_influences = _influences_for_level(influence_groups, i, count)
		b.levels.append(lv)
	return b


## Gruppo di pesi del livello `i`: un solo gruppo vale per tutti i livelli, altrimenti uno per livello (i gruppi in piu' si
## ignorano, quelli in meno lasciano il livello senza pesi).
static func _group_for_level(groups: Array[Dictionary], i: int, count: int) -> Dictionary:
	if groups.size() == 1 and count > 1:
		return groups[0]
	if i < groups.size():
		return groups[i]
	return {}


static func _influences_for_level(groups: Array, i: int, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var chosen: Array = []
	if groups.size() == 1 and count > 1:
		chosen = groups[0]
	elif i < groups.size():
		chosen = groups[i]
	for item in chosen:
		out.append(item)
	return out


## Influenze della colonna 10: `{A(50),B2(100)},{},{C(10)}` -> un elenco per gruppo di primo livello (uno per livello
## dell'edificio). Ogni voce {"token", "family", "level", "bonus"}. Le voci si leggono per forma NOME(numero), quindi anche
## quelle senza virgola tra loro (nel file reale: `HORSE_BREEDER3(100)ARMOURER(200)`). Senza graffe il testo e' un solo gruppo.
static func parse_influence_groups(text: String) -> Array:
	var groups: Array = []
	var raw_groups: Array[String] = []
	var depth := 0
	var start := -1
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch == "{":
			if depth == 0:
				start = i + 1
			depth += 1
		elif ch == "}" and depth > 0:
			depth -= 1
			if depth == 0 and start >= 0:
				raw_groups.append(text.substr(start, i - start))
				start = -1
	if raw_groups.is_empty() and not text.strip_edges().is_empty():
		raw_groups.append(text)
	var re := RegEx.new()
	re.compile("([A-Za-z_][A-Za-z_0-9]*)\\s*\\(\\s*(-?[0-9]*\\.?[0-9]+)\\s*\\)")
	for raw in raw_groups:
		var entries: Array[Dictionary] = []
		for m in re.search_all(raw):
			var token := m.get_string(1).to_upper()
			var parts := split_token(token)
			entries.append({"token": token, "family": str(parts["family"]), "level": int(parts["level"]), "bonus": m.get_string(2).to_float()})
		groups.append(entries)
	return groups


static func _int(s: String, family_id: String, what: String, table: BuildingTable) -> int:
	var t := s.strip_edges()
	if t.is_empty():
		return 0
	if not t.is_valid_int():
		table.errors.append("%s: %s non intero: %s" % [family_id, what, t])
		return 0
	return t.to_int()


## Valori per livello di una colonna: sempre esattamente `count` voci.
static func _levels(f: PackedStringArray, col: int, count: int, family_id: String, table: BuildingTable) -> PackedStringArray:
	var text := UnitProdLoader.cell(f, col)
	var parts := PackedStringArray()
	if not text.is_empty():
		parts = UnitProdLoader.split_top(text)
	if parts.size() == count + 1 and parts[count].is_empty():
		parts.remove_at(count)
	if parts.size() == 1 and count > 1:
		var one := parts[0]
		for i in range(1, count):
			parts.append(one)
	if parts.size() > count:
		table.errors.append("%s: colonna %d ha %d valori per %d livelli" % [family_id, col, parts.size(), count])
		parts.resize(count)
	while parts.size() < count:
		parts.append("")
	return parts
