extends RefCounted
## Test della logica pura dell'interfaccia della fase 3 (scontri): colore delle frecce, bersagli
## d'attacco, guerre, assedi, testi degli eventi e resoconto di fine anno.
## Gli eventi, le guerre e gli assedi sono costruiti a mano (Dictionary e oggetti di prova): i test
## non dipendono dalla simulazione della fase 3. Mondo: tests/fixtures/sim_*.txt
## (ALTA e BASSA di ALPHA, MEZZA di BETA, SOLA dei ribelli).

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const ArmyLayerScript := preload("res://scenes/army_layer.gd")


## Assedio di prova con oggetti al posto dei Dictionary.
class FakeSiege:
	var faction := "FN_ALPHA"
	var years := 3
	var army_ids: Array = [4, 5]
	var assault_ordered := false


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


func _ev(const_name: String, data: Dictionary) -> Dictionary:
	var e := {"tipo": CampaignUiText.event_kind(const_name), "anno": 1000}
	e.merge(data)
	return e


# --- frecce e attacchi --------------------------------------------------------


func test_bersaglio_d_attacco_per_proprietario_e_presenze(t: TestContext) -> void:
	var none := PackedStringArray()
	t.assert_false(MarkerLayout.is_attack_target("FN_ALPHA", "FN_ALPHA", none), "provincia propria vuota")
	t.assert_true(MarkerLayout.is_attack_target("FN_ALPHA", "FN_BETA", none), "provincia altrui")
	t.assert_true(MarkerLayout.is_attack_target("FN_ALPHA", "FN_REBEL", none), "provincia dei ribelli")
	t.assert_true(MarkerLayout.is_attack_target("FN_ALPHA", "FN_ALPHA", PackedStringArray(["FN_BETA"])), "propria ma con un esercito nemico")
	t.assert_false(MarkerLayout.is_attack_target("FN_ALPHA", "FN_ALPHA", PackedStringArray(["fn_alpha"])), "solo forze proprie")
	t.assert_false(MarkerLayout.is_attack_target("FN_ALPHA", "", none), "mare vuoto")
	t.assert_true(MarkerLayout.is_attack_target("FN_ALPHA", "", PackedStringArray(["FN_BETA"])), "mare con una flotta nemica")


func test_bersaglio_d_attacco_sullo_stato(t: TestContext) -> void:
	var s := _world()
	var army := s.create_army("FN_ALPHA", "ID_ALTA", false)
	army.stacks.append(UnitStack.new("SPEARMEN", 60, 0))
	t.assert_false(CampaignUiText.attack_target(s, army, "ID_BASSA"), "provincia propria")
	t.assert_true(CampaignUiText.attack_target(s, army, "ID_MEZZA"), "provincia di BETA")
	t.assert_true(CampaignUiText.attack_target(s, army, "ID_SOLA"), "provincia dei ribelli")
	var enemy := s.create_army("FN_BETA", "ID_BASSA", false)
	enemy.stacks.append(UnitStack.new("SPEARMEN", 30, 0))
	t.assert_true(CampaignUiText.attack_target(s, army, "ID_BASSA"), "provincia propria con un esercito nemico")
	enemy.stacks.clear()
	t.assert_false(CampaignUiText.attack_target(s, army, "ID_BASSA"), "esercito nemico senza pile non conta")


func test_colore_delle_frecce(t: TestContext) -> void:
	var normal := ArmyLayerScript.arrow_color(true, false)
	var attack := ArmyLayerScript.arrow_color(true, true)
	t.assert_true(attack != normal, "freccia d'attacco diversa dalla normale")
	t.assert_true(attack.r > 0.8 and attack.g < 0.3 and attack.b < 0.3, "l'attacco è rosso")
	t.assert_true(ArmyLayerScript.arrow_color(false, true).r > ArmyLayerScript.arrow_color(false, true).g, "anche non selezionata resta rossa")
	t.assert_true(ArmyLayerScript.arrow_color(false, false) != ArmyLayerScript.arrow_color(true, false))


func test_posizione_del_simbolo_di_assedio(t: TestContext) -> void:
	var one := MarkerLayout.siege_symbol_offset(0, 28.0)
	t.assert_eq(one.x, 0.0)
	t.assert_true(one.y < 0.0, "sopra l'ancora")
	t.assert_true(MarkerLayout.siege_symbol_offset(2, 28.0).y < MarkerLayout.siege_symbol_offset(1, 28.0).y, "più righe, più in alto")


# --- guerre --------------------------------------------------------------------


