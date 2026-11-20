extends RefCounted
## Test di guerra, battaglie in campo, ritirate e scontri navali (spec. fase 3 §1-§4) sul mondo
## piccolo tests/fixtures/sim_*.txt (nessuna statistica: forza di una pila = uomini).
##   Esercito 1 = ALPHA in ALTA (160), 2 = flotta ALPHA in ID_MARE_NORD (1 galea), 3 = ALPHA in BASSA (80),
##   4 = BETA in MEZZA (60 Nizari, castello livello 2), 5 = ribelli in SOLA (50, nessun castello).
##   Vicini di MEZZA nell'ordine di SetNeighbours: BASSA, SOLA, MARE_SUD. Fazioni: REBEL, ALPHA, BETA, GAMMA.
## Valori attesi verificati con una replica Python delle formule (vedi test_sim_combat.gd):
##   1.000.000 contro 60 x 1,15 = 69: perdente 54 uomini (restano 6), vincitore 31
##   100 contro 1.000.000 x 1,15: attaccante perde 90 (restano 10), difensore 39
##   80 contro 60 x 1,15, vince il difensore: 46 e 20; 80 contro 50 x 1,15, vince l'attaccante: 32 e 19
##   flotte: 4 galee (7,0) contro 10 galee (17,5): vince il difensore -> 3 e 1 perse; vince l'attaccante -> 5 e 2

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const EPS := 1.0e-6


func _world(seed_value: int = 1) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var rules := Rules.new()
	rules.combat.capture_share = 0.0   # ADR-073: qui si provano le ritirate senza i prigionieri della ritirata parziale (test_sim_prigionieri)
	return GameSetup.new_game(campaign, units, buildings, rules, seed_value)


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _near(t: TestContext, actual: float, expected: float, message: String) -> void:
	t.assert_true(absf(actual - expected) < EPS, "%s: atteso %s, ottenuto %s" % [message, str(expected), str(actual)])


## Come se l'esercito fosse appena arrivato in `to_region` da dove si trovava (e' l'attaccante).
func _invade(s: GameState, army: Army, to_region: String) -> void:
	army.from_region = army.region
	army.region = to_region
	army.arrived_year = s.year


func _add_army(s: GameState, faction_id: String, region_id: String, unit_id: String, men: int, fleet: bool = false) -> Army:
	var a := s.create_army(faction_id, region_id, fleet)
	a.stacks.append(UnitStack.new(unit_id, men, 0))
	return a


func _men_total(s: GameState) -> int:
	var total := 0
	for a in s.armies:
		total += a.men_total()
	return total


## Uomini persi in un anno secondo il registro: battaglie, catture, resa per fame.
func _men_lost(s: GameState) -> int:
	var total := 0
	for e in _events_of(s, GameState.EV_BATTLE):
		total += int(e["perdite_attaccante"]) + int(e["perdite_difensore"])
	for e in _events_of(s, GameState.EV_CAPTURED_UNITS):
		total += int(e["uomini"])
	for e in _events_of(s, GameState.EV_STARVED):
		total += int(e["uomini"])
	return total


## Toglie i ribelli di SOLA e la assegna a BETA (per avere una provincia propria in cui ritirarsi).
func _give_sola_to_beta(s: GameState) -> void:
	s.remove_army(s.army(5))
	s.province("ID_SOLA").owner = "FN_BETA"


# --- guerra ------------------------------------------------------------------------------------


