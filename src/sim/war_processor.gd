class_name WarProcessor
extends RefCounted
## Guerra del fine anno (spec. fase 3 §1 e §3): battaglie in campo e scontri navali, ritirate,
## assedi, conquiste e fazioni distrutte. `TurnProcessor.end_year` la chiama dopo il movimento.
##
## Ordine fisso: regioni nell'ordine di dichiarazione, fazioni nell'ordine di dichiarazione,
## eserciti in ordine di id. Ogni estrazione casuale passa da `Combat` e da `state.rng`.
##
## Regole non documentate, tutte PROVVISORIE (catalogo r.88, r.101-r.108):
## - una ritirata verso una provincia confinante propria o verso la regione di partenza e'
##   possibile solo se li' non ci sono eserciti di una fazione in guerra con chi si ritira;
## - la ritirata al punto di partenza vale per ogni esercito che si e' mosso almeno una volta
##   (non solo per chi e' arrivato quest'anno), cosi' chi assedia e perde contro un esercito di
##   soccorso torna indietro invece di essere catturato;
## - un esercito entra nel castello per intero o per niente (peso: cavalleria doppia, max 16);
## - le flotte sconfitte tornano da dove sono venute o vanno nel primo mare confinante libero
##   (il manuale non descrive le ritirate navali); senza vie sono affondate (catturate);
## - ADR-073: chi perde e si ritira lascia prigioniera una quota dei sopravvissuti; chi e' catturato per intero, la
##   guarnigione espugnata o affamata e il comandante di un esercito annientato diventano prigionieri (PrisonerProcessor);
## - un assedio appena iniziato non conta il primo anno: la fame comincia dal fine anno seguente;
## - una guarnigione che cede per fame o perde un assalto o una sortita sparisce (nessun riscatto
##   prima della fase 5).


# --- guerra e movimento ---------------------------------------------------------------------


## Fazioni che una fazione attacca entrando in `region_id`: il proprietario della provincia (se
## altrui) e le fazioni con eserciti (flotte, per una flotta) gia' presenti. In ordine di scoperta.
## Fase 5a: gli eserciti (e le flotte) alleati gia' presenti non sono ostili (si sta nella stessa regione senza
## combattere); entrare in una provincia di un alleato o di chi ha una tregua con noi resta un attacco (nessun
## diritto di passaggio: PROVVISORIA) e rompe il trattato (`DiplomacyProcessor.break_for_attack`).
## In mare (segnalazione di Federico, 2026-11-13) le flotte di chi non e' in guerra con noi convivono nella stessa zona,
## come nell'originale: sono ostili solo le flotte delle fazioni in guerra (ribelli compresi). Per attaccare una flotta
## neutrale la si sceglie come bersaglio (GameCommands.order_naval_attack, con la conferma dell'interfaccia).
static func hostile_factions(state: GameState, faction_id: String, fleet: bool, region_id: String) -> Array[String]:
	var key := SimUtil.norm(faction_id)
	var out: Array[String] = []
	var region := state.campaign.region(region_id)
	if region == null:
		return out
	if not region.is_sea:
		var province := state.province(region.id)
		if province != null and province.owner != "" and province.owner != key:
			out.append(province.owner)
	for a in state.armies_in(region.id):
		if a.faction != key and a.is_fleet == fleet and not a.stacks.is_empty() and not out.has(a.faction) and not state.is_allied(key, a.faction):
			if region.is_sea and not state.at_war(key, a.faction):
				continue
			out.append(a.faction)
	return out


# --- battaglie in campo ------------------------------------------------------------------


## Battaglie in campo e scontri navali di tutte le regioni, nell'ordine di dichiarazione delle regioni.
static func field_battles(state: GameState) -> void:
	var contested := _contested_regions(state)
	if contested.is_empty():
		return
	for region in state.campaign.regions:
		if contested.has(region.id):
			_region_battles(state, region)


