extends RefCounted
## Test della logica pura dell'interfaccia della fase 5a (agenti e diplomazia): tipi e segnalini degli agenti,
## disposizione affiancata con gli eserciti, livello dei segnalini, menu delle missioni scelto da mission_options,
## messaggi degli ordini, righe del pannello della diplomazia, testi degli eventi nuovi e resoconto di fine anno,
## lealtà con la voce delle spie. Mondo di prova: tests/unit/agent_world.gd (ALPHA, BETA, GAMMA; ALPHA è il giocatore).
## Regioni: ALTA, BASSA (ALPHA), MEZZA (BETA), ORTO (GAMMA); BASSA confina con ALTA e MEZZA; l'emissario di ALPHA sta in
## BASSA, quello di BETA in MEZZA, quello di GAMMA in ORTO.

const W := preload("res://tests/unit/agent_world.gd")
const ArmyLayerScript := preload("res://scenes/army_layer.gd")
const EPS := 1.0e-4


func _world() -> GameState:
	var s := W.world()
	s.faction(W.A).is_player = true
	return s


func _emissary(s: GameState, faction_id: String = W.A) -> AgentState:
	return W.agent_of(s, faction_id, AgentState.EMISSARY)


func _ev(kind: String, data: Dictionary) -> Dictionary:
	var e := {"tipo": kind, "anno": 1000}
	e.merge(data)
	return e


