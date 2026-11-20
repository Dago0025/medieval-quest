extends RefCounted
## Pergamena della provincia a schede e tabella a due colonne (ADR-029): la parte pura, in CampaignUiText.
## La finestra vera sta in scenes/campaign_map.gd e non si prova qui.


func test_schede_di_una_provincia_propria_e_di_una_altrui(t: TestContext) -> void:
	var own := CampaignUiText.province_tabs(true)
	t.assert_eq(own.size(), 4)
	t.assert_true(own.has(CampaignUiText.TAB_GOVERNMENT), "nella propria provincia c'e' il governo")
	var other := CampaignUiText.province_tabs(false)
	t.assert_eq(other.size(), 3)
	t.assert_false(other.has(CampaignUiText.TAB_GOVERNMENT), "governatore e lealta' altrui non si vedono")
	t.assert_eq(own[0], CampaignUiText.TAB_PROVINCE, "la prima scheda e' sempre Provincia")
	t.assert_eq(other[0], CampaignUiText.TAB_PROVINCE)


func test_nomi_delle_schede(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.province_tab_name(CampaignUiText.TAB_PROVINCE), "Provincia")
	t.assert_eq(CampaignUiText.province_tab_name(CampaignUiText.TAB_CASTLE), "Castello")
	t.assert_eq(CampaignUiText.province_tab_name(CampaignUiText.TAB_GOVERNMENT), "Governo")
	t.assert_eq(CampaignUiText.province_tab_name(CampaignUiText.TAB_BUILDINGS), "Edifici")


func test_coppie_e_righe_larghe_della_tabella(t: TestContext) -> void:
	var text := "Proprietario: Auror\nSotto assedio\nRendita base: 403\nPorto: sì\nConfinanti: Scania, Sassonia, Skagerrak, Mare del Nord"
	var facts := CampaignUiText.fact_rows(text)
	var pairs: Array = facts["coppie"]
	t.assert_eq(pairs.size(), 3, "tre dati brevi in tabella")
	t.assert_eq(pairs[0], ["Proprietario", "Auror"])
	t.assert_eq(pairs[1], ["Rendita base", "403"], "nell'ordine del testo")
	var wide: PackedStringArray = facts["righe"]
	t.assert_eq(wide.size(), 2)
	t.assert_eq(wide[0], "Sotto assedio", "le righe senza due punti restano intere")
	t.assert_true(wide[1].begins_with("Confinanti: "), "i valori lunghi restano a tutta larghezza")


func test_testo_vuoto(t: TestContext) -> void:
	var facts := CampaignUiText.fact_rows("")
	t.assert_true((facts["coppie"] as Array).is_empty())
	t.assert_eq((facts["righe"] as PackedStringArray).size(), 0)
