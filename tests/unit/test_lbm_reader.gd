extends RefCounted
## Test del lettore IFF PBM (ByteRun1).
## Il file di prova tests/fixtures/mini.lbm (8x4, palette di 4 colori) è generato da
## tests/fixtures/make_mini_lbm.py. I test sul file reale LukMap.Lbm vengono saltati se
## l'installazione di MTW non si trova; i valori attesi sono stati misurati con
## tools/decode_lbm.py sul file del 2026-11-07.

const FIXTURE := "res://tests/fixtures/mini.lbm"

var _real: LbmReader
var _histogram := PackedInt32Array()


func _load_real(t: TestContext) -> LbmReader:
	if not FileAccess.file_exists(GameFiles.lookup_map()):   # mappa d'Europa dell'originale: tolta da originale/ il 18/11/2026
		t.skip("installazione di MTW non trovata in %s" % GameFiles.game_dir())
		return null
	if _real == null:
		_real = LbmReader.load_file(GameFiles.lookup_map())
	return _real


func test_file_di_prova_dimensioni_e_palette(t: TestContext) -> void:
	var lbm := LbmReader.load_file(FIXTURE)
	t.assert_eq(lbm.error, "", "errore di lettura")
	t.assert_true(lbm.is_valid(), "file valido")
	t.assert_eq(lbm.width, 8, "larghezza")
	t.assert_eq(lbm.height, 4, "altezza")
	t.assert_eq(lbm.bit_planes, 8, "bit per pixel")
	t.assert_eq(lbm.compression, 1, "compressione ByteRun1")
	t.assert_eq(lbm.palette.size(), 4, "voci di palette")
	t.assert_eq(lbm.palette[0], Color8(255, 0, 255), "palette 0")
	t.assert_eq(lbm.palette[1], Color8(255, 0, 0), "palette 1")
	t.assert_eq(lbm.palette[2], Color8(0, 255, 0), "palette 2")
	t.assert_eq(lbm.palette[3], Color8(0, 0, 255), "palette 3")
	t.assert_eq(lbm.palette_color(3), Color8(0, 0, 255))
	t.assert_eq(lbm.palette_color(4), Color.TRANSPARENT, "indice di palette inesistente")


func test_file_di_prova_pixel(t: TestContext) -> void:
	var lbm := LbmReader.load_file(FIXTURE)
	var expected := PackedByteArray([
		0, 0, 0, 0, 0, 0, 0, 0,
		1, 2, 3, 0, 1, 2, 3, 0,
		2, 2, 2, 3, 3, 0, 0, 1,
		1, 1, 1, 1, 2, 2, 2, 2,
	])
	t.assert_eq(lbm.indices, expected, "indici decodificati")
	t.assert_eq(lbm.index_at(0, 0), 0)
	t.assert_eq(lbm.index_at(2, 1), 3)
	t.assert_eq(lbm.index_at(7, 2), 1, "ultimo pixel della riga 2 (ripetizione che passa alla riga 3)")
	t.assert_eq(lbm.index_at(0, 3), 1, "primo pixel della riga 3")
	t.assert_eq(lbm.index_at(7, 3), 2)


func test_indice_fuori_dall_immagine(t: TestContext) -> void:
	var lbm := LbmReader.load_file(FIXTURE)
	t.assert_eq(lbm.index_at(8, 0), -1)
	t.assert_eq(lbm.index_at(0, 4), -1)
	t.assert_eq(lbm.index_at(-1, 0), -1)
	t.assert_eq(lbm.index_at(0, -1), -1)


func test_immagine_r8(t: TestContext) -> void:
	var lbm := LbmReader.load_file(FIXTURE)
	var img := lbm.to_image()
	t.assert_true(img != null, "immagine creata")
	if img == null:
		return
	t.assert_eq(img.get_format(), Image.FORMAT_R8, "formato")
	t.assert_eq(img.get_width(), 8)
	t.assert_eq(img.get_height(), 4)
	t.assert_eq(img.get_data(), lbm.indices, "byte dell'immagine")
	t.assert_eq(img.get_pixel(2, 1).r8, 3, "rosso = indice")


func test_file_non_valido(t: TestContext) -> void:
	t.assert_false(LbmReader.parse(PackedByteArray()).is_valid(), "file vuoto")
	t.assert_false(LbmReader.load_file("res://tests/fixtures/non_esiste.lbm").is_valid(), "file mancante")
	var ilbm := FileAccess.get_file_as_bytes(FIXTURE)
	ilbm[8] = "I".unicode_at(0)   # FORM....IBM invece di PBM
	t.assert_false(LbmReader.parse(ilbm).is_valid(), "tipo di FORM diverso da PBM")
	var truncated := FileAccess.get_file_as_bytes(FIXTURE)
	truncated = truncated.slice(0, truncated.size() - 6)
	var broken := LbmReader.parse(truncated)
	t.assert_false(broken.is_valid(), "BODY troncato")
	t.assert_true(broken.error != "", "messaggio di errore presente")
	t.assert_false(LbmReader.from_indices(2, 2, PackedByteArray([1, 2, 3])).is_valid(), "dimensioni incoerenti")
	t.assert_true(LbmReader.from_indices(2, 2, PackedByteArray([1, 2, 3, 4])).is_valid())


