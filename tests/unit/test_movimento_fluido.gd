extends RefCounted
## Movimento fluido (richiesta di Federico del 2026-11-10, CampaignUiMoves): pedine in viaggio disegnate all'arrivo
## senza frecce, regioni raggiungibili colorate mentre si trascina, e il blocco navale che le toglie.
## Mondo di prova del trasporto (tests/fixtures/transport_startpos.txt, vedi il commento in testa al file):
##   esercito 1 = ALPHA in PORTA (confina con ENTRO e MARE_UNO), 2 = flotta ALPHA in MARE_UNO, 5 = BETA in FARO.

const STARTPOS := "res://tests/fixtures/transport_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)
	s.faction("FN_ALPHA").is_player = true
	return s


func _fleet(s: GameState, faction_id: String, zone: String) -> Army:
	var a := s.create_army(faction_id, zone, true)
	a.stacks.append(UnitStack.new("Galley", 1, 0))
	return a


func _all_seas(s: GameState) -> void:
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	_fleet(s, "FN_ALPHA", "ID_MARE_TRE")
	_fleet(s, "FN_ALPHA", "ID_MARE_QUATTRO")


# --- pedine disegnate all'arrivo ------------------------------------------------------------------------------


func test_senza_ordine_la_pedina_resta_nella_sua_regione(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiMoves.army_shown_region(s, s.army(1)), "ID_PORTA")
	t.assert_false(CampaignUiMoves.army_in_transit(s.army(1)))


