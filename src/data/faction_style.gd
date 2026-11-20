class_name FactionStyle
extends RefCounted
## Come appaiono le fazioni nel remake (fase 8): nomi italiani, nome con l'articolo, colori e stemmi che sostituiscono quelli
## dello startpos, da data/fazioni.cfg. Gli id dei dati non cambiano (FN_DANISH resta FN_DANISH): la fazione del giocatore si
## chiama Auror per scelta di Federico. Senza voce nella tabella il nome viene dall'id («FN_ALPHA» -> «Alpha»).

const TABLE := "res://data/fazioni.cfg"

static var _loaded := false
static var _names := {}
static var _full := {}
static var _colors := {}
static var _shields := {}
static var _banners := {}
static var _articles := {}    ## id -> articolo («gli», «il», «l'», «la Repubblica di»; in inglese «the»)
static var _plural := {}      ## id -> vero se il nome e' plurale (dagli articoli italiani, vale in ogni lingua)
static var _svg_cache := {}
static var _portraits := {}   ## id -> immagine del ritratto proprio del capo
static var _portrait_numerals := {}   ## id -> numerale del re a cui spetta (0 = ogni capo)


static func reset() -> void:
	_loaded = false
	_names.clear()
	_full.clear()
	_colors.clear()
	_shields.clear()
	_banners.clear()
	_articles.clear()
	_plural.clear()
	_svg_cache.clear()
	_portraits.clear()
	_portrait_numerals.clear()


## Nome della fazione («Auror», «Inglesi», «ribelli»).
static func name_of(faction_id: String) -> String:
	_ensure()
	var key := faction_id.to_upper()
	if _names.has(key):
		return str(_names[key])
	return key.trim_prefix("FN_").replace("_", " ").capitalize()


## Nome con l'articolo per titoli e barra («Gli Auror»); senza voce, il nome semplice.
static func full_name_of(faction_id: String) -> String:
	_ensure()
	return str(_full.get(faction_id.to_upper(), name_of(faction_id)))


## Articolo della fazione nei testi («gli» per gli Inglesi, «il» per il Sacro Romano Impero), "" senza voce.
static func article(faction_id: String) -> String:
	_ensure()
	return str(_articles.get(faction_id.to_upper(), ""))


## Vero se il nome della fazione e' plurale (articolo i, gli, le): il verbo si accorda al plurale.
static func is_plural(faction_id: String) -> bool:
	_ensure()
	return bool(_plural.get(faction_id.to_upper(), false))


## Nome con l'articolo minuscolo («gli Inglesi», «l'Orda d'Oro»); senza articolo, il nome.
static func with_article(faction_id: String) -> String:
	var a := article(faction_id)
	var n := name_of(faction_id)
	if a == "":
		return n
	return a + n if a.ends_with("'") else "%s %s" % [a, n]


## Colore dello stendardo delle pedine (data/fazioni.cfg [stendardi]); `fallback` (il primario) se non c'e'.
static func banner_color(faction_id: String, fallback: Color) -> Color:
	_ensure()
	var v := str(_banners.get(faction_id.to_upper(), ""))
	return Color(v) if v != "" else fallback


## Stemma disegnato dal remake (percorso res:// di un SVG), "" se si usa quello dell'originale.
## Immagine del ritratto proprio del capo della fazione ("" se non ne ha): `numeral` = numerale del re (1 per «Darkos I»);
## se la tabella fissa un numerale il ritratto spetta solo a quel re.
static func leader_portrait(faction_id: String, numeral: int) -> String:
	_ensure()
	var key := faction_id.to_upper()
	var path := str(_portraits.get(key, ""))
	if path == "":
		return ""
	var wanted := int(_portrait_numerals.get(key, 0))
	return path if wanted <= 0 or wanted == numeral else ""


static func shield_svg(faction_id: String) -> String:
	_ensure()
	return str(_shields.get(faction_id.to_upper(), ""))


