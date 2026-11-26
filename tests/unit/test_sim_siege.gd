extends RefCounted
## Test degli assedi (spec. fase 3 §3.4 e §2): inizio, fame per grado del castello, sortita, assalto,
## assedio tolto, esercito di soccorso, ordini d'assalto e salvataggio. Mondo piccolo
## tests/fixtures/sim_*.txt: MEZZA e' di BETA (Castle2 = Fort, 1 anno di fame), la guarnigione e'
## l'esercito 4 (60 Nizari) nel castello; l'assediante e' l'esercito 3 di ALPHA (80 Spearmen) arrivato
## da BASSA. Forza di una pila = uomini (le unita' di prova non hanno statistiche).
## Valori attesi verificati con una replica Python delle formule:
##   sortita vinta 1.000.000 contro 80 x 1,15: assedianti -72 (restano 8), guarnigione -41
##   sortita persa 200 contro 80 x 1,15 (vince l'assediante): assedianti -43, guarnigione -200
##   assalto vinto 10.000.000 contro 60 x 1,5 = 90: assediante -40, guarnigione -60
##   assalto respinto 100 contro 1.000.000 x 1,5: assediante -90 (restano 10), guarnigione -30

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


func _kinds(s: GameState) -> Array[String]:
	var out: Array[String] = []
	for e in s.events:
		out.append(str(e["tipo"]))
	return out


func _near(t: TestContext, actual: float, expected: float, message: String) -> void:
	t.assert_true(absf(actual - expected) < EPS, "%s: atteso %s, ottenuto %s" % [message, str(expected), str(actual)])


func _invade(s: GameState, army: Army, to_region: String) -> void:
	army.from_region = army.region
	army.region = to_region
	army.arrived_year = s.year


func _add_army(s: GameState, faction_id: String, region_id: String, unit_id: String, men: int) -> Army:
	var a := s.create_army(faction_id, region_id, false)
	a.stacks.append(UnitStack.new(unit_id, men, 0))
	return a


## ALPHA assedia MEZZA: dopo il primo fine anno l'assedio e' appena iniziato (anni = 0), siamo nel 1001.
## `castle_level` e' il livello di CASTLE di MEZZA (2 = Fort, 7 = Castle, ...).
func _siege_world(besieger_men: int = 80, garrison_men: int = 60, castle_level: int = 2) -> GameState:
	var s := _world()
	s.army(3).stacks[0].men = besieger_men
	s.army(4).stacks[0].men = garrison_men
	s.army(4).in_castle = true
	s.province("ID_MEZZA").set_level("CASTLE", castle_level)
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	TurnProcessor.end_year(s)
	return s


# --- inizio dell'assedio -------------------------------------------------------------------------------


func test_l_assedio_inizia_senza_battaglia(t: TestContext) -> void:
	var s := _siege_world()
	t.assert_eq(s.year, 1001)
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 0, "la guarnigione e' nel castello: niente battaglia in campo")
	t.assert_true(s.sieges.has("ID_MEZZA"))
	var siege := s.siege_in("id_mezza")
	t.assert_true(siege != null)
	t.assert_eq(siege.faction, "FN_ALPHA")
	t.assert_eq(siege.years, 0, "il primo anno non conta")
	t.assert_eq(siege.army_ids, PackedInt32Array([3]))
	t.assert_eq(siege.region, "ID_MEZZA")
	var started := _events_of(s, GameState.EV_SIEGE_STARTED)
	t.assert_eq(started.size(), 1)
	t.assert_eq(started[0]["fazione"], "FN_ALPHA")
	t.assert_eq(started[0]["assediata"], "FN_BETA")
	t.assert_eq(started[0]["regione"], "ID_MEZZA")
	t.assert_true(str(started[0]["testo"]).contains("Mezza"), str(started[0]["testo"]))
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA", "la provincia non cade")
	t.assert_true(s.army(4).in_castle)
	t.assert_true(s.is_besieged("ID_MEZZA"))
	t.assert_eq(Combat.years_to_starve(s, siege), 1, "Fort: 1 anno")
	# le province assediate non rendono (manuale p21)
	var income := s.province("ID_MEZZA").last_income
	t.assert_eq(income["totale"], 0)
	t.assert_eq(income["conteso"], true)


func test_senza_nemici_la_guarnigione_resta_nel_castello(t: TestContext) -> void:
	# dal 2026-11-10 (richiesta di Federico) la guarnigione resta nel castello finche' non la si fa uscire o muovere
	var s := _world()
	s.army(4).in_castle = true
	TurnProcessor.end_year(s)
	t.assert_true(s.army(4).in_castle, "nessun assediante: la guarnigione resta dentro")
	t.assert_true(s.sieges.is_empty())


