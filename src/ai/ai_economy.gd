class_name AiEconomy
extends RefCounted
## Economia dell'IA (fase 7a): tasse, costruzioni, reclutamento. Tutto passa dai comandi di `GameCommands`
## (`set_tax`, `can_queue_building`/`queue_building`, `can_queue_unit`/`queue_unit`) e se ne controlla l'esito.
## Regole PROVVISORIE (parametri in `data/regole/ia.cfg`); i PESI per profilo vengono dai file del gioco.

## Cache delle unita' reclutabili in una provincia: chiave (tabella, fazione, provincia, epoca, edifici) -> elenco di UnitType.
## Funzione pura della chiave, quindi valida anche tra partite diverse.
static var _option_cache := {}


## Ordine di preferenza: punteggio ("score") decrescente, a parita' "k" crescente (deterministico).
static func before(x: Dictionary, y: Dictionary) -> bool:
	var sx := float(x["score"])
	var sy := float(y["score"])
	return sx > sy or (sx == sy and int(x["k"]) < int(y["k"]))


# --- tasse -----------------------------------------------------------------------------------------------


## Tassa di ogni provincia: normale; alta (fino a `tassa_max` del profilo) se la lealta' prevista resta di `margine_alta` punti
## sopra la soglia di rivolta; bassa o minima nelle province vicine alla rivolta; una fazione ricca la abbassa di un livello
## (migliora la lealta' e spende il tesoro in eccesso). Il livello previsto usa l'ultimo calcolo della lealta'
## (`ProvinceState.last_loyalty`): somma senza il termine della tassa piu' il termine del livello.
static func plan_taxes(plan: AiPlan) -> void:
	var state := plan.state
	var pr := state.rules.province
	var normal := state.rules.default_tax
	var max_level := clampi(roundi(plan.num("tassa_max")), 0, state.rules.tax_multipliers.size() - 1)
	var threshold := pr.revolt_threshold
	var rich := is_rich(plan)
	for p in plan.provinces:
		var terms: Dictionary = p.last_loyalty
		if terms.is_empty():
			continue
		var base_sum := int(terms.get("somma", 0)) - int(terms.get("tassa", 0))
		var level := normal
		var current := p.loyalty
		var low_margin := threshold + plan.rules.tax_margin_low
		var high_margin := threshold + plan.rules.tax_margin_high
		if current < low_margin or _predicted(pr, base_sum, normal) < low_margin:
			level = normal - 1
			if current < threshold - 15 or _predicted(pr, base_sum, normal - 1) < threshold:
				level = normal - 2
		else:
			for candidate in range(state.rules.tax_multipliers.size() - 1, normal, -1):
				if candidate <= max_level and current >= low_margin and _predicted(pr, base_sum, candidate) >= high_margin:
					level = candidate
					break
		if rich and level > normal - 1:
			level -= 1
		level = clampi(mini(level, max_level), 0, state.rules.tax_multipliers.size() - 1)
		if level != p.tax_level:
			plan.record(GameCommands.set_tax(state, plan.id, p.id, level), "tassa %s %d" % [p.id, level])


static func _predicted(pr: ProvinceRules, base_sum: int, level: int) -> int:
	return clampi(base_sum + pr.tax_term(clampi(level, 0, pr.tax_terms.size() - 1)), 0, pr.max_loyalty)


## Fazione ricca: tesoro oltre la riserva piu' `anni_tesoro_alto` anni di reddito.
static func is_rich(plan: AiPlan) -> bool:
	return plan.income > 0 and float(plan.faction.treasury) > float(plan.reserve) + plan.rules.rich_years * float(plan.income)


# --- costruzioni -----------------------------------------------------------------------------------------


