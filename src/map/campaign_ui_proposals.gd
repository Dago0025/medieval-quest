class_name CampaignUiProposals
extends RefCounted
## Testi e dati dell'interfaccia delle proposte dell'IA al giocatore (fase 7b): funzioni pure che leggono lo stato e producono
## stringhe o liste, senza modificarlo (ADR-003). La finestra in `scenes/campaign_map.gd` mostra una proposta alla volta e invia
## solo `GameCommands.answer_proposal`; nessuna regola e' ricalcolata qui.

const KIND_NAMES := {
	"alleanza": "un'alleanza",
	"tregua": "una tregua",
	"matrimonio": "un matrimonio",
}

const EXPIRY_REASONS := {
	"scaduta": "il tempo per rispondere è finito",
	"agente": "l'emissario non c'è più",
	"proponente": "chi la proponeva è scomparso",
	"destinatario": "il destinatario è scomparso",
}


## Proposte in attesa per la fazione, in ordine di id, pronte per la finestra: elenco di
## {"id", "da", "tipo", "titolo", "testo", "accetta", "rifiuta", "scadenza"}.
static func windows(state: GameState, faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in state.proposals_for(faction_id):
		out.append(window_of(state, p))
	return out


## Numero di proposte in attesa per la fazione.
static func count(state: GameState, faction_id: String) -> int:
	return state.proposals_for(faction_id).size()


## Id delle proposte in attesa, in ordine (la coda della finestra).
static func queue_ids(state: GameState, faction_id: String) -> Array[int]:
	var out: Array[int] = []
	for p in state.proposals_for(faction_id):
		out.append(int(p.get("id", 0)))
	return out


static func kind_phrase(kind: String) -> String:
	return Lang.t(str(KIND_NAMES[kind])) if KIND_NAMES.has(kind) else kind


## Una proposta: titolo, testo (chi propone, che cosa, dove si trova l'emissario, entro quando rispondere) ed etichette dei pulsanti.
static func window_of(state: GameState, p: Dictionary) -> Dictionary:
	var kind := str(p.get("tipo", ""))
	var from_name := SimUtil.faction_label(str(p.get("da", "")))
	var deadline := int(p.get("scadenza", 0))
	var lines: Array[String] = []
	lines.append(Lang.t("%s ti propone %s.") % [from_name, kind_phrase(kind)])
	var agent := state.agent(int(p.get("agente", 0)))
	if agent != null:
		lines.append(Lang.t("L'emissario aspetta la risposta a %s.") % CampaignUiText.region_name(state, agent.region))
	lines.append(Lang.t("Rispondi entro il %d: poi la proposta decade.") % deadline)
	if kind == "matrimonio":
		lines.append(Lang.t("Se accetti, una principessa sposa un loro generale e ne nasce un'alleanza."))
	elif kind == "tregua":
		lines.append(Lang.t("Se accetti, la guerra tra voi si ferma per qualche anno."))
	elif kind == "alleanza":
		lines.append(Lang.t("Se accetti, siete alleati: non vi potete attaccare senza rompere il patto."))
	return {
		"id": int(p.get("id", 0)),
		"da": str(p.get("da", "")),
		"tipo": kind,
		"titolo": Lang.t("Proposta di %s") % from_name,
		"testo": "\n".join(lines),
		"accetta": Lang.t("Accetta"),
		"rifiuta": Lang.t("Rifiuta"),
		"scadenza": deadline,
	}


## Risponde con il comando e restituisce {"ok", "testo"}: il testo dell'esito (o l'errore) da mostrare alla fazione.
static func answer(state: GameState, faction_id: String, proposal_id: int, accept: bool) -> Dictionary:
	var result := GameCommands.answer_proposal(state, faction_id, proposal_id, accept)
	if not bool(result["ok"]):
		return {"ok": false, "testo": str(result["errore"])}
	var text := str(result.get("testo", ""))
	if text == "":
		text = Lang.t("Proposta accettata.") if accept else Lang.t("Proposta rifiutata.")
	return {"ok": true, "testo": text}


## Testo italiano degli eventi delle proposte ("" per gli altri).
static func format_event(state: GameState, kind: String, e: Dictionary) -> String:
	if kind == GameState.EV_PROPOSAL_RECEIVED:
		return Lang.t("%s ti propone %s (rispondi entro il %d).") % [
			SimUtil.faction_label(str(e.get("fazione", ""))), kind_phrase(str(e.get("missione", ""))), int(e.get("scadenza", 0))]
	if kind == GameState.EV_PROPOSAL_EXPIRED:
		return Lang.t("La proposta di %s per %s è decaduta: %s.") % [
			SimUtil.faction_label(str(e.get("fazione", ""))), kind_phrase(str(e.get("missione", ""))),
			Lang.t(str(EXPIRY_REASONS.get(str(e.get("motivo", "")), "non è più valida")))]
	return ""
