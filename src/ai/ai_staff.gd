class_name AiStaff
extends RefCounted
## Comandanti, titoli e cariche dell'IA (fase 7a): il generale migliore (comando efficace) guida l'esercito piu' forte tra quelli che
## condividono la sua regione; i titoli di governatore vanno ai generali piu' leali nelle province piu' ricche ancora senza
## governatore. Ogni ordine passa da `GameCommands.set_commander` / `assign_title`. Regole PROVVISORIE.


static func plan(plan_data: AiPlan) -> void:
	var chars: Array = plan_data.ctx.chars_by_faction.get(plan_data.id, [])
	if chars.is_empty():
		return
	_commanders(plan_data, chars)
	_titles(plan_data, chars)
	_offices(plan_data, chars)


## Ultimo passo dell'anno: gli eserciti di terra fermi della fazione nella stessa regione (stessa posizione nel castello, non
## crociati) si riuniscono nel piu' grande finche' c'e' posto, con GameCommands.merge_armies. Pochi eserciti grandi invece di
## molti piccoli (e meno lavoro per l'IA). Si fa per ultimo perche' la fotografia dell'anno (AiContext) non vede le unioni.
static func consolidate(plan: AiPlan) -> void:
	var state := plan.state
	var by_key := {}
	var keys: Array[String] = []
	for a in state.armies_of(plan.id):
		if a.is_fleet or a.stacks.is_empty() or not a.path.is_empty() or a.is_crusade() or a.assault_ordered:
			continue
		var key := "%s|%s" % [a.region, str(a.in_castle)]
		if not by_key.has(key):
			by_key[key] = []
			keys.append(key)
		var list: Array = by_key[key]
		list.append(a)
	for key in keys:
		var group: Array = by_key[key]
		if group.size() < 2:
			continue
		group.sort_custom(func(x: Army, y: Army) -> bool: return x.stacks.size() > y.stacks.size() or (x.stacks.size() == y.stacks.size() and x.id < y.id))
		for i in range(1, group.size()):
			var small: Army = group[i]
			for j in i:
				var big: Army = group[j]
				if state.army(big.id) == null or state.army(small.id) == null:
					continue
				if StackMerge.size_after_join(state, big, small.stacks) <= state.rules.max_stacks:
					plan.record(GameCommands.merge_armies(state, plan.id, small.id, big.id), "unione %d -> %d" % [small.id, big.id])
					break


## Per ogni esercito, dal piu' forte, se nella stessa regione c'e' un personaggio (non il capo, maggiorenne, non gia' usato) con
## comando efficace maggiore di quello del comandante attuale, lo mette al comando (`set_commander` scambia i due eserciti se
## serve). Il capo non si sposta e non si sostituisce.
static func _commanders(plan: AiPlan, chars: Array) -> void:
	var ctx := plan.ctx
	var state := plan.state
	var by_region := {}
	var command := {}
	for item in chars:
		var c: Character = item
		if c.role == Character.ROLE_LEADER or not c.can_command(state.rules.dynasty, state.year):
			continue
		var region := ctx.char_region(c)
		if not by_region.has(region):
			by_region[region] = []
		var list: Array = by_region[region]
		list.append(c)
		command[c.id] = c.effective(Character.ATTR_COMMAND, state.rules, state.campaign)
	if by_region.is_empty():
		return
	var armies: Array[Dictionary] = []
	for item in ctx.land_armies_of(plan.id):
		var a: Army = item
		if by_region.has(a.region):
			armies.append({"a": a, "score": ctx.force(a), "k": a.id})
	armies.sort_custom(AiEconomy.before)
	var used := {}
	for entry in armies:
		var army: Army = entry["a"]
		var current := state.commander_of(army.id)
		var current_value := -1
		if current != null:
			if current.role == Character.ROLE_LEADER:
				continue
			current_value = current.effective(Character.ATTR_COMMAND, state.rules, state.campaign)
		var best: Character = null
		var best_value := current_value
		for item in by_region[army.region]:
			var c2: Character = item
			if used.has(c2.id) or c2 == current:
				continue
			var v := int(command[c2.id])
			if v > best_value:
				best = c2
				best_value = v
		if best == null:
			continue
		if plan.record(GameCommands.set_commander(state, plan.id, army.id, best.id), "comandante %d <- %d" % [army.id, best.id]):
			used[best.id] = true
			if current != null:
				used[current.id] = true


## Cariche di Stato vacanti (manuale p25), nell'ordine del file: al personaggio libero (non il capo, maggiorenne, senza carica)
## con piu' stelle di comando, a parita' l'id minore. Al massimo `cariche_per_anno` cariche. PROVVISORIA.
static func _offices(plan: AiPlan, chars: Array) -> void:
	var state := plan.state
	if plan.rules.offices_per_year <= 0:
		return
	var given := 0
	for o in DynastyProcessor.available_offices(state, plan.id):
		if given >= plan.rules.offices_per_year:
			break
		if DynastyProcessor.office_holder(state, plan.id, o.building) != null:
			continue
		var best: Character = null
		var best_stars := -1
		for item in chars:
			var c: Character = item
			if not c.alive or c.role == Character.ROLE_LEADER or c.office != "" or not c.can_command(state.rules.dynasty, state.year):
				continue
			var stars := c.stars(state.rules, state.campaign)
			if stars > best_stars or (stars == best_stars and best != null and c.id < best.id):
				best = c
				best_stars = stars
		if best == null:
			return
		if plan.record(GameCommands.assign_office(state, plan.id, best.id, o.building), "carica %s <- %d" % [o.building, best.id]):
			given += 1


## I generali senza titolo (non il capo, maggiorenni) con lealta' efficace almeno `lealta_min_titolo` governano le province senza
## governatore, dalla piu' ricca; il piu' leale per primo. Al massimo `titoli_per_anno` titoli.
static func _titles(plan: AiPlan, chars: Array) -> void:
	var ctx := plan.ctx
	var state := plan.state
	if plan.rules.titles_per_year <= 0:
		return
	var candidates: Array[Dictionary] = []
	for item in chars:
		var c: Character = item
		if c.role == Character.ROLE_LEADER or c.title != "" or not c.can_command(state.rules.dynasty, state.year):
			continue
		var loyalty := c.effective(Character.ATTR_LOYALTY, state.rules, state.campaign)
		if loyalty >= plan.rules.title_min_loyalty:
			candidates.append({"c": c, "score": float(loyalty), "k": c.id})
	if candidates.is_empty():
		return
	candidates.sort_custom(AiEconomy.before)
	var seats: Array[Dictionary] = []
	for i in plan.provinces.size():
		var p := plan.provinces[i]
		if not ctx.governors.has(p.id):
			seats.append({"p": p, "score": float(ctx.province_income.get(p.id, 0)), "k": i})
	seats.sort_custom(AiEconomy.before)
	var given := 0
	var next := 0
	for seat in seats:
		if given >= plan.rules.titles_per_year or next >= candidates.size():
			break
		var chosen: Character = candidates[next]["c"]
		var province: ProvinceState = seat["p"]
		if plan.record(GameCommands.assign_title(state, plan.id, chosen.id, province.id), "titolo %s <- %d" % [province.id, chosen.id]):
			ctx.governors[province.id] = chosen
			given += 1
		next += 1
