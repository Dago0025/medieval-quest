class_name UiTheme
extends RefCounted
## Tema dell'interfaccia (fase 8): pergamene e cornici dell'originale (AssetLibrary, ADR-007), caratteri liberi scelti da
## Federico (Fondamento per titoli, sezioni e pulsanti, Alegreya per il testo, licenza OFL in assets/fonts) e colori d'inchiostro. Costruito a codice per
## tenere in un posto solo colori, margini e stati dei controlli. Se l'esportazione delle immagini manca, gli stessi controlli
## usano stili disegnati (StyleBoxFlat) con gli stessi colori: l'interfaccia resta leggibile.
##
## Varianti (theme_type_variation): "Title" e "Subtitle" (Label, Fondamento), "MapLabel" (Label sopra la mappa: chiaro con
## contorno), "TopBar" (PanelContainer: striscia di pergamena), "Section" (Button piatto per le intestazioni richiudibili),
## "Card" (PanelContainer della carta di un'unita'), "Tile" (Button di pergamena con immagine e didascalia).
## I pulsanti comuni sono rosso scuro con testo bianco (richiesta di Federico del 2026-11-09).

## Nome del gioco (scelto da Federico l'11/11/2026). Il nome del progetto in project.godot resta «MTW Remake»: da quello
## dipende la cartella dei dati dell'utente (salvataggi, impostazioni), che cambiando nome andrebbe persa.
const GAME_NAME := "Medieval Quest"
const FONT_TITLE := "res://assets/fonts/Fondamento-Regular.ttf"
const FONT_TEXT := "res://assets/fonts/Alegreya-VF.ttf"
const SHARPEN_SHADER := "res://src/ui/sharpen.gdshader"
## La nitidezza vale solo per le immagini piccole dell'originale (carte 50x50, ritratti 96x142): sulle immagini rifatte,
## grandi e gia' nitide, il filtro scuriva le figure (segnalazione di Federico del 15/11 sulla scheda delle unita').
const SHARPEN_MAX_SOURCE := 160

## Inchiostri sulla pergamena.
const INK := Color("2e2013")
const INK_FAINT := Color("6b5638")
const INK_TITLE := Color("5c1a10")
const INK_BAD := Color("9a1f12")
const INK_GOOD := Color("2f5d23")
const INK_BLUE := Color("1f3f6b")
## Carta e cuoio.
const PAPER := Color("efe4c8")
const PAPER_LIGHT := Color("f6efdc")
const PAPER_DARK := Color("d8c7a0")
const LEATHER := Color("6b4a2a")
const PANEL_BORDER := Color("8a6a3f")     ## bordo dei pannelli: cuoio chiaro, si sposa con la pietra e i pulsanti rossi
const PANEL_RADIUS := 12
const FRAME_EDGE := 16                    ## margine della cornice a nove parti (tools/genera_pannello.py: MARGIN)
const FRAME_PADDING := 8                  ## spazio in piu' tra la cornice e il contenuto rispetto al pannello piatto
## Pulsanti (richiesta di Federico: piu' contrasto): rosso scuro con testo bianco. Contrasto del testo bianco sul fondo
## normale 11,9:1, al passaggio del mouse 9,1:1, sul premuto 15:1 (WCAG AA chiede 4,5:1).
const BUTTON_BG := Color("6e1410")
const BUTTON_BG_HOVER := Color("8c1d16")
const BUTTON_BG_PRESSED := Color("4f0d0a")
const BUTTON_BG_DISABLED := Color("7a5a52")
const BUTTON_BORDER := Color("2e0806")
const BUTTON_BORDER_HOVER := Color("d9b45a")
const BUTTON_TEXT := Color("ffffff")
const BUTTON_TEXT_DISABLED := Color("e4d6cf")
## Testo sopra la mappa.
const MAP_TEXT := Color("f4ead2")
const MAP_OUTLINE := Color("1b120a")

