class_name GameSetup
extends RefCounted
## Crea una partita nuova dai dati statici (startpos, tabella unita', tabella edifici).


## Partita all'anno di inizio della campagna.
## - tesoro = primo valore di SetTreasury (gli altri sono per le difficolta' superiori);
## - edifici dai MakeBuilding (`Castle15`, `SHIPYARD1`... -> famiglia + livello);
## - eserciti dalle MakeUnit militari: una regione forma eserciti del proprietario con al
##   massimo `rules.max_stacks` pile ciascuno; le navi formano una flotta nella prima zona
##   di mare confinante (PROVVISORIA, catalogo r.89: il gioco usa probabilmente
##   l'orientamento del porto); emissari e principesse diventano agenti con anno di nascita.
## Le anomalie dei dati (token o unita' sconosciute) finiscono in `state.setup_errors`.
## - personaggi (fase 4a): vedi `create_characters`; `heroes` (nomi, re ed eroi famosi) e' facoltativo.
## - religione delle province (fase 5b): composizione e zelo iniziali (`ReligionProcessor.init_religions`, PROVVISORIA);
## - lealta' delle province (fase 4b): ogni provincia parte dal suo obiettivo (`ProvinceProcessor.init_loyalty`, PROVVISORIA),
##   calcolato dopo la religione perche' la penalita' di religione dipende dalla composizione.
static func new_game(campaign: CampaignData, units: UnitProdLoader.UnitTable, buildings: BuildingProdLoader.BuildingTable, rules: Rules, seed_value: int, heroes: HeroesData = null) -> GameState:
	var state := GameState.new(campaign, units, buildings, rules)
	state.year = campaign.start_year
	state.final_year = rules.final_year
	state.era = state.era_for_year(state.year)
	state.seed_value = seed_value
	state.rng.seed = seed_value
	for f in campaign.factions:
		var start_treasury := 0
		if not f.treasury.is_empty():
			start_treasury = f.treasury[0]
		start_treasury = rules.traits.start_treasury(f.id, start_treasury)   # ADR-089: tratti della fazione
		state.add_faction(FactionState.new(f.id, start_treasury, f.is_active()))
	for r in campaign.land_regions():
		var p := ProvinceState.new(r.id, r.owner)
		p.tax_level = rules.default_tax
		for token in r.buildings:
			var lv := buildings.resolve(token)
			if lv == null:
				state.setup_errors.append("Edificio sconosciuto %s in %s" % [token, r.id])
			else:
				p.set_level(lv.family, maxi(p.level_of(lv.family), lv.level))
		state.add_province(p)
	_create_forces(state)
	add_trait_forces(state)   # ADR-089: truppe e navi in piu' dei tratti delle fazioni
	create_characters(state, heroes)
	AurorUnits.setup_king_army(state)     # ADR-074: Darkos parte in un'armata completa di unita' esclusive
	AurorUnits.ensure_king_guard(state)   # ADR-074: e ha sempre i Corazzieri del Drago
	ReligionProcessor.init_religions(state)
	ProvinceProcessor.init_loyalty(state)
	return state


## Crea i personaggi di una partita (nuova, oppure caricata da un salvataggio senza personaggi: v1 e v2).
## Solo le fazioni vive con `SetStartLeader` hanno una dinastia (i mondi di prova senza quel comando non
## hanno personaggi). Per ciascuna, in ordine di dichiarazione: il capo (`CharacterFactory.make_start_leader`),
## che comanda il primo esercito di terra nella regione di `PlaceLeader`; i membri di `AddHeir` (il maschio piu'
## anziano e' l'erede designato, i maschi maggiorenni gli altri sono principi, i minorenni restano eredi finche'
## non diventano maggiorenni); poi un generale per ogni esercito rimasto senza comandante, i titoli e le cariche
## iniziali. Gli eroi famosi gia' disponibili all'anno dello stato non vengono creati (sono segnati come fatti,
## PROVVISORIA); gli altri compaiono negli anni seguenti. Usa un generatore dedicato (seme + 7919): il
## generatore dello stato non viene toccato, cosi' le sequenze dei test non cambiano.
static func create_characters(state: GameState, heroes: HeroesData = null) -> void:
	if heroes != null:
		state.heroes = heroes
	if state.heroes != null:
		for h in state.heroes.heroes:
			if h.year <= state.year:
				state.heroes_done[DynastyProcessor.hero_key(h)] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = state.seed_value + 7919
	var any := false
	for cf in state.campaign.factions:
		var fs := state.faction(cf.id)
		if fs == null or not fs.alive or not cf.is_active() or not cf.has_leader_data():
			continue
		_create_dynasty(state, cf, rng)
		any = true
	if any:
		DynastyProcessor.ensure_commanders(state, rng, state.year)
		DynastyProcessor.assign_initial_titles(state, state.year)
		link_start_princesses(state)
	AgentProcessor.name_agents(state)
	for a in state.armies:
		if a.is_fleet and not a.admiral.is_empty():
			a.admiral["nome"] = Admirals.admiral_name(state, a)   # ora ci sono le liste dei nomi della campagna
	Admirals.ensure(state)
	AgentProcessor.apply_faction_minimum(state)   # agenti degli Auror al massimo (auror.cfg agenti_al_massimo)


