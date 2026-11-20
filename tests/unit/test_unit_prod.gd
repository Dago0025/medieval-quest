extends RefCounted
## Test del lettore del file prod delle unità: estratto di prova (9 righe reali
## con virgolette, liste e celle multilinea) e file reale dell'installazione.
## Sul file reale si controlla la struttura della XL; i valori che dipendono dalla
## parte Auror (unità con FN_DANISH, regioni aggiunte) non vengono fissati.
## Numeri contati sui file del 2026-11-07.

const FIXTURE := "res://tests/fixtures/mini_unit_prod.txt"
const EARLY := "MTW_XL_EARLY_UNIT_PROD11.TXT"
const LATE := "MTW_XL_LATE_UNIT_PROD11.TXT"

var _fixture: UnitProdLoader.UnitTable
var _real := {}


func _mini() -> UnitProdLoader.UnitTable:
	if _fixture == null:
		_fixture = UnitProdLoader.load_file(FIXTURE)
	return _fixture


func _load_real(t: TestContext, file_name: String) -> UnitProdLoader.UnitTable:
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.prod_file(file_name)):
		t.skip("file %s non trovato in %s" % [file_name, GameFiles.game_dir()])
		return null
	if not _real.has(file_name):
		_real[file_name] = UnitProdLoader.load_file(GameFiles.prod_file(file_name))
	return _real[file_name]


func _flat(condition: Array[PackedStringArray]) -> String:
	var groups := PackedStringArray()
	for g in condition:
		groups.append("+".join(g))
	return "|".join(groups)


# --- lettori di base --------------------------------------------------------


func test_tsv_virgolette_tab_e_a_capo(t: TestContext) -> void:
	var rows := UnitProdLoader.parse_tsv("a\t\"b\tc\"\t\"x\ny\"\t\"say \"\"hi\"\"\"\r\n\r\nz\n")
	t.assert_eq(rows.size(), 2, "righe (la vuota si salta)")
	t.assert_eq(rows[0], PackedStringArray(["a", "b\tc", "x\ny", "say \"hi\""]))
	t.assert_eq(rows[1], PackedStringArray(["z"]))


func test_liste_e_condizioni(t: TestContext) -> void:
	t.assert_eq(UnitProdLoader.split_list(" a, b,,c "), PackedStringArray(["A", "B", "C"]))
	t.assert_eq(_flat(UnitProdLoader.parse_condition("")), "")
	t.assert_eq(_flat(UnitProdLoader.parse_condition("{}")), "")
	t.assert_eq(_flat(UnitProdLoader.parse_condition("{ CASTLE}")), "CASTLE")
	t.assert_eq(_flat(UnitProdLoader.parse_condition("{ CHAPTER_HOUSE, ARMOURER2 }")), "CHAPTER_HOUSE+ARMOURER2")
	t.assert_eq(_flat(UnitProdLoader.parse_condition("{ {BOWYER2, GRAND_MOSQUE},{BOWYER2, CATHEDRAL} }")), "BOWYER2+GRAND_MOSQUE|BOWYER2+CATHEDRAL")
	t.assert_eq(_flat(UnitProdLoader.parse_condition("{{ CASTLE},{CASTLE2},{ CASTLE3}}")), "CASTLE|CASTLE2|CASTLE3")
	t.assert_eq(UnitProdLoader.split_top("{A, B},{C}, D"), PackedStringArray(["{A, B}", "{C}", "D"]))


func test_condition_met(t: TestContext) -> void:
	var cond := UnitProdLoader.parse_condition("{ {A, B},{C} }")
	t.assert_true(UnitProdLoader.condition_met(cond, PackedStringArray(["A", "B"])))
	t.assert_true(UnitProdLoader.condition_met(cond, PackedStringArray(["C"])))
	t.assert_false(UnitProdLoader.condition_met(cond, PackedStringArray(["A"])))
	t.assert_true(UnitProdLoader.condition_met(UnitProdLoader.parse_condition("{}"), PackedStringArray()))


