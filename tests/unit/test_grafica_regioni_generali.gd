extends RefCounted
## Richieste di Federico del 22/11/2026: (1) la grafica degli edifici resta quella della fazione e della cultura d'origine
## della regione anche dopo la conquista (RegionStyle: castelli propri, varianti delle icone; gli edifici di una religione
## che la regione non ha restano del conquistatore); (2) i generali degli Auror nati da truppe di altre fazioni prendono
## nome e ritratto della fazione dell'unita' (CharacterFactory.unit_origin, Character.origin); (3) cancellazione di piu'
## salvataggi insieme (SaveLoadPanel.delete_names). Sui file reali della mappa del mondo.

const AUROR := "FN_DANISH"


func _ready(t: TestContext) -> bool:
	if not WorldMap.available():
		t.skip("dati della mappa del mondo assenti")
		return false
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata")
		return false
	return true


func _state(auror: bool) -> GameState:
	Scenario.set_auror(auror)
	var c := Scenario.load_startpos()
	var units := Scenario.load_units(GameFiles.prod_file(c.unit_prod_file))
	var buildings := Scenario.load_buildings(GameFiles.prod_file(c.building_prod_file))
	var rules := Rules.load_file()
	Scenario.apply_rules(rules)
	var s := GameSetup.new_game(c, units, buildings, rules, 11)
	Scenario.set_auror(true)
	return s


func _a_land_region(s: GameState, faction_id: String) -> String:
	for p in s.provinces:
		if p.owner == faction_id:
			return p.id
	return ""


func test_castelli_della_fazione_d_origine(t: TestContext) -> void:
	if not _ready(t):
		return
	var s := _state(true)
	t.assert_eq(RegionStyle.home_faction(s, "ID_KINAI"), "FN_JAPANESE")
	t.assert_eq(RegionStyle.native_religion(s, "ID_KINAI"), ProvinceState.DHARMA)
	var kinai := s.province("ID_KINAI")
	kinai.owner = "FN_ENGLISH"   # conquistata dagli Inglesi
	t.assert_eq(RegionStyle.castle_faction(s, "ID_KINAI"), "FN_JAPANESE", "i castelli restano giapponesi")
	if AssetLibrary.is_remade("campmap/pieces/buildings/japanese/CASTLE.Buf"):
		t.assert_true(CastleStyle.map_original(RegionStyle.castle_faction(s, "ID_KINAI"), 2) != "", "pedina giapponese sulla mappa")
	var english := _a_land_region(s, "FN_ENGLISH")
	t.assert_true(english != "", "una regione inglese")
	s.province(english).owner = "FN_JAPANESE"   # e l'Inghilterra conquistata dai Giapponesi resta europea
	t.assert_eq(CastleStyle.map_original(RegionStyle.castle_faction(s, english), 2), "", "castelli comuni in Inghilterra")
	for r in s.campaign.land_regions():
		if SimUtil.norm(r.owner) == GameState.REBEL:
			t.assert_eq(RegionStyle.home_faction(s, r.id), "", "regione dei ribelli: nessuna fazione d'origine")
			# ADR-126: finche' e' dei ribelli ha il loro villaggio; conquistata, lo stile dell'occupante (non si eredita)
			s.province(r.id).owner = GameState.REBEL
			t.assert_eq(RegionStyle.castle_faction(s, r.id), GameState.REBEL)
			s.province(r.id).owner = "FN_JAPANESE"
			t.assert_eq(RegionStyle.castle_faction(s, r.id), "FN_JAPANESE", "lo stile del conquistatore, non quello dei ribelli")
			s.province(r.id).owner = "FN_CHINESE"
			t.assert_eq(RegionStyle.castle_faction(s, r.id), "FN_CHINESE", "e poi di chi la riconquista")
			break


func test_edifici_con_la_cultura_della_regione(t: TestContext) -> void:
	if not _ready(t):
		return
	var s := _state(true)
	s.province("ID_KINAI").owner = "FN_ENGLISH"
	var common: BuildingType = null
	for fam in s.buildings.families:
		if fam.religions.is_empty() and fam.id != s.rules.combat.castle_family:
			common = fam
			break
	t.assert_true(common != null)
	t.assert_eq(RegionStyle.building_religion(s, "ID_KINAI", common, "FN_ENGLISH"), ProvinceState.DHARMA, "edifici comuni: grafica giapponese")
	var church := s.buildings.get_family("CHURCH")
	if church != null and not GameCommands.building_allows_religion(church, ProvinceState.DHARMA):
		t.assert_eq(RegionStyle.building_religion(s, "ID_KINAI", church, "FN_ENGLISH"), "CATHOLIC", "la chiesa degli Inglesi resta cattolica")
	var temple := s.buildings.get_family("DHARMA_TEMPLE")
	if temple != null:
		t.assert_eq(RegionStyle.building_religion(s, "ID_KINAI", temple, "FN_ENGLISH"), ProvinceState.DHARMA, "il tempio resta del Dharma")
	t.assert_eq(RegionStyle.building_religion(s, "", common, "FN_ENGLISH", "X"), "CATHOLIC", "senza regione: il proprietario")
	t.assert_eq(BuildingArt.religion_folders(RegionStyle.building_religion(s, "ID_KINAI", common, "FN_ENGLISH"))[0], "asian")


