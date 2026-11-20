extends RefCounted
## Scheda «Agenti» della finestra dei messaggi con «Raggiungi» (richiesta di Federico del 18/11/2026: rintracciare gli
## agenti come i generali con «Vai all'esercito»). Mondo di prova: agent_world.gd.

const W := preload("res://tests/unit/agent_world.gd")


func test_elenco_degli_agenti_propri(t: TestContext) -> void:
	var s := W.world()
	for a in s.agents.duplicate():
		s.remove_agent(a)
	var spy := W.add_agent(s, W.A, W.ALTA, AgentState.SPY, 3)
	var emissary := W.add_agent(s, W.A, W.BASSA, AgentState.EMISSARY, 5)
	W.add_agent(s, W.B, W.ALTA, AgentState.SPY, 2)
	var rows := CampaignUiAgents.roster(s, "fn_alpha")
	t.assert_eq(rows.size(), 2, "solo gli agenti propri")
	t.assert_eq(rows[0]["id"], emissary.id, "prima gli emissari, poi le spie")
	t.assert_eq(rows[1]["id"], spy.id)
	t.assert_eq(rows[0]["regione"], W.BASSA)
	t.assert_eq(rows[0]["dove"], CampaignUiText.region_name(s, W.BASSA))
	t.assert_eq(rows[0]["titolo"], CampaignUiAgents.title(emissary))
	t.assert_eq(rows[0]["attivita"], "In attesa")
	emissary.destination = W.SOLA
	t.assert_true(str(CampaignUiAgents.roster(s, W.A)[0]["attivita"]).begins_with("In viaggio verso"), "viaggio lungo")
	t.assert_true(CampaignUiAgents.roster(s, W.G).is_empty(), "fazione senza agenti")


## Scheda dei religiosi (richiesta di Federico del 18/11/2026): mostra la conversione annua dove si trovano.
func test_scheda_dei_religiosi_con_la_conversione(t: TestContext) -> void:
	var s := W.world()
	var priest := W.add_agent(s, W.A, W.ALTA, "BISHOP", 2)
	var lines := CampaignUiAgents.religious_effect_lines(s, priest)
	var conversion := ReligionProcessor.agent_conversion(s, priest)
	if conversion.is_empty():
		t.assert_eq(lines.size(), 1, "senza conversione una riga che lo dice")
	else:
		t.assert_true(str(lines[0]).begins_with("Conversione a "), str(lines))
	t.assert_true(CampaignUiAgents.sheet_lines(s, priest).size() > lines.size())
	var spy := W.add_agent(s, W.A, W.ALTA, AgentState.SPY, 2)
	t.assert_true(CampaignUiAgents.religious_effect_lines(s, spy).is_empty(), "solo i religiosi")