func test_chiavi_e_simmetria_delle_guerre(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(GameState.war_key("FN_BETA", "FN_ALPHA"), "FN_ALPHA|FN_BETA", "A < B")
	t.assert_eq(GameState.war_key("fn_alpha", "FN_BETA"), "FN_ALPHA|FN_BETA", "maiuscolo")
	t.assert_false(s.at_war("FN_ALPHA", "FN_BETA"), "all'inizio nessuna guerra")
	t.assert_false(s.at_war("FN_ALPHA", "FN_ALPHA"), "nessuno e' in guerra con se stesso")
	t.assert_true(s.at_war("FN_ALPHA", "FN_REBEL"), "i ribelli sono in guerra con tutti")
	t.assert_true(s.at_war("FN_REBEL", "FN_BETA"))
	t.assert_true(s.declare_war("FN_BETA", "FN_ALPHA"), "guerra nuova")
	t.assert_false(s.declare_war("FN_ALPHA", "FN_BETA"), "gia' in corso")
	t.assert_true(s.at_war("FN_ALPHA", "FN_BETA"))
	t.assert_true(s.at_war("FN_BETA", "FN_ALPHA"), "simmetrica")
	t.assert_false(s.at_war("FN_ALPHA", "FN_GAMMA"))
	t.assert_false(s.declare_war("FN_ALPHA", "FN_REBEL"), "i ribelli non si dichiarano")
	t.assert_eq(s.wars.size(), 1, "solo ALPHA|BETA")
	t.assert_eq(s.enemies_of("FN_ALPHA"), ["FN_BETA"] as Array[String], "esclusi i ribelli")
	t.assert_eq(s.enemies_of("FN_GAMMA"), [] as Array[String])


func test_la_guerra_si_dichiara_a_fine_anno_non_all_ordine(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	var order := GameCommands.order_move(s, "FN_ALPHA", 3, PackedStringArray(["ID_MEZZA"]))
	t.assert_true(bool(order["ok"]), str(order["errore"]))
	t.assert_true(bool(order["attacco"]), "l'ordine dice che e' un attacco")
	t.assert_false(s.at_war("FN_ALPHA", "FN_BETA"), "ancora in pace: la guerra parte con il movimento")
	TurnProcessor.end_year(s)
	t.assert_true(s.at_war("FN_ALPHA", "FN_BETA"))
	var declared := _events_of(s, GameState.EV_WAR_DECLARED)
	t.assert_eq(declared.size(), 1)
	t.assert_eq(declared[0]["fazione"], "FN_ALPHA")
	t.assert_eq(declared[0]["contro"], "FN_BETA")
	t.assert_eq(declared[0]["regione"], "ID_MEZZA")
	t.assert_eq(declared[0]["anno"], 1000)
	t.assert_true(str(declared[0]["testo"]).contains("Alpha") and str(declared[0]["testo"]).contains("Beta"), str(declared[0]["testo"]))
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_WAR_DECLARED).size(), 0, "la guerra c'e' gia'")
	t.assert_true(s.at_war("FN_ALPHA", "FN_BETA"), "le guerre durano")


func test_quando_un_movimento_e_un_attacco(t: TestContext) -> void:
	var s := _world()
	t.assert_true(GameCommands.is_hostile_target(s, "FN_ALPHA", "ID_MEZZA"), "provincia di BETA")
	t.assert_false(GameCommands.is_hostile_target(s, "FN_ALPHA", "ID_BASSA"), "provincia propria")
	t.assert_true(GameCommands.is_hostile_target(s, "FN_ALPHA", "ID_SOLA"), "provincia dei ribelli")
	t.assert_false(GameCommands.is_hostile_target(s, "FN_ALPHA", "ID_MARE_NORD", true), "solo una flotta propria")
	t.assert_false(GameCommands.is_hostile_target(s, "FN_BETA", "ID_MARE_NORD", true), "flotta neutrale: le flotte convivono")
	s.declare_war("FN_ALPHA", "FN_BETA")
	t.assert_true(GameCommands.is_hostile_target(s, "FN_BETA", "ID_MARE_NORD", true), "in guerra la flotta di ALPHA e' ostile")
	s.end_war("FN_ALPHA", "FN_BETA")
	t.assert_false(GameCommands.is_hostile_target(s, "FN_BETA", "ID_MARE_SUD", true), "mare vuoto")
	var move := GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_BASSA"]))
	t.assert_false(bool(move["attacco"]), "muoversi in casa propria non e' un attacco")
	# una regione propria dove sta un esercito di un'altra fazione: attaccare e' dichiarare guerra
	_invade(s, s.army(4), "ID_BASSA")
	t.assert_true(GameCommands.is_hostile_target(s, "FN_ALPHA", "ID_BASSA"), "ci sono eserciti di BETA")


func test_movimento_di_una_flotta_verso_una_flotta_nemica(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	var fleet := _add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 4, true)
	s.declare_war("FN_ALPHA", "FN_BETA")
	t.assert_true(bool(GameCommands.order_move(s, "FN_BETA", fleet.id, PackedStringArray(["ID_MARE_NORD"]))["ok"]))
	TurnProcessor.end_year(s)
	var battles := _events_of(s, GameState.EV_BATTLE)
	t.assert_eq(battles.size(), 1, "in guerra si combatte")
	t.assert_eq(battles[0]["scontro"], "navale")


func test_una_flotta_che_entra_dove_c_e_una_flotta_neutrale_non_dichiara_guerra(t: TestContext) -> void:
	# segnalazione di Federico (2026-11-13): spostarsi in un mare con una flotta neutrale non e' un attacco
	var s := _world()
	var fleet := _add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 4, true)
	t.assert_true(bool(GameCommands.order_move(s, "FN_BETA", fleet.id, PackedStringArray(["ID_MARE_NORD"]))["ok"]))
	TurnProcessor.end_year(s)
	t.assert_false(s.at_war("FN_ALPHA", "FN_BETA"), "nessuna guerra")
	t.assert_eq(_events_of(s, GameState.EV_WAR_DECLARED).size(), 0)
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 0)
	t.assert_eq(fleet.region, "ID_MARE_NORD", "la flotta e' arrivata e convive con quella di ALPHA")