const TEXT_SIZE := 17
const TITLE_SIZE := 24
const SUBTITLE_SIZE := 18
const BUTTON_SIZE := 15

## Immagini dell'originale (percorsi del gioco). Dal 2026-11-10 i pannelli non usano piu' la pergamena (PANEL_PARCHMENT,
## BAR_PARCHMENT, DIVIDER restano per chi le vuole riprendere con _texture_box).
const PANEL_PARCHMENT := "frontend_files/wide_parchment_crop.BIF"     ## 600x560, bordi bruciati
const BAR_PARCHMENT := "campmap/TOOLTIP_BACK.BIF"                     ## 200x65, striscia
const DIVIDER := "campmap/parchments/divider region info.BIF"         ## fregio tra le sezioni
const FRAME := "frontend_files/mappic border.BIF"                     ## cornice di pietra per le immagini


## Tema completo. `use_assets` = false forza gli stili disegnati (test, o esportazione assente).
static func build(use_assets: bool = true) -> Theme:
	var t := Theme.new()
	var text_font := _font(FONT_TEXT, 500)
	var title_font := _font(FONT_TITLE, 0)
	if text_font != null:
		t.default_font = text_font
	t.default_font_size = TEXT_SIZE
	var assets := use_assets and AssetLibrary.is_available()

	# testo
	t.set_color("font_color", "Label", INK)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_type_variation("Title", "Label")
	t.set_color("font_color", "Title", INK_TITLE)
	t.set_font_size("font_size", "Title", TITLE_SIZE)
	t.set_type_variation("Subtitle", "Label")
	t.set_color("font_color", "Subtitle", INK_TITLE)
	t.set_font_size("font_size", "Subtitle", SUBTITLE_SIZE)
	if title_font != null:
		t.set_font("font", "Title", title_font)
		t.set_font("font", "Subtitle", title_font)
	t.set_type_variation("MapLabel", "Label")
	t.set_color("font_color", "MapLabel", MAP_TEXT)
	t.set_color("font_outline_color", "MapLabel", MAP_OUTLINE)
	t.set_constant("outline_size", "MapLabel", 5)

	# pannelli (richiesta di Federico, 2026-11-10): niente pergamena bruciata, un pannello color carta ben rifinito, con gli
	# angoli stondati, un bordo di cuoio e un'ombra morbida sulla mappa
	var panel := _panel_box(PANEL_RADIUS, 18)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_type_variation("TopBar", "PanelContainer")
	t.set_stylebox("panel", "TopBar", _panel_box(8, 8))
	var sep_line := StyleBoxLine.new()
	sep_line.color = Color(LEATHER, 0.35)
	sep_line.thickness = 1
	sep_line.grow_begin = -4
	sep_line.grow_end = -4
	t.set_stylebox("separator", "HSeparator", sep_line)
	t.set_constant("separation", "HSeparator", 14)
	t.set_type_variation("Card", "PanelContainer")
	var card := _flat(PAPER_DARK, LEATHER, 1, 2, 2)
	t.set_stylebox("panel", "Card", card)

	# pulsanti: rosso scuro e testo bianco (anche le tendine, che sono pulsanti)
	for type_name in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type_name, _flat(BUTTON_BG, BUTTON_BORDER, 1, 3, 8, 4))
		t.set_stylebox("hover", type_name, _flat(BUTTON_BG_HOVER, BUTTON_BORDER_HOVER, 1, 3, 8, 4))
		t.set_stylebox("pressed", type_name, _flat(BUTTON_BG_PRESSED, BUTTON_BORDER_HOVER, 1, 3, 8, 4))
		t.set_stylebox("hover_pressed", type_name, _flat(BUTTON_BG_PRESSED, BUTTON_BORDER_HOVER, 1, 3, 8, 4))
		t.set_stylebox("disabled", type_name, _flat(BUTTON_BG_DISABLED, BUTTON_BORDER, 1, 3, 8, 4))
		t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(color_name, type_name, BUTTON_TEXT)
		t.set_color("font_disabled_color", type_name, BUTTON_TEXT_DISABLED)
		t.set_color("icon_normal_color", type_name, BUTTON_TEXT)
		t.set_color("icon_hover_color", type_name, BUTTON_TEXT)
		t.set_color("icon_pressed_color", type_name, BUTTON_TEXT)
		t.set_font_size("font_size", type_name, BUTTON_SIZE)
		if title_font != null:
			t.set_font("font", type_name, title_font)
	# tessere con un'immagine (edifici e unita' nella finestra della provincia): restano di pergamena, perche' la
	# didascalia sotto l'immagine e' un'etichetta d'inchiostro
	t.set_type_variation("Tile", "Button")
	t.set_stylebox("normal", "Tile", _flat(PAPER_LIGHT, LEATHER, 1, 3, 6, 3))
	t.set_stylebox("hover", "Tile", _flat(Color("fbf6e8"), INK_TITLE, 2, 3, 6, 3))
	t.set_stylebox("pressed", "Tile", _flat(PAPER_DARK, INK_TITLE, 2, 3, 6, 3))
	t.set_stylebox("hover_pressed", "Tile", _flat(PAPER_DARK, INK_TITLE, 2, 3, 6, 3))
	t.set_stylebox("disabled", "Tile", _flat(Color("e3d8bd"), Color("a89272"), 1, 3, 6, 3))
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(color_name, "Tile", INK)
	t.set_type_variation("Section", "Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "Section", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2, 2))
	t.set_stylebox("hover_pressed", "Section", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2, 2))
	t.set_color("font_color", "Section", INK_TITLE)
	t.set_color("font_hover_color", "Section", INK_BAD)
	t.set_color("font_pressed_color", "Section", INK_BAD)
	t.set_color("font_hover_pressed_color", "Section", INK_BAD)
	t.set_color("font_focus_color", "Section", INK_TITLE)
	t.set_color("font_disabled_color", "Section", INK_FAINT)
	t.set_font_size("font_size", "Section", SUBTITLE_SIZE)

	# caselle
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK_TITLE)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())

	# menu a tendina, suggerimenti, separatori, barre di scorrimento
	t.set_stylebox("panel", "PopupMenu", _flat(PAPER, LEATHER, 1, 2, 6))
	t.set_stylebox("hover", "PopupMenu", _flat(PAPER_DARK, PAPER_DARK, 0, 0, 2))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK_TITLE)
	t.set_stylebox("panel", "TooltipPanel", _flat(PAPER_LIGHT, LEATHER, 1, 2, 8))
	t.set_color("font_color", "TooltipLabel", INK)
	var line := StyleBoxLine.new()
	line.color = Color(LEATHER, 0.55)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 10)
	var grabber := _flat(Color(LEATHER, 0.7), Color(LEATHER, 0.7), 0, 3, 0)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", _flat(INK_TITLE, INK_TITLE, 0, 3, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _flat(INK_TITLE, INK_TITLE, 0, 3, 0))
	var track := _flat(Color(LEATHER, 0.12), Color(LEATHER, 0.12), 0, 3, 0)
	track.content_margin_left = 4
	track.content_margin_right = 4
	t.set_stylebox("scroll", "VScrollBar", track)

	# elenchi (scelta della fazione, salvataggi) e campi di testo
	t.set_stylebox("panel", "ItemList", _flat(Color(PAPER_LIGHT, 0.85), LEATHER, 1, 3, 6))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", _flat(Color(0.86, 0.74, 0.42, 0.55), Color(0.72, 0.53, 0.12), 1, 2, 2))
	t.set_stylebox("selected_focus", "ItemList", _flat(Color(0.86, 0.74, 0.42, 0.55), Color(0.72, 0.53, 0.12), 1, 2, 2))
	t.set_stylebox("hovered", "ItemList", _flat(Color(PAPER_DARK, 0.6), Color(0, 0, 0, 0), 0, 2, 2))
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", INK_TITLE)
	t.set_color("font_hovered_color", "ItemList", INK_TITLE)
	t.set_color("guide_color", "ItemList", Color(LEATHER, 0.18))
	t.set_constant("v_separation", "ItemList", 6)
	# schede (finestra della provincia)
	t.set_stylebox("panel", "TabContainer", _flat(Color(PAPER_LIGHT, 0.9), LEATHER, 1, 3, 8))
	t.set_stylebox("tab_selected", "TabContainer", _flat(PAPER_LIGHT, LEATHER, 1, 3, 10, 4))
	t.set_stylebox("tab_unselected", "TabContainer", _flat(Color(PAPER_DARK, 0.85), Color(LEATHER, 0.6), 1, 3, 10, 4))
	t.set_stylebox("tab_hovered", "TabContainer", _flat(Color(PAPER_LIGHT, 0.8), LEATHER, 1, 3, 10, 4))
	t.set_color("font_selected_color", "TabContainer", INK_TITLE)
	t.set_color("font_unselected_color", "TabContainer", INK)
	t.set_color("font_hovered_color", "TabContainer", INK_TITLE)
	t.set_stylebox("normal", "LineEdit", _flat(PAPER_LIGHT, LEATHER, 1, 3, 6, 3))
	t.set_stylebox("focus", "LineEdit", _flat(Color("fbf6e8"), INK_TITLE, 1, 3, 6, 3))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", INK_TITLE)
	t.set_color("selection_color", "LineEdit", Color(0.86, 0.74, 0.42, 0.6))
	return t