func test_statistiche(t: TestContext) -> void:
	var s := UnitProdLoader.parse_stats("HEIGHT( 85 ), PROJECTILE_TYPE( NONE ), SCALE( 1.5 ), CHARGE_BONUS( -3 )")
	t.assert_eq(s["HEIGHT"], 85)
	t.assert_eq(s["PROJECTILE_TYPE"], "NONE")
	t.assert_eq(s["SCALE"], 1.5)
	t.assert_eq(s["CHARGE_BONUS"], -3)
	t.assert_eq(s.size(), 4)


func test_senza_data_start(t: TestContext) -> void:
	var table := UnitProdLoader.load_text("a\tb\n1\t2\n")
	t.assert_eq(table.units.size(), 0)
	t.assert_eq(table.errors.size(), 1)


# --- estratto di prova ------------------------------------------------------


func test_estratto_conteggi(t: TestContext) -> void:
	var table := _mini()
	t.assert_eq(table.errors, PackedStringArray(), "errori")
	t.assert_eq(table.units.size(), 9)
	t.assert_eq(table.column_names.size(), 52)
	t.assert_eq(table.column_names[0], "Name/Identifier")
	t.assert_eq(table.military().size(), 5, "truppe e navi")
	t.assert_eq(table.ships().size(), 1)
	t.assert_eq(table.mounts().size(), 1)
	t.assert_eq(table.agents().size(), 3)
	t.assert_eq(table.agent_type_names(), PackedStringArray(["PRIEST", "PRINCESS", "SPY"]))
	t.assert_eq(table.units[0].id, "HighlandClansman")
	t.assert_eq(table.units[8].index, 8)


func test_estratto_fanteria(t: TestContext) -> void:
	var u := _mini().get_unit("highlandclansman")
	t.assert_true(u != null, "ricerca senza maiuscole")
	t.assert_eq(u.type_name, "INFANTRY")
	t.assert_true(u.is_infantry() and u.is_military() and not u.is_agent())
	t.assert_eq(u.cost, 100)
	t.assert_eq(u.support_cost, 3)
	t.assert_eq(u.build_time, 1)
	t.assert_eq(u.base_strength, 16)
	t.assert_eq(u.men, 60)
	t.assert_eq(u.honour_step, 1)
	t.assert_eq(u.general_candidate, "DISCOURAGED")
	t.assert_eq(u.ruler_advantage, "FN_SCOTS")
	t.assert_eq(u.region_advantage, "ID_SCOTLAND")
	t.assert_eq(_flat(u.requires), "CASTLE")
	t.assert_eq(u.unit_classes, PackedStringArray(["ATTACKER", "AMBUSH"]))
	t.assert_true(u.has_moral_bonus)
	t.assert_eq(u.moral_bonus, 2)
	t.assert_eq(u.periods, PackedStringArray(["ALL_PERIODS"]))
	t.assert_true(u.scalable)
	t.assert_eq(u.charge_bonus, 7)
	t.assert_eq(u.melee_bonus, 5)
	t.assert_eq(u.defence_bonus, -3)
	t.assert_eq(u.armour_level, 1)
	t.assert_eq(u.honour_level, 2)
	t.assert_eq(u.ammo, 0)
	t.assert_eq(u.projectile, "NONE")
	t.assert_eq(u.stats.size(), 22)
	t.assert_eq(u.stat_int("FORMATIONS_PREFERRED_NUM_ROWS"), 4)
	t.assert_true(u.all_factions)
	t.assert_true(u.allows_faction("FN_ENGLISH"))
	t.assert_true(u.regions.has("ID_SCOTLAND"))
	t.assert_true(u.allows_region("id_scotland"))
	t.assert_false(u.allows_region("ID_WESSEX"))
	t.assert_eq(u.cultures, PackedStringArray(["CATHOLIC", "ORTHODOX"]))
	t.assert_true(u.allows_culture("catholic"))
	t.assert_false(u.allows_culture("MUSLIM"))
	t.assert_eq(u.weapon_type, "SWORD")
	t.assert_true(u.mercenary)
	t.assert_true(u.available_in_period("LATE"))