func test_senza_guerra_non_si_combatte(t: TestContext) -> void:
	var s := _world()
	_invade(s, s.army(4), "ID_ALTA")   # BETA in casa di ALPHA, ma in pace
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 0)
	t.assert_eq(s.army(4).region, "ID_ALTA")
	t.assert_eq(s.province("ID_ALTA").owner, "FN_ALPHA", "non si conquista senza guerra")
	t.assert_eq(s.army(1).men_total(), 160)


# --- battaglia in campo --------------------------------------------------------------------------


func test_battaglia_vinta_dall_attaccante(t: TestContext) -> void:
	var s := _world()
	s.army(3).stacks[0].men = 1000000
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	var before := _men_total(s)
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0)
	var battles := _events_of(s, GameState.EV_BATTLE)
	t.assert_eq(battles.size(), 1)
	var b := battles[0]
	t.assert_eq(b["tipo"], GameState.EV_BATTLE)
	t.assert_eq(b["attaccante"], "FN_ALPHA", "e' entrato quest'anno")
	t.assert_eq(b["difensore"], "FN_BETA")
	t.assert_eq(b["fazione"], "FN_ALPHA")
	t.assert_eq(b["regione"], "ID_MEZZA")
	t.assert_eq(b["scontro"], "campo")
	t.assert_true(bool(b["vittoria_attaccante"]))
	t.assert_eq(b["vincitore"], "FN_ALPHA")
	t.assert_eq(b["perdente"], "FN_BETA")
	_near(t, float(b["forza_attaccante"]), 1000000.0, "forza attaccante")
	_near(t, float(b["forza_difensore_base"]), 60.0, "forza difensore")
	_near(t, float(b["forza_difensore"]), 69.0, "con il bonus del difensore")
	t.assert_eq(b["uomini_attaccante"], 1000000)
	t.assert_eq(b["uomini_difensore"], 60)
	t.assert_eq(b["perdite_difensore"], 54)
	t.assert_eq(b["perdite_attaccante"], 31)
	t.assert_true(str(b["testo"]).contains("Mezza") and str(b["testo"]).contains("Alpha"), str(b["testo"]))
	t.assert_eq(s.army(3).men_total(), 999969)
	t.assert_eq(s.army(4).men_total(), 6)
	t.assert_eq(before - _men_lost(s), _men_total(s), "uomini conservati: prima - perdite = dopo")
	# BETA, sconfitta nella propria provincia con castello, si ritira nel castello (caso 1)
	t.assert_true(s.army(4).in_castle)
	t.assert_eq(s.army(4).region, "ID_MEZZA")
	var retreats := _events_of(s, GameState.EV_RETREAT)
	t.assert_eq(retreats.size(), 1)
	t.assert_eq(retreats[0]["caso"], "castello")
	t.assert_eq((b["ritirate"] as Array).size(), 1, "le ritirate sono anche nel dettaglio della battaglia")
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA", "la provincia non cade: c'e' la guarnigione")
	t.assert_true(s.sieges.has("ID_MEZZA"), "inizia l'assedio")


func test_battaglia_vinta_dal_difensore_e_ritirata_in_provincia_amica(t: TestContext) -> void:
	var s := _world()
	s.army(4).stacks[0].men = 1000000
	s.army(3).stacks[0].men = 100
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	var before := _men_total(s)
	TurnProcessor.end_year(s)
	var b := _events_of(s, GameState.EV_BATTLE)[0]
	t.assert_false(bool(b["vittoria_attaccante"]))
	t.assert_eq(b["vincitore"], "FN_BETA")
	t.assert_eq(b["perdite_attaccante"], 90)
	t.assert_eq(b["perdite_difensore"], 39)
	t.assert_eq(s.army(3).men_total(), 10)
	t.assert_eq(s.army(4).men_total(), 999961)
	# caso 2: la prima provincia confinante propria nell'ordine di SetNeighbours (BASSA)
	t.assert_eq(s.army(3).region, "ID_BASSA")
	t.assert_false(s.army(3).in_castle)
	t.assert_eq(s.army(3).from_region, "", "dopo la ritirata non e' piu' un attaccante")
	var retreats := _events_of(s, GameState.EV_RETREAT)
	t.assert_eq(retreats.size(), 1)
	t.assert_eq(retreats[0]["caso"], "provincia_amica")
	t.assert_eq(retreats[0]["da"], "ID_MEZZA")
	t.assert_eq(retreats[0]["a"], "ID_BASSA")
	t.assert_eq(retreats[0]["fazione"], "FN_ALPHA")
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA")
	t.assert_false(s.sieges.has("ID_MEZZA"), "nessun assedio: BETA e' in campo")
	t.assert_eq(before - _men_lost(s), _men_total(s))


