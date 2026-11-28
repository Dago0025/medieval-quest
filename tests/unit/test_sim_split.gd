extends RefCounted
## Test dei comandi per dividere e unire gli eserciti (GameCommands.split_army, transfer_stacks, merge_armies).

const W := preload("res://tests/unit/agent_world.gd")


func _world() -> GameState:
	var s := W.world()
	s.rules.merge_same_units = false   # pile distinguibili dagli uomini; l'accorpamento (ADR-146) e' in test_accorpamento
	for c in s.characters:
		c.old_age = 500
	return s


## Esercito di ALPHA in BASSA con tre pile distinguibili dagli uomini (30, 40, 50).
func _three(s: GameState) -> Army:
	var a := s.create_army(W.A, W.BASSA, false)
	for men in [30, 40, 50]:
		a.stacks.append(UnitStack.new("Spearmen", men, 0))
	return a


func _men(a: Army) -> Array:
	var out := []
	for st in a.stacks:
		out.append(st.men)
	return out


func test_dividere_crea_un_esercito_nuovo_nella_stessa_regione(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	var r := GameCommands.split_army(s, W.A, a.id, PackedInt32Array([0, 2]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var fresh := s.army(int(r["esercito"]))
	t.assert_true(fresh != null)
	t.assert_eq(fresh.region, W.BASSA)
	t.assert_eq(fresh.faction, W.A)
	t.assert_eq(_men(fresh), [30, 50], "le pile scelte, nell'ordine dell'esercito")
	t.assert_eq(_men(a), [40], "resta la pila non scelta")
	t.assert_true(fresh.path.is_empty(), "l'esercito nuovo e' fermo")
	t.assert_true(s.commander_of(fresh.id) == null, "senza comandante fino a fine anno")


func test_dividere_conserva_gli_uomini_e_il_castello(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	a.in_castle = true
	var before := a.men_total()
	var r := GameCommands.split_army(s, W.A, a.id, PackedInt32Array([1]))
	var fresh := s.army(int(r["esercito"]))
	t.assert_eq(a.men_total() + fresh.men_total(), before)
	t.assert_true(fresh.in_castle, "nel castello come l'esercito di partenza")


func test_non_si_divide_tutto_ne_con_indici_sbagliati(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	t.assert_false(bool(GameCommands.split_army(s, W.A, a.id, PackedInt32Array([0, 1, 2]))["ok"]), "deve restare una pila")
	t.assert_false(bool(GameCommands.split_army(s, W.A, a.id, PackedInt32Array([]))["ok"]), "nessuna pila")
	t.assert_false(bool(GameCommands.split_army(s, W.A, a.id, PackedInt32Array([3]))["ok"]), "indice fuori")
	t.assert_false(bool(GameCommands.split_army(s, W.A, a.id, PackedInt32Array([1, 1]))["ok"]), "doppione")
	t.assert_false(bool(GameCommands.split_army(s, W.B, a.id, PackedInt32Array([0]))["ok"]), "esercito altrui")
	t.assert_eq(a.stacks.size(), 3, "nessuna modifica dopo un rifiuto")


func test_spostare_pile_tra_due_eserciti(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	var b := s.create_army(W.A, W.BASSA, false)
	b.stacks.append(UnitStack.new("Spearmen", 10, 0))
	var r := GameCommands.transfer_stacks(s, W.A, a.id, b.id, PackedInt32Array([2]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_false(bool(r["rimosso"]))
	t.assert_eq(_men(a), [30, 40])
	t.assert_eq(_men(b), [10, 50])


func test_unire_toglie_l_esercito_di_partenza_e_libera_il_comandante(t: TestContext) -> void:
	var s := _world()
	var a := W.general_army(s, W.A, W.BASSA, 60, "Spearmen")
	var general := s.commander_of(a.id)
	var b := _three(s)
	var r := GameCommands.merge_armies(s, W.A, a.id, b.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_true(bool(r["rimosso"]))
	t.assert_true(s.army(a.id) == null, "l'esercito unito sparisce")
	t.assert_eq(b.stacks.size(), 4)
	if general != null:
		t.assert_eq(general.army, 0, "il comandante resta senza esercito")


func test_limiti_dell_unione(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	var elsewhere := s.create_army(W.A, W.ALTA, false)
	elsewhere.stacks.append(UnitStack.new("Spearmen", 10, 0))
	t.assert_false(bool(GameCommands.merge_armies(s, W.A, a.id, elsewhere.id)["ok"]), "regioni diverse")
	var inside := s.create_army(W.A, W.BASSA, false)
	inside.stacks.append(UnitStack.new("Spearmen", 10, 0))
	inside.in_castle = true
	t.assert_false(bool(GameCommands.merge_armies(s, W.A, a.id, inside.id)["ok"]), "castello e campo")
	var foreign := s.create_army(W.B, W.BASSA, false)
	foreign.stacks.append(UnitStack.new("Spearmen", 10, 0))
	t.assert_false(bool(GameCommands.merge_armies(s, W.A, a.id, foreign.id)["ok"]), "fazioni diverse")
	t.assert_false(bool(GameCommands.merge_armies(s, W.A, a.id, a.id)["ok"]), "lo stesso esercito")
	var full := s.create_army(W.A, W.BASSA, false)
	for i in s.rules.max_stacks - 1:
		full.stacks.append(UnitStack.new("Spearmen", 10, 0))
	t.assert_false(bool(GameCommands.merge_armies(s, W.A, a.id, full.id)["ok"]), "oltre il massimo di pile")
	t.assert_true(bool(GameCommands.transfer_stacks(s, W.A, a.id, full.id, PackedInt32Array([0]))["ok"]), "una pila ci sta")


func test_gli_eserciti_crociati_non_si_dividono(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	a.crusade = {"tipo": "crociata", "zelo": 80, "bersaglio": ""}
	t.assert_false(bool(GameCommands.split_army(s, W.A, a.id, PackedInt32Array([0]))["ok"]))


func test_compagni_per_l_unione(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	var b := s.create_army(W.A, W.BASSA, false)
	b.stacks.append(UnitStack.new("Spearmen", 10, 0))
	var partners := GameCommands.merge_partners(s, W.A, a.id)
	var ids := []
	for p in partners:
		ids.append(p.id)
	t.assert_true(ids.has(b.id), "l'altro esercito di ALPHA in BASSA")
	t.assert_false(ids.has(a.id), "non se stesso")


func test_dopo_la_divisione_il_fine_anno_da_un_comandante(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	var r := GameCommands.split_army(s, W.A, a.id, PackedInt32Array([0]))
	var fresh_id := int(r["esercito"])
	TurnProcessor.end_year(s)
	var fresh := s.army(fresh_id)
	if fresh != null and not fresh.stacks.is_empty():
		t.assert_true(s.commander_of(fresh_id) != null, "a fine anno l'esercito nuovo ha un comandante")


## Richiesta di Federico del 28/11/2026: lo stendardo dell'armata si riempie con gli uomini (20 pile da 100 = 2000), non con
## il numero di unita'; le flotte contano le navi.
func test_stendardo_pieno_a_duemila_uomini(t: TestContext) -> void:
	var a := Army.new(1, "FN_FRENCH", "ID_ILE_DE_FRANCE")
	for i in 20:
		a.stacks.append(UnitStack.new("Spearmen", 50, 0))
	t.assert_eq(a.banner_fill(20), 0.5, "20 unita' da 50 uomini: mezzo stendardo")
	a.stacks.clear()
	for i in 10:
		a.stacks.append(UnitStack.new("Spearmen", 200, 0))
	t.assert_eq(a.banner_fill(20), 1.0, "2000 uomini in 10 unita': stendardo pieno")
	a.stacks.append(UnitStack.new("Spearmen", 100, 0))
	t.assert_eq(a.banner_fill(20), 1.0, "oltre 2000 resta pieno")
	var f := Army.new(2, "FN_FRENCH", "ID_ENGLISH_CHANNEL", true)
	for i in 5:
		f.stacks.append(UnitStack.new("Cog", 1, 0))
	t.assert_eq(f.banner_fill(20), 0.25, "flotta: navi su 20")