## Fase 5a: le principesse dello startpos (agenti PRINCESS senza personaggio) di una fazione con dinastia diventano
## anche personaggi con ruolo `principessa` e anno di nascita della MakeUnit, collegati all'agente (il loro valore
## e' l'acume). Attributi e nome come i figli del capo (`CharacterFactory.make_child`), con un generatore proprio
## (seme + 104729): il generatore dello stato non viene toccato. Idempotente: non tocca le principesse gia' collegate;
## serve anche ai salvataggi precedenti alla versione 5.
static func link_start_princesses(state: GameState) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = state.seed_value + 104729
	for a in state.agents:
		if a.type_name != AgentState.PRINCESS or a.character_id != 0:
			continue
		var f := state.faction(a.faction)
		var leader := state.leader_of(a.faction)
		if f == null or not f.alive or leader == null or DynastyProcessor.is_elective(state, f.id):
			continue
		var c := CharacterFactory.make_child(state, leader, false, a.birth_year, a.region, rng)
		a.character_id = c.id
		a.name = c.full_name()
		a.valour = clampi(c.effective(Character.ATTR_ACUMEN, state.rules, state.campaign), 0, state.rules.agents.max_valour)


static func _create_dynasty(state: GameState, cf: CampaignData.Faction, rng: RandomNumberGenerator) -> void:
	var d := state.rules.dynasty
	var region_id := cf.leader_region
	var own := state.province(region_id)
	if own == null or own.owner != cf.id:
		var owned := state.provinces_of(cf.id)
		region_id = ""
		if not owned.is_empty():
			region_id = owned[0].id
	var leader := CharacterFactory.make_start_leader(state, cf, region_id, state.year, rng)
	for a in state.armies_of(cf.id):
		if not a.is_fleet and a.region == region_id and state.commander_of(a.id) == null:
			leader.army = a.id
			break
	var oldest: Character = null
	var members: Array[Character] = []
	var entries: Array = [] if DynastyProcessor.is_elective(state, cf.id) else cf.heir_entries()   # il Papa non ha figli (ADR-072)
	for entry in entries:
		var male := bool(entry["male"])
		var child := CharacterFactory.make_child(state, leader, male, state.year - int(entry["age"]), region_id, rng)
		members.append(child)
		if male and (oldest == null or child.birth_year < oldest.birth_year):
			oldest = child
	for m in members:
		if m.male and m != oldest and m.age(state.year) >= d.prince_age:
			m.role = Character.ROLE_PRINCE


static func _create_forces(state: GameState) -> void:
	var campaign := state.campaign
	var by_region := {}
	for su in campaign.start_units:
		if not by_region.has(su.region):
			by_region[su.region] = []
		var list: Array = by_region[su.region]
		list.append(su)
	for sea in campaign.sea_regions():
		if by_region.has(sea.id):
			state.setup_errors.append("Unita' iniziali in una zona di mare (%s): ignorate" % sea.id)
	for region in campaign.land_regions():
		if not by_region.has(region.id):
			continue
		var troops: Array[UnitStack] = []
		var ships: Array[UnitStack] = []
		var entries: Array = by_region[region.id]
		for item in entries:
			var su: CampaignData.StartUnit = item
			var ut: UnitType = state.units.get_unit(su.unit_type)
			if ut == null:
				state.setup_errors.append("Unita' sconosciuta %s in %s (riga %d)" % [su.unit_type, region.id, su.line])
			elif ut.is_ship():
				ships.append(state.new_stack(region.owner, ut.id, su.amount))
			elif ut.is_military():
				troops.append(state.new_stack(region.owner, ut.id, su.amount))
			elif ut.is_mount():
				state.setup_errors.append("Cavalcatura %s in %s: ignorata" % [ut.id, region.id])
			else:
				var agent := state.create_agent(region.owner, region.id, ut.id, ut.type_name, su.amount)
				agent.valour = clampi(state.rules.agents.start_valour, 0, state.rules.agents.max_valour)
		_fill_armies(state, region.owner, region.id, troops, false)
		if not ships.is_empty():
			var sea_id := first_sea_neighbour(campaign, region)
			if sea_id == "":
				state.setup_errors.append("Navi in %s senza zona di mare confinante: ignorate" % region.id)
			else:
				_fill_armies(state, region.owner, sea_id, ships, true)


