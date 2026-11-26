extends RefCounted
## Test del trasporto via mare degli eserciti (spec. fase 3 par. 9): catena di zone di mare con flotte
## proprie, partenza da un porto, sbarco ostile, catena ricontrollata a fine anno, salvataggio.
## Mondo di prova: tests/fixtures/transport_startpos.txt (vedi il commento in testa al file).
##   Esercito 1 = ALPHA in PORTA (100), 2 = flotta ALPHA in MARE_UNO (1 galea), 3 = ALPHA in ENTRO (interna),
##   4 = ALPHA in SENZAPORTO (edificio PORT ma senza SetPort), 5 = BETA in FARO (60, castello livello 2),
##   6 = ribelli in LONTANA (30).
##   Catene da PORTA con tutte le zone libere (flotte ALPHA ovunque): FARO = UNO > DUE;
##   LONTANA = UNO > DUE > QUATTRO (DUE prima di TRE nell'ordine dei vicini di UNO);
##   con DUE interrotta: FARO e LONTANA = UNO > TRE > QUATTRO.
## Sui dati reali: catene calcolate in Python (ricerca in ampiezza, ordine di SetNeighbours) da ID_DENMARK.

const STARTPOS := "res://tests/fixtures/transport_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"

var _real_campaign: CampaignData
var _real_units: UnitProdLoader.UnitTable
var _real_buildings: BuildingProdLoader.BuildingTable


func _world(seed_value: int = 1) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, Rules.new(), seed_value)
	# regola di base del blocco (basta una flotta); il blocco solo in inferiorita' di navi (22/11/2026) ha i suoi test
	s.rules.combat.blockade_needs_more_ships = false
	return s


func _fleet(s: GameState, faction_id: String, zone: String) -> Army:
	var a := s.create_army(faction_id, zone, true)
	a.stacks.append(UnitStack.new("Galley", 1, 0))
	return a


## Flotte ALPHA in tutte le zone di mare (in MARE_UNO c'e' gia' l'esercito 2).
func _all_seas(s: GameState) -> void:
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	_fleet(s, "FN_ALPHA", "ID_MARE_TRE")
	_fleet(s, "FN_ALPHA", "ID_MARE_QUATTRO")


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _chain(ids: Array) -> PackedStringArray:
	return SimUtil.strings_from(ids)


# --- catene --------------------------------------------------------------------------------------


