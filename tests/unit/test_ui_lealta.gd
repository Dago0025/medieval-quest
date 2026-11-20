extends RefCounted
## Lealtà delle province resa chiara (richiesta di Federico del 16/11/2026: «va reso più chiaro il valore che indica la
## possibilità di ribellione»): stato a parole, rischio di rivolta a fine anno uguale al sorteggio, tendenza, termini.
## Mondo di prova: agent_world.gd (ALTA di ALPHA).

const W := preload("res://tests/unit/agent_world.gd")


func _province(loyalty: int, target: int) -> Array:
	var s := W.world()
	var p := s.province(W.ALTA)
	p.loyalty = loyalty
	p.last_loyalty = {"base": 100, "tassa": target - 100, "obiettivo": target}
	return [s, p]


func test_il_rischio_e_quello_del_sorteggio_con_la_lealta_di_fine_anno(t: TestContext) -> void:
	var sp := _province(80, 60)
	var s: GameState = sp[0]
	var p: ProvinceState = sp[1]
	var st := CampaignUiText.loyalty_status(s, p)
	t.assert_eq(st["fine_anno"], ProvinceProcessor.approach(80, 60, s.rules.province.drift), "lealtà a fine anno")
	t.assert_eq(st["rischio"], ProvinceProcessor.revolt_risk(s, p, int(st["fine_anno"])), "stesso calcolo del fine anno")
	t.assert_true(str(st["tendenza"]).begins_with("in calo verso 60"), str(st["tendenza"]))
	t.assert_true(st["stato"] == CampaignUiText.LOYALTY_RESTLESS or st["stato"] == CampaignUiText.LOYALTY_REVOLT, str(st))
	t.assert_true(str(st["spiegazione"]).contains("100"), "la soglia spiegata")
	t.assert_eq(st["termini"][0], ["Base", 100])


func test_rischio_in_percentuale_e_stati(t: TestContext) -> void:
	var sp := _province(40, 30)
	var s: GameState = sp[0]
	var p: ProvinceState = sp[1]
	s.rules.province.revolt_k = 0.01
	var st := CampaignUiText.loyalty_status(s, p)
	if ProvinceProcessor.can_rebel(s, p):
		t.assert_eq(st["stato"], CampaignUiText.LOYALTY_REVOLT, "38 a fine anno: 50% (limite), rivolta probabile")
		t.assert_true(str(st["rischio_testo"]).ends_with("50%"), str(st["rischio_testo"]))
		t.assert_true(CampaignUiText.loyalty_summary(s, p).contains("rivolta a fine anno 50%"))
	var calm := CampaignUiText.loyalty_status(s, _with(p, 120, 125))
	t.assert_eq(calm["stato"], CampaignUiText.LOYALTY_CALM)
	t.assert_eq(calm["rischio_testo"], "Rischio di rivolta a fine anno: nessuno")
	var loyal := CampaignUiText.loyalty_status(s, _with(p, 170, 170))
	t.assert_eq(loyal["stato"], CampaignUiText.LOYALTY_LOYAL)
	t.assert_eq(loyal["tendenza"], "stabile")
	t.assert_eq(CampaignUiText.loyalty_summary(s, p), "Lealtà: Fedele (170 su 200)")


func _with(p: ProvinceState, loyalty: int, target: int) -> ProvinceState:
	p.loyalty = loyalty
	p.last_loyalty = {"base": 100, "obiettivo": target}
	return p


func test_percentuali(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.percent_text(0.15), "15%")
	t.assert_eq(CampaignUiText.percent_text(0.025), "2,5%")


## Il numero «Ribelli: 29» della scheda era l'indice del popolo dei ribelli (SetRegionRebels), non una probabilita'.
func test_il_popolo_dei_ribelli_al_posto_del_numero(t: TestContext) -> void:
	if not GameFiles.is_available():
		t.skip("installazione di MTW non trovata")
		return
	t.assert_eq(CampaignUiText.rebel_people(0), "gli Alani", "primo popolo dei testi italiani")
	t.assert_eq(CampaignUiText.rebel_people(-1), "")
	t.assert_eq(CampaignUiText.rebel_people(5000), "")
