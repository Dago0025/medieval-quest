class_name CultureUnits
extends RefCounted
## Unita' proprie delle fazioni nuove della mappa del mondo (ADR-116, richiesta di Federico del 21/11/2026), descritte in
## `data/unita_mondo.cfg`: Giapponesi, Cinesi, Aztechi, Inca, Kanem, Cahokia, Coreani, Mongoli, Chola e Khmer. Come per
## le unita' degli Auror (AurorUnits) ogni unita' nasce dalla riga del suo `modello` nel prod (corpo, cavalcatura, arma,
## classi, pesi dell'IA) con sopra i valori del file: costo, mantenimento, uomini, statistiche, morale, epoche, edifici
## richiesti, fazioni, regioni dei mercenari, unita' del capo. Si aggiungono solo con la mappa del mondo (Scenario).
## Finche' non hanno immagini proprie mostrano la carta del modello (o di `carta`).

const FILE := "res://data/unita_mondo.cfg"

static var _cfg: ConfigFile = null
static var _lower := {}   # id in minuscolo -> sezione


static func reset() -> void:
	_cfg = null
	_lower.clear()


## File esplicito (test); null torna a quello del progetto.
static func use_config(cfg: ConfigFile) -> void:
	_cfg = cfg
	_lower.clear()


static func _ensure() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if FileAccess.file_exists(FILE) and _cfg.load(FILE) != OK:
			push_warning("Unita' delle fazioni nuove non lette da %s" % FILE)
	if _lower.is_empty():
		for s in _cfg.get_sections():
			_lower[s.to_lower()] = s
	return _cfg


## Id delle unita' del file, nell'ordine.
static func ids() -> PackedStringArray:
	return _ensure().get_sections()


## Sezione del file per l'id (senza distinguere maiuscole), "" se non c'e'.
static func _section(unit_id: String) -> String:
	_ensure()
	return str(_lower.get(unit_id.strip_edges().to_lower(), ""))


static func is_culture_unit(unit_id: String) -> bool:
	return _section(unit_id) != ""


static func value(unit_id: String, key: String, fallback: Variant = null) -> Variant:
	var s := _section(unit_id)
	return fallback if s == "" else _ensure().get_value(s, key, fallback)


