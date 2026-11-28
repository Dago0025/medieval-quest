extends RefCounted
## Test delle illustrazioni della fase 8b (EventArt, data/ui/illustrazioni.cfg): ogni evento storico ha una tavola che non e'
## un segnaposto, i temi e il ripiego sono stabili, la fine partita sceglie l'immagine giusta (mai la sala danese per gli Auror)
## e ogni percorso della tabella esiste nell'esportazione. Le prove sulle immagini si saltano senza _ASSET_EXPORT.


func test_ogni_evento_storico_ha_una_tavola_vera(t: TestContext) -> void:
	EventArt.reset()
	var seen := {}
	for i in 142:   # 71 dell'originale e 71 aggiunti il 28/11/2026, con la tavola di ripiego
		var f := EventArt.historical_frame(i, "")
		t.assert_true(f >= 1 and f <= 160, "evento %d: tavola %d nell'intervallo" % [i, f])
		t.assert_false(EventArt.is_placeholder(f), "evento %d: la tavola %d non e' un segnaposto" % [i, f])
		seen[f] = true
	t.assert_true(seen.size() >= 35, "abbinamenti vari, non sempre la stessa tavola (%d diverse)" % seen.size())
	t.assert_eq(EventArt.historical_frame(37, ""), 77, "la polvere da sparo e' l'esplosione")
	t.assert_eq(EventArt.historical_frame(54, ""), 148, "il giudizio di Dio (la peste nera) sono i ratti")


## Eventi aggiunti il 28/11/2026: la vignetta propria assets/eventi/storici/<chiave>.png vince sulla tavola, se c'e'.
func test_vignetta_propria_degli_eventi_nuovi(t: TestContext) -> void:
	EventArt.reset()
	t.assert_eq(EventArt.historical_own_path(""), "", "senza chiave nessuna vignetta")
	t.assert_eq(EventArt.historical_own_path("evento_inventato"), "", "vignetta mancante")
	var rules := EventRules.load_file()
	var e := rules.historical(86)
	t.assert_true(e != null and e.key == "scisma_d_oriente", "l'evento 86 e' lo scisma d'Oriente")
	var w := {"indice": 86, "chiave": "scisma_d_oriente"}
	var own := EventArt.historical_own_path("scisma_d_oriente")
	if own == "":
		t.assert_eq(EventArt.historical_frame(86, "scisma_d_oriente"), 97, "senza vignetta la tavola di ripiego di [storici]")
	else:
		t.assert_eq((EventArt.window_texture(w) as Texture2D).resource_path, own, "la vignetta propria")


func test_temi_e_ripiego_stabili(t: TestContext) -> void:
	EventArt.reset()
	t.assert_eq(EventArt.theme_frame("cometa_di_halley"), 64)
	t.assert_true([148, 100].has(EventArt.theme_frame("peste_nera_1347")), "peste_nera vince su peste")
	t.assert_eq(EventArt.theme_frame("nulla_di_noto"), 0, "nessun tema")
	var a := EventArt.historical_frame(500, "evento_inventato")
	t.assert_true(a > 0 and not EventArt.is_placeholder(a), "indice sconosciuto: una tavola generica")
	t.assert_eq(EventArt.historical_frame(500, "evento_inventato"), a, "sempre la stessa per la stessa chiave")
	t.assert_true(EventArt.is_placeholder(5) and EventArt.is_placeholder(40), "le tavole col solo nome sono segnaposto")


func test_immagine_di_fine_partita(t: TestContext) -> void:
	EventArt.reset()
	var auror := EventArt.end_picture_path("FN_DANISH", "CATHOLIC", VictoryState.DOMINATION, true)
	t.assert_eq(auror, "campmap/GameEnd/Vikings/FN_07_WIN.BIF", "gli Auror: la sala degli stendardi bianchi")
	t.assert_false(auror.contains("DANISH"), "nessuna insegna danese")
	t.assert_eq(EventArt.end_picture_path("FN_EGYPTIAN", "MUSLIM", VictoryState.DEFEAT, false), "campmap/GameEnd/game_end_islam.BIF")
	t.assert_eq(EventArt.end_picture_path("FN_RUSSIAN", "ORTHODOX", VictoryState.CAMPAIGN_END, false), "campmap/GameEnd/game_end_eastfactions.BIF",
		"fine per l'anno senza vincere: la citta' in fiamme")
	var r := EventArt.end_ribbon()
	t.assert_true(r.size.x > 100.0 and r.position.y < 20.0, "il nastro e' in cima: %s" % r)


func test_le_immagini_della_tabella_esistono(t: TestContext) -> void:
	AssetLibrary.reset()
	EventArt.reset()
	if not GameFiles.is_available() or not AssetLibrary.is_available():
		t.skip("installazione o esportazione delle immagini non trovata")
		return
	t.assert_eq(AssetLibrary.frame_count("campmap/EPIC.BIF"), 160, "EPIC.BIF ha 160 tavole")
	t.assert_true(EventArt.historical_texture(0, "") != null, "la tavola del primo evento si carica")
	# dal 18/11/2026 restano solo le tavole usate da [storici], [temi] e [epic] generiche (tools/originale_necessari.txt)
	for section in ["storici", "temi"]:
		for key in cfg_frames(section):
			t.assert_true(EventArt.epic_texture(key) != null, "tavola %d usata da [%s]" % [key, section])
	var cfg := ConfigFile.new()
	cfg.load(EventArt.TABLE)
	for key in cfg.get_section_keys("fine"):
		var v: Variant = cfg.get_value("fine", key)
		if v is String:
			t.assert_true(AssetLibrary.has(str(v)), "%s: %s nell'esportazione" % [key, v])
	t.assert_true(AssetLibrary.has("campmap/GameEnd/FN_ENGLISH_WIN.BIF"), "le sale delle altre fazioni ci sono")
	t.assert_eq(EventArt.end_picture_path("FN_ENGLISH", "CATHOLIC", VictoryState.DOMINATION, true), "campmap/GameEnd/FN_ENGLISH_WIN.BIF")


## Numeri delle tavole citati in una sezione di illustrazioni.cfg.
func cfg_frames(section: String) -> Array:
	var cfg := ConfigFile.new()
	cfg.load(EventArt.TABLE)
	var out: Array = []
	for key in cfg.get_section_keys(section):
		var v: Variant = cfg.get_value(section, key)
		for n in (v if v is Array else [v]):
			if not out.has(int(n)):
				out.append(int(n))
	return out
