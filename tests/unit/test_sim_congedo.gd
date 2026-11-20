extends RefCounted
## Congedare le unita' (GameCommands.disband_stacks, richiesta di Federico dell'11/11/2026): le pile scelte spariscono
## senza rimborso e smettono di costare mantenimento. Mondo di prova: agent_world.gd (in sola lettura).

const W := preload("res://tests/unit/agent_world.gd")


func _world() -> GameState:
	var s := W.world()
	s.faction(W.A).treasury = 10000
	return s


## Esercito di ALPHA in BASSA con tre pile distinguibili dagli uomini (30, 40, 50).
func _three(s: GameState, fleet: bool = false) -> Army:
	var a := s.create_army(W.A, W.NORD if fleet else W.BASSA, fleet)
	for men in [30, 40, 50]:
		a.stacks.append(UnitStack.new("Spearmen", men, 0))
	return a


func _men(a: Army) -> Array:
	var out := []
	for st in a.stacks:
		out.append(st.men)
	return out


func test_congedare_toglie_le_pile_scelte_senza_rimborso(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	var before := s.faction(W.A).treasury
	var r := GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([0, 2]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(_men(a), [40], "resta la pila non scelta")
	t.assert_eq(int(r["pile"]), 2)
	t.assert_eq(int(r["uomini"]), 80)
	t.assert_false(bool(r["rimosso"]), "l'esercito resta")
	t.assert_eq(s.faction(W.A).treasury, before, "nessun rimborso")
	t.assert_true(s.army(a.id) != null)


func test_congedare_riduce_il_mantenimento(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	var before := Economy.faction_upkeep(s, W.A)
	var r := GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([1]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var after := Economy.faction_upkeep(s, W.A)
	t.assert_true(after < before, "il mantenimento cala (%d -> %d)" % [before, after])
	t.assert_eq(int(r["mantenimento"]), before - after, "l'esito dice quanto si risparmia l'anno")


func test_congedare_tutte_le_pile_toglie_l_esercito_e_libera_il_comandante(t: TestContext) -> void:
	var s := _world()
	var a := W.land_army(s, W.A, W.BASSA)
	var general := s.commander_of(a.id)
	if general == null:
		general = s.leader_of(W.A)
		general.army = a.id
	var all := PackedInt32Array()
	for i in a.stacks.size():
		all.append(i)
	var r := GameCommands.disband_stacks(s, W.A, a.id, all)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_true(bool(r["rimosso"]))
	t.assert_true(s.army(a.id) == null, "l'esercito non c'e' piu'")
	t.assert_eq(general.army, 0, "il comandante resta senza esercito")
	t.assert_true(general.alive, "ed e' vivo")


func test_non_si_congeda_con_indici_sbagliati_ne_l_esercito_altrui(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	t.assert_false(bool(GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([]))["ok"]), "nessuna pila")
	t.assert_false(bool(GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([3]))["ok"]), "indice fuori")
	t.assert_false(bool(GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([1, 1]))["ok"]), "indice doppio")
	t.assert_false(bool(GameCommands.disband_stacks(s, W.B, a.id, PackedInt32Array([0]))["ok"]), "esercito di un altro")
	t.assert_false(bool(GameCommands.disband_stacks(s, W.A, 9999, PackedInt32Array([0]))["ok"]), "esercito inesistente")
	t.assert_eq(_men(a), [30, 40, 50], "nulla e' cambiato")


func test_un_esercito_crociato_non_si_congeda(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	a.crusade = {"tipo": Army.CRUSADE_KIND, "zelo": 80, "bersaglio": ""}
	var r := GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_false(bool(r["ok"]))
	t.assert_eq(a.stacks.size(), 3)


func test_si_congedano_anche_navi_mercenari_e_truppe_nel_castello(t: TestContext) -> void:
	var s := _world()
	var fleet := _three(s, true)
	t.assert_true(bool(GameCommands.disband_stacks(s, W.A, fleet.id, PackedInt32Array([0]))["ok"]), "navi")
	var a := _three(s)
	a.in_castle = true
	a.stacks[1].mercenary = true
	var r := GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([1]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(_men(a), [30, 50])
	t.assert_true(a.in_castle, "chi resta non esce dal castello")


func test_congedare_rimborsa_il_riaddestramento_in_corso(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	var ordered := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	if not bool(ordered["ok"]):
		t.skip("riaddestramento non ordinabile in questo mondo: %s" % str(ordered["errore"]))
		return
	var paid := int(ordered["costo"])
	var before := s.faction(W.A).treasury
	var r := GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([2]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(int(r["rimborso_riaddestramento"]), paid, "gli indici cambiano: l'ordine e' rimborsato")
	t.assert_eq(s.faction(W.A).treasury, before + paid)
	t.assert_true(RetrainProcessor.orders_of(s, a.id).is_empty())


func test_chi_doveva_unirsi_all_esercito_congedato_arriva_lo_stesso(t: TestContext) -> void:
	var s := _world()
	var target := _three(s)
	var mover := s.create_army(W.A, W.ALTA, false)
	mover.stacks.append(UnitStack.new("Spearmen", 20, 0))
	var order := GameCommands.order_merge(s, W.A, mover.id, target.id)
	t.assert_true(bool(order["ok"]), str(order["errore"]))
	t.assert_true(bool(GameCommands.disband_stacks(s, W.A, target.id, PackedInt32Array([0, 1, 2]))["ok"]))
	var report := TurnProcessor.end_year(s)
	t.assert_true(bool(report["ok"]), str(report.get("errori", [])))
	t.assert_true(s.army(mover.id) != null, "l'esercito in marcia esiste ancora")
	t.assert_eq(s.army(mover.id).region, W.BASSA, "ed e' arrivato")


func test_l_anno_dopo_il_mantenimento_pagato_e_minore(t: TestContext) -> void:
	var s := _world()
	var twin := _world()   # stesso seme: stessa partita, senza il congedo
	var a := _three(s)
	_three(twin)
	t.assert_true(bool(GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([0, 1, 2]))["ok"]))
	TurnProcessor.end_year(s)
	TurnProcessor.end_year(twin)
	t.assert_true(int(s.faction(W.A).last_income["mantenimento"]) < int(twin.faction(W.A).last_income["mantenimento"]),
		"mantenimento %s contro %s" % [str(s.faction(W.A).last_income["mantenimento"]), str(twin.faction(W.A).last_income["mantenimento"])])


# --- i congedati diventano mercenari (manuale p26 e p70) ---------------------------------------------------------------


func _pool(s: GameState, province_id: String) -> Array:
	return s.mercenaries.get(province_id, [])


func test_le_truppe_congedate_diventano_mercenari_nella_provincia(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	a.stacks[2].value = 4
	var before := _pool(s, W.BASSA).size()
	var r := GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([0, 2]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(int(r["mercenari"]), 2, "l'esito dice quante compagnie sono nate")
	var list := _pool(s, W.BASSA)
	t.assert_eq(list.size(), before + 2)
	var first: Dictionary = list[list.size() - 2]
	var second: Dictionary = list[list.size() - 1]
	t.assert_eq(str(first["unita"]), "Spearmen")
	t.assert_eq(int(first["uomini"]), 30, "con gli uomini che aveva")
	t.assert_eq(int(first["anni"]), 0, "compagnia nuova")
	t.assert_eq(int(second["uomini"]), 50)
	t.assert_eq(int(second["valore"]), 4, "e il valore che aveva")


func test_le_navi_congedate_non_diventano_mercenari(t: TestContext) -> void:
	var s := _world()
	var fleet := _three(s, true)
	var r := GameCommands.disband_stacks(s, W.A, fleet.id, PackedInt32Array([0, 1]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(int(r["mercenari"]), 0)
	t.assert_true(_pool(s, W.NORD).is_empty(), "in mare non ci sono compagnie di mercenari")


func test_con_la_regola_spenta_i_congedati_spariscono(t: TestContext) -> void:
	var s := _world()
	s.rules.mercenaries.disbanded_join = false
	var a := _three(s)
	var before := _pool(s, W.BASSA).size()
	var r := GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(int(r["mercenari"]), 0)
	t.assert_eq(_pool(s, W.BASSA).size(), before)


func test_i_congedati_si_possono_riassoldare_come_mercenari(t: TestContext) -> void:
	var s := _world()
	var a := _three(s)
	t.assert_true(bool(GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([1]))["ok"]))
	var owner := s.province(W.BASSA).owner
	s.faction(owner).treasury = 10000
	var index := _pool(s, W.BASSA).size() - 1
	var hired := GameCommands.hire_mercenary(s, owner, W.BASSA, index)
	t.assert_true(bool(hired["ok"]), str(hired["errore"]))
	var army := s.army(int(hired["esercito"]))
	var st := army.stacks[army.stacks.size() - 1]
	t.assert_eq(st.men, 40, "gli stessi uomini")
	t.assert_true(st.mercenary, "ora al soldo come mercenari")


func test_i_congedati_non_cambiano_i_sorteggi_dell_anno(t: TestContext) -> void:
	var s := _world()
	var twin := _world()
	var a := _three(s)
	var b := _three(twin)
	twin.rules.mercenaries.disbanded_join = false
	GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([0]))
	GameCommands.disband_stacks(twin, W.A, b.id, PackedInt32Array([0]))
	t.assert_eq(s.rng.state, twin.rng.state, "il congedo non consuma numeri casuali")