func test_catena_semplice(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	var expected := _chain(["ID_MARE_UNO", "ID_MARE_DUE"])
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO"), expected, "UNO > DUE")
	t.assert_eq(GameCommands.sea_route(s, "fn_alpha", "id_porta", "id_faro"), expected, "id in minuscolo")
	var r := GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_true(bool(r["via_mare"]), "l'esito dice che e' un trasporto")
	t.assert_eq(SimUtil.strings_from(r["catena"]), expected)
	t.assert_true(bool(r["attacco"]), "sbarco in una provincia di BETA = attacco")
	t.assert_eq(r["passi"], 1)
	t.assert_eq(s.army(1).path, PackedStringArray(["ID_FARO"]))
	t.assert_eq(s.army(1).sea_route, expected)
	t.assert_eq(s.army(1).region, "ID_PORTA", "l'ordine non muove subito")
	t.assert_false(s.at_war("FN_ALPHA", "FN_BETA"), "la guerra si dichiara a fine anno")


func test_un_movimento_a_piedi_non_e_un_trasporto(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	var r := GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_ENTRO"]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_false(r.has("via_mare"), "ENTRO confina con PORTA")
	t.assert_true(s.army(1).sea_route.is_empty())
	# un trasporto ordinato e poi sostituito da un movimento a piedi perde la catena
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	t.assert_false(s.army(1).sea_route.is_empty())
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_ENTRO"]))
	t.assert_true(s.army(1).sea_route.is_empty(), "nuovo ordine, niente catena")
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	GameCommands.cancel_move(s, "FN_ALPHA", 1)
	t.assert_true(s.army(1).sea_route.is_empty(), "annullare toglie la catena")
	t.assert_true(s.army(1).path.is_empty())


func test_un_ordine_rifiutato_non_cambia_la_catena(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	var r := GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_ENTRO", "ID_FARO"]))
	t.assert_false(bool(r["ok"]), "due passi, il secondo non confina")
	t.assert_eq(s.army(1).sea_route, _chain(["ID_MARE_UNO", "ID_MARE_DUE"]), "il vecchio ordine resta")
	t.assert_eq(s.army(1).path, PackedStringArray(["ID_FARO"]))


func test_catena_piu_corta_e_ordine_dei_vicini(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO"), _chain(["ID_MARE_UNO", "ID_MARE_DUE"]), "FARO: due zone, non tre")
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_LONTANA"), _chain(["ID_MARE_UNO", "ID_MARE_DUE", "ID_MARE_QUATTRO"]), "LONTANA: DUE viene prima di TRE")
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_SENZAPORTO"), _chain(["ID_MARE_UNO"]), "una zona sola")
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_LONTANA"), GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_LONTANA"), "deterministica")


func test_manca_una_flotta_propria_nella_catena(t: TestContext) -> void:
	var s := _world()
	# solo UNO ha una flotta: FARO non e' raggiungibile
	t.assert_true(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO").is_empty())
	var r := GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("Nessun trasporto via mare"), str(r["errore"]))
	t.assert_true(str(r["errore"]).contains("non confina"), "il messaggio di sempre resta in testa: %s" % str(r["errore"]))
	t.assert_true(s.army(1).path.is_empty() and s.army(1).sea_route.is_empty(), "nessun ordine")
	# una flotta di un'altra fazione non conta come propria (BETA non e' in guerra con ALPHA, ma non e' sua); con il
	# blocco navale chiude anzi la zona
	_fleet(s, "FN_BETA", "ID_MARE_DUE")
	t.assert_true(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO").is_empty())
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_BLOCKED)
	s.rules.combat.neutral_blockade = false
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_NO_FLEET, "senza blocco navale")
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_UNO"), GameCommands.ZONE_PASSABLE)
	# una flotta senza pile non conta
	var empty := _fleet(s, "FN_ALPHA", "ID_MARE_TRE")
	empty.stacks.clear()
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_TRE"), GameCommands.ZONE_NO_FLEET)


func test_catena_interrotta_da_una_flotta_ostile(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	s.declare_war("FN_ALPHA", "FN_GAMMA")
	_fleet(s, "FN_GAMMA", "ID_MARE_DUE")
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_BLOCKED, "anche se ci sono flotte proprie")
	var around := _chain(["ID_MARE_UNO", "ID_MARE_TRE", "ID_MARE_QUATTRO"])
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO"), around, "si gira attorno a DUE")
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_LONTANA"), around)
	_fleet(s, "FN_GAMMA", "ID_MARE_TRE")
	t.assert_true(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO").is_empty(), "DUE e TRE chiuse")
	t.assert_false(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_SENZAPORTO").is_empty(), "UNO e' libera")
	var r := GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("blocco navale"), str(r["errore"]))


func test_una_flotta_ostile_blocca_anche_la_prima_zona(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	s.declare_war("FN_ALPHA", "FN_BETA")
	# la flotta del proprietario della provincia d'arrivo interrompe la catena (spec. par. 9)
	_fleet(s, "FN_BETA", "ID_MARE_UNO")
	t.assert_true(GameCommands.sea_destinations(s, "FN_ALPHA", 1).is_empty(), "UNO chiusa: nessuna destinazione")
	t.assert_true(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_SENZAPORTO").is_empty())


func test_senza_blocco_navale_una_flotta_in_pace_non_blocca(t: TestContext) -> void:
	# regola dell'originale (`[flotte] blocco_neutrali = false`): bloccano solo le flotte nemiche
	var s := _world()
	s.rules.combat.neutral_blockade = false
	_all_seas(s)
	_fleet(s, "FN_BETA", "ID_MARE_DUE")
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_PASSABLE)
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO"), _chain(["ID_MARE_UNO", "ID_MARE_DUE"]))
	_fleet(s, "FN_REBEL", "ID_MARE_DUE")
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_BLOCKED, "i ribelli sono in guerra con tutti")


func test_blocco_navale_una_flotta_neutrale_chiude_la_zona(t: TestContext) -> void:
	# richiesta di Federico (2026-11-10): navi neutrali o nemiche bloccano l'arrivo di truppe
	var s := _world()
	t.assert_true(s.rules.combat.neutral_blockade, "il blocco navale e' attivo per impostazione")
	_all_seas(s)
	t.assert_eq(s.relation("FN_ALPHA", "FN_BETA"), GameState.REL_NEUTRAL)
	_fleet(s, "FN_BETA", "ID_MARE_DUE")
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_BLOCKED, "neutrale: blocca, anche con flotte proprie")
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO"), _chain(["ID_MARE_UNO", "ID_MARE_TRE", "ID_MARE_QUATTRO"]), "si gira attorno")
	_fleet(s, "FN_BETA", "ID_MARE_TRE")
	var r := GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	t.assert_false(bool(r["ok"]), "DUE e TRE chiuse dalle navi neutrali")


func test_blocco_navale_la_flotta_alleata_non_blocca(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	s.form_alliance("FN_ALPHA", "FN_BETA")
	_fleet(s, "FN_BETA", "ID_MARE_DUE")
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_PASSABLE)


func test_blocco_navale_interrompe_un_trasporto_gia_ordinato(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	t.assert_true(bool(GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))["ok"]))
	# durante l'anno una flotta neutrale si mette in ognuna delle zone della catena e delle alternative
	_fleet(s, "FN_BETA", "ID_MARE_UNO")
	s.events.clear()
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(1).region, "ID_PORTA", "l'esercito resta in porto")
	t.assert_eq(_events_of(s, GameState.EV_TRANSPORT_BLOCKED).size(), 1)
	t.assert_true(str(_events_of(s, GameState.EV_TRANSPORT_BLOCKED)[0]["motivo"]).contains("blocco navale"))


