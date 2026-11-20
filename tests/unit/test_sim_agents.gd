extends RefCounted
## Test degli agenti (fase 5a): modello esteso, nascita nella coda di reclutamento, principesse collegate ai
## personaggi, movimento (anche via mare), valore, cattura degli agenti nemici, effetti passivi delle spie
## (lealta' delle province, porte aperte negli assedi), pulizia di fine anno, eventi e salvataggi.
## Mondo di prova: vedi agent_world.gd. Le missioni stanno in test_sim_missions.gd, la diplomazia in test_sim_diplomacy.gd.

const W := preload("res://tests/unit/agent_world.gd")


func _end_year(t: TestContext, s: GameState) -> void:
	var r := TurnProcessor.end_year(s)
	t.assert_true(bool(r["ok"]), "fine anno")
	t.assert_eq((r["errori"] as Array).size(), 0, "nessuna anomalia dei dati: %s" % str(r["errori"]))


func _princess_character(s: GameState, faction_id: String, birth_year: int) -> Character:
	var c := s.create_character(faction_id)
	c.role = Character.ROLE_PRINCESS
	c.male = false
	c.royal_blood = true
	c.forename = "Prova"
	c.birth_year = birth_year
	c.loyalty = 8
	c.acumen = 4
	c.old_age = 500
	return c


# --- parametri -----------------------------------------------------------------------------------------


func test_i_parametri_degli_agenti_sono_quelli_del_file(t: TestContext) -> void:
	var from_file := AgentRules.load_file()
	t.assert_eq(from_file.errors, PackedStringArray(), "il file agenti.cfg si legge")
	t.assert_eq(AgentRules.new().to_dict(), from_file.to_dict(), "predefiniti = file")
	t.assert_eq(Rules.new().agents.to_dict(), from_file.to_dict(), "Rules carica gli agenti")
	t.assert_eq(from_file.kill_steps.size(), 16, "tabella a 16 gradini")
	t.assert_eq(from_file.kill_chance(0), 0.0)
	t.assert_eq(from_file.kill_chance(15), 0.97)
	t.assert_eq(from_file.kill_chance(99), 0.97, "oltre la tabella: ultimo gradino")
	t.assert_eq(from_file.kill_chance(-3), 0.0, "sotto la tabella: primo gradino")
	t.assert_eq(from_file.max_step(), 15)


# --- modello e partenza --------------------------------------------------------------------------------


func test_tipi_di_agente(t: TestContext) -> void:
	for kind in ["EMISSARY", "SPY", "ASSASSIN", "BISHOP", "PRIEST", "CARDINAL", "MULLAH", "INQUISITOR"]:
		t.assert_true(AgentState.is_recruitable_type(kind), "%s si recluta" % kind)
	for kind in ["PRINCESS", "CRUSADE", "JIHAD", "INFANTRY", ""]:
		t.assert_false(AgentState.is_recruitable_type(kind), "%s non si recluta" % kind)
	t.assert_true(AgentState.is_religious_type("BISHOP"))
	t.assert_false(AgentState.is_religious_type("SPY"))
	var spy := AgentState.new(1, W.A, W.ALTA, "Spy", AgentState.SPY, 1000)
	t.assert_true(spy.is_invisible())
	t.assert_false(spy.is_religious())
	t.assert_false(AgentState.new(2, W.A, W.ALTA, "Emissary", AgentState.EMISSARY, 1000).is_invisible())
	t.assert_true(AgentState.new(3, W.A, W.ALTA, "Bishop", "BISHOP", 1000).is_religious())


func test_la_partenza_ha_agenti_con_valore_e_nome(t: TestContext) -> void:
	var s := W.world()
	t.assert_eq(s.agents.size(), 5, "3 emissari e 2 principesse")
	var start := s.rules.agents.start_valour
	for faction_id in [W.A, W.B, W.G]:
		var e := W.agent_of(s, faction_id, AgentState.EMISSARY)
		t.assert_true(e != null, "emissario di %s" % faction_id)
		t.assert_eq(e.valour, start, "valore iniziale degli emissari")
		t.assert_true(e.name != "", "ha un nome")
		t.assert_eq(e.character_id, 0, "gli emissari non sono personaggi")
	t.assert_eq(W.agent_of(s, W.A, AgentState.EMISSARY).region, W.BASSA)
	t.assert_eq(W.agent_of(s, W.B, AgentState.EMISSARY).region, W.MEZZA)
	t.assert_eq(W.agent_of(s, W.G, AgentState.EMISSARY).region, W.ORTO)
	t.assert_true(W.agent_of(s, W.G, AgentState.PRINCESS) == null, "GAMMA non ha principesse")


func test_le_principesse_dello_startpos_sono_collegate_a_un_personaggio(t: TestContext) -> void:
	var s := W.world()
	var expected := {W.A: 980, W.B: 990}
	for faction_id in [W.A, W.B]:
		var a := W.agent_of(s, faction_id, AgentState.PRINCESS)
		t.assert_true(a != null, "principessa di %s" % faction_id)
		t.assert_true(a.character_id != 0, "collegata")
		var c := s.character(a.character_id)
		t.assert_true(c != null and c.alive)
		t.assert_eq(c.role, Character.ROLE_PRINCESS)
		t.assert_eq(c.faction, faction_id)
		t.assert_false(c.male)
		t.assert_true(c.royal_blood)
		t.assert_eq(c.birth_year, int(expected[faction_id]), "anno di nascita = valore della MakeUnit")
		t.assert_eq(a.valour, clampi(c.effective(Character.ATTR_ACUMEN, s.rules, s.campaign), 0, s.rules.agents.max_valour), "il valore e' l'acume")
		t.assert_eq(a.name, c.full_name())
		t.assert_eq(AgentMissions.princess_agent(s, c), a)


func test_il_collegamento_delle_principesse_e_idempotente_e_deterministico(t: TestContext) -> void:
	var s := W.world()
	var count := s.characters.size()
	var ids := []
	for a in s.agents:
		ids.append(a.character_id)
	GameSetup.link_start_princesses(s)
	t.assert_eq(s.characters.size(), count, "nessun personaggio in piu'")
	var again := []
	for a in s.agents:
		again.append(a.character_id)
	t.assert_eq(again, ids)
	var other := W.world()
	t.assert_eq(SaveGame.to_json(other), SaveGame.to_json(s), "stessa partita, stesso stato")


