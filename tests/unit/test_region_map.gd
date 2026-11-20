extends RefCounted
## Test dell'unione tra la bitmap delle regioni e i dati della campagna (RegionMap).
## Prima su una piccola mappa 8x4 costruita a mano, poi sul file reale (saltati se manca
## l'installazione). I valori reali sono stati misurati con tools/decode_lbm.py sul
## file LukMap.Lbm e su EARLY_XL.TXT del 2026-11-07.

const MINI_STARTPOS := """
DeclareFaction:: "FN_REBEL"
DeclareFaction:: "FN_DANISH"
DeclareFaction:: "FN_ENGLISH"
SetFactionCol:: FN_DANISH 200 10 20 0 0 0
SetFactionCol:: FN_ENGLISH 10 20 200 0 0 0
DeclareLandRegion:: "ID_DENMARK"
DeclareLandRegion:: "ID_SWEDEN"
DeclareLandRegion:: "ID_WESSEX"
DeclareSeaRegion:: "ID_NORTH_SEA"
SetRegionOwner:: ID_DENMARK FN_DANISH
SetRegionOwner:: ID_WESSEX FN_ENGLISH
SetCastle:: ID_DENMARK 24 40
SetCastle:: ID_WESSEX 100 130
"""

var _real_map: RegionMap
var _real_data: CampaignData


## Mappa di prova (indice di palette per pixel, righe dall'alto):
##   0 2 3 4 5 6 216 250
##   2 2 3 3 4 4 216 216
##   6 6 6 0 0 0 216 216
##   2 3 2 3 217 217 7 7
## Danimarca = 2,3; Svezia = 4,5; Wessex = 6,7; Mare del Nord = 216; 217 e 250 senza regione.
func _mini() -> RegionMap:
	var data := StartposLoader.load_text(MINI_STARTPOS)
	var pixels := PackedByteArray([
		0, 2, 3, 4, 5, 6, 216, 250,
		2, 2, 3, 3, 4, 4, 216, 216,
		6, 6, 6, 0, 0, 0, 216, 216,
		2, 3, 2, 3, 217, 217, 7, 7,
	])
	return RegionMap.new(LbmReader.from_indices(8, 4, pixels), data)


func _id(region: CampaignData.Region) -> String:
	return "" if region == null else region.id


func _load_real(t: TestContext) -> RegionMap:
	if not FileAccess.file_exists(GameFiles.lookup_map()):   # mappa d'Europa dell'originale: tolta da originale/ il 18/11/2026
		t.skip("installazione di MTW non trovata in %s" % GameFiles.game_dir())
		return null
	if _real_map == null:
		_real_data = StartposLoader.load_file(GameFiles.startpos())
		_real_map = RegionMap.new(LbmReader.load_file(GameFiles.lookup_map()), _real_data)
	return _real_map


func test_indice_verso_regione(t: TestContext) -> void:
	var m := _mini()
	t.assert_eq(_id(m.region_for_index(2)), "ID_DENMARK")
	t.assert_eq(_id(m.region_for_index(3)), "ID_DENMARK", "indice dispari = stessa regione")
	t.assert_eq(_id(m.region_for_index(4)), "ID_SWEDEN")
	t.assert_eq(_id(m.region_for_index(5)), "ID_SWEDEN")
	t.assert_eq(_id(m.region_for_index(6)), "ID_WESSEX")
	t.assert_eq(_id(m.region_for_index(7)), "ID_WESSEX")
	t.assert_eq(_id(m.region_for_index(8)), "", "oltre le regioni di terra dichiarate")
	t.assert_eq(_id(m.region_for_index(216)), "ID_NORTH_SEA")
	t.assert_eq(_id(m.region_for_index(217)), "", "mare non dichiarato")
	t.assert_eq(_id(m.region_for_index(0)), "")
	t.assert_eq(_id(m.region_for_index(1)), "")
	t.assert_eq(_id(m.region_for_index(-1)), "")
	t.assert_eq(_id(m.region_for_index(255)), "")


