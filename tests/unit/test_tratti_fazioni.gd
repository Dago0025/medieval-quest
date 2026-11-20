extends RefCounted
## Tratti storici delle fazioni (ADR-089, richiesta di Federico del 17/11/2026): bonus e malus da
## data/regole/tratti_fazioni.cfg su reddito, costi, tempi, mantenimento, forza, lealta', agenti e forze di partenza,
## descritti nella scelta della fazione. Mondo di prova: agent_world.gd.

const W := preload("res://tests/unit/agent_world.gd")


func _traits(entry: Dictionary, faction_id: String = W.A) -> Rules:
	var rules := W.quiet_rules()
	rules.traits.table = {faction_id: entry}
	return rules


func _world(entry: Dictionary) -> GameState:
	var s := W.world()
	s.rules.traits.table = {W.A: entry}
	return s


func test_il_file_reale_copre_tutte_le_fazioni(t: TestContext) -> void:
	var traits := FactionTraits.load_file()
	t.assert_eq(traits.errors.size(), 0, "nessun errore: %s" % ", ".join(traits.errors))
	var names := ConfigFile.new()
	t.assert_eq(names.load("res://data/fazioni.cfg"), OK)
	for id in names.get_section_keys("nomi"):
		if id == "FN_REBEL":
			continue
		t.assert_true(traits.has_traits(id), "%s ha i suoi tratti" % id)
		var e := traits.of(id)
		for key in ["titolo", "titolo_en", "descrizione", "descrizione_en"]:
			t.assert_true(str(e.get(key, "")) != "", "%s: %s" % [id, key])
		var bonus := 0
		var malus := 0
		for line in traits.lines(id):
			if bool(line["bonus"]):
				bonus += 1
			else:
				malus += 1
		t.assert_true(bonus >= 2 and malus >= 1, "%s: almeno due bonus e un malus (%d/%d)" % [id, bonus, malus])
	t.assert_eq(traits.of("FN_DANES"), traits.of("FN_DANISH"), "i Danesi della mappa del mondo come quelli dello storico")


func test_costi_tempi_e_mantenimento(t: TestContext) -> void:
	var rules := _traits({"costo_truppe": 10.0, "costo_cavalleria": -30.0, "costo_navi": -20.0, "anni_navi": -1,
		"costo_edifici": 50.0, "anni_edifici": 1, "mantenimento_navi": 100.0})
	var tr := rules.traits
	var foot := UnitType.new("Foot")
	foot.type_name = UnitType.INFANTRY
	foot.cost = 100
	foot.build_time = 1
	var horse := UnitType.new("Horse")
	horse.type_name = UnitType.CAVALRY
	horse.cost = 400
	var ship := UnitType.new("Ship")
	ship.type_name = UnitType.SHIP
	ship.cost = 500
	ship.build_time = 2
	var spy := UnitType.new("Spy")
	spy.type_name = "SPY"
	spy.cost = 100
	t.assert_eq(tr.unit_cost(W.A, foot), 110)
	t.assert_eq(tr.unit_cost(W.A, horse), 320, "cavalleria: +10% truppe e -30% cavalleria")
	t.assert_eq(tr.unit_cost(W.A, ship), 400)
	t.assert_eq(tr.unit_cost(W.A, spy), 100, "gli agenti costano come nel file")
	t.assert_eq(tr.unit_cost(W.B, foot), 100, "le altre fazioni no")
	t.assert_eq(tr.unit_years(W.A, ship), 1, "un anno in meno")
	t.assert_eq(tr.unit_years(W.A, foot), 1, "mai sotto 1, e solo per le navi")
	t.assert_eq(tr.upkeep_factor(W.A, ship), 2.0)
	t.assert_eq(tr.upkeep_factor(W.A, foot), 1.0)
	var lv := BuildingType.Level.new()
	lv.cost = 200
	lv.build_time = 2
	t.assert_eq(tr.building_cost(W.A, lv), 300)
	t.assert_eq(tr.building_years(W.A, lv), 3)


