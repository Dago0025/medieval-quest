extends RefCounted
## Test del processo dell'inquisitore (fase 5b): missione `processo` (INQUISITOR, GRAND_INQUISITOR) in AgentMissions,
## GameCommands (order_mission, mission_options), risoluzione nel passo 1b di AgentProcessor (rogo, successione del capo,
## agenti), probabilita' (PROVVISORIA: base_processo + k_pieta x (5 - pieta')) ed eventi. Gli effetti annuali degli
## inquisitori sulla provincia (eretici, zelo, malus d'inattivita') sono in test_sim_religion.gd.
## Mondo di prova: vedi agent_world.gd (ALPHA e GAMMA cattoliche, BETA musulmana). Per isolare le regole la probabilita'
## del processo si porta a 1 (`_certain`) o a 0 (`_never`).

const W := preload("res://tests/unit/agent_world.gd")


func _certain(s: GameState) -> void:
	s.rules.religion.trial_p_min = 1.0
	s.rules.religion.trial_p_max = 1.0


func _never(s: GameState) -> void:
	s.rules.religion.trial_p_min = 0.0
	s.rules.religion.trial_p_max = 0.0


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.000001


func _person(c: Character) -> Dictionary:
	return {"tipo": AgentMissions.TARGET_CHARACTER, "id": c.id}


func _agent(a: AgentState) -> Dictionary:
	return {"tipo": AgentMissions.TARGET_AGENT, "id": a.id}


func _order(t: TestContext, s: GameState, agent: AgentState, target: Variant) -> Dictionary:
	var r := GameCommands.order_mission(s, agent.faction, agent.id, AgentMissions.TRIAL, target)
	t.assert_true(bool(r["ok"]), "ordine del processo: %s" % str(r["errore"]))
	return r


func _refused(t: TestContext, s: GameState, agent: AgentState, target: Variant, needle: String = "") -> void:
	var before := agent.mission.duplicate(true)
	var r := GameCommands.order_mission(s, agent.faction, agent.id, AgentMissions.TRIAL, target)
	t.assert_false(bool(r["ok"]), "il processo dovrebbe essere rifiutato")
	t.assert_true(str(r["errore"]) != "", "serve un motivo")
	if needle != "":
		t.assert_true(str(r["errore"]).find(needle) >= 0, "il motivo dice '%s' (e' '%s')" % [needle, str(r["errore"])])
	t.assert_eq(agent.mission, before, "un ordine rifiutato non cambia l'agente")


# --- catalogo -----------------------------------------------------------------------------------------------


func test_la_missione_e_degli_inquisitori(t: TestContext) -> void:
	t.assert_eq(AgentMissions.TRIAL, "processo")
	t.assert_eq(AgentMissions.missions_for("INQUISITOR"), PackedStringArray([AgentMissions.TRIAL]))
	t.assert_eq(AgentMissions.missions_for("GRAND_INQUISITOR"), PackedStringArray([AgentMissions.TRIAL]))
	for kind in ["BISHOP", "PRIEST", "CARDINAL", "MULLAH"]:   # la spia ha le sue missioni dal 18/11/2026
		t.assert_true(AgentMissions.missions_for(kind).is_empty(), "%s non ha missioni" % kind)
	t.assert_eq(AgentMissions.missions_for(AgentState.ASSASSIN), PackedStringArray([AgentMissions.ASSASSINATE]), "il resto non cambia")
	t.assert_eq(AgentMissions.normalize_target(AgentMissions.TRIAL, {"tipo": "agente", "id": 3.0}), {"tipo": "agente", "id": 3})


func test_i_nomi_degli_eventi(t: TestContext) -> void:
	t.assert_eq(GameState.EV_HERETIC_REVOLT, "rivolta_eretica")
	t.assert_eq(GameState.EV_INQUISITION, "inquisizione")
	t.assert_eq(GameState.EV_INQUISITION_FAILED, "inquisizione_fallita")


# --- validazione ----------------------------------------------------------------------------------------------


