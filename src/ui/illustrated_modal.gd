class_name IllustratedModal
extends PanelContainer
## Finestra con l'immagine come sfondo (richiesta di Federico del 2026-11-20: «tutti gli eventi con l'immagine come sfondo
## della modale»). Dentro la cornice dei pannelli: l'immagine copre tutta la superficie (ritagliata al centro), una sfumatura
## scura in alto regge la categoria e il titolo in chiaro, in basso una piastra di pergamena semitrasparente contiene il resto
## (`body`, inchiostri soliti). Senza immagine resta un fondo di cuoio scuro, cosi' i testi chiari si leggono comunque.
## La usano gli eventi storici, gli avvisi (CampaignUiAlerts), le notizie, i prigionieri e le proposte.

const RATIO := 9.0 / 16.0
const CATEGORY_GOOD := Color("a9d98f")
const CATEGORY_BAD := Color("ffab94")
const CATEGORY_NONE := Color("ecd29a")
const TITLE_COLOR := Color("f6ecd2")
const PLATE_ALPHA := 0.9
const FRAME_INSET := 12                   ## spessore visibile della cornice (tools/genera_pannello.py: FRAME)

var body: VBoxContainer
var _stage: MarginContainer
var _backdrop: ColorRect
var _picture: TextureRect
var _shade: TextureRect
var _category: Label
var _title: Label
var _width := 760.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", frame_box())
	_stage = MarginContainer.new()
	_stage.clip_contents = true
	for side in ["left", "right", "top", "bottom"]:
		_stage.add_theme_constant_override("margin_" + side, 0)
	add_child(_stage)
	_backdrop = ColorRect.new()
	_backdrop.color = Color("2a1d12")
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_backdrop)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_picture)
	_shade = TextureRect.new()
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.texture = shade_texture()
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_shade)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 18)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(column)
	_category = Label.new()
	_category.add_theme_font_size_override("font_size", 15)
	_category.add_theme_color_override("font_outline_color", UiTheme.MAP_OUTLINE)
	_category.add_theme_constant_override("outline_size", 5)
	column.add_child(_category)
	_title = Label.new()
	_title.theme_type_variation = "Title"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_title.add_theme_color_override("font_outline_color", UiTheme.MAP_OUTLINE)
	_title.add_theme_constant_override("outline_size", 7)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	column.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 24)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", plate_box())
	column.add_child(plate)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	plate.add_child(body)
	set_width(_width)


## Larghezza della finestra: l'immagine resta in 16:9 (l'altezza cresce solo se il testo non ci sta).
func set_width(width: float) -> void:
	_width = width
	_stage.custom_minimum_size = Vector2(width, roundf(width * RATIO))
	reset_size()


func get_width() -> float:
	return _width


## Immagine di sfondo (null = fondo di cuoio).
func set_picture(tex: Texture2D) -> void:
	_picture.texture = tex
	_picture.visible = tex != null


func has_picture() -> bool:
	return _picture.texture != null


## Riga piccola sopra il titolo; `outcome` e' un CampaignUiAlerts.ESITO_* e ne sceglie il colore.
func set_category(text: String, outcome: String = "") -> void:
	_category.text = text
	_category.visible = text != ""
	var color := CATEGORY_NONE
	if outcome == CampaignUiAlerts.ESITO_GOOD:
		color = CATEGORY_GOOD
	elif outcome == CampaignUiAlerts.ESITO_BAD:
		color = CATEGORY_BAD
	_category.add_theme_color_override("font_color", color)


func set_title(text: String) -> void:
	_title.text = text
	_title.visible = text != ""


func category_text() -> String:
	return _category.text


func title_text() -> String:
	return _title.text


## Cornice dei pannelli senza il giro di pergamena interno (richiesta di Federico del 2026-11-20: «togliere quel bordo
## intorno alle tavole, per farle aderire alle cornici»): l'immagine parte dal filo d'ottone.
static func frame_box() -> StyleBox:
	var box := UiTheme._panel_box(UiTheme.PANEL_RADIUS, 0)
	box.set_content_margin_all(FRAME_INSET if box is StyleBoxTexture else 2)
	return box


## Sfumatura verticale: scura in alto (titolo), chiara al centro (l'immagine), un po' scura in basso (piastra).
static func shade_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.72), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.45)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 128
	return t


## Piastra di pergamena semitrasparente sotto il testo.
static func plate_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UiTheme.PAPER, PLATE_ALPHA)
	box.border_color = Color(UiTheme.LEATHER, 0.7)
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 6
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box
