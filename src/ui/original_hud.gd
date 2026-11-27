class_name OriginalHud
extends Control
## Interfaccia della campagna come nell'originale (richiesta di Federico, 2026-11-09). Misure dalle schermate a 800x600:
## barra in basso alta 115, larga 800 e centrata (anche a risoluzioni maggiori l'originale la lascia di 800 al centro):
## - a sinistra `campmap/info_panel.BIF` (240x115): cinque pulsanti informativi nella fascia in alto (militare, alleanze,
##   economia, spie, famiglia reale; centrati e accostati: le immagini hanno il fondo di pietra), la carta di costruzione e
##   quella di addestramento (`button_build`/`button_trainunit`, 80x61, a misura) ai lati dello scudo della fazione posato
##   sullo scudo con le spade incrociate, e nella colonna di destra le frecce per scorrere le province (`button_ipprev`
##   20x58 sopra, `button_ipnext` 20x57 sotto: insieme formano la colonna, 58 + 57 = 115). Misure dei riquadri ricavate dai
##   pixel di info_panel (fascia alta x 6-219, y 3-36; fascia bassa y 38-111; scudo 95-129 x 60-99);
## - al centro il pannello di rassegna su pergamena (edifici della provincia, unita' dell'esercito, messaggi);
## - a destra `campmap/status_panel.BIF` (115x115): tesoreria, anno e il pulsante di fine anno (`buttons/button_season.BIF`).
## In alto a sinistra la minimappa con il trapezio rosso della visuale (manuale p11). Tutto e' disegnato a 800x600 e scalato
## di `ui_scale` (altezza dello schermo / 720, tra 1 e 2), con filtro lineare. Solo disegno: i comandi escono come segnali.

signal end_year_pressed
signal info_pressed(index: int)          ## 0 militare, 1 alleanze, 2 economia, 3 spie, 4 famiglia reale
signal build_pressed
signal train_pressed
signal cycle_province(step: int)
signal minimap_pressed(world: Vector2)
signal card_pressed(index: int)          ## clic (senza trascinare) su una voce del pannello di rassegna
signal card_info(index: int)             ## clic destro su una voce: la scheda
## Trascinamento di una carta dal pannello di rassegna (richiesta di Federico, 2026-11-10: separare truppe e navi sulla
## mappa): inizio, movimento e rilascio; la posizione la legge chi ascolta (mouse nel viewport).
signal card_drag_started(index: int)
signal card_drag_moved(index: int)
signal card_drag_released(index: int)
const REVIEW_CARD_GROUP := "mq_carte_rassegna"   ## voci del pannello di rassegna (review_card_at)

const CARD_DRAG_THRESHOLD := 6.0
signal details_pressed
signal action_pressed(id: String)        ## comando dell'esercito scelto, dalla riga dei pulsanti del pannello di rassegna (ADR-035)
signal dismiss_pressed                   ## «Congeda»: sciogliere le unita' scelte nel pannello di rassegna (ADR-031)
signal proposals_pressed
signal shield_pressed                    ## clic sullo stemma della fazione: il menu delle opzioni della mappa
signal sites_pressed                     ## clic sulla bussola della minimappa: i medaglioni di tutti i luoghi scoperti
signal help_pressed                      ## clic su «H: comandi e tasti» sotto le carte: la finestra dei comandi

const BAR_W := 800.0
const BAR_H := 115.0
const LEFT_W := 240.0
const RIGHT_W := 115.0
const MINI_W_EUROPE := 176.0
const MINI_H_EUROPE := 134.0
## Dimensioni della minimappa: 176x134 sulla mappa d'Europa, larga e bassa sulla mappa del mondo (ADR-077).
static var MINI_W := MINI_W_EUROPE
static var MINI_H := MINI_H_EUROPE


## Proporzioni della minimappa: `aspect` = larghezza / altezza della mappa (0 = mappa d'Europa, 176x134).
## Colore di una zona di mare nella minimappa: scuro se non vista, schiarito se vista, azzurrato con flotte proprie.
static func sea_color(seen: bool, own_fleet: bool) -> Color:
	if own_fleet:
		return SEA_OWN_FLEET
	return SEA.lightened(0.12) if seen else SEA


## Zone di mare (id maiuscolo -> true) dove la fazione ha almeno una flotta con navi.
static func own_fleet_seas(state: GameState, faction_id: String) -> Dictionary:
	var out := {}
	if state == null:
		return out
	var me := SimUtil.norm(faction_id)
	for a in state.armies:
		if a.is_fleet and a.faction == me and not a.stacks.is_empty():
			out[a.region] = true
	return out


static func set_minimap_aspect(aspect: float) -> void:
	if aspect <= 0.0:
		MINI_W = MINI_W_EUROPE
		MINI_H = MINI_H_EUROPE
	else:
		MINI_W = 256.0
		MINI_H = roundf(256.0 / aspect)
const MINI_FRAME := 6.0
const INFO_X := 6.0 + (213.0 - 5.0 * 35.0) / 2.0   ## primo pulsante informativo: i cinque centrati nella fascia alta (213)
## Con la veste nuova i cinque medaglioni non si toccano: tra l'uno e l'altro c'e' questo spazio (richiesta di Federico
## dell'11/11); restano centrati nella fascia alta. Nella barra dell'originale stanno accostati, negli incavi della pietra.
const INFO_GAP_NEW := 6.0
const BUILD_POS := Vector2(6, 44)                 ## carta di costruzione 80x61 nella fascia bassa, a sinistra dello scudo
const TRAIN_POS := Vector2(139, 44)               ## carta di addestramento, a destra dello scudo
const CARD_SIZE := Vector2(80, 61)
const CARD_INNER := Rect2(12, 3, 55, 52)          ## riquadro della carta (nero nell'originale), dove va l'icona della prima voce in coda
const SHIELD_RECT := Rect2(95, 60, 34, 38)        ## lo scudo di metallo di info_panel, su cui si posa quello della fazione
const MINI_SIDE := 18.0                   ## la barra verticale a destra della minimappa (pulsante del menu automatico)
const INFO_BUTTONS := ["military", "alliance", "economy", "spy", "heirs"]
const INFO_TIPS := ["Militare: classifica delle fazioni, province e forze (G)", "Alleanze e diplomazia (D)",
	"Economia: proventi delle province nel dettaglio (F1)", "Spie e messaggi: registro degli eventi dell'anno", "Famiglia reale: la corte (C)"]
const INK := Color("2e2013")
const PLATE_TEXT := Color("2e2013")
const SEA := Color("27343c")
const LAND := Color("5a5d5f")
## Mare con flotte del giocatore nella minimappa: un poco piu' azzurro del mare visto (richiesta di Federico del 18/11/2026).
const SEA_OWN_FLEET := Color("2f5266")
const VIEW := Color(0.95, 0.12, 0.1)
## Veste nuova (richiesta di Federico, 2026-11-11, ADR-027): legno scuro, ottone e pergamena disegnati a codice al posto
## della pietra grigia di info_panel/status_panel. Stessa geometria e stessi comandi; restano dell'originale le carte di
## costruzione e addestramento, lo stemma e tutte le immagini del pannello di rassegna. Medaglioni dei pulsanti
## informativi, disegni delle due carte, frecce e pennacchi dei comandanti sono dipinti (ADR-038 e 040,
## `painted_texture`); se i file mancano tornano quelli dell'originale.
## La barra e' piu' grande (scala = altezza / 600 invece di / 720). `veste_nuova = false` riporta la barra dell'originale.
static var veste_nuova := true
const SCALE_BASE_NEW := 600.0
const SCALE_BASE_ORIGINAL := 720.0
const WOOD_TOP := Color("5a3e26")
const WOOD_BOTTOM := Color("2e1e12")
const WOOD_DARK := Color("2a1b10")
const BRASS := Color("d9b354")
const BRASS_DARK := Color("8a6a2a")
const IRON := Color("3a3a38")
const OUTLINE := Color("120b06")
const SEAL_RED := Color("7a1e16")
const SEAL_RED_HOVER := Color("96281d")
const COMPASS_NORTH := Color("b3352a")
const HELP_HINT_FONT := 7                   ## «H: comandi e tasti» sotto le carte (a misura 800x115)
const HELP_HINT_LIGHT := Color("e8d6a0")    ## pergamena chiara sul legno della veste nuova
## Bussola dei luoghi leggendari nell'angolo in basso a sinistra della minimappa (richiesta di Federico del 26/11/2026).
const COMPASS := Vector2(20, 20)
## Texture ripetibili della veste nuova (facoltative): `legno.png` e `pergamena.png`. Se mancano restano le tinte piatte.
## Si rigenerano con tools/genera_texture_base.py o si sostituiscono con tools/prepara_texture.py (immagini dipinte).
const SKIN_DIR := "res://assets/ui/veste/"
## Cornice della barra nella veste nuova (richiesta di Federico dell'11/11): il legno sporge di BAR_PAD attorno ai
## controlli (che restano alla geometria dell'originale), ha gli angoli stondati e sta staccato dal fondo di BAR_GAP.
const BAR_PAD := 7.0
const BAR_GAP := 8.0
const BAR_RADIUS := 10
const BADGE_SIZE := Vector2(11, 24)      ## pennacchio del comandante sulle carte (originale 14x31)
const UPGRADE_ICON_SIZE := Vector2(12, 12)   ## scudo e spada dei potenziamenti sulle carte (assets/icone, SVG nitidi)
const UPGRADE_EMBLEM_SIZE := Vector2(16, 16)  ## emblema unico dei potenziamenti: bordo dello scudo = armatura, spada = armi
const UPGRADE_EMBLEM_SWORD_DOWN := true        ## spada con la punta in basso (false: punta in alto)
const SMALL_BUTTON_FONT := 8                 ## comandi dell'esercito, «Congeda», «Dettagli», «Proposte» (10 prima)
const UNIT_NUMBER_SIZE := 9                  ## numero dei soldati sulle carte delle unita' (11 prima: un 20% piu' piccolo)
const SIDE_ICON := Vector2(76, 57)       ## icona a fianco della rassegna (le icone degli edifici sono 4:3)
const BADGE_SIZE_NEW := Vector2(14, 31)  ## pennacchio dipinto (veste nuova): alla misura dell'originale, lo stendardo e' piu' corto
const ARROW_HEAD := Vector2(13, 42)      ## punta di freccia dipinta dentro il tassello di legno 20x58 (veste nuova)
const NEW_CARD_WELL := Rect2(9, 2, 62, 57)   ## riquadro con la cornice d'ottone dentro la carta 80x61 (veste nuova)