func test_bersagli_dei_personaggi(t: TestContext) -> void:
	var s := W.world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var leader := s.leader_of(W.A)
	var own := W.add_general(s, W.A, W.BASSA)
	var prince := W.add_general(s, W.A, W.ALTA)
	prince.role = Character.ROLE_PRINCE
	var muslim := W.add_general(s, W.B, W.BASSA)
	var far := W.add_general(s, W.G, W.ORTO)
	var dead := W.add_general(s, W.A, W.ALTA)
	DynastyProcessor.kill(s, dead, s.year + 1, "vecchiaia", false)
	t.assert_eq(s.character_region(leader), W.ALTA, "il capo di ALPHA e' a ALTA")
	_order(t, s, ins, _person(leader))
	t.assert_eq(ins.mission["tipo"], AgentMissions.TRIAL, "anche il capo della propria fazione")
	_order(t, s, ins, _person(own))
	t.assert_eq(ins.mission["regione"], W.BASSA, "un generale della propria fazione, in una regione confinante")
	_order(t, s, ins, _person(prince))
	_refused(t, s, ins, _person(muslim), "cattolico")
	_refused(t, s, ins, _person(far), "portata")
	_refused(t, s, ins, _person(dead), "morto")
	_refused(t, s, ins, {"tipo": AgentMissions.TARGET_CHARACTER, "id": 9999}, "sconosciuto")
	var heir := s.heir_of(W.A)
	t.assert_true(heir != null)
	if heir != null:
		_refused(t, s, ins, _person(heir), "non e' un capo")
	var princess := s.character(W.agent_of(s, W.A, AgentState.PRINCESS).character_id)
	_refused(t, s, ins, _person(princess), "non e' un capo")
	# una fazione cattolica straniera si processa, se e' a portata
	ins.region = W.MEZZA
	var r := _order(t, s, ins, _person(far))
	t.assert_eq(r["regione"], W.ORTO)
	# anche in guerra o in alleanza: nessun vincolo diplomatico
	s.form_alliance(W.A, W.G)
	_order(t, s, ins, _person(far))


func test_bersagli_degli_agenti(t: TestContext) -> void:
	var s := W.world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var bishop := W.add_agent(s, W.A, W.BASSA, "BISHOP", 1)
	var spy := W.add_agent(s, W.A, W.BASSA, "SPY", 1)
	var shaman := W.add_agent(s, W.A, W.BASSA, "SHAMAN", 1)
	var mullah := W.add_agent(s, W.B, W.BASSA, "MULLAH", 1)
	var muslim_spy := W.add_agent(s, W.B, W.BASSA, "SPY", 1)
	var far := W.agent_of(s, W.G, AgentState.EMISSARY)
	var beta_emissary := W.agent_of(s, W.B, AgentState.EMISSARY)
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	_order(t, s, ins, _agent(bishop))
	_order(t, s, ins, _agent(spy))
	_order(t, s, ins, _agent(princess))
	_refused(t, s, ins, _agent(shaman), "cattolico")
	_refused(t, s, ins, _agent(mullah), "cattolico")
	_refused(t, s, ins, _agent(muslim_spy), "cattolico")
	_refused(t, s, ins, _agent(beta_emissary), "cattolico")
	_refused(t, s, ins, _agent(far), "portata")
	_refused(t, s, ins, _agent(ins), "se stesso")
	_refused(t, s, ins, {"tipo": AgentMissions.TARGET_AGENT, "id": 9999}, "sconosciuto")
	_refused(t, s, ins, {"tipo": "mostro", "id": 1}, "Tipo")
	_refused(t, s, ins, 5, "{")
	# la religione di un religioso viene da unit_prod (colonna 45) quando c'e'
	var unit := s.units.get_unit("Bishop")
	var raw := unit.raw
	if raw.size() <= ReligionProcessor.COL_CONVERSION:
		raw.resize(ReligionProcessor.COL_CONVERSION + 1)
	raw[ReligionProcessor.COL_CONVERSION] = "ORTHODOX(2)"
	unit.raw = raw
	_refused(t, s, ins, _agent(bishop), "cattolico")


func test_solo_gli_inquisitori_ordinano_un_processo(t: TestContext) -> void:
	var s := W.world()
	var emissary := W.agent_of(s, W.A, AgentState.EMISSARY)
	var bishop := W.add_agent(s, W.A, W.BASSA, "BISHOP", 1)
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 1)
	_refused(t, s, emissary, _agent(bishop), "non puo' svolgere")
	_refused(t, s, bishop, _agent(ins), "non puo' svolgere")
	var r := GameCommands.order_mission(s, W.B, ins.id, AgentMissions.TRIAL, _agent(bishop))
	t.assert_false(bool(r["ok"]), "l'inquisitore e' di ALPHA")
	var grand := W.add_agent(s, W.A, W.ALTA, "GRAND_INQUISITOR", 1)
	_order(t, s, grand, _agent(bishop))


# --- ordine, probabilita', anteprima ------------------------------------------------------------------------------


