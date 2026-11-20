extends RefCounted
## Test della logica pura dei segnalini (MarkerLayout): disposizione affiancata, raggruppamento
## per regione, hit test, punta delle frecce e punto di ancoraggio delle zone di mare.

## Mappa di prova 8x4 (la stessa di test_region_map): Danimarca = 2,3; mare del Nord = 216;
## 217 è un'altra zona di mare (due pixel in basso); 250 è un indice senza regione.
const PIXELS := [
	0, 2, 3, 4, 5, 6, 216, 250,
	2, 2, 3, 3, 4, 4, 216, 216,
	6, 6, 6, 0, 0, 0, 216, 216,
	2, 3, 2, 3, 217, 217, 7, 7,
]


func _pixels() -> PackedByteArray:
	return PackedByteArray(PIXELS)


func _groups() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(RegionMap.TABLE_SIZE)
	for i in range(RegionMap.TABLE_SIZE):
		out[i] = RegionMap.group_for_index(i)
	return out


# --- disposizione -------------------------------------------------------------


func test_slot_un_segnalino_sta_nell_ancora(t: TestContext) -> void:
	var s := MarkerLayout.slot_offsets(1, 10.0)
	t.assert_eq(s.size(), 1)
	t.assert_eq(s[0], Vector2.ZERO)


func test_slot_nessun_segnalino(t: TestContext) -> void:
	t.assert_eq(MarkerLayout.slot_offsets(0, 10.0).size(), 0)
	t.assert_eq(MarkerLayout.slot_offsets(-3, 10.0).size(), 0)


func test_slot_due_e_tre_affiancati_e_centrati(t: TestContext) -> void:
	var two := MarkerLayout.slot_offsets(2, 10.0)
	t.assert_eq(two[0], Vector2(-5.0, 0.0))
	t.assert_eq(two[1], Vector2(5.0, 0.0))
	var three := MarkerLayout.slot_offsets(3, 10.0)
	t.assert_eq(three[0], Vector2(-10.0, 0.0))
	t.assert_eq(three[1], Vector2(0.0, 0.0))
	t.assert_eq(three[2], Vector2(10.0, 0.0))


func test_slot_va_a_capo_dopo_la_riga_piena(t: TestContext) -> void:
	var five := MarkerLayout.slot_offsets(5, 10.0, 4)
	t.assert_eq(five.size(), 5)
	# Prima riga: quattro segnalini, seconda riga: uno solo, al centro.
	t.assert_eq(five[0], Vector2(-15.0, -5.0))
	t.assert_eq(five[3], Vector2(15.0, -5.0))
	t.assert_eq(five[4], Vector2(0.0, 5.0))


func test_slot_senza_sovrapposizioni(t: TestContext) -> void:
	var many := MarkerLayout.slot_offsets(11, 28.0)
	for i in range(many.size()):
		for j in range(i + 1, many.size()):
			t.assert_true(many[i].distance_to(many[j]) >= 28.0 - 0.001, "segnalini %d e %d troppo vicini" % [i, j])


# --- raggruppamento -------------------------------------------------------------


func test_raggruppa_per_regione_in_ordine_di_id(t: TestContext) -> void:
	var armies: Array[Army] = [
		Army.new(7, "FN_A", "ID_X", false),
		Army.new(2, "FN_A", "ID_Y", false),
		Army.new(5, "FN_B", "ID_X", false),
		Army.new(3, "FN_A", "ID_X", false),
	]
	var groups := MarkerLayout.group_by_region(armies)
	t.assert_eq(groups.size(), 2)
	var x: PackedInt32Array = groups["ID_X"]
	t.assert_eq(Array(x), [3, 5, 7], "ID_X ordinata per id")
	var y: PackedInt32Array = groups["ID_Y"]
	t.assert_eq(Array(y), [2])


func test_raggruppa_lista_vuota(t: TestContext) -> void:
	var none: Array[Army] = []
	t.assert_true(MarkerLayout.group_by_region(none).is_empty())


# --- hit test e frecce ---------------------------------------------------------


func test_hit_index(t: TestContext) -> void:
	var centers := PackedVector2Array([Vector2(100, 100), Vector2(110, 100), Vector2(300, 50)])
	var half := Vector2(11, 11)
	t.assert_eq(MarkerLayout.hit_index(centers, half, Vector2(300, 55)), 2)
	t.assert_eq(MarkerLayout.hit_index(centers, half, Vector2(95, 100)), 0, "solo il primo copre il punto")
	t.assert_eq(MarkerLayout.hit_index(centers, half, Vector2(105, 100)), 1, "sovrapposti: vince l'ultimo")
	t.assert_eq(MarkerLayout.hit_index(centers, half, Vector2(200, 200)), -1)
	t.assert_eq(MarkerLayout.hit_index(PackedVector2Array(), half, Vector2.ZERO), -1)


