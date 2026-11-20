extends Control
## Riepilogo della campagna caricata (numeri di fazioni, regioni, confini, unità).
## Non è più la scena principale: la mappa è in campaign_map.tscn, che mostra
## lo stesso testo con il tasto F1. Questa scena resta avviabile da sola.


func _ready() -> void:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 48
	label.offset_top = 48
	label.add_theme_font_size_override("font_size", 22)
	add_child(label)
	label.text = _summary()


func _summary() -> String:
	if not GameFiles.campaign_available():
		return Lang.t("Dati della campagna non trovati:\n%s") % GameFiles.startpos()
	return summary_from(Scenario.load_startpos())


## Riepilogo testuale di una campagna già caricata (usato anche dalla mappa, tasto F1).
static func summary_from(data: CampaignData) -> String:
	var lines := PackedStringArray()
	lines.append(Lang.t("%s · riepilogo della campagna") % UiTheme.GAME_NAME)
	lines.append("")
	lines.append(Lang.t("Campagna: %s, inizio %d (epoche: %s)") % [GameFiles.MAIN_STARTPOS, data.start_year, str(data.period_starts)])
	lines.append(Lang.t("Fazioni: %d dichiarate, %d attive") % [data.factions.size(), data.active_factions().size()])
	lines.append(Lang.t("Regioni: %d di terra, %d di mare") % [data.land_regions().size(), data.sea_regions().size()])
	lines.append(Lang.t("Confini: %d") % data.adjacency_pairs().size())
	lines.append(Lang.t("Unità iniziali: %d") % data.start_units.size())
	lines.append(Lang.t("Province della fazione %s: %d") % [FactionStyle.name_of("FN_DANISH"), data.regions_owned_by("FN_DANISH").size()])
	lines.append(Lang.t("Errori: %d · comandi ancora da interpretare: %d") % [data.errors.size(), data.ignored_commands.size()])
	return "\n".join(lines)
