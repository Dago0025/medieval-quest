extends RefCounted
## Scenario storico e modalita' Auror (ADR-068): filtri sui file dell'installazione (startpos, prod, eroi), regole senza i
## poteri degli Auror, nomi delle fazioni, scenario nei salvataggi. I test sul file reale si saltano senza installazione.
## Ogni test rimette la modalita' Auror, il valore predefinito di Scenario nei test.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"

const SAMPLE := "SetTreasury:: FN_A\t99999\t// MOD Auror\n" + \
	"SetTreasury:: FN_B\t10000\n" + \
	"//SetActiveFaction:: FN_N\tFT_MAJOR\t// MOD Auror: fazione disattivata, senza territori (fix crash eredi)\n" + \
	"//PlaceLeader:: ID_NORWAY\tFN_N\t// MOD Auror: regione agli Auror, fazione senza territori\n" + \
	"//AddHeir:: FN_N \t 1 11\n" + \
	"//AddHeir:: FN_X \t 1 11\n" + \
	"PlaceLeader:: ID_FINLAND\tFN_S\t// MOD Auror (era ID_SWEDEN)\n" + \
	"MakeUnit:: ID_DENMARK\tHousecarle\t60\n" + \
	"// MOD Auror: esercito 1 (ID_DENMARK)\n" + \
	"MakeUnit::\tID_DENMARK\tTeutonicKnights\t40\t//FN_DANISH\n" + \
	"MakeUnit::\tID_DENMARK\tTeutonicKnights\t40\t//FN_DANISH\n" + \
	"// MOD Auror: flotta 1 (ID_DENMARK)\n" + \
	"MakeUnit::\tID_DENMARK\tCarrack\t1\t//FN_DANISH\n" + \
	"MakeUnit:: ID_SWEDEN\tArchers\t60\n" + \
	"//MakeUnit:: ID_SCANIA\tHousecarle\t60\t// MOD Auror: truppe tolte, solo le armate d'elite\n"


func test_filtro_dello_startpos(t: TestContext) -> void:
	var out := ScenarioFilter.startpos(SAMPLE, "SetTreasury:: FN_A\t10000")
	var lines := Array(out.split("\n"))
	t.assert_false(out.contains("99999"), "righe della mod tolte")
	t.assert_true(lines.has("SetTreasury:: FN_B\t10000"), "righe originali intatte")
	t.assert_true(lines.has("SetActiveFaction:: FN_N\tFT_MAJOR"), "fazione disattivata dalla mod di nuovo attiva")
	t.assert_true(lines.has("PlaceLeader:: ID_NORWAY\tFN_N"), "capitale di nuovo piazzata")
	t.assert_true(lines.has("AddHeir:: FN_N \t 1 11"), "eredi della fazione riattivata")
	t.assert_true(lines.has("//AddHeir:: FN_X \t 1 11"), "eredi commentati nell'originale restano commentati")
	t.assert_true(lines.has("PlaceLeader:: ID_SWEDEN\t\tFN_S"), "capitale spostata dalla mod rimessa dov'era")
	t.assert_false(out.contains("TeutonicKnights") or out.contains("Carrack"), "eserciti e flotte della mod tolti")
	t.assert_true(lines.has("MakeUnit:: ID_DENMARK\tHousecarle\t60") and lines.has("MakeUnit:: ID_SWEDEN\tArchers\t60"), "unita' originali")
	t.assert_true(lines.has("MakeUnit:: ID_SCANIA\tHousecarle\t60"), "truppe della XL tolte dalla mod di nuovo presenti (ADR-126)")
	t.assert_eq(lines[lines.size() - 1], "SetTreasury:: FN_A\t10000", "aggiunte in fondo")


func test_filtro_degli_eroi_e_righe_dei_prod(t: TestContext) -> void:
	var text := "SET_FORENAMES::\tFN_DANISH\t2\t1\n  \"Darkos\"\nresto"
	var rows := [["SET_FORENAMES::\tFN_DANISH\t2\t1", "SET_FORENAMES::\tFN_DANISH\t2\t8"], ["\"Darkos\"", "\"Sweyn\""]]
	t.assert_eq(ScenarioFilter.heroes(text, rows), "SET_FORENAMES::\tFN_DANISH\t2\t8\n\"Sweyn\"\nresto")
	t.assert_eq(ScenarioFilter.heroes_matches(text, rows), 2)
	var row := ScenarioFilter.patch_row(PackedStringArray(["A", "B"]), {1: "x", 3: "z"})
	t.assert_eq(row, PackedStringArray(["A", "x", "", "z"]))
	var plain := UnitProdLoader.load_file(UNITS)
	var first: UnitType = plain.units[0]
	var patched := UnitProdLoader.load_file(UNITS, {first.id.to_upper(): {UnitProdLoader.COL_COST: "1234"}})
	t.assert_eq(patched.get_unit(first.id).cost, 1234, "cella corretta prima della lettura")
	t.assert_eq(patched.units.size(), plain.units.size())


