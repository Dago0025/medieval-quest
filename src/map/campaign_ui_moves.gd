class_name CampaignUiMoves
extends RefCounted
## Movimento fluido delle pedine (richiesta di Federico del 2026-11-10), funzioni pure sullo stato per l'interfaccia:
## - niente frecce: la pedina con un ordine di movimento si disegna gia' nella regione dove sara' a fine anno; nella
##   simulazione resta dov'e' finche' l'anno non finisce (come nell'originale), quindi non e' un bersaglio per le altre
##   pedine e si ridispone o interagisce solo dall'anno dopo;
## - regioni raggiungibili: mentre si trascina una pedina le regioni dove puo' andare quest'anno hanno un fondo diverso
##   (confinanti, via mare con le flotte proprie, zone di mare entro il raggio delle navi), rosse se e' un attacco.
## Le regole restano quelle dei comandi (GameCommands.order_move, fleet_path, sea_destinations, order_agent_move).

const REACH_NONE := 0
const REACH_MOVE := 1     ## confinante (o zona di mare entro il raggio): movimento
const REACH_SEA := 2      ## provincia raggiungibile con un trasporto via mare
const REACH_ATTACK := 3   ## movimento che diventa un attacco (regione o forze di altri)
const REACH_ORIGIN := 4   ## regione di partenza (lasciare qui = riordino o annullamento)


## Regione in cui si disegna l'esercito: con un ordine di movimento quella in cui sara' a fine anno (il primo passo, o per
## una flotta il passo del suo raggio annuale), altrimenti quella in cui si trova.
static func army_shown_region(state: GameState, army: Army) -> String:
	if army == null:
		return ""
	if army.path.is_empty():
		return army.region
	var steps := Combat.fleet_range(state, army) if army.is_fleet else 1
	return army.path[clampi(steps, 1, army.path.size()) - 1]


## Regione in cui si disegna l'agente (il primo passo del percorso, o quella in cui si trova).
static func agent_shown_region(agent: AgentState) -> String:
	if agent == null:
		return ""
	return agent.region if agent.path.is_empty() else agent.path[0]


## Vero se la pedina e' in viaggio quest'anno: disegnata altrove, non e' un bersaglio per le altre pedine.
static func army_in_transit(army: Army) -> bool:
	return army != null and not army.path.is_empty()


static func agent_in_transit(agent: AgentState) -> bool:
	return agent != null and not agent.path.is_empty()


## Id della regione disegnata per ogni esercito con un ordine (id -> regione), per MarkerLayout.group_by_region.
static func shown_army_regions(state: GameState, armies: Array[Army], player_id: String) -> Dictionary:
	var out := {}
	for a in armies:
		if a.faction == player_id and not a.path.is_empty():
			out[a.id] = army_shown_region(state, a)
	return out


static func shown_agent_regions(agents: Array[AgentState], player_id: String) -> Dictionary:
	var out := {}
	for a in agents:
		if a.faction == player_id and not a.path.is_empty():
			out[a.id] = agent_shown_region(a)
	return out


## Regioni dove l'esercito puo' arrivare quest'anno: id regione -> REACH_*. Truppe: le province confinanti e quelle
## raggiungibili via mare (GameCommands.sea_destinations); flotte: le zone di mare entro il raggio annuale. Nulla per la
## guarnigione di un castello assediato. La partenza e' REACH_ORIGIN.
static func army_reach(state: GameState, army: Army) -> Dictionary:
	var out := {}
	if army == null:
		return out
	out[army.region] = REACH_ORIGIN
	if army.in_castle and state.is_besieged(army.region):
		return out
	var here := state.campaign.region(army.region)
	if here == null:
		return out
	if army.is_fleet:
		for zone_id in fleet_zones(state, army):
			out[zone_id] = REACH_ATTACK if CampaignUiText.attack_target(state, army, zone_id) else REACH_MOVE
		return out
	for n in here.neighbours:
		var next := state.campaign.region(n)
		if next == null or next.is_sea:
			continue
		out[next.id] = REACH_ATTACK if CampaignUiText.attack_target(state, army, next.id) else REACH_MOVE
	for land_id in GameCommands.sea_destinations(state, army.faction, army.id):
		if not out.has(land_id):
			out[land_id] = REACH_ATTACK if CampaignUiText.attack_target(state, army, land_id) else REACH_SEA
	return out


## Zone di mare che la flotta raggiunge quest'anno: entro `Combat.fleet_range` passi tra zone confinanti, in ordine di
## distanza (ricerca in ampiezza, ordine di SetNeighbours). Esclusa la zona di partenza.
static func fleet_zones(state: GameState, army: Army) -> PackedStringArray:
	var out := PackedStringArray()
	if army == null or not army.is_fleet:
		return out
	var limit := Combat.fleet_range(state, army)
	var dist := {army.region: 0}
	var queue: Array[String] = [army.region]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		var d := int(dist[current])
		if d >= limit:
			continue
		var region := state.campaign.region(current)
		if region == null:
			continue
		for n in region.neighbours:
			var next := state.campaign.region(n)
			if next == null or not next.is_sea or dist.has(next.id):
				continue
			if not Combat.can_enter(state, army, next.id):
				continue   # zona troppo lontana dalla costa per le navi della flotta
			dist[next.id] = d + 1
			queue.append(next.id)
			out.append(next.id)
	return out


## Regioni dove l'agente puo' arrivare quest'anno: le province confinanti e quelle raggiungibili via mare con le flotte
## della sua fazione (gli agenti entrano ovunque senza dichiarare guerra; il blocco navale delle flotte neutrali non li ferma). Nulla se aspetta la risposta a una proposta.
static func agent_reach(state: GameState, agent: AgentState) -> Dictionary:
	var out := {}
	if agent == null:
		return out
	out[agent.region] = REACH_ORIGIN
	if not state.proposal_of_agent(agent.id).is_empty():
		return out
	var here := state.campaign.region(agent.region)
	if here == null:
		return out
	for n in here.neighbours:
		var next := state.campaign.region(n)
		if next != null and not next.is_sea:
			out[next.id] = REACH_MOVE
	for land_id in GameCommands.sea_destinations_from(state, agent.faction, agent.region, false):
		if not out.has(land_id):
			out[land_id] = REACH_SEA
	return out