func test_chiave_di_guerra_ordinata(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.war_key("FN_BETA", "fn_alpha"), "FN_ALPHA|FN_BETA")
	t.assert_eq(CampaignUiText.war_key("FN_ALPHA", "FN_BETA"), "FN_ALPHA|FN_BETA")


func test_nemici_da_dictionary_elenco_e_coppie(t: TestContext) -> void:
	var as_dict := {"FN_ALPHA|FN_BETA": true, "FN_ALPHA|FN_REBEL": true, "FN_BETA|FN_GAMMA": true, "FN_ALPHA|FN_DELTA": true}
	var enemies := CampaignUiText.enemies_from(as_dict, "FN_ALPHA")
	t.assert_eq(enemies, PackedStringArray(["FN_BETA", "FN_DELTA"]), "ribelli esclusi, ordine alfabetico")
	t.assert_eq(CampaignUiText.enemies_from(as_dict, "FN_GAMMA"), PackedStringArray(["FN_BETA"]))
	var as_list := ["FN_ALPHA|FN_BETA", "FN_BETA|FN_GAMMA"]
	t.assert_eq(CampaignUiText.enemies_from(as_list, "fn_beta"), PackedStringArray(["FN_ALPHA", "FN_GAMMA"]))
	var as_pairs := [["FN_BETA", "FN_ALPHA"]]
	t.assert_eq(CampaignUiText.enemies_from(as_pairs, "FN_ALPHA"), PackedStringArray(["FN_BETA"]))
	t.assert_true(CampaignUiText.enemies_from(null, "FN_ALPHA").is_empty(), "nessun dato = nessuna guerra")


func test_nemici_dello_stato_senza_guerre(t: TestContext) -> void:
	var s := _world()
	t.assert_true(CampaignUiText.enemies_of(s, "FN_ALPHA").is_empty(), "partita nuova: nessuna guerra")


func test_testo_della_barra_delle_guerre(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.war_bar_text(PackedStringArray()), "In pace")
	t.assert_eq(CampaignUiText.war_bar_text(PackedStringArray(["FN_BETA"])), "In guerra: Beta")
	var many := PackedStringArray(["FN_A", "FN_B", "FN_C", "FN_D", "FN_E"])
	t.assert_eq(CampaignUiText.war_bar_text(many), "In guerra: A, B, C +2")
	var tip := CampaignUiText.war_tooltip(many)
	t.assert_true(tip.contains("  D") and tip.contains("  E"), "il tooltip ha tutti i nomi: " + tip)
	t.assert_true(CampaignUiText.war_tooltip(PackedStringArray()).contains("nessuna"))


# --- assedi ----------------------------------------------------------------------


func test_assedio_da_dictionary(t: TestContext) -> void:
	var sieges := {"ID_MEZZA": {"fazione": "FN_ALPHA", "anni": 2, "anni_alla_resa": 3, "eserciti": [4]}}
	var info := CampaignUiText.siege_info_from(sieges, "id_mezza")
	t.assert_true(bool(info["assediata"]))
	t.assert_eq(info["assediante"], "FN_ALPHA")
	t.assert_eq(info["anni"], 2)
	t.assert_eq(info["anni_alla_resa"], 3)
	t.assert_eq(info["eserciti"], PackedInt32Array([4]))
	var lines := CampaignUiText.siege_lines_from(info)
	t.assert_eq(lines, PackedStringArray(["Assediata da Alpha", "Anni di assedio: 2", "Resa per fame tra 3 anni"]))
	t.assert_false(bool(CampaignUiText.siege_info_from(sieges, "ID_ALTA")["assediata"]))
	t.assert_true(CampaignUiText.siege_lines_from(CampaignUiText.siege_info_from(sieges, "ID_ALTA")).is_empty())


func test_assedio_da_oggetto_senza_anni_alla_resa(t: TestContext) -> void:
	var siege := FakeSiege.new()
	var info := CampaignUiText.siege_info_from({"ID_MEZZA": siege}, "ID_MEZZA")
	t.assert_eq(info["assediante"], "FN_ALPHA")
	t.assert_eq(info["anni"], 3)
	t.assert_eq(info["anni_alla_resa"], -1, "non esposto")
	t.assert_eq(info["eserciti"], PackedInt32Array([4, 5]))
	t.assert_eq(info["assalto"], 0, "flag booleano presente e falso")
	var lines := CampaignUiText.siege_lines_from(info)
	t.assert_eq(lines.size(), 2, "senza anni alla resa solo assediante e anni")
	siege.assault_ordered = true
	t.assert_eq(CampaignUiText.siege_info_from({"ID_MEZZA": siege}, "ID_MEZZA")["assalto"], 1)
	t.assert_eq(CampaignUiText.siege_info_from(null, "ID_MEZZA")["assalto"], -1, "senza assedi: non noto")


