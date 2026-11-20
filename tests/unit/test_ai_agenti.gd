extends RefCounted
## Agenti e crociate dell'IA (fase 7b): reclutamento entro il tetto, spie alla frontiera, assassini contro i generali nemici,
## corruzione, crociate e jihad. Mondi di prova: agent_world.gd (agenti di ogni tipo) e papacy_world.gd (Casa del Capitolo, Ribat,
## scomunica); le regole dell'IA vengono da ai_world.gd.

const W := preload("res://tests/unit/agent_world.gd")
const PW := preload("res://tests/unit/papacy_world.gd")
const AW := preload("res://tests/unit/ai_world.gd")


func _rules() -> AiRules:
	var r := AW.quiet_ai_rules()
	r.peace_prob = 0.0
	r.crusade_prob = 1.0
	r.agents_per_year = 10
	r.agent_budget = 5.0
	return r


func _plan(s: GameState, faction_id: String, r: AiRules, profile: String = "") -> AiPlan:
	return AW.plan_for(s, faction_id, profile, AW.context(s, r))


## Agenti in coda di reclutamento per tipo (di tutte le province della fazione).
func _queued_types(s: GameState, faction_id: String) -> Dictionary:
	var out := {}
	for p in s.provinces_of(faction_id):
		for q in p.unit_queue:
			var u := s.units.get_unit(q.key)
			if u != null:
				out[u.type_name] = int(out.get(u.type_name, 0)) + 1
	return out


# --- reclutamento ----------------------------------------------------------------------------------------------------


func test_recluta_agenti_entro_il_tetto(t: TestContext) -> void:
	var s := W.world()
	s.faction(W.A).treasury = 100000
	var r := _rules()
	for i in 3:
		AiAgents.plan(_plan(s, W.A, r))
	var queued := _queued_types(s, W.A)
	var provinces := s.provinces_of(W.A).size()
	t.assert_true(int(queued.get("SPY", 0)) >= 1, "almeno una spia in coda")
	t.assert_true(int(queued.get("SPY", 0)) <= ceili(float(provinces) * r.cap_spy), "spie entro il tetto")
	t.assert_true(int(queued.get("ASSASSIN", 0)) <= ceili(float(provinces) * r.cap_assassin), "assassini entro il tetto")
	t.assert_eq(int(queued.get("EMISSARY", 0)), 0, "ALPHA ha gia' il suo emissario: il tetto e' pieno")


func test_non_recluta_senza_denaro(t: TestContext) -> void:
	var s := W.world()
	s.faction(W.A).treasury = 0
	AiAgents.plan(_plan(s, W.A, _rules()))
	t.assert_true(_queued_types(s, W.A).is_empty(), "senza tesoro oltre la riserva non si assume nessuno")


# --- spie, assassini, corruzione -----------------------------------------------------------------------------------


