extends RefCounted
## IA: viaggi lunghi degli agenti e commercio navale (ADR-053, specifica del 2026-11-13). Le fazioni IA usano gli stessi viaggi
## del giocatore (`AgentTravel`) e la stessa funzione del commercio marittimo (`Economy.sea_trade_of` in modalita' ipotesi).
## Mondi di prova: agent_world.gd per gli agenti (ALTA-BASSA-MEZZA-ORTO a terra, ALTA e MEZZA con porto collegate da
## NORD-SUD; gli agenti viaggiano via mare anche senza flotte) e sim_startpos.txt per il commercio (ALTA di ALPHA con porto e
## Merchant2, MEZZA di BETA con porto; una flotta di ALPHA in MARE_NORD).

const W := preload("res://tests/unit/agent_world.gd")
const AW := preload("res://tests/unit/ai_world.gd")
const SIM_STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const SIM_UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const SIM_BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _rules() -> AiRules:
	var r := AW.quiet_ai_rules()
	r.journey_threshold = 0.0
	r.alliance_min_p = 0.0
	r.alliance_prob = 1.0
	return r


func _plan(s: GameState, faction_id: String, r: AiRules) -> AiPlan:
	return AW.plan_for(s, faction_id, "", AW.context(s, r))


## Personaggio bersaglio dell'ordine di lungo periodo dell'agente.
func _target_of(s: GameState, a: AgentState) -> Character:
	var target: Dictionary = a.ai_order.get("bersaglio", {})
	return s.character(int(target.get("id", 0)))


## Sposta il personaggio (con il suo esercito, se ne comanda uno).
func _move_char(s: GameState, c: Character, region_id: String) -> void:
	if c.army > 0 and s.army(c.army) != null:
		s.army(c.army).region = region_id
	else:
		c.region = region_id


func _end_year(t: TestContext, s: GameState) -> void:
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]), "fine anno")


# --- viaggi degli agenti -----------------------------------------------------------------------------------------------


