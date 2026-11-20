class_name AiController
extends RefCounted
## Regia dell'IA (fase 7, ADR-003, ADR-008, ADR-012). L'IA e' un giocatore come gli altri: legge lo stato e manda solo comandi
## (`GameCommands`), senza regole proprie ne' scorciatoie. NON e' dentro `TurnProcessor.end_year`: la chiama chi fa avanzare la
## partita (`CampaignTurn.advance`).
##
## Casualita': un generatore per fazione e anno (`AiContext.rng_for`), non `state.rng`, non salvato: stesso stato = stessi ordini.
## Ordine fisso: fazioni nell'ordine di dichiarazione, province in quello del file, eserciti per id.


## Pianifica un anno per tutte le fazioni vive, non del giocatore e non ribelli. `difficulty` (vuoto = quella di ia.cfg) e
## `ai_rules` (null = `AiRules.default_rules()`) sono facoltativi. Imposta `state.ai_orders_horde` (l'Orda la guida l'IA); chi
## chiama il fine anno a mano dopo `plan_year` deve rimetterlo a falso (lo fa `CampaignTurn.advance`).
## Restituisce un rapporto: "anno", "fazioni" (pianificate), "ordini" (accettati), "rifiutati" (comandi respinti: un difetto
## dell'IA), "rifiuti" (primi messaggi), "ms" (tempo), "registro" (una riga per ordine, solo con `keep_log`).
static func plan_year(state: GameState, difficulty: String = "", ai_rules: AiRules = null, keep_log: bool = false) -> Dictionary:
	var started := Time.get_ticks_usec()
	var report := {"anno": state.year, "fazioni": 0, "ordini": 0, "rifiutati": 0, "rifiuti": [], "ms": 0.0, "registro": []}
	state.ai_orders_horde = true
	if state.is_game_over() or state.campaign == null:
		return report
	var rules := ai_rules if ai_rules != null else AiRules.default_rules()
	var ctx := AiContext.build(state, rules, difficulty)
	ctx.keep_log = keep_log
	var planned := 0
	for f in state.factions:
		if not f.alive or f.is_player or f.id == GameState.REBEL:
			continue
		AiFaction.plan(ctx, f.id)
		planned += 1
	report["fazioni"] = planned
	report["ordini"] = ctx.orders
	report["rifiutati"] = ctx.rejected
	report["rifiuti"] = ctx.rejections
	report["registro"] = ctx.log
	report["ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	return report
