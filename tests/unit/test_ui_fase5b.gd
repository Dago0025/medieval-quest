extends RefCounted
## Test della logica pura dell'interfaccia della fase 5b (religione e Inquisizione): nomi delle religioni, ordinamento e
## formattazione delle percentuali, righe del pannello della provincia (religione del proprietario, eretici oltre la
## soglia, zelo), colori e legenda della tinta religiosa, voci del menu del processo dell'inquisitore, testi degli eventi
## nuovi e del resoconto di fine anno.
## Mondo di prova: tests/unit/agent_world.gd (ALPHA e GAMMA cattoliche, BETA musulmana; ALPHA è il giocatore).

const W := preload("res://tests/unit/agent_world.gd")

const MINI_STARTPOS := """
DeclareFaction:: "FN_REBEL"
DeclareFaction:: "FN_DANISH"
DeclareFaction:: "FN_ENGLISH"
SetFactionCol:: FN_DANISH 200 10 20 0 0 0
SetFactionCol:: FN_ENGLISH 10 20 200 0 0 0
DeclareLandRegion:: "ID_DENMARK"
DeclareLandRegion:: "ID_SWEDEN"
DeclareLandRegion:: "ID_WESSEX"
DeclareSeaRegion:: "ID_NORTH_SEA"
SetRegionOwner:: ID_DENMARK FN_DANISH
SetRegionOwner:: ID_WESSEX FN_ENGLISH
"""


func _world() -> GameState:
	var s := W.world()
	s.faction(W.A).is_player = true
	return s


func _ev(kind: String, data: Dictionary) -> Dictionary:
	var e := {"tipo": kind, "anno": 1000}
	e.merge(data)
	return e


func _units(cath: int, orth: int, muslim: int, pagan: int, heretic: int) -> Dictionary:
	return {"CATHOLIC": cath, "ORTHODOX": orth, "MUSLIM": muslim, "PAGAN": pagan, "HERETIC": heretic}


