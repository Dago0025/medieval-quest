class_name AiWar
extends RefCounted
## Guerra dell'IA (fase 7a): assedi e assalti, difesa (rinforzi alla frontiera, capitale mai sguarnita, soccorso agli assedi),
## attacco (rapporto di forza stimato con la formula di `Combat` senza casualita', soglia per profilo), concentrazione dei
## rinforzi sul fronte e razzie dei predoni. Ogni ordine passa da `GameCommands` (`order_move`, `order_assault`) e se ne
## controlla l'esito. Regole PROVVISORIE; parametri in `data/regole/ia.cfg`.
##
## Ordine di una fazione: 1) assedi propri (assalto o attesa), 2) difesa, 3) attacchi, 4) concentrazione.


## Assedi, difesa e attacchi per terra. La concentrazione degli eserciti liberi verso la frontiera e' a parte
## (`concentrate`), dopo gli sbarchi di AiNavy, altrimenti porterebbe via gli eserciti che potrebbero imbarcarsi.
static func plan(plan_data: AiPlan) -> void:
	_sieges(plan_data)
	_defence(plan_data)
	if plan_data.target_level > 0:
		_attack(plan_data)


static func concentrate(plan_data: AiPlan) -> void:
	_concentrate(plan_data)


# --- assedi ----------------------------------------------------------------------------------------------


## Gli eserciti che assediano restano dove sono. Si ordina l'assalto quando la forza degli assedianti, contro la guarnigione
## moltiplicata per il castello, supera `soglia_assalto` (x difficolta'); se la guarnigione sta per cedere per fame (resta un anno
## o meno) si aspetta; altrimenti si continua l'assedio.
static func _sieges(plan: AiPlan) -> void:
	var ctx := plan.ctx
	var state := plan.state
	for siege in state.sieges_in_order():
		if siege.faction != plan.id:
			continue
		var besiegers: Array[Army] = []
		for item in ctx.armies_at(siege.region):
			var a: Army = item
			if a.faction == plan.id and not a.in_castle:
				besiegers.append(a)
		if besiegers.is_empty():
			continue
		for b in besiegers:
			ctx.busy[b.id] = true
		if Combat.years_to_starve(state, siege) <= 1:
			continue
		var garrison := AiForce.garrison_in_assault(ctx, siege.region)
		if garrison <= 0.0:
			continue
		var need := plan.rules.assault_ratio * float(ctx.diff.get("soglia", 1.0))
		if AiForce.ratio(AiForce.sum_force(ctx, besiegers), garrison) < need:
			continue
		for b in besiegers:
			if b.assault_ordered:
				break
			if not b.path.is_empty():
				continue
			if plan.record(GameCommands.order_assault(state, plan.id, b.id), "assalto %s" % siege.region):
				break


# --- spazio libero e rinforzi ------------------------------------------------------------------------------


## Eserciti della fazione in `region_id` che possono partire senza violare i minimi: forza pari a `margine_difesa` volte la
## minaccia nemica della provincia e, per la capitale, `uomini_min_capitale` uomini. Partono prima i piu' deboli (restano i piu'
## forti). Gli eserciti che non sono liberi ma restano (assediati, assedianti, impegnati senza ordine) contano come presenti.
static func spare(plan: AiPlan, region_id: String) -> Array[Army]:
	var out: Array[Army] = []
	var t: Dictionary = plan.threat.get(region_id, {})
	var keep_force := float(t.get("nemica", 0.0)) * plan.num("margine_difesa")
	var keep_men := plan.rules.capital_min_men if bool(t.get("capitale", false)) else 0
	var stay_force := 0.0
	var stay_men := 0
	var movable: Array[Dictionary] = []
	for item in plan.ctx.armies_at(region_id):
		var a: Army = item
		if a.faction != plan.id or not a.path.is_empty():
			continue
		if plan.is_free(a):
			movable.append({"a": a, "score": plan.ctx.force(a), "k": a.id})
		else:
			stay_force += plan.ctx.force(a)
			stay_men += a.men_total()
	movable.sort_custom(AiEconomy.before)
	# dal piu' forte: quelli che servono per i minimi restano, gli altri sono liberi
	for entry in movable:
		var a2: Army = entry["a"]
		if stay_force < keep_force or stay_men < keep_men:
			stay_force += plan.ctx.force(a2)
			stay_men += a2.men_total()
		else:
			out.append(a2)
	return out


