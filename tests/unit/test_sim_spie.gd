extends RefCounted
## Missioni delle spie (richiesta di Federico del 18/11/2026: «le spie sembrano non poter fare nulla»): spiare una provincia
## o un esercito, fomentare il malcontento, sabotare un edificio, aprire le porte. Mondo di prova: agent_world.gd
## (ALTA e BASSA di ALPHA, MEZZA di BETA confinante con BASSA, SOLA dei ribelli).

const W := preload("res://tests/unit/agent_world.gd")


func _spy(s: GameState, region_id: String = W.BASSA, valour: int = 4) -> AgentState:
	return W.add_agent(s, W.A, region_id, AgentState.SPY, valour)


func test_la_spia_ha_le_sue_missioni(t: TestContext) -> void:
	t.assert_eq(AgentMissions.missions_for(AgentState.SPY), PackedStringArray([AgentMissions.SPY_ON, AgentMissions.UNREST, AgentMissions.SABOTAGE, AgentMissions.GATES]))
	var s := W.world()
	var spy := _spy(s)
	s.province(W.MEZZA).set_level("TEST_BOTTEGA", 2)
	var kinds := {}
	for opt in AgentMissions.options(s, spy):
		kinds[str(opt["tipo"])] = true
		t.assert_true(str(opt["regione"]) == W.MEZZA, "solo bersagli altrui a portata: %s" % str(opt))
	t.assert_true(kinds.has(AgentMissions.SPY_ON) and kinds.has(AgentMissions.UNREST) and kinds.has(AgentMissions.SABOTAGE))
	t.assert_false(kinds.has(AgentMissions.GATES), "senza assedio niente porte")
	t.assert_false(bool(AgentMissions.validate(s, spy, AgentMissions.UNREST, W.ALTA)["ok"]), "non nella propria provincia")
	var far := _spy(s, W.ALTA)
	t.assert_false(bool(AgentMissions.validate(s, far, AgentMissions.UNREST, W.MEZZA)["ok"]), "fuori portata")


func test_spionaggio_della_provincia_e_scadenza(t: TestContext) -> void:
	var s := W.world()
	s.rules.agents.intel_base = 1.0
	var spy := _spy(s)
	t.assert_false(SpyIntel.knows_province(s, W.A, W.MEZZA), "senza spia non si sa")
	t.assert_true(SpyIntel.knows_province(s, W.A, W.BASSA), "la propria provincia si conosce")
	t.assert_true(SpyIntel.knows_province(s, W.A, W.SOLA), "i ribelli si conoscono")
	var r := GameCommands.order_mission(s, W.A, spy.id, AgentMissions.SPY_ON, {"tipo": AgentMissions.TARGET_PROVINCE, "id": W.MEZZA})
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	AgentProcessor.process_year(s)   # l'agente si avvicina
	AgentProcessor.process_year(s)   # e agisce
	t.assert_eq(W.events_of(s, GameState.EV_SPY_REPORT).size(), 1)
	var until := int(s.faction(W.A).intel[SpyIntel.province_key(W.MEZZA)])
	t.assert_eq(until, s.year + s.rules.agents.intel_years, "valide per gli anni delle regole")
	s.agent(spy.id).region = W.BASSA   # anche senza la spia nella provincia
	t.assert_true(SpyIntel.knows_province(s, W.A, W.MEZZA), "informazioni valide")
	s.year = until + 1
	SpyIntel.expire(s)
	t.assert_false(s.faction(W.A).intel.has(SpyIntel.province_key(W.MEZZA)), "scadute si tolgono")
	var saved := FactionState.from_dict(s.faction(W.B).to_dict())
	t.assert_true(saved.intel.is_empty())


func test_la_presenza_della_spia_basta(t: TestContext) -> void:
	var s := W.world()
	var enemy := W.land_army(s, W.G, W.ORTO)   # ORTO confina solo con MEZZA: lontano da ALPHA
	t.assert_false(SpyIntel.knows_army(s, W.A, enemy))
	_spy(s, W.ORTO)
	t.assert_true(SpyIntel.knows_army(s, W.A, enemy), "spia nella regione dell'esercito")
	t.assert_true(SpyIntel.knows_province(s, W.A, W.ORTO))
	t.assert_true(CampaignUiText.army_estimate(enemy).begins_with("Forze stimate: circa"))


## Richiesta di Federico del 20/11/2026: «dove confino o se ho navi in prossimità» si vedono flotte e armate.
func test_si_vede_dal_confine(t: TestContext) -> void:
	var s := W.world()
	var enemy := W.land_army(s, W.B, W.MEZZA)   # MEZZA confina con BASSA di ALPHA
	t.assert_true(SpyIntel.watches_region(s, W.A, W.MEZZA))
	t.assert_true(SpyIntel.knows_army(s, W.A, enemy), "esercito in una provincia confinante")
	t.assert_false(SpyIntel.knows_province(s, W.A, W.MEZZA), "edifici, lealta' e rendite restano alle spie")
	t.assert_false(SpyIntel.knows_army(s, W.A, W.land_army(s, W.G, W.ORTO)), "due province piu' in la' no")
	var intruder := W.general_army(s, W.G, W.BASSA)
	t.assert_true(SpyIntel.knows_army(s, W.A, intruder), "esercito dentro una propria provincia")
	var off_coast := W.fleet(s, W.B, W.NORD)   # NORD bagna ALTA di ALPHA
	t.assert_true(SpyIntel.knows_army(s, W.A, off_coast), "flotta nelle acque che bagnano una propria provincia")