## Voci (Dictionary) di un piano del menu.
func _entries(plan: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(plan["voci"])
	return out


func _options(s: GameState, agent: AgentState) -> Array:
	var r := GameCommands.mission_options(s, agent.faction, agent.id)
	return r["missioni"]


# --- tipi e segnalini -------------------------------------------------------------------------------------------


func test_iniziali_e_nomi_dei_tipi(t: TestContext) -> void:
	t.assert_eq(CampaignUiAgents.type_letter("EMISSARY"), "E")
	t.assert_eq(CampaignUiAgents.type_letter("PRINCESS"), "P")
	t.assert_eq(CampaignUiAgents.type_letter("SPY"), "S")
	t.assert_eq(CampaignUiAgents.type_letter("ASSASSIN"), "A")
	for religious in ["BISHOP", "CARDINAL", "PRIEST", "SHAMAN", "ORTHODOX_BISHOP", "MULLAH", "ULAMA"]:
		t.assert_eq(CampaignUiAgents.type_letter(religious), "V", religious)
	t.assert_eq(CampaignUiAgents.type_letter("INQUISITOR"), "I")
	t.assert_eq(CampaignUiAgents.type_letter("GRAND_INQUISITOR"), "I")
	t.assert_eq(CampaignUiAgents.type_letter("ALTRO"), "?")
	t.assert_eq(CampaignUiAgents.type_label("EMISSARY"), "Emissario")
	t.assert_eq(CampaignUiAgents.type_label("ORTHODOX_BISHOP"), "Vescovo ortodosso")
	t.assert_eq(CampaignUiAgents.type_label("GRAND_INQUISITOR"), "Gran inquisitore")
	t.assert_eq(CampaignUiAgents.type_label("MAGO_STRANO"), "Mago Strano", "tipo sconosciuto: id leggibile")
	for kind in AgentState.RELIGIOUS_TYPES:
		t.assert_true(CampaignUiAgents.TYPE_LABELS.has(kind), "etichetta per %s" % kind)


func test_testo_del_segnalino_e_titolo(t: TestContext) -> void:
	var s := _world()
	var a := W.add_agent(s, W.A, W.BASSA, "SPY", 4)
	a.name = "Marco"
	t.assert_eq(CampaignUiAgents.marker_text(a), "S4")
	t.assert_eq(CampaignUiAgents.title(a), "Spia Marco")
	a.valour = 10
	t.assert_eq(CampaignUiAgents.marker_text(a), "S10")
	a.valour = -1
	t.assert_eq(CampaignUiAgents.marker_text(a), "S-", "valore non assegnato")
	a.name = ""
	t.assert_eq(CampaignUiAgents.title(a), "Spia #%d" % a.id)
	t.assert_eq(CampaignUiAgents.label_of(s, a.id), "Spia #%d" % a.id)
	t.assert_eq(CampaignUiAgents.label_of(s, 9999, "ASSASSIN"), "Assassino", "agente sparito: il tipo")
	t.assert_eq(CampaignUiAgents.label_of(s, 9999), "Un agente")


func test_visibilita_degli_agenti(t: TestContext) -> void:
	var s := _world()
	var spy := W.add_agent(s, W.B, W.BASSA, "SPY", 2)
	var emissary := _emissary(s, W.B)
	t.assert_false(CampaignUiAgents.HIDE_FOREIGN_INVISIBLE, "per ora la mappa mostra anche le spie nemiche")
	t.assert_true(CampaignUiAgents.is_visible_to(s, spy, W.A))
	t.assert_true(CampaignUiAgents.is_visible_to(s, emissary, W.A))
	t.assert_eq(CampaignUiAgents.visible_agents(s, W.A).size(), s.agents.size())
	t.assert_eq(CampaignUiAgents.visible_agents_in(s, W.BASSA, W.A).size(), 2, "emissario e spia in BASSA")


func test_percorso_della_freccia_dell_agente(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	t.assert_true(CampaignUiAgents.route_ids(a).is_empty(), "senza ordini nessuna freccia")
	GameCommands.order_agent_move(s, W.A, a.id, PackedStringArray([W.MEZZA]))
	t.assert_eq(CampaignUiAgents.route_ids(a), PackedStringArray([W.BASSA, W.MEZZA]))
	# via mare: partenza, zone della catena, destinazione
	a.path = PackedStringArray([W.MEZZA])
	a.sea_route = PackedStringArray([W.NORD, W.SUD])
	t.assert_eq(CampaignUiAgents.route_ids(a), PackedStringArray([W.BASSA, W.NORD, W.SUD, W.MEZZA]))


# --- disposizione dei segnalini ----------------------------------------------------------------------------------


func test_agenti_raggruppati_per_regione(t: TestContext) -> void:
	var s := _world()
	var extra := W.add_agent(s, W.A, W.BASSA, "SPY", 1)
	var groups := MarkerLayout.group_agents_by_region(s.agents)
	var in_bassa: PackedInt32Array = groups[W.BASSA]
	t.assert_eq(in_bassa.size(), 2)
	t.assert_true(in_bassa[0] < in_bassa[1], "in ordine di id")
	t.assert_true(in_bassa.has(extra.id))
	t.assert_true(groups.has(W.ALTA), "la principessa di ALPHA sta in ALTA")
	var none: Array[AgentState] = []
	t.assert_true(MarkerLayout.group_agents_by_region(none).is_empty())


func test_disposizione_mista_senza_sovrapposizioni(t: TestContext) -> void:
	var spacing := 28.0
	for armies in range(0, 7):
		for agents in range(0, 7):
			var layout := MarkerLayout.mixed_slots(armies, agents, spacing)
			var army_slots: PackedVector2Array = layout["eserciti"]
			var agent_slots: PackedVector2Array = layout["agenti"]
			t.assert_eq(army_slots.size(), armies)
			t.assert_eq(agent_slots.size(), agents)
			var all := PackedVector2Array()
			all.append_array(army_slots)
			all.append_array(agent_slots)
			for i in range(all.size()):
				for j in range(i + 1, all.size()):
					t.assert_true(all[i].distance_to(all[j]) >= spacing - EPS, "%d eserciti e %d agenti: %d e %d si sovrappongono" % [armies, agents, i, j])
			t.assert_eq(int(layout["righe"]), ceili((armies + agents) / float(MarkerLayout.ROW_MAX)))


func test_senza_agenti_la_disposizione_e_quella_di_prima(t: TestContext) -> void:
	for armies in range(1, 9):
		var layout := MarkerLayout.mixed_slots(armies, 0, 28.0)
		t.assert_eq(layout["eserciti"], MarkerLayout.slot_offsets(armies, 28.0), "%d eserciti" % armies)
	var only_agents := MarkerLayout.mixed_slots(0, 3, 28.0)
	t.assert_eq(only_agents["agenti"], MarkerLayout.slot_offsets(3, 28.0))
	t.assert_eq(MarkerLayout.mixed_slots(-2, -1, 28.0)["righe"], 0)


func test_il_livello_disegna_e_trova_gli_agenti(t: TestContext) -> void:
	var layer: ArmyLayerScript = ArmyLayerScript.new()
	layer.set_view(Vector2(100.0, 100.0), 1.0, Vector2(1280.0, 720.0))   # l'ancora (100,100) cade al centro dello schermo
	layer.add_agent_marker(7, Vector2(100.0, 100.0), Vector2.ZERO, Color.RED, "E3", true, false)
	layer.add_agent_marker(8, Vector2(100.0, 100.0), Vector2(28.0, 0.0), Color.BLUE, "S1", false, true)
	layer.add_marker(3, Vector2(100.0, 100.0), Vector2(-28.0, 0.0), Color.GREEN, "2", false, true, false)
	t.assert_eq(layer.agent_marker_count(), 2)
	t.assert_eq(layer.agent_marker_text(0), "E3")
	t.assert_eq(layer.agent_marker_text(5), "", "fuori intervallo")
	var center := Vector2(640.0, 360.0)
	t.assert_eq(layer.agent_at(center), 7)
	t.assert_eq(layer.agent_at(center + Vector2(28.0, 0.0)), 8)
	t.assert_eq(layer.agent_at(center + Vector2(0.0, 40.0)), 0, "nessun agente sotto")
	t.assert_eq(layer.army_at(center + Vector2(-28.0, 0.0)), 3, "l'esercito accanto si trova ancora")
	t.assert_eq(layer.army_at(center), 0, "gli agenti non sono eserciti")
	layer.add_agent_marker(9, Vector2(100.0, 100.0), Vector2.ZERO, Color.WHITE, "A2", true, false)
	t.assert_eq(layer.agent_at(center), 9, "con segnalini sovrapposti vince l'ultimo")
	layer.clear_all()
	t.assert_eq(layer.agent_marker_count(), 0)
	t.assert_eq(layer.agent_at(center), 0)
	layer.free()


# --- descrizione dell'agente ---------------------------------------------------------------------------------------


func test_descrizione_dell_agente_con_missione(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	a.name = "Giovanni"
	var plain := CampaignUiAgents.describe_agent(s, a)
	t.assert_true(plain.begins_with("Emissario Giovanni (Alpha)"), plain)
	t.assert_true(plain.contains("Valore: 2 · posizione: Bassa"), plain)
	t.assert_true(plain.contains("Nessuna missione"), plain)
	t.assert_eq(CampaignUiAgents.mission_line(s, a), "")
	var r := GameCommands.order_mission(s, W.A, a.id, AgentMissions.ALLIANCE, W.B)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(CampaignUiAgents.mission_line(s, a), "Proporre un'alleanza a Beta (Mezza): in avvicinamento")
	var busy := CampaignUiAgents.describe_agent(s, a)
	t.assert_true(busy.contains("Movimento: Mezza"), busy)
	t.assert_true(busy.contains("Missione: Proporre un'alleanza a Beta (Mezza)"), busy)
	var spy := W.add_agent(s, W.A, W.BASSA, "SPY", 1)
	# dal 18/11/2026 anche la spia ha missioni da ordinare (spionaggio, malcontento, sabotaggio, porte)
	t.assert_true(CampaignUiAgents.describe_agent(s, spy).contains("Nessuna missione"), "la spia ha missioni ma nessuna in corso")


func test_descrizione_della_principessa(t: TestContext) -> void:
	var s := _world()
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var text := CampaignUiAgents.describe_agent(s, princess)
	t.assert_true(text.contains("Principessa "), text)
	t.assert_true(text.contains("anni"), text)


func test_elenco_degli_agenti_della_provincia(t: TestContext) -> void:
	var s := _world()
	var spy := W.add_agent(s, W.B, W.BASSA, "SPY", 2)
	spy.name = "Ombra"
	var mine := _emissary(s)
	mine.name = "Luca"
	var lines := CampaignUiAgents.province_lines(s, W.BASSA, W.A)
	t.assert_eq(lines.size(), 2)
	t.assert_true(bool(lines[0]["mio"]), "prima i propri")
	t.assert_eq(lines[0]["id"], mine.id)
	t.assert_eq(lines[0]["testo"], "[E] Emissario Luca · valore 2")
	t.assert_false(bool(lines[1]["mio"]))
	t.assert_eq(lines[1]["testo"], "[S] Spia Ombra · valore 2 · Beta")
	mine.mission = {"tipo": "alleanza", "bersaglio": W.B, "regione": W.MEZZA, "avvicinamento": true}
	t.assert_eq(CampaignUiAgents.province_lines(s, W.BASSA, W.A)[0]["testo"], "[E] Emissario Luca · valore 2 · in missione")
	t.assert_true(CampaignUiAgents.province_lines(s, W.SOLA, W.A).is_empty())


# --- reclutamento -------------------------------------------------------------------------------------------------------


func test_gli_agenti_reclutabili_hanno_un_etichetta(t: TestContext) -> void:
	var s := _world()
	var units := s.units
	var emissary_unit: UnitType = null
	var troop_unit: UnitType = null
	for u in units.agents():
		if u.type_name == AgentState.EMISSARY:
			emissary_unit = u
	for u in units.military():
		troop_unit = u
	t.assert_true(emissary_unit != null, "l'emissario è nel file prod di prova")
	t.assert_true(CampaignUiAgents.is_recruitable_agent(emissary_unit))
	t.assert_false(CampaignUiAgents.is_recruitable_agent(troop_unit), "le truppe non sono agenti")
	for u in units.agents():
		var expected := AgentState.is_recruitable_type(u.type_name)
		t.assert_eq(CampaignUiAgents.is_recruitable_agent(u), expected, u.id)
	var text := CampaignUiAgents.recruit_text(emissary_unit, 150, 2)
	t.assert_true(text.begins_with("[Agente] "), text)
	t.assert_true(text.ends_with("150 denari, 2 anni"), text)
	t.assert_true(CampaignUiAgents.recruit_tip(emissary_unit, "Costo 150.").contains("alleanze"))
	t.assert_eq(CampaignUiAgents.queue_label(s, emissary_unit.id), "[Agente] " + CampaignUiText.agent_unit_name(emissary_unit.id))
	t.assert_eq(CampaignUiAgents.queue_label(s, troop_unit.id), CampaignUiText.unit_name(troop_unit.id), "le truppe in coda restano come prima")
	var check := GameCommands.can_queue_unit(s, W.A, W.BASSA, emissary_unit.id)
	t.assert_true(bool(check["ok"]) or str(check["errore"]) != "", "can_queue_unit risponde per gli agenti")


# --- menu delle missioni --------------------------------------------------------------------------------------------------


func test_clic_su_una_regione_senza_missioni_muove(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	var plan := CampaignUiAgents.click_plan(s, a, _options(s, a), W.ALTA)
	t.assert_eq(plan["azione"], CampaignUiAgents.PLAN_MOVE, "ALTA è di ALPHA: nessuna proposta possibile")
	t.assert_true(_entries(plan).is_empty())
	t.assert_eq(CampaignUiAgents.click_plan(s, a, _options(s, a), W.ORTO)["azione"], CampaignUiAgents.PLAN_MOVE, "fuori portata: ci pensa order_agent_move")
	t.assert_eq(CampaignUiAgents.click_plan(s, a, _options(s, a), "")["azione"], CampaignUiAgents.PLAN_NONE)


func test_clic_sulla_regione_dell_agente_annulla(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	t.assert_eq(CampaignUiAgents.click_plan(s, a, _options(s, a), W.BASSA)["azione"], CampaignUiAgents.PLAN_CANCEL)


func test_menu_di_una_regione_straniera(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	var options := _options(s, a)
	var plan := CampaignUiAgents.click_plan(s, a, options, W.MEZZA)
	t.assert_eq(plan["azione"], CampaignUiAgents.PLAN_MENU)
	var entries := _entries(plan)
	t.assert_eq(entries[0]["azione"], CampaignUiAgents.ACTION_MOVE, "prima 'Muovi'")
	t.assert_eq(entries[0]["testo"], "Muovi a Mezza")
	t.assert_eq(entries[0]["regione"], W.MEZZA)
	t.assert_eq(entries.size(), 2, "muovi e alleanza (nessuna guerra, nessun esercito corruttibile)")
	var alliance := entries[1]
	t.assert_eq(alliance["azione"], CampaignUiAgents.ACTION_MISSION)
	t.assert_eq(alliance["tipo"], AgentMissions.ALLIANCE)
	t.assert_eq(alliance["bersaglio"], W.B)
	var chance := 0.0
	for o in options:
		var opt: Dictionary = o
		if opt["tipo"] == AgentMissions.ALLIANCE and opt["bersaglio"] == W.B:
			chance = float(opt["probabilita"])
	t.assert_eq(alliance["testo"], "Proponi un'alleanza a Beta · %d%%" % roundi(chance * 100.0))
	t.assert_true(str(alliance["tooltip"]).contains("l'agente ci va prima"), str(alliance["tooltip"]))


func test_il_menu_porta_il_comando_giusto_a_order_mission(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	var entries := _entries(CampaignUiAgents.click_plan(s, a, _options(s, a), W.MEZZA))
	var chosen := entries[1]
	var r := GameCommands.order_mission(s, W.A, a.id, str(chosen["tipo"]), chosen["bersaglio"])
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(a.mission["tipo"], AgentMissions.ALLIANCE)
	var who := CampaignUiAgents.title(a)
	var shown_chance := CampaignUiAgents.chance_text(float(r["probabilita"]))
	t.assert_eq(CampaignUiAgents.ordered_text(s, a, r), "%s: proporre un'alleanza a Beta a Mezza (riuscita %s). L'agente ci va prima." % [who, shown_chance])
	# dopo l'ordine, il clic sulla propria regione offre l'annullamento
	var again := CampaignUiAgents.click_plan(s, a, _options(s, a), W.BASSA)
	t.assert_eq(again["azione"], CampaignUiAgents.PLAN_CANCEL, "senza missioni possibili qui: annulla")


func test_corruzione_su_un_segnalino_di_esercito(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	var general_army := W.general_army(s, W.B, W.MEZZA)
	var options := _options(s, a)
	# clic sul segnalino: la proposta alla sua fazione (come nell'originale, emissario sopra il re) e la corruzione di quell'esercito
	var on_army := _entries(CampaignUiAgents.click_plan(s, a, options, W.MEZZA, general_army.id))
	t.assert_eq(on_army.size(), 3, "muovi, alleanza con Beta e corrompi")
	t.assert_eq(on_army[1]["tipo"], AgentMissions.ALLIANCE)
	t.assert_eq(on_army[1]["bersaglio"], W.B)
	t.assert_eq(on_army[2]["tipo"], AgentMissions.BRIBE)
	t.assert_eq(on_army[2]["bersaglio"], general_army.id)
	var text := str(on_army[2]["testo"])
	t.assert_true(text.begins_with("Corrompi l'esercito %d di Beta (60 uomini) · " % general_army.id), text)
	t.assert_true(text.contains(" denari"), text)
	t.assert_true(str(on_army[2]["tooltip"]).contains("solo se l'esercito accetta"), str(on_army[2]["tooltip"]))
	# clic sulla regione: alleanza e corruzione, nell'ordine di mission_options
	var on_region := _entries(CampaignUiAgents.click_plan(s, a, options, W.MEZZA))
	t.assert_eq(on_region.size(), 3)
	t.assert_eq(on_region[1]["tipo"], AgentMissions.ALLIANCE)
	t.assert_eq(on_region[2]["tipo"], AgentMissions.BRIBE)
	# un esercito dello stesso agente non compare tra i bersagli di un'altra regione
	var elsewhere := _entries(CampaignUiAgents.click_plan(s, a, options, W.ALTA))
	t.assert_true(elsewhere.is_empty())


func test_corruzione_con_tesoro_insufficiente_si_avverte(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	var general_army := W.general_army(s, W.B, W.MEZZA)
	s.faction(W.A).treasury = 0
	var on_army := _entries(CampaignUiAgents.click_plan(s, a, _options(s, a), W.MEZZA, general_army.id))
	t.assert_true(str(on_army[2]["testo"]).ends_with("(tesoro insufficiente)"), str(on_army[2]["testo"]))
	var ordered := GameCommands.order_mission(s, W.A, a.id, AgentMissions.BRIBE, general_army.id)
	t.assert_true(bool(ordered["ok"]), "l'ordine resta possibile: si paga solo se l'esercito accetta")
	t.assert_true(CampaignUiAgents.ordered_text(s, a, ordered).contains("denari a fine anno se accetta"))


func test_assassinio_per_nome_e_ruolo(t: TestContext) -> void:
	var s := _world()
	var killer := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	var options := _options(s, killer)
	var entries := _entries(CampaignUiAgents.click_plan(s, killer, options, W.MEZZA))
	t.assert_eq(entries[0]["azione"], CampaignUiAgents.ACTION_MOVE)
	var leader := s.leader_of(W.B)
	var leader_text := ""
	var princess_text := ""
	for e in entries:
		var text := str(e["testo"])
		if e["tipo"] == AgentMissions.ASSASSINATE:
			t.assert_true(text.begins_with("Assassina "), text)
			t.assert_true(text.contains(" · "), "porta la probabilità: %s" % text)
			if text.contains(leader.full_name()):
				leader_text = text
			if text.contains("Principessa"):
				princess_text = text
	t.assert_true(leader_text.contains("(capo di Beta)"), "il capo si elenca per nome e ruolo: %s" % leader_text)
	t.assert_true(princess_text.contains("(valore "), "un agente per tipo e valore: %s" % princess_text)
	# clic sul segnalino dell'esercito del capo: l'assassinio del comandante (e nient'altro)
	var leader_army := W.land_army(s, W.B, W.MEZZA)
	var on_army := _entries(CampaignUiAgents.click_plan(s, killer, options, W.MEZZA, leader_army.id))
	t.assert_eq(on_army.size(), 2, "muovi e assassina il comandante")
	t.assert_true(str(on_army[1]["testo"]).contains(leader.full_name()), str(on_army[1]["testo"]))
	# l'ordine riesce e il messaggio dice chi e dove
	var r := GameCommands.order_mission(s, W.A, killer.id, str(on_army[1]["tipo"]), on_army[1]["bersaglio"])
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_true(CampaignUiAgents.ordered_text(s, killer, r).contains("assassinare %s" % leader.full_name()), CampaignUiAgents.ordered_text(s, killer, r))


func test_nozze_della_principessa(t: TestContext) -> void:
	var s := _world()
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	princess.region = W.BASSA
	var general := W.add_general(s, W.A, W.BASSA)
	general.forename = "Guglielmo"
	var options := _options(s, princess)
	var entries := _entries(CampaignUiAgents.click_plan(s, princess, options, W.BASSA))
	var found := false
	for e in entries:
		if e["tipo"] == AgentMissions.BRIDE and e["bersaglio"] == general.id:
			found = true
			t.assert_eq(e["testo"], "Concedi la mano a Guglielmo (generale) · certa")
	t.assert_true(found, "la sposa generale compare con il nome del generale")


func test_voci_dalla_lista_scritta_a_mano(t: TestContext) -> void:
	# la scelta delle voci dipende solo dall'elenco di mission_options, non dalla simulazione
	var s := _world()
	var options: Array = [
		{"tipo": "tregua", "bersaglio": W.G, "regione": W.ORTO, "probabilita": 0.3, "prezzo": 0, "tesoro_sufficiente": true},
		{"tipo": "alleanza", "bersaglio": W.B, "regione": W.MEZZA, "probabilita": 0.45, "prezzo": 0, "tesoro_sufficiente": true},
	]
	var picked := CampaignUiAgents.select_options(s, options, W.MEZZA, 0)
	t.assert_eq(picked.size(), 1)
	t.assert_eq(picked[0]["tipo"], "alleanza")
	# la proposta alla fazione proprietaria vale anche se si svolgerebbe in un'altra regione
	var elsewhere: Array = [{"tipo": "alleanza", "bersaglio": W.B, "regione": W.BASSA, "probabilita": 0.4}]
	t.assert_eq(CampaignUiAgents.select_options(s, elsewhere, W.MEZZA, 0).size(), 1)
	t.assert_true(CampaignUiAgents.select_options(s, elsewhere, W.ORTO, 0).is_empty())
	t.assert_true(CampaignUiAgents.select_options(s, [], W.MEZZA, 0).is_empty())
	t.assert_eq(CampaignUiAgents.chance_text(0.456), "46%")
	t.assert_eq(CampaignUiAgents.chance_text(0.0), "0%")
	t.assert_eq(CampaignUiAgents.chance_text(1.0), "certa")
	var text := CampaignUiAgents.option_text(s, options[1])
	t.assert_eq(text, "Proponi un'alleanza a Beta · 45%")


func test_messaggio_del_movimento(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	a.name = "Luca"
	var r := GameCommands.order_agent_move(s, W.A, a.id, PackedStringArray([W.MEZZA]))
	t.assert_true(bool(r["ok"]))
	t.assert_eq(CampaignUiAgents.moved_text(s, a, W.MEZZA, r), "Emissario Luca: movimento verso Mezza.")
	var sea := {"ok": true, "via_mare": true, "catena": [W.NORD, W.SUD]}
	var sea_text := CampaignUiAgents.moved_text(s, a, W.MEZZA, sea)
	t.assert_true(sea_text.contains("trasporto via mare verso Mezza"), sea_text)
	t.assert_true(sea_text.contains(CampaignUiText.region_name(s, W.NORD)), sea_text)


## Viaggio verso una provincia lontana (richiesta del 2026-11-13): il messaggio dice la meta, gli anni e la prima tappa;
## la descrizione dell'agente dice dove va e quando arriva; il registro aggiunge la meta o la fine del viaggio.
func test_messaggio_e_descrizione_del_viaggio(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	a.name = "Luca"
	var r := GameCommands.order_agent_move(s, W.A, a.id, PackedStringArray([W.ORTO]))
	t.assert_true(bool(r["ok"]), str(r))
	var text := CampaignUiAgents.moved_text(s, a, W.ORTO, r)
	t.assert_eq(text, "Emissario Luca: in viaggio verso Orto, arrivo in 2 anni (prima tappa Mezza).")
	var lines := CampaignUiAgents.describe_agent(s, a)
	t.assert_true(lines.contains("In viaggio verso Orto · arrivo in 2 anni"), lines)
	t.assert_true(lines.contains("Tappa di quest'anno: Mezza"), lines)
	t.assert_eq(CampaignUiAgents.years_text(1), "1 anno")
	t.assert_eq(CampaignUiAgents.years_text(3), "3 anni")
	var moved := {"tipo": GameState.EV_AGENT_MOVED, "fazione": W.A, "agente": a.id, "tipo_agente": "EMISSARY", "da": W.BASSA, "a": W.MEZZA, "destinazione": W.ORTO}
	t.assert_true(CampaignUiText.format_event(s, moved).ends_with("In viaggio verso Orto."), CampaignUiText.format_event(s, moved))
	moved.erase("destinazione")
	moved["arrivato"] = true
	t.assert_true(CampaignUiText.format_event(s, moved).ends_with("Fine del viaggio."))
	var stopped := {"tipo": GameState.EV_AGENT_JOURNEY_STOPPED, "fazione": W.A, "agente": a.id, "tipo_agente": "EMISSARY", "regione": W.BASSA, "verso": W.ORTO}
	t.assert_true(CampaignUiText.format_event(s, stopped).contains("nessun percorso porta più a Orto"), CampaignUiText.format_event(s, stopped))


## Nomi degli agenti come nella versione italiana dell'originale (Loc/Italian/names.txt).
func test_nomi_italiani_dei_religiosi(t: TestContext) -> void:
	t.assert_eq(CampaignUiAgents.type_label("MULLAH"), "Ulema")
	t.assert_eq(CampaignUiAgents.type_label("ULAMA"), "Imam")
	var shaman := AgentState.new(50, W.A, W.ALTA, "Shaman", "PRIEST", 1000)
	t.assert_eq(CampaignUiAgents.agent_label(shaman), "Sciamano", "lo sciamano e' di tipo PRIEST ma ha il suo nome")
	var priest := AgentState.new(51, W.A, W.ALTA, "Priest", "PRIEST", 1000)
	t.assert_eq(CampaignUiAgents.agent_label(priest), "Sacerdote")


# --- diplomazia -------------------------------------------------------------------------------------------------------------


func test_religione_e_relazione_in_parole(t: TestContext) -> void:
	t.assert_eq(CampaignUiAgents.religion_name("REL_CATHOLIC"), "Cattolica")
	t.assert_eq(CampaignUiAgents.religion_name("REL_ISLAMIC"), "Musulmana")
	t.assert_eq(CampaignUiAgents.religion_name("REL_ORTHODOX"), "Ortodossa")
	t.assert_eq(CampaignUiAgents.religion_name("REL_PAGAN"), "Pagana")
	t.assert_eq(CampaignUiAgents.religion_name(""), "sconosciuta")
	t.assert_eq(CampaignUiAgents.religion_name("REL_ZOROASTRIAN"), "Zoroastrian")
	t.assert_eq(CampaignUiAgents.relation_text(GameState.REL_WAR), "In guerra")
	t.assert_eq(CampaignUiAgents.relation_text(GameState.REL_ALLIANCE), "Alleata")
	t.assert_eq(CampaignUiAgents.relation_text(GameState.REL_NEUTRAL), "Neutrale")
	t.assert_eq(CampaignUiAgents.relation_text(GameState.REL_TRUCE, 1010), "Tregua fino al 1010")
	t.assert_eq(CampaignUiAgents.relation_text(GameState.REL_TRUCE), "Tregua")


func test_righe_della_diplomazia(t: TestContext) -> void:
	var s := _world()
	s.form_alliance(W.A, W.B)
	s.declare_war(W.A, W.G)
	var rows := CampaignUiAgents.diplomacy_rows(s, "fn_alpha")
	t.assert_eq(rows.size(), 3, "i ribelli non compaiono")
	t.assert_true(bool(rows[0]["giocatore"]), "il giocatore in cima")
	t.assert_eq(rows[0]["fazione"], W.A)
	t.assert_eq(rows[0]["relazione"], "")
	t.assert_eq(rows[0]["testo_relazione"], "Tu")
	t.assert_eq(rows[0]["province"], 2, "ALTA e BASSA")
	t.assert_eq(rows[1]["fazione"], W.B)
	t.assert_eq(rows[1]["relazione"], GameState.REL_ALLIANCE)
	t.assert_eq(rows[1]["testo_relazione"], "Alleata")
	t.assert_eq(rows[1]["religione"], "Musulmana")
	t.assert_eq(rows[2]["fazione"], W.G)
	t.assert_eq(rows[2]["relazione"], GameState.REL_WAR)
	t.assert_eq(rows[2]["testo_relazione"], "In guerra")
	t.assert_eq(rows[2]["religione"], "Cattolica")
	# chi e' in guerra con chi (al posto dell'influenza del capo)
	t.assert_false(rows[1].has("influenza"), "l'influenza del capo non c'e' piu'")
	t.assert_eq(rows[0]["guerre"], [W.G], "Alpha in guerra con Gamma")
	t.assert_eq(rows[0]["testo_guerre"], "Gamma")
	t.assert_eq(rows[1]["guerre"], [], "Beta in pace con tutti")
	t.assert_eq(rows[1]["testo_guerre"], "-")
	t.assert_eq(rows[2]["guerre"], [W.A])
	s.declare_war(W.B, W.G)
	var again := CampaignUiAgents.diplomacy_rows(s, W.A)
	t.assert_eq(again[2]["guerre"], [W.A, W.B], "Gamma in guerra con Alpha e Beta, nell'ordine delle righe")
	t.assert_eq(again[2]["testo_guerre"], "Alpha, Beta")


func test_tregua_con_scadenza_e_fazioni_morte(t: TestContext) -> void:
	var s := _world()
	s.declare_war(W.A, W.B)
	s.end_war(W.A, W.B)
	s.make_truce(W.A, W.B, 1010)
	var rows := CampaignUiAgents.diplomacy_rows(s, W.A)
	var beta: Dictionary = {}
	for r in rows:
		if r["fazione"] == W.B:
			beta = r
	t.assert_eq(beta["testo_relazione"], "Tregua fino al 1010")
	t.assert_eq(beta["fino_al"], 1010)
	t.assert_eq(rows[2]["testo_relazione"], "Neutrale", "GAMMA: nessun trattato")
	s.faction(W.G).alive = false
	t.assert_eq(CampaignUiAgents.diplomacy_rows(s, W.A).size(), 2, "una fazione morta non compare")


func test_celle_del_pannello_della_diplomazia(t: TestContext) -> void:
	var s := _world()
	var rows := CampaignUiAgents.diplomacy_rows(s, W.A)
	t.assert_eq(CampaignUiAgents.diplomacy_headers().size(), 5)
	var mine := CampaignUiAgents.diplomacy_cells(rows[0])
	t.assert_eq(mine.size(), 5, "una cella per colonna")
	t.assert_eq(mine[0], "Alpha (tu)")
	t.assert_eq(mine[1], "Tu")
	t.assert_eq(mine[2], "Cattolica")
	t.assert_eq(mine[4], "2")
	var other := CampaignUiAgents.diplomacy_cells(rows[1])
	t.assert_eq(other[0], "Beta")
	t.assert_eq(other[1], "Neutrale")
	t.assert_eq(CampaignUiAgents.diplomacy_headers()[3], "In guerra con")
	t.assert_eq(other[3], "-", "nessuna guerra")
	s.declare_war(W.A, W.B)
	var warring := CampaignUiAgents.diplomacy_rows(s, W.A)
	t.assert_eq(CampaignUiAgents.diplomacy_cells(warring[0])[3], "Beta")
	t.assert_eq(CampaignUiAgents.diplomacy_cells(warring[1])[3], "Alpha")


# --- lealtà con le spie -------------------------------------------------------------------------------------------------------


func test_etichette_dei_termini_nuovi(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.term_label("spie"), "Spie")
	t.assert_eq(CampaignUiText.term_label("spies"), "Spie")
	t.assert_eq(CampaignUiText.term_label("inquisitore"), "Inquisitore")
	t.assert_eq(CampaignUiText.term_label("inquisitor"), "Inquisitore")
	t.assert_eq(CampaignUiText.term_label("religione"), "Religione")
	t.assert_eq(CampaignUiText.term_label("religion"), "Religione")
	t.assert_eq(CampaignUiText.term_label("ribellione_regionale"), "Ribellione regionale")
	var terms := CampaignUiText.loyalty_terms_of({"spie": 5, "religione": -15, "inquisitore": 3})
	t.assert_eq(terms.size(), 3)
	t.assert_eq(terms[0], {"nome": "Spie", "valore": "+5"})
	t.assert_eq(terms[1], {"nome": "Religione", "valore": "-15"})
	t.assert_eq(terms[2], {"nome": "Inquisitore", "valore": "+3"})


func test_lealta_dal_dettaglio_dell_ultimo_calcolo(t: TestContext) -> void:
	var s := _world()
	var p := s.province(W.BASSA)
	p.loyalty = 90
	p.last_loyalty = {"corrente": 90, "obiettivo": 95, "base": 60, "tassa": 10, "guarnigione": 0, "edifici": 0, "religione": -15, "distanza": 0, "terrore": 0, "spie": 5, "somma": 95, "uomini": 80, "passi": 1}
	var lines := CampaignUiText.loyalty_lines(p)
	t.assert_eq(lines, PackedStringArray([
		"Lealtà: 90 · obiettivo 95",
		"Termini dell'obiettivo:",
		"  Base: +60",
		"  Tassa: +10",
		"  Religione: -15",
		"  Spie: +5",
		"Sotto 100 la provincia rischia la rivolta.",
	]), "\n".join(lines))
	p.last_loyalty = {}
	t.assert_eq(CampaignUiText.loyalty_lines(p), PackedStringArray(["Lealtà: 90", "Sotto 100 la provincia rischia la rivolta."]), "senza dettaglio: come prima")


func test_il_dettaglio_vero_della_simulazione_ha_la_voce_spie(t: TestContext) -> void:
	var s := _world()
	W.add_agent(s, W.A, W.BASSA, "SPY", 1)
	var p := s.province(W.BASSA)
	p.last_loyalty = ProvinceProcessor.loyalty_terms(s, p)
	var lines := CampaignUiText.loyalty_lines(p)
	var has_spies := false
	for line in lines:
		if line.strip_edges().begins_with("Spie: +"):
			has_spies = true
	t.assert_true(has_spies, "la spia propria alza la lealtà obiettivo: %s" % "\n".join(lines))


# --- eventi ------------------------------------------------------------------------------------------------------------------------


func test_testi_degli_eventi_degli_agenti(t: TestContext) -> void:
	var s := _world()
	var a := _emissary(s)
	a.name = "Luca"
	var title := CampaignUiAgents.title(a)
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_AGENT_RECRUITED, {"fazione": W.A, "regione": W.BASSA, "provincia": W.BASSA, "agente": a.id, "tipo_agente": "EMISSARY", "valore": 2, "origine": "coda"})),
		"Nuovo agente a Bassa: Emissario Luca (valore 2).")
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var princess_character := s.character(princess.character_id)
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_AGENT_RECRUITED, {"fazione": W.A, "regione": W.ALTA, "provincia": W.ALTA, "agente": princess.id, "tipo_agente": "PRINCESS", "valore": 4, "origine": "principessa", "personaggio": princess.character_id})),
		"%s è in età da marito: diventa un'agente a Alta (valore 4)." % princess_character.full_name())
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_AGENT_MOVED, {"fazione": W.A, "agente": a.id, "tipo_agente": "EMISSARY", "da": W.BASSA, "a": W.MEZZA, "regione": W.MEZZA})),
		"%s (Alpha): da Bassa a Mezza." % title)
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_AGENT_MOVED, {"fazione": W.A, "agente": a.id, "tipo_agente": "EMISSARY", "da": W.ALTA, "a": W.MEZZA, "via_mare": true, "catena": [W.NORD, W.SUD]})),
		"%s (Alpha): da Alta a Mezza via mare (%s > %s)." % [title, CampaignUiText.region_name(s, W.NORD), CampaignUiText.region_name(s, W.SUD)])
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_AGENT_CAPTURED, {"fazione": W.B, "con": W.A, "regione": W.MEZZA, "agente": 99, "tipo_agente": "SPY", "catturatore": "il forte di confine", "catturatore_agente": 0})),
		"Beta cattura un agente di Alpha a Mezza: Spia, preso dal forte di confine.")
	var guard := _emissary(s, W.B)
	guard.name = "Pietro"
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_AGENT_CAPTURED, {"fazione": W.B, "con": W.A, "regione": W.MEZZA, "agente": 99, "tipo_agente": "ASSASSIN", "catturatore_agente": guard.id})),
		"Beta cattura un agente di Alpha a Mezza: Assassino, preso da Emissario Pietro.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_MISSION_FAILED, {"fazione": W.A, "regione": W.BASSA, "agente": a.id, "tipo_agente": "EMISSARY", "missione": "corruzione", "motivo": "tesoro insufficiente: servono 5000, ci sono 100"})),
		"Missione fallita (corruzione): %s di Alpha a Bassa: tesoro insufficiente: servono 5000, ci sono 100." % title)
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_GATES_OPENED, {"fazione": W.A, "regione": W.MEZZA, "assediata": W.B})),
		"Una spia di Alpha apre le porte del castello a Mezza: Beta perde la provincia.")