func test_la_partita_senza_dinastia_non_crea_personaggi_per_le_principesse(t: TestContext) -> void:
	var campaign := StartposLoader.load_file("res://tests/fixtures/sim_startpos.txt")
	var units := UnitProdLoader.load_file("res://tests/fixtures/sim_unit_prod.txt")
	var buildings := BuildingProdLoader.load_file(W.BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, Rules.new(), 3)
	for a in s.agents:
		t.assert_eq(a.character_id, 0, "senza capo non c'e' dinastia")
		t.assert_true(a.valour >= 0, "ma il valore c'e'")


# --- reclutamento ------------------------------------------------------------------------------------------------


func test_tipi_reclutabili_nella_coda(t: TestContext) -> void:
	var s := W.world()
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.A, W.ALTA, "Emissary")["ok"]))
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.A, W.ALTA, "Spy")["ok"]), "la spia vuole il castello")
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.A, W.ALTA, "Assassin")["ok"]), "l'assassino vuole il castello 2: ALTA ha il 3")
	t.assert_false(bool(GameCommands.can_queue_unit(s, W.A, W.BASSA, "Assassin")["ok"]), "BASSA ha il castello 1")
	t.assert_false(bool(GameCommands.can_queue_unit(s, W.A, W.ALTA, "Princess")["ok"]), "le principesse nascono con la dinastia")
	# fase 5c: crociata e jihad si reclutano (cattolici, musulmani) ma nascono come eserciti, non come agenti
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.A, W.ALTA, "Crusade")["ok"]), "crociata: ALPHA e' cattolica")
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.B, W.MEZZA, "Jihad")["ok"]), "jihad: BETA e' musulmana")
	t.assert_false(bool(GameCommands.can_queue_unit(s, W.B, W.MEZZA, "Crusade")["ok"]), "la crociata non e' dei musulmani")
	t.assert_false(bool(GameCommands.can_queue_unit(s, W.A, W.ALTA, "Bishop")["ok"]), "manca la chiesa")
	t.assert_false(bool(GameCommands.can_queue_unit(s, W.A, W.BASSA, "Mullah")["ok"]), "solo FN_BETA")
	var princess_failure := GameCommands.can_queue_unit(s, W.A, W.ALTA, "Princess")
	t.assert_true(str(princess_failure["errore"]).find("dinastia") >= 0, "il motivo e' detto")


func test_l_agente_nasce_alla_fine_della_coda(t: TestContext) -> void:
	var s := W.world()
	var armies_before := s.armies.size()
	var treasury := s.faction(W.A).treasury
	var spy_cost := s.units.get_unit("Spy").cost
	var r := GameCommands.queue_unit(s, W.A, W.ALTA, "Spy")
	t.assert_true(bool(r["ok"]))
	t.assert_eq(s.faction(W.A).treasury, treasury - spy_cost, "costo pagato subito")
	t.assert_eq(W.agent_of(s, W.A, AgentState.SPY), null, "non c'e' ancora")
	_end_year(t, s)
	var spy := W.agent_of(s, W.A, AgentState.SPY)
	t.assert_true(spy != null, "la spia e' nata")
	t.assert_eq(spy.region, W.ALTA)
	t.assert_eq(spy.unit_id, "Spy")
	t.assert_eq(spy.birth_year, 1001)
	t.assert_true(spy.name != "")
	t.assert_eq(s.armies.size(), armies_before, "un agente non entra in un esercito")
	t.assert_eq(s.province(W.ALTA).unit_queue.size(), 0)
	var events := W.events_of(s, GameState.EV_AGENT_RECRUITED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["agente"], spy.id)
	t.assert_eq(events[0]["fazione"], W.A)
	t.assert_eq(events[0]["regione"], W.ALTA)
	t.assert_eq(events[0]["valore"], spy.valour)
	t.assert_eq(events[0]["origine"], "coda")
	t.assert_eq(W.events_of(s, GameState.EV_RECRUITED).size(), 0, "non e' un reclutamento di truppe")


func test_gli_agenti_nuovi_hanno_id_in_fondo_alla_coda(t: TestContext) -> void:
	var s := W.world()
	var last := 0
	for a in s.agents:
		last = maxi(last, a.id)
	GameCommands.queue_unit(s, W.A, W.ALTA, "Emissary")
	GameCommands.queue_unit(s, W.A, W.BASSA, "Emissary")
	GameCommands.queue_unit(s, W.B, W.MEZZA, "Emissary")
	_end_year(t, s)
	t.assert_eq(s.agents.size(), 8)
	var born: Array[int] = []
	for e in W.events_of(s, GameState.EV_AGENT_RECRUITED):
		born.append(int(e["agente"]))
	t.assert_eq(born, [last + 1, last + 2, last + 3] as Array[int], "nell'ordine delle province")


func test_valore_iniziale_dalla_livello_dell_edificio_produttore(t: TestContext) -> void:
	var s := W.world()
	var ar := s.rules.agents
	var spy_unit := s.units.get_unit("Spy")
	t.assert_eq(AgentProcessor.initial_valour(s, s.province(W.BASSA), spy_unit), ar.base_valour, "castello di livello 1")
	t.assert_eq(AgentProcessor.initial_valour(s, s.province(W.ALTA), spy_unit), ar.base_valour + 2 * ar.valour_per_level, "castello di livello 3")
	var emissary_unit := s.units.get_unit("Emissary")
	t.assert_eq(AgentProcessor.initial_valour(s, s.province(W.ALTA), emissary_unit), ar.base_valour, "nessun requisito: livello 1")
	ar.max_valour = 2
	t.assert_eq(AgentProcessor.initial_valour(s, s.province(W.ALTA), spy_unit), 2, "limitato al massimo")


func test_valore_predefinito_per_i_salvataggi_vecchi(t: TestContext) -> void:
	var s := W.world()
	var ar := s.rules.agents
	var e := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 5)
	t.assert_eq(AgentProcessor.default_valour(s, e), ar.start_valour)
	var spy := s.create_agent(W.A, W.ALTA, "Spy", AgentState.SPY, 990)
	t.assert_eq(AgentProcessor.default_valour(s, spy), ar.base_valour + 2 * ar.valour_per_level, "come un reclutato in quella provincia")


