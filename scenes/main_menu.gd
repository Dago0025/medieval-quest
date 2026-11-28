extends Control
## Menu iniziale (fase 8c): Nuova campagna (scelta della fazione e della difficolta'), Continua (l'ultimo salvataggio), Carica,
## Impostazioni, Esci. Le scelte passano alla mappa con GameLaunch; le immagini sono quelle dell'originale (originale/_ASSET_EXPORT).

const MAP_SCENE := "res://scenes/campaign_map.tscn"
const BACKGROUND := "frontend_files/default_parchment_wide.tga"
const SIDE_PARCHMENT := "frontend_files/Main_Menu/parch322x536_no_border.BIF"
const DEFAULT_FACTION := "FN_DANISH"
## Veste nuova (ADR-030, scelte di Federico dell'11/11): sfondo dipinto a tutto schermo e menu in una colonna a sinistra
## con l'emblema degli Auror. Se le immagini mancano resta il menu di prima. Dal 27/11/2026 lo sfondo e' il grande porto
## (MQ_SFONDO_C, Pro Image 3, con la seppia leggera di tools/seppia_sfondo.py) al posto del castello nella nebbia.
const NEW_BACKGROUND := "res://assets/ui/menu/sfondo.jpg"
const NEW_EMBLEM := "res://assets/stemmi/auror_grande.png"
const HOME_SKETCH := "Credits/Out/pic_03.tga"   ## schizzo a matita dei titoli di coda: un guerriero senza insegne
## ADR-068: tre clic sul logo (emblema o titolo) entro questo tempo attivano o spengono la modalita' Auror.
const TRIPLE_CLICK_MS := 900

var _data: CampaignData = null
var _home: Control
var _new_page: Control
var _settings_page: Control
var _saves: SaveLoadPanel
var _continue_button: Button
var _faction_list: ItemList
var _faction_ids: PackedStringArray = []
var _faction_shield: TextureRect
var _faction_name: Label
var _faction_info: Label
var _faction_motto: Label            ## ADR-089: titolo dei tratti storici
var _faction_traits: RichTextLabel   ## ADR-089: descrizione, bonus (verde) e malus (rosso)
var _traits: FactionTraits
var _difficulty_new: OptionButton
var _difficulty_settings: OptionButton
var _tilt_slider: HSlider
var _tilt_label: Label
var _music_slider: HSlider
var _effects_slider: HSlider
var _message: Label
var _logo_clicks: Array[int] = []
var _logo: Control = null   ## emblema (o titolo) che lampeggia al cambio di modalita'
var _updates_check: CheckButton   ## ADR-144: controllo degli aggiornamenti all'avvio (Impostazioni)
var _update_panel: PanelContainer = null   ## ADR-144: avviso della nuova versione, solo nella pagina iniziale
var _version_label: Label


func _ready() -> void:
	Lang.apply_saved()   # lingua scelta nelle sessioni precedenti (ADR-066)
	Scenario.begin_session()   # ADR-068: si parte dallo scenario storico; la modalita' Auror col triplo clic sul logo
	UiTheme.install()
	var back := TextureRect.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	back.texture = AssetLibrary.texture(BACKGROUND) if AssetLibrary.is_available() else null
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	if _new_look():
		back.texture = load(NEW_BACKGROUND) as Texture2D
		add_child(_left_shade())
	if back.texture == null:
		var plain := ColorRect.new()
		plain.color = Color(0.29, 0.17, 0.08)
		plain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(plain)
	_home = _build_home()
	add_child(_home)
	_new_page = _build_new_page()
	add_child(_new_page)
	_settings_page = _build_settings_page()
	add_child(_settings_page)
	_saves = SaveLoadPanel.new()
	_saves.load_requested.connect(_on_load_chosen)
	add_child(_saves)
	_message = Label.new()
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.offset_top = -48
	_message.offset_bottom = -20
	_message.add_theme_color_override("font_color", Color(0.98, 0.92, 0.78))
	add_child(_message)
	_version_label = _build_version_label()
	add_child(_version_label)
	_show_page(_home)
	GameAudio.play_music("menu")
	var updates := UpdateCheck.new()   # ADR-144: nuove versioni su GitHub, in silenzio se non c'e' rete
	updates.update_found.connect(_show_update)
	add_child(updates)
	updates.start()
	if not GameFiles.campaign_available():
		_message.text = Lang.t("Dati della campagna non trovati: %s") % GameFiles.startpos()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	if _saves.visible:
		_saves.close()
	elif not _home.visible:
		_show_page(_home)


