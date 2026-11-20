extends RefCounted
## Test del caricatore su un startpos minimo scritto apposta.

const FIXTURE := "res://tests/fixtures/mini_startpos.txt"


func _load() -> CampaignData:
	return StartposLoader.load_file(FIXTURE)


func test_date_ed_epoche(t: TestContext) -> void:
	var d := _load()
	t.assert_eq(d.start_year, 1000)
	t.assert_eq(d.period, "EARLY")
	t.assert_eq(d.period_starts, {"EARLY": 1000, "HIGH": 1205, "LATE": 1321})
	t.assert_eq(d.unit_prod_file, "UNITS.TXT")
	t.assert_eq(d.building_prod_file, "BUILDINGS.TXT")


func test_dichiarazioni(t: TestContext) -> void:
	var d := _load()
	t.assert_eq(d.factions.size(), 3)
	t.assert_eq(d.land_regions().size(), 3)
	t.assert_eq(d.sea_regions().size(), 1)
	t.assert_eq(d.region("ID_NORTH_SEA").index, 0, "indice del primo mare")
	t.assert_eq(d.region("ID_WESSEX").index, 2, "indice della terza regione di terra")
	t.assert_eq(d.trade_goods, {"FISH": 20})


func test_id_senza_distinzione_di_maiuscole(t: TestContext) -> void:
	var d := _load()
	t.assert_eq(d.region("ID_SWEDEN").owner, "FN_DANISH", "ID_Sweden e fn_danish nel file")
	t.assert_eq(d.region("id_denmark").id, "ID_DENMARK")


func test_attributi_della_regione(t: TestContext) -> void:
	var d := _load()
	var dk := d.region("ID_DENMARK")
	t.assert_eq(dk.display_name, "Danimarca")
	t.assert_eq(dk.culture, "CATHOLIC_CULTURE")
	t.assert_eq(dk.income, 400)
	t.assert_eq(dk.castle_name, "Danimarca Castle_xzy")
	t.assert_eq(dk.castle_pos, Vector2i(7144, 4056))
	t.assert_true(dk.has_port)
	t.assert_eq(dk.trade_goods, PackedStringArray(["FISH", "SALT"]))
	t.assert_eq(dk.resources, PackedStringArray(["IRON", "GOLD"]))
	t.assert_eq(dk.buildings, PackedStringArray(["Castle15"]))
	t.assert_eq(d.region("ID_WESSEX").display_name, "Wessex // non e' un commento")
	t.assert_eq(d.region("ID_WESSEX").rebels, 55)


func test_confini(t: TestContext) -> void:
	var d := _load()
	t.assert_eq(d.adjacency_pairs(), PackedStringArray(["ID_DENMARK|ID_NORTH_SEA", "ID_DENMARK|ID_SWEDEN", "ID_NORTH_SEA|ID_WESSEX"]))
	t.assert_eq(d.asymmetric_neighbours().size(), 0)


func test_unita_iniziali(t: TestContext) -> void:
	var d := _load()
	t.assert_eq(d.start_units.size(), 3)
	t.assert_eq(d.start_units[0].unit_type, "Huscarles")
	t.assert_eq(d.start_units[0].amount, 60)
	t.assert_eq(d.start_units[1].amount, 985, "per l'emissario e' l'anno di nascita")
	t.assert_eq(d.start_units[2].culture, "CATHOLIC_CULTURE")


func test_fazione_auror(t: TestContext) -> void:
	var d := _load()
	var f := d.faction("FN_DANISH")
	t.assert_true(f.is_active())
	t.assert_eq(f.religion, "REL_CATHOLIC")
	t.assert_eq(f.behaviour, "CATHOLIC_DEFENSIVE")
	t.assert_eq(f.treasury, PackedInt32Array([99999, 99999, 99999, 99999]))
	t.assert_eq(f.color_secondary, Color8(255, 0, 0))
	t.assert_eq(f.leader_region, "ID_DENMARK")
	t.assert_eq(f.start_leader, PackedStringArray(["0", "1", "1"]))
	t.assert_eq(f.heirs.size(), 1)
	t.assert_false(d.faction("FN_ENGLISH").is_active())