# --- fame ------------------------------------------------------------------------------------------------


func test_la_guarnigione_cede_per_fame_e_la_provincia_cade(t: TestContext) -> void:
	var s := _siege_world()
	var before := s.army(4).men_total() + s.army(3).men_total()
	TurnProcessor.end_year(s)
	var starved := _events_of(s, GameState.EV_STARVED)
	t.assert_eq(starved.size(), 1)
	t.assert_eq(starved[0]["fazione"], "FN_BETA")
	t.assert_eq(starved[0]["assediante"], "FN_ALPHA")
	t.assert_eq(starved[0]["uomini"], 60)
	t.assert_eq(starved[0]["anni"], 1)
	t.assert_true(str(starved[0]["testo"]).contains("fame"), str(starved[0]["testo"]))
	t.assert_true(s.army(4) == null, "la guarnigione e' eliminata")
	t.assert_eq(s.army(3).men_total(), 80)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_ALPHA", "senza guarnigione la provincia passa all'assediante")
	t.assert_true(s.sieges.is_empty())
	var kinds := _kinds(s)
	t.assert_true(kinds.has(GameState.EV_SIEGE_ENDED))
	t.assert_eq(_events_of(s, GameState.EV_SIEGE_ENDED)[0]["motivo"], "conquista")
	t.assert_eq(_events_of(s, GameState.EV_PROVINCE_CAPTURED).size(), 1)
	t.assert_true(kinds.find(GameState.EV_STARVED) < kinds.find(GameState.EV_PROVINCE_CAPTURED), "prima la resa, poi la conquista")
	t.assert_true(kinds.find(GameState.EV_PROVINCE_CAPTURED) < kinds.find(GameState.EV_FACTION_DESTROYED), "BETA non ha piu' nulla")
	t.assert_true(before > 0)


func test_anni_di_fame_secondo_il_grado_del_castello(t: TestContext) -> void:
	# Castle livello 7 = grado 3 (Castle): 3 anni. La resa avviene al terzo anno completo di assedio.
	var s := _siege_world(80, 60, 7)
	var siege := s.siege_in("ID_MEZZA")
	t.assert_eq(Combat.years_to_starve(s, siege), 3)
	TurnProcessor.end_year(s)
	t.assert_eq(siege.years, 1)
	t.assert_eq(Combat.years_to_starve(s, siege), 2)
	t.assert_eq(_events_of(s, GameState.EV_STARVED).size(), 0)
	TurnProcessor.end_year(s)
	t.assert_eq(siege.years, 2)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA", "ancora in piedi")
	t.assert_true(s.army(4) != null and s.army(4).in_castle)
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_STARVED).size(), 1, "terzo anno: resa")
	t.assert_eq(_events_of(s, GameState.EV_STARVED)[0]["anni"], 3)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_ALPHA")
	# Fortress (livello 13) e' tarata su 5 anni, Keep (livello 4) su 2
	var keep := _siege_world(80, 60, 4)
	TurnProcessor.end_year(keep)
	t.assert_eq(keep.province("ID_MEZZA").owner, "FN_BETA", "Keep: dopo 1 anno regge")
	TurnProcessor.end_year(keep)
	t.assert_eq(keep.province("ID_MEZZA").owner, "FN_ALPHA", "Keep: cede al secondo")


