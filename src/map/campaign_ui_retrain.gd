class_name CampaignUiRetrain
extends RefCounted
## Testi e dati dell'interfaccia del riaddestramento delle unità: funzioni pure che leggono lo stato e producono stringhe o
## dizionari, senza modificarlo (ADR-003). Il pannello dell'esercito in `scenes/campaign_map.gd` usa le caselle delle pile
## già esistenti e invia solo `GameCommands.order_retrain` / `cancel_retrain`; nessuna regola è ricalcolata qui (costi e
## motivi vengono da `GameCommands.retrain_options`).

const BUTTON_TEXT := "Riaddestra le pile scelte"
const CANCEL_TEXT := "Annulla riaddestramento"
const IN_PROGRESS := "(in riaddestramento)"
const RESTORE_TEXT := "Ripristina"

const CANCEL_REASONS := {
	"esercito_perso": "l'esercito non c'è più",
	"esercito_mosso": "l'esercito si è mosso",
	"provincia_persa": "la provincia non è più vostra",
	"pila_cambiata": "la pila è cambiata (perdite o spostamenti)",
}


## Testo della casella di una pila nel pannello dell'esercito: come prima ("Unità · N uomini · valore V") più, se la pila è in
## riaddestramento, «(in riaddestramento)».
static func stack_label(state: GameState, army: Army, index: int) -> String:
	var st := army.stacks[index]
	var text := Lang.t("%s · %d uomini%s") % [CampaignUiText.unit_name(st.unit_id), st.men, (Lang.t(" · valore %d") % st.value) if st.value > 0 else ""]
	if not RetrainProcessor.order_at(state, army.id, index).is_empty():
		text += " " + Lang.t(IN_PROGRESS)
	return text


## Stato dei controlli del riaddestramento per l'esercito e le caselle spuntate `checked` (indici di pila):
##   "visibile" (c'è almeno una pila riaddestrabile o già ordinata), "testo" del pulsante (con il costo totale se ce n'è uno),
##   "costo" (delle pile spuntate che l'ordine accetterebbe, nel limite per provincia), "pile" (quante), "tooltip" (costi,
##   motivi per le pile spuntate che non si possono riaddestrare, tesoro), "annulla_visibile", "annulla_testo" (con il rimborso).
static func panel_state(state: GameState, faction_id: String, army: Army, checked: PackedInt32Array) -> Dictionary:
	var out := {
		"visibile": false, "testo": Lang.t(BUTTON_TEXT), "costo": 0, "pile": 0, "tooltip": "",
		"annulla_visibile": false, "annulla_testo": Lang.t(CANCEL_TEXT),
	}
	if army == null:
		return out
	var options := GameCommands.retrain_options(state, faction_id, army.id)
	if not bool(options["ok"]):
		out["tooltip"] = CampaignUiText.order_error_text(state, str(options["errore"]))
		return out
	var piles: Array = options["pile"]
	var room := int(options["posti"])
	var eligible := 0
	for entry in piles:
		var e: Dictionary = entry
		if bool(e["si_puo"]):
			eligible += 1
	var orders := RetrainProcessor.orders_of(state, army.id)
	out["visibile"] = eligible > 0 or not orders.is_empty()
	if not orders.is_empty():
		var refund := 0
		for o in orders:
			refund += int(o["costo"])
		out["annulla_visibile"] = true
		out["annulla_testo"] = Lang.t("%s (rimborso %d)") % [Lang.t(CANCEL_TEXT), refund]
	var ascending := PackedInt32Array(checked)
	ascending.sort()
	var cost := 0
	var taken := 0
	var notes: Array[String] = []
	for i in ascending:
		if i < 0 or i >= piles.size():
			continue
		var e: Dictionary = piles[i]
		var name_text := CampaignUiText.unit_name(str(e["unita"]))
		if bool(e["si_puo"]) and taken < room:
			cost += int(e["costo"])
			taken += 1
		elif bool(e["si_puo"]):
			notes.append(Lang.t("%s: limite di pile riaddestrate nella provincia raggiunto") % name_text)
		elif bool(e["in_riaddestramento"]):
			notes.append("%s: %s" % [name_text, Lang.t("già in riaddestramento")])
		else:
			notes.append("%s: %s" % [name_text, CampaignUiText.order_error_text(state, str(e["motivo"]))])
	out["costo"] = cost
	out["pile"] = taken
	if cost > 0:
		out["testo"] = Lang.t("%s (%d fiorini)") % [Lang.t(BUTTON_TEXT), cost]
	var lines: Array[String] = [Lang.t("Riporta all'organico pieno le pile spuntate pagando in proporzione agli uomini mancanti; la pila perde esperienza in proporzione ai nuovi arrivati. Si applica a fine anno, se l'esercito resta fermo qui.")]
	if cost > 0:
		lines.append(Lang.t("Costo totale: %d fiorini per %d pile.") % [cost, taken])
		var faction := state.faction(faction_id)
		if faction != null and faction.treasury < cost:
			lines.append(Lang.t("Tesoro insufficiente: ci sono %d fiorini.") % faction.treasury)
	elif ascending.is_empty():
		lines.append(Lang.t("Spunta le pile da riaddestrare (non i mercenari né gli ordini militari)."))
	lines.append_array(notes)
	out["tooltip"] = "\n".join(lines)
	return out