## Passi di una ricerca in ampiezza sulle province proprie a partire da `start`, fino a `radius` passi: restituisce
## {"padre": regione -> regione piu' vicina a `start`, "ordine": regioni in ordine di scoperta (start escluso)}.
static func _own_bfs(plan: AiPlan, start: String, radius: int) -> Dictionary:
	var parent := {start: ""}
	var depth := {start: 0}
	var order: Array[String] = []
	var queue: Array[String] = [start]
	var i := 0
	while i < queue.size():
		var current := queue[i]
		i += 1
		if int(depth[current]) >= radius:
			continue
		for n in plan.ctx.land_neighbours.get(current, PackedStringArray()):
			if parent.has(n) or plan.ctx.owner_of(n) != plan.id:
				continue
			parent[n] = current
			depth[n] = int(depth[current]) + 1
			order.append(n)
			queue.append(n)
	return {"padre": parent, "ordine": order}


## Percorso da `from_id` verso `start` della ricerca `_own_bfs` (il primo passo e' il vicino di `from_id`).
static func _path_toward(parent: Dictionary, from_id: String, start: String) -> PackedStringArray:
	var path := PackedStringArray()
	var current := from_id
	var guard := 0
	while current != start and guard < 64:
		guard += 1
		current = str(parent.get(current, start))
		path.append(current)
	return path


# --- difesa -------------------------------------------------------------------------------------------------


## Le province con nemici nelle vicinanze e forza propria sotto `margine_difesa` x minaccia ricevono rinforzi dagli eserciti
## liberi delle province proprie entro `raggio_rinforzi` passi (prima le piu' urgenti). Se in una provincia propria stanno eserciti
## nemici (assedio o campo), i rinforzi partono solo se, insieme alla forza propria in campo, battono i nemici con il rapporto
## `soglia_soccorso`: non si manda nessuno al macello.
static func _defence(plan: AiPlan) -> void:
	var state := plan.state
	var margin := plan.num("margine_difesa")
	var bonus := 1.0 + state.rules.combat.defender_bonus
	var needs: Array[Dictionary] = []
	for i in plan.provinces.size():
		var p := plan.provinces[i]
		var t: Dictionary = plan.threat.get(p.id, {})
		var enemy := float(t.get("nemica", 0.0))
		if enemy <= 0.0:
			continue
		var incoming := float(plan.incoming.get(p.id, 0.0))
		var here := float(t.get("qui", 0.0))
		var own_field := _own_field_force(plan, p.id)
		var deficit := 0.0
		if here > 0.0:
			deficit = here * bonus * plan.rules.relief_ratio * float(plan.ctx.diff.get("soglia", 1.0)) - (own_field + incoming)
		else:
			deficit = enemy * margin - (float(t.get("propria", 0.0)) + incoming)
		if deficit <= 0.0:
			continue
		needs.append({"id": p.id, "deficit": deficit, "score": enemy / (float(t.get("propria", 0.0)) + incoming + 1.0), "k": i, "occupata": here > 0.0})
	needs.sort_custom(AiEconomy.before)
	for need in needs:
		_reinforce(plan, str(need["id"]), float(need["deficit"]), bool(need["occupata"]))
	_barricade(plan)