func test_forza_per_classe(t: TestContext) -> void:
	var tr := _traits({"forza_fanteria": 10.0, "forza_cavalleria": 20.0, "forza_arcieri": 30.0, "forza_navi": -10.0}).traits
	var foot := UnitType.new("Foot")
	foot.type_name = UnitType.INFANTRY
	foot.projectile = "NONE"
	var archer := UnitType.new("Archer")
	archer.type_name = UnitType.INFANTRY
	archer.projectile = "ARROW"
	var horse_archer := UnitType.new("HorseArcher")
	horse_archer.type_name = UnitType.CAVALRY
	horse_archer.unit_classes = PackedStringArray(["MISSILE"])
	var ship := UnitType.new("Ship")
	ship.type_name = UnitType.SHIP
	t.assert_true(is_equal_approx(tr.strength_factor(W.A, foot), 1.1))
	t.assert_true(is_equal_approx(tr.strength_factor(W.A, archer), 1.3), "gli arcieri a piedi non sono fanteria da mischia")
	t.assert_true(is_equal_approx(tr.strength_factor(W.A, horse_archer), 1.5), "arcieri a cavallo: cavalleria + arcieri")
	t.assert_true(is_equal_approx(tr.strength_factor(W.A, ship), 0.9))


func test_reclutamento_e_costruzioni_pagano_il_prezzo_della_fazione(t: TestContext) -> void:
	var s := _world({"costo_truppe": -50.0})
	var plain := W.world()
	var check := GameCommands.can_queue_unit(s, W.A, W.ALTA, "Spearmen")
	var base := GameCommands.can_queue_unit(plain, W.A, W.ALTA, "Spearmen")
	t.assert_true(bool(check["ok"]) and bool(base["ok"]), str(check))
	t.assert_eq(int(check["costo"]), roundi(int(base["costo"]) * 0.5))
	var before := s.faction(W.A).treasury
	t.assert_true(bool(GameCommands.queue_unit(s, W.A, W.ALTA, "Spearmen")["ok"]))
	t.assert_eq(before - s.faction(W.A).treasury, int(check["costo"]), "pagato il prezzo scontato")
	var s2 := _world({"costo_edifici": 100.0})
	for fam in s2.buildings.families:
		var b := GameCommands.can_queue_building(plain, W.A, W.ALTA, fam.id)
		if bool(b["ok"]) and int(b["costo"]) * 2 <= s2.faction(W.A).treasury:
			var b2 := GameCommands.can_queue_building(s2, W.A, W.ALTA, fam.id)
			t.assert_eq(int(b2["costo"]), int(b["costo"]) * 2, "edificio %s al doppio" % fam.id)
			return
	t.fail("nessun edificio costruibile nel mondo di prova")


func test_reddito_mantenimento_e_lealta(t: TestContext) -> void:
	var plain := W.world()
	var s := _world({"agricoltura": 50.0, "mantenimento_truppe": 100.0, "lealta": 10})
	var p0 := Economy.province_income(plain, plain.province(W.ALTA))
	var p1 := Economy.province_income(s, s.province(W.ALTA))
	t.assert_true(int(p0["agricoltura"]) > 0)
	t.assert_true(absi(int(p1["agricoltura"]) - roundi(int(p0["agricoltura"]) * 1.5)) <= 1, "agricoltura +50%%: %d -> %d" % [int(p0["agricoltura"]), int(p1["agricoltura"])])
	var land := W.land_army(s, W.A, W.ALTA)
	t.assert_eq(Economy.army_support_sum(s, land), Economy.army_support_sum(plain, W.land_army(plain, W.A, W.ALTA)) * 2)
	var terms := ProvinceProcessor.loyalty_terms(s, s.province(W.ALTA))
	var terms0 := ProvinceProcessor.loyalty_terms(plain, plain.province(W.ALTA))
	t.assert_eq(int(terms["fazione"]), 10)
	t.assert_eq(int(terms["somma"]), int(terms0["somma"]) + 10)
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province(W.MEZZA))["fazione"]), 0, "solo le province della fazione")


func test_forza_degli_eserciti_nella_risoluzione(t: TestContext) -> void:
	var plain := W.world()
	var s := _world({"forza_fanteria": 20.0, "forza_arcieri": 20.0, "forza_cavalleria": 20.0})
	var a0 := Combat.army_strength(plain, W.land_army(plain, W.A, W.ALTA))
	var a1 := Combat.army_strength(s, W.land_army(s, W.A, W.ALTA))
	t.assert_true(is_equal_approx(a1, a0 * 1.2), "%f contro %f" % [a1, a0])