# --- pagine ---------------------------------------------------------------------------------------------------------


func _page(width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(width, 0)
	return panel


func _box(panel: Control, separation: int = 10) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	margin.add_child(box)
	return box


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 40)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func() -> void: GameAudio.play_sfx("menu_clic"))
	b.pressed.connect(action)
	return b


## Vero se il menu usa la veste nuova: interruttore generale acceso e sfondo presente.
static func _new_look() -> bool:
	return OriginalHud.veste_nuova and ResourceLoader.exists(NEW_BACKGROUND)


## Ombra che scurisce il terzo sinistro dello sfondo, dove sta la colonna del menu.
func _left_shade() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.03, 0.02, 0.72))
	g.set_color(1, Color(0.04, 0.03, 0.02, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 64
	gt.height = 8
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.anchor_right = 0.5
	r.anchor_bottom = 1.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Pagina iniziale della veste nuova: colonna a sinistra con emblema, titolo e i cinque comandi.
func _build_home_column() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 90
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := _box(panel, 12)
	if ResourceLoader.exists(NEW_EMBLEM):
		var emblem := TextureRect.new()
		emblem.texture = load(NEW_EMBLEM) as Texture2D
		emblem.custom_minimum_size = Vector2(0, 150)
		emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_make_logo(emblem)
		box.add_child(emblem)
	var title := Label.new()
	title.text = UiTheme.GAME_NAME
	title.theme_type_variation = "Title"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_make_logo(title)
	box.add_child(title)
	box.add_child(UiTheme.divider())
	box.add_child(_button(Lang.t("Nuova campagna"), _on_new_pressed))
	_continue_button = _button(Lang.t("Continua"), _on_continue)
	box.add_child(_continue_button)
	box.add_child(_button(Lang.t("Carica partita"), func() -> void: _saves.open_load()))
	box.add_child(_button(Lang.t("Impostazioni"), func() -> void: _show_page(_settings_page)))
	box.add_child(_button(Lang.t("Esci"), func() -> void: get_tree().quit()))
	box.add_child(UiTheme.divider())
	box.add_child(_language_row())
	for b in box.get_children():
		if b is Button:
			(b as Button).custom_minimum_size = Vector2(290, 46)
			(b as Button).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return panel


func _build_home() -> Control:
	if _new_look():
		return _build_home_column()
	var holder := HBoxContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BOTH
	holder.add_theme_constant_override("separation", 30)
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	var sketch_tex := AssetLibrary.texture(HOME_SKETCH) if AssetLibrary.is_available() else null
	if sketch_tex != null:
		var sketch := UiTheme.picture(sketch_tex, Vector2(640, 480))
		sketch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		holder.add_child(sketch)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_child(panel)
	var box := _box(panel, 12)
	var title := Label.new()
	title.text = UiTheme.GAME_NAME
	title.theme_type_variation = "Title"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_make_logo(title)
	box.add_child(title)
	box.add_child(UiTheme.divider())
	box.add_child(_button(Lang.t("Nuova campagna"), _on_new_pressed))
	_continue_button = _button(Lang.t("Continua"), _on_continue)
	box.add_child(_continue_button)
	box.add_child(_button(Lang.t("Carica partita"), func() -> void: _saves.open_load()))
	box.add_child(_button(Lang.t("Impostazioni"), func() -> void: _show_page(_settings_page)))
	box.add_child(_button(Lang.t("Esci"), func() -> void: get_tree().quit()))
	box.add_child(UiTheme.divider())
	box.add_child(_language_row())
	for b in box.get_children():
		if b is Button:
			(b as Button).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return holder


## Logo del menu (emblema e titolo): risponde ai clic per il triplo clic della modalita' Auror (ADR-068).
func _make_logo(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.gui_input.connect(_on_logo_input)
	if _logo == null:
		_logo = node


func _on_logo_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var now := Time.get_ticks_msec()
	_logo_clicks.append(now)
	while not _logo_clicks.is_empty() and now - _logo_clicks[0] > TRIPLE_CLICK_MS:
		_logo_clicks.remove_at(0)
	if _logo_clicks.size() >= 3:
		_logo_clicks.clear()
		_toggle_auror()


## Triplo clic sul logo: modalita' Auror (gli Auror con tutti i potenziamenti al posto dei Danesi) o scenario storico.
func _toggle_auror() -> void:
	Scenario.set_auror(not Scenario.auror)
	_data = null   # fazioni, nomi e stemmi si rileggono per lo scenario nuovo
	if Scenario.auror:
		_message.text = Lang.t("Modalità Auror attivata: gli Auror entrano in gioco con tutti i loro poteri.")
		GameAudio.play_sfx("evento_cristiano")
	else:
		_message.text = Lang.t("Modalità Auror disattivata: si gioca lo scenario storico.")
		GameAudio.play_sfx("chiudi")
	if _logo != null:
		var flash := create_tween()
		_logo.modulate = Color(1.6, 1.4, 0.9) if Scenario.auror else Color(0.6, 0.6, 0.6)
		flash.tween_property(_logo, "modulate", Color.WHITE, 0.8)


## Scelta della lingua (ADR-066): Italiano / English. La scelta si salva subito nelle impostazioni, vale anche nelle
## sessioni successive, e il menu si ricarica nella lingua nuova.
func _language_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var group := ButtonGroup.new()
	for code in Lang.LANGUAGES:
		var b := Button.new()
		b.text = str(Lang.NAMES[code])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = code == Lang.current()
		b.custom_minimum_size = Vector2(130, 34)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.tooltip_text = "Lingua del gioco" if code == Lang.IT else "Game language"
		b.pressed.connect(_on_language_chosen.bind(code))
		row.add_child(b)
	return row


func _on_language_chosen(code: String) -> void:
	if code == Lang.current():
		return
	GameAudio.play_sfx("menu_clic")
	Lang.choose(code)
	get_tree().reload_current_scene.call_deferred()


func _build_new_page() -> Control:
	var panel := _page(900)
	var box := _box(panel, 8)
	var title := Label.new()
	title.text = Lang.t("Scegli la tua fazione")
	title.theme_type_variation = "Title"
	box.add_child(title)
	box.add_child(UiTheme.divider())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	_faction_list = ItemList.new()
	_faction_list.custom_minimum_size = Vector2(300, 440)
	_faction_list.fixed_icon_size = Vector2i(26, 30)
	_faction_list.item_selected.connect(_on_faction_selected)
	_faction_list.item_activated.connect(func(_i: int) -> void: _on_start())
	row.add_child(_faction_list)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 8)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	detail.add_child(head)
	_faction_shield = UiTheme.picture(null, Vector2(110, 130))
	head.add_child(_faction_shield)
	var names := VBoxContainer.new()
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	_faction_name = Label.new()
	_faction_name.theme_type_variation = "Title"
	_faction_name.add_theme_font_size_override("font_size", 30)
	names.add_child(_faction_name)
	_faction_motto = Label.new()
	_faction_motto.add_theme_color_override("font_color", UiTheme.INK_TITLE)
	_faction_motto.add_theme_font_size_override("font_size", 19)
	names.add_child(_faction_motto)
	_faction_info = Label.new()
	_faction_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_faction_info.custom_minimum_size = Vector2(440, 0)
	detail.add_child(_faction_info)
	_faction_traits = RichTextLabel.new()
	_faction_traits.bbcode_enabled = true
	_faction_traits.fit_content = true
	_faction_traits.scroll_active = false
	_faction_traits.selection_enabled = false
	_faction_traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_faction_traits.custom_minimum_size = Vector2(440, 0)
	_faction_traits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_faction_traits.add_theme_color_override("default_color", UiTheme.INK)
	_faction_traits.add_theme_font_size_override("normal_font_size", 15)
	_faction_traits.add_theme_font_size_override("italics_font_size", 15)
	_faction_traits.add_theme_font_size_override("bold_font_size", 15)
	_faction_traits.add_theme_constant_override("line_separation", 2)
	if UiTheme.italic_font() != null:
		_faction_traits.add_theme_font_override("italics_font", UiTheme.italic_font())
	if UiTheme.bold_font() != null:
		_faction_traits.add_theme_font_override("bold_font", UiTheme.bold_font())
	detail.add_child(_faction_traits)
	detail.add_child(UiTheme.divider())
	var diff_row := HBoxContainer.new()
	detail.add_child(diff_row)
	var diff_label := Label.new()
	diff_label.text = Lang.t("Difficoltà: ")
	diff_row.add_child(diff_label)
	_difficulty_new = _difficulty_button()
	diff_row.add_child(_difficulty_new)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	detail.add_child(buttons)
	var back := Button.new()
	back.text = Lang.t("Indietro (Esc)")
	back.pressed.connect(func() -> void: _show_page(_home))
	buttons.add_child(back)
	var start := Button.new()
	start.text = Lang.t("Inizia la campagna")
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(_on_start)
	buttons.add_child(start)
	return panel


func _build_settings_page() -> Control:
	var panel := _page(560)
	var box := _box(panel, 10)
	var title := Label.new()
	title.text = Lang.t("Impostazioni")
	title.theme_type_variation = "Title"
	box.add_child(title)
	box.add_child(UiTheme.divider())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	grid.add_child(_label(Lang.t("Difficoltà dell'IA")))
	_difficulty_settings = _difficulty_button()
	grid.add_child(_difficulty_settings)
	grid.add_child(_label(Lang.t("Inclinazione della plancia")))
	var tilt_row := HBoxContainer.new()
	_tilt_slider = _slider(MapProjection.MIN_TILT, MapProjection.MAX_TILT, 0.1)
	_tilt_slider.value_changed.connect(func(v: float) -> void: _tilt_label.text = Lang.t("vista dall'alto") if v <= 1.001 else "%.1f" % v)
	tilt_row.add_child(_tilt_slider)
	_tilt_label = Label.new()
	_tilt_label.custom_minimum_size = Vector2(120, 0)
	tilt_row.add_child(_tilt_label)
	grid.add_child(tilt_row)
	grid.add_child(_label(Lang.t("Volume della musica")))
	_music_slider = _slider(0.0, 1.0, 0.05)
	grid.add_child(_music_slider)
	grid.add_child(_label(Lang.t("Volume degli effetti")))
	_effects_slider = _slider(0.0, 1.0, 0.05)
	grid.add_child(_effects_slider)
	grid.add_child(_label(Lang.t("Nuove versioni")))
	_updates_check = CheckButton.new()
	_updates_check.text = Lang.t("Controlla all'avvio")
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_updates_check.add_theme_color_override(c, UiTheme.INK)   # il tema dei pulsanti ha il testo bianco
	_updates_check.tooltip_text = Lang.t("All'avvio chiede a GitHub se c'è una versione più recente del gioco.")
	grid.add_child(_updates_check)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var back := Button.new()
	back.text = Lang.t("Indietro (Esc)")
	back.pressed.connect(func() -> void: _show_page(_home))
	buttons.add_child(back)
	var save := Button.new()
	save.text = Lang.t("Salva")
	save.pressed.connect(_on_settings_save)
	buttons.add_child(save)
	return panel


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _slider(lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(220, 24)
	return s


func _difficulty_button() -> OptionButton:
	var b := OptionButton.new()
	for d in UserSettings.DIFFICULTIES:
		b.add_item(Lang.t(str(UserSettings.DIFFICULTY_NAMES[d])))
	b.select(UserSettings.DIFFICULTIES.find(UserSettings.difficulty()))
	return b


func _show_page(page: Control) -> void:
	for p in [_home, _new_page, _settings_page]:
		p.visible = p == page
	_version_label.visible = page == _home
	if _update_panel != null:
		_update_panel.visible = page == _home
	if page == _home:
		_continue_button.disabled = SaveGame.list_summaries().is_empty()
	elif page == _settings_page:
		_difficulty_settings.select(UserSettings.DIFFICULTIES.find(UserSettings.difficulty()))
		_tilt_slider.value = UserSettings.tilt()
		_tilt_slider.value_changed.emit(_tilt_slider.value)
		_music_slider.value = float(UserSettings.get_value("volume_musica"))
		_effects_slider.value = float(UserSettings.get_value("volume_effetti"))
		_updates_check.button_pressed = UpdateCheck.enabled()


# --- aggiornamenti (ADR-144) -----------------------------------------------------------------------------------------


## Versione in uso, discreta nell'angolo in basso a destra della pagina iniziale.
func _build_version_label() -> Label:
	var l := Label.new()
	l.text = Lang.t("Versione %s") % UpdateCheck.current_version()
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.offset_right = -18
	l.offset_bottom = -10
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.98, 0.92, 0.78, 0.75))
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Avviso della nuova versione in basso a destra: Scarica (installer o pagina della release), Novita' (pagina),
## Piu' tardi (chiude fino al prossimo avvio), Salta questa versione (non la ripropone piu').
func _show_update(info: Dictionary) -> void:
	if _update_panel != null:
		_update_panel.queue_free()
	var version := str(info.get("versione", ""))
	var page := str(info.get("pagina", UpdateCheck.RELEASES_PAGE))
	var download := str(info.get("installer", ""))
	if download == "":
		download = page
	_update_panel = PanelContainer.new()
	_update_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_update_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_update_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_update_panel.offset_right = -24
	_update_panel.offset_bottom = -40
	_update_panel.custom_minimum_size = Vector2(440, 0)
	var box := _box(_update_panel, 8)
	var title := Label.new()
	title.text = Lang.t("Nuova versione disponibile")
	title.theme_type_variation = "Title"
	box.add_child(title)
	var text := Label.new()
	text.text = Lang.t("%s %s è pronto da scaricare. Versione in uso: %s.") % [UiTheme.GAME_NAME, version, UpdateCheck.current_version()]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(396, 0)
	box.add_child(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var get_it := Button.new()
	get_it.text = Lang.t("Scarica")
	get_it.tooltip_text = download
	get_it.pressed.connect(func() -> void:
		GameAudio.play_sfx("menu_clic")
		OS.shell_open(download))
	row.add_child(get_it)
	if download != page:
		var notes := Button.new()
		notes.text = Lang.t("Novità")
		notes.tooltip_text = page
		notes.pressed.connect(func() -> void:
			GameAudio.play_sfx("menu_clic")
			OS.shell_open(page))
		row.add_child(notes)
	var later := Button.new()
	later.text = Lang.t("Più tardi")
	later.pressed.connect(func() -> void:
		GameAudio.play_sfx("chiudi")
		_update_panel.queue_free()
		_update_panel = null)
	row.add_child(later)
	var skip := Button.new()
	skip.text = Lang.t("Salta questa versione")
	skip.pressed.connect(func() -> void:
		GameAudio.play_sfx("chiudi")
		UpdateCheck.skip_version(version)
		_update_panel.queue_free()
		_update_panel = null)
	row.add_child(skip)
	add_child(_update_panel)
	_update_panel.visible = _home.visible


# --- azioni ---------------------------------------------------------------------------------------------------------


func _on_new_pressed() -> void:
	if not _ensure_campaign():
		return
	_faction_list.clear()
	_faction_ids = playable_factions(_data)
	for id in _faction_ids:
		_faction_list.add_item(FactionStyle.name_of(id), AssetLibrary.faction_shield(id, false))
	var start := maxi(0, _faction_ids.find(DEFAULT_FACTION))
	if not _faction_ids.is_empty():
		_faction_list.select(start)
		_on_faction_selected(start)
	_difficulty_new.select(UserSettings.DIFFICULTIES.find(UserSettings.difficulty()))
	_show_page(_new_page)


## Fazioni giocabili della campagna: le attive (ribelli esclusi), FN_DANISH per prima (gli Auror, o i Danesi nello scenario
## storico di ADR-068), poi in ordine di nome.
static func playable_factions(data: CampaignData) -> PackedStringArray:
	var ids: Array[String] = []
	for f in data.active_factions():
		if f.id != "FN_REBEL":
			ids.append(f.id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		if a == DEFAULT_FACTION or b == DEFAULT_FACTION:
			return a == DEFAULT_FACTION
		return FactionStyle.name_of(a).naturalnocasecmp_to(FactionStyle.name_of(b)) < 0)
	return PackedStringArray(ids)


## Riassunto della fazione per la scheda: religione, province, capitale, tesoro iniziale.
static func faction_summary(data: CampaignData, faction_id: String) -> String:
	var f := data.faction(faction_id)
	if f == null:
		return ""
	var lines := PackedStringArray()
	lines.append(Lang.t("Religione: %s") % CampaignUiReligion.religion_label(f.religion))
	lines.append(Lang.t("Province all'inizio: %d") % data.regions_owned_by(faction_id).size())
	if f.leader_region != "":
		lines.append(Lang.t("Capitale: %s") % RegionNames.shown(data, f.leader_region))
	if not f.treasury.is_empty():
		lines.append(Lang.t("Tesoro iniziale: %d denari") % f.treasury[0])
	return "\n".join(lines)


## Tratti storici della fazione per la scheda (ADR-089): descrizione in corsivo, poi «Punti di forza» (verde) e «Punti
## deboli» (rosso), una riga per voce. Vuoto se la fazione non ha tratti.
static func traits_bbcode(traits: FactionTraits, faction_id: String) -> String:
	if traits == null or not traits.has_traits(faction_id):
		return ""
	var out := PackedStringArray()
	var desc := traits.description(faction_id)
	if desc != "":
		out.append("[i]%s[/i]" % desc)
	for good in [true, false]:
		var color := (UiTheme.INK_GOOD if good else UiTheme.INK_BAD).to_html(false)
		var rows := PackedStringArray()
		for line in traits.lines(faction_id):
			if bool(line["bonus"]) == good:
				rows.append("[color=#%s]•  %s[/color]" % [color, str(line["testo"])])
		if not rows.is_empty():
			out.append("[b]%s[/b]" % (Lang.t("Punti di forza") if good else Lang.t("Punti deboli")))
			out.append_array(rows)
	return "\n".join(out)


func _on_faction_selected(index: int) -> void:
	if index < 0 or index >= _faction_ids.size():
		return
	var id := _faction_ids[index]
	_faction_name.text = FactionStyle.full_name_of(id)
	_faction_shield.texture = AssetLibrary.faction_shield(id, true)
	_faction_info.text = faction_summary(_data, id)
	if _traits == null:
		_traits = FactionTraits.load_file()
	var auror_powers := Scenario.auror and id == "FN_DANISH"
	_faction_motto.text = Lang.t("Imperatore Dio e poteri divini") if auror_powers else _traits.title(id)
	_faction_traits.text = Lang.t("[i]Modalità Auror: al posto dei tratti storici, tutti i potenziamenti degli Auror.[/i]") if auror_powers else traits_bbcode(_traits, id)


func _on_start() -> void:
	var picked := _faction_list.get_selected_items()
	if picked.is_empty():
		return
	var difficulty := str(UserSettings.DIFFICULTIES[maxi(0, _difficulty_new.selected)])
	GameLaunch.new_game(_faction_ids[picked[0]], difficulty, randi_range(1, 2147483646))
	get_tree().change_scene_to_file(MAP_SCENE)


func _on_continue() -> void:
	var all := SaveGame.list_summaries()
	if all.is_empty():
		return
	_on_load_chosen(str(all[0]["nome"]))


func _on_load_chosen(save_name: String) -> void:
	GameLaunch.load_game(save_name)
	get_tree().change_scene_to_file(MAP_SCENE)


func _on_settings_save() -> void:
	UserSettings.set_value("difficolta", UserSettings.DIFFICULTIES[maxi(0, _difficulty_settings.selected)])
	UserSettings.set_value("inclinazione", snappedf(_tilt_slider.value, 0.1))
	UserSettings.set_value("volume_musica", _music_slider.value)
	UserSettings.set_value("volume_effetti", _effects_slider.value)
	UserSettings.set_value("aggiornamenti", _updates_check.button_pressed)
	_message.text = Lang.t("Impostazioni salvate.") if UserSettings.save() else Lang.t("Impostazioni non salvate (file non scrivibile).")
	GameAudio.apply_volumes()
	_show_page(_home)


func _ensure_campaign() -> bool:
	if _data != null:
		return true
	if not GameFiles.campaign_available():
		_message.text = Lang.t("Dati della campagna non trovati: impossibile iniziare una campagna.")
		return false
	_data = Scenario.load_startpos()   # ADR-068: scenario storico o modalita' Auror
	FactionStyle.apply_overrides(_data)
	AssetLibrary.use_campaign(_data)
	return true