## Per ogni provincia con la coda di costruzione vuota, il prossimo livello col punteggio piu' alto:
##   (peso della colonna 9 per il profilo + influenze della colonna 10 + bisogni) x (1 + rumore) / (1 + costo / scala + anni / scala)
## Un edificio con peso zero per il profilo non si costruisce mai (le influenze non lo resuscitano); i bisogni sono il castello
## nelle province minacciate o capitali, la felicita' nelle province vicine alla rivolta, la rendita, il commercio nei porti e,
## per i profili navali, porto e cantiere. Si spende al massimo `quota_costruzioni` del tesoro oltre la riserva, al massimo
## `max_per_anno` costruzioni, scegliendo prima il punteggio migliore.
static func plan_buildings(plan: AiPlan) -> void:
	var state := plan.state
	var budget_scale := float(plan.ctx.diff.get("budget", 1.0))
	var available := int(float(plan.faction.treasury - plan.reserve) * clampf(plan.num("quota_costruzioni") * budget_scale, 0.0, 1.0))
	if available <= 0:
		return
	var candidates: Array[Dictionary] = []
	for i in plan.provinces.size():
		var p := plan.provinces[i]
		if not p.building_queue.is_empty():
			continue
		var option := _best_building(plan, p, available)
		if not option.is_empty():
			option["i"] = i
			option["k"] = i
			candidates.append(option)
	candidates.sort_custom(before)
	var built := 0
	for c in candidates:
		if built >= plan.rules.build_max_per_year:
			break
		var cost := int(c["costo"])
		if cost > available:
			continue
		var p2: ProvinceState = plan.provinces[int(c["i"])]
		var family_id := str(c["famiglia"])
		if plan.record(GameCommands.queue_building(state, plan.id, p2.id, family_id), "costruzione %s %s" % [p2.id, family_id]):
			available -= cost
			built += 1


## Migliore costruzione ammessa di una provincia entro `available` fiorini: {"famiglia", "costo", "score"} oppure {}.
static func _best_building(plan: AiPlan, p: ProvinceState, available: int) -> Dictionary:
	var state := plan.state
	var region := state.campaign.region(p.id)
	if region == null:
		return {}
	var scored: Array[Dictionary] = []
	for k in state.buildings.families.size():
		var family: BuildingType = state.buildings.families[k]
		var lv := family.get_level(p.level_of(family.id) + 1)
		if lv == null or not lv.allows_faction(plan.id):
			continue
		var price := state.rules.traits.building_cost(plan.id, lv)   # ADR-089: tratti della fazione
		if price > available:
			continue
		var score := building_score(plan, p, region, family, lv)
		if score >= plan.rules.build_min_score:
			scored.append({"famiglia": family.id, "score": score, "k": k, "costo": price})
	if scored.is_empty():
		return {}
	scored.sort_custom(before)
	var checked := 0
	for s in scored:
		if checked >= 6:
			break
		checked += 1
		if bool(GameCommands.can_queue_building(state, plan.id, p.id, str(s["famiglia"]))["ok"]):
			return s
	return {}


## Punteggio di un livello di edificio per la fazione (0 se il profilo non lo vuole). Estratto per i test.
static func building_score(plan: AiPlan, p: ProvinceState, region: CampaignData.Region, family: BuildingType, lv: BuildingType.Level) -> float:
	var r := plan.rules
	var weight := lv.ai_weight(plan.profile, -1.0)
	if weight < 0.0:
		weight = r.neutral_weight
	var pr := plan.state.rules.province
	var numerator := 0.0
	if weight > 0.0:
		numerator = weight
		for inf in lv.ai_influences:
			if p.level_of(str(inf["family"])) >= int(inf["level"]):
				numerator += float(inf["bonus"])
	var t: Dictionary = plan.threat.get(p.id, {})
	if family.id == plan.state.rules.combat.castle_family:
		if float(t.get("nemica", 0.0)) > 0.0:
			numerator += r.need_castle
		elif bool(t.get("fronte", false)):
			numerator += r.need_castle * 0.4
		if bool(t.get("capitale", false)):
			numerator += r.need_castle * 0.3
	if lv.happiness > 0 and p.loyalty < pr.revolt_threshold + 15:
		numerator += r.need_loyalty * float(lv.happiness)
	if lv.income > 0:
		numerator += r.need_income * float(lv.income)
	var has_goods := not region.trade_goods.is_empty() or not p.extra_goods.is_empty()
	var goods_factor := r.trade_building_priority if has_goods else 1.0   # ADR-053: costa con merci = rotte che rendono
	if plan.state.rules.trade_families.has(family.id) and region.has_port and p.level_of(plan.state.rules.port_family) > 0:
		numerator += r.need_trade * goods_factor
	if has_goods and region.has_port and family.id == plan.state.rules.port_family and plan.state.rules.sea_trade:
		numerator += r.need_trade * (goods_factor - 1.0)   # PROVVISORIA (ADR-053): il porto apre il commercio marittimo
	if plan.flag("navale") and region.has_port and (family.id == plan.state.rules.port_family or family.has_type("SHIP_PRODUCER")):
		numerator += r.need_port
	if numerator <= 0.0:
		return 0.0
	var noise := 1.0 + (plan.rng.randf() * 2.0 - 1.0) * r.build_noise
	var divisor := 1.0 + float(lv.cost) / r.build_cost_scale + float(maxi(1, lv.build_time)) / r.build_time_scale
	return numerator * noise / divisor


