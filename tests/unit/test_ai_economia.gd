extends RefCounted
## Economia dell'IA (fase 7a): tasse, costruzioni entro la riserva, reclutamento entro budget e tetto di mantenimento, pesi per
## profilo dai file del gioco (qui tabelle di prova con pesi inventati). Mondo: ai_world.gd.

const W := preload("res://tests/unit/ai_world.gd")


# --- tasse -------------------------------------------------------------------------------------


func test_tasse_basse_nelle_province_vicine_alla_rivolta(t: TestContext) -> void:
	var s := W.world()
	var b1 := s.province(W.B1)
	var threshold := s.rules.province.revolt_threshold
	b1.loyalty = threshold - 30
	b1.last_loyalty = {"somma": threshold - 30, "tassa": 0, "obiettivo": threshold - 30}
	var plan := W.plan_for(s, W.B, "CATHOLIC_DEFENSIVE")
	AiEconomy.plan_taxes(plan)
	t.assert_true(b1.tax_level < s.rules.default_tax, "tassa abbassata: %d" % b1.tax_level)


func test_la_tassa_massima_del_profilo_si_rispetta(t: TestContext) -> void:
	var s := W.world()
	var b1 := s.province(W.B1)
	b1.loyalty = s.rules.province.max_loyalty
	b1.last_loyalty = {"somma": b1.loyalty, "tassa": 0, "obiettivo": b1.loyalty}
	var plan := W.plan_for(s, W.B, AiProfiles.DESPERATE)
	AiEconomy.plan_taxes(plan)
	t.assert_true(b1.tax_level <= 1, "difesa disperata: tassa al massimo 1, trovata %d" % b1.tax_level)


func test_senza_calcolo_della_lealta_le_tasse_non_cambiano(t: TestContext) -> void:
	var s := W.world()
	var before := s.province(W.A1).tax_level
	AiEconomy.plan_taxes(W.plan_for(s, W.A))
	t.assert_eq(s.province(W.A1).tax_level, before)


# --- costruzioni ---------------------------------------------------------------------------------


func test_costruisce_entro_la_riserva(t: TestContext) -> void:
	var s := W.world()
	W.set_treasury(s, W.A, 6000)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	var start := s.faction(W.A).treasury
	AiEconomy.plan_buildings(plan)
	t.assert_true(W.queued_buildings(s, W.A) > 0, "qualcosa in costruzione")
	t.assert_true(W.queued_buildings(s, W.A) <= plan.rules.build_max_per_year, "al massimo max_per_anno")
	t.assert_true(s.faction(W.A).treasury >= plan.reserve, "la riserva (%d) non si tocca: tesoro %d" % [plan.reserve, s.faction(W.A).treasury])
	var spent := start - s.faction(W.A).treasury
	var share := float(start - plan.reserve) * plan.num("quota_costruzioni")
	t.assert_true(float(spent) <= share + 0.5, "speso %d, quota %d" % [spent, int(share)])
	t.assert_eq(plan.ctx.rejected, 0, "nessun comando rifiutato: %s" % str(plan.ctx.rejections))


func test_non_costruisce_sotto_la_riserva(t: TestContext) -> void:
	var s := W.world()
	var plan0 := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	W.set_treasury(s, W.A, plan0.reserve)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	AiEconomy.plan_buildings(plan)
	t.assert_eq(W.queued_buildings(s, W.A), 0, "tesoro uguale alla riserva: nessuna costruzione")
	t.assert_eq(s.faction(W.A).treasury, plan.reserve)


func test_un_edificio_con_peso_zero_non_si_costruisce(t: TestContext) -> void:
	var s := W.world()
	W.set_treasury(s, W.A, 50000)
	var rules := W.quiet_ai_rules()
	rules.build_max_per_year = 20
	var ctx := W.context(s, rules)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST", ctx)
	var tavern := s.buildings.get_family("TAVERN")
	var region := s.campaign.region(W.A2)
	t.assert_eq(AiEconomy.building_score(plan, s.province(W.A2), region, tavern, tavern.get_level(1)), 0.0, "peso 0 anche con l'influenza del castello")
	AiEconomy.plan_buildings(plan)
	for p in s.provinces_of(W.A):
		for q in p.building_queue:
			t.assert_true(q.key != "TAVERN", "la taverna non si costruisce")


func test_i_pesi_del_profilo_cambiano_il_punteggio(t: TestContext) -> void:
	var s := W.world()
	W.set_treasury(s, W.A, 50000)
	var ctx := W.context(s, W.quiet_ai_rules())
	var poor := W.plan_for(s, W.A, AiProfiles.POVERTY, ctx)
	var normal := W.plan_for(s, W.A, "CATHOLIC_TRADER", ctx)
	var castle := s.buildings.get_family("CASTLE")
	var p := s.province(W.A2)
	var region := s.campaign.region(W.A2)
	var low := AiEconomy.building_score(poor, p, region, castle, castle.get_level(2))
	var high := AiEconomy.building_score(normal, p, region, castle, castle.get_level(2))
	t.assert_true(low < high, "castello: poverta' %f, commerciante %f" % [low, high])
	var farm := s.buildings.get_family("IMPROVED_FARMLAND")
	var farm_poor := AiEconomy.building_score(poor, p, region, farm, farm.get_level(1))
	var farm_normal := AiEconomy.building_score(normal, p, region, farm, farm.get_level(1))
	t.assert_true(farm_poor > farm_normal, "fattorie: la poverta' le vuole di piu' (%f > %f)" % [farm_poor, farm_normal])


