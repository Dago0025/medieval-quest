extends RefCounted
## Nebbia di guerra (Visibility): province proprie, regioni con propri eserciti, flotte e agenti, e le confinanti.
## Mondo di prova degli agenti: ALPHA ha ALTA e BASSA, BETA ha MEZZA (confina con BASSA, SOLA, ORTO, MARE_SUD),
## GAMMA ha ORTO (confina con MEZZA); ALTA confina con MARE_NORD, che confina con MARE_SUD.

const W := preload("res://tests/unit/agent_world.gd")


func test_proprie_e_confinanti(t: TestContext) -> void:
	var s := W.world()
	for a in s.agents_of(W.A):
		a.region = W.BASSA   # gli agenti restano nelle province proprie
	for f in s.armies_of(W.A):
		if f.is_fleet:
			f.stacks.clear()   # senza flotte in mare
	var seen := Visibility.visible_regions(s, W.A)
	t.assert_true(seen.has(W.ALTA) and seen.has(W.BASSA), "province proprie")
	t.assert_true(seen.has(W.MEZZA), "MEZZA confina con BASSA")
	t.assert_true(seen.has(W.NORD), "il mare accanto ad ALTA")
	t.assert_false(seen.has(W.ORTO), "ORTO confina solo con MEZZA: fuori vista")
	t.assert_false(seen.has(W.SUD), "MARE_SUD confina con MEZZA e MARE_NORD, non con province di ALPHA")


func test_un_agente_porta_la_vista_con_se(t: TestContext) -> void:
	var s := W.world()
	var emissary := W.agent_of(s, W.A, AgentState.EMISSARY)
	emissary.region = W.MEZZA
	var seen := Visibility.visible_regions(s, W.A)
	t.assert_true(seen.has(W.ORTO), "dall'agente in MEZZA si vede ORTO")
	t.assert_true(seen.has(W.SUD))


func test_una_flotta_vede_le_zone_accanto(t: TestContext) -> void:
	var s := W.world()
	for a in s.agents_of(W.A):
		a.region = W.BASSA
	for f in s.armies_of(W.A):
		if f.is_fleet:
			f.stacks.clear()
	t.assert_false(Visibility.sees(s, W.A, W.SUD), "senza flotte MARE_SUD e' fuori vista")
	var fleet := s.create_army(W.A, W.NORD, true)
	fleet.stacks.append(UnitStack.new("Galley", 1, 0))
	t.assert_true(Visibility.sees(s, W.A, W.SUD), "la flotta in MARE_NORD vede MARE_SUD")
