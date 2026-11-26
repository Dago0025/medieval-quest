extends RefCounted
## Test della logica pura dell'interfaccia per il trasporto via mare (spec. fase 3 par. 9): tratteggio
## della freccia, province da evidenziare, regioni lungo cui si disegna la catena, testi degli
## eventi e dei messaggi d'errore. Mondo: tests/fixtures/transport_startpos.txt
## (PORTA e ENTRO di ALPHA, FARO di BETA, zone MARE_UNO..QUATTRO; esercito 1 = ALPHA in PORTA).

const STARTPOS := "res://tests/fixtures/transport_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const ArmyLayerScript := preload("res://scenes/army_layer.gd")
const EPS := 1.0e-4


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)
	s.rules.combat.blockade_needs_more_ships = false   # regola di base del blocco (la superiorita' di navi ha i suoi test)
	return s


func _fleet(s: GameState, faction_id: String, zone: String) -> Army:
	var a := s.create_army(faction_id, zone, true)
	a.stacks.append(UnitStack.new("Galley", 1, 0))
	return a


func _ev(const_name: String, data: Dictionary) -> Dictionary:
	var e := {"tipo": CampaignUiText.event_kind(const_name), "anno": 1000}
	e.merge(data)
	return e


func _length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


# --- tratteggio della freccia ----------------------------------------------------------------------


func test_tratteggio_su_una_retta(t: TestContext) -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	var pieces := MarkerLayout.dashed_segments(line, 10.0, 10.0)
	t.assert_eq(pieces.size(), 5, "tratti da 10 ogni 20 su 100")
	t.assert_true(pieces[0][0].is_equal_approx(Vector2(0, 0)) and pieces[0][1].is_equal_approx(Vector2(10, 0)), "primo tratto")
	t.assert_true(pieces[1][0].is_equal_approx(Vector2(20, 0)) and pieces[1][1].is_equal_approx(Vector2(30, 0)), "secondo tratto")
	t.assert_true(pieces[4][0].is_equal_approx(Vector2(80, 0)) and pieces[4][1].is_equal_approx(Vector2(90, 0)), "ultimo tratto")
	var drawn := 0.0
	for p in pieces:
		drawn += _length(p)
	t.assert_true(absf(drawn - 50.0) < EPS, "meta' della linea e' disegnata: %s" % str(drawn))


func test_il_tratto_segue_gli_angoli(t: TestContext) -> void:
	var bent := PackedVector2Array([Vector2(0, 0), Vector2(15, 0), Vector2(15, 15)])
	var pieces := MarkerLayout.dashed_segments(bent, 20.0, 5.0)
	t.assert_eq(pieces.size(), 2)
	t.assert_eq(pieces[0].size(), 3, "il primo tratto gira l'angolo")
	t.assert_true(pieces[0][1].is_equal_approx(Vector2(15, 0)) and pieces[0][2].is_equal_approx(Vector2(15, 5)))
	t.assert_true(absf(_length(pieces[0]) - 20.0) < EPS)
	t.assert_true(pieces[1][0].is_equal_approx(Vector2(15, 10)) and pieces[1][1].is_equal_approx(Vector2(15, 15)), "il secondo arriva in fondo")


func test_tratteggio_casi_limite(t: TestContext) -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(50, 0)])
	t.assert_eq(MarkerLayout.dashed_segments(PackedVector2Array(), 10.0, 5.0).size(), 0, "nessun punto")
	t.assert_eq(MarkerLayout.dashed_segments(PackedVector2Array([Vector2(1, 1)]), 10.0, 5.0).size(), 0, "un punto")
	t.assert_eq(MarkerLayout.dashed_segments(line, 0.0, 5.0).size(), 0, "tratto nullo")
	var solid := MarkerLayout.dashed_segments(line, 10.0, 0.0)
	t.assert_eq(solid.size(), 1, "senza vuoti la linea e' continua")
	t.assert_eq(solid[0], line)
	var short := MarkerLayout.dashed_segments(PackedVector2Array([Vector2(0, 0), Vector2(4, 0)]), 10.0, 5.0)
	t.assert_eq(short.size(), 1, "linea piu' corta di un tratto")
	t.assert_true(absf(_length(short[0]) - 4.0) < EPS)
	var same := MarkerLayout.dashed_segments(PackedVector2Array([Vector2(3, 3), Vector2(3, 3), Vector2(13, 3)]), 4.0, 4.0)
	t.assert_true(same.size() >= 1, "punti coincidenti non rompono il tratteggio")