func test_regione_verso_indici(t: TestContext) -> void:
	var m := _mini()
	t.assert_eq(m.indices_for_region(m.data.region("ID_DENMARK")), PackedInt32Array([2, 3]))
	t.assert_eq(m.indices_for_region(m.data.region("ID_SWEDEN")), PackedInt32Array([4, 5]))
	t.assert_eq(m.indices_for_region(m.data.region("ID_WESSEX")), PackedInt32Array([6, 7]))
	t.assert_eq(m.indices_for_region(m.data.region("ID_NORTH_SEA")), PackedInt32Array([216]))
	for r in m.data.regions:
		for i in m.indices_for_region(r):
			t.assert_eq(m.region_for_index(i), r, "andata e ritorno per %s" % r.id)


func test_regione_al_pixel(t: TestContext) -> void:
	var m := _mini()
	t.assert_eq(_id(m.region_at_pixel(1, 0)), "ID_DENMARK")
	t.assert_eq(_id(m.region_at_pixel(2, 0)), "ID_DENMARK")
	t.assert_eq(_id(m.region_at_pixel(3, 0)), "ID_SWEDEN")
	t.assert_eq(_id(m.region_at_pixel(5, 0)), "ID_WESSEX")
	t.assert_eq(_id(m.region_at_pixel(6, 0)), "ID_NORTH_SEA")
	t.assert_eq(_id(m.region_at_pixel(0, 0)), "", "indice 0")
	t.assert_eq(_id(m.region_at_pixel(7, 0)), "", "indice 250")
	t.assert_eq(_id(m.region_at_pixel(4, 3)), "", "indice 217")
	t.assert_eq(_id(m.region_at_pixel(7, 3)), "ID_WESSEX", "indice 7")
	t.assert_eq(_id(m.region_at_pixel(8, 0)), "", "fuori a destra")
	t.assert_eq(_id(m.region_at_pixel(0, 4)), "", "fuori in basso")
	t.assert_eq(_id(m.region_at_pixel(-1, 0)), "", "fuori a sinistra")


func test_regione_alla_coordinata_startpos(t: TestContext) -> void:
	var m := _mini()
	t.assert_eq(RegionMap.startpos_to_pixel(Vector2i(24, 40)), Vector2i(1, 2))
	t.assert_eq(RegionMap.startpos_to_pixel(Vector2i(15, 16)), Vector2i(0, 1))
	t.assert_eq(RegionMap.startpos_to_pixel(Vector2i(14024, 5224)), Vector2i(876, 326))
	# Castello della Danimarca (24, 40) -> pixel (1, 2) -> indice 6 = Wessex nella mappa di prova.
	t.assert_eq(_id(m.region_at_startpos(Vector2i(24, 40))), "ID_WESSEX")
	t.assert_eq(_id(m.region_at_startpos(Vector2i(16, 0))), "ID_DENMARK", "pixel (1, 0)")
	t.assert_eq(_id(m.region_at_startpos(Vector2i(31, 15))), "ID_DENMARK", "ultimo punto del pixel (1, 0)")
	t.assert_eq(_id(m.region_at_startpos(Vector2i(100, 130))), "", "pixel (6, 8) è fuori dalla mappa")
	t.assert_eq(_id(m.region_at_startpos(Vector2i(100, 16))), "ID_NORTH_SEA", "pixel (6, 1)")


func test_gruppi(t: TestContext) -> void:
	t.assert_eq(RegionMap.group_for_index(0), 0)
	t.assert_eq(RegionMap.group_for_index(1), 0)
	t.assert_eq(RegionMap.group_for_index(2), RegionMap.group_for_index(3), "2 e 3 stessa regione")
	t.assert_eq(RegionMap.group_for_index(2), 1)
	t.assert_eq(RegionMap.group_for_index(214), 107)
	t.assert_eq(RegionMap.group_for_index(215), 107)
	t.assert_true(RegionMap.group_for_index(3) != RegionMap.group_for_index(4), "regioni vicine hanno gruppi diversi")
	t.assert_eq(RegionMap.group_for_index(216), 216)
	t.assert_eq(RegionMap.group_for_index(251), 251)


