class_name AiCrusades
extends RefCounted
## Crociate e jihad dell'IA (fase 7b). Regole PROVVISORIE, parametri in `ia.cfg` ([crociate]).
##   - BANDIRE: i profili crociati (`profili_crociati`, cattolici non scomunicati) bandiscono una crociata, i profili del jihad
##     (`profili_jihad`, musulmani) un jihad, con probabilita' annua `prob_crociata`, solo se entro `raggio_crociata` passi di terra
##     dalle province proprie c'e' un bersaglio valido (`PapacyProcessor.target_reason`, proprietario ne' alleato ne' in tregua), se
##     non c'e' gia' una crociata attiva o in coda, se il profilo effettivo non e' di difesa disperata o di poverta' e se il tesoro
##     oltre la riserva copre `tesoro_crociata` volte il costo. L'unita' si mette in coda in una provincia che soddisfa i requisiti;
##     se nessuna li soddisfa si costruisce l'edificio mancante (la Casa del Capitolo) con `queue_building`.
##   - GUIDARE: ogni esercito crociato proprio senza bersaglio (o il cui bersaglio non e' piu' valido) riceve con `set_crusade_target`
##     il bersaglio migliore entro `raggio_crociata` passi: rendita della provincia, castello e rapporto di forza, divisi per la
##     distanza. Il percorso lo assegna il comando.


## Chiamato da `AiFaction.plan` dopo la guerra e prima degli agenti.
static func plan(data: AiPlan) -> void:
	if data.provinces.is_empty():
		return
	_steer(data)
	var kind := kind_of(data)
	if kind != "":
		_launch(data, kind)


## Genere di crociata che il profilo bandisce: KIND_CRUSADE, KIND_JIHAD o "".
static func kind_of(data: AiPlan) -> String:
	var base := AiProfiles.base(data.ctx, data.id)
	if data.rules.is_jihadi(base) and ReligionProcessor.faction_religion(data.state, data.id) == ProvinceState.MUSLIM:
		return PapacyProcessor.KIND_JIHAD
	if data.rules.is_crusader(base) and PapacyProcessor.is_catholic(data.state, data.id):
		return PapacyProcessor.KIND_CRUSADE
	return ""


# --- guida degli eserciti crociati ------------------------------------------------------------------------------------


static func _steer(data: AiPlan) -> void:
	for item in data.ctx.land_armies_of(data.id):
		var army: Army = item
		if not army.is_crusade():
			continue
		var target := army.crusade_target()
		if target != "" and PapacyProcessor.target_problem(data.state, army, target) == "":
			if army.region == target or not army.path.is_empty():
				continue
			# bersaglio valido ma l'esercito e' fermo: rinnova il comando (assegna il percorso)
			data.record(GameCommands.set_crusade_target(data.state, data.id, army.id, target), "crociata %d verso %s" % [army.id, target])
			continue
		var best := best_target(data, army)
		if best != "":
			data.record(GameCommands.set_crusade_target(data.state, data.id, army.id, best), "bersaglio crociata %d: %s" % [army.id, best])


## Miglior bersaglio valido per l'esercito crociato entro `raggio_crociata` passi, "" se non ce n'e'.
static func best_target(data: AiPlan, army: Army) -> String:
	var ctx := data.ctx
	var search := AiAgents.bfs(ctx, army.region, data.rules.crusade_radius)
	var order: Array = search["ordine"]
	var depth: Dictionary = search["profondita"]
	var own_force := ctx.force(army)
	var best := ""
	var best_score := -1.0
	for item in order:
		var rid := str(item)
		if PapacyProcessor.target_problem(data.state, army, rid) != "":
			continue
		var castle := Combat.castle_level(data.state, rid)
		var worth := float(ctx.province_income.get(rid, 0)) + 50.0 * float(castle) + 100.0
		var defence := AiForce.defenders(ctx, rid, army.faction)
		var r := clampf(AiForce.ratio(own_force, float(defence["totale"])), 0.25, 3.0)
		var score := worth * r / (1.0 + 0.5 * float(depth.get(rid, 1)))
		if score > best_score:
			best_score = score
			best = rid
	return best


# --- bandire ---------------------------------------------------------------------------------------------------------