## Voci (Dictionary) di un piano del menu.
func _entries(plan: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(plan["voci"])
	return out


func _options(s: GameState, agent: AgentState) -> Array:
	var r := GameCommands.mission_options(s, agent.faction, agent.id)
	return r["missioni"]


func _mini_map() -> RegionMap:
	var data := StartposLoader.load_text(MINI_STARTPOS)
	var pixels := PackedByteArray([
		0, 2, 3, 4, 5, 6, 216, 250,
		2, 2, 3, 3, 4, 4, 216, 216,
		6, 6, 6, 0, 0, 0, 216, 216,
		2, 3, 2, 3, 217, 217, 7, 7,
	])
	return RegionMap.new(LbmReader.from_indices(8, 4, pixels), data)


func _owner_rgb(table: Image, palette_index: int) -> Vector3i:
	var bytes := table.get_data()
	var o := (RegionMap.ROW_OWNER * RegionMap.TABLE_SIZE + palette_index) * 4
	return Vector3i(bytes[o], bytes[o + 1], bytes[o + 2])


func _rgb(c: Color) -> Vector3i:
	return Vector3i(c.r8, c.g8, c.b8)


# --- nomi e percentuali -----------------------------------------------------------------------------------------


func test_nomi_delle_religioni(t: TestContext) -> void:
	t.assert_eq(CampaignUiReligion.religion_label("CATHOLIC"), "Cattolica")
	t.assert_eq(CampaignUiReligion.religion_label("ORTHODOX"), "Ortodossa")
	t.assert_eq(CampaignUiReligion.religion_label("MUSLIM"), "Musulmana")
	t.assert_eq(CampaignUiReligion.religion_label("PAGAN"), "Pagana")
	t.assert_eq(CampaignUiReligion.religion_label("HERETIC"), "Eretica")
	t.assert_eq(CampaignUiReligion.religion_label("REL_ISLAMIC"), "Musulmana", "i token dei file")
	t.assert_eq(CampaignUiReligion.religion_label(""), "sconosciuta")


func test_la_colonna_religione_della_diplomazia_e_in_italiano(t: TestContext) -> void:
	var s := _world()
	var rows := CampaignUiAgents.diplomacy_rows(s, W.A)
	var seen := {}
	for row in rows:
		seen[str(row["fazione"])] = str(row["religione"])
	t.assert_eq(seen[W.A], "Cattolica")
	t.assert_eq(seen[W.B], "Musulmana")
	t.assert_eq(CampaignUiAgents.religion_name("REL_ORTHODOX"), "Ortodossa")
	t.assert_eq(CampaignUiAgents.religion_name("REL_PAGAN"), "Pagana")


func test_percentuali_senza_decimali_inutili(t: TestContext) -> void:
	t.assert_eq(CampaignUiReligion.percent_text(100.0), "100%")
	t.assert_eq(CampaignUiReligion.percent_text(75.0), "75%")
	t.assert_eq(CampaignUiReligion.percent_text(10.0), "10%", "gli zeri prima della virgola restano")
	t.assert_eq(CampaignUiReligion.percent_text(12.5), "12,5%")
	t.assert_eq(CampaignUiReligion.percent_text(0.25), "0,25%")
	t.assert_eq(CampaignUiReligion.percent_text(33.75), "33,75%")
	t.assert_eq(CampaignUiReligion.percent_text(99.75), "99,75%")
	t.assert_eq(CampaignUiReligion.percent_text(0.0), "0%")
	t.assert_eq(CampaignUiReligion.percent_text(-3.0), "0%", "mai negative")
	t.assert_eq(CampaignUiReligion.percent_text(12.3456), "12,35%", "al massimo due decimali")


# --- composizione -----------------------------------------------------------------------------------------------


func test_composizione_in_ordine_decrescente_e_solo_le_presenti(t: TestContext) -> void:
	var p := ProvinceState.new("ID_X", W.A)
	p.set_religion_units(_units(100, 0, 240, 59, 1))   # 25 / 0 / 60 / 14,75 / 0,25
	var rows := CampaignUiReligion.composition(p)
	t.assert_eq(rows.size(), 4, "l'ortodossa (0) non compare")
	t.assert_eq(rows[0]["chiave"], "MUSLIM")
	t.assert_eq(rows[1]["chiave"], "CATHOLIC")
	t.assert_eq(rows[2]["chiave"], "PAGAN")
	t.assert_eq(rows[3]["chiave"], "HERETIC")
	t.assert_eq(rows[0]["testo"], "Musulmana 60%")
	t.assert_eq(rows[1]["testo"], "Cattolica 25%")
	t.assert_eq(rows[2]["testo"], "Pagana 14,75%")
	t.assert_eq(rows[3]["testo"], "Eretica 0,25%")
	p.set_religion_units(_units(0, 0, 0, 400, 0))
	t.assert_eq(CampaignUiReligion.composition(p).size(), 1, "una sola religione")
	t.assert_eq(CampaignUiReligion.composition(p)[0]["testo"], "Pagana 100%")


func test_a_parita_vale_l_ordine_fisso_delle_religioni(t: TestContext) -> void:
	var p := ProvinceState.new("ID_X", W.A)
	p.set_religion_units(_units(100, 100, 100, 100, 0))
	var keys := PackedStringArray()
	for row in CampaignUiReligion.composition(p):
		keys.append(str(row["chiave"]))
	t.assert_eq(keys, PackedStringArray(["CATHOLIC", "ORTHODOX", "MUSLIM", "PAGAN"]))


func test_righe_del_pannello_con_proprietario_e_soglia(t: TestContext) -> void:
	var s := _world()
	s.rules.religion.heretic_revolt_threshold = 30.0
	var p := s.province(W.BASSA)
	p.set_religion_units(_units(280, 0, 0, 0, 120))   # 70% cattolici, 30% eretici: la soglia non e' superata
	var rows := CampaignUiReligion.section_rows(s, p)
	t.assert_eq(rows.size(), 2)
	t.assert_eq(rows[0]["testo"], "Cattolica 70% · religione del proprietario")
	t.assert_true(bool(rows[0]["proprietario"]))
	t.assert_false(bool(rows[0]["rosso"]))
	t.assert_eq(rows[1]["testo"], "Eretica 30%")
	t.assert_false(bool(rows[1]["proprietario"]))
	t.assert_false(bool(rows[1]["rosso"]), "esattamente alla soglia: non e' ancora rosso")
	p.set_religion_units(_units(272, 0, 0, 0, 128))   # 32% di eretici
	rows = CampaignUiReligion.section_rows(s, p)
	t.assert_true(bool(rows[1]["rosso"]), "oltre la soglia: rosso")
	t.assert_true(str(rows[1]["testo"]).contains("oltre il 30%"), str(rows[1]["testo"]))
	t.assert_false(bool(rows[0]["rosso"]), "solo gli eretici")
	s.rules.religion.heretic_revolt_threshold = 40.0
	rows = CampaignUiReligion.section_rows(s, p)
	t.assert_false(bool(rows[1]["rosso"]), "la soglia viene dalle regole")


func test_provincia_di_altra_religione_e_dei_ribelli(t: TestContext) -> void:
	var s := _world()
	var p := s.province(W.MEZZA)
	p.set_religion_units(_units(100, 0, 300, 0, 0))
	var rows := CampaignUiReligion.section_rows(s, p)
	t.assert_eq(rows[0]["testo"], "Musulmana 75% · religione del proprietario", "BETA e' musulmana")
	t.assert_eq(rows[1]["testo"], "Cattolica 25%")
	t.assert_false(bool(rows[1]["proprietario"]))
	var rebel := s.province(W.SOLA)
	if rebel != null:
		rebel.set_religion_units(_units(0, 0, 0, 200, 200))
		var rebel_rows := CampaignUiReligion.section_rows(s, rebel)
		for row in rebel_rows:
			t.assert_false(bool(row["proprietario"]), "i ribelli non hanno una religione")
			t.assert_false(bool(row["rosso"]), "nessuna rivolta eretica nelle province dei ribelli")


func test_riga_dello_zelo(t: TestContext) -> void:
	var s := _world()
	var p := s.province(W.BASSA)
	p.zeal = 63
	t.assert_eq(CampaignUiReligion.zeal_text(s, p), "Zelo (Cattolica): 63 su 100")
	var rebel := s.province(W.SOLA)
	if rebel != null:
		rebel.zeal = 50
		t.assert_eq(CampaignUiReligion.zeal_text(s, rebel), "Zelo: 50 su 100")


# --- tinta religiosa --------------------------------------------------------------------------------------------


func test_colori_della_tinta_religiosa(t: TestContext) -> void:
	var seen := {}
	for key in ProvinceState.RELIGIONS:
		var c := StateTint.religion_color(key)
		var rgb := _rgb(c)
		t.assert_false(seen.has(rgb), "colore ripetuto per %s" % key)
		seen[rgb] = true
		t.assert_eq(c.a, 1.0, "opaco")
	t.assert_eq(StateTint.religion_color("catholic"), StateTint.religion_color("CATHOLIC"), "maiuscole indifferenti")
	t.assert_eq(StateTint.religion_color("ZORO"), StateTint.UNKNOWN_RELIGION_COLOR)
	t.assert_eq(StateTint.religion_color(""), StateTint.UNKNOWN_RELIGION_COLOR)
	t.assert_false(seen.has(_rgb(StateTint.UNKNOWN_RELIGION_COLOR)), "il grigio non e' una religione")


func test_legenda_della_tinta_religiosa(t: TestContext) -> void:
	var legend := CampaignUiReligion.legend_entries()
	t.assert_eq(legend.size(), ProvinceState.RELIGIONS.size())
	t.assert_eq(legend[0]["nome"], "Cattolica")
	t.assert_eq(legend[4]["nome"], "Eretica")
	for entry in legend:
		t.assert_eq(entry["colore"], StateTint.religion_color(str(entry["chiave"])))


func test_la_tinta_religiosa_segue_la_maggioranza_e_la_normale_non_cambia(t: TestContext) -> void:
	var map := _mini_map()
	var s := GameState.new(map.data)
	var danish := ProvinceState.new("ID_DENMARK", "FN_DANISH")
	danish.set_religion_units(_units(100, 0, 300, 0, 0))   # maggioranza musulmana
	var english := ProvinceState.new("ID_WESSEX", "FN_ENGLISH")
	english.set_religion_units(_units(300, 0, 0, 100, 0))   # maggioranza cattolica
	s.add_province(danish)
	s.add_province(english)
	var base := map.build_table(null)
	var religious := StateTint.apply_religion(base, map, s)
	t.assert_eq(_owner_rgb(religious, 2), _rgb(StateTint.religion_color("MUSLIM")), "Danimarca (indice 2)")
	t.assert_eq(_owner_rgb(religious, 3), _rgb(StateTint.religion_color("MUSLIM")), "Danimarca (indice 3)")
	t.assert_eq(_owner_rgb(religious, 6), _rgb(StateTint.religion_color("CATHOLIC")), "Wessex")
	# la tinta dei proprietari e' quella di sempre
	var owners := StateTint.apply(base, map, s)
	var red := Color(map.data.faction("FN_DANISH").color_primary, 1.0)
	t.assert_eq(_owner_rgb(owners, 2), _rgb(red))
	# la riga delle informazioni (evidenziata, gruppo, tipo) e' la stessa
	var info_a := religious.get_data().slice(RegionMap.TABLE_SIZE * 4)
	var info_b := base.get_data().slice(RegionMap.TABLE_SIZE * 4)
	t.assert_eq(info_a, info_b, "la riga delle informazioni resta quella della tabella")
	# a parita' di quote la prima religione dell'ordine fisso
	danish.set_religion_units(_units(0, 200, 200, 0, 0))
	religious = StateTint.apply_religion(base, map, s)
	t.assert_eq(_owner_rgb(religious, 2), _rgb(StateTint.religion_color("ORTHODOX")))


# --- menu del processo ------------------------------------------------------------------------------------------


func test_voci_del_processo_con_nome_ruolo_e_probabilita(t: TestContext) -> void:
	var s := _world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var bishop := W.add_agent(s, W.A, W.ALTA, "BISHOP", 1)
	var leader := s.leader_of(W.A)
	var options := _options(s, ins)
	var entries := _entries(CampaignUiAgents.click_plan(s, ins, options, W.ALTA))
	var leader_text := ""
	var bishop_text := ""
	for e in entries:
		if e["azione"] != CampaignUiAgents.ACTION_MISSION:
			continue
		t.assert_eq(e["tipo"], AgentMissions.TRIAL)
		var text := str(e["testo"])
		t.assert_true(text.begins_with("Processo a "), text)
		t.assert_true(text.ends_with("%"), "porta la probabilità: %s" % text)
		if text.contains(leader.full_name()):
			leader_text = text
		if text.contains("(agente, valore 1,"):
			bishop_text = text
	var p_leader := AgentMissions.trial_chance(s, {"tipo": AgentMissions.TARGET_CHARACTER, "id": leader.id})
	t.assert_eq(leader_text, "Processo a %s (capo di %s): %s" % [leader.full_name(), CampaignUiText.faction_name(W.A), CampaignUiAgents.chance_text(p_leader)])
	t.assert_true(bishop_text.contains("Vescovo"), "l'agente bersaglio e' descritto per tipo: %s" % bishop_text)
	t.assert_true(bishop_text.contains(CampaignUiText.faction_name(W.A)), bishop_text)
	t.assert_true(bishop_text.contains("%d%%" % roundi(AgentMissions.trial_chance(s, {"tipo": AgentMissions.TARGET_AGENT, "id": bishop.id}) * 100.0)), bishop_text)


func test_tooltip_del_processo_avverte_se_il_bersaglio_e_proprio(t: TestContext) -> void:
	var s := _world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var entries := _entries(CampaignUiAgents.click_plan(s, ins, _options(s, ins), W.ALTA))
	var found := false
	for e in entries:
		if e["azione"] == CampaignUiAgents.ACTION_MISSION:
			found = true
			var tip := str(e["tooltip"])
			t.assert_true(tip.contains("rogo"), tip)
			t.assert_true(tip.contains("stessa fazione"), "in ALTA ci sono solo bersagli di ALPHA: %s" % tip)
	t.assert_true(found, "almeno una voce")


func test_clic_sul_segnalino_dell_esercito_processa_il_comandante(t: TestContext) -> void:
	var s := _world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var army := W.general_army(s, W.A, W.ALTA)
	var commander := s.commander_of(army.id)
	t.assert_true(commander != null, "il generale comanda l'esercito")
	if commander == null:
		return
	var entries := _entries(CampaignUiAgents.click_plan(s, ins, _options(s, ins), W.ALTA, army.id))
	t.assert_eq(entries.size(), 1, "solo il processo del comandante")
	t.assert_eq(entries[0]["tipo"], AgentMissions.TRIAL)
	t.assert_true(str(entries[0]["testo"]).contains(commander.full_name()), str(entries[0]["testo"]))


func test_ordine_del_processo_dal_menu(t: TestContext) -> void:
	var s := _world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.ALTA)
	var target := {"tipo": AgentMissions.TARGET_CHARACTER, "id": general.id}
	var r := GameCommands.order_mission(s, W.A, ins.id, AgentMissions.TRIAL, target)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(CampaignUiAgents.mission_verb(s, AgentMissions.TRIAL, target), "processare %s" % general.full_name())
	var ordered := CampaignUiAgents.ordered_text(s, ins, r)
	t.assert_true(ordered.contains("processare %s" % general.full_name()), ordered)
	t.assert_true(CampaignUiAgents.mission_line(s, ins).begins_with("Processare %s" % general.full_name()), CampaignUiAgents.mission_line(s, ins))
	t.assert_true(CampaignUiAgents.describe_agent(s, ins).contains("rogo"), "la descrizione dell'inquisitore")


