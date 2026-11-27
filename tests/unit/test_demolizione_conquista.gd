extends RefCounted
## Demolizione degli edifici (manuale p37) e edifici persi nella conquista (ConquestDamage), richieste di Federico del 15/11.
## Mondo piccolo tests/fixtures/sim_*.txt: ALPHA (cattolici) ha ID_ALTA (Castle3, Port, Improved_Farmland2, Merchant2) e
## ID_BASSA; BETA (musulmani) ha ID_MEZZA. Merchant2 richiede CASTLE2; Merchant costa 800/1000.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world(rules: Rules = null) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, rules if rules != null else Rules.new(), 1)


func test_demolire_toglie_un_livello_e_rimborsa_meta(t: TestContext) -> void:
	var s := _world()
	var alta := s.province("ID_ALTA")
	var before := s.faction("FN_ALPHA").treasury
	var check := GameCommands.can_demolish_building(s, "FN_ALPHA", "ID_ALTA", "MERCHANT")
	t.assert_true(bool(check["ok"]), str(check))
	t.assert_eq(int(check["rimborso"]), 500, "meta' dei 1000 denari del livello 2")
	var r := GameCommands.demolish_building(s, "FN_ALPHA", "ID_ALTA", "MERCHANT")
	t.assert_true(bool(r["ok"]))
	t.assert_eq(alta.level_of("MERCHANT"), 1)
	t.assert_eq(s.faction("FN_ALPHA").treasury, before + 500)
	GameCommands.demolish_building(s, "FN_ALPHA", "ID_ALTA", "MERCHANT")
	t.assert_eq(alta.level_of("MERCHANT"), 0)
	t.assert_false(alta.buildings.has("MERCHANT"), "livello 0: la voce sparisce")
	t.assert_false(bool(GameCommands.can_demolish_building(s, "FN_ALPHA", "ID_ALTA", "MERCHANT")["ok"]), "non c'e' piu'")


func test_non_si_demolisce_cio_che_serve_ad_altri_o_e_in_coda(t: TestContext) -> void:
	var s := _world()
	t.assert_true(bool(GameCommands.demolish_building(s, "FN_ALPHA", "ID_ALTA", "CASTLE")["ok"]), "Castle3 -> Castle2: Merchant2 regge")
	var blocked := GameCommands.can_demolish_building(s, "FN_ALPHA", "ID_ALTA", "CASTLE")
	t.assert_false(bool(blocked["ok"]), "Castle2 serve a Merchant2")
	t.assert_true(str(blocked["errore"]).contains("MERCHANT2"), str(blocked["errore"]))
	t.assert_eq(s.province("ID_ALTA").level_of("CASTLE"), 2, "il controllo non cambia la provincia")
	t.assert_false(bool(GameCommands.can_demolish_building(s, "FN_BETA", "ID_ALTA", "PORT")["ok"]), "provincia altrui")
	s.faction("FN_ALPHA").treasury = 99999
	t.assert_true(bool(GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "SHIPYARD")["ok"]))
	t.assert_false(bool(GameCommands.can_demolish_building(s, "FN_ALPHA", "ID_ALTA", "PORT")["ok"]), "il porto serve al cantiere in coda")


func _sure_rules() -> Rules:
	var r := Rules.new()
	r.conquest_building_chance = 1.0
	r.conquest_min_chance = 1.0
	r.conquest_castle_protection = 0.0
	r.conquest_castle_drop = 1.0
	return r


func test_conquista_danneggia_gli_edifici(t: TestContext) -> void:
	var s := _world(_sure_rules())
	var alta := s.province("ID_ALTA")
	alta.set_level("CHURCH", 1)
	WarProcessor.transfer_province(s, alta, "FN_BETA", ConquestDamage.MEANS_FIELD)
	t.assert_eq(alta.owner, "FN_BETA")
	t.assert_eq(alta.level_of("CASTLE"), 3, "senza assedio il castello resta")
	t.assert_eq(alta.level_of("MERCHANT"), 1, "un livello in meno")
	t.assert_eq(alta.level_of("IMPROVED_FARMLAND"), 1)
	t.assert_eq(alta.level_of("PORT"), 0, "livello 1 perso = distrutto")
	t.assert_eq(alta.level_of("CHURCH"), 0, "chiesa persa per i musulmani")
	var ev: Dictionary = {}
	for e in s.events:
		if str(e["tipo"]) == GameState.EV_PROVINCE_CAPTURED:
			ev = e
	t.assert_true((ev["distrutti"] as Array).has("CHURCH") and (ev["danneggiati"] as Array).has("MERCHANT2"), str(ev))
	t.assert_true(str(ev["testo"]).contains("distrutti"), str(ev["testo"]))


func test_assedio_corruzione_e_porte(t: TestContext) -> void:
	var s := _world(_sure_rules())
	var alta := s.province("ID_ALTA")
	ConquestDamage.apply(s, alta, "FN_BETA", ConquestDamage.MEANS_SIEGE)
	t.assert_eq(alta.level_of("CASTLE"), 2, "dopo un assedio il castello perde un livello")
	var s2 := _world(_sure_rules())
	var alta2 := s2.province("ID_ALTA")
	alta2.set_level("CHURCH", 1)
	var d: Dictionary = ConquestDamage.apply(s2, alta2, "FN_BETA", ConquestDamage.MEANS_BRIBE)
	t.assert_eq(alta2.level_of("MERCHANT"), 2, "guarnigione corrotta: niente danni...")
	t.assert_eq(Array(d["distrutti"]), ["CHURCH"], "...tranne gli edifici dell'altra religione")
	var r3 := _sure_rules()
	r3.conquest_means[ConquestDamage.MEANS_GATES] = 0.0
	var s3 := _world(r3)
	ConquestDamage.apply(s3, s3.province("ID_ALTA"), "FN_GAMMA", ConquestDamage.MEANS_GATES)
	t.assert_eq(s3.province("ID_ALTA").level_of("MERCHANT"), 2, "il moltiplicatore del modo conta (porte a 0)")
	t.assert_eq(Rules.new().conquest_means[ConquestDamage.MEANS_GATES], 0.4)


func test_regole_lette_da_economia_cfg(t: TestContext) -> void:
	var r := Rules.load_file()
	var d := Rules.new()
	t.assert_eq(r.demolish_refund, d.demolish_refund)
	t.assert_eq(r.conquest_building_chance, d.conquest_building_chance)
	t.assert_eq(r.conquest_means, d.conquest_means)
	t.assert_eq(r.conquest_castle_drop, d.conquest_castle_drop)
