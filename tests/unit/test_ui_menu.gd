extends RefCounted
## Test della fase 8c: impostazioni dell'utente, scelte del menu (GameLaunch), riepiloghi e nomi dei salvataggi, fazioni
## giocabili. I pulsanti veri stanno in scenes/main_menu.gd e non si provano qui.

const W := preload("res://tests/unit/agent_world.gd")
const Menu := preload("res://scenes/main_menu.gd")


func test_impostazioni_dell_utente(t: TestContext) -> void:
	UserSettings.path = "user://test_impostazioni.cfg"
	DirAccess.remove_absolute(UserSettings.path)
	UserSettings.reset()
	t.assert_eq(UserSettings.difficulty(), "normale", "predefinita")
	t.assert_true(is_equal_approx(UserSettings.tilt(), 1.6))
	UserSettings.set_value("difficolta", "difficile")
	UserSettings.set_value("inclinazione", 9.0)
	t.assert_true(UserSettings.save())
	UserSettings.reset()
	t.assert_eq(UserSettings.difficulty(), "difficile", "riletta dal file")
	t.assert_true(is_equal_approx(UserSettings.tilt(), MapProjection.MAX_TILT), "inclinazione entro i limiti")
	UserSettings.set_value("difficolta", "impossibile")
	t.assert_eq(UserSettings.difficulty(), "normale", "valore sconosciuto: la predefinita")
	DirAccess.remove_absolute(UserSettings.path)
	UserSettings.path = UserSettings.PATH
	UserSettings.reset()


func test_scelte_del_menu(t: TestContext) -> void:
	GameLaunch.new_game("FN_ENGLISH", "facile", 42)
	t.assert_eq(GameLaunch.faction, "FN_ENGLISH")
	t.assert_eq(GameLaunch.load_save, "")
	GameLaunch.load_game("partita")
	t.assert_eq(GameLaunch.faction, "", "caricare azzera la fazione: vale quella salvata")
	t.assert_eq(GameLaunch.load_save, "partita")
	GameLaunch.reset()
	t.assert_eq(GameLaunch.seed_value, 0)


func test_nomi_e_riepiloghi_dei_salvataggi(t: TestContext) -> void:
	t.assert_eq(SaveGame.safe_name("Gli Auror, anno 1123!"), "Gli_Auror_anno_1123")
	t.assert_eq(SaveGame.safe_name("  Città d'oro  "), "Citta_d_oro")
	t.assert_eq(SaveGame.safe_name("???"), "", "nessun carattere valido")
	var s := W.world()
	s.faction(W.A).is_player = true
	s.year = 1123
	var r := SaveGame.save_file(s, "test_riepilogo")
	t.assert_true(bool(r["ok"]), str(r))
	var summary := SaveGame.summary("test_riepilogo")
	t.assert_eq(int(summary["anno"]), 1123)
	t.assert_eq(str(summary["fazione"]), W.A, "la fazione del giocatore viene dal salvataggio")
	t.assert_true(int(summary["modificato"]) > 0)
	var found := false
	for x in SaveGame.list_summaries():
		found = found or str(x["nome"]) == "test_riepilogo"
	t.assert_true(found, "compare nell'elenco")
	t.assert_true(SaveLoadPanel.row_text(summary).begins_with("test_riepilogo — "), SaveLoadPanel.row_text(summary))
	SaveGame.delete_file("test_riepilogo")
	t.assert_true(SaveGame.summary("test_riepilogo").is_empty(), "file eliminato")


func test_fazioni_giocabili(t: TestContext) -> void:
	var s := W.world()
	var ids: PackedStringArray = Menu.playable_factions(s.campaign)
	t.assert_false(ids.has("FN_REBEL"), "i ribelli non si giocano")
	t.assert_true(ids.size() >= 2, str(ids))
	t.assert_true(Menu.faction_summary(s.campaign, ids[0]).contains("Religione:"))
	if not GameFiles.is_available():
		t.skip("installazione non trovata")
		return
	var data := StartposLoader.load_file(GameFiles.startpos())
	FactionStyle.apply_overrides(data)
	var real: PackedStringArray = Menu.playable_factions(data)
	t.assert_eq(real[0], "FN_DANISH", "gli Auror per primi")
	t.assert_true(real.size() >= 20, "tutte le fazioni attive: %d" % real.size())


func test_musica_e_suoni(t: TestContext) -> void:
	t.assert_eq(GameAudio.map_music_key("MUSLIM"), "mappa_islamica")
	t.assert_eq(GameAudio.map_music_key("CATHOLIC"), "mappa_cristiana")
	t.assert_eq(GameAudio.map_music_key(""), "mappa_cristiana")
	var cfg := ConfigFile.new()
	t.assert_eq(cfg.load(GameAudio.TABLE), OK, "tabella dell'audio leggibile")
	for key in ["menu", "mappa_cristiana", "mappa_islamica", "vittoria_cristiana", "sconfitta_islamica"]:
		t.assert_true((cfg.get_value("musica", key, []) as Array).size() > 0, "playlist %s" % key)
	if not GameFiles.is_available():
		t.skip("installazione non trovata")
		return
	t.assert_true(GameAudio.find_file(GameAudio.MUSIC_DIR, "xl tension 1.wav") != "", "maiuscole indifferenti")
	for key in cfg.get_section_keys("musica"):
		for f in cfg.get_value("musica", key):
			t.assert_true(GameAudio.find_file(GameAudio.MUSIC_DIR, str(f)) != "", "%s: %s nei dati" % [key, f])
	for key in cfg.get_section_keys("suoni"):
		var v: Variant = cfg.get_value("suoni", key)
		for f in (v if v is Array else [v]):
			var found := false
			for d in GameAudio.SFX_DIRS:
				found = found or GameAudio.find_file(d, str(f)) != ""
			t.assert_true(found, "suono %s: %s nei dati" % [key, f])


func test_traduzioni_italiane(t: TestContext) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("eventi_titoli", "0", "Titolo tradotto")
	cfg.set_value("disastri", "floodregmes_xzy", "Inondazione in %s.")
	cfg.set_value("peste", "varianti", ["Morbo uno in %s.", "Morbo due in %s."])
	cfg.set_value("descrizioni_unita", "Spearmen", "Fanti con la lancia.")
	ItalianTexts.use_table(cfg)
	var texts := EventTexts.load_text('@["Historical_event_titles"]\n@{"Original"}\n@["Historical_event_text"]\n@{"Text"}\n@["floodregmes_xzy"] {"Flood in %s."}\n')
	t.assert_eq(texts.historical_title(0), "Original", "testi di prova: niente traduzioni")
	texts.italian = true
	t.assert_eq(texts.historical_title(0), "Titolo tradotto")
	t.assert_eq(texts.historical_text(0), "Text", "senza traduzione resta l'originale")
	t.assert_eq(texts.disaster_message(GameState.EV_FLOOD, "Roma"), "Inondazione in Roma.")
	t.assert_eq(texts.disaster_message(GameState.EV_PLAGUE, "Roma", 1), "Morbo due in Roma.")
	t.assert_eq(UnitTexts.description("Spearmen"), "Fanti con la lancia.")
	ItalianTexts.reset()