func test_ritirata_caso_2_se_il_castello_e_pieno(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	_give_sola_to_beta(s)
	var full := s.create_army("FN_BETA", "ID_MEZZA", false)
	for i in 16:
		full.stacks.append(UnitStack.new("Nizari", 10, 0))
	full.in_castle = true
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	TurnProcessor.end_year(s)
	var retreats := _events_of(s, GameState.EV_RETREAT)
	t.assert_eq(retreats.size(), 1)
	t.assert_eq(retreats[0]["caso"], "provincia_amica", "il castello ha gia' 16 unita'")
	t.assert_eq(s.army(4).region, "ID_SOLA", "BASSA e' di ALPHA: la prima propria e' SOLA")
	t.assert_false(s.army(4).in_castle)


func test_capienza_del_castello_la_cavalleria_conta_doppio(t: TestContext) -> void:
	# guarnigione gia' nel castello: (cavalieri, fanti) -> peso; l'esercito 4 pesa 1 e entra solo se resta <= 16
	var cases := [[7, 1, true], [7, 2, false], [8, 0, false], [6, 3, true]]
	for item in cases:
		var knights: int = item[0]
		var foot: int = item[1]
		var fits: bool = item[2]
		var s := _world()
		s.rules.combat.forced_outcome = 1
		_give_sola_to_beta(s)
		var garrison := s.create_army("FN_BETA", "ID_MEZZA", false)
		for i in knights:
			garrison.stacks.append(UnitStack.new("Knights", 40, 0))
		for i in foot:
			garrison.stacks.append(UnitStack.new("Nizari", 40, 0))
		garrison.in_castle = true
		t.assert_eq(Combat.garrison_load(s, "ID_MEZZA"), knights * 2 + foot)
		s.declare_war("FN_ALPHA", "FN_BETA")
		_invade(s, s.army(3), "ID_MEZZA")
		TurnProcessor.end_year(s)
		var message := "%d cavalieri + %d fanti" % [knights, foot]
		t.assert_eq(s.army(4).in_castle, fits, message)
		t.assert_eq(s.army(4).region, "ID_MEZZA" if fits else "ID_SOLA", message)


func test_ritirata_senza_castello(t: TestContext) -> void:
	# senza castello non c'e' il caso 1: caso 2 se c'e' una provincia propria, altrimenti catturato
	var s := _world()
	s.rules.combat.forced_outcome = 1
	_give_sola_to_beta(s)
	s.province("ID_MEZZA").buildings.erase("CASTLE")
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_RETREAT)[0]["caso"], "provincia_amica")
	t.assert_eq(s.army(4).region, "ID_SOLA")
	t.assert_true(s.sieges.is_empty(), "nessun castello, nessun assedio")
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_ALPHA", "MEZZA e' vuota: conquista immediata")
	var s2 := _world()
	s2.rules.combat.forced_outcome = 1
	s2.province("ID_MEZZA").buildings.erase("CASTLE")
	s2.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s2, s2.army(3), "ID_MEZZA")
	TurnProcessor.end_year(s2)
	t.assert_true(s2.army(4) == null, "nessuna via: catturato")
	t.assert_eq(_events_of(s2, GameState.EV_RETREAT).size(), 0)
	t.assert_eq(_events_of(s2, GameState.EV_CAPTURED_UNITS)[0]["caso"], "nessuna_via")


func test_ritirata_caso_3_ritorno_alla_regione_di_partenza(t: TestContext) -> void:
	# BASSA e SOLA non sono di ALPHA: niente caso 2; l'attaccante perdente torna da dove e' partito
	var s := _world()
	s.rules.combat.forced_outcome = -1
	s.province("ID_BASSA").owner = "FN_REBEL"
	GameCommands.order_move(s, "FN_ALPHA", 3, PackedStringArray(["ID_MEZZA"]))
	TurnProcessor.end_year(s)
	var retreats := _events_of(s, GameState.EV_RETREAT)
	t.assert_eq(retreats.size(), 1)
	t.assert_eq(retreats[0]["caso"], "ritorno")
	t.assert_eq(retreats[0]["a"], "ID_BASSA")
	var b := _events_of(s, GameState.EV_BATTLE)[0]
	t.assert_eq(b["perdite_attaccante"], 46)
	t.assert_eq(b["perdite_difensore"], 20)
	t.assert_eq(s.army(3).region, "ID_BASSA")
	t.assert_eq(s.army(3).men_total(), 34)
	t.assert_eq(s.army(4).men_total(), 40)
	# BASSA (ribelle, senza eserciti) e' ora presidiata da ALPHA: la conquista
	t.assert_eq(s.province("ID_BASSA").owner, "FN_ALPHA")


