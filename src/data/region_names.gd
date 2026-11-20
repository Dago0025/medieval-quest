class_name RegionNames
extends RefCounted
## Nomi italiani delle regioni (fase 8, scelta di Federico), da data/province.cfg: valgono per l'interfaccia e per i testi
## degli eventi. Gli id e i nomi letti dallo startpos non cambiano; senza voce nella tabella resta il nome dei dati.

const TABLE := "res://data/province.cfg"
const OFFICES := "res://data/cariche.cfg"

static var _loaded := false
static var _names := {}
static var _ranks := {}
static var _offices := {}
static var _places := {}


static func reset() -> void:
	_loaded = false
	_names.clear()
	_ranks.clear()
	_offices.clear()
	_places.clear()


## Nome italiano della regione, "" se la tabella non la conosce. In inglese la tabella data/lingue/en/province.cfg, che ha
## solo le zone di mare: per le province vale il nome dei dati della XL.
static func italian(region_id: String) -> String:
	_ensure()
	return str(_names.get(region_id.to_upper(), ""))


## Titolo di un governatore in italiano: «Duke of Scotland» -> «Duca di Scozia» (rango dalla sezione [ranghi], regione dal
## nome dei dati ricondotto al nome italiano). Un titolo che non segue lo schema resta com'e'.
static func translate_title(campaign: CampaignData, text: String) -> String:
	if Lang.is_english():
		return text   # in inglese il titolo dei dati com'e' («Duke of Scotland»)
	_ensure()
	var cut := text.find(" of ")
	var rank_key := text.substr(0, cut).replace(" ", "_") if cut >= 0 else ""
	if cut < 0 or not _ranks.has(rank_key):
		return text
	var rank: String = _ranks[rank_key]
	var place := text.substr(cut + 4)
	if campaign != null:
		for r in campaign.regions:
			if r.display_name == place or r.id.trim_prefix("ID_").replace("_", " ").to_lower() == place.to_lower():
				var it := italian(r.id)
				if it != "":
					place = it
				break
	var prep := _preposition(place)
	return "%s %s%s%s" % [rank, prep, "" if prep.ends_with("'") else " ", place]


## Carica di corte in italiano: «Archbishop of Lund» -> «Arcivescovo di Lund», «Admiral of the Fleet» -> «Ammiraglio della
## Flotta» (data/cariche.cfg); senza luogo si traduce la sola carica. Le parti sconosciute restano come sono.
static func translate_office(campaign: CampaignData, text: String) -> String:
	if Lang.is_english():
		return text   # in inglese la carica dei dati com'e' («Archbishop of Lund»)
	_ensure()
	var cut := text.findn(" of ")
	var base := text if cut < 0 else text.substr(0, cut)
	var base_it := str(_offices.get(_key(base), base))
	if cut < 0:
		return base_it
	var place := text.substr(cut + 4)
	if _places.has(_key(place)):
		return "%s %s" % [base_it, _places[_key(place)]]
	var region_place := place
	if campaign != null:
		for r in campaign.regions:
			if r.display_name == place or r.id.trim_prefix("ID_").replace("_", " ").to_lower() == place.to_lower():
				var it := italian(r.id)
				if it != "":
					region_place = it
				break
	var prep := _preposition(region_place)
	return "%s %s%s%s" % [base_it, prep, "" if prep.ends_with("'") else " ", region_place]


## Nome mostrato: quello italiano della tabella, poi quello dei dati, poi l'id (in inglese il nome dei dati).
static func shown(campaign: CampaignData, region_id: String) -> String:
	var it := italian(region_id)
	if it != "":
		return it
	var r: CampaignData.Region = campaign.region(region_id) if campaign != null else null
	if r != null and r.display_name != "":
		return r.display_name
	return region_id


## Chiave della tabella: spazi -> _, senza apostrofi.
static func _key(text: String) -> String:
	return text.replace("'", "").replace("’", "").replace(" ", "_")


## «di» oppure «d'» davanti a una vocale.
static func _preposition(place: String) -> String:
	var first := place.substr(0, 1).to_lower()
	return "d'" if first in ["a", "e", "i", "o", "u", "î"] else "di"


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(Lang.data_path(TABLE)) != OK:
		return
	for section in ["terra", "mare"]:
		if cfg.has_section(section):
			for k in cfg.get_section_keys(section):
				_names[k.to_upper()] = str(cfg.get_value(section, k))
	if cfg.has_section("ranghi"):
		for k in cfg.get_section_keys("ranghi"):
			_ranks[k] = str(cfg.get_value("ranghi", k))
	var offices := ConfigFile.new()
	if offices.load(OFFICES) == OK:
		for pair in [["cariche", _offices], ["luoghi", _places]]:
			var section: String = pair[0]
			var dict: Dictionary = pair[1]
			if offices.has_section(section):
				for k in offices.get_section_keys(section):
					dict[k] = str(offices.get_value(section, k))
		# ADR-068: nello scenario storico le voci di [luoghi_storico] sostituiscono quelle di [luoghi]; vuota = voce tolta
		# («Chancellor of Denmark» torna «Cancelliere di Danimarca» invece che «degli Auror»)
		if not Scenario.auror and offices.has_section("luoghi_storico"):
			for k in offices.get_section_keys("luoghi_storico"):
				var v := str(offices.get_value("luoghi_storico", k))
				if v == "":
					_places.erase(k)
				else:
					_places[k] = v