func test_estratto_campi_grezzi(t: TestContext) -> void:
	var u := _mini().get_unit("HighlandClansman")
	t.assert_eq(u.raw.size(), 52)
	t.assert_eq(u.raw[0], "HighlandClansman")
	t.assert_true(u.raw[31].contains("\n"), "cella multilinea tra virgolette")
	t.assert_true(u.raw[31].begins_with("SKIRMISH(0)"))
	t.assert_true(u.raw[14].begins_with("POVERTY_STRICKEN("), "colonna non interpretata")


func test_estratto_requisiti_e_liste(t: TestContext) -> void:
	var spear := _mini().get_unit("Spearmen")
	t.assert_eq(spear.cost, 150)
	t.assert_eq(spear.support_cost, 4)
	t.assert_eq(spear.men, 100)
	t.assert_eq(_flat(spear.requires), "SPEARMAKER")
	t.assert_eq(spear.weapon_type, "SPEAR")
	t.assert_eq(spear.moral_bonus, 0)
	t.assert_false(spear.has_moral_bonus)
	t.assert_eq(spear.factions.size(), 14)
	t.assert_false(spear.all_factions)
	t.assert_true(spear.allows_faction("fn_spanish"))
	t.assert_false(spear.allows_faction("FN_ENGLISH"))
	var nizari := _mini().get_unit("Nizari")
	t.assert_eq(_flat(nizari.requires), "BOWYER2+GRAND_MOSQUE|BOWYER2+CATHEDRAL")
	t.assert_eq(nizari.required_tokens(), PackedStringArray(["BOWYER2", "GRAND_MOSQUE", "CATHEDRAL"]))
	t.assert_true(UnitProdLoader.condition_met(nizari.requires, PackedStringArray(["BOWYER2", "CATHEDRAL"])))
	t.assert_false(UnitProdLoader.condition_met(nizari.requires, PackedStringArray(["BOWYER2"])))
	t.assert_eq(nizari.ammo, 36)
	t.assert_eq(nizari.projectile, "SBOW")
	t.assert_eq(nizari.honour_level, 8)
	t.assert_eq(nizari.region_advantage, "ID_SYRIA")
	t.assert_eq(nizari.cultures, PackedStringArray(["MUSLIM", "CATHOLIC"]))


func test_estratto_artiglieria_nave_agenti(t: TestContext) -> void:
	var b := _mini().get_unit("BallistaCrew")
	t.assert_true(b.is_artillery())
	t.assert_eq(b.cost, 175)
	t.assert_eq(b.build_time, 2)
	t.assert_eq(b.men, 8)
	t.assert_eq(b.ammo, 40)
	t.assert_eq(b.projectile, "BALISTA")
	t.assert_true(b.has_moral_bonus)
	t.assert_eq(b.moral_bonus, 0)
	t.assert_eq(b.unit_classes, PackedStringArray(["MISSILE", "CASTLE_DEFENDER"]))
	var c := _mini().get_unit("Carrack")
	t.assert_true(c.is_ship() and c.is_military())
	t.assert_eq(c.cost, 1500)
	t.assert_eq(c.support_cost, 50)
	t.assert_true(c.is_ship_data)
	t.assert_eq([c.ship_range, c.ship_attack, c.ship_defence, c.ship_speed, c.ship_strength], [3, 6, 3, 3, 0])
	t.assert_eq(c.ship_sunk_label, "carrack sunk message")
	t.assert_eq(_flat(c.requires), "SHIPYARD4+FOUNDRY3")
	t.assert_eq(c.stats.size(), 0, "le navi non hanno statistiche di battaglia")
	var spy := _mini().get_unit("Spy")
	t.assert_true(spy.is_agent() and spy.invisible)
	t.assert_eq(_flat(spy.requires), "BROTHEL|NEW_BROTHEL")
	t.assert_true(spy.all_factions)
	var princess := _mini().get_unit("Princess")
	t.assert_true(princess.is_agent())
	t.assert_eq(princess.cost, 0)
	t.assert_eq(princess.build_time, 0)
	t.assert_true(princess.requires.is_empty())
	t.assert_eq(princess.cultures, PackedStringArray(["CATHOLIC", "ORTHODOX", "PAGAN"]))
	var shaman := _mini().get_unit("Shaman")
	t.assert_eq(shaman.type_name, "PRIEST")
	t.assert_eq(shaman.factions, PackedStringArray(["FN_GOLDEN_HORDE", "FN_CUMANS", "FN_LITHUANIANS"]))
	var camel := _mini().get_unit("Camel")
	t.assert_true(camel.is_mount())
	t.assert_false(camel.is_military() or camel.is_agent())