## Tratti delle fazioni (ADR-089): `truppe_iniziali` pile di terra in piu' nella capitale, copie delle unita' iniziali
## piu' forti della fazione (senza l'unita' del capo), e `navi_iniziali` navi in piu' nella zona di mare vicina alla
## capitale (o a un'altra provincia costiera), copie delle sue navi o, se non ne ha, della nave piu' economica che puo'
## costruire nell'epoca di partenza.
static func add_trait_forces(state: GameState) -> void:
	var traits := state.rules.traits
	if traits.table.is_empty():
		return
	for cf in state.campaign.factions:
		if not cf.is_active():
			continue
		var troops := traits.int_value(cf.id, "truppe_iniziali")
		var ships := traits.int_value(cf.id, "navi_iniziali")
		if troops <= 0 and ships <= 0:
			continue
		var owned := state.campaign.regions_owned_by(cf.id)
		if owned.is_empty():
			continue
		var capital := owned[0].id
		for r in owned:
			if r.id == cf.leader_region:
				capital = r.id
		if troops > 0:
			_add_extra_troops(state, cf.id, capital, troops)
		if ships > 0:
			_add_extra_ships(state, cf.id, capital, owned, ships)


static func _add_extra_troops(state: GameState, faction_id: String, capital: String, count: int) -> void:
	var models: Array[UnitStack] = []
	for a in state.armies_of(faction_id):
		if a.is_fleet:
			continue
		for s in a.stacks:
			var u: UnitType = state.units.get_unit(s.unit_id)
			if u != null and u.is_military() and not u.is_ship() and not u.leader_of.has(faction_id):
				models.append(s)
	if models.is_empty():
		return
	models.sort_custom(func(x: UnitStack, y: UnitStack) -> bool:
		var sx := Combat.stack_strength(state, x)
		var sy := Combat.stack_strength(state, y)
		return sx > sy if sx != sy else x.unit_id < y.unit_id)
	var added: Array[UnitStack] = []
	for i in count:
		var m := models[i % models.size()]
		var u: UnitType = state.units.get_unit(m.unit_id)
		added.append(state.new_stack(faction_id, m.unit_id, u.men if u.men > 0 else m.men))
	_place_stacks(state, faction_id, capital, added, false)


static func _add_extra_ships(state: GameState, faction_id: String, capital: String, owned: Array[CampaignData.Region], count: int) -> void:
	var zone := ""
	var cap_region := state.campaign.region(capital)
	if cap_region != null:
		zone = first_sea_neighbour(state.campaign, cap_region)
	if zone == "":
		for r in owned:
			if r.has_port:
				zone = first_sea_neighbour(state.campaign, r)
				if zone != "":
					break
	if zone == "":
		return
	var model := ""
	for a in state.armies_of(faction_id):
		if a.is_fleet and not a.stacks.is_empty():
			model = a.stacks[0].unit_id
			break
	if model == "":
		var best: UnitType = null
		for u in state.units.units:
			if u.is_ship() and u.allows_faction(faction_id) and u.available_in_period(state.era) and (best == null or u.cost < best.cost):
				best = u
		if best == null:
			return
		model = best.id
	var ut: UnitType = state.units.get_unit(model)
	var added: Array[UnitStack] = []
	for i in count:
		added.append(state.new_stack(faction_id, model, ut.men if ut != null and ut.men > 0 else 1))
	_place_stacks(state, faction_id, zone, added, true)


## Aggiunge le pile a un esercito (o flotta) della fazione nella regione con posto libero, altrimenti a eserciti nuovi.
static func _place_stacks(state: GameState, faction_id: String, region_id: String, stacks: Array[UnitStack], fleet: bool) -> void:
	var limit := maxi(1, state.rules.max_stacks)
	var rest: Array[UnitStack] = []
	for st in stacks:
		var placed := false
		for a in state.armies_in(region_id):
			if a.faction == faction_id and a.is_fleet == fleet and a.stacks.size() < limit:
				a.stacks.append(st)
				placed = true
				break
		if not placed:
			rest.append(st)
	if not rest.is_empty():
		_fill_armies(state, faction_id, region_id, rest, fleet)


## Prima zona di mare tra i vicini della regione, "" se non ce ne sono.
static func first_sea_neighbour(campaign: CampaignData, region: CampaignData.Region) -> String:
	for n in region.neighbours:
		var other := campaign.region(n)
		if other != null and other.is_sea:
			return other.id
	return ""


## Distribuisce le pile in uno o piu' eserciti da al massimo `max_stacks` pile.
static func _fill_armies(state: GameState, owner_id: String, region_id: String, stacks: Array[UnitStack], fleet: bool) -> void:
	var limit := maxi(1, state.rules.max_stacks)
	var i := 0
	while i < stacks.size():
		var a := state.create_army(owner_id, region_id, fleet)
		var last := mini(i + limit, stacks.size())
		for j in range(i, last):
			a.stacks.append(stacks[j])
		i = last
