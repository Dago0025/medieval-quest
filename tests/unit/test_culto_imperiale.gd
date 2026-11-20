extends RefCounted
## Culto Imperiale degli Auror e titolo dell'Imperatore Dio (richieste di Federico del 16/11/2026): religione propria con
## edifici e agenti dei cattolici, fuori dal Papato; il capo degli Auror e' «Imperatore Dio» e solo lui si chiama Darkos.
## Mondo di prova: vedi agent_world.gd (ALPHA diventa imperiale con `_imperial`).

const W := preload("res://tests/unit/agent_world.gd")
const I := ProvinceState.IMPERIAL
const C := ProvinceState.CATHOLIC
const O := ProvinceState.ORTHODOX


func _imperial() -> GameState:
	var s := W.world()
	s.campaign.faction(W.A).religion = "REL_IMPERIAL"
	ReligionProcessor.init_religions(s)
	for p in s.provinces:
		p.loyalty = 150
	return s


func test_chiavi_del_culto(t: TestContext) -> void:
	t.assert_true(ProvinceState.RELIGIONS.has(I), "religione della provincia")
	t.assert_eq(ProvinceState.RELIGIONS[5], I, "in coda all'ordine: le parita' di prima non cambiano")
	t.assert_eq(GameCommands.religion_key("REL_IMPERIAL"), I)
	t.assert_eq(GameCommands.religion_base(I), C, "usa edifici e agenti cattolici")
	t.assert_eq(GameCommands.religion_base(O), O)
	var s := _imperial()
	t.assert_eq(ReligionProcessor.faction_religion(s, W.A), I)
	t.assert_eq(DiplomacyProcessor.faction_religion(s, W.A), I)


func test_le_terre_cattoliche_degli_auror_partono_tutte_al_culto(t: TestContext) -> void:
	var s := _imperial()
	t.assert_eq(s.province(W.ALTA).religion_pct(I), 100.0, "cultura cattolica, proprietario imperiale")
	t.assert_eq(s.province(W.BASSA).religion_pct(I), 25.0, "cultura ortodossa: quota del proprietario")
	t.assert_eq(s.province(W.BASSA).religion_pct(O), 75.0)
	t.assert_false(ProvinceProcessor.religion_differs(s, s.province(W.ALTA)), "le terre cattoliche non sono estranee al culto")
	t.assert_true(ProvinceProcessor.religion_differs(s, s.province(W.BASSA)))


func test_le_chiese_si_costruiscono_e_convertono_al_culto(t: TestContext) -> void:
	var s := _imperial()
	var church := s.buildings.get_family("CHURCH")
	t.assert_true(GameCommands._religion_allows(s, church, W.A), "la chiesa cattolica e' anche del culto")
	church.get_level(1).faith = 0.1
	var bassa := s.province(W.BASSA)
	bassa.set_level("CHURCH", 1)
	ReligionProcessor.process_year(s)
	t.assert_eq(bassa.religion_pct(I), 27.0, "deriva +1 e chiesa +1 al culto, non al cattolicesimo")
	t.assert_eq(bassa.religion_pct(C), 0.0)


func test_vescovi_e_preti_degli_auror_predicano_il_culto(t: TestContext) -> void:
	var s := _imperial()
	var bishop := W.add_agent(s, W.A, W.ORTO, "BISHOP", 1)
	t.assert_eq(ReligionProcessor.agent_religion(s, bishop), I)
	t.assert_eq(ReligionProcessor.agent_conversion(s, bishop), {"IMPERIAL": 2.0})
	var priest := W.add_agent(s, W.A, W.ALTA, "PRIEST", 1)
	t.assert_eq(ReligionProcessor.agent_religion(s, priest), I)
	var gamma_bishop := W.add_agent(s, W.G, W.ORTO, "BISHOP", 1)
	t.assert_eq(ReligionProcessor.agent_religion(s, gamma_bishop), C, "i vescovi delle altre fazioni restano cattolici")
	s.agents.erase(gamma_bishop)
	ReligionProcessor.process_year(s)
	t.assert_true(s.province(W.ORTO).religion_pct(I) > 0.0, "il vescovo degli Auror converte la provincia cattolica")
	var unit := s.units.get_unit("Bishop")
	var raw := unit.raw
	raw[ReligionProcessor.COL_CONVERSION] = "CATHOLIC(3)"
	unit.raw = raw
	t.assert_eq(ReligionProcessor.agent_conversion(s, bishop), {"IMPERIAL": 3.0}, "anche dalla colonna 45")


func test_niente_eresia_ne_papato_per_il_culto(t: TestContext) -> void:
	var s := _imperial()
	var alta := s.province(W.ALTA)
	alta.tax_level = 4
	alta.loyalty = 50
	ReligionProcessor.process_year(s)
	t.assert_eq(alta.religion_pct(ProvinceState.HERETIC), 0.0, "l'eresia e' dei cattolici")
	t.assert_false(PapacyProcessor.is_catholic(s, W.A), "fuori dal Papato")
	t.assert_true(PapacyProcessor.launch_problem(s, W.A, PapacyProcessor.KIND_CRUSADE).contains("cattolic"), "non bandisce crociate")
	t.assert_eq(PapacyProcessor.target_reason(s, PapacyProcessor.KIND_CRUSADE, alta), "non_cattolico", "bersaglio delle crociate altrui")


