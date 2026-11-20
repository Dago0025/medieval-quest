extends RefCounted
## Test del lettore del file prod degli edifici: estratto di prova (9 famiglie
## reali) e file reale dell'installazione. Sul file reale si controlla la
## struttura della XL; le liste di fazioni, che includono gli Auror, non vengono
## fissate. Numeri contati sui file del 2026-11-07.

const FIXTURE := "res://tests/fixtures/mini_build_prod.txt"
const BUILD := "MTW_XL_EARLY_BUILD_PROD13.TXT"
const EARLY_UNITS := "MTW_XL_EARLY_UNIT_PROD11.TXT"
const LATE_UNITS := "MTW_XL_LATE_UNIT_PROD11.TXT"

var _fixture: BuildingProdLoader.BuildingTable
var _real: BuildingProdLoader.BuildingTable


func _mini() -> BuildingProdLoader.BuildingTable:
	if _fixture == null:
		_fixture = BuildingProdLoader.load_file(FIXTURE)
	return _fixture


func _load_real(t: TestContext) -> BuildingProdLoader.BuildingTable:
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.prod_file(BUILD)):
		t.skip("file %s non trovato in %s" % [BUILD, GameFiles.game_dir()])
		return null
	if _real == null:
		_real = BuildingProdLoader.load_file(GameFiles.prod_file(BUILD))
	return _real


func _flat(condition: Array[PackedStringArray]) -> String:
	var groups := PackedStringArray()
	for g in condition:
		groups.append("+".join(g))
	return "|".join(groups)


# --- token ------------------------------------------------------------------


func test_split_token(t: TestContext) -> void:
	t.assert_eq(BuildingProdLoader.split_token("CASTLE10"), {"family": "CASTLE", "level": 10})
	t.assert_eq(BuildingProdLoader.split_token("castle"), {"family": "CASTLE", "level": 1})
	t.assert_eq(BuildingProdLoader.split_token("SHIPYARD1"), {"family": "SHIPYARD", "level": 1})
	t.assert_eq(BuildingProdLoader.split_token("NEW_TAVERN3"), {"family": "NEW_TAVERN", "level": 3})


func test_senza_data_start(t: TestContext) -> void:
	var table := BuildingProdLoader.load_text("a\tb\n")
	t.assert_eq(table.families.size(), 0)
	t.assert_eq(table.errors.size(), 1)


# --- estratto di prova ------------------------------------------------------


func test_estratto_conteggi(t: TestContext) -> void:
	var table := _mini()
	t.assert_eq(table.errors, PackedStringArray(), "errori")
	t.assert_eq(table.families.size(), 9)
	t.assert_eq(table.level_total(), 36, "15+4+4+4+1+2+4+1+1")
	t.assert_eq(table.column_names.size(), 28)
	t.assert_eq(table.families[0].id, "CASTLE")
	t.assert_true(table.has_family("castle"))
	t.assert_false(table.has_family("PORT"))


func test_estratto_castello(t: TestContext) -> void:
	var c := _mini().get_family("CASTLE")
	t.assert_eq(c.level_count(), 15)
	t.assert_eq(c.types, PackedStringArray(["CASTLE", "TROOP_PRODUCER"]))
	t.assert_false(c.is_unique())
	t.assert_true(c.has_type("troop_producer"))
	t.assert_eq(c.token(1), "CASTLE")
	t.assert_eq(c.token(15), "CASTLE15")
	var costs := PackedInt32Array()
	var times := PackedInt32Array()
	var techs := PackedInt32Array()
	for lv in c.levels:
		costs.append(lv.cost)
		times.append(lv.build_time)
		techs.append(lv.tech_level)
	t.assert_eq(costs, PackedInt32Array([400, 100, 100, 1000, 200, 200, 2000, 300, 300, 4000, 500, 500, 8000, 1000, 1000]))
	t.assert_eq(times, PackedInt32Array([4, 1, 1, 8, 2, 2, 12, 3, 3, 16, 5, 5, 20, 10, 10]))
	t.assert_eq(techs, PackedInt32Array([0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4, 4]))
	t.assert_eq(c.get_level(1).label, "Fort")
	t.assert_eq(c.get_level(15).label, "Fortress Artillerytowers2")
	t.assert_eq(c.get_level(1).capacity, 240)
	t.assert_eq(c.get_level(15).capacity, 960)
	t.assert_eq(c.get_level(1).mercenary_magnetism, -10)
	t.assert_eq(c.get_level(15).mercenary_magnetism, -40)
	t.assert_true(c.get_level(0) == null and c.get_level(16) == null)


