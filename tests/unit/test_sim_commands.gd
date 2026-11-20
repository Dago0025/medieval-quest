extends RefCounted
## Test di GameCommands su un mondo piccolo (tests/fixtures/sim_*.txt):
## ALPHA (tesoro 5000) ha ID_ALTA (porto, Castle3, coltivazioni 2, Merchant2) e ID_BASSA
## (Castle, miniere d'oro 2 e di sale 1, entroterra); BETA (tesoro 2000, islamica) ha ID_MEZZA.
## Esercito 1 = ALPHA in ALTA, 2 = flotta ALPHA in ID_MARE_NORD, 3 = ALPHA in BASSA, 4 = BETA in MEZZA.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


## Verifica che il comando sia riuscito (ok vero e errore vuoto).
func _expect_ok(t: TestContext, result: Dictionary, what: String) -> void:
	t.assert_true(bool(result["ok"]), "%s: doveva riuscire (%s)" % [what, str(result["errore"])])
	t.assert_eq(str(result["errore"]), "", "%s: errore vuoto" % what)


## Verifica che il comando sia fallito, con un messaggio in italiano.
func _expect_fail(t: TestContext, result: Dictionary, what: String) -> void:
	t.assert_false(bool(result["ok"]), "%s: doveva fallire" % what)
	t.assert_true(str(result["errore"]) != "", "%s: serve un messaggio d'errore" % what)


# --- set_tax -------------------------------------------------------------------


func test_tassa_valida(t: TestContext) -> void:
	var s := _world()
	for level in 5:
		_expect_ok(t, GameCommands.set_tax(s, "FN_ALPHA", "ID_ALTA", level), "tassa %d" % level)
		t.assert_eq(s.province("ID_ALTA").tax_level, level)


func test_tassa_non_valida(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.set_tax(s, "FN_ALPHA", "ID_ALTA", 5), "livello 5")
	_expect_fail(t, GameCommands.set_tax(s, "FN_ALPHA", "ID_ALTA", -1), "livello -1")
	t.assert_eq(s.province("ID_ALTA").tax_level, 2, "invariata")


func test_tassa_solo_proprie_province(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.set_tax(s, "FN_ALPHA", "ID_MEZZA", 4), "provincia di BETA")
	_expect_fail(t, GameCommands.set_tax(s, "FN_ALPHA", "ID_SOLA", 4), "provincia dei ribelli")
	_expect_fail(t, GameCommands.set_tax(s, "FN_ALPHA", "ID_NESSUNA", 4), "provincia sconosciuta")
	_expect_fail(t, GameCommands.set_tax(s, "FN_ALPHA", "ID_MARE_NORD", 4), "il mare non e' una provincia")
	_expect_fail(t, GameCommands.set_tax(s, "FN_NESSUNA", "ID_ALTA", 4), "fazione sconosciuta")
	_expect_fail(t, GameCommands.set_tax(s, "FN_GAMMA", "ID_ALTA", 4), "fazione non attiva")
	_expect_fail(t, GameCommands.set_tax(s, "FN_REBEL", "ID_SOLA", 4), "i ribelli non giocano")
	t.assert_eq(s.province("ID_MEZZA").tax_level, 2)
	t.assert_eq(s.province("ID_ALTA").tax_level, 2)


func test_id_senza_distinzione_di_maiuscole(t: TestContext) -> void:
	var s := _world()
	_expect_ok(t, GameCommands.set_tax(s, "fn_alpha", "id_alta", 3), "minuscole")
	t.assert_eq(s.province("ID_ALTA").tax_level, 3)


# --- queue_building -----------------------------------------------------------


func test_costruzione_in_coda_paga_subito(t: TestContext) -> void:
	var s := _world()
	var r := GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER")
	_expect_ok(t, r, "BOWYER")
	t.assert_eq(r["livello"], 1)
	t.assert_eq(r["costo"], 200)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 4800, "costo pagato all'accodamento")
	var q := s.province("ID_ALTA").building_queue
	t.assert_eq(q.size(), 1)
	t.assert_eq(q[0].kind, QueueItem.KIND_BUILDING)
	t.assert_eq(q[0].key, "BOWYER")
	t.assert_eq(q[0].level, 1)
	t.assert_eq(q[0].years_left, 2)
	t.assert_eq(q[0].cost_paid, 200)
	t.assert_eq(s.province("ID_ALTA").level_of("BOWYER"), 0, "non ancora costruito")


