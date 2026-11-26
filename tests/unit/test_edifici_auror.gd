extends RefCounted
## Edifici, castelli e fortezza degli Auror (richiesta di Federico del 25/11/2026, prompt/edifici_auror.md): stile occidentale
## gotico, massiccio e dorato. Solo in modalita' Auror: castelli dello stile «auror» per la fazione degli Auror, icone degli
## edifici della cartella «auror» per il Culto Imperiale (mai come ripiego delle altre religioni), e nelle regioni d'origine
## degli Auror (Atlantide) gli edifici con la grafica Auror. Nello scenario storico i Danesi restano comuni.

const AUROR := "FN_DANISH"


func _ready(t: TestContext) -> bool:
	if not WorldMap.available():
		t.skip("dati della mappa del mondo assenti")
		return false
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata")
		return false
	return true


func _state() -> GameState:
	Scenario.set_auror(true)
	var c := Scenario.load_startpos()
	var units := Scenario.load_units(GameFiles.prod_file(c.unit_prod_file))
	var buildings := Scenario.load_buildings(GameFiles.prod_file(c.building_prod_file))
	var rules := Rules.load_file()
	Scenario.apply_rules(rules)
	return GameSetup.new_game(c, units, buildings, rules, 11)


func test_stile_dei_castelli_solo_in_modalita_auror(t: TestContext) -> void:
	CastleStyle.reset()
	Scenario.set_auror(true)
	t.assert_eq(CastleStyle.style_of(AUROR), CastleStyle.AUROR_STYLE)
	t.assert_eq(CastleStyle.style_of("FN_ENGLISH"), "", "le altre fazioni restano comuni")
	Scenario.set_auror(false)
	t.assert_eq(CastleStyle.style_of(AUROR), "", "scenario storico: i Danesi hanno i castelli comuni")
	t.assert_eq(CastleStyle.map_original(AUROR, 2), "")
	Scenario.set_auror(true)


func test_immagini_dei_castelli_auror(t: TestContext) -> void:
	Scenario.set_auror(true)
	if not AssetLibrary.is_available() or not AssetLibrary.is_remade("campmap/pieces/buildings/auror/CASTLE.Buf"):
		t.skip("castelli Auror non ancora preparati")
		return
	for tier in range(CastleStyle.TIER_NAMES.size()):
		t.assert_true(CastleStyle.map_original(AUROR, tier) != "", "pedina del grado %d" % tier)
		t.assert_true(CastleStyle.icon(AUROR, tier) != null, "icona del grado %d" % tier)


func test_icone_degli_edifici_auror_solo_per_il_culto_imperiale(t: TestContext) -> void:
	BuildingArt.reset()
	if not AssetLibrary.is_available() or AssetLibrary.list("campmap/review_panel/Buildings/Auror/").is_empty():
		t.skip("icone Auror non ancora preparate")
		return
	var imperial := BuildingArt.icon_path("Armourers Workshop", "ARMOURER", "IMPERIAL")
	t.assert_true(imperial.to_lower().contains("/auror/"), "Culto Imperiale: icona Auror (%s)" % imperial)
	t.assert_true(BuildingArt.icon("Armourers Workshop", "ARMOURER", "IMPERIAL") != null)
	for rel in ["CATHOLIC", "ORTHODOX", "MUSLIM", "PAGAN", "DHARMA", ""]:
		var p := BuildingArt.icon_path("Armourers Workshop", "ARMOURER", rel)
		t.assert_false(p.to_lower().contains("/auror/"), "%s non usa le icone Auror (%s)" % [rel, p])
	var church := BuildingArt.icon_path("Church", "CHURCH", "IMPERIAL")
	t.assert_true(church.to_lower().contains("/auror/"), "cappella imperiale")
	t.assert_true(BuildingArt.icon_path("Church", "CHURCH", "CATHOLIC").to_lower().contains("/catholic/"), "chiesa cattolica")


