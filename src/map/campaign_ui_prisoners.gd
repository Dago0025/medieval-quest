class_name CampaignUiPrisoners
extends RefCounted
## Testi e dati della finestra dei prigionieri (ADR-073): funzioni pure che leggono lo stato e producono stringhe o liste,
## senza modificarlo (ADR-003). La finestra in `scenes/campaign_map.gd` mostra una decisione alla volta e invia solo
## `GameCommands.decide_prisoners` (il giocatore ha vinto) o `GameCommands.answer_ransom` (gli si chiede il riscatto).

const RELEASE := "libera"
const RANSOM := "riscatto"
const EXECUTE := "giustizia"
const PAY := "paga"
const REFUSE := "rifiuta"


## Id delle decisioni in attesa del giocatore, in ordine (la coda della finestra).
static func queue_ids(state: GameState, faction_id: String) -> Array[int]:
	var out: Array[int] = []
	for e in PrisonerProcessor.decisions_for(state, faction_id):
		out.append(int(e["id"]))
	return out


## Elenco dei prigionieri: personaggi (con il ruolo) e uomini per unita'.
static func captives_lines(state: GameState, e: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for ch in PrisonerProcessor.characters_of(state, e):
		lines.append(Lang.t("%s (%s)") % [ch.full_name(), Lang.t(ch.role)])
	var by_unit := {}
	var order: Array[String] = []
	for item in e.get("pile", []):
		var d: Dictionary = item
		var unit := str(d.get("unita", ""))
		if not by_unit.has(unit):
			by_unit[unit] = 0
			order.append(unit)
		by_unit[unit] = int(by_unit[unit]) + int(d.get("uomini", 0))
	for unit in order:
		lines.append(Lang.t("%d uomini: %s") % [int(by_unit[unit]), CampaignUiText.unit_name(unit)])
	return lines


## La finestra di una decisione: {"id", "titolo", "testo", "scelte": [{"id", "testo"}]}; {} se la voce non c'e' o non
## spetta al giocatore.
static func window_of(state: GameState, faction_id: String, prisoner_id: int) -> Dictionary:
	var e := PrisonerProcessor.entry_of(state, prisoner_id)
	if e.is_empty():
		return {}
	var key := SimUtil.norm(faction_id)
	var place := CampaignUiText.region_name(state, str(e["regione"]))
	var captives := "\n".join(captives_lines(state, e))
	var price := PrisonerProcessor.price(state, e) if str(e["stato"]) == PrisonerProcessor.STATE_PENDING else int(e["prezzo"])
	var loser_name := SimUtil.faction_label(str(e["perdente"]))
	var captor_name := SimUtil.faction_label(str(e["vincitore"]))
	if str(e["stato"]) == PrisonerProcessor.STATE_PENDING and str(e["vincitore"]) == key:
		var lines: Array[String] = []
		lines.append(Lang.t("Dopo lo scontro a %s i tuoi uomini hanno catturato prigionieri di %s:") % [place, loser_name])
		lines.append(captives)
		lines.append("")
		lines.append(Lang.t("Puoi liberarli, chiedere un riscatto di %d denari (%s decide se pagare: se rifiuta saranno giustiziati) o giustiziarli tutti.") % [price, loser_name])
		return {
			"id": prisoner_id,
			"titolo": Lang.t("Prigionieri di %s a %s") % [loser_name, place],
			"testo": "\n".join(lines),
			"scelte": [
				{"id": RELEASE, "testo": Lang.t("Libera")},
				{"id": RANSOM, "testo": Lang.t("Chiedi il riscatto (%d)") % price},
				{"id": EXECUTE, "testo": Lang.t("Giustizia tutti")},
			],
		}
	if str(e["stato"]) == PrisonerProcessor.STATE_RANSOM and str(e["perdente"]) == key:
		var home := PrisonerProcessor.nearest_home(state, key, str(e["regione"]))
		var treasury := state.faction(key).treasury if state.faction(key) != null else 0
		var lines: Array[String] = []
		lines.append(Lang.t("%s tiene prigionieri questi tuoi uomini, catturati a %s:") % [captor_name, place])
		lines.append(captives)
		lines.append("")
		lines.append(Lang.t("Chiede %d denari di riscatto (nel tesoro ne hai %d; puoi anche indebitarti).") % [price, treasury])
		if home != "":
			lines.append(Lang.t("Se paghi tornano a %s; se rifiuti saranno giustiziati.") % CampaignUiText.region_name(state, home))
		else:
			lines.append(Lang.t("Se rifiuti saranno giustiziati."))
		return {
			"id": prisoner_id,
			"titolo": Lang.t("Riscatto chiesto da %s") % captor_name,
			"testo": "\n".join(lines),
			"scelte": [
				{"id": PAY, "testo": Lang.t("Paga %d denari") % price},
				{"id": REFUSE, "testo": Lang.t("Rifiuta")},
			],
		}
	return {}


## Esegue la scelta con il comando e restituisce {"ok", "testo"}: il testo dell'esito (o l'errore).
static func answer(state: GameState, faction_id: String, prisoner_id: int, choice: String) -> Dictionary:
	var result: Dictionary
	if choice == PAY or choice == REFUSE:
		result = GameCommands.answer_ransom(state, faction_id, prisoner_id, choice == PAY)
	else:
		result = GameCommands.decide_prisoners(state, faction_id, prisoner_id, choice)
	if not bool(result["ok"]):
		return {"ok": false, "testo": str(result["errore"])}
	return {"ok": true, "testo": str(result.get("testo", ""))}
