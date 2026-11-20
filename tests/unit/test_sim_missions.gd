extends RefCounted
## Test delle missioni degli agenti (fase 5a): validazione dei bersagli, anteprima (mission_options), probabilita e
## prezzi (PROVVISORI), risoluzione di alleanze, tregue, matrimoni, spose generali, corruzione e assassinii, comandi
## GameCommands (order_mission, cancel_mission, mission_options, bribe_price). Mondo di prova: vedi agent_world.gd.
## Per isolare le regole le probabilita' si portano a 0 o 1 (W.always_accept, W.never_accept, W.kill_always...).

const W := preload("res://tests/unit/agent_world.gd")


func _end_year(t: TestContext, s: GameState) -> void:
	var r := TurnProcessor.end_year(s)
	t.assert_true(bool(r["ok"]), "fine anno")
	t.assert_eq((r["errori"] as Array).size(), 0, "nessuna anomalia dei dati: %s" % str(r["errori"]))


func _order(t: TestContext, s: GameState, agent: AgentState, kind: String, target: Variant) -> Dictionary:
	var r := GameCommands.order_mission(s, agent.faction, agent.id, kind, target)
	t.assert_true(bool(r["ok"]), "ordine %s: %s" % [kind, str(r["errore"])])
	return r


func _refused(t: TestContext, s: GameState, agent: AgentState, kind: String, target: Variant, needle: String = "") -> void:
	var before := agent.mission.duplicate(true)
	var r := GameCommands.order_mission(s, agent.faction, agent.id, kind, target)
	t.assert_false(bool(r["ok"]), "%s dovrebbe essere rifiutato" % kind)
	t.assert_true(str(r["errore"]) != "", "%s: serve un motivo" % kind)
	if needle != "":
		t.assert_true(str(r["errore"]).find(needle) >= 0, "%s: il motivo dice '%s' (e' '%s')" % [kind, needle, str(r["errore"])])
	t.assert_eq(agent.mission, before, "un ordine rifiutato non cambia l'agente")


# --- catalogo delle missioni ---------------------------------------------------------------------------------


func test_missioni_per_tipo_di_agente(t: TestContext) -> void:
	t.assert_eq(AgentMissions.missions_for(AgentState.EMISSARY), PackedStringArray([AgentMissions.ALLIANCE, AgentMissions.TRUCE, AgentMissions.BRIBE]))
	t.assert_eq(AgentMissions.missions_for(AgentState.PRINCESS), PackedStringArray([AgentMissions.MARRIAGE, AgentMissions.BRIDE]))
	t.assert_eq(AgentMissions.missions_for(AgentState.ASSASSIN), PackedStringArray([AgentMissions.ASSASSINATE]))
	t.assert_eq(AgentMissions.missions_for(AgentState.SPY).size(), 4, "dal 18/11/2026 la spia ha le sue missioni (test_sim_spie)")
	t.assert_true(AgentMissions.missions_for("BISHOP").is_empty(), "i religiosi arrivano con la fase 5b")
	t.assert_eq(AgentMissions.ALLIANCE, "alleanza")
	t.assert_eq(AgentMissions.ASSASSINATE, "assassinio")


func test_il_bersaglio_si_normalizza(t: TestContext) -> void:
	t.assert_eq(AgentMissions.normalize_target(AgentMissions.ALLIANCE, " fn_beta "), "FN_BETA")
	t.assert_eq(AgentMissions.normalize_target(AgentMissions.BRIBE, 4.0), 4)
	t.assert_eq(AgentMissions.normalize_target(AgentMissions.BRIDE, 7), 7)
	var d: Variant = AgentMissions.normalize_target(AgentMissions.ASSASSINATE, {"tipo": "agente", "id": 3.0})
	t.assert_eq(d, {"tipo": "agente", "id": 3})


# --- validazione: proposte ----------------------------------------------------------------------------------------