func test_testi_degli_eventi_diplomatici(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_ALLIANCE_FORMED, {"fazione": W.A, "con": W.B, "regione": W.MEZZA})),
		"Alpha e Beta stringono un'alleanza a Mezza.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_TRUCE, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "fino_al": 1010})),
		"Alpha e Beta firmano una tregua fino al 1010 a Mezza.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_ALLIANCE_BROKEN, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "influenza_persa": 1})),
		"Alpha rompe l'alleanza con Beta attaccando a Mezza. L'influenza del suo capo scende di 1.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_TRUCE_BROKEN, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "influenza_persa": 0})),
		"Alpha rompe la tregua con Beta attaccando a Mezza.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_TRUCE_EXPIRED, {"fazione": W.A, "con": W.B, "regione": ""})),
		"La tregua tra Alpha e Beta è scaduta.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_PROPOSAL_REFUSED, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "missione": "alleanza", "probabilita": 0.35})),
		"Beta rifiuta un'alleanza proposta da Alpha a Mezza (probabilità 35%).")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_PROPOSAL_REFUSED, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "missione": "tregua"})),
		"Beta rifiuta una tregua proposta da Alpha a Mezza.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_MARRIAGE, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "nome": "Matilde", "nuova_alleanza": true})),
		"La principessa Matilde di Alpha sposa un nobile di Beta a Mezza: nasce un'alleanza.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_MARRIAGE, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "nuova_alleanza": false})),
		"Una principessa di Alpha sposa un nobile di Beta a Mezza.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_MARRIAGE, {"fazione": W.A, "con": "", "regione": W.BASSA, "nome": "Guglielmo", "personaggio": 4})),
		"Una principessa di Alpha sposa il generale Guglielmo a Bassa: la sua lealtà cresce ed entra nella linea di sangue.")