func _unit_where(s: GameState, test: Callable) -> String:
	for u in s.units.units:
		if u.is_military() and test.call(u):
			return u.id
	return ""


func _army_with(s: GameState, faction_id: String, unit_id: String) -> Army:
	var region := _a_land_region(s, faction_id)
	if region == "":
		region = s.provinces[0].id
	var a := s.create_army(faction_id, region, false)
	a.stacks.append(s.new_stack(faction_id, unit_id, 40))
	return a


func test_generali_auror_dalle_unita(t: TestContext) -> void:
	if not _ready(t):
		return
	var s := _state(true)
	t.assert_true(s.rules.generals_from_units_factions.has(AUROR), "generali_dalle_unita in auror.cfg")
	var jap := _unit_where(s, func(u: UnitType) -> bool: return u.factions == PackedStringArray(["FN_JAPANESE"]) and not u.all_factions)
	t.assert_true(jap != "", "un'unita' solo giapponese")
	var a := _army_with(s, AUROR, jap)
	t.assert_eq(CharacterFactory.unit_origin(s, a), "FN_JAPANESE", "truppa giapponese: generale giapponese")
	var g := CharacterFactory.make_general(s, AUROR, a.region, s.year, s.rng, CharacterFactory.unit_origin(s, a))
	t.assert_eq(g.faction, AUROR, "resta un generale degli Auror")
	t.assert_eq(g.origin, "FN_JAPANESE")
	t.assert_eq(g.look_faction(), "FN_JAPANESE")
	t.assert_true(CharacterFactory.forenames_of(s, "FN_JAPANESE").has(g.forename), "nome giapponese: %s" % g.forename)
	t.assert_true(CharacterFactory.surnames_of(s, "FN_JAPANESE").has(g.surname), "cognome giapponese: %s" % g.surname)
	t.assert_eq(Character.from_dict(g.to_dict()).origin, "FN_JAPANESE", "salvato e ricaricato")
	var jap_portrait := PortraitArt.culture_pick("FN_JAPANESE", "general", g.id)
	if jap_portrait != "":
		t.assert_eq(PortraitArt.portrait_path(s.campaign, g), jap_portrait, "ritratto giapponese")
	# generale che nasce da solo nell'esercito senza comandante, in una provincia senza personaggi liberi: un principe
	# libero nella stessa provincia prenderebbe il comando (ADR-126: alla partenza gli Auror hanno solo tre armate e i
	# principi restano liberi)
	for p in s.provinces_of(AUROR):
		var busy := s.characters.any(func(c: Character) -> bool:
			return c.alive and c.faction == AUROR and c.army == 0 and s.character_region(c) == p.id)
		if not busy:
			a.region = p.id
			break
	DynastyProcessor.ensure_commanders(s, s.rng, s.year)
	var cmd := s.commander_of(a.id)
	t.assert_true(cmd != null and cmd.origin == "FN_JAPANESE", "comandante nato dalla truppa giapponese")
	# truppe proprie, esclusive o di tutte le fazioni: il generale resta degli Auror
	var own := _unit_where(s, func(u: UnitType) -> bool: return u.factions.has(AUROR) and not u.elite and not u.all_factions)
	if own != "":
		t.assert_eq(CharacterFactory.unit_origin(s, _army_with(s, AUROR, own)), "", "truppa propria")
	var elite := _unit_where(s, func(u: UnitType) -> bool: return u.elite)
	if elite != "":
		t.assert_eq(CharacterFactory.unit_origin(s, _army_with(s, AUROR, elite)), "", "unita' esclusiva degli Auror")
	var plain := CharacterFactory.make_general(s, AUROR, a.region, s.year, s.rng)
	t.assert_eq(plain.origin, "")
	t.assert_false(plain.to_dict().has("origine"), "salvataggi senza la voce se non serve")
	# solo gli Auror
	t.assert_eq(CharacterFactory.unit_origin(s, _army_with(s, "FN_ENGLISH", jap)), "", "le altre fazioni no")


func test_generali_storico_senza_poteri(t: TestContext) -> void:
	if not _ready(t):
		return
	var s := _state(false)
	t.assert_true(s.rules.generals_from_units_factions.is_empty(), "scenario storico: nessuna fazione")


func test_cancellazione_di_piu_salvataggi(t: TestContext) -> void:
	var names := PackedStringArray(["provamultia", "provamultib", "provamultic"])
	DirAccess.make_dir_recursive_absolute(SaveGame.SAVE_DIR)
	for n in names:
		var f := FileAccess.open(SaveGame.path_of(n), FileAccess.WRITE)
		f.store_string("{}")
		f.close()
	t.assert_eq(SaveLoadPanel.delete_names(PackedStringArray([names[0], names[2]])), 2)
	t.assert_false(FileAccess.file_exists(SaveGame.path_of(names[0])))
	t.assert_true(FileAccess.file_exists(SaveGame.path_of(names[1])), "gli altri restano")
	t.assert_false(FileAccess.file_exists(SaveGame.path_of(names[2])))
	SaveLoadPanel.delete_names(PackedStringArray([names[1]]))
	var panel := SaveLoadPanel.new()
	panel._refresh()
	panel.select_all()
	t.assert_eq(panel.selected_names().size(), SaveGame.list_summaries().size(), "«Tutti» sceglie l'intero elenco")
	panel.free()
