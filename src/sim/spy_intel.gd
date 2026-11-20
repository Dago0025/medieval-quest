class_name SpyIntel
extends RefCounted
## Informazioni delle spie (richiesta di Federico del 18/11/2026: «spiare provincia o esercito»). Senza informazioni le
## province e gli eserciti delle altre fazioni mostrano solo dati sommari; con informazioni, tutto. Si sa tutto di:
## - province ed eserciti propri e degli alleati, e dei ribelli;
## - province ed eserciti dove la fazione ha una spia (la sola presenza basta, come nell'originale);
## - province ed eserciti spiati con la missione «spiare» negli ultimi `intel_years` anni (`FactionState.intel`).
## Eserciti, flotte e guarnigioni si conoscono anche da vicino (richiesta di Federico del 20/11/2026, `watches_region`):
## nelle proprie province e in quelle o nelle acque che vi confinano, e dove una propria flotta sta o confina. Edifici,
## lealta' e rendite di una provincia altrui restano alle spie.
## Solo calcolo, nessun numero casuale.

const PROVINCE_PREFIX := "P:"
const ARMY_PREFIX := "A:"


static func province_key(region_id: String) -> String:
	return PROVINCE_PREFIX + SimUtil.norm(region_id)


static func army_key(army_id: int) -> String:
	return ARMY_PREFIX + str(army_id)


## Vero se `viewer` conosce i dettagli della provincia (edifici, guarnigione, lealta', rendite).
static func knows_province(state: GameState, viewer: String, region_id: String) -> bool:
	var me := SimUtil.norm(viewer)
	var p := state.province(region_id)
	if p == null:
		return true
	if p.owner == me or p.owner == GameState.REBEL or p.owner == "" or state.is_allied(me, p.owner):
		return true
	if has_spy(state, me, p.id):
		return true
	return _valid(state, me, province_key(p.id))


## Vero se `viewer` conosce la composizione dell'esercito (unita', uomini, comandante).
static func knows_army(state: GameState, viewer: String, army: Army) -> bool:
	if army == null:
		return false
	var me := SimUtil.norm(viewer)
	if army.faction == me or army.faction == GameState.REBEL or state.is_allied(me, army.faction):
		return true
	if has_spy(state, me, army.region) or watches_region(state, me, army.region):
		return true
	return _valid(state, me, army_key(army.id)) or _valid(state, me, province_key(army.region))


## Vero se `viewer` osserva da vicino la regione (terra o mare) e ne conosce quindi eserciti, flotte e guarnigioni
## (richiesta di Federico del 20/11/2026: «dove confino o se ho navi in prossimità»): la regione o una regione confinante
## e' una sua provincia, oppure una sua flotta (con almeno una nave) sta nella regione o in una regione confinante.
static func watches_region(state: GameState, viewer: String, region_id: String) -> bool:
	var me := SimUtil.norm(viewer)
	var key := SimUtil.norm(region_id)
	var near: Array = [key]
	var region := state.campaign.region(key)
	if region != null:
		for n in region.neighbours:
			near.append(SimUtil.norm(str(n)))
	for r in near:
		var p := state.province(str(r))
		if p != null and p.owner == me:
			return true
		for a in state.armies_in(str(r)):
			if a.faction == me and a.is_fleet and not a.stacks.is_empty():
				return true
	return false


## Vero se la fazione ha una spia nella regione.
static func has_spy(state: GameState, faction_id: String, region_id: String) -> bool:
	for a in state.agents:
		if a.type_name == AgentState.SPY and a.faction == faction_id and a.region == region_id:
			return true
	return false


## Registra le informazioni ottenute da una spia, valide fino all'anno `until` compreso.
static func record(state: GameState, faction_id: String, key: String, until: int) -> void:
	var f := state.faction(faction_id)
	if f != null:
		f.intel[key] = maxi(int(f.intel.get(key, 0)), until)


## Toglie le informazioni scadute (a fine anno).
static func expire(state: GameState) -> void:
	for f in state.factions:
		for key in f.intel.keys():
			if int(f.intel[key]) < state.year:
				f.intel.erase(key)


static func _valid(state: GameState, faction_id: String, key: String) -> bool:
	var f := state.faction(faction_id)
	return f != null and int(f.intel.get(key, -1)) >= state.year