# --- file reale -------------------------------------------------------------


func test_reale_struttura(t: TestContext) -> void:
	var table := _load_real(t, EARLY)
	if table == null:
		return
	t.assert_eq(table.errors, PackedStringArray(), "errori di lettura")
	t.assert_eq(table.units.size(), 256, "righe")
	t.assert_eq(table.of_type("INFANTRY").size(), 127)
	t.assert_eq(table.of_type("CAVALRY").size(), 83)
	t.assert_eq(table.of_type("ARTILLERY").size(), 13)
	t.assert_eq(table.ships().size(), 13)
	t.assert_eq(table.military().size(), 236, "fanteria + cavalleria + artiglieria + navi")
	t.assert_eq(table.mounts().size(), 5)
	# 15 voci di agente/azione ma 14 tipi distinti: Priest e Shaman sono entrambi PRIEST.
	t.assert_eq(table.agents().size(), 15)
	t.assert_eq(table.agent_type_names().size(), 14)
	t.assert_eq(table.units[0].id, "HighlandClansman")
	t.assert_eq(table.units[255].id, "Shaman")


func test_reale_coerenza_dei_campi(t: TestContext) -> void:
	var table := _load_real(t, EARLY)
	if table == null:
		return
	var with_mount := 0
	var with_moral := 0
	var invisible := PackedStringArray()
	var with_ammo := 0
	for u in table.units:
		t.assert_eq(u.raw.size(), 52, u.id)
		if u.mount_type != "":
			with_mount += 1
			t.assert_true(u.is_cavalry(), "cavalcatura su non-cavalleria: " + u.id)
		if u.has_moral_bonus:
			with_moral += 1
		if u.invisible:
			invisible.append(u.id)
		if u.ammo > 0:
			with_ammo += 1
		if u.is_ship():
			t.assert_true(u.is_ship_data, "dati nave: " + u.id)
		if u.is_infantry() or u.is_cavalry() or u.is_artillery():
			t.assert_true(u.men >= 8, "uomini: " + u.id)
			t.assert_true(u.stats.size() > 0, "statistiche: " + u.id)
	t.assert_eq(with_mount, 83, "cavalleria con cavalcatura")
	t.assert_eq(with_moral, 49, "unità con bonus morale")
	t.assert_eq(with_ammo, 78, "unità con munizioni")
	invisible.sort()
	t.assert_eq(invisible, PackedStringArray(["Assassin", "Hashishin", "SherwoodForesters", "Spy", "WelshBandits"]))