func test_errori_e_comandi_ignorati(t: TestContext) -> void:
	var d := _load()
	t.assert_eq(d.errors.size(), 1, "solo ID_ATLANTIS non dichiarata")
	t.assert_true(d.errors[0].contains("ID_ATLANTIS"))
	t.assert_eq(d.ignored_commands, {"GGConquestReward": 1})


# --- personaggi (fase 4a) -------------------------------------------------------------------


const DYNASTY_FIXTURE := "res://tests/fixtures/dynasty_startpos.txt"


func test_dati_dei_capi_e_degli_eredi(t: TestContext) -> void:
	var d := StartposLoader.load_file(DYNASTY_FIXTURE)
	var alpha := d.faction("FN_ALPHA")
	t.assert_true(alpha.has_leader_data())
	t.assert_eq(alpha.leader_region, "ID_ALTA")
	t.assert_eq(alpha.start_leader, PackedStringArray(["0", "3", "0", "1", "0"]))
	t.assert_eq(alpha.leader_counters(), PackedInt32Array([0, 1, 0]), "un contatore per nome reale")
	var heirs := alpha.heir_entries()
	t.assert_eq(heirs.size(), 3)
	t.assert_eq(heirs[0], {"male": true, "age": 20})
	t.assert_eq(heirs[2], {"male": false, "age": 8}, "sesso 0 = femmina")
	t.assert_false(d.faction("FN_GAMMA").has_leader_data())
	t.assert_eq(d.faction("FN_GAMMA").leader_counters(), PackedInt32Array())
	t.assert_eq(d.faction("FN_GAMMA").heir_entries().size(), 0)


func test_mini_auror_ha_un_solo_nome_reale(t: TestContext) -> void:
	var d := _load()
	var f := d.faction("FN_DANISH")
	t.assert_eq(f.leader_counters(), PackedInt32Array([1]), "Darkos I")
	var heirs := f.heir_entries()
	t.assert_eq(heirs.size(), 1)
	t.assert_eq(heirs[0], {"male": true, "age": 13})


func test_titoli_cariche_e_file_dei_nomi(t: TestContext) -> void:
	var d := StartposLoader.load_file(DYNASTY_FIXTURE)
	t.assert_eq(d.errors.size(), 0)
	t.assert_eq(d.ignored_commands, {}, "SetNameData, AddTitle e AddOffice ora si interpretano")
	t.assert_eq(d.name_data_file, "campmap\\names\\DYNASTY_HEROES.TXT")
	t.assert_eq(d.name_data_basename(), "DYNASTY_HEROES.TXT")
	t.assert_eq(d.titles.size(), 2)
	var title := d.title_for("ID_Bassa")
	t.assert_true(title != null)
	t.assert_eq(title.region, "ID_BASSA")
	t.assert_eq(title.display_name, "Duca di Bassa")
	t.assert_eq(title.loyalty, 1)
	t.assert_eq(title.acumen, 2)
	t.assert_eq(title.dread, 0)
	t.assert_eq(title.warcraft, 1)
	t.assert_eq(title.bonus("command"), 1)
	t.assert_eq(title.bonus("acumen"), 2)
	t.assert_eq(title.bonus("unknown"), 0)
	t.assert_eq(d.title_for("ID_ALTA").display_name, "", "titolo senza nome")
	t.assert_true(d.title_for("ID_MEZZA") == null)
	t.assert_eq(d.offices.size(), 1)
	var office := d.office_for("fn_alpha", "CASTLE")
	t.assert_true(office != null)
	t.assert_eq(office.building, "castle")
	t.assert_eq(office.display_name, "Gran Maresciallo")
	t.assert_eq(office.bonus("command"), 2)
	t.assert_eq(office.bonus("loyalty"), 1)
	t.assert_eq(d.offices_of("FN_ALPHA").size(), 1)
	t.assert_eq(d.offices_of("FN_BETA").size(), 0)
	t.assert_true(d.office_for("FN_BETA", "castle") == null)


func test_titoli_con_pochi_argomenti_sono_errori(t: TestContext) -> void:
	var d := StartposLoader.load_text("DeclareLandRegion:: ID_A\nDeclareFaction:: FN_X\nAddTitle:: ID_A \"Nome\" 1 2\nAddOffice:: FN_X castle \"Nome\" 1\n")
	t.assert_eq(d.titles.size(), 0)
	t.assert_eq(d.offices.size(), 0)
	t.assert_eq(d.errors.size(), 2)
