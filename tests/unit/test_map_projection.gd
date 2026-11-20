extends RefCounted
## Test della prospettiva della plancia (MapProjection) e dei segnalini proiettati.

const ArmyLayerScript := preload("res://scenes/army_layer.gd")
const SCREEN := Vector2(1600.0, 900.0)
const EPS := 0.01


func _near(t: TestContext, actual: Vector2, expected: Vector2, message: String) -> void:
	t.assert_true(actual.distance_to(expected) < EPS, "%s: atteso %s, ottenuto %s" % [message, expected, actual])


func test_vista_dall_alto_e_l_identita(t: TestContext) -> void:
	var p := MapProjection.new(SCREEN, 1.0)
	t.assert_true(p.is_flat())
	t.assert_eq(p.flat_size(), SCREEN)
	_near(t, p.screen_to_flat(Vector2(123.0, 456.0)), Vector2(123.0, 456.0), "schermo -> piatta")
	_near(t, p.flat_to_screen(Vector2(77.0, 800.0)), Vector2(77.0, 800.0), "piatta -> schermo")
	t.assert_eq(p.bottom_width(), SCREEN.x)


func test_angoli_dello_schermo(t: TestContext) -> void:
	var k := 1.6
	var p := MapProjection.new(SCREEN, k)
	var f := p.flat_size()
	t.assert_eq(f, SCREEN * k)
	# In alto si vede tutta la larghezza della vista piatta, in basso solo 1/k al centro.
	_near(t, p.screen_to_flat(Vector2.ZERO), Vector2.ZERO, "alto a sinistra")
	_near(t, p.screen_to_flat(Vector2(SCREEN.x, 0.0)), Vector2(f.x, 0.0), "alto a destra")
	_near(t, p.screen_to_flat(Vector2(0.0, SCREEN.y)), Vector2(f.x * (0.5 - 0.5 / k), f.y), "basso a sinistra")
	_near(t, p.screen_to_flat(SCREEN), Vector2(f.x * (0.5 + 0.5 / k), f.y), "basso a destra")
	t.assert_true(absf(p.bottom_width() - SCREEN.x) < EPS, "la striscia in basso è larga quanto lo schermo")


func test_andata_e_ritorno(t: TestContext) -> void:
	for k in [1.0, 1.3, 1.6, 2.4]:
		var p := MapProjection.new(SCREEN, k)
		for s in [Vector2(0.0, 0.0), Vector2(800.0, 450.0), Vector2(1599.0, 12.0), Vector2(3.0, 899.0), Vector2(400.0, 700.0)]:
			var screen: Vector2 = s
			_near(t, p.flat_to_screen(p.screen_to_flat(screen)), screen, "k %.1f punto %s" % [k, screen])


func test_in_basso_al_centro_un_pixel_vale_un_pixel(t: TestContext) -> void:
	var p := MapProjection.new(SCREEN, 1.6)
	var a := p.screen_to_flat(Vector2(SCREEN.x / 2.0, SCREEN.y - 1.0))
	var b := p.screen_to_flat(Vector2(SCREEN.x / 2.0 + 10.0, SCREEN.y - 1.0))
	t.assert_true(absf(b.x - a.x - 10.0) < 0.05, "scala orizzontale in basso: %f" % (b.x - a.x))
	# In alto la stessa distanza sullo schermo copre più mappa (la plancia si allontana).
	var c := p.screen_to_flat(Vector2(SCREEN.x / 2.0, 0.0))
	var d := p.screen_to_flat(Vector2(SCREEN.x / 2.0 + 10.0, 0.0))
	t.assert_true(d.x - c.x > 15.0, "in alto la mappa è rimpicciolita")


func test_le_rette_restano_rette(t: TestContext) -> void:
	# Le frecce sono spezzate in coordinate del mondo: la proiezione deve conservare l'allineamento.
	var p := MapProjection.new(SCREEN, 1.8)
	var a := p.flat_to_screen(Vector2(100.0, 100.0))
	var b := p.flat_to_screen(Vector2(1100.0, 900.0))
	var m := p.flat_to_screen(Vector2(600.0, 500.0))
	var cross := (b - a).cross(m - a)
	t.assert_true(absf(cross) < 0.5, "punto medio allineato (prodotto vettoriale %f)" % cross)


func test_inclinazione_limitata_e_risoluzione(t: TestContext) -> void:
	t.assert_eq(MapProjection.new(SCREEN, 0.5).tilt, MapProjection.MIN_TILT)
	t.assert_eq(MapProjection.new(SCREEN, 9.0).tilt, MapProjection.MAX_TILT)
	t.assert_eq(MapProjection.new(SCREEN, 1.6).render_scale(), 1.0)
	var big := MapProjection.new(Vector2(3840.0, 2160.0), 2.0)
	t.assert_true(big.render_scale() < 1.0, "schermo 4K molto inclinato: vista piatta ridotta")
	t.assert_true(maxf(big.flat_size().x, big.flat_size().y) * big.render_scale() <= MapProjection.MAX_FLAT_SIDE + 0.5)


func test_segnalino_cliccabile_dove_viene_disegnato(t: TestContext) -> void:
	var layer: ArmyLayerScript = ArmyLayerScript.new()
	var p := MapProjection.new(SCREEN, 1.6)
	var center := Vector2(1000.0, 800.0)
	var zoom := 2.0
	layer.set_view(center, zoom, p.flat_size(), p)
	var anchor := Vector2(1100.0, 760.0)
	layer.add_marker(7, anchor, Vector2.ZERO, Color.RED, "3", false, true, false)
	var flat := (anchor - center) * zoom + p.flat_size() / 2.0
	var screen := p.flat_to_screen(flat)
	t.assert_eq(layer.army_at(screen), 7, "clic sul segnalino proiettato")
	t.assert_eq(layer.army_at(flat), 0, "nella posizione non proiettata non c'è")
	layer.free()
