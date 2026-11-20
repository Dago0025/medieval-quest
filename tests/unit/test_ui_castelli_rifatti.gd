extends RefCounted
## Castelli della plancia rifatti (ADR-061, tools/prepara_castelli_mappa.py): ogni grado ha la sua immagine in
## assets/rifatti, alla misura dell'originale, con lo stendardo rosso chiave che PieceArt ricolora con la fazione.


func test_ogni_grado_ha_il_castello_rifatto(t: TestContext) -> void:
	for name in PieceArt.CASTLE_PIECES:
		var original := "%s/buildings/%s" % [PieceArt.BASE, name]
		t.assert_true(AssetLibrary.is_remade(original), "%s rifatto" % name)


func test_il_dipinto_non_ha_colori_chiave_sotto_lo_stendardo(t: TestContext) -> void:
	for name in PieceArt.CASTLE_PIECES:
		var tex := AssetLibrary.remade("%s/buildings/%s" % [PieceArt.BASE, name])
		t.assert_true(tex != null, "%s caricato" % name)
		if tex == null:
			continue
		var img := tex.get_image()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		var top := img.get_height()
		var bottom := -1
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.0 and PieceArt.key_of(c) == "rosso":
					top = mini(top, y)
					bottom = maxi(bottom, y)
		t.assert_true(bottom > top, "%s: lo stendardo rosso chiave c'e'" % name)
		t.assert_true(bottom < img.get_height() * 0.75, "%s: nessun rosso chiave nella fortificazione dipinta (fino a %d)" % [name, bottom])


func test_stendardo_ricolorato_anche_con_le_riduzioni(t: TestContext) -> void:
	PieceArt.reset()
	var tex := PieceArt.castle_piece(null, "FN_DANISH", 2, 1.0)
	t.assert_true(tex != null, "castello del grado 2")
	if tex == null:
		return
	var img := tex.get_image()
	t.assert_true(img.has_mipmaps(), "riduzioni intermedie rifatte dopo il colore")
	var small := img.duplicate() as Image
	small.resize(img.get_width() / 4, img.get_height() / 4, Image.INTERPOLATE_BILINEAR)
	var reds := 0
	for y in small.get_height():
		for x in small.get_width():
			var c := small.get_pixel(x, y)
			if c.a > 0.5 and PieceArt.key_of(c) == "rosso":
				reds += 1
	t.assert_eq(reds, 0, "nessun rosso chiave rimasto da lontano")
	PieceArt.reset()


## Porto rifatto (ADR-061): un file per fotogramma, il primo senza suffisso.
func test_percorso_dei_fotogrammi_rifatti(t: TestContext) -> void:
	t.assert_eq(AssetLibrary.remade_path("campmap/ships/port.BIF"), "res://assets/rifatti/campmap/ships/port.png")
	t.assert_eq(AssetLibrary.remade_path("campmap/ships/port.BIF", 1), "res://assets/rifatti/campmap/ships/port.png")
	t.assert_eq(AssetLibrary.remade_path("campmap/ships/port.BIF", 3), "res://assets/rifatti/campmap/ships/port__f03.png")


## Porti rifatti (ADR-061): ognuno degli 8 orientamenti del molo ha la sua immagine, alla stessa proporzione del fotogramma
## dell'originale (180x150), cosi' PieceArt.port_piece la disegna nello stesso posto.
func test_ogni_orientamento_del_porto_e_rifatto(t: TestContext) -> void:
	for frame in range(1, 9):
		var tex := AssetLibrary.remade(PieceArt.PORT_IMAGE, frame)
		t.assert_true(tex != null, "porto, fotogramma %d" % frame)
		if tex != null:
			t.assert_eq(tex.get_size(), Vector2(360, 300), "fotogramma %d: il doppio di 180x150" % frame)
	AssetLibrary.reset()
	PieceArt.reset()
	t.assert_true(AssetLibrary.is_remade(PieceArt.PORT_IMAGE), "il primo orientamento senza suffisso")
