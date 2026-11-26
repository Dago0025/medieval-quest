extends RefCounted
## Test delle regole (Rules) e della partita nuova (GameSetup) su un mondo piccolo:
## tests/fixtures/sim_startpos.txt (4 regioni di terra, 2 mari, 3 fazioni + ribelli),
## sim_unit_prod.txt e sim_build_prod.txt (generati da make_sim_fixtures.py).

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world(seed_value: int = 1, rules: Rules = null) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var rule_set: Rules = rules if rules != null else Rules.new()
	return GameSetup.new_game(campaign, units, buildings, rule_set, seed_value)


func _faction_ids(s: GameState) -> PackedStringArray:
	var out := PackedStringArray()
	for f in s.factions:
		out.append(f.id)
	return out


# --- regole -------------------------------------------------------------------


func test_i_dati_di_prova_si_leggono_senza_errori(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	t.assert_eq(campaign.errors, PackedStringArray(), "errori startpos")
	t.assert_eq(units.errors, PackedStringArray(), "errori unita'")
	t.assert_eq(buildings.errors, PackedStringArray(), "errori edifici")
	t.assert_eq(units.units.size(), 11, "unita' di prova")
	t.assert_eq(buildings.families.size(), 13, "famiglie di prova")


func test_regole_predefinite_uguali_al_file(t: TestContext) -> void:
	var from_file := Rules.load_file()
	t.assert_eq(from_file.errors, PackedStringArray(), "errori di lettura di economia.cfg")
	t.assert_eq(from_file.to_dict(), Rules.new().to_dict(), "il file e i valori predefiniti devono coincidere")


func test_regole_valori_della_specifica(t: TestContext) -> void:
	var r := Rules.new()
	t.assert_eq(r.annual_scale, 0.52)
	t.assert_eq(r.final_year, 1700)
	t.assert_eq(r.max_stacks, 20, "20 unita' per esercito (Federico, 22/11/2026; 16 nell'originale)")
	t.assert_eq(r.max_building_queue, 4)
	t.assert_eq(r.max_unit_queue, 5)
	t.assert_eq(r.default_tax, 2)
	t.assert_eq(r.tax_multiplier(0), 0.75)
	t.assert_eq(r.tax_multiplier(2), 1.0)
	t.assert_eq(r.tax_multiplier(4), 1.25)
	t.assert_eq(r.farm_multiplier(0), 1.0)
	t.assert_eq(r.farm_multiplier(4), 1.8)
	t.assert_eq(r.trade_multiplier(0), 0.0, "senza edificio commerciale")
	t.assert_eq(r.trade_multiplier(1), 1.0)
	t.assert_eq(r.trade_multiplier(4), 1.6)
	t.assert_true(r.is_valid_tax(4))
	t.assert_false(r.is_valid_tax(5))
	t.assert_false(r.is_valid_tax(-1))


func test_regole_file_mancante(t: TestContext) -> void:
	var r := Rules.load_file("res://data/regole/non_esiste.cfg")
	t.assert_eq(r.errors.size(), 1, "un errore di lettura")
	t.assert_eq(r.annual_scale, 0.52, "valori predefiniti")


func test_regole_file_parziale(t: TestContext) -> void:
	var path := "user://test_sim_regole.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("tassa", "predefinita", 3)
	cfg.set_value("tassa", "moltiplicatori", [1.0, 1.0, 1.0, 1.0, 2.0])
	cfg.set_value("code", "reclutamento", 7)
	cfg.set_value("miniere", "famiglie", ["gold_mine"])
	t.assert_eq(cfg.save(path), OK, "scrittura del file di prova")
	var r := Rules.load_file(path)
	DirAccess.remove_absolute(path)
	t.assert_eq(r.errors, PackedStringArray())
	t.assert_eq(r.default_tax, 3)
	t.assert_eq(r.tax_multiplier(4), 2.0)
	t.assert_eq(r.max_unit_queue, 7)
	t.assert_eq(r.mine_families, PackedStringArray(["GOLD_MINE"]), "maiuscolo")
	t.assert_eq(r.max_building_queue, 4, "chiave assente = valore predefinito")
	t.assert_eq(r.farm_multiplier(2), 1.4)


func test_regole_tassa_predefinita_fuori_scala(t: TestContext) -> void:
	var path := "user://test_sim_regole2.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("tassa", "predefinita", 9)
	t.assert_eq(cfg.save(path), OK)
	var r := Rules.load_file(path)
	DirAccess.remove_absolute(path)
	t.assert_eq(r.errors.size(), 1)
	t.assert_eq(r.default_tax, 2)


# --- partita nuova ------------------------------------------------------------


func test_stato_di_base(t: TestContext) -> void:
	var s := _world(7)
	t.assert_eq(s.year, 1000)
	t.assert_eq(s.era, "EARLY")
	t.assert_eq(s.final_year, 1700)
	t.assert_eq(s.seed_value, 7)
	t.assert_false(s.is_finished())
	t.assert_eq(s.setup_errors, PackedStringArray(), "anomalie dei dati")
	t.assert_eq(s.events.size(), 0)
	t.assert_eq(_faction_ids(s), PackedStringArray(["FN_REBEL", "FN_ALPHA", "FN_BETA", "FN_GAMMA"]))


func test_tesoro_e_fazioni_vive(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(s.faction("FN_ALPHA").treasury, 5000, "primo valore di SetTreasury")
	t.assert_eq(s.faction("fn_beta").treasury, 2000)
	t.assert_eq(s.faction("FN_REBEL").treasury, 0, "senza SetTreasury")
	t.assert_true(s.faction("FN_ALPHA").alive)
	t.assert_true(s.faction("FN_BETA").alive)
	t.assert_false(s.faction("FN_REBEL").alive, "i ribelli non sono attivi")
	t.assert_false(s.faction("FN_GAMMA").alive, "dichiarata ma non attiva")
	t.assert_false(s.faction("FN_ALPHA").is_player)
	t.assert_true(s.faction("FN_NESSUNA") == null)


func test_province(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(s.provinces.size(), 4, "solo le regioni di terra")
	var ids := PackedStringArray()
	for p in s.provinces:
		ids.append(p.id)
		t.assert_eq(p.tax_level, 2, "tassa normale %s" % p.id)
		t.assert_eq(p.building_queue.size() + p.unit_queue.size(), 0)
	t.assert_eq(ids, PackedStringArray(["ID_ALTA", "ID_BASSA", "ID_MEZZA", "ID_SOLA"]))
	t.assert_eq(s.province("ID_ALTA").owner, "FN_ALPHA")
	t.assert_eq(s.province("id_mezza").owner, "FN_BETA")
	t.assert_eq(s.province("ID_SOLA").owner, "FN_REBEL")
	t.assert_true(s.province("ID_MARE_NORD") == null, "il mare non e' una provincia")
	t.assert_eq(s.provinces_of("FN_ALPHA").size(), 2)


func test_edifici_iniziali(t: TestContext) -> void:
	var s := _world()
	var alta := s.province("ID_ALTA")
	t.assert_eq(alta.level_of("CASTLE"), 3, "Castle3")
	t.assert_eq(alta.level_of("port"), 1, "PORT senza numero = livello 1")
	t.assert_eq(alta.level_of("IMPROVED_FARMLAND"), 2)
	t.assert_eq(alta.level_of("MERCHANT"), 2)
	t.assert_eq(alta.level_of("BOWYER"), 0)
	var bassa := s.province("ID_BASSA")
	t.assert_eq(bassa.level_of("CASTLE"), 1, "Castle = livello 1")
	t.assert_eq(bassa.level_of("GOLD_MINE"), 2)
	t.assert_eq(bassa.level_of("SALT_MINE"), 1)
	t.assert_eq(bassa.level_of("IMPROVED_FARMLAND"), 1)
	t.assert_eq(s.province("ID_MEZZA").level_of("PORT"), 1, "Port nel file")
	t.assert_eq(s.province("ID_SOLA").buildings.size(), 0)


func test_token_dei_livelli_con_numero_uno(t: TestContext) -> void:
	# SHIPYARD1 e SHIPYARD sono lo stesso livello (le unita' usano SHIPYARD1)
	var text := FileAccess.get_file_as_string(STARTPOS) + "\nMakeBuilding:: ID_SOLA SHIPYARD1\nMakeBuilding:: ID_SOLA shipyard\nMakeBuilding:: ID_SOLA Castle2\nMakeBuilding:: ID_SOLA CASTLE\n"
	var s := GameSetup.new_game(StartposLoader.load_text(text), UnitProdLoader.load_file(UNITS), BuildingProdLoader.load_file(BUILDINGS), Rules.new(), 1)
	t.assert_eq(s.setup_errors, PackedStringArray())
	t.assert_eq(s.province("ID_SOLA").level_of("SHIPYARD"), 1)
	t.assert_eq(s.province("ID_SOLA").level_of("CASTLE"), 2, "vale il livello piu' alto, non l'ultimo letto")


func test_token_e_unita_sconosciuti(t: TestContext) -> void:
	var text := FileAccess.get_file_as_string(STARTPOS) + "\nMakeBuilding:: ID_SOLA Foobar3\nMakeBuilding:: ID_SOLA Castle9\nMakeUnit:: ID_SOLA Ghost 10\nMakeUnit:: ID_SOLA Camel 1\n"
	var s := GameSetup.new_game(StartposLoader.load_text(text), UnitProdLoader.load_file(UNITS), BuildingProdLoader.load_file(BUILDINGS), Rules.new(), 1)
	t.assert_eq(s.setup_errors.size(), 4, "famiglia, livello, unita' e cavalcatura: %s" % str(s.setup_errors))
	t.assert_eq(s.province("ID_SOLA").buildings.size(), 0)


func test_eserciti_iniziali(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(s.armies.size(), 5)
	t.assert_eq(s.next_army_id, 6)
	var a1 := s.army(1)
	t.assert_eq(a1.faction, "FN_ALPHA")
	t.assert_eq(a1.region, "ID_ALTA")
	t.assert_false(a1.is_fleet)
	t.assert_eq(a1.stack_count(), 2)
	t.assert_eq(a1.stacks[0].unit_id, "Spearmen")
	t.assert_eq(a1.stacks[0].men, 100)
	t.assert_eq(a1.stacks[1].unit_id, "Archers")
	t.assert_eq(a1.stacks[1].men, 60)
	t.assert_eq(a1.stacks[0].value, 0)
	t.assert_eq(a1.men_total(), 160)
	t.assert_true(a1.path.is_empty())
	var a3 := s.army(3)
	t.assert_eq(a3.region, "ID_BASSA")
	t.assert_eq(a3.faction, "FN_ALPHA", "esercito del proprietario della regione")
	t.assert_eq(s.army(4).faction, "FN_BETA")
	t.assert_eq(s.army(5).faction, "FN_REBEL", "anche i ribelli hanno un esercito")
	t.assert_true(s.army(99) == null)
	t.assert_eq(s.armies_in("id_alta").size(), 1)
	t.assert_eq(s.armies_of("FN_ALPHA").size(), 3)


func test_flotta_nella_prima_zona_di_mare(t: TestContext) -> void:
	var s := _world()
	var fleet := s.army(2)
	t.assert_true(fleet.is_fleet)
	t.assert_eq(fleet.region, "ID_MARE_NORD", "ALTA confina con ID_MARE_NORD")
	t.assert_eq(fleet.faction, "FN_ALPHA")
	t.assert_eq(fleet.stack_count(), 1)
	t.assert_eq(fleet.stacks[0].unit_id, "Galley")
	var campaign := StartposLoader.load_file(STARTPOS)
	t.assert_eq(GameSetup.first_sea_neighbour(campaign, campaign.region("ID_ALTA")), "ID_MARE_NORD")
	t.assert_eq(GameSetup.first_sea_neighbour(campaign, campaign.region("ID_MEZZA")), "ID_MARE_SUD")
	t.assert_eq(GameSetup.first_sea_neighbour(campaign, campaign.region("ID_BASSA")), "", "entroterra")


func test_agenti_conservati(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(s.agents.size(), 2)
	t.assert_eq(s.agents[0].type_name, "EMISSARY")
	t.assert_eq(s.agents[0].faction, "FN_ALPHA")
	t.assert_eq(s.agents[0].region, "ID_BASSA")
	t.assert_eq(s.agents[0].birth_year, 985, "per gli emissari l'argomento e' l'anno di nascita")
	t.assert_eq(s.agents[1].type_name, "PRINCESS")
	t.assert_eq(s.agents[1].faction, "FN_BETA")
	t.assert_eq(s.agents[1].birth_year, 990)
	t.assert_eq(s.next_agent_id, 3)
	for a in s.armies:
		for st in a.stacks:
			t.assert_true(st.unit_id != "Emissary" and st.unit_id != "Princess", "gli agenti non sono pile")


func test_limite_di_pile_per_esercito(t: TestContext) -> void:
	var rules := Rules.new()
	rules.max_stacks = 1
	var s := _world(1, rules)
	t.assert_eq(s.armies.size(), 6, "ALTA: due eserciti di terra e la flotta")
	t.assert_eq(s.armies_in("ID_ALTA").size(), 2)
	for a in s.armies:
		t.assert_true(a.stack_count() <= 1)
	# 22 unita' in una regione con il limite normale: 20 + 2 (piu' quella gia' in SOLA)
	var lines := ""
	for i in 22:
		lines += "MakeUnit:: ID_SOLA Spearmen %d\n" % (10 + i)
	var text := FileAccess.get_file_as_string(STARTPOS) + "\n" + lines
	var s2 := GameSetup.new_game(StartposLoader.load_text(text), UnitProdLoader.load_file(UNITS), BuildingProdLoader.load_file(BUILDINGS), Rules.new(), 1)
	var sola := s2.armies_in("ID_SOLA")
	t.assert_eq(sola.size(), 2, "23 unita' = 20 + 3")
	t.assert_eq(sola[0].stack_count(), 20)
	t.assert_eq(sola[1].stack_count(), 3)


func test_epoca_secondo_le_date(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(s.era_for_year(1000), "EARLY")
	t.assert_eq(s.era_for_year(1204), "EARLY")
	t.assert_eq(s.era_for_year(1205), "HIGH")
	t.assert_eq(s.era_for_year(1320), "HIGH")
	t.assert_eq(s.era_for_year(1321), "LATE")
	t.assert_eq(s.era_for_year(1700), "LATE")


func test_generatore_con_seme(t: TestContext) -> void:
	var a := _world(42)
	var b := _world(42)
	var c := _world(43)
	var seq_a := [a.rng.randi(), a.rng.randi(), a.rng.randi()]
	var seq_b := [b.rng.randi(), b.rng.randi(), b.rng.randi()]
	var seq_c := [c.rng.randi(), c.rng.randi(), c.rng.randi()]
	t.assert_eq(seq_a, seq_b, "stesso seme, stessa sequenza")
	t.assert_true(seq_a != seq_c, "semi diversi, sequenze diverse")
