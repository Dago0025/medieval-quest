extends RefCounted
## Viaggio degli agenti verso province lontane e agenti degli Auror al massimo (richieste di Federico del 2026-11-13).
## Un agente mandato oltre la portata di un anno parte e prosegue da solo, una tappa all'anno (a piedi o via mare), fino
## all'arrivo (`AgentTravel`, `AgentState.destination`). Gli agenti delle fazioni con `agenti_al_massimo` (gli Auror) hanno
## sempre il valore massimo. Mondo di prova: agent_world.gd (ALTA-BASSA-MEZZA-ORTO a terra; ALTA e MEZZA con porto,
## collegate da NORD-SUD; gli agenti viaggiano via mare anche senza flotte).

const W := preload("res://tests/unit/agent_world.gd")


func _end_year(t: TestContext, s: GameState) -> void:
	var r := TurnProcessor.end_year(s)
	t.assert_true(bool(r["ok"]), "fine anno")
	t.assert_eq((r["errori"] as Array).size(), 0, "nessuna anomalia: %s" % str(r["errori"]))


# --- viaggio -----------------------------------------------------------------------------------------------------------


func test_il_percorso_e_il_piu_breve_in_anni(t: TestContext) -> void:
	var s := W.world()
	var land := AgentTravel.plan(s, W.A, W.BASSA, W.ORTO)
	t.assert_eq(land.size(), 2, "BASSA > MEZZA > ORTO")
	t.assert_eq(str(land[0]["regione"]), W.MEZZA)
	t.assert_true((land[0]["catena"] as PackedStringArray).is_empty(), "a piedi")
	var mixed := AgentTravel.plan(s, W.A, W.ALTA, W.ORTO)
	t.assert_eq(mixed.size(), 2, "via mare fino a MEZZA, poi a piedi: 2 anni invece di 3")
	t.assert_eq(str(mixed[0]["regione"]), W.MEZZA)
	t.assert_eq(mixed[0]["catena"], PackedStringArray([W.NORD, W.SUD]))
	t.assert_eq(str(mixed[1]["regione"]), W.ORTO)
	t.assert_true(AgentTravel.plan(s, W.A, W.ALTA, W.ALTA).is_empty(), "gia' li'")
	t.assert_true(AgentTravel.plan(s, W.A, W.ALTA, W.NORD).is_empty(), "non si va per mare come meta")
	t.assert_true(AgentTravel.plan(s, W.A, W.ALTA, "ID_NESSUNA").is_empty())


func test_l_agente_mandato_lontano_parte_e_arriva_da_solo(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)   # a BASSA
	var r := GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.ORTO]))
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_true(bool(r.get("viaggio", false)), "e' un viaggio")
	t.assert_eq(int(r["anni"]), 2)
	t.assert_eq(str(r["destinazione"]), W.ORTO)
	t.assert_eq(str(r["tappa"]), W.MEZZA)
	t.assert_eq(e.destination, W.ORTO)
	t.assert_eq(e.path, PackedStringArray([W.MEZZA]), "solo la tappa di quest'anno")
	t.assert_eq(AgentTravel.years_to(s, e, W.ORTO), 2)
	_end_year(t, s)
	t.assert_eq(e.region, W.MEZZA)
	t.assert_eq(e.destination, W.ORTO, "prosegue")
	t.assert_eq(e.path, PackedStringArray([W.ORTO]), "tappa dell'anno dopo gia' pronta")
	var moved := W.events_of(s, GameState.EV_AGENT_MOVED)
	t.assert_eq(str(moved[0].get("destinazione", "")), W.ORTO)
	_end_year(t, s)
	t.assert_eq(e.region, W.ORTO, "arrivato")
	t.assert_eq(e.destination, "")
	t.assert_true(e.path.is_empty())
	t.assert_true(bool(W.events_of(s, GameState.EV_AGENT_MOVED)[0].get("arrivato", false)))
	_end_year(t, s)
	t.assert_eq(e.region, W.ORTO, "fermo")


func test_il_viaggio_usa_il_mare_e_ripiega_a_terra_se_una_flotta_nemica_chiude_la_rotta(t: TestContext) -> void:
	var s := W.world()
	var a := W.add_agent(s, W.A, W.ALTA, "SPY", 3)
	var r := GameCommands.order_agent_move(s, W.A, a.id, PackedStringArray([W.ORTO]))
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_true(bool(r.get("via_mare", false)), "prima tappa via mare")
	t.assert_eq(int(r["anni"]), 2)
	s.declare_war(W.A, W.B)
	W.fleet(s, W.B, W.SUD)
	_end_year(t, s)
	t.assert_eq(a.region, W.ALTA, "la rotta e' chiusa: resta in porto")
	t.assert_eq(a.destination, W.ORTO, "il viaggio non si perde")
	t.assert_eq(a.path, PackedStringArray([W.BASSA]), "nuova tappa a piedi")
	t.assert_eq(W.events_of(s, GameState.EV_AGENT_JOURNEY_STOPPED).size(), 0)


