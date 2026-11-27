extends RefCounted
## Interfaccia del riaddestramento: logica pura in CampaignUiRetrain (src/map), testi dei due eventi nel resoconto di fine anno
## e messaggi d'esito. I pulsanti veri stanno in scenes/campaign_map.gd e non si provano qui. Mondo di prova: agent_world.gd
## (ALPHA con 10000 denari; Spearmen 100 uomini e 100 denari, Nizari solo di BETA).

const W := preload("res://tests/unit/agent_world.gd")


func _world() -> GameState:
	var s := W.world()
	s.faction(W.A).treasury = 10000
	return s


func _army(s: GameState, region: String, stacks: Array) -> Army:
	var a := s.create_army(W.A, region, false)
	for entry in stacks:
		var row: Array = entry
		a.stacks.append(UnitStack.new(str(row[0]), int(row[1]), int(row[2])))
	return a


func _ev(kind: String, data: Dictionary) -> Dictionary:
	var e := {"tipo": kind, "anno": 1000}
	e.merge(data)
	return e


# --- caselle delle pile ----------------------------------------------------------------------------------------------


func test_testo_delle_caselle(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 55, 3]])
	var name_text := CampaignUiText.unit_name("Spearmen")
	t.assert_eq(CampaignUiRetrain.stack_label(s, a, 0), "%s · 40 uomini" % name_text, "come prima, senza ordine")
	t.assert_eq(CampaignUiRetrain.stack_label(s, a, 1), "%s · 55 uomini · valore 3" % name_text)
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([1]))
	t.assert_eq(CampaignUiRetrain.stack_label(s, a, 0), "%s · 40 uomini" % name_text, "la pila senza ordine non cambia")
	t.assert_eq(CampaignUiRetrain.stack_label(s, a, 1), "%s · 55 uomini · valore 3 (in riaddestramento)" % name_text)
	t.assert_eq(CampaignUiRetrain.IN_PROGRESS, "(in riaddestramento)")


# --- pulsanti ----------------------------------------------------------------------------------------------------


func test_nessun_controllo_se_non_c_e_niente_da_riaddestrare(t: TestContext) -> void:
	var s := _world()
	var full := _army(s, W.BASSA, [["Spearmen", 100, 0]])
	t.assert_false(CampaignUiRetrain.has_controls(s, W.A, full), "pila piena")
	var info := CampaignUiRetrain.panel_state(s, W.A, full, PackedInt32Array([0]))
	t.assert_false(bool(info["visibile"]))
	t.assert_false(bool(info["annulla_visibile"]))
	var foreign := _army(s, W.BASSA, [["Nizari", 10, 0]])
	t.assert_false(CampaignUiRetrain.has_controls(s, W.A, foreign), "Nizari non e' reclutabile da ALPHA")
	t.assert_false(CampaignUiRetrain.has_controls(s, W.A, null), "nessun esercito")
	t.assert_false(CampaignUiRetrain.has_controls(s, W.B, full), "non e' un esercito di BETA")
	var other := CampaignUiRetrain.panel_state(s, W.B, full, PackedInt32Array())
	t.assert_true(str(other["tooltip"]) != "", "il motivo sta nel tooltip")


func test_un_esercito_di_una_pila_decimata_mostra_i_controlli(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	t.assert_true(CampaignUiRetrain.has_controls(s, W.A, a))


func test_costo_totale_nel_testo_e_nel_tooltip(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 100, 0], ["Spearmen", 70, 0]])
	var none := CampaignUiRetrain.panel_state(s, W.A, a, PackedInt32Array())
	t.assert_true(bool(none["visibile"]))
	t.assert_eq(str(none["testo"]), "Riaddestra le pile scelte", "senza caselle spuntate niente costo")
	t.assert_eq(int(none["costo"]), 0)
	t.assert_true(str(none["tooltip"]).contains("Spunta"), str(none["tooltip"]))
	var one := CampaignUiRetrain.panel_state(s, W.A, a, PackedInt32Array([0]))
	t.assert_eq(int(one["costo"]), 60)
	t.assert_eq(int(one["pile"]), 1)
	t.assert_eq(str(one["testo"]), "Riaddestra le pile scelte (60 denari)")
	t.assert_true(str(one["tooltip"]).contains("Costo totale: 60 denari per 1 pile."), str(one["tooltip"]))
	var two := CampaignUiRetrain.panel_state(s, W.A, a, PackedInt32Array([2, 0]))
	t.assert_eq(int(two["costo"]), 60 + 30, "in qualsiasi ordine di spunta")
	t.assert_eq(str(two["testo"]), "Riaddestra le pile scelte (90 denari)")
	# una pila piena spuntata non costa e il tooltip dice perche'
	var with_full := CampaignUiRetrain.panel_state(s, W.A, a, PackedInt32Array([0, 1]))
	t.assert_eq(int(with_full["costo"]), 60)
	t.assert_true(str(with_full["tooltip"]).contains("completo"), str(with_full["tooltip"]))
	# solo una pila piena: nessun costo
	var only_full := CampaignUiRetrain.panel_state(s, W.A, a, PackedInt32Array([1]))
	t.assert_eq(int(only_full["costo"]), 0)
	t.assert_eq(str(only_full["testo"]), "Riaddestra le pile scelte")