func test_ritirata_caso_4_arrivati_dal_mare_sono_catturati(t: TestContext) -> void:
	# BASSA non e' di ALPHA (altrimenti varrebbe il caso 2, che viene prima): niente province proprie vicine
	var s := _world()
	s.rules.combat.forced_outcome = -1
	s.province("ID_BASSA").owner = "FN_REBEL"
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	s.army(3).from_region = "ID_MARE_SUD"   # sbarcato dalle navi
	var before := _men_total(s)
	TurnProcessor.end_year(s)
	t.assert_true(s.army(3) == null, "catturato")
	var captured := _events_of(s, GameState.EV_CAPTURED_UNITS)
	t.assert_eq(captured.size(), 1)
	t.assert_eq(captured[0]["caso"], "sbarco")
	t.assert_eq(captured[0]["esercito"], 3)
	t.assert_eq(captured[0]["fazione"], "FN_ALPHA")
	t.assert_eq(captured[0]["uomini"], 34, "80 - 46 caduti in battaglia")
	t.assert_eq(captured[0]["regione"], "ID_MEZZA")
	t.assert_eq(_events_of(s, GameState.EV_RETREAT).size(), 0)
	var returned := 0   # ADR-073: prigionieri riscattati o liberati tornano a casa
	for e in _events_of(s, GameState.EV_PRISONERS):
		if str(e["esito"]) == PrisonerProcessor.OUTCOME_RELEASED or str(e["esito"]) == PrisonerProcessor.OUTCOME_RANSOMED:
			returned += int(e["uomini"])
	t.assert_eq(before - _men_lost(s) + returned, _men_total(s), "i catturati sono tolti dal conto")


func test_ritirata_caso_5_nessuna_via_e_catturato(t: TestContext) -> void:
	# i ribelli di SOLA (nessun castello, nessun vicino ribelle, mai mossi) perdono: catturati
	var s := _world()
	s.rules.combat.forced_outcome = 1
	_invade(s, s.army(3), "ID_SOLA")
	TurnProcessor.end_year(s)
	var b := _events_of(s, GameState.EV_BATTLE)[0]
	t.assert_eq(b["difensore"], "FN_REBEL")
	t.assert_eq(b["perdite_difensore"], 32)
	t.assert_eq(b["perdite_attaccante"], 19)
	t.assert_eq(_events_of(s, GameState.EV_WAR_DECLARED).size(), 0, "i ribelli non dichiarano")
	var captured := _events_of(s, GameState.EV_CAPTURED_UNITS)
	t.assert_eq(captured.size(), 1)
	t.assert_eq(captured[0]["caso"], "nessuna_via")
	t.assert_eq(captured[0]["uomini"], 18)
	t.assert_true(s.army(5) == null)
	t.assert_eq(s.province("ID_SOLA").owner, "FN_ALPHA", "senza difensori la provincia cade")


func test_se_la_regione_di_partenza_e_occupata_dal_nemico_si_e_catturati(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = -1
	s.province("ID_BASSA").owner = "FN_REBEL"
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	_add_army(s, "FN_REBEL", "ID_BASSA", "Spearmen", 10)   # i ribelli presidiano la partenza
	TurnProcessor.end_year(s)
	t.assert_true(s.army(3) == null)
	t.assert_eq(_events_of(s, GameState.EV_CAPTURED_UNITS)[0]["caso"], "nessuna_via")


# --- ruoli e ordine delle battaglie ----------------------------------------------------------------


func test_attaccante_e_difensore(t: TestContext) -> void:
	# arrivati entrambi: difende il proprietario della provincia
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	_invade(s, s.army(4), "ID_MEZZA")   # BETA e' tornata in casa quest'anno
	TurnProcessor.end_year(s)
	var b := _events_of(s, GameState.EV_BATTLE)[0]
	t.assert_eq(b["attaccante"], "FN_ALPHA")
	t.assert_eq(b["difensore"], "FN_BETA")
	# nessuno e' arrivato quest'anno: difende comunque il proprietario
	var s2 := _world()
	s2.rules.combat.forced_outcome = 1
	s2.declare_war("FN_ALPHA", "FN_BETA")
	s2.army(3).region = "ID_MEZZA"
	TurnProcessor.end_year(s2)
	var b2 := _events_of(s2, GameState.EV_BATTLE)[0]
	t.assert_eq(b2["attaccante"], "FN_ALPHA")
	t.assert_eq(b2["difensore"], "FN_BETA")
	# arriva BETA in casa di ALPHA: attacca BETA
	var s3 := _world()
	s3.rules.combat.forced_outcome = 1
	s3.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s3, s3.army(4), "ID_ALTA")
	TurnProcessor.end_year(s3)
	var b3 := _events_of(s3, GameState.EV_BATTLE)[0]
	t.assert_eq(b3["attaccante"], "FN_BETA")
	t.assert_eq(b3["difensore"], "FN_ALPHA")
	t.assert_eq(b3["regione"], "ID_ALTA")


