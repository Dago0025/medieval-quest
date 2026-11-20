class_name VictoryProcessor
extends RefCounted
## Vittoria, sconfitta e fine della campagna (fase 6b, spec. fase 6 §6b, ADR-011). `check` gira in fondo al fine anno, dopo
## il calendario: gli eventi portano l'anno raggiunto (quello di `state.year` dopo l'incremento).
##   1. sconfitta: la fazione del giocatore e' estinta o senza province ne' eserciti -> EV_DEFEAT, partita finita;
##   2. dominio (una volta): il giocatore controlla almeno la quota `soglia_dominio` delle province di terra -> EV_VICTORY;
##      la partita aspetta la scelta (`GameCommands.continue_after_victory`) e si puo' continuare;
##   3. fine della campagna: `state.year >= state.final_year` -> EV_CAMPAIGN_END con la classifica; partita finita.
## Senza una fazione del giocatore (mondi di prova, simulazioni senza giocatore) restano solo la classifica e la fine della
## campagna. Le imprese gloriose sono escluse dal remake (scelta di Federico): nessun punteggio, si vince solo per dominio.


## La fazione del giocatore, null se nessuna e' segnata.
static func player_faction(state: GameState) -> FactionState:
	for f in state.factions:
		if f.is_player:
			return f
	return null


## Quante province di terra ci sono in tutto (il denominatore della quota).
static func total_provinces(state: GameState) -> int:
	return state.provinces.size()


## Avanzamento verso il dominio di una fazione: {"province" (controllate), "necessarie", "totale", "quota" (0-1), "soglia",
## "raggiunto"}.
static func domination_progress(state: GameState, faction_id: String) -> Dictionary:
	var total := total_provinces(state)
	var owned := state.provinces_of(faction_id).size()
	var needed := state.rules.victory.provinces_needed(total)
	return {
		"province": owned,
		"necessarie": needed,
		"totale": total,
		"quota": _share(owned, total),
		"soglia": state.rules.victory.domination_threshold,
		"raggiunto": needed > 0 and owned >= needed,
	}


## Classifica delle fazioni vive con province (piu' quella del giocatore, anche senza), per numero di province e, a parita',
## per reddito lordo dell'ultimo anno (agricoltura + miniere + commercio) e poi per ordine di dichiarazione. I ribelli non
## ci sono. Righe: {"posizione" (da 1), "fazione", "province", "reddito", "netto", "quota", "giocatore"}.
static func standings(state: GameState) -> Array[Dictionary]:
	var total := total_provinces(state)
	var rows: Array[Dictionary] = []
	var order := 0
	for f in state.factions:
		order += 1
		if f.id == GameState.REBEL:
			continue
		var owned := state.provinces_of(f.id).size()
		if not ((f.alive and owned > 0) or f.is_player):
			continue
		var li := f.last_income
		var income := int(li.get("agricoltura", 0)) + int(li.get("miniere", 0)) + int(li.get("commercio", 0))
		rows.append({
			"posizione": 0,
			"fazione": f.id,
			"province": owned,
			"reddito": income,
			"netto": int(li.get("netto", 0)),
			"quota": _share(owned, total),
			"giocatore": f.is_player,
			"_ordine": order,
		})
	rows.sort_custom(_ranks_before)
	for i in rows.size():
		rows[i]["posizione"] = i + 1
		rows[i].erase("_ordine")
	return rows


static func _ranks_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["province"]) != int(b["province"]):
		return int(a["province"]) > int(b["province"])
	if int(a["reddito"]) != int(b["reddito"]):
		return int(a["reddito"]) > int(b["reddito"])
	return int(a["_ordine"]) < int(b["_ordine"])


static func _share(owned: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return normalize_share(float(owned) / float(total))


## Quota arrotondata a quattro decimali con una divisione per 10000: il risultato e' il numero piu' vicino al valore
## decimale, quindi lo stesso che si rilegge dal testo JSON dei salvataggi.
static func normalize_share(share: float) -> float:
	return float(roundi(share * 10000.0)) / 10000.0


## Vero se la fazione del giocatore e' perduta: estinta, o senza province ne' eserciti. Il motivo e' "estinta" o
## "senza_province" (vuoto se non e' persa).
static func defeat_reason(state: GameState, f: FactionState) -> String:
	if not f.alive:
		return "estinta"
	if state.provinces_of(f.id).is_empty() and state.armies_of(f.id).is_empty():
		return "senza_province"
	return ""


## Controllo di fine anno (vedi la testata). Modifica `state.victory` e aggiunge gli eventi.
static func check(state: GameState) -> void:
	var v := state.victory
	if v.is_final():
		return
	var player := player_faction(state)
	if player != null:
		var reason := defeat_reason(state, player)
		if reason != "":
			_defeat(state, player, reason)
			return
		if v.domination_year == 0:
			var progress := domination_progress(state, player.id)
			if bool(progress["raggiunto"]):
				_domination(state, player, progress)
	if state.year >= state.final_year:
		_campaign_end(state, player)


static func _defeat(state: GameState, player: FactionState, reason: String) -> void:
	var v := state.victory
	v.outcome = VictoryState.DEFEAT
	v.year = state.year
	v.continues = false
	v.set_ranking(standings(state))
	var why := Lang.t("la dinastia si e' estinta") if reason == "estinta" else Lang.t("non restano province ne' eserciti")
	state.add_event(GameState.EV_DEFEAT, {
		"fazione": player.id,
		"regione": "",
		"motivo": reason,
		"testo": Lang.t("Sconfitta: %s e' caduta (%s).") % [SimUtil.faction_label(player.id), why],
	})


static func _domination(state: GameState, player: FactionState, progress: Dictionary) -> void:
	var v := state.victory
	v.outcome = VictoryState.DOMINATION
	v.year = state.year
	v.continues = false
	v.domination_year = state.year
	v.set_ranking(standings(state))
	state.add_event(GameState.EV_VICTORY, {
		"fazione": player.id,
		"regione": "",
		"province": int(progress["province"]),
		"necessarie": int(progress["necessarie"]),
		"totale": int(progress["totale"]),
		"quota": float(progress["quota"]),
		"soglia": float(progress["soglia"]),
		"testo": Lang.t("Vittoria per dominio: %s controlla %d province su %d.") % [SimUtil.faction_label(player.id), int(progress["province"]), int(progress["totale"])],
	})


static func _campaign_end(state: GameState, player: FactionState) -> void:
	var v := state.victory
	v.outcome = VictoryState.CAMPAIGN_END
	v.year = state.year
	# `continues` resta com'era: dice se il giocatore aveva scelto di continuare dopo una vittoria per dominio
	v.set_ranking(standings(state))
	var winner := ""
	var player_rank := 0
	for row in v.ranking:
		var d: Dictionary = row
		if winner == "":
			winner = str(d["fazione"])
		if bool(d["giocatore"]):
			player_rank = int(d["posizione"])
	var text := Lang.t("Fine della campagna (%d).") % state.year
	if winner != "":
		text += Lang.t(" Prima in classifica: %s.") % SimUtil.faction_label(winner)
	state.add_event(GameState.EV_CAMPAIGN_END, {
		"fazione": winner,
		"regione": "",
		"vincitore": winner,
		"posizione_giocatore": player_rank,
		"giocatore": player.id if player != null else "",
		"classifica": v.ranking.duplicate(true),
		"testo": text,
	})