func test_testi_di_corruzioni_e_assassinii(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_BRIBE, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "esercito": 5, "prezzo": 4200})),
		"Alpha corrompe l'esercito 5 di Beta per 4200 denari a Mezza.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_BRIBE, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "esercito": 5, "prezzo": 4200, "provincia": W.MEZZA})),
		"Alpha corrompe l'esercito 5 di Beta per 4200 denari a Mezza. Con la guarnigione passa Mezza.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_BRIBE_REFUSED, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "esercito": 5, "prezzo": 4200})),
		"L'esercito 5 di Beta rifiuta la corruzione di Alpha a Mezza.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_ASSASSINATION, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "bersaglio_tipo": "personaggio", "bersaglio": 3, "nome": "Henry"})),
		"Alpha assassina Henry (Beta) a Mezza.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_ASSASSINATION_FAILED, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "nome": "Henry", "assassino_morto": true})),
		"L'assassino di Alpha fallisce il colpo contro Henry (Beta) a Mezza e muore.")
	t.assert_eq(CampaignUiText.format_event(s, _ev(GameState.EV_ASSASSINATION_FAILED, {"fazione": W.A, "con": W.B, "regione": W.MEZZA, "nome": "Henry", "assassino_morto": false})),
		"L'assassino di Alpha fallisce il colpo contro Henry (Beta) a Mezza.")


