extends RefCounted
## Riaddestramento dell'IA: prima del reclutamento la fazione riporta all'organico pieno le pile sotto `soglia_ia` (0,7) degli
## eserciti di terra fermi nelle sue province, entro il budget del reclutamento. Mondo: ai_world.gd (lancieri: 100 uomini, 100
## denari; il riaddestramento e' spento da `quiet_rules` e qui si riaccende con `allow_retraining`).

const W := preload("res://tests/unit/ai_world.gd")


## Mondo senza eserciti di partenza, con il riaddestramento acceso e ALPHA con 5000 denari.
func _world() -> GameState:
	var s := W.world()
	W.allow_retraining(s)
	W.clear_armies(s)
	W.set_treasury(s, W.A, 5000)
	return s


func test_la_soglia_predefinita(t: TestContext) -> void:
	t.assert_eq(AiRules.new().retrain_threshold, 0.7)
	t.assert_eq(AiRules.load_file(AiRules.DEFAULT_PATH).retrain_threshold, 0.7, "ia.cfg [riaddestramento] soglia_ia")
	t.assert_true(AiRules.new().to_dict().has("retrain_threshold"))


func test_riaddestra_solo_le_pile_sotto_soglia(t: TestContext) -> void:
	var s := _world()
	var weak := W.put(s, W.A, W.A2, 50)          # 0,5: si riaddestra
	W.put(s, W.A, W.A3, 80)                       # 0,8: no
	var edge := W.put(s, W.A, W.A1, 70)          # 0,7 esatto: non e' sotto la soglia
	var start := s.faction(W.A).treasury
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	var spent := AiEconomy.plan_retraining(plan, 1000.0)
	t.assert_eq(spent, 50, "100 x 50 / 100")
	t.assert_eq(s.retrain_orders.size(), 1)
	t.assert_eq(int(s.retrain_orders[0]["esercito"]), weak.id)
	t.assert_eq(RetrainProcessor.orders_of(s, edge.id).size(), 0)
	t.assert_eq(s.faction(W.A).treasury, start - 50)
	t.assert_eq(plan.ctx.rejected, 0, "nessun rifiuto: %s" % str(plan.ctx.rejections))
	TurnProcessor.end_year(s)
	t.assert_eq(weak.stacks[0].men, 100)


func test_resta_nel_budget_e_prosegue_con_le_pile_meno_costose(t: TestContext) -> void:
	var s := _world()
	var army := W.put(s, W.A, W.A2, 40)
	army.stacks.append(UnitStack.new("Spearmen", 50, 0))
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	# la pila piu' decimata (60 denari) non ci sta: si prende l'altra (50)
	var spent := AiEconomy.plan_retraining(plan, 55.0)
	t.assert_eq(spent, 50)
	t.assert_eq(s.retrain_orders.size(), 1)
	t.assert_eq(int(s.retrain_orders[0]["pila"]), 1)
	t.assert_eq(plan.ctx.rejected, 0)
	# budget zero o negativo: niente
	var s2 := _world()
	W.put(s2, W.A, W.A2, 40)
	t.assert_eq(AiEconomy.plan_retraining(W.plan_for(s2, W.A, "CATHOLIC_EXPANSIONIST"), 0.0), 0)
	t.assert_true(s2.retrain_orders.is_empty())


func test_prima_la_pila_piu_decimata(t: TestContext) -> void:
	var s := _world()
	var army := W.put(s, W.A, W.A2, 60)
	army.stacks.append(UnitStack.new("Spearmen", 20, 0))
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	AiEconomy.plan_retraining(plan, 90.0)
	t.assert_eq(s.retrain_orders.size(), 1, "con 90 denari ce ne sta una sola (80 + 40 = 120)")
	t.assert_eq(int(s.retrain_orders[0]["pila"]), 1, "la pila da 20 uomini")


func test_rispetta_il_limite_per_provincia(t: TestContext) -> void:
	var s := _world()
	var army := W.put(s, W.A, W.A2, 10)
	for i in 5:
		army.stacks.append(UnitStack.new("Spearmen", 10, 0))
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	AiEconomy.plan_retraining(plan, 100000.0)
	t.assert_eq(s.retrain_orders.size(), s.rules.retrain.max_per_province, "al massimo 4 pile per provincia")
	t.assert_eq(plan.ctx.rejected, 0, "il limite non genera rifiuti")


func test_non_riaddestra_mercenari_ordini_militari_ed_eserciti_in_marcia(t: TestContext) -> void:
	var s := _world()
	var moving := W.put(s, W.A, W.A3, 10)
	moving.path = PackedStringArray([W.A2])
	var plan2 := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	AiEconomy.plan_retraining(plan2, 1000.0)
	t.assert_eq(RetrainProcessor.orders_of(s, moving.id).size(), 0, "esercito in marcia: no")
	t.assert_eq(plan2.ctx.rejected, 0)


func test_spento_con_limite_zero_o_soglia_zero(t: TestContext) -> void:
	var s := _world()
	W.put(s, W.A, W.A2, 10)
	s.rules.retrain.max_per_province = 0
	t.assert_eq(AiEconomy.plan_retraining(W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST"), 1000.0), 0, "limite 0")
	W.allow_retraining(s)
	var r := W.quiet_ai_rules()
	r.retrain_threshold = 0.0
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST", W.context(s, r))
	t.assert_eq(AiEconomy.plan_retraining(plan, 1000.0), 0, "soglia 0")
	t.assert_true(s.retrain_orders.is_empty())


func test_il_costo_rientra_nel_budget_del_reclutamento(t: TestContext) -> void:
	var s := W.world()
	W.allow_retraining(s)
	W.enrich(s, W.A)
	W.set_treasury(s, W.A, 3000)
	var weak := W.land_army(s, W.A, W.A3)       # 60 uomini su 100
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	var start := s.faction(W.A).treasury
	var spent := AiEconomy.plan_recruitment(plan)
	t.assert_eq(RetrainProcessor.orders_of(s, weak.id).size(), 1, "la pila di A3 e' stata riaddestrata prima di reclutare")
	t.assert_true(spent >= 40, "la spesa comprende i 40 denari del riaddestramento")
	t.assert_eq(start - s.faction(W.A).treasury, spent, "il tesoro scende della spesa totale")
	t.assert_eq(plan.ctx.rejected, 0, "nessun rifiuto: %s" % str(plan.ctx.rejections))
	var budget := plan.num("quota_truppe") * float(plan.income)
	if not AiEconomy.is_rich(plan):
		t.assert_true(float(spent) <= budget + 0.5, "speso %d, budget %d" % [spent, int(budget)])


func test_un_anno_intero_senza_rifiuti_di_riaddestramento_e_deterministico(t: TestContext) -> void:
	var texts: Array[String] = []
	for i in 2:
		var s := W.world()
		W.allow_retraining(s)
		W.enrich(s, W.A)
		W.set_treasury(s, W.A, 4000)
		var ctx := W.run_faction(s, W.A)
		for line in ctx.rejections:
			t.assert_false(line.contains("riaddestra"), "rifiuto di un ordine di riaddestramento: %s" % line)
		texts.append(W.footprint(s) + str(s.retrain_orders))
	t.assert_eq(texts[0], texts[1], "stesso stato, stessi ordini")
