class_name UiIcons
extends RefCounted
## Icone dell'interfaccia originale (fase 8): merci, giacimenti, religioni e attributi dei personaggi, dalla tabella
## data/ui/icone.cfg (nome dei dati -> immagine del gioco) e da AssetLibrary. Le icone sono piccole (18x20): si mostrano a una
## volta e mezza con UiTheme.picture. Senza immagine si ripiega sul testo.

const TABLE := "res://data/ui/icone.cfg"
const ICON_SIZE := Vector2(27, 30)
const SMALL_SIZE := Vector2(20, 22)

static var _table := {}     ## sezione -> {nome in maiuscolo -> percorso}


static func reset() -> void:
	_table.clear()


## Percorso dell'immagine del gioco per `name` nella sezione ("merci", "risorse", "religioni", "attributi"), "" se manca.
static func path_for(section: String, name: String) -> String:
	_ensure()
	var rows: Dictionary = _table.get(section, {})
	return str(rows.get(name.to_upper(), ""))


static func texture(section: String, name: String) -> Texture2D:
	var p := path_for(section, name)
	if p == "" or not AssetLibrary.is_available():
		return null
	return AssetLibrary.texture(p)


## Icona con suggerimento; se l'immagine manca, un'etichetta con il testo `fallback`.
static func icon(section: String, name: String, tooltip: String, size: Vector2 = ICON_SIZE, fallback: String = "") -> Control:
	var tex := texture(section, name)
	if tex == null:
		var l := Label.new()
		l.text = fallback if fallback != "" else tooltip
		l.tooltip_text = tooltip
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		return l
	var r := UiTheme.picture(tex, size)
	r.tooltip_text = tooltip
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


## Nome leggibile (sezione «nomi_<sezione>» della tabella), o il nome dei dati con l'iniziale maiuscola.
static func label_for(section: String, name: String) -> String:
	var l := path_for("nomi_" + section, name)
	return l if l != "" else name.capitalize()


## Riga di icone (con a capo) per un elenco di nomi dei dati, ciascuna con il nome leggibile nel suggerimento.
static func icon_flow(section: String, names: PackedStringArray) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 2)
	for n in names:
		var label := label_for(section, n)
		flow.add_child(icon(section, n, label, ICON_SIZE, label))
	return flow


## Attributo con icona e valore accanto ("acume 8" -> penna e 8); il nome per esteso nel suggerimento.
static func attribute(attr: String, value: int, tooltip: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.tooltip_text = "%s: %d" % [tooltip, value]
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var tex := texture("attributi", attr)
	if tex != null:
		box.add_child(UiTheme.picture(tex, SMALL_SIZE))
	var l := Label.new()
	l.text = str(value) if tex != null else "%s %d" % [tooltip, value]
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return box


## Stelle di comando di un generale (stella dell'originale ripetuta; oltre 5 una stella e il numero).
static func stars(count: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.tooltip_text = Lang.t("Comando: %d %s") % [count, Lang.t("stella") if count == 1 else Lang.t("stelle")]
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var tex := texture("attributi", "star")
	if tex == null or count > 5:
		if tex != null:
			box.add_child(UiTheme.picture(tex, Vector2(18, 18)))
		var l := Label.new()
		l.text = str(count) if tex != null else (Lang.t("%d stelle") % count)
		box.add_child(l)
		return box
	for i in count:
		box.add_child(UiTheme.picture(tex, Vector2(18, 18)))
	return box


static func _ensure() -> void:
	if not _table.is_empty():
		return
	var cfg := ConfigFile.new()
	if cfg.load(TABLE) != OK:
		return
	for section in cfg.get_sections():
		var rows := {}
		for k in cfg.get_section_keys(section):
			rows[k.to_upper()] = str(cfg.get_value(section, k))
		_table[section] = rows