func test_i_parametri_di_fame_vengono_dalle_regole(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.starve_years = PackedInt32Array([4])
	s.army(4).in_castle = true
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	TurnProcessor.end_year(s)
	for i in 3:
		TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA", "3 anni di assedio su 4")
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_ALPHA")


# --- sortita ------------------------------------------------------------------------------------------------


func test_sortita_vinta_toglie_l_assedio(t: TestContext) -> void:
	var s := _siege_world(80, 1000000)
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0)
	var sally := _events_of(s, GameState.EV_SALLY)
	t.assert_eq(sally.size(), 1)
	t.assert_eq(sally[0]["fazione"], "FN_BETA")
	t.assert_eq(sally[0]["vittoria"], true)
	var battle := _events_of(s, GameState.EV_BATTLE)[0]
	t.assert_eq(battle["scontro"], "sortita")
	t.assert_eq(battle["attaccante"], "FN_BETA", "nella sortita attacca la guarnigione")
	t.assert_eq(battle["difensore"], "FN_ALPHA")
	_near(t, float(battle["forza_difensore"]), 92.0, "gli assedianti hanno il bonus del difensore")
	t.assert_eq(battle["perdite_difensore"], 72)
	t.assert_eq(battle["perdite_attaccante"], 41)
	t.assert_eq(s.army(3).men_total(), 8)
	t.assert_eq(s.army(3).region, "ID_BASSA", "gli assedianti sconfitti si ritirano")
	t.assert_eq(_events_of(s, GameState.EV_RETREAT)[0]["caso"], "provincia_amica")
	t.assert_true(s.sieges.is_empty(), "assedio tolto")
	t.assert_eq(_events_of(s, GameState.EV_SIEGE_ENDED)[0]["motivo"], "tolto")
	t.assert_true(s.army(4).in_castle, "la guarnigione resta nel castello (2026-11-10)")
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA")
	t.assert_eq(_events_of(s, GameState.EV_STARVED).size(), 0, "con la sortita non c'e' un anno di fame")
	var kinds := _kinds(s)
	t.assert_true(kinds.find(GameState.EV_SALLY) < kinds.find(GameState.EV_BATTLE))


func test_sortita_persa_annienta_la_guarnigione(t: TestContext) -> void:
	var s := _siege_world(80, 200)
	s.rules.combat.forced_outcome = -1   # vincono gli assedianti
	TurnProcessor.end_year(s)
	var sally := _events_of(s, GameState.EV_SALLY)
	t.assert_eq(sally.size(), 1)
	t.assert_eq(sally[0]["vittoria"], false)
	var battle := _events_of(s, GameState.EV_BATTLE)[0]
	t.assert_eq(battle["perdite_attaccante"], 200, "sortita persa: guarnigione annientata (manuale p31)")
	t.assert_eq(battle["perdite_difensore"], 43)
	t.assert_true(s.army(4) == null)
	t.assert_eq(s.army(3).men_total(), 37)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_ALPHA", "senza guarnigione la provincia cade subito")
	t.assert_true(s.sieges.is_empty())
	t.assert_eq(_events_of(s, GameState.EV_STARVED).size(), 0)


func test_nessuna_sortita_sotto_la_soglia(t: TestContext) -> void:
	# 150 contro 80: sotto la soglia 2,0 (160). Con soglia 1,5 (120) la guarnigione esce.
	var s := _siege_world(80, 150, 7)
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_SALLY).size(), 0)
	var s2 := _siege_world(80, 150, 7)
	s2.rules.combat.sally_threshold = 1.5
	TurnProcessor.end_year(s2)
	t.assert_eq(_events_of(s2, GameState.EV_SALLY).size(), 1)


# --- assalto -------------------------------------------------------------------------------------------------


func test_assalto_vinto_espugna_il_castello(t: TestContext) -> void:
	var s := _siege_world(10000000, 60)
	var order := GameCommands.order_assault(s, "FN_ALPHA", 3)
	t.assert_true(bool(order["ok"]), str(order["errore"]))
	t.assert_true(s.army(3).assault_ordered)
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0)
	var assault := _events_of(s, GameState.EV_ASSAULT)
	t.assert_eq(assault.size(), 1)
	t.assert_eq(assault[0]["fazione"], "FN_ALPHA")
	t.assert_eq(assault[0]["vittoria"], true)
	var battle := _events_of(s, GameState.EV_BATTLE)[0]
	t.assert_eq(battle["scontro"], "assalto")
	t.assert_eq(battle["attaccante"], "FN_ALPHA")
	t.assert_eq(battle["difensore"], "FN_BETA")
	_near(t, float(battle["forza_difensore_base"]), 60.0, "guarnigione")
	_near(t, float(battle["moltiplicatore_difensore"]), 1.5, "Fort")
	_near(t, float(battle["forza_difensore"]), 90.0, "60 x 1,5")
	t.assert_eq(battle["perdite_difensore"], 60, "guarnigione annientata")
	t.assert_eq(battle["perdite_attaccante"], 40)
	t.assert_false(s.army(3).assault_ordered, "l'ordine e' consumato")
	t.assert_eq(s.army(3).men_total(), 9999960)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_ALPHA")
	t.assert_true(s.sieges.is_empty())
	var kinds := _kinds(s)
	t.assert_true(kinds.find(GameState.EV_ASSAULT) < kinds.find(GameState.EV_BATTLE))
	t.assert_true(kinds.find(GameState.EV_BATTLE) < kinds.find(GameState.EV_PROVINCE_CAPTURED))