func test_atlantide_con_la_grafica_auror(t: TestContext) -> void:
	if not _ready(t):
		return
	var s := _state()
	t.assert_eq(RegionStyle.home_faction(s, "ID_ATLANTIS"), AUROR)
	t.assert_true(RegionStyle.is_auror_home(s, "ID_ATLANTIS"))
	t.assert_eq(RegionStyle.castle_faction(s, "ID_GADEIRA"), AUROR, "castelli Auror nelle altre isole")
	var fam: BuildingType = s.buildings.get_family("ARMOURER") if s.buildings != null else null
	t.assert_eq(RegionStyle.building_religion(s, "ID_GADEIRA", fam, AUROR, "CATHOLIC"), RegionStyle.AUROR_RELIGION)
	var english := ""
	for p in s.provinces:
		if p.owner == "FN_ENGLISH":
			english = p.id
			break
	t.assert_true(english != "")
	t.assert_false(RegionStyle.is_auror_home(s, english))
	s.province(english).owner = AUROR   # conquistata: vale la cultura d'origine (ADR-119)
	t.assert_true(RegionStyle.building_religion(s, english, fam, AUROR, "CATHOLIC") != RegionStyle.AUROR_RELIGION)
	Scenario.set_auror(false)
	t.assert_false(RegionStyle.is_auror_home(s, "ID_ATLANTIS"), "scenario storico: nessuna grafica Auror")
	Scenario.set_auror(true)


## Federico, 25/11/2026: anche le regioni dei ribelli all'inizio della partita, se gli Auror sono i primi a conquistarle.
func test_regioni_ribelli_conquistate_per_prime_dagli_auror(t: TestContext) -> void:
	if not _ready(t):
		return
	var s := _state()
	var rebels: Array = []
	for r in s.campaign.land_regions():
		if RegionStyle.home_faction(s, r.id) == "" and s.province(r.id) != null:
			rebels.append(r.id)
		if rebels.size() == 2:
			break
	t.assert_eq(rebels.size(), 2, "due regioni dei ribelli")
	var first: String = rebels[0]
	var second: String = rebels[1]
	t.assert_false(RegionStyle.is_auror_home(s, first), "prima della conquista: grafica comune")
	WarProcessor.transfer_province(s, s.province(first), AUROR)
	t.assert_eq(s.province(first).first_conqueror, AUROR)
	t.assert_true(RegionStyle.is_auror_home(s, first), "conquistata per prima dagli Auror")
	t.assert_eq(RegionStyle.castle_faction(s, first), AUROR)
	var fam: BuildingType = s.buildings.get_family("ARMOURER")
	t.assert_eq(RegionStyle.building_religion(s, first, fam, AUROR, "CATHOLIC"), RegionStyle.AUROR_RELIGION)
	WarProcessor.transfer_province(s, s.province(first), "FN_ENGLISH")
	t.assert_eq(s.province(first).first_conqueror, AUROR, "il primo conquistatore resta")
	t.assert_true(RegionStyle.is_auror_home(s, first), "la grafica Auror resta anche se la perdono")
	WarProcessor.transfer_province(s, s.province(second), "FN_ENGLISH")
	WarProcessor.transfer_province(s, s.province(second), AUROR)
	t.assert_false(RegionStyle.is_auror_home(s, second), "presa agli Inglesi: non sono i primi")
	t.assert_eq(RegionStyle.castle_faction(s, second), AUROR, "castello dell'occupante come per tutti (ADR-126)")
	var copy := ProvinceState.from_dict(s.province(first).to_dict())
	t.assert_eq(copy.first_conqueror, AUROR, "salvato e ricaricato")
	t.assert_false(ProvinceState.from_dict(ProvinceState.new("ID_X", "").to_dict()).to_dict().has("primo_conquistatore"), "assente se vuoto")
	Scenario.set_auror(false)
	t.assert_false(RegionStyle.is_auror_home(s, first), "scenario storico: niente grafica Auror")
	Scenario.set_auror(true)