## Applica il tema a tutta l'applicazione: lo fonde nel tema predefinito di Godot, che vale anche per i controlli sotto un
## CanvasLayer e per le finestre a comparsa (menu a tendina, suggerimenti). Si puo' chiamare piu' volte.
static func install(use_assets: bool = true) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.title = GAME_NAME   # titolo della finestra
	var t := build(use_assets)
	var target := ThemeDB.get_default_theme()
	target.merge_with(t)
	if t.default_font != null:
		target.default_font = t.default_font
		ThemeDB.fallback_font = t.default_font
	target.default_font_size = t.default_font_size
	ThemeDB.fallback_font_size = t.default_font_size


static var _bold: Font = null


## Carattere del testo in grassetto (Alegreya, asse wght 760): nomi delle tessere e numeri delle carte.
static func bold_font() -> Font:
	if _bold == null:
		_bold = _font(FONT_TEXT, 760)
	return _bold


static var _italic: Font = null


## Corsivo del testo: Alegreya inclinato (il progetto non ha il file corsivo), per le frasi dell'originale nei resoconti.
static func italic_font() -> Font:
	if _italic == null:
		var base := _font(FONT_TEXT, 500)
		if base == null:
			return null
		var v := FontVariation.new()
		v.base_font = base
		v.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
		_italic = v
	return _italic


