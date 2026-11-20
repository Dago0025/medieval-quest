extends RefCounted
## Notizie dalle altre fazioni (richiesta di Federico del 2026-11-13): guerre, diplomazia, crociate e jihad, scomuniche e
## successioni delle fazioni che non sono il giocatore arrivano nel resoconto di fine anno in una sezione propria; crociate
## e jihad bandite (e quelle dirette contro il giocatore) hanno anche una finestra illustrata. Mondo: sim_startpos.txt.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)
	s.events.clear()
	return s


func _section(secs: Array[Dictionary], title: String) -> PackedStringArray:
	for sec in secs:
		if str(sec.get("titolo", "")) == title:
			return sec["righe"]
	return PackedStringArray()


func test_la_guerra_tra_due_altre_fazioni_arriva_nelle_notizie(t: TestContext) -> void:
	var s := _world()
	s.declare_war("FN_BETA", "FN_GAMMA")
	s.add_event(GameState.EV_WAR_DECLARED, {"fazione": "FN_BETA", "contro": "FN_GAMMA", "testo": "BETA dichiara guerra a GAMMA."})
	s.add_event(GameState.EV_ALLIANCE_FORMED, {"fazione": "FN_BETA", "con": "FN_GAMMA", "testo": "Alleanza tra BETA e GAMMA."})
	var secs := CampaignUiText.year_report_sections(s, "FN_ALPHA", {})
	var news := _section(secs, CampaignUiText.NEWS_TITLE)
	t.assert_true(news.size() >= 2, "guerra e alleanza tra altre fazioni: %s" % str(secs))
	t.assert_true(_section(secs, "Guerre dichiarate").is_empty(), "le guerre degli altri non vanno tra quelle del giocatore")


func test_gli_eventi_del_giocatore_restano_nelle_loro_sezioni(t: TestContext) -> void:
	var s := _world()
	s.add_event(GameState.EV_WAR_DECLARED, {"fazione": "FN_BETA", "contro": "FN_ALPHA", "testo": "BETA dichiara guerra ad ALPHA."})
	var secs := CampaignUiText.year_report_sections(s, "FN_ALPHA", {})
	t.assert_eq(_section(secs, "Guerre dichiarate").size(), 1, "guerra contro il giocatore nella sua sezione")
	t.assert_true(_section(secs, CampaignUiText.NEWS_TITLE).is_empty(), "e non ripetuta nelle notizie")


func test_eventi_minori_degli_altri_restano_fuori(t: TestContext) -> void:
	var s := _world()
	s.add_event(GameState.EV_BUILT, {"fazione": "FN_BETA", "provincia": "ID_MEZZA", "edificio": "PORT", "livello": 1})
	s.add_event(GameState.EV_BATTLE, {"fazione": "FN_BETA", "regione": "ID_SOLA", "testo": "Battaglia a Sola."})
	t.assert_true(CampaignUiText.year_report_sections(s, "FN_ALPHA", {}).is_empty(), "costruzioni e battaglie degli altri no")


func test_crociata_bandita_ha_la_sua_finestra(t: TestContext) -> void:
	var s := _world()
	s.add_event(GameState.EV_CRUSADE_LAUNCHED, {"fazione": "FN_BETA", "genere": "crociata", "provincia": "ID_MEZZA", "esercito": 0,
		"pile": 4, "zelo": 50, "testo": "BETA bandisce una crociata."})
	s.add_event(GameState.EV_CRUSADE_LAUNCHED, {"fazione": "FN_GAMMA", "genere": "jihad", "provincia": "ID_SOLA", "esercito": 0,
		"pile": 3, "zelo": 40, "testo": "GAMMA proclama la jihad."})
	var windows := CampaignUiEvents.news_windows(s, "FN_ALPHA")
	t.assert_eq(windows.size(), 2)
	t.assert_eq(str(windows[0]["titolo"]), "Crociata bandita")
	t.assert_eq(str(windows[0]["chiave"]), "crociata")
	t.assert_eq(int(windows[0]["indice"]), -1)
	t.assert_true(str(windows[0]["effetto"]).begins_with("guidata "), str(windows[0]["effetto"]))
	t.assert_eq(str(windows[1]["titolo"]), "Jihad proclamata")
	t.assert_eq(str(windows[1]["chiave"]), "jihad")
	var news := _section(CampaignUiText.year_report_sections(s, "FN_ALPHA", {}), CampaignUiText.NEWS_TITLE)
	t.assert_eq(news.size(), 2, "anche nel resoconto")


func test_crociata_contro_il_giocatore(t: TestContext) -> void:
	var s := _world()
	s.add_event(GameState.EV_CRUSADE_TARGET, {"fazione": "FN_BETA", "genere": "crociata", "esercito": 0, "bersaglio": "ID_ALTA",
		"proprietario": "FN_ALPHA", "testo": "La crociata punta su Alta."})
	s.add_event(GameState.EV_CRUSADE_TARGET, {"fazione": "FN_BETA", "genere": "crociata", "esercito": 0, "bersaglio": "ID_SOLA",
		"proprietario": "FN_REBEL", "testo": "La crociata punta su Sola."})
	var windows := CampaignUiEvents.news_windows(s, "FN_ALPHA")
	t.assert_eq(windows.size(), 1, "solo quella contro una provincia del giocatore")
	t.assert_eq(str(windows[0]["titolo"]), "La crociata marcia contro di voi")


func test_le_unita_arruolate_non_compaiono_nel_resoconto(t: TestContext) -> void:
	var s := _world()
	s.add_event(GameState.EV_RECRUITED, {"fazione": "FN_ALPHA", "provincia": "ID_ALTA", "unita": "Spearmen", "esercito": 1})
	t.assert_true(CampaignUiText.year_report_sections(s, "FN_ALPHA", {}).is_empty(), "nessuna riga per le reclute dell'anno")
	s.add_event(GameState.EV_BUILT, {"fazione": "FN_ALPHA", "provincia": "ID_ALTA", "edificio": "PORT", "livello": 1})
	var secs := CampaignUiText.year_report_sections(s, "FN_ALPHA", {})
	t.assert_eq((secs[0]["righe"] as PackedStringArray).size(), 1, "la costruzione resta")

