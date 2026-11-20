extends RefCounted
## Test dell'estrattore dei confini vettoriali (BorderExtractor).
## Prima su piccole griglie costruite qui (polilinee grezze attese esatte), poi sulla mappa
## reale (saltati se manca l'installazione). I valori reali sono stati misurati con un'implementazione
## Python dello stesso algoritmo su LukMap.Lbm e EARLY_XL.TXT del 2026-11-08.
##
## Indici usati nelle griglie: 2 e 3 = regione di terra A (gruppo 1), 4 = terra B (gruppo 2),
## 216 = mare (gruppo 216), 0 = nessuna regione.

const TEST_CACHE := "user://cache/test_confini.dat"

var _real_lbm: LbmReader
var _real_data: CampaignData
var _real_raw: Array[BorderExtractor.Border] = []
var _real_smooth: Array[BorderExtractor.Border] = []


func _raw(rows: Array) -> Array[BorderExtractor.Border]:
	var pixels := PackedByteArray()
	for row in rows:
		for v in row:
			pixels.append(v)
	return BorderExtractor.new().extract_raw(pixels, rows[0].size(), rows.size())


func _pts(values: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in values:
		out.append(Vector2(v[0], v[1]))
	return out


func _load_real(t: TestContext) -> bool:
	if not FileAccess.file_exists(GameFiles.lookup_map()):   # mappa d'Europa dell'originale: tolta da originale/ il 18/11/2026
		t.skip("installazione di MTW non trovata in %s" % GameFiles.game_dir())
		return false
	if _real_lbm == null:
		_real_lbm = LbmReader.load_file(GameFiles.lookup_map())
		_real_data = StartposLoader.load_file(GameFiles.startpos())
		var extractor := BorderExtractor.new()
		_real_raw = extractor.extract_raw(_real_lbm.indices, _real_lbm.width, _real_lbm.height)
		for border in _real_raw:
			var copy := BorderExtractor.Border.new()
			copy.group_a = border.group_a
			copy.group_b = border.group_b
			copy.kind = border.kind
			copy.closed = border.closed
			copy.points = BorderExtractor.smooth_points(border.points, border.closed, extractor.simplify_tolerance, extractor.smooth_iterations)
			_real_smooth.append(copy)
	return true


# --- Griglie di prova ------------------------------------------------------------

func test_tipo_di_confine(t: TestContext) -> void:
	t.assert_eq(BorderExtractor.kind_of(1, 2), BorderExtractor.KIND_LAND_LAND)
	t.assert_eq(BorderExtractor.kind_of(107, 1), BorderExtractor.KIND_LAND_LAND, "l'ordine non conta")
	t.assert_eq(BorderExtractor.kind_of(5, 216), BorderExtractor.KIND_COAST)
	t.assert_eq(BorderExtractor.kind_of(251, 5), BorderExtractor.KIND_COAST)
	t.assert_eq(BorderExtractor.kind_of(216, 217), BorderExtractor.KIND_SEA_SEA)
	t.assert_eq(BorderExtractor.kind_of(0, 5), BorderExtractor.KIND_LAND_NONE)
	t.assert_eq(BorderExtractor.kind_of(5, 0), BorderExtractor.KIND_LAND_NONE)
	t.assert_eq(BorderExtractor.kind_of(0, 216), BorderExtractor.KIND_SEA_NONE)


## Griglia 6x4: A a sinistra con un gradino, B al centro, mare a destra, nessuna regione in basso a sinistra.
##   2 2 4 4 216 216
##   2 2 4 4 216 216
##   2 2 2 4 216 216
##   0 0 0 4 216 216
func test_griglia_polilinee_esatte(t: TestContext) -> void:
	var list := _raw([
		[2, 2, 4, 4, 216, 216],
		[2, 2, 4, 4, 216, 216],
		[2, 2, 2, 4, 216, 216],
		[0, 0, 0, 4, 216, 216],
	])
	t.assert_eq(list.size(), 4, "numero di polilinee")
	# Ordine: coppie crescenti (0,1), (0,2), (1,2), (2,216).
	t.assert_eq([list[0].group_a, list[0].group_b], [0, 1])
	t.assert_eq([list[1].group_a, list[1].group_b], [0, 2])
	t.assert_eq([list[2].group_a, list[2].group_b], [1, 2])
	t.assert_eq([list[3].group_a, list[3].group_b], [2, 216])
	t.assert_eq(list[0].points, _pts([[0, 3], [3, 3]]), "nessuna-A")
	t.assert_eq(list[1].points, _pts([[3, 3], [3, 4]]), "nessuna-B")
	t.assert_eq(list[2].points, _pts([[2, 0], [2, 2], [3, 2], [3, 3]]), "A-B con il gradino")
	t.assert_eq(list[3].points, _pts([[4, 0], [4, 4]]), "B-mare")
	t.assert_eq(list[0].kind, BorderExtractor.KIND_LAND_NONE)
	t.assert_eq(list[1].kind, BorderExtractor.KIND_LAND_NONE)
	t.assert_eq(list[2].kind, BorderExtractor.KIND_LAND_LAND)
	t.assert_eq(list[3].kind, BorderExtractor.KIND_COAST)
	for border in list:
		t.assert_false(border.closed, "tutte aperte")
	t.assert_true(list[2].involves(1) and list[2].involves(2) and not list[2].involves(3))


## Una regione isolata (indici 2 e 3 mescolati) circondata dal nulla: un solo anello chiuso.
func test_anello_chiuso(t: TestContext) -> void:
	var list := _raw([
		[0, 0, 0, 0, 0],
		[0, 2, 3, 2, 0],
		[0, 3, 2, 3, 0],
		[0, 0, 0, 0, 0],
	])
	t.assert_eq(list.size(), 1, "un solo anello: niente confini tra gli indici 2 e 3")
	t.assert_true(list[0].closed)
	t.assert_eq(list[0].points, _pts([[1, 1], [4, 1], [4, 3], [1, 3], [1, 1]]))
	t.assert_eq(list[0].kind, BorderExtractor.KIND_LAND_NONE)


## Due pixel in diagonale: il vertice centrale ha quattro spigoli della stessa coppia e diventa
## l'estremo di quattro polilinee.
func test_incrocio_a_quattro_spigoli(t: TestContext) -> void:
	var list := _raw([
		[2, 4],
		[4, 2],
	])
	t.assert_eq(list.size(), 4)
	t.assert_eq(list[0].points, _pts([[1, 0], [1, 1]]))
	t.assert_eq(list[1].points, _pts([[0, 1], [1, 1]]))
	t.assert_eq(list[2].points, _pts([[1, 1], [2, 1]]))
	t.assert_eq(list[3].points, _pts([[1, 1], [1, 2]]))


func test_indici_pari_e_dispari_non_sono_confine(t: TestContext) -> void:
	var list := _raw([
		[2, 3, 2, 3],
		[3, 2, 3, 2],
		[4, 5, 4, 5],
	])
	t.assert_eq(list.size(), 1, "solo il confine tra la regione di 2-3 e quella di 4-5")
	t.assert_eq([list[0].group_a, list[0].group_b], [1, 2])
	t.assert_eq(list[0].points, _pts([[0, 2], [4, 2]]))


func test_nessun_confine_in_una_sola_regione(t: TestContext) -> void:
	t.assert_eq(_raw([[216, 216, 216], [216, 216, 216]]).size(), 0)
	t.assert_eq(_raw([[2, 3], [3, 2]]).size(), 0)


func test_dimensioni_incoerenti(t: TestContext) -> void:
	var extractor := BorderExtractor.new()
	t.assert_eq(extractor.extract_raw(PackedByteArray([1, 2, 3]), 2, 2).size(), 0)
	t.assert_eq(extractor.extract_raw(PackedByteArray(), 0, 0).size(), 0)


# --- Semplificazione e levigatura -------------------------------------------------

func test_semplifica_toglie_la_scalettatura(t: TestContext) -> void:
	var stairs := _pts([[0, 0], [1, 0], [1, 1], [2, 1], [2, 2], [3, 2], [3, 3]])
	t.assert_eq(BorderExtractor.simplify(stairs, 0.9), _pts([[0, 0], [3, 3]]), "scalino da 0,71 px sotto la tolleranza")
	# Con tolleranza 0,5 piu' punti sono alla stessa distanza (0,71): quale resta dipende dagli arrotondamenti,
	# quindi si controllano numero di punti ed estremi, non le coordinate intermedie.
	var finer := BorderExtractor.simplify(stairs, 0.5)
	t.assert_eq(finer.size(), 5, "con tolleranza 0,5 restano piu' punti")
	t.assert_eq(finer[0], Vector2(0, 0))
	t.assert_eq(finer[finer.size() - 1], Vector2(3, 3))


func test_semplifica_mantiene_le_sporgenze(t: TestContext) -> void:
	var bend := _pts([[0, 0], [5, 0], [5, 3]])
	t.assert_eq(BorderExtractor.simplify(bend, 0.9), bend)
	t.assert_eq(BorderExtractor.simplify(bend, 0.0), bend, "tolleranza zero = nessuna semplificazione")
	t.assert_eq(BorderExtractor.simplify(_pts([[0, 0], [4, 0]]), 0.9), _pts([[0, 0], [4, 0]]))


func test_semplifica_ciclo_chiuso(t: TestContext) -> void:
	var square := _pts([[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]])
	t.assert_eq(BorderExtractor.simplify(square, 0.9), square, "gli angoli di un quadrato grande restano")
	# Un pixel isolato: la sola semplificazione lo schiaccia su un segmento, smooth_points lo conserva.
	var tiny := _pts([[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]])
	t.assert_eq(BorderExtractor.simplify(tiny, 0.9), _pts([[0, 0], [1, 1], [0, 0]]))
	var kept := BorderExtractor.smooth_points(tiny, true, 0.9, 1)
	t.assert_eq(kept.size(), 9, "anello di un pixel levigato con un'iterazione")
	t.assert_eq(kept[0], kept[kept.size() - 1])


func test_chaikin_polilinea_aperta(t: TestContext) -> void:
	t.assert_eq(BorderExtractor.chaikin(_pts([[0, 0], [4, 0]]), false, 0), _pts([[0, 0], [4, 0]]))
	t.assert_eq(BorderExtractor.chaikin(_pts([[0, 0], [4, 0], [4, 4]]), false, 1), _pts([
		[0, 0], [1, 0], [3, 0], [4, 1], [4, 3], [4, 4],
	]))
	var two := BorderExtractor.chaikin(_pts([[0, 0], [4, 0], [4, 4]]), false, 2)
	t.assert_eq(two.size(), 12)
	t.assert_eq(two[0], Vector2(0, 0), "estremo iniziale fisso")
	t.assert_eq(two[11], Vector2(4, 4), "estremo finale fisso")
	t.assert_eq(two[1], Vector2(0.25, 0.0))
	t.assert_eq(two[2], Vector2(0.75, 0.0))
	t.assert_eq(two[5], Vector2(3.25, 0.25))


func test_chaikin_polilinea_chiusa(t: TestContext) -> void:
	var out := BorderExtractor.chaikin(_pts([[0, 0], [2, 0], [2, 2], [0, 2], [0, 0]]), true, 1)
	t.assert_eq(out, _pts([[0.5, 0], [1.5, 0], [2, 0.5], [2, 1.5], [1.5, 2], [0.5, 2], [0, 1.5], [0, 0.5], [0.5, 0]]))
	t.assert_eq(out[0], out[out.size() - 1], "resta chiusa")


func test_estrazione_completa_tiene_fissi_gli_estremi(t: TestContext) -> void:
	var rows := [
		[2, 2, 4, 4, 216, 216],
		[2, 2, 4, 4, 216, 216],
		[2, 2, 2, 4, 216, 216],
		[0, 0, 0, 4, 216, 216],
	]
	var pixels := PackedByteArray()
	for row in rows:
		for v in row:
			pixels.append(v)
	var extractor := BorderExtractor.new()
	var raw := extractor.extract_raw(pixels, 6, 4)
	var smooth := extractor.extract(pixels, 6, 4)
	t.assert_eq(smooth.size(), raw.size())
	for i in range(raw.size()):
		t.assert_eq(smooth[i].points[0], raw[i].points[0], "primo punto %d" % i)
		t.assert_eq(smooth[i].points[smooth[i].points.size() - 1], raw[i].points[raw[i].points.size() - 1], "ultimo punto %d" % i)
	t.assert_eq(extractor.edge_count, 12, "spigoli totali: 3 + 1 + 4 + 4")


func test_cache_andata_e_ritorno(t: TestContext) -> void:
	var extractor := BorderExtractor.new()
	var pixels := PackedByteArray([2, 2, 4, 4, 216, 216, 2, 2, 4, 4, 216, 216, 0, 0, 4, 4, 216, 216])
	var borders := extractor.extract(pixels, 6, 3)
	t.assert_true(borders.size() > 0)
	t.assert_true(extractor.save_cache(TEST_CACHE, "chiave-a", 6, 3, borders), "scrittura")
	var back := extractor.load_cache(TEST_CACHE, "chiave-a", 6, 3)
	t.assert_eq(back.size(), borders.size())
	for i in range(borders.size()):
		t.assert_eq(back[i].points, borders[i].points, "punti %d" % i)
		t.assert_eq([back[i].group_a, back[i].group_b, back[i].kind, back[i].closed], [borders[i].group_a, borders[i].group_b, borders[i].kind, borders[i].closed])
	t.assert_eq(extractor.load_cache(TEST_CACHE, "chiave-b", 6, 3).size(), 0, "chiave diversa = cache ignorata")
	t.assert_eq(extractor.load_cache(TEST_CACHE, "chiave-a", 7, 3).size(), 0, "dimensioni diverse")
	var other := BorderExtractor.new()
	other.simplify_tolerance = 0.5
	t.assert_eq(other.load_cache(TEST_CACHE, "chiave-a", 6, 3).size(), 0, "parametri diversi")
	t.assert_eq(extractor.load_cache("user://cache/non_esiste.dat", "chiave-a", 6, 3).size(), 0)
	# File troncato = cache ignorata, senza errori.
	var f := FileAccess.open(TEST_CACHE, FileAccess.READ)
	var half := f.get_buffer(f.get_length() >> 1)
	f.close()
	var cut := FileAccess.open(TEST_CACHE, FileAccess.WRITE)
	cut.store_buffer(half)
	cut.close()
	t.assert_eq(extractor.load_cache(TEST_CACHE, "chiave-a", 6, 3).size(), 0, "file troncato")
	DirAccess.remove_absolute(TEST_CACHE)


func test_load_or_extract_usa_la_cache(t: TestContext) -> void:
	var pixels := PackedByteArray([2, 2, 4, 4, 216, 216, 2, 2, 4, 4, 216, 216, 0, 0, 4, 4, 216, 216])
	DirAccess.remove_absolute(TEST_CACHE)
	var first := BorderExtractor.new()
	var a := first.load_or_extract("res://project.godot", pixels, 6, 3, TEST_CACHE)
	t.assert_false(first.from_cache, "prima volta: estrazione")
	var second := BorderExtractor.new()
	var b := second.load_or_extract("res://project.godot", pixels, 6, 3, TEST_CACHE)
	t.assert_true(second.from_cache, "seconda volta: cache")
	t.assert_eq(b.size(), a.size())
	t.assert_eq(b[0].points, a[0].points)
	t.assert_true(BorderExtractor.cache_key("res://project.godot", 6, 3).contains("|6x3"), "la chiave include le dimensioni")
	t.assert_eq(BorderExtractor.cache_key("res://non_esiste.xyz", 6, 3), "senza-file|6x3")
	DirAccess.remove_absolute(TEST_CACHE)


# --- Mappa reale ---------------------------------------------------------------------

func _pair_name(group_a: int, group_b: int) -> String:
	var land := _real_data.land_regions()
	var id_a: String = land[group_a - 1].id
	var id_b: String = land[group_b - 1].id
	return "%s|%s" % [id_a, id_b] if id_a < id_b else "%s|%s" % [id_b, id_a]


func test_reale_coppie_terra_terra(t: TestContext) -> void:
	if not _load_real(t):
		return
	var found := {}
	for border in _real_raw:
		if border.kind == BorderExtractor.KIND_LAND_LAND:
			found[_pair_name(border.group_a, border.group_b)] = true
	var known := {}
	for pair in _real_data.adjacency_pairs():
		var ids := pair.split("|")
		var a := _real_data.region(ids[0])
		var b := _real_data.region(ids[1])
		if a != null and b != null and not a.is_sea and not b.is_sea:
			known[pair] = true
	t.assert_eq(known.size(), 208, "adiacenze di terra dichiarate nello startpos")
	t.assert_eq(found.size(), 208, "coppie di gruppi di terra confinanti nella bitmap")
	var missing := PackedStringArray()
	for pair in known:
		if not found.has(pair):
			missing.append(pair)
	var extra := PackedStringArray()
	for pair in found:
		if not known.has(pair):
			extra.append(pair)
	missing.sort()
	extra.sort()
	# Costantinopoli e Nicea sono divise dal Bosforo: la bitmap non le fa toccare. Danimarca e Svezia
	# si toccano nella bitmap ma lo startpos non le dichiara vicine.
	t.assert_eq(missing, PackedStringArray(["ID_CONSTANTINOPLE|ID_NICAEA"]), "dichiarate ma senza contatto nella bitmap")
	t.assert_eq(extra, PackedStringArray(["ID_DENMARK|ID_SWEDEN"]), "a contatto nella bitmap ma non dichiarate")


func test_reale_tipi_e_numeri(t: TestContext) -> void:
	if not _load_real(t):
		return
	var pairs_by_kind := {}
	var closed := 0
	var raw_points := 0
	for border in _real_raw:
		var set_for_kind: Dictionary = pairs_by_kind.get(border.kind, {})
		set_for_kind[border.group_a * 256 + border.group_b] = true
		pairs_by_kind[border.kind] = set_for_kind
		if border.closed:
			closed += 1
		raw_points += border.points.size()
	var counts := {}
	for kind in pairs_by_kind:
		counts[kind] = (pairs_by_kind[kind] as Dictionary).size()
	t.assert_eq(counts.get(BorderExtractor.KIND_LAND_LAND, 0), 208, "coppie terra-terra")
	t.assert_eq(counts.get(BorderExtractor.KIND_LAND_NONE, 0), 72, "coppie terra-nessuna regione (la costa)")
	t.assert_eq(counts.get(BorderExtractor.KIND_SEA_NONE, 0), 36, "coppie mare-nessuna regione")
	t.assert_eq(counts.get(BorderExtractor.KIND_COAST, 0), 0, "nella bitmap reale il mare non tocca mai la terra")
	t.assert_eq(counts.get(BorderExtractor.KIND_SEA_SEA, 0), 0, "e le zone di mare non si toccano")
	t.assert_eq(_real_raw.size(), 661, "polilinee grezze")
	t.assert_eq(closed, 76, "polilinee chiuse")
	t.assert_eq(raw_points, 70298, "punti delle polilinee grezze")


func test_reale_nessun_confine_tra_indici_della_stessa_regione(t: TestContext) -> void:
	if not _load_real(t):
		return
	# Prova che il caso esiste: nelle prime 400 righe ci sono 16711 coppie orizzontali di pixel
	# con indice diverso ma stessa regione.
	var indices := _real_lbm.indices
	var w := _real_lbm.width
	var same_region_pairs := 0
	for y in range(400):
		for x in range(w - 1):
			var a: int = indices[y * w + x]
			var b: int = indices[y * w + x + 1]
			if a != b and a >= 2 and b >= 2 and a < 216 and b < 216 and (a >> 1) == (b >> 1):
				same_region_pairs += 1
	t.assert_eq(same_region_pairs, 16711, "pixel adiacenti di indice pari e dispari della stessa regione")
	# Ogni segmento di ogni polilinea separa davvero i due gruppi dichiarati: guardo i due pixel
	# ai lati del primo spigolo unitario del segmento.
	var segments := 0
	var wrong := 0
	for border in _real_raw:
		t.assert_true(border.group_a < border.group_b, "gruppi ordinati e diversi")
		var pts := border.points
		for i in range(pts.size() - 1):
			var p := pts[i]
			var q := pts[i + 1]
			var left: int
			var right: int
			if p.x == q.x:
				var y := int(minf(p.y, q.y))
				left = indices[y * w + int(p.x) - 1]
				right = indices[y * w + int(p.x)]
			else:
				var x := int(minf(p.x, q.x))
				left = indices[(int(p.y) - 1) * w + x]
				right = indices[int(p.y) * w + x]
			var ga := RegionMap.group_for_index(left)
			var gb := RegionMap.group_for_index(right)
			segments += 1
			if not ((ga == border.group_a and gb == border.group_b) or (ga == border.group_b and gb == border.group_a)):
				wrong += 1
	t.assert_eq(segments, 69637, "segmenti delle polilinee grezze")
	t.assert_eq(wrong, 0, "segmenti che non separano la coppia di gruppi dichiarata")


func test_reale_levigatura(t: TestContext) -> void:
	if not _load_real(t):
		return
	t.assert_eq(_real_smooth.size(), _real_raw.size())
	var total := 0
	var w := float(_real_lbm.width)
	var h := float(_real_lbm.height)
	for i in range(_real_raw.size()):
		var raw := _real_raw[i].points
		var smooth := _real_smooth[i].points
		total += smooth.size()
		if _real_raw[i].closed:
			# Sugli anelli la levigatura e' circolare: anche il primo punto si sposta, ma l'anello resta chiuso.
			t.assert_eq(smooth[0], smooth[smooth.size() - 1], "anello %d chiuso" % i)
		else:
			# Sulle linee aperte gli estremi restano fermi, cosi' si agganciano agli incroci.
			t.assert_eq(smooth[0], raw[0], "primo punto della polilinea %d" % i)
			t.assert_eq(smooth[smooth.size() - 1], raw[raw.size() - 1], "ultimo punto della polilinea %d" % i)
		for p in smooth:
			if p.x < 0.0 or p.y < 0.0 or p.x > w or p.y > h:
				t.assert_true(false, "punto fuori dalla mappa nella polilinea %d" % i)
				break
	# Misurato in Python: 89408 punti con tolleranza 0,9 e 2 iterazioni di Chaikin.
	t.assert_true(total > 88000 and total < 90500, "punti levigati: %d" % total)