func test_tre_fazioni_si_combattono_a_coppie_nell_ordine_delle_fazioni(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = -1   # il proprietario di ALTA resiste a tutti
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(5), "ID_ALTA")   # ribelli
	_invade(s, s.army(4), "ID_ALTA")   # BETA
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0)
	var battles := _events_of(s, GameState.EV_BATTLE)
	t.assert_eq(battles.size(), 2)
	t.assert_eq(battles[0]["attaccante"], "FN_REBEL", "ordine di dichiarazione: REBEL, ALPHA, BETA")
	t.assert_eq(battles[0]["difensore"], "FN_ALPHA")
	t.assert_eq(battles[0]["perdite_attaccante"], 39)
	t.assert_eq(battles[0]["perdite_difensore"], 17)
	t.assert_eq(battles[1]["attaccante"], "FN_BETA")
	t.assert_eq(battles[1]["difensore"], "FN_ALPHA")
	t.assert_eq(s.army(1).region, "ID_ALTA")
	t.assert_true(s.army(1).men_total() < 160 - 17, "ALPHA ha combattuto due volte")
	t.assert_eq(s.army(5).region, "ID_SOLA", "i ribelli tornano da dove sono partiti")
	t.assert_eq(s.army(4).region, "ID_MEZZA")


func test_le_regioni_si_risolvono_nell_ordine_di_dichiarazione(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(1), "ID_MEZZA")    # ALTA, BASSA, MEZZA, SOLA: MEZZA viene dopo BASSA
	_invade(s, s.army(3), "ID_SOLA")     # SOLA e' dopo MEZZA
	TurnProcessor.end_year(s)
	var battles := _events_of(s, GameState.EV_BATTLE)
	t.assert_eq(battles.size(), 2)
	t.assert_eq(battles[0]["regione"], "ID_MEZZA")
	t.assert_eq(battles[1]["regione"], "ID_SOLA")


func test_il_vincitore_in_campo_guadagna_valore(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.rules.combat.valour_chance = 1.0
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(3).stacks[0].value, 1, "pila vincitrice sopravvissuta: +1")
	t.assert_eq(s.army(4).stacks[0].value, 0, "pila sconfitta: nessun guadagno")


# --- scontri navali -----------------------------------------------------------------------------------


func test_scontro_navale_vince_il_difensore(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = -1
	s.army(2).stacks[0].men = 10
	var raiders := _add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 4, true)
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, raiders, "ID_MARE_NORD")
	var before := _men_total(s)
	TurnProcessor.end_year(s)
	var battles := _events_of(s, GameState.EV_BATTLE)
	t.assert_eq(battles.size(), 1)
	var b := battles[0]
	t.assert_eq(b["scontro"], "navale")
	t.assert_eq(b["attaccante"], "FN_BETA")
	t.assert_eq(b["difensore"], "FN_ALPHA")
	_near(t, float(b["forza_attaccante"]), 7.0, "4 galee x 1,75")
	_near(t, float(b["forza_difensore"]), 17.5, "10 galee, nessun bonus in mare")
	t.assert_eq(b["perdite_attaccante"], 3)
	t.assert_eq(b["perdite_difensore"], 1)
	t.assert_true(str(b["testo"]).contains("navale"), str(b["testo"]))
	t.assert_eq(s.army(2).men_total(), 9)
	t.assert_eq(raiders.men_total(), 1)
	t.assert_eq(raiders.region, "ID_MARE_SUD", "la flotta sconfitta torna da dove e' venuta")
	var retreats := _events_of(s, GameState.EV_RETREAT)
	t.assert_eq(retreats.size(), 1)
	t.assert_eq(retreats[0]["caso"], "ritorno")
	t.assert_eq(before - _men_lost(s), _men_total(s))
	t.assert_eq(s.army(1).men_total(), 160, "le flotte non combattono con gli eserciti")


