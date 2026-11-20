class_name AiNavy
extends RefCounted
## Flotte e trasporti dell'IA (fase 7a). I profili navali (`navale` in ia.cfg) tengono flotte nei porti (una ogni due province con
## porto, PROVVISORIA) comprandole nei cantieri; le flotte attaccano le flotte nemiche delle zone di mare vicine se il rapporto di
## forza lo consente; le fazioni con flotte sbarcano eserciti liberi nei porti verso le province raggiungibili via mare
## (`GameCommands.sea_destinations` / `order_move` con trasporto). Ogni ordine passa da `GameCommands`.


static func plan(plan_data: AiPlan) -> void:
	var fleets := plan_data.ctx.fleets_of(plan_data.id)
	if not plan_data.flag("navale") and fleets.is_empty():
		return
	_fleet_attacks(plan_data, fleets)
	if plan_data.flag("navale"):
		_build_fleets(plan_data, fleets)
	if not fleets.is_empty() and plan_data.target_level > 0:
		if not _invade(plan_data) and plan_data.flag("navale"):
			position_fleets(plan_data, fleets)


# --- flotte -------------------------------------------------------------------------------------------------


## Flotte (di mare) nemiche: la flotta (o tutte le flotte libere della zona) attacca una zona entro il raggio delle sue navi
## (Combat.fleet_range, come il giocatore dal 2026-11-09) se il rapporto di forza stimato supera `soglia_flotte` x difficolta';
## la rotta e' la piu' breve (GameCommands.fleet_path).
static func _fleet_attacks(plan: AiPlan, fleets: Array) -> void:
	var ctx := plan.ctx
	var state := plan.state
	var bonus := 1.0 + state.rules.combat.sea_defender_bonus
	var done := {}
	for item in fleets:
		var lead: Army = item
		if done.has(lead.region) or not lead.path.is_empty() or ctx.busy.has(lead.id):
			continue
		done[lead.region] = true
		var group: Array[Army] = []
		for entry in ctx.fleets_at(lead.region):
			var f: Army = entry
			if f.faction == plan.id and f.path.is_empty() and not ctx.busy.has(f.id):
				group.append(f)
		var attack_force := AiForce.sum_force(ctx, group)
		var reach := 99
		for f in group:
			reach = mini(reach, Combat.fleet_range(state, f))
		var best_zone := ""
		var best_ratio := 0.0
		for zone in _zones_within(ctx, lead.region, reach):
			var enemy := 0.0
			var treaty := false
			for entry in ctx.fleets_at(zone):
				var e: Army = entry
				if e.faction == plan.id or state.is_allied(plan.id, e.faction):
					continue
				if not state.at_war(plan.id, e.faction):
					treaty = true   # neutrali e tregue: le flotte non si attaccano senza guerra
					continue
				enemy += ctx.force(e)
			if treaty or enemy <= 0.0:
				continue
			var r := AiForce.ratio(attack_force, enemy * bonus)
			if r > best_ratio:
				best_ratio = r
				best_zone = zone
		if best_zone == "" or best_ratio < plan.rules.fleet_ratio * float(ctx.diff.get("soglia", 1.0)):
			continue
		for f2 in group:
			var route := GameCommands.fleet_path(state, f2.id, best_zone)
			if route.is_empty():
				continue
			if plan.record(GameCommands.order_move(state, plan.id, f2.id, route), "flotta %d -> %s" % [f2.id, best_zone]):
				ctx.busy[f2.id] = true


## Zone di mare raggiungibili da `start` in al massimo `steps` passi (esclusa la partenza), in ordine di distanza e di
## SetNeighbours.
static func _zones_within(ctx: AiContext, start: String, steps: int) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {start: true}
	var frontier := PackedStringArray([start])
	for depth in maxi(1, steps):
		var next_frontier := PackedStringArray()
		for zone in frontier:
			for n in ctx.sea_neighbours.get(zone, PackedStringArray()):
				if seen.has(n):
					continue
				seen[n] = true
				out.append(n)
				next_frontier.append(n)
		frontier = next_frontier
	return out


## Costruisce una nave se le flotte (piu' le navi in coda) sono meno di `flotte_per_porto` x province con porto (almeno una). La
## provincia e' un porto con cantiere dove la nave e' reclutabile; spesa al massimo la meta' del tesoro oltre la riserva.
static func _build_fleets(plan: AiPlan, fleets: Array) -> void:
	var state := plan.state
	var ports: Array[ProvinceState] = []
	for p in plan.provinces:
		var region := state.campaign.region(p.id)
		if region != null and region.has_port:
			ports.append(p)
	if ports.is_empty():
		return
	var wanted := maxi(1, ceili(float(ports.size()) * plan.rules.fleets_per_port))
	var have := fleets.size()
	for p in ports:
		for q in p.unit_queue:
			var u := state.units.get_unit(q.key)
			if u != null and u.is_ship():
				have += 1
	if have >= wanted:
		return
	var budget := float(plan.faction.treasury - plan.reserve) * 0.5
	if budget <= 0.0:
		return
	var support_room := plan.num("tetto_mantenimento") * float(plan.income) - float(plan.upkeep)
	for p in ports:
		if p.unit_queue.size() >= plan.rules.recruit_queue_max:
			continue
		var ship := AiEconomy.pick_unit(plan, p, budget, support_room, true)
		if ship == null:
			continue
		if not bool(GameCommands.can_queue_unit(state, plan.id, p.id, ship.id)["ok"]):
			continue
		if plan.record(GameCommands.queue_unit(state, plan.id, p.id, ship.id), "nave %s %s" % [p.id, ship.id]):
			plan.upkeep += ship.support_cost
			return