# --- porto ---------------------------------------------------------------------------------------


func test_partenza_senza_porto(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	# ENTRO: interna, senza SetPort
	t.assert_true(GameCommands.sea_route(s, "FN_ALPHA", "ID_ENTRO", "ID_FARO").is_empty())
	var r := GameCommands.order_move(s, "FN_ALPHA", 3, PackedStringArray(["ID_FARO"]))
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("porto"), str(r["errore"]))
	t.assert_true(GameCommands.sea_destinations(s, "FN_ALPHA", 3).is_empty())
	# SENZAPORTO: l'edificio c'e' ma la regione non ha SetPort
	r = GameCommands.order_move(s, "FN_ALPHA", 4, PackedStringArray(["ID_FARO"]))
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("non ha un porto"), str(r["errore"]))
	# PORTA: SetPort c'e' ma l'edificio PORT no
	s.province("ID_PORTA").buildings.erase("PORT")
	r = GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("non e' ancora costruito"), str(r["errore"]))
	t.assert_true(GameCommands.sea_destinations(s, "FN_ALPHA", 1).is_empty())
	s.province("ID_PORTA").set_level("PORT", 1)
	t.assert_false(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO").is_empty(), "con il porto costruito si parte")
	# provincia non propria
	s.province("ID_PORTA").owner = "FN_BETA"
	t.assert_true(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO").is_empty(), "il porto e' di BETA")
	t.assert_true(GameCommands.embark_problem(s, "FN_ALPHA", "ID_PORTA").contains("propria"))
	t.assert_eq(GameCommands.embark_problem(s, "FN_BETA", "ID_PORTA"), "", "BETA puo' imbarcare dal suo porto")


func test_destinazioni_via_mare(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(GameCommands.sea_destinations(s, "FN_ALPHA", 1), PackedStringArray(["ID_SENZAPORTO"]), "con la sola flotta di UNO")
	_all_seas(s)
	t.assert_eq(GameCommands.sea_destinations(s, "FN_ALPHA", 1), PackedStringArray(["ID_SENZAPORTO", "ID_FARO", "ID_LONTANA"]),
		"ENTRO e' interna, PORTA e' la partenza")
	t.assert_true(GameCommands.sea_destinations(s, "FN_BETA", 1).is_empty(), "esercito altrui")
	t.assert_true(GameCommands.sea_destinations(s, "FN_ALPHA", 2).is_empty(), "una flotta non si imbarca")
	t.assert_true(GameCommands.sea_destinations(s, "FN_ALPHA", 99).is_empty(), "esercito sconosciuto")
	# BETA parte da FARO (SetPort + edificio): UNO e' lontana ma DUE e QUATTRO no, senza flotte BETA non c'e' nulla
	t.assert_true(GameCommands.sea_destinations(s, "FN_BETA", 5).is_empty(), "BETA non ha flotte")
	_fleet(s, "FN_BETA", "ID_MARE_QUATTRO")
	t.assert_true(GameCommands.sea_destinations(s, "FN_BETA", 5).is_empty(), "la flotta ALPHA in QUATTRO fa il blocco navale")
	s.rules.combat.neutral_blockade = false
	t.assert_eq(GameCommands.sea_destinations(s, "FN_BETA", 5), PackedStringArray(["ID_LONTANA"]), "senza blocco navale")


# --- fine anno: sbarco ----------------------------------------------------------------------------


func test_sbarco_ostile_vittorioso(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	s.rules.combat.forced_outcome = 1
	var order := GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	t.assert_true(bool(order["ok"]), str(order["errore"]))
	TurnProcessor.end_year(s)
	t.assert_true(s.at_war("FN_ALPHA", "FN_BETA"), "lo sbarco ostile dichiara guerra")
	var declared := _events_of(s, GameState.EV_WAR_DECLARED)
	t.assert_eq(declared.size(), 1)
	t.assert_eq(declared[0]["fazione"], "FN_ALPHA")
	t.assert_eq(declared[0]["contro"], "FN_BETA")
	t.assert_eq(declared[0]["regione"], "ID_FARO")
	var moved := _events_of(s, GameState.EV_MOVED)
	t.assert_eq(moved.size(), 1, "si e' mosso solo l'esercito 1")
	t.assert_eq(moved[0]["da"], "ID_PORTA")
	t.assert_eq(moved[0]["a"], "ID_FARO")
	t.assert_true(bool(moved[0]["via_mare"]))
	t.assert_eq(SimUtil.strings_from(moved[0]["catena"]), _chain(["ID_MARE_UNO", "ID_MARE_DUE"]))
	var battles := _events_of(s, GameState.EV_BATTLE)
	t.assert_eq(battles.size(), 1)
	t.assert_eq(battles[0]["attaccante"], "FN_ALPHA", "chi sbarca attacca")
	t.assert_eq(battles[0]["vincitore"], "FN_ALPHA")
	t.assert_eq(battles[0]["regione"], "ID_FARO")
	var landed := s.army(1)
	t.assert_true(landed != null, "il vincitore resta")
	t.assert_eq(landed.region, "ID_FARO")
	t.assert_eq(landed.from_region, "ID_MARE_DUE", "l'ultima zona di mare della catena")
	t.assert_true(landed.path.is_empty() and landed.sea_route.is_empty(), "ordine eseguito")
	t.assert_true(s.army(5).in_castle, "BETA si ritira nel castello (caso 1)")
	t.assert_true(s.is_besieged("ID_FARO"), "inizia l'assedio")
	t.assert_eq(s.province("ID_FARO").owner, "FN_BETA")
	t.assert_true(s.army(2) != null and s.army(2).region == "ID_MARE_UNO", "le flotte non si spostano")


func test_sbarco_in_una_provincia_vuota_la_conquista(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	s.remove_army(s.army(5))
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 0, "nessun difensore")
	t.assert_eq(s.province("ID_FARO").owner, "FN_ALPHA", "conquista immediata")
	t.assert_eq(_events_of(s, GameState.EV_PROVINCE_CAPTURED).size(), 1)
	t.assert_true(s.at_war("FN_ALPHA", "FN_BETA"))


func test_sbarco_in_una_provincia_propria_non_dichiara_guerra(t: TestContext) -> void:
	var s := _world()
	_all_seas(s)
	s.province("ID_LONTANA").owner = "FN_ALPHA"
	s.remove_army(s.army(6))
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_LONTANA"]))
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(1).region, "ID_LONTANA")
	t.assert_eq(_events_of(s, GameState.EV_WAR_DECLARED).size(), 0)
	t.assert_eq(s.army(1).from_region, "ID_MARE_QUATTRO")
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 0)


func test_sbarco_ostile_perso_cattura_l_esercito(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	s.rules.combat.forced_outcome = -1
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	TurnProcessor.end_year(s)
	var battles := _events_of(s, GameState.EV_BATTLE)
	t.assert_eq(battles.size(), 1)
	t.assert_eq(battles[0]["vincitore"], "FN_BETA")
	t.assert_true(s.army(1) == null, "FARO non confina con province ALPHA: chi perde dopo uno sbarco e' catturato")
	var captured := _events_of(s, GameState.EV_CAPTURED_UNITS)
	t.assert_eq(captured.size(), 1)
	t.assert_eq(captured[0]["caso"], "sbarco")
	t.assert_eq(captured[0]["fazione"], "FN_ALPHA")
	t.assert_eq(_events_of(s, GameState.EV_RETREAT).size(), 0)
	t.assert_true(s.army(5) != null and s.army(5).region == "ID_FARO", "il difensore resta")
	t.assert_eq(s.province("ID_FARO").owner, "FN_BETA")
	t.assert_true(s.army(2) != null, "le flotte restano")


func test_sbarco_perso_con_una_provincia_propria_vicina_si_ritira_a_terra(t: TestContext) -> void:
	# ritirata caso 2 prima del caso 4 (ordine del manuale): se la provincia di sbarco confina con
	# una provincia propria, l'esercito sconfitto vi si ritira invece di essere catturato
	var s := _world()
	_all_seas(s)
	s.campaign.region("ID_LONTANA").neighbours.append("ID_SENZAPORTO")   # i ribelli di LONTANA confinano con una provincia ALPHA
	s.remove_army(s.army(4))   # SENZAPORTO libera
	s.rules.combat.forced_outcome = -1
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_LONTANA"]))
	TurnProcessor.end_year(s)
	t.assert_true(s.army(1) != null, "non e' catturato")
	t.assert_eq(s.army(1).region, "ID_SENZAPORTO", "si ritira a terra")
	var retreats := _events_of(s, GameState.EV_RETREAT)
	t.assert_eq(retreats.size(), 1)
	t.assert_eq(retreats[0]["caso"], "provincia_amica")
	var whole := _events_of(s, GameState.EV_CAPTURED_UNITS).filter(func(e: Dictionary) -> bool: return str(e["caso"]) != "ritirata")
	t.assert_eq(whole.size(), 0, "nessuna cattura per intero (ADR-073: solo i prigionieri della ritirata)")


# --- fine anno: catena interrotta ------------------------------------------------------------------


func test_catena_interrotta_a_fine_anno(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	t.assert_true(bool(GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))["ok"]))
	# nel frattempo una flotta di una fazione in guerra con ALPHA entra in DUE
	s.declare_war("FN_ALPHA", "FN_GAMMA")
	_fleet(s, "FN_GAMMA", "ID_MARE_DUE")
	TurnProcessor.end_year(s)
	var army := s.army(1)
	t.assert_eq(army.region, "ID_PORTA", "resta dov'e'")
	t.assert_true(army.path.is_empty() and army.sea_route.is_empty(), "l'ordine decade")
	var blocked := _events_of(s, GameState.EV_TRANSPORT_BLOCKED)
	t.assert_eq(blocked.size(), 1)
	t.assert_eq(blocked[0]["esercito"], 1)
	t.assert_eq(blocked[0]["fazione"], "FN_ALPHA")
	t.assert_eq(blocked[0]["regione"], "ID_PORTA")
	t.assert_eq(blocked[0]["verso"], "ID_FARO")
	t.assert_true(str(blocked[0]["motivo"]).contains("ID_MARE_DUE"), str(blocked[0]["motivo"]))
	t.assert_true(str(blocked[0]["testo"]).contains("interrotto"), str(blocked[0]["testo"]))
	t.assert_eq(_events_of(s, GameState.EV_MOVED).size(), 0, "nessun movimento dell'esercito")
	t.assert_false(s.at_war("FN_ALPHA", "FN_BETA"), "un trasporto interrotto non dichiara la guerra")
	t.assert_eq(_events_of(s, GameState.EV_WAR_DECLARED).size(), 0)
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_TRANSPORT_BLOCKED).size(), 0, "l'evento non si ripete")


