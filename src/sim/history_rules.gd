class_name HistoryRules
extends RefCounted
## Limiti storici della campagna (ADR-114, richiesta di Federico del 21/11/2026), letti da data/regole/storia.cfg:
## invenzioni che sbloccano edifici e unita' (polvere da sparo, bussola), popoli senza cavalli prima dell'arrivo degli
## europei, guardia a cavallo del capo. I valori predefiniti sono quelli del file, cosi' `Rules.new()` si comporta come il
## gioco (tranne la guardia, spenta senza file); senza eventi storici nelle regole (mondi di prova) le invenzioni non
## limitano nulla.

const DEFAULT_PATH := "res://data/regole/storia.cfg"

## Invenzione (colonna 26 degli edifici, in maiuscolo) -> chiave dell'evento storico che la porta (in maiuscolo).
var inventions := {"GUNPOWDER": "POLVERE_DA_SPARO", "COMPASS": "BUSSOLA"}
## Fazioni che ignorano le invenzioni (`armi_da_fuoco_subito` di auror.cfg: gli Auror). Vuoto nello scenario storico.
var invention_free := PackedStringArray(["FN_DANISH"])

## Popoli senza cavalli prima dell'arrivo degli europei.
var horseless_factions := PackedStringArray(["FN_AZTECS", "FN_INCA", "FN_MISSISSIPPIANS", "FN_MAYA", "FN_PUEBLO"])
## Regioni delle Americhe: l'arrivo e' il primo anno in cui una fazione fuori da `horseless_factions` ne possiede una.
var americas := PackedStringArray()

## Guardia del capo (cavalleria; a piedi per i popoli senza cavalli). Spenta in `Rules.new()` (mondi di prova con eserciti
## contati pila per pila), accesa da storia.cfg nel gioco.
var guard_enabled := false
var guard_roles := PackedStringArray(["capo"])

var errors := PackedStringArray()


static func load_file(path: String = DEFAULT_PATH, auror_path: String = "") -> HistoryRules:
	var r := HistoryRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Limiti storici non letti da %s (errore %d): uso i valori predefiniti" % [path, err])
	else:
		if cfg.has_section("invenzioni"):
			r.inventions = {}
			for key in cfg.get_section_keys("invenzioni"):
				var v: Variant = cfg.get_value("invenzioni", key, "")
				if typeof(v) != TYPE_STRING:
					r.errors.append("invenzioni/%s non e' un testo" % key)
					continue
				r.inventions[str(key).strip_edges().to_upper()] = str(v).strip_edges().to_upper()
		r.horseless_factions = _upper_list(cfg, "cavalli", "fazioni", r.horseless_factions, r.errors)
		r.americas = _upper_list(cfg, "cavalli", "regioni", r.americas, r.errors)
		if cfg.has_section_key("guardia", "attiva"):
			r.guard_enabled = bool(cfg.get_value("guardia", "attiva", r.guard_enabled))
		var roles := _upper_list(cfg, "guardia", "ruoli", r.guard_roles, r.errors)
		r.guard_roles = PackedStringArray()
		for role in roles:
			r.guard_roles.append(role.to_lower())
	if auror_path != "":
		r._read_auror(auror_path)
	return r


## `armi_da_fuoco_subito` delle sezioni FN_* di auror.cfg: quelle fazioni non aspettano le invenzioni.
func _read_auror(auror_path: String) -> void:
	if not FileAccess.file_exists(auror_path):
		return
	var cfg := ConfigFile.new()
	if cfg.load(auror_path) != OK:
		errors.append("Regole degli Auror non lette da %s" % auror_path)
		return
	var free := PackedStringArray()
	for section in cfg.get_sections():
		if section.begins_with("FN_") and cfg.get_value(section, "armi_da_fuoco_subito", false) == true:
			free.append(section.to_upper())
	invention_free = free


func ignores_inventions(faction_id: String) -> bool:
	return invention_free.has(faction_id.strip_edges().to_upper())


func is_horseless(faction_id: String) -> bool:
	return horseless_factions.has(faction_id.strip_edges().to_upper())


func is_americas(region_id: String) -> bool:
	return americas.has(region_id.strip_edges().to_upper())


func guard_for_role(role: String) -> bool:
	return guard_enabled and guard_roles.has(role.strip_edges().to_lower())


func to_dict() -> Dictionary:
	return {
		"inventions": inventions.duplicate(),
		"invention_free": Array(invention_free),
		"horseless_factions": Array(horseless_factions),
		"americas": Array(americas),
		"guard_enabled": guard_enabled,
		"guard_roles": Array(guard_roles),
	}


static func _upper_list(cfg: ConfigFile, section: String, key: String, fallback: PackedStringArray, errs: PackedStringArray) -> PackedStringArray:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, [])
	if typeof(v) != TYPE_ARRAY:
		errs.append("%s/%s non e' un elenco: uso il valore predefinito" % [section, key])
		return fallback
	var out := PackedStringArray()
	for item in v:
		out.append(str(item).strip_edges().to_upper())
	return out
