extends RefCounted
## Informazioni al passaggio del mouse (CampaignUiHover, richiesta di Federico del 2026-11-13) sul mondo piccolo
## tests/fixtures/sim_*.txt: esercito 1 = ALPHA in ALTA, 2 = flotta ALPHA in ID_MARE_NORD, 4 = BETA in MEZZA, 5 = ribelli in SOLA.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


func _fleet(s: GameState, faction_id: String, zone: String) -> Army:
	var a := s.create_army(faction_id, zone, true)
	a.stacks.append(UnitStack.new("Galley", 4, 0))
	return a


func test_pedine_vostre_nemiche_alleate_neutrali(t: TestContext) -> void:
	var s := _world()
	t.assert_true(CampaignUiHover.army_text(s, "FN_ALPHA", s.army(1)).contains("Vostro"), "esercito proprio")
	t.assert_true(CampaignUiHover.army_text(s, "FN_ALPHA", s.army(2)).contains("Vostra"), "flotta propria")
	var beta := CampaignUiHover.army_text(s, "FN_ALPHA", s.army(4))
	t.assert_true(beta.begins_with("Esercito") and beta.contains("Neutrali"), beta)
	t.assert_true(CampaignUiHover.army_text(s, "FN_ALPHA", s.army(5)).contains("Ribelli"), "ribelli")
	s.declare_war("FN_ALPHA", "FN_BETA")
	t.assert_true(CampaignUiHover.army_text(s, "FN_ALPHA", s.army(4)).contains("In guerra con voi"))
	s.end_war("FN_ALPHA", "FN_BETA")
	s.form_alliance("FN_ALPHA", "FN_BETA")
	t.assert_true(CampaignUiHover.army_text(s, "FN_ALPHA", s.army(4)).contains("Alleati"))
	var other := _fleet(s, "FN_GAMMA", "ID_MARE_SUD")
	var text := CampaignUiHover.army_text(s, "FN_ALPHA", other)
	t.assert_true(text.begins_with("Flotta") and text.contains("1 unità"), text)


func test_acque_neutrali_vostre_nemiche_e_blocco(t: TestContext) -> void:
	var s := _world()
	var empty := CampaignUiHover.region_text(s, "FN_ALPHA", "ID_MARE_SUD")
	t.assert_true(empty.contains("Acque neutrali"), empty)
	var own := CampaignUiHover.region_text(s, "FN_ALPHA", "ID_MARE_NORD")
	t.assert_true(own.contains("Acque vostre"), own)
	var beta := _fleet(s, "FN_BETA", "ID_MARE_NORD")
	s.rules.combat.neutral_blockade = true
	var mine := s.army(2).stacks.size()
	if mine >= 1:
		var even := CampaignUiHover.region_text(s, "FN_ALPHA", "ID_MARE_NORD")
		if mine == 1:
			t.assert_true(even.contains("Nessun blocco navale") and not even.contains("Blocco navale"), "navi pari: nessun blocco\n" + even)
	while beta.stacks.size() <= mine:
		beta.stacks.append(UnitStack.new(beta.stacks[0].unit_id, 4, 0))   # Beta ha piu' navi: blocco (22/11/2026)
	var blocked := CampaignUiHover.region_text(s, "FN_ALPHA", "ID_MARE_NORD")
	t.assert_true(blocked.contains("Blocco navale") and blocked.contains("Beta"), blocked)
	s.declare_war("FN_ALPHA", "FN_BETA")
	var hostile := CampaignUiHover.region_text(s, "FN_ALPHA", "ID_MARE_NORD")
	t.assert_true(hostile.contains("Acque nemiche") and hostile.contains("Blocco navale"), hostile)
	t.assert_true(CampaignUiHover.region_text(s, "FN_ALPHA", "ID_MARE_SUD", {"ID_ALTA": true}).contains("non osservate"), "nebbia")


func test_province(t: TestContext) -> void:
	var s := _world()
	t.assert_true(CampaignUiHover.region_text(s, "FN_ALPHA", "ID_ALTA").contains("Vostra provincia"))
	var beta := CampaignUiHover.region_text(s, "FN_ALPHA", "ID_MEZZA")
	t.assert_true(beta.contains("Neutrali"), beta)


func test_colori_del_rapporto(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiHover.relation_kind(s, "FN_ALPHA", "FN_ALPHA"), "")
	t.assert_eq(CampaignUiHover.relation_kind(s, "FN_ALPHA", "FN_BETA"), "neutrale")
	t.assert_eq(CampaignUiHover.relation_kind(s, "FN_ALPHA", "FN_REBEL"), "nemico")
	var neutral := CampaignUiHover.army_text(s, "FN_ALPHA", s.army(4), true)
	t.assert_true(neutral.contains("[color=#%s]" % CampaignUiHover.COLOR_NEUTRAL), "neutrali in blu: " + neutral)
	s.declare_war("FN_ALPHA", "FN_BETA")
	t.assert_true(CampaignUiHover.army_text(s, "FN_ALPHA", s.army(4), true).contains("[color=#%s]" % CampaignUiHover.COLOR_ENEMY), "nemici in rosso")
	s.end_war("FN_ALPHA", "FN_BETA")
	s.form_alliance("FN_ALPHA", "FN_BETA")
	t.assert_true(CampaignUiHover.army_text(s, "FN_ALPHA", s.army(4), true).contains("[color=#%s]" % CampaignUiHover.COLOR_ALLY), "alleati in verde")
	t.assert_false(CampaignUiHover.army_text(s, "FN_ALPHA", s.army(4)).contains("[color"), "senza rich nessun codice")
	t.assert_false(CampaignUiHover.army_text(s, "FN_ALPHA", s.army(1), true).contains("[color"), "la propria fazione senza colore")
