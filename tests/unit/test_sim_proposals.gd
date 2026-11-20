extends RefCounted
## Proposte dell'IA al giocatore (fase 7b, ADR-012): una missione di alleanza, tregua o matrimonio di un'IA verso la fazione di un
## giocatore non si risolve da sola ma diventa una voce di `GameState.pending_proposals`; l'agente aspetta; `answer_proposal`
## applica l'esito con gli eventi di sempre; a fine anno scadono; il salvataggio (versione 10) le conserva. Tra due IA nulla cambia.
## Mondo di prova: agent_world.gd (ALPHA: ALTA e BASSA; BETA: MEZZA; i confini sono ALTA - BASSA - MEZZA).

const W := preload("res://tests/unit/agent_world.gd")


func _end_year(t: TestContext, s: GameState) -> void:
	var r := TurnProcessor.end_year(s)
	t.assert_true(bool(r["ok"]), "fine anno")
	t.assert_eq((r["errori"] as Array).size(), 0, "nessuna anomalia dei dati: %s" % str(r["errori"]))


## BETA e' il giocatore; l'emissario di ALPHA propone `kind` a BETA e il fine anno la mette in coda.
func _queued(t: TestContext, kind: String, war: bool = false) -> GameState:
	var s := W.world()
	s.faction(W.B).is_player = true
	if war:
		s.declare_war(W.A, W.B)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var r := GameCommands.order_mission(s, W.A, e.id, kind, W.B)
	t.assert_true(bool(r["ok"]), "ordine: %s" % str(r["errore"]))
	_end_year(t, s)
	return s


func test_la_proposta_dell_ia_al_giocatore_va_in_coda(t: TestContext) -> void:
	var s := _queued(t, AgentMissions.ALLIANCE)
	t.assert_eq(s.pending_proposals.size(), 1, "una proposta in attesa")
	var p: Dictionary = s.pending_proposals[0]
	t.assert_eq(p["da"], W.A)
	t.assert_eq(p["a"], W.B)
	t.assert_eq(p["tipo"], AgentMissions.ALLIANCE)
	t.assert_eq(int(p["scadenza"]), int(p["anno"]) + 1, "scade alla fine dell'anno dopo")
	t.assert_true(s.agent(int(p["agente"])) != null, "l'agente aspetta")
	t.assert_false(s.is_allied(W.A, W.B), "senza risposta niente alleanza")
	t.assert_eq(W.events_of(s, GameState.EV_PROPOSAL_RECEIVED).size(), 1)
	t.assert_eq(s.proposals_for(W.B).size(), 1)
	t.assert_eq(s.proposals_for(W.A).size(), 0)
	t.assert_true(s.has_proposal(W.A, W.B, AgentMissions.ALLIANCE))


func test_l_agente_in_attesa_non_riceve_altri_ordini(t: TestContext) -> void:
	var s := _queued(t, AgentMissions.ALLIANCE)
	var p: Dictionary = s.pending_proposals[0]
	var agent_id := int(p["agente"])
	var r := GameCommands.order_mission(s, W.A, agent_id, AgentMissions.TRUCE, W.B)
	t.assert_false(bool(r["ok"]), "aspetta la risposta")
	var m := GameCommands.order_agent_move(s, W.A, agent_id, PackedStringArray([W.BASSA]))
	t.assert_false(bool(m["ok"]), "non si muove")


func test_accettare_l_alleanza(t: TestContext) -> void:
	var s := _queued(t, AgentMissions.ALLIANCE)
	var id := int((s.pending_proposals[0] as Dictionary)["id"])
	var r := GameCommands.answer_proposal(s, W.B, id, true)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_true(s.is_allied(W.A, W.B))
	t.assert_true(s.pending_proposals.is_empty())
	t.assert_eq(r["evento"], GameState.EV_ALLIANCE_FORMED)
	t.assert_true(str(r["testo"]) != "")
	t.assert_eq(W.events_of(s, GameState.EV_ALLIANCE_FORMED).size(), 1)


func test_rifiutare_la_proposta(t: TestContext) -> void:
	var s := _queued(t, AgentMissions.ALLIANCE)
	var id := int((s.pending_proposals[0] as Dictionary)["id"])
	var r := GameCommands.answer_proposal(s, W.B, id, false)
	t.assert_true(bool(r["ok"]))
	t.assert_false(s.is_allied(W.A, W.B))
	t.assert_true(s.pending_proposals.is_empty())
	t.assert_eq(r["evento"], GameState.EV_PROPOSAL_REFUSED)
	t.assert_eq(W.events_of(s, GameState.EV_PROPOSAL_REFUSED).size(), 1)


func test_accettare_la_tregua(t: TestContext) -> void:
	var s := _queued(t, AgentMissions.TRUCE, true)
	t.assert_eq(s.pending_proposals.size(), 1)
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_WAR)
	var id := int((s.pending_proposals[0] as Dictionary)["id"])
	var r := GameCommands.answer_proposal(s, W.B, id, true)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_TRUCE)
	t.assert_eq(r["evento"], GameState.EV_TRUCE)