func test_tesoro_insufficiente_nel_tooltip(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 10, 0]])
	s.faction(W.A).treasury = 50
	var info := CampaignUiRetrain.panel_state(s, W.A, a, PackedInt32Array([0]))
	t.assert_eq(int(info["costo"]), 90)
	t.assert_true(str(info["tooltip"]).contains("Tesoro insufficiente"), str(info["tooltip"]))


func test_il_limite_per_provincia_nel_conto(t: TestContext) -> void:
	var s := _world()
	var rows: Array = []
	for i in 6:
		rows.append(["Spearmen", 50, 0])
	var a := _army(s, W.BASSA, rows)
	var info := CampaignUiRetrain.panel_state(s, W.A, a, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	t.assert_eq(int(info["pile"]), 4, "solo 4 pile per provincia")
	t.assert_eq(int(info["costo"]), 4 * 50)
	t.assert_true(str(info["tooltip"]).contains("limite"), str(info["tooltip"]))
	# il conto del pannello coincide con quello che il comando accetta
	var r := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	t.assert_eq(int(r["pile"]), int(info["pile"]))
	t.assert_eq(int(r["costo"]), int(info["costo"]))


func test_annulla_compare_solo_con_ordini(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 80, 0]])
	t.assert_false(bool(CampaignUiRetrain.panel_state(s, W.A, a, PackedInt32Array())["annulla_visibile"]))
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
	var info := CampaignUiRetrain.panel_state(s, W.A, a, PackedInt32Array([0]))
	t.assert_true(bool(info["annulla_visibile"]))
	t.assert_eq(str(info["annulla_testo"]), "Annulla riaddestramento (rimborso 80)", "60 + 20")
	t.assert_true(bool(info["visibile"]), "i controlli restano per poter annullare")
	t.assert_eq(int(info["costo"]), 0, "le pile gia' ordinate non si pagano due volte")
	t.assert_true(str(info["tooltip"]).contains("già in riaddestramento"), str(info["tooltip"]))
	GameCommands.cancel_retrain(s, W.A, a.id)
	t.assert_false(bool(CampaignUiRetrain.panel_state(s, W.A, a, PackedInt32Array())["annulla_visibile"]))


func test_un_esercito_in_marcia_non_ha_i_controlli(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	a.path = PackedStringArray([W.ALTA])
	t.assert_false(CampaignUiRetrain.has_controls(s, W.A, a))


# --- messaggi d'esito -------------------------------------------------------------------------------------------------


func test_messaggi_dei_comandi(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 100, 0]])
	var ordered := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
	t.assert_eq(CampaignUiRetrain.ordered_text(s, ordered),
		"Riaddestramento ordinato: 1 pile, 60 denari (a fine anno tornano all'organico pieno). Saltate 1 pile (La pila e' gia' al completo).")
	var refused := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_eq(CampaignUiRetrain.ordered_text(s, refused), "La pila e' gia' in riaddestramento", "il motivo del rifiuto")
	var cancelled := GameCommands.cancel_retrain(s, W.A, a.id)
	t.assert_eq(CampaignUiRetrain.cancelled_text(s, cancelled), "Riaddestramento annullato: 60 denari rimborsati per 1 pile.")
	var nothing := GameCommands.cancel_retrain(s, W.A, a.id)
	t.assert_eq(CampaignUiRetrain.cancelled_text(s, nothing), "Nessun riaddestramento da annullare per l'esercito %d" % a.id)
	# nota dopo un movimento o una divisione che annulla gli ordini
	var b := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	GameCommands.order_retrain(s, W.A, b.id, PackedInt32Array([0]))
	var moved := GameCommands.order_move(s, W.A, b.id, PackedStringArray([W.ALTA]))
	t.assert_eq(CampaignUiRetrain.refund_note(moved), "Riaddestramento annullato: 60 denari rimborsati.")
	t.assert_eq(CampaignUiRetrain.refund_note({"ok": true, "errore": ""}), "", "nessuna nota senza ordini annullati")


# --- eventi nel resoconto ----------------------------------------------------------------------------------------------