func test_estratto_requisiti(t: TestContext) -> void:
	var c := _mini().get_family("CASTLE")
	t.assert_eq(_flat(c.get_level(1).requires), "", "{} = nessun requisito")
	t.assert_eq(_flat(c.get_level(2).requires), "CASTLE")
	t.assert_eq(_flat(c.get_level(4).requires), "CASTLE|CASTLE2|CASTLE3", "gruppi annidati = OR")
	t.assert_eq(_flat(c.get_level(12).requires), "CASTLE11+GUNSMITH", "lista = AND")
	t.assert_eq(_flat(_mini().get_family("ARMOURER").get_level(1).requires), "CASTLE4+BOWYER|CASTLE4+SPEARMAKER")
	t.assert_eq(_flat(_mini().get_family("ARMOURER").get_level(2).requires), "CASTLE7+ARMOURER")
	# MERCHANT ha una virgola in più dopo l'ultimo livello: va ignorata.
	var m := _mini().get_family("MERCHANT")
	t.assert_eq(m.level_count(), 4)
	t.assert_eq(_flat(m.get_level(4).requires), "CASTLE10+MERCHANT3")


func test_estratto_fazioni_e_risorse(t: TestContext) -> void:
	var g := _mini().get_family("GUNSMITH")
	t.assert_eq(g.get_level(1).factions, PackedStringArray(["FN_EGYPTIAN", "FN_DANISH"]))
	t.assert_true(g.get_level(1).allows_faction("fn_egyptian"))
	t.assert_false(g.get_level(1).allows_faction("FN_ENGLISH"))
	t.assert_true(g.get_level(2).factions.is_empty())
	t.assert_true(g.get_level(2).allows_faction("FN_ENGLISH"), "vuoto = tutte")
	t.assert_eq(g.get_level(4).upgrades, PackedStringArray(["UPGRADE_VALOUR(1)"]))
	t.assert_eq(g.get_level(1).inventions, PackedStringArray(), "NONE non è un'invenzione")
	t.assert_eq(_mini().get_family("TAVERN").get_level(1).factions, PackedStringArray(["FN_REBEL"]))
	var metal := _mini().get_family("METALSMITH")
	for n in range(1, 5):
		t.assert_eq(metal.get_level(n).resources, PackedStringArray(["IRON"]), "risorsa valida per tutti i livelli")
	t.assert_eq(metal.get_level(1).resource(), "IRON")
	t.assert_eq(_mini().get_family("ARMOURER").get_level(1).resource(), "")
	t.assert_eq(_mini().get_family("ARMOURER").get_level(3).upgrades, PackedStringArray(["UPGRADE_ARMOUR(3)"]))