func test_accettare_il_matrimonio(t: TestContext) -> void:
	var s := W.world()
	s.faction(W.B).is_player = true
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var character_id := princess.character_id
	princess.region = W.BASSA
	var o := GameCommands.order_mission(s, W.A, princess.id, AgentMissions.MARRIAGE, W.B)
	t.assert_true(bool(o["ok"]), str(o["errore"]))
	_end_year(t, s)
	t.assert_eq(s.pending_proposals.size(), 1)
	t.assert_true(s.agent(princess.id) != null, "la principessa aspetta")
	var id := int((s.pending_proposals[0] as Dictionary)["id"])
	var r := GameCommands.answer_proposal(s, W.B, id, true)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_true(s.is_allied(W.A, W.B), "il matrimonio porta all'alleanza")
	t.assert_true(s.agent(princess.id) == null, "la principessa lascia la partita")
	t.assert_false(s.character(character_id).alive)


func test_risposte_non_valide(t: TestContext) -> void:
	var s := _queued(t, AgentMissions.ALLIANCE)
	var id := int((s.pending_proposals[0] as Dictionary)["id"])
	t.assert_false(bool(GameCommands.answer_proposal(s, W.G, id, true)["ok"]), "non e' per GAMMA")
	t.assert_false(bool(GameCommands.answer_proposal(s, W.B, id + 99, true)["ok"]), "proposta sconosciuta")
	t.assert_eq(s.pending_proposals.size(), 1, "gli errori non toccano la coda")
	# la situazione cambia: le due fazioni vanno in guerra, l'alleanza non si puo' piu' stringere
	s.declare_war(W.A, W.B)
	var r := GameCommands.answer_proposal(s, W.B, id, true)
	t.assert_false(bool(r["ok"]), "non sono piu' neutrali")
	t.assert_true(s.pending_proposals.is_empty(), "la proposta decaduta si toglie")


func test_la_proposta_scade_alla_fine_dell_anno_dopo(t: TestContext) -> void:
	# nata nel fine anno Y con scadenza Y+1: il giocatore ha tutto l'anno Y+1 per rispondere, poi al fine anno Y+1 decade
	var s := _queued(t, AgentMissions.ALLIANCE)
	t.assert_eq(s.pending_proposals.size(), 1, "durante l'anno dopo aspetta ancora")
	_end_year(t, s)
	t.assert_true(s.pending_proposals.is_empty(), "al fine dell'anno dopo decade")
	var expired := W.events_of(s, GameState.EV_PROPOSAL_EXPIRED)
	t.assert_eq(expired.size(), 1)
	t.assert_eq(expired[0]["motivo"], "scaduta")
	t.assert_false(s.is_allied(W.A, W.B))


func test_la_proposta_cade_se_l_agente_muore(t: TestContext) -> void:
	var s := _queued(t, AgentMissions.ALLIANCE)
	var p: Dictionary = s.pending_proposals[0]
	s.remove_agent(s.agent(int(p["agente"])))
	_end_year(t, s)
	t.assert_true(s.pending_proposals.is_empty())
	var expired := W.events_of(s, GameState.EV_PROPOSAL_EXPIRED)
	t.assert_eq(expired.size(), 1)
	t.assert_eq(expired[0]["motivo"], "agente")


func test_tra_due_ia_non_cambia_nulla(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var r := GameCommands.order_mission(s, W.A, e.id, AgentMissions.ALLIANCE, W.B)
	t.assert_true(bool(r["ok"]))
	_end_year(t, s)
	t.assert_true(s.pending_proposals.is_empty(), "nessuna proposta tra IA")
	t.assert_true(s.is_allied(W.A, W.B), "si risolve con il sorteggio di sempre")
	t.assert_eq(W.events_of(s, GameState.EV_PROPOSAL_RECEIVED).size(), 0)


func test_una_proposta_uguale_non_si_duplica(t: TestContext) -> void:
	var s := _queued(t, AgentMissions.ALLIANCE)
	# un secondo emissario di ALPHA propone la stessa cosa mentre la prima aspetta
	var second := W.add_agent(s, W.A, W.BASSA, AgentState.EMISSARY, 2)
	var r := GameCommands.order_mission(s, W.A, second.id, AgentMissions.ALLIANCE, W.B)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	AgentProcessor.process_year(s)
	t.assert_eq(s.pending_proposals.size(), 1, "una sola proposta uguale")
	t.assert_false(second.has_mission(), "la seconda missione e' caduta")


func test_il_salvataggio_conserva_le_proposte(t: TestContext) -> void:
	var s := _queued(t, AgentMissions.ALLIANCE)
	var before: Array = s.pending_proposals.duplicate(true)
	var next_id := s.next_proposal_id
	var text := SaveGame.to_json(s)
	var data: Dictionary = JSON.parse_string(text)
	var campaign := StartposLoader.load_file(W.STARTPOS)
	var units := UnitProdLoader.load_file(W.UNITS)
	var buildings := BuildingProdLoader.load_file(W.BUILDINGS)
	var r := SaveGame.from_dict(data, campaign, units, buildings, W.quiet_rules())
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	var loaded: GameState = r["stato"]
	t.assert_eq(loaded.pending_proposals.size(), before.size())
	var a: Dictionary = loaded.pending_proposals[0]
	var b: Dictionary = before[0]
	for key in b.keys():
		t.assert_eq(a[key], b[key], "campo %s" % key)
	t.assert_eq(loaded.next_proposal_id, next_id)
	t.assert_eq(typeof(a["id"]), TYPE_INT, "gli interi tornano interi")
	var answered := GameCommands.answer_proposal(loaded, W.B, int(a["id"]), true)
	t.assert_true(bool(answered["ok"]), str(answered.get("errore", "")))
	t.assert_true(loaded.is_allied(W.A, W.B))
