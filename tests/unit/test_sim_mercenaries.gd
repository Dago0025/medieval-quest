extends RefCounted
## Test dei mercenari (fase 8d): regole dal file, comparsa e scioglimento delle compagnie, ingaggio (costo, esercito, pila
## mercenaria), mantenimento maggiorato, niente riaddestramento, salvataggio. Mondo di prova: agent_world.gd.

const W := preload("res://tests/unit/agent_world.gd")


func _world() -> GameState:
	var s := W.world()
	for id in ["Spearmen", "Archers"]:
		s.units.get_unit(id).mercenary = true
	s.faction(W.A).treasury = 10000
	return s


func test_regole_dal_file_uguali_ai_predefiniti(t: TestContext) -> void:
	var r := MercenaryRules.load_file()
	t.assert_true(r.errors.is_empty(), str(r.errors))
	t.assert_eq(r.to_dict(), MercenaryRules.new().to_dict(), "file e predefiniti coincidono")
	t.assert_eq(r.hire_cost(100), 150)


func test_le_compagnie_compaiono_e_si_sciolgono(t: TestContext) -> void:
	var s := _world()
	s.rules.mercenaries.new_per_year = 20
	MercenaryProcessor.process_year(s)
	var total := 0
	for pid in s.mercenaries:
		var list: Array = s.mercenaries[pid]
		t.assert_true(list.size() <= s.rules.mercenaries.max_per_province, "al massimo %d per provincia" % s.rules.mercenaries.max_per_province)
		for c in list:
			t.assert_true(["Spearmen", "Archers"].has(str(c["unita"])), "solo unita' con la colonna 49: %s" % c["unita"])
		total += list.size()
	t.assert_true(total > 0, "sono comparse compagnie")
	s.rules.mercenaries.new_per_year = 0
	s.rules.mercenaries.move_chance = 0.0
	for i in s.rules.mercenaries.max_age:
		MercenaryProcessor.process_year(s)
	t.assert_true(s.mercenaries.is_empty(), "dopo %d anni si sciolgono tutte" % s.rules.mercenaries.max_age)


func test_ingaggio(t: TestContext) -> void:
	var s := _world()
	s.mercenaries[W.BASSA] = [{"unita": "Spearmen", "uomini": 80, "valore": 1, "anni": 2}]
	var opts := GameCommands.mercenary_options(s, W.A, W.BASSA)
	t.assert_eq(opts.size(), 1)
	t.assert_eq(int(opts[0]["costo"]), 150, "costo dell'unita' x 1,5")
	t.assert_false(bool(GameCommands.can_hire_mercenary(s, W.B, W.BASSA, 0)["ok"]), "solo nelle proprie province")
	var before := s.faction(W.A).treasury
	var r := GameCommands.hire_mercenary(s, W.A, W.BASSA, 0)
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_eq(s.faction(W.A).treasury, before - 150)
	t.assert_false(s.mercenaries.has(W.BASSA), "la compagnia lascia la provincia")
	var army := s.army(int(r["esercito"]))
	var st: UnitStack = army.stacks[army.stacks.size() - 1]
	t.assert_true(st.mercenary, "pila mercenaria")
	t.assert_eq(st.men, 80, "con i suoi uomini")
	t.assert_eq(st.value, 1, "e il suo valore")
	t.assert_true(RetrainProcessor.stack_problem(s, W.A, army, army.stacks.size() - 1).begins_with("I mercenari"), "non si riaddestra")
	var normal := UnitStack.new("Spearmen", 80, 0)
	var probe := Army.new()
	probe.stacks.append(normal)
	var base := Economy.army_support_sum(s, probe)
	probe.stacks[0] = st
	t.assert_eq(Economy.army_support_sum(s, probe), roundi(base * s.rules.mercenaries.upkeep_factor), "mantenimento maggiorato")
	s.faction(W.A).treasury = 10
	s.mercenaries[W.BASSA] = [{"unita": "Spearmen", "uomini": 80, "valore": 0, "anni": 0}]
	t.assert_false(bool(GameCommands.hire_mercenary(s, W.A, W.BASSA, 0)["ok"]), "tesoro insufficiente")


func test_salvataggio(t: TestContext) -> void:
	var s := _world()
	s.mercenaries[W.ALTA] = [{"unita": "Archers", "uomini": 60, "valore": 0, "anni": 3}]
	s.mercenaries[W.BASSA] = [{"unita": "Spearmen", "uomini": 100, "valore": 0, "anni": 0}]
	GameCommands.hire_mercenary(s, W.A, W.BASSA, 0)
	var d := SaveGame.to_dict(s)
	var r := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)), s.campaign, s.units, s.buildings, s.rules, s.heroes)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	var back: GameState = r["stato"]
	t.assert_eq(back.mercenaries.get(W.ALTA, []).size(), 1, "compagnie salvate")
	var merc_stacks := 0
	for a in back.armies:
		for st in a.stacks:
			if st.mercenary:
				merc_stacks += 1
	t.assert_eq(merc_stacks, 1, "la pila mercenaria resta mercenaria")
