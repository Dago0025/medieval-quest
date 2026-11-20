extends RefCounted
## Conferma degli attacchi e attacco a una flotta precisa (CampaignUiAttack, richiesta di Federico del 2026-11-13) sul mondo
## piccolo tests/fixtures/sim_*.txt: esercito 1 = ALPHA in ALTA, 2 = flotta ALPHA in ID_MARE_NORD, 4 = BETA in MEZZA,
## 5 = ribelli in SOLA. Fazioni: REBEL, ALPHA, BETA, GAMMA, tutte in pace tra loro all'inizio.

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


func test_conferma_solo_se_l_attacco_apre_una_guerra(t: TestContext) -> void:
	var s := _world()
	var other := _fleet(s, "FN_BETA", "ID_MARE_SUD")
	t.assert_eq(CampaignUiAttack.new_wars_naval(s, s.army(2), other), PackedStringArray(["FN_BETA"]), "in pace: serve la conferma")
	t.assert_eq(CampaignUiAttack.new_wars_entering(s, s.army(4), "ID_ALTA"), PackedStringArray(["FN_ALPHA"]), "provincia di ALPHA, in pace")
	s.declare_war("FN_ALPHA", "FN_BETA")
	t.assert_eq(CampaignUiAttack.new_wars_naval(s, s.army(2), other), PackedStringArray(), "gia' in guerra: niente conferma")
	t.assert_eq(CampaignUiAttack.new_wars_entering(s, s.army(1), "ID_BASSA"), PackedStringArray(), "provincia propria: niente conferma")
	t.assert_eq(CampaignUiAttack.new_wars_entering(s, s.army(4), "ID_ALTA"), PackedStringArray(), "dopo la dichiarazione di guerra: niente conferma")
	t.assert_eq(CampaignUiAttack.new_wars_entering(s, s.army(4), "ID_SOLA"), PackedStringArray(), "i ribelli sono sempre in guerra")


func test_testo_della_conferma_secondo_il_rapporto(t: TestContext) -> void:
	var s := _world()
	var other := _fleet(s, "FN_BETA", "ID_MARE_SUD")
	var subject := CampaignUiAttack.naval_subject(s, other)
	t.assert_true(subject.begins_with("Attaccare la flotta"), subject)
	var peace := CampaignUiAttack.prompt_text(s, "FN_ALPHA", PackedStringArray(["FN_BETA"]), subject)
	t.assert_true(peace.begins_with(subject), peace)
	t.assert_true(peace.contains("in pace") and peace.contains("dichiarazione di guerra"), peace)
	s.form_alliance("FN_ALPHA", "FN_BETA")
	var ally := CampaignUiAttack.prompt_text(s, "FN_ALPHA", PackedStringArray(["FN_BETA"]), subject)
	t.assert_true(ally.contains("rompe l'alleanza"), ally)
	t.assert_eq(CampaignUiAttack.prompt_text(s, "FN_ALPHA", PackedStringArray(), subject), "", "nessuna guerra nuova: nessun testo")


func test_flotta_lasciata_sulla_zona_attacca_solo_le_flotte_in_guerra(t: TestContext) -> void:
	var s := _world()
	t.assert_true(CampaignUiAttack.fleet_target_in(s, s.army(2), "ID_MARE_SUD") == null, "zona vuota: movimento normale")
	var other := _fleet(s, "FN_BETA", "ID_MARE_SUD")
	t.assert_true(CampaignUiAttack.fleet_target_in(s, s.army(2), "ID_MARE_SUD") == null, "flotta neutrale: si convive, nessun attacco")
	t.assert_eq(CampaignUiAttack.new_wars_entering(s, s.army(2), "ID_MARE_SUD"), PackedStringArray(), "nessuna conferma")
	t.assert_false(CampaignUiText.attack_target(s, s.army(2), "ID_MARE_SUD"), "zona non rossa mentre si trascina")
	s.declare_war("FN_ALPHA", "FN_BETA")
	t.assert_eq(CampaignUiAttack.fleet_target_in(s, s.army(2), "ID_MARE_SUD"), other, "in guerra: attacca e insegue")
	t.assert_true(CampaignUiText.attack_target(s, s.army(2), "ID_MARE_SUD"))
	t.assert_true(CampaignUiAttack.fleet_target_in(s, s.army(2), "ID_MARE_SUD", {"ID_ALTA": true}) == null, "nella nebbia non si vede")
	t.assert_true(CampaignUiAttack.fleet_target_in(s, s.army(1), "ID_MARE_SUD") == null, "un esercito di terra non attacca flotte")


func test_messaggi_dell_ordine(t: TestContext) -> void:
	var s := _world()
	var near := _fleet(s, "FN_BETA", "ID_MARE_NORD")
	var r := GameCommands.order_naval_attack(s, "FN_ALPHA", 2, near.id)
	var here := CampaignUiAttack.naval_order_text(s, s.army(2), near, r)
	t.assert_true(here.contains("qui in") and here.contains("La guerra si dichiara a fine anno."), here)
	t.assert_true(CampaignUiAttack.target_line(s, s.army(2)).contains("flotta %d" % near.id), "riga della scheda")
	var far := _fleet(s, "FN_GAMMA", "ID_MARE_SUD")
	s.declare_war("FN_ALPHA", "FN_GAMMA")
	r = GameCommands.order_naval_attack(s, "FN_ALPHA", 2, far.id)
	var there := CampaignUiAttack.naval_order_text(s, s.army(2), far, r)
	t.assert_true(there.contains("attacco alla flotta") and there.contains("la insegue"), there)
	t.assert_false(there.contains("La guerra si dichiara"), "gia' in guerra")
	t.assert_true(CampaignUiText.describe_army(s, s.army(2)).contains("All'attacco della flotta"), "scheda della flotta")