func test_con_un_ordine_la_pedina_e_gia_all_arrivo_ma_non_si_muove_nella_simulazione(t: TestContext) -> void:
	var s := _world()
	t.assert_true(bool(GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_ENTRO"]))["ok"]))
	t.assert_eq(CampaignUiMoves.army_shown_region(s, s.army(1)), "ID_ENTRO")
	t.assert_eq(s.army(1).region, "ID_PORTA", "nella simulazione arriva a fine anno")
	t.assert_true(CampaignUiMoves.army_in_transit(s.army(1)))
	var shown := CampaignUiMoves.shown_army_regions(s, s.armies, "FN_ALPHA")
	t.assert_eq(shown.get(1, ""), "ID_ENTRO")
	t.assert_false(shown.has(5), "le pedine altrui restano dove sono")
	var groups := MarkerLayout.group_by_region(s.armies, shown)
	t.assert_true((groups["ID_ENTRO"] as PackedInt32Array).has(1))
	t.assert_false(groups.has("ID_PORTA") and (groups["ID_PORTA"] as PackedInt32Array).has(1))


func test_trasporto_via_mare_disegnato_nella_provincia_di_sbarco(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	t.assert_true(bool(GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_LONTANA"]))["ok"]))
	t.assert_eq(CampaignUiMoves.army_shown_region(s, s.army(1)), "ID_LONTANA")


func test_flotta_disegnata_dove_arriva_quest_anno(t: TestContext) -> void:
	var s := _world()
	var fleet := s.army(2)
	var route := GameCommands.fleet_path(s, fleet.id, "ID_MARE_QUATTRO")
	t.assert_eq(route.size(), 2)
	GameCommands.order_move(s, "FN_ALPHA", fleet.id, route)
	var reach := Combat.fleet_range(s, fleet)
	t.assert_eq(CampaignUiMoves.army_shown_region(s, fleet), route[mini(reach, route.size()) - 1])


func test_agente_disegnato_al_primo_passo(t: TestContext) -> void:
	var s := _world()
	var ag := s.create_agent("FN_ALPHA", "ID_PORTA", "Emissary", "EMISSARY", 980)
	t.assert_eq(CampaignUiMoves.agent_shown_region(ag), "ID_PORTA")
	ag.path = PackedStringArray(["ID_ENTRO"])
	t.assert_eq(CampaignUiMoves.agent_shown_region(ag), "ID_ENTRO")
	t.assert_true(CampaignUiMoves.agent_in_transit(ag))
	var groups := MarkerLayout.group_agents_by_region(s.agents, CampaignUiMoves.shown_agent_regions(s.agents, "FN_ALPHA"))
	t.assert_true((groups["ID_ENTRO"] as PackedInt32Array).has(ag.id))


# --- regioni raggiungibili ----------------------------------------------------------------------------------


func test_raggiungibili_a_piedi_e_via_mare(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	var reach := CampaignUiMoves.army_reach(s, s.army(1))
	t.assert_eq(reach.get("ID_PORTA", 0), CampaignUiMoves.REACH_ORIGIN)
	t.assert_eq(reach.get("ID_ENTRO", 0), CampaignUiMoves.REACH_MOVE, "confinante propria")
	t.assert_eq(reach.get("ID_SENZAPORTO", 0), CampaignUiMoves.REACH_SEA, "via mare, propria")
	t.assert_eq(reach.get("ID_FARO", 0), CampaignUiMoves.REACH_ATTACK, "via mare, di BETA: sbarco ostile")
	t.assert_eq(reach.get("ID_LONTANA", 0), CampaignUiMoves.REACH_ATTACK, "ribelli")
	t.assert_false(reach.has("ID_MARE_UNO"), "le truppe non vanno in mare")
	for region_id in reach:
		if int(reach[region_id]) == CampaignUiMoves.REACH_ORIGIN:
			continue
		var probe := _world()
		_all_seas(probe)
		t.assert_true(bool(GameCommands.order_move(probe, "FN_ALPHA", 1, PackedStringArray([region_id]))["ok"]), "l'ordine verso %s e' valido" % region_id)


func test_senza_flotte_solo_le_confinanti(t: TestContext) -> void:
	var s := _world()
	s.army(2).stacks.clear()
	var reach := CampaignUiMoves.army_reach(s, s.army(1))
	t.assert_eq(reach.size(), 2, "partenza ed ENTRO: %s" % str(reach))


func test_il_blocco_navale_toglie_le_province_via_mare(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	_fleet(s, "FN_BETA", "ID_MARE_UNO")   # BETA e' neutrale con ALPHA
	var reach := CampaignUiMoves.army_reach(s, s.army(1))
	t.assert_false(reach.has("ID_SENZAPORTO"))
	t.assert_false(reach.has("ID_FARO"))
	t.assert_true(reach.has("ID_ENTRO"), "a piedi si va comunque")


func test_flotta_raggiunge_le_zone_entro_il_raggio(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.coast_limit = false   # qui si prova il raggio di movimento; la distanza dalla costa in test_flotte_costa
	var fleet := s.army(2)
	var limit := Combat.fleet_range(s, fleet)
	var zones := CampaignUiMoves.fleet_zones(s, fleet)
	t.assert_false(zones.has("ID_MARE_UNO"), "la partenza esclusa")
	t.assert_true(zones.has("ID_MARE_DUE") and zones.has("ID_MARE_TRE"), "le confinanti ci sono sempre")
	for z in ["ID_MARE_DUE", "ID_MARE_TRE", "ID_MARE_QUATTRO"]:
		var steps := GameCommands.fleet_path(s, fleet.id, z).size()
		t.assert_eq(zones.has(z), steps <= limit, "%s a %d passi, raggio %d" % [z, steps, limit])
	var reach := CampaignUiMoves.army_reach(s, fleet)
	t.assert_false(reach.has("ID_PORTA"), "le flotte non vanno a terra")


func test_agente_confinanti_e_via_mare(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	var ag := s.create_agent("FN_ALPHA", "ID_PORTA", "Emissary", "EMISSARY", 980)
	var reach := CampaignUiMoves.agent_reach(s, ag)
	t.assert_eq(reach.get("ID_ENTRO", 0), CampaignUiMoves.REACH_MOVE)
	t.assert_eq(reach.get("ID_FARO", 0), CampaignUiMoves.REACH_SEA, "gli agenti non attaccano")


func test_il_blocco_navale_non_ferma_gli_agenti(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	_fleet(s, "FN_BETA", "ID_MARE_UNO")   # neutrale: blocca le truppe, non gli agenti
	var ag := s.create_agent("FN_ALPHA", "ID_PORTA", "Emissary", "EMISSARY", 980)
	t.assert_false(CampaignUiMoves.army_reach(s, s.army(1)).has("ID_FARO"), "le truppe sono bloccate")
	t.assert_eq(CampaignUiMoves.agent_reach(s, ag).get("ID_FARO", 0), CampaignUiMoves.REACH_SEA, "l'agente passa")
	t.assert_true(bool(GameCommands.order_agent_move(s, "FN_ALPHA", ag.id, PackedStringArray(["ID_FARO"]))["ok"]))
	s.events.clear()
	TurnProcessor.end_year(s)
	t.assert_eq(ag.region, "ID_FARO", "sbarcato nonostante la flotta neutrale")


func test_la_flotta_nemica_ferma_anche_gli_agenti(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	s.declare_war("FN_ALPHA", "FN_GAMMA")
	_fleet(s, "FN_GAMMA", "ID_MARE_UNO")
	var ag := s.create_agent("FN_ALPHA", "ID_PORTA", "Emissary", "EMISSARY", 980)
	t.assert_false(CampaignUiMoves.agent_reach(s, ag).has("ID_FARO"))
	t.assert_false(bool(GameCommands.order_agent_move(s, "FN_ALPHA", ag.id, PackedStringArray(["ID_FARO"]))["ok"]))