func test_non_compresso_e_larghezza_dispari(t: TestContext) -> void:
	# 3x2 non compresso: ogni riga ha un byte di riempimento (4 byte per riga).
	var body := PackedByteArray([1, 2, 3, 99, 4, 5, 6, 99])
	var lbm := LbmReader.parse(_build_pbm(3, 2, 0, body))
	t.assert_eq(lbm.error, "")
	t.assert_eq(lbm.indices, PackedByteArray([1, 2, 3, 4, 5, 6]), "senza il riempimento")
	t.assert_eq(lbm.index_at(0, 1), 4)
	# Stessa immagine compressa: un letterale di 8 byte.
	var packed := PackedByteArray([7]) + body
	var lbm2 := LbmReader.parse(_build_pbm(3, 2, 1, packed))
	t.assert_eq(lbm2.indices, PackedByteArray([1, 2, 3, 4, 5, 6]), "compresso, larghezza dispari")


func test_reale_dimensioni_e_palette(t: TestContext) -> void:
	var lbm := _load_real(t)
	if lbm == null:
		return
	t.assert_eq(lbm.error, "", "errore di lettura")
	t.assert_eq(lbm.width, 2048, "larghezza")
	t.assert_eq(lbm.height, 1536, "altezza")
	t.assert_eq(lbm.indices.size(), 2048 * 1536, "byte decodificati")
	t.assert_eq(lbm.palette.size(), 256, "voci di palette")
	t.assert_eq(lbm.palette[0], Color8(255, 0, 255), "palette 0")
	t.assert_eq(lbm.palette[1], Color8(143, 63, 63), "palette 1")


func test_reale_pixel_noti(t: TestContext) -> void:
	var lbm := _load_real(t)
	if lbm == null:
		return
	t.assert_eq(lbm.index_at(0, 0), 0, "angolo in alto a sinistra")
	t.assert_eq(lbm.index_at(2047, 1535), 147, "angolo in basso a destra")
	t.assert_eq(lbm.index_at(876, 326), 18, "castello della Danimarca (pixel 14024/16, 5224/16)")


func test_reale_istogramma(t: TestContext) -> void:
	var lbm := _load_real(t)
	if lbm == null:
		return
	if _histogram.is_empty():
		_histogram.resize(256)
		_histogram.fill(0)
		for v in lbm.indices:
			_histogram[v] += 1
	var land := 0
	for i in range(2, 216):
		land += _histogram[i]
		t.assert_true(_histogram[i] > 0, "indice di terra %d mai usato" % i)
	var sea := 0
	for i in range(216, 256):
		sea += _histogram[i]
	t.assert_eq(_histogram[0], 194074, "pixel senza regione (indice 0)")
	t.assert_eq(_histogram[1], 0, "indice 1 mai usato")
	t.assert_eq(land, 1914085, "pixel di terra (indici 2..215)")
	t.assert_eq(sea, 1037569, "pixel di mare (indici 216 e oltre)")
	t.assert_eq(_histogram[251] > 0 and _histogram[252] == 0, true, "ultimo indice di mare usato = 251")
	t.assert_eq(land + sea + _histogram[0], 2048 * 1536, "somma dei pixel")


## Costruisce un file PBM minimo (palette di 2 colori) con il BODY dato.
func _build_pbm(w: int, h: int, compression: int, body: PackedByteArray) -> PackedByteArray:
	var bmhd := PackedByteArray()
	bmhd.append_array(_be16(w))
	bmhd.append_array(_be16(h))
	bmhd.append_array(_be16(0))
	bmhd.append_array(_be16(0))
	bmhd.append_array(PackedByteArray([8, 0, compression, 0]))
	bmhd.append_array(_be16(0))
	bmhd.append_array(PackedByteArray([1, 1]))
	bmhd.append_array(_be16(w))
	bmhd.append_array(_be16(h))
	var cmap := PackedByteArray([0, 0, 0, 255, 255, 255])
	var form := "PBM ".to_ascii_buffer()
	form.append_array(_chunk("BMHD", bmhd))
	form.append_array(_chunk("CMAP", cmap))
	form.append_array(_chunk("BODY", body))
	var out := "FORM".to_ascii_buffer()
	out.append_array(_be32(form.size()))
	out.append_array(form)
	return out


func _chunk(tag: String, payload: PackedByteArray) -> PackedByteArray:
	var out := tag.to_ascii_buffer()
	out.append_array(_be32(payload.size()))
	out.append_array(payload)
	if payload.size() % 2 == 1:
		out.append(0)
	return out


func _be16(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 8) & 255, v & 255])


func _be32(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255])