## Guarnigione volontaria (PROVVISORIA, `soglia_barricata`): nelle province con un castello dove la minaccia nemica supera
## la difesa in campo (eserciti fuori dal castello piu' rinforzi in arrivo, x bonus del difensore x soglia), gli eserciti
## liberi della provincia si chiudono nel castello finche' c'e' posto, i piu' forti prima: il nemico deve assediare invece di
## vincere in campo. Se a fine anno nessuno assedia escono da soli (WarProcessor.refresh_sieges).
static func _barricade(plan: AiPlan) -> void:
	var state := plan.state
	var c := state.rules.combat
	var bonus := 1.0 + c.defender_bonus
	for p in plan.provinces:
		if Combat.castle_level(state, p.id) <= 0:
			continue
		var t: Dictionary = plan.threat.get(p.id, {})
		var enemy := float(t.get("nemica", 0.0))
		if enemy <= 0.0:
			continue
		var field := _own_field_force(plan, p.id) + float(plan.incoming.get(p.id, 0.0))
		if enemy <= field * bonus * plan.rules.barricade_ratio:
			continue
		var candidates: Array[Army] = []
		for item in plan.ctx.armies_at(p.id):
			var a: Army = item
			if plan.is_free(a) and not a.in_castle:
				candidates.append(a)
		candidates.sort_custom(func(x: Army, y: Army) -> bool:
			var fx := plan.ctx.force(x)
			var fy := plan.ctx.force(y)
			return fx > fy if fx != fy else x.id < y.id)
		for a in candidates:
			if not bool(GameCommands.can_enter_castle(state, plan.id, a.id)["ok"]):
				continue
			if plan.record(GameCommands.enter_castle(state, plan.id, a.id), "barricata %d in %s" % [a.id, p.id]):
				plan.ctx.busy[a.id] = true


static func _own_field_force(plan: AiPlan, region_id: String) -> float:
	var total := 0.0
	for item in plan.ctx.armies_at(region_id):
		var a: Army = item
		if a.faction == plan.id and not a.in_castle:
			total += plan.ctx.force(a)
	return total


## Manda alla provincia `target` gli eserciti liberi piu' vicini finche' la lacuna `deficit` e' colmata. Con `all_or_nothing`
## (provincia occupata dal nemico) non parte nessuno se i rinforzi disponibili non bastano.
static func _reinforce(plan: AiPlan, target: String, deficit: float, all_or_nothing: bool) -> void:
	var search := _own_bfs(plan, target, plan.rules.reinforce_radius)
	var parent: Dictionary = search["padre"]
	var picks: Array[Dictionary] = []
	var available := 0.0
	for region_id in search["ordine"]:
		for a in spare(plan, region_id):
			picks.append({"a": a, "from": region_id})
			available += plan.ctx.force(a)
			if available >= deficit:
				break
		if available >= deficit:
			break
	if picks.is_empty() or (all_or_nothing and available < deficit):
		return
	for pick in picks:
		var a: Army = pick["a"]
		var path := _path_toward(parent, str(pick["from"]), target)
		if plan.record(GameCommands.order_move(plan.state, plan.id, a.id, path), "rinforzo %d -> %s" % [a.id, target]):
			plan.commit(a, target)


# --- attacco ------------------------------------------------------------------------------------------------------


## Fino a `attacchi_max` attacchi all'anno: ogni volta si sceglie il bersaglio migliore (rapporto stimato sopra la soglia,
## valore della provincia) tra le regioni di terra confinanti con quelle dove la fazione ha eserciti liberi; tutti gli eserciti
## liberi delle regioni confinanti col bersaglio partono insieme. Contro un neutrale si attacca con probabilita' `aggressione`
## (un sorteggio per fazione bersaglio); contro ribelli e nemici in guerra sempre. Mai alleati, tregue, avvertimenti papali.
## I predoni (BARBARIAN_RAIDER) scelgono la provincia piu' ricca.
static func _attack(plan: AiPlan) -> void:
	var tried := {}
	var rolls := {}
	var launches := 0
	while launches < plan.rules.attacks_per_year:
		var best := _best_target(plan, tried, rolls)
		if best.is_empty():
			break
		var target := str(best["regione"])
		tried[target] = true
		var moved := 0
		for entry in best["armate"]:
			var a: Army = entry
			if plan.record(GameCommands.order_move(plan.state, plan.id, a.id, PackedStringArray([target])), "attacco %d -> %s" % [a.id, target]):
				plan.commit(a, target)
				moved += 1
		if moved > 0:
			launches += 1


