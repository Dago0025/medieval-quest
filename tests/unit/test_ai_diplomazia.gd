extends RefCounted
## Diplomazia dell'IA (fase 7b): tregue quando una guerra va male, alleanze contro un nemico comune, nozze, tradimento solo per i
## profili espansionisti, proposte al giocatore che aspettano la risposta. Mondo di prova: agent_world.gd (ALPHA - BETA - GAMMA, un
## emissario per fazione, una principessa per ALPHA e BETA); si usano le funzioni dell'IA di ai_world.gd.
## Le probabilita' annue si portano a 1 (o a 0) per avere situazioni nette.

const W := preload("res://tests/unit/agent_world.gd")
const AW := preload("res://tests/unit/ai_world.gd")


func _rules() -> AiRules:
	var r := AW.quiet_ai_rules()
	r.peace_prob = 0.0
	r.alliance_prob = 1.0
	r.alliance_min_p = 0.0
	r.marriage_prob = 1.0
	r.betray_prob = 1.0
	r.player_proposal_prob = 1.0
	return r


func _plan(s: GameState, faction_id: String, r: AiRules, profile: String = "") -> AiPlan:
	var ctx := AW.context(s, r)
	return AW.plan_for(s, faction_id, profile, ctx)


func _mission_of(s: GameState, faction_id: String, type_name: String) -> Dictionary:
	for a in s.agents:
		if a.faction == faction_id and a.type_name == type_name and a.has_mission():
			return a.mission
	return {}


# --- tregue --------------------------------------------------------------------------------------------------------