# --- eventi -----------------------------------------------------------------------------------------------------


func test_testo_della_rivolta_eretica(t: TestContext) -> void:
	var s := _world()
	var e := _ev(GameState.EV_HERETIC_REVOLT, {"fazione": W.A, "regione": W.ALTA, "provincia": W.ALTA, "eretici": 32.5, "esercito": 9, "uomini": 40})
	var text := CampaignUiText.format_event(s, e)
	t.assert_eq(text, "Rivolta eretica a %s (%s): gli eretici sono il 32,5%% della popolazione, 40 ribelli." % [CampaignUiText.region_name(s, W.ALTA), CampaignUiText.faction_name(W.A)])
	var bare := _ev(GameState.EV_HERETIC_REVOLT, {"fazione": W.A, "provincia": W.ALTA})
	t.assert_eq(CampaignUiText.format_event(s, bare), "Rivolta eretica a %s (%s)." % [CampaignUiText.region_name(s, W.ALTA), CampaignUiText.faction_name(W.A)])
	var no_place := _ev(GameState.EV_HERETIC_REVOLT, {"fazione": W.A, "testo": "testo della simulazione"})
	t.assert_eq(CampaignUiText.format_event(s, no_place), "testo della simulazione", "senza luogo ripiega sul testo")


func test_testi_dell_inquisizione(t: TestContext) -> void:
	var s := _world()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var place := CampaignUiText.region_name(s, W.ALTA)
	var alpha := CampaignUiText.faction_name(W.A)
	var beta := CampaignUiText.faction_name(W.B)
	var burned := _ev(GameState.EV_INQUISITION, {
		"fazione": W.A, "regione": W.ALTA, "agente": ins.id, "tipo_agente": "INQUISITOR",
		"bersaglio_tipo": "personaggio", "bersaglio": 3, "nome": "Edward I", "con": W.B, "pieta": 3, "probabilita": 0.45})
	t.assert_eq(CampaignUiText.format_event(s, burned), "L'Inquisizione di %s manda sul rogo Edward I di %s a %s (probabilità 45%%)." % [alpha, beta, place])
	var burned_agent := _ev(GameState.EV_INQUISITION, {
		"fazione": W.A, "regione": W.ALTA, "agente": ins.id, "tipo_agente": "INQUISITOR",
		"bersaglio_tipo": "agente", "bersaglio": 77, "nome": "", "con": W.B, "probabilita": 0.9})
	t.assert_eq(CampaignUiText.format_event(s, burned_agent), "L'Inquisizione di %s manda sul rogo un agente di %s a %s (probabilità 90%%)." % [alpha, beta, place])
	var failed := _ev(GameState.EV_INQUISITION_FAILED, {
		"fazione": W.A, "regione": W.ALTA, "agente": ins.id, "tipo_agente": "INQUISITOR",
		"bersaglio_tipo": "personaggio", "bersaglio": 3, "nome": "Edward I", "con": W.B, "probabilita": 0.45})
	t.assert_eq(CampaignUiText.format_event(s, failed), "Il processo di %s (%s) contro Edward I di %s a %s fallisce (probabilità 45%%)." % [alpha, CampaignUiAgents.title(ins), beta, place])
	var raw := _ev(GameState.EV_INQUISITION, {"testo": "testo della simulazione"})
	t.assert_eq(CampaignUiText.format_event(s, raw), "testo della simulazione", "senza i campi essenziali ripiega sul testo")


