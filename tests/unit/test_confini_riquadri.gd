extends RefCounted
## Confini vettoriali a riquadri (BorderLayer, ADR-077): con la mappa del mondo lo zoom ridisegnava tutte le polilinee a ogni
## scatto (segnalazione di Federico del 16/11/2026). Ora si aggiornano subito solo i riquadri in vista e, con la mappa
## lontana, si disegnano le versioni semplificate.


func _border(points: PackedVector2Array, kind: int = BorderExtractor.KIND_LAND_LAND) -> BorderExtractor.Border:
	var b := BorderExtractor.Border.new()
	b.points = points
	b.kind = kind
	b.group_a = 1
	b.group_b = 2
	return b


func _line(from: Vector2, to: Vector2, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		out.append(from.lerp(to, float(i) / float(n - 1)))
	return out


func test_semplificazione_tiene_gli_estremi(t: TestContext) -> void:
	var pts := _line(Vector2.ZERO, Vector2(100, 0), 101)   # un punto ogni pixel
	var d := BorderLayer.decimate(pts, 6.0)
	t.assert_eq(d[0], Vector2.ZERO)
	t.assert_eq(d[d.size() - 1], Vector2(100, 0))
	t.assert_true(d.size() <= 18 and d.size() >= 16, "circa un punto ogni 6 pixel: %d" % d.size())
	t.assert_eq(BorderLayer.decimate(pts, 0.0).size(), 101, "versione completa")


func test_versione_secondo_lo_zoom(t: TestContext) -> void:
	t.assert_eq(BorderLayer.lod_for(4.0), 0, "da vicino tutti i punti")
	t.assert_true(BorderLayer.lod_for(0.1) > BorderLayer.lod_for(1.0), "da lontano meno punti")
	t.assert_eq(BorderLayer.lod_for(0.05), BorderLayer.LOD_STEPS.size() - 1)


func test_zoom_aggiorna_solo_i_riquadri_in_vista(t: TestContext) -> void:
	var layer := BorderLayer.new()
	var list: Array[BorderExtractor.Border] = []
	# una polilinea vicino all'origine e una lontana, in riquadri diversi
	list.append(_border(_line(Vector2(10, 10), Vector2(400, 300), 50)))
	list.append(_border(_line(Vector2(8000, 4000), Vector2(8500, 4200), 50), BorderExtractor.KIND_COAST))
	# una lunga (piu' di PIECE_POINTS punti) che attraversa vari riquadri
	list.append(_border(_line(Vector2(0, 2000), Vector2(5000, 2000), 1200)))
	layer.set_view(Rect2(0, 0, 1200, 800))
	layer.set_borders(list)
	var counts := layer.tile_counts()
	t.assert_true(counts.x >= 4, "riquadri: %d" % counts.x)
	t.assert_true(counts.y >= 1 and counts.y < counts.x, "si disegnano solo i riquadri in vista: %s" % counts)
	layer.set_zoom(2.0)
	counts = layer.tile_counts()
	t.assert_true(counts.y >= 1 and counts.y < counts.x, "solo i riquadri in vista allo zoom nuovo: %s" % counts)
	layer.set_view(Rect2(7500, 3500, 1500, 1000))
	t.assert_true(layer.tile_counts().y > counts.y, "spostando la vista si aggiornano quelli che entrano")
	layer.free()


func test_evidenziazione_della_provincia(t: TestContext) -> void:
	var layer := BorderLayer.new()
	var list: Array[BorderExtractor.Border] = []
	list.append(_border(_line(Vector2(10, 10), Vector2(400, 300), 20)))
	layer.set_borders(list)
	layer.set_selected_group(2)
	t.assert_eq(layer.selected_group, 2)
	t.assert_eq((layer._by_group.get(2, PackedInt32Array()) as PackedInt32Array).size(), 1)
	layer.free()