func test_costruzione_prossimo_livello(t: TestContext) -> void:
	var s := _world()
	var r := GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "improved_farmland")
	_expect_ok(t, r, "coltivazioni 3")
	t.assert_eq(r["livello"], 3, "da 2 a 3")
	t.assert_eq(r["costo"], 1500)
	t.assert_eq(s.province("ID_ALTA").building_queue[0].years_left, 6)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 3500)


func test_costruzione_livello_massimo(t: TestContext) -> void:
	var s := _world()
	s.province("ID_ALTA").set_level("IMPROVED_FARMLAND", 4)
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "IMPROVED_FARMLAND"), "oltre il livello 4")
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "PORT"), "porto gia' costruito (un solo livello)")


func test_costruzione_stessa_famiglia_due_volte(t: TestContext) -> void:
	var s := _world()
	_expect_ok(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER"), "prima")
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER"), "seconda")
	t.assert_eq(s.province("ID_ALTA").building_queue.size(), 1)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 4800, "nessun secondo addebito")


func test_costruzione_famiglia_sconosciuta(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "TORRE_DI_BABELE"), "famiglia sconosciuta")


func test_costruzione_requisiti_e_livello_almeno_n(t: TestContext) -> void:
	var s := _world()
	# ARMOURER richiede {{CASTLE2,BOWYER},{CASTLE4}}: Castle3 c'e' (>= 2) ma manca BOWYER
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "ARMOURER"), "manca BOWYER")
	s.province("ID_ALTA").set_level("BOWYER", 1)
	_expect_ok(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "ARMOURER"), "CASTLE3 soddisfa CASTLE2, con BOWYER")
	# secondo gruppo (OR): solo Castle4
	var s2 := _world()
	s2.province("ID_ALTA").set_level("CASTLE", 4)
	_expect_ok(t, GameCommands.queue_building(s2, "FN_ALPHA", "ID_ALTA", "ARMOURER"), "CASTLE4 da solo")
	# livello uguale al richiesto: UNIVERSITY chiede CASTLE3
	var s3 := _world()
	_expect_ok(t, GameCommands.queue_building(s3, "FN_ALPHA", "ID_ALTA", "UNIVERSITY"), "Castle3 = richiesto")
	_expect_fail(t, GameCommands.queue_building(s3, "FN_ALPHA", "ID_BASSA", "UNIVERSITY"), "Castle1 < 3")


func test_costruzione_requisito_senza_castello(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(s.province("ID_SOLA").level_of("CASTLE"), 0)
	var r := GameCommands.requirements_met(s.buildings.get_family("BOWYER").get_level(1).requires, s.province("ID_SOLA"), s.buildings)
	t.assert_false(r, "BOWYER richiede {CASTLE}")
	var none: Array[PackedStringArray] = []
	t.assert_true(GameCommands.requirements_met(none, s.province("ID_SOLA"), s.buildings), "nessun requisito")


func test_costruzione_fazione_ammessa(t: TestContext) -> void:
	var s := _world()
	# GUNSMITH e' solo di FN_BETA
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "GUNSMITH"), "ALPHA non puo'")
	var r := GameCommands.queue_building(s, "FN_BETA", "ID_MEZZA", "GUNSMITH")
	_expect_ok(t, r, "BETA puo'")
	t.assert_eq(s.faction("FN_BETA").treasury, 1600)


func test_costruzione_religione(t: TestContext) -> void:
	var s := _world()
	_expect_ok(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "CHURCH"), "chiesa cattolica")
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_BASSA", "MOSQUE"), "moschea per i cattolici")
	_expect_ok(t, GameCommands.queue_building(s, "FN_BETA", "ID_MEZZA", "MOSQUE"), "moschea islamica")
	_expect_fail(t, GameCommands.queue_building(s, "FN_BETA", "ID_MEZZA", "CHURCH"), "chiesa per gli islamici")
	t.assert_eq(GameCommands.religion_key("REL_ISLAMIC"), "MUSLIM")
	t.assert_eq(GameCommands.religion_key("rel_orthodox"), "ORTHODOX")


