class_name CampaignUiEvents
extends RefCounted
## Testi e dati dell'interfaccia della fase 6 (eventi e storia): funzioni pure che leggono lo stato e producono stringhe o
## dizionari, senza modificarlo. L'interfaccia (scenes/) mostra e invia solo comandi (ADR-003, 008).
##
## - finestra dell'evento storico: titolo e testo originali letti da Events.txt dell'installazione con `EventTexts` (ADR-007),
##   o un testo di ripiego in italiano con la chiave se il file manca; una riga con l'effetto;
## - testi italiani degli eventi della 6a (storici, disastri, Peste Nera, Orda d'Oro) e della 6b (vittoria, sconfitta, fine
##   della campagna) per il resoconto di fine anno, sezione «Eventi e storia». I disastri portano in coda il messaggio
##   originale di Events.txt con il nome della regione, quando il file c'e'.
##
## I testi originali non entrano mai nel repository: si leggono a ogni avvio, una volta sola, e si tengono in `_texts`.

static var _texts: EventTexts = null


## I testi originali (Events.txt dell'installazione, letti alla prima richiesta). Senza il file la tabella e' vuota.
static func texts() -> EventTexts:
	if _texts == null:
		_texts = EventTexts.load_file()
	return _texts


## Sostituisce i testi (per i test e per chi li ha gia' letti).
static func set_texts(new_texts: EventTexts) -> void:
	_texts = new_texts


## Dimentica i testi letti: la prossima richiesta li rilegge dall'installazione.
static func reset_texts() -> void:
	_texts = null


# --- finestra dell'evento storico ---------------------------------------------------------------------------------