# --- congedo ---------------------------------------------------------------------------------------------


## Congedo (PROVVISORIO, `[congedo]` di ia.cfg; ADR-031): solo con il tesoro sotto zero e il mantenimento oltre il reddito.
## Scioglie con `GameCommands.disband_stacks` al massimo `max_per_anno` pile di terra, finche' il mantenimento rientra nel
## reddito: prima i mercenari, poi le piu' care da mantenere. Restano fuori gli eserciti non liberi (in marcia, assediati,
## assedianti, crociati), le province minacciate e l'ultima pila della fazione in una provincia. Restituisce le pile congedate.
static func plan_disband(plan: AiPlan) -> int:
	var state := plan.state
	if plan.rules.disband_per_year <= 0 or plan.faction.treasury >= 0 or plan.upkeep <= plan.income:
		return 0
	var factor := state.rules.upkeep_multiplier
	var merc_factor := state.rules.mercenaries.upkeep_factor
	var done := 0
	while done < plan.rules.disband_per_year and plan.upkeep > plan.income:
		var left := {}   # provincia -> pile di terra della fazione
		for item in plan.ctx.land_armies_of(plan.id):
			var mine: Army = item
			if state.army(mine.id) != null:
				left[mine.region] = int(left.get(mine.region, 0)) + mine.stacks.size()
		var best := {}
		for item in plan.ctx.land_armies_of(plan.id):
			var a: Army = item
			if state.army(a.id) == null or not plan.is_free(a) or int(left.get(a.region, 0)) <= 1:
				continue
			var t: Dictionary = plan.threat.get(a.region, {})
			if t.is_empty() or float(t.get("nemica", 0.0)) > 0.0 or bool(t.get("assedio", false)):
				continue   # fuori dalle proprie province o sotto minaccia: non si scioglie nulla
			for i in a.stacks.size():
				var st := a.stacks[i]
				var unit := state.units.get_unit(st.unit_id)
				var cost := float(unit.support_cost) if unit != null else 0.0
				if st.mercenary:
					cost *= merc_factor
				var score := cost + (1000000.0 if st.mercenary else 0.0)
				var entry := {"score": score, "k": a.id * 100 + i, "esercito": a.id, "pila": i, "costo": cost}
				if best.is_empty() or before(entry, best):
					best = entry
		if best.is_empty():
			break
		var r := GameCommands.disband_stacks(state, plan.id, int(best["esercito"]), PackedInt32Array([int(best["pila"])]))
		if not plan.record(r, "congeda %d/%d" % [int(best["esercito"]), int(best["pila"])]):
			break
		plan.upkeep -= roundi(float(best["costo"]) * factor)
		done += 1
	return done


# --- reclutamento ----------------------------------------------------------------------------------------