func test_catena_interrotta_perche_manca_la_flotta_o_il_porto(t: TestContext) -> void:
	var s := _world()
	var fleet := _fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	s.remove_army(fleet)
	TurnProcessor.end_year(s)
	var blocked := _events_of(s, GameState.EV_TRANSPORT_BLOCKED)
	t.assert_eq(blocked.size(), 1)
	t.assert_true(str(blocked[0]["motivo"]).contains("nessuna flotta propria"), str(blocked[0]["motivo"]))
	t.assert_eq(s.army(1).region, "ID_PORTA")
	# porto perso
	var s2 := _world()
	_fleet(s2, "FN_ALPHA", "ID_MARE_DUE")
	GameCommands.order_move(s2, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	s2.province("ID_PORTA").buildings.erase("PORT")
	TurnProcessor.end_year(s2)
	var blocked2 := _events_of(s2, GameState.EV_TRANSPORT_BLOCKED)
	t.assert_eq(blocked2.size(), 1)
	t.assert_true(str(blocked2[0]["motivo"]).contains("porto"), str(blocked2[0]["motivo"]))
	t.assert_eq(s2.army(1).region, "ID_PORTA")


func test_la_catena_si_controlla_prima_che_si_muovano_le_flotte(t: TestContext) -> void:
	# la flotta di DUE parte nello stesso fine anno: il trasporto vale comunque (controllo a inizio movimento)
	var s := _world()
	var fleet := _fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	s.rules.combat.forced_outcome = 1
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	t.assert_true(bool(GameCommands.order_move(s, "FN_ALPHA", fleet.id, PackedStringArray(["ID_MARE_QUATTRO"]))["ok"]))
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_TRANSPORT_BLOCKED).size(), 0)
	t.assert_eq(s.army(1).region, "ID_FARO")
	t.assert_eq(s.army(fleet.id).region, "ID_MARE_QUATTRO")


