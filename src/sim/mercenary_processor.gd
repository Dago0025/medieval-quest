class_name MercenaryProcessor
extends RefCounted
## Mercenari (fase 8d): ogni fine anno le compagnie invecchiano e si sciolgono dopo `durata_massima` anni, alcune passano a
## una provincia confinante e ne compaiono di nuove dove il richiamo e' maggiore (locande, taverne, centri «hub»). Si
## assoldano subito con GameCommands.hire_mercenary. Regole in data/regole/mercenari.cfg (tutte PROVVISORIE).
## Sorteggi con state.rng, in ordine fisso: province in ordine di id, compagnie nell'ordine dell'elenco.


static func process_year(state: GameState) -> void:
	var r := state.rules.mercenaries
	_age_and_move(state, r)
	_spawn(state, r)


## Richiamo della provincia: base + magnetismo degli edifici + hub.
static func pull(state: GameState, province_id: String) -> int:
	var r := state.rules.mercenaries
	var p := state.province(province_id)
	if p == null:
		return 0
	var total := r.base_pull
	var hub := false
	for fam_id in p.buildings.keys():
		var fam: BuildingType = state.buildings.get_family(str(fam_id)) if state.buildings != null else null
		if fam == null:
			continue
		var lv := fam.get_level(maxi(1, p.level_of(str(fam_id))))
		if lv != null:
			total += maxi(0, lv.mercenary_magnetism)
		if fam.mercenary_hub:
			hub = true
	if hub:
		total += r.hub_pull
	return total


## Unita' che possono comparire tra i mercenari nella provincia: colonna 49 = YES, truppe di terra, epoca in corso,
## regione e cultura ammesse (nessun vincolo di fazione: i mercenari servono chi paga).
static func candidates(state: GameState, province_id: String) -> Array[UnitType]:
	var out: Array[UnitType] = []
	var region: CampaignData.Region = state.campaign.region(province_id)
	if region == null or region.is_sea or state.units == null:
		return out
	for u in state.units.military():
		if not u.mercenary or u.is_ship() or not u.available_in_period(state.era):
			continue
		if not u.allows_region(region.id) or not u.allows_culture(GameCommands.culture_key(region.culture)):
			continue
		if state.rules.mercenaries.local_only(region.id) and not u.regions.has(region.id):
			continue   # ADR-116: lontano dall'Europa solo i mercenari del posto (ronin, wako, tuareg...)
		if not HistoricalLimits.unit_allowed(state, "", u, region.id):
			continue   # ADR-114: invenzioni e cavalli nelle Americhe
		out.append(u)
	return out


static func pool(state: GameState, province_id: String) -> Array:
	if not state.mercenaries.has(province_id):
		state.mercenaries[province_id] = []
	return state.mercenaries[province_id]


## Truppe congedate (GameCommands.disband_stacks, ADR-031; manuale p26 e p70): le pile di terra diventano compagnie di
## mercenari nella provincia `region_id`, con gli uomini e il valore che avevano, anche oltre `max_per_provincia` (non
## spariscono: semmai e' la comparsa di compagnie nuove a fermarsi). Nessun sorteggio. Restituisce le compagnie nate.
static func add_disbanded(state: GameState, region_id: String, stacks: Array[UnitStack]) -> int:
	if not state.rules.mercenaries.disbanded_join or state.province(region_id) == null:
		return 0
	var region: CampaignData.Region = state.campaign.region(region_id)
	if region == null or region.is_sea:
		return 0
	var born := 0
	for st in stacks:
		if st.men <= 0 or st.unit_id == "":
			continue
		pool(state, region_id).append({"unita": st.unit_id, "uomini": st.men, "valore": st.value, "anni": 0})
		born += 1
	return born


static func _age_and_move(state: GameState, r: MercenaryRules) -> void:
	var ids: Array = state.mercenaries.keys()
	ids.sort()
	var moves: Array = []   # [da, compagnia]
	for pid in ids:
		var list: Array = state.mercenaries[pid]
		var keep: Array = []
		for c in list:
			var company: Dictionary = c
			company["anni"] = int(company.get("anni", 0)) + 1
			if int(company["anni"]) >= r.max_age:
				continue
			if state.rng.randf() < r.move_chance:
				moves.append([str(pid), company])
				continue
			keep.append(company)
		state.mercenaries[pid] = keep
	for m in moves:
		var target := _neighbour_by_pull(state, str(m[0]))
		var dest := target if target != "" and pool(state, target).size() < r.max_per_province else str(m[0])
		pool(state, dest).append(m[1])
	for pid in state.mercenaries.keys():
		if (state.mercenaries[pid] as Array).is_empty():
			state.mercenaries.erase(pid)


static func _neighbour_by_pull(state: GameState, province_id: String) -> String:
	var options: Array[String] = []
	var weights: Array[int] = []
	var region: CampaignData.Region = state.campaign.region(province_id)
	if region == null:
		return ""
	var neighbours: Array = Array(region.neighbours)
	neighbours.sort()
	for n in neighbours:
		var nid := str(n)
		var nr: CampaignData.Region = state.campaign.region(nid)
		if nr == null or nr.is_sea:
			continue
		options.append(nid)
		weights.append(maxi(1, pull(state, nid)))
	return _weighted(state, options, weights)


static func _spawn(state: GameState, r: MercenaryRules) -> void:
	var options: Array[String] = []
	var weights: Array[int] = []
	var land: Array = []
	for region in state.campaign.land_regions():
		land.append(region.id)
	land.sort()
	for pid in land:
		if state.province(str(pid)) == null:
			continue
		options.append(str(pid))
		weights.append(maxi(0, pull(state, str(pid))))
	for i in r.new_per_year:
		var pid := _weighted(state, options, weights)
		if pid == "" or pool(state, pid).size() >= r.max_per_province:
			continue
		var units := candidates(state, pid)
		if units.is_empty():
			continue
		var u: UnitType = units[state.rng.randi_range(0, units.size() - 1)]
		pool(state, pid).append({"unita": u.id, "uomini": u.men, "valore": 0, "anni": 0})
	for pid in state.mercenaries.keys():
		if (state.mercenaries[pid] as Array).is_empty():
			state.mercenaries.erase(pid)


static func _weighted(state: GameState, options: Array[String], weights: Array[int]) -> String:
	var total := 0
	for w in weights:
		total += w
	if total <= 0 or options.is_empty():
		return ""
	var roll := state.rng.randi_range(1, total)
	for i in options.size():
		roll -= weights[i]
		if roll <= 0:
			return options[i]
	return options[options.size() - 1]