func test_estratto_rendita_e_altri_campi(t: TestContext) -> void:
	var mine := _mini().get_family("COPPER_MINE")
	t.assert_eq(mine.level_count(), 2)
	t.assert_eq(mine.get_level(1).income, 100)
	t.assert_eq(mine.get_level(2).income, 200)
	t.assert_true(mine.get_level(1).has_income())
	t.assert_eq(mine.get_level(1).cost, 500)
	t.assert_eq(mine.get_level(2).cost, 900)
	t.assert_eq(_flat(mine.get_level(1).requires), "")
	t.assert_eq(_flat(mine.get_level(2).requires), "COPPER_MINE")
	t.assert_false(_mini().get_family("MERCHANT").get_level(1).has_income())
	var cat := _mini().get_family("CATHEDRAL")
	t.assert_true(cat.is_unique())
	t.assert_eq(cat.religions, PackedStringArray(["CATHOLIC", "ORTHODOX"]))
	var lv := cat.get_level(1)
	t.assert_eq(lv.cost, 1000)
	t.assert_eq(lv.build_time, 16)
	t.assert_eq(lv.tech_level, 4)
	t.assert_eq(_flat(lv.requires), "CHURCH+CASTLE10")
	t.assert_eq(lv.glory_goals, PackedStringArray(["NOTRE_DAME", "FLORENCE_DUOMO"]))
	t.assert_eq(lv.faith, 0.15)
	t.assert_eq(lv.income, 100)
	t.assert_eq(lv.happiness, 40)
	t.assert_eq(lv.upgrades, PackedStringArray(["UPGRADE_MORALE(3)"]))
	var inn := _mini().get_family("INN")
	t.assert_true(inn.mercenary_hub)
	t.assert_eq(inn.get_level(1).mercenary_magnetism, 40)
	t.assert_false(cat.mercenary_hub)
	t.assert_eq(inn.raw.size(), 28)
	t.assert_eq(inn.raw[1], "INN", "campi grezzi conservati")


func test_estratto_risoluzione_token(t: TestContext) -> void:
	var table := _mini()
	t.assert_eq(table.resolve("CASTLE7").level, 7)
	t.assert_eq(table.resolve("castle7").family, "CASTLE")
	t.assert_eq(table.resolve("ARMOURER").level, 1)
	t.assert_eq(table.resolve("ARMOURER1").level, 1, "NOME1 = livello 1")
	t.assert_eq(table.resolve("ARMOURER4").token, "ARMOURER4")
	t.assert_true(table.resolve("ARMOURER5") == null)
	t.assert_true(table.resolve("PORT") == null, "famiglia non nell'estratto")


# --- file reale -------------------------------------------------------------


func test_reale_struttura(t: TestContext) -> void:
	var table := _load_real(t)
	if table == null:
		return
	t.assert_eq(table.errors, PackedStringArray(), "errori di lettura")
	t.assert_eq(table.families.size(), 46, "famiglie")
	t.assert_eq(table.level_total(), 112, "livelli")
	var by_levels := {}
	var unique := PackedStringArray()
	var troop := 0
	var agent := 0
	var with_income := 0
	var income_sum := 0
	var or_levels := 0
	var no_req_levels := 0
	for b in table.families:
		by_levels[b.level_count()] = int(by_levels.get(b.level_count(), 0)) + 1
		if b.is_unique():
			unique.append(b.id)
		if b.has_type("TROOP_PRODUCER"):
			troop += 1
		if b.has_type("AGENT_PRODUCER"):
			agent += 1
		t.assert_eq(b.raw.size(), 28, b.id)
		for lv in b.levels:
			if lv.has_income():
				with_income += 1
				income_sum += lv.income
			if lv.requires.size() > 1:
				or_levels += 1
			if lv.requires.is_empty():
				no_req_levels += 1
			t.assert_true(lv.cost > 0 and lv.build_time > 0, "costo e tempo: " + lv.token)
	t.assert_eq(by_levels, {1: 23, 2: 6, 3: 2, 4: 14, 15: 1}, "famiglie per numero di livelli")
	unique.sort()
	t.assert_eq(unique, PackedStringArray(["ADMIRALTY", "CATHEDRAL", "CHANCELLERY", "CONSTABLES_PALACE", "GRAND_MOSQUE", "MARSHALS_PALACE", "PAGAN_MONUMENT"]))
	t.assert_eq(troop, 13, "produttori di truppe")
	t.assert_eq(agent, 14, "produttori di agenti")
	t.assert_eq(with_income, 16, "livelli con rendita")
	t.assert_eq(income_sum, 2475, "somma delle rendite")
	t.assert_eq(or_levels, 7, "livelli con requisiti alternativi")
	t.assert_eq(no_req_levels, 10, "livelli senza requisiti")


