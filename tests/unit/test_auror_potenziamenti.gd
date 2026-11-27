extends RefCounted
## Potenziamenti degli Auror portati dal gioco originale (patch exe del 2026-11-09, scheda MTW del Second Brain):
## ogni pila della fazione nasce con valore 9 e la coda di reclutamento del giocatore fa 5 passaggi l'anno.
## Mondo piccolo tests/fixtures/sim_*.txt: ALPHA (tesoro 5000) ha ID_ALTA e ID_BASSA; Spearmen 100 denari, 1 anno;
## Archers 150 denari, 2 anni, con BOWYER. Nei test FN_ALPHA prende le regole che nel gioco ha FN_DANISH.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _rules_alpha(player_only: bool = true) -> Rules:
	var r := Rules.new()
	r.combat.start_valour = {"FN_ALPHA": 9}
	r.recruit_rounds = {"FN_ALPHA": 5}
	r.recruit_rounds_player_only = player_only
	return r


func _world(rules: Rules = null) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, rules if rules != null else _rules_alpha(), 1)


func _recruited(s: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == GameState.EV_RECRUITED:
			out.append(e)
	return out


func _end_year(s: GameState) -> void:
	s.events.clear()
	TurnProcessor.end_year(s)


# --- regole lette da auror.cfg --------------------------------------------------------------------------


func test_auror_cfg_valore_9_e_5_passaggi_per_gli_auror(t: TestContext) -> void:
	var r := Rules.load_file()
	t.assert_eq(r.combat.start_valour_of("FN_DANISH"), 9)
	t.assert_eq(r.combat.start_valour_of("FN_FRENCH"), 0, "le altre fazioni nascono a 0")
	t.assert_eq(r.recruit_rounds_of("FN_DANISH", true), 5)
	t.assert_eq(r.recruit_rounds_of("FN_DANISH", false), 1, "solo quando gli Auror sono del giocatore")
	t.assert_eq(r.recruit_rounds_of("FN_FRENCH", true), 1)


# --- valore iniziale ------------------------------------------------------------------------------------


func test_gli_eserciti_iniziali_della_fazione_nascono_a_valore_9(t: TestContext) -> void:
	var s := _world()
	var seen := 0
	for a in s.armies:
		for st in a.stacks:
			if a.faction == "FN_ALPHA":
				t.assert_eq(st.value, 9, "pila %s dell'esercito %d" % [st.unit_id, a.id])
				seen += 1
			else:
				t.assert_eq(st.value, 0, "le altre fazioni restano a 0")
	t.assert_true(seen > 0)


func test_le_reclute_nascono_a_valore_9(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	_end_year(s)
	var ev := _recruited(s)
	t.assert_eq(ev.size(), 1)
	var army := s.army(int(ev[0]["esercito"]))
	t.assert_eq(army.stacks[army.stacks.size() - 1].value, 9)


func test_new_stack_non_abbassa_un_valore_piu_alto_e_non_supera_il_massimo(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(s.new_stack("FN_ALPHA", "Spearmen", 100, 3).value, 9)
	t.assert_eq(s.new_stack("FN_BETA", "Spearmen", 100, 3).value, 3)
	s.rules.combat.start_valour = {"FN_ALPHA": 12}
	t.assert_eq(s.new_stack("FN_ALPHA", "Spearmen", 100).value, s.rules.combat.valour_max)


func test_il_riaddestramento_non_diluisce_il_valore_degli_auror(t: TestContext) -> void:
	var s := _world()
	var army: Army = null
	for a in s.armies_of("FN_ALPHA"):
		if not a.is_fleet and a.region == "ID_ALTA":
			army = a
	t.assert_true(army != null)
	army.stacks[0].men = 20
	var r := GameCommands.order_retrain(s, "FN_ALPHA", army.id, PackedInt32Array([0]))
	if not bool(r.get("ok", false)):
		t.skip("riaddestramento non ordinabile nel mondo di prova: %s" % str(r.get("errore", "")))
		return
	_end_year(s)
	t.assert_eq(army.stacks[0].value, 9)


# --- passaggi della coda --------------------------------------------------------------------------------


func test_il_giocatore_completa_fino_a_5_unita_da_un_anno(t: TestContext) -> void:
	var s := _world()
	s.faction("FN_ALPHA").is_player = true
	for i in 5:
		t.assert_true(bool(GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")["ok"]))
	_end_year(s)
	t.assert_eq(_recruited(s).size(), 5)
	t.assert_eq(s.province("ID_ALTA").unit_queue.size(), 0)


func test_l_ia_resta_a_un_passaggio(t: TestContext) -> void:
	var s := _world()
	s.faction("FN_ALPHA").is_player = false
	for i in 3:
		GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	_end_year(s)
	t.assert_eq(_recruited(s).size(), 1)
	t.assert_eq(s.province("ID_ALTA").unit_queue.size(), 2)


func test_le_unita_lunghe_vanno_piu_veloci(t: TestContext) -> void:
	var s := _world()
	s.faction("FN_ALPHA").is_player = true
	s.province("ID_ALTA").set_level("BOWYER", 1)
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Archers")   # 2 anni = 2 passaggi
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Archers")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Archers")
	_end_year(s)
	# 5 passaggi: due arcieri completi (4 passaggi), il terzo a meta'
	t.assert_eq(_recruited(s).size(), 2)
	var q := s.province("ID_ALTA").unit_queue
	t.assert_eq(q.size(), 1)
	t.assert_eq(q[0].years_left, 1)


func test_coda_ripetuta_una_unita_ripagata_5_volte(t: TestContext) -> void:
	var s := _world()
	var f := s.faction("FN_ALPHA")
	f.is_player = true
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", true)
	var before := f.treasury
	_end_year(s)
	t.assert_eq(_recruited(s).size(), 5)
	var p := s.province("ID_ALTA")
	t.assert_eq(p.unit_queue.size(), 1, "l'unita' resta in coda per l'anno dopo, gia' pagata")
	var net := int(f.last_income.get("netto", 0))
	t.assert_eq(f.treasury, before + net - 5 * 100, "cinque nuove paghe")


func test_coda_ripetuta_senza_fondi_si_ferma(t: TestContext) -> void:
	var s := _world()
	var f := s.faction("FN_ALPHA")
	f.is_player = true
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", true)
	f.treasury = 0
	_end_year(s)
	# il reddito dell'anno arriva prima del reclutamento: si paga finche' basta, poi la coda va in pausa
	t.assert_true(_recruited(s).size() >= 1)
	t.assert_true(f.treasury >= 0, "il tesoro non va sotto zero")


func test_regola_estesa_anche_all_ia_se_non_solo_giocatore(t: TestContext) -> void:
	var s := _world(_rules_alpha(false))
	s.faction("FN_ALPHA").is_player = false
	for i in 3:
		GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	_end_year(s)
	t.assert_eq(_recruited(s).size(), 3)


## Gli Auror e solo loro arruolano ogni truppa e nave (richiesta di Federico dell'11/11): cadono fazione, epoca, regione
## e cultura; agenti e crociate seguono le loro regole.
func test_gli_auror_arruolano_ogni_unita(t: TestContext) -> void:
	var r := Rules.load_file()
	t.assert_true(r.all_units_factions.has("FN_DANISH"), "tutte_le_unita in auror.cfg")
	var troop := UnitType.new("Prova")
	troop.type_name = UnitType.INFANTRY
	troop.factions = PackedStringArray(["FN_FRENCH"])
	troop.periods = PackedStringArray(["LATE"])
	troop.regions = PackedStringArray(["ID_ILE_DE_FRANCE"])
	t.assert_true(r.lifts_unit_limits("FN_DANISH", troop), "truppa di un'altra fazione, epoca e regione")
	t.assert_true(r.lifts_unit_limits("fn_danish", troop))
	t.assert_false(r.lifts_unit_limits("FN_FRENCH", troop), "solo gli Auror")
	var agent := UnitType.new("Spia")
	agent.type_name = "SPY"
	t.assert_false(r.lifts_unit_limits("FN_DANISH", agent), "gli agenti no")
	t.assert_false(r.lifts_unit_limits("FN_DANISH", null))