func test_scontro_navale_vince_l_attaccante(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.army(2).stacks[0].men = 10
	var raiders := _add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 4, true)
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, raiders, "ID_MARE_NORD")
	TurnProcessor.end_year(s)
	var b := _events_of(s, GameState.EV_BATTLE)[0]
	t.assert_eq(b["perdite_attaccante"], 2)
	t.assert_eq(b["perdite_difensore"], 5)
	t.assert_eq(raiders.men_total(), 2)
	t.assert_eq(raiders.region, "ID_MARE_NORD", "la flotta vincitrice resta")
	# la flotta di ALPHA, mai mossa, va nel primo mare confinante libero (ID_MARE_SUD)
	t.assert_eq(s.army(2).region, "ID_MARE_SUD")
	t.assert_eq(_events_of(s, GameState.EV_RETREAT)[0]["caso"], "mare_vicino")
	t.assert_eq(s.army(2).men_total(), 5)


func test_flotta_senza_vie_di_fuga_e_affondata(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.army(2).stacks[0].men = 10
	var raiders := _add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 4, true)
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, raiders, "ID_MARE_NORD")
	_add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 1, true)   # un'altra flotta nemica chiude l'unico mare vicino
	TurnProcessor.end_year(s)
	t.assert_true(s.army(2) == null, "affondata")
	var captured := _events_of(s, GameState.EV_CAPTURED_UNITS)
	t.assert_eq(captured.size(), 1)
	t.assert_eq(captured[0]["caso"], "nessuna_via")
	t.assert_true(str(captured[0]["testo"]).contains("affondata"), str(captured[0]["testo"]))


func test_flotte_di_fazioni_in_pace_convivono(t: TestContext) -> void:
	var s := _world()
	var other := _add_army(s, "FN_BETA", "ID_MARE_NORD", "Galley", 20, true)
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 0)
	t.assert_eq(other.men_total(), 20)


# --- attacco a una flotta precisa (richiesta di Federico, 2026-11-13) ---------------------------------------------


func test_attacco_a_una_flotta_neutrale_nella_stessa_zona(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.army(2).stacks[0].men = 10
	var other := _add_army(s, "FN_BETA", "ID_MARE_NORD", "Galley", 4, true)
	var r := GameCommands.order_naval_attack(s, "FN_ALPHA", 2, other.id)
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_true(bool(r["stessa_zona"]), "stessa zona: nessun movimento")
	t.assert_true(bool(r["guerra_nuova"]), "in pace: l'attacco e' una dichiarazione di guerra")
	t.assert_eq(r["relazione"], GameState.REL_NEUTRAL)
	t.assert_eq(s.army(2).attack_target, other.id)
	TurnProcessor.end_year(s)
	t.assert_true(s.at_war("FN_ALPHA", "FN_BETA"), "la guerra e' dichiarata")
	var battles := _events_of(s, GameState.EV_BATTLE)
	t.assert_eq(battles.size(), 1)
	t.assert_eq(battles[0]["scontro"], "navale")
	t.assert_eq(battles[0]["attaccante"], "FN_ALPHA", "attacca chi ha dato l'ordine")
	t.assert_eq(s.army(2).attack_target, 0, "l'ordine e' eseguito")


func test_la_flotta_bersaglio_che_si_sposta_non_sfugge(t: TestContext) -> void:
	# senza inseguimento le due flotte si scambierebbero di zona senza combattere
	var s := _world()
	s.rules.combat.forced_outcome = 1
	var other := _add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 4, true)
	t.assert_true(bool(GameCommands.order_naval_attack(s, "FN_ALPHA", 2, other.id)["ok"]))
	t.assert_eq(s.army(2).path, PackedStringArray(["ID_MARE_SUD"]))
	var away := _add_army(s, "FN_GAMMA", "ID_MARE_SUD", "Galley", 1, true)   # resta nella zona lasciata vuota
	GameCommands.order_move(s, "FN_BETA", other.id, PackedStringArray(["ID_MARE_NORD"]))
	s.declare_war("FN_ALPHA", "FN_BETA")
	TurnProcessor.end_year(s)
	var naval := []
	for b in _events_of(s, GameState.EV_BATTLE):
		if b["scontro"] == "navale" and ((b["eserciti_difensori"] as Array).has(other.id) or (b["eserciti_attaccanti"] as Array).has(other.id)):
			naval.append(b)
	t.assert_eq(naval.size(), 1, "lo scontro con la flotta bersaglio c'e'")
	t.assert_false(s.at_war("FN_ALPHA", "FN_GAMMA"), "la flotta di GAMMA rimasta nella zona di partenza non e' attaccata")
	t.assert_eq(away.men_total(), 1)