# --- livello delle frecce ---------------------------------------------------------------------------


func test_il_livello_registra_frecce_tratteggiate_e_province_evidenziate(t: TestContext) -> void:
	var layer: ArmyLayerScript = ArmyLayerScript.new()
	var points := PackedVector2Array([Vector2(0, 0), Vector2(50, 0), Vector2(90, 40)])
	layer.add_arrow(points, true, false)
	layer.add_arrow(points, true, true, true)
	t.assert_eq(layer.arrow_count(), 2)
	t.assert_false(layer.arrow_is_dashed(0), "freccia normale")
	t.assert_true(layer.arrow_is_dashed(1), "freccia del trasporto")
	t.assert_false(layer.arrow_is_dashed(5), "indice fuori misura")
	layer.add_reach_mark(Vector2(10, 10))
	layer.add_reach_mark(Vector2(20, 20))
	t.assert_eq(layer.reach_count(), 2)
	layer.clear_all()
	t.assert_eq(layer.reach_count(), 0, "clear_all svuota le province evidenziate")
	layer.free()
	# lo sbarco ostile resta rosso anche se tratteggiato
	t.assert_true(ArmyLayerScript.arrow_color(true, true).r > 0.8)


# --- province evidenziate e catena --------------------------------------------------------------------


func test_province_raggiungibili_via_mare_per_l_interfaccia(t: TestContext) -> void:
	var s := _world()
	var army := s.army(1)
	t.assert_eq(CampaignUiText.sea_reachable(s, army, "FN_ALPHA"), PackedStringArray(["ID_SENZAPORTO"]), "con la sola flotta di UNO")
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	t.assert_eq(CampaignUiText.sea_reachable(s, army, "FN_ALPHA"), PackedStringArray(["ID_SENZAPORTO", "ID_FARO"]))
	t.assert_true(CampaignUiText.sea_reachable(s, army, "FN_BETA").is_empty(), "non e' un esercito del giocatore")
	t.assert_true(CampaignUiText.sea_reachable(s, s.army(2), "FN_ALPHA").is_empty(), "una flotta non si imbarca")
	t.assert_true(CampaignUiText.sea_reachable(s, s.army(3), "FN_ALPHA").is_empty(), "ENTRO non ha il porto")
	t.assert_true(CampaignUiText.sea_reachable(s, null, "FN_ALPHA").is_empty(), "nessuna selezione")