var ui_scale := 1.0
var _bar: Control
var _minimap: Control
var _help_hint: Label
var _compass: Control
var _compass_on := false
var _compass_hover := false
var _mini_rect: TextureRect
var _mini_quad := PackedVector2Array()
var _mini_overlay: Control
var _map_size := Vector2(2048, 1536)
var _treasury: Label
var _year: Label
var _end_button: TextureButton
var _end_label: Label
var _shield: TextureRect
var _build_card: TextureRect            ## icona della prima voce in coda (nel riquadro nero della carta)
var _train_card: TextureRect
var _build_frame: TextureRect           ## la carta dell'originale (button_build / button_trainunit) a misura
var _train_frame: TextureRect
var _review_title: Label
var _review_flow: Container            ## gruppo di immagini in costruzione (l'ultimo aperto)
var _review_side_flow: HFlowContainer   ## fila dei gruppi affiancati (le armate nel castello), creata al primo gruppo
const SIDE_GROUP_ROW := 8               ## voci per riga in un gruppo affiancato, oltre va a capo
## Carte del castello scelto (accanto alla sua icona) e delle armate nel pannello di rassegna, a griglia di
## ARMY_COLUMNS colonne. Commenti ricostruiti il 25/11/2026 dalla build esportata: gli originali sono andati persi.
const CASTLE_CARD := Vector2(30, 30)
## Carte delle armate: piu' piccole delle 56x41 di prima, in una griglia di colonne fisse cosi' le righe restano
## allineate.
const ARMY_COLUMNS := 10
const ARMY_CARD := Vector2(38, 38)
var _review_box: VBoxContainer          ## i gruppi del pannello di rassegna, uno sotto l'altro
var _review_scroll: ScrollContainer
var _review_text: Label
var _details_button: Button
var _dismiss_button: Button
var _actions_box: HBoxContainer         ## comandi dell'esercito scelto, prima di «Congeda»
var _side_frame: PanelContainer         ## cornice dell'icona a fianco della rassegna (il castello scelto)
var _side_icon: TextureRect
var _side_head: HBoxContainer           ## nome in grassetto e nota, sopra le voci
var _side_name: Label
var _side_note: Label
var _proposals_button: Button
var _info_buttons: Array[TextureButton] = []
var _card_press := -1                    ## voce premuta col tasto sinistro (-1 = nessuna)
var _card_press_pos := Vector2.ZERO
var _card_dragging := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_build_bar()
	_build_minimap()


## Altezza in pixel dello schermo occupata dalla barra (per spostare sopra di essa pannelli e scritte).
func bar_height() -> float:
	return (BAR_H + 2.0 * _pad() + _gap()) * ui_scale


func _pad() -> float:
	return BAR_PAD if veste_nuova else 0.0


func _gap() -> float:
	return BAR_GAP if veste_nuova else 0.0


func layout(view: Vector2) -> void:
	ui_scale = scale_for(view.y)
	if _bar != null:
		_bar.scale = Vector2(ui_scale, ui_scale)
		_bar.position = Vector2(roundf((view.x - BAR_W * ui_scale) / 2.0), view.y - (BAR_H + _pad() + _gap()) * ui_scale)
	if _minimap != null:
		_minimap.scale = Vector2(ui_scale, ui_scale)
		_minimap.position = Vector2.ZERO


## Scala della barra per un'altezza di schermo: la veste nuova e' disegnata piu' grande (a 1600x900 la barra e' 1200x172).
static func scale_for(view_height: float) -> float:
	if veste_nuova:
		return clampf(view_height / SCALE_BASE_NEW, 1.0, 2.2)
	return clampf(view_height / SCALE_BASE_ORIGINAL, 1.0, 2.0)


# --- dati dal gioco --------------------------------------------------------------------------------------------------


func set_status(treasury: int, year: int, treasury_tip: String, year_tip: String, game_over: bool, end_tip: String) -> void:
	_treasury.text = Lang.t("%d denari") % treasury
	_treasury.add_theme_color_override("font_color", Color("8a1c12") if treasury < 0 else PLATE_TEXT)
	_treasury.tooltip_text = treasury_tip
	_year.text = Lang.t("AD %d") % year
	_year.tooltip_text = year_tip
	_end_button.disabled = game_over
	_end_button.tooltip_text = end_tip
	_end_label.modulate = Color(1, 1, 1, 0.45) if game_over else Color.WHITE


func set_shield(tex: Texture2D) -> void:
	_shield.texture = tex


## Carte della barra: `build_tex`/`train_tex` = icona della prima voce in coda, oppure null (o l'immagine stessa della carta)
## per la carta dell'originale con il suo disegno.
func set_cards(build_tex: Texture2D, build_tip: String, train_tex: Texture2D, train_tip: String) -> void:
	_set_card(_build_card, _build_frame, build_tex, build_tip)
	_set_card(_train_card, _train_frame, train_tex, train_tip)


func _set_card(icon: TextureRect, frame: TextureRect, tex: Texture2D, tip: String) -> void:
	var well := icon.get_parent() as Control
	if veste_nuova:
		# cornice d'ottone al posto della pietra: dentro c'e' il disegno dell'originale (ritagliato dalla sua carta) oppure
		# l'icona della prima voce in coda
		var original: Texture2D = frame.get_meta("carta", null) if frame != null else null
		var art: Texture2D = frame.get_meta("disegno", null) if frame != null else null
		var own := tex == null or tex == original
		icon.texture = art if own else tex
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if own else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		well.visible = true
		icon.tooltip_text = tip
		if frame != null:
			frame.tooltip_text = tip
		return
	var no_frame := frame == null or frame.texture == null
	var own := tex == null or (not no_frame and tex == frame.texture)
	icon.texture = tex if no_frame or not own else null
	well.visible = no_frame or not own
	icon.tooltip_text = tip
	if frame != null:
		frame.tooltip_text = tip


func set_proposals(count: int) -> void:
	_proposals_button.visible = count > 0
	_proposals_button.text = Lang.t("Proposte (%d)") % count