static var _crisp: Font = null
static var _crisp_cache := {}
static var _crisp_theme: Theme = null

## Alegreya a peso fisso (500 e 760) senza contorni sovrapposti, ricavati dal carattere variabile con fontTools
## (instancer, OverlapMode.REMOVE): il campo di distanza del carattere variabile lasciava puntini accanto alle lettere.
const FONT_TEXT_CRISP := "res://assets/fonts/Alegreya-500-nitido.ttf"
const FONT_BOLD_CRISP := "res://assets/fonts/Alegreya-760-nitido.ttf"
## Fondamento senza contorni sovrapposti (fontTools removeOverlaps), con un altro nome interno come chiede la sua licenza
## OFL per le versioni modificate: col campo di distanza l'originale lasciava macchie su alcune lettere (g, a finale).
const FONT_TITLE_CRISP := "res://assets/fonts/Titoli-nitido.ttf"


## Carattere a campo di distanza a piu' canali (MSDF) per le parti scalate dell'interfaccia: la barra in basso cresce con
## la finestra (a 1920x1080 e' scalata 1,8 volte) e i caratteri normali, disegnati alla loro misura e poi ingranditi col
## nodo, uscivano sgranati (segnalazione di Federico dell'11/11/2026). Il campo di distanza resta definito a ogni scala e
## in ogni posizione. Provato e scartato il sovracampionamento per carattere: nitido solo a certe scale.
static func crisp_font(path: String) -> Font:
	if _crisp_cache.has(path):
		return _crisp_cache[path]
	var base := load(path) as FontFile
	if base == null:
		return null
	var msdf := base.duplicate() as FontFile
	msdf.multichannel_signed_distance_field = true
	msdf.msdf_pixel_range = 8
	msdf.msdf_size = 48
	_crisp_cache[path] = msdf
	return msdf


