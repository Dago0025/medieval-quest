class_name HistoricalLimits
extends RefCounted
## Limiti storici della simulazione (ADR-114, richiesta di Federico del 21/11/2026), regole in data/regole/storia.cfg
## (`Rules.history`):
## - **invenzioni**: un livello d'edificio con un'invenzione (colonna 26: GUNPOWDER, COMPASS) si costruisce solo dopo
##   l'evento storico che la porta (polvere da sparo 1260, bussola 1169); un'unita' che si arruola solo con edifici di
##   invenzioni non arrivate non si arruola e non compare tra ribelli, lealisti, mercenari, crociati. Gli Auror ne sono
##   esenti (`armi_da_fuoco_subito`);
## - **cavalli nelle Americhe**: Aztechi, Inca e Cahokia non hanno cavalleria finche' una fazione venuta da fuori non
##   possiede una regione delle Americhe (`GameState.americas_contact_year`).
## Funzioni pure sullo stato, nessun sorteggio.


## Vero se l'invenzione e' disponibile: senza evento associato (o con un evento che la tabella non ha) sempre.
static func invention_known(state: GameState, invention: String) -> bool:
	var key := str(state.rules.history.inventions.get(invention.strip_edges().to_upper(), ""))
	if key == "":
		return true
	for e in state.rules.events.history:
		if e.key.to_upper() == key:
			return state.historical_done.has(e.index)
	return true


## Prima invenzione mancante per il livello d'edificio (per la fazione), "" se non ne manca nessuna.
static func missing_invention(state: GameState, faction_id: String, lv: BuildingType.Level) -> String:
	if lv == null or lv.inventions.is_empty() or state.rules.history.ignores_inventions(faction_id):
		return ""
	for inv in lv.inventions:
		if not invention_known(state, inv):
			return inv
	return ""


## Vero se l'unita' si puo' avere per le invenzioni: nessun requisito, oppure almeno un'alternativa di edifici richiesti
## senza livelli di invenzioni mancanti (anche nei requisiti di quei livelli). Con `faction_id` esente (Auror) sempre vero.
static func unit_inventions_ok(state: GameState, faction_id: String, unit: UnitType) -> bool:
	if unit == null or unit.requires.is_empty():
		return true
	if faction_id != "" and state.rules.history.ignores_inventions(faction_id):
		return true
	if state.buildings == null:
		return true
	return not _groups_blocked(state, unit.requires, 0)


## Vero se ogni alternativa di requisiti contiene un livello bloccato da un'invenzione mancante, anche attraverso i suoi
## requisiti (la fonderia di cannoni richiede la fonderia di campane, che aspetta la polvere da sparo). Profondita' massima 6.
static func _groups_blocked(state: GameState, groups: Array[PackedStringArray], depth: int) -> bool:
	if groups.is_empty() or depth > 6:
		return false
	for group in groups:
		var blocked := false
		for token in group:
			if _level_blocked(state, state.buildings.resolve(token), depth + 1):
				blocked = true
				break
		if not blocked:
			return false
	return true


static func _level_blocked(state: GameState, lv: BuildingType.Level, depth: int) -> bool:
	if lv == null:
		return false
	if missing_invention(state, "", lv) != "":
		return true
	return _groups_blocked(state, lv.requires, depth)


## Unita' a cavallo (o su cammello).
static func is_mounted(unit: UnitType) -> bool:
	return unit != null and not unit.is_ship() and (unit.is_cavalry() or unit.mount_type != "")


## Vero se la fazione ha i cavalli: tutte, tranne i popoli senza cavalli prima dell'arrivo degli europei.
static func horses_allowed(state: GameState, faction_id: String) -> bool:
	return not state.rules.history.is_horseless(faction_id) or state.americas_contact_year > 0


## Vero se nella regione possono comparire cavalli (ribelli e mercenari): fuori dalle Americhe sempre, nelle Americhe
## dopo l'arrivo degli europei.
static func horses_in_region(state: GameState, region_id: String) -> bool:
	return state.americas_contact_year > 0 or not state.rules.history.is_americas(region_id)


## Tutti i limiti storici per un'unita' della fazione (invenzioni e cavalli). `region_id` (facoltativo) vale per chi non
## e' una fazione con dinastia (ribelli, mercenari): i cavalli seguono la regione.
static func unit_allowed(state: GameState, faction_id: String, unit: UnitType, region_id: String = "") -> bool:
	if not unit_inventions_ok(state, faction_id, unit):
		return false
	if not is_mounted(unit):
		return true
	if not horses_allowed(state, faction_id):
		return false
	return region_id == "" or horses_in_region(state, region_id)


## Fine anno: l'arrivo degli europei nelle Americhe (il primo anno in cui una fazione fuori dall'elenco dei popoli senza
## cavalli, ribelli esclusi, possiede una regione delle Americhe). Restituisce vero l'anno in cui accade.
static func update_contact(state: GameState) -> bool:
	if state.americas_contact_year > 0 or state.rules.history.americas.is_empty():
		return false
	for p in state.provinces:
		if p.owner == "" or p.owner == GameState.REBEL or state.rules.history.is_horseless(p.owner):
			continue
		if state.rules.history.is_americas(p.id):
			state.americas_contact_year = state.year
			state.add_event(GameState.EV_AMERICAS_CONTACT, {
				"fazione": p.owner,
				"regione": p.id,
				"provincia": p.id,
				"testo": Lang.t("Primo approdo straniero nelle Americhe: %s a %s. Da ora i popoli del Nuovo Mondo conoscono il cavallo.") % [
					SimUtil.faction_label(p.owner), WarProcessor.region_label(state, p.id)],
			})
			return true
	return false