func test_la_spia_va_alla_frontiera_nemica(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	var spy := W.add_agent(s, W.A, W.ALTA, AgentState.SPY, 1)
	AiAgents.plan(_plan(s, W.A, _rules()))
	t.assert_false(spy.path.is_empty(), "la spia parte")
	t.assert_eq(spy.path[spy.path.size() - 1], W.MEZZA, "verso la provincia nemica di confine")


func test_l_assassino_colpisce_il_generale_nemico(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	s.declare_war(W.A, W.B)
	var assassin := W.add_agent(s, W.A, W.BASSA, AgentState.ASSASSIN, 2)
	var general := W.add_general(s, W.B, W.MEZZA)
	AiAgents.plan(_plan(s, W.A, _rules()))
	t.assert_true(assassin.has_mission(), "l'assassino ha un bersaglio")
	t.assert_eq(assassin.mission.get("tipo", ""), AgentMissions.ASSASSINATE)
	var target: Dictionary = assassin.mission["bersaglio"]
	t.assert_eq(target["tipo"], AgentMissions.TARGET_CHARACTER)
	var hit := s.character(int(target["id"]))
	t.assert_eq(hit.faction, W.B, "un personaggio della fazione in guerra")
	t.assert_true(general != null)


func test_l_assassino_non_colpisce_in_pace(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	var assassin := W.add_agent(s, W.A, W.BASSA, AgentState.ASSASSIN, 2)
	W.add_general(s, W.B, W.MEZZA)
	AiAgents.plan(_plan(s, W.A, _rules()))
	t.assert_false(assassin.has_mission(), "BETA non e' in guerra con ALPHA")


func test_l_emissario_corrompe_un_esercito_nemico(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	s.declare_war(W.A, W.B)
	s.faction(W.A).treasury = 1000000
	var bribed_army := W.general_army(s, W.B, W.MEZZA, 60)
	var emissary := W.agent_of(s, W.A, AgentState.EMISSARY)
	AiAgents.plan(_plan(s, W.A, _rules()))
	t.assert_eq(emissary.mission.get("tipo", ""), AgentMissions.BRIBE, "corrompe l'esercito di BETA")
	t.assert_eq(emissary.mission.get("bersaglio", 0), bribed_army.id)


# --- crociate ---------------------------------------------------------------------------------------------------------


func _crusade_world() -> GameState:
	var s := PW.world()
	s.campaign.faction(PW.A).behaviour = "CATHOLIC_EXPANSIONIST_CRUSADER"
	s.faction(PW.A).treasury = 100000
	return s


func _crusades_queued(s: GameState, faction_id: String) -> int:
	var n := 0
	for p in s.provinces_of(faction_id):
		for q in p.unit_queue:
			if q.key == "Crusade":
				n += 1
	return n


func test_il_crociato_bandisce_una_crociata_con_un_bersaglio_valido(t: TestContext) -> void:
	var s := _crusade_world()
	var data := _plan(s, PW.A, _rules(), "CATHOLIC_EXPANSIONIST_CRUSADER")
	t.assert_eq(AiCrusades.kind_of(data), PapacyProcessor.KIND_CRUSADE)
	t.assert_true(AiCrusades.has_valid_target(data, PapacyProcessor.KIND_CRUSADE), "BETA, musulmana, confina")
	AiCrusades.plan(data)
	t.assert_eq(_crusades_queued(s, PW.A), 1, "la crociata e' in coda")
	AiCrusades.plan(_plan(s, PW.A, _rules(), "CATHOLIC_EXPANSIONIST_CRUSADER"))
	t.assert_eq(_crusades_queued(s, PW.A), 1, "una sola alla volta")


func test_nessuna_crociata_se_scomunicato(t: TestContext) -> void:
	var s := _crusade_world()
	s.faction(PW.A).excommunicated = true
	AiCrusades.plan(_plan(s, PW.A, _rules(), "CATHOLIC_EXPANSIONIST_CRUSADER"))
	t.assert_eq(_crusades_queued(s, PW.A), 0, "gli scomunicati non possono bandire")


func test_nessuna_crociata_senza_bersagli(t: TestContext) -> void:
	var s := _crusade_world()
	# BETA (musulmana) e i ribelli non sono piu' a portata: alleanza con BETA, i ribelli spariscono
	s.form_alliance(PW.A, PW.B)
	for p in s.provinces:
		if p.owner == GameState.REBEL:
			p.owner = PW.G
	AiCrusades.plan(_plan(s, PW.A, _rules(), "CATHOLIC_EXPANSIONIST_CRUSADER"))
	t.assert_eq(_crusades_queued(s, PW.A), 0, "nessun bersaglio valido")


func test_nessuna_crociata_con_probabilita_zero(t: TestContext) -> void:
	var s := _crusade_world()
	var r := _rules()
	r.crusade_prob = 0.0
	AiCrusades.plan(_plan(s, PW.A, r, "CATHOLIC_EXPANSIONIST_CRUSADER"))
	t.assert_eq(_crusades_queued(s, PW.A), 0)


func test_il_profilo_non_crociato_non_bandisce(t: TestContext) -> void:
	var s := PW.world()
	s.campaign.faction(PW.A).behaviour = "CATHOLIC_DEFENSIVE"
	s.faction(PW.A).treasury = 100000
	AiCrusades.plan(_plan(s, PW.A, _rules(), "CATHOLIC_DEFENSIVE"))
	t.assert_eq(_crusades_queued(s, PW.A), 0)


func test_l_esercito_crociato_riceve_un_bersaglio(t: TestContext) -> void:
	var s := _crusade_world()
	var army := PW.add_crusade(s, PW.A, PW.NORD1, PapacyProcessor.KIND_CRUSADE, "")
	AiCrusades.plan(_plan(s, PW.A, _rules(), "CATHOLIC_EXPANSIONIST_CRUSADER"))
	var target := army.crusade_target()
	t.assert_true(target != "", "l'IA sceglie un bersaglio")
	t.assert_eq(PapacyProcessor.target_problem(s, army, target), "", "e' un bersaglio valido")
	t.assert_false(army.path.is_empty(), "e il comando assegna il percorso")


func test_il_jihad_e_dei_profili_musulmani(t: TestContext) -> void:
	var s := PW.world()
	s.campaign.faction(PW.B).behaviour = "MUSLIM_DEVOUT"
	var data := _plan(s, PW.B, _rules(), "MUSLIM_DEVOUT")
	t.assert_eq(AiCrusades.kind_of(data), PapacyProcessor.KIND_JIHAD)
	var data_a := _plan(s, PW.A, _rules(), "CATHOLIC_DEFENSIVE")
	t.assert_eq(AiCrusades.kind_of(data_a), "")


# --- modulo intero ----------------------------------------------------------------------------------------------------


func test_l_intera_fazione_non_ha_rifiuti(t: TestContext) -> void:
	var s := W.world()
	s.faction(W.A).treasury = 100000
	s.declare_war(W.A, W.B)
	W.add_agent(s, W.A, W.ALTA, AgentState.SPY, 1)
	W.add_agent(s, W.A, W.BASSA, AgentState.ASSASSIN, 2)
	W.add_general(s, W.B, W.MEZZA)
	var ctx := AW.run_faction(s, W.A, _rules())
	t.assert_eq(ctx.rejected, 0, "l'IA non manda comandi rifiutati: %s" % str(ctx.rejections))