func test_ordine_e_avvicinamento(t: TestContext) -> void:
	var s := W.world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.BASSA)
	var r := _order(t, s, ins, {"tipo": "personaggio", "id": float(general.id)})
	t.assert_eq(r["tipo"], AgentMissions.TRIAL)
	t.assert_eq(r["bersaglio"], _person(general))
	t.assert_eq(typeof((ins.mission["bersaglio"] as Dictionary)["id"]), TYPE_INT, "il bersaglio e' normalizzato")
	t.assert_eq(r["regione"], W.BASSA)
	t.assert_eq(r["prezzo"], 0)
	t.assert_true(bool(ins.mission["avvicinamento"]))
	t.assert_eq(ins.path, PackedStringArray([W.BASSA]))
	t.assert_eq(ins.region, W.ALTA, "l'ordine non muove")
	var here := W.add_general(s, W.A, W.ALTA)
	_order(t, s, ins, _person(here))
	t.assert_false(bool(ins.mission["avvicinamento"]))
	t.assert_true(ins.path.is_empty(), "stessa regione: nessun avvicinamento")
	t.assert_true(bool(GameCommands.cancel_mission(s, W.A, ins.id)["ok"]))
	t.assert_false(ins.has_mission())


func test_probabilita_del_processo(t: TestContext) -> void:
	var s := W.world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.ALTA)
	general.piety = 0
	var rr := s.rules.religion
	var p0 := AgentMissions.chance(s, ins, AgentMissions.TRIAL, _person(general))
	t.assert_true(_near(p0, 0.7), "pieta' 0: 0,3 + 0,08 x 5 = %s" % str(p0))
	t.assert_true(_near(p0, rr.trial_chance(general.effective(Character.ATTR_PIETY, s.rules, s.campaign))), "con la pieta' efficace")
	general.piety = 5
	t.assert_true(_near(AgentMissions.chance(s, ins, AgentMissions.TRIAL, _person(general)), 0.3), "pieta' 5: la base")
	general.piety = 10
	t.assert_true(_near(AgentMissions.chance(s, ins, AgentMissions.TRIAL, _person(general)), 0.05), "limite inferiore")
	t.assert_true(_near(AgentMissions.trial_chance(s, _person(general)), 0.05))
	var bishop := W.add_agent(s, W.A, W.BASSA, "BISHOP", 1)
	t.assert_true(_near(AgentMissions.chance(s, ins, AgentMissions.TRIAL, _agent(bishop)), rr.trial_chance(rr.agent_piety)), "un agente ha la pieta' di un agente")
	rr.agent_piety = 0
	t.assert_true(_near(AgentMissions.chance(s, ins, AgentMissions.TRIAL, _agent(bishop)), 0.7))
	t.assert_eq(AgentMissions.trial_chance(s, {"tipo": "personaggio", "id": 9999}), 0.0, "bersaglio sconosciuto")
	t.assert_eq(AgentMissions.trial_chance(s, {"tipo": "agente", "id": 9999}), 0.0)
	var r := _order(t, s, ins, _person(general))
	t.assert_true(_near(float(r["probabilita"]), 0.05), "l'ordine riporta la probabilita'")


func test_anteprima_delle_missioni(t: TestContext) -> void:
	var s := W.world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var bishop := W.add_agent(s, W.A, W.BASSA, "BISHOP", 1)
	var leader := s.leader_of(W.A)
	var muslim := W.add_general(s, W.B, W.ALTA)
	var res := GameCommands.mission_options(s, W.A, ins.id)
	t.assert_true(bool(res["ok"]), str(res["errore"]))
	var list: Array = res["missioni"]
	t.assert_true(list.size() >= 3, "capo, agenti e generali a portata: %d" % list.size())
	var found_leader := false
	var found_bishop := false
	for item in list:
		var o: Dictionary = item
		t.assert_eq(o["tipo"], AgentMissions.TRIAL)
		t.assert_eq(o["prezzo"], 0)
		t.assert_eq(o["gradino"], -1)
		t.assert_true(float(o["probabilita"]) >= 0.05 and float(o["probabilita"]) <= 0.9)
		t.assert_true(str(o["etichetta"]) != "")
		t.assert_true(bool(o["tesoro_sufficiente"]))
		var target: Dictionary = o["bersaglio"]
		t.assert_true(target != _person(muslim), "i non cattolici non si offrono")
		if target == _person(leader):
			found_leader = true
		if target == _agent(bishop):
			found_bishop = true
		t.assert_true(target != _agent(ins), "mai se stesso")
		var order := GameCommands.order_mission(s, W.A, ins.id, str(o["tipo"]), o["bersaglio"])
		t.assert_true(bool(order["ok"]), "ogni voce dell'anteprima si ordina: %s" % str(order["errore"]))
	t.assert_true(found_leader, "il capo della propria fazione")
	t.assert_true(found_bishop, "un agente cattolico vicino")
	var emissary := W.agent_of(s, W.A, AgentState.EMISSARY)
	for item in (GameCommands.mission_options(s, W.A, emissary.id)["missioni"] as Array):
		var o: Dictionary = item
		t.assert_true(o["tipo"] != AgentMissions.TRIAL, "un emissario non processa")


