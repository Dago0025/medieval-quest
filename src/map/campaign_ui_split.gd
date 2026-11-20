class_name CampaignUiSplit
extends RefCounted
## Separare truppe o navi trascinandole dalla barra in basso sulla mappa (richiesta di Federico del 2026-11-10): si scelgono
## le carte dell'esercito o della flotta nel pannello di rassegna e le si lascia
## - su un altro proprio esercito (o flotta) della stessa regione: le pile passano a lui;
## - su un proprio esercito di una regione raggiungibile: un esercito nuovo con quelle pile parte e vi si unisce all'arrivo;
## - in un punto vuoto della stessa regione: diventano un esercito nuovo, la cui pedina sta dove la si posa (fuori dal
##   castello, se l'esercito di partenza era dentro e non e' assediato);
## - su un'altra regione: un esercito nuovo con quelle pile ci va (movimento o attacco).
## Se si scelgono tutte le pile vale come trascinare l'intera pedina e non si divide nulla. Gli ordini passano dai comandi
## della simulazione (split_army, transfer_stacks, order_move, order_merge, set_piece_spot): se il movimento non si puo'
## dare, le pile tornano nell'esercito di partenza.

const TRASFERISCI := "trasferisci"
const DIVIDI_QUI := "dividi_qui"
const DIVIDI_E_MUOVI := "dividi_e_muovi"
const DIVIDI_E_UNISCI := "dividi_e_unisci"
const TUTTO := "tutto"
const NIENTE := "niente"


## Cosa succede lasciando le pile `indices` dell'esercito `army` nella regione `region_id`, sopra l'esercito `target_id`
## (0 = nessuno): {"azione", "testo" (motivo se NIENTE)}.
static func plan(state: GameState, player_id: String, army: Army, indices: PackedInt32Array, region_id: String, target_id: int) -> Dictionary:
	if army == null or army.faction != SimUtil.norm(player_id) or army.stacks.is_empty():
		return {"azione": NIENTE, "testo": ""}
	var picked := _valid(army, indices)
	if picked.is_empty():
		return {"azione": NIENTE, "testo": Lang.t("Scegli prima una o più unità nella barra in basso.")}
	if army.is_crusade():
		return {"azione": NIENTE, "testo": Lang.t("Un esercito crociato non si divide.")}
	if picked.size() >= army.stacks.size():
		return {"azione": TUTTO, "testo": ""}
	var target := state.army(target_id)
	if target != null and target.id != army.id and target.faction == army.faction:
		if target.is_fleet != army.is_fleet:
			return {"azione": NIENTE, "testo": Lang.t("Truppe e navi non si mescolano.")}
		if target.stacks.size() + picked.size() > state.rules.max_stacks:
			return {"azione": NIENTE, "testo": Lang.t("Non c'è posto: un esercito ha al massimo %d unità.") % state.rules.max_stacks}
		if target.region == army.region:
			if target.in_castle != army.in_castle:
				return {"azione": NIENTE, "testo": Lang.t("Uno dei due eserciti è nel castello.")}
			return {"azione": TRASFERISCI, "testo": ""}
		return {"azione": DIVIDI_E_UNISCI, "testo": ""}
	var region := state.campaign.region(region_id)
	if region == null:
		return {"azione": NIENTE, "testo": Lang.t("Nessuna regione in quel punto.")}
	if region.is_sea != army.is_fleet:
		return {"azione": NIENTE, "testo": Lang.t("Le navi stanno in mare, le truppe a terra.")}
	if region.id == army.region:
		return {"azione": DIVIDI_QUI, "testo": ""}
	return {"azione": DIVIDI_E_MUOVI, "testo": ""}