func test_il_castello_piu_alto_pesa_di_piu_nell_assalto(t: TestContext) -> void:
	for item in [[2, 1.5], [4, 2.0], [7, 2.5], [10, 3.0], [13, 4.0]]:
		var level: int = item[0]
		var expected: float = item[1]
		var s := _siege_world(10000000, 60, level)
		GameCommands.order_assault(s, "FN_ALPHA", 3)
		TurnProcessor.end_year(s)
		var battle := _events_of(s, GameState.EV_BATTLE)[0]
		_near(t, float(battle["moltiplicatore_difensore"]), expected, "castello livello %d" % level)
		_near(t, float(battle["forza_difensore"]), 60.0 * expected, "forza con castello livello %d" % level)


func test_assalto_respinto_toglie_l_assedio(t: TestContext) -> void:
	var s := _siege_world(100, 1000000)
	GameCommands.order_assault(s, "FN_ALPHA", 3)
	TurnProcessor.end_year(s)
	var assault := _events_of(s, GameState.EV_ASSAULT)
	t.assert_eq(assault[0]["vittoria"], false)
	t.assert_eq(_events_of(s, GameState.EV_SALLY).size(), 0, "con l'assalto ordinato la guarnigione non fa la sortita")
	var battle := _events_of(s, GameState.EV_BATTLE)[0]
	t.assert_eq(battle["perdite_attaccante"], 90)
	t.assert_eq(battle["perdite_difensore"], 30)
	t.assert_eq(s.army(3).men_total(), 10)
	t.assert_eq(s.army(3).region, "ID_BASSA", "gli assalitori respinti si ritirano")
	t.assert_false(s.army(3).assault_ordered)
	t.assert_true(s.sieges.is_empty(), "senza assedianti l'assedio finisce")
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA")
	t.assert_true(s.army(4).in_castle, "la guarnigione resta nel castello")
	t.assert_eq(s.army(4).men_total(), 999970)


func test_assalto_con_esito_forzato_e_guarnigione_non_annientata(t: TestContext) -> void:
	# con assalto_annienta = false i superstiti della guarnigione sono catturati a fine assalto
	var s := _siege_world(500, 60)
	s.rules.combat.assault_annihilates = false
	s.rules.combat.forced_outcome = 1
	GameCommands.order_assault(s, "FN_ALPHA", 3)
	TurnProcessor.end_year(s)
	var battle := _events_of(s, GameState.EV_BATTLE)[0]
	var captured := _events_of(s, GameState.EV_CAPTURED_UNITS)
	t.assert_eq(captured.size(), 1)
	t.assert_eq(captured[0]["caso"], "castello_espugnato")
	t.assert_eq(int(captured[0]["uomini"]) + int(battle["perdite_difensore"]), 60)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_ALPHA")


# --- ordini ---------------------------------------------------------------------------------------------------


func test_ordini_di_assalto(t: TestContext) -> void:
	var fresh := _world()
	var none := GameCommands.can_order_assault(fresh, "FN_ALPHA", 3)
	t.assert_false(bool(none["ok"]), "nessun assedio")
	t.assert_true(str(none["errore"]).contains("assediando"), str(none["errore"]))
	var s := _siege_world(80, 60, 7)
	var second := _add_army(s, "FN_ALPHA", "ID_MEZZA", "Spearmen", 5)
	var check := GameCommands.can_order_assault(s, "FN_ALPHA", 3)
	t.assert_true(bool(check["ok"]), str(check["errore"]))
	t.assert_eq(check["regione"], "ID_MEZZA")
	t.assert_false(s.army(3).assault_ordered, "can_order_assault non modifica lo stato")
	t.assert_false(bool(GameCommands.can_order_assault(s, "FN_BETA", 3)["ok"]), "esercito altrui")
	t.assert_false(bool(GameCommands.can_order_assault(s, "FN_BETA", 4)["ok"]), "la guarnigione non assalta")
	t.assert_false(bool(GameCommands.can_order_assault(s, "FN_ALPHA", 2)["ok"]), "una flotta")
	t.assert_false(bool(GameCommands.can_order_assault(s, "FN_ALPHA", 1)["ok"]), "esercito che non assedia")
	t.assert_false(bool(GameCommands.can_order_assault(s, "FN_ALPHA", 99)["ok"]), "sconosciuto")
	s.army(3).path = PackedStringArray(["ID_BASSA"])
	t.assert_false(bool(GameCommands.can_order_assault(s, "FN_ALPHA", 3)["ok"]), "ha un ordine di movimento")
	s.army(3).path = PackedStringArray()
	var order := GameCommands.order_assault(s, "FN_ALPHA", 3)
	t.assert_true(bool(order["ok"]), str(order["errore"]))
	t.assert_true(s.army(3).assault_ordered)
	t.assert_true(second.assault_ordered, "l'ordine vale per tutti gli assedianti")
	var again := GameCommands.order_assault(s, "FN_ALPHA", 3)
	t.assert_false(bool(again["ok"]))
	t.assert_eq(again["gia_ordinato"], true)
	t.assert_false(bool(GameCommands.cancel_assault(s, "FN_BETA", 3)["ok"]), "annullare l'assalto altrui")
	var cancel := GameCommands.cancel_assault(s, "FN_ALPHA", 3)
	t.assert_true(bool(cancel["ok"]), str(cancel["errore"]))
	t.assert_false(s.army(3).assault_ordered)
	t.assert_false(second.assault_ordered)
	t.assert_false(bool(GameCommands.cancel_assault(s, "FN_ALPHA", 3)["ok"]), "nessun assalto da annullare")
	t.assert_false(bool(GameCommands.cancel_assault(s, "FN_ALPHA", 99)["ok"]))