func test_resa_alla_fine_dell_anno(t: TestContext) -> void:
	var info := CampaignUiText.siege_info_from({"ID_MEZZA": {"fazione": "FN_ALPHA", "anni": 5, "anni_alla_resa": 0}}, "ID_MEZZA")
	t.assert_true(CampaignUiText.siege_lines_from(info)[2].contains("fine di quest'anno"))


func test_chi_assedia(t: TestContext) -> void:
	var info := CampaignUiText.siege_info_from({"ID_MEZZA": {"fazione": "FN_ALPHA", "anni": 1, "eserciti": [4, 5]}}, "ID_MEZZA")
	t.assert_true(CampaignUiText.is_besieging_from(info, 4, "fn_alpha"))
	t.assert_false(CampaignUiText.is_besieging_from(info, 9, "FN_ALPHA"), "esercito non tra gli assedianti")
	t.assert_false(CampaignUiText.is_besieging_from(info, 4, "FN_BETA"), "altra fazione")
	var no_list := CampaignUiText.siege_info_from({"ID_MEZZA": {"fazione": "FN_ALPHA", "anni": 1}}, "ID_MEZZA")
	t.assert_true(CampaignUiText.is_besieging_from(no_list, 9, "FN_ALPHA"), "elenco non noto: conta la fazione")


func test_stato_di_un_esercito_nel_castello_o_che_assedia(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.army_status_text(false, false, false, 0, -1), "")
	t.assert_eq(CampaignUiText.army_status_text(true, false, false, 0, -1), "Stato: in guarnigione nel castello")
	var besieged := CampaignUiText.army_status_text(true, false, true, 2, -1)
	t.assert_true(besieged.contains("assediato") and besieged.contains("2"), besieged)
	var besieging := CampaignUiText.army_status_text(false, true, false, 1, 0)
	t.assert_true(besieging.contains("assedia il castello") and not besieging.contains("Assalto ordinato"), besieging)
	t.assert_true(CampaignUiText.army_status_text(false, true, false, 1, 1).contains("Assalto ordinato"))


func test_stato_e_descrizione_senza_dati_della_fase_3(t: TestContext) -> void:
	var s := _world()
	var army := s.create_army("FN_ALPHA", "ID_ALTA", false)
	army.stacks.append(UnitStack.new("SPEARMEN", 60, 0))
	t.assert_eq(CampaignUiText.army_status(s, army), "", "nessun assedio")
	t.assert_false(CampaignUiText.is_besieging(s, army))
	t.assert_true(CampaignUiText.assault_state(s, army) <= 0, "nessun assalto ordinato")
	army.path = PackedStringArray(["ID_MEZZA"])
	var text := CampaignUiText.describe_army(s, army)
	t.assert_true(text.contains("Attacco a Mezza"), text)
	army.path = PackedStringArray(["ID_BASSA"])
	t.assert_false(CampaignUiText.describe_army(s, army).contains("Attacco"))


# --- testi degli eventi ----------------------------------------------------------


func test_testo_di_una_battaglia_completa(t: TestContext) -> void:
	var s := _world()
	var e := _ev("EV_BATTLE", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "tipo_battaglia": "campo",
			"attaccanti": ["FN_ALPHA"], "difensori": ["FN_BETA"], "forze": {"attaccanti": 1200.4, "difensori": 900},
			"vincitore": "FN_ALPHA", "perdite": {"FN_ALPHA": 120, "FN_BETA": 340}, "testo": "ignorato"})
	t.assert_eq(CampaignUiText.format_event(s, e), "Battaglia in campo a Mezza: Alpha contro Beta (forze 1200 contro 900). Vince Alpha. Perdite: Alpha 120 uomini, Beta 340 uomini.")


func test_battaglia_con_dettagli_in_altre_forme(t: TestContext) -> void:
	var s := _world()
	var e := _ev("EV_BATTLE", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "tipo_battaglia": "assalto",
			"attaccanti": "FN_ALPHA", "difensori": ["FN_BETA", "FN_GAMMA"], "forza_attaccanti": 50, "forza_difensori": 70,
			"vincitore": "difensori", "perdite": {"FN_BETA": {"uomini": 10}}})
	var text := CampaignUiText.format_event(s, e)
	t.assert_eq(text, "Assalto al castello a Mezza: Alpha contro Beta e Gamma (forze 50 contro 70). Vincono Beta e Gamma. Perdite: Beta 10 uomini.")
	var naval := _ev("EV_BATTLE", {"fazione": "FN_ALPHA", "regione": "ID_MARE_NORD", "tipo_battaglia": "navale", "attaccanti": ["FN_ALPHA"], "difensori": ["FN_BETA"], "vincitore": ""})
	t.assert_eq(CampaignUiText.format_event(s, naval), "Scontro navale a %s: Alpha contro Beta." % CampaignUiText.region_name(s, "ID_MARE_NORD"))


