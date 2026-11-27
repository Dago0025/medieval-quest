extends RefCounted
## ADR-146: accorpamento delle pile dello stesso tipo (manuale p29) unendo eserciti, spostando pile e dopo le battaglie.

const W := preload("res://tests/unit/agent_world.gd")


func _world() -> GameState:
	var s := W.world()
	s.rules.merge_same_units = true
	s.rules.merge_after_battle = true
	return s


func _army(s: GameState, faction: String, region: String, stacks: Array) -> Army:
	var a := s.create_army(faction, region, false)
	for pair in stacks:
		a.stacks.append(UnitStack.new(str(pair[0]), int(pair[1]), int(pair[2]) if pair.size() > 2 else 0))
	return a


func _men(a: Army) -> Array:
	var out := []
	for st in a.stacks:
		out.append([st.unit_id, st.men])
	return out


func _full(s: GameState, unit: String) -> int:
	return StackMerge.full_men(s, UnitStack.new(unit, 1, 0))


func test_riempire_la_pila_piu_forte_con_la_piu_debole(t: TestContext) -> void:
	var s := _world()
	var full := _full(s, "Spearmen")
	t.assert_true(full >= 60, "organico delle lance nella fixture: %d" % full)
	var a := _army(s, W.A, W.BASSA, [["Spearmen", full - 30], ["Archers", 10], ["Spearmen", 20], ["Spearmen", full - 10]])
	var moved := StackMerge.consolidate(s, a)
	t.assert_eq(moved, 20, "i 20 uomini della pila piu' debole")
	t.assert_eq(_men(a), [["Spearmen", full - 20], ["Archers", 10], ["Spearmen", full]], "la piu' forte si riempie per prima (10), il resto va alla seconda, la vuota sparisce, l'ordine resta")
	t.assert_eq(StackMerge.consolidate(s, a), 0, "una seconda volta non cambia nulla")


func test_valore_medio_e_mercenari_a_parte(t: TestContext) -> void:
	var s := _world()
	var full := _full(s, "Spearmen")
	var a := _army(s, W.A, W.BASSA, [["Spearmen", full - 20, 4], ["Spearmen", 20, 0], ["Spearmen", 30, 2]])
	a.stacks[2].mercenary = true
	StackMerge.consolidate(s, a)
	t.assert_eq(a.stacks.size(), 2, "il mercenario non si accorpa con le pile normali")
	t.assert_eq(a.stacks[0].men, full)
	t.assert_eq(a.stacks[0].value, roundi(float(4 * (full - 20)) / float(full)), "valore = media sugli uomini")
	t.assert_eq(a.stacks[1].men, 30)


func test_unire_due_eserciti_riempie_le_pile_uguali(t: TestContext) -> void:
	var s := _world()
	var full := _full(s, "Spearmen")
	var a := _army(s, W.A, W.BASSA, [["Spearmen", full / 2], ["Archers", 10]])
	var b := _army(s, W.A, W.BASSA, [["Spearmen", full / 2], ["Spearmen", 5]])
	var before := a.men_total() + b.men_total()
	var r := GameCommands.merge_armies(s, W.A, a.id, b.id)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_true(s.army(a.id) == null, "l'esercito di partenza sparisce")
	t.assert_eq(b.men_total(), before, "nessun uomo perso")
	t.assert_eq(b.stacks.size(), 3, "lance: piena + 5 uomini, piu' gli arcieri")
	t.assert_eq(b.stacks[0].men, full, "la pila di destinazione e' piena")
	t.assert_true(int(r["uomini_accorpati"]) > 0)


func test_spostare_una_pila_riempie_quella_di_destinazione(t: TestContext) -> void:
	var s := _world()
	var full := _full(s, "Spearmen")
	var a := _army(s, W.A, W.BASSA, [["Spearmen", full - 10], ["Archers", 40]])
	var b := _army(s, W.A, W.BASSA, [["Spearmen", full - 25]])
	var r := GameCommands.transfer_stacks(s, W.A, a.id, b.id, PackedInt32Array([0]))
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_eq(_men(b), [["Spearmen", full], ["Spearmen", full - 35]], "la pila che c'era si riempie, l'eccedenza resta in quella arrivata")


func test_il_posto_si_conta_dopo_l_accorpamento(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.A, W.BASSA, [])
	var b := _army(s, W.A, W.BASSA, [])
	for i in s.rules.max_stacks:
		b.stacks.append(UnitStack.new("Spearmen", 10, 0))
	a.stacks.append(UnitStack.new("Spearmen", 10, 0))
	t.assert_true(bool(GameCommands.order_merge(s, W.A, a.id, b.id)["ok"]), "21 pile da 10 uomini stanno in poche pile piene")
	t.assert_true(b.stacks.size() < s.rules.max_stacks)
	var c := _army(s, W.A, W.BASSA, [["Archers", 10]])
	var full := _army(s, W.A, W.BASSA, [])
	for i in s.rules.max_stacks:
		full.stacks.append(UnitStack.new("Knights", _full(s, "Knights"), 0))
	t.assert_false(bool(GameCommands.merge_armies(s, W.A, c.id, full.id)["ok"]), "pile diverse: il limite resta")


