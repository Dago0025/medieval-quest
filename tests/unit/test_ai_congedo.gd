extends RefCounted
## Congedo dell'IA (ADR-031, ia.cfg [congedo]): una fazione in debito e con il mantenimento oltre il reddito scioglie poche
## pile l'anno, prima i mercenari, poi le piu' care, mai l'ultima pila di una provincia ne' dove c'e' una minaccia.
## Mondo: ai_world.gd (A3 di ALPHA confina con B1 di BETA).

const W := preload("res://tests/unit/ai_world.gd")


func _world() -> GameState:
	var s := W.world()
	W.clear_armies(s)
	return s


## Riempie A1 di cavalieri finche' il mantenimento supera il reddito; restituisce l'esercito.
func _too_many_knights(s: GameState) -> Army:
	var a := W.put(s, W.A, W.A1, 40, "Knights")
	for i in 200:
		var plan := W.plan_for(s, W.A)
		if plan.upkeep > plan.income:
			break
		if a.stacks.size() >= s.rules.max_stacks:
			a = W.put(s, W.A, W.A1, 40, "Knights")
		else:
			a.stacks.append(UnitStack.new("Knights", 40, 0))
	return a


func _stacks(s: GameState, faction_id: String) -> int:
	var n := 0
	for a in s.armies_of(faction_id):
		n += a.stacks.size()
	return n


func _count(s: GameState, unit_id: String) -> int:
	var n := 0
	for a in s.armies_of(W.A):
		for st in a.stacks:
			if st.unit_id == unit_id:
				n += 1
	return n


func test_regola_predefinita(t: TestContext) -> void:
	t.assert_eq(AiRules.new().disband_per_year, 2)
	t.assert_eq(AiRules.load_file(AiRules.DEFAULT_PATH).disband_per_year, 2, "ia.cfg [congedo] max_per_anno")


func test_in_debito_e_in_perdita_congeda_al_massimo_due_pile(t: TestContext) -> void:
	var s := _world()
	_too_many_knights(s)
	W.set_treasury(s, W.A, -500)
	var before := _stacks(s, W.A)
	var plan := W.plan_for(s, W.A)
	t.assert_true(plan.upkeep > plan.income, "premessa: mantenimento %d oltre il reddito %d" % [plan.upkeep, plan.income])
	var upkeep_before := plan.upkeep
	var n := AiEconomy.plan_disband(plan)
	t.assert_true(n >= 1 and n <= 2, "pile congedate: %d" % n)
	t.assert_eq(_stacks(s, W.A), before - n)
	t.assert_true(plan.upkeep < upkeep_before, "il piano conta il mantenimento nuovo")
	t.assert_eq(plan.ctx.rejected, 0, str(plan.ctx.rejections))


func test_con_il_tesoro_positivo_o_i_conti_in_ordine_non_congeda(t: TestContext) -> void:
	var s := _world()
	_too_many_knights(s)
	W.set_treasury(s, W.A, 50)
	var before := _stacks(s, W.A)
	t.assert_eq(AiEconomy.plan_disband(W.plan_for(s, W.A)), 0, "in perdita ma senza debito")
	var calm := _world()
	W.put(calm, W.A, W.A1, 100)
	W.put(calm, W.A, W.A1, 100)
	W.set_treasury(calm, W.A, -500)
	t.assert_eq(AiEconomy.plan_disband(W.plan_for(calm, W.A)), 0, "in debito ma con il reddito oltre il mantenimento")
	t.assert_eq(_stacks(s, W.A), before)


func test_prima_i_mercenari_poi_le_pile_piu_care(t: TestContext) -> void:
	var s := _world()
	_too_many_knights(s)
	var cheap := W.put(s, W.A, W.A1, 100)
	cheap.stacks.append(UnitStack.new("Spearmen", 90, 0))
	cheap.stacks[1].mercenary = true
	W.set_treasury(s, W.A, -500)
	var rules := AiRules.default_rules()
	rules.disband_per_year = 1
	var plan := W.plan_for(s, W.A, "", W.context(s, rules))
	t.assert_eq(AiEconomy.plan_disband(plan), 1)
	t.assert_eq(cheap.stacks.size(), 1, "il mercenario e' il primo ad andarsene")
	t.assert_false(cheap.stacks[0].mercenary)
	var knights := _count(s, "Knights")
	var again := W.plan_for(s, W.A, "", W.context(s, rules))
	t.assert_true(again.upkeep > again.income, "premessa: ancora in perdita")
	t.assert_eq(AiEconomy.plan_disband(again), 1)
	t.assert_eq(_count(s, "Knights"), knights - 1, "poi un cavaliere (10 di mantenimento), non il lanciere (3)")
	t.assert_eq(cheap.stacks.size(), 1)


func test_non_lascia_vuota_una_provincia_ne_tocca_quelle_minacciate(t: TestContext) -> void:
	var s := _world()
	_too_many_knights(s)
	var lone := W.put(s, W.A, W.A2, 40, "Knights")
	var front := W.put(s, W.A, W.A3, 40, "Knights")
	front.stacks.append(UnitStack.new("Knights", 40, 0))
	s.declare_war(W.B, W.A)
	W.put(s, W.B, W.B1, 200)
	W.set_treasury(s, W.A, -500)
	var rules := AiRules.default_rules()
	rules.disband_per_year = 50
	var plan := W.plan_for(s, W.A, "", W.context(s, rules))
	AiEconomy.plan_disband(plan)
	t.assert_eq(lone.stacks.size(), 1, "l'unica pila di A2 resta")
	t.assert_eq(front.stacks.size(), 2, "A3 e' minacciata da B1: non si tocca")
	t.assert_true(W.men_in(s, W.A, W.A1) > 0, "anche ad A1 resta almeno una pila")
	t.assert_eq(plan.ctx.rejected, 0, str(plan.ctx.rejections))