func test_regole_senza_i_poteri_degli_auror(t: TestContext) -> void:
	var r := Rules.load_file()
	t.assert_true(r.all_units_factions.has("FN_DANISH"), "modalita' Auror: ogni unita'")
	r.remove_faction_powers()
	t.assert_eq(r.combat.start_valour_of("FN_DANISH"), 0)
	t.assert_eq(r.recruit_rounds_of("FN_DANISH", true), 1)
	t.assert_false(r.all_units_factions.has("FN_DANISH"))
	t.assert_eq(r.agent_valour_floor("FN_DANISH"), 0)
	t.assert_true(r.dynasty.fixed.is_empty(), "niente comando fisso, re immortale, Darkos")
	t.assert_true(r.combat.fixed_command.is_empty() and r.combat.start_upgrades.is_empty())


func test_nomi_delle_fazioni_per_scenario(t: TestContext) -> void:
	Scenario.set_auror(true)
	t.assert_eq(FactionStyle.name_of("FN_DANISH"), "Auror")
	Scenario.set_auror(false)
	t.assert_eq(FactionStyle.name_of("FN_DANISH"), "Danesi")
	t.assert_eq(FactionStyle.full_name_of("FN_DANISH"), "I Danesi")
	t.assert_eq(FactionStyle.leader_portrait("FN_DANISH", 1), "", "niente ritratto di Darkos I")
	t.assert_eq(FactionStyle.name_of("FN_ENGLISH"), "Inglesi", "le altre fazioni non cambiano")
	t.assert_eq(Scenario.id(), Scenario.STORICO)
	Scenario.set_auror(true)
	t.assert_eq(FactionStyle.name_of("FN_DANISH"), "Auror")


func test_scenario_nei_salvataggi(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var rules := Rules.new()
	var s := GameSetup.new_game(campaign, units, buildings, rules, 3)
	t.assert_false(SaveGame.to_dict(s).has("scenario"), "senza scenario la voce non c'e' (salvataggi di prima)")
	t.assert_eq(SaveGame.scenario_of(SaveGame.to_dict(s)), Scenario.AUROR, "salvataggi di prima: Auror")
	s.scenario = Scenario.STORICO
	var d := SaveGame.to_dict(s)
	t.assert_eq(str(d["scenario"]), "storico")
	var back := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)), campaign, units, buildings, rules)
	t.assert_true(bool(back["ok"]), str(back.get("errore", "")))
	t.assert_eq((back["stato"] as GameState).scenario, "storico")
	t.assert_eq(SaveGame.scenario_of(d), Scenario.STORICO)


