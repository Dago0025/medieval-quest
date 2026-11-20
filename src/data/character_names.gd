class_name CharacterNames
extends RefCounted
## Nomi dei personaggi per fazione da data/nomi_personaggi.cfg (ADR-079): set dedicati agli Auror (richiesta di Federico
## del 16/11/2026: non piu' i nomi scandinavi dei Danesi) e alle fazioni nuove della mappa del mondo. Si applicano al
## modello del file dei nomi dell'installazione (HeroesData) dopo la lettura: le liste si aggiungono in fondo e si
## associano alla fazione come farebbero SET_FORENAMES, SET_SURNAMES, SET_PRINCESS e SET_REBELS.

const FILE := "res://data/nomi_personaggi.cfg"

static var _cfg: ConfigFile = null


static func _ensure() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if _cfg.load(FILE) != OK:
			push_warning("Nomi dei personaggi non leggibili: %s" % FILE)
	return _cfg


## Per i test: rilegge il file alla prossima chiamata.
static func reset() -> void:
	_cfg = null


## Fazioni con un set di nomi valido nella modalita' indicata.
static func factions(auror_mode: bool) -> PackedStringArray:
	var out := PackedStringArray()
	var cfg := _ensure()
	for s in cfg.get_sections():
		if bool(cfg.get_value(s, "solo_auror", false)) and not auror_mode:
			continue
		out.append(s.strip_edges().to_upper())
	return out


## Applica i set di nomi a `data`. `auror_mode`: le sezioni con `solo_auror` valgono solo in modalita' Auror.
static func apply(data: HeroesData, auror_mode: bool) -> void:
	if data == null:
		return
	var cfg := _ensure()
	for s in cfg.get_sections():
		if bool(cfg.get_value(s, "solo_auror", false)) and not auror_mode:
			continue
		var fid := s.strip_edges().to_upper()
		var n := data.names_for(fid)
		var forenames := _strings(cfg.get_value(s, "nomi", []))
		if not forenames.is_empty():
			data.forename_lists.append(forenames)
			n.forename_list = data.forename_lists.size()
			n.royal_count = clampi(int(cfg.get_value(s, "reali", forenames.size())), 1, forenames.size())
		var surnames := _strings(cfg.get_value(s, "cognomi", []))
		if not surnames.is_empty():
			data.surname_lists.append(surnames)
			n.surname_list = data.surname_lists.size()
		var princesses := _strings(cfg.get_value(s, "principesse", []))
		if not princesses.is_empty():
			data.princess_lists.append(princesses)
			n.princess_list = data.princess_lists.size()
		for region in _strings(cfg.get_value(s, "regioni_ribelli", [])):
			data.add_rebels(region, n.forename_list, n.surname_list)
		if bool(cfg.get_value(s, "togli_eroi", false)):
			var kept: Array[HeroesData.FamousHero] = []
			for h in data.heroes:
				if h.faction != fid:
					kept.append(h)
			data.heroes = kept
			data.declared_heroes.erase(fid)


static func _strings(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v is Array or v is PackedStringArray:
		for x in v:
			var t := str(x).strip_edges()
			if t != "":
				out.append(t)
	return out