## Esegue il piano: {"ok", "azione", "testo" (per il messaggio), "esercito" (id dell'esercito nuovo, 0 se nessuno)}.
## `spot` = punto della mappa dove posare la pedina nuova (DIVIDI_QUI; Vector2.INF = posizione automatica).
static func apply(state: GameState, player_id: String, army_id: int, indices: PackedInt32Array, region_id: String, target_id: int, spot: Vector2 = Vector2.INF) -> Dictionary:
	var army := state.army(army_id)
	var p := plan(state, player_id, army, indices, region_id, target_id)
	var action := str(p["azione"])
	var out := {"ok": false, "azione": action, "testo": str(p["testo"]), "esercito": 0}
	var picked := _valid(army, indices) if army != null else PackedInt32Array()
	var count := picked.size()
	var what := (Lang.t("nave") if count == 1 else Lang.t("navi")) if army != null and army.is_fleet else Lang.t("unità")
	match action:
		TRASFERISCI:
			var r := GameCommands.transfer_stacks(state, player_id, army_id, target_id, picked)
			out["ok"] = bool(r["ok"])
			out["testo"] = (Lang.t("%d %s %s all'esercito %d.") % [count, what, _verb(count, Lang.t("passa"), Lang.t("passano")), target_id]) if out["ok"] else str(r.get("errore", ""))
		DIVIDI_QUI:
			var r := GameCommands.split_army(state, player_id, army_id, picked)
			if not bool(r["ok"]):
				out["testo"] = str(r.get("errore", ""))
				return out
			var fresh := state.army(int(r["esercito"]))
			out["esercito"] = fresh.id
			out["ok"] = true
			var note := ""
			if fresh.in_castle and spot != Vector2.INF:
				if bool(GameCommands.leave_castle(state, player_id, fresh.id)["ok"]):
					note = Lang.t(", fuori dal castello")
			if spot != Vector2.INF and not fresh.in_castle:
				GameCommands.set_piece_spot(state, player_id, "esercito", fresh.id, spot)
			out["testo"] = Lang.t("%d %s %s l'esercito %d%s.") % [count, what, _verb(count, Lang.t("forma"), Lang.t("formano")), fresh.id, note]
		DIVIDI_E_MUOVI, DIVIDI_E_UNISCI:
			var r := GameCommands.split_army(state, player_id, army_id, picked)
			if not bool(r["ok"]):
				out["testo"] = str(r.get("errore", ""))
				return out
			var fresh := state.army(int(r["esercito"]))
			var order := {}
			if action == DIVIDI_E_UNISCI:
				order = GameCommands.order_merge(state, player_id, fresh.id, target_id)
			else:
				order = GameCommands.order_move(state, player_id, fresh.id, _path(state, fresh, region_id))
			if not bool(order["ok"]):
				# il movimento non si puo' dare: le pile tornano da dove venivano
				GameCommands.merge_armies(state, player_id, fresh.id, army_id)
				out["testo"] = str(order.get("errore", Lang.t("Movimento non possibile.")))
				return out
			out["ok"] = true
			out["esercito"] = fresh.id
			var where := CampaignUiText.region_name(state, state.army(target_id).region if action == DIVIDI_E_UNISCI else region_id)
			if action == DIVIDI_E_UNISCI:
				out["testo"] = Lang.t("%d %s %s per %s e %s all'esercito %d all'arrivo.") % [count, what, _verb(count, Lang.t("parte"), Lang.t("partono")), where, _verb(count, Lang.t("si unirà"), Lang.t("si uniranno")), target_id]
			elif bool(order.get("attacco", false)):
				out["testo"] = Lang.t("%d %s %s %s (esercito %d).") % [count, what, _verb(count, Lang.t("attacca"), Lang.t("attaccano")), where, fresh.id]
			else:
				out["testo"] = Lang.t("%d %s %s per %s (esercito %d).") % [count, what, _verb(count, Lang.t("parte"), Lang.t("partono")), where, fresh.id]
	return out


static func _verb(count: int, one: String, many: String) -> String:
	return one if count == 1 else many


static func _path(state: GameState, army: Army, region_id: String) -> PackedStringArray:
	var here := state.campaign.region(army.region)
	if army.is_fleet and here != null and not here.neighbours.has(region_id):
		var route := GameCommands.fleet_path(state, army.id, region_id)
		if not route.is_empty():
			return route
	return PackedStringArray([SimUtil.norm(region_id)])


static func _valid(army: Army, indices: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if army == null:
		return out
	for i in indices:
		if i >= 0 and i < army.stacks.size() and not out.has(i):
			out.append(i)
	out.sort()
	return out