func test_senza_la_regola_niente_accorpamento(t: TestContext) -> void:
	var s := W.world()
	s.rules.merge_same_units = false
	var a := _army(s, W.A, W.BASSA, [["Spearmen", 20]])
	var b := _army(s, W.A, W.BASSA, [["Spearmen", 20]])
	GameCommands.merge_armies(s, W.A, a.id, b.id)
	t.assert_eq(b.stacks.size(), 2, "regola spenta: come prima")


func test_dopo_la_battaglia_le_pile_uguali_si_accorpano(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.rules.combat.valour_chance = 0.0
	var full := _full(s, "Spearmen")
	var spears := []
	for i in 6:
		spears.append(["Spearmen", full])
	var attackers := _army(s, "FN_ALPHA", "ID_MEZZA", spears)
	var defenders := _army(s, "FN_BETA", "ID_MEZZA", [["Nizari", 30]])
	var men_before := attackers.men_total()
	var list_a: Array[Army] = [attackers]
	var list_d: Array[Army] = [defenders]
	var r := Combat.resolve(s, "ID_MEZZA", list_a, list_d, BattleResult.KIND_FIELD, 1.0)
	t.assert_true(r.attacker_won)
	var lost := men_before - attackers.men_total()
	t.assert_true(lost > 0, "il vincitore ha perso uomini")
	t.assert_eq(attackers.stacks.size(), ceili(float(attackers.men_total()) / float(full)), "pile accorpate: al piu' una non piena")
	var not_full := 0
	for st in attackers.stacks:
		if st.men < full:
			not_full += 1
	t.assert_true(not_full <= 1)


# --- ADR-147: carta trascinata su un'altra carta della stessa armata ------------------------------------------------


func test_carta_su_carta_uguale_la_riempie(t: TestContext) -> void:
	var s := _world()
	var full := _full(s, "Spearmen")
	var a := _army(s, W.A, W.BASSA, [["Spearmen", full - 30, 2], ["Archers", 20], ["Spearmen", 50, 0]])
	var r := GameCommands.fill_stack(s, W.A, a.id, PackedInt32Array([2]), 0)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_eq(int(r["uomini"]), 30)
	t.assert_true(bool(r["piena"]))
	t.assert_eq(_men(a), [["Spearmen", full], ["Archers", 20], ["Spearmen", 20]], "l'eccedenza resta nella carta trascinata")
	t.assert_eq(a.stacks[0].value, roundi(float(2 * (full - 30)) / float(full)), "valore medio")
	var r2 := GameCommands.fill_stack(s, W.A, a.id, PackedInt32Array([0]), 2)
	t.assert_true(bool(r2["ok"]))
	t.assert_eq(int(r2["pile_tolte"]), 0)
	t.assert_eq(a.stacks[2].men, full, "anche al contrario: la destinazione si riempie")


func test_carta_che_si_svuota_sparisce(t: TestContext) -> void:
	var s := _world()
	var full := _full(s, "Spearmen")
	var a := _army(s, W.A, W.BASSA, [["Spearmen", 10], ["Spearmen", 15], ["Spearmen", full - 20]])
	var r := GameCommands.fill_stack(s, W.A, a.id, PackedInt32Array([0, 1]), 2)
	t.assert_true(bool(r["ok"]))
	t.assert_eq(int(r["pile_tolte"]), 1, "la prima cede tutti i suoi 10 uomini")
	t.assert_eq(int(r["pila"]), 1, "nuovo indice della pila riempita")
	t.assert_eq(_men(a), [["Spearmen", 5], ["Spearmen", full]])


func test_carta_su_carta_diversa_o_piena(t: TestContext) -> void:
	var s := _world()
	var full := _full(s, "Spearmen")
	var a := _army(s, W.A, W.BASSA, [["Spearmen", 40], ["Archers", 20], ["Spearmen", full]])
	t.assert_false(bool(GameCommands.fill_stack(s, W.A, a.id, PackedInt32Array([1]), 0)["ok"]), "tipo diverso")
	t.assert_false(bool(GameCommands.fill_stack(s, W.A, a.id, PackedInt32Array([0]), 2)["ok"]), "gia' piena")
	t.assert_false(bool(GameCommands.fill_stack(s, W.A, a.id, PackedInt32Array([0]), 0)["ok"]), "su se stessa")
	t.assert_false(bool(GameCommands.fill_stack(s, W.B, a.id, PackedInt32Array([2]), 0)["ok"]), "esercito altrui")
	a.stacks[2].men = 30
	a.stacks[2].mercenary = true
	t.assert_false(bool(GameCommands.fill_stack(s, W.A, a.id, PackedInt32Array([2]), 0)["ok"]), "mercenari a parte")
	t.assert_eq(_men(a), [["Spearmen", 40], ["Archers", 20], ["Spearmen", 30]], "nessuna modifica dopo i rifiuti")