## Pannello di rassegna: titolo, immagini (Texture2D, con suggerimento e didascalia) o, senza immagini, righe di testo.
## `details` mostra il pulsante che apre la pergamena informativa. Una voce {"intestazione": testo} apre un gruppo nuovo, su
## una riga sua, con l'etichetta a sinistra; con "evidenzia" il gruppo ha un fondo scuro (la coda di produzione, separata
## dagli edifici costruiti: richiesta di Federico del 2026-11-10). Gli indici dei clic restano quelli di `items`.
## `side` (richiesta di Federico dell'11/11/2026, il castello scelto): {"immagine", "nome", "nota", "suggerimento"} mette
## l'icona a sinistra, il nome in grassetto e la nota sopra le voci, che cosi' stanno accanto all'icona.
## `columns` > 0: la prima fila di voci e' una griglia di `columns` colonne invece di andare a capo da sola.
func show_review(title: String, items: Array, lines: PackedStringArray, details: bool, side: Dictionary = {}, columns: int = 0) -> void:
	_review_title.text = title
	_review_title.visible = title != ""
	var side_tex: Texture2D = side.get("immagine")
	_side_icon.texture = side_tex
	_side_icon.visible = side_tex != null
	_side_frame.visible = side_tex != null
	_side_frame.tooltip_text = str(side.get("suggerimento", ""))
	_side_head.visible = not side.is_empty()
	_side_name.text = str(side.get("nome", ""))
	_side_name.tooltip_text = str(side.get("suggerimento", ""))
	_side_note.text = str(side.get("nota", ""))
	_side_note.tooltip_text = str(side.get("suggerimento_nota", ""))
	for c in _review_box.get_children():
		c.queue_free()
	_review_side_flow = null
	_review_flow = _review_group("", false, "", columns)
	var first_flow := _review_flow
	for i in items.size():
		var item: Dictionary = items[i]
		if item.has("intestazione"):
			if bool(item.get("affianca", false)):
				# quante voci ha il gruppo (fino alla prossima intestazione) e quanto sono larghe: serve per mandarlo a capo
				var count := 0
				var width := 38.0
				for j in range(i + 1, items.size()):
					var next: Dictionary = items[j]
					if next.has("intestazione"):
						break
					var next_size: Vector2 = next.get("misura", Vector2(56, 41))
					width = next_size.x
					count += 1
				_review_flow = _review_side_group(str(item["intestazione"]), str(item.get("suggerimento", "")), count, width)
			else:
				_review_flow = _review_group(str(item["intestazione"]), bool(item.get("evidenzia", false)), str(item.get("suggerimento", "")))
			continue
		_review_flow.add_child(_review_item(item, i))
	# senza voci nella prima fila (solo gruppi con intestazione) la fila vuota non occupa spazio
	first_flow.get_parent().visible = first_flow.get_child_count() > 0 or items.is_empty()
	_review_scroll.visible = not items.is_empty()
	_review_scroll.scroll_vertical = 0
	_review_text.text = "\n".join(lines)
	_review_text.visible = items.is_empty() and not lines.is_empty()
	_details_button.visible = details


## Comandi dell'esercito scelto, in fila prima di «Congeda» (ADR-035: la pergamena dell'esercito non c'e' piu', i suoi
## comandi stanno qui): ogni voce {"id", "testo", "suggerimento", "attivo"}; il clic emette `action_pressed(id)`.
func set_actions(actions: Array) -> void:
	for c in _actions_box.get_children():
		_actions_box.remove_child(c)
		c.queue_free()
	for item in actions:
		var a: Dictionary = item
		var b := _small_button(str(a.get("testo", "")))
		b.tooltip_text = str(a.get("suggerimento", ""))
		b.disabled = not bool(a.get("attivo", true))
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW if b.disabled else Control.CURSOR_POINTING_HAND
		b.pressed.connect(func() -> void: action_pressed.emit(str(a.get("id", ""))))
		_actions_box.add_child(b)


## Pulsante «Congeda» accanto a «Dettagli»: visibile per un esercito o una flotta propri, acceso con delle unita' scelte.
func set_dismiss(shown: bool, enabled: bool = false, text: String = Lang.t("Congeda"), tip: String = "") -> void:
	_dismiss_button.visible = shown
	_dismiss_button.disabled = not enabled
	_dismiss_button.text = text
	_dismiss_button.tooltip_text = tip
	_dismiss_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW


func set_minimap(img: Image, map_size: Vector2) -> void:
	_map_size = map_size
	_mini_rect.texture = ImageTexture.create_from_image(img)


## Trapezio della visuale in coordinate della mappa (pixel della bitmap).
func set_view_quad(world_points: PackedVector2Array) -> void:
	_mini_quad = PackedVector2Array()
	for p in world_points:
		_mini_quad.append(Vector2(p.x / _map_size.x * MINI_W, p.y / _map_size.y * MINI_H))
	if _mini_overlay != null:
		_mini_overlay.queue_redraw()


# --- costruzione -------------------------------------------------------------------------------------------------


## Bordo sinistro del pulsante informativo `index` (0-4) nelle coordinate della barra, secondo la veste.
static func info_x(index: int) -> float:
	var gap := INFO_GAP_NEW if veste_nuova else 0.0
	return 6.0 + (213.0 - 5.0 * 35.0 - 4.0 * gap) / 2.0 + (35.0 + gap) * float(index)


func _tex(path: String, frame: int = 1) -> Texture2D:
	return AssetLibrary.texture(path, frame) if AssetLibrary.is_available() else null


