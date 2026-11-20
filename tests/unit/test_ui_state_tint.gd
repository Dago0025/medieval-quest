extends RefCounted
## Test della tinta dei proprietari letta dallo stato di gioco (StateTint) sulla mini mappa 8x4.

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
"""


func _map() -> RegionMap:
	var data := StartposLoader.load_text(MINI_STARTPOS)
	var pixels := PackedByteArray([
		0, 2, 3, 4, 5, 6, 216, 250,
		2, 2, 3, 3, 4, 4, 216, 216,
		6, 6, 6, 0, 0, 0, 216, 216,
		2, 3, 2, 3, 217, 217, 7, 7,
	])
	return RegionMap.new(LbmReader.from_indices(8, 4, pixels), data)


func _state(map: RegionMap) -> GameState:
	var s := GameState.new(map.data)
	s.add_province(ProvinceState.new("ID_DENMARK", "FN_DANISH"))
	s.add_province(ProvinceState.new("ID_SWEDEN", "FN_REBEL"))
	s.add_province(ProvinceState.new("ID_WESSEX", "FN_ENGLISH"))
	return s


func _owner_rgb(table: Image, palette_index: int) -> Vector3i:
	var bytes := table.get_data()
	var o := (RegionMap.ROW_OWNER * RegionMap.TABLE_SIZE + palette_index) * 4
	return Vector3i(bytes[o], bytes[o + 1], bytes[o + 2])


func _owner_alpha(table: Image, palette_index: int) -> int:
	var bytes := table.get_data()
	return bytes[(RegionMap.ROW_OWNER * RegionMap.TABLE_SIZE + palette_index) * 4 + 3]


func test_i_colori_seguono_lo_stato(t: TestContext) -> void:
	var map := _map()
	var s := _state(map)
	# La Danimarca passa agli inglesi nello stato: la mappa deve diventare blu.
	s.province("ID_DENMARK").owner = "FN_ENGLISH"
	var table := StateTint.apply(map.build_table(null), map, s)
	var blue := Color(map.data.faction("FN_ENGLISH").color_primary, 1.0)
	var expected := Vector3i(blue.r8, blue.g8, blue.b8)
	t.assert_eq(_owner_rgb(table, 2), expected, "indice 2 (Danimarca)")
	t.assert_eq(_owner_rgb(table, 3), expected, "indice 3 (Danimarca)")
	t.assert_eq(_owner_rgb(table, 6), expected, "indice 6 (Wessex)")
	t.assert_eq(_owner_alpha(table, 2), 255)


func test_ribelli_e_sconosciuti_in_grigio(t: TestContext) -> void:
	var map := _map()
	var s := _state(map)
	s.province("ID_WESSEX").owner = "FN_NESSUNA"
	var table := StateTint.apply(map.build_table(null), map, s)
	var grey := Vector3i(map.rebel_color.r8, map.rebel_color.g8, map.rebel_color.b8)
	t.assert_eq(_owner_rgb(table, 4), grey, "Svezia ribelle")
	t.assert_eq(_owner_rgb(table, 6), grey, "fazione sconosciuta = grigio")


func test_il_mare_resta_senza_tinta_e_le_informazioni_non_cambiano(t: TestContext) -> void:
	var map := _map()
	var s := _state(map)
	var base := map.build_table(map.data.region("ID_DENMARK"))
	var table := StateTint.apply(base, map, s)
	t.assert_eq(_owner_alpha(table, 216), 0, "il mare non ha tinta")
	var info_before := base.get_data().slice(RegionMap.TABLE_SIZE * 4, RegionMap.TABLE_SIZE * 8)
	var info_after := table.get_data().slice(RegionMap.TABLE_SIZE * 4, RegionMap.TABLE_SIZE * 8)
	t.assert_eq(info_after, info_before, "riga delle informazioni (evidenziazione, gruppo, tipo)")
	t.assert_eq(table.get_width(), RegionMap.TABLE_SIZE)
	t.assert_eq(table.get_height(), 2)


func test_la_tabella_di_partenza_non_viene_modificata(t: TestContext) -> void:
	var map := _map()
	var s := _state(map)
	s.province("ID_DENMARK").owner = "FN_ENGLISH"
	var base := map.build_table(null)
	var before := base.get_data()
	StateTint.apply(base, map, s)
	t.assert_eq(base.get_data(), before)


func test_colore_del_proprietario(t: TestContext) -> void:
	var map := _map()
	t.assert_eq(StateTint.owner_color(map, "fn_danish"), Color(map.data.faction("FN_DANISH").color_primary, 1.0), "senza distinzione di maiuscole")
	t.assert_eq(StateTint.owner_color(map, ""), map.rebel_color)
	t.assert_eq(StateTint.owner_color(map, "FN_REBEL"), map.rebel_color)