## Reclutamento di terra: budget annuo = `quota_truppe` x reddito (piu' un quarto dell'eccesso se la fazione e' ricca) entro il
## tesoro oltre meta' della riserva (nessuna riserva in difesa disperata); mantenimento totale (con le reclute in coda) entro
## `tetto_mantenimento` x reddito. Le province minacciate vengono prima (minaccia / forza propria), poi la capitale se ha
## meno uomini del minimo, poi le province di frontiera, poi le altre. Unita' scelte con i pesi della colonna 14 per il profilo
## tra quelle reclutabili nella provincia (edifici richiesti, cultura, regione, epoca), con un po' di rumore.
## Restituisce i fiorini spesi.
static func plan_recruitment(plan: AiPlan) -> int:
	var state := plan.state
	var quota := plan.num("quota_truppe")
	if quota <= 0.0 or plan.income <= 0:
		return 0
	var budget := quota * float(plan.income) * float(plan.ctx.diff.get("budget", 1.0))
	var cap_ratio := plan.num("tetto_mantenimento")
	if is_rich(plan):
		var excess := float(plan.faction.treasury) - float(plan.reserve) - plan.rules.rich_years * float(plan.income)
		budget += plan.rules.rich_spend * excess
		cap_ratio = maxf(cap_ratio, plan.rules.rich_upkeep_cap)
	var floor_reserve := 0.0 if plan.profile == AiProfiles.DESPERATE else float(plan.reserve) * 0.5
	budget = minf(budget, float(plan.faction.treasury) - floor_reserve)
	var support_room := cap_ratio * float(plan.income) - float(plan.upkeep)
	# tetto delle pile di terra (PROVVISORIA, ia.cfg): eserciti e reclute gia' in coda
	var stack_room := plan.rules.stacks_base + roundi(plan.rules.stacks_per_province * float(plan.provinces.size())) - _land_stacks(plan)
	# prima delle reclute nuove: le pile decimate tornano all'organico pieno (costo dentro lo stesso budget)
	var spent := plan_retraining(plan, budget)
	# fase 8d: nelle province minacciate i mercenari arrivano subito (costano di piu', dentro lo stesso budget)
	var hired := plan_mercenaries(plan, budget - float(spent), support_room, stack_room)
	spent += int(hired["costo"])
	support_room -= float(hired["mantenimento"])
	stack_room -= int(hired["pile"])
	var order: Array[Dictionary] = []
	for i in plan.provinces.size():
		var p := plan.provinces[i]
		if p.unit_queue.size() >= plan.rules.recruit_queue_max:
			continue
		order.append({"i": i, "k": i, "score": _recruit_priority(plan, p)})
	order.sort_custom(before)
	var multiplier := state.rules.upkeep_multiplier
	for entry in order:
		var province: ProvinceState = plan.provinces[int(entry["i"])]
		var added := 0
		while added < plan.rules.recruit_per_province and budget - float(spent) > 0.0 and support_room > 0.0 and stack_room > 0:
			var unit := pick_unit(plan, province, budget - float(spent), support_room, false)
			if unit == null:
				break
			if not bool(GameCommands.can_queue_unit(state, plan.id, province.id, unit.id)["ok"]):
				break
			if not plan.record(GameCommands.queue_unit(state, plan.id, province.id, unit.id), "recluta %s %s" % [province.id, unit.id]):
				break
			spent += state.rules.traits.unit_cost(plan.id, unit)   # ADR-089
			var unit_upkeep := float(unit.support_cost) * multiplier * state.rules.traits.upkeep_factor(plan.id, unit)
			support_room -= unit_upkeep
			plan.upkeep += roundi(unit_upkeep)
			if not unit.is_ship():
				stack_room -= 1
			added += 1
	return spent