func test_morte_sul_rogo(t: TestContext) -> void:
	var s := _world()
	var e := _ev(GameState.EV_DEATH, {"fazione": W.B, "nome": "Edward I", "ruolo": Character.ROLE_GENERAL, "eta": 40, "causa": "rogo"})
	t.assert_eq(CampaignUiText.format_event(s, e), "Muore Edward I (%s, 40 anni) sul rogo." % Character.ROLE_GENERAL.to_lower())
	var old := _ev(GameState.EV_DEATH, {"fazione": W.B, "nome": "Edward I", "ruolo": Character.ROLE_GENERAL, "eta": 40, "causa": "vecchiaia"})
	t.assert_true(CampaignUiText.format_event(s, old).ends_with("di vecchiaia."), "le altre cause non cambiano")


func test_sezione_del_resoconto_della_fase_5b(t: TestContext) -> void:
	var sections := CampaignUiText.phase5b_sections()
	t.assert_eq(sections.size(), 1)
	t.assert_eq(sections[0]["titolo"], "Religione")
	var kinds: PackedStringArray = sections[0]["tipi"]
	t.assert_true(kinds.has(GameState.EV_HERETIC_REVOLT))
	t.assert_true(kinds.has(GameState.EV_INQUISITION))
	t.assert_true(kinds.has(GameState.EV_INQUISITION_FAILED))
	var every := CampaignUiText.all_report_sections()
	t.assert_eq(every.size(), CampaignUiText.report_sections().size() + CampaignUiText.phase5a_sections().size() + 1 + CampaignUiText.phase5c_sections().size() + CampaignUiText.phase6_sections().size())
	t.assert_eq(every[every.size() - 3]["titolo"], "Religione", "dopo la 5a e prima della 5c")