## Il solo medaglione rotondo di un pulsante informativo: fuori dal cerchio trasparente, cosi' la pietra di info_panel
## resta continua tra un pulsante e l'altro (le immagini hanno un fondo scuro rettangolare che non combacia).
static func _round(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var center := Vector2(img.get_width() / 2.0, img.get_height() / 2.0 - 0.5)
	var radius := minf(img.get_width(), img.get_height()) / 2.0
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d > radius:
				var c := img.get_pixel(x, y)
				c.a = clampf(radius + 1.0 - d, 0.0, 1.0) * c.a
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _build_bar() -> void:
	_bar = Control.new()
	_bar.theme = UiTheme.crisp_theme()   # la barra e' scalata: caratteri nitidi a ogni misura
	_bar.size = Vector2(BAR_W, BAR_H)
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # immagini dipinte e rifatte piu' grandi della misura
	add_child(_bar)
	if veste_nuova:
		# corpo di legno piu' largo dei controlli, stondato (i figli sono ritagliati sulla sua forma) e con l'ombra sulla mappa
		var outer := Vector2(BAR_W, BAR_H) + Vector2(BAR_PAD, BAR_PAD) * 2.0
		var body := Panel.new()
		body.position = -Vector2(BAR_PAD, BAR_PAD)
		body.size = outer
		body.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		body.mouse_filter = Control.MOUSE_FILTER_STOP
		var body_style := StyleBoxFlat.new()
		body_style.bg_color = WOOD_DARK
		body_style.set_corner_radius_all(BAR_RADIUS)
		body_style.shadow_color = Color(0, 0, 0, 0.45)
		body_style.shadow_size = 6
		body_style.shadow_offset = Vector2(0, 3)
		body.add_theme_stylebox_override("panel", body_style)
		_bar.add_child(body)
		body.add_child(_wood(outer))
		var chrome := Control.new()
		chrome.size = outer
		chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chrome.draw.connect(_draw_bar_chrome.bind(chrome))
		body.add_child(chrome)
		var rim := Panel.new()   # orlo d'ottone stondato sopra il legno
		rim.position = body.position
		rim.size = outer
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rim_style := StyleBoxFlat.new()
		rim_style.draw_center = false
		rim_style.border_color = BRASS
		rim_style.set_border_width_all(1)   # orlo sottile (Federico, 11/11)
		rim_style.set_corner_radius_all(BAR_RADIUS)
		rim.add_theme_stylebox_override("panel", rim_style)
		_bar.add_child(rim)
	# --- sinistra: info_panel ---
	var left := TextureRect.new()
	left.texture = null if veste_nuova else _tex("campmap/info_panel.BIF")
	left.size = Vector2(LEFT_W, BAR_H)
	left.stretch_mode = TextureRect.STRETCH_SCALE
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(left)
	if left.texture == null and not veste_nuova:
		left.add_child(_flat_panel(Vector2(LEFT_W, BAR_H)))
	for i in INFO_BUTTONS.size():
		var b := TextureButton.new()
		var name := str(INFO_BUTTONS[i])
		var painted := medallion_texture(name) if veste_nuova else null
		if painted != null:
			b.texture_normal = painted
			b.texture_hover = medallion_texture(name, "_sopra")
			b.texture_pressed = medallion_texture(name, "_premuto")
			b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		else:
			b.texture_normal = _round(_tex("campmap/buttons/button_%s.BIF" % name, 1))
			b.texture_pressed = _round(_tex("campmap/buttons/button_%s.BIF" % name, 2))
			b.texture_hover = b.texture_pressed
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.position = Vector2(info_x(i), 3.0)
		b.size = Vector2(35, 33)
		b.tooltip_text = Lang.t(str(INFO_TIPS[i]))
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func() -> void: info_pressed.emit(i))
		_bar.add_child(b)
		_info_buttons.append(b)
	_build_card = _card(BUILD_POS, "campmap/buttons/button_build.BIF", Lang.t("Costruzione: apre la pergamena di costruzione della provincia scelta"))
	_build_card.gui_input.connect(_on_card_input.bind("build"))
	_train_card = _card(TRAIN_POS, "campmap/buttons/button_trainunit.BIF", Lang.t("Addestramento: apre la pergamena di addestramento della provincia scelta"))
	_train_card.gui_input.connect(_on_card_input.bind("train"))
	# «H: comandi e tasti» in piccolo sotto le due carte (richiesta di Federico del 27/11/2026); il clic apre la finestra
	_help_hint = Label.new()
	_help_hint.text = Lang.t("H: comandi e tasti")
	_help_hint.position = Vector2(BUILD_POS.x, BUILD_POS.y + CARD_SIZE.y)
	_help_hint.size = Vector2(TRAIN_POS.x + CARD_SIZE.x - BUILD_POS.x, BAR_H - BUILD_POS.y - CARD_SIZE.y)
	_help_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_help_hint.add_theme_font_size_override("font_size", HELP_HINT_FONT)
	_help_hint.add_theme_color_override("font_color", HELP_HINT_LIGHT if veste_nuova else PLATE_TEXT)
	_help_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_hint.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_help_hint.tooltip_text = Lang.t("Tutti i comandi del mouse e i tasti (H)")
	_help_hint.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			help_pressed.emit())
	_bar.add_child(_help_hint)
	# centrata nella fascia di 10 punti sotto le carte (la riga del carattere nitido e' piu' alta della fascia)
	var band := BAR_H - BUILD_POS.y - CARD_SIZE.y
	_help_hint.size.y = _help_hint.get_combined_minimum_size().y
	_help_hint.position.y = BUILD_POS.y + CARD_SIZE.y + band / 2.0 - _help_hint.size.y / 2.0
	_arrow(Vector2(LEFT_W - 20.0, 0), Vector2(20, 58), "campmap/buttons/button_ipprev.BIF", -1)
	_arrow(Vector2(LEFT_W - 20.0, 58), Vector2(20, 57), "campmap/buttons/button_ipnext.BIF", 1)
	_shield = TextureRect.new()
	_shield.position = SHIELD_RECT.position
	_shield.size = SHIELD_RECT.size
	_shield.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shield.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shield.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # stemma proprio a 136x160: nitido a ogni scala
	_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_shield.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_shield.tooltip_text = Lang.t("Opzioni della mappa: confini, tinta, prospettiva")
	_shield.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			shield_pressed.emit())
	_bar.add_child(_shield)
	# --- centro: pannello di rassegna ---
	var center := Panel.new()
	center.position = Vector2(LEFT_W + 3.0, 0)
	center.size = Vector2(BAR_W - LEFT_W - RIGHT_W - 6.0, BAR_H)
	center.add_theme_stylebox_override("panel", _review_style())
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.add_child(center)
	var paper_tex := skin_texture("pergamena") if veste_nuova else null
	if paper_tex != null:
		# grana della pergamena dentro il bordo del pannello
		var grain := TextureRect.new()
		grain.texture = paper_tex
		grain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # prima della misura: altrimenti l'altezza minima e' quella della texture
		grain.stretch_mode = TextureRect.STRETCH_TILE
		grain.position = Vector2(2, 2)
		grain.size = center.size - Vector2(4, 4)
		grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(grain)
	var box := VBoxContainer.new()
	box.position = Vector2(14, 8)
	box.size = center.size - Vector2(28, 14)
	box.add_theme_constant_override("separation", 1)
	center.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_review_title = Label.new()
	_review_title.add_theme_font_size_override("font_size", 11)
	_review_title.add_theme_color_override("font_color", Color("5c1a10"))
	_review_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_review_title.clip_text = true
	head.add_child(_review_title)
	_proposals_button = _small_button(Lang.t("Proposte"))
	_proposals_button.visible = false
	_proposals_button.pressed.connect(func() -> void: proposals_pressed.emit())
	head.add_child(_proposals_button)
	_actions_box = HBoxContainer.new()
	_actions_box.add_theme_constant_override("separation", 3)
	_actions_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_actions_box)
	_dismiss_button = _small_button(Lang.t("Congeda"))
	_dismiss_button.visible = false
	_dismiss_button.pressed.connect(func() -> void: dismiss_pressed.emit())
	head.add_child(_dismiss_button)
	_details_button = _small_button(Lang.t("Dettagli"))
	_details_button.tooltip_text = Lang.t("Apre la pergamena informativa (doppio clic sulla pedina o clic destro sulla provincia)")
	_details_button.visible = false
	_details_button.pressed.connect(func() -> void: details_pressed.emit())
	head.add_child(_details_button)
	# corpo: a sinistra, quando serve, l'icona di cio' che si guarda (il castello); a destra nome, nota e voci
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	_side_frame = PanelContainer.new()
	# richiesta di Federico (2026-11-15): niente riquadro scuro dietro l'icona, le icone dipinte sono gia' scontornate
	_side_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_side_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_side_frame.visible = false
	body.add_child(_side_frame)
	_side_icon = TextureRect.new()
	_side_icon.custom_minimum_size = SIDE_ICON
	_side_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_side_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_side_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # icona rifatta piu' grande del riquadro
	_side_icon.visible = false
	_side_frame.add_child(_side_icon)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	_side_head = HBoxContainer.new()
	_side_head.add_theme_constant_override("separation", 8)
	_side_head.visible = false
	content.add_child(_side_head)
	_side_name = Label.new()
	_side_name.add_theme_font_size_override("font_size", 13)
	_side_name.add_theme_color_override("font_color", INK)
	if UiTheme.crisp_text_bold() != null:
		_side_name.add_theme_font_override("font", UiTheme.crisp_text_bold())
	_side_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_name.clip_text = true
	_side_name.mouse_filter = Control.MOUSE_FILTER_PASS
	_side_head.add_child(_side_name)
	_side_note = Label.new()
	_side_note.add_theme_font_size_override("font_size", 11)
	_side_note.add_theme_color_override("font_color", Color("5c1a10"))
	_side_note.mouse_filter = Control.MOUSE_FILTER_PASS
	_side_head.add_child(_side_note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_review_scroll = scroll
	_review_box = VBoxContainer.new()
	_review_box.add_theme_constant_override("separation", 3)
	_review_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_review_box)
	_review_flow = _review_group("", false)
	_review_text = Label.new()
	_review_text.add_theme_color_override("font_color", INK)
	_review_text.add_theme_font_size_override("font_size", 13)
	_review_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_review_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_review_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_review_text)
	# --- destra: status_panel ---
	var right := TextureRect.new()
	right.texture = null if veste_nuova else _tex("campmap/status_panel.BIF")
	right.position = Vector2(BAR_W - RIGHT_W, 0)
	right.size = Vector2(RIGHT_W, BAR_H)
	right.stretch_mode = TextureRect.STRETCH_SCALE
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(right)
	if right.texture == null and not veste_nuova:
		right.add_child(_flat_panel(Vector2(RIGHT_W, BAR_H)))
	_treasury = _plate_label(Vector2(BAR_W - RIGHT_W + 12, 7), Vector2(91, 19))
	_year = _plate_label(Vector2(BAR_W - RIGHT_W + 12, 33), Vector2(91, 19))
	_end_button = TextureButton.new()
	if not veste_nuova:
		_end_button.texture_normal = _tex("campmap/buttons/button_season.BIF", 1)
		_end_button.texture_pressed = _tex("campmap/buttons/button_season.BIF", 2)
	_end_button.ignore_texture_size = true
	_end_button.stretch_mode = TextureButton.STRETCH_SCALE
	_end_button.position = Vector2(BAR_W - RIGHT_W + 6, 62)
	_end_button.size = Vector2(103, 46)
	_end_button.focus_mode = Control.FOCUS_NONE
	_end_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_end_button.pressed.connect(func() -> void: end_year_pressed.emit())
	_bar.add_child(_end_button)
	if veste_nuova:
		_end_button.add_child(_seal_plate(_end_button))
	_end_label = Label.new()
	_end_label.text = Lang.t("Fine\nanno")
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_label.add_theme_font_size_override("font_size", 14)
	_end_label.add_theme_constant_override("line_spacing", -5)
	_end_label.add_theme_color_override("font_color", Color.WHITE if veste_nuova else Color("2a2622"))
	_end_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55) if veste_nuova else Color(1, 1, 1, 0.35))
	_end_label.add_theme_constant_override("shadow_offset_y", 1)
	_end_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_button.add_child(_end_label)


## Cornice della minimappa: con la veste nuova un filo sottile e nessuna fascia a destra (richiesta di Federico
## dell'11/11/2026: «ridurre i bordi»); con la barra dell'originale restano le misure di prima.
func _mini_frame() -> float:
	return 1.0 if veste_nuova else MINI_FRAME


func _mini_side() -> float:
	return 0.0 if veste_nuova else MINI_SIDE