func test_muoversi_toglie_l_ordine_d_assalto_e_la_guarnigione_non_esce(t: TestContext) -> void:
	var s := _siege_world(80, 60, 7)
	GameCommands.order_assault(s, "FN_ALPHA", 3)
	var move := GameCommands.order_move(s, "FN_ALPHA", 3, PackedStringArray(["ID_BASSA"]))
	t.assert_true(bool(move["ok"]), str(move["errore"]))
	t.assert_false(s.army(3).assault_ordered, "il movimento toglie l'ordine d'assalto")
	var blocked := GameCommands.order_move(s, "FN_BETA", 4, PackedStringArray(["ID_BASSA"]))
	t.assert_false(bool(blocked["ok"]), "la guarnigione assediata non esce")
	t.assert_true(str(blocked["errore"]).contains("assediato"), str(blocked["errore"]))


func test_assedio_tolto_se_gli_assedianti_partono(t: TestContext) -> void:
	var s := _siege_world(80, 60, 7)
	GameCommands.order_move(s, "FN_ALPHA", 3, PackedStringArray(["ID_BASSA"]))
	TurnProcessor.end_year(s)
	t.assert_true(s.sieges.is_empty())
	var ended := _events_of(s, GameState.EV_SIEGE_ENDED)
	t.assert_eq(ended.size(), 1)
	t.assert_eq(ended[0]["motivo"], "tolto")
	t.assert_eq(ended[0]["regione"], "ID_MEZZA")
	t.assert_true(s.army(4).in_castle, "la guarnigione resta nel castello")
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA")


func test_assedio_tolto_se_gli_assedianti_muoiono(t: TestContext) -> void:
	var s := _siege_world(80, 60, 7)
	s.remove_army(s.army(3))
	TurnProcessor.end_year(s)
	t.assert_true(s.sieges.is_empty())
	t.assert_eq(_events_of(s, GameState.EV_SIEGE_ENDED)[0]["motivo"], "tolto")
	t.assert_true(s.army(4).in_castle)


func test_esercito_di_soccorso_rompe_l_assedio(t: TestContext) -> void:
	var s := _siege_world(80, 60, 7)
	var relief := _add_army(s, "FN_BETA", "ID_MEZZA", "Nizari", 1000000)
	relief.from_region = "ID_SOLA"
	relief.arrived_year = s.year
	TurnProcessor.end_year(s)
	var battle := _events_of(s, GameState.EV_BATTLE)
	t.assert_eq(battle.size(), 1)
	t.assert_eq(battle[0]["scontro"], "campo")
	t.assert_eq(battle[0]["attaccante"], "FN_BETA", "chi arriva attacca, anche per rompere un assedio")
	t.assert_eq(battle[0]["difensore"], "FN_ALPHA")
	t.assert_eq(s.army(3).region, "ID_BASSA", "gli assedianti sconfitti si ritirano")
	t.assert_true(s.sieges.is_empty())
	t.assert_eq(_events_of(s, GameState.EV_SIEGE_ENDED)[0]["motivo"], "tolto")
	t.assert_true(s.army(4).in_castle)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA")


