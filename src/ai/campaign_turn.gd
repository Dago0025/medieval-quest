class_name CampaignTurn
extends RefCounted
## Un anno di campagna con l'IA (fase 7): le fazioni del computer danno gli ordini (`AiController.plan_year`), poi il fine
## anno della simulazione (`TurnProcessor.end_year`). La fazione del giocatore non riceve ordini dall'IA. Usato dall'interfaccia
## (pulsante Fine anno) e dalle partite automatiche dei test.


## IA poi fine anno. Restituisce lo stesso Dictionary di `TurnProcessor.end_year` ("ok", "anno", "finita", "errori", "avvisi").
## A partita finita non pianifica nulla e il fine anno risponde "ok" falso, come sempre. `difficulty` vuota = quella di ia.cfg.
static func advance(state: GameState, difficulty: String = "", ai_rules: AiRules = null) -> Dictionary:
	if state.is_game_over():
		return TurnProcessor.end_year(state)
	AiController.plan_year(state, difficulty, ai_rules)
	var result := TurnProcessor.end_year(state)
	state.ai_orders_horde = false
	return result