# --- risoluzione ----------------------------------------------------------------------------------------------


func test_processo_riuscito_di_un_generale(t: TestContext) -> void:
	var s := W.world()
	_certain(s)
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.ALTA)
	general.piety = 2
	_order(t, s, ins, _person(general))
	AgentProcessor.process_year(s)
	t.assert_false(general.alive, "sul rogo")
	t.assert_eq(general.death_cause, "rogo")
	t.assert_eq(general.death_year, s.year + 1)
	var events := W.events_of(s, GameState.EV_INQUISITION)
	t.assert_eq(events.size(), 1)
	t.assert_eq(W.events_of(s, GameState.EV_INQUISITION_FAILED).size(), 0)
	t.assert_eq(W.events_of(s, GameState.EV_ASSASSINATION).size(), 0, "non e' un assassinio")
	if events.size() == 1:
		var e := events[0]
		t.assert_eq(e["fazione"], W.A)
		t.assert_eq(e["regione"], W.ALTA)
		t.assert_eq(e["agente"], ins.id)
		t.assert_eq(e["tipo_agente"], "INQUISITOR")
		t.assert_eq(e["bersaglio_tipo"], AgentMissions.TARGET_CHARACTER)
		t.assert_eq(e["bersaglio"], general.id)
		t.assert_eq(e["nome"], general.full_name())
		t.assert_eq(e["con"], W.A, "anche della propria fazione")
		t.assert_eq(e["pieta"], general.effective(Character.ATTR_PIETY, s.rules, s.campaign))
		t.assert_eq(float(e["probabilita"]), 1.0)
		t.assert_true(str(e["testo"]) != "")
	t.assert_false(ins.has_mission(), "missione conclusa")
	t.assert_eq(ins.valour, 3 + s.rules.agents.valour_growth, "il successo fa crescere il valore")
	t.assert_true(s.agent(ins.id) != null, "l'inquisitore resta")


func test_processo_fallito(t: TestContext) -> void:
	var s := W.world()
	_never(s)
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.ALTA)
	_order(t, s, ins, _person(general))
	var rng_before := s.rng.state
	AgentProcessor.process_year(s)
	t.assert_true(general.alive)
	var events := W.events_of(s, GameState.EV_INQUISITION_FAILED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(W.events_of(s, GameState.EV_INQUISITION).size(), 0)
	if events.size() == 1:
		t.assert_eq(events[0]["bersaglio"], general.id)
		t.assert_eq(float(events[0]["probabilita"]), 0.0)
		t.assert_true(str(events[0]["testo"]) != "")
	t.assert_eq(ins.valour, 3, "nessuna crescita")
	t.assert_true(s.agent(ins.id) != null, "e l'inquisitore non rischia nulla")
	t.assert_false(ins.has_mission())
	t.assert_eq(s.rng.state, rng_before, "con probabilita' zero non si sorteggia")


func test_un_solo_sorteggio_per_processo(t: TestContext) -> void:
	var s := W.world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.ALTA)
	general.piety = 5
	_order(t, s, ins, _person(general))
	var reference := RandomNumberGenerator.new()
	reference.state = s.rng.state
	var expected := reference.randf() < 0.3
	AgentProcessor.process_year(s)
	t.assert_eq(not general.alive, expected, "esito uguale al primo numero del generatore")
	t.assert_eq(s.rng.state, reference.state, "e un solo numero estratto")


func test_processo_al_capo_con_successione_normale(t: TestContext) -> void:
	var s := W.world()
	_certain(s)
	var leader := s.leader_of(W.A)
	var ins := W.add_agent(s, W.A, s.character_region(leader), "GRAND_INQUISITOR", 2)
	_order(t, s, ins, _person(leader))
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0, "nessuna anomalia dei dati: %s" % str(res["errori"]))
	t.assert_false(leader.alive)
	t.assert_eq(leader.death_cause, "rogo")
	var next := s.leader_of(W.A)
	t.assert_true(next != null, "ALPHA ha un nuovo capo")
	if next != null:
		t.assert_true(next != leader)
		t.assert_eq(next.role, Character.ROLE_LEADER)
	t.assert_true(s.faction(W.A).alive)
	t.assert_eq(W.events_of(s, GameState.EV_INQUISITION).size(), 1)