## Stemma (SVG o immagine importata) reso alle dimensioni chieste (in memoria per dimensione), o null.
static func shield_image(faction_id: String, size: Vector2i) -> Image:
	var path := shield_svg(faction_id)
	if path == "":
		return null
	var key := "%s|%d|%d" % [path, size.x, size.y]
	if _svg_cache.has(key):
		return _svg_cache[key]
	var img: Image = null
	if not path.to_lower().ends_with(".svg"):
		# stemma dipinto (PNG importato, come auror.png ricavato da un'immagine generata): si riduce alla misura chiesta
		var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
		if tex != null:
			img = tex.get_image()
			if img != null:
				img = img.duplicate()
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_RGBA8)
				img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		_svg_cache[key] = img
		return img
	var text := FileAccess.get_file_as_string(path)
	if text != "":
		img = Image.new()
		var native_h := 240.0
		if img.load_svg_from_string(text, float(size.y) / native_h) != OK:
			img = null
		elif img.get_size() != size:
			img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	_svg_cache[key] = img
	return img


## Colori della tabella al posto di quelli dello startpos (SetFactionCol), sulle fazioni della campagna caricata.
static func apply_overrides(campaign: CampaignData) -> void:
	_ensure()
	if campaign == null:
		return
	for f in campaign.factions:
		var c: Array = _colors.get(f.id.to_upper(), [])
		if c.size() >= 2:
			f.color_primary = Color(str(c[0]))
			f.color_secondary = Color(str(c[1]))


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(TABLE) != OK:
		return
	for pair in [["nomi", _names], ["nomi_estesi", _full], ["colori", _colors], ["stemmi", _shields], ["stendardi", _banners], ["articoli", _articles],
			["ritratti", _portraits], ["ritratti_numerale", _portrait_numerals]]:
		var section: String = pair[0]
		var dict: Dictionary = pair[1]
		if not cfg.has_section(section):
			continue
		for k in cfg.get_section_keys(section):
			dict[k.to_upper()] = cfg.get_value(section, k)
	_apply_scenario(cfg, ["nomi", "nomi_estesi", "colori", "stemmi", "stendardi", "articoli", "ritratti", "ritratti_numerale"])
	for k in _articles:
		_plural[k] = str(_articles[k]).get_slice(" ", 0) in ["i", "gli", "le"]
	# in inglese (ADR-066) nomi, nomi estesi e articoli di data/lingue/en/fazioni.cfg al posto di quelli italiani
	if Lang.is_english():
		var en := ConfigFile.new()
		if en.load(Lang.data_path(TABLE)) == OK:
			for pair in [["nomi", _names], ["nomi_estesi", _full], ["articoli", _articles]]:
				var dict: Dictionary = pair[1]
				dict.clear()
				if en.has_section(pair[0]):
					for k in en.get_section_keys(pair[0]):
						dict[k.to_upper()] = en.get_value(pair[0], k)
			_apply_scenario(en, ["nomi", "nomi_estesi", "articoli"])


## Scenario storico (ADR-068): le sezioni `<nome>_storico` della tabella sostituiscono le voci di `<nome>` (FN_DANISH torna
## ai Danesi dell'originale); un valore vuoto toglie la voce (niente ritratto di Darkos I). In modalita' Auror non cambia nulla.
static func _apply_scenario(cfg: ConfigFile, sections: Array) -> void:
	if Scenario.auror:
		return
	var dicts := {"nomi": _names, "nomi_estesi": _full, "colori": _colors, "stemmi": _shields, "stendardi": _banners,
		"articoli": _articles, "ritratti": _portraits, "ritratti_numerale": _portrait_numerals}
	for section in sections:
		var over: String = section + "_storico"
		if not cfg.has_section(over):
			continue
		var dict: Dictionary = dicts[section]
		for k in cfg.get_section_keys(over):
			var v: Variant = cfg.get_value(over, k)
			if typeof(v) == TYPE_STRING and str(v) == "":
				dict.erase(k.to_upper())
			else:
				dict[k.to_upper()] = v
