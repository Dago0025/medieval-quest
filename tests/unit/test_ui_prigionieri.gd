extends RefCounted
## Test della finestra dei prigionieri (ADR-073): testi e scelte per il vincitore e per lo sconfitto, esito dei pulsanti,
## resoconto di fine anno. Mondo di prova: papacy_world.gd.

const W := preload("res://tests/unit/papacy_world.gd")


## GAMMA batte ALPHA a EST; `player` e' la fazione del giocatore. Se ALPHA non ha vie di ritirata il re e' prigioniero.
func _world(player: String, king_taken: bool) -> GameState:
	var s := W.world()
	s.declare_war(W.A, W.G)
	s.rules.combat.forced_outcome = -1
	s.leader_of(W.G).dread = 0
	s.faction(player).is_player = true
	var army := W.land_army(s, W.A, W.NORD1)
	army.region = W.EST
	army.from_region = "" if king_taken else W.NORD1
	army.arrived_year = s.year
	if king_taken:
		s.province(W.NORD1).owner = W.D
	WarProcessor.field_battles(s)
	PrisonerProcessor.process_year(s)
	return s


func test_la_finestra_del_vincitore(t: TestContext) -> void:
	var s := _world(W.G, true)
	var ids := CampaignUiPrisoners.queue_ids(s, W.G)
	t.assert_eq(ids.size(), 1)
	var w := CampaignUiPrisoners.window_of(s, W.G, ids[0])
	t.assert_true(str(w["titolo"]).contains(SimUtil.faction_label(W.A)))
	t.assert_true(str(w["testo"]).contains(s.leader_of(W.A).full_name()), "il re e' tra i prigionieri")
	var choices: Array = w["scelte"]
	t.assert_eq(choices.size(), 3)
	t.assert_eq((choices[0] as Dictionary)["id"], CampaignUiPrisoners.RELEASE)
	t.assert_eq((choices[1] as Dictionary)["id"], CampaignUiPrisoners.RANSOM)
	t.assert_eq((choices[2] as Dictionary)["id"], CampaignUiPrisoners.EXECUTE)
	t.assert_true(str((choices[1] as Dictionary)["testo"]).contains(str(PrisonerProcessor.price(s, s.prisoners[0]))), "il prezzo sul pulsante")
	t.assert_true(CampaignUiPrisoners.window_of(s, W.A, ids[0]).is_empty(), "non per chi ha perso")
	var r := CampaignUiPrisoners.answer(s, W.G, ids[0], CampaignUiPrisoners.RELEASE)
	t.assert_true(bool(r["ok"]))
	t.assert_true(str(r["testo"]) != "")
	t.assert_true(CampaignUiPrisoners.queue_ids(s, W.G).is_empty())


func test_la_finestra_del_riscatto(t: TestContext) -> void:
	var s := _world(W.A, false)
	var ids := CampaignUiPrisoners.queue_ids(s, W.A)
	t.assert_eq(ids.size(), 1, "l'IA vincitrice chiede il riscatto al giocatore")
	var w := CampaignUiPrisoners.window_of(s, W.A, ids[0])
	var choices: Array = w["scelte"]
	t.assert_eq(choices.size(), 2)
	t.assert_eq((choices[0] as Dictionary)["id"], CampaignUiPrisoners.PAY)
	t.assert_eq((choices[1] as Dictionary)["id"], CampaignUiPrisoners.REFUSE)
	t.assert_true(str(w["testo"]).contains(CampaignUiText.region_name(s, W.NORD1)), "dice dove tornerebbero")
	var r := CampaignUiPrisoners.answer(s, W.A, ids[0], CampaignUiPrisoners.REFUSE)
	t.assert_true(bool(r["ok"]))
	t.assert_true(s.prisoners.is_empty())


func test_il_resoconto_mostra_i_prigionieri(t: TestContext) -> void:
	var s := _world(W.G, false)
	var found := false
	for section in CampaignUiText.report_sections():
		if (section["tipi"] as PackedStringArray).has(GameState.EV_PRISONERS):
			found = true
	t.assert_true(found, "i prigionieri stanno nella sezione delle ritirate e catture")
	var taken := W.events_of(s, GameState.EV_PRISONERS)
	t.assert_eq(taken.size(), 1)
	t.assert_eq(CampaignUiText.format_event(s, taken[0]), str(taken[0]["testo"]))
	var partial := W.events_of(s, GameState.EV_CAPTURED_UNITS)
	t.assert_eq(partial.size(), 1, "gli uomini presi nella ritirata compaiono tra le catture")
	t.assert_eq(partial[0]["caso"], "ritirata")
	t.assert_true(CampaignUiText.format_event(s, partial[0]) != "")