func test_il_viaggio_senza_percorso_si_ferma_con_un_evento(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.ORTO]))
	e.destination = "ID_NESSUNA"   # meta che non si raggiunge piu'
	e.path = PackedStringArray()
	_end_year(t, s)
	t.assert_eq(e.destination, "")
	t.assert_true(e.path.is_empty())
	var stopped := W.events_of(s, GameState.EV_AGENT_JOURNEY_STOPPED)
	t.assert_eq(stopped.size(), 1)
	t.assert_eq(int(stopped[0]["agente"]), e.id)
	t.assert_eq(str(stopped[0]["verso"]), "ID_NESSUNA")


func test_annullare_o_dare_una_missione_ferma_il_viaggio(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.ORTO]))
	t.assert_true(bool(GameCommands.cancel_agent_move(s, W.A, e.id)["ok"]))
	t.assert_eq(e.destination, "", "annullato")
	GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.ORTO]))
	t.assert_true(bool(GameCommands.order_mission(s, W.A, e.id, AgentMissions.ALLIANCE, W.B)["ok"]))
	t.assert_eq(e.destination, "", "la missione sostituisce il viaggio")
	GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.ORTO]))
	t.assert_true(bool(GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.ALTA]))["ok"]))
	t.assert_eq(e.destination, "", "un movimento normale sostituisce il viaggio")


func test_la_destinazione_si_salva(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)
	GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.ORTO]))
	var back := AgentState.from_dict(e.to_dict())
	t.assert_eq(back.destination, W.ORTO)
	t.assert_eq(back.path, PackedStringArray([W.MEZZA]))
	var still := AgentState.from_dict(W.agent_of(s, W.B, AgentState.EMISSARY).to_dict())
	t.assert_eq(still.destination, "", "senza viaggio il campo non c'e'")
	t.assert_false(W.agent_of(s, W.B, AgentState.EMISSARY).to_dict().has("destinazione"))


# --- agenti al massimo -------------------------------------------------------------------------------------------------


func test_gli_auror_hanno_gli_agenti_al_massimo_nel_file(t: TestContext) -> void:
	var r := Rules.load_file()
	t.assert_true(r.max_agents_factions.has("FN_DANISH"), "agenti_al_massimo in auror.cfg")
	t.assert_eq(r.max_agents_factions.size(), 1, "solo gli Auror")
	t.assert_eq(r.agent_valour_floor("FN_DANISH"), r.agents.max_valour)
	t.assert_eq(r.agent_valour_floor("FN_ENGLISH"), 0)
	t.assert_eq(Rules.new().max_agents_factions, r.max_agents_factions, "predefiniti = file")


func _top_world() -> GameState:
	var campaign := StartposLoader.load_file(W.STARTPOS)
	var units := UnitProdLoader.load_file(W.UNITS)
	var buildings := BuildingProdLoader.load_file(W.BUILDINGS)
	var rules := W.quiet_rules()
	rules.max_agents_factions = PackedStringArray([W.A])
	var s := GameSetup.new_game(campaign, units, buildings, rules, 7)
	for c in s.characters:
		c.old_age = 500
	return s


func test_gli_agenti_della_fazione_nascono_e_restano_al_massimo(t: TestContext) -> void:
	var s := _top_world()
	var top := s.rules.agents.max_valour
	t.assert_eq(W.agent_of(s, W.A, AgentState.EMISSARY).valour, top, "emissario iniziale al massimo")
	t.assert_eq(W.agent_of(s, W.A, AgentState.PRINCESS).valour, top, "principessa al massimo")
	t.assert_eq(W.agent_of(s, W.B, AgentState.EMISSARY).valour, s.rules.agents.start_valour, "le altre fazioni no")
	var unit := s.units.get_unit("Assassin")
	if unit == null:
		unit = s.units.get_unit("Spy")
	t.assert_true(unit != null, "unita' di agente nel file di prova")
	var recruit := AgentProcessor.spawn_recruit(s, s.province(W.BASSA), unit)
	t.assert_eq(recruit.valour, top, "il reclutato nasce al massimo")
	var low := W.add_agent(s, W.A, W.ALTA, "ASSASSIN", 1)
	_end_year(t, s)
	t.assert_eq(low.valour, top, "a fine anno sale al massimo")
	t.assert_eq(W.agent_of(s, W.A, AgentState.PRINCESS).valour, top, "la principessa non torna all'acume")
	var other := W.add_agent(s, W.B, W.MEZZA, "ASSASSIN", 1)
	AgentProcessor.apply_faction_minimum(s)
	t.assert_eq(other.valour, 1, "le altre fazioni non cambiano")


func test_l_assassino_al_massimo_ha_le_probabilita_piu_alte_contro_i_nobili(t: TestContext) -> void:
	var s := _top_world()
	var ar := s.rules.agents
	t.assert_eq(ar.kill_chance(ar.step_noble + ar.max_valour), 0.97, "erede, principe o generale: ultimo gradino della tabella")
	t.assert_eq(ar.kill_chance(ar.step_leader + ar.max_valour), 0.95, "capo: 95%")