func test_senza_i_campi_essenziali_si_ripiega_sul_testo(t: TestContext) -> void:
	var s := _world()
	for kind in [GameState.EV_ALLIANCE_FORMED, GameState.EV_TRUCE, GameState.EV_ALLIANCE_BROKEN, GameState.EV_TRUCE_EXPIRED, GameState.EV_PROPOSAL_REFUSED, GameState.EV_MARRIAGE, GameState.EV_BRIBE, GameState.EV_BRIBE_REFUSED, GameState.EV_ASSASSINATION, GameState.EV_ASSASSINATION_FAILED, GameState.EV_AGENT_CAPTURED, GameState.EV_GATES_OPENED, GameState.EV_MISSION_FAILED, GameState.EV_AGENT_MOVED]:
		var fallback := CampaignUiText.format_event(s, _ev(kind, {"testo": "Testo libero."}))
		t.assert_eq(fallback, "Testo libero.", str(kind))


# --- resoconto di fine anno ---------------------------------------------------------------------------------------------------------


func test_sezioni_del_resoconto_della_fase_5a(t: TestContext) -> void:
	var titles := PackedStringArray()
	for sec in CampaignUiText.phase5a_sections():
		titles.append(str(sec["titolo"]))
	t.assert_eq(titles, PackedStringArray(["Agenti", "Intrighe", "Diplomazia"]))
	var all_titles := PackedStringArray()
	for sec in CampaignUiText.all_report_sections():
		all_titles.append(str(sec["titolo"]))
	t.assert_eq(all_titles.size(), CampaignUiText.report_sections().size() + 3 + CampaignUiText.phase5b_sections().size() + CampaignUiText.phase5c_sections().size() + CampaignUiText.phase6_sections().size(), "le sezioni di prima restano (3 della 5a, poi quelle della 5b, della 5c e della fase 6)")
	var kinds := PackedStringArray()
	for sec in CampaignUiText.phase5a_sections():
		kinds.append_array(sec["tipi"])
	for kind in [GameState.EV_AGENT_RECRUITED, GameState.EV_AGENT_MOVED, GameState.EV_ALLIANCE_FORMED, GameState.EV_ALLIANCE_BROKEN, GameState.EV_TRUCE, GameState.EV_TRUCE_BROKEN, GameState.EV_TRUCE_EXPIRED, GameState.EV_PROPOSAL_REFUSED, GameState.EV_MARRIAGE, GameState.EV_BRIBE, GameState.EV_BRIBE_REFUSED, GameState.EV_ASSASSINATION, GameState.EV_ASSASSINATION_FAILED, GameState.EV_AGENT_CAPTURED, GameState.EV_GATES_OPENED, GameState.EV_MISSION_FAILED]:
		t.assert_true(kinds.has(kind), "nel resoconto: %s" % kind)