func test_l_inquisizione_cattolica_non_processa_gli_auror(t: TestContext) -> void:
	var s := _imperial()
	var inquisitor := W.add_agent(s, W.G, W.ALTA, "INQUISITOR", 5)
	var general := W.add_general(s, W.A, W.ALTA)
	var r := AgentMissions.validate(s, inquisitor, AgentMissions.TRIAL, {"tipo": AgentMissions.TARGET_CHARACTER, "id": general.id})
	t.assert_false(bool(r["ok"]), str(r))


func test_nome_e_colore_del_culto(t: TestContext) -> void:
	t.assert_eq(CampaignUiReligion.religion_label("IMPERIAL"), "Culto Imperiale")
	t.assert_eq(CampaignUiReligion.religion_label("REL_IMPERIAL"), "Culto Imperiale")
	t.assert_true(StateTint.religion_color("IMPERIAL") != StateTint.UNKNOWN_RELIGION_COLOR)
	# richiesta di Federico del 16/11/2026: simbolo proprio, una I maiuscola gotica color oro
	t.assert_eq(UiIcons.path_for("religioni", "IMPERIAL"), "campmap/parchments/icon_imperial.BIF")
	var icon := AssetLibrary.remade("campmap/parchments/icon_imperial.BIF")
	t.assert_true(icon != null, "icona rifatta del culto")
	if icon != null:
		t.assert_eq(icon.get_size(), Vector2(144, 160), "8 volte le icone dell'originale (18x20)")
	var keys := []
	for e in CampaignUiReligion.legend_entries():
		keys.append(e["chiave"])
	t.assert_true(keys.has(I), "in legenda in modalita' Auror")


func test_gli_auror_seguono_il_culto_solo_in_modalita_auror(t: TestContext) -> void:
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata")
		return
	Scenario.set_auror(true)
	t.assert_eq(Scenario.load_startpos().faction("FN_DANISH").religion, "REL_IMPERIAL")
	Scenario.set_auror(false)
	t.assert_eq(Scenario.load_startpos().faction("FN_DANISH").religion, "REL_CATHOLIC", "i Danesi storici restano cattolici")
	Scenario.set_auror(true)


# --- Imperatore Dio e nomi degli eredi ----------------------------------------------------------------------------------


func test_titolo_e_nome_del_capo_da_auror_cfg(t: TestContext) -> void:
	var d := DynastyRules.load_file()
	t.assert_eq(d.leader_title("FN_DANISH"), "Imperatore Dio")
	t.assert_eq(d.leader_name("FN_DANISH"), "Darkos")
	t.assert_eq(d.leader_title("FN_ENGLISH"), "")
	t.assert_eq(DynastyRules.new().to_dict(), d.to_dict(), "valori predefiniti uguali al file")


func test_l_imperatore_dio_nella_barra_e_nelle_schede(t: TestContext) -> void:
	var s := W.world()
	s.rules.dynasty.fixed[W.A] = {"leader_title": "Imperatore Dio"}
	var king := s.leader_of(W.A)
	t.assert_true(king != null, "ALPHA ha un capo")
	if king == null:
		return
	t.assert_eq(CampaignUiText.character_role_text(s, king), "Imperatore Dio")
	t.assert_eq(CampaignUiText.leader_rank(s, W.A), "Imperatore Dio")
	t.assert_eq(CampaignUiText.leader_rank(s, W.B), "re", "gli altri capi restano re")
	t.assert_true(CampaignUiText.character_lines(s, king)[0].contains("Imperatore Dio"))
	var hall := CampaignUiText.rulers(s, W.A)
	t.assert_true(str(hall[0]["nome"]).begins_with("Imperatore Dio "), str(hall[0]))
	var army := W.land_army(s, W.A, W.ALTA)
	king.army = army.id
	t.assert_true(CampaignUiText.commander_caption(s, army).begins_with("Imperatore Dio "), CampaignUiText.commander_caption(s, army))


func test_solo_il_capo_si_chiama_darkos(t: TestContext) -> void:
	var s := W.world()
	var names := CharacterFactory.royal_names(s, W.A)
	var reserved := names[0]
	s.rules.dynasty.fixed[W.A] = {"leader_name": reserved}
	var king := s.leader_of(W.A)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 200:
		var child := CharacterFactory.make_child(s, king, true, s.year, W.ALTA, rng)
		t.assert_true(child.forename != reserved, "il figlio %d non porta il nome riservato" % i)
		if child.forename == reserved:
			return
	# partite salvate prima della correzione: l'erede Darkos prende un altro nome
	var heir := CharacterFactory.make_child(s, king, true, s.year, W.ALTA, rng)
	heir.forename = reserved
	heir.name_index = 0
	t.assert_true(CharacterFactory.rename_reserved_heirs(s) >= 1)
	t.assert_true(heir.forename != reserved and heir.forename == names[heir.name_index])
	t.assert_eq(CharacterFactory.rename_reserved_heirs(s), 0, "una volta sola")