func test_gli_altri_ordini_non_sono_toccati_dal_ricontrollo(t: TestContext) -> void:
	var s := _world()
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	GameCommands.order_move(s, "FN_ALPHA", 3, PackedStringArray(["ID_PORTA"]))
	s.declare_war("FN_ALPHA", "FN_GAMMA")
	_fleet(s, "FN_GAMMA", "ID_MARE_UNO")
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(1).region, "ID_PORTA", "bloccato")
	t.assert_eq(s.army(3).region, "ID_PORTA", "l'esercito 3 si muove a piedi come sempre")
	t.assert_eq(_events_of(s, GameState.EV_TRANSPORT_BLOCKED).size(), 1)


# --- movimento delle flotte invariato -----------------------------------------------------------


func test_le_flotte_non_usano_il_trasporto(t: TestContext) -> void:
	var s := _world()
	var r := GameCommands.order_move(s, "FN_ALPHA", 2, PackedStringArray(["ID_MARE_QUATTRO"]))
	t.assert_false(bool(r["ok"]), "UNO non confina con QUATTRO")
	t.assert_true(s.army(2).sea_route.is_empty())
	r = GameCommands.order_move(s, "FN_ALPHA", 2, PackedStringArray(["ID_MARE_DUE"]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_false(r.has("via_mare"))


# --- salvataggio ---------------------------------------------------------------------------------


func test_salvataggio_della_rotta_via_mare(t: TestContext) -> void:
	var s := _world(7)
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_FARO"]))
	var data := SaveGame.to_dict(s)
	t.assert_eq(data["versione"], SaveGame.VERSION, "la rotta non cambia la versione")
	var armies: Array = data["eserciti"]
	var first: Dictionary = armies[0]
	t.assert_true(first.has("rotta_mare"), "il trasporto e' salvato")
	var third: Dictionary = armies[2]
	t.assert_false(third.has("rotta_mare"), "campo facoltativo: assente per i movimenti normali")
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	var parsed_data: Dictionary = parsed
	var loaded := SaveGame.from_dict(parsed_data, s.campaign, s.units, s.buildings, s.rules)
	t.assert_true(bool(loaded["ok"]), str(loaded["errore"]))
	var back: GameState = loaded["stato"]
	t.assert_eq(back.army(1).sea_route, _chain(["ID_MARE_UNO", "ID_MARE_DUE"]))
	t.assert_eq(back.army(1).path, PackedStringArray(["ID_FARO"]))
	t.assert_eq(SaveGame.to_json(back), text, "stato identico dopo il testo JSON")
	# l'anno dopo e' identico, con lo sbarco
	TurnProcessor.end_year(s)
	TurnProcessor.end_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "stesso anno successivo")
	t.assert_eq(s.army(1).region if s.army(1) != null else "", back.army(1).region if back.army(1) != null else "")
	# un salvataggio senza il campo (versione 1 e 2 di prima) si carica con la rotta vuota
	var old := SaveGame.to_dict(_world(7))
	var old_loaded := SaveGame.from_dict(old, s.campaign, s.units, s.buildings, s.rules)
	var old_state: GameState = old_loaded["stato"]
	t.assert_true(old_state.army(1).sea_route.is_empty())


# --- dati reali ------------------------------------------------------------------------------------


func _load_real(t: TestContext) -> bool:
	if _real_campaign != null:
		return true
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata in %s" % GameFiles.game_dir())
		return false
	var campaign := StartposLoader.load_file(GameFiles.startpos())
	var unit_path := GameFiles.prod_file(campaign.unit_prod_file)
	var building_path := GameFiles.prod_file(campaign.building_prod_file)
	if not FileAccess.file_exists(unit_path) or not FileAccess.file_exists(building_path):
		t.skip("file prod non trovati in %s" % GameFiles.game_dir())
		return false
	_real_units = UnitProdLoader.load_file(unit_path)
	_real_buildings = BuildingProdLoader.load_file(building_path)
	_real_campaign = campaign
	return true


## Catene calcolate in Python sul file reale EARLY_XL.TXT (ricerca in ampiezza dalle zone di
## ID_DENMARK, ordine di SetNeighbours, tutte le 36 zone di mare con una flotta danese):
##   IRELAND = NORTH_SEA > NORTH_ATLANTIC; WESSEX = NORTH_SEA > ENGLISH_CHANNEL;
##   SICILY = NORTH_SEA > NORTH_ATLANTIC > ATLANTIC_OCEAN > STRAITS_GIBRALTAR > WESTERN_MED > STRAITS_SICILY;
##   con NORTH_ATLANTIC interrotta: IRELAND = NORTH_SEA > ENGLISH_CHANNEL > IRISH_SEA e SICILY passa dalla Manica
##   (stessa lunghezza, 6 zone: NORTH_SEA > ENGLISH_CHANNEL > ATLANTIC_OCEAN > STRAITS_GIBRALTAR > WESTERN_MED > STRAITS_SICILY);
##   con anche ENGLISH_CHANNEL chiusa: IRELAND, SICILY e WESSEX irraggiungibili, SWEDEN = SKAGERRAK. Destinazioni: 68 province (71 costiere meno la
##   partenza e i suoi vicini di terra SCANIA e SAXONY), le prime ID_NORWAY, ID_SWEDEN, ID_POMERANIA, ID_FREISLAND.
func test_catene_sui_dati_reali(t: TestContext) -> void:
	if not _load_real(t):
		return
	var s := GameSetup.new_game(_real_campaign, _real_units, _real_buildings, Rules.load_file(), 1)
	s.rules.combat.blockade_needs_more_ships = false   # regola di base: una flotta nemica basta a chiudere la zona
	var existing: Array[Army] = []
	existing.assign(s.armies)
	for a in existing:
		if a.is_fleet:
			s.remove_army(a)
	for zone in s.campaign.sea_regions():
		_fleet(s, "FN_DANISH", zone.id)
	t.assert_eq(GameCommands.embark_problem(s, "FN_DANISH", "ID_DENMARK"), "", "la Danimarca ha SetPort e l'edificio PORT")
	t.assert_eq(GameCommands.sea_route(s, "FN_DANISH", "ID_DENMARK", "ID_IRELAND"), _chain(["ID_NORTH_SEA", "ID_NORTH_ATLANTIC"]), "Irlanda")
	t.assert_eq(GameCommands.sea_route(s, "FN_DANISH", "ID_DENMARK", "ID_WESSEX"), _chain(["ID_NORTH_SEA", "ID_ENGLISH_CHANNEL"]), "Wessex")
	t.assert_eq(GameCommands.sea_route(s, "FN_DANISH", "ID_DENMARK", "ID_SICILY"), _chain([
		"ID_NORTH_SEA", "ID_NORTH_ATLANTIC", "ID_ATLANTIC_OCEAN", "ID_STRAITS_GIBRALTAR", "ID_WESTERN_MED", "ID_STRAITS_SICILY"]), "Sicilia")
	var army := s.create_army("FN_DANISH", "ID_DENMARK", false)
	army.stacks.append(UnitStack.new("Spearmen", 100, 0))
	var destinations := GameCommands.sea_destinations(s, "FN_DANISH", army.id)
	t.assert_eq(destinations.size(), 68, "province raggiungibili")
	t.assert_eq(destinations.slice(0, 4), PackedStringArray(["ID_NORWAY", "ID_SWEDEN", "ID_POMERANIA", "ID_FREISLAND"]), "ordine della ricerca")
	t.assert_false(destinations.has("ID_SCANIA"), "confina per terra")
	t.assert_false(destinations.has("ID_DENMARK"))
	# interruzioni con flotte di una fazione in guerra con la Danimarca
	s.declare_war("FN_DANISH", "FN_ENGLISH")
	_fleet(s, "FN_ENGLISH", "ID_NORTH_ATLANTIC")
	t.assert_eq(GameCommands.sea_route(s, "FN_DANISH", "ID_DENMARK", "ID_IRELAND"), _chain(["ID_NORTH_SEA", "ID_ENGLISH_CHANNEL", "ID_IRISH_SEA"]), "Irlanda, giro lungo")
	t.assert_eq(GameCommands.sea_route(s, "FN_DANISH", "ID_DENMARK", "ID_SICILY"), _chain([
		"ID_NORTH_SEA", "ID_ENGLISH_CHANNEL", "ID_ATLANTIC_OCEAN", "ID_STRAITS_GIBRALTAR", "ID_WESTERN_MED", "ID_STRAITS_SICILY"]), "Sicilia, per la Manica")
	_fleet(s, "FN_ENGLISH", "ID_ENGLISH_CHANNEL")
	t.assert_true(GameCommands.sea_route(s, "FN_DANISH", "ID_DENMARK", "ID_IRELAND").is_empty(), "Irlanda irraggiungibile")
	t.assert_true(GameCommands.sea_route(s, "FN_DANISH", "ID_DENMARK", "ID_SICILY").is_empty(), "Sicilia irraggiungibile")
	t.assert_true(GameCommands.sea_route(s, "FN_DANISH", "ID_DENMARK", "ID_WESSEX").is_empty(), "Wessex irraggiungibile")
	t.assert_eq(GameCommands.sea_route(s, "FN_DANISH", "ID_DENMARK", "ID_SWEDEN"), _chain(["ID_SKAGERRAK"]), "Svezia via SKAGERRAK")
	# l'ordine passa da order_move e salva la catena
	var r := GameCommands.order_move(s, "FN_DANISH", army.id, PackedStringArray(["ID_SWEDEN"]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_true(bool(r["via_mare"]), "SWEDEN non confina per terra con DENMARK")
	t.assert_eq(army.sea_route, _chain(["ID_SKAGERRAK"]))


## Richiesta di Federico del 22/11/2026: il blocco navale vale solo se chi blocca ha piu' navi di quelle proprie nella zona.
func test_blocco_solo_in_inferiorita_di_navi(t: TestContext) -> void:
	t.assert_true(Rules.load_file().combat.blockade_needs_more_ships, "attivo in scontri.cfg")
	var s := _world()
	s.rules.combat.blockade_needs_more_ships = true
	_all_seas(s)   # una nave ALPHA in DUE, TRE e QUATTRO
	var beta := _fleet(s, "FN_BETA", "ID_MARE_DUE")
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_PASSABLE, "navi pari: nessun blocco")
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO"), _chain(["ID_MARE_UNO", "ID_MARE_DUE"]))
	t.assert_true(GameCommands.zone_blockers(s, "FN_ALPHA", "ID_MARE_DUE").is_empty())
	beta.stacks.append(UnitStack.new("Galley", 1, 0))
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_BLOCKED, "Beta ha piu' navi: blocco")
	t.assert_eq(GameCommands.zone_blockers(s, "FN_ALPHA", "ID_MARE_DUE"), PackedStringArray(["FN_BETA"]))
	t.assert_eq(GameCommands.sea_route(s, "FN_ALPHA", "ID_PORTA", "ID_FARO"), _chain(["ID_MARE_UNO", "ID_MARE_TRE", "ID_MARE_QUATTRO"]), "si gira attorno")
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	_fleet(s, "FN_ALPHA", "ID_MARE_DUE")
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_PASSABLE, "ora ALPHA ha piu' navi")
	# la stessa regola per le flotte nemiche, contate per fazione
	s.declare_war("FN_ALPHA", "FN_GAMMA")
	var gamma := _fleet(s, "FN_GAMMA", "ID_MARE_TRE")
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_TRE"), GameCommands.ZONE_PASSABLE, "nemico con le stesse navi")
	gamma.stacks.append(UnitStack.new("Galley", 1, 0))
	t.assert_eq(GameCommands.sea_zone_status(s, "FN_ALPHA", "ID_MARE_TRE"), GameCommands.ZONE_BLOCKED, "nemico con piu' navi")
	# senza navi proprie basta una flotta non alleata
	var s2 := _world()
	s2.rules.combat.blockade_needs_more_ships = true
	_fleet(s2, "FN_BETA", "ID_MARE_DUE")
	t.assert_eq(GameCommands.sea_zone_status(s2, "FN_ALPHA", "ID_MARE_DUE"), GameCommands.ZONE_BLOCKED, "nessuna nave propria")