## Vero se il pannello deve mostrare i controlli del riaddestramento per l'esercito (anche con una sola pila).
static func has_controls(state: GameState, faction_id: String, army: Army) -> bool:
	return bool(panel_state(state, faction_id, army, PackedInt32Array())["visibile"])


## Testo del messaggio dopo `GameCommands.order_retrain`.
static func ordered_text(state: GameState, r: Dictionary) -> String:
	if not bool(r["ok"]):
		return CampaignUiText.order_error_text(state, str(r["errore"]))
	var text := Lang.t("Riaddestramento ordinato: %d pile, %d fiorini (a fine anno tornano all'organico pieno).") % [int(r.get("pile", 0)), int(r.get("costo", 0))]
	var skipped := CampaignUiText.list_of(r.get("rifiutate"))
	if not skipped.is_empty():
		var first: Dictionary = skipped[0]
		text += Lang.t(" Saltate %d pile (%s).") % [skipped.size(), CampaignUiText.order_error_text(state, str(first.get("motivo", "")))]
	return text


## Pulsante «Ripristina» dell'esercito scelto nella barra in basso (ADR-046): {"visibile", "attivo", "testo", "suggerimento"}.
## Visibile per un esercito proprio di terra con almeno una pila che ha perso uomini; acceso se si puo' ripristinare adesso
## (fermo, in una provincia propria non assediata, tesoro), altrimenti spento con il motivo nel suggerimento.
static func restore_action(state: GameState, faction_id: String, army: Army) -> Dictionary:
	var out := {"visibile": false, "attivo": false, "testo": Lang.t(RESTORE_TEXT), "suggerimento": ""}
	if army == null or army.is_fleet or army.faction != SimUtil.norm(faction_id) or not _has_losses(state, army):
		return out
	out["visibile"] = true
	var preview := GameCommands.restore_preview(state, faction_id, army.id)
	if not bool(preview["ok"]):
		out["suggerimento"] = Lang.t("Riporta l'esercito al pieno delle forze entro fine anno, in una vostra provincia.\n%s") % CampaignUiText.order_error_text(state, str(preview["errore"]))
		return out
	var piles := int(preview["pile"])
	if piles <= 0:
		var excluded: Array = preview["escluse"]
		if not excluded.is_empty():
			out["suggerimento"] = CampaignUiText.order_error_text(state, str((excluded[0] as Dictionary)["motivo"]))
		else:
			out["visibile"] = false   # tutte gia' in riaddestramento (resta «Ferma riaddestr.») o niente da fare
		return out
	var cost := int(preview["costo"])
	var treasury := state.faction(faction_id).treasury
	out["attivo"] = treasury >= RetrainProcessor.stack_cost(state, army.stacks[int((preview["indici"] as Array)[0])])
	var lines := PackedStringArray([Lang.t("Riporta al pieno delle forze %d %s entro fine anno: %d uomini, %d fiorini.") % [
		piles, Lang.t("pila") if piles == 1 else Lang.t("pile"), int(preview["uomini"]), cost]])
	if treasury < cost:
		lines.append(Lang.t("Il tesoro (%d) non basta per tutte: si ripristinano quelle che si possono pagare.") % treasury)
	if not out["attivo"]:
		lines[lines.size() - 1] = Lang.t("Tesoro insufficiente: servono %d fiorini, ce ne sono %d.") % [cost, treasury]
	lines.append(Lang.t("Se l'esercito si muove prima di fine anno, il costo è rimborsato."))
	out["suggerimento"] = "\n".join(lines)
	return out


