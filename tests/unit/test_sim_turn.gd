extends RefCounted
## Test di ogni passo del fine anno (TurnProcessor.end_year) e dell'economia (Economy) sul
## mondo piccolo tests/fixtures/sim_*.txt. Valori attesi verificati con una replica Python
## delle formule (base x 0,52 x terreno x tassa, arrotondati):
##   ALTA   agricoltura 400 x 0,52 x 1,4 (coltivazioni 2) x 1,0 = 291,2 -> 291
##          commercio (pesce 20 + grano 80) x 1,2 (Merchant2) x 0,52 = 62,4 -> 62
##   BASSA  agricoltura 300 x 0,52 x 1,2 (coltivazioni 1) = 187,2 -> 187
##          miniere oro 2 (400) + sale 1 (50) = 450
##   MEZZA  agricoltura 200 x 0,52 = 104 (nessun edificio commerciale)
##   mantenimento ALPHA 3 + 5 + 20 (nave) + 3 = 31; BETA 4
## Primo anno: ALPHA +959 (agricoltura 478, miniere 450, commercio 62, mantenimento 31), BETA +100.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world(rules: Rules = null) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var rule_set: Rules = rules if rules != null else Rules.new()
	return GameSetup.new_game(campaign, units, buildings, rule_set, 1)


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _errors(result: Dictionary) -> Array:
	var errs: Array = result["errori"]
	return errs


func _warnings(result: Dictionary) -> Array:
	var warns: Array = result["avvisi"]
	return warns


# --- reddito ------------------------------------------------------------------


func test_reddito_del_primo_anno(t: TestContext) -> void:
	var s := _world()
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]))
	t.assert_eq(res["anno"], 1001)
	t.assert_false(bool(res["finita"]))
	t.assert_eq(_errors(res).size(), 0, "nessuna anomalia")
	t.assert_eq(_warnings(res).size(), 0)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5959, "5000 - 31 + 990")
	t.assert_eq(s.faction("FN_BETA").treasury, 2100, "2000 - 4 + 104")
	t.assert_eq(s.faction("FN_REBEL").treasury, 0, "i ribelli non incassano")
	t.assert_eq(s.faction("FN_GAMMA").treasury, 0)


func test_dettaglio_del_reddito(t: TestContext) -> void:
	var s := _world()
	TurnProcessor.end_year(s)
	var alta := s.province("ID_ALTA").last_income
	t.assert_eq(alta["agricoltura"], 291)
	t.assert_eq(alta["miniere"], 0)
	t.assert_eq(alta["commercio"], 62)
	t.assert_eq(alta["totale"], 353)
	t.assert_eq(alta["conteso"], false)
	var bassa := s.province("ID_BASSA").last_income
	t.assert_eq(bassa["agricoltura"], 187)
	t.assert_eq(bassa["miniere"], 450)
	t.assert_eq(bassa["commercio"], 0, "BASSA e' nell'entroterra")
	t.assert_eq(s.province("ID_MEZZA").last_income["totale"], 104)
	t.assert_eq(s.province("ID_SOLA").last_income["totale"], 0, "provincia ribelle")
	var a := s.faction("FN_ALPHA").last_income
	t.assert_eq(a["agricoltura"], 478)
	t.assert_eq(a["miniere"], 450)
	t.assert_eq(a["commercio"], 62)
	t.assert_eq(a["mantenimento"], 31)
	t.assert_eq(a["netto"], 959)
	var b := s.faction("FN_BETA").last_income
	t.assert_eq(b["agricoltura"], 104)
	t.assert_eq(b["mantenimento"], 4)
	t.assert_eq(b["netto"], 100)


func test_livelli_di_tassa(t: TestContext) -> void:
	var s := _world()
	var expected := [218, 262, 291, 320, 364]
	for level in 5:
		GameCommands.set_tax(s, "FN_ALPHA", "ID_ALTA", level)
		var inc := Economy.province_income(s, s.province("ID_ALTA"))
		t.assert_eq(inc["agricoltura"], expected[level], "agricoltura a tassa %d" % level)
		t.assert_eq(inc["commercio"], 62, "il commercio non dipende dalla tassa")
	# le miniere non dipendono dalla tassa
	GameCommands.set_tax(s, "FN_ALPHA", "ID_BASSA", 0)
	t.assert_eq(Economy.province_income(s, s.province("ID_BASSA"))["miniere"], 450)
	GameCommands.set_tax(s, "FN_ALPHA", "ID_BASSA", 4)
	t.assert_eq(Economy.province_income(s, s.province("ID_BASSA"))["miniere"], 450)
	# la tassa 4 ad ALTA entra nel fine anno: 364 + 187 + 450 + 62 - 31 = 1032
	GameCommands.set_tax(s, "FN_ALPHA", "ID_BASSA", 2)
	TurnProcessor.end_year(s)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 6032)