func test_testi_dei_due_eventi(t: TestContext) -> void:
	var s := _world()
	var place := CampaignUiText.region_name(s, W.BASSA)
	var done := _ev(GameState.EV_RETRAINED, {"fazione": W.A, "provincia": W.BASSA, "regione": W.BASSA, "esercito": 7, "pile": 2, "uomini": 90, "costo": 90, "unita": ["Spearmen", "Spearmen"]})
	t.assert_eq(CampaignUiText.format_event(s, done),
		"Riaddestramento a %s (esercito 7): 2 pile tornano all'organico pieno, +90 uomini (90 denari)." % place)
	var reasons := {
		"esercito_perso": "l'esercito non c'è più",
		"esercito_mosso": "l'esercito si è mosso",
		"provincia_persa": "la provincia non è più vostra",
		"pila_cambiata": "la pila è cambiata (perdite o spostamenti)",
	}
	for key in reasons:
		var cancelled := _ev(GameState.EV_RETRAIN_CANCELLED, {"fazione": W.A, "provincia": W.BASSA, "esercito": 7, "pile": 1, "rimborso": 60, "motivo": key})
		t.assert_eq(CampaignUiText.format_event(s, cancelled),
			"Riaddestramento annullato a %s (esercito 7): 1 pile, 60 denari rimborsati (%s)." % [place, reasons[key]], key)
	var no_reason := _ev(GameState.EV_RETRAIN_CANCELLED, {"fazione": W.A, "provincia": W.BASSA, "esercito": 7, "pile": 1, "rimborso": 60})
	t.assert_eq(CampaignUiText.format_event(s, no_reason), "Riaddestramento annullato a %s (esercito 7): 1 pile, 60 denari rimborsati." % place)
	# senza luogo si ripiega sul testo della simulazione, poi sul tipo
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_RETRAINED, {"testo": "Testo della simulazione."})), "Testo della simulazione.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_RETRAINED, {})), GameState.EV_RETRAINED)
	# gli altri tipi non sono suoi
	t.assert_eq(CampaignUiRetrain.format_event(s, GameState.EV_RECRUITED, {}), "")


func test_il_resoconto_di_fine_anno_riporta_i_due_eventi(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	var b := _army(s, W.ALTA, [["Spearmen", 30, 0]])
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	GameCommands.order_retrain(s, W.A, b.id, PackedInt32Array([0]))
	b.stacks[0].men = 20                      # perdite dopo l'ordine: l'ordine non si applica piu'
	var result := TurnProcessor.end_year(s)
	t.assert_true(bool(result["ok"]), str(result["errori"]))
	var lines := CampaignUiText.year_report(s, W.A, result)
	var done_lines := 0
	var cancelled_lines := 0
	for line in lines:
		if line.contains("tornano all'organico pieno"):
			done_lines += 1
		if line.contains("Riaddestramento annullato") and line.contains("la pila è cambiata"):
			cancelled_lines += 1
	t.assert_eq(done_lines, 1, "righe: %s" % str(lines))
	t.assert_eq(cancelled_lines, 1, "righe: %s" % str(lines))
	for line in CampaignUiText.year_report(s, W.B, result):
		t.assert_false(line.contains("Riaddestramento"), "gli eventi di ALPHA non riguardano BETA: %s" % line)


# --- «Ripristina» (richiesta di Federico, 2026-11-13, ADR-046) ---------------------------------------------------------


func test_pulsante_ripristina(t: TestContext) -> void:
	var s := _world()
	var full := _army(s, W.ALTA, [["Spearmen", 100, 0]])
	t.assert_false(bool(CampaignUiRetrain.restore_action(s, W.A, full).get("visibile")), "esercito al completo: nessun pulsante")
	var a := _army(s, W.ALTA, [["Spearmen", 40, 0], ["Spearmen", 90, 0]])
	var on := CampaignUiRetrain.restore_action(s, W.A, a)
	t.assert_true(bool(on["visibile"]) and bool(on["attivo"]), str(on))
	t.assert_eq(on["testo"], "Ripristina")
	t.assert_true(str(on["suggerimento"]).contains("2 pile") and str(on["suggerimento"]).contains("70 uomini") and str(on["suggerimento"]).contains("70 denari"), str(on["suggerimento"]))
	var abroad := _army(s, W.MEZZA, [["Spearmen", 40, 0]])
	var off := CampaignUiRetrain.restore_action(s, W.A, abroad)
	t.assert_true(bool(off["visibile"]) and not bool(off["attivo"]), "fuori dalle proprie province: spento, con il motivo")
	t.assert_true(str(off["suggerimento"]).contains("provincia"), str(off["suggerimento"]))
	s.faction(W.A).treasury = 5
	t.assert_false(bool(CampaignUiRetrain.restore_action(s, W.A, a)["attivo"]), "tesoro insufficiente")
	s.faction(W.A).treasury = 10000
	var r := GameCommands.restore_army(s, W.A, a.id)
	var text := CampaignUiRetrain.restored_text(s, a, r)
	t.assert_true(text.contains("pieno delle forze a fine anno") and text.contains("2 pile"), text)
	var after := CampaignUiRetrain.restore_action(s, W.A, a)
	t.assert_false(bool(after["visibile"]), "gia' ordinato: resta solo «Ferma riaddestr.»")