## Grassetto del testo, nitido a ogni scala (per le parti scalate dell'interfaccia).
static func crisp_text_bold() -> Font:
	return crisp_font(FONT_BOLD_CRISP)


## Tema da dare alla radice di una parte scalata dell'interfaccia (barra in basso): stessi caratteri del tema generale,
## in versione nitida. Tutto il resto (colori, misure, riquadri) viene dal tema generale.
static func crisp_theme() -> Theme:
	if _crisp_theme != null:
		return _crisp_theme
	var t := Theme.new()
	var text := crisp_font(FONT_TEXT_CRISP)
	var title := crisp_font(FONT_TITLE_CRISP)
	if text != null:
		t.default_font = text
	if title != null:
		for type_name in ["Button", "Title", "Subtitle"]:
			t.set_font("font", type_name, title)
	_crisp_theme = t
	return _crisp_theme


## Grassetto nitido anche quando l'interfaccia e' scalata (la barra in basso cresce con la finestra): campo di distanza a piu'
## canali (MSDF), che resta definito a ogni ingrandimento, con margine per il contorno. Per i numeri delle truppe sulle carte.
static func crisp_bold_font() -> Font:
	if _crisp != null:
		return _crisp
	var base := load(FONT_TEXT) as FontFile
	if base == null:
		return null
	var msdf := base.duplicate() as FontFile
	msdf.multichannel_signed_distance_field = true
	msdf.msdf_pixel_range = 14
	msdf.msdf_size = 48
	var v := FontVariation.new()
	v.base_font = msdf
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	_crisp = v
	return _crisp


## Separatore tra due sezioni: una linea sottile color cuoio (il fregio dell'originale stava male sul pannello rifinito e
## nei pannelli stretti si sovrapponeva al testo; richiesta di Federico del 2026-11-10).
## Riquadro dei messaggi brevi in alto sulla mappa (richiesta di Federico del 2026-11-13): stessa cornice di menu e
## finestre, angoli stondati, margini piu' stretti perche' di solito e' una riga sola.
static func toast_box() -> StyleBox:
	var box := _panel_box(10, 8)
	if box is StyleBoxTexture:
		box.content_margin_left = FRAME_EDGE + 10
		box.content_margin_right = FRAME_EDGE + 10
		box.content_margin_top = FRAME_EDGE - 2
		box.content_margin_bottom = FRAME_EDGE - 2
	return box


static func divider() -> Control:
	var sep := HSeparator.new()
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


