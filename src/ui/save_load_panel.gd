class_name SaveLoadPanel
extends PanelContainer
## Finestra dei salvataggi con nome (fase 8c), usata dal menu iniziale e dalla mappa: elenco dal piu' recente con fazione e
## anno, campo del nome per salvare, Elimina. Emette `save_requested(nome)` o `load_requested(nome)`; chi la usa salva o carica
## e la chiude. Scelta multipla (Federico, 22/11/2026: cancellare piu' salvataggi alla volta): Ctrl/Maiusc + clic o «Tutti»;
## con piu' di un salvataggio scelto Elimina chiede un secondo clic di conferma.

signal save_requested(save_name: String)
signal load_requested(save_name: String)

var _saving := false
var _title: Label
var _list: ItemList
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _confirm: Button
var _delete: Button
var _select_all: Button
var _delete_armed := false   ## primo clic su Elimina con piu' salvataggi scelti: il secondo li cancella
var _note: Label
var _names: PackedStringArray = []


func _init() -> void:
	visible = false
	z_index = 9
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_title = Label.new()
	_title.theme_type_variation = "Title"
	box.add_child(_title)
	box.add_child(UiTheme.divider())
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(560, 300)
	_list.select_mode = ItemList.SELECT_MULTI
	_list.item_selected.connect(_on_selected)
	_list.multi_selected.connect(func(index: int, _selected: bool) -> void: _on_selected(index))
	_list.item_activated.connect(func(_i: int) -> void: _on_confirm())
	box.add_child(_list)
	_name_row = HBoxContainer.new()
	box.add_child(_name_row)
	var name_label := Label.new()
	name_label.text = Lang.t("Nome:")
	_name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 48
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_confirm())
	_name_row.add_child(_name_edit)
	_note = Label.new()
	_note.add_theme_color_override("font_color", UiTheme.INK_BAD)
	_note.visible = false
	box.add_child(_note)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	var hint := Label.new()
	hint.text = Lang.t("Ctrl o Maiusc + clic: piu' salvataggi")
	hint.add_theme_font_size_override("font_size", 13)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(hint)
	_select_all = Button.new()
	_select_all.text = Lang.t("Tutti")
	_select_all.tooltip_text = Lang.t("Sceglie tutti i salvataggi dell'elenco")
	_select_all.pressed.connect(select_all)
	buttons.add_child(_select_all)
	_delete = Button.new()
	_delete.text = Lang.t("Elimina")
	_delete.pressed.connect(_on_delete)
	buttons.add_child(_delete)
	var cancel := Button.new()
	cancel.text = Lang.t("Annulla (Esc)")
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	_confirm = Button.new()
	_confirm.pressed.connect(_on_confirm)
	buttons.add_child(_confirm)


## Apre per salvare, con `default_name` gia' scritto (per esempio «Auror_1123»).
func open_save(default_name: String) -> void:
	_saving = true
	_title.text = Lang.t("Salva la partita")
	_confirm.text = Lang.t("Salva")
	_name_row.visible = true
	_name_edit.text = SaveGame.safe_name(default_name)
	_refresh()
	visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()


func open_load() -> void:
	_saving = false
	_title.text = Lang.t("Carica una partita")
	_confirm.text = Lang.t("Carica")
	_name_row.visible = false
	_refresh()
	visible = true
	if _list.item_count > 0:
		_list.select(0)
		_on_selected(0)
	_list.grab_focus()


func close() -> void:
	visible = false


## Testo di una riga: «Auror_1123 — Auror, anno 1123 · 08/11/2026 22:10».
static func row_text(s: Dictionary) -> String:
	var who := FactionStyle.name_of(str(s.get("fazione", ""))) if str(s.get("fazione", "")) != "" else "?"
	var when := Time.get_datetime_string_from_unix_time(int(s.get("modificato", 0)) + _utc_offset(), true)
	var date := "%s/%s/%s %s" % [when.substr(8, 2), when.substr(5, 2), when.substr(0, 4), when.substr(11, 5)]
	return Lang.t("%s — %s, anno %d · %s") % [str(s.get("nome", "")), who, int(s.get("anno", 0)), date]


func _refresh() -> void:
	_list.clear()
	_names.clear()
	for s in SaveGame.list_summaries():
		_list.add_item(row_text(s))
		_names.append(str(s["nome"]))
	_note.visible = false
	_disarm()
	_delete.text = Lang.t("Elimina")
	_delete.disabled = true
	_select_all.disabled = _names.is_empty()
	_confirm.disabled = not _saving
	if _names.is_empty() and not _saving:
		_note.text = Lang.t("Nessuna partita salvata.")
		_note.visible = true


func _on_selected(index: int) -> void:
	_disarm()
	var count := _list.get_selected_items().size()
	_delete.disabled = count == 0
	_delete.text = Lang.t("Elimina (%d)") % count if count > 1 else Lang.t("Elimina")
	if index < 0 or index >= _names.size() or not _list.is_selected(index):
		_confirm.disabled = not _saving and count == 0
		return
	_confirm.disabled = false
	if _saving:
		_name_edit.text = _names[index]


## Sceglie tutti i salvataggi dell'elenco (per cancellarli insieme).
func select_all() -> void:
	for i in _list.item_count:
		_list.select(i, false)
	_on_selected(-1)


## Nomi dei salvataggi scelti, nell'ordine dell'elenco.
func selected_names() -> PackedStringArray:
	var out := PackedStringArray()
	var picked := _list.get_selected_items()
	picked.sort()
	for i in picked:
		if i >= 0 and i < _names.size():
			out.append(_names[i])
	return out


func _disarm() -> void:
	_delete_armed = false
	_note.visible = false


func _on_confirm() -> void:
	if _saving:
		var save_name := SaveGame.safe_name(_name_edit.text)
		if save_name == "":
			_note.text = Lang.t("Scrivi un nome per il salvataggio.")
			_note.visible = true
			return
		save_requested.emit(save_name)
		return
	var picked := _list.get_selected_items()
	if picked.is_empty():
		return
	load_requested.emit(_names[picked[0]])


func _on_delete() -> void:
	var chosen := selected_names()
	if chosen.is_empty():
		return
	if chosen.size() > 1 and not _delete_armed:
		_delete_armed = true
		_delete.text = Lang.t("Conferma: elimina %d") % chosen.size()
		_note.text = Lang.t("Clic di nuovo su «Conferma» per eliminare %d salvataggi.") % chosen.size()
		_note.visible = true
		return
	delete_names(chosen)
	_refresh()


## Cancella i salvataggi indicati; restituisce quanti sono stati cancellati.
static func delete_names(names: PackedStringArray) -> int:
	var done := 0
	for n in names:
		if SaveGame.delete_file(n):
			done += 1
	return done


static func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
