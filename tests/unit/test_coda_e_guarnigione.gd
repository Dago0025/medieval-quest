extends RefCounted
## Test della coda di reclutamento ripetuta e della guarnigione volontaria (richieste di Federico del 2026-11-09).
## Mondo piccolo tests/fixtures/sim_*.txt: ALPHA (tesoro 5000) ha ID_ALTA (Castle3) e ID_BASSA (Castle); BETA ha
## ID_MEZZA (Castle2) con l'esercito 4; l'esercito 1 e' di ALPHA in ALTA, il 3 di ALPHA in BASSA.
## Spearmen: 100 denari, 1 anno.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _keys(q: Array[QueueItem]) -> PackedStringArray:
	var out := PackedStringArray()
	for item in q:
		out.append(item.key)
	return out


func _end_year(s: GameState) -> void:
	s.events.clear()
	TurnProcessor.end_year(s)


# --- coda ripetuta ------------------------------------------------------------------------------------


func test_senza_ripetizione_la_coda_si_svuota(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	_end_year(s)
	t.assert_eq(s.province("ID_ALTA").unit_queue.size(), 0)


func test_l_unita_completata_torna_in_fondo_e_si_paga(t: TestContext) -> void:
	var s := _world()
	var p := s.province("ID_ALTA")
	p.set_level("BOWYER", 1)
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Archers")
	t.assert_true(bool(GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", true)["ok"]))
	t.assert_true(p.repeats_units())
	var before := s.faction("FN_ALPHA").treasury
	var income_before := before
	_end_year(s)
	# lo Spearmen e' nato ed e' tornato in coda dietro gli arcieri, pagato di nuovo
	t.assert_eq(_keys(p.unit_queue), PackedStringArray(["Archers", "Spearmen"]))
	t.assert_eq(p.unit_queue[1].cost_paid, 100)
	t.assert_eq(p.unit_queue[1].years_left, 1)
	t.assert_eq(_events_of(s, GameState.EV_RECRUITED).size(), 1)
	var f := s.faction("FN_ALPHA")
	var net := int(f.last_income.get("netto", 0))
	t.assert_eq(f.treasury, income_before + net - 100, "reddito dell'anno meno la nuova paga")


func test_il_giro_continua_negli_anni(t: TestContext) -> void:
	var s := _world()
	var p := s.province("ID_ALTA")
	for i in 3:
		GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", true)
	var recruited := 0
	for year in 5:
		_end_year(s)
		recruited += _events_of(s, GameState.EV_RECRUITED).size()
		t.assert_eq(p.unit_queue.size(), 3, "la coda resta piena (anno %d)" % year)
	t.assert_eq(recruited, 5, "una unita' l'anno")


func test_senza_fondi_la_coda_va_in_pausa_e_riprende(t: TestContext) -> void:
	var s := _world()
	var p := s.province("ID_ALTA")
	var f := s.faction("FN_ALPHA")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", true)
	# il tesoro dopo il reddito non basta: si azzerano le rendite togliendo i soldi dopo il calcolo
	f.treasury = -100000
	_end_year(s)
	t.assert_eq(p.unit_queue.size(), 1, "la seconda (gia' pagata) resta in coda")
	t.assert_eq(p.repeat_pending, PackedStringArray(["Spearmen"]), "la prima aspetta i fondi")
	var paused := _events_of(s, GameState.EV_QUEUE_PAUSED)
	t.assert_eq(paused.size(), 1)
	t.assert_eq(paused[0]["provincia"], "ID_ALTA")
	t.assert_eq(paused[0]["costo"], 100)
	t.assert_eq(p.unit_queue_load(), 2, "le unita' in attesa contano nella coda")
	# anno dopo: la seconda nasce e finisce anch'essa in attesa, dietro la prima; niente secondo avviso
	_end_year(s)
	t.assert_eq(p.unit_queue.size(), 0)
	t.assert_eq(p.repeat_pending, PackedStringArray(["Spearmen", "Spearmen"]))
	t.assert_eq(_events_of(s, GameState.EV_QUEUE_PAUSED).size(), 0)
	# tornano i fondi: entrambe rientrano in coda, pagate, e la coda riparte
	f.treasury = 5000
	_end_year(s)
	t.assert_true(p.repeat_pending.is_empty())
	t.assert_eq(_events_of(s, GameState.EV_QUEUE_RESUMED).size(), 1)
	t.assert_eq(_events_of(s, GameState.EV_RECRUITED).size(), 1, "la prima riparte e nasce nello stesso anno")
	t.assert_eq(p.unit_queue.size(), 2, "nata la prima, torna in fondo")


func test_coda_piena_conta_le_unita_in_attesa(t: TestContext) -> void:
	var s := _world()
	var p := s.province("ID_ALTA")
	GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", true)
	for i in 4:
		GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	p.repeat_pending = PackedStringArray(["Spearmen"])
	t.assert_false(bool(GameCommands.can_queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")["ok"]), "4 in coda + 1 in attesa = 5")
	GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", false)
	t.assert_true(p.repeat_pending.is_empty(), "spenta, le attese si dimenticano")
	t.assert_true(bool(GameCommands.can_queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")["ok"]))


func test_unita_non_piu_reclutabile_esce_dal_giro(t: TestContext) -> void:
	var s := _world()
	var p := s.province("ID_ALTA")
	p.set_level("BOWYER", 1)
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Archers")
	GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", true)
	p.buildings.erase("BOWYER")
	_end_year(s)
	_end_year(s)
	t.assert_eq(p.unit_queue.size(), 0, "senza BOWYER gli arcieri non tornano in coda")
	t.assert_eq(_events_of(s, GameState.EV_QUEUE_DROPPED).size(), 1)


func test_la_ripetizione_si_spegne_se_la_provincia_cambia_mano(t: TestContext) -> void:
	var s := _world()
	var p := s.province("ID_ALTA")
	GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", true)
	p.repeat_pending = PackedStringArray(["Spearmen"])
	p.owner = "FN_BETA"
	t.assert_false(p.repeats_units())
	t.assert_eq(p.unit_queue_load(), 0)
	_end_year(s)
	t.assert_eq(p.repeat_faction, "")
	t.assert_true(p.repeat_pending.is_empty())


func test_solo_le_proprie_province(t: TestContext) -> void:
	var s := _world()
	t.assert_false(bool(GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_MEZZA", true)["ok"]))
	t.assert_eq(s.province("ID_MEZZA").repeat_faction, "")


func test_la_coda_ripetuta_si_salva(t: TestContext) -> void:
	var s := _world()
	var p := s.province("ID_ALTA")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", true)
	p.repeat_pending = PackedStringArray(["Spearmen"])
	var copy := ProvinceState.from_dict(p.to_dict())
	t.assert_eq(copy.repeat_faction, "FN_ALPHA")
	t.assert_eq(copy.repeat_pending, PackedStringArray(["Spearmen"]))
	var plain := ProvinceState.from_dict(s.province("ID_BASSA").to_dict())
	t.assert_eq(plain.repeat_faction, "")
	t.assert_false(s.province("ID_BASSA").to_dict().has("coda_ripetuta"), "la chiave compare solo se serve")


# --- guarnigione volontaria ---------------------------------------------------------------------------


func test_ci_si_barrica_nel_castello_della_propria_provincia(t: TestContext) -> void:
	var s := _world()
	var a := s.army(4)
	var r := GameCommands.enter_castle(s, "FN_BETA", a.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_true(a.in_castle)
	t.assert_eq(r["regione"], "ID_MEZZA")
	t.assert_false(bool(GameCommands.enter_castle(s, "FN_BETA", a.id)["ok"]), "gia' dentro")
	var out := GameCommands.leave_castle(s, "FN_BETA", a.id)
	t.assert_true(bool(out["ok"]), str(out["errore"]))
	t.assert_false(a.in_castle)


func test_il_nemico_che_arriva_assedia_invece_di_combattere(t: TestContext) -> void:
	var s := _world()
	GameCommands.enter_castle(s, "FN_BETA", 4)
	s.declare_war("FN_ALPHA", "FN_BETA")
	var attacker := s.army(3)
	attacker.from_region = attacker.region
	attacker.region = "ID_MEZZA"
	attacker.arrived_year = s.year
	_end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 0, "nessuna battaglia in campo")
	t.assert_true(s.is_besieged("ID_MEZZA"))
	t.assert_true(s.army(4).in_castle)
	t.assert_false(bool(GameCommands.leave_castle(s, "FN_BETA", 4)["ok"]), "assediato non esce")


func test_senza_nemici_la_guarnigione_resta_nel_castello(t: TestContext) -> void:
	# fino al 2026-11-10 la guarnigione volontaria usciva da sola a fine anno; ora resta (le reclute nascono nel castello)
	var s := _world()
	GameCommands.enter_castle(s, "FN_BETA", 4)
	_end_year(s)
	t.assert_true(s.army(4).in_castle)


func test_barricarsi_toglie_l_ordine_di_movimento(t: TestContext) -> void:
	var s := _world()
	var a := s.army(1)
	a.path = PackedStringArray(["ID_BASSA"])
	t.assert_true(bool(GameCommands.enter_castle(s, "FN_ALPHA", a.id)["ok"]))
	t.assert_true(a.path.is_empty())


func test_quando_non_ci_si_puo_barricare(t: TestContext) -> void:
	var s := _world()
	t.assert_false(bool(GameCommands.enter_castle(s, "FN_ALPHA", 4)["ok"]), "esercito altrui")
	t.assert_false(bool(GameCommands.enter_castle(s, "FN_ALPHA", 2)["ok"]), "flotta")
	t.assert_false(bool(GameCommands.enter_castle(s, "FN_ALPHA", 999)["ok"]), "sconosciuto")
	s.province("ID_ALTA").buildings.erase("CASTLE")
	t.assert_false(bool(GameCommands.enter_castle(s, "FN_ALPHA", 1)["ok"]), "senza castello")
	# provincia altrui: ALPHA in MEZZA
	var a := s.army(3)
	a.region = "ID_MEZZA"
	t.assert_false(bool(GameCommands.enter_castle(s, "FN_ALPHA", 3)["ok"]), "castello altrui")


func test_il_castello_pieno_non_accoglie(t: TestContext) -> void:
	var s := _world()
	var a := s.army(4)
	while a.stacks.size() < 17:
		a.stacks.append(UnitStack.new(a.stacks[0].unit_id, 60, 0))
	var r := GameCommands.can_enter_castle(s, "FN_BETA", a.id)
	t.assert_false(bool(r["ok"]), "oltre 16 pile")
	t.assert_true(str(r["errore"]).contains("posto"))
