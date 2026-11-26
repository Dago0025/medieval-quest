extends RefCounted
## Dharma dei popoli asiatici e completamento di Giapponesi e Cinesi (richiesta di Federico del 22/11/2026): religione
## propria con tempio, monastero, grande pagoda e monaco; cultura Asian per pedine e carte degli agenti; castelli
## giapponesi e cinesi dal mastio in su.

const D := ProvinceState.DHARMA


func _ready(t: TestContext) -> bool:
	if not WorldMap.available():
		t.skip("dati della mappa del mondo assenti")
		return false
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata")
		return false
	return true


func _load() -> Dictionary:
	Scenario.set_auror(false)
	var c := Scenario.load_startpos()
	var out := {
		"campaign": c,
		"units": Scenario.load_units(GameFiles.prod_file(c.unit_prod_file)),
		"buildings": Scenario.load_buildings(GameFiles.prod_file(c.building_prod_file)),
	}
	Scenario.set_auror(true)
	return out


func test_chiavi_della_religione(t: TestContext) -> void:
	t.assert_eq(ProvinceState.RELIGIONS[6], D, "in coda all'ordine: le parita' e i salvataggi di prima non cambiano")
	t.assert_eq(GameCommands.religion_key("REL_DHARMA"), D)
	t.assert_eq(GameCommands.religion_base(D), D, "edifici e agenti propri, non di un'altra religione")
	t.assert_eq(ReligionRules.religion_key("REL_DHARMA"), D)
	t.assert_eq(ReligionRules.new().type_religion.get("MONK", ""), D)
	t.assert_eq(ProvinceRules.new().culture_religion.get("DHARMA_CULTURE", ""), "REL_DHARMA")
	t.assert_eq(ReligionRules.parse_points("DHARMA(3)"), {"DHARMA": 3.0}, "punti di conversione del monaco")
	t.assert_true(StateTint.RELIGION_COLORS.has(D), "colore della tinta religiosa")
	t.assert_eq(CampaignUiAgents.RELIGION_NAMES.get(D, ""), "Dharma")


func test_cultura_asiatica_delle_immagini(t: TestContext) -> void:
	t.assert_eq(PieceArt.culture_folder("REL_DHARMA"), "Asian", "pedine e carte degli agenti")
	t.assert_eq(PieceArt.ship_folder("REL_DHARMA"), "Asian", "giunche")
	t.assert_eq(PieceArt.culture_folder("REL_PAGAN"), "Pagan")
	t.assert_eq(PortraitArt.religion_folder("REL_DHARMA"), "Pagan", "ritratti dell'originale: quelli pagani")
	t.assert_eq(BuildingArt.religion_folders("DHARMA"), PackedStringArray(["asian", "pagan"]))


func test_fazioni_e_terre_del_dharma(t: TestContext) -> void:
	if not _ready(t):
		return
	var c: CampaignData = _load()["campaign"]
	for fid in Dharma.factions():
		var f := c.faction(fid)
		t.assert_true(f != null, "%s sulla mappa del mondo" % fid)
		if f != null:
			t.assert_eq(f.religion, "REL_DHARMA", "%s segue il Dharma" % fid)
	t.assert_eq(c.faction("FN_AZTECS").religion, "REL_PAGAN", "le fazioni non asiatiche restano come sono")
	for rid in ["ID_KINAI", "ID_KAIFENG", "ID_KOREA", "ID_KHMER", "ID_CHOLA", "ID_TIBET"]:
		var r := c.region(rid)
		t.assert_true(r != null and r.culture == Dharma.CULTURE, "%s di cultura del Dharma" % rid)
	t.assert_eq(c.region("ID_BORNEO").culture, "PAGAN_CULTURE", "le isole delle spezie restano pagane")