## Mercenari (PROVVISORIO, `[mercenari]` di ia.cfg): nelle province proprie minacciate da forze nemiche (le piu' minacciate prima)
## assolda le compagnie presenti con GameCommands.hire_mercenary, al massimo `max_per_anno`, finche' costo (`budget`), mantenimento
## (`support_room`) e tetto delle pile (`stack_room`) lo permettono. Restituisce {"costo", "mantenimento", "pile"}.
static func plan_mercenaries(plan: AiPlan, budget: float, support_room: float, stack_room: int) -> Dictionary:
	var state := plan.state
	var out := {"costo": 0, "mantenimento": 0.0, "pile": 0}
	if plan.rules.merc_per_year <= 0 or budget <= 0.0 or state.mercenaries.is_empty():
		return out
	var targets: Array[Dictionary] = []
	var k := 0
	for p in plan.provinces:
		if not state.mercenaries.has(p.id):
			continue
		var priority := _recruit_priority(plan, p)
		if priority < 1000.0:   # solo dove ci sono forze nemiche
			continue
		targets.append({"id": p.id, "score": priority, "k": k})
		k += 1
	targets.sort_custom(before)
	var factor := state.rules.mercenaries.upkeep_factor * state.rules.upkeep_multiplier
	var hired := 0
	for t in targets:
		var pid := str(t["id"])
		var i := 0
		while hired < plan.rules.merc_per_year and i < (state.mercenaries.get(pid, []) as Array).size():
			var company: Dictionary = state.mercenaries[pid][i]
			var unit := state.units.get_unit(str(company.get("unita", "")))
			var cost := state.rules.mercenaries.hire_cost(unit.cost) if unit != null else 0
			var upkeep := float(unit.support_cost) * factor if unit != null else 0.0
			if unit == null or float(int(out["costo"]) + cost) > budget or upkeep > support_room - float(out["mantenimento"]) or int(out["pile"]) >= stack_room:
				i += 1
				continue
			if not plan.record(GameCommands.hire_mercenary(state, plan.id, pid, i), "mercenari %s %s" % [pid, unit.id]):
				i += 1
				continue
			out["costo"] = int(out["costo"]) + cost
			out["mantenimento"] = float(out["mantenimento"]) + upkeep
			out["pile"] = int(out["pile"]) + 1
			plan.upkeep += roundi(upkeep)
			hired += 1
	return out


## Riaddestramento (PROVVISORIO, `[riaddestramento]` di ia.cfg): le pile con meno di `soglia_ia` dell'organico pieno degli eserciti
## di terra fermi nelle province della fazione (`GameCommands.retrain_options`: niente assedio, mercenari, ordini militari) si
## riaddestrano con `GameCommands.order_retrain`, nell'ordine di priorita' del reclutamento (province minacciate prima) e poi della
## pila piu' decimata, finche' il costo sta nel `budget` del reclutamento. Restituisce i fiorini spesi (da contare nel budget).
static func plan_retraining(plan: AiPlan, budget: float) -> int:
	var state := plan.state
	var threshold := plan.rules.retrain_threshold
	if threshold <= 0.0 or budget <= 0.0 or state.rules.retrain.max_per_province <= 0:
		return 0
	var candidates: Array[Dictionary] = []
	var k := 0
	for item in plan.ctx.land_armies_of(plan.id):
		var a: Army = item
		var options := GameCommands.retrain_options(state, plan.id, a.id)
		if not bool(options["ok"]):
			continue
		var province := state.province(a.region)
		var priority := _recruit_priority(plan, province)
		var piles: Array = options["pile"]
		for entry in piles:
			var e: Dictionary = entry
			if not bool(e["si_puo"]) or int(e["pieni"]) <= 0:
				continue
			var fraction := float(int(e["uomini"])) / float(int(e["pieni"]))
			if fraction >= threshold:
				continue
			candidates.append({"army": a.id, "indice": int(e["indice"]), "costo": int(e["costo"]), "score": priority + (1.0 - fraction), "k": k})
			k += 1
	candidates.sort_custom(before)
	var spent := 0
	for c in candidates:
		var cost := int(c["costo"])
		if float(spent + cost) > budget:
			continue
		var army: Army = state.army(int(c["army"]))
		if army == null or RetrainProcessor.orders_in(state, army.region) >= state.rules.retrain.max_per_province:
			continue
		var result := GameCommands.order_retrain(state, plan.id, army.id, PackedInt32Array([int(c["indice"])]))
		if plan.record(result, "riaddestra %s esercito %d pila %d" % [army.region, army.id, int(c["indice"])]):
			spent += int(result["costo"])
	return spent