func test_battaglia_con_eserciti_al_posto_delle_fazioni(t: TestContext) -> void:
	var s := _world()
	var mine := s.create_army("FN_ALPHA", "ID_ALTA", false)
	var theirs := s.create_army("FN_BETA", "ID_ALTA", false)
	var e := _ev("EV_BATTLE", {"fazione": "FN_ALPHA", "regione": "ID_ALTA", "attaccanti": [mine.id], "difensori": [theirs.id], "attaccante_vince": true})
	t.assert_eq(CampaignUiText.format_event(s, e), "Battaglia a Alta: Alpha contro Beta. Vince Alpha.")
	t.assert_true(CampaignUiText.event_mentions(e, "FN_BETA") == false, "gli id degli eserciti non sono fazioni")


func test_battaglia_senza_dettagli_usa_il_testo_della_simulazione(t: TestContext) -> void:
	var s := _world()
	var e := _ev("EV_BATTLE", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "testo": "Testo della simulazione"})
	t.assert_eq(CampaignUiText.format_event(s, e), "Testo della simulazione")


func test_testi_degli_altri_eventi_della_fase_3(t: TestContext) -> void:
	var s := _world()
	var f := CampaignUiText
	t.assert_eq(f.format_event(s, _ev("EV_WAR_DECLARED", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "contro": "FN_BETA"})), "Alpha dichiara guerra a Beta.")
	t.assert_eq(f.format_event(s, _ev("EV_WAR_DECLARED", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA"})), "Alpha dichiara guerra (attacco a Mezza).")
	t.assert_eq(f.format_event(s, _ev("EV_RETREAT", {"fazione": "FN_BETA", "esercito": 7, "da": "ID_MEZZA", "a": "ID_ALTA"})), "Esercito 7 si ritira da Mezza a Alta.")
	t.assert_eq(f.format_event(s, _ev("EV_CAPTURED_UNITS", {"fazione": "FN_BETA", "regione": "ID_MEZZA", "uomini": 40})), "40 uomini di Beta catturati a Mezza.")
	t.assert_eq(f.format_event(s, _ev("EV_SIEGE_STARTED", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA"})), "Alpha inizia l'assedio del castello di Mezza.")
	t.assert_eq(f.format_event(s, _ev("EV_SIEGE_ENDED", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "anni": 3, "motivo": "gli assedianti se ne sono andati"})), "L'assedio di Mezza è terminato dopo 3 anni (gli assedianti se ne sono andati).")
	t.assert_eq(f.format_event(s, _ev("EV_STARVED", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "anni": 4})), "La guarnigione di Mezza si arrende per fame dopo 4 anni di assedio.")
	t.assert_eq(f.format_event(s, _ev("EV_ASSAULT", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA"})), "Alpha assalta il castello di Mezza.")
	t.assert_eq(f.format_event(s, _ev("EV_SALLY", {"fazione": "FN_BETA", "regione": "ID_MEZZA"})), "La guarnigione di Mezza fa una sortita.")
	t.assert_eq(f.format_event(s, _ev("EV_PROVINCE_CAPTURED", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "precedente": "FN_BETA"})), "Alpha conquista Mezza (era di Beta).")
	t.assert_eq(f.format_event(s, _ev("EV_FACTION_DESTROYED", {"fazione": "FN_GAMMA"})), "Gamma è stata distrutta.")


func test_assalto_e_sortita_con_dettagli_di_battaglia(t: TestContext) -> void:
	var s := _world()
	var assault := _ev("EV_ASSAULT", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "attaccanti": ["FN_ALPHA"], "difensori": ["FN_BETA"], "vincitore": "FN_ALPHA"})
	t.assert_eq(CampaignUiText.format_event(s, assault), "Assalto al castello a Mezza: Alpha contro Beta. Vince Alpha.")
	var sally := _ev("EV_SALLY", {"fazione": "FN_BETA", "regione": "ID_MEZZA", "attaccanti": ["FN_BETA"], "difensori": ["FN_ALPHA"], "vincitore": "attaccanti"})
	t.assert_eq(CampaignUiText.format_event(s, sally), "Sortita della guarnigione a Mezza: Beta contro Alpha. Vince Beta.")


func test_eventi_vecchi_e_sconosciuti_restano_uguali(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiText.format_event(s, {"tipo": "altro"}), "altro")
	t.assert_eq(CampaignUiText.format_event(s, {"tipo": GameState.EV_MOVED, "esercito": 2, "da": "ID_ALTA", "a": "ID_BASSA"}), "Esercito 2: da Alta a Bassa.")


func test_chi_e_nominato_in_un_evento(t: TestContext) -> void:
	var e := _ev("EV_BATTLE", {"fazione": "FN_ALPHA", "attaccanti": ["FN_ALPHA"], "difensori": ["fn_beta"], "perdite": {"FN_GAMMA": 3}, "testo": "FN_DELTA"})
	t.assert_true(CampaignUiText.event_mentions(e, "FN_ALPHA"))
	t.assert_true(CampaignUiText.event_mentions(e, "FN_BETA"), "anche in minuscolo, nei difensori")
	t.assert_true(CampaignUiText.event_mentions(e, "FN_GAMMA"), "nelle chiavi delle perdite")
	t.assert_false(CampaignUiText.event_mentions(e, "FN_DELTA"), "il testo libero non conta")


# --- resoconto di fine anno ---------------------------------------------------------


func test_resoconto_con_sezioni_della_fase_3(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	s.events.append({"tipo": GameState.EV_MOVED, "anno": 1000, "fazione": "FN_ALPHA", "esercito": 2, "da": "ID_ALTA", "a": "ID_BASSA"})
	s.events.append(_ev("EV_WAR_DECLARED", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "contro": "FN_BETA"}))
	s.events.append(_ev("EV_BATTLE", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "attaccanti": ["FN_ALPHA"], "difensori": ["FN_BETA"], "vincitore": "FN_ALPHA"}))
	s.events.append(_ev("EV_BATTLE", {"fazione": "FN_BETA", "regione": "ID_SOLA", "attaccanti": ["FN_BETA"], "difensori": ["FN_GAMMA"], "vincitore": "FN_BETA"}))
	s.events.append(_ev("EV_PROVINCE_CAPTURED", {"fazione": "FN_ALPHA", "regione": "ID_MEZZA", "precedente": "FN_BETA"}))
	s.events.append(_ev("EV_FACTION_DESTROYED", {"fazione": "FN_GAMMA"}))
	var lines := CampaignUiText.year_report(s, "fn_alpha", {"ok": true, "avvisi": [], "errori": []})
	var expected := PackedStringArray([
		"— Battaglie —",
		"  Battaglia a Mezza: Alpha contro Beta. Vince Alpha.",
		"— Conquiste —",
		"  Alpha conquista Mezza (era di Beta).",
		"— Fazioni distrutte —",
		"  Gamma è stata distrutta.",
		"— Guerre dichiarate —",
		"  Alpha dichiara guerra a Beta.",
		"— Altri eventi —",
		"Esercito 2: da Alta a Bassa.",
	])
	t.assert_eq(lines, expected, "\n".join(lines))


func test_resoconto_senza_intestazioni_se_non_ci_sono_eventi_della_fase_3(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	s.events.append({"tipo": GameState.EV_MOVED, "anno": 1000, "fazione": "FN_ALPHA", "esercito": 2, "da": "ID_ALTA", "a": "ID_BASSA"})
	s.events.append(_ev("EV_BATTLE", {"fazione": "FN_BETA", "regione": "ID_SOLA", "attaccanti": ["FN_BETA"], "difensori": ["FN_GAMMA"]}))
	var lines := CampaignUiText.year_report(s, "FN_ALPHA", {"ok": true, "avvisi": [], "errori": []})
	t.assert_eq(lines, PackedStringArray(["Esercito 2: da Alta a Bassa."]))


func test_sezioni_della_fase_3_in_ordine(t: TestContext) -> void:
	var sections := CampaignUiText.phase3_sections()
	var titles := PackedStringArray()
	for sec in sections:
		titles.append(str(sec["titolo"]))
	t.assert_eq(titles, PackedStringArray(["Battaglie", "Conquiste", "Assedi", "Ritirate e catture", "Fazioni distrutte", "Guerre dichiarate"]))
	var kinds: PackedStringArray = sections[0]["tipi"]
	t.assert_eq(kinds, PackedStringArray([CampaignUiText.event_kind("EV_BATTLE"), CampaignUiText.event_kind("EV_ADMIRAL_PROMOTED")]), "con le promozioni degli ammiragli (ADR-056)")
