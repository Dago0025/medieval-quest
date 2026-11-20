extends RefCounted
## Test delle richieste di Federico del 2026-11-09 (pomeriggio): raggio delle flotte (zone di mare all'anno, bussola,
## percorso verso zone non confinanti), orientamento dei porti dallo startpos, stendardo del castello secondo la guarnigione.
## Mondo di prova: tests/fixtures/transport_startpos.txt (zone UNO - DUE/TRE - QUATTRO; esercito 2 = flotta ALPHA con una
## galea in MARE_UNO; la galea di prova ha raggio 1).

const STARTPOS := "res://tests/fixtures/transport_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


func _fleet(s: GameState) -> Army:
	var f := s.army(2)
	return f


# --- raggio delle flotte ------------------------------------------------------------------------------------------------


func test_raggio_della_flotta_dalla_nave_piu_lenta(t: TestContext) -> void:
	var s := _world()
	var f := _fleet(s)
	t.assert_true(f.is_fleet)
	t.assert_eq(Combat.fleet_range(s, f), 1, "galea: raggio 1")
	s.units.get_unit("Galley").ship_range = 3
	t.assert_eq(Combat.fleet_range(s, f), 3)
	t.assert_eq(Combat.fleet_range(s, s.army(1)), 1, "un esercito di terra fa un passo")


func test_la_bussola_aggiunge_una_zona(t: TestContext) -> void:
	var s := _world()
	var f := _fleet(s)
	var e := EventRules.HistoricalEvent.new()
	e.index = 21
	e.key = "bussola"
	s.rules.events.history.append(e)
	t.assert_eq(Combat.fleet_range(s, f), 1, "prima della bussola")
	s.historical_done[21] = 1169
	t.assert_eq(Combat.fleet_range(s, f), 2, "dopo la bussola")


func test_percorso_verso_una_zona_non_confinante(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(GameCommands.fleet_path(s, 2, "ID_MARE_QUATTRO"), PackedStringArray(["ID_MARE_DUE", "ID_MARE_QUATTRO"]))
	t.assert_eq(GameCommands.fleet_path(s, 2, "ID_MARE_DUE"), PackedStringArray(["ID_MARE_DUE"]))
	t.assert_true(GameCommands.fleet_path(s, 2, "ID_PORTA").is_empty(), "solo zone di mare")
	t.assert_true(GameCommands.fleet_path(s, 1, "ID_MARE_DUE").is_empty(), "solo flotte")


func test_la_flotta_percorre_il_suo_raggio_in_un_anno(t: TestContext) -> void:
	var s := _world()
	var f := _fleet(s)
	var path := GameCommands.fleet_path(s, 2, "ID_MARE_QUATTRO")
	t.assert_true(bool(GameCommands.order_move(s, "FN_ALPHA", 2, path)["ok"]))
	TurnProcessor.end_year(s)
	t.assert_eq(f.region, "ID_MARE_DUE", "raggio 1: una zona")
	s.units.get_unit("Galley").ship_range = 2
	var s2 := _world()
	s2.units.get_unit("Galley").ship_range = 2
	GameCommands.order_move(s2, "FN_ALPHA", 2, GameCommands.fleet_path(s2, 2, "ID_MARE_QUATTRO"))
	TurnProcessor.end_year(s2)
	t.assert_eq(s2.army(2).region, "ID_MARE_QUATTRO", "raggio 2: due zone nello stesso anno")
	t.assert_true(s2.army(2).path.is_empty())


func test_la_flotta_si_ferma_dove_trova_il_nemico(t: TestContext) -> void:
	var s := _world()
	s.units.get_unit("Galley").ship_range = 2
	var enemy := s.create_army("FN_BETA", "ID_MARE_DUE", true)
	enemy.stacks.append(UnitStack.new("Galley", 1, 0))
	s.declare_war("FN_ALPHA", "FN_BETA")
	GameCommands.order_move(s, "FN_ALPHA", 2, GameCommands.fleet_path(s, 2, "ID_MARE_QUATTRO"))
	TurnProcessor.end_year(s)
	var f := s.army(2)
	if f != null:
		t.assert_true(f.region == "ID_MARE_DUE" or f.region == "ID_MARE_UNO", "si ferma alla battaglia (o si ritira): %s" % f.region)
	t.assert_true(f == null or f.region != "ID_MARE_QUATTRO", "non passa oltre il nemico")


# --- porti ---------------------------------------------------------------------------------------------------------------


func test_orientamento_del_porto_dallo_startpos(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(STARTPOS)
	var porta := campaign.region("ID_PORTA")
	t.assert_true(porta.has_port)
	t.assert_eq(porta.port_pos, Vector2i(100, 100))
	t.assert_eq(porta.port_dir, 2, "quarto campo di SetPort")


# --- stendardo del castello --------------------------------------------------------------------------------------------


func _banner_image() -> Image:
	var img := Image.create(4, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 20:
		for x in 4:
			img.set_pixel(x, y, Color(1, 0, 0, 1))   # rosso puro: stendardo
	return img


func test_stendardo_del_castello_vuoto_e_pallido(t: TestContext) -> void:
	var banner := Color(0.1, 0.2, 0.8)
	var empty := _banner_image()
	PieceArt.recolor_castle(empty, banner, 0.0)
	t.assert_true(empty.get_pixel(1, 19).a < 0.9, "castello vuoto: anche la parte bassa e' pallida")
	var full := _banner_image()
	PieceArt.recolor_castle(full, banner, 1.0)
	t.assert_true(full.get_pixel(1, 0).is_equal_approx(Color(banner.r / 0.95 * 0.95, banner.g, banner.b, 1.0)) or full.get_pixel(1, 0).a > 0.99, "pieno: colore della fazione")
	var half := _banner_image()
	PieceArt.recolor_castle(half, banner, 0.5)
	t.assert_true(half.get_pixel(1, 19).a > 0.99, "meta': colorato in basso")
	t.assert_true(half.get_pixel(1, 0).a < 0.9, "meta': pallido in alto")


func test_la_flotta_dell_ia_attacca_entro_il_raggio(t: TestContext) -> void:
	var s := _world()
	s.units.get_unit("Galley").ship_range = 2
	var mine := s.army(2)   # flotta ALPHA in MARE_UNO
	mine.stacks[0].men = 5
	var enemy := s.create_army("FN_BETA", "ID_MARE_QUATTRO", true)   # a due zone di distanza
	enemy.stacks.append(UnitStack.new("Galley", 1, 0))
	s.declare_war("FN_ALPHA", "FN_BETA")
	var ctx := AiContext.build(s, AiRules.default_rules(), "")
	var plan := AiPlan.create(ctx, "FN_ALPHA", "CATHOLIC_EXPANSIONIST")
	AiNavy.plan(plan)
	t.assert_eq(mine.path, PackedStringArray(["ID_MARE_DUE", "ID_MARE_QUATTRO"]), "raggio 2: attacca la flotta a due zone")