func test_reale_castello_e_risorse(t: TestContext) -> void:
	var table := _load_real(t)
	if table == null:
		return
	var c := table.get_family("CASTLE")
	t.assert_eq(c.level_count(), 15)
	t.assert_eq(c.get_level(1).cost, 400)
	t.assert_eq(c.get_level(15).cost, 1000)
	t.assert_eq(c.get_level(13).cost, 8000)
	t.assert_eq(c.get_level(13).build_time, 20)
	t.assert_eq(c.get_level(1).capacity, 240)
	t.assert_eq(c.get_level(15).capacity, 960)
	t.assert_eq(c.get_level(10).glory_goals, PackedStringArray(["KRAK_DES_CHEVALIERS", "ALHAMBRA_PALACE"]))
	t.assert_eq(c.get_level(13).glory_goals, PackedStringArray(["KREMLIN"]))
	t.assert_eq(_flat(c.get_level(12).requires), "CASTLE11+GUNSMITH")
	t.assert_eq(_flat(c.get_level(15).requires), "CASTLE14+FOUNDRY3")
	var mines := {"COPPER_MINE": "COPPER", "SILVER_MINE": "SILVER", "GOLD_MINE": "GOLD", "SALT_MINE": "SALT", "METALSMITH": "IRON"}
	for family_id in mines:
		var b := table.get_family(family_id)
		for lv in b.levels:
			t.assert_eq(lv.resource(), mines[family_id], lv.token)
	t.assert_eq(table.get_family("IMPROVED_FARMLAND").get_level(4).income, 180)
	t.assert_eq(table.get_family("GOLD_MINE").get_level(2).income, 400)
	t.assert_eq(table.get_family("WATCH_TOWERS").frontier, true)
	t.assert_eq(table.get_family("INN").mercenary_hub, true)
	t.assert_true(table.get_family("GUNSMITH").get_level(1).factions.has("FN_EGYPTIAN"))
	t.assert_eq(table.get_family("TAVERN").get_level(1).factions, PackedStringArray(["FN_REBEL"]))
	t.assert_eq(table.get_family("CHURCH").religions, PackedStringArray(["CATHOLIC", "ORTHODOX"]))


func test_reale_i_requisiti_delle_unita_esistono(t: TestContext) -> void:
	var table := _load_real(t)
	if table == null:
		return
	for file_name: String in [EARLY_UNITS, LATE_UNITS]:
		if not FileAccess.file_exists(GameFiles.prod_file(file_name)):
			t.skip("file %s non trovato" % file_name)
			return
		var units := UnitProdLoader.load_file(GameFiles.prod_file(file_name))
		var missing := PackedStringArray()
		for u in units.units:
			for token in u.required_tokens():
				if table.resolve(token) == null:
					missing.append("%s:%s" % [u.id, token])
		t.assert_eq(missing, PackedStringArray(), "token sconosciuti nei requisiti di " + file_name)


# --- pesi e influenze dell'IA (fase 7a, colonne 9 e 10) --------------------


func _ai_table() -> BuildingProdLoader.BuildingTable:
	return BuildingProdLoader.load_file("res://tests/fixtures/ai_build_prod.txt")


func test_pesi_ia_per_livello(t: TestContext) -> void:
	var table := _ai_table()
	t.assert_eq(table.errors, PackedStringArray(), "errori di lettura")
	var castle := table.get_family("CASTLE")
	for n in range(1, 5):
		t.assert_true(castle.get_level(n).has_ai_weights(), "livello %d" % n)
	t.assert_eq(castle.get_level(1).ai_weight("POVERTY_STRICKEN"), 10.0)
	t.assert_eq(castle.get_level(4).ai_weight("POVERTY_STRICKEN"), 10.0, "un gruppo per livello")
	t.assert_eq(castle.get_level(3).ai_weight("CATHOLIC_EXPANSIONIST"), 100.0)
	var farm := table.get_family("IMPROVED_FARMLAND")
	t.assert_eq(farm.get_level(2).ai_weight("POVERTY_STRICKEN"), 800.0)
	t.assert_eq(farm.get_level(2).ai_weight("MUSLIM_DEVOUT"), 400.0)
	t.assert_eq(farm.get_level(1).ai_weight("NON_ESISTE", -1.0), -1.0)