func _build_minimap() -> void:
	_minimap = Control.new()
	_minimap.size = Vector2(MINI_W + _mini_frame() * 2.0 + _mini_side(), MINI_H + _mini_frame() * 2.0)
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_minimap.gui_input.connect(_on_minimap_input)
	add_child(_minimap)
	var frame := Panel.new()
	frame.size = _minimap.size
	frame.add_theme_stylebox_override("panel", _stone_style())
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.add_child(frame)
	_mini_rect = TextureRect.new()
	_mini_rect.position = Vector2(_mini_frame(), _mini_frame())
	_mini_rect.size = Vector2(MINI_W, MINI_H)
	_mini_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mini_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_mini_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.add_child(_mini_rect)
	_mini_overlay = Control.new()
	_mini_overlay.size = _minimap.size
	_mini_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_overlay.draw.connect(_draw_minimap_overlay)
	_minimap.add_child(_mini_overlay)
	_compass = Control.new()
	_compass.size = COMPASS
	_compass.position = Vector2(_mini_frame() + 3.0, _mini_frame() + MINI_H - COMPASS.y - 3.0)
	_compass.mouse_filter = Control.MOUSE_FILTER_STOP
	_compass.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_compass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # bussola dipinta a 128 px
	_compass.visible = false
	_compass.draw.connect(_draw_compass)
	_compass.gui_input.connect(_on_compass_input)
	_compass.mouse_entered.connect(_on_compass_hover.bind(true))
	_compass.mouse_exited.connect(_on_compass_hover.bind(false))
	_minimap.add_child(_compass)


## Bussola dei luoghi leggendari: `shown` la mostra (solo sulla mappa del mondo), `on` = medaglioni tutti aperti.
func set_sites_button(shown: bool, on: bool, tip: String) -> void:
	if _compass == null:
		return
	_compass.visible = shown
	_compass_on = on
	_compass.tooltip_text = tip
	_compass.queue_redraw()


func sites_button() -> Control:
	return _compass


func help_hint() -> Label:
	return _help_hint


func _on_compass_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		sites_pressed.emit()
		_compass.accept_event()


func _on_compass_hover(on: bool) -> void:
	_compass_hover = on
	_compass.queue_redraw()


## Disco scuro con l'anello d'ottone e la rosa dei venti: punta del nord rossa, le altre d'ottone; piu' chiara al
## passaggio del mouse, su fondo d'ambra se attiva.
func _draw_compass() -> void:
	var c := _compass
	var s := c.size
	var m := s / 2.0
	var lit := _compass_on or _compass_hover
	c.draw_circle(m, s.x / 2.0, Color(0.42, 0.29, 0.09, 0.95) if _compass_on else Color(0.10, 0.07, 0.04, 0.80))
	c.draw_arc(m, s.x / 2.0 - 0.75, 0.0, TAU, 32, BRASS if lit else BRASS_DARK, 1.5, true)
	var painted := painted_texture("bussola")
	if painted != null:
		# rosa dei venti dipinta (assets/ui/veste/bussola.png, tools/prepara_simboli_luoghi.py): piu' chiara se accesa
		var side := s.x * 0.84
		c.draw_texture_rect(painted, Rect2(m - Vector2(side, side) / 2.0, Vector2(side, side)), false, Color(1.25, 1.2, 1.1) if lit else Color.WHITE)
		return
	var ink := BRASS.lightened(0.3) if lit else BRASS
	var tip_len := s.x * 0.37
	var side_len := s.x * 0.20
	var half := s.x * 0.10
	for d in [Vector2.RIGHT, Vector2.LEFT]:
		_compass_point(c, m, d, side_len, half * 0.8, ink.darkened(0.25))
	_compass_point(c, m, Vector2.DOWN, tip_len, half, ink)
	_compass_point(c, m, Vector2.UP, tip_len, half, COMPASS_NORTH.lightened(0.2) if lit else COMPASS_NORTH)
	c.draw_circle(m, 1.6, WOOD_DARK)
	c.draw_circle(m, 0.9, ink)


## Una punta della rosa dei venti: triangolo dal centro (base larga `half` per lato) fino a `length` nella direzione `d`.
func _compass_point(c: Control, m: Vector2, d: Vector2, length: float, half: float, color: Color) -> void:
	var side := Vector2(-d.y, d.x) * half
	c.draw_colored_polygon(PackedVector2Array([m + d * length, m + side, m - side]), color)


func _draw_minimap_overlay() -> void:
	if _mini_quad.size() < 3:
		return
	var pts := PackedVector2Array()
	var clip := Rect2(Vector2.ZERO, Vector2(MINI_W, MINI_H))
	for p in _mini_quad:
		pts.append(Vector2(clampf(p.x, clip.position.x, clip.end.x), clampf(p.y, clip.position.y, clip.end.y)) + Vector2(_mini_frame(), _mini_frame()))
	pts.append(pts[0])
	_mini_overlay.draw_polyline(pts, VIEW, 1.5, true)


func _on_minimap_input(event: InputEvent) -> void:
	var press := event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	var drag := event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if not press and not drag:
		return
	var local: Vector2 = (event as InputEventMouse).position - Vector2(_mini_frame(), _mini_frame())
	if local.x < 0.0 or local.y < 0.0 or local.x > MINI_W or local.y > MINI_H:
		return
	minimap_pressed.emit(Vector2(local.x / MINI_W * _map_size.x, local.y / MINI_H * _map_size.y))
	_minimap.accept_event()


func _on_card_input(event: InputEvent, which: String) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if which == "build":
			build_pressed.emit()
		else:
			train_pressed.emit()


## Carta di costruzione o addestramento: l'immagine dell'originale a misura (cliccabile) e sopra, nel suo riquadro nero,
## l'icona della prima voce in coda quando c'e'. Restituisce l'icona (riceve i clic e il suggerimento).
func _card(pos: Vector2, frame_path: String, tip: String) -> TextureRect:
	var frame := TextureRect.new()
	frame.texture = _tex(frame_path, 1)
	frame.position = pos
	frame.size = CARD_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.tooltip_text = tip
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_bar.add_child(frame)
	if frame_path.contains("build"):
		_build_frame = frame
	else:
		_train_frame = frame
	var well := Panel.new()   # fondo chiaro come i pannelli (richiesta di Federico, 2026-11-10: non nero)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.PAPER
	sb.border_color = UiTheme.PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	well.add_theme_stylebox_override("panel", sb)
	well.position = pos + CARD_INNER.position
	well.size = CARD_INNER.size
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.visible = frame.texture == null
	var inset := Vector2.ZERO
	if veste_nuova:
		# la carta di pietra dell'originale non si disegna: dentro una cornice d'ottone sta il disegno dipinto (ADR-040)
		# oppure, se manca, quello dell'originale ritagliato dalla sua carta
		var art: Texture2D = painted_texture("carta_build" if frame_path.contains("build") else "carta_trainunit")
		if art == null and frame.texture != null:
			var crop := AtlasTexture.new()
			crop.atlas = frame.texture
			crop.region = Rect2(CARD_INNER.position, CARD_INNER.size - Vector2(2, 0))   # senza il filo di pietra a destra
			art = crop
		if art != null:
			if frame.texture != null:
				frame.set_meta("carta", frame.texture)
			frame.set_meta("disegno", art)
			frame.texture = null
		sb.border_color = BRASS
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.shadow_color = OUTLINE
		sb.shadow_size = 1
		well.position = pos + NEW_CARD_WELL.position
		well.size = NEW_CARD_WELL.size
		well.visible = true
		inset = Vector2(1, 1)
	_bar.add_child(well)
	var r := TextureRect.new()
	r.position = inset
	r.size = well.size - inset * 2.0
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # il disegno dipinto e' 4 volte il riquadro
	r.tooltip_text = tip
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	well.add_child(r)
	frame.gui_input.connect(func(event: InputEvent) -> void: r.gui_input.emit(event))
	return r


func _arrow(pos: Vector2, size: Vector2, path: String, step: int) -> void:
	if veste_nuova:
		_wood_arrow(pos, size, step)
		return
	var b := TextureButton.new()
	b.texture_normal = _tex(path, 1)
	b.texture_pressed = _tex(path, 2)
	b.texture_hover = b.texture_pressed
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = size
	b.tooltip_text = (Lang.t("Provincia precedente") if step < 0 else Lang.t("Provincia successiva")) + Lang.t(" (tasti , e .; con Maiusc solo quelle con qualcosa in coda)")
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func() -> void: cycle_province.emit(step))
	_bar.add_child(b)


