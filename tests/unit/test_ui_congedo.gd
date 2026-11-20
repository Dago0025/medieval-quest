extends RefCounted
## Testi dell'interfaccia del congedo (CampaignUiDismiss, ADR-031): pulsante, conferma ed esito. Mondo: agent_world.gd.

const W := preload("res://tests/unit/agent_world.gd")


func _three(s: GameState, fleet: bool = false) -> Army:
	var a := s.create_army(W.A, W.NORD if fleet else W.BASSA, fleet)
	for men in [30, 40, 50]:
		a.stacks.append(UnitStack.new("Spearmen", men, 0))
	return a


func test_il_pulsante_c_e_solo_per_i_propri_eserciti_non_crociati(t: TestContext) -> void:
	var s := W.world()
	var a := _three(s)
	t.assert_true(CampaignUiDismiss.allowed(s, W.A, a))
	t.assert_false(CampaignUiDismiss.allowed(s, W.B, a), "esercito altrui")
	t.assert_false(CampaignUiDismiss.allowed(s, W.A, null))
	a.crusade = {"tipo": Army.CRUSADE_KIND, "zelo": 80, "bersaglio": ""}
	t.assert_false(CampaignUiDismiss.allowed(s, W.A, a), "crociata")


func test_senza_unita_scelte_il_pulsante_e_spento_e_dice_cosa_fare(t: TestContext) -> void:
	var s := W.world()
	var a := _three(s)
	var b := CampaignUiDismiss.button_state(s, W.A, a, PackedInt32Array())
	t.assert_true(bool(b["visibile"]))
	t.assert_false(bool(b["attivo"]))
	t.assert_eq(str(b["testo"]), "Congeda")
	t.assert_true(str(b["suggerimento"]).contains("Scegli"), str(b["suggerimento"]))


func test_con_unita_scelte_dice_quante_e_quanto_si_risparmia(t: TestContext) -> void:
	var s := W.world()
	var a := _three(s)
	var b := CampaignUiDismiss.button_state(s, W.A, a, PackedInt32Array([0, 2]))
	t.assert_true(bool(b["attivo"]))
	t.assert_eq(str(b["testo"]), "Congeda (2)")
	var saved := CampaignUiDismiss.upkeep_saved(s, a, PackedInt32Array([0, 2]))
	t.assert_true(saved > 0, "mantenimento risparmiato: %d" % saved)
	var before := Economy.faction_upkeep(s, W.A)
	var r := GameCommands.disband_stacks(s, W.A, a.id, PackedInt32Array([0, 2]))
	t.assert_eq(saved, before - Economy.faction_upkeep(s, W.A), "la stima coincide con l'esito del comando")
	t.assert_eq(int(r["mantenimento"]), saved)


func test_la_conferma_nomina_unita_uomini_e_avverte_che_non_si_torna_indietro(t: TestContext) -> void:
	var s := W.world()
	var a := _three(s)
	var text := CampaignUiDismiss.confirm_text(s, W.A, a, PackedInt32Array([0, 2]))
	t.assert_true(text.contains("2 unità"), text)
	t.assert_true(text.contains("80 uomini"), text)
	t.assert_true(text.contains("rimborso"), text)
	var one := CampaignUiDismiss.confirm_text(s, W.A, a, PackedInt32Array([1]))
	t.assert_true(one.contains("1 unità") and one.contains("40 uomini"), one)
	var all := CampaignUiDismiss.confirm_text(s, W.A, a, PackedInt32Array([0, 1, 2]))
	t.assert_true(all.contains("intero"), "avverte che l'esercito sparisce: " + all)


func test_per_le_flotte_parla_di_navi(t: TestContext) -> void:
	var s := W.world()
	var f := _three(s, true)
	var text := CampaignUiDismiss.confirm_text(s, W.A, f, PackedInt32Array([0]))
	t.assert_true(text.contains("1 nave"), text)
	t.assert_true(CampaignUiDismiss.confirm_text(s, W.A, f, PackedInt32Array([0, 1])).contains("2 navi"))
	t.assert_true(CampaignUiDismiss.confirm_text(s, W.A, f, PackedInt32Array([0, 1, 2])).contains("intera"))


func test_il_comandante_reale_e_nominato_nella_conferma(t: TestContext) -> void:
	var s := W.world()
	var a := W.land_army(s, W.A, W.ALTA)
	var c := s.commander_of(a.id)
	if c == null:
		t.skip("nessun comandante in questo mondo")
		return
	var all := PackedInt32Array()
	for i in a.stacks.size():
		all.append(i)
	var text := CampaignUiDismiss.confirm_text(s, W.A, a, all)
	t.assert_true(text.contains(c.full_name()), text)


func test_il_messaggio_dopo_il_congedo(t: TestContext) -> void:
	var done := CampaignUiDismiss.done_text({"ok": true, "pile": 2, "uomini": 80, "mantenimento": 6, "rimosso": false}, false)
	t.assert_true(done.contains("2 unità") and done.contains("80 uomini") and done.contains("6"), done)
	var ships := CampaignUiDismiss.done_text({"ok": true, "pile": 1, "uomini": 1, "mantenimento": 0, "rimosso": true}, true)
	t.assert_true(ships.contains("1 nave"), ships)
	var refund := CampaignUiDismiss.done_text({"ok": true, "pile": 1, "uomini": 30, "mantenimento": 3, "rimosso": false,
		"rimborso_riaddestramento": 50, "pile_riaddestramento": 1}, false)
	t.assert_true(refund.contains("50"), refund)


func test_la_conferma_avverte_che_i_congedati_diventano_mercenari(t: TestContext) -> void:
	var s := W.world()
	var a := _three(s)
	var text := CampaignUiDismiss.confirm_text(s, W.A, a, PackedInt32Array([0]))
	t.assert_true(text.contains("mercenari"), text)
	var f := _three(s, true)
	t.assert_false(CampaignUiDismiss.confirm_text(s, W.A, f, PackedInt32Array([0])).contains("mercenari"), "le navi no")
	s.rules.mercenaries.disbanded_join = false
	t.assert_false(CampaignUiDismiss.confirm_text(s, W.A, a, PackedInt32Array([0])).contains("mercenari"), "regola spenta")


func test_il_messaggio_dice_quante_compagnie_di_mercenari_sono_nate(t: TestContext) -> void:
	var done := CampaignUiDismiss.done_text({"ok": true, "pile": 2, "uomini": 80, "mantenimento": 6, "rimosso": false, "mercenari": 2}, false)
	t.assert_true(done.contains("mercenari"), done)
	var none := CampaignUiDismiss.done_text({"ok": true, "pile": 1, "uomini": 1, "mantenimento": 0, "rimosso": true, "mercenari": 0}, true)
	t.assert_false(none.contains("mercenari"), none)