func test_nomi_degli_agenti_dalla_lista_della_fazione(t: TestContext) -> void:
	var s := W.world()
	var a := s.create_agent(W.A, W.ALTA, "Emissary", AgentState.EMISSARY, 1000)
	t.assert_eq(a.name, "")
	AgentProcessor.name_agents(s)
	t.assert_true(a.name != "")
	var kept := a.name
	AgentProcessor.name_agents(s)
	t.assert_eq(a.name, kept, "un nome gia' dato non cambia")
	t.assert_eq(AgentProcessor.agent_name(s, a), kept, "scelto con l'id, nessun sorteggio")


# --- valore ----------------------------------------------------------------------------------------------------------------


func test_il_valore_cresce_fino_al_massimo(t: TestContext) -> void:
	var s := W.world()
	var ar := s.rules.agents
	var a := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 3)
	AgentProcessor.grow_valour(s, a)
	t.assert_eq(a.valour, 3 + ar.valour_growth)
	a.valour = ar.max_valour
	AgentProcessor.grow_valour(s, a)
	t.assert_eq(a.valour, ar.max_valour, "mai oltre il massimo")


# --- movimento ---------------------------------------------------------------------------------------------------------------


func test_l_agente_si_muove_di_una_regione_all_anno(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var r := GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.MEZZA, W.ORTO]))
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_eq(r["passi"], 2)
	t.assert_eq(e.region, W.BASSA, "l'ordine non muove")
	_end_year(t, s)
	t.assert_eq(e.region, W.MEZZA)
	t.assert_eq(e.path, PackedStringArray([W.ORTO]))
	var moved := W.events_of(s, GameState.EV_AGENT_MOVED)
	t.assert_eq(moved.size(), 1)
	t.assert_eq(moved[0]["agente"], e.id)
	t.assert_eq(moved[0]["da"], W.BASSA)
	t.assert_eq(moved[0]["a"], W.MEZZA)
	t.assert_eq(moved[0]["fazione"], W.A)
	t.assert_eq(moved[0]["tipo_agente"], "EMISSARY")
	_end_year(t, s)
	t.assert_eq(e.region, W.ORTO)
	t.assert_true(e.path.is_empty(), "arrivato")
	_end_year(t, s)
	t.assert_eq(e.region, W.ORTO, "fermo")
	t.assert_eq(W.events_of(s, GameState.EV_AGENT_MOVED).size(), 0)


func test_gli_agenti_entrano_in_territorio_altrui_senza_guerra(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.MEZZA]))
	_end_year(t, s)
	t.assert_eq(e.region, W.MEZZA)
	t.assert_false(s.at_war(W.A, W.B))
	t.assert_eq(W.events_of(s, GameState.EV_WAR_DECLARED).size(), 0)
	t.assert_eq(W.events_of(s, GameState.EV_BATTLE).size(), 0)
	var rebel := W.add_agent(s, W.A, W.BASSA, "EMISSARY", 1)
	t.assert_true(bool(GameCommands.order_agent_move(s, W.A, rebel.id, PackedStringArray([W.MEZZA, W.SOLA]))["ok"]), "anche tra i ribelli")


func test_ordini_di_movimento_non_validi(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	var foreign := W.agent_of(s, W.B, AgentState.EMISSARY)
	var failures := [
		GameCommands.order_agent_move(s, W.A, 9999, PackedStringArray([W.ALTA])),
		GameCommands.order_agent_move(s, W.A, foreign.id, PackedStringArray([W.MEZZA])),
		GameCommands.order_agent_move(s, "FN_NESSUNA", e.id, PackedStringArray([W.ALTA])),
		GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray()),
		GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray(["ID_NESSUNA"])),
		GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.NORD])),
		GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.ALTA, W.ORTO])),
	]
	for i in range(failures.size()):
		var f: Dictionary = failures[i]
		t.assert_false(bool(f["ok"]), "ordine %d rifiutato" % i)
		t.assert_true(str(f["errore"]) != "", "ordine %d: motivo" % i)
	t.assert_true(e.path.is_empty(), "nessun ordine e' stato salvato")


func test_un_nuovo_ordine_annulla_la_missione_e_la_cancellazione_toglie_il_percorso(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	t.assert_true(bool(GameCommands.order_mission(s, W.A, e.id, AgentMissions.ALLIANCE, W.B)["ok"]))
	t.assert_true(e.has_mission())
	t.assert_false(e.path.is_empty(), "si avvicina")
	t.assert_true(bool(GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.ALTA]))["ok"]))
	t.assert_false(e.has_mission(), "l'ordine di movimento annulla la missione")
	var c := GameCommands.cancel_agent_move(s, W.A, e.id)
	t.assert_true(bool(c["ok"]))
	t.assert_true(e.path.is_empty())
	t.assert_false(bool(GameCommands.cancel_agent_move(s, W.A, 9999)["ok"]))
	t.assert_false(bool(GameCommands.cancel_agent_move(s, W.B, e.id)["ok"]), "non e' di BETA")
	# annullare il movimento di avvicinamento annulla la missione
	GameCommands.order_mission(s, W.A, e.id, AgentMissions.ALLIANCE, W.B)
	GameCommands.cancel_agent_move(s, W.A, e.id)
	t.assert_false(e.has_mission(), "avvicinamento annullato = missione annullata")


func test_trasporto_via_mare_degli_agenti(t: TestContext) -> void:
	var s := W.world()
	W.fleet(s, W.A, W.NORD)
	W.fleet(s, W.A, W.SUD)
	var traveller := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 2)
	var r := GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.MEZZA]))
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_true(bool(r["via_mare"]))
	t.assert_eq(r["catena"], [W.NORD, W.SUD] as Array)
	_end_year(t, s)
	t.assert_eq(traveller.region, W.MEZZA, "sbarcato")
	var moved := W.events_of(s, GameState.EV_AGENT_MOVED)
	t.assert_eq(moved.size(), 1)
	t.assert_true(bool(moved[0].get("via_mare", false)))
	t.assert_true(traveller.sea_route.is_empty())


func test_il_trasporto_via_mare_interrotto_lascia_l_agente_dov_e(t: TestContext) -> void:
	var s := W.world()
	W.fleet(s, W.A, W.NORD)
	W.fleet(s, W.A, W.SUD)
	var traveller := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 2)
	GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.MEZZA]))
	s.declare_war(W.A, W.B)
	W.fleet(s, W.B, W.SUD)
	_end_year(t, s)
	t.assert_eq(traveller.region, W.ALTA, "non si e' mosso")
	t.assert_true(traveller.path.is_empty() and traveller.sea_route.is_empty(), "ordine perso")
	t.assert_true(W.events_of(s, GameState.EV_TRANSPORT_BLOCKED).size() >= 1, "evento di trasporto interrotto")