## Fazioni che arruolano l'unita' (vuoto per i soli mercenari).
static func factions_of(unit_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in value(unit_id, "fazioni", []):
		out.append(str(f).strip_edges().to_upper())
	return out


## Fazioni che hanno unita' proprie nel file.
static func factions_with_units() -> PackedStringArray:
	var out := PackedStringArray()
	for s in ids():
		for f in factions_of(s):
			if not out.has(f):
				out.append(f)
	return out


## Unita' da cui prendere carta e scheda finche' l'unita' non ha immagini proprie: `carta`, altrimenti il modello.
static func card_model(unit_id: String) -> String:
	var s := _section(unit_id)
	if s == "":
		return ""
	return str(_ensure().get_value(s, "carta", _ensure().get_value(s, "modello", "")))


## Nome plurale, singolare o descrizione nella lingua corrente ("" se l'unita' non e' del file).
static func text(unit_id: String, key: String) -> String:
	var s := _section(unit_id)
	if s == "":
		return ""
	var cfg := _ensure()
	if Lang.is_english() and cfg.has_section_key(s, key + "_en"):
		return str(cfg.get_value(s, key + "_en"))
	return str(cfg.get_value(s, key, ""))


## Aggiunge le unita' alla tabella (dopo le altre). Un modello che manca e' un errore della tabella.
static func append_to(table: UnitProdLoader.UnitTable) -> void:
	var cfg := _ensure()
	var index := table.units.size()
	for s in ids():
		if table.has_unit(s):
			continue
		var model := table.get_unit(str(cfg.get_value(s, "modello", "")))
		if model == null:
			table.errors.append("Unita' delle fazioni nuove %s: modello %s non trovato" % [s, cfg.get_value(s, "modello", "")])
			continue
		var u := UnitProdLoader.build_row(row_for(s, model.raw), index, table)
		if u == null:
			continue
		if cfg.has_section_key(s, "peso_ia"):
			# un solo peso per tutti i profili (colonna 14): con il rumore dell'IA le unita' di pari peso si alternano e gli
			# eserciti escono misti, invece di riempirsi dell'unita' col peso piu' alto nel modello
			var w := float(cfg.get_value(s, "peso_ia"))
			var weights := {}
			for k in (model.ai_weights if not model.ai_weights.is_empty() else _reference_weights(table)):
				weights[k] = w
			u.ai_weights = weights
		table.add(u)
		index += 1
	table._faction_cache.clear()


## Startpos del mondo: le unita' dell'originale nelle regioni delle fazioni nuove (le guarnigioni dello startpos del
## mondo, come i lancieri coreani in Cina) diventano l'unita' propria che le elenca in `sostituisce_nello_startpos`, tra
## quelle della fazione proprietaria. Restituisce quante unita' ha cambiato.
static func replace_start_units(data: CampaignData) -> int:
	var swaps := {}   # "FAZIONE|unita' in minuscolo" -> unita' propria
	for s in ids():
		for old in _ensure().get_value(s, "sostituisce_nello_startpos", []):
			for f in factions_of(s):
				swaps["%s|%s" % [f, str(old).strip_edges().to_lower()]] = s
	var count := 0
	if swaps.is_empty():
		return count
	for su in data.start_units:
		var r := data.region(su.region)
		if r == null:
			continue
		var key := "%s|%s" % [r.owner, su.unit_type.strip_edges().to_lower()]
		if swaps.has(key):
			su.unit_type = swaps[key]
			count += 1
	return count


## Profili dell'IA di un'unita' comune (i lancieri), per i modelli senza pesi.
static func _reference_weights(table: UnitProdLoader.UnitTable) -> Dictionary:
	var ref := table.get_unit("Spearmen")
	return ref.ai_weights if ref != null else {}


## Riga del prod per la sezione `s`, dalla riga del modello.
static func row_for(s: String, model_row: PackedStringArray) -> PackedStringArray:
	var cfg := _ensure()
	var factions := ", ".join(factions_of(s))
	var guard := bool(cfg.get_value(s, "guardia", false))
	var periods := PackedStringArray(cfg.get_value(s, "epoche", [UnitType.ALL_PERIODS]))
	var cells := {
		UnitProdLoader.COL_NAME: s,
		UnitProdLoader.COL_COST: str(int(cfg.get_value(s, "costo", 0))),
		UnitProdLoader.COL_SUPPORT: str(int(cfg.get_value(s, "mantenimento", 0))),
		10: "",                                   # niente unita' ribelli fuori dalle loro terre
		UnitProdLoader.COL_RULER: "",
		UnitProdLoader.COL_REGION_ADV: "",
		UnitProdLoader.COL_PERIODS: ", ".join(periods),
		UnitProdLoader.COL_LEADER_OF: factions if guard else "",
		UnitProdLoader.COL_FACTIONS: factions,
		UnitProdLoader.COL_REGIONS: ", ".join(PackedStringArray(cfg.get_value(s, "regioni", []))),
		UnitProdLoader.COL_CULTURES: "",          # le culture del modello (BombardCrew cattolica) non valgono qui
		UnitProdLoader.COL_MERCENARY: "YES" if bool(cfg.get_value(s, "mercenario", false)) else "",
		51: factions,
	}
	if guard:
		cells[UnitProdLoader.COL_GENERAL] = "PREFERRED"
	if cfg.has_section_key(s, "requisiti"):
		cells[UnitProdLoader.COL_REQUIRES] = str(cfg.get_value(s, "requisiti"))
	if cfg.has_section_key(s, "uomini"):
		cells[UnitProdLoader.COL_MEN] = str(int(cfg.get_value(s, "uomini")))
	if cfg.has_section_key(s, "morale"):
		cells[UnitProdLoader.COL_MORAL] = str(int(cfg.get_value(s, "morale")))
	cells[UnitProdLoader.COL_STATS] = _stats(UnitProdLoader.cell(model_row, UnitProdLoader.COL_STATS), s)
	return ScenarioFilter.patch_row(model_row, cells)


## Colonna 21 del modello con carica, mischia, difesa e armatura della sezione.
static func _stats(text: String, s: String) -> String:
	var cfg := _ensure()
	var out := text
	for pair in [["CHARGE_BONUS", "carica"], ["MELEE_BONUS", "mischia"], ["DEFENCE_BONUS", "difesa"], ["ARMOUR_LEVEL", "armatura"]]:
		if not cfg.has_section_key(s, pair[1]):
			continue
		var rx := RegEx.create_from_string("%s\\(\\s*-?[0-9.]+\\s*\\)" % pair[0])
		var repl := "%s( %d )" % [pair[0], int(cfg.get_value(s, pair[1]))]
		if rx.search(out) != null:
			out = rx.sub(out, repl)
		else:
			out += ", " + repl
	return out