func test_tabella_dei_colori(t: TestContext) -> void:
	var m := _mini()
	var table := m.build_table()
	t.assert_eq(table.get_width(), 256, "larghezza della tabella")
	t.assert_eq(table.get_height(), 2)
	t.assert_eq(table.get_format(), Image.FORMAT_RGBA8)
	for i in [2, 3]:
		var c := table.get_pixel(i, 0)
		t.assert_eq([c.r8, c.g8, c.b8, c.a8], [200, 10, 20, 255], "Danimarca, indice %d" % i)
	for i in [6, 7]:
		var c := table.get_pixel(i, 0)
		t.assert_eq([c.r8, c.g8, c.b8, c.a8], [10, 20, 200, 255], "Wessex, indice %d" % i)
	var rebel := table.get_pixel(4, 0)
	t.assert_eq([rebel.r8, rebel.g8, rebel.b8, rebel.a8], [140, 140, 140, 255], "Svezia senza proprietario = ribelli in grigio")
	t.assert_eq(table.get_pixel(216, 0).a8, 0, "mare senza tinta")
	t.assert_eq(table.get_pixel(0, 0).a8, 0, "indice 0 senza tinta")
	t.assert_eq(table.get_pixel(100, 0).a8, 0, "indice senza regione")


func test_tabella_gruppi_e_tipi(t: TestContext) -> void:
	var m := _mini()
	var table := m.build_table()
	t.assert_eq(table.get_pixel(2, 1).g8, 1)
	t.assert_eq(table.get_pixel(3, 1).g8, 1)
	t.assert_eq(table.get_pixel(4, 1).g8, 2)
	t.assert_eq(table.get_pixel(6, 1).g8, 3)
	t.assert_eq(table.get_pixel(216, 1).g8, 216)
	t.assert_eq(table.get_pixel(2, 1).b8, 255, "terra")
	t.assert_eq(table.get_pixel(216, 1).b8, 128, "mare")
	t.assert_eq(table.get_pixel(0, 1).b8, 0, "nessuna regione")
	t.assert_eq(table.get_pixel(0, 1).g8, 0)
	t.assert_eq(table.get_pixel(2, 1).r8, 0, "nulla selezionato")


func test_tabella_evidenziazione(t: TestContext) -> void:
	var m := _mini()
	var table := m.build_table(m.data.region("ID_DENMARK"))
	t.assert_eq(table.get_pixel(2, 1).r8, 255, "indice pari evidenziato")
	t.assert_eq(table.get_pixel(3, 1).r8, 255, "indice dispari evidenziato")
	t.assert_eq(table.get_pixel(4, 1).r8, 0, "Svezia non evidenziata")
	t.assert_eq(table.get_pixel(216, 1).r8, 0)
	var sea := m.build_table(m.data.region("ID_NORTH_SEA"))
	t.assert_eq(sea.get_pixel(216, 1).r8, 255, "anche una zona di mare si evidenzia")
	t.assert_eq(sea.get_pixel(2, 1).r8, 0)


func test_reale_regioni_nell_intervallo(t: TestContext) -> void:
	var m := _load_real(t)
	if m == null:
		return
	t.assert_eq(m.data.land_regions().size(), 107)
	t.assert_eq(m.data.sea_regions().size(), 36)
	for i in range(2, 216):
		var r := m.region_for_index(i)
		t.assert_true(r != null and not r.is_sea, "indice di terra %d senza regione di terra" % i)
	for i in range(216, 252):
		var r := m.region_for_index(i)
		t.assert_true(r != null and r.is_sea, "indice di mare %d senza zona di mare" % i)
	t.assert_eq(_id(m.region_for_index(252)), "", "oltre l'ultima zona di mare")
	t.assert_eq(_id(m.region_for_index(0)), "")
	t.assert_eq(_id(m.region_for_index(1)), "")
	t.assert_eq(_id(m.region_for_index(215)), m.data.land_regions()[106].id, "ultima regione di terra")