func _plate_label(pos: Vector2, size: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", PLATE_TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.add_child(l)
	return l


func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	# piu' bassi e con il carattere piu' piccolo (richiesta di Federico, 2026-11-13); nella barra scalata il carattere e'
	# quello nitido (MSDF) di UiTheme.crisp_theme, quindi resta definito anche piccolo
	b.add_theme_font_size_override("font_size", SMALL_BUTTON_FONT)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # non si allunga fino all'altezza del titolo della riga
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.BUTTON_BG_HOVER if state == "hover" else UiTheme.BUTTON_BG
		if state == "disabled":
			sb.bg_color = Color(UiTheme.BUTTON_BG, 0.35)   # spento: stesso ingombro, colore smorzato
		sb.content_margin_top = 0
		sb.content_margin_bottom = 1
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.set_corner_radius_all(2)
		b.add_theme_stylebox_override(state, sb)
	return b


## Gruppo del pannello di rassegna: etichetta verticale a sinistra (se c'e') e le immagini; `highlight` = fondo scuro.
func _review_group(label: String, highlight: bool, tip: String = "", columns: int = 0) -> Container:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var holder: Control = row
	if highlight:
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.36, 0.22, 0.10, 0.16)
		sb.border_color = Color(0.36, 0.22, 0.10, 0.45)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(5)
		sb.set_content_margin_all(2)
		sb.content_margin_left = 3
		panel.add_theme_stylebox_override("panel", sb)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		holder = panel
	if label != "":
		var l := Label.new()
		l.text = label
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", Color("5c1a10"))
		l.custom_minimum_size = Vector2(44, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE if tip == "" else Control.MOUSE_FILTER_STOP
		l.tooltip_text = tip
		row.add_child(l)
	if columns > 0:
		var grid := GridContainer.new()
		grid.columns = columns
		grid.add_theme_constant_override("h_separation", 3)
		grid.add_theme_constant_override("v_separation", 2)
		row.add_child(grid)
		_review_box.add_child(holder)
		return grid
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 3)
	flow.add_theme_constant_override("v_separation", 2)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(flow)
	_review_box.add_child(holder)
	return flow


## Gruppo affiancato agli altri (un'armata nel castello): etichetta sopra, voci sotto, in una cornice leggera. I gruppi
## stanno uno accanto all'altro e vanno a capo insieme quando non c'e' posto.
func _review_side_group(label: String, tip: String, count: int, item_width: float) -> Container:
	if _review_side_flow == null:
		_review_side_flow = HFlowContainer.new()
		_review_side_flow.add_theme_constant_override("h_separation", 5)
		_review_side_flow.add_theme_constant_override("v_separation", 3)
		_review_side_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_review_box.add_child(_review_side_flow)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.36, 0.22, 0.10, 0.10)
	sb.border_color = Color(0.36, 0.22, 0.10, 0.40)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	panel.add_theme_stylebox_override("panel", sb)
	panel.tooltip_text = tip if tip.begins_with(label) else (label + ("\n" + tip if tip != "" else ""))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 2)
	flow.add_theme_constant_override("v_separation", 2)
	var per_row := clampi(ceili(float(count) / 2.0), 1, SIDE_GROUP_ROW)
	flow.custom_minimum_size = Vector2(float(per_row) * item_width + float(per_row - 1) * 2.0, 0)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(flow)
	_review_side_flow.add_child(panel)
	return flow


func _review_item(item: Dictionary, index: int) -> Control:
	if bool(item.get("separatore", false)):
		# riga verticale tra le voci in coda e gli edifici costruiti
		var gap := Control.new()
		var gap_size: Vector2 = item.get("misura", Vector2(7, 40))
		gap.custom_minimum_size = gap_size
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var line := ColorRect.new()
		line.color = Color(INK, 0.45)
		line.position = Vector2(floorf(gap_size.x / 2.0), 3)
		line.size = Vector2(1, gap_size.y - 6)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gap.add_child(line)
		return gap
	var tex: Texture2D = item.get("immagine")
	var size: Vector2 = item.get("misura", Vector2(56, 41))
	var holder := Control.new()
	holder.custom_minimum_size = size
	holder.tooltip_text = str(item.get("suggerimento", ""))
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if tex != null:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pic)
	var badge: Texture2D = item.get("distintivo")
	if badge != null:
		# pennacchio del comandante (corona del re, insegna di erede e principi, del generale) sulla carta
		var flag := TextureRect.new()
		flag.texture = badge
		flag.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		flag.size = BADGE_SIZE_NEW if veste_nuova else BADGE_SIZE
		flag.position = Vector2(-2.0, -2.0)   # in alto a sinistra (richiesta di Federico dell'11/11/2026)
		flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flag.name = "Distintivo"
		holder.add_child(flag)
	var caption := str(item.get("didascalia", ""))
	# carta di un'unita' (ha i campi dei potenziamenti): il numero dei soldati va in basso a destra, un 20% piu' piccolo, e in
	# basso a sinistra stanno scudo e spada uno sopra l'altro (richiesta di Federico, 2026-11-13)
	var unit_card := tex != null and (item.has("armi") or item.has("armatura"))
	if caption != "" or tex == null:
		var l := Label.new()
		l.text = caption if caption != "" else str(item.get("suggerimento", "?")).get_slice("\n", 0)
		# numeri delle truppe nitidi (richiesta di Federico, 2026-11-10): grassetto MSDF, piu' grande, contorno pieno
		l.add_theme_font_size_override("font_size", UNIT_NUMBER_SIZE if unit_card else (11 if tex != null else 9))
		l.add_theme_color_override("font_color", Color.WHITE if tex != null else INK)
		l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 1.0))
		l.add_theme_constant_override("outline_size", (0 if unit_card else 4) if tex != null else 0)
		if unit_card and UiTheme.crisp_text_bold() != null:
			# copia nitida senza contorni sovrapposti: a corpo 9 senza contorno il carattere variabile mostra puntini spuri
			l.add_theme_font_override("font", UiTheme.crisp_text_bold())
		elif tex != null and UiTheme.crisp_bold_font() != null:
			l.add_theme_font_override("font", UiTheme.crisp_bold_font())
		# didascalia sul piede dell'immagine: posizione fissa dall'alto (con le ancore in basso finiva sotto la carta,
		# perche' il contenitore cresce dopo, fino alla sua misura minima)
		if unit_card:
			# numero piccolo nitido: niente contorno (a questa misura chiude le cifre), su una targhetta scura semitrasparente
			# larga quanto le cifre, in basso a destra
			l.add_theme_stylebox_override("normal", StyleBoxEmpty.new())   # senza i margini del tema: si misura solo il testo
			var label_size := l.get_combined_minimum_size()
			var font := UiTheme.crisp_text_bold()
			var digits_w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UNIT_NUMBER_SIZE).x if font != null else label_size.x
			var plate_size := Vector2(ceilf(digits_w) + 4.0, UNIT_NUMBER_SIZE + 3.0)
			var plate := Panel.new()
			var plate_sb := StyleBoxFlat.new()
			plate_sb.bg_color = Color(0.10, 0.06, 0.03, 0.72)
			plate_sb.set_corner_radius_all(2)
			plate.add_theme_stylebox_override("panel", plate_sb)
			plate.size = plate_size
			plate.position = Vector2(size.x - plate_size.x, size.y - plate_size.y).round()
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			plate.name = "Targhetta"
			holder.add_child(plate)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			# il carattere nitido ha una riga alta: l'etichetta prende la sua misura minima e si centra sulla targhetta
			l.size = label_size
			l.position = (plate.position + plate_size / 2.0 - label_size / 2.0).round()
		elif tex != null:
			l.position = Vector2(1, size.y - 16)
		else:
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF if tex != null else TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.name = "Uomini"
		holder.add_child(l)
	# potenziamenti dagli edifici (richiesta di Federico, 2026-11-13), in basso a sinistra al posto del numero (che sta sul
	# lato opposto). Un'icona sola che mostra i due valori (richiesta di Federico, 2026-11-26): uno scudo con il bordo nel
	# metallo dell'armatura e, sul campo scuro, una spada nel metallo delle armi (ferro, bronzo, argento, oro). A livello 0
	# il bordo e' di legno scuro e la spada non c'e'.
	if unit_card:
		var emblem := upgrade_emblem(int(item.get("armatura", 0)), int(item.get("armi", 0)))
		if emblem != null:
			var mark := _upgrade_mark(emblem, UPGRADE_EMBLEM_SIZE)
			mark.position = Vector2(1.0, size.y - UPGRADE_EMBLEM_SIZE.y - 1.0)
			mark.name = "Potenziamenti"
			holder.add_child(mark)
	if bool(item.get("scelta", false)):
		# voce scelta per essere separata: cornice dorata sotto l'immagine
		var frame := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.85, 0.3, 0.28)
		sb.border_color = Color(0.85, 0.62, 0.12)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		frame.add_theme_stylebox_override("panel", sb)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.show_behind_parent = false
		holder.add_child(frame)
		holder.move_child(frame, 0)
	holder.gui_input.connect(_on_card_gui_input.bind(index))
	holder.set_meta("voce", index)
	holder.add_to_group(REVIEW_CARD_GROUP)
	return holder