## Richiesta di Federico dell'11/11/2026: emissari, principesse e gli altri agenti viaggiano via mare anche senza navi
## proprie a fare da ponte (`[flotte] agenti_senza_navi` di scontri.cfg); li ferma solo una flotta nemica.
func test_gli_agenti_viaggiano_via_mare_anche_senza_flotte(t: TestContext) -> void:
	var s := W.world()
	t.assert_true(s.rules.combat.agents_free_sea, "attivo per impostazione")
	var traveller := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 2)
	var r := GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.MEZZA]))
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_true(bool(r["via_mare"]))
	t.assert_eq(r["catena"], [W.NORD, W.SUD] as Array)
	t.assert_true(GameCommands.sea_destinations_from(s, W.A, W.ALTA, false).has(W.MEZZA), "tra le mete via mare dell'agente")
	_end_year(t, s)
	t.assert_eq(traveller.region, W.MEZZA, "sbarcato senza nessuna flotta")


func test_senza_flotte_una_flotta_nemica_ferma_comunque_l_agente(t: TestContext) -> void:
	var s := W.world()
	var traveller := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 2)
	s.declare_war(W.A, W.B)
	W.fleet(s, W.B, W.SUD)
	var problem := GameCommands.sea_transport_problem(s, W.A, W.ALTA, W.MEZZA, false)
	t.assert_true(problem.contains("nemic"), "la zona con la flotta nemica e' chiusa: %s" % problem)
	# dal 2026-11-13 una meta fuori portata e' un viaggio di piu' anni: si va a piedi (ALTA > BASSA > MEZZA)
	var r := GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.MEZZA]))
	t.assert_true(bool(r["ok"]) and bool(r.get("viaggio", false)), str(r))
	t.assert_false(bool(r.get("via_mare", false)), "non per mare")
	t.assert_eq(traveller.path, PackedStringArray([W.BASSA]))


func test_la_flotta_nemica_arrivata_dopo_l_ordine_ferma_l_agente_senza_navi(t: TestContext) -> void:
	var s := W.world()
	var traveller := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 2)
	t.assert_true(bool(GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.MEZZA]))["ok"]))
	s.declare_war(W.A, W.B)
	W.fleet(s, W.B, W.SUD)
	_end_year(t, s)
	t.assert_eq(traveller.region, W.ALTA, "non si e' mosso")


func test_le_truppe_hanno_ancora_bisogno_delle_flotte(t: TestContext) -> void:
	var s := W.world()
	var army := W.land_army(s, W.A, W.ALTA)
	var r := GameCommands.order_move(s, W.A, army.id, PackedStringArray([W.MEZZA]))
	t.assert_false(bool(r["ok"]), "senza flotte gli eserciti non attraversano il mare")
	t.assert_false(GameCommands.sea_destinations_from(s, W.A, W.ALTA, true).has(W.MEZZA))


## Richiesta di Federico del 16/11/2026 (mappa del mondo): senza navi gli agenti attraversano i mari ma non gli oceani
## (`[flotte] oceani` di scontri.cfg); per un oceano serve una flotta propria nella zona, come per le truppe.
func test_l_agente_non_attraversa_un_oceano_senza_flotte(t: TestContext) -> void:
	var s := W.world()
	s.rules.combat.oceans = {W.SUD: true}
	var traveller := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 2)
	t.assert_false(GameCommands.sea_destinations_from(s, W.A, W.ALTA, false).has(W.MEZZA), "l'oceano chiude la rotta")
	var problem := GameCommands.sea_transport_problem(s, W.A, W.ALTA, W.MEZZA, false)
	t.assert_true(problem.contains("ocean"), "il motivo nomina l'oceano: %s" % problem)
	var r := GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.MEZZA]))
	t.assert_false(bool(r.get("via_mare", false)), "non per mare: %s" % str(r))


## Toglie le flotte di partenza di ALPHA (la galea nel mare del Nord), per costruire il ponte di navi a mano.
func _no_fleets(s: GameState) -> void:
	for a in s.armies.duplicate():
		if a.is_fleet and a.faction == W.A:
			s.armies.erase(a)


func test_una_flotta_nell_oceano_non_basta_senza_il_ponte_fino_alla_costa(t: TestContext) -> void:
	var s := W.world()
	s.rules.combat.oceans = {W.SUD: true}
	_no_fleets(s)
	W.fleet(s, W.A, W.SUD)
	var traveller := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 2)
	t.assert_false(GameCommands.sea_destinations_from(s, W.A, W.ALTA, false).has(W.MEZZA), "il mare prima dell'oceano non ha navi")
	var r := GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.MEZZA]))
	t.assert_false(bool(r.get("via_mare", false)), "segnalazione di Federico del 16/11: una sola flotta in mezzo all'oceano non fa da ponte: %s" % str(r))


func test_con_il_ponte_di_navi_l_agente_attraversa_l_oceano(t: TestContext) -> void:
	var s := W.world()
	s.rules.combat.oceans = {W.SUD: true}
	W.fleet(s, W.A, W.NORD)
	W.fleet(s, W.A, W.SUD)
	var traveller := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 2)
	var r := GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.MEZZA]))
	t.assert_true(bool(r["ok"]) and bool(r.get("via_mare", false)), str(r))
	t.assert_eq(r["catena"], [W.NORD, W.SUD] as Array, "flotte proprie in ogni zona della rotta oceanica")
	_end_year(t, s)
	t.assert_eq(traveller.region, W.MEZZA, "sbarcato grazie al ponte di navi")


func test_se_una_flotta_del_ponte_se_ne_va_l_agente_resta_a_terra(t: TestContext) -> void:
	var s := W.world()
	s.rules.combat.oceans = {W.SUD: true}
	_no_fleets(s)
	var first := W.fleet(s, W.A, W.NORD)
	W.fleet(s, W.A, W.SUD)
	var traveller := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 2)
	t.assert_true(bool(GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.MEZZA]))["ok"]))
	s.armies.erase(first)
	t.assert_true(GameCommands.chain_problem(s, W.A, W.ALTA, traveller.sea_route, W.MEZZA, false).contains("ponte"))
	_end_year(t, s)
	t.assert_eq(traveller.region, W.ALTA, "non si e' mosso")
	t.assert_true(AgentTravel.sea_table(s, W.A).get(W.ALTA, PackedStringArray()).has(W.MEZZA) == false, "nemmeno nei viaggi lunghi")