func test_costruzione_risorsa_nella_regione(t: TestContext) -> void:
	var s := _world()
	# BASSA ha oro e sale: SALT_MINE passa da 1 a 2
	var r := GameCommands.queue_building(s, "FN_ALPHA", "ID_BASSA", "SALT_MINE")
	_expect_ok(t, r, "miniera di sale")
	t.assert_eq(r["costo"], 400)
	# ALTA non ha oro
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "GOLD_MINE"), "senza la risorsa")


func test_costruzione_porto_solo_sulla_costa(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_BASSA", "PORT"), "BASSA e' nell'entroterra")
	# MEZZA ha il porto (SetPort): se l'edificio manca si puo' costruire
	s.province("ID_MEZZA").buildings.erase("PORT")
	_expect_ok(t, GameCommands.queue_building(s, "FN_BETA", "ID_MEZZA", "PORT"), "MEZZA ha il porto")


func test_costruzione_tesoro_insufficiente(t: TestContext) -> void:
	var s := _world()
	s.faction("FN_ALPHA").treasury = 199
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER"), "199 < 200")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 199, "nessun addebito")
	t.assert_eq(s.province("ID_ALTA").building_queue.size(), 0)
	s.faction("FN_ALPHA").treasury = 200
	_expect_ok(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER"), "200 = 200")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 0, "il tesoro arriva a zero ma non sotto")


func test_costruzione_coda_piena(t: TestContext) -> void:
	var s := _world()
	s.faction("FN_ALPHA").treasury = 99999
	for family in ["IMPROVED_FARMLAND", "BOWYER", "CHURCH", "UNIVERSITY"]:
		_expect_ok(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", family), family)
	t.assert_eq(s.province("ID_ALTA").building_queue.size(), 4)
	var before := s.faction("FN_ALPHA").treasury
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "MERCHANT"), "quinta voce")
	t.assert_eq(s.faction("FN_ALPHA").treasury, before)
	t.assert_eq(s.province("ID_ALTA").building_queue.size(), 4)
	# l'altra provincia ha la sua coda
	_expect_ok(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_BASSA", "SALT_MINE"), "coda di BASSA")


func test_costruzione_provincia_altrui(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_MEZZA", "BOWYER"), "provincia di BETA")
	_expect_fail(t, GameCommands.queue_building(s, "FN_GAMMA", "ID_ALTA", "BOWYER"), "fazione non attiva")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5000)


func test_can_queue_building_non_modifica(t: TestContext) -> void:
	var s := _world()
	var r := GameCommands.can_queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER")
	_expect_ok(t, r, "controllo")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5000)
	t.assert_eq(s.province("ID_ALTA").building_queue.size(), 0)


# --- cancel_queue_item --------------------------------------------------------


func test_annulla_costruzione_rimborsa(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER")
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "CHURCH")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 4600)
	var r := GameCommands.cancel_queue_item(s, "FN_ALPHA", "ID_ALTA", GameCommands.QUEUE_BUILDING, 0)
	_expect_ok(t, r, "annulla la prima")
	t.assert_eq(r["rimborso"], 200)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 4800)
	var q := s.province("ID_ALTA").building_queue
	t.assert_eq(q.size(), 1)
	t.assert_eq(q[0].key, "CHURCH", "resta la seconda")