## Regioni in cui stanno (fuori dal castello) eserciti di almeno due fazioni in guerra tra loro.
static func _contested_regions(state: GameState) -> Dictionary:
	var seen := {}
	for a in state.armies:
		if a.in_castle or a.stacks.is_empty():
			continue
		if not seen.has(a.region):
			seen[a.region] = [] as Array[String]
		var list: Array = seen[a.region]
		if not list.has(a.faction):
			list.append(a.faction)
	var out := {}
	for region_id in seen:
		var factions: Array = seen[region_id]
		for i in factions.size():
			for j in range(i + 1, factions.size()):
				if state.at_war(str(factions[i]), str(factions[j])):
					out[region_id] = true
	return out


static func _region_battles(state: GameState, region: CampaignData.Region) -> void:
	var guard := 0
	while guard < 32:
		guard += 1
		var field := _field_armies(state, region.id)
		var pair := _first_war_pair(state, _factions_present(state, field))
		if pair.is_empty():
			return
		var armies_a := _armies_of_faction(field, pair[0])
		var armies_b := _armies_of_faction(field, pair[1])
		var attacker_id := _pick_attacker(state, region, pair[0], pair[1], armies_a, armies_b)
		var attackers := armies_a
		var defenders := armies_b
		if attacker_id == pair[1]:
			attackers = armies_b
			defenders = armies_a
		var kind := BattleResult.KIND_FIELD
		if region.is_sea:
			kind = BattleResult.KIND_NAVAL
		var multiplier := Combat.defender_multiplier(state, kind, 0)
		var result := Combat.resolve(state, region.id, attackers, defenders, kind, multiplier)
		var losers := defenders
		var winners := attackers
		if not result.attacker_won:
			losers = attackers
			winners = defenders
		for a in losers:
			if state.armies.has(a):
				_retreat(state, a, region, result)
			elif not a.is_fleet:
				PrisonerProcessor.capture_commander(state, a.id, a.faction, region.id, result.winner_faction(), PrisonerProcessor.captor_commander(state, result))
		_emit_battle(state, result, region.id, {})
		if kind == BattleResult.KIND_NAVAL:
			for p in Admirals.after_battle(state, winners, losers):
				var fleet := state.army(int(p["esercito"]))
				state.add_event(GameState.EV_ADMIRAL_PROMOTED, {"fazione": fleet.faction if fleet != null else "", "esercito": int(p["esercito"]),
					"regione": region.id, "nome": str(p["nome"]), "stelle": int(p["stelle"]),
					"testo": Lang.t("L'ammiraglio %s sale a %d stelle dopo la vittoria in %s.") % [str(p["nome"]), int(p["stelle"]), region_label(state, region.id)]})


## Eserciti (o flotte) della regione fuori dal castello, in ordine di id.
static func _field_armies(state: GameState, region_id: String) -> Array[Army]:
	var out: Array[Army] = []
	for a in state.armies:
		if a.region == region_id and not a.in_castle and not a.stacks.is_empty():
			out.append(a)
	return out


## Fazioni presenti, nell'ordine di dichiarazione delle fazioni.
static func _factions_present(state: GameState, armies: Array[Army]) -> Array[String]:
	var out: Array[String] = []
	for f in state.factions:
		for a in armies:
			if a.faction == f.id:
				out.append(f.id)
				break
	for a in armies:
		if not out.has(a.faction):
			out.append(a.faction)
	return out


