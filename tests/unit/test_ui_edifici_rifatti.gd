extends RefCounted
## Icone degli edifici rifatte (ADR-060, tools/prepara_edifici.py): ogni icona che il gioco sceglie per un livello del
## file prod della XL, con qualunque religione del giocatore, ha la sua immagine in assets/rifatti. Usa l'installazione
## e la sua esportazione; senza, il test si salta.


func _setup(t: TestContext) -> BuildingProdLoader.BuildingTable:
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata in %s" % GameFiles.game_dir())
		return null
	var campaign := StartposLoader.load_file(GameFiles.startpos())
	var path := GameFiles.prod_file(campaign.building_prod_file)
	if not FileAccess.file_exists(path):
		t.skip("file prod degli edifici non trovato in %s" % GameFiles.game_dir())
		return null
	AssetLibrary.reset()
	BuildingArt.reset()
	if not AssetLibrary.is_available():
		t.skip("esportazione delle immagini non trovata")
		return null
	return BuildingProdLoader.load_file(path)


func _teardown() -> void:
	AssetLibrary.reset()
	BuildingArt.reset()


func test_ogni_icona_usata_e_rifatta(t: TestContext) -> void:
	var table := _setup(t)
	if table == null:
		return
	var missing := PackedStringArray()
	var checked := 0
	for b in table.families:
		for lv in b.levels:
			for religion in ["CATHOLIC", "ORTHODOX", "MUSLIM", "PAGAN"]:
				var path := BuildingArt.icon_path(lv.label, b.id, religion)
				if path == "":
					continue
				checked += 1
				if not AssetLibrary.is_remade(path):
					var line := "%s (%s, %s) -> %s" % [lv.label, b.id, religion, path]
					if not missing.has(line):
						missing.append(line)
	t.assert_true(checked > 300, "icone controllate: %d" % checked)
	t.assert_eq(missing.size(), 0, "icone dell'originale ancora in uso: %s" % ", ".join(missing.slice(0, 12)))
	_teardown()


func test_icona_rifatta_quattro_volte_l_originale(t: TestContext) -> void:
	var table := _setup(t)
	if table == null:
		return
	for label in ["Armourer", "Spearmaker", "Castle", "Merchant"]:
		var path := BuildingArt.icon_path(label, "", "CATHOLIC")
		t.assert_true(path != "", "percorso dell'icona di %s" % label)
		var tex := AssetLibrary.remade(path)
		t.assert_true(tex != null, "%s rifatta" % label)
		if tex != null:
			t.assert_eq(tex.get_size(), Vector2(272, 200), "%s: 4 volte 68x50" % label)
			t.assert_true(tex.get_image().has_mipmaps(), "%s: con le riduzioni intermedie" % label)
	_teardown()
