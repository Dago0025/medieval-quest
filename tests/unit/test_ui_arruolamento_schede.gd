extends RefCounted
## Richieste di Federico del 18/11/2026: nella finestra di arruolamento tre schede (truppe, flotta, agenti) sotto «Ripeti la
## coda»; pedine dei ribelli con la base grigio chiaro, diverse da quelle degli Auror (bianco e nero).


func test_tre_schede_di_arruolamento(t: TestContext) -> void:
	var entries := [
		{"unit": "Spearmen", "agente": false, "nave": false},
		{"unit": "Cog", "agente": false, "nave": true},
		{"unit": "Spy", "agente": true, "nave": false},
		{"unit": "Knights", "agente": false, "nave": false},
	]
	var groups := CampaignUiQueues.recruit_groups(entries)
	t.assert_eq(groups.size(), 3)
	t.assert_eq(groups[0]["titolo"], "Truppe")
	t.assert_eq(groups[1]["titolo"], "Flotta")
	t.assert_eq(groups[2]["titolo"], "Agenti")
	t.assert_eq((groups[0]["voci"] as Array).size(), 2, "truppe nell'ordine ricevuto")
	t.assert_eq(str((groups[0]["voci"] as Array)[1]["unit"]), "Knights")
	t.assert_eq(str((groups[1]["voci"] as Array)[0]["unit"]), "Cog")
	t.assert_eq(str((groups[2]["voci"] as Array)[0]["unit"]), "Spy")


func test_ribelli_con_la_base_grigio_chiaro(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(GameFiles.startpos())
	FactionStyle.apply_overrides(campaign)
	var rebels := PieceArt.faction_colors(campaign, "FN_REBEL")
	var auror := PieceArt.faction_colors(campaign, "FN_DANISH")
	t.assert_true(rebels[1].v > 0.75 and rebels[1].s < 0.05, "base grigio chiaro: %s" % rebels[1])
	t.assert_true(absf(rebels[1].v - auror[1].v) > 0.5, "base ben diversa da quella nera degli Auror")
	t.assert_true(rebels[0].v < 0.7, "stendardo grigio, non bianco come gli Auror")