func test_campagna_reale_storica(t: TestContext) -> void:
	if not GameFiles.is_available():
		t.skip("installazione di MTW non trovata")
		return
	Scenario.set_auror(false)
	var d := Scenario.load_startpos()
	t.assert_eq(d.region("ID_DENMARK").owner, "FN_DANISH")
	t.assert_eq(d.region("ID_SCANIA").owner, "FN_DANISH")
	t.assert_eq(d.region("ID_NORWAY").owner, "FN_NORWEGIAN")
	t.assert_eq(d.region("ID_SWEDEN").owner, "FN_SWEDISH")
	var ids := PackedStringArray()
	for f in d.active_factions():
		ids.append(f.id)
	t.assert_true(ids.has("FN_NORWEGIAN") and ids.has("FN_SWEDISH"), "Norvegesi e Svedesi attivi")
	t.assert_eq(d.faction("FN_DANISH").treasury[0], 10000)
	t.assert_eq(d.faction("FN_NORWEGIAN").leader_region, "ID_NORWAY")
	t.assert_eq(d.faction("FN_SWEDISH").leader_region, "ID_SWEDEN")
	t.assert_eq(d.faction("FN_DANISH").heirs.size(), 3, "gli eredi danesi della XL, senza quelli aggiunti dalla mod")
	t.assert_eq(d.faction("FN_NORWEGIAN").heirs.size(), 3)
	t.assert_eq(d.start_year, 1000, "lo spostamento al 1000 resta")
	var danish_units := 0
	for su in d.start_units:
		t.assert_false(su.unit_type in ["TeutonicKnights", "KnightsTemplar", "Carrack", "Arquebusier"], "%s in %s" % [su.unit_type, su.region])
		if su.region == "ID_DENMARK":
			danish_units += 1
	t.assert_eq(danish_units, 3, "in Danimarca le unita' iniziali della XL")
	t.assert_true(d.region("ID_DENMARK").buildings.has("Castle6"), str(d.region("ID_DENMARK").buildings))
	t.assert_false(d.region("ID_DENMARK").buildings.has("Castle15"))
	t.assert_false(d.region("ID_DENMARK").resources.has("GOLD"), "niente risorse aggiunte dalla mod")
	t.assert_eq(d.errors, PackedStringArray(), "nessun errore di lettura")
	# prod: niente FN_DANISH aggiunto dalla mod, caracca dell'originale
	var units := Scenario.load_units(GameFiles.prod_file(d.unit_prod_file))
	var carrack := units.get_unit("Carrack")
	t.assert_eq(carrack.cost, 1500)
	t.assert_true(carrack.factions.has("FN_ENGLISH"), "la caracca torna di tutte le fazioni dell'originale")
	t.assert_false(units.get_unit("Longbows").allows_faction("FN_DANISH"), "arcieri lunghi solo inglesi")
	t.assert_true(units.get_unit("Housecarle").allows_faction("FN_DANISH"), "huscarl danesi come nella XL")
	t.assert_false(units.get_unit("SherwoodForesters").allows_region("ID_DENMARK"))
	t.assert_eq(Scenario.unit_overrides().size() > 100, true)
	var buildings := Scenario.load_buildings(GameFiles.prod_file(d.building_prod_file))
	t.assert_true(buildings.errors.is_empty(), str(buildings.errors))
	# eroi: niente Darkos, re famosi danesi dell'originale
	var text := TextIO.read_latin1(GameFiles.heroes_file(d.name_data_basename()))
	t.assert_eq(ScenarioFilter.heroes_matches(text, Scenario.hero_rows()), Scenario.hero_rows().size(), "ogni riga da correggere trovata")
	t.assert_false(ScenarioFilter.heroes(text, Scenario.hero_rows()).contains("\"Darkos\""))
	# partita nuova: Norvegesi e Svedesi con il loro re, i Danesi senza i potenziamenti
	var rules := Rules.load_file()
	Scenario.apply_rules(rules)
	var heroes := Scenario.load_heroes(GameFiles.heroes_file(d.name_data_basename()))
	var s := GameSetup.new_game(d, units, buildings, rules, 7, heroes)
	for fid in ["FN_DANISH", "FN_NORWEGIAN", "FN_SWEDISH"]:
		var alive := false
		for c in s.characters:
			if c.faction == fid and c.role == Character.ROLE_LEADER and c.alive:
				alive = true
				t.assert_false(c.full_name().contains("Darkos"), c.full_name())
		t.assert_true(alive, "%s ha un re" % fid)
	for a in s.armies:
		if a.faction == "FN_DANISH":
			for st in a.stacks:
				t.assert_true(st.value < 9, "le pile danesi non nascono a valore 9")
	Scenario.set_auror(true)


func test_campagna_reale_auror_invariata(t: TestContext) -> void:
	if not GameFiles.is_available():
		t.skip("installazione di MTW non trovata")
		return
	Scenario.set_auror(true)
	var d := Scenario.load_startpos()
	# ADR-078: sulla mappa del mondo gli Auror stanno sull'isola di Atlantide; la Scandinavia torna alle fazioni storiche
	for r in AtlantisScenario.ISLAND:
		t.assert_eq(d.region(r).owner, "FN_DANISH", r)
	for pair in [["ID_DENMARK", "FN_DANES"], ["ID_SCANIA", "FN_DANES"], ["ID_NORWAY", "FN_NORWEGIAN"], ["ID_SWEDEN", "FN_SWEDISH"]]:
		t.assert_eq(d.region(pair[0]).owner, pair[1], pair[0])
	t.assert_eq(d.faction("FN_DANISH").treasury[0], 99999)