func test_terreno_per_livello_delle_coltivazioni(t: TestContext) -> void:
	var s := _world()
	var alta := s.province("ID_ALTA")
	var expected := [208, 250, 291, 333, 374]   # 208 x 1,0 / 1,2 / 1,4 / 1,6 / 1,8
	for level in 5:
		if level == 0:
			alta.buildings.erase("IMPROVED_FARMLAND")
		else:
			alta.set_level("IMPROVED_FARMLAND", level)
		t.assert_eq(Economy.province_income(s, alta)["agricoltura"], expected[level], "coltivazioni %d" % level)


func test_miniere_per_livello(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	t.assert_eq(Economy.mine_income(s, bassa), 450, "oro 2 (400) + sale 1 (50)")
	bassa.set_level("GOLD_MINE", 1)
	t.assert_eq(Economy.mine_income(s, bassa), 250, "oro 1 (200) + sale 1 (50)")
	bassa.buildings.erase("GOLD_MINE")
	bassa.buildings.erase("SALT_MINE")
	t.assert_eq(Economy.mine_income(s, bassa), 0)
	var rules := Rules.new()
	rules.mine_scale = 0.5
	var s2 := _world(rules)
	t.assert_eq(Economy.province_income(s2, s2.province("ID_BASSA"))["miniere"], 225, "scala 0,5")


func test_commercio_locale_richiede_l_edificio(t: TestContext) -> void:
	var s := _world()
	var alta := s.province("ID_ALTA")
	t.assert_eq(Economy.province_income(s, alta)["commercio"], 62)
	var expected := {1: 52, 2: 62, 3: 73, 4: 83}   # 100 x (1,0 / 1,2 / 1,4 / 1,6) x 0,52
	for level in expected:
		alta.set_level("MERCHANT", int(level))
		t.assert_eq(Economy.province_income(s, alta)["commercio"], expected[level], "Merchant %d" % level)
	alta.set_level("MERCHANT", 2)
	alta.buildings.erase("PORT")
	t.assert_eq(Economy.province_income(s, alta)["commercio"], 62, "il commercio locale non richiede il porto (manuale p22)")
	s.rules.local_trade_without_port = false
	t.assert_eq(Economy.province_income(s, alta)["commercio"], 0, "con locale_senza_porto=false: come prima")
	s.rules.local_trade_without_port = true
	alta.set_level("PORT", 1)
	alta.buildings.erase("MERCHANT")
	t.assert_eq(Economy.province_income(s, alta)["commercio"], 0, "senza edificio commerciale")
	# BASSA: edifici presenti ma regione senza porto
	var bassa := s.province("ID_BASSA")
	bassa.set_level("PORT", 1)
	bassa.set_level("MERCHANT", 4)
	var inland := Economy.province_income(s, bassa)
	t.assert_true(int(inland["commercio_locale"]) > 0, "entroterra: commercio locale con il mercante (manuale p22)")
	t.assert_eq([inland["commercio_marittimo"], inland["importazioni"], inland["rotte"]], [0, 0, []], "regione senza porto: niente rotte")


func test_commercio_fattore_di_regola(t: TestContext) -> void:
	var rules := Rules.new()
	rules.trade_factor = 0.5
	var s := _world(rules)
	t.assert_eq(Economy.province_income(s, s.province("ID_ALTA"))["commercio"], 31, "62,4 x 0,5 = 31,2")


func test_provincia_contesa_senza_reddito(t: TestContext) -> void:
	var s := _world()
	var enemy := s.create_army("FN_BETA", "ID_BASSA", false)
	enemy.stacks.append(UnitStack.new("Spearmen", 10, 0))
	TurnProcessor.end_year(s)
	var bassa := s.province("ID_BASSA").last_income
	t.assert_eq(bassa["conteso"], true)
	t.assert_eq(bassa["totale"], 0)
	t.assert_eq(bassa["miniere"], 0, "anche le miniere")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5322, "5000 + (291 + 62) - 31")
	t.assert_eq(s.faction("FN_BETA").treasury, 2097, "2000 + 104 - (4 + 3 dell'esercito in terra altrui)")