func test_edifici_del_dharma(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load()
	var table: BuildingProdLoader.BuildingTable = d["buildings"]
	for e in table.errors:
		t.assert_false(str(e).contains("Dharma"), str(e))
	for fid in ["DHARMA_TEMPLE", "DHARMA_MONASTERY", "DHARMA_PAGODA"]:
		var fam := table.get_family(fid)
		t.assert_true(fam != null, "%s nella tabella" % fid)
		if fam != null:
			t.assert_eq(fam.religions, PackedStringArray([D]), "%s solo del Dharma" % fid)
			t.assert_true(fam.levels.size() == 1 and fam.levels[0].faith > 0.0, "%s propaga la fede" % fid)
	t.assert_true(table.get_family("DHARMA_PAGODA").types.has("UNIQUE"), "una sola grande pagoda")
	t.assert_true(table.get_family("DHARMA_MONASTERY").levels[0].requires[0].has("DHARMA_TEMPLE"), "il monastero vuole il tempio")
	var uni := table.get_family("UNIVERSITY")
	t.assert_true(uni.religions.has(D), "universita' anche per il Dharma")
	var via_pagoda := false
	for g in uni.levels[0].requires:
		via_pagoda = via_pagoda or g.has("DHARMA_PAGODA")
	t.assert_true(via_pagoda, "universita' con la grande pagoda al posto della cattedrale")


func test_monaco_al_posto_dello_sciamano(t: TestContext) -> void:
	if not _ready(t):
		return
	var units: UnitProdLoader.UnitTable = _load()["units"]
	var monk := units.get_unit("Monk")
	t.assert_true(monk != null, "monaco nella tabella")
	if monk == null:
		return
	t.assert_eq(monk.type_name, "PRIEST", "religioso come lo sciamano")
	for fid in Dharma.factions():
		t.assert_true(monk.allows_faction(fid), "%s arruola il monaco" % fid)
	t.assert_false(monk.allows_faction("FN_AZTECS"))
	t.assert_true(monk.required_tokens().has("DHARMA_TEMPLE"), "si arruola nel tempio")
	t.assert_eq(ReligionRules.parse_points(UnitProdLoader.cell(monk.raw, 45)), {"DHARMA": 3.0})
	var shaman := units.get_unit("Shaman")
	t.assert_false(shaman.allows_faction("FN_JAPANESE"), "niente sciamano per i Giapponesi")
	t.assert_false(shaman.allows_faction("FN_CHINESE"))
	t.assert_true(shaman.allows_faction("FN_AZTECS"), "le fazioni pagane lo tengono")
	t.assert_eq(UnitTexts.singular_name("Monk"), "Monaco")
	t.assert_true(UnitTexts.description("Monk") != "", "descrizione del monaco")


func test_castelli_giapponesi_e_cinesi(t: TestContext) -> void:
	CastleStyle.reset()
	t.assert_eq(CastleStyle.style_of("FN_JAPANESE"), "japanese")
	t.assert_eq(CastleStyle.style_of("FN_CHINESE"), "chinese")
	t.assert_eq(CastleStyle.style_of("FN_ENGLISH"), "")
	t.assert_true(CastleStyle.map_original("FN_JAPANESE", 0) != "", "anche il forte ha lo stile della cultura (ADR-126)")
	t.assert_eq(CastleStyle.map_original("FN_ENGLISH", 2), "")
	t.assert_eq(CastleStyle.style_of("FN_KOREANS"), "chinese", "Coreani con i castelli cinesi")
	t.assert_eq(CastleStyle.style_of("FN_MONGOLS"), "chinese", "Mongoli con i castelli cinesi")
	for fid in ["FN_JAPANESE", "FN_CHINESE", "FN_KOREANS", "FN_MONGOLS"]:
		for tier in range(1, 5):
			t.assert_true(CastleStyle.map_original(fid, tier) != "", "pedina del castello di grado %d per %s" % [tier, fid])
			t.assert_true(CastleStyle.icon_original(fid, tier) != "", "icona del castello di grado %d per %s" % [tier, fid])


func test_immagini_asiatiche_pronte(t: TestContext) -> void:
	for state in ["awaiting", "moving"]:
		for path in ["campmap/pieces/Units/Asian/army_held_%s.BIF", "campmap/pieces/Units/Asian/army_leader_held_%s.BIF",
				"campmap/pieces/Ships/Asian/fleet_held_%s.BIF", "campmap/pieces/Agents/Asian/emissary_held_%s.BIF",
				"campmap/pieces/Agents/Asian/spy_held_%s.BIF", "campmap/pieces/Agents/Asian/assassin_held_%s.BIF",
				"campmap/pieces/Agents/Asian/priest_held_%s.BIF", "campmap/pieces/Agents/Asian/princess_held_%s.BIF"]:
			var p := str(path) % state
			t.assert_true(AssetLibrary.is_remade(p), "pedina %s" % p)
	for uid in ["Emissary", "Spy", "Assassin", "Monk", "Princess"]:
		var card := AssetLibrary.unit_card_path(uid, "Asian")
		t.assert_eq(card, "campmap/review_panel/Agents/Asian/%s.BIF" % uid, "carta asiatica di %s" % uid)
		t.assert_true(AssetLibrary.is_remade(card), "carta rifatta di %s" % uid)
	for label in ["Dharma Temple", "Dharma Monastery", "Great Pagoda"]:
		t.assert_true(AssetLibrary.is_remade("campmap/review_panel/Buildings/Asian/%s.BIF" % label), "icona di %s" % label)
	t.assert_true(AssetLibrary.is_remade("campmap/parchments/icon_dharma.BIF"), "simbolo del Dharma")


func test_castelli_aztechi_e_inca(t: TestContext) -> void:
	CastleStyle.reset()
	t.assert_eq(CastleStyle.style_of("FN_AZTECS"), "aztec")
	t.assert_eq(CastleStyle.style_of("FN_INCA"), "inca")
	for fid in ["FN_AZTECS", "FN_INCA"]:
		t.assert_true(CastleStyle.map_original(fid, 0) != "", "forte nello stile della cultura (ADR-126)")
		for tier in range(1, 5):
			t.assert_true(CastleStyle.map_original(fid, tier) != "", "pedina del castello di grado %d per %s" % [tier, fid])
			t.assert_true(CastleStyle.icon_original(fid, tier) != "", "icona del castello di grado %d per %s" % [tier, fid])


func test_castelli_del_kanem(t: TestContext) -> void:
	CastleStyle.reset()
	t.assert_eq(CastleStyle.style_of("FN_KANEM"), "kanem", "citta' saheliane di mattoni crudi (ADR-125)")
	t.assert_true(CastleStyle.map_original("FN_KANEM", 0) != "", "villaggio saheliano al posto del forte (ADR-126)")
	for tier in range(1, 5):
		t.assert_true(CastleStyle.map_original("FN_KANEM", tier) != "", "pedina del castello di grado %d" % tier)
		t.assert_true(CastleStyle.icon_original("FN_KANEM", tier) != "", "icona del castello di grado %d" % tier)


func test_forti_per_cultura_e_ribelli(t: TestContext) -> void:
	CastleStyle.reset()
	t.assert_eq(CastleStyle.style_of("FN_REBEL"), "rebel")
	t.assert_eq(CastleStyle.style_of("FN_MISSISSIPPIANS"), "mississippian")
	for fid in ["FN_JAPANESE", "FN_CHINESE", "FN_AZTECS", "FN_INCA", "FN_KANEM", "FN_MISSISSIPPIANS", "FN_CHOLA", "FN_KHMER", "FN_REBEL"]:
		t.assert_true(CastleStyle.map_original(fid, 0) != "", "forte di %s sulla mappa" % fid)
		t.assert_true(CastleStyle.icon_original(fid, 0) != "", "icona del forte di %s" % fid)
	for tier in range(1, 5):
		for fid in ["FN_MISSISSIPPIANS", "FN_CHOLA", "FN_KHMER"]:
			t.assert_true(CastleStyle.map_original(fid, tier) != "", "castello di %s di grado %d" % [fid, tier])
			t.assert_true(CastleStyle.icon_original(fid, tier) != "", "icona del castello di %s di grado %d" % [fid, tier])
		t.assert_eq(CastleStyle.map_original("FN_REBEL", tier), "", "dal mastio in su i ribelli usano i castelli comuni")
	t.assert_eq(CastleStyle.map_original("FN_ENGLISH", 0), "", "gli Europei restano col forte comune")