## Una finestra per ogni evento storico del registro dell'anno, nell'ordine del registro:
## {"indice", "chiave", "anno", "titolo", "testo", "effetto" (riga), "originale" (vero se titolo e testo vengono da Events.txt),
## "provvisoria"}.
static func historical_windows(state: GameState, source: EventTexts = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in state.events:
		if str(e.get("tipo", "")) == GameState.EV_HISTORICAL:
			out.append(historical_window(state, e, source))
	return out


## Finestre illustrate per le notizie piu' importanti dell'anno, dopo quelle degli eventi storici (richiesta di Federico del
## 2026-11-13): crociate e jihad bandite da qualunque fazione e crociate dirette contro una provincia di `viewer`. Stessa forma
## delle finestre storiche, con "indice" -1 e "chiave" crociata o jihad (la tavola la sceglie `EventArt` per tema).
static func news_windows(state: GameState, viewer: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key := SimUtil.norm(viewer)
	for e in state.events:
		var kind := str(e.get("tipo", ""))
		var jihad := str(e.get("genere", "")).to_lower().contains("jihad")
		var theme := "jihad" if jihad else "crociata"
		if kind == GameState.EV_CRUSADE_LAUNCHED:
			out.append({"indice": -1, "chiave": theme, "anno": CampaignUiText.int_of(e.get("anno"), state.year),
				"titolo": Lang.t("Jihad proclamata") if jihad else Lang.t("Crociata bandita"), "testo": CampaignUiText.format_event(state, e),
				"effetto": crusade_effect(state, e, key), "originale": false, "provvisoria": false})
		elif kind == GameState.EV_CRUSADE_TARGET:
			var target := str(e.get("bersaglio", ""))
			var province := state.province(target)
			if target == "" or province == null or province.owner != key:
				continue
			out.append({"indice": -1, "chiave": theme, "anno": CampaignUiText.int_of(e.get("anno"), state.year),
				"titolo": Lang.t("La %s marcia contro di voi") % (Lang.t("jihad") if jihad else Lang.t("crociata")), "testo": CampaignUiText.format_event(state, e),
				"effetto": Lang.t("minaccia su %s") % CampaignUiText.region_name(state, target), "originale": false, "provvisoria": false})
	return out


## Riga dell'effetto di una crociata o jihad bandita: chi la guida e se il giocatore puo' unirsi (stessa fede).
static func crusade_effect(state: GameState, e: Dictionary, viewer: String) -> String:
	var leader := str(e.get("fazione", ""))
	if leader == viewer:
		return Lang.t("la guidate voi: l'esercito crociato raccoglie volontari nelle province che attraversa")
	return Lang.t("guidata %s") % CampaignUiText.fprep("da", leader, "by")


## La finestra di un evento storico. Con `source` nullo si usano i testi dell'installazione.
static func historical_window(state: GameState, e: Dictionary, source: EventTexts = null) -> Dictionary:
	var lines := source if source != null else texts()
	var index := CampaignUiText.int_of(e.get("indice"), -1)
	var key := CampaignUiText.text_of(e.get("chiave"))
	var year := CampaignUiText.int_of(e.get("anno"))
	var original := lines.has_historical(index)
	var title := ""
	var body := ""
	if original:
		title = lines.historical_title(index).strip_edges()
		body = lines.historical_text(index).strip_edges()
	if title == "":
		original = false
		title = fallback_title(index, key)
	if body == "":
		original = false
		body = fallback_text(index, key, year)
	return {
		"indice": index,
		"chiave": key,
		"anno": year,
		"titolo": title,
		"testo": body,
		"effetto": effect_line(state, e),
		"originale": original,
		"provvisoria": bool(e.get("provvisoria", false)),
	}


static func fallback_title(index: int, key: String) -> String:
	if key != "":
		return Lang.t("Evento storico: %s") % key.replace("_", " ").capitalize()
	return Lang.t("Evento storico n. %d") % index


static func fallback_text(index: int, key: String, year: int) -> String:
	var label := Lang.t("n. %d") % index
	if key != "":
		label = "«%s»" % key
	return Lang.t("Il testo originale non è disponibile: i file di Medieval: Total War non sono stati trovati (evento storico %s, anno %d).") % [label, year]


## Riga con l'effetto di un evento storico (campi "effetto", "valore", "regioni", "fazioni", "provvisoria").
static func effect_line(state: GameState, e: Dictionary) -> String:
	var effect := CampaignUiText.text_of(e.get("effetto"))
	var value := CampaignUiText.int_of(e.get("valore"))
	var regions := CampaignUiText.list_of(e.get("regioni"))
	var factions := CampaignUiText.list_of(e.get("fazioni"))
	var text := Lang.t("nessun effetto sul gioco")
	if effect == EventRules.EFFECT_GOODS:
		text = Lang.t("nuove merci per il commercio: %s") % region_list(state, regions)
	elif effect == EventRules.EFFECT_LOYALTY:
		text = Lang.t("lealtà dei generali e dei principi %s: %s") % [CampaignUiText.signed(value), faction_list(factions)]
	elif effect == EventRules.EFFECT_ZEAL:
		text = Lang.t("zelo %s: %s") % [CampaignUiText.signed(value), region_list(state, regions)]
	elif effect == EventRules.EFFECT_HERETICS:
		text = Lang.t("eretici %s%% in %s") % [CampaignUiText.signed(value), region_list(state, regions)]
	elif effect == EventRules.EFFECT_PIETY:
		text = Lang.t("pietà del capo %s: %s") % [CampaignUiText.signed(value), faction_list(factions)]
	elif effect == EventRules.EFFECT_TREASURY:
		text = Lang.t("tesoro %s denari: %s") % [CampaignUiText.signed(value), faction_list(factions)]
	if effect != EventRules.EFFECT_NONE and effect != "" and bool(e.get("provvisoria", false)):
		text += Lang.t(" (effetto provvisorio)")
	return text


## "A, B, C e altre 4" per un elenco di regioni (id).
static func region_list(state: GameState, ids: Array, limit: int = 5) -> String:
	if ids.is_empty():
		return Lang.t("nessuna provincia coinvolta")
	var names := PackedStringArray()
	for id in ids:
		names.append(CampaignUiText.region_name(state, str(id)))
	return _joined(names, limit)


## Elenco di fazioni (id), con lo stesso troncamento.
static func faction_list(ids: Array, limit: int = 5) -> String:
	if ids.is_empty():
		return Lang.t("nessuna fazione coinvolta")
	var names := PackedStringArray()
	for id in ids:
		names.append(CampaignUiText.faction_name(SimUtil.norm(str(id))))
	return _joined(names, limit)


static func _joined(names: PackedStringArray, limit: int) -> String:
	if names.size() <= limit:
		return ", ".join(names)
	var shown := PackedStringArray()
	for i in range(limit):
		shown.append(names[i])
	return Lang.t("%s e altre %d") % [", ".join(shown), names.size() - limit]


# --- testi del resoconto -----------------------------------------------------------------------------------------


## Testo italiano di un evento della 6a o della 6b; vuoto se `kind` non e' uno dei loro tipi. Senza i campi essenziali ripiega
## sul campo "testo" scritto dalla simulazione.
static func format_event(state: GameState, kind: String, e: Dictionary) -> String:
	var fallback_text_free := CampaignUiText.text_of(e.get("testo"))
	if kind == GameState.EV_HISTORICAL:
		return _historical_line(state, e)
	if kind == GameState.EV_FLOOD or kind == GameState.EV_FAMINE or kind == GameState.EV_QUAKE or kind == GameState.EV_PLAGUE:
		return _disaster_line(state, kind, e, fallback_text_free)
	if kind == GameState.EV_STORM:
		return _storm_line(state, e, fallback_text_free)
	if kind == GameState.EV_BLACK_DEATH:
		return _black_death_line(state, e, fallback_text_free)
	if kind == GameState.EV_HORDE_ARRIVES:
		return _horde_arrives_line(state, e, fallback_text_free)
	if kind == GameState.EV_HORDE_GONE:
		return _horde_gone_line(e)
	if kind == GameState.EV_VICTORY:
		return _victory_line(e, fallback_text_free)
	if kind == GameState.EV_DEFEAT:
		return _defeat_line(e, fallback_text_free)
	if kind == GameState.EV_CAMPAIGN_END:
		return _campaign_end_line(e, fallback_text_free)
	return ""


static func _historical_line(state: GameState, e: Dictionary) -> String:
	var window := historical_window(state, e)
	var label := str(window["titolo"])
	if not bool(window["originale"]):
		var key := str(window["chiave"])
		label = key.replace("_", " ").capitalize() if key != "" else Lang.t("n. %d") % int(window["indice"])
	return Lang.t("Evento storico «%s»: %s.") % [label, str(window["effetto"])]


## Nome della provincia con il proprietario tra parentesi ("Bologna (Alpha)"); senza proprietario solo il nome.
static func place_with_owner(state: GameState, region_id: String, owner_id: String) -> String:
	var place := CampaignUiText.region_name(state, region_id)
	var who := SimUtil.norm(owner_id)
	if who == "":
		return place
	return "%s (%s)" % [place, CampaignUiText.faction_name(who)]


## Il messaggio originale del disastro, con il nome della regione ("" se il file non c'e'): « testo ».
static func original_message(state: GameState, kind: String, region_id: String, e: Dictionary, variant_seed: int = 0) -> String:
	var lines := texts()
	var message := lines.disaster_message(kind, CampaignUiText.region_name(state, region_id), CampaignUiText.int_of(e.get("anno")) + variant_seed)
	message = message.strip_edges()
	if message == "":
		return ""
	return " «%s»" % message


static func _disaster_line(state: GameState, kind: String, e: Dictionary, fallback_text_free: String) -> String:
	var region_id := CampaignUiText.text_of(CampaignUiText.prop(e, ["provincia", "regione"]))
	if region_id == "":
		return fallback_text_free if fallback_text_free != "" else kind
	var place := place_with_owner(state, region_id, CampaignUiText.text_of(e.get("proprietario")))
	var text := ""
	var message_kind := kind
	if kind == GameState.EV_FLOOD:
		text = Lang.t("Inondazione a %s: il raccolto dell'anno è dimezzato.") % place
	elif kind == GameState.EV_FAMINE:
		text = Lang.t("Carestia a %s: nessun raccolto quest'anno") % place
		var lost := CampaignUiText.int_of(e.get("lealta_persa"))
		if lost > 0:
			text += Lang.t(" e lealtà -%d") % lost
		text += "."
	elif kind == GameState.EV_QUAKE:
		var building := CampaignUiText.text_of(e.get("edificio"))
		var building_label := building.replace("_", " ").capitalize()
		text = Lang.t("Terremoto a %s: ") % place
		if building == "":
			text += Lang.t("nessun edificio colpito.")
		elif CampaignUiText.int_of(e.get("livello")) <= 0:
			text += Lang.t("%s è distrutto.") % building_label
		else:
			text += Lang.t("%s scende al livello %d.") % [building_label, CampaignUiText.int_of(e.get("livello"))]
	else:
		var black := bool(e.get("peste_nera", false))
		if black:
			message_kind = GameState.EV_BLACK_DEATH
		text = Lang.t("%s a %s: %d uomini morti") % [Lang.t("Peste Nera") if black else Lang.t("Peste"), place, CampaignUiText.int_of(e.get("uomini"))]
		var armies := CampaignUiText.int_of(e.get("eserciti"))
		if armies > 0:
			text += Lang.t(" in %d eserciti e guarnigioni") % armies
		var origin := CampaignUiText.text_of(e.get("origine"))
		if origin != "":
			text += Lang.t(", contagio da %s") % CampaignUiText.region_name(state, origin)
		text += "."
	return text + original_message(state, message_kind, region_id, e)


static func _storm_line(state: GameState, e: Dictionary, fallback_text_free: String) -> String:
	var region_id := CampaignUiText.text_of(e.get("regione"))
	var faction_id := SimUtil.norm(CampaignUiText.text_of(e.get("fazione")))
	if region_id == "" or faction_id == "":
		return fallback_text_free if fallback_text_free != "" else GameState.EV_STORM
	var text := Lang.t("Tempesta in %s: la flotta %d di %s perde una pila (%d uomini).") % [
		CampaignUiText.region_name(state, region_id), CampaignUiText.int_of(e.get("esercito")),
		CampaignUiText.faction_name(faction_id), CampaignUiText.int_of(e.get("uomini"))]
	return text + original_message(state, GameState.EV_STORM, region_id, e)


static func _black_death_line(state: GameState, e: Dictionary, fallback_text_free: String) -> String:
	var origin := CampaignUiText.list_of(e.get("regioni"))
	if origin.is_empty():
		return fallback_text_free if fallback_text_free != "" else GameState.EV_BLACK_DEATH
	var first := str(origin[0])
	var text := Lang.t("La Peste Nera comincia a %s.") % region_list(state, origin, 3)
	return text + original_message(state, GameState.EV_BLACK_DEATH, first, e)


static func _horde_arrives_line(state: GameState, e: Dictionary, fallback_text_free: String) -> String:
	var region_id := CampaignUiText.text_of(CampaignUiText.prop(e, ["provincia", "regione"]))
	if region_id == "":
		return fallback_text_free if fallback_text_free != "" else GameState.EV_HORDE_ARRIVES
	return Lang.t("L'Orda d'Oro arriva a %s con %d pile (%d uomini).") % [
		CampaignUiText.region_name(state, region_id), CampaignUiText.int_of(e.get("pile")), CampaignUiText.int_of(e.get("uomini"))]


static func _horde_gone_line(e: Dictionary) -> String:
	var provinces := CampaignUiText.list_of(e.get("province")).size()
	var armies := CampaignUiText.list_of(e.get("eserciti")).size()
	var men := CampaignUiText.int_of(e.get("uomini"))
	var why := Lang.t("si scioglie dopo anni senza conquiste")
	if CampaignUiText.text_of(e.get("motivo")) == "distrutta":
		why = Lang.t("è distrutta")
	var text := Lang.t("L'Orda d'Oro %s: %d province passano ai ribelli") % [why, provinces]
	if armies > 0:
		text += Lang.t(", %d eserciti sciolti") % armies
	if men > 0:
		text += Lang.t(" (%d uomini)") % men
	return text + "."


static func _victory_line(e: Dictionary, fallback_text_free: String) -> String:
	var owned := CampaignUiText.int_of(e.get("province"))
	var total := CampaignUiText.int_of(e.get("totale"))
	var who := SimUtil.norm(CampaignUiText.text_of(e.get("fazione")))
	if who == "" or total <= 0:
		return fallback_text_free if fallback_text_free != "" else GameState.EV_VICTORY
	return Lang.t("Vittoria per dominio! %s %s %d province su %d (servivano %d).") % [
		CampaignUiText.fsubj(who), CampaignUiText.fverb(who, Lang.t("controlla"), Lang.t("controllano")), owned, total, CampaignUiText.int_of(e.get("necessarie"))]


static func _defeat_line(e: Dictionary, fallback_text_free: String) -> String:
	var who := SimUtil.norm(CampaignUiText.text_of(e.get("fazione")))
	if who == "":
		return fallback_text_free if fallback_text_free != "" else GameState.EV_DEFEAT
	var why := Lang.t("non restano né province né eserciti")
	if CampaignUiText.text_of(e.get("motivo")) == "estinta":
		why = Lang.t("la dinastia si è estinta")
	return Lang.t("Sconfitta: %s %s, %s.") % [CampaignUiText.fart(who), CampaignUiText.fverb(who, Lang.t("è caduta"), Lang.t("sono caduti")), why]


static func _campaign_end_line(e: Dictionary, fallback_text_free: String) -> String:
	var year := CampaignUiText.int_of(e.get("anno"))
	var winner := SimUtil.norm(CampaignUiText.text_of(e.get("vincitore")))
	var text := Lang.t("Fine della campagna (anno %d).") % year
	if winner != "":
		var rows := CampaignUiText.list_of(e.get("classifica"))
		var best := 0
		if not rows.is_empty() and rows[0] is Dictionary:
			var first: Dictionary = rows[0]
			best = CampaignUiText.int_of(first.get("province"))
		text += Lang.t(" Prima in classifica: %s") % CampaignUiText.faction_name(winner)
		if best > 0:
			text += Lang.t(" con %d province") % best
		text += "."
	elif fallback_text_free != "":
		return fallback_text_free
	var rank := CampaignUiText.int_of(e.get("posizione_giocatore"))
	if rank > 0:
		text += Lang.t(" Il giocatore è %dº.") % rank
	return text