## Immagine piccola dell'originale mostrata piu' grande: filtro lineare e nitidezza (sharpen.gdshader), cosi' i ritratti e le
## carte 50x50 restano leggibili a 1,5-2 volte senza un ingrandimento preparato a mano.
static func picture(tex: Texture2D, size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = size
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # le immagini rifatte sono piu' grandi del riquadro
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null and size.x > float(tex.get_width()) * 1.2 and wants_sharpen(tex):
		var shader := load(SHARPEN_SHADER) as Shader
		if shader != null:
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter("strength", 0.6)
			r.material = m
	return r


## Vero per le immagini piccole dell'originale, che la nitidezza aiuta; falso per quelle rifatte (vedi SHARPEN_MAX_SOURCE).
static func wants_sharpen(tex: Texture2D) -> bool:
	return tex != null and maxi(tex.get_width(), tex.get_height()) <= SHARPEN_MAX_SOURCE


## Ritratto di un personaggio con la cornice comune (richiesta di Federico dell'11/11: i ritratti nuovi, dipinti, non
## hanno la cornice di pietra dentro l'immagine): l'immagine riempie il riquadro e sopra si disegna, a codice e quindi
## nitida a ogni misura, una cornice sottile d'ottone tra due fili scuri con una borchia per angolo. Vale per tutti i
## ritratti: a quelli dell'originale `PortraitArt.portrait` toglie prima la cornice di pietra.
const PORTRAIT_BRASS := Color("d9b354")
const PORTRAIT_BRASS_DARK := Color("8a6a2a")
const PORTRAIT_INK := Color("120b06")
static func portrait(tex: Texture2D, size: Vector2) -> Control:
	var holder := Control.new()
	holder.name = "Ritratto"
	holder.custom_minimum_size = size
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := picture(tex, size)
	pic.name = "Immagine"
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(pic)
	var frame := Control.new()
	frame.name = "Cornice"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(func() -> void: draw_portrait_frame(frame))
	holder.add_child(frame)
	return holder


static func portrait_frame_width(size: Vector2) -> float:
	return clampf(roundf(size.x * 0.03), 2.0, 6.0)


static func draw_portrait_frame(c: Control) -> void:
	var s := c.size
	var w := portrait_frame_width(s)
	c.draw_rect(Rect2(0.5, 0.5, s.x - 1.0, s.y - 1.0), PORTRAIT_INK, false, 1.0)                            # filo scuro esterno
	c.draw_rect(Rect2(1.0 + w / 2.0, 1.0 + w / 2.0, s.x - 2.0 - w, s.y - 2.0 - w), PORTRAIT_BRASS_DARK, false, w)  # ottone
	c.draw_rect(Rect2(1.5, 1.5, s.x - 3.0, s.y - 3.0), PORTRAIT_BRASS, false, 1.0)                           # luce sul bordo
	c.draw_rect(Rect2(1.5 + w, 1.5 + w, s.x - 3.0 - 2.0 * w, s.y - 3.0 - 2.0 * w), PORTRAIT_INK, false, 1.0)  # filo scuro interno
	var k := 1.0 + w / 2.0
	var corners: Array[Vector2] = [Vector2(k, k), Vector2(s.x - k, k), Vector2(k, s.y - k), Vector2(s.x - k, s.y - k)]
	for corner in corners:
		c.draw_circle(corner, maxf(1.0, w * 0.42), PORTRAIT_BRASS)


## Scudo della fazione come immagine (vuota se manca l'esportazione).
static func shield(faction_id: String, size: Vector2 = Vector2(34, 40)) -> TextureRect:
	var r := picture(AssetLibrary.faction_shield(faction_id, size.y > 24.0), size)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # lo stemma proprio e' piu' grande del riquadro
	return r


# --- interni ------------------------------------------------------------------------------------------------------


## Carattere del progetto; `weight` > 0 sceglie il peso di un carattere variabile (asse wght).
static func _font(path: String, weight: int) -> Font:
	var base := load(path) as FontFile
	if base == null:
		return null
	if weight <= 0:
		return base
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return v


## Pannello rifinito: carta, bordo di cuoio di 2 pixel con angoli stondati, ombra morbida.
## Pannello di menu e finestre. Con la veste nuova (ADR-028, scelta di Federico dell'11/11) e' la cornice a nove parti di
## `assets/ui/veste/pannello.png`: legno, filo d'ottone, borchie e grana leggera di pergamena, angoli stondati (centro e
## bordi si ripetono senza giunte; si rigenera con tools/genera_pannello.py). Senza la veste nuova, o se l'immagine
## manca, resta il pannello color carta di ADR-023.
static func _panel_box(radius: int, margin: int) -> StyleBox:
	var frame := OriginalHud.skin_texture("pannello") if OriginalHud.veste_nuova else null
	if frame != null:
		var box := StyleBoxTexture.new()
		box.texture = frame
		box.set_texture_margin_all(FRAME_EDGE)
		box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		box.set_content_margin_all(margin + FRAME_PADDING)
		return box
	var s := _flat(PAPER, PANEL_BORDER, 2, radius, margin)
	s.border_blend = false
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	return s


static func _flat(bg: Color, border: Color, border_width: int, radius: int, margin: int, margin_v: int = -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin if margin_v < 0 else margin_v
	s.content_margin_bottom = margin if margin_v < 0 else margin_v
	return s


## Pergamena a nove parti: i bordi (`edge` pixel dell'immagine) non si deformano, il centro si ripete. Con `clean_top` si toglie
## il nastro del titolo dal bordo alto (altrimenti nei pannelli larghi si ripeterebbe): vedi `without_ribbon`.
static func _texture_box(original: String, edge: int, content: int, clean_top: bool = false) -> StyleBoxTexture:
	var tex := AssetLibrary.texture(original)
	if tex == null:
		return null
	if clean_top:
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		tex = ImageTexture.create_from_image(without_ribbon(img, edge + 16))
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = edge
	s.texture_margin_right = edge
	s.texture_margin_top = edge
	s.texture_margin_bottom = edge
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.content_margin_left = content
	s.content_margin_right = content
	s.content_margin_top = content
	s.content_margin_bottom = content
	return s


## Bordo alto senza il nastro del titolo: tra gli angoli, le prime `band` righe si rifanno con il bordo basso capovolto
## (anch'esso bruciato), sfumando nelle ultime righe per non lasciare una cucitura.
static func without_ribbon(img: Image, band: int) -> Image:
	var out := img.duplicate() as Image
	var w := img.get_width()
	var h := img.get_height()
	var corner := mini(90, w / 4)
	var fade := 10
	var side := 30   # sfumatura verso gli angoli, che restano quelli originali
	for y in band:
		var t := clampf(float(band - 1 - y) / float(fade), 0.0, 1.0)   # 1 = tutto dal basso, verso 0 nelle ultime righe
		for x in range(corner, w - corner):
			var tx := clampf(float(x - corner) / float(side), 0.0, 1.0) * clampf(float(w - corner - x) / float(side), 0.0, 1.0)
			var below := img.get_pixel(x, h - 1 - y)
			var here := img.get_pixel(x, y)
			out.set_pixel(x, y, here.lerp(below, t * tx))
	return out


## Casella disegnata a codice: quadrato d'inchiostro, con una croce se spuntata.
static func _check_icon(checked: bool) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in n:
		for w in 2:
			img.set_pixel(i, w, LEATHER)
			img.set_pixel(i, n - 1 - w, LEATHER)
			img.set_pixel(w, i, LEATHER)
			img.set_pixel(n - 1 - w, i, LEATHER)
	for x in range(2, n - 2):
		for y in range(2, n - 2):
			img.set_pixel(x, y, PAPER_LIGHT)
	if checked:
		for i in range(4, n - 4):
			for d in [-1, 0, 1]:
				img.set_pixel(clampi(i + d, 0, n - 1), i, INK_TITLE)
				img.set_pixel(clampi(n - 1 - i + d, 0, n - 1), i, INK_TITLE)
	return ImageTexture.create_from_image(img)