func test_agenti_con_stelle_in_piu(t: TestContext) -> void:
	var s := _world({"valore_spie": 2, "valore_religiosi": -1})
	var spy := s.units.get_unit("Spy")
	var plain := W.world()
	var a := AgentProcessor.spawn_recruit(s, s.province(W.ALTA), spy)
	var b := AgentProcessor.spawn_recruit(plain, plain.province(W.ALTA), spy)
	t.assert_eq(a.valour, b.valour + 2)
	t.assert_eq(s.rules.traits.agent_bonus(W.A, "BISHOP"), -1)
	t.assert_eq(s.rules.traits.agent_bonus(W.A, "EMISSARY"), 0)


func test_forze_e_tesoro_della_partita_nuova(t: TestContext) -> void:
	var rules := _traits({"truppe_iniziali": 2, "navi_iniziali": 1, "tesoro_iniziale": 10.0})
	var s := GameSetup.new_game(StartposLoader.load_file(W.STARTPOS), UnitProdLoader.load_file(W.UNITS), BuildingProdLoader.load_file(W.BUILDINGS), rules, 7)
	var plain := W.world()
	t.assert_eq(s.faction(W.A).treasury, 5500)
	t.assert_eq(_stacks(s, W.A, false), _stacks(plain, W.A, false) + 2)
	t.assert_eq(_stacks(s, W.A, true), _stacks(plain, W.A, true) + 1)
	t.assert_eq(_stacks(s, W.B, false), _stacks(plain, W.B, false), "le altre fazioni come prima")
	t.assert_eq(s.faction(W.B).treasury, plain.faction(W.B).treasury)


func _stacks(s: GameState, faction_id: String, fleets: bool) -> int:
	var n := 0
	for a in s.armies_of(faction_id):
		if a.is_fleet == fleets:
			n += a.stacks.size()
	return n


func test_gli_auror_non_hanno_i_tratti_dei_danesi(t: TestContext) -> void:
	var was := Scenario.auror
	var rules := _traits({"commercio": 20.0}, "FN_DANISH")
	Scenario.auror = true
	Scenario.apply_rules(rules)
	t.assert_false(rules.traits.has_traits("FN_DANISH"), "modalita' Auror: poteri di auror.cfg, niente tratti")
	var storico := _traits({"commercio": 20.0}, "FN_DANISH")
	Scenario.auror = false
	Scenario.apply_rules(storico)
	t.assert_true(storico.traits.has_traits("FN_DANISH"), "scenario storico: i Danesi hanno i loro tratti")
	Scenario.auror = was


func test_righe_della_descrizione(t: TestContext) -> void:
	var tr := _traits({"commercio": 30.0, "costo_navi": -15.0, "forza_fanteria": -10.0, "anni_navi": -1, "navi_iniziali": 2,
		"lealta": -5, "valore_emissari": 2, "titolo": "La Serenissima", "descrizione": "Mercanti."}).traits
	var lines := tr.lines(W.A)
	t.assert_eq(lines.size(), 7)
	t.assert_eq(str(lines[0]["testo"]), "Commercio +30%")
	t.assert_true(bool(lines[0]["bonus"]))
	t.assert_eq(str(lines[1]["testo"]), "Costo delle navi −15%")
	t.assert_true(bool(lines[1]["bonus"]), "un costo piu' basso e' un vantaggio")
	t.assert_eq(str(lines[2]["testo"]), "Navi: 1 anno in meno per costruirle")
	t.assert_eq(str(lines[3]["testo"]), "Forza della fanteria −10%")
	t.assert_false(bool(lines[3]["bonus"]))
	t.assert_eq(str(lines[4]["testo"]), "Lealtà delle province −5")
	t.assert_eq(str(lines[5]["testo"]), "Emissari e principesse: +2 stelle")
	t.assert_eq(str(lines[6]["testo"]), "+2 navi alla partenza")
	t.assert_eq(tr.title(W.A), "La Serenissima")
	var bb := preload("res://scenes/main_menu.gd").traits_bbcode(tr, W.A)
	t.assert_true(bb.begins_with("[i]Mercanti.[/i]"))
	t.assert_true(bb.contains("[b]Punti di forza[/b]\n[color=#%s]•  Commercio +30%%" % UiTheme.INK_GOOD.to_html(false)), bb)
	t.assert_true(bb.contains("[b]Punti deboli[/b]\n[color=#%s]•  Forza della fanteria" % UiTheme.INK_BAD.to_html(false)), bb)
	t.assert_true(bb.find("Punti di forza") < bb.find("Punti deboli"), "prima i punti di forza")