func test_reale_unita_note(t: TestContext) -> void:
	var table := _load_real(t, EARLY)
	if table == null:
		return
	var s := table.get_unit("Spearmen")
	t.assert_eq(s.cost, 150)
	t.assert_eq(s.support_cost, 4)
	t.assert_eq(s.men, 100)
	t.assert_eq(_flat(s.requires), "SPEARMAKER")
	t.assert_eq([s.charge_bonus, s.melee_bonus, s.defence_bonus, s.armour_level, s.honour_level], [5, 0, -1, 1, 2])
	# La caracca e' modificata dalla mod Auror (parte integrante, ancora in evoluzione):
	# requisiti e attacco cambiano, quindi qui si controlla solo che sia una nave leggibile.
	var c := table.get_unit("Carrack")
	t.assert_true(c != null, "la caracca esiste")
	t.assert_true(c.cost > 0 and c.ship_attack > 0, "costo e attacco navale letti")
	t.assert_false(c.requires.is_empty(), "requisiti letti")
	var crusade := table.get_unit("Crusade")
	t.assert_eq(crusade.type_name, "CRUSADE")
	t.assert_eq(crusade.cost, 1000)
	t.assert_eq(crusade.build_time, 4)
	t.assert_eq(_flat(crusade.requires), "CHAPTER_HOUSE")
	var gh := table.get_unit("GhaziInfantry")
	t.assert_eq(_flat(gh.requires), "SWORDSMITH+MOSQUE|SWORDSMITH+CHURCH")
	var or_units := PackedStringArray()
	for u in table.units:
		if u.requires.size() > 1:
			or_units.append(u.id)
	or_units.sort()
	t.assert_eq(or_units, PackedStringArray(["Assassin", "GhaziInfantry", "Hashishin", "Nizari", "Spy"]), "requisiti con alternative")
	var periods_early := 0
	for u in table.units:
		if u.periods == PackedStringArray(["EARLY"]):
			periods_early += 1
	t.assert_eq(periods_early, 26, "unità solo del periodo EARLY")


func test_reale_late_ha_le_stesse_voci(t: TestContext) -> void:
	var early := _load_real(t, EARLY)
	var late := _load_real(t, LATE)
	if early == null or late == null:
		return
	t.assert_eq(late.errors, PackedStringArray(), "errori di lettura")
	t.assert_eq(late.units.size(), early.units.size())
	for i in early.units.size():
		if late.units[i].id != early.units[i].id:
			t.assert_true(false, "ordine diverso alla riga %d: %s / %s" % [i, early.units[i].id, late.units[i].id])
			return


# --- pesi dell'IA (fase 7a, colonna 14) -------------------------------------


func test_pesi_ia_dell_estratto_di_prova(t: TestContext) -> void:
	var table := UnitProdLoader.load_file("res://tests/fixtures/ai_unit_prod.txt")
	t.assert_eq(table.errors, PackedStringArray(), "errori di lettura")
	var spear := table.get_unit("Spearmen")
	t.assert_true(spear.has_ai_weights())
	t.assert_eq(spear.ai_weights.size(), 20, "venti profili")
	t.assert_eq(spear.ai_weight("CATHOLIC_EXPANSIONIST"), 100.0)
	t.assert_eq(spear.ai_weight("catholic_expansionist"), 100.0, "il nome non distingue le maiuscole")
	var archers := table.get_unit("Archers")
	t.assert_eq(archers.ai_weight("CATHOLIC_DEFENSIVE"), 400.0)
	t.assert_eq(archers.ai_weight("CATHOLIC_EXPANSIONIST"), 0.0, "un peso zero e' un peso")
	t.assert_eq(archers.ai_weight("MUSLIM_DEVOUT"), 100.0)
	t.assert_eq(archers.ai_weight("NON_ESISTE", -1.0), -1.0, "profilo sconosciuto: valore di riserva")
	var knights := table.get_unit("Knights")
	t.assert_eq(knights.ai_weight("CATHOLIC_EXPANSIONIST"), 400.0)
	t.assert_eq(knights.ai_weight("CATHOLIC_DEFENSIVE"), 0.0)


func test_pesi_ia_unita_senza_colonna(t: TestContext) -> void:
	var table := UnitProdLoader.load_file("res://tests/fixtures/agents_unit_prod.txt")
	var any_unit := table.units[0]
	t.assert_false(any_unit.has_ai_weights(), "la tabella del 5a non ha la colonna 14")
	t.assert_eq(any_unit.ai_weight("CATHOLIC_EXPANSIONIST", 7.5), 7.5)
	t.assert_eq(any_unit.ai_weight("CATHOLIC_EXPANSIONIST"), 0.0)