func test_punta_della_freccia(t: TestContext) -> void:
	var head := MarkerLayout.arrow_head(Vector2(0, 0), Vector2(10, 0), 4.0)
	t.assert_eq(head.size(), 3)
	t.assert_eq(head[0], Vector2(10, 0), "la punta e' nel punto di arrivo")
	t.assert_eq(head[1].x, 6.0)
	t.assert_eq(head[2].x, 6.0)
	t.assert_eq(absf(head[1].y), 2.0)
	t.assert_eq(head[1].y, -head[2].y, "i due angoli sono simmetrici")


func test_punta_con_punti_coincidenti_e_vuota(t: TestContext) -> void:
	t.assert_true(MarkerLayout.arrow_head(Vector2(3, 3), Vector2(3, 3), 5.0).is_empty())


# --- ancoraggio delle zone ------------------------------------------------------


func test_ancora_del_mare_e_il_pixel_piu_vicino_al_baricentro(t: TestContext) -> void:
	var wanted := {216: true}
	var anchors := MarkerLayout.zone_anchors(_pixels(), 8, 4, _groups(), wanted, 1)
	t.assert_eq(anchors.size(), 1)
	# Pixel 216: (6,0) (6,1) (7,1) (6,2) (7,2): baricentro (6,4; 1,2); il piu' vicino e' (6,1).
	t.assert_eq(anchors[216], Vector2(6.5, 1.5))


func test_ancora_cade_sempre_dentro_la_zona(t: TestContext) -> void:
	# Zona a "C": il baricentro cade fuori dalla zona.
	var pixels := PackedByteArray([
		216, 216, 216, 216, 216,
		216, 0, 0, 0, 0,
		216, 0, 0, 0, 0,
		216, 0, 0, 0, 0,
		216, 216, 216, 216, 216,
	])
	var anchors := MarkerLayout.zone_anchors(pixels, 5, 5, _groups(), {216: true}, 1)
	t.assert_true(anchors.has(216))
	var a: Vector2 = anchors[216]
	t.assert_eq(pixels[int(a.y) * 5 + int(a.x)], 216, "l'ancora e' su un pixel della zona")


func test_ancora_di_una_regione_con_due_indici(t: TestContext) -> void:
	# Danimarca = gruppo 1 (indici 2 e 3 insieme).
	var anchors := MarkerLayout.zone_anchors(_pixels(), 8, 4, _groups(), {1: true}, 1)
	t.assert_true(anchors.has(1))
	var a: Vector2 = anchors[1]
	var idx: int = _pixels()[int(a.y) * 8 + int(a.x)]
	t.assert_true(idx == 2 or idx == 3, "il pixel e' della Danimarca (indice %d)" % idx)


func test_ancora_non_richiesta_non_compare(t: TestContext) -> void:
	var anchors := MarkerLayout.zone_anchors(_pixels(), 8, 4, _groups(), {216: true}, 1)
	t.assert_false(anchors.has(217))
	t.assert_false(anchors.has(1))
	t.assert_true(MarkerLayout.zone_anchors(_pixels(), 8, 4, _groups(), {}, 1).is_empty())


func test_campionamento_ricade_sul_passo_uno(t: TestContext) -> void:
	# Con passo 2 si leggono solo x pari e y pari: i due pixel di 217 (y = 3) sfuggono, ma la
	# zona e' richiesta, quindi viene cercata di nuovo pixel per pixel.
	var anchors := MarkerLayout.zone_anchors(_pixels(), 8, 4, _groups(), {217: true}, 2)
	t.assert_true(anchors.has(217))
	var a: Vector2 = anchors[217]
	t.assert_eq(_pixels()[int(a.y) * 8 + int(a.x)], 217)


func test_ancora_con_dati_non_validi(t: TestContext) -> void:
	t.assert_true(MarkerLayout.zone_anchors(PackedByteArray(), 8, 4, _groups(), {216: true}, 1).is_empty(), "bitmap troppo corta")
	t.assert_true(MarkerLayout.zone_anchors(_pixels(), 0, 4, _groups(), {216: true}, 1).is_empty(), "larghezza zero")