func test_si_vede_dalle_proprie_navi(t: TestContext) -> void:
	var s := W.world()
	# GAMMA ha solo ORTO, che confina con MEZZA: ALTA e i mari sono lontani
	var far_army := W.land_army(s, W.A, W.ALTA)
	var far_fleet := W.fleet(s, W.A, W.NORD)
	t.assert_false(SpyIntel.knows_army(s, W.G, far_army))
	t.assert_false(SpyIntel.knows_army(s, W.G, far_fleet))
	var empty := s.create_army(W.G, W.SUD, true)   # una flotta senza navi non osserva nulla
	t.assert_false(SpyIntel.knows_army(s, W.G, far_fleet), "flotta vuota: %d navi" % empty.stacks.size())
	var mine := W.fleet(s, W.G, W.SUD)
	t.assert_true(SpyIntel.knows_army(s, W.G, far_fleet), "flotta nella zona di mare confinante")
	t.assert_false(SpyIntel.knows_army(s, W.G, far_army), "ALTA non si affaccia sul Mare del Sud")
	mine.region = W.NORD
	t.assert_true(SpyIntel.knows_army(s, W.G, far_army), "esercito sulla costa bagnata dalla propria flotta")
	t.assert_false(SpyIntel.knows_province(s, W.G, W.ALTA), "la flotta vede le truppe, non gli edifici")


func test_malcontento(t: TestContext) -> void:
	var s := W.world()
	s.rules.agents.unrest_base = 1.0
	var spy := _spy(s, W.BASSA, 5)
	var p := s.province(W.MEZZA)
	var before := ProvinceProcessor.spies_term(s, p)
	var r := GameCommands.order_mission(s, W.A, spy.id, AgentMissions.UNREST, W.MEZZA)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	AgentProcessor.process_year(s)   # l'agente si avvicina
	AgentProcessor.process_year(s)   # e agisce
	var events := W.events_of(s, GameState.EV_UNREST)
	t.assert_eq(events.size(), 1)
	var loss := AgentMissions.unrest_loyalty(s, 5)
	t.assert_eq(int(events[0]["lealta"]), loss)
	t.assert_eq(int(p.counters["malcontento"]), loss)
	var term := ProvinceProcessor.spies_term(s, p)
	t.assert_true(term <= before - loss, "lealta' giu' almeno del malcontento: %d -> %d" % [before, term])
	s.year = int(p.counters["malcontento_fino"]) + 1
	t.assert_true(ProvinceProcessor.spies_term(s, p) > term, "finito il periodo il malcontento sparisce")


func test_sabotaggio_riuscito_e_fallito(t: TestContext) -> void:
	var s := W.world()
	var p := s.province(W.MEZZA)
	var castle := s.rules.combat.castle_family
	var castle_level := p.level_of(castle)
	for family in p.buildings.keys():
		if str(family) != castle:
			p.set_level(str(family), 0)   # solo l'edificio di prova (MEZZA ha anche il porto)
	p.set_level("TEST_BOTTEGA", 2)
	s.rules.agents.sabotage_base = 1.0
	s.rules.agents.sabotage_max = 1.0
	var spy := _spy(s, W.MEZZA)
	t.assert_eq(AgentMissions.sabotage_targets(s, p), PackedStringArray(["TEST_BOTTEGA"]), "mai il castello")
	t.assert_true(bool(GameCommands.order_mission(s, W.A, spy.id, AgentMissions.SABOTAGE, W.MEZZA)["ok"]))
	AgentProcessor.process_year(s)
	t.assert_eq(p.level_of("TEST_BOTTEGA"), 1, "un livello in meno")
	t.assert_eq(p.level_of(castle), castle_level, "il castello resta")
	t.assert_eq(W.events_of(s, GameState.EV_SABOTAGE).size(), 1)
	s.rules.agents.sabotage_base = 0.0
	s.rules.agents.sabotage_k = 0.0
	s.rules.agents.sabotage_death = 1.0
	t.assert_true(bool(GameCommands.order_mission(s, W.A, spy.id, AgentMissions.SABOTAGE, W.MEZZA)["ok"]))
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(spy.id) == null, "se fallisce la spia puo' morire")
	t.assert_eq(p.level_of("TEST_BOTTEGA"), 1)


func test_porte_solo_durante_un_assedio_proprio(t: TestContext) -> void:
	var s := W.world()
	var spy := _spy(s, W.MEZZA, 6)
	t.assert_false(bool(AgentMissions.validate(s, spy, AgentMissions.GATES, W.MEZZA)["ok"]))
	t.assert_true(absf(AgentMissions.spy_chance(s, AgentMissions.GATES, 6) - minf(1.0, s.rules.agents.gates_k * 6.0 * s.rules.agents.gates_mission_factor)) < 0.0001)
	t.assert_true(AgentMissions.spy_chance(s, AgentMissions.UNREST, 10) <= 0.95)