func test_attacco_a_una_flotta_alleata_rompe_l_alleanza(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	t.assert_true(s.form_alliance("FN_ALPHA", "FN_BETA"), "alleanza di prova")
	var other := _add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 4, true)
	var r := GameCommands.order_naval_attack(s, "FN_ALPHA", 2, other.id)
	t.assert_eq(r["relazione"], GameState.REL_ALLIANCE)
	TurnProcessor.end_year(s)
	t.assert_false(s.is_allied("FN_ALPHA", "FN_BETA"), "alleanza rotta")
	t.assert_true(s.at_war("FN_ALPHA", "FN_BETA"))
	t.assert_eq(_events_of(s, GameState.EV_ALLIANCE_BROKEN).size(), 1)
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 1)


func test_attacco_a_una_flotta_che_non_c_e_piu(t: TestContext) -> void:
	var s := _world()
	var other := _add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 4, true)
	t.assert_true(bool(GameCommands.order_naval_attack(s, "FN_ALPHA", 2, other.id)["ok"]))
	s.remove_army(other)
	var r := TurnProcessor.end_year(s)
	t.assert_eq(r["errori"], [], "nessun errore")
	t.assert_eq(s.army(2).region, "ID_MARE_NORD", "la flotta resta dov'e'")
	t.assert_eq(s.army(2).attack_target, 0)
	t.assert_false(s.at_war("FN_ALPHA", "FN_BETA"))


func test_ordine_di_attacco_navale_rifiutato(t: TestContext) -> void:
	var s := _world()
	var other := _add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 4, true)
	t.assert_false(bool(GameCommands.order_naval_attack(s, "FN_ALPHA", 1, other.id)["ok"]), "un esercito di terra non attacca flotte")
	t.assert_false(bool(GameCommands.order_naval_attack(s, "FN_BETA", 2, other.id)["ok"]), "flotta di un'altra fazione")
	t.assert_false(bool(GameCommands.order_naval_attack(s, "FN_ALPHA", 2, 4)["ok"]), "il bersaglio non e' una flotta")
	var mine := _add_army(s, "FN_ALPHA", "ID_MARE_SUD", "Galley", 1, true)
	t.assert_false(bool(GameCommands.order_naval_attack(s, "FN_ALPHA", 2, mine.id)["ok"]), "flotta propria")


func test_un_nuovo_ordine_toglie_il_bersaglio_e_il_salvataggio_lo_conserva(t: TestContext) -> void:
	var s := _world()
	var other := _add_army(s, "FN_BETA", "ID_MARE_SUD", "Galley", 4, true)
	GameCommands.order_naval_attack(s, "FN_ALPHA", 2, other.id)
	var copy := Army.from_dict(s.army(2).to_dict())
	t.assert_eq(copy.attack_target, other.id, "salvato e riletto")
	GameCommands.cancel_move(s, "FN_ALPHA", 2)
	t.assert_eq(s.army(2).attack_target, 0, "annullato")
	GameCommands.order_naval_attack(s, "FN_ALPHA", 2, other.id)
	GameCommands.order_move(s, "FN_ALPHA", 2, PackedStringArray(["ID_MARE_SUD"]))
	t.assert_eq(s.army(2).attack_target, 0, "un movimento normale sostituisce l'attacco")
	t.assert_false(Army.from_dict(s.army(2).to_dict()).to_dict().has("attacca_flotta"), "campo assente senza bersaglio")


# --- determinismo ------------------------------------------------------------------------------------------


func _war_scenario(seed_value: int) -> GameState:
	var s := _world(seed_value)
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	_invade(s, s.army(1), "ID_MEZZA")
	return s


func test_determinismo_a_parita_di_seme(t: TestContext) -> void:
	var a := _war_scenario(31)
	var b := _war_scenario(31)
	var c := _war_scenario(32)
	for i in 3:
		TurnProcessor.end_year(a)
		TurnProcessor.end_year(b)
		TurnProcessor.end_year(c)
	t.assert_eq(SaveGame.to_json(a), SaveGame.to_json(b), "stesso seme, stessa guerra")
	t.assert_true(a.rng.state != c.rng.state, "un altro seme sorteggia altri numeri")


func test_il_registro_degli_eventi_ha_i_campi_comuni(t: TestContext) -> void:
	var s := _war_scenario(5)
	TurnProcessor.end_year(s)
	var kinds := {}
	for e in s.events:
		var kind: String = e["tipo"]
		kinds[kind] = true
		if kind == GameState.EV_MOVED or kind == GameState.EV_BUILT or kind == GameState.EV_RECRUITED or kind == GameState.EV_NEGATIVE_TREASURY:
			continue   # eventi della fase 2: formattati dall'interfaccia
		t.assert_true(e.has("anno") and e.has("fazione") and e.has("regione") and e.has("testo"), "evento %s senza i campi comuni" % kind)
		t.assert_true(str(e["testo"]) != "", "evento %s senza testo" % kind)
		t.assert_eq(e["anno"], 1000)
	t.assert_true(kinds.has(GameState.EV_BATTLE))
