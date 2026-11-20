extends RefCounted
## Scheda dell'agente con il ritratto (richiesta di Federico del 2026-11-13): righe della scheda (valore in stelle, eta',
## ruolo, posizione, viaggio, missione). Mondo di prova: agent_world.gd (principessa di ALPHA ad ALTA nata nel 980 e
## collegata a un personaggio; emissario di ALPHA a BASSA).

const W := preload("res://tests/unit/agent_world.gd")


func test_stelle_del_valore(t: TestContext) -> void:
	var s := W.world()
	var spy := W.add_agent(s, W.A, W.ALTA, AgentState.SPY, 3)
	t.assert_eq(CampaignUiAgents.valour_stars(spy, 5), "★★★☆☆ (3)")
	spy.valour = -1
	t.assert_eq(CampaignUiAgents.valour_stars(spy, 5), "-")
	spy.valour = 12
	t.assert_eq(CampaignUiAgents.valour_stars(spy, 10), "★★★★★★★★★★ (12)", "oltre il massimo: stelle piene e il numero vero")


func test_la_principessa_ha_eta_e_ruolo(t: TestContext) -> void:
	var s := W.world()
	var princess := W.agent_of(s, W.A, AgentState.PRINCESS)
	var c := s.character(princess.character_id)
	t.assert_true(c != null, "collegata a un personaggio")
	var lines := CampaignUiAgents.sheet_lines(s, princess)
	t.assert_true(str(lines[0]).begins_with("Valore: "), "prima riga: il valore")
	t.assert_true(lines.has("Età: %d anni" % c.age(s.year)), "eta' dal personaggio: %s" % str(lines))
	t.assert_true(lines.has(str(CampaignUiAgents.ROLE_TEXTS["PRINCESS"])), "cosa fa una principessa")
	t.assert_true(lines.has("Posizione: %s" % CampaignUiText.region_name(s, W.ALTA)))


func test_viaggio_e_missione_nella_scheda(t: TestContext) -> void:
	var s := W.world()
	var e := W.agent_of(s, W.A, AgentState.EMISSARY)   # a BASSA
	var r := GameCommands.order_agent_move(s, W.A, e.id, PackedStringArray([W.ORTO]))
	t.assert_true(bool(r["ok"]), str(r))
	var text := "\n".join(CampaignUiAgents.sheet_lines(s, e))
	t.assert_true(text.contains("In viaggio verso %s" % CampaignUiText.region_name(s, W.ORTO)), text)
	t.assert_true(text.contains(str(CampaignUiAgents.ROLE_TEXTS["EMISSARY"])), "cosa fa un emissario")
	t.assert_false(text.contains("Spia:"), "nessuna riga d'aiuto ripetuta")


func test_eta_ignota_e_religiosi(t: TestContext) -> void:
	var s := W.world()
	var priest := W.add_agent(s, W.A, W.ALTA, "BISHOP", 2)
	priest.birth_year = 0
	t.assert_eq(CampaignUiAgents.agent_age(s, priest), -1, "eta' ignota")
	var lines := CampaignUiAgents.sheet_lines(s, priest)
	t.assert_true(lines.has(CampaignUiAgents.RELIGIOUS_TEXT), "cosa fa un religioso")
	for line in lines:
		t.assert_false(str(line).begins_with("Età"), "niente eta' se ignota")