static func _launch(data: AiPlan, kind: String) -> void:
	var state := data.state
	if PapacyProcessor.launch_problem(state, data.id, kind) != "":
		return
	if data.profile == AiProfiles.DESPERATE or data.profile == AiProfiles.POVERTY:
		return
	if kind == PapacyProcessor.KIND_JIHAD and _jihad_active(data):
		return
	if not has_valid_target(data, kind):
		return
	if data.rng.randf() >= data.rules.crusade_prob:
		return
	var type_name := AgentState.JIHAD if kind == PapacyProcessor.KIND_JIHAD else AgentState.CRUSADE
	var unit := _cheapest_unit(data, type_name)
	if unit == null:
		return
	var spendable := float(data.faction.treasury - data.reserve)
	if spendable < data.rules.crusade_treasury * float(unit.cost):
		return
	# provincia che soddisfa i requisiti dell'unita'
	for p in data.provinces:
		if p.unit_queue.size() >= data.rules.recruit_queue_max:
			continue
		if not bool(GameCommands.can_queue_unit(state, data.id, p.id, unit.id)["ok"]):
			continue
		data.record(GameCommands.queue_unit(state, data.id, p.id, unit.id), "%s %s" % [kind, p.id])
		return
	_build_requirement(data, unit)


## Il jihad non ha il limite di uno alla volta nelle regole: l'IA ne tiene uno solo (attivo o in coda).
static func _jihad_active(data: AiPlan) -> bool:
	for item in data.ctx.land_armies_of(data.id):
		var a: Army = item
		if a.crusade_kind() == PapacyProcessor.KIND_JIHAD:
			return true
	for p in data.provinces:
		for q in p.unit_queue:
			var u := data.state.units.get_unit(q.key)
			if u != null and u.type_name == AgentState.JIHAD:
				return true
	return false


static func _cheapest_unit(data: AiPlan, type_name: String) -> UnitType:
	var best: UnitType = null
	for item in data.ctx.units_of_type(type_name):
		var u: UnitType = item
		if not u.allows_faction(data.id) or not u.available_in_period(data.state.era):
			continue
		if best == null or u.cost < best.cost:
			best = u
	return best


## Vero se entro `raggio_crociata` passi di terra da una provincia propria c'e' una provincia che e' un bersaglio valido per `kind`
## e il cui proprietario non ha un trattato con la fazione.
static func has_valid_target(data: AiPlan, kind: String) -> bool:
	var state := data.state
	var ctx := data.ctx
	var seen := {}
	var frontier: Array[String] = []
	for p in data.provinces:
		seen[p.id] = true
		frontier.append(p.id)
	var step := 0
	while not frontier.is_empty() and step < data.rules.crusade_radius:
		step += 1
		var next: Array[String] = []
		for rid in frontier:
			for n in ctx.land_neighbours.get(rid, PackedStringArray()):
				if seen.has(n):
					continue
				seen[n] = true
				next.append(n)
				var target := state.province(n)
				if target == null or target.owner == data.id:
					continue
				if PapacyProcessor.target_reason(state, kind, target) == "":
					continue
				var rel := state.relation(data.id, target.owner)
				if rel == GameState.REL_ALLIANCE or rel == GameState.REL_TRUCE:
					continue
				return true
		frontier = next
	return false


## Mette in coda l'edificio che manca per reclutare `unit` (il primo token non soddisfatto del primo gruppo possibile) nella
## provincia dove costa meno.
static func _build_requirement(data: AiPlan, unit: UnitType) -> void:
	var state := data.state
	for group in unit.requires:
		for token in group:
			var lv := state.buildings.resolve(token)
			if lv == null:
				continue
			for p in data.provinces:
				if p.level_of(lv.family) >= lv.level or p.building_queue.size() >= state.rules.max_building_queue:
					continue
				var check := GameCommands.can_queue_building(state, data.id, p.id, lv.family)
				if not bool(check["ok"]) or int(check["livello"]) != lv.level:
					continue
				if float(data.faction.treasury - data.reserve) < float(check["costo"]) + float(unit.cost):
					return
				data.record(GameCommands.queue_building(state, data.id, p.id, lv.family), "edificio per %s in %s" % [unit.id, p.id])
				return