func test_l_assassino_parte_per_un_bersaglio_lontano_e_lo_colpisce_all_arrivo(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	s.declare_war(W.A, W.G)
	var assassin := W.add_agent(s, W.A, W.ALTA, AgentState.ASSASSIN, 2)
	W.add_general(s, W.G, W.ORTO)
	var r := _rules()
	var data := _plan(s, W.A, r)
	AiJourneys.plan(data)
	t.assert_eq(data.ctx.rejected, 0, "nessun comando rifiutato: %s" % str(data.ctx.rejections))
	t.assert_eq(str(assassin.ai_order.get("tipo", "")), AgentMissions.ASSASSINATE, "ordine di lungo periodo")
	t.assert_eq(_target_of(s, assassin).faction, W.G, "un personaggio di GAMMA in ORTO (il capo vale di piu')")
	t.assert_eq(assassin.destination, W.ORTO, "viaggio di 2 anni: via mare fino a MEZZA, poi a piedi")
	t.assert_eq(assassin.path, PackedStringArray([W.MEZZA]))
	_end_year(t, s)
	t.assert_eq(assassin.region, W.MEZZA, "prima tappa")
	var data2 := _plan(s, W.A, r)
	AiJourneys.continue_orders(data2)
	t.assert_eq(data2.ctx.rejected, 0, str(data2.ctx.rejections))
	t.assert_true(assassin.has_mission(), "da MEZZA il generale in ORTO e' a portata: missione")
	t.assert_eq(str(assassin.mission["tipo"]), AgentMissions.ASSASSINATE)
	t.assert_true(assassin.ai_order.is_empty(), "l'ordine di lungo periodo e' concluso")


func test_un_bersaglio_oltre_gli_anni_massimi_non_si_assegna(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	s.declare_war(W.A, W.G)
	var assassin := W.add_agent(s, W.A, W.ALTA, AgentState.ASSASSIN, 2)
	W.add_general(s, W.G, W.ORTO)
	var r := _rules()
	r.journey_years["assassino"] = 1
	AiJourneys.plan(_plan(s, W.A, r))
	t.assert_true(assassin.ai_order.is_empty(), "ORTO e' a 2 anni, il massimo e' 1")
	t.assert_true(assassin.path.is_empty() and assassin.destination == "", "l'agente resta fermo")


func test_l_assassino_non_prende_mai_la_propria_fazione_o_un_alleato(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	s.declare_war(W.A, W.B)
	s.form_alliance(W.A, W.G)
	var assassin := W.add_agent(s, W.A, W.ALTA, AgentState.ASSASSIN, 2)
	W.add_general(s, W.A, W.ORTO)
	W.add_general(s, W.G, W.ORTO)
	W.add_general(s, W.B, W.SOLA)
	var data := _plan(s, W.A, _rules())
	var options := AiJourneys.evaluate(data, assassin, "assassino", {}, {})
	t.assert_true(not options.is_empty(), "c'e' almeno un bersaglio")
	for o in options:
		var target: Dictionary = o["bersaglio"]
		if str(target["tipo"]) == AgentMissions.TARGET_CHARACTER:
			var c := s.character(int(target["id"]))
			t.assert_eq(c.faction, W.B, "solo personaggi della fazione in guerra")
	AiJourneys.plan(data)
	t.assert_eq(_target_of(s, assassin).faction, W.B, "parte contro BETA")


func test_bersaglio_morto_a_meta_viaggio_l_agente_abbandona(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	s.declare_war(W.A, W.G)
	var assassin := W.add_agent(s, W.A, W.ALTA, AgentState.ASSASSIN, 2)
	W.add_general(s, W.G, W.ORTO)
	var r := _rules()
	r.journey_threshold = 1000000.0   # dopo l'abbandono nessun nuovo obiettivo: si controlla che resti libero
	r.journey_hysteresis = 1000.0
	var first := _rules()
	AiJourneys.plan(_plan(s, W.A, first))
	t.assert_eq(assassin.destination, W.ORTO)
	_target_of(s, assassin).alive = false
	var data := _plan(s, W.A, r)
	AiJourneys.continue_orders(data)
	t.assert_true(assassin.ai_order.is_empty(), "ordine abbandonato")
	t.assert_eq(assassin.destination, "", "viaggio fermato")
	t.assert_true(assassin.path.is_empty())
	t.assert_true(data.is_agent_free(assassin), "di nuovo libero per un altro obiettivo nello stesso anno")


func test_bersaglio_che_si_sposta_inseguito_fino_al_massimo_dei_ricalcoli(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	s.declare_war(W.A, W.G)
	var assassin := W.add_agent(s, W.A, W.ALTA, AgentState.ASSASSIN, 2)
	W.add_general(s, W.G, W.ORTO)
	var r := _rules()
	r.journey_max_recalcs = 1
	r.journey_hysteresis = 1000.0
	AiJourneys.plan(_plan(s, W.A, r))
	var general := _target_of(s, assassin)
	_move_char(s, general, W.SOLA)
	AiJourneys.continue_orders(_plan(s, W.A, r))
	t.assert_eq(assassin.destination, W.SOLA, "ricalcola il viaggio verso la nuova posizione")
	t.assert_eq(int(assassin.ai_order["ricalcoli"]), 1)
	_move_char(s, general, W.ORTO)
	AiJourneys.continue_orders(_plan(s, W.A, r))
	t.assert_true(assassin.ai_order.is_empty(), "oltre max_ricalcoli rinuncia")
	t.assert_eq(assassin.destination, "")


func test_l_emissario_va_a_proporre_l_alleanza_a_una_fazione_lontana(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	s.declare_war(W.G, W.B)   # nemico comune
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)   # a BASSA
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)   # ad ALTA
	var data := _plan(s, W.A, _rules())
	t.assert_eq(str(AiJourneys.evaluate(data, e, "emissario", {}, {})[0]["tipo"]), AgentMissions.ALLIANCE, "per l'emissario: alleanza")
	AiJourneys.plan(data)
	t.assert_eq(data.ctx.rejected, 0, str(data.ctx.rejections))
	t.assert_eq(str(princess.ai_order.get("tipo", "")), AgentMissions.MARRIAGE, "la principessa (id minore) parte per le nozze")
	t.assert_eq(str(princess.ai_order.get("bersaglio", "")), W.G)
	t.assert_eq(princess.destination, W.ORTO, "fino a ORTO, attraverso MEZZA nemica (gli agenti passano)")
	t.assert_true(data.courting.has(W.G), "GAMMA corteggiata quest'anno")
	t.assert_true(e.ai_order.is_empty(), "l'emissario non si sovrappone alla principessa")
	princess.ai_order = {}
	GameCommands.cancel_agent_move(s, W.A, princess.id)
	princess.character_id = 0
	var p2 := _plan(s, W.A, _rules())
	p2.agents_used[princess.id] = true
	AiJourneys.plan(p2)
	t.assert_eq(str(e.ai_order.get("tipo", "")), AgentMissions.ALLIANCE, "senza la principessa parte l'emissario")
	t.assert_eq(e.destination, W.ORTO)


func test_l_agente_ia_attraversa_il_mare_senza_navi_e_il_blocco_non_lo_ferma(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	s.declare_war(W.A, W.G)
	var spy_free_sea := W.add_agent(s, W.A, W.ALTA, AgentState.ASSASSIN, 2)
	W.add_general(s, W.G, W.MEZZA)
	W.fleet(s, W.B, W.SUD)   # flotta neutrale: blocco per le truppe, non per gli agenti (ADR-019)
	var data := _plan(s, W.A, _rules())
	AiJourneys.plan(data)
	t.assert_eq(data.ctx.rejected, 0, str(data.ctx.rejections))
	t.assert_false(spy_free_sea.sea_route.is_empty(), "da ALTA via mare senza flotte proprie")
	_end_year(t, s)
	t.assert_eq(spy_free_sea.region, W.MEZZA, "sbarcato nonostante la flotta neutrale")


func test_le_spie_presidiano_la_frontiera_nemica_lontana(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	var spy := W.add_agent(s, W.A, W.ALTA, AgentState.SPY, 1)
	var data := _plan(s, W.A, _rules())
	AiJourneys.plan(data)
	t.assert_eq(str(spy.ai_order.get("tipo", "")), AiJourneys.STATION)
	t.assert_eq(str(spy.ai_order.get("bersaglio", "")), W.MEZZA, "provincia nemica di confine")
	var second := W.add_agent(s, W.A, W.ALTA, AgentState.SPY, 1)
	AiJourneys.plan(_plan(s, W.A, _rules()))
	t.assert_true(second.ai_order.is_empty(), "MEZZA e' gia' coperta: una spia per provincia")


func test_l_ordine_sopravvive_al_salvataggio(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	s.declare_war(W.A, W.G)
	var assassin := W.add_agent(s, W.A, W.ALTA, AgentState.ASSASSIN, 2)
	W.add_general(s, W.G, W.ORTO)
	AiJourneys.plan(_plan(s, W.A, _rules()))
	var back := AgentState.from_dict(assassin.to_dict())
	t.assert_eq(back.ai_order, assassin.ai_order, "ordine dell'IA salvato e riletto")
	var f := s.faction(W.A)
	f.ai_trade_zones = PackedStringArray([W.NORD, W.SUD])
	f.ai_trade_year = 1003
	var fb := FactionState.from_dict(f.to_dict())
	t.assert_eq(fb.ai_trade_zones, f.ai_trade_zones, "piano navale salvato")
	t.assert_eq(fb.ai_trade_year, 1003)


func test_riserva_difensiva_un_assassino_resta_a_casa(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	s.declare_war(W.A, W.G)
	var home := W.add_agent(s, W.A, W.ALTA, AgentState.ASSASSIN, 2)
	var away := W.add_agent(s, W.A, W.ALTA, AgentState.ASSASSIN, 2)
	W.add_general(s, W.G, W.ORTO)
	W.add_general(s, W.G, W.ORTO)
	var leader: Character = null
	for c in s.characters:
		if c.faction == W.A and c.role == Character.ROLE_LEADER:
			leader = c
	t.assert_true(leader != null, "ALPHA ha un capo")
	W.add_agent(s, W.G, W.BASSA, AgentState.ASSASSIN, 2)   # assassino nemico vicino al capo
	AiJourneys.plan(_plan(s, W.A, _rules()))
	t.assert_true(home.ai_order.is_empty(), "il primo assassino fa da scorta")
	t.assert_false(away.ai_order.is_empty(), "l'altro parte")


# --- commercio navale --------------------------------------------------------------------------------------------------


func _sim_world() -> GameState:
	var campaign := StartposLoader.load_file(SIM_STARTPOS)
	var units := UnitProdLoader.load_file(SIM_UNITS)
	var buildings := BuildingProdLoader.load_file(SIM_BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, AW.quiet_rules(), 1)
	s.rules.sea_trade_reference = 0.0   # ogni porto vale 1, come in test_sim_turn: 62 + 8
	for c in s.characters:
		c.old_age = 500
	return s


func test_il_piano_sceglie_la_catena_intera_verso_il_porto_straniero(t: TestContext) -> void:
	var s := _sim_world()
	var data := _plan(s, "FN_ALPHA", _rules())
	var routes := AiTrade.candidate_routes(data)
	t.assert_eq(routes.size(), 1, "un solo porto straniero raggiungibile")
	t.assert_eq(routes[0], PackedStringArray(["ID_MARE_NORD", "ID_MARE_SUD"]))
	var result := AiTrade.plan_zones(data, 2)
	t.assert_eq(result["zone"], PackedStringArray(["ID_MARE_NORD", "ID_MARE_SUD"]))
	t.assert_eq(int(result["base"]), 0, "senza zone nessun commercio via mare")
	t.assert_eq(int(result["rendita"]), 70, "62 di merci + 8 di importazioni, come il giocatore (test_sim_turn)")
	var half := AiTrade.plan_zones(data, 1)
	t.assert_true((half["zone"] as PackedStringArray).is_empty(), "con una sola flotta la catena a meta' non rende nulla")


func test_la_flotta_libera_va_a_chiudere_la_catena_e_la_rendita_sale(t: TestContext) -> void:
	var s := _sim_world()
	var second := s.create_army("FN_ALPHA", "ID_MARE_NORD", true)
	second.stacks.append(UnitStack.new("Galley", 1, 0))
	var before := Economy.sea_trade_of(s, "FN_ALPHA")
	s.faction("FN_ALPHA").ai_trade_year = s.year - 10   # piano scaduto: si ripianifica quest'anno
	var data := _plan(s, "FN_ALPHA", _rules())
	AiTrade.plan(data)
	t.assert_eq(data.ctx.rejected, 0, str(data.ctx.rejections))
	t.assert_eq(s.faction("FN_ALPHA").ai_trade_zones, PackedStringArray(["ID_MARE_NORD", "ID_MARE_SUD"]))
	var moving := 0
	for a in s.armies:
		if a.faction == "FN_ALPHA" and a.is_fleet and a.path == PackedStringArray(["ID_MARE_SUD"]):
			moving += 1
	t.assert_eq(moving, 1, "una flotta resta in MARE_NORD, l'altra va in MARE_SUD")
	_end_year(t, s)
	t.assert_true(Economy.sea_trade_of(s, "FN_ALPHA") > before, "con la catena completa il commercio via mare sale")


func test_niente_rotte_verso_chi_e_in_guerra(t: TestContext) -> void:
	var s := _sim_world()
	s.declare_war("FN_ALPHA", "FN_BETA")
	var data := _plan(s, "FN_ALPHA", _rules())
	t.assert_true(AiTrade.candidate_routes(data).is_empty(), "MEZZA e' di una fazione in guerra")
	t.assert_true((AiTrade.plan_zones(data, 5)["zone"] as PackedStringArray).is_empty())


func test_una_flotta_nemica_nel_piano_fa_ripianificare(t: TestContext) -> void:
	var s := _sim_world()
	var f := s.faction("FN_ALPHA")
	f.ai_trade_zones = PackedStringArray(["ID_MARE_NORD", "ID_MARE_SUD"])
	f.ai_trade_year = s.year
	s.declare_war("FN_ALPHA", "FN_GAMMA")
	var enemy := s.create_army("FN_GAMMA", "ID_MARE_SUD", true)
	enemy.stacks.append(UnitStack.new("Galley", 1, 0))
	var data := _plan(s, "FN_ALPHA", _rules())
	AiTrade.plan(data)
	t.assert_eq(f.ai_trade_year, s.year, "ripianificato subito")
	t.assert_true(f.ai_trade_zones.size() <= 1, "con una sola flotta libera la catena intera non si puo' fare")


func test_senza_flotte_nessun_errore_e_si_chiede_una_nave(t: TestContext) -> void:
	var s := _sim_world()
	AW.clear_armies(s)
	var r := _rules()
	r.trade_build_threshold = 10.0
	s.faction("FN_ALPHA").ai_trade_year = s.year - 10
	var data := _plan(s, "FN_ALPHA", r)
	var result := AiTrade.plan_zones(data, 0)
	t.assert_true((result["zone"] as PackedStringArray).is_empty())
	t.assert_true(bool(result["serve_nave"]), "la rotta renderebbe 70 > 10: serve una nave")
	AiTrade.plan(data)
	t.assert_eq(data.ctx.rejected, 0, str(data.ctx.rejections))


func test_il_commercio_perso_per_una_guerra_si_misura_con_la_stessa_formula(t: TestContext) -> void:
	var s := _sim_world()
	var chain := s.create_army("FN_ALPHA", "ID_MARE_SUD", true)
	chain.stacks.append(UnitStack.new("Galley", 1, 0))
	var data := _plan(s, "FN_ALPHA", _rules())
	t.assert_eq(AiDiplomacy.lost_trade(data, "FN_BETA"), 0, "in pace non si perde nulla")
	s.declare_war("FN_ALPHA", "FN_BETA")
	t.assert_eq(AiDiplomacy.lost_trade(_plan(s, "FN_ALPHA", _rules()), "FN_BETA"), 70, "la guerra chiude la rotta verso MEZZA: 62 + 8")


func test_porto_e_mercante_valgono_di_piu_sulla_costa_con_merci(t: TestContext) -> void:
	var s := _sim_world()
	var data := _plan(s, "FN_ALPHA", _rules())
	var alta := s.province("ID_ALTA")
	var region := s.campaign.region("ID_ALTA")
	var family := s.buildings.get_family("MERCHANT")
	var lv := family.get_level(alta.level_of("MERCHANT") + 1)
	if lv == null:
		t.skip("nessun livello successivo del mercante nel file di prova")
		return
	data.rules.build_noise = 0.0
	var with_goods := AiEconomy.building_score(data, alta, region, family, lv)
	var saved := region.trade_goods
	region.trade_goods = PackedStringArray()
	var without := AiEconomy.building_score(data, alta, region, family, lv)
	region.trade_goods = saved
	t.assert_true(with_goods > without, "con merci da vendere il mercante vale di piu' (%.1f > %.1f)" % [with_goods, without])


func test_il_primo_piano_navale_e_scaglionato_tra_le_fazioni(t: TestContext) -> void:
	var s := _sim_world()
	var f := s.faction("FN_ALPHA")
	var planned_years := 0
	for i in 3:
		f.ai_trade_year = -1
		AiTrade.plan(_plan(s, "FN_ALPHA", _rules()))
		if f.ai_trade_year == s.year:
			planned_years += 1
		s.year += 1
	t.assert_eq(planned_years, 1, "su tre anni di fila la fazione fa il primo piano una volta sola")


func test_tabella_del_mare_uguale_alle_destinazioni_una_per_una(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	W.fleet(s, W.B, W.SUD)
	for fid in [W.A, W.B, W.G]:
		var table := AgentTravel.sea_table(s, fid)
		for r in s.campaign.regions:
			if r.is_sea:
				continue
			var one := Array(GameCommands.sea_destinations_from(s, fid, r.id, false))
			var all := Array(table.get(r.id, PackedStringArray()))
			one.sort()
			all.sort()
			t.assert_eq(all, one, "%s da %s" % [fid, r.id])


func test_partita_ia_breve_con_viaggi_e_commercio_senza_rifiuti(t: TestContext) -> void:
	var s := AW.world()
	for i in 6:
		var report := AiController.plan_year(s)
		t.assert_eq(int(report["rifiutati"]), 0, "anno %d: %s" % [s.year, str(report["rifiuti"])])
		s.ai_orders_horde = false
		_end_year(t, s)