## Clic, clic destro e trascinamento di una voce del pannello di rassegna. Il controllo premuto riceve anche i movimenti e
## il rilascio fuori dal suo rettangolo, quindi il trascinamento puo' finire sulla mappa.
func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			card_info.emit(index)
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_card_press = index
			_card_press_pos = mb.global_position
			_card_dragging = false
			return
		if _card_press == index:
			if _card_dragging:
				card_drag_released.emit(index)
			else:
				card_pressed.emit(index)
		_card_press = -1
		_card_dragging = false
	elif event is InputEventMouseMotion and _card_press == index:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		if not _card_dragging and mm.global_position.distance_to(_card_press_pos) > CARD_DRAG_THRESHOLD:
			_card_dragging = true
			card_drag_started.emit(index)
		if _card_dragging:
			card_drag_moved.emit(index)


## Indice della voce del pannello di rassegna sotto il punto `point` (viewport), -1 se non ce n'e' (ADR-147: carta lasciata
## su un'altra carta della stessa armata).
func review_card_at(point: Vector2) -> int:
	if not is_inside_tree():
		return -1
	for node in get_tree().get_nodes_in_group(REVIEW_CARD_GROUP):
		var c := node as Control
		if c == null or c.is_queued_for_deletion() or not c.is_visible_in_tree() or not is_ancestor_of(c):
			continue
		if c.get_global_rect().has_point(point):
			return int(c.get_meta("voce", -1))
	return -1


## Vero se il punto `point` (viewport) sta sulla barra in basso o sulla minimappa.
func covers(point: Vector2) -> bool:
	var pad := Vector2(_pad(), _pad())
	if _bar != null and Rect2(_bar.position - pad * ui_scale, (Vector2(BAR_W, BAR_H) + pad * 2.0) * ui_scale).has_point(point):
		return true
	return _minimap != null and Rect2(_minimap.position, _minimap.size * ui_scale).has_point(point)


## Pergamena del pannello di rassegna dentro una cornice di pietra (TOOLTIP_BACK dell'originale a nove parti).
func _review_style() -> StyleBox:
	if veste_nuova:
		var paper := StyleBoxFlat.new()
		paper.bg_color = UiTheme.PAPER
		paper.border_color = UiTheme.PANEL_BORDER
		paper.set_border_width_all(1)
		paper.set_corner_radius_all(6)
		return paper
	var tex := _tex("campmap/TOOLTIP_BACK.BIF")
	if tex == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = UiTheme.PAPER
		flat.border_color = Color("6c6c6c")
		flat.set_border_width_all(4)
		return flat
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = 14
	s.texture_margin_right = 14
	s.texture_margin_top = 12
	s.texture_margin_bottom = 12
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return s


## Cornice di pietra della minimappa, presa dal bordo di info_panel (pietra grigia dell'originale).
func _stone_style() -> StyleBox:
	if veste_nuova:
		var wood := StyleBoxFlat.new()
		wood.bg_color = Color("3a2718")
		wood.border_color = BRASS_DARK
		wood.set_border_width_all(1)
		wood.corner_radius_bottom_right = 4
		return wood
	var tex := _tex("campmap/info_panel.BIF")
	if tex == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color("6f7072")
		flat.border_color = Color("3d3e40")
		flat.set_border_width_all(2)
		return flat
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(0, 36, 100, 79)
	var s := StyleBoxTexture.new()
	s.texture = atlas
	s.texture_margin_left = 5
	s.texture_margin_right = 5
	s.texture_margin_top = 4
	s.texture_margin_bottom = 4
	return s


func _flat_panel(size: Vector2) -> Panel:
	var p := Panel.new()
	p.size = size
	var s := StyleBoxFlat.new()
	s.bg_color = Color("6f7072")
	s.border_color = Color("3d3e40")
	s.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# --- veste nuova: legno, ottone e pergamena disegnati a codice --------------------------------------------------------


## Texture della veste nuova, se c'e' ed e' importata; altrimenti null.
static func skin_texture(name: String) -> Texture2D:
	var path := SKIN_DIR + name + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Medaglione dipinto di un pulsante informativo (ADR-038): `assets/ui/veste/medaglione_<nome><stato>.png`, 140x132, dai
## simboli generati con l'IA locale (`tools/prepara_medaglioni.py`). Stati: "" normale, "_sopra" col puntatore sopra,
## "_premuto". Sullo schermo e' largo da 50 a 80 punti: porta le riduzioni intermedie (mipmap), altrimenti rimpicciolito
## sgrana. Null se il file manca.
static func medallion_texture(name: String, state: String = "") -> Texture2D:
	return painted_texture("medaglione_" + name + state)


## Immagine dipinta della veste nuova (`assets/ui/veste/<nome>.png`: medaglioni, carte, freccia, pennacchi; ADR-038 e
## 040) con le riduzioni intermedie (mipmap): sono molto piu' grandi della misura a schermo e senza sgranerebbero. Chi la
## mostra usa il filtro LINEAR_WITH_MIPMAPS. Null se il file manca: allora si usa l'immagine dell'originale.
static var _painted: Dictionary = {}
static func painted_texture(name: String) -> Texture2D:
	if _painted.has(name):
		return _painted[name] as Texture2D
	var tex := skin_texture(name)
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_painted[name] = tex
	return tex


## Pennacchio del comandante per il percorso dell'originale (`campmap/is_king_mon.BIF`, `is_heir_mon`, `is_noble_mon`,
## `is_merc_mon`): con la veste nuova quello dipinto (`pennacchio_king.png` ...), altrimenti, o se manca, quello
## dell'installazione. Null se non c'e' nessuno dei due.
static func pennant_texture(original_path: String) -> Texture2D:
	if original_path == "":
		return null
	if veste_nuova:
		var kind := original_path.get_file().get_basename().trim_prefix("is_").trim_suffix("_mon")
		var painted := painted_texture("pennacchio_" + kind)
		if painted != null:
			return painted
	if original_path == CampaignUiText.ADMIRAL_PENNANT:
		original_path = "campmap/is_noble_mon.BIF"   # l'originale non ha il pennacchio dell'ammiraglio (ADR-062)
	return AssetLibrary.texture(original_path) if AssetLibrary.is_available() else null


## Fondo di legno: la texture ripetuta con un'ombra verso il basso, oppure (senza texture) la sola sfumatura dal bruno
## chiaro al bruno scuro.
func _wood(size: Vector2) -> TextureRect:
	var tex := skin_texture("legno")
	if tex == null:
		return _shade(size, WOOD_TOP, WOOD_BOTTOM)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # prima della misura: altrimenti l'altezza minima e' quella della texture
	r.stretch_mode = TextureRect.STRETCH_TILE
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(_shade(size, Color(1.0, 0.9, 0.75, 0.10), Color(0, 0, 0, 0.42)))
	return r


## Rettangolo con una sfumatura verticale da `top` a `bottom`.
func _shade(size: Vector2, top: Color, bottom: Color) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 64
	var r := TextureRect.new()
	r.texture = gt
	r.size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Ornamenti della barra, sotto pulsanti e carte: anelli d'ottone dei medaglioni, piastra dello stemma, targhe di pergamena
## di tesoro e anno, cinghie di ferro con borchie tra i tre blocchi, filo d'ottone in alto e angolari.
func _draw_bar_chrome(c: Control) -> void:
	c.draw_set_transform(Vector2(BAR_PAD, BAR_PAD))   # si disegna nelle coordinate dei controlli (barra 800x115)
	var right_x := BAR_W - RIGHT_W
	c.draw_rect(Rect2(-BAR_PAD, 37, LEFT_W - 20.0 + BAR_PAD, 1), Color(OUTLINE, 0.7))
	c.draw_rect(Rect2(-BAR_PAD, 38, LEFT_W - 20.0 + BAR_PAD, 1), Color(BRASS_DARK, 0.6))
	for i in INFO_BUTTONS.size():
		var center := Vector2(info_x(i) + 17.5, 3.0 + 16.5)
		c.draw_circle(center, 17.4, OUTLINE)
		if medallion_texture(str(INFO_BUTTONS[i])) == null:   # il medaglione dipinto porta gia' il suo anello
			c.draw_arc(center, 16.6, 0.0, TAU, 40, BRASS, 1.4, true)
	var shield_center := SHIELD_RECT.get_center()
	c.draw_circle(shield_center, 25.0, OUTLINE)
	c.draw_circle(shield_center, 24.0, WOOD_DARK)
	c.draw_arc(shield_center, 23.5, 0.0, TAU, 48, BRASS, 1.0, true)
	var plate_style := StyleBoxFlat.new()   # targhe di pergamena stondate per tesoro e anno
	plate_style.bg_color = UiTheme.PAPER
	plate_style.border_color = UiTheme.PANEL_BORDER
	plate_style.set_border_width_all(1)
	plate_style.set_corner_radius_all(4)
	plate_style.shadow_color = OUTLINE
	plate_style.shadow_size = 1
	var plates: Array[Rect2] = [Rect2(right_x + 12, 7, 91, 19), Rect2(right_x + 12, 33, 91, 19)]
	for plate in plates:
		c.draw_style_box(plate_style, plate)
	var straps: Array[float] = [LEFT_W + 1.5, right_x - 1.5]
	for x in straps:
		c.draw_rect(Rect2(x - 3.0, -BAR_PAD, 6, BAR_H + 2.0 * BAR_PAD), OUTLINE)
		c.draw_rect(Rect2(x - 2.0, -BAR_PAD, 4, BAR_H + 2.0 * BAR_PAD), IRON)
		var rivets: Array[float] = [4.0, 40.0, 76.0, 111.0]
		for y in rivets:
			c.draw_circle(Vector2(x, y), 1.6, BRASS)