func test_esercito_vuoto_non_conteso(t: TestContext) -> void:
	var s := _world()
	s.create_army("FN_BETA", "ID_BASSA", false)
	TurnProcessor.end_year(s)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5959)


func test_esercito_proprio_non_conteso(t: TestContext) -> void:
	var s := _world()
	t.assert_false(Economy.is_contested(s, s.province("ID_ALTA")))
	var guest := s.create_army("FN_ALPHA", "ID_BASSA", false)
	guest.stacks.append(UnitStack.new("Spearmen", 10, 0))
	t.assert_false(Economy.is_contested(s, s.province("ID_BASSA")))


func test_fazione_non_viva_non_incassa(t: TestContext) -> void:
	var s := _world()
	s.faction("FN_BETA").alive = false
	TurnProcessor.end_year(s)
	t.assert_eq(s.faction("FN_BETA").treasury, 2000, "ne' reddito ne' mantenimento")
	t.assert_eq(s.province("ID_MEZZA").last_income["totale"], 0)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5959)


# --- mantenimento --------------------------------------------------------------


func test_mantenimento_include_le_flotte(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(Economy.faction_upkeep(s, "FN_ALPHA"), 31, "3 + 5 + 20 + 3")
	t.assert_eq(Economy.army_support_sum(s, s.army(2)), 20, "la galea")
	t.assert_eq(Economy.faction_upkeep(s, "FN_BETA"), 4)
	t.assert_eq(Economy.faction_upkeep(s, "FN_GAMMA"), 0)


func test_mantenimento_moltiplicatore_di_regola(t: TestContext) -> void:
	var rules := Rules.new()
	rules.upkeep_multiplier = 2.0
	var s := _world(rules)
	TurnProcessor.end_year(s)
	t.assert_eq(s.faction("FN_ALPHA").last_income["mantenimento"], 62)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5928, "5000 + 990 - 62")


func test_tesoro_negativo_avvisa(t: TestContext) -> void:
	var s := _world()
	s.faction("FN_ALPHA").treasury = -2000
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]))
	t.assert_eq(s.faction("FN_ALPHA").treasury, -1041, "-2000 - 31 + 990")
	t.assert_eq(_warnings(res).size(), 1)
	t.assert_true(str(_warnings(res)[0]).contains("FN_ALPHA"))
	var evs := _events_of(s, GameState.EV_NEGATIVE_TREASURY)
	t.assert_eq(evs.size(), 1)
	t.assert_eq(evs[0]["fazione"], "FN_ALPHA")
	t.assert_eq(evs[0]["tesoro"], -1041)


func test_unita_sconosciuta_e_un_errore(t: TestContext) -> void:
	var s := _world()
	s.army(1).stacks.append(UnitStack.new("Fantasma", 10, 0))
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]), "l'anno procede")
	t.assert_eq(_errors(res).size(), 1)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5959, "l'unita' sconosciuta costa 0")


# --- costruzioni ----------------------------------------------------------------


func test_costruzione_avanza_un_elemento_alla_volta(t: TestContext) -> void:
	var s := _world()
	s.faction("FN_ALPHA").treasury = 99999
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER")
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "CHURCH")
	var q := s.province("ID_ALTA").building_queue
	t.assert_eq(s.faction("FN_ALPHA").treasury, 99599)
	TurnProcessor.end_year(s)
	t.assert_eq(q[0].years_left, 1, "il primo avanza")
	t.assert_eq(q[1].years_left, 2, "il secondo aspetta")
	t.assert_eq(s.province("ID_ALTA").level_of("BOWYER"), 0)
	t.assert_eq(_events_of(s, GameState.EV_BUILT).size(), 0)
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_ALTA").level_of("BOWYER"), 1, "completato dopo 2 anni")
	t.assert_eq(q.size(), 1)
	t.assert_eq(q[0].key, "CHURCH")
	t.assert_eq(q[0].years_left, 2, "ora comincia il secondo")
	var built := _events_of(s, GameState.EV_BUILT)
	t.assert_eq(built.size(), 1)
	t.assert_eq(built[0]["edificio"], "BOWYER")
	t.assert_eq(built[0]["provincia"], "ID_ALTA")
	t.assert_eq(built[0]["livello"], 1)
	t.assert_eq(built[0]["fazione"], "FN_ALPHA")
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_ALTA").level_of("CHURCH"), 0)
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_ALTA").level_of("CHURCH"), 1)
	t.assert_eq(q.size(), 0)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 103435, "99599 + 4 x 959: nessun altro addebito")