func test_pesi_ia_un_solo_gruppo_vale_per_tutti_i_livelli(t: TestContext) -> void:
	var table := _ai_table()
	var bowyer := table.get_family("BOWYER")
	t.assert_eq(bowyer.level_count(), 2)
	t.assert_eq(bowyer.get_level(1).ai_weight("CATHOLIC_TRADER"), 120.0)
	t.assert_eq(bowyer.get_level(2).ai_weight("CATHOLIC_TRADER"), 120.0, "il solo gruppo vale anche per il secondo livello")
	var tavern := table.get_family("TAVERN")
	t.assert_eq(tavern.get_level(1).ai_weight("CATHOLIC_EXPANSIONIST", -1.0), 0.0, "peso zero: l'edificio non si vuole")


func test_gruppi_in_piu_si_ignorano(t: TestContext) -> void:
	var text := "POPE(1), REBELS(2) POPE(3), REBELS(4) POPE(5), REBELS(6)"
	var groups := UnitProdLoader.parse_weight_groups(text)
	t.assert_eq(groups.size(), 3)
	t.assert_eq(float(groups[2]["POPE"]), 5.0)
	var table := _ai_table()
	t.assert_eq(table.get_family("PORT").level_count(), 1)
	t.assert_true(table.get_family("PORT").get_level(2) == null, "nessun livello inventato per i gruppi in piu'")


func test_influenze_per_livello(t: TestContext) -> void:
	var table := _ai_table()
	var bowyer := table.get_family("BOWYER")
	t.assert_eq(bowyer.get_level(1).ai_influences.size(), 0, "il primo gruppo e' vuoto")
	var infl: Array = bowyer.get_level(2).ai_influences
	t.assert_eq(infl.size(), 1)
	t.assert_eq(str(infl[0]["token"]), "CASTLE2")
	t.assert_eq(str(infl[0]["family"]), "CASTLE")
	t.assert_eq(int(infl[0]["level"]), 2)
	t.assert_eq(float(infl[0]["bonus"]), 70.0)
	var tavern: Array = table.get_family("TAVERN").get_level(1).ai_influences
	t.assert_eq(tavern.size(), 1, "senza graffe in piu': un livello")
	t.assert_eq(float(tavern[0]["bonus"]), 100.0)


func test_influenze_senza_virgola(t: TestContext) -> void:
	# anomalia del file reale: due voci attaccate, si leggono per forma NOME(numero)
	var groups := BuildingProdLoader.parse_influence_groups("{HORSE_BREEDER3(100)ARMOURER(200)},{}")
	t.assert_eq(groups.size(), 2)
	var first: Array = groups[0]
	t.assert_eq(first.size(), 2)
	t.assert_eq(str(first[0]["family"]), "HORSE_BREEDER")
	t.assert_eq(int(first[0]["level"]), 3)
	t.assert_eq(float(first[1]["bonus"]), 200.0)
	var second: Array = groups[1]
	t.assert_eq(second.size(), 0)


func test_reale_pesi_e_influenze_ia(t: TestContext) -> void:
	var table := _load_real(t)
	if table == null:
		return
	var with_influence := 0
	for b in table.families:
		var first := b.get_level(1)
		t.assert_true(first.has_ai_weights(), "pesi di %s" % b.id)
		t.assert_eq(first.ai_weights.size(), 20, "20 profili in %s" % b.id)
		for n in range(1, b.level_count() + 1):
			if not b.get_level(n).ai_influences.is_empty():
				with_influence += 1
	t.assert_true(with_influence > 0, "qualche livello ha influenze")