func test_annulla_perde_i_progressi(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER")
	s.province("ID_ALTA").building_queue[0].years_left = 1
	GameCommands.cancel_queue_item(s, "FN_ALPHA", "ID_ALTA", GameCommands.QUEUE_BUILDING, 0)
	_expect_ok(t, GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER"), "di nuovo")
	t.assert_eq(s.province("ID_ALTA").building_queue[0].years_left, 2, "si riparte da capo")


func test_annulla_reclutamento(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 4900)
	var r := GameCommands.cancel_queue_item(s, "FN_ALPHA", "ID_ALTA", GameCommands.QUEUE_UNIT, 0)
	_expect_ok(t, r, "annulla reclutamento")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5000)
	t.assert_eq(s.province("ID_ALTA").unit_queue.size(), 0)


func test_annulla_errori(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER")
	_expect_fail(t, GameCommands.cancel_queue_item(s, "FN_ALPHA", "ID_ALTA", GameCommands.QUEUE_BUILDING, 1), "indice oltre la coda")
	_expect_fail(t, GameCommands.cancel_queue_item(s, "FN_ALPHA", "ID_ALTA", GameCommands.QUEUE_BUILDING, -1), "indice negativo")
	_expect_fail(t, GameCommands.cancel_queue_item(s, "FN_ALPHA", "ID_ALTA", GameCommands.QUEUE_UNIT, 0), "coda di reclutamento vuota")
	_expect_fail(t, GameCommands.cancel_queue_item(s, "FN_ALPHA", "ID_ALTA", "magazzino", 0), "coda sconosciuta")
	_expect_fail(t, GameCommands.cancel_queue_item(s, "FN_BETA", "ID_ALTA", GameCommands.QUEUE_BUILDING, 0), "provincia altrui")
	t.assert_eq(s.province("ID_ALTA").building_queue.size(), 1)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 4800)


# --- queue_unit ---------------------------------------------------------------


func test_reclutamento_in_coda_paga_subito(t: TestContext) -> void:
	var s := _world()
	var r := GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "spearmen")
	_expect_ok(t, r, "Spearmen")
	t.assert_eq(r["costo"], 100)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 4900)
	var q := s.province("ID_ALTA").unit_queue
	t.assert_eq(q.size(), 1)
	t.assert_eq(q[0].kind, QueueItem.KIND_UNIT)
	t.assert_eq(q[0].key, "Spearmen", "id come nel file prod")
	t.assert_eq(q[0].years_left, 1)
	t.assert_eq(q[0].cost_paid, 100)


