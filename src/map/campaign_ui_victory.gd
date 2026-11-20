class_name CampaignUiVictory
extends RefCounted
## Testi e dati dell'interfaccia della fase 6b (vittoria, sconfitta, fine della campagna): funzioni pure che leggono lo stato e
## producono stringhe, righe o dizionari, senza modificarlo. L'interfaccia (scenes/) mostra e invia solo comandi
## (ADR-003, 008). Nessuna regola e' ricalcolata qui: avanzamento e classifica vengono da `VictoryProcessor`.
##
## - barra in alto: «Province 12/48» (province controllate / necessarie per il dominio) con tooltip;
## - pannello della classifica (tasto G): fazioni per province, reddito e quota;
## - schermata di fine partita: vittoria per dominio (con «Continua a giocare»), sconfitta, fine della campagna con la classifica.


## Quota come percentuale con la virgola: 0.6667 -> "66,7%".
static func percent_text(share: float) -> String:
	var text := "%.1f%%" % (share * 100.0)
	return text if Lang.is_english() else text.replace(".", ",")


# --- barra in alto ----------------------------------------------------------------------------------------------


## Avanzamento del dominio per la barra: {"testo", "tooltip", "raggiunto"}.
static func progress_info(state: GameState, faction_id: String) -> Dictionary:
	var p := VictoryProcessor.domination_progress(state, faction_id)
	var owned := int(p["province"])
	var needed := int(p["necessarie"])
	var total := int(p["totale"])
	var tip := Lang.t("Dominio: per vincere servono %d province di terra su %d (soglia %s).\nOra ne controlli %d (%s).\nClassifica delle fazioni: G.") % [
		needed, total, percent_text(float(p["soglia"])), owned, percent_text(float(p["quota"]))]
	if bool(p["raggiunto"]):
		tip += Lang.t("\nSoglia raggiunta.")
	elif needed > owned:
		tip += Lang.t("\nTi mancano %d province.") % (needed - owned)
	if state.victory.domination_year > 0:
		tip += Lang.t("\nVittoria per dominio nell'anno %d.") % state.victory.domination_year
	return {"testo": Lang.t("Province %d/%d") % [owned, needed], "tooltip": tip, "raggiunto": bool(p["raggiunto"])}


# --- classifica -------------------------------------------------------------------------------------------------


static func standings_headers() -> PackedStringArray:
	return PackedStringArray(["#", Lang.t("Fazione"), Lang.t("Province"), Lang.t("Reddito"), Lang.t("Quota")])


## Titolo del pannello della classifica.
static func standings_title(state: GameState) -> String:
	var needed := state.rules.victory.provinces_needed(VictoryProcessor.total_provinces(state))
	return Lang.t("Classifica · anno %d · dominio: %d province su %d") % [state.year, needed, VictoryProcessor.total_provinces(state)]


## Righe del pannello dalla classifica attuale (`VictoryProcessor.standings`).
static func standings_rows(state: GameState) -> Array[Dictionary]:
	return rows_from(VictoryProcessor.standings(state))