func test_le_zone_di_mare_restano_libere_e_gli_oceani_si_leggono_da_scontri_cfg(t: TestContext) -> void:
	var rules := CombatRules.load_file()
	t.assert_true(rules.oceans.has("ID_MID_ATLANTIC"), "l'Atlantico centrale e' un oceano")
	t.assert_true(rules.oceans.has("ID_N_PACIFIC"))
	t.assert_false(rules.oceans.has("ID_NORTH_SEA"), "il mare del Nord no")
	t.assert_false(rules.oceans.has("ID_ATLANTIC_OCEAN"), "le zone della mappa d'Europa restano mari")
	var s := W.world()
	t.assert_false(GameCommands.is_ocean(s, W.SUD), "nel mondo di prova nessun oceano")


## Richiesta di Federico dell'11/11/2026: un agente si imbarca anche da un porto non suo, per tornare da una provincia
## straniera (`[flotte] agenti_da_ogni_porto`).
func _foreign_port(s: GameState) -> String:
	# MEZZA non e' di ALPHA: le si da' un porto costruito
	var region := s.campaign.region(W.MEZZA)
	region.has_port = true
	s.province(W.MEZZA).buildings[GameCommands.PORT_FAMILY] = 1
	return W.MEZZA


func test_l_agente_si_imbarca_anche_da_un_porto_altrui(t: TestContext) -> void:
	var s := W.world()
	var port := _foreign_port(s)
	t.assert_true(s.province(port).owner != W.A, "provincia di un altro")
	var traveller := W.add_agent(s, W.A, port, "EMISSARY", 2)
	t.assert_eq(GameCommands.embark_problem(s, W.A, port, false), "", "l'agente puo' imbarcarsi")
	t.assert_true(GameCommands.embark_problem(s, W.A, port, true) != "", "le truppe no")
	var r := GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.ALTA]))
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_true(bool(r["via_mare"]))
	_end_year(t, s)
	t.assert_eq(traveller.region, W.ALTA, "tornato per mare")


func test_con_la_regola_spenta_l_agente_parte_solo_dai_propri_porti(t: TestContext) -> void:
	var s := W.world()
	s.rules.combat.agents_any_port = false
	var port := _foreign_port(s)
	var traveller := W.add_agent(s, W.A, port, "EMISSARY", 2)
	t.assert_true(GameCommands.embark_problem(s, W.A, port, false) != "")
	var r := GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.ALTA]))
	t.assert_false(bool(r.get("via_mare", false)), "non si imbarca dal porto altrui: %s" % str(r))


## Regola dell'originale (`agenti_senza_navi = false`): anche gli agenti hanno bisogno della catena di flotte.
func test_senza_flotte_non_c_e_trasporto_via_mare(t: TestContext) -> void:
	var s := W.world()
	s.rules.combat.agents_free_sea = false
	var traveller := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 2)
	t.assert_true(GameCommands.sea_transport_problem(s, W.A, W.ALTA, W.MEZZA, false) != "", "nessuna catena senza flotte")
	var r := GameCommands.order_agent_move(s, W.A, traveller.id, PackedStringArray([W.MEZZA]))
	t.assert_false(bool(r.get("via_mare", false)), "senza flotte non va per mare: %s" % str(r))


# --- cattura -------------------------------------------------------------------------------------------------------------------


func test_probabilita_di_cattura(t: TestContext) -> void:
	var s := W.world()
	var ar := s.rules.agents
	ar.capture_max = 0.8   # il mondo di prova azzera le catture: qui serve il limite vero
	var victim := W.add_agent(s, W.B, W.BASSA, "EMISSARY", 2)
	var expected := ar.capture_base + ar.capture_k * float(5 - 2)
	t.assert_true(absf(AgentProcessor.capture_chance(s, 5, victim) - expected) < 0.000001, "base + k * (V - valore)")
	var spy := W.add_agent(s, W.B, W.BASSA, "SPY", 2)
	t.assert_true(absf(AgentProcessor.capture_chance(s, 5, spy) - (expected - ar.invisible_malus)) < 0.000001, "spie e assassini: meno")
	victim.valour = 10
	t.assert_eq(AgentProcessor.capture_chance(s, 0, victim), 0.0, "mai sotto zero")
	t.assert_eq(AgentProcessor.capture_chance(s, 50, W.add_agent(s, W.B, W.BASSA, "EMISSARY", 0)), ar.capture_max, "mai oltre il massimo")


func test_il_catturatore_e_l_elemento_di_valore_massimo(t: TestContext) -> void:
	var s := W.world()
	var p := s.province(W.BASSA)
	var own := W.agent_of(s, W.A, AgentState.EMISSARY)
	var best := AgentProcessor.best_capturer(s, p)
	t.assert_eq(int(best["valore"]), own.valour)
	t.assert_eq(best["agente"], own)
	var spy := W.add_agent(s, W.A, W.BASSA, "SPY", own.valour)
	best = AgentProcessor.best_capturer(s, p)
	t.assert_eq(best["agente"], spy, "a parita' vince la spia sull'emissario")
	var assassin := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", own.valour)
	t.assert_eq(AgentProcessor.best_capturer(s, p)["agente"], spy, "a parita' la spia batte l'assassino")
	assassin.valour = own.valour + 1
	t.assert_eq(AgentProcessor.best_capturer(s, p)["agente"], assassin, "il valore piu' alto vince")
	p.set_level(s.rules.agents.border_fort_family, 5)
	best = AgentProcessor.best_capturer(s, p)
	t.assert_eq(int(best["valore"]), 5 * s.rules.agents.border_fort_per_level)
	t.assert_true(best["agente"] == null, "il forte di confine")
	W.add_agent(s, W.B, W.BASSA, "SPY", 10)
	t.assert_true(AgentProcessor.best_capturer(s, p)["agente"] == null, "gli agenti stranieri non contano")


func test_nessun_catturatore_senza_forte_e_senza_agenti(t: TestContext) -> void:
	var s := W.world()
	t.assert_true(AgentProcessor.best_capturer(s, s.province(W.ALTA)).is_empty())