func test_piu_eserciti_assediano_insieme(t: TestContext) -> void:
	var s := _siege_world(80, 60, 7)
	var second := _add_army(s, "FN_ALPHA", "ID_MEZZA", "Spearmen", 5)
	TurnProcessor.end_year(s)
	var siege := s.siege_in("ID_MEZZA")
	t.assert_eq(siege.army_ids, PackedInt32Array([3, second.id]), "in ordine di id")
	t.assert_eq(siege.years, 1)
	t.assert_eq(_events_of(s, GameState.EV_SIEGE_STARTED).size(), 0, "l'assedio e' lo stesso")
	# un esercito di un'altra fazione in guerra non e' un assediante di ALPHA
	t.assert_eq(siege.faction, "FN_ALPHA")


# --- rinforzi --------------------------------------------------------------------------------------------------


func test_i_rinforzi_nascono_nel_castello_assediato(t: TestContext) -> void:
	var s := _siege_world(80, 60, 7)
	var queued := GameCommands.queue_unit(s, "FN_BETA", "ID_MEZZA", "Nizari")
	t.assert_true(bool(queued["ok"]), str(queued["errore"]))
	TurnProcessor.end_year(s)
	t.assert_eq(s.army(4).stack_count(), 2, "si aggiunge alla guarnigione in castello")
	t.assert_true(s.army(4).in_castle)
	# guarnigione piena: l'esercito nuovo nasce comunque nel castello
	var s2 := _siege_world(80, 60, 7)
	# pile da un uomo: la guarnigione si riempie senza superare la soglia di sortita
	# (con pile da 10 uomini esce in sortita, rompe l'assedio e il test non misura piu' nulla)
	while s2.army(4).stack_count() < s2.rules.max_stacks:   # esercito pieno: la recluta non vi si aggiunge
		s2.army(4).stacks.append(UnitStack.new("Nizari", 1, 0))
	GameCommands.queue_unit(s2, "FN_BETA", "ID_MEZZA", "Nizari")
	var armies_before := s2.armies.size()
	TurnProcessor.end_year(s2)
	t.assert_eq(s2.armies.size(), armies_before + 1)
	var newcomer := s2.armies[s2.armies.size() - 1]
	t.assert_eq(newcomer.faction, "FN_BETA")
	t.assert_true(newcomer.in_castle, "in una provincia assediata le truppe nuove nascono nel castello")
	# fuori da un assedio le truppe nuove vanno nel castello solo se c'e' posto (2026-11-10): castello pieno, in campo
	var s3 := _world()
	for i in 15:
		s3.army(4).stacks.append(UnitStack.new("Nizari", 10, 0))
	s3.army(4).in_castle = true
	GameCommands.queue_unit(s3, "FN_BETA", "ID_MEZZA", "Nizari")
	TurnProcessor.end_year(s3)
	t.assert_false(s3.armies[s3.armies.size() - 1].in_castle)


# --- salvataggio ----------------------------------------------------------------------------------------------------


func test_salvataggio_con_assedio_e_ordine_d_assalto(t: TestContext) -> void:
	var s := _siege_world(80, 60, 7)
	GameCommands.order_assault(s, "FN_ALPHA", 3)
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var data := SaveGame.to_dict(s)
	t.assert_eq(data["versione"], SaveGame.VERSION)
	t.assert_eq((data["assedi"] as Array).size(), 1)
	t.assert_eq(data["guerre"], ["FN_ALPHA|FN_BETA"])
	var same_rules := Rules.new()
	same_rules.combat.capture_share = s.rules.combat.capture_share
	var restored := SaveGame.from_dict(data, campaign, units, buildings, same_rules)
	t.assert_true(bool(restored["ok"]), str(restored["errore"]))
	var loaded: GameState = restored["stato"]
	t.assert_true(loaded.at_war("FN_ALPHA", "FN_BETA"))
	var siege := loaded.siege_in("ID_MEZZA")
	t.assert_true(siege != null and siege.faction == "FN_ALPHA" and siege.years == 0)
	t.assert_eq(siege.army_ids, PackedInt32Array([3]))
	t.assert_true(loaded.army(4).in_castle)
	t.assert_true(loaded.army(3).assault_ordered)
	t.assert_eq(loaded.army(3).from_region, "ID_BASSA")
	t.assert_eq(loaded.army(3).arrived_year, 1000)
	t.assert_eq(SaveGame.to_json(loaded), SaveGame.to_json(s))
	TurnProcessor.end_year(s)
	TurnProcessor.end_year(loaded)
	t.assert_eq(SaveGame.to_json(loaded), SaveGame.to_json(s), "l'anno dopo (assalto) e' identico")