func test_costruzione_di_un_livello_successivo(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "IMPROVED_FARMLAND")   # 2 -> 3, 6 anni
	for i in 5:
		TurnProcessor.end_year(s)
		t.assert_eq(s.province("ID_ALTA").level_of("IMPROVED_FARMLAND"), 2, "anno %d" % (i + 1))
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_ALTA").level_of("IMPROVED_FARMLAND"), 3)
	# dal sesto anno il reddito sale: 208 x 1,6 = 332,8 -> 333
	t.assert_eq(Economy.province_income(s, s.province("ID_ALTA"))["agricoltura"], 333)


func test_costruzioni_in_province_diverse_avanzano_insieme(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER")      # 2 anni
	GameCommands.queue_building(s, "FN_ALPHA", "ID_BASSA", "SALT_MINE")  # 2 -> 4 anni
	TurnProcessor.end_year(s)
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_ALTA").level_of("BOWYER"), 1)
	t.assert_eq(s.province("ID_BASSA").building_queue[0].years_left, 2)


# --- reclutamento ----------------------------------------------------------------


func test_nuova_unita_entra_nella_guarnigione(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_ALTA").unit_queue.size(), 0)
	# dal 2026-11-10 la recluta nasce nel castello (c'e' posto): una guarnigione nuova, l'esercito in campo resta com'e'
	t.assert_eq(s.armies.size(), 6, "la guarnigione nuova")
	t.assert_eq(s.army(1).stack_count(), 2)
	var garrison := s.armies[s.armies.size() - 1]
	t.assert_true(garrison.in_castle)
	t.assert_eq(garrison.region, "ID_ALTA")
	t.assert_eq(garrison.stack_count(), 1)
	t.assert_eq(garrison.stacks[0].unit_id, "Spearmen")
	t.assert_eq(garrison.stacks[0].men, 100, "uomini del tipo")
	t.assert_eq(garrison.stacks[0].value, 0)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5859, "5000 - 100 + 959: il mantenimento parte dall'anno dopo")
	var evs := _events_of(s, GameState.EV_RECRUITED)
	t.assert_eq(evs.size(), 1)
	t.assert_eq(evs[0]["unita"], "Spearmen")
	t.assert_eq(evs[0]["esercito"], garrison.id)
	TurnProcessor.end_year(s)
	t.assert_eq(s.faction("FN_ALPHA").last_income["mantenimento"], 34, "31 + 3")


func test_guarnigione_piena_apre_un_esercito_nuovo(t: TestContext) -> void:
	var rules := Rules.new()
	rules.max_stacks = 2
	var s := _world(rules)
	t.assert_eq(s.army(1).stack_count(), 2, "guarnigione di ALTA piena")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	TurnProcessor.end_year(s)
	t.assert_eq(s.armies.size(), 6)
	var fresh := s.army(6)
	t.assert_eq(fresh.region, "ID_ALTA")
	t.assert_eq(fresh.faction, "FN_ALPHA")
	t.assert_false(fresh.is_fleet)
	t.assert_eq(fresh.stack_count(), 1)
	t.assert_eq(s.army(1).stack_count(), 2)
	# la unita' successiva riempie l'esercito nuovo
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	TurnProcessor.end_year(s)
	t.assert_eq(s.armies.size(), 6)
	t.assert_eq(fresh.stack_count(), 2)


func test_esercito_in_marcia_non_e_guarnigione(t: TestContext) -> void:
	var s := _world()
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_BASSA"]))
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(1).region, "ID_BASSA", "il movimento viene prima del reclutamento")
	t.assert_eq(s.army(1).stack_count(), 2)
	var fresh := s.army(6)
	t.assert_eq(fresh.region, "ID_ALTA")
	t.assert_eq(fresh.stack_count(), 1)


