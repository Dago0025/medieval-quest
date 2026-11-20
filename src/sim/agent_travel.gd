class_name AgentTravel
extends RefCounted
## Viaggio di un agente verso una provincia lontana (richiesta di Federico del 2026-11-13): come nell'originale, l'agente
## mandato oltre la portata di un anno parte e prosegue da solo, una tappa all'anno, fino all'arrivo.
##
## Una tappa e' quello che un agente fa in un anno con gli ordini di sempre: una provincia confinante a piedi oppure un
## trasporto via mare (`GameCommands.sea_route` con `troops` falso: porti, zone libere da flotte nemiche, ADR-019/034/035).
## Il percorso e' il piu' breve in anni (ricerca in ampiezza sulle province di terra; a parita' prima la terra, nell'ordine
## di SetNeighbours, poi il mare nell'ordine della ricerca delle zone). L'agente tiene solo la destinazione
## (`AgentState.destination`) e la tappa dell'anno (`path` e `sea_route`): a ogni fine anno, dopo battaglie e conquiste,
## `AgentProcessor.plan_journeys` ricalcola la tappa successiva sullo stato nuovo (porti presi, flotte nemiche...).
## Nessuna formula dell'originale da tarare: e' la regola del movimento ripetuta anno per anno.

## Chiave dei gruppi di zone di mare (`sea_groups`) nella cache di `years_from`.
const TABLE_KEY := "_tabella_mare"
## Chiave dei confini di terra (provincia -> province confinanti) nella cache di `years_from`.
const LAND_KEY := "_confini_terra"