func test_alleanza_validazione(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	_refused(t, s, e, AgentMissions.ALLIANCE, W.A, "propria")
	_refused(t, s, e, AgentMissions.ALLIANCE, GameState.REBEL)
	_refused(t, s, e, AgentMissions.ALLIANCE, "FN_NESSUNA", "sconosciuta")
	_refused(t, s, e, AgentMissions.ALLIANCE, 12, "fazione")
	_refused(t, s, e, AgentMissions.ALLIANCE, W.G, "Nessuna regione")
	_refused(t, s, e, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": 1}, "non puo'")
	s.faction(W.G).alive = false
	_refused(t, s, e, AgentMissions.ALLIANCE, W.G, "sconosciuta o non attiva")
	s.declare_war(W.A, W.B)
	_refused(t, s, e, AgentMissions.ALLIANCE, W.B, "neutrale")
	s.end_war(W.A, W.B)
	s.form_alliance(W.A, W.B)
	_refused(t, s, e, AgentMissions.ALLIANCE, W.B, "neutrale")
	s.break_alliance(W.A, W.B)
	s.make_truce(W.A, W.B, 1010)
	_refused(t, s, e, AgentMissions.ALLIANCE, W.B, "neutrale")
	s.break_truce(W.A, W.B)
	# fase 7b: un'IA puo' proporre a un giocatore (nasce una proposta in attesa); due giocatori non trattano tra loro
	s.faction(W.B).is_player = true
	_order(t, s, e, AgentMissions.ALLIANCE, W.B)
	s.faction(W.A).is_player = true
	_refused(t, s, e, AgentMissions.ALLIANCE, W.B, "giocatori")
	s.faction(W.A).is_player = false
	s.faction(W.B).is_player = false
	_order(t, s, e, AgentMissions.ALLIANCE, W.B)


func test_tregua_validazione(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	_refused(t, s, e, AgentMissions.TRUCE, W.B, "in guerra")
	s.declare_war(W.A, W.B)
	_order(t, s, e, AgentMissions.TRUCE, W.B)
	s.end_war(W.A, W.B)
	_refused(t, s, e, AgentMissions.TRUCE, W.B, "in guerra")
	s.declare_war(W.A, W.G)
	_refused(t, s, e, AgentMissions.TRUCE, W.G, "Nessuna regione")
	# un esercito della fazione in guerra nella portata dell'agente basta
	var scout := s.create_army(W.G, W.ALTA, false)
	scout.stacks.append(UnitStack.new("Spearmen", 10, 0))
	_order(t, s, e, AgentMissions.TRUCE, W.G)


func test_matrimonio_validazione(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	_refused(t, s, e, AgentMissions.MARRIAGE, W.B, "non puo'")
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	_refused(t, s, princess, AgentMissions.MARRIAGE, W.B, "Nessuna regione")
	princess.region = W.BASSA
	s.declare_war(W.A, W.B)
	_refused(t, s, princess, AgentMissions.MARRIAGE, W.B, "guerra")
	s.end_war(W.A, W.B)
	_order(t, s, princess, AgentMissions.MARRIAGE, W.B)
	var young := W.agent_of(s, W.B, AgentState.PRINCESS)
	_refused(t, s, young, AgentMissions.MARRIAGE, W.A, "giovane")
	var c := s.character(princess.character_id)
	c.alive = false
	_refused(t, s, princess, AgentMissions.MARRIAGE, W.B, "non e' piu' in gioco")


func test_gli_ordini_di_agenti_altrui_o_sconosciuti_sono_rifiutati(t: TestContext) -> void:
	var s := W.world()
	var mine := W.agent_of(s, W.A, AgentState.EMISSARY)
	var theirs := W.agent_of(s, W.B, AgentState.EMISSARY)
	t.assert_false(bool(GameCommands.order_mission(s, W.A, theirs.id, AgentMissions.ALLIANCE, W.G)["ok"]))
	t.assert_false(bool(GameCommands.order_mission(s, W.A, 9999, AgentMissions.ALLIANCE, W.B)["ok"]))
	t.assert_false(bool(GameCommands.order_mission(s, "FN_NESSUNA", mine.id, AgentMissions.ALLIANCE, W.B)["ok"]))
	t.assert_false(bool(GameCommands.cancel_mission(s, W.B, mine.id)["ok"]))
	t.assert_false(bool(GameCommands.mission_options(s, W.B, mine.id)["ok"]))
	t.assert_true(mine.mission.is_empty() and theirs.mission.is_empty())


# --- ordine, sostituzione, annullamento --------------------------------------------------------------------------------


func test_l_ordine_imposta_la_missione_e_l_avvicinamento(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var r := _order(t, s, e, AgentMissions.ALLIANCE, "fn_beta")
	t.assert_eq(r["tipo"], AgentMissions.ALLIANCE)
	t.assert_eq(r["bersaglio"], W.B, "forma canonica")
	t.assert_eq(r["regione"], W.MEZZA)
	t.assert_eq(r["prezzo"], 0)
	t.assert_eq(float(r["probabilita"]), DiplomacyProcessor.acceptance(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.B, e.valour))
	t.assert_eq(e.mission["tipo"], AgentMissions.ALLIANCE)
	t.assert_true(bool(e.mission["avvicinamento"]))
	t.assert_eq(e.path, PackedStringArray([W.MEZZA]))
	t.assert_eq(e.region, W.BASSA, "l'ordine non muove")


func test_senza_avvicinamento_se_il_bersaglio_e_nella_stessa_regione(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	e.region = W.MEZZA
	_order(t, s, e, AgentMissions.ALLIANCE, W.B)
	t.assert_false(bool(e.mission["avvicinamento"]))
	t.assert_true(e.path.is_empty())


func test_un_nuovo_ordine_sostituisce_il_precedente(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	_order(t, s, e, AgentMissions.ALLIANCE, W.B)
	t.assert_eq(e.mission["tipo"], AgentMissions.ALLIANCE)
	s.declare_war(W.A, W.B)
	_order(t, s, e, AgentMissions.TRUCE, W.B)
	t.assert_eq(e.mission["tipo"], AgentMissions.TRUCE, "una missione per agente")


func test_cancel_mission(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	t.assert_false(bool(GameCommands.cancel_mission(s, W.A, e.id)["ok"]), "nessuna missione da annullare")
	_order(t, s, e, AgentMissions.ALLIANCE, W.B)
	t.assert_true(bool(GameCommands.cancel_mission(s, W.A, e.id)["ok"]))
	t.assert_false(e.has_mission())
	t.assert_true(e.path.is_empty(), "si ferma anche l'avvicinamento")
	e.region = W.MEZZA
	_order(t, s, e, AgentMissions.ALLIANCE, W.B)
	t.assert_true(bool(GameCommands.cancel_mission(s, W.A, e.id)["ok"]))
	t.assert_eq(e.region, W.MEZZA)


# --- risoluzione: alleanza e tregua ---------------------------------------------------------------------------------------


func test_alleanza_accettata(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var valour := e.valour
	_order(t, s, e, AgentMissions.ALLIANCE, W.B)
	AgentProcessor.process_year(s)
	t.assert_true(s.is_allied(W.A, W.B))
	t.assert_eq(e.region, W.MEZZA, "l'emissario e' andato dal destinatario")
	t.assert_false(e.has_mission(), "missione conclusa")
	t.assert_eq(e.valour, valour + s.rules.agents.valour_growth, "il successo fa crescere il valore")
	var events := W.events_of(s, GameState.EV_ALLIANCE_FORMED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["fazione"], W.A)
	t.assert_eq(events[0]["con"], W.B)
	t.assert_eq(events[0]["agente"], e.id)
	t.assert_true(str(events[0]["testo"]) != "")


func test_alleanza_rifiutata(t: TestContext) -> void:
	var s := W.world()
	W.never_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var valour := e.valour
	_order(t, s, e, AgentMissions.ALLIANCE, W.B)
	AgentProcessor.process_year(s)
	t.assert_false(s.is_allied(W.A, W.B))
	t.assert_false(e.has_mission(), "la missione finisce comunque")
	t.assert_eq(e.valour, valour)
	t.assert_true(s.agent(e.id) != null, "l'emissario sopravvive")
	var events := W.events_of(s, GameState.EV_PROPOSAL_REFUSED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["missione"], AgentMissions.ALLIANCE)
	t.assert_eq(events[0]["con"], W.B)


func test_tregua_accettata(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	s.declare_war(W.A, W.B)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	_order(t, s, e, AgentMissions.TRUCE, W.B)
	AgentProcessor.process_year(s)
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_TRUCE)
	t.assert_false(s.at_war(W.A, W.B))
	t.assert_eq(s.truce_until(W.A, W.B), s.year + 1 + s.rules.diplomacy.truce_years)
	var events := W.events_of(s, GameState.EV_TRUCE)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["fino_al"], s.truce_until(W.A, W.B))


func test_tregua_rifiutata_lascia_la_guerra(t: TestContext) -> void:
	var s := W.world()
	W.never_accept(s)
	s.declare_war(W.A, W.B)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	_order(t, s, e, AgentMissions.TRUCE, W.B)
	AgentProcessor.process_year(s)
	t.assert_true(s.at_war(W.A, W.B))
	t.assert_eq(W.events_of(s, GameState.EV_PROPOSAL_REFUSED).size(), 1)


func test_la_missione_cade_se_il_bersaglio_non_e_piu_valido(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	_order(t, s, e, AgentMissions.ALLIANCE, W.B)
	s.declare_war(W.A, W.B)       # nel frattempo la coppia e' in guerra: non e' piu' neutrale
	AgentProcessor.process_year(s)
	t.assert_false(s.is_allied(W.A, W.B))
	t.assert_false(e.has_mission())
	t.assert_true(e.path.is_empty() or e.region == W.MEZZA)
	var events := W.events_of(s, GameState.EV_MISSION_FAILED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["missione"], AgentMissions.ALLIANCE)
	t.assert_true(str(events[0]["motivo"]) != "")


func test_avvicinamento_e_risoluzione_nello_stesso_fine_anno(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	_order(t, s, e, AgentMissions.ALLIANCE, W.B)
	_end_year(t, s)
	t.assert_true(s.is_allied(W.A, W.B), "avvicinamento e risoluzione nello stesso fine anno")
	t.assert_eq(e.region, W.MEZZA)


# --- risoluzione: matrimonio -----------------------------------------------------------------------------------------------


func test_matrimonio_accettato_crea_un_alleanza_e_toglie_la_principessa(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var character_id := princess.character_id
	princess.region = W.BASSA
	_order(t, s, princess, AgentMissions.MARRIAGE, W.B)
	AgentProcessor.process_year(s)
	t.assert_true(s.is_allied(W.A, W.B), "il matrimonio porta all'alleanza")
	t.assert_true(s.agent(princess.id) == null, "la principessa lascia la partita")
	var c := s.character(character_id)
	t.assert_false(c.alive)
	t.assert_eq(c.death_cause, "matrimonio")
	var events := W.events_of(s, GameState.EV_MARRIAGE)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["con"], W.B)
	t.assert_eq(events[0]["personaggio"], character_id)
	t.assert_true(bool(events[0]["nuova_alleanza"]))


func test_matrimonio_con_un_alleato_non_crea_una_nuova_alleanza(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	s.form_alliance(W.A, W.B)
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	princess.region = W.BASSA
	_order(t, s, princess, AgentMissions.MARRIAGE, W.B)
	AgentProcessor.process_year(s)
	t.assert_false(bool(W.events_of(s, GameState.EV_MARRIAGE)[0]["nuova_alleanza"]))
	t.assert_true(s.is_allied(W.A, W.B))


func test_matrimonio_rifiutato_tiene_la_principessa(t: TestContext) -> void:
	var s := W.world()
	W.never_accept(s)
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	princess.region = W.BASSA
	_order(t, s, princess, AgentMissions.MARRIAGE, W.B)
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(princess.id) != null)
	t.assert_true(s.character(princess.character_id).alive)
	t.assert_false(s.is_allied(W.A, W.B))
	t.assert_eq(W.events_of(s, GameState.EV_PROPOSAL_REFUSED).size(), 1)


# --- risoluzione: sposa generale -----------------------------------------------------------------------------------------------


func test_sposa_generale(t: TestContext) -> void:
	var s := W.world()
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var character_id := princess.character_id
	var general := W.add_general(s, W.A, W.ALTA)
	general.loyalty = 5
	var r := _order(t, s, princess, AgentMissions.BRIDE, general.id)
	t.assert_eq(r["regione"], W.ALTA)
	t.assert_eq(float(r["probabilita"]), 1.0, "senza sorteggi")
	AgentProcessor.process_year(s)
	t.assert_eq(general.loyalty, 5 + s.rules.agents.marriage_loyalty_bonus)
	t.assert_true(general.royal_blood, "entra nella linea di sangue")
	t.assert_eq(general.role, Character.ROLE_PRINCE)
	t.assert_true(s.agent(princess.id) == null)
	t.assert_false(s.character(character_id).alive)
	var events := W.events_of(s, GameState.EV_MARRIAGE)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["personaggio"], general.id)
	t.assert_eq(events[0]["con"], "")


func test_sposa_generale_lealta_limitata_al_massimo_e_avvicinamento(t: TestContext) -> void:
	var s := W.world()
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var general := W.add_general(s, W.A, W.BASSA)
	general.loyalty = s.rules.dynasty.max_attribute
	_order(t, s, princess, AgentMissions.BRIDE, general.id)
	t.assert_eq(princess.path, PackedStringArray([W.BASSA]))
	AgentProcessor.process_year(s)
	t.assert_eq(general.loyalty, s.rules.dynasty.max_attribute)
	t.assert_eq(W.events_of(s, GameState.EV_MARRIAGE).size(), 1)
	t.assert_true(s.agent(princess.id) == null)


func test_sposa_generale_validazione(t: TestContext) -> void:
	var s := W.world()
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var ok := W.add_general(s, W.A, W.ALTA)
	var minor := W.add_general(s, W.A, W.ALTA)
	minor.birth_year = s.year - 5
	var woman := W.add_general(s, W.A, W.ALTA)
	woman.male = false
	var stranger := W.add_general(s, W.B, W.ALTA)
	var far := W.add_general(s, W.A, W.ALTA)
	far.region = W.ORTO
	var dead := W.add_general(s, W.A, W.ALTA)
	dead.alive = false
	_refused(t, s, princess, AgentMissions.BRIDE, minor.id, "minorenne")
	_refused(t, s, princess, AgentMissions.BRIDE, woman.id, "generale")
	_refused(t, s, princess, AgentMissions.BRIDE, stranger.id, "fazione")
	_refused(t, s, princess, AgentMissions.BRIDE, far.id, "portata")
	_refused(t, s, princess, AgentMissions.BRIDE, dead.id, "sconosciuto")
	_refused(t, s, princess, AgentMissions.BRIDE, 9999, "sconosciuto")
	_refused(t, s, princess, AgentMissions.BRIDE, s.leader_of(W.A).id, "non e' un generale")
	_refused(t, s, princess, AgentMissions.BRIDE, "abc", "generale")
	_order(t, s, princess, AgentMissions.BRIDE, ok.id)
	var young := W.agent_of(s, W.B, AgentState.PRINCESS)
	var local := W.add_general(s, W.B, W.MEZZA)
	_refused(t, s, young, AgentMissions.BRIDE, local.id, "giovane")


# --- corruzione ---------------------------------------------------------------------------------------------------------------------


func _bribe_price_by_hand(s: GameState, army: Army) -> int:
	var total := 0.0
	for st in army.stacks:
		var u := s.units.get_unit(st.unit_id)
		total += float(u.cost) * float(st.men) / float(maxi(1, u.men))
	var c := s.commander_of(army.id)
	var loyalty := 0
	var command := 0
	if c != null:
		loyalty = c.effective(Character.ATTR_LOYALTY, s.rules, s.campaign)
		command = c.stars(s.rules, s.campaign)
	return roundi(total * s.rules.agents.bribe_price_k * (1.0 + float(loyalty) / 10.0) * (1.0 + float(command) / 10.0))


func test_prezzo_della_corruzione(t: TestContext) -> void:
	var s := W.world()
	var army := W.general_army(s, W.B, W.MEZZA, 60)
	var price := AgentMissions.bribe_price(s, army)
	t.assert_eq(price, _bribe_price_by_hand(s, army))
	t.assert_true(price > 0)
	var c := s.commander_of(army.id)
	c.loyalty += 2
	t.assert_true(AgentMissions.bribe_price(s, army) > price, "un comandante piu' leale costa di piu'")
	var small := W.general_army(s, W.B, W.MEZZA, 30)
	small.stacks[0].men = 30
	t.assert_true(AgentMissions.bribe_price(s, small) < AgentMissions.bribe_price(s, army), "meno uomini costano meno")
	var unled := s.create_army(W.G, W.ORTO, false)
	unled.stacks.append(UnitStack.new("Spearmen", 100, 0))
	t.assert_eq(AgentMissions.bribe_price(s, unled), roundi(float(s.units.get_unit("Spearmen").cost) * s.rules.agents.bribe_price_k), "senza comandante: lealta' e comando 0")


func test_probabilita_della_corruzione(t: TestContext) -> void:
	var s := W.world()
	var ar := s.rules.agents
	var army := W.general_army(s, W.B, W.MEZZA, 60)
	var loyalty := s.commander_of(army.id).effective(Character.ATTR_LOYALTY, s.rules, s.campaign)
	var expected := clampf(ar.bribe_base - ar.bribe_k_loyalty * float(loyalty) + ar.bribe_k_valour * 3.0, ar.bribe_p_min, ar.bribe_p_max)
	t.assert_true(absf(AgentMissions.bribe_chance(s, army, 3) - expected) < 0.000001)
	t.assert_true(AgentMissions.bribe_chance(s, army, 9) >= AgentMissions.bribe_chance(s, army, 1), "il valore aiuta")
	s.commander_of(army.id).loyalty = 10
	t.assert_true(AgentMissions.bribe_chance(s, army, 0) >= ar.bribe_p_min, "mai sotto il minimo")


func test_comando_bribe_price(t: TestContext) -> void:
	var s := W.world()
	var army := W.general_army(s, W.B, W.MEZZA, 60)
	var r := GameCommands.bribe_price(s, army.id)
	t.assert_true(bool(r["ok"]))
	t.assert_eq(r["prezzo"], AgentMissions.bribe_price(s, army))
	t.assert_eq(r["comandante"], s.commander_of(army.id).id)
	t.assert_true(bool(r["corruttibile"]))
	var leader_army := W.land_army(s, W.B, W.MEZZA)
	if s.commander_of(leader_army.id) != null and s.commander_of(leader_army.id).role == Character.ROLE_LEADER:
		var l := GameCommands.bribe_price(s, leader_army.id)
		t.assert_true(bool(l["ok"]))
		t.assert_false(bool(l["corruttibile"]), "l'esercito del capo non si compra")
		t.assert_true(str(l["motivo"]) != "")
	var fleet := W.fleet(s, W.B, W.SUD)
	t.assert_false(bool(GameCommands.bribe_price(s, fleet.id)["corruttibile"]), "le flotte no")
	t.assert_false(bool(GameCommands.bribe_price(s, 9999)["ok"]))


func test_corruzione_validazione(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var target := W.general_army(s, W.B, W.MEZZA, 60)
	var own := W.general_army(s, W.A, W.BASSA, 40)
	var far := W.general_army(s, W.G, W.ORTO, 40)
	var fleet := W.fleet(s, W.B, W.SUD)
	var leader_army := W.land_army(s, W.B, W.MEZZA)
	_refused(t, s, e, AgentMissions.BRIBE, own.id, "tua fazione")
	_refused(t, s, e, AgentMissions.BRIBE, far.id, "portata")
	_refused(t, s, e, AgentMissions.BRIBE, fleet.id, "flotte")
	_refused(t, s, e, AgentMissions.BRIBE, 9999, "sconosciuto")
	_refused(t, s, e, AgentMissions.BRIBE, "x", "esercito")
	if s.commander_of(leader_army.id) != null and s.commander_of(leader_army.id).role == Character.ROLE_LEADER:
		_refused(t, s, e, AgentMissions.BRIBE, leader_army.id, "capo")
	var heir_army := W.general_army(s, W.B, W.MEZZA, 30)
	s.commander_of(heir_army.id).role = Character.ROLE_HEIR
	_refused(t, s, e, AgentMissions.BRIBE, heir_army.id, "erede")
	s.form_alliance(W.A, W.B)
	_refused(t, s, e, AgentMissions.BRIBE, target.id, "alleato")
	s.break_alliance(W.A, W.B)
	var r := _order(t, s, e, AgentMissions.BRIBE, target.id)
	t.assert_eq(r["prezzo"], AgentMissions.bribe_price(s, target))
	t.assert_eq(r["regione"], W.MEZZA)


func test_corruzione_accettata(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var target := W.general_army(s, W.B, W.MEZZA, 60)
	var commander := s.commander_of(target.id)
	var price := AgentMissions.bribe_price(s, target)
	var treasury := s.faction(W.A).treasury
	var valour := e.valour
	_order(t, s, e, AgentMissions.BRIBE, target.id)
	AgentProcessor.process_year(s)
	t.assert_eq(target.faction, W.A, "l'esercito passa")
	t.assert_eq(commander.faction, W.A, "con il comandante")
	t.assert_eq(s.faction(W.A).treasury, treasury - price, "il prezzo e' pagato")
	t.assert_false(s.at_war(W.A, W.B), "la corruzione non dichiara guerra")
	t.assert_eq(e.valour, valour + s.rules.agents.valour_growth)
	var events := W.events_of(s, GameState.EV_BRIBE)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["prezzo"], price)
	t.assert_eq(events[0]["esercito"], target.id)
	t.assert_eq(events[0]["con"], W.B)


func test_corruzione_rifiutata_non_costa_nulla(t: TestContext) -> void:
	var s := W.world()
	W.never_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var target := W.general_army(s, W.B, W.MEZZA, 60)
	var treasury := s.faction(W.A).treasury
	_order(t, s, e, AgentMissions.BRIBE, target.id)
	AgentProcessor.process_year(s)
	t.assert_eq(target.faction, W.B)
	t.assert_eq(s.faction(W.A).treasury, treasury)
	t.assert_eq(W.events_of(s, GameState.EV_BRIBE_REFUSED).size(), 1)
	t.assert_true(s.agent(e.id) != null)


func test_corruzione_senza_fondi_fallisce(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var target := W.general_army(s, W.B, W.MEZZA, 60)
	s.faction(W.A).treasury = 0
	_order(t, s, e, AgentMissions.BRIBE, target.id)
	AgentProcessor.process_year(s)
	t.assert_eq(target.faction, W.B)
	t.assert_eq(s.faction(W.A).treasury, 0)
	var events := W.events_of(s, GameState.EV_MISSION_FAILED)
	t.assert_eq(events.size(), 1)
	t.assert_true(str(events[0]["motivo"]).find("tesoro") >= 0)
	t.assert_false(e.has_mission())


func test_il_comandante_corrotto_perde_titoli_e_sangue_reale(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var target := W.general_army(s, W.B, W.MEZZA, 60)
	var prince := s.commander_of(target.id)
	prince.role = Character.ROLE_PRINCE
	prince.royal_blood = true
	prince.office = "castle"
	_order(t, s, e, AgentMissions.BRIBE, target.id)
	AgentProcessor.process_year(s)
	t.assert_eq(prince.faction, W.A)
	t.assert_eq(prince.role, Character.ROLE_GENERAL, "il principe diventa un generale")
	t.assert_false(prince.royal_blood)
	t.assert_eq(prince.office, "")
	t.assert_eq(prince.title, "")


func test_la_guarnigione_corrotta_porta_con_se_la_provincia(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var target := W.general_army(s, W.B, W.MEZZA, 60)
	target.in_castle = true
	_order(t, s, e, AgentMissions.BRIBE, target.id)
	AgentProcessor.process_year(s)
	t.assert_eq(s.province(W.MEZZA).owner, W.A, "la provincia passa con la guarnigione")
	t.assert_eq(W.events_of(s, GameState.EV_PROVINCE_CAPTURED).size(), 1)
	t.assert_eq(W.events_of(s, GameState.EV_BRIBE)[0]["provincia"], W.MEZZA)
	t.assert_false(target.in_castle, "dopo la conquista nessuno e' piu' nel castello")


func test_trasferimento_di_un_esercito(t: TestContext) -> void:
	var s := W.world()
	var army := W.general_army(s, W.B, W.MEZZA, 60)
	army.path = PackedStringArray([W.ORTO])
	army.assault_ordered = true
	var province_id := AgentProcessor.transfer_army(s, army, W.A)
	t.assert_eq(province_id, "", "fuori dal castello: la provincia non passa")
	t.assert_eq(army.faction, W.A)
	t.assert_true(army.path.is_empty())
	t.assert_false(army.assault_ordered)
	t.assert_eq(s.province(W.MEZZA).owner, W.B)


# --- risoluzione: assassinio ---------------------------------------------------------------------------------------------------------


func test_gradino_della_tabella_per_tipo_di_bersaglio(t: TestContext) -> void:
	var s := W.world()
	var ar := s.rules.agents
	var emissary := W.add_agent(s, W.B, W.MEZZA, "EMISSARY", 2)
	var spy := W.add_agent(s, W.B, W.MEZZA, "SPY", 4)
	var bishop := W.add_agent(s, W.B, W.MEZZA, "BISHOP", 3)
	var princess := W.agent_of(s, W.B, AgentState.PRINCESS)
	princess.valour = 1
	t.assert_eq(AgentMissions.kill_step(s, 2, {"tipo": "agente", "id": emissary.id}), ar.step_emissary, "valore pari: gradino di base")
	t.assert_eq(AgentMissions.kill_step(s, 5, {"tipo": "agente", "id": emissary.id}), mini(ar.step_emissary + 3, ar.max_step()), "+1 per punto di vantaggio")
	t.assert_eq(AgentMissions.kill_step(s, 0, {"tipo": "agente", "id": emissary.id}), ar.step_emissary - 2, "-1 per punto di svantaggio")
	t.assert_eq(AgentMissions.kill_step(s, 4, {"tipo": "agente", "id": spy.id}), ar.step_spy)
	t.assert_eq(AgentMissions.kill_step(s, 3, {"tipo": "agente", "id": bishop.id}), ar.step_religious)
	t.assert_eq(AgentMissions.kill_step(s, 1, {"tipo": "agente", "id": princess.id}), ar.step_princess)
	t.assert_eq(AgentMissions.kill_step(s, 10, {"tipo": "agente", "id": emissary.id}), ar.max_step(), "limitato alla tabella")
	emissary.valour = 10
	t.assert_eq(AgentMissions.kill_step(s, 0, {"tipo": "agente", "id": emissary.id}), 0, "mai sotto il primo gradino")
	t.assert_eq(AgentMissions.kill_step(s, 5, {"tipo": "agente", "id": 9999}), 0, "bersaglio sconosciuto")
	var leader := s.leader_of(W.B)
	t.assert_eq(AgentMissions.kill_step(s, 3, {"tipo": "personaggio", "id": leader.id}), clampi(ar.step_leader + 3 - leader.stars(s.rules, s.campaign), 0, ar.max_step()))
	var general := W.add_general(s, W.B, W.MEZZA)
	t.assert_eq(AgentMissions.kill_step(s, 3, {"tipo": "personaggio", "id": general.id}), clampi(ar.step_noble + 3 - 3, 0, ar.max_step()), "il generale ha comando 3")


func test_assassinio_validazione(t: TestContext) -> void:
	var s := W.world()
	var killer := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	var victim := W.add_agent(s, W.B, W.MEZZA, "EMISSARY", 2)
	var far := W.agent_of(s, W.G, AgentState.EMISSARY)
	var mine := W.agent_of(s, W.A, AgentState.EMISSARY)
	var general := W.add_general(s, W.B, W.MEZZA)
	_refused(t, s, killer, AgentMissions.ASSASSINATE, far.id, "{")
	_refused(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": far.id}, "portata")
	_refused(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": mine.id}, "tua fazione")
	_refused(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": 9999}, "sconosciuto")
	_refused(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "personaggio", "id": 9999}, "sconosciuto")
	_refused(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "mostro", "id": 1}, "Tipo")
	var linked := s.character(W.agent_of(s, W.B, AgentState.PRINCESS).character_id)
	_refused(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "personaggio", "id": linked.id}, "agente")
	s.form_alliance(W.A, W.B)
	_refused(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": victim.id}, "alleato")
	_refused(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "personaggio", "id": general.id}, "alleato")
	s.break_alliance(W.A, W.B)
	var r := _order(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": victim.id})
	t.assert_eq(r["regione"], W.MEZZA)
	t.assert_eq(r["bersaglio"], {"tipo": "agente", "id": victim.id})
	t.assert_eq(float(r["probabilita"]), s.rules.agents.kill_chance(AgentMissions.kill_step(s, killer.valour, {"tipo": "agente", "id": victim.id})))
	_order(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "personaggio", "id": general.id})
	t.assert_eq(killer.mission["bersaglio"]["tipo"], "personaggio", "il nuovo ordine sostituisce il precedente")


func test_assassinio_riuscito_di_un_agente(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	var killer := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	var victim := W.add_agent(s, W.B, W.MEZZA, "EMISSARY", 2)
	_order(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": victim.id})
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(victim.id) == null, "la vittima e' morta")
	t.assert_eq(killer.region, W.MEZZA)
	t.assert_eq(killer.valour, 3 + s.rules.agents.valour_growth)
	var events := W.events_of(s, GameState.EV_ASSASSINATION)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["bersaglio"], victim.id)
	t.assert_eq(events[0]["con"], W.B)
	t.assert_eq(W.events_of(s, GameState.EV_ASSASSINATION_FAILED).size(), 0)


func test_assassinio_riuscito_di_un_personaggio(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	var killer := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	var army := W.general_army(s, W.B, W.MEZZA, 40)
	var general := s.commander_of(army.id)
	_order(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "personaggio", "id": general.id})
	AgentProcessor.process_year(s)
	t.assert_false(general.alive)
	t.assert_eq(general.death_cause, "assassinio")
	t.assert_true(s.commander_of(army.id) == null, "l'esercito resta senza comandante")
	t.assert_eq(W.events_of(s, GameState.EV_ASSASSINATION).size(), 1)


func test_assassinio_del_capo_innesca_la_successione(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	var killer := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	var leader := s.leader_of(W.B)
	leader.region = W.MEZZA
	_order(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "personaggio", "id": leader.id})
	_end_year(t, s)
	t.assert_false(leader.alive)
	t.assert_eq(leader.death_cause, "assassinio")
	t.assert_eq(W.events_of(s, GameState.EV_ASSASSINATION).size(), 1)


func test_assassinio_fallito_l_assassino_puo_morire(t: TestContext) -> void:
	var s := W.world()
	W.kill_never(s)
	s.rules.agents.fail_death_chance = 0.0
	var killer := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	var victim := W.add_agent(s, W.B, W.MEZZA, "EMISSARY", 2)
	_order(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": victim.id})
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(victim.id) != null)
	t.assert_true(s.agent(killer.id) != null, "sopravvive")
	t.assert_eq(killer.valour, 3, "nessuna crescita")
	var events := W.events_of(s, GameState.EV_ASSASSINATION_FAILED)
	t.assert_eq(events.size(), 1)
	t.assert_false(bool(events[0]["assassino_morto"]))
	s.rules.agents.fail_death_chance = 1.0
	var killer2 := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	_order(t, s, killer2, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": victim.id})
	s.events.clear()
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(killer2.id) == null, "l'assassino muore")
	t.assert_true(bool(W.events_of(s, GameState.EV_ASSASSINATION_FAILED)[0]["assassino_morto"]))


func test_l_assassino_insegue_il_bersaglio_che_si_sposta(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	var killer := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	var victim := W.add_agent(s, W.B, W.MEZZA, "EMISSARY", 2)
	_order(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": victim.id})
	victim.region = W.ORTO     # fuori dalla portata di BASSA, ma confinante con MEZZA
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(victim.id) == null or killer.region == W.MEZZA, "se la vittima e' fuggita l'assassino e' andato a MEZZA")
	if s.agent(victim.id) != null:
		t.assert_true(killer.has_mission(), "la missione continua")
		t.assert_eq(killer.path, PackedStringArray([W.ORTO]))
		AgentProcessor.process_year(s)
		t.assert_true(s.agent(victim.id) == null, "raggiunta e uccisa")
		t.assert_eq(killer.region, W.ORTO)


func test_il_bersaglio_scomparso_fa_fallire_la_missione(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	var killer := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	var victim := W.add_agent(s, W.B, W.MEZZA, "EMISSARY", 2)
	_order(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": victim.id})
	s.remove_agent(victim)
	AgentProcessor.process_year(s)
	t.assert_false(killer.has_mission())
	t.assert_true(killer.path.is_empty(), "l'avvicinamento si ferma")
	t.assert_eq(killer.region, W.MEZZA, "si e' mosso prima di accorgersene")
	t.assert_eq(W.events_of(s, GameState.EV_MISSION_FAILED).size(), 1)


func test_ordine_degli_agenti_nello_stesso_anno(t: TestContext) -> void:
	var s := W.world()
	W.kill_always(s)
	W.always_accept(s)
	var killer := W.add_agent(s, W.A, W.ALTA, "ASSASSIN", 3)
	var victim := W.add_agent(s, W.B, W.BASSA, "EMISSARY", 2)
	_order(t, s, killer, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": victim.id})
	# la vittima ha una proposta in corso nella sua regione: le missioni si risolvono in ordine di id e l'assassino ha l'id minore
	_order(t, s, victim, AgentMissions.ALLIANCE, W.A)
	t.assert_false(bool(victim.mission["avvicinamento"]))
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(victim.id) == null)
	t.assert_false(s.is_allied(W.A, W.B), "la missione dell'ucciso non si svolge")
	t.assert_eq(W.events_of(s, GameState.EV_ALLIANCE_FORMED).size(), 0)


# --- anteprima ------------------------------------------------------------------------------------------------------------------------------


func test_anteprima_delle_missioni_dell_emissario(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var army := W.general_army(s, W.B, W.MEZZA, 60)
	var r := GameCommands.mission_options(s, W.A, e.id)
	t.assert_true(bool(r["ok"]))
	var list: Array = r["missioni"]
	var kinds := []
	for item in list:
		var o: Dictionary = item
		kinds.append(o["tipo"])
		for key in ["tipo", "bersaglio", "regione", "etichetta", "probabilita", "prezzo", "tesoro_sufficiente", "gradino"]:
			t.assert_true(o.has(key), "la voce ha '%s'" % key)
		t.assert_true(float(o["probabilita"]) >= 0.0 and float(o["probabilita"]) <= 1.0)
	t.assert_true(kinds.has(AgentMissions.ALLIANCE), "alleanza con BETA")
	t.assert_false(kinds.has(AgentMissions.TRUCE), "nessuna guerra: nessuna tregua")
	t.assert_true(kinds.has(AgentMissions.BRIBE), "l'esercito con generale")
	var alliance_targets := []
	var bribe_targets := []
	for item in list:
		var o: Dictionary = item
		if o["tipo"] == AgentMissions.ALLIANCE:
			alliance_targets.append(o["bersaglio"])
		if o["tipo"] == AgentMissions.BRIBE:
			bribe_targets.append(o["bersaglio"])
			t.assert_eq(o["prezzo"], AgentMissions.bribe_price(s, s.army(int(o["bersaglio"]))))
			t.assert_true(bool(o["tesoro_sufficiente"]))
	t.assert_eq(alliance_targets, [W.B] as Array, "GAMMA e' troppo lontana")
	t.assert_true(bribe_targets.has(army.id))
	var again: Array = GameCommands.mission_options(s, W.A, e.id)["missioni"]
	t.assert_eq(again, list, "stesso stato, stessa anteprima")


func test_tutte_le_voci_dell_anteprima_si_possono_ordinare(t: TestContext) -> void:
	var s := W.world()
	W.general_army(s, W.B, W.MEZZA, 60)
	W.add_general(s, W.A, W.ALTA)
	W.add_general(s, W.A, W.BASSA)
	s.declare_war(W.A, W.G)
	var scout := s.create_army(W.G, W.ALTA, false)
	scout.stacks.append(UnitStack.new("Spearmen", 10, 0))
	var assassin := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	W.add_agent(s, W.B, W.MEZZA, "EMISSARY", 2)
	var total := 0
	for a in s.agents.duplicate():
		if a.faction != W.A:
			continue
		var list: Array = GameCommands.mission_options(s, W.A, a.id)["missioni"]
		for item in list:
			var o: Dictionary = item
			var r := GameCommands.order_mission(s, W.A, a.id, str(o["tipo"]), o["bersaglio"])
			t.assert_true(bool(r["ok"]), "agente %d: %s -> %s" % [a.id, o["tipo"], str(r["errore"])])
			t.assert_eq(float(r["probabilita"]), float(o["probabilita"]), "stessa probabilita'")
			total += 1
		a.mission = {}
		a.path = PackedStringArray()
	t.assert_true(total >= 5, "l'anteprima ha voci per piu' tipi di agente: %d" % total)
	var kinds := {}
	for item in GameCommands.mission_options(s, W.A, assassin.id)["missioni"]:
		kinds[(item as Dictionary)["tipo"]] = true
	t.assert_eq(kinds.keys(), [AgentMissions.ASSASSINATE] as Array)


func test_l_anteprima_di_spie_e_religiosi_e_vuota(t: TestContext) -> void:
	var s := W.world()
	var spy := W.add_agent(s, W.A, W.BASSA, "SPY", 3)
	var bishop := W.add_agent(s, W.A, W.BASSA, "BISHOP", 3)
	t.assert_true((GameCommands.mission_options(s, W.A, spy.id)["missioni"] as Array).size() > 0, "la spia ha missioni verso MEZZA (18/11/2026)")
	t.assert_eq((GameCommands.mission_options(s, W.A, bishop.id)["missioni"] as Array).size(), 0)
	t.assert_false(bool(GameCommands.order_mission(s, W.A, spy.id, AgentMissions.ASSASSINATE, {"tipo": "agente", "id": 1})["ok"]))


func test_le_proposte_tra_giocatori_non_compaiono_ma_quelle_dell_ia_si(t: TestContext) -> void:
	var s := W.world()
	s.faction(W.B).is_player = true
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var found := false
	for item in (GameCommands.mission_options(s, W.A, e.id)["missioni"] as Array):
		var o: Dictionary = item
		if o["tipo"] == AgentMissions.ALLIANCE and o["bersaglio"] == W.B:
			found = true
	t.assert_true(found, "fase 7b: l'IA di ALPHA puo' proporre un'alleanza a BETA, giocatore")
	s.faction(W.A).is_player = true
	for item in (GameCommands.mission_options(s, W.A, e.id)["missioni"] as Array):
		var o2: Dictionary = item
		t.assert_false(o2["tipo"] == AgentMissions.ALLIANCE and o2["bersaglio"] == W.B, "niente proposte tra due giocatori")
	_refused(t, s, e, AgentMissions.ALLIANCE, W.B, "giocatori")


func test_il_tesoro_insufficiente_si_vede_nell_anteprima(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	W.general_army(s, W.B, W.MEZZA, 60)
	s.faction(W.A).treasury = 1
	for item in (GameCommands.mission_options(s, W.A, e.id)["missioni"] as Array):
		var o: Dictionary = item
		if o["tipo"] == AgentMissions.BRIBE:
			t.assert_false(bool(o["tesoro_sufficiente"]))
			t.assert_true(int(o["prezzo"]) > 1)