## Pile di terra della regione, dentro e fuori dal castello.
func _stacks_in(s: GameState, region: String) -> int:
	var n := 0
	for a in s.armies_in(region):
		if not a.is_fleet:
			n += a.stacks.size()
	return n


func test_reclutamento_avanza_un_elemento_alla_volta(t: TestContext) -> void:
	var s := _world()
	s.province("ID_ALTA").set_level("BOWYER", 1)
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Archers")    # 2 anni
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")   # 1 anno
	var q := s.province("ID_ALTA").unit_queue
	TurnProcessor.end_year(s)
	t.assert_eq(q[0].years_left, 1)
	t.assert_eq(q[1].years_left, 1, "la seconda non e' partita")
	t.assert_eq(_stacks_in(s, "ID_ALTA"), 2)
	TurnProcessor.end_year(s)
	t.assert_eq(_stacks_in(s, "ID_ALTA"), 3, "arrivano gli arcieri")
	var newest := s.armies[s.armies.size() - 1]
	t.assert_eq(newest.stacks[0].unit_id, "Archers")
	t.assert_eq(newest.stacks[0].men, 60)
	t.assert_eq(q.size(), 1)
	TurnProcessor.end_year(s)
	t.assert_eq(_stacks_in(s, "ID_ALTA"), 4, "poi la lancia")
	t.assert_eq(q.size(), 0)


func test_nave_nuova_entra_nella_flotta(t: TestContext) -> void:
	var s := _world()
	s.province("ID_ALTA").set_level("SHIPYARD", 1)
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Galley")   # 2 anni
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(2).stack_count(), 1)
	TurnProcessor.end_year(s)
	t.assert_eq(s.armies.size(), 5)
	t.assert_eq(s.army(2).stack_count(), 2, "la galea si unisce alla flotta in ID_MARE_NORD")
	t.assert_eq(s.army(2).stacks[1].unit_id, "Galley")
	t.assert_eq(s.army(2).stacks[1].men, 1)
	t.assert_eq(s.army(1).stack_count(), 2, "la guarnigione di terra non cambia")


func test_nave_nuova_con_la_flotta_altrove(t: TestContext) -> void:
	var s := _world()
	s.province("ID_ALTA").set_level("SHIPYARD", 1)
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Galley")
	GameCommands.order_move(s, "FN_ALPHA", 2, PackedStringArray(["ID_MARE_SUD"]))
	TurnProcessor.end_year(s)
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(2).region, "ID_MARE_SUD")
	t.assert_eq(s.armies.size(), 6, "una flotta nuova in ID_MARE_NORD")
	t.assert_eq(s.army(6).region, "ID_MARE_NORD")
	t.assert_true(s.army(6).is_fleet)


# --- movimento --------------------------------------------------------------------


func test_movimento_un_passo_per_anno(t: TestContext) -> void:
	var s := _world()
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_BASSA", "ID_MEZZA"]))
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(1).region, "ID_BASSA", "primo passo in una provincia propria")
	t.assert_eq(s.army(1).path, PackedStringArray(["ID_MEZZA"]))
	var moves := _events_of(s, GameState.EV_MOVED)
	t.assert_eq(moves.size(), 1)
	t.assert_eq(moves[0]["da"], "ID_ALTA")
	t.assert_eq(moves[0]["a"], "ID_BASSA")
	t.assert_eq(s.army(1).pending_conflict, "")


