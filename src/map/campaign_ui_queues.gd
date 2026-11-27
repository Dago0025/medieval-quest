class_name CampaignUiQueues
extends RefCounted
## Code di produzione a colpo d'occhio (richiesta di Federico del 2026-11-10): le voci in coda di una provincia per il
## pannello di rassegna e l'elenco di tutte le province proprie con le loro code (tasto Q), per scorrerle in fretta.
## Funzioni pure sullo stato; le immagini le sceglie la scena (BuildingArt, PieceArt).


## Voci in coda della provincia, nell'ordine in cui si completano: prima gli edifici, poi le unita', poi le unita' della
## coda ripetuta in attesa di fondi. Ogni voce: {"tipo": QueueItem.KIND_BUILDING | KIND_UNIT, "chiave", "livello",
## "anni" (0 = in attesa), "posizione" (da 1 nella sua coda), "attesa" (vero per quelle senza fondi)}.
static func entries(province: ProvinceState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if province == null:
		return out
	for i in province.building_queue.size():
		var b := province.building_queue[i]
		out.append({"tipo": QueueItem.KIND_BUILDING, "chiave": b.key, "livello": b.level, "anni": b.years_left, "posizione": i + 1, "attesa": false})
	for i in province.unit_queue.size():
		var u := province.unit_queue[i]
		out.append({"tipo": QueueItem.KIND_UNIT, "chiave": u.key, "livello": 0, "anni": u.years_left, "posizione": i + 1, "attesa": false})
	if province.repeats_units():
		for unit_id in province.repeat_pending:
			out.append({"tipo": QueueItem.KIND_UNIT, "chiave": str(unit_id), "livello": 0, "anni": 0, "posizione": 0, "attesa": true})
	return out


## Righe dell'elenco delle code: una per provincia propria, nell'ordine delle frecce della barra (GameState.provinces_of).
## Ogni riga: {"provincia", "nome", "voci" (entries), "edifici", "unita" (quante in coda), "ripete" (coda ripetuta)}.
## `only_busy` tiene solo le province con qualcosa in coda; `only_idle` solo quelle senza nulla.
static func rows(state: GameState, player_id: String, only_busy: bool = false, only_idle: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in state.provinces_of(player_id):
		var items := entries(p)
		if only_busy and items.is_empty():
			continue
		if only_idle and not items.is_empty():
			continue
		out.append({"provincia": p.id, "nome": CampaignUiText.region_name(state, p.id), "voci": items,
			"edifici": p.building_queue.size(), "unita": p.unit_queue.size(), "ripete": p.repeats_units()})
	return out


## Provincia propria dopo (o prima, `step` = -1) `current` nell'ordine delle frecce; "" se il giocatore non ne ha.
## Con `only_busy` salta le province senza nulla in coda (e se nessuna ha code restituisce "").
static func next_province(state: GameState, player_id: String, current: String, step: int, only_busy: bool = false) -> String:
	var own := state.provinces_of(player_id)
	var ids := PackedStringArray()
	for p in own:
		if not only_busy or not entries(p).is_empty():
			ids.append(p.id)
	if ids.is_empty():
		return ""
	var index := -1
	var all := PackedStringArray()
	for p in own:
		all.append(p.id)
	var at := all.find(SimUtil.norm(current))
	if at < 0:
		return ids[0] if step >= 0 else ids[ids.size() - 1]
	# prossima nell'ordine completo che sia tra quelle ammesse
	for k in range(1, all.size() + 1):
		var candidate := all[posmod(at + k * signi(step if step != 0 else 1), all.size())]
		index = ids.find(candidate)
		if index >= 0:
			return candidate
	return ids[0]


## Testo breve delle code per il titolo del pannello di rassegna («in coda: 2 edifici, 3 unità»), "" se vuote.
static func summary(province: ProvinceState) -> String:
	if province == null:
		return ""
	var parts := PackedStringArray()
	if not province.building_queue.is_empty():
		parts.append("%d %s" % [province.building_queue.size(), Lang.t("edificio") if province.building_queue.size() == 1 else Lang.t("edifici")])
	var units := province.unit_queue.size()
	if units > 0:
		parts.append("%d %s" % [units, Lang.t("unità")])
	if parts.is_empty():
		return ""
	return Lang.t("in coda: ") + ", ".join(parts) + (Lang.t(" (si ripete)") if province.repeats_units() else "")


# --- finestra di costruzione a icone (richiesta di Federico dell'11/11/2026) ----------------------------------------------
# Un edificio scelto sparisce da quelli da costruire e compare, con la sua icona, tra quelli in costruzione; un clic li'
# lo toglie dalla coda e lo fa tornare tra quelli da costruire.


## Tessere degli edifici in coda, nell'ordine della coda: {"indice" (nella coda, per annullare), "famiglia", "livello",
## "anni" (che mancano), "in_corso" (vero per il primo), "rimborso" (denari restituiti annullando)}.
static func building_tiles(province: ProvinceState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if province == null:
		return out
	for i in province.building_queue.size():
		var b := province.building_queue[i]
		out.append({"indice": i, "famiglia": b.key, "livello": b.level, "anni": b.years_left, "in_corso": i == 0, "rimborso": b.cost_paid})
	return out


## Voci degli edifici ancora da scegliere: quelle di `entries` (campo "family") la cui famiglia non e' gia' in coda.
static func not_queued(entries: Array[Dictionary], province: ProvinceState) -> Array[Dictionary]:
	var queued := {}
	if province != null:
		for b in province.building_queue:
			queued[b.key] = true
	var out: Array[Dictionary] = []
	for e in entries:
		if not queued.has(str(e.get("family", ""))):
			out.append(e)
	return out


## Didascalia e suggerimento della tessera di un edificio in coda (`title` = nome con il livello).
static func building_tile_text(tile: Dictionary, title: String) -> Dictionary:
	var years := int(tile.get("anni", 0))
	var when := "%d %s" % [years, Lang.t("anno") if years == 1 else Lang.t("anni")]
	var caption := (Lang.t("in corso · %s") % when) if bool(tile.get("in_corso", false)) else (Lang.t("in attesa · %s") % when)
	var tip := Lang.t("%s\n%s\nClic: toglilo dalla coda e torna tra gli edifici da costruire (rimborso %d denari, i lavori fatti si perdono).") % [
		title, Lang.t("In costruzione: mancano %s.") % when if bool(tile.get("in_corso", false)) else Lang.t("In coda: %s di lavori.") % when, int(tile.get("rimborso", 0))]
	return {"didascalia": caption, "suggerimento": tip}


## Tessere della coda di arruolamento (richiesta di Federico dell'11/11/2026: come gli edifici, icone e non righe): prima le
## unita' in coda {"indice", "unita", "anni", "in_corso", "rimborso", "attesa": false}, poi quelle della coda ripetuta in
## attesa di fondi {"indice": -1, "unita", "anni": 0, "in_corso": false, "rimborso": 0, "attesa": true} (non annullabili).
static func unit_tiles(province: ProvinceState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if province == null:
		return out
	for i in province.unit_queue.size():
		var u := province.unit_queue[i]
		out.append({"indice": i, "unita": u.key, "anni": u.years_left, "in_corso": i == 0, "rimborso": u.cost_paid, "attesa": false})
	if province.repeats_units():
		for unit_id in province.repeat_pending:
			out.append({"indice": -1, "unita": str(unit_id), "anni": 0, "in_corso": false, "rimborso": 0, "attesa": true})
	return out


## Didascalia e suggerimento della tessera di un'unita' in coda (`title` = nome dell'unita').
static func unit_tile_text(tile: Dictionary, title: String) -> Dictionary:
	if bool(tile.get("attesa", false)):
		return {"didascalia": Lang.t("senza fondi"), "suggerimento": Lang.t("%s\nCoda ripetuta in pausa: riparte da sola quando il tesoro basta.") % title}
	var years := int(tile.get("anni", 0))
	var when := "%d %s" % [years, Lang.t("anno") if years == 1 else Lang.t("anni")]
	var caption := (Lang.t("in corso · %s") % when) if bool(tile.get("in_corso", false)) else (Lang.t("in attesa · %s") % when)
	return {"didascalia": caption, "suggerimento": Lang.t("%s\n%s\nClic: toglila dalla coda (rimborso %d denari).") % [
		title, Lang.t("In addestramento: mancano %s.") % when if bool(tile.get("in_corso", false)) else Lang.t("In coda: %s di addestramento.") % when, int(tile.get("rimborso", 0))]}


## Voci arruolabili divise nelle tre schede della finestra di arruolamento (richiesta di Federico del 18/11/2026):
## «Truppe» (non navi, non agenti), «Flotta» (navi), «Agenti». Ogni scheda: {"titolo", "voci"} nell'ordine ricevuto.
static func recruit_groups(entries: Array) -> Array[Dictionary]:
	var troops: Array = []
	var ships: Array = []
	var agents: Array = []
	for item in entries:
		var e: Dictionary = item
		if bool(e.get("agente", false)):
			agents.append(e)
		elif bool(e.get("nave", false)):
			ships.append(e)
		else:
			troops.append(e)
	return [{"titolo": Lang.t("Truppe"), "voci": troops}, {"titolo": Lang.t("Flotta"), "voci": ships}, {"titolo": Lang.t("Agenti"), "voci": agents}]
