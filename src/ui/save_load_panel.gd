class_name SaveLoadPanel
extends PanelContainer
## Finestra dei salvataggi con nome (fase 8c), usata dal menu iniziale e dalla mappa: elenco dal piu' recente con fazione e
## anno, campo del nome per salvare, Elimina. Emette `save_requested(nome)` o `load_requested(nome)`; chi la usa salva o carica
## e la chiude.

signal save_requested(save_name: String)
signal load_requested(save_name: String)

var _saving := false
var _title: Label
var _list: ItemList
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _confirm: Button
var _delete: Button
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
	_list.item_selected.connect(_on_selected)
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
	_delete.disabled = true
	_confirm.disabled = not _saving
	if _names.is_empty() and not _saving:
		_note.text = Lang.t("Nessuna partita salvata.")
		_note.visible = true


func _on_selected(index: int) -> void:
	_delete.disabled = index < 0
	if index < 0 or index >= _names.size():
		return
	_confirm.disabled = false
	if _saving:
		_name_edit.text = _names[index]


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
	var picked := _list.get_selected_items()
	if picked.is_empty():
		return
	SaveGame.delete_file(_names[picked[0]])
	_refresh()


static func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