## Prima coppia in guerra (nell'ordine delle fazioni), vuota se non ce ne sono.
static func _first_war_pair(state: GameState, present: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for i in present.size():
		for j in range(i + 1, present.size()):
			if state.at_war(present[i], present[j]):
				out.append(present[i])
				out.append(present[j])
				return out
	return out


static func _armies_of_faction(armies: Array[Army], faction_id: String) -> Array[Army]:
	var out: Array[Army] = []
	for a in armies:
		if a.faction == faction_id:
			out.append(a)
	return out


## Attaccante = chi e' entrato quest'anno nella regione. Se sono entrati entrambi o nessuno:
## il proprietario della provincia difende; altrimenti attacca la fazione prima nell'ordine.
static func _pick_attacker(state: GameState, region: CampaignData.Region, first: String, second: String, armies_first: Array[Army], armies_second: Array[Army]) -> String:
	var first_arrived := _any_arrived(state, armies_first)
	var second_arrived := _any_arrived(state, armies_second)
	if first_arrived and not second_arrived:
		return first
	if second_arrived and not first_arrived:
		return second
	if not region.is_sea:
		var province := state.province(region.id)
		if province != null:
			if province.owner == first:
				return second
			if province.owner == second:
				return first
	return first


static func _any_arrived(state: GameState, armies: Array[Army]) -> bool:
	for a in armies:
		if a.arrived_in(state.year):
			return true
	return false


# --- ritirate -------------------------------------------------------------------------------


## Ritirata di un esercito perdente (manuale p32, cinque casi in quest'ordine). Registra l'esito
## in `result.retreats` o `result.captures`; gli eventi li crea `_emit_battle`.
static func _retreat(state: GameState, army: Army, region: CampaignData.Region, result: BattleResult) -> void:
	if army.is_fleet:
		_retreat_fleet(state, army, region, result)
		return
	var province := state.province(region.id)
	# ADR-073: prima della ritirata una parte dei sopravvissuti resta prigioniera (manuale p56); chi poi non ha vie e' catturato tutto
	if _retreat_route(state, army, region) != "":
		var taken := PrisonerProcessor.take_share(state, army, region.id, result.winner_faction(), PrisonerProcessor.captor_commander(state, result))
		if taken > 0:
			result.captures.append({"esercito": army.id, "fazione": army.faction, "uomini": taken, "caso": "ritirata",
				"testo": Lang.t("%d uomini dell'esercito %d di %s sono fatti prigionieri a %s.") % [taken, army.id, SimUtil.faction_label(army.faction), region_label(state, region.id)]})
	# 1. difensore nella propria provincia con castello e posto in guarnigione
	if province != null and province.owner == army.faction and Combat.castle_level(state, region.id) > 0:
		if Combat.garrison_load(state, region.id) + Combat.garrison_weight(state, army, region.id) <= Combat.garrison_capacity(state, region.id):
			army.in_castle = true
			army.path = PackedStringArray()
			army.sea_route = PackedStringArray()
			army.assault_ordered = false
			_record_retreat(state, army, region.id, region.id, "castello", result)
			return
	# 2. una provincia confinante propria (la prima nell'ordine di SetNeighbours)
	for n in region.neighbours:
		var neighbour := state.campaign.region(n)
		if neighbour == null or neighbour.is_sea:
			continue
		var owned := state.province(neighbour.id)
		if owned != null and owned.owner == army.faction and not _hostile_present(state, neighbour.id, army.faction, false):
			_record_retreat(state, army, region.id, neighbour.id, "provincia_amica", result)
			return
	# 3. torna alla regione da cui e' partito; 4. arrivato dal mare: catturato; 5. nessuna via: catturato
	if army.from_region != "":
		var origin := state.campaign.region(army.from_region)
		if origin != null and origin.is_sea:
			_capture(state, army, region.id, "sbarco", result)
			return
		if origin != null and origin.id != region.id and not _hostile_present(state, origin.id, army.faction, false):
			_record_retreat(state, army, region.id, origin.id, "ritorno", result)
			return
	_capture(state, army, region.id, "nessuna_via", result)


## Dove si ritirerebbe l'esercito di terra sconfitto ("" = catturato): stesse regole e stesso ordine di `_retreat`.
static func _retreat_route(state: GameState, army: Army, region: CampaignData.Region) -> String:
	var province := state.province(region.id)
	if province != null and province.owner == army.faction and Combat.castle_level(state, region.id) > 0:
		if Combat.garrison_load(state, region.id) + Combat.garrison_weight(state, army, region.id) <= Combat.garrison_capacity(state, region.id):
			return region.id
	for n in region.neighbours:
		var neighbour := state.campaign.region(n)
		if neighbour == null or neighbour.is_sea:
			continue
		var owned := state.province(neighbour.id)
		if owned != null and owned.owner == army.faction and not _hostile_present(state, neighbour.id, army.faction, false):
			return neighbour.id
	if army.from_region != "":
		var origin := state.campaign.region(army.from_region)
		if origin != null and not origin.is_sea and origin.id != region.id and not _hostile_present(state, origin.id, army.faction, false):
			return origin.id
	return ""


## PROVVISORIA (catalogo r.108: ritirate navali non descritte): la flotta torna da dove e' venuta,
## altrimenti va nel primo mare confinante senza flotte nemiche, altrimenti e' affondata.
static func _retreat_fleet(state: GameState, army: Army, region: CampaignData.Region, result: BattleResult) -> void:
	if army.from_region != "":
		var origin := state.campaign.region(army.from_region)
		if origin != null and origin.is_sea and origin.id != region.id and not _hostile_present(state, origin.id, army.faction, true):
			_record_retreat(state, army, region.id, origin.id, "ritorno", result)
			return
	for n in region.neighbours:
		var neighbour := state.campaign.region(n)
		if neighbour != null and neighbour.is_sea and not _hostile_present(state, neighbour.id, army.faction, true):
			_record_retreat(state, army, region.id, neighbour.id, "mare_vicino", result)
			return
	_capture(state, army, region.id, "nessuna_via", result)


## Come `_hostile_present`, per gli altri moduli (PrisonerProcessor).
static func hostile_present(state: GameState, region_id: String, faction_id: String, fleet: bool) -> bool:
	return _hostile_present(state, region_id, faction_id, fleet)


## Vero se nella regione ci sono (anche nel castello) eserciti, o flotte, di fazioni in guerra con `faction_id`.
static func _hostile_present(state: GameState, region_id: String, faction_id: String, fleet: bool) -> bool:
	for a in state.armies:
		if a.region == region_id and a.is_fleet == fleet and not a.stacks.is_empty() and state.at_war(a.faction, faction_id):
			return true
	return false


static func _record_retreat(state: GameState, army: Army, from_id: String, to_id: String, case_name: String, result: BattleResult) -> void:
	army.region = to_id
	if case_name != "castello":
		army.in_castle = false
	army.path = PackedStringArray()
	army.sea_route = PackedStringArray()
	army.assault_ordered = false
	army.from_region = ""
	army.arrived_year = 0
	var text := ""
	if case_name == "castello":
		text = Lang.t("L'esercito %d di %s si ritira nel castello di %s.") % [army.id, SimUtil.faction_label(army.faction), region_label(state, from_id)]
	else:
		text = Lang.t("L'esercito %d di %s si ritira da %s a %s.") % [army.id, SimUtil.faction_label(army.faction), region_label(state, from_id), region_label(state, to_id)]
	result.retreats.append({"esercito": army.id, "fazione": army.faction, "da": from_id, "a": to_id, "caso": case_name, "testo": text})


## Esercito catturato: tolto dal campo; le truppe di terra e il comandante diventano prigionieri del vincitore (ADR-073).
static func _capture(state: GameState, army: Army, region_id: String, case_name: String, result: BattleResult) -> void:
	var men := army.men_total()
	if not army.is_fleet:
		PrisonerProcessor.capture_army(state, army, region_id, result.winner_faction(), PrisonerProcessor.captor_commander(state, result))
	var text := Lang.t("L'esercito %d di %s (%d uomini) e' catturato a %s.") % [army.id, SimUtil.faction_label(army.faction), men, region_label(state, region_id)]
	if army.is_fleet:
		text = Lang.t("La flotta %d di %s (%d navi) e' affondata a %s.") % [army.id, SimUtil.faction_label(army.faction), men, region_label(state, region_id)]
	result.captures.append({"esercito": army.id, "fazione": army.faction, "uomini": men, "caso": case_name, "testo": text})
	state.remove_army(army)


# --- eventi delle battaglie ----------------------------------------------------------------------


## Eventi di una battaglia: prima EV_BATTLE (con i dettagli), poi le ritirate e le catture.
## `extra` e' unito ai dettagli di EV_BATTLE.
static func _emit_battle(state: GameState, result: BattleResult, region_id: String, extra: Dictionary) -> void:
	var label := region_label(state, region_id)
	var intro := Lang.t("Battaglia a %s") % label
	if result.kind == BattleResult.KIND_NAVAL:
		intro = Lang.t("Battaglia navale in %s") % label
	elif result.kind == BattleResult.KIND_ASSAULT:
		intro = Lang.t("Assalto al castello di %s") % label
	elif result.kind == BattleResult.KIND_SALLY:
		intro = Lang.t("Sortita dal castello di %s") % label
	var text := Lang.t("%s: %s (%d uomini) contro %s (%d); vince %s. Perdite: %d contro %d.") % [
		intro,
		SimUtil.faction_label(result.attacker_faction), result.attacker_men_before,
		SimUtil.faction_label(result.defender_faction), result.defender_men_before,
		SimUtil.faction_label(result.winner_faction()),
		result.attacker_losses, result.defender_losses,
	]
	var data := result.to_dict()
	data["fazione"] = result.attacker_faction
	data["regione"] = region_id
	data["testo"] = text
	data.merge(extra, true)
	state.add_event(GameState.EV_BATTLE, data)
	for item in result.retreats:
		var d: Dictionary = item
		var e := d.duplicate()
		e["regione"] = region_id
		state.add_event(GameState.EV_RETREAT, e)
	for item in result.captures:
		var d: Dictionary = item
		var e := d.duplicate()
		e["regione"] = region_id
		state.add_event(GameState.EV_CAPTURED_UNITS, e)


# --- assedi ---------------------------------------------------------------------------------------


## Gestione degli assedi del fine anno: nuovi assedi (che non contano il primo anno), poi per ogni
## assedio gia' in corso assalto, sortita oppure un anno di fame.
static func process_sieges(state: GameState) -> void:
	var fresh := refresh_sieges(state)
	for siege in state.sieges_in_order():
		if fresh.has(siege.region) or state.siege_in(siege.region) != siege:
			continue
		_process_siege(state, siege)


## Allinea gli assedi agli eserciti presenti: crea quelli nuovi (guarnigione nel castello e un
## esercito in guerra fuori), aggiorna gli eserciti assedianti, chiude quelli senza assedianti o
## senza guarnigione (e fa uscire dal castello la guarnigione). Restituisce le regioni dei nuovi assedi.
static func refresh_sieges(state: GameState) -> Dictionary:
	var created := {}
	var garrison := {}
	var field := {}
	for a in state.armies:
		if a.is_fleet or a.stacks.is_empty():
			continue
		var bucket := field
		if a.in_castle:
			bucket = garrison
		if not bucket.has(a.region):
			bucket[a.region] = [] as Array[Army]
		var list: Array = bucket[a.region]
		list.append(a)
	for region in state.campaign.land_regions():
		var inside: Array = garrison.get(region.id, [])
		var outside: Array = field.get(region.id, [])
		var siege := state.siege_in(region.id)
		if inside.is_empty():
			if siege != null:
				_end_siege(state, siege, "guarnigione_assente")
			continue
		var first_inside: Army = inside[0]
		var garrison_faction := first_inside.faction
		var besieger := ""
		if siege != null and state.at_war(siege.faction, garrison_faction) and _has_faction(outside, siege.faction):
			besieger = siege.faction
		else:
			for item in outside:
				var candidate: Army = item
				if state.at_war(candidate.faction, garrison_faction):
					besieger = candidate.faction
					break
		if besieger == "":
			# nessun assediante: la guarnigione resta nel castello (dal 2026-11-10, richiesta di Federico: le reclute nascono
			# nel castello e ci restano finche' non le si fa uscire o muovere; prima usciva da sola a fine anno)
			if siege != null:
				_end_siege(state, siege, "tolto")
			continue
		if siege == null:
			siege = SiegeState.new(region.id, besieger, 0)
			state.sieges[region.id] = siege
			created[region.id] = true
			state.add_event(GameState.EV_SIEGE_STARTED, {
				"fazione": besieger,
				"regione": region.id,
				"assediata": garrison_faction,
				"testo": Lang.t("%s assedia il castello di %s (%s).") % [SimUtil.faction_label(besieger), region_label(state, region.id), SimUtil.faction_label(garrison_faction)],
			})
		elif siege.faction != besieger:
			siege.faction = besieger
			siege.years = 0
		siege.army_ids = PackedInt32Array()
		for item in outside:
			var besieging: Army = item
			if besieging.faction == besieger:
				siege.army_ids.append(besieging.id)
	return created


static func _has_faction(armies: Array, faction_id: String) -> bool:
	for item in armies:
		var a: Army = item
		if a.faction == faction_id:
			return true
	return false


static func _process_siege(state: GameState, siege: SiegeState) -> void:
	var c := state.rules.combat
	var region_id := siege.region
	var garrison: Array[Army] = []
	var besiegers: Array[Army] = []
	for a in state.armies:
		if a.region != region_id or a.is_fleet or a.stacks.is_empty():
			continue
		if a.in_castle:
			garrison.append(a)
		elif a.faction == siege.faction:
			besiegers.append(a)
	if besiegers.is_empty():
		_end_siege(state, siege, "tolto")
		return
	if garrison.is_empty():
		return   # niente da assediare: la provincia passa all'assediante nel passo delle conquiste
	var region := state.campaign.region(region_id)
	var level := Combat.castle_level(state, region_id)
	var ordered := false
	for a in besiegers:
		if a.assault_ordered:
			ordered = true
	# assalto ordinato dall'assediante: battaglia con il moltiplicatore del castello
	if ordered:
		var result := Combat.resolve(state, region_id, besiegers, garrison, BattleResult.KIND_ASSAULT, Combat.defender_multiplier(state, BattleResult.KIND_ASSAULT, level) * LegendarySites.region_factor(state, region_id, "difesa"))   # luoghi leggendari (Danevirke, Muraglia)
		for a in besiegers:
			a.assault_ordered = false
		if result.attacker_won:
			# castello espugnato: chi era rimasto in guarnigione e' catturato (con `assalto_annienta` non resta nessuno,
			# ma il comandante annientato e' prigioniero: ADR-073)
			for a in garrison:
				if state.armies.has(a):
					_capture(state, a, region_id, "castello_espugnato", result)
				else:
					PrisonerProcessor.capture_commander(state, a.id, a.faction, region_id, siege.faction, PrisonerProcessor.captor_commander(state, result))
		else:
			for a in besiegers:
				if state.armies.has(a):
					_retreat(state, a, region, result)
		state.add_event(GameState.EV_ASSAULT, {
			"fazione": siege.faction,
			"regione": region_id,
			"vittoria": result.attacker_won,
			"testo": Lang.t("%s assalta il castello di %s: %s.") % [SimUtil.faction_label(siege.faction), region_label(state, region_id), Lang.t("espugnato") if result.attacker_won else Lang.t("respinto")],
		})
		_emit_battle(state, result, region_id, {})
		return
	# sortita: la guarnigione esce se e' molto piu' forte degli assedianti
	var garrison_strength := Combat.side_strength(state, garrison)
	var besieger_strength := Combat.side_strength(state, besiegers)
	if besieger_strength > 0.0 and garrison_strength > c.sally_threshold * besieger_strength:
		var sally := Combat.resolve(state, region_id, garrison, besiegers, BattleResult.KIND_SALLY, Combat.defender_multiplier(state, BattleResult.KIND_SALLY, level))
		if sally.attacker_won:
			for a in besiegers:
				if state.armies.has(a):
					_retreat(state, a, region, sally)
		else:
			for a in garrison:
				if not state.armies.has(a):
					PrisonerProcessor.capture_commander(state, a.id, a.faction, region_id, siege.faction, PrisonerProcessor.captor_commander(state, sally))
		var garrison_faction := garrison[0].faction
		state.add_event(GameState.EV_SALLY, {
			"fazione": garrison_faction,
			"regione": region_id,
			"vittoria": sally.attacker_won,
			"testo": Lang.t("La guarnigione di %s (%s) fa una sortita: %s.") % [region_label(state, region_id), SimUtil.faction_label(garrison_faction), Lang.t("respinge gli assedianti") if sally.attacker_won else Lang.t("e' annientata")],
		})
		_emit_battle(state, sally, region_id, {})
		return
	# un anno di assedio: fame
	siege.years += 1
	siege.army_ids = PackedInt32Array()
	for a in besiegers:
		siege.army_ids.append(a.id)
	if siege.years >= c.starve_after(level) + LegendarySites.region_int(state, region_id, "anni_assedio"):
		var men := Combat.men_of(garrison)
		var garrison_faction := garrison[0].faction
		var captor_id := 0
		for a in besiegers:
			var bc := state.commander_of(a.id)
			if bc != null:
				captor_id = bc.id
				break
		for a in garrison:
			PrisonerProcessor.capture_army(state, a, region_id, siege.faction, captor_id)   # ADR-073: la guarnigione affamata si arrende
			state.remove_army(a)
		state.add_event(GameState.EV_STARVED, {
			"fazione": garrison_faction,
			"regione": region_id,
			"assediante": siege.faction,
			"anni": siege.years,
			"uomini": men,
			"testo": Lang.t("La guarnigione di %s (%s) cede per fame dopo %d anni di assedio.") % [region_label(state, region_id), SimUtil.faction_label(garrison_faction), siege.years],
		})


## Chiude un assedio: la guarnigione rimasta esce dal castello, gli ordini d'assalto cadono.
## `reason`: tolto, guarnigione_assente, conquista.
static func _end_siege(state: GameState, siege: SiegeState, reason: String) -> void:
	state.sieges.erase(siege.region)
	for a in state.armies:
		if a.region == siege.region and not a.is_fleet:
			a.assault_ordered = false   # la guarnigione resta nel castello anche ad assedio finito (2026-11-10)
	var text := Lang.t("L'assedio di %s e' terminato (%s).") % [region_label(state, siege.region), _reason_label(reason)]
	state.add_event(GameState.EV_SIEGE_ENDED, {
		"fazione": siege.faction,
		"regione": siege.region,
		"motivo": reason,
		"anni": siege.years,
		"testo": text,
	})


static func _reason_label(reason: String) -> String:
	if reason == "tolto":
		return Lang.t("gli assedianti se ne sono andati o sono stati sconfitti")
	if reason == "guarnigione_assente":
		return Lang.t("il castello e' vuoto")
	if reason == "conquista":
		return Lang.t("la provincia e' stata conquistata")
	return reason


# --- conquiste e fazioni distrutte -------------------------------------------------------------------


## Una provincia passa all'attaccante quando non ci sono piu' eserciti del proprietario (ne' in
## campo ne' in guarnigione) e c'e' un esercito di una fazione in guerra con lui fuori dal castello.
## Code svuotate, tassa normale; alcuni edifici vanno persi (ConquestDamage, PROVVISORIA).
static func conquests(state: GameState) -> void:
	var present := {}
	for a in state.armies:
		if a.is_fleet or a.stacks.is_empty():
			continue
		if not present.has(a.region):
			present[a.region] = [] as Array[Army]
		var list: Array = present[a.region]
		list.append(a)
	for p in state.provinces:
		var here: Array = present.get(p.id, [])
		if here.is_empty():
			continue
		var owner_present := false
		for item in here:
			var a: Army = item
			if a.faction == p.owner:
				owner_present = true
		if owner_present:
			continue
		# fase 5c: un esercito crociato conquista solo il suo bersaglio, non le province che attraversa
		var capable: Array = []
		for item in here:
			var able: Army = item
			if PapacyProcessor.may_conquer(able, p.id):
				capable.append(able)
		var conqueror := ""
		var siege := state.siege_in(p.id)
		if siege != null and state.at_war(siege.faction, p.owner) and _has_faction(capable, siege.faction):
			conqueror = siege.faction
		else:
			for item in capable:
				var candidate: Army = item
				if not candidate.in_castle and state.at_war(candidate.faction, p.owner):
					conqueror = candidate.faction
					break
		if conqueror != "":
			_conquer(state, p, conqueror, ConquestDamage.MEANS_SIEGE if siege != null else ConquestDamage.MEANS_FIELD)
	refresh_sieges(state)


## La provincia passa a `conqueror` fuori dal passo delle conquiste (porte aperte da una spia, guarnigione
## corrotta, fase 5a): stesse conseguenze di una conquista (assedio chiuso, code svuotate, EV_PROVINCE_CAPTURED). `means`
## e' il modo per i danni agli edifici (ConquestDamage: «porte» per la spia, «corruzione» per la guarnigione corrotta).
static func transfer_province(state: GameState, province: ProvinceState, conqueror: String, means: String = ConquestDamage.MEANS_FIELD) -> void:
	_conquer(state, province, conqueror, means)


static func _conquer(state: GameState, province: ProvinceState, conqueror: String, means: String = ConquestDamage.MEANS_FIELD) -> void:
	var previous := province.owner
	var siege := state.siege_in(province.id)
	var damage := ConquestDamage.apply(state, province, conqueror, means)   # 15/11: edifici persi nella conquista
	province.owner = conqueror
	if province.first_conqueror == "" and conqueror != GameState.REBEL:
		province.first_conqueror = conqueror
	state.mark_war_turn(conqueror, previous)
	province.building_queue.clear()
	province.unit_queue.clear()
	province.tax_level = state.rules.default_tax
	if siege != null:
		_end_siege(state, siege, "conquista")
	for a in state.armies:
		if a.region == province.id and not a.is_fleet:
			a.assault_ordered = false
			a.in_castle = false
	var text := Lang.t("%s conquista %s (era di %s).") % [SimUtil.faction_label(conqueror), region_label(state, province.id), SimUtil.faction_label(previous)]
	var lost := ConquestDamage.describe(state, damage)
	state.add_event(GameState.EV_PROVINCE_CAPTURED, {
		"fazione": conqueror,
		"regione": province.id,
		"precedente": previous,
		"modo": means,
		"distrutti": Array(damage["distrutti"]),
		"danneggiati": Array(damage["danneggiati"]),
		"testo": text if lost == "" else "%s %s" % [text, lost],
	})


## Fazioni senza province e senza eserciti: distrutte. I ribelli non si distruggono mai.
static func destroyed_factions(state: GameState) -> void:
	for f in state.factions:
		if not f.alive or f.id == GameState.REBEL:
			continue
		if state.provinces_of(f.id).is_empty() and state.armies_of(f.id).is_empty():
			f.alive = false
			state.add_event(GameState.EV_FACTION_DESTROYED, {
				"fazione": f.id,
				"regione": "",
				"testo": Lang.t("%s e' stata distrutta.") % SimUtil.faction_label(f.id),
			})


## Nome leggibile della regione (come nello startpos) per i testi degli eventi.
static func region_label(state: GameState, region_id: String) -> String:
	return RegionNames.shown(state.campaign, region_id)   # fase 8: nomi italiani di data/province.cfg (in inglese i dati)
