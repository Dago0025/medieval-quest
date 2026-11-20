extends RefCounted
## Interfaccia della fase 7b: finestra delle proposte ricevute dall'IA (testo, scadenza, pulsanti Accetta e Rifiuta che chiamano
## `answer_proposal`), coda di piu' proposte e testi italiani degli eventi nuovi. Logica pura in CampaignUiProposals (src/map);
## la finestra vera sta in scenes/campaign_map.gd e non si prova qui. Mondo di prova: agent_world.gd (BETA e' il giocatore).

const W := preload("res://tests/unit/agent_world.gd")


func _with_proposal(t: TestContext, kind: String = AgentMissions.ALLIANCE) -> GameState:
	var s := W.world()
	s.faction(W.B).is_player = true
	if kind == AgentMissions.TRUCE:
		s.declare_war(W.A, W.B)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var r := GameCommands.order_mission(s, W.A, e.id, kind, W.B)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var end := TurnProcessor.end_year(s)
	t.assert_true(bool(end["ok"]))
	return s


func test_senza_proposte_nessuna_finestra(t: TestContext) -> void:
	var s := W.world()
	t.assert_eq(CampaignUiProposals.windows(s, W.B).size(), 0)
	t.assert_eq(CampaignUiProposals.count(s, W.B), 0)
	t.assert_true(CampaignUiProposals.queue_ids(s, W.B).is_empty())


func test_finestra_di_una_proposta(t: TestContext) -> void:
	var s := _with_proposal(t)
	var windows := CampaignUiProposals.windows(s, W.B)
	t.assert_eq(windows.size(), 1)
	var w: Dictionary = windows[0]
	var p: Dictionary = s.pending_proposals[0]
	t.assert_eq(w["id"], int(p["id"]))
	t.assert_eq(w["da"], W.A)
	t.assert_eq(w["tipo"], AgentMissions.ALLIANCE)
	t.assert_true(str(w["titolo"]).find(SimUtil.faction_label(W.A)) >= 0, "il titolo dice chi propone")
	var text := str(w["testo"])
	t.assert_true(text.find("un'alleanza") >= 0, "dice che cosa propone")
	t.assert_true(text.find(str(int(p["scadenza"]))) >= 0, "dice entro quando rispondere")
	t.assert_eq(w["accetta"], "Accetta")
	t.assert_eq(w["rifiuta"], "Rifiuta")


func test_testo_della_tregua(t: TestContext) -> void:
	var s := _with_proposal(t, AgentMissions.TRUCE)
	var w: Dictionary = CampaignUiProposals.windows(s, W.B)[0]
	t.assert_true(str(w["testo"]).find("una tregua") >= 0)


func test_piu_proposte_una_dopo_l_altra(t: TestContext) -> void:
	var s := _with_proposal(t)
	var second := W.add_agent(s, W.G, W.ORTO, AgentState.EMISSARY, 2)
	var r := GameCommands.order_mission(s, W.G, second.id, AgentMissions.ALLIANCE, W.B)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	AgentProcessor.process_year(s)
	var ids := CampaignUiProposals.queue_ids(s, W.B)
	t.assert_eq(ids.size(), 2, "due proposte, in ordine di id")
	t.assert_true(ids[0] < ids[1])
	t.assert_eq(CampaignUiProposals.count(s, W.B), 2)


func test_accetta_e_rifiuta_chiamano_il_comando(t: TestContext) -> void:
	var s := _with_proposal(t)
	var id := CampaignUiProposals.queue_ids(s, W.B)[0]
	var accepted := CampaignUiProposals.answer(s, W.B, id, true)
	t.assert_true(bool(accepted["ok"]))
	t.assert_true(str(accepted["testo"]) != "", "un testo da mostrare")
	t.assert_true(s.is_allied(W.A, W.B))
	t.assert_eq(CampaignUiProposals.count(s, W.B), 0, "la proposta e' uscita dalla coda")
	var s2 := _with_proposal(t)
	var id2 := CampaignUiProposals.queue_ids(s2, W.B)[0]
	var refused := CampaignUiProposals.answer(s2, W.B, id2, false)
	t.assert_true(bool(refused["ok"]))
	t.assert_false(s2.is_allied(W.A, W.B))


func test_risposta_a_una_proposta_inesistente(t: TestContext) -> void:
	var s := W.world()
	var r := CampaignUiProposals.answer(s, W.B, 99, true)
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["testo"]) != "", "l'errore si mostra")


func test_testi_degli_eventi(t: TestContext) -> void:
	var s := _with_proposal(t)
	var received := W.events_of(s, GameState.EV_PROPOSAL_RECEIVED)
	t.assert_eq(received.size(), 1)
	var line := CampaignUiText.format_event(s, received[0])
	t.assert_true(line.find("ti propone") >= 0 and line.find("un'alleanza") >= 0, line)
	TurnProcessor.end_year(s)   # senza risposta nell'anno della scadenza la proposta decade
	var expired := W.events_of(s, GameState.EV_PROPOSAL_EXPIRED)
	t.assert_eq(expired.size(), 1)
	var text := CampaignUiText.format_event(s, expired[0])
	t.assert_true(text.find("decaduta") >= 0 and text.find("tempo") >= 0, text)
	t.assert_eq(CampaignUiProposals.format_event(s, "altro", {}), "", "gli altri eventi non sono suoi")


func test_la_proposta_compare_nel_resoconto_del_giocatore(t: TestContext) -> void:
	var s := _with_proposal(t)
	var lines := CampaignUiText.year_report(s, W.B, {})
	var text := "\n".join(lines)
	t.assert_true(text.find("Diplomazia") >= 0, "sezione della diplomazia: " + text)
	t.assert_true(text.find("ti propone") >= 0, "la proposta e' nel resoconto: " + text)