# --- sbarchi ------------------------------------------------------------------------------------------------


## Un solo sbarco all'anno: dai porti propri dove gli eserciti liberi possono imbarcarsi, verso le province raggiungibili via
## mare il cui proprietario si puo' attaccare, con rapporto stimato sopra la soglia x `fattore_soglia`. I trasporti richiedono
## flotte proprie nelle zone di mare (altrimenti `sea_destinations` e' vuoto).
static func _invade(plan: AiPlan) -> bool:
	var ctx := plan.ctx
	var state := plan.state
	var best_target := ""
	var best_source := ""
	var best_armies: Array[Army] = []
	var best_score := 0.0
	var rolls := {}
	var checked := 0
	for p in plan.provinces:
		if checked >= 3:
			break
		if GameCommands.embark_problem(state, plan.id, p.id) != "":
			continue
		var movers := AiWar.spare(plan, p.id)
		if movers.is_empty():
			continue
		checked += 1
		var group: Array[Army] = []
		for a in movers:
			if group.size() < 8:
				group.append(a)
		var destinations := GameCommands.sea_destinations(state, plan.id, group[0].id)
		var attack_force := AiForce.sum_force(ctx, group)
		for dest in destinations:
			var kind := AiPolicy.attackable(plan, ctx.owner_of(dest))
			if kind == "" or kind == AiPolicy.KIND_BETRAYAL:
				continue   # il tradimento di un alleato si fa solo per terra
			var defence := AiForce.defenders(ctx, dest, plan.id)
			var r := AiForce.ratio(attack_force, float(defence["totale"]))
			if r < AiPolicy.threshold_for(plan, kind) * plan.rules.naval_factor:
				continue
			var region := state.campaign.region(dest)
			var score := (float(region.income) + 100.0) * minf(r, 4.0)
			if score <= best_score:
				continue
			if kind == AiPolicy.KIND_NEUTRAL:
				var owner_id := ctx.owner_of(dest)
				if not rolls.has(owner_id):
					rolls[owner_id] = plan.rng.randf() < plan.aggression
				if not bool(rolls[owner_id]):
					continue
			best_target = dest
			best_source = p.id
			best_armies = group
			best_score = score
	if best_target == "":
		return false
	var moved := false
	for a in best_armies:
		if plan.record(GameCommands.order_move(state, plan.id, a.id, PackedStringArray([best_target])), "sbarco %d %s -> %s" % [a.id, best_source, best_target]):
			plan.commit(a, best_target)
			moved = true
	return moved


## Senza sbarchi nell'anno, le fazioni navali spostano una flotta libera nella zona di mare, confinante con un loro porto da cui
## si imbarca, che si affaccia sul bersaglio migliore (ribelli, nemici o neutrali attaccabili; reddito + 100 diviso per i
## difensori, x1,5 per ribelli e nemici), cosi' l'anno dopo gli eserciti hanno la catena per sbarcare (Giapponesi fermi con
## la flotta nel Mar Cinese Orientale, 18/11/2026). Nessuno spostamento se una flotta propria e' gia' nella zona migliore.
static func position_fleets(plan: AiPlan, fleets: Array) -> void:
	var ctx := plan.ctx
	var state := plan.state
	var scores := {}
	var best_zone := ""
	var best_score := 0.0
	for p in plan.provinces:
		if GameCommands.embark_problem(state, plan.id, p.id) != "":
			continue
		for zone in ctx.sea_neighbours.get(p.id, PackedStringArray()):
			if scores.has(zone):
				continue
			var value := _zone_value(plan, zone)
			scores[zone] = value
			if value > best_score:
				best_score = value
				best_zone = zone
	if best_zone == "":
		return
	var idle: Array[Army] = []
	for item in fleets:
		var f: Army = item
		if not f.path.is_empty() or ctx.busy.has(f.id):
			continue
		if f.region == best_zone:
			return
		idle.append(f)
	var chosen: Army = null
	var chosen_value := INF
	for f in idle:
		var here := float(scores.get(f.region, 0.0))
		if here < chosen_value and not GameCommands.fleet_path(state, f.id, best_zone).is_empty():
			chosen = f
			chosen_value = here
	if chosen == null or chosen_value >= best_score:
		return
	var route := GameCommands.fleet_path(state, chosen.id, best_zone)
	if plan.record(GameCommands.order_move(state, plan.id, chosen.id, route), "flotta %d in posizione -> %s" % [chosen.id, best_zone]):
		ctx.busy[chosen.id] = true


## Valore della zona di mare per uno sbarco: il miglior bersaglio di terra che vi si affaccia (0 se nessuno).
static func _zone_value(plan: AiPlan, zone: String) -> float:
	var ctx := plan.ctx
	var region := plan.state.campaign.region(zone)
	var best := 0.0
	if region == null:
		return best
	for n in region.neighbours:
		var land := plan.state.campaign.region(n)
		if land == null or land.is_sea:
			continue
		var kind := AiPolicy.attackable(plan, ctx.owner_of(n))
		if kind == "" or kind == AiPolicy.KIND_BETRAYAL:
			continue
		var defence := float(AiForce.defenders(ctx, n, plan.id)["totale"])
		var value := (float(land.income) + 100.0) / (1.0 + defence)
		if kind != AiPolicy.KIND_NEUTRAL:
			value *= 1.5
		best = maxf(best, value)
	return best