func test_reclutamento_requisiti_in_edifici(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Archers"), "manca BOWYER")
	s.province("ID_ALTA").set_level("BOWYER", 1)
	var r := GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Archers")
	_expect_ok(t, r, "con BOWYER")
	t.assert_eq(r["anni"], 2)
	t.assert_eq(s.faction("FN_ALPHA").treasury, 4850)


func test_reclutamento_epoca(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Knights"), "i cavalieri sono HIGH/LATE")
	s.era = "HIGH"
	var r := GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Knights")
	_expect_ok(t, r, "in epoca HIGH (Castle3 soddisfa il primo gruppo)")
	t.assert_eq(r["costo"], 400)
	t.assert_eq(r["anni"], 3)
	# BASSA: Castle1 non basta ne' per CASTLE3 ne' per CASTLE2+BOWYER2
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_BASSA", "Knights"), "Castle1")


func test_reclutamento_navi(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Galley"), "manca SHIPYARD1")
	s.province("ID_ALTA").set_level("SHIPYARD", 1)
	_expect_ok(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Galley"), "con il cantiere")
	s.province("ID_BASSA").set_level("SHIPYARD", 1)
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_BASSA", "Galley"), "entroterra, senza porto")


func test_reclutamento_fazione_regione_cultura(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Nizari"), "solo FN_BETA")
	_expect_ok(t, GameCommands.queue_unit(s, "FN_BETA", "ID_MEZZA", "Nizari"), "BETA")
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Alpine"), "solo ID_BASSA")
	_expect_ok(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_BASSA", "Alpine"), "in BASSA")
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "GreekHoplite"), "cultura cattolica")
	_expect_ok(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_BASSA", "GreekHoplite"), "cultura ortodossa")
	t.assert_eq(GameCommands.culture_key("ORTHODOX_CULTURE"), "ORTHODOX")
	t.assert_eq(GameCommands.culture_key("pagan"), "PAGAN")


func test_reclutamento_tipi_non_reclutabili(t: TestContext) -> void:
	var s := _world()
	# fase 5a: l'emissario e' un agente reclutabile (nasce alla fine della coda); la principessa nasce con la dinastia
	_expect_ok(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Emissary"), "emissario")
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Princess"), "principessa")
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Camel"), "cavalcatura")
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Drago"), "sconosciuta")
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "NoFactions"), "senza fazioni ammesse")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5000)


func test_reclutamento_tesoro_e_coda(t: TestContext) -> void:
	var s := _world()
	s.faction("FN_ALPHA").treasury = 99
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen"), "99 < 100")
	t.assert_eq(s.faction("FN_ALPHA").treasury, 99)
	s.faction("FN_ALPHA").treasury = 99999
	for i in 5:
		_expect_ok(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen"), "voce %d" % (i + 1))
	var before := s.faction("FN_ALPHA").treasury
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen"), "sesta voce")
	t.assert_eq(s.faction("FN_ALPHA").treasury, before)
	t.assert_eq(s.province("ID_ALTA").unit_queue.size(), 5)


func test_reclutamento_provincia_altrui(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_MEZZA", "Spearmen"), "provincia di BETA")
	_expect_fail(t, GameCommands.queue_unit(s, "FN_ALPHA", "ID_NESSUNA", "Spearmen"), "provincia sconosciuta")


# --- order_move ---------------------------------------------------------------


func test_movimento_valido(t: TestContext) -> void:
	var s := _world()
	var r := GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_BASSA"]))
	_expect_ok(t, r, "un passo")
	t.assert_eq(s.army(1).path, PackedStringArray(["ID_BASSA"]))
	_expect_ok(t, GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["id_bassa", "id_mezza"])), "due passi in minuscolo")
	t.assert_eq(s.army(1).path, PackedStringArray(["ID_BASSA", "ID_MEZZA"]), "ID normalizzati")
	t.assert_eq(s.army(1).region, "ID_ALTA", "l'ordine non muove subito")


func test_movimento_passi_non_adiacenti(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_MEZZA"])), "ALTA non confina con MEZZA")
	_expect_fail(t, GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_BASSA", "ID_SOLA"])), "BASSA non confina con SOLA")
	_expect_fail(t, GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_ALTA"])), "la posizione attuale")
	t.assert_true(s.army(1).path.is_empty(), "un ordine non valido non cambia il percorso")


func test_movimento_terra_e_mare(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_MARE_NORD"])), "un esercito di terra in mare")
	_expect_ok(t, GameCommands.order_move(s, "FN_ALPHA", 2, PackedStringArray(["ID_MARE_SUD"])), "flotta in mare")
	_expect_ok(t, GameCommands.order_move(s, "FN_ALPHA", 2, PackedStringArray(["ID_MARE_SUD", "ID_MARE_NORD"])), "flotta avanti e indietro")
	_expect_fail(t, GameCommands.order_move(s, "FN_ALPHA", 2, PackedStringArray(["ID_ALTA"])), "una flotta a terra")
	_expect_fail(t, GameCommands.order_move(s, "FN_ALPHA", 2, PackedStringArray(["ID_MARE_SUD", "ID_MEZZA"])), "sbarco a meta' percorso")


func test_movimento_errori(t: TestContext) -> void:
	var s := _world()
	_expect_fail(t, GameCommands.order_move(s, "FN_ALPHA", 99, PackedStringArray(["ID_BASSA"])), "esercito sconosciuto")
	_expect_fail(t, GameCommands.order_move(s, "FN_BETA", 1, PackedStringArray(["ID_BASSA"])), "esercito di un'altra fazione")
	_expect_fail(t, GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray()), "percorso vuoto")
	_expect_fail(t, GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_ATLANTIDE"])), "regione sconosciuta")
	_expect_fail(t, GameCommands.order_move(s, "FN_ALPHA", 5, PackedStringArray(["ID_MEZZA"])), "esercito dei ribelli")


func test_movimento_annulla(t: TestContext) -> void:
	var s := _world()
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_BASSA"]))
	s.army(1).pending_conflict = "ID_MEZZA"
	_expect_fail(t, GameCommands.cancel_move(s, "FN_BETA", 1), "esercito altrui")
	_expect_ok(t, GameCommands.cancel_move(s, "FN_ALPHA", 1), "annulla")
	t.assert_true(s.army(1).path.is_empty())
	t.assert_eq(s.army(1).pending_conflict, "")
	_expect_fail(t, GameCommands.cancel_move(s, "FN_ALPHA", 99), "sconosciuto")


func test_nuovo_ordine_azzera_il_conflitto_in_sospeso(t: TestContext) -> void:
	var s := _world()
	s.army(3).pending_conflict = "ID_MEZZA"
	_expect_ok(t, GameCommands.order_move(s, "FN_ALPHA", 3, PackedStringArray(["ID_ALTA"])), "nuovo ordine")
	t.assert_eq(s.army(3).pending_conflict, "")
