class_name AiFaction
extends RefCounted
## Una fazione dell'IA per un anno (fase 7a). Ordine dei moduli: profilo effettivo, mappa delle minacce, tasse, congedo (ADR-031), reclutamento,
## costruzioni, diplomazia (tradimento, tregue, alleanze, nozze: 7b), guerra (assedi, difesa, attacchi, concentrazione), flotte
## e sbarchi, commercio navale (ADR-053), crociate e jihad (7b), agenti (7b) e viaggi lunghi degli agenti (ADR-053: gli ordini in corso
## proseguono prima della diplomazia, i nuovi dopo gli agenti a corto raggio), comandanti e titoli (`AiStaff.consolidate` per ultimo: vede i cambi dell'anno). I ribelli non ricevono
## ordini (le rivolte sono regole della 4b); il Papato (POPE) non attacca; l'Orda d'Oro e i predoni (BARBARIAN_RAIDER) attaccano
## la provincia confinante piu' ricca. Tutto passa da `GameCommands`.


## Dai gli ordini dell'anno alla fazione. Restituisce il profilo effettivo usato ("" se la fazione non riceve ordini).
static func plan(ctx: AiContext, faction_id: String) -> String:
	var state := ctx.state
	var f := state.faction(faction_id)
	if f == null or not f.alive or f.is_player or f.id == GameState.REBEL:
		return ""
	var profile := AiProfiles.effective(ctx, faction_id)
	if profile == AiProfiles.REBELS:
		return ""
	var data := AiPlan.create(ctx, faction_id, profile)
	AiThreat.build(data)
	AiEconomy.plan_taxes(data)
	AiEconomy.plan_disband(data)
	AiEconomy.plan_recruitment(data)
	AiEconomy.plan_buildings(data)
	AiDiplomacy.plan_betrayal(data)
	AiJourneys.continue_orders(data)
	AiDiplomacy.plan(data)
	AiWar.plan(data)
	AiNavy.plan(data)
	AiTrade.plan(data)
	AiWar.concentrate(data)
	AiCrusades.plan(data)
	AiAgents.plan(data)
	AiJourneys.plan(data)
	AiStaff.plan(data)
	AiStaff.consolidate(data)
	return profile