func test_passo_verso_una_regione_altrui_e_un_attacco(t: TestContext) -> void:
	# fase 3: il conflitto in sospeso non esiste piu', entrare in una regione altrui dichiara guerra e combatte
	var s := _world()
	s.rules.combat.forced_outcome = 1   # vince l'attaccante: l'esito non e' l'oggetto di questo test
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_BASSA", "ID_MEZZA"]))
	TurnProcessor.end_year(s)
	t.assert_false(s.at_war("FN_ALPHA", "FN_BETA"), "il primo passo e' in una provincia propria")
	TurnProcessor.end_year(s)
	var a := s.army(1)
	t.assert_true(a != null and a.region == "ID_MEZZA", "il secondo passo entra nella regione di BETA")
	t.assert_true(a.path.is_empty())
	t.assert_eq(a.pending_conflict, "", "il campo obsoleto non si imposta piu'")
	t.assert_true(s.at_war("FN_ALPHA", "FN_BETA"))
	t.assert_eq(_events_of(s, GameState.EV_PENDING_CONFLICT).size(), 0, "EV_PENDING_CONFLICT non si produce piu'")
	var wars := _events_of(s, GameState.EV_WAR_DECLARED)
	t.assert_eq(wars.size(), 1)
	t.assert_eq(wars[0]["fazione"], "FN_ALPHA")
	t.assert_eq(wars[0]["contro"], "FN_BETA")
	t.assert_eq(wars[0]["regione"], "ID_MEZZA")
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 1, "BETA ha un esercito in MEZZA: battaglia")
	# i ribelli sono in guerra con tutti: nessuna dichiarazione, ma l'attacco avviene
	var s2 := _world()
	s2.rules.combat.forced_outcome = 1
	s2.army(4).path = PackedStringArray(["ID_SOLA"])
	TurnProcessor.end_year(s2)
	t.assert_eq(s2.army(4).region, "ID_SOLA")
	t.assert_eq(_events_of(s2, GameState.EV_WAR_DECLARED).size(), 0, "i ribelli non si dichiarano")
	t.assert_eq(_events_of(s2, GameState.EV_BATTLE).size(), 1)
	t.assert_eq(s2.province("ID_SOLA").owner, "FN_BETA", "i ribelli sconfitti: la provincia passa a BETA")


func test_flotta_si_muove_in_mare(t: TestContext) -> void:
	var s := _world()
	GameCommands.order_move(s, "FN_ALPHA", 2, PackedStringArray(["ID_MARE_SUD", "ID_MARE_NORD"]))
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(2).region, "ID_MARE_SUD")
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(2).region, "ID_MARE_NORD")
	t.assert_true(s.army(2).path.is_empty())
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(2).region, "ID_MARE_NORD", "senza percorso resta ferma")


func test_percorso_non_valido_alla_partenza_e_un_errore(t: TestContext) -> void:
	var s := _world()
	s.army(1).path = PackedStringArray(["ID_ATLANTIDE"])
	var res := TurnProcessor.end_year(s)
	t.assert_eq(_errors(res).size(), 1)
	t.assert_true(s.army(1).path.is_empty())
	t.assert_eq(s.army(1).region, "ID_ALTA")


func test_provincia_che_cambia_proprietario_diventa_un_attacco(t: TestContext) -> void:
	var s := _world()
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_BASSA"]))
	s.province("ID_BASSA").owner = "FN_BETA"   # cambia proprietario prima del fine anno
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(1).region, "ID_BASSA", "ora entra: e' un attacco")
	t.assert_true(s.at_war("FN_ALPHA", "FN_BETA"))
	t.assert_eq(s.province("ID_BASSA").owner, "FN_ALPHA", "provincia vuota di difensori: conquista immediata")
	t.assert_eq(_events_of(s, GameState.EV_PROVINCE_CAPTURED).size(), 1)


# --- calendario ---------------------------------------------------------------------


func test_cambio_di_epoca(t: TestContext) -> void:
	var s := _world()
	s.year = 1204
	var res := TurnProcessor.end_year(s)
	t.assert_eq(res["anno"], 1205)
	t.assert_eq(s.year, 1205)
	t.assert_eq(s.era, "HIGH")
	s.year = 1320
	TurnProcessor.end_year(s)
	t.assert_eq(s.year, 1321)
	t.assert_eq(s.era, "LATE")
	s.year = 1400
	TurnProcessor.end_year(s)
	t.assert_eq(s.era, "LATE")


func test_fine_della_partita(t: TestContext) -> void:
	var s := _world()
	s.year = 1699
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]))
	t.assert_true(bool(res["finita"]))
	t.assert_eq(s.year, 1700)
	t.assert_true(s.is_finished())
	var treasury := s.faction("FN_ALPHA").treasury
	var again := TurnProcessor.end_year(s)
	t.assert_false(bool(again["ok"]), "dopo il 1700 non si va avanti")
	t.assert_eq(_errors(again).size(), 1)
	t.assert_eq(s.year, 1700)
	t.assert_eq(s.faction("FN_ALPHA").treasury, treasury, "stato invariato")