func test_gruppi_di_pesi_decimali_e_ripetuti(t: TestContext) -> void:
	var one := UnitProdLoader.parse_weight_groups("POPE(0.5), REBELS(12)")
	t.assert_eq(one.size(), 1)
	t.assert_eq(float(one[0]["POPE"]), 0.5)
	t.assert_eq(float(one[0]["REBELS"]), 12.0)
	var two := UnitProdLoader.parse_weight_groups("POPE(1) REBELS(2)\n POPE(3), REBELS(4)")
	t.assert_eq(two.size(), 2, "un nuovo gruppo comincia quando un profilo si ripete")
	t.assert_eq(float(two[1]["POPE"]), 3.0)
	t.assert_eq(UnitProdLoader.parse_weight_groups("").size(), 0, "testo vuoto: nessun gruppo")


func test_reale_pesi_ia(t: TestContext) -> void:
	var table := _load_real(t, EARLY)
	if table == null:
		return
	var with_weights := 0
	for u in table.military():
		if u.has_ai_weights():
			with_weights += 1
		t.assert_eq(u.ai_weights.size(), 20, "20 profili in %s" % u.id)
	t.assert_eq(with_weights, table.military().size(), "tutte le truppe hanno i pesi")
	var some := table.military()[0]
	for profile in ["CATHOLIC_EXPANSIONIST", "POPE", "REBELS", "CLOSE_TO_SUPPORT_LIMIT", "POVERTY_STRICKEN"]:
		t.assert_true(some.ai_weights.has(profile), "profilo %s" % profile)
		t.assert_true(some.ai_weight(profile) >= 0.0)


## Unita' regionali (segnalazione di Federico dell'11/11: mancavano gli uscarli vichinghi): colonna delle fazioni vuota,
## ma regioni ed edifici indicati = le arruola chi possiede quelle regioni. Senza regioni o senza edifici restano fuori.
func test_unita_regionali_senza_elenco_di_fazioni(t: TestContext) -> void:
	var u := UnitType.new("Prova")
	u.type_name = UnitType.INFANTRY
	t.assert_false(u.recruitable_by("FN_DANISH"), "senza fazioni, regioni ne' edifici: di nessuno")
	u.regions = PackedStringArray(["ID_DENMARK"])
	t.assert_false(u.recruitable_by("FN_DANISH"), "senza edifici richiesti: solo ribelli o mercenari")
	u.requires = [PackedStringArray(["SWORDSMITH"])]
	t.assert_true(u.is_regional())
	t.assert_true(u.recruitable_by("FN_DANISH") and u.recruitable_by("FN_FRENCH"), "regionale: di chi possiede la regione")
	t.assert_false(u.allows_faction("FN_DANISH"), "la colonna delle fazioni resta vuota")
	u.factions = PackedStringArray(["FN_FRENCH"])
	t.assert_false(u.recruitable_by("FN_DANISH"), "con un elenco di fazioni vale l'elenco")
	t.assert_true(u.recruitable_by("FN_FRENCH"))


func test_reale_unita_regionali(t: TestContext) -> void:
	var table := _load_real(t, EARLY)
	if table == null:
		return
	var regional := PackedStringArray()
	for u in table.military():
		if u.is_regional():
			regional.append(u.id)
	for id in ["VikingHuscarles", "VikingKarls", "VikingLandsmenn", "VikingThralls", "VikingRaiderCavalry", "Fyrdmen",
			"SherwoodForesters", "SlavJavelinmen", "SlavWarriors", "VarangianSwordsmen"]:
		t.assert_true(regional.has(id), "unita' regionale: %s" % id)
	for id in ["JomsVikings", "WelshBandits", "EarlyVarangianGuard"]:
		t.assert_false(regional.has(id), "solo ribelli o mercenari: %s" % id)
	var land := table.land_for("FN_DANISH")
	var names := PackedStringArray()
	for u in land:
		names.append(u.id)
	t.assert_true(names.has("VikingHuscarles"), "gli uscarli vichinghi sono tra le truppe degli Auror")