func test_un_agente_nemico_viene_catturato(t: TestContext) -> void:
	var s := W.world()
	W.capture_always(s)
	var intruder := W.add_agent(s, W.B, W.BASSA, "EMISSARY", 3)
	var guard := W.agent_of(s, W.A, AgentState.EMISSARY)
	var before := guard.valour
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(intruder.id) == null, "catturato")
	var events := W.events_of(s, GameState.EV_AGENT_CAPTURED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["fazione"], W.A)
	t.assert_eq(events[0]["con"], W.B)
	t.assert_eq(events[0]["agente"], intruder.id)
	t.assert_eq(events[0]["regione"], W.BASSA)
	t.assert_eq(guard.valour, before + s.rules.agents.valour_growth, "il catturatore cresce")


func test_la_cattura_non_tocca_gli_alleati_ne_i_propri_agenti_ne_i_ribelli(t: TestContext) -> void:
	var s := W.world()
	W.capture_always(s)
	s.form_alliance(W.A, W.B)
	var ally := W.add_agent(s, W.B, W.BASSA, "EMISSARY", 1)
	var own := W.add_agent(s, W.A, W.BASSA, "EMISSARY", 1)
	W.add_agent(s, W.A, W.SOLA, "EMISSARY", 1)
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(ally.id) != null, "alleato")
	t.assert_true(s.agent(own.id) != null, "proprio")
	t.assert_eq(W.events_of(s, GameState.EV_AGENT_CAPTURED).size(), 0, "nessuna cattura nelle province dei ribelli")


func test_nessuna_cattura_senza_catturatore(t: TestContext) -> void:
	var s := W.world()
	W.capture_always(s)
	var intruder := W.add_agent(s, W.B, W.ALTA, "EMISSARY", 1)
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(intruder.id) != null, "ALTA non ha ne' forte ne' agenti suoi adatti")


func test_la_cattura_di_una_principessa_porta_via_anche_il_personaggio(t: TestContext) -> void:
	var s := W.world()
	W.capture_always(s)
	var princess := W.agent_of(s, W.B, AgentState.PRINCESS)
	var character_id := princess.character_id
	princess.region = W.BASSA
	AgentProcessor.process_year(s)
	t.assert_true(s.agent(princess.id) == null)
	var c := s.character(character_id)
	t.assert_false(c.alive)
	t.assert_eq(c.death_cause, "catturato")


func test_con_capture_max_zero_non_si_cattura_mai(t: TestContext) -> void:
	var s := W.world()
	s.rules.agents.capture_base = 1.0
	var intruder := W.add_agent(s, W.B, W.BASSA, "EMISSARY", 0)
	for i in range(5):
		_end_year(t, s)
	t.assert_true(s.agent(intruder.id) != null)


# --- spie: lealta' e porte --------------------------------------------------------------------------------------------------------


func test_le_spie_cambiano_la_lealta_obiettivo(t: TestContext) -> void:
	var s := W.world()
	var ar := s.rules.agents
	var p := s.province(W.ALTA)
	t.assert_eq(ProvinceProcessor.spies_term(s, p), 0)
	var own := W.add_agent(s, W.A, W.ALTA, "SPY", 2)
	t.assert_eq(ProvinceProcessor.spies_term(s, p), ar.spy_loyalty_bonus, "spia propria: bonus")
	var second := W.add_agent(s, W.A, W.ALTA, "SPY", 2)
	t.assert_eq(ProvinceProcessor.spies_term(s, p), ar.spy_loyalty_bonus, "una sola conta")
	var foreign := W.add_agent(s, W.G, W.ALTA, "SPY", 2)
	t.assert_eq(ProvinceProcessor.spies_term(s, p), ar.spy_loyalty_bonus - ar.spy_loyalty_malus, "e una straniera toglie")
	s.agents.erase(own)
	s.agents.erase(second)
	t.assert_eq(ProvinceProcessor.spies_term(s, p), -ar.spy_loyalty_malus, "solo la straniera")
	s.form_alliance(W.A, W.G)
	t.assert_eq(ProvinceProcessor.spies_term(s, p), 0, "una spia alleata non danneggia")
	s.agents.erase(foreign)
	W.add_agent(s, W.A, W.SOLA, "SPY", 2)
	t.assert_eq(ProvinceProcessor.spies_term(s, s.province(W.SOLA)), 0, "le province dei ribelli non hanno il termine")


func test_i_termini_di_lealta_includono_le_spie(t: TestContext) -> void:
	var s := W.world()
	var p := s.province(W.ALTA)
	var without := ProvinceProcessor.loyalty_terms(s, p)
	t.assert_true(without.has("spie"))
	t.assert_eq(without["spie"], 0)
	W.add_agent(s, W.A, W.ALTA, "SPY", 2)
	var with := ProvinceProcessor.loyalty_terms(s, p)
	t.assert_eq(with["spie"], s.rules.agents.spy_loyalty_bonus)
	t.assert_eq(int(with["somma"]) - int(without["somma"]), s.rules.agents.spy_loyalty_bonus, "entra nella somma")


func _siege_of_mezza(s: GameState) -> Army:
	s.declare_war(W.A, W.B)
	var besieger := s.create_army(W.A, W.MEZZA, false)
	besieger.stacks.append(UnitStack.new("Spearmen", 80, 0))
	W.land_army(s, W.B, W.MEZZA).in_castle = true
	var siege := SiegeState.new(W.MEZZA, W.A, 0)
	siege.army_ids = PackedInt32Array([besieger.id])
	s.sieges[W.MEZZA] = siege
	return besieger


func test_una_spia_apre_le_porte_del_castello_assediato(t: TestContext) -> void:
	var s := W.world()
	s.rules.agents.gates_k = 1.0
	_siege_of_mezza(s)
	var spy := W.add_agent(s, W.A, W.MEZZA, "SPY", 2)
	AgentProcessor.process_year(s)
	t.assert_eq(s.province(W.MEZZA).owner, W.A, "la provincia passa all'assediante")
	t.assert_false(s.is_besieged(W.MEZZA), "l'assedio e' finito")
	var events := W.events_of(s, GameState.EV_GATES_OPENED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["agente"], spy.id)
	t.assert_eq(events[0]["assediata"], W.B)
	t.assert_eq(spy.valour, 2 + s.rules.agents.valour_growth)
	t.assert_eq(W.events_of(s, GameState.EV_PROVINCE_CAPTURED).size(), 1)