func test_settecento_anni(t: TestContext) -> void:
	var s := _world()
	var early := 0
	var high := 0
	var late := 0
	var steps := 0
	while not s.is_finished():
		var res := TurnProcessor.end_year(s)
		steps += 1
		if not bool(res["ok"]) or _errors(res).size() > 0:
			t.assert_true(false, "anno %d: %s" % [s.year, str(res)])
			return
		match s.era:
			"EARLY":
				early += 1
			"HIGH":
				high += 1
			"LATE":
				late += 1
	t.assert_eq(steps, 700)
	t.assert_eq(s.year, 1700)
	t.assert_eq(early, 204, "anni 1001-1204")
	t.assert_eq(high, 116, "anni 1205-1320")
	t.assert_eq(late, 380, "anni 1321-1700")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 676300, "5000 + 700 x 959")
	t.assert_eq(s.faction("FN_BETA").treasury, 72000, "2000 + 700 x 100")


func test_registro_degli_eventi_si_svuota(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_RECRUITED).size(), 1)
	for e in s.events:
		t.assert_eq(e["anno"], 1000, "gli eventi portano l'anno in cui sono avvenuti")
	TurnProcessor.end_year(s)
	t.assert_eq(s.events.size(), 0, "nessun evento il secondo anno")


# --- saldo reale e spese per voce (segnalazione di Federico, 2026-11-13) ------------------------------------------


func test_saldo_reale_con_le_spese(t: TestContext) -> void:
	var s := _world()
	var f := s.faction("FN_ALPHA")
	f.treasury = 5000
	f.treasury_mark = 5000
	var built := GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER")
	t.assert_true(bool(built["ok"]), str(built))
	var recruit := GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	t.assert_true(bool(recruit["ok"]), str(recruit))
	var building_cost := int(built["costo"])
	var unit_cost := int(recruit["costo"])
	t.assert_eq(f.spent, {"costruzioni": building_cost, "arruolamenti": unit_cost}, "spese registrate per voce")
	GameCommands.cancel_queue_item(s, "FN_ALPHA", "ID_ALTA", GameCommands.QUEUE_UNIT, 0)
	t.assert_eq(int(f.spent["arruolamenti"]), 0, "il rimborso toglie dalla voce")
	TurnProcessor.end_year(s)
	var li := f.last_income
	t.assert_eq(li["spese"], {"costruzioni": building_cost}, "spese dell'anno chiuse nel resoconto (le voci a zero spariscono)")
	t.assert_eq(int(li["saldo"]), f.treasury - 5000, "saldo reale = variazione del tesoro")
	t.assert_eq(int(li["saldo"]), int(li["netto"]) - building_cost, "reddito netto meno le spese")
	t.assert_true(f.spent.is_empty(), "l'anno nuovo riparte senza spese")
	t.assert_eq(f.treasury_mark, f.treasury)
	var lines := CampaignUiText.balance_lines(f)
	t.assert_true(lines[0].begins_with("Saldo dell'ultimo anno"), str(lines))
	t.assert_true("\n".join(lines).contains("Costruzioni -%d" % building_cost), str(lines))
	var back := FactionState.from_dict(f.to_dict())
	t.assert_eq(back.treasury_mark, f.treasury_mark, "salvato e riletto")
	t.assert_eq(back.last_income["spese"], li["spese"])


# --- commercio marittimo (manuale p22, richiesta di Federico del 2026-11-13) ----------------------------------------
# ALTA (ALPHA: porto, Merchant2, pesce 20 + grano 80) confina con MARE_NORD (flotta 2 di ALPHA); MEZZA (BETA: porto, spezie
# 80) confina con MARE_SUD. Con una flotta di ALPHA anche in MARE_SUD la catena arriva al porto di MEZZA:
#   marittimo    = (20 + 80) x 0,52 x 1,2 x quota 1,0 = 62,4 -> 62 (BETA non ha ne' pesce ne' grano)
#   importazioni = 80 (spezie) x 0,52 x 0,2 = 8,32 -> 8