func test_resoconto_con_agenti_e_diplomazia(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	var gamma_agent := _emissary(s, W.G)
	var beta_agent := _emissary(s, W.B)
	gamma_agent.name = "Carlo"
	beta_agent.name = "Pietro"
	s.events.append(_ev(GameState.EV_ALLIANCE_FORMED, {"fazione": W.A, "con": W.B, "regione": W.MEZZA}))
	s.events.append(_ev(GameState.EV_AGENT_MOVED, {"fazione": W.G, "agente": gamma_agent.id, "tipo_agente": "EMISSARY", "da": W.ORTO, "a": W.MEZZA, "regione": W.MEZZA}))
	s.events.append(_ev(GameState.EV_AGENT_MOVED, {"fazione": W.B, "agente": beta_agent.id, "tipo_agente": "EMISSARY", "da": W.MEZZA, "a": W.BASSA, "regione": W.BASSA}))
	s.events.append(_ev(GameState.EV_ASSASSINATION, {"fazione": W.G, "con": W.B, "regione": W.MEZZA, "nome": "Henry", "bersaglio_tipo": "personaggio"}))
	var result := {"ok": true, "avvisi": [], "errori": []}
	var for_alpha := CampaignUiText.year_report(s, W.A, result)
	t.assert_eq(for_alpha, PackedStringArray([
		"— Agenti —",
		"  Emissario Pietro (Beta): da Mezza a Bassa.",
		"— Diplomazia —",
		"  Alpha e Beta stringono un'alleanza a Mezza.",
	]), "ALPHA vede l'alleanza e l'emissario che entra in BASSA, non le mosse e gli omicidi altrui\n" + "\n".join(for_alpha))
	var for_gamma := CampaignUiText.year_report(s, W.G, result)
	t.assert_eq(for_gamma, PackedStringArray([
		"— Agenti —",
		"  Emissario Carlo (Gamma): da Orto a Mezza.",
		"— Intrighe —",
		"  Gamma assassina Henry (Beta) a Mezza.",
		"— Notizie dalle altre fazioni —",
		"  Alpha e Beta stringono un'alleanza a Mezza.",
	]), "GAMMA vede anche l'alleanza tra altre fazioni (notizie, 2026-11-13)\n" + "\n".join(for_gamma))
	var for_beta := CampaignUiText.year_report(s, W.B, result)
	t.assert_eq(for_beta.size(), 7, "BETA: le sue mosse, l'assassinio subito, l'alleanza\n" + "\n".join(for_beta))
	t.assert_true(for_beta.has("— Intrighe —"))
	t.assert_true(for_beta.has("  Gamma assassina Henry (Beta) a Mezza."))


func test_il_resoconto_delle_fasi_precedenti_non_cambia_con_la_5a(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	s.events.append({"tipo": GameState.EV_MOVED, "anno": 1000, "fazione": W.A, "esercito": 2, "da": W.ALTA, "a": W.BASSA})
	var lines := CampaignUiText.year_report(s, W.A, {"ok": true, "avvisi": [], "errori": []})
	t.assert_eq(lines, PackedStringArray(["Esercito 2: da Alta a Bassa."]))


func test_eventi_veri_della_simulazione_hanno_testo_leggibile(t: TestContext) -> void:
	var s := _world()
	W.always_accept(s)
	W.kill_always(s)
	W.capture_always(s)
	var proposer := _emissary(s)
	t.assert_true(bool(GameCommands.order_mission(s, W.A, proposer.id, AgentMissions.ALLIANCE, W.B)["ok"]))
	var killer := W.add_agent(s, W.A, W.BASSA, "ASSASSIN", 3)
	var victim := _emissary(s, W.B)
	var kill_order := GameCommands.order_mission(s, W.A, killer.id, AgentMissions.ASSASSINATE, {"tipo": AgentMissions.TARGET_AGENT, "id": victim.id})
	t.assert_true(bool(kill_order["ok"]), str(kill_order["errore"]))
	W.add_agent(s, W.G, W.ALTA, "EMISSARY", 1)   # intruso in ALTA: cattura possibile
	var step := TurnProcessor.end_year(s)
	t.assert_true(bool(step["ok"]))
	var kinds_5a := PackedStringArray()
	for sec in CampaignUiText.phase5a_sections():
		kinds_5a.append_array(sec["tipi"])
	var seen := 0
	for e in s.events:
		var kind := str(e["tipo"])
		if not kinds_5a.has(kind):
			continue
		seen += 1
		var text := CampaignUiText.format_event(s, e)
		t.assert_true(text != "" and text != kind, "riga grezza per %s" % kind)
		t.assert_false(text.contains("ID_"), "id non tradotti: %s" % text)
		t.assert_false(text.contains("FN_"), "id non tradotti: %s" % text)
	t.assert_true(seen >= 2, "almeno movimento e un esito (visti %d)" % seen)
	var lines := CampaignUiText.year_report(s, W.A, step)
	t.assert_true(lines.size() > 0, "il resoconto di ALPHA non è vuoto")
	for line in lines:
		t.assert_false(line.strip_edges() in kinds_5a, "riga grezza: %s" % line)
