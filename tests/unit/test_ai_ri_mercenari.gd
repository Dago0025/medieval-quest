extends RefCounted
## Mercenari dell'IA (fase 8d, ia.cfg [mercenari]): la fazione assolda compagnie solo nelle province minacciate da forze nemiche,
## al massimo `max_per_anno`, entro il budget. Mondo: ai_world.gd (A3 di ALPHA confina con B1 di BETA).

const W := preload("res://tests/unit/ai_world.gd")


func _world() -> GameState:
	var s := W.world()
	W.clear_armies(s)
	W.set_treasury(s, W.A, 5000)
	s.units.get_unit("Spearmen").mercenary = true
	return s


func test_regola_predefinita(t: TestContext) -> void:
	t.assert_eq(AiRules.new().merc_per_year, 2)
	t.assert_eq(AiRules.load_file(AiRules.DEFAULT_PATH).merc_per_year, 2, "ia.cfg [mercenari] max_per_anno")


func test_assolda_solo_nelle_province_minacciate(t: TestContext) -> void:
	var s := _world()
	s.mercenaries[W.A1] = [{"unita": "Spearmen", "uomini": 100, "valore": 0, "anni": 0}]
	s.mercenaries[W.A3] = [{"unita": "Spearmen", "uomini": 100, "valore": 0, "anni": 0}, {"unita": "Spearmen", "uomini": 90, "valore": 0, "anni": 0},
		{"unita": "Spearmen", "uomini": 80, "valore": 0, "anni": 0}]
	# senza nemici nessun ingaggio
	var calm := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	t.assert_eq(int(AiEconomy.plan_mercenaries(calm, 1000.0, 1000.0, 10)["pile"]), 0, "in pace niente mercenari")
	s.declare_war(W.B, W.A)
	W.put(s, W.B, W.B1, 200)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	var before := s.faction(W.A).treasury
	var r := AiEconomy.plan_mercenaries(plan, 1000.0, 1000.0, 10)
	t.assert_eq(int(r["pile"]), 2, "al massimo 2 l'anno")
	t.assert_eq(int(r["costo"]), 300, "2 x 150")
	t.assert_eq(s.faction(W.A).treasury, before - 300)
	t.assert_eq((s.mercenaries[W.A3] as Array).size(), 1, "ne resta una ad A3")
	t.assert_eq((s.mercenaries[W.A1] as Array).size(), 1, "A1 non e' minacciata")
	t.assert_eq(plan.ctx.rejected, 0, str(plan.ctx.rejections))


func test_rispetta_il_budget(t: TestContext) -> void:
	var s := _world()
	s.declare_war(W.B, W.A)
	W.put(s, W.B, W.B1, 200)
	s.mercenaries[W.A3] = [{"unita": "Spearmen", "uomini": 100, "valore": 0, "anni": 0}]
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	t.assert_eq(int(AiEconomy.plan_mercenaries(plan, 100.0, 1000.0, 10)["pile"]), 0, "150 non sta in 100")
	t.assert_eq(int(AiEconomy.plan_mercenaries(plan, 1000.0, 1000.0, 0)["pile"]), 0, "nessun posto per pile nuove")