## Piastra del pulsante di fine anno: rosso scuro (ADR-013) lavorato come una targa, con cornice e filetto d'ottone,
## borchie agli angoli, losanghe ai lati della scritta e un filo di luce in alto (richiesta di Federico dell'11/11: non un
## semplice rettangolo rosso).
func _seal_plate(button: Control) -> Panel:
	var plate := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SEAL_RED
	sb.border_color = OUTLINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	plate.add_theme_stylebox_override("panel", sb)
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.draw.connect(_draw_seal_plate.bind(plate))
	button.mouse_entered.connect(func() -> void: sb.bg_color = SEAL_RED_HOVER)
	button.mouse_exited.connect(func() -> void: sb.bg_color = SEAL_RED)
	return plate


func _draw_seal_plate(plate: Control) -> void:
	var w := plate.size.x
	var h := plate.size.y
	plate.draw_rect(Rect2(3, 3, w - 6, h * 0.42), Color(1, 1, 1, 0.07))                     # luce sulla meta' alta
	plate.draw_rect(Rect2(3, h - 6, w - 6, 3), Color(0, 0, 0, 0.22))                        # ombra in basso
	plate.draw_rect(Rect2(1.5, 1.5, w - 3, h - 3), BRASS, false, 1.0)                       # cornice d'ottone
	plate.draw_rect(Rect2(3.5, 3.5, w - 7, h - 7), Color(OUTLINE, 0.8), false, 1.0)
	plate.draw_rect(Rect2(6.5, 6.5, w - 13, h - 13), BRASS_DARK, false, 1.0)                # filetto interno
	var corners: Array[Vector2] = [Vector2(6.5, 6.5), Vector2(w - 6.5, 6.5), Vector2(6.5, h - 6.5), Vector2(w - 6.5, h - 6.5)]
	for corner in corners:
		plate.draw_circle(corner, 3.0, OUTLINE)
		plate.draw_circle(corner, 2.2, BRASS)
	var sides: Array[float] = [16.0, w - 16.0]
	for x in sides:
		var c := Vector2(x, h / 2.0)
		plate.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4.5), c + Vector2(3.5, 0), c + Vector2(0, 4.5), c + Vector2(-3.5, 0)]), BRASS)
		plate.draw_line(c + Vector2(0, -9), c + Vector2(0, -6), BRASS_DARK, 1.0)
		plate.draw_line(c + Vector2(0, 6), c + Vector2(0, 9), BRASS_DARK, 1.0)


## Freccia per scorrere le province: tassello di legno con il triangolo d'ottone (su = precedente, giu' = successiva).
func _wood_arrow(pos: Vector2, size: Vector2, step: int) -> void:
	var b := Button.new()
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = (Lang.t("Provincia precedente") if step < 0 else Lang.t("Provincia successiva")) + Lang.t(" (tasti , e .; con Maiusc solo quelle con qualcosa in coda)")
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = WOOD_TOP if state == "hover" else WOOD_DARK
		sb.border_color = BRASS_DARK
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func() -> void: cycle_province.emit(step))
	var painted := painted_texture("freccia")
	if painted != null:
		# punta di freccia d'ottone dipinta (ADR-040): in su per la provincia precedente, capovolta per la successiva
		var head := TextureRect.new()
		head.name = "Freccia"
		head.texture = painted
		head.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		head.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.size = ARROW_HEAD
		head.position = ((size - ARROW_HEAD) / 2.0).round()
		head.flip_v = step > 0
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(head)
		_bar.add_child(b)
		return
	var tri := Control.new()
	tri.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tri.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dir := -1.0 if step < 0 else 1.0
	var mid := size / 2.0
	tri.draw.connect(func() -> void:
		tri.draw_colored_polygon(PackedVector2Array([mid + Vector2(-5, -3 * dir), mid + Vector2(5, -3 * dir), mid + Vector2(0, 5 * dir)]), BRASS))
	b.add_child(tri)
	_bar.add_child(b)


## Icona di un potenziamento sulla carta, alla misura data, senza intercettare il mouse.
static func _upgrade_mark(tex: Texture2D, mark_size: Vector2) -> TextureRect:
	var mark := TextureRect.new()
	mark.texture = tex
	mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size = mark_size
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return mark


## Metalli dei livelli 1-4 (ferro, bronzo, argento, oro): chiaro, medio, scuro, come le icone in assets/icone.
const UPGRADE_METALS := [
	["#c3c8ce", "#8d949c", "#3d4248"],
	["#e9a96a", "#b06a34", "#5c3214"],
	["#ffffff", "#cfd5dd", "#6f7782"],
	["#fff1a8", "#e0a91e", "#7a5207"],
]
const UPGRADE_NO_METAL := ["#6b5640", "#4a3a2a", "#2a1f15"]   ## bordo dello scudo senza potenziamento dell'armatura
static var _upgrade_emblems := {}


## Emblema dei potenziamenti (richiesta di Federico, 2026-11-26): scudo col bordo nel metallo dell'armatura e spada nel
## metallo delle armi sul campo scuro. Disegnato dall'SVG in memoria (nitido a ogni scala); null se entrambi sono a 0.
static func upgrade_emblem(armour: int, weapons: int) -> Texture2D:
	armour = clampi(armour, 0, TroopUpgrades.MAX_LEVEL)
	weapons = clampi(weapons, 0, TroopUpgrades.MAX_LEVEL)
	if armour == 0 and weapons == 0:
		return null
	var key := "%d_%d" % [armour, weapons]
	if not _upgrade_emblems.has(key):
		var image := Image.new()
		if image.load_svg_from_string(upgrade_emblem_svg(armour, weapons), 1.0) == OK:
			image.generate_mipmaps()
			_upgrade_emblems[key] = ImageTexture.create_from_image(image)
		else:
			_upgrade_emblems[key] = null
	return _upgrade_emblems[key]


## Sorgente SVG 64x64 dell'emblema (vedi upgrade_emblem).
static func upgrade_emblem_svg(armour: int, weapons: int) -> String:
	var rim: Array = UPGRADE_METALS[armour - 1] if armour > 0 else UPGRADE_NO_METAL
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><defs>'
	svg += '<linearGradient id="a" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="%s"/><stop offset="0.55" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % rim
	if weapons > 0:
		svg += '<linearGradient id="w" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="%s"/><stop offset="0.5" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % UPGRADE_METALS[weapons - 1]
	svg += '</defs>'
	svg += '<path d="M32 3 L57 11 L57 30 C57 46 46 55 32 61 C18 55 7 46 7 30 L7 11 Z" fill="url(#a)" stroke="#120a04" stroke-width="3.5" stroke-linejoin="round"/>'
	svg += '<path d="M32 11 L49 16.5 L49 30 C49 41 42 48 32 52.5 C22 48 15 41 15 30 L15 16.5 Z" fill="#2b1a0d" stroke="#120a04" stroke-width="1.5" stroke-linejoin="round"/>'
	if weapons > 0:
		var mid: String = UPGRADE_METALS[weapons - 1][1]
		svg += '<g transform="rotate(%d 32 32)"><g stroke="#120a04" stroke-width="1.8" stroke-linejoin="round">' % (180 if UPGRADE_EMBLEM_SWORD_DOWN else 0)
		svg += '<path d="M27.5 21 L32 11.5 L36.5 21 L36.5 39 L27.5 39 Z" fill="url(#w)"/>'
		svg += '<rect x="20" y="38.5" width="24" height="6" rx="2" fill="%s"/>' % mid
		svg += '<rect x="29.5" y="44.5" width="5" height="5.5" fill="#5a3418"/>'
		svg += '<circle cx="32" cy="52.5" r="3.6" fill="%s"/></g></g>' % mid
	return svg + '</svg>'


static var _upgrade_icons := {}


## Icona del potenziamento: `kind` «armatura» (scudo) o «armi» (spada), `level` 1-4 (ferro, bronzo, argento, oro); null a 0.
static func upgrade_icon(kind: String, level: int) -> Texture2D:
	if level <= 0:
		return null
	var key := "%s_%d" % [kind, clampi(level, 1, TroopUpgrades.MAX_LEVEL)]
	if not _upgrade_icons.has(key):
		var path := "res://assets/icone/%s.svg" % key
		_upgrade_icons[key] = load(path) if ResourceLoader.exists(path) else null
	return _upgrade_icons[key]