## Migliore bersaglio attuale {"regione", "armate", "rapporto", "score"} oppure {}.
static func _best_target(plan: AiPlan, tried: Dictionary, rolls: Dictionary) -> Dictionary:
	var ctx := plan.ctx
	var state := plan.state
	var raider := plan.profile == AiProfiles.RAIDER
	var spare_by_region := {}
	var region_order: Array[String] = []
	for item in ctx.land_armies_of(plan.id):
		var a: Army = item
		if spare_by_region.has(a.region):
			continue
		var list := spare(plan, a.region)
		spare_by_region[a.region] = list
		if not list.is_empty():
			region_order.append(a.region)
	var sources := {}
	var target_order: Array[String] = []
	for region_id in region_order:
		for n in ctx.land_neighbours.get(region_id, PackedStringArray()):
			if tried.has(n):
				continue
			if AiPolicy.attackable(plan, ctx.owner_of(n)) == "":
				continue
			if not sources.has(n):
				sources[n] = []
				target_order.append(n)
			var src: Array = sources[n]
			src.append(region_id)
	var best: Dictionary = {}
	var best_score := 0.0
	for n in target_order:
		if _treaty_army_present(plan, n):
			continue
		var owner_id := ctx.owner_of(n)
		var kind := AiPolicy.attackable(plan, owner_id)
		var armies: Array[Army] = []
		for src_region in sources[n]:
			armies.append_array(spare_by_region[src_region])
		var attack_force := AiForce.sum_force(ctx, armies)
		var defence := AiForce.defenders(ctx, n, plan.id, plan.betray)
		var r := AiForce.ratio(attack_force, float(defence["totale"]))
		if r < AiPolicy.threshold_for(plan, kind):
			continue
		var region := state.campaign.region(n)
		var value := float(region.income) + 50.0 * float(Combat.castle_level(state, n)) + 100.0
		var score := value if raider else value * minf(r, 4.0)
		if score <= best_score:
			continue
		if kind == AiPolicy.KIND_NEUTRAL:
			if not rolls.has(owner_id):
				rolls[owner_id] = plan.rng.randf() < plan.aggression
			if not bool(rolls[owner_id]):
				continue
		best = {"regione": n, "armate": armies, "rapporto": r, "score": score}
		best_score = score
	return best


## Vero se nella regione sta un esercito di una fazione con cui c'e' una tregua (attaccarla romperebbe il trattato).
static func _treaty_army_present(plan: AiPlan, region_id: String) -> bool:
	for item in plan.ctx.armies_at(region_id):
		var a: Army = item
		if a.faction != plan.id and plan.state.relation(plan.id, a.faction) == GameState.REL_TRUCE:
			return true
	return false


# --- concentrazione ---------------------------------------------------------------------------------------------


## Gli eserciti liberi nelle province interne (senza fronte) si avvicinano alla provincia di frontiera piu' vicina entro
## `raggio_rinforzi` + 1 passi, cosi' da poter attaccare e difendere insieme.
static func _concentrate(plan: AiPlan) -> void:
	var radius := plan.rules.reinforce_radius + 1
	for p in plan.provinces:
		var t: Dictionary = plan.threat.get(p.id, {})
		if bool(t.get("fronte", false)) or float(t.get("nemica", 0.0)) > 0.0:
			continue
		var movers := spare(plan, p.id)
		if movers.is_empty():
			continue
		var search := _own_bfs(plan, p.id, radius)
		var goal := ""
		for region_id in search["ordine"]:
			var tt: Dictionary = plan.threat.get(region_id, {})
			if bool(tt.get("fronte", false)):
				goal = region_id
				break
		if goal == "":
			continue
		var parent: Dictionary = search["padre"]
		var path := _path_toward_goal(parent, goal, p.id)
		for a in movers:
			if plan.record(GameCommands.order_move(plan.state, plan.id, a.id, path), "concentrazione %d -> %s" % [a.id, goal]):
				plan.commit(a, goal)


## Percorso da `start` (radice della ricerca) fino a `goal`.
static func _path_toward_goal(parent: Dictionary, goal: String, start: String) -> PackedStringArray:
	var reversed := PackedStringArray()
	var current := goal
	var guard := 0
	while current != start and guard < 64:
		guard += 1
		reversed.append(current)
		current = str(parent.get(current, start))
	var path := PackedStringArray()
	for i in range(reversed.size() - 1, -1, -1):
		path.append(reversed[i])
	return path