func test_le_porte_non_si_aprono_senza_la_condizione(t: TestContext) -> void:
	var s := W.world()
	s.rules.agents.gates_k = 1.0
	_siege_of_mezza(s)
	W.add_agent(s, W.B, W.MEZZA, "SPY", 5)           # spia della fazione assediata
	W.add_agent(s, W.G, W.MEZZA, "SPY", 5)           # spia di una terza fazione
	W.add_agent(s, W.A, W.MEZZA, "EMISSARY", 5)      # non e' una spia
	W.add_agent(s, W.A, W.ORTO, "SPY", 5)            # altrove
	AgentProcessor.process_year(s)
	t.assert_eq(s.province(W.MEZZA).owner, W.B)
	t.assert_true(s.is_besieged(W.MEZZA))
	t.assert_eq(W.events_of(s, GameState.EV_GATES_OPENED).size(), 0)


func test_le_porte_dipendono_dalla_probabilita(t: TestContext) -> void:
	var s := W.world()
	s.rules.agents.gates_k = 0.0
	_siege_of_mezza(s)
	W.add_agent(s, W.A, W.MEZZA, "SPY", 10)
	AgentProcessor.process_year(s)
	t.assert_eq(s.province(W.MEZZA).owner, W.B, "k_porte = 0: mai")


# --- pulizia di fine anno ------------------------------------------------------------------------------------------------------------


func test_la_principessa_il_cui_personaggio_muore_sparisce(t: TestContext) -> void:
	var s := W.world()
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	s.character(princess.character_id).alive = false
	AgentProcessor.sync_year(s)
	t.assert_true(s.agent(princess.id) == null)
	t.assert_true(W.agent_of(s, W.B, AgentState.PRINCESS) != null, "l'altra resta")


func test_la_principessa_si_ritira_a_fine_anno_con_il_suo_agente(t: TestContext) -> void:
	var s := W.world()
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var c := s.character(princess.character_id)
	c.birth_year = s.year + 1 - s.rules.dynasty.princess_retire_age
	var id := princess.id
	_end_year(t, s)
	t.assert_false(c.alive)
	t.assert_eq(c.death_cause, "ritiro")
	t.assert_true(s.agent(id) == null, "l'agente se ne va con il personaggio")


func test_agenti_di_fazioni_scomparse_o_in_mare_spariscono(t: TestContext) -> void:
	var s := W.world()
	var gamma := W.agent_of(s, W.G, AgentState.EMISSARY)
	s.faction(W.G).alive = false
	var at_sea := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 1)
	at_sea.region = W.NORD
	var rebel := W.add_agent(s, W.A, W.ALTA, "EMISSARY", 1)
	rebel.faction = GameState.REBEL
	AgentProcessor.sync_year(s)
	t.assert_true(s.agent(gamma.id) == null, "fazione morta")
	t.assert_true(s.agent(at_sea.id) == null, "in mare")
	t.assert_true(s.agent(rebel.id) == null, "dei ribelli")
	t.assert_true(W.agent_of(s, W.A, AgentState.EMISSARY) != null, "gli altri restano")


func test_una_principessa_maggiorenne_senza_agente_ne_riceve_uno(t: TestContext) -> void:
	var s := W.world()
	var c := _princess_character(s, W.G, 1000 - 20)
	t.assert_true(AgentMissions.princess_agent(s, c) == null)
	AgentProcessor.sync_year(s)
	var a := AgentMissions.princess_agent(s, c)
	t.assert_true(a != null, "nata")
	t.assert_eq(a.faction, W.G)
	t.assert_eq(a.region, W.ORTO, "nella capitale (la regione del capo)")
	t.assert_eq(a.valour, c.acumen, "il valore e' l'acume")
	t.assert_eq(a.character_id, c.id)
	var events := W.events_of(s, GameState.EV_AGENT_RECRUITED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["origine"], "principessa")
	AgentProcessor.sync_year(s)
	t.assert_eq(s.agents_of(W.G).size(), 2, "una volta sola (emissario e principessa)")


func test_una_principessa_minorenne_non_ha_agente(t: TestContext) -> void:
	var s := W.world()
	var c := _princess_character(s, W.G, 1000 - 5)
	AgentProcessor.sync_year(s)
	t.assert_true(AgentMissions.princess_agent(s, c) == null)


func test_la_principessa_diventa_agente_compiuti_gli_anni(t: TestContext) -> void:
	var s := W.world()
	var young: Character = null
	for c in s.characters_of(W.A):
		if c.role == Character.ROLE_PRINCESS and AgentMissions.princess_agent(s, c) == null:
			young = c
	t.assert_true(young != null, "ALPHA ha una principessa di 8 anni senza agente")
	if young == null:
		return
	var ready_year := young.birth_year + s.rules.dynasty.princess_age
	while s.year + 1 < ready_year:
		_end_year(t, s)
		t.assert_true(AgentMissions.princess_agent(s, young) == null, "anno %d: troppo giovane" % s.year)
	_end_year(t, s)
	t.assert_true(AgentMissions.princess_agent(s, young) != null, "compiuti gli anni diventa agente")


func test_il_valore_della_principessa_segue_l_acume(t: TestContext) -> void:
	var s := W.world()
	var a := W.agent_of(s, W.A, AgentState.PRINCESS)
	s.character(a.character_id).acumen = 7
	AgentProcessor.sync_year(s)
	t.assert_eq(a.valour, s.character(a.character_id).effective(Character.ATTR_ACUMEN, s.rules, s.campaign))


# --- eventi -----------------------------------------------------------------------------------------------------------------------------


func test_i_nuovi_eventi_hanno_nomi_in_minuscolo_e_distinti(t: TestContext) -> void:
	var names: Array[String] = [
		GameState.EV_AGENT_RECRUITED, GameState.EV_AGENT_MOVED, GameState.EV_ALLIANCE_FORMED, GameState.EV_ALLIANCE_BROKEN,
		GameState.EV_TRUCE, GameState.EV_TRUCE_BROKEN, GameState.EV_TRUCE_EXPIRED, GameState.EV_PROPOSAL_REFUSED,
		GameState.EV_MARRIAGE, GameState.EV_BRIBE, GameState.EV_BRIBE_REFUSED, GameState.EV_ASSASSINATION,
		GameState.EV_ASSASSINATION_FAILED, GameState.EV_AGENT_CAPTURED, GameState.EV_GATES_OPENED, GameState.EV_MISSION_FAILED,
	]
	var seen := {}
	for n in names:
		t.assert_eq(n, n.to_lower(), "%s in minuscolo" % n)
		t.assert_false(n.contains(" "), "%s senza spazi" % n)
		t.assert_false(seen.has(n), "%s ripetuto" % n)
		seen[n] = true
	t.assert_eq(GameState.REL_WAR, "guerra")
	t.assert_eq(GameState.REL_ALLIANCE, "alleanza")
	t.assert_eq(GameState.REL_TRUCE, "tregua")
	t.assert_eq(GameState.REL_NEUTRAL, "neutrale")


