class_name UnitTexts
extends RefCounted
## Nomi e descrizioni delle unita' dall'installazione (fase 8b): `Loc/<lingua>/names.txt` («Spearmen_Plural») e
## `Descriptions.txt` («Spearmen_desc»). Come per gli eventi (ADR-007) i testi si leggono a ogni avvio e non entrano nel
## repository; senza installazione i nomi ripiegano sull'id e la descrizione resta vuota.

const ITALIAN_TABLE := "res://data/nomi_unita.cfg"   ## nomi italiani (fase 8d): hanno la precedenza sull'installazione
const NAMES_FILE := "names.txt"
const DESCRIPTIONS_FILE := "Descriptions.txt"

static var _italian: ConfigFile = null
static var _names: LocLoader.LocTable = null
static var _descriptions: LocLoader.LocTable = null


static func reset() -> void:
	_italian = null
	_names = null
	_descriptions = null


## Tabelle esplicite (test).
static func use_tables(names: LocLoader.LocTable, descriptions: LocLoader.LocTable) -> void:
	_names = names
	_descriptions = descriptions


## Nome plurale dell'unita': quello italiano della tabella («Cavalieri feudali»), poi quello dell'installazione, "" se manca.
## In inglese (ADR-066): data/lingue/en/nomi_unita.cfg per le unita' che l'originale non ha, poi names.txt inglese (_INGLESE).
static func plural_name(unit_id: String) -> String:
	var own := AurorUnits.text(unit_id, "nome")   # ADR-074: unita' esclusive degli Auror, testi in data/unita_auror.cfg
	if own != "":
		return own
	var it := _italian_name("nomi", unit_id)
	if it != "":
		return it
	return _names.find_text("%s_Plural" % unit_id, "").strip_edges() if _names != null else ""


static func singular_name(unit_id: String) -> String:
	var own := AurorUnits.text(unit_id, "singolare")
	if own != "":
		return own
	var it := _italian_name("singolari", unit_id)
	if it != "":
		return it
	return _names.find_text("%s_Singular" % unit_id, "").strip_edges() if _names != null else ""


## Voce della tabella italiana senza distinguere maiuscole, "" se manca.
static func _italian_name(section: String, unit_id: String) -> String:
	if _italian == null:
		_italian = ConfigFile.new()
		_italian.load(Lang.data_path(ITALIAN_TABLE))   # in inglese data/lingue/en/nomi_unita.cfg
	if not _italian.has_section(section):
		return ""
	if _italian.has_section_key(section, unit_id):
		return str(_italian.get_value(section, unit_id))
	var low := unit_id.to_lower()
	for k in _italian.get_section_keys(section):
		if k.to_lower() == low:
			return str(_italian.get_value(section, k))
	return ""


## Descrizione dell'originale, "" se manca.
static func description(unit_id: String) -> String:
	var own := AurorUnits.text(unit_id, "descrizione")
	if own != "":
		return own
	var it := ItalianTexts.text("descrizioni_unita", unit_id)   # testi propri (data/testi/<lingua>), 18/11/2026
	if it == "":
		for k in ItalianTexts.keys("descrizioni_unita"):
			if k.to_lower() == unit_id.to_lower():
				it = ItalianTexts.text("descrizioni_unita", k)
				break
	if it != "" or _descriptions == null:
		return it
	return _descriptions.find_text("%s_desc" % unit_id, "").strip_edges()


## Dal 18/11/2026 nomi e descrizioni non si leggono piu' dai file dell'originale: nomi in data/nomi_unita.cfg e
## data/lingue/en/nomi_unita.cfg, descrizioni in data/testi/<lingua>. Le tabelle Loc restano solo per i test (use_tables).
