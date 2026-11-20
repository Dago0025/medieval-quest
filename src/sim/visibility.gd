class_name Visibility
extends RefCounted
## Nebbia di guerra (richiesta di Federico, 2026-11-09). Manuale p11, minimappa: «Le zone che possiedi, quelle in cui hai un
## agente e quelle che puoi vedere da una provincia adiacente sono evidenziate con il colore della fazione»; p39: senza una spia
## non si vedono gli assassini altrui (regola gia' in CampaignUiAgents). Qui: visibili le province proprie, le regioni (terra o
## mare) dove la fazione ha un esercito, una flotta o un agente, e tutte le regioni confinanti con queste. Fuori vista non si
## vedono eserciti, flotte e agenti altrui; castelli e porti, strutture fisse della mappa, restano visibili come nell'originale.
## Gli alleati non condividono la vista (il manuale non lo dice: PROVVISORIA). Solo calcolo, nessuno stato.


## Regioni visibili alla fazione: id regione -> true.
static func visible_regions(state: GameState, faction_id: String) -> Dictionary:
	var key := SimUtil.norm(faction_id)
	var seen := {}
	var sources := {}
	for p in state.provinces:
		if p.owner == key:
			sources[p.id] = true
	for a in state.armies:
		if a.faction == key and not a.stacks.is_empty():
			sources[a.region] = true
	for ag in state.agents:
		if ag.faction == key:
			sources[ag.region] = true
	for region_id in sources:
		seen[region_id] = true
		var region := state.campaign.region(str(region_id))
		if region == null:
			continue
		for n in region.neighbours:
			seen[n] = true
	return seen


## Vero se la fazione vede la regione.
static func sees(state: GameState, faction_id: String, region_id: String) -> bool:
	return visible_regions(state, faction_id).has(SimUtil.norm(region_id))