func test_propone_la_tregua_quando_la_guerra_va_male(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	W.general_army(s, W.B, W.BASSA, 2000)
	var data := _plan(s, W.A, _rules())
	t.assert_true(AiDiplomacy.war_going_badly(data, W.B), "un nemico molto piu' forte dentro le province proprie")
	AiDiplomacy.plan(data)
	var m := _mission_of(s, W.A, AgentState.EMISSARY)
	t.assert_eq(m.get("tipo", ""), AgentMissions.TRUCE, "l'emissario di ALPHA va a chiedere la tregua")
	t.assert_eq(m.get("bersaglio", ""), W.B)
	t.assert_true(data.courting.has(W.B), "quest'anno non si attacca chi si corteggia")


func test_la_tregua_dopo_province_perdute(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	var data := _plan(s, W.A, _rules())
	t.assert_false(AiDiplomacy.war_going_badly(data, W.B), "forze pari e nessuna perdita")
	data.ctx.captures_lost["%s>%s" % [W.A, W.B]] = 1
	t.assert_true(AiDiplomacy.war_going_badly(data, W.B), "ha perso una provincia contro BETA")


func test_non_propone_la_tregua_se_vince(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	W.general_army(s, W.A, W.BASSA, 2000)
	var data := _plan(s, W.A, _rules())
	t.assert_false(AiDiplomacy.war_going_badly(data, W.B))
	AiDiplomacy.plan(data)
	t.assert_true(_mission_of(s, W.A, AgentState.EMISSARY).is_empty(), "con la guerra in mano non cerca la pace")


func test_chi_non_e_espansionista_cerca_la_pace_a_volte(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	var r := _rules()
	r.peace_prob = 1.0
	var data := _plan(s, W.A, r, "CATHOLIC_DEFENSIVE")
	AiDiplomacy.plan(data)
	t.assert_eq(_mission_of(s, W.A, AgentState.EMISSARY).get("tipo", ""), AgentMissions.TRUCE)
	var s2 := W.world()
	s2.declare_war(W.A, W.B)
	var data2 := _plan(s2, W.A, r, "CATHOLIC_EXPANSIONIST")
	AiDiplomacy.plan(data2)
	t.assert_true(_mission_of(s2, W.A, AgentState.EMISSARY).is_empty(), "l'espansionista non cerca la pace senza perdere")


# --- alleanze e nozze ---------------------------------------------------------------------------------------------


func _common_enemy(s: GameState) -> void:
	s.declare_war(W.A, W.G)
	s.declare_war(W.B, W.G)


func test_alleanza_contro_un_nemico_comune(t: TestContext) -> void:
	var s := W.world()
	_common_enemy(s)
	var data := _plan(s, W.A, _rules())
	var candidates := AiDiplomacy.alliance_candidates(data)
	t.assert_eq(candidates.size(), 1, "BETA confina, e' neutrale ed e' in guerra con GAMMA")
	t.assert_eq(candidates[0]["id"], W.B)
	AiDiplomacy.plan(data)
	var m := _mission_of(s, W.A, AgentState.EMISSARY)
	t.assert_eq(m.get("tipo", ""), AgentMissions.ALLIANCE)
	t.assert_eq(m.get("bersaglio", ""), W.B)


func test_senza_nemico_comune_niente_alleanza(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.G)
	var data := _plan(s, W.A, _rules())
	t.assert_true(AiDiplomacy.alliance_candidates(data).is_empty(), "BETA non ha nemici in comune con ALPHA")


func test_niente_alleanze_oltre_il_massimo(t: TestContext) -> void:
	var s := W.world()
	_common_enemy(s)
	var r := _rules()
	r.alliances_max = 0
	var data := _plan(s, W.A, r)
	t.assert_true(AiDiplomacy.alliance_candidates(data).is_empty())


func test_la_principessa_sposa_il_vicino(t: TestContext) -> void:
	var s := W.world()
	_common_enemy(s)
	var emissary := W.agent_of(s, W.A, AgentState.EMISSARY)
	s.remove_agent(emissary)
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	princess.region = W.BASSA
	var data := _plan(s, W.A, _rules())
	AiDiplomacy.plan(data)
	t.assert_eq(princess.mission.get("tipo", ""), AgentMissions.MARRIAGE)
	t.assert_eq(princess.mission.get("bersaglio", ""), W.B)


# --- tradimento -----------------------------------------------------------------------------------------------------


func _betrayal_world() -> GameState:
	var s := W.world()
	s.form_alliance(W.A, W.B)
	W.general_army(s, W.A, W.BASSA, 3000)
	return s


func test_l_espansionista_puo_tradire_l_alleato_debole(t: TestContext) -> void:
	var s := _betrayal_world()
	var data := _plan(s, W.A, _rules(), "CATHOLIC_EXPANSIONIST")
	data.target_level = 3
	AiDiplomacy.plan_betrayal(data)
	t.assert_true(data.betray.has(W.B), "ALPHA e' molto piu' forte e non ha nemici in comune con BETA")


func test_chi_non_e_espansionista_non_tradisce(t: TestContext) -> void:
	var s := _betrayal_world()
	var data := _plan(s, W.A, _rules(), "CATHOLIC_DEFENSIVE")
	data.target_level = 3
	AiDiplomacy.plan_betrayal(data)
	t.assert_true(data.betray.is_empty(), "il difensivo rispetta l'alleanza")


func test_il_mercante_puo_tradire_con_la_sua_probabilita(t: TestContext) -> void:
	var s := _betrayal_world()
	var r := _rules()
	r.betray_prob = 0.0
	r.betray_prob_other = 1.0
	var data := _plan(s, W.A, r, "CATHOLIC_TRADER")
	data.target_level = 2
	AiDiplomacy.plan_betrayal(data)
	t.assert_true(data.betray.has(W.B), "un profilo non difensivo che attacca chi e' in guerra puo' tradire l'alleato debole")
	t.assert_eq(AiPolicy.attackable(data, W.B), AiPolicy.KIND_BETRAYAL, "e con i bersagli «guerra» lo puo' attaccare")
	var never := _plan(_betrayal_world(), W.A, r, "CATHOLIC_TRADER")
	never.target_level = 1
	AiDiplomacy.plan_betrayal(never)
	t.assert_true(never.betray.is_empty(), "chi attacca solo i ribelli non tradisce")
	r.betray_prob_other = 0.0
	var calm := _plan(_betrayal_world(), W.A, r, "CATHOLIC_TRADER")
	calm.target_level = 2
	AiDiplomacy.plan_betrayal(calm)
	t.assert_true(calm.betray.is_empty(), "probabilita' zero: nessun tradimento")


func test_la_guerra_in_stallo_porta_alla_tregua_anche_l_espansionista(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	var r := _rules()
	r.stalemate_peace_prob = 1.0
	var data := _plan(s, W.A, r, "CATHOLIC_EXPANSIONIST")
	t.assert_false(AiDiplomacy.wants_truce(data, W.B), "guerra appena dichiarata e forze pari: niente tregua")
	s.year += r.stalemate_years
	data = _plan(s, W.A, r, "CATHOLIC_EXPANSIONIST")
	t.assert_true(AiDiplomacy.wants_truce(data, W.B), "%d anni senza svolte: anche l'espansionista cerca la tregua" % r.stalemate_years)
	s.mark_war_turn(W.A, W.B)
	data = _plan(s, W.A, r, "CATHOLIC_EXPANSIONIST")
	t.assert_false(AiDiplomacy.wants_truce(data, W.B), "una provincia passata di mano quest'anno: la guerra non e' in stallo")
	s.year += r.stalemate_years
	r.stalemate_peace_prob = 0.0
	data = _plan(s, W.A, r, "CATHOLIC_EXPANSIONIST")
	t.assert_false(AiDiplomacy.wants_truce(data, W.B), "probabilita' zero: niente tregua")


func test_non_tradisce_se_l_alleato_ha_un_nemico_in_comune(t: TestContext) -> void:
	var s := _betrayal_world()
	_common_enemy(s)
	var data := _plan(s, W.A, _rules(), "CATHOLIC_EXPANSIONIST")
	data.target_level = 3
	AiDiplomacy.plan_betrayal(data)
	t.assert_true(data.betray.is_empty(), "l'alleato serve contro GAMMA")


func test_tradire_non_conviene_contro_un_alleato_forte(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.A, W.B)
	W.general_army(s, W.B, W.MEZZA, 5000)
	var data := _plan(s, W.A, _rules(), "CATHOLIC_EXPANSIONIST")
	data.target_level = 3
	AiDiplomacy.plan_betrayal(data)
	t.assert_true(data.betray.is_empty())


# --- proposte al giocatore ------------------------------------------------------------------------------------------


func _player_world() -> GameState:
	var s := W.world()
	_common_enemy(s)
	s.faction(W.B).is_player = true
	return s


func test_la_proposta_al_giocatore_aspetta_la_risposta(t: TestContext) -> void:
	var s := _player_world()
	AW.run_faction(s, W.A, _rules())
	var r := TurnProcessor.end_year(s)
	t.assert_true(bool(r["ok"]))
	t.assert_eq(s.proposals_for(W.B).size(), 1, "ALPHA propone un'alleanza al giocatore BETA")
	t.assert_false(s.is_allied(W.A, W.B), "finche' il giocatore non risponde non c'e' alleanza")
	var id := int((s.proposals_for(W.B)[0] as Dictionary)["id"])
	var answer := GameCommands.answer_proposal(s, W.B, id, true)
	t.assert_true(bool(answer["ok"]), str(answer.get("errore", "")))
	t.assert_true(s.is_allied(W.A, W.B), "accettata: alleanza")


func test_la_proposta_al_giocatore_scade(t: TestContext) -> void:
	var s := _player_world()
	AW.run_faction(s, W.A, _rules())
	TurnProcessor.end_year(s)
	t.assert_eq(s.proposals_for(W.B).size(), 1)
	TurnProcessor.end_year(s)
	TurnProcessor.end_year(s)
	t.assert_true(s.proposals_for(W.B).is_empty(), "dopo l'anno successivo e' decaduta")
	t.assert_false(s.is_allied(W.A, W.B))


func test_nessuna_proposta_con_probabilita_zero(t: TestContext) -> void:
	var s := _player_world()
	var r := _rules()
	r.player_proposal_prob = 0.0
	AW.run_faction(s, W.A, r)
	TurnProcessor.end_year(s)
	t.assert_true(s.proposals_for(W.B).is_empty())


func test_pochi_proposte_in_attesa(t: TestContext) -> void:
	var s := _player_world()
	var r := _rules()
	r.player_proposals_max = 0
	AW.run_faction(s, W.A, r)
	TurnProcessor.end_year(s)
	t.assert_true(s.proposals_for(W.B).is_empty(), "il tetto di proposte in attesa blocca l'invio")


# --- ordine e determinismo ---------------------------------------------------------------------------------------


func test_stesso_stato_stessi_ordini(t: TestContext) -> void:
	var a := W.world()
	_common_enemy(a)
	AW.run_faction(a, W.A, _rules())
	var b := W.world()
	_common_enemy(b)
	AW.run_faction(b, W.A, _rules())
	t.assert_eq(str(_mission_of(a, W.A, AgentState.EMISSARY)), str(_mission_of(b, W.A, AgentState.EMISSARY)))