## Pile di terra della fazione, contate in pile piene equivalenti (uomini / uomini base dell'unita'): pile decimate da
## battaglie o peste contano meno, cosi' la fazione puo' rimpiazzarle. Piu' le truppe in coda (non navi, non agenti).
static func _land_stacks(plan: AiPlan) -> int:
	var equivalent := 0.0
	for item in plan.ctx.land_armies_of(plan.id):
		var a: Army = item
		for st in a.stacks:
			var base := plan.state.units.get_unit(st.unit_id)
			var full := maxi(1, base.men if base != null else st.men)
			equivalent += minf(1.0, float(st.men) / float(full))
	var total := ceili(equivalent)
	for p in plan.provinces:
		for q in p.unit_queue:
			var u := plan.state.units.get_unit(q.key)
			if u != null and u.is_military() and not u.is_ship():
				total += 1
	return total


## Priorita' di una provincia nel reclutamento: minacciata (1000 + minaccia / forza propria), capitale scoperta (800), fronte (300),
## altre (100).
static func _recruit_priority(plan: AiPlan, p: ProvinceState) -> float:
	var t: Dictionary = plan.threat.get(p.id, {})
	var enemy := float(t.get("nemica", 0.0))
	if enemy > 0.0:
		return 1000.0 + 10.0 * enemy / (float(t.get("propria", 0.0)) + 1.0)
	if bool(t.get("capitale", false)) and _men_in(plan, p.id) < plan.rules.capital_min_men:
		return 800.0
	if bool(t.get("fronte", false)):
		return 300.0
	return 100.0


static func _men_in(plan: AiPlan, region_id: String) -> int:
	var total := 0
	for item in plan.ctx.armies_at(region_id):
		var a: Army = item
		if a.faction == plan.id:
			total += a.men_total()
	return total


## Unita' scelta per la provincia: quella col punteggio piu' alto (peso x rumore) tra le reclutabili entro budget e mantenimento;
## null se non ce n'e'. `ships` sceglie tra le navi invece che tra le truppe di terra.
static func pick_unit(plan: AiPlan, p: ProvinceState, budget: float, support_room: float, ships: bool) -> UnitType:
	var best: UnitType = null
	var best_score := 0.0
	var multiplier := plan.state.rules.upkeep_multiplier
	var traits := plan.state.rules.traits   # ADR-089
	for u in recruit_options(plan, p, ships):
		if float(traits.unit_cost(plan.id, u)) > budget or float(u.support_cost) * multiplier * traits.upkeep_factor(plan.id, u) > support_room:
			continue
		var w := u.ai_weight(plan.profile, -1.0)
		if w < 0.0:
			w = plan.rules.neutral_weight
		if w <= 0.0:
			continue
		var score := w * (1.0 + (plan.rng.randf() * 2.0 - 1.0) * plan.rules.recruit_noise)
		if score > best_score:
			best_score = score
			best = u
	return best


## Unita' (truppe di terra o navi) che la fazione puo' reclutare nella provincia, senza guardare costo e mantenimento:
## fazione, epoca, regione, cultura, edifici richiesti, uomini. In ordine del file. Memorizzate (funzione di tabella, fazione,
## provincia, epoca ed edifici).
static func recruit_options(plan: AiPlan, p: ProvinceState, ships: bool) -> Array[UnitType]:
	var state := plan.state
	var key := "%d|%s|%s|%s|%s|%s" % [state.units.get_instance_id(), plan.id, p.id, state.era, "N" if ships else "T", str(p.buildings)]
	if _option_cache.has(key):
		var cached: Array = _option_cache[key]
		var again: Array[UnitType] = []
		for item in cached:
			again.append(item)
		return again
	var region := state.campaign.region(p.id)
	var out: Array[UnitType] = []
	if region != null and (not ships or region.has_port):
		var culture := GameCommands.culture_key(region.culture)
		var pool: Array[UnitType] = state.units.ships_for(plan.id) if ships else state.units.land_for(plan.id)
		for u in pool:
			if u.men <= 0 or not u.available_in_period(state.era) or not u.allows_region(region.id) or not u.allows_culture(culture):
				continue
			if GameCommands.requirements_met(u.requires, p, state.buildings):
				out.append(u)
	if _option_cache.size() > 6000:
		_option_cache.clear()
	_option_cache[key] = out
	return out