static func _has_losses(state: GameState, army: Army) -> bool:
	for st in army.stacks:
		var unit := state.units.get_unit(st.unit_id) if state.units != null else null
		if unit != null and unit.is_military() and not unit.is_ship() and st.men < unit.men:
			return true
	return false


## Testo del messaggio dopo `GameCommands.restore_army`.
static func restored_text(state: GameState, army: Army, r: Dictionary) -> String:
	if not bool(r["ok"]):
		return CampaignUiText.order_error_text(state, str(r["errore"]))
	var piles := int(r.get("pile", 0))
	var text := Lang.t("%s torna al pieno delle forze a fine anno: %d %s, %d uomini, %d fiorini.") % [
		CampaignUiText.army_title(army), piles, Lang.t("pila") if piles == 1 else Lang.t("pile"), int(r.get("uomini", 0)), int(r.get("costo", 0))]
	if int(r.get("rimaste", 0)) > 0:
		text += Lang.t(" Il tesoro non bastava per altre %d.") % int(r["rimaste"])
	var excluded := CampaignUiText.list_of(r.get("escluse"))
	if not excluded.is_empty():
		text += Lang.t(" Escluse %d (%s).") % [excluded.size(), CampaignUiText.order_error_text(state, str((excluded[0] as Dictionary).get("motivo", "")))]
	return text


## Testo del messaggio dopo `GameCommands.cancel_retrain`.
static func cancelled_text(state: GameState, r: Dictionary) -> String:
	if not bool(r["ok"]):
		return CampaignUiText.order_error_text(state, str(r["errore"]))
	return Lang.t("Riaddestramento annullato: %d fiorini rimborsati per %d pile.") % [int(r.get("rimborso", 0)), int(r.get("pile", 0))]


## Frase da aggiungere al messaggio di un movimento, di una divisione o di un'unione che ha annullato degli ordini di
## riaddestramento ("" se non ce n'erano).
static func refund_note(r: Dictionary) -> String:
	if int(r.get("pile_riaddestramento", 0)) <= 0:
		return ""
	return Lang.t("Riaddestramento annullato: %d fiorini rimborsati.") % int(r.get("rimborso_riaddestramento", 0))


## Testo italiano degli eventi EV_RETRAINED e EV_RETRAIN_CANCELLED; vuoto per gli altri tipi. Senza i campi essenziali ripiega
## sul campo "testo" scritto dalla simulazione.
static func format_event(state: GameState, kind: String, e: Dictionary) -> String:
	if kind != GameState.EV_RETRAINED and kind != GameState.EV_RETRAIN_CANCELLED:
		return ""
	var region_id := CampaignUiText.text_of(CampaignUiText.prop(e, ["provincia", "regione"]))
	var fallback := CampaignUiText.text_of(e.get("testo"))
	if region_id == "":
		return fallback if fallback != "" else kind
	var place := CampaignUiText.region_name(state, region_id)
	var army_id := CampaignUiText.int_of(e.get("esercito"))
	var stacks := CampaignUiText.int_of(e.get("pile"))
	if kind == GameState.EV_RETRAINED:
		return Lang.t("Riaddestramento a %s (esercito %d): %d pile tornano all'organico pieno, +%d uomini (%d fiorini).") % [
			place, army_id, stacks, CampaignUiText.int_of(e.get("uomini")), CampaignUiText.int_of(e.get("costo"))]
	var reason := Lang.t(str(CANCEL_REASONS.get(CampaignUiText.text_of(e.get("motivo")), "")))
	var text := Lang.t("Riaddestramento annullato a %s (esercito %d): %d pile, %d fiorini rimborsati") % [
		place, army_id, stacks, CampaignUiText.int_of(e.get("rimborso"))]
	if reason != "":
		text += Lang.t(" (%s)") % reason
	return text + "."
