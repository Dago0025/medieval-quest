extends RefCounted
## Test del trascinamento delle pedine come nell'originale (richiesta di Federico del 2026-11-09): unione di eserciti
## trascinandoli uno sull'altro (subito o all'arrivo), posizione scelta nella regione (riordino), missioni degli agenti
## lasciati sopra un esercito o un altro agente (proposte alla sua fazione, nozze della principessa con un generale).
## Mondo di prova degli agenti (tests/unit/agent_world.gd): ALPHA ha ALTA e BASSA (confinanti), BETA ha MEZZA.

const W := preload("res://tests/unit/agent_world.gd")


func _world() -> GameState:
	var s := W.world()
	s.faction(W.A).is_player = true
	return s


func _options(s: GameState, agent: AgentState) -> Array:
	return GameCommands.mission_options(s, agent.faction, agent.id)["missioni"]


func _kinds(plan: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for e in plan["voci"]:
		out.append(str((e as Dictionary)["tipo"]))
	return out


func _end_year(s: GameState) -> void:
	TurnProcessor.end_year(s)


# --- unione di eserciti -------------------------------------------------------------------------------------------


func test_nella_stessa_regione_si_uniscono_subito(t: TestContext) -> void:
	var s := _world()
	var main := W.land_army(s, W.A, W.ALTA)
	var extra := s.create_army(W.A, W.ALTA, false)
	extra.stacks.append(UnitStack.new(main.stacks[0].unit_id, 40, 0))
	var before := main.stacks.size()
	var r := GameCommands.order_merge(s, W.A, extra.id, main.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_true(bool(r["subito"]))
	t.assert_eq(main.stacks.size(), before + 1)
	t.assert_true(s.army(extra.id) == null, "l'esercito trascinato confluisce e sparisce")


func test_in_una_regione_confinante_si_uniscono_all_arrivo(t: TestContext) -> void:
	var s := _world()
	var target := W.land_army(s, W.A, W.ALTA)
	var mover := W.land_army(s, W.A, W.BASSA)
	var total := target.stacks.size() + mover.stacks.size()
	var r := GameCommands.order_merge(s, W.A, mover.id, target.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_false(bool(r["subito"]))
	t.assert_eq(mover.path, PackedStringArray([W.ALTA]))
	t.assert_eq(mover.merge_target, target.id)
	_end_year(s)
	t.assert_true(s.army(mover.id) == null, "arrivato, confluisce")
	t.assert_eq(target.stacks.size(), total)
	t.assert_eq(W.events_of(s, GameState.EV_ARMIES_MERGED).size(), 1)


func test_unione_mancata_se_il_bersaglio_parte(t: TestContext) -> void:
	var s := _world()
	var target := W.land_army(s, W.A, W.ALTA)
	var mover := W.land_army(s, W.A, W.BASSA)
	GameCommands.order_merge(s, W.A, mover.id, target.id)
	GameCommands.order_move(s, W.A, target.id, PackedStringArray([W.BASSA]))
	_end_year(s)
	t.assert_true(s.army(mover.id) != null)
	t.assert_eq(mover.merge_target, 0, "l'ordine cade")
	t.assert_eq(W.events_of(s, GameState.EV_MERGE_FAILED).size(), 1)


func test_senza_posto_non_si_uniscono(t: TestContext) -> void:
	var s := _world()
	var target := W.land_army(s, W.A, W.ALTA)
	var full := StackMerge.full_men(s, target.stacks[0])   # pile piene: l'accorpamento (ADR-146) non libera posto
	for st in target.stacks:
		st.men = maxi(st.men, StackMerge.full_men(s, st))
	while target.stacks.size() < s.rules.max_stacks:
		target.stacks.append(UnitStack.new(target.stacks[0].unit_id, full, 0))
	var mover := W.land_army(s, W.A, W.BASSA)
	var r := GameCommands.order_merge(s, W.A, mover.id, target.id)
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("posto"), str(r["errore"]))
	t.assert_true(mover.path.is_empty(), "nessun movimento ordinato")


func test_un_nuovo_ordine_toglie_l_unione(t: TestContext) -> void:
	var s := _world()
	var target := W.land_army(s, W.A, W.ALTA)
	var mover := W.land_army(s, W.A, W.BASSA)
	GameCommands.order_merge(s, W.A, mover.id, target.id)
	GameCommands.cancel_move(s, W.A, mover.id)
	t.assert_eq(mover.merge_target, 0)
	GameCommands.order_merge(s, W.A, mover.id, target.id)
	GameCommands.order_move(s, W.A, mover.id, PackedStringArray([W.ALTA]))
	t.assert_eq(mover.merge_target, 0, "un movimento normale non unisce")


func test_non_si_uniscono_eserciti_altrui(t: TestContext) -> void:
	var s := _world()
	var mine := W.land_army(s, W.A, W.BASSA)
	var theirs := W.land_army(s, W.B, W.MEZZA)
	t.assert_false(bool(GameCommands.order_merge(s, W.A, mine.id, theirs.id)["ok"]))
	t.assert_false(bool(GameCommands.order_merge(s, W.A, mine.id, mine.id)["ok"]))


func test_l_unione_ordinata_si_salva(t: TestContext) -> void:
	var s := _world()
	var mover := W.land_army(s, W.A, W.BASSA)
	mover.merge_target = 3
	var copy := Army.from_dict(mover.to_dict())
	t.assert_eq(copy.merge_target, 3)
	t.assert_false(W.land_army(s, W.A, W.ALTA).to_dict().has("unisci_a"))


# --- riordino nella regione ---------------------------------------------------------------------------------------


func test_la_pedina_resta_dove_la_si_posa_finche_non_cambia_regione(t: TestContext) -> void:
	var s := _world()
	var army := W.land_army(s, W.A, W.BASSA)
	t.assert_eq(army.spot_here(), Vector2.INF)
	t.assert_true(bool(GameCommands.set_piece_spot(s, W.A, "esercito", army.id, Vector2(120, 80))["ok"]))
	t.assert_eq(army.spot_here(), Vector2(120, 80))
	var copy := Army.from_dict(army.to_dict())
	t.assert_eq(copy.spot_here(), Vector2(120, 80), "si salva")
	army.region = W.ALTA
	t.assert_eq(army.spot_here(), Vector2.INF, "in un'altra regione torna la posizione automatica")
	var agent := W.agent_of(s, W.A, AgentState.EMISSARY)
	t.assert_true(bool(GameCommands.set_piece_spot(s, W.A, "agente", agent.id, Vector2(5, 6))["ok"]))
	t.assert_eq(AgentState.from_dict(agent.to_dict()).spot_here(), Vector2(5, 6))
	t.assert_false(bool(GameCommands.set_piece_spot(s, W.B, "agente", agent.id, Vector2(5, 6))["ok"]), "solo le proprie pedine")


# --- agenti lasciati su un bersaglio --------------------------------------------------------------------------------


func test_emissario_sopra_un_emissario_straniero_propone(t: TestContext) -> void:
	var s := _world()
	var mine := W.agent_of(s, W.A, AgentState.EMISSARY)
	var theirs := W.agent_of(s, W.B, AgentState.EMISSARY)
	var plan := CampaignUiAgents.click_plan(s, mine, _options(s, mine), theirs.region, 0, theirs.id)
	t.assert_eq(plan["azione"], CampaignUiAgents.PLAN_MENU)
	t.assert_true(_kinds(plan).has(AgentMissions.ALLIANCE), str(_kinds(plan)))
	for e in plan["voci"]:
		var entry: Dictionary = e
		if str(entry["tipo"]) == AgentMissions.ALLIANCE:
			t.assert_eq(entry["bersaglio"], W.B)


func test_emissario_sopra_il_re_propone_la_tregua_in_guerra(t: TestContext) -> void:
	var s := _world()
	s.declare_war(W.A, W.B)
	var mine := W.agent_of(s, W.A, AgentState.EMISSARY)
	var king := W.land_army(s, W.B, W.MEZZA)
	var plan := CampaignUiAgents.click_plan(s, mine, _options(s, mine), W.MEZZA, king.id)
	t.assert_true(_kinds(plan).has(AgentMissions.TRUCE), str(_kinds(plan)))
	t.assert_false(_kinds(plan).has(AgentMissions.ALLIANCE), "in guerra niente alleanza")


func test_principessa_sopra_un_esercito_straniero_propone_le_nozze(t: TestContext) -> void:
	var s := _world()
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var king := W.land_army(s, W.B, W.MEZZA)
	var near := GameCommands.order_agent_move(s, W.A, princess.id, PackedStringArray([W.BASSA]))
	princess.region = W.BASSA   # confina con MEZZA
	princess.path = PackedStringArray()
	var plan := CampaignUiAgents.click_plan(s, princess, _options(s, princess), W.MEZZA, king.id)
	t.assert_true(_kinds(plan).has(AgentMissions.MARRIAGE), "%s %s" % [str(_kinds(plan)), str(near)])


func test_bersaglio_fuori_portata_l_agente_si_avvia(t: TestContext) -> void:
	var s := _world()
	var mine := W.agent_of(s, W.A, AgentState.EMISSARY)
	var far := W.land_army(s, W.G, W.ORTO)
	var plan := CampaignUiAgents.click_plan(s, mine, _options(s, mine), W.ORTO, far.id)
	t.assert_eq(plan["azione"], CampaignUiAgents.PLAN_MOVE)


func test_barricarsi_toglie_la_posizione_scelta(t: TestContext) -> void:
	var s := _world()
	var army := W.land_army(s, W.A, W.BASSA)
	GameCommands.set_piece_spot(s, W.A, "esercito", army.id, Vector2(10, 10))
	t.assert_true(bool(GameCommands.enter_castle(s, W.A, army.id)["ok"]))
	t.assert_eq(army.spot_here(), Vector2.INF, "nel castello la pedina sta davanti al castello")
