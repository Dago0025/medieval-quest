extends RefCounted
## Testi propri del remake (richiesta di Federico del 18/11/2026: non usare piu' nulla dell'originale): descrizioni e nomi
## delle unita' in italiano e in inglese per ogni unita' del prod, popoli ribelli, nessuna lettura dei file dell'originale.


func _units() -> Array:
	var units := UnitProdLoader.load_file(GameFiles.prod_file("MTW_XL_EARLY_UNIT_PROD11.TXT"))
	var ids: Array = []
	for u in units.units:
		ids.append(u.id)
	return ids


func test_descrizioni_in_italiano_e_inglese(t: TestContext) -> void:
	var it := ConfigFile.new()
	var en := ConfigFile.new()
	t.assert_eq(it.load("res://data/testi/it/descrizioni_unita.cfg"), OK)
	t.assert_eq(en.load("res://data/testi/en/descrizioni_unita.cfg"), OK)
	t.assert_eq(en.get_section_keys("descrizioni_unita"), it.get_section_keys("descrizioni_unita"), "stesse unita' nelle due lingue")
	var known := {}
	for k in it.get_section_keys("descrizioni_unita"):
		known[k.to_lower()] = true
	var mounts := ["KHORSE", "ARMHORSE", "LIHORSE", "CAMEL", "EHORSE"]   # righe delle cavalcature, non unita' arruolabili
	var missing: Array = []
	for id in _units():
		if mounts.has(str(id).to_upper()):
			continue
		if not known.has(str(id).to_lower()) and AurorUnits.text(str(id), "descrizione") == "":
			missing.append(id)
	t.assert_eq(missing, [], "unita' senza descrizione")


func test_nomi_inglesi_delle_unita(t: TestContext) -> void:
	var it := ConfigFile.new()
	var en := ConfigFile.new()
	t.assert_eq(it.load("res://data/nomi_unita.cfg"), OK)
	t.assert_eq(en.load("res://data/lingue/en/nomi_unita.cfg"), OK)
	for section in ["nomi", "singolari"]:
		for k in it.get_section_keys(section):
			t.assert_true(en.has_section_key(section, k), "nome inglese mancante: %s/%s" % [section, k])


func test_popoli_ribelli_dai_testi_propri(t: TestContext) -> void:
	ItalianTexts.reset()
	t.assert_true(CampaignUiText.rebel_people(0) != "", "primo popolo ribelle")
	t.assert_eq(CampaignUiText.rebel_people(-1), "")
	t.assert_eq(CampaignUiText.rebel_people(100000), "")


func test_nessun_testo_dall_originale(t: TestContext) -> void:
	for path in ["res://src/data/unit_texts.gd", "res://src/data/event_texts.gd", "res://src/data/italian_texts.gd", "res://src/map/campaign_ui_text.gd"]:
		var code := FileAccess.get_file_as_string(path)
		t.assert_false(code.contains("GameFiles.loc_file("), "%s legge ancora i Loc dell'originale" % path)
		t.assert_false(code.contains("GameFiles.path(FOLDER)"), "%s legge ancora _ITALIANO" % path)