## Tappe del viaggio piu' breve da `from_id` a `to_id` per un agente di `faction_id`: [{"regione", "catena"}], una per
## anno ("catena" = zone di mare, vuota a piedi). Vuoto se `to_id` coincide con la partenza o non si raggiunge.
static func plan(state: GameState, faction_id: String, from_id: String, to_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key := SimUtil.norm(faction_id)
	var start := state.campaign.region(SimUtil.norm(from_id))
	var goal := state.campaign.region(SimUtil.norm(to_id))
	if start == null or goal == null or goal.is_sea or start.id == goal.id:
		return out
	var parent := {start.id: ""}
	var by_sea := {}
	var queue: Array[String] = [start.id]
	var head := 0
	var found := false
	while head < queue.size() and not found:
		var current := queue[head]
		head += 1
		var region := state.campaign.region(current)
		if region == null:
			continue
		for n in region.neighbours:
			var next := state.campaign.region(n)
			if next == null or next.is_sea or parent.has(next.id):
				continue
			parent[next.id] = current
			queue.append(next.id)
			if next.id == goal.id:
				found = true
				break
		if found:
			break
		for land_id in GameCommands.sea_destinations_from(state, key, current, false):
			if parent.has(land_id):
				continue
			parent[land_id] = current
			by_sea[land_id] = true
			queue.append(land_id)
			if land_id == goal.id:
				found = true
				break
	if not parent.has(goal.id):
		return out
	var steps := PackedStringArray()
	var at := goal.id
	while at != start.id:
		steps.insert(0, at)
		at = str(parent[at])
	var previous := start.id
	for step in steps:
		var chain := PackedStringArray()
		if by_sea.has(step):
			chain = GameCommands.sea_route(state, key, previous, step, false)
		out.append({"regione": step, "catena": chain})
		previous = step
	return out


## Anni di viaggio da `from_id` verso ogni provincia raggiungibile entro `max_years` anni da un agente di `faction_id`, con le
## stesse tappe di `plan` (a piedi una provincia confinante, oppure un trasporto via mare): regione -> anni (la partenza vale 0).
## `sea_cache` (facoltativo, da riusare per la stessa fazione e lo stesso stato) ricorda i gruppi di zone di mare (`sea_groups`,
## chiave `TABLE_KEY`, calcolati una volta sola). Le province escluse da `sea_destinations_from` (la partenza e le sue confinanti
## di terra) si raggiungono comunque entro lo stesso anno a piedi: gli anni sono gli stessi. Serve all'IA (ADR-053) per valutare in una volta tutti gli obiettivi lontani di un agente.
static func years_from(state: GameState, faction_id: String, from_id: String, max_years: int, sea_cache: Dictionary = {}) -> Dictionary:
	var key := SimUtil.norm(faction_id)
	var start := state.campaign.region(SimUtil.norm(from_id))
	var out := {}
	if start == null or start.is_sea:
		return out
	out[start.id] = 0
	var used_groups := {}
	if not sea_cache.has(LAND_KEY):
		var land := {}
		for r in state.campaign.regions:
			if r.is_sea:
				continue
			var near := PackedStringArray()
			for n in r.neighbours:
				var other := state.campaign.region(n)
				if other != null and not other.is_sea:
					near.append(other.id)
			land[r.id] = near
		sea_cache[LAND_KEY] = land
	var land_map: Dictionary = sea_cache[LAND_KEY]
	var frontier: Array[String] = [start.id]
	for year in range(1, maxi(0, max_years) + 1):
		var next_frontier: Array[String] = []
		for current in frontier:
			for next_id in land_map.get(current, PackedStringArray()):
				if out.has(next_id):
					continue
				out[next_id] = year
				next_frontier.append(next_id)
			if not sea_cache.has(TABLE_KEY):
				sea_cache[TABLE_KEY] = sea_groups(state, key)
			var groups: Dictionary = sea_cache[TABLE_KEY]
			var port_groups: Dictionary = groups["porti"]
			if not port_groups.has(current):
				continue
			var coasts: Array = groups["coste"]
			for g in port_groups[current]:
				if used_groups.has(g):
					continue   # le coste di un gruppo di zone si raggiungono tutte nello stesso anno: basta la prima volta
				used_groups[g] = true
				for land_id in coasts[int(g)]:
					if out.has(land_id):
						continue
					out[land_id] = year
					next_frontier.append(land_id)
		if next_frontier.is_empty():
			break
		frontier = next_frontier
	return out


## Anni che servono all'agente per arrivare a `to_id` dalla sua posizione (0 se c'e' gia', -1 se non ci arriva).
static func years_to(state: GameState, agent: AgentState, to_id: String) -> int:
	if agent == null:
		return -1
	if agent.region == SimUtil.norm(to_id):
		return 0
	var legs := plan(state, agent.faction, agent.region, to_id)
	return legs.size() if not legs.is_empty() else -1


## Imposta la tappa di quest'anno verso la destinazione dell'agente. Vero se c'e' una tappa; falso se e' gia' arrivato
## (la destinazione si azzera) o se non c'e' piu' un percorso (la destinazione resta: decide chi chiama).
static func set_next_leg(state: GameState, agent: AgentState) -> bool:
	if agent.destination == "" or agent.destination == agent.region:
		agent.destination = ""
		return false
	var legs := plan(state, agent.faction, agent.region, agent.destination)
	if legs.is_empty():
		return false
	agent.path = PackedStringArray([str(legs[0]["regione"])])
	agent.sea_route = legs[0]["catena"]
	return true


## Gruppi di zone di mare aperte per gli agenti di `faction_id` (stessa mappa delle zone, stessa zona aperta e stessa condizione
## d'imbarco di `GameCommands.sea_destinations_from(..., troops = false)`): {"porti": provincia d'imbarco -> Array dei gruppi che
## toccano le sue zone, "coste": per ogni gruppo le province di terra che confinano con le sue zone}. Da un porto si raggiunge via
## mare ogni provincia costiera dei suoi gruppi.
static func sea_groups(state: GameState, faction_id: String) -> Dictionary:
	var key := SimUtil.norm(faction_id)
	var status := GameCommands.sea_status(state, key, false)
	var need_fleet := GameCommands._needs_fleet(state, false)
	var coasts: Array[PackedStringArray] = []
	var maps: Array[Dictionary] = [_group_zones(state, status, need_fleet, coasts)]
	if not need_fleet and GameCommands.map_has_oceans(state):
		# ADR-081: gli oceani si attraversano solo con una rotta tutta di flotte proprie: gruppi a parte
		maps.append(_group_zones(state, status, true, coasts))
	var ports := {}
	for region in state.campaign.regions:
		if region.is_sea or GameCommands.embark_problem(state, key, region.id, false) != "":
			continue
		var groups: Array[int] = []
		for group_of in maps:
			for n in region.neighbours:
				if group_of.has(n) and not groups.has(int(group_of[n])):
					groups.append(int(group_of[n]))
		if not groups.is_empty():
			ports[region.id] = groups
	return {"porti": ports, "coste": coasts}


## Gruppi di zone di mare aperte con la stessa regola (`GameCommands._zone_open` con `need_fleet`): zona -> indice del gruppo in
## `coasts`, a cui si aggiungono le province di terra che confinano con ogni gruppo nuovo.
static func _group_zones(state: GameState, status: Dictionary, need_fleet: bool, coasts: Array[PackedStringArray]) -> Dictionary:
	var group_of := {}
	for region in state.campaign.regions:
		if not region.is_sea or group_of.has(region.id) or not GameCommands._zone_open(state, status, region.id, need_fleet):
			continue
		var g := coasts.size()
		var coast := PackedStringArray()
		var seen_land := {}
		var queue: Array[String] = [region.id]
		group_of[region.id] = g
		var head := 0
		while head < queue.size():
			var zone := state.campaign.region(queue[head])
			head += 1
			for n in zone.neighbours:
				var other := state.campaign.region(n)
				if other == null:
					continue
				if other.is_sea:
					if not group_of.has(other.id) and GameCommands._zone_open(state, status, other.id, need_fleet):
						group_of[other.id] = g
						queue.append(other.id)
				elif not seen_land.has(other.id):
					seen_land[other.id] = true
					coast.append(other.id)
		coasts.append(coast)
	return group_of


## Destinazioni via mare di un agente di `faction_id` da ogni provincia di terra: regione -> PackedStringArray, stesso insieme
## di `GameCommands.sea_destinations_from(..., troops = false)` (non lo stesso ordine), calcolato in un solo passaggio dai
## gruppi di `sea_groups`.
static func sea_table(state: GameState, faction_id: String) -> Dictionary:
	var out := {}
	var groups := sea_groups(state, faction_id)
	var coasts: Array = groups["coste"]
	var ports: Dictionary = groups["porti"]
	for region_id in ports:
		var region := state.campaign.region(str(region_id))
		var dest := PackedStringArray()
		var added := {}
		for g in ports[region_id]:
			for land_id in coasts[int(g)]:
				if land_id == region.id or added.has(land_id) or region.neighbours.has(land_id):
					continue
				added[land_id] = true
				dest.append(land_id)
		out[region.id] = dest
	return out
