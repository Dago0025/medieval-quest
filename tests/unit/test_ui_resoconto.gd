extends RefCounted
## Test del resoconto di fine anno impaginato (CampaignUiReport) e dei suoi blocchi (CampaignUiText.year_report_sections),
## sul mondo piccolo tests/fixtures/sim_*.txt.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


func _result() -> Dictionary:
	return {"ok": true, "avvisi": ["FN_ALPHA: tesoro negativo (-3) nell'anno 1000", "altro avviso"], "errori": ["unità sconosciuta"]}


func test_blocchi_del_resoconto(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	s.add_event(GameState.EV_BUILT, {"fazione": "FN_ALPHA", "provincia": "ID_ALTA", "edificio": "PORT", "livello": 1})
	s.add_event(GameState.EV_NEGATIVE_TREASURY, {"fazione": "FN_ALPHA", "tesoro": -3})
	var secs := CampaignUiText.year_report_sections(s, "fn_alpha", _result())
	t.assert_eq(secs.size(), 3)
	t.assert_eq(str(secs[0]["tipo"]), CampaignUiText.REPORT_OTHERS)
	t.assert_eq(str(secs[0]["titolo"]), "", "senza sezioni gli altri eventi non hanno intestazione")
	t.assert_eq((secs[0]["righe"] as PackedStringArray).size(), 2)
	t.assert_eq(str(secs[1]["tipo"]), CampaignUiText.REPORT_WARNINGS)
	t.assert_eq((secs[1]["righe"] as PackedStringArray)[0], "altro avviso", "l'avviso di tesoro negativo non si ripete")
	t.assert_eq(str(secs[2]["tipo"]), CampaignUiText.REPORT_ERRORS)
	t.assert_eq(CampaignUiReport.event_count(secs), 2, "avvisi ed errori non contano")


func test_resoconto_vuoto(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	t.assert_true(CampaignUiText.year_report_sections(s, "FN_ALPHA", {}).is_empty())
	t.assert_eq(CampaignUiReport.subtitle(1001, []), "Ora è il 1001 · nessun avvenimento")


func test_impaginazione_con_sezioni_e_nomi_in_grassetto(t: TestContext) -> void:
	var s := _world()
	var secs: Array[Dictionary] = [
		{"tipo": CampaignUiText.REPORT_SECTION, "titolo": "Conquiste", "righe": PackedStringArray(["Alta passa a Beta."])},
		{"tipo": CampaignUiText.REPORT_OTHERS, "titolo": "Altri eventi", "righe": PackedStringArray(["Peste ad Alta. «Il contagio [grave] dilaga.»"])},
		{"tipo": CampaignUiText.REPORT_WARNINGS, "titolo": "", "righe": PackedStringArray(["attenzione"])},
	]
	var code := CampaignUiReport.bbcode(s, secs, "FN_ALPHA", "La campagna è finita.")
	t.assert_true(code.contains("Conquiste"), code)
	t.assert_true(code.contains("Avvisi"), "gli avvisi hanno la loro intestazione")
	t.assert_true(code.contains("[table=2]"), "un avvenimento per riga, con il rientro sospeso")
	t.assert_true(code.contains("[b]Alta[/b]"), "le province in grassetto: " + code)
	var beta := CampaignUiText.faction_name("FN_BETA")
	t.assert_true(code.contains("[color=#%s]%s[/color]" % [UiTheme.INK_BLUE.to_html(false), beta]), "le altre fazioni in blu")
	t.assert_true(code.contains("[i]"), "la frase dell'originale in corsivo")
	t.assert_true(code.contains("[lb]grave]"), "le parentesi quadre del testo non diventano BBCode")
	t.assert_true(code.contains("[b]La campagna è finita.[/b]"))
	t.assert_eq(CampaignUiReport.subtitle(1001, secs), "Ora è il 1001 · 2 avvenimenti")


func test_nomi_come_parole_intere(t: TestContext) -> void:
	var names := {"Alta": null, "Alta Valle": null}
	var re := CampaignUiReport.name_pattern(names)
	t.assert_eq(CampaignUiReport.highlight("Altamura e Alta Valle", names, re), "Altamura e [b]Alta Valle[/b]")
	t.assert_eq(CampaignUiReport.highlight("Verso Alta.", names, re), "Verso [b]Alta[/b].")


func test_frase_dell_originale(t: TestContext) -> void:
	var p := CampaignUiReport.split_quote("Tempesta in Mar Baltico. «Tempesta in Mar Baltico.»")
	t.assert_eq(p[0], "Tempesta in Mar Baltico.")
	t.assert_eq(p[1], "Tempesta in Mar Baltico.")
	var q := CampaignUiReport.split_quote("Nessuna frase qui.")
	t.assert_eq(q[1], "")