func test_resoconto_con_inquisizione_e_rivolta_eretica(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	s.events.append(_ev(GameState.EV_INQUISITION, {
		"fazione": W.A, "regione": W.ALTA, "agente": ins.id, "tipo_agente": "INQUISITOR",
		"bersaglio_tipo": "personaggio", "bersaglio": 3, "nome": "Edward I", "con": W.B, "probabilita": 0.45}))
	s.events.append(_ev(GameState.EV_HERETIC_REVOLT, {"fazione": W.A, "regione": W.BASSA, "provincia": W.BASSA, "eretici": 40.0, "esercito": 9, "uomini": 30}))
	# un processo tra altre fazioni non riguarda il giocatore
	s.events.append(_ev(GameState.EV_INQUISITION, {"fazione": W.G, "regione": W.ORTO, "bersaglio_tipo": "agente", "bersaglio": 5, "nome": "Tizio", "con": W.G, "probabilita": 0.3}))
	var lines := CampaignUiText.year_report(s, W.A, {"ok": true, "avvisi": [], "errori": []})
	t.assert_eq(lines.size(), 3, "intestazione e due righe: %s" % str(lines))
	t.assert_eq(lines[0], "— Religione —")
	t.assert_true(lines[1].begins_with("  L'Inquisizione di "), lines[1])
	t.assert_true(lines[2].begins_with("  Rivolta eretica a "), lines[2])
	for line in lines:
		t.assert_false(line.contains("ID_"), line)
		t.assert_false(line.contains("FN_"), line)


func test_eventi_veri_del_processo_hanno_testo_leggibile(t: TestContext) -> void:
	var s := _world()
	s.rules.religion.trial_p_min = 1.0
	s.rules.religion.trial_p_max = 1.0
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 3)
	var general := W.add_general(s, W.A, W.ALTA)
	var r := GameCommands.order_mission(s, W.A, ins.id, AgentMissions.TRIAL, {"tipo": AgentMissions.TARGET_CHARACTER, "id": general.id})
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var step := TurnProcessor.end_year(s)
	t.assert_true(bool(step["ok"]))
	var seen := 0
	for e in s.events:
		var kind := str(e["tipo"])
		if kind != GameState.EV_INQUISITION and kind != GameState.EV_INQUISITION_FAILED:
			continue
		seen += 1
		var text := CampaignUiText.format_event(s, e)
		t.assert_true(text != "" and text != kind, "riga grezza per %s" % kind)
		t.assert_false(text.contains("ID_"), text)
		t.assert_false(text.contains("FN_"), text)
		t.assert_true(text.contains("sul rogo"), text)
	t.assert_eq(seen, 1, "un processo, un esito")
	# la simulazione non emette EV_DEATH per il rogo (emit=false): la morte e' nell'evento EV_INQUISITION
	t.assert_false(general.alive, "con probabilità 1 il generale muore sul rogo")
	t.assert_eq(general.death_cause, "rogo")