# --- salvataggio -------------------------------------------------------------------------------------------------------------------------


func _restore(data: Dictionary, quiet: bool = true) -> GameState:
	var campaign := StartposLoader.load_file(W.STARTPOS)
	var units := UnitProdLoader.load_file(W.UNITS)
	var buildings := BuildingProdLoader.load_file(W.BUILDINGS)
	var rules := Rules.new()
	if quiet:
		rules = W.quiet_rules()
	var r := SaveGame.from_dict(data, campaign, units, buildings, rules)
	return r["stato"]


func _busy_world() -> GameState:
	var s := W.world(5)
	s.form_alliance(W.A, W.G)
	s.make_truce(W.B, W.G, 1006)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	GameCommands.order_mission(s, W.A, e.id, AgentMissions.ALLIANCE, W.B)
	var spy := W.add_agent(s, W.B, W.MEZZA, "SPY", 4)
	GameCommands.order_agent_move(s, W.B, spy.id, PackedStringArray([W.ORTO]))
	var assassin := W.add_agent(s, W.G, W.ORTO, "ASSASSIN", 3)
	GameCommands.order_mission(s, W.G, assassin.id, AgentMissions.ASSASSINATE, {"tipo": AgentMissions.TARGET_AGENT, "id": spy.id})
	return s


func test_il_salvataggio_ha_la_versione_corrente_e_i_dati_della_fase_5a(t: TestContext) -> void:
	var s := _busy_world()
	var d := SaveGame.to_dict(s)
	t.assert_eq(d["versione"], SaveGame.VERSION)
	t.assert_true(SaveGame.VERSION >= 5)
	t.assert_eq((d["alleanze"] as Array).size(), 1)
	t.assert_eq((d["tregue"] as Dictionary).size(), 1)
	var ag: Dictionary = {}
	for item in (d["agenti"] as Array):
		var entry: Dictionary = item
		if int(entry["id"]) == W.agent_of(s, W.A, AgentState.EMISSARY).id:
			ag = entry
	t.assert_true(ag.has("valore") and ag.has("nome") and ag.has("personaggio"))
	t.assert_true(ag.has("missione"), "la missione si salva")


func test_andata_e_ritorno_di_trattati_e_agenti(t: TestContext) -> void:
	var s := _busy_world()
	var back := _restore(SaveGame.to_dict(s))
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "stato identico")
	t.assert_true(back.is_allied(W.A, W.G))
	t.assert_eq(back.truce_until(W.B, W.G), 1006)
	for a in s.agents:
		var b := back.agent(a.id)
		t.assert_true(b != null, "agente %d" % a.id)
		t.assert_eq(b.valour, a.valour)
		t.assert_eq(b.name, a.name)
		t.assert_eq(b.character_id, a.character_id)
		t.assert_eq(b.path, a.path)
		t.assert_eq(b.mission.size(), a.mission.size())
	var assassin := W.agent_of(back, W.G, AgentState.ASSASSIN)
	t.assert_eq(assassin.mission["bersaglio"]["tipo"], AgentMissions.TARGET_AGENT)
	t.assert_eq(int(assassin.mission["bersaglio"]["id"]), W.agent_of(back, W.B, AgentState.SPY).id, "il bersaglio resta un intero")


func test_il_ricaricato_e_l_originale_giocano_allo_stesso_modo(t: TestContext) -> void:
	var s := _busy_world()
	W.always_accept(s)
	var back := _restore(SaveGame.to_dict(s))
	W.always_accept(back)
	for i in range(4):
		TurnProcessor.end_year(s)
		TurnProcessor.end_year(back)
		t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "anno %d" % s.year)


func test_un_salvataggio_della_versione_4_si_legge(t: TestContext) -> void:
	var s := W.world()
	var d := SaveGame.to_dict(s)
	d["versione"] = 4
	d.erase("alleanze")
	d.erase("tregue")
	var stripped: Array = []
	for item in (d["agenti"] as Array):
		var entry: Dictionary = (item as Dictionary).duplicate()
		for key in ["valore", "nome", "personaggio", "percorso", "rotta_mare", "missione"]:
			entry.erase(key)
		stripped.append(entry)
	d["agenti"] = stripped
	# in un salvataggio vero della versione 4 le principesse dello startpos non erano personaggi
	var linked := {}
	for a in s.agents:
		if a.character_id != 0:
			linked[a.character_id] = true
	var kept_characters: Array = []
	for item in (d["personaggi"] as Array):
		var cd: Dictionary = item
		if not linked.has(int(cd["id"])):
			kept_characters.append(cd)
	d["personaggi"] = kept_characters
	var back := _restore(JSON.parse_string(JSON.stringify(d)))
	t.assert_eq(back.alliances.size(), 0, "nessun trattato")
	t.assert_eq(back.truces.size(), 0)
	t.assert_eq(back.agents.size(), s.agents.size())
	for a in back.agents:
		t.assert_true(a.valour >= 0, "il valore predefinito")
		t.assert_true(a.name != "", "e un nome")
	t.assert_eq(W.agent_of(back, W.A, AgentState.EMISSARY).valour, back.rules.agents.start_valour)
	for faction_id in [W.A, W.B]:
		var princess := W.agent_of(back, faction_id, AgentState.PRINCESS)
		t.assert_true(princess.character_id != 0, "principessa ricollegata")
		var c := back.character(princess.character_id)
		t.assert_true(c != null and c.alive)


func test_versioni_non_supportate_sono_rifiutate(t: TestContext) -> void:
	var s := W.world()
	var d := SaveGame.to_dict(s)
	d["versione"] = SaveGame.VERSION + 1
	var campaign := StartposLoader.load_file(W.STARTPOS)
	var units := UnitProdLoader.load_file(W.UNITS)
	var buildings := BuildingProdLoader.load_file(W.BUILDINGS)
	var r := SaveGame.from_dict(d, campaign, units, buildings, Rules.new())
	t.assert_false(bool(r["ok"]))
