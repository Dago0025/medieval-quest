class_name CampaignUiDismiss
extends RefCounted
## Testi dell'interfaccia del congedo delle unità (ADR-031, richiesta di Federico dell'11/11/2026): funzioni pure che leggono
## lo stato e producono stringhe o dizionari, senza modificarlo (ADR-003). La barra in basso e la pergamena dell'esercito in
## `scenes/campaign_map.gd` inviano solo `GameCommands.disband_stacks`, dopo la conferma.

const BUTTON_TEXT := "Congeda"
const CONFIRM_TITLE := "Congedo"
const CONFIRM_OK := "Congeda"
const CONFIRM_CANCEL := "Annulla"


## Vero se l'esercito (o la flotta) è del giocatore e si può congedare.
static func allowed(state: GameState, faction_id: String, army: Army) -> bool:
	return GameCommands.disband_problem(state, faction_id, army) == ""


## Vero se le pile congedate di questo esercito diventano compagnie di mercenari (truppe di terra in una provincia, con la
## regola accesa): serve per avvertire il giocatore prima della conferma.
static func becomes_mercenaries(state: GameState, army: Army) -> bool:
	if army == null or army.is_fleet or not state.rules.mercenaries.disbanded_join:
		return false
	return state.province(army.region) != null


## Indici validi e distinti, in ordine crescente.
static func picked(army: Army, indices: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if army == null:
		return out
	for i in indices:
		if i >= 0 and i < army.stacks.size() and not out.has(i):
			out.append(i)
	out.sort()
	return out


## Fiorini di mantenimento l'anno che si risparmiano congedando le pile `indices` (lo stesso numero che dà il comando).
static func upkeep_saved(state: GameState, army: Army, indices: PackedInt32Array) -> int:
	if army == null or state.units == null:
		return 0
	var total := 0
	for a in state.armies_of(army.faction):
		total += Economy.army_support_sum(state, a)
	var gone := 0
	for i in picked(army, indices):
		var st := army.stacks[i]
		var unit := state.units.get_unit(st.unit_id)
		if unit != null:
			gone += roundi(unit.support_cost * state.rules.mercenaries.upkeep_factor) if st.mercenary else unit.support_cost
	var m := state.rules.upkeep_multiplier
	return roundi(float(total) * m) - roundi(float(total - gone) * m)


## «2 unità», «1 nave», «3 navi».
static func count_text(count: int, fleet: bool) -> String:
	if fleet:
		return "%d %s" % [count, Lang.t("nave") if count == 1 else Lang.t("navi")]
	return Lang.t("%d unità") % count


## Stato del pulsante «Congeda» per l'esercito e le pile scelte: {"visibile", "attivo", "testo", "suggerimento"}.
static func button_state(state: GameState, faction_id: String, army: Army, indices: PackedInt32Array) -> Dictionary:
	var out := {"visibile": false, "attivo": false, "testo": Lang.t(BUTTON_TEXT), "suggerimento": ""}
	if not allowed(state, faction_id, army):
		return out
	out["visibile"] = true
	var what := Lang.t("navi") if army.is_fleet else Lang.t("unità")
	var chosen := picked(army, indices)
	if chosen.is_empty():
		out["suggerimento"] = Lang.t("Scegli una o più %s, poi congedale: lasciano subito l'esercito, senza rimborso, e non costano più mantenimento.") % what
		if becomes_mercenaries(state, army):
			out["suggerimento"] += Lang.t(" Le truppe congedate diventano mercenari.")
		return out
	out["attivo"] = true
	out["testo"] = "%s (%d)" % [Lang.t(BUTTON_TEXT), chosen.size()]
	out["suggerimento"] = Lang.t("Congeda %s: %d fiorini di mantenimento in meno l'anno. Chiede conferma.") % [count_text(chosen.size(), army.is_fleet), upkeep_saved(state, army, chosen)]
	return out


## Testo della finestra di conferma.
static func confirm_text(state: GameState, faction_id: String, army: Army, indices: PackedInt32Array) -> String:
	if not allowed(state, faction_id, army):
		return ""
	var chosen := picked(army, indices)
	var men := 0
	var names := {}
	for i in chosen:
		var st := army.stacks[i]
		men += st.men
		var unit_name := CampaignUiText.unit_name(st.unit_id)
		names[unit_name] = int(names.get(unit_name, 0)) + 1
	var parts := PackedStringArray()
	for unit_name in names:
		parts.append(str(unit_name) if int(names[unit_name]) == 1 else "%s × %d" % [unit_name, int(names[unit_name])])
	var lines := PackedStringArray()
	var head := Lang.t("Congedare %s") % count_text(chosen.size(), army.is_fleet)
	if not army.is_fleet:
		head += Lang.t(" (%d uomini)") % men
	lines.append(head + "?")
	lines.append(", ".join(parts) + ".")
	if chosen.size() >= army.stacks.size():
		if army.is_fleet:
			lines.append(Lang.t("È l'intera flotta: la pedina sparisce dalla mappa."))
		else:
			var commander := state.commander_of(army.id)
			var who := (Lang.t(" e %s resta senza esercito") % commander.full_name()) if commander != null else ""
			lines.append(Lang.t("È l'intero esercito: la pedina sparisce dalla mappa%s.") % who)
	lines.append("")
	lines.append(Lang.t("Risparmi %d fiorini di mantenimento l'anno.") % upkeep_saved(state, army, chosen))
	if becomes_mercenaries(state, army):
		lines.append(Lang.t("I congedati diventano mercenari in %s: potrà assoldarli chi possiede la provincia.") % CampaignUiText.region_name(state, army.region))
	lines.append(Lang.t("Non c'è rimborso e non si torna indietro."))
	return "\n".join(lines)


## Messaggio dopo il comando riuscito (`r` = esito di `GameCommands.disband_stacks`).
static func done_text(r: Dictionary, fleet: bool) -> String:
	var count := int(r.get("pile", 0))
	var text := "%s %s" % [Lang.t("Congedata") if count == 1 else Lang.t("Congedate"), count_text(count, fleet)]
	if not fleet:
		text += Lang.t(" (%d uomini)") % int(r.get("uomini", 0))
	text += Lang.t(": %d fiorini di mantenimento in meno l'anno.") % int(r.get("mantenimento", 0))
	var companies := int(r.get("mercenari", 0))
	if companies > 0:
		text += Lang.t(" Ora %s tra i mercenari della provincia.") % (Lang.t("è") if companies == 1 else Lang.t("sono"))
	var note := CampaignUiRetrain.refund_note(r)
	return text if note == "" else text + " " + note