func test_regioni_lungo_cui_si_disegna_la_freccia(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	t.assert_true(CampaignUiText.transport_region_ids(s.army(1)).is_empty(), "nessun ordine")
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_ENTRO"]))
	t.assert_true(CampaignUiText.transport_region_ids(s.army(1)).is_empty(), "movimento a piedi")
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	t.assert_eq(CampaignUiText.transport_region_ids(s.army(1)), PackedStringArray(["ID_PORTA", "ID_MARE_UNO", "ID_MARE_DUE", "ID_FARO"]), "partenza, zone, arrivo")
	t.assert_true(CampaignUiText.attack_target(s, s.army(1), "ID_FARO"), "sbarco ostile: freccia rossa")


# --- testi ------------------------------------------------------------------------------------------------


func test_id_di_regione_nei_messaggi_diventano_nomi(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiText.humanize_ids(s, "ID_FARO non confina con ID_PORTA."), "Faro non confina con Porta.")
	t.assert_eq(CampaignUiText.humanize_ids(s, "nessun id qui"), "nessun id qui")
	t.assert_eq(CampaignUiText.humanize_ids(s, "ID_SCONOSCIUTA resta"), "ID_SCONOSCIUTA resta", "id sconosciuto invariato")
	t.assert_eq(CampaignUiText.humanize_ids(s, "flotta ostile in ID_MARE_DUE, ID_FARO"), "flotta ostile in ID_MARE_DUE, Faro", "i mari senza nome restano con l'id")
	t.assert_eq(CampaignUiText.chain_names(s, ["ID_MARE_UNO", "ID_MARE_DUE"]), "ID_MARE_UNO > ID_MARE_DUE")
	t.assert_eq(CampaignUiText.chain_names(s, PackedStringArray(["ID_MARE_UNO"])), "ID_MARE_UNO")
	t.assert_eq(CampaignUiText.chain_names(s, null), "")


func test_messaggio_d_errore_leggibile_se_non_raggiungibile(t: TestContext) -> void:
	var s := _world()
	var r := GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	t.assert_false(bool(r["ok"]))
	var text := CampaignUiText.order_error_text(s, str(r["errore"]))
	t.assert_false(text.contains("ID_PORTA") or text.contains("ID_FARO"), "niente id grezzi: %s" % text)
	t.assert_true(text.contains("Faro") and text.contains("Porta"), text)
	t.assert_true(text.contains("Nessun trasporto via mare"), text)
	var inland := GameCommands.order_move(s, "FN_ALPHA", 3, PackedStringArray(["ID_FARO"]))
	var inland_text := CampaignUiText.order_error_text(s, str(inland["errore"]))
	t.assert_true(inland_text.contains("Entro non ha un porto"), inland_text)


func test_testo_dell_evento_di_trasporto_interrotto(t: TestContext) -> void:
	var s := _world()
	var e := _ev("EV_TRANSPORT_BLOCKED", {"fazione": "FN_ALPHA", "regione": "ID_PORTA", "esercito": 1, "verso": "ID_FARO", "motivo": "flotta ostile in ID_MARE_DUE"})
	var text := CampaignUiText.format_event(s, e)
	t.assert_true(text.begins_with("Trasporto via mare interrotto"), text)
	t.assert_true(text.contains("esercito 1") and text.contains("Porta") and text.contains("Faro"), text)
	t.assert_true(text.contains("flotta ostile in ID_MARE_DUE"), text)
	var sea_move := _ev("EV_MOVED", {"esercito": 1, "fazione": "FN_ALPHA", "da": "ID_PORTA", "a": "ID_FARO", "via_mare": true, "catena": ["ID_MARE_UNO", "ID_MARE_DUE"]})
	var moved_text := CampaignUiText.format_event(s, sea_move)
	t.assert_true(moved_text.contains("via mare") and moved_text.contains("ID_MARE_UNO > ID_MARE_DUE"), moved_text)
	var walk := _ev("EV_MOVED", {"esercito": 3, "fazione": "FN_ALPHA", "da": "ID_ENTRO", "a": "ID_PORTA"})
	t.assert_eq(CampaignUiText.format_event(s, walk), "Esercito 3: da Entro a Porta.", "il movimento normale non cambia")


func test_descrizione_dell_esercito_con_trasporto(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	var text := CampaignUiText.describe_army(s, s.army(1))
	t.assert_true(text.contains("Movimento: Faro"), text)
	t.assert_true(text.contains("Trasporto via mare, attraverso: ID_MARE_UNO > ID_MARE_DUE"), text)
	t.assert_true(text.contains("Attacco a Faro"), text)
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_ENTRO"]))
	t.assert_false(CampaignUiText.describe_army(s, s.army(1)).contains("Trasporto via mare"))


func test_il_resoconto_di_fine_anno_riporta_il_trasporto_interrotto(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	s.declare_war("FN_ALPHA", "FN_GAMMA")
	_fleet(s, "FN_GAMMA", "ID_MARE_DUE")
	var result := TurnProcessor.end_year(s)
	var lines := CampaignUiText.year_report(s, "FN_ALPHA", result)
	var found := false
	for line in lines:
		if line.begins_with("Trasporto via mare interrotto"):
			found = true
			t.assert_true(line.contains("Porta") and line.contains("Faro"), line)
	t.assert_true(found, "riga del trasporto interrotto nel resoconto: %s" % str(lines))
	# BETA non c'entra: il resoconto di BETA non la riporta
	for line in CampaignUiText.year_report(s, "FN_BETA", result):
		t.assert_false(line.begins_with("Trasporto via mare interrotto"), line)