func test_reale_danimarca_al_castello(t: TestContext) -> void:
	var m := _load_real(t)
	if m == null:
		return
	var denmark := m.data.region("ID_DENMARK")
	t.assert_eq(denmark.index, 8, "Danimarca è l'ottava regione di terra")
	t.assert_eq(denmark.castle_pos, Vector2i(14024, 5224))
	t.assert_eq(RegionMap.startpos_to_pixel(denmark.castle_pos), Vector2i(876, 326))
	t.assert_eq(m.lbm.index_at(876, 326), 18, "indice al castello")
	t.assert_eq(m.indices_for_region(denmark), PackedInt32Array([18, 19]))
	t.assert_eq(_id(m.region_at_startpos(denmark.castle_pos)), "ID_DENMARK")
	t.assert_eq(_id(m.region_at_pixel(876, 326)), "ID_DENMARK")


func test_reale_castelli_sulla_propria_regione(t: TestContext) -> void:
	var m := _load_real(t)
	if m == null:
		return
	var total := 0
	var on_own_region := 0
	var on_exact_index := 0
	var on_adjacent_odd_index := 0
	var on_sea := 0
	var sea_id := ""
	for r in m.data.land_regions():
		total += 1
		var pixel := RegionMap.startpos_to_pixel(r.castle_pos)
		var palette_index := m.lbm.index_at(pixel.x, pixel.y)
		var first := m.indices_for_region(r)[0]
		if m.region_at_startpos(r.castle_pos) == r:
			on_own_region += 1
		if palette_index == first:
			on_exact_index += 1
		elif palette_index == first + 1:
			on_adjacent_odd_index += 1
		elif palette_index >= RegionMap.SEA_FIRST_INDEX:
			on_sea += 1
			sea_id = r.id
	t.assert_eq(total, 107, "regioni di terra con castello")
	t.assert_eq(on_exact_index, 103, "castelli sull'indice esatto")
	t.assert_eq(on_adjacent_odd_index, 3, "castelli sull'indice dispari adiacente")
	t.assert_eq(on_own_region, 106, "castelli che cadono sulla propria regione")
	t.assert_eq(on_sea, 1, "castelli in mare")
	t.assert_eq(sea_id, "ID_CRIMEA", "il castello finito in mare")
	var crimea := m.data.region("ID_CRIMEA")
	var crimea_sea := m.region_at_startpos(crimea.castle_pos)
	t.assert_true(crimea_sea != null and crimea_sea.is_sea, "il pixel del castello di Crimea è una zona di mare")
	t.assert_eq(_id(crimea_sea), "ID_BLACK_SEA")


func test_reale_tabella(t: TestContext) -> void:
	var m := _load_real(t)
	if m == null:
		return
	var denmark := m.data.region("ID_DENMARK")
	var color := m.data.faction(denmark.owner).color_primary
	var table := m.build_table(denmark)
	t.assert_eq(table.get_width(), 256)
	var c := table.get_pixel(18, 0)
	t.assert_eq([c.r8, c.g8, c.b8, c.a8], [color.r8, color.g8, color.b8, 255], "colore del proprietario della Danimarca")
	t.assert_eq(table.get_pixel(18, 1).r8, 255, "Danimarca evidenziata")
	t.assert_eq(table.get_pixel(19, 1).r8, 255)
	t.assert_eq(table.get_pixel(20, 1).r8, 0)
	t.assert_eq(table.get_pixel(18, 1).g8, table.get_pixel(19, 1).g8, "stesso gruppo")
	t.assert_eq(table.get_pixel(246, 0).a8, 0, "Mar Nero senza tinta")