# --- reclutamento ----------------------------------------------------------------------------------


func test_recluta_entro_il_budget(t: TestContext) -> void:
	var s := W.world()
	W.enrich(s, W.A)
	W.set_treasury(s, W.A, 3000)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	var start := s.faction(W.A).treasury
	var rich := AiEconomy.is_rich(plan)
	var spent := AiEconomy.plan_recruitment(plan)
	t.assert_true(spent > 0, "ha reclutato")
	t.assert_eq(start - s.faction(W.A).treasury, spent, "il tesoro scende della spesa")
	if not rich:
		var budget := plan.num("quota_truppe") * float(plan.income)
		t.assert_true(float(spent) <= budget + 0.5, "speso %d, budget %d" % [spent, int(budget)])
	t.assert_true(s.faction(W.A).treasury >= plan.reserve / 2, "meta' della riserva resta")
	t.assert_true(W.queued_units(s, W.A) <= 3 * plan.rules.recruit_queue_max)
	t.assert_eq(plan.ctx.rejected, 0, "nessun rifiuto: %s" % str(plan.ctx.rejections))


func test_non_supera_il_tetto_di_mantenimento(t: TestContext) -> void:
	var s := W.world()
	W.enrich(s, W.A)
	W.set_treasury(s, W.A, 3000)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	# mantenimento ben oltre il tetto (con il mantenimento basso dei dati servirebbero migliaia di pile: lo si fissa qui)
	plan.upkeep = plan.income * 2
	var spent := AiEconomy.plan_recruitment(plan)
	t.assert_eq(spent, 0, "oltre il tetto non si recluta")
	t.assert_eq(W.queued_units(s, W.A), 0)


func test_la_poverta_non_recluta(t: TestContext) -> void:
	var s := W.world()
	W.enrich(s, W.A)
	var plan := W.plan_for(s, W.A, AiProfiles.POVERTY)
	t.assert_eq(AiEconomy.plan_recruitment(plan), 0, "quota_truppe 0")


func test_i_pesi_scelgono_le_unita_per_profilo(t: TestContext) -> void:
	var s := W.world()
	var a2 := s.province(W.A2)
	a2.set_level("CASTLE", 3)
	a2.set_level("BOWYER", 1)
	var ctx := W.context(s, W.quiet_ai_rules())
	var expansionist := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST", ctx)
	var defensive := W.plan_for(s, W.A, "CATHOLIC_DEFENSIVE", ctx)
	var ids := PackedStringArray()
	for u in AiEconomy.recruit_options(expansionist, a2, false):
		ids.append(u.id)
	t.assert_true(ids.has("Spearmen") and ids.has("Archers") and ids.has("Knights"), "unita' reclutabili: %s" % str(ids))
	t.assert_false(ids.has("Galley"), "le navi non sono truppe di terra")
	t.assert_false(ids.has("Emissary"), "gli agenti non sono truppe")
	var first := AiEconomy.pick_unit(expansionist, a2, 100000.0, 100000.0, false)
	var second := AiEconomy.pick_unit(defensive, a2, 100000.0, 100000.0, false)
	t.assert_eq(first.id, "Knights", "l'espansionista vuole i cavalieri (peso 400)")
	t.assert_eq(second.id, "Archers", "il difensivo vuole gli arcieri (peso 400, cavalieri 0)")


func test_un_peso_zero_non_si_recluta_mai(t: TestContext) -> void:
	var s := W.world()
	var a2 := s.province(W.A2)
	a2.set_level("CASTLE", 3)
	a2.set_level("BOWYER", 1)
	var ctx := W.context(s)
	var defensive := W.plan_for(s, W.A, "CATHOLIC_DEFENSIVE", ctx)
	for i in 30:
		var u := AiEconomy.pick_unit(defensive, a2, 100000.0, 100000.0, false)
		t.assert_true(u != null and u.id != "Knights", "con peso 0 niente cavalieri")


func test_budget_e_mantenimento_limitano_la_scelta(t: TestContext) -> void:
	var s := W.world()
	var a2 := s.province(W.A2)
	a2.set_level("CASTLE", 3)
	a2.set_level("BOWYER", 1)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	t.assert_true(AiEconomy.pick_unit(plan, a2, 50.0, 100000.0, false) == null, "nessuna unita' costa meno di 50")
	var cheap := AiEconomy.pick_unit(plan, a2, 120.0, 100000.0, false)
	t.assert_true(cheap != null and cheap.id == "Spearmen", "con 120 solo i lancieri")
	t.assert_true(AiEconomy.pick_unit(plan, a2, 100000.0, 0.5, false) == null, "senza spazio di mantenimento nulla")