func test_processo_a_un_agente_cattolico(t: TestContext) -> void:
	var s := W.world()
	_certain(s)
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var bishop := W.add_agent(s, W.A, W.ALTA, "BISHOP", 1)
	_order(t, s, ins, _agent(bishop))
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(bishop.id) == null, "l'agente e' morto")
	var events := W.events_of(s, GameState.EV_INQUISITION)
	t.assert_eq(events.size(), 1)
	if events.size() == 1:
		t.assert_eq(events[0]["bersaglio_tipo"], AgentMissions.TARGET_AGENT)
		t.assert_eq(events[0]["bersaglio"], bishop.id)
		t.assert_eq(events[0]["con"], W.A)
	# una principessa porta via con se' il personaggio
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var character := s.character(princess.character_id)
	_order(t, s, ins, _agent(princess))
	s.events.clear()
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(princess.id) == null)
	t.assert_false(character.alive, "e il suo personaggio")
	t.assert_eq(character.death_cause, "rogo")


func test_l_inquisitore_raggiunge_il_bersaglio_e_lo_processa(t: TestContext) -> void:
	var s := W.world()
	_certain(s)
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.BASSA)
	_order(t, s, ins, _person(general))
	AgentProcessor.process_year(s)
	t.assert_eq(ins.region, W.BASSA, "e' andato dal bersaglio")
	t.assert_true(ins.path.is_empty())
	t.assert_false(general.alive)
	var events := W.events_of(s, GameState.EV_INQUISITION)
	t.assert_eq(events.size(), 1)
	if events.size() == 1:
		t.assert_eq(events[0]["regione"], W.BASSA)


func test_il_bersaglio_sparito_fa_cadere_la_missione(t: TestContext) -> void:
	var s := W.world()
	_certain(s)
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.BASSA)
	_order(t, s, ins, _person(general))
	DynastyProcessor.kill(s, general, s.year + 1, "vecchiaia", false)
	AgentProcessor.process_year(s)
	var failed := W.events_of(s, GameState.EV_MISSION_FAILED)
	t.assert_eq(failed.size(), 1)
	if failed.size() == 1:
		t.assert_eq(failed[0]["missione"], AgentMissions.TRIAL)
	t.assert_eq(W.events_of(s, GameState.EV_INQUISITION).size(), 0)
	t.assert_false(ins.has_mission())
	t.assert_true(ins.path.is_empty())
	# un bersaglio che non e' piu' cattolico (cambio di religione della fazione) fa cadere la missione
	var other := W.add_general(s, W.A, W.ALTA)
	_order(t, s, ins, _person(other))
	s.campaign.faction(W.A).religion = "REL_ISLAMIC"
	s.events.clear()
	AgentProcessor.process_year(s)
	t.assert_true(other.alive)
	t.assert_eq(W.events_of(s, GameState.EV_MISSION_FAILED).size(), 1)


func test_un_processo_in_corso_tiene_attivo_l_inquisitore(t: TestContext) -> void:
	var s := W.world()
	_certain(s)
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.ALTA)
	var alta := s.province(W.ALTA)
	t.assert_eq(ReligionProcessor.inquisitor_term(s, alta), -s.rules.religion.inactive_malus, "senza eretici ne' processi")
	_order(t, s, ins, _person(general))
	t.assert_eq(ReligionProcessor.inquisitor_term(s, alta), 0, "con un processo in corso")
	AgentProcessor.process_year(s)
	t.assert_eq(ReligionProcessor.inquisitor_term(s, alta), -s.rules.religion.inactive_malus, "concluso, e' di nuovo inattivo")


func test_il_processo_in_un_salvataggio(t: TestContext) -> void:
	var s := W.world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.BASSA)
	_order(t, s, ins, _person(general))
	var parsed: Variant = JSON.parse_string(SaveGame.to_json(s))
	var data: Dictionary = parsed
	var r := SaveGame.from_dict(data, s.campaign, s.units, s.buildings, W.quiet_rules(), s.heroes)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_eq(back.agent(ins.id).mission, ins.mission, "la missione sopravvive al salvataggio")
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s))
	AgentProcessor.process_year(s)
	AgentProcessor.process_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "stesso esito dopo il ricarico")