## Righe formattate da una classifica (anche quella salvata nell'esito): {"fazione", "giocatore", "province", "celle"}, con le celle
## nell'ordine di `standings_headers`.
static func rows_from(ranking: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in ranking:
		var r: Dictionary = item
		var cells := PackedStringArray([
			str(CampaignUiText.int_of(r.get("posizione"))),
			CampaignUiText.faction_name(SimUtil.norm(CampaignUiText.text_of(r.get("fazione")))),
			str(CampaignUiText.int_of(r.get("province"))),
			str(CampaignUiText.int_of(r.get("reddito"))),
			percent_text(float(r.get("quota", 0.0))),
		])
		out.append({
			"fazione": SimUtil.norm(CampaignUiText.text_of(r.get("fazione"))),
			"giocatore": bool(r.get("giocatore", false)),
			"province": CampaignUiText.int_of(r.get("province")),
			"celle": cells,
		})
	return out


# --- fine della partita -----------------------------------------------------------------------------------------


## Riga per il resoconto di fine anno quando la partita finisce per l'anno finale ("" negli altri casi: la vittoria e la sconfitta
## hanno gia' la loro riga negli eventi).
static func finished_line(state: GameState) -> String:
	var outcome := state.victory.outcome
	if outcome == VictoryState.CAMPAIGN_END or (outcome == VictoryState.NONE and state.is_finished()):
		return Lang.t("La partita è finita: anno finale %d raggiunto.") % state.year
	return ""


## Avviso breve quando si prova a giocare un anno a partita finita.
static func game_over_hint(state: GameState) -> String:
	var v := state.victory
	if v.awaits_choice():
		return Lang.t("Vittoria per dominio: scegli se continuare a giocare.")
	if v.outcome == VictoryState.DEFEAT:
		return Lang.t("La partita è finita: sconfitta nell'anno %d.") % v.year
	return Lang.t("La partita è finita (anno %d).") % state.year


## Vero se la partita e' finita o aspetta la scelta dopo la vittoria: la schermata di fine partita va mostrata.
static func has_end_screen(state: GameState) -> bool:
	return state.is_game_over()


## Contenuto della schermata di fine partita: {"esito" (VictoryState.*, "fine_campagna" se finita solo per l'anno),
## "titolo", "testo", "intestazioni", "righe" (celle e giocatore), "puo_continuare"}.
static func end_screen(state: GameState, faction_id: String) -> Dictionary:
	var v := state.victory
	var outcome := v.outcome
	if outcome == VictoryState.NONE:
		outcome = VictoryState.CAMPAIGN_END
	var ranking: Array = v.ranking
	if ranking.is_empty():
		ranking = VictoryProcessor.standings(state)
	var rows := rows_from(ranking)
	var key := SimUtil.norm(faction_id)
	var player_name := CampaignUiText.faction_name(key)
	var position := 0
	for i in rows.size():
		if bool(rows[i]["giocatore"]) or str(rows[i]["fazione"]) == key:
			position = i + 1
	var title := ""
	var body := ""
	if outcome == VictoryState.DOMINATION:
		var progress := VictoryProcessor.domination_progress(state, key)
		title = Lang.t("Vittoria per dominio")
		# i nomi delle fazioni sono plurali («Auror», «Inglesi»): il testo parla al giocatore, cosi' il verbo non dipende dal nome
		body = Lang.t("Nel %d, alla guida di %s, controlli %d province su %d (%s): il dominio è tuo.\n\nPuoi continuare a giocare fino al %d, o fermarti qui.") % [
			v.domination_year if v.domination_year > 0 else v.year, player_name, int(progress["province"]), int(progress["totale"]),
			percent_text(float(progress["quota"])), state.final_year]
	elif outcome == VictoryState.DEFEAT:
		title = Lang.t("Sconfitta")
		var last := {}
		for e in state.events:
			if str(e.get("tipo", "")) == GameState.EV_DEFEAT:
				last = e
		var why := Lang.t("non restano né province né eserciti")
		if CampaignUiText.text_of(last.get("motivo")) == "estinta":
			why = Lang.t("la dinastia si è estinta")
		body = Lang.t("Nel %d la tua fazione (%s) è caduta: %s.\n\nLa campagna è finita.") % [v.year, player_name, why]
	else:
		title = Lang.t("Fine della campagna")
		var winner := ""
		if not rows.is_empty():
			winner = CampaignUiText.fart(str(rows[0]["fazione"]))
		body = Lang.t("Siamo nel %d: la campagna è finita.") % state.year
		if winner != "":
			body += Lang.t("\n\nAl primo posto: %s, con %d province.") % [winner, int(rows[0]["province"])]
		if position > 0:
			body += Lang.t("\nLa tua fazione (%s) è in posizione %d su %d.") % [player_name, position, rows.size()]
		if v.domination_year > 0:
			body += Lang.t("\nIl dominio era già tuo dal %d.") % v.domination_year
	return {
		"esito": outcome,
		"titolo": title,
		"testo": body,
		"intestazioni": standings_headers(),
		"righe": rows,
		"puo_continuare": v.awaits_choice(),
	}