func test_commercio_marittimo_con_la_catena_di_flotte(t: TestContext) -> void:
	var s := _world()
	s.rules.sea_trade_reference = 0.0   # ogni porto vale 1: i conti qui sotto; il peso per ricchezza nel test seguente
	var alta := s.province("ID_ALTA")
	var alone := Economy.province_income(s, alta)
	t.assert_eq(alone["rotte"], [], "la flotta in MARE_NORD da sola non raggiunge porti stranieri")
	t.assert_eq(alone["commercio"], 62, "solo il commercio locale")
	var chain := s.create_army("FN_ALPHA", "ID_MARE_SUD", true)
	chain.stacks.append(UnitStack.new("Galley", 1, 0))
	var inc := Economy.province_income(s, alta)
	t.assert_eq(inc["rotte"], ["ID_MEZZA"], "catena NORD -> SUD fino al porto di MEZZA")
	t.assert_eq(inc["commercio_locale"], 62)
	t.assert_eq(inc["commercio_marittimo"], 62)
	t.assert_eq(inc["importazioni"], 8)
	t.assert_eq(inc["commercio"], 132)
	var neutral := s.create_army("FN_GAMMA", "ID_MARE_SUD", true)
	neutral.stacks.append(UnitStack.new("Galley", 1, 0))
	t.assert_eq(Economy.province_income(s, alta)["rotte"], ["ID_MEZZA"], "una flotta neutrale non chiude la rotta")
	s.declare_war("FN_ALPHA", "FN_GAMMA")
	t.assert_eq(Economy.province_income(s, alta)["rotte"], [], "una flotta in guerra chiude la zona (blocco commerciale)")
	s.end_war("FN_ALPHA", "FN_GAMMA")
	s.declare_war("FN_ALPHA", "FN_BETA")
	t.assert_eq(Economy.province_income(s, alta)["rotte"], [], "non si commercia con chi e' in guerra")
	s.end_war("FN_ALPHA", "FN_BETA")
	s.province("ID_MEZZA").buildings.erase("PORT")
	t.assert_eq(Economy.province_income(s, alta)["rotte"], [], "serve il porto costruito del partner")
	s.province("ID_MEZZA").set_level("PORT", 1)
	alta.buildings.erase("MERCHANT")
	var no_merchant := Economy.province_income(s, alta)
	t.assert_eq([no_merchant["commercio_locale"], no_merchant["commercio_marittimo"], no_merchant["importazioni"]], [0, 0, 8],
		"senza edificio commerciale restano le importazioni (basta il porto)")
	s.rules.sea_trade = false
	alta.set_level("MERCHANT", 2)
	t.assert_eq(Economy.province_income(s, alta)["commercio"], 62, "marittimo=false: solo il locale")


# Peso dei porti secondo la ricchezza (richiesta di Federico del 2026-11-13): MEZZA vale 200 x 0,52 = 104 (niente fattorie,
# miniere ne' mercante) -> peso 104 / 500 = 0,208: merci 62,4 x 0,208 = 12,98 -> 13, importazioni 8,32 x 0,208 = 1,73 -> 2.
# Una provincia ricchissima pesa al massimo 2: merci 124,8 -> 125, importazioni 16,64 -> 17.
func test_il_porto_raggiunto_pesa_secondo_la_sua_ricchezza(t: TestContext) -> void:
	var s := _world()
	var chain := s.create_army("FN_ALPHA", "ID_MARE_SUD", true)
	chain.stacks.append(UnitStack.new("Galley", 1, 0))
	var mezza := s.province("ID_MEZZA")
	var region := s.campaign.region("ID_MEZZA")
	t.assert_true(absf(Economy.partner_value(s, mezza, region) - 104.0) < 0.01, "valore economico di MEZZA")
	t.assert_true(absf(Economy.partner_weight(s, mezza, region) - 0.208) < 0.001)
	var poor := Economy.province_income(s, s.province("ID_ALTA"))
	t.assert_eq([poor["commercio_marittimo"], poor["importazioni"]], [13, 2], "partner povero: poco")
	region.income = 100000
	var rich := Economy.province_income(s, s.province("ID_ALTA"))
	t.assert_eq([rich["commercio_marittimo"], rich["importazioni"]], [125, 17], "partner ricchissimo: al massimo il doppio")
	region.income = 200
	mezza.set_level("IMPROVED_FARMLAND", 2)
	t.assert_true(Economy.partner_weight(s, mezza, region) > 0.208, "le fattorie del partner lo rendono piu' prezioso")

