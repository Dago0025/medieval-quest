class_name ItalianTexts
extends RefCounted
## Testi lunghi propri del remake (dal 18/11/2026 riscritti, non piu' traduzioni dell'originale): eventi storici, messaggi
## dei disastri, varianti della peste, popoli ribelli, descrizioni delle unita'. Stanno in `res://data/testi/<lingua>/*.cfg`
## (it, en) e si scelgono con la lingua del gioco (Lang). Il nome della classe resta per compatibilita'.
const FOLDER := "res://data/testi"
const KNOWN_FILES := ["descrizioni_unita.cfg", "eventi.cfg"]

static var _cfg: ConfigFile = null


static func reset() -> void:
	_cfg = null


## Tabella esplicita (test); null torna ai file del progetto.
static func use_table(cfg: ConfigFile) -> void:
	_cfg = cfg


## Testo tradotto, "" se manca.
static func text(section: String, key: String) -> String:
	_ensure()
	return str(_cfg.get_value(section, key, ""))


static func array(section: String, key: String) -> PackedStringArray:
	_ensure()
	var v: Variant = _cfg.get_value(section, key, [])
	return PackedStringArray(v) if v is Array else PackedStringArray()


## Chiavi di una sezione (vuoto se manca).
static func keys(section: String) -> PackedStringArray:
	_ensure()
	return _cfg.get_section_keys(section) if _cfg.has_section(section) else PackedStringArray()


static func is_available() -> bool:
	_ensure()
	return not _cfg.get_sections().is_empty()


static func _ensure() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	var dir := FOLDER.path_join("en" if Lang.is_english() else "it")
	var files := DirAccess.get_files_at(dir)
	if files.is_empty():
		files = PackedStringArray(KNOWN_FILES)   # gioco esportato senza elenco delle cartelle: i file noti
	files.sort()
	for f in files:
		if f.get_extension().to_lower() != "cfg":
			continue
		var part := ConfigFile.new()
		if part.load(dir.path_join(f)) != OK:
			push_warning("Testi non leggibili: %s" % dir.path_join(f))
			continue
		for section in part.get_sections():
			for key in part.get_section_keys(section):
				_cfg.set_value(section, key, part.get_value(section, key))
