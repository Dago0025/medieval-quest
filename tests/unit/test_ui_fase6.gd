extends RefCounted
## Test della logica pura dell'interfaccia della fase 6 (eventi e vittoria): avanzamento del dominio nella barra, righe della
## classifica, schermata di fine partita (vittoria per dominio, sconfitta, fine della campagna), finestra dell'evento storico
## (titolo e testo da Events.txt o ripiego italiano, riga con l'effetto), testi italiani degli eventi della 6a e della 6b e la
## sezione «Eventi e storia» del resoconto di fine anno.
## Mondo di prova: tests/unit/papacy_world.gd (ALPHA, GAMMA e DELTA cattoliche, BETA musulmana, il Papato a ROMA, ribelli in
## RIBELLE: 9 province di terra; ALPHA ha NORD1-NORD3 ed e' il giocatore). Nomi delle regioni: Roma, Nord1, Nord2, Nord3, Est,
## Delta1, Sud1, Sud2, Ribelle; delle fazioni: Alpha, Beta, Gamma, Delta, Papist. Testi di prova: tests/fixtures/mini_events.txt
## (nessun testo originale). I testi si ripristinano alla fine di ogni test che li cambia.

const W := preload("res://tests/unit/papacy_world.gd")
const E := preload("res://tests/unit/event_world.gd")
const MINI_EVENTS := "res://tests/fixtures/mini_events.txt"


func _world() -> GameState:
	var s := W.world()
	s.faction(W.A).is_player = true
	s.rules.victory.domination_threshold = 0.6667   # i conti dei testi sono scritti sui due terzi (il predefinito e' 85%)
	return s


func _ev(kind: String, data: Dictionary) -> Dictionary:
	var e := {"tipo": kind, "anno": 1000}
	e.merge(data)
	return e


func _mini() -> EventTexts:
	return EventTexts.load_file(MINI_EVENTS)


## Testo di un evento con i testi di prova (`mini` vero) o senza nessun testo originale.
func _text(s: GameState, kind: String, data: Dictionary, mini: bool = true) -> String:
	CampaignUiEvents.set_texts(_mini() if mini else EventTexts.new())
	var line := CampaignUiText.format_event(s, _ev(kind, data))
	CampaignUiEvents.reset_texts()
	return line


func _no_raw_ids(t: TestContext, text: String) -> void:
	t.assert_false(text.contains("ID_"), text)
	t.assert_false(text.contains("FN_"), text)


# --- barra in alto: avanzamento del dominio ---------------------------------------------------------------------


func test_percentuali_in_italiano(t: TestContext) -> void:
	t.assert_eq(CampaignUiVictory.percent_text(0.6667), "66,7%")
	t.assert_eq(CampaignUiVictory.percent_text(1.0), "100,0%")
	t.assert_eq(CampaignUiVictory.percent_text(0.0), "0,0%")
	t.assert_eq(CampaignUiVictory.percent_text(0.3333), "33,3%")


func test_avanzamento_del_dominio_nella_barra(t: TestContext) -> void:
	var s := _world()
	var info := CampaignUiVictory.progress_info(s, W.A)
	t.assert_eq(info["testo"], "Province 3/6", "3 province controllate su 6 necessarie (due terzi di 9)")
	t.assert_false(bool(info["raggiunto"]))
	var tip := str(info["tooltip"])
	t.assert_true(tip.contains("servono 6 province di terra su 9"), tip)
	t.assert_true(tip.contains("soglia 66,7%"), tip)
	t.assert_true(tip.contains("ne controlli 3 (33,3%)"), tip)
	t.assert_true(tip.contains("Ti mancano 3 province"), tip)
	t.assert_true(tip.contains("G"), "rimanda alla classifica")
	t.assert_false(tip.contains("Vittoria per dominio nell'anno"), "nessuna vittoria ancora")


func test_avanzamento_con_la_soglia_raggiunta(t: TestContext) -> void:
	var s := _world()
	s.rules.victory.domination_threshold = 0.3
	var info := CampaignUiVictory.progress_info(s, W.A)
	t.assert_eq(info["testo"], "Province 3/3")
	t.assert_true(bool(info["raggiunto"]))
	t.assert_true(str(info["tooltip"]).contains("Soglia raggiunta."))
	s.victory.domination_year = 1005
	t.assert_true(str(CampaignUiVictory.progress_info(s, W.A)["tooltip"]).contains("Vittoria per dominio nell'anno 1005."))
	s.rules.victory.domination_threshold = 1.0
	t.assert_eq(CampaignUiVictory.progress_info(s, W.A)["testo"], "Province 3/9", "cento per cento: tutte")


# --- classifica ---------------------------------------------------------------------------------------------------


func test_righe_della_classifica(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiVictory.standings_headers(), PackedStringArray(["#", "Fazione", "Province", "Reddito", "Quota"]))
	t.assert_eq(CampaignUiVictory.standings_title(s), "Classifica · anno 1000 · dominio: 6 province su 9")
	s.faction(W.G).last_income = {"agricoltura": 120, "miniere": 30, "commercio": 50, "netto": 10}
	var rows := CampaignUiVictory.standings_rows(s)
	t.assert_eq(rows.size(), 5, "Alpha, Beta, Gamma, Delta e Papist; i ribelli no")
	t.assert_eq(rows[0]["celle"], PackedStringArray(["1", "Alpha", "3", "0", "33,3%"]))
	t.assert_true(bool(rows[0]["giocatore"]))
	t.assert_eq(rows[0]["fazione"], W.A)
	t.assert_eq(rows[1]["celle"], PackedStringArray(["2", "Beta", "2", "0", "22,2%"]))
	t.assert_false(bool(rows[1]["giocatore"]))
	t.assert_eq(rows[2]["celle"], PackedStringArray(["3", "Gamma", "1", "200", "11,1%"]), "a parita' di province il reddito lordo")
	for row in rows:
		for cell in (row["celle"] as PackedStringArray):
			_no_raw_ids(t, cell)


# --- schermata di fine partita -------------------------------------------------------------------------------------


func test_nessuna_schermata_a_partita_in_corso(t: TestContext) -> void:
	var s := _world()
	t.assert_false(CampaignUiVictory.has_end_screen(s))
	t.assert_eq(CampaignUiVictory.finished_line(s), "")
	t.assert_eq(CampaignUiVictory.game_over_hint(s), "La partita è finita (anno 1000).")


func test_schermata_della_vittoria_per_dominio(t: TestContext) -> void:
	var s := _world()
	s.victory.outcome = VictoryState.DOMINATION
	s.victory.year = 1042
	s.victory.domination_year = 1042
	t.assert_true(CampaignUiVictory.has_end_screen(s), "in attesa della scelta")
	var screen := CampaignUiVictory.end_screen(s, W.A)
	t.assert_eq(screen["esito"], VictoryState.DOMINATION)
	t.assert_eq(screen["titolo"], "Vittoria per dominio")
	var body := str(screen["testo"])
	t.assert_true(body.begins_with("Nel 1042, alla guida di Alpha, controlli 3 province su 9 (33,3%): il dominio è tuo."), body)
	t.assert_true(body.contains("continuare a giocare fino al 1700"), body)
	t.assert_true(bool(screen["puo_continuare"]), "il pulsante «Continua a giocare»")
	t.assert_eq((screen["righe"] as Array).size(), 5, "senza classifica salvata si usa quella attuale")
	t.assert_eq(screen["intestazioni"], CampaignUiVictory.standings_headers())
	t.assert_eq(CampaignUiVictory.game_over_hint(s), "Vittoria per dominio: scegli se continuare a giocare.")
	t.assert_eq(CampaignUiVictory.finished_line(s), "", "la vittoria ha gia' la sua riga negli eventi")
	# dopo la scelta
	t.assert_true(bool(GameCommands.continue_after_victory(s, W.A)["ok"]))
	t.assert_false(CampaignUiVictory.has_end_screen(s), "si gioca ancora")
	t.assert_false(bool(CampaignUiVictory.end_screen(s, W.A)["puo_continuare"]))


func test_schermata_della_sconfitta(t: TestContext) -> void:
	var s := _world()
	s.victory.outcome = VictoryState.DEFEAT
	s.victory.year = 1100
	var screen := CampaignUiVictory.end_screen(s, W.A)
	t.assert_eq(screen["titolo"], "Sconfitta")
	t.assert_eq(screen["testo"], "Nel 1100 la tua fazione (Alpha) è caduta: non restano né province né eserciti.\n\nLa campagna è finita.")
	t.assert_false(bool(screen["puo_continuare"]))
	t.assert_eq(CampaignUiVictory.game_over_hint(s), "La partita è finita: sconfitta nell'anno 1100.")
	t.assert_eq(CampaignUiVictory.finished_line(s), "")
	s.events.append(_ev(GameState.EV_DEFEAT, {"fazione": W.A, "motivo": "estinta"}))
	t.assert_true(str(CampaignUiVictory.end_screen(s, W.A)["testo"]).contains("la dinastia si è estinta"))


func test_schermata_della_fine_della_campagna(t: TestContext) -> void:
	var s := _world()
	s.year = 1700
	s.victory.outcome = VictoryState.CAMPAIGN_END
	s.victory.year = 1700
	s.victory.domination_year = 1650
	s.victory.set_ranking(VictoryProcessor.standings(s))
	var screen := CampaignUiVictory.end_screen(s, W.A)
	t.assert_eq(screen["esito"], VictoryState.CAMPAIGN_END)
	t.assert_eq(screen["titolo"], "Fine della campagna")
	t.assert_eq(screen["testo"], "Siamo nel 1700: la campagna è finita.\n\nAl primo posto: Alpha, con 3 province.\nLa tua fazione (Alpha) è in posizione 1 su 5.\nIl dominio era già tuo dal 1650.")
	t.assert_false(bool(screen["puo_continuare"]))
	t.assert_eq(CampaignUiVictory.finished_line(s), "La partita è finita: anno finale 1700 raggiunto.")
	# una partita finita solo per l'anno (salvataggio precedente alla fase 6b): schermata della fine della campagna
	var old := _world()
	old.year = 1700
	t.assert_true(CampaignUiVictory.has_end_screen(old))
	t.assert_eq(CampaignUiVictory.end_screen(old, W.A)["esito"], VictoryState.CAMPAIGN_END)
	t.assert_eq(CampaignUiVictory.finished_line(old), "La partita è finita: anno finale 1700 raggiunto.")
	# la classifica salvata vince su quella attuale
	old.victory.set_ranking([{"posizione": 1, "fazione": W.G, "province": 7, "reddito": 5, "netto": 1, "quota": 0.7778, "giocatore": false}])
	var rows: Array = CampaignUiVictory.end_screen(old, W.A)["righe"]
	t.assert_eq(rows.size(), 1)
	t.assert_eq((rows[0] as Dictionary)["celle"], PackedStringArray(["1", "Gamma", "7", "5", "77,8%"]))


func test_dal_dominio_al_resoconto_con_il_fine_anno_vero(t: TestContext) -> void:
	var s := _world()
	s.rules.victory.domination_threshold = 0.3
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]))
	t.assert_true(s.victory.awaits_choice())
	var lines := CampaignUiText.year_report(s, W.A, res)
	t.assert_true(lines.has("— Eventi e storia —"), str(lines))
	t.assert_true(lines.has("  Vittoria per dominio! Alpha controlla 3 province su 9 (servivano 3)."), str(lines))
	t.assert_true(CampaignUiVictory.has_end_screen(s))
	t.assert_true(bool(CampaignUiVictory.end_screen(s, W.A)["puo_continuare"]))


# --- finestra dell'evento storico ----------------------------------------------------------------------------------


func test_finestre_degli_eventi_storici(t: TestContext) -> void:
	var s := _world()
	s.events.append(_ev(GameState.EV_HISTORICAL, {"fazione": "", "indice": 1, "chiave": "prova_uno", "effetto": "zelo", "valore": 10,
		"regioni": [W.NORD1, W.NORD2], "fazioni": [], "provvisoria": true}))
	s.events.append(_ev(GameState.EV_BATTLE, {"fazione": W.A}))
	s.events.append(_ev(GameState.EV_HISTORICAL, {"fazione": "", "indice": 2, "chiave": "prova_due", "effetto": "nessuno", "valore": 0,
		"regioni": [], "fazioni": [], "provvisoria": false}))
	s.events.append(_ev(GameState.EV_HISTORICAL, {"fazione": "", "indice": 9, "chiave": "prova_9", "effetto": "tesoro", "valore": 200,
		"regioni": [], "fazioni": [W.A], "provvisoria": false}))
	var windows := CampaignUiEvents.historical_windows(s, _mini())
	t.assert_eq(windows.size(), 3, "una finestra per evento storico, nell'ordine del registro")
	t.assert_eq(windows[0]["titolo"], "Titolo uno")
	t.assert_eq(windows[0]["testo"], "Testo uno.")
	t.assert_eq(windows[0]["effetto"], "zelo +10: Nord1, Nord2 (effetto provvisorio)")
	t.assert_true(bool(windows[0]["originale"]))
	t.assert_true(bool(windows[0]["provvisoria"]))
	t.assert_eq(windows[0]["anno"], 1000)
	t.assert_eq(windows[1]["titolo"], "Titolo due")
	t.assert_eq(windows[1]["effetto"], "nessun effetto sul gioco")
	# indice senza testo: ripiego in italiano con la chiave
	t.assert_false(bool(windows[2]["originale"]))
	t.assert_eq(windows[2]["titolo"], "Evento storico: Prova 9")
	var fallback := str(windows[2]["testo"])
	t.assert_true(fallback.contains("Il testo originale non è disponibile"), fallback)
	t.assert_true(fallback.contains("«prova_9»"), fallback)
	t.assert_true(fallback.contains("1000"), fallback)
	t.assert_eq(windows[2]["effetto"], "tesoro +200 fiorini: Alpha")


func test_finestra_con_i_testi_dell_installazione_assenti(t: TestContext) -> void:
	var s := _world()
	s.events.append(_ev(GameState.EV_HISTORICAL, {"fazione": "", "indice": 4, "chiave": "", "effetto": "nessuno", "valore": 0,
		"regioni": [], "fazioni": [], "provvisoria": false}))
	CampaignUiEvents.set_texts(EventTexts.new())
	var windows := CampaignUiEvents.historical_windows(s)
	CampaignUiEvents.reset_texts()
	t.assert_eq(windows.size(), 1)
	t.assert_false(bool(windows[0]["originale"]))
	t.assert_eq(windows[0]["titolo"], "Evento storico n. 4", "senza chiave: il numero")
	t.assert_true(str(windows[0]["testo"]).contains("n. 4"), str(windows[0]["testo"]))
	# senza eventi storici nel registro: nessuna finestra
	t.assert_eq(CampaignUiEvents.historical_windows(_world(), _mini()).size(), 0)


func test_righe_degli_effetti(t: TestContext) -> void:
	var s := _world()
	var cases := [
		[{"effetto": "merci", "regioni": [W.EST], "valore": 0}, "nuove merci per il commercio: Est"],
		[{"effetto": "merci", "regioni": [], "valore": 0}, "nuove merci per il commercio: nessuna provincia coinvolta"],
		[{"effetto": "lealta", "valore": -5, "fazioni": [W.A, W.G]}, "lealtà dei generali e dei principi -5: Alpha, Gamma"],
		[{"effetto": "lealta", "valore": 2, "fazioni": []}, "lealtà dei generali e dei principi +2: nessuna fazione coinvolta"],
		[{"effetto": "zelo", "valore": 20, "regioni": [W.NORD1]}, "zelo +20: Nord1"],
		[{"effetto": "eretici", "valore": 10, "regioni": [W.NORD1]}, "eretici +10% in Nord1"],
		[{"effetto": "pieta_capo", "valore": 1, "fazioni": [W.A]}, "pietà del capo +1: Alpha"],
		[{"effetto": "tesoro", "valore": -300, "fazioni": [W.G]}, "tesoro -300 fiorini: Gamma"],
		[{"effetto": "nessuno"}, "nessun effetto sul gioco"],
		[{}, "nessun effetto sul gioco"],
		[{"effetto": "zelo", "valore": 5, "regioni": [W.NORD1, W.NORD2, W.NORD3, W.EST, W.DELTA1, W.SUD1, W.SUD2]}, "zelo +5: Nord1, Nord2, Nord3, Est, Delta1 e altre 2"],
	]
	for item in cases:
		var data: Dictionary = item[0]
		t.assert_eq(CampaignUiEvents.effect_line(s, data), str(item[1]))


# --- testi degli eventi della 6a e della 6b -----------------------------------------------------------------------


func test_testi_dei_disastri_con_il_messaggio_originale(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(_text(s, GameState.EV_FLOOD, {"fazione": W.A, "regione": W.NORD1, "provincia": W.NORD1, "proprietario": W.A}),
		"Inondazione a Nord1 (Alpha): il raccolto dell'anno è dimezzato. «Prova di inondazione in Nord1.»")
	t.assert_eq(_text(s, GameState.EV_FAMINE, {"fazione": W.A, "regione": W.NORD1, "provincia": W.NORD1, "proprietario": W.A, "lealta_persa": 10}),
		"Carestia a Nord1 (Alpha): nessun raccolto quest'anno e lealtà -10. «Prova di carestia in Nord1.»")
	t.assert_eq(_text(s, GameState.EV_FAMINE, {"fazione": W.A, "regione": W.NORD1, "provincia": W.NORD1, "proprietario": W.A, "lealta_persa": 0}, false),
		"Carestia a Nord1 (Alpha): nessun raccolto quest'anno.", "senza il file nessun messaggio originale")
	t.assert_eq(_text(s, GameState.EV_QUAKE, {"fazione": W.A, "regione": W.NORD1, "provincia": W.NORD1, "proprietario": W.A, "edificio": "CHURCH", "livello": 1}),
		"Terremoto a Nord1 (Alpha): Church scende al livello 1. «Prova di terremoto in Nord1.»")
	t.assert_eq(_text(s, GameState.EV_QUAKE, {"fazione": W.A, "regione": W.NORD1, "provincia": W.NORD1, "proprietario": W.A, "edificio": "CHURCH", "livello": 0}, false),
		"Terremoto a Nord1 (Alpha): Church è distrutto.")
	t.assert_eq(_text(s, GameState.EV_QUAKE, {"fazione": W.A, "regione": W.NORD1, "provincia": W.NORD1, "proprietario": W.A, "edificio": "", "livello": 0}, false),
		"Terremoto a Nord1 (Alpha): nessun edificio colpito.")
	t.assert_eq(_text(s, GameState.EV_STORM, {"fazione": W.A, "regione": W.NORD1, "esercito": 7, "uomini": 60, "pile": 1}),
		"Tempesta in Nord1: la flotta 7 di Alpha perde una pila (60 uomini). «Prova di tempesta in Nord1.»")


func test_testi_della_peste(t: TestContext) -> void:
	var s := _world()
	var plague := {"fazione": W.G, "regione": W.EST, "provincia": W.EST, "proprietario": W.G, "uomini": 40, "eserciti": 2, "origine": W.NORD1, "peste_nera": false}
	# la malattia dipende dall'anno (1000 mod 3 = 1: la seconda)
	t.assert_eq(_text(s, GameState.EV_PLAGUE, plague),
		"Peste a Est (Gamma): 40 uomini morti in 2 eserciti e guarnigioni, contagio da Nord1. «Seconda malattia in Est.»")
	plague["peste_nera"] = true
	plague["origine"] = ""
	plague["eserciti"] = 0
	t.assert_eq(_text(s, GameState.EV_PLAGUE, plague),
		"Peste Nera a Est (Gamma): 40 uomini morti. «Prova di Peste Nera ovunque, anche in Est.»")
	t.assert_eq(_text(s, GameState.EV_BLACK_DEATH, {"fazione": "", "regione": W.NORD1, "regioni": [W.NORD1], "anno_inizio": 1000}),
		"La Peste Nera comincia a Nord1. «Prova di Peste Nera ovunque, anche in Nord1.»")
	t.assert_eq(_text(s, GameState.EV_BLACK_DEATH, {"fazione": "", "regione": W.NORD1, "regioni": [W.NORD1], "anno_inizio": 1000}, false),
		"La Peste Nera comincia a Nord1.")


func test_testi_dell_orda_d_oro(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(_text(s, GameState.EV_HORDE_ARRIVES, {"fazione": W.G, "regione": W.EST, "provincia": W.EST, "eserciti": [4, 5], "pile": 8, "uomini": 4000}),
		"L'Orda d'Oro arriva a Est con 8 pile (4000 uomini).")
	t.assert_eq(_text(s, GameState.EV_HORDE_GONE, {"fazione": W.G, "motivo": "senza_conquiste", "province": [W.EST, W.NORD1], "eserciti": [1, 2, 3], "uomini": 900}),
		"L'Orda d'Oro si scioglie dopo anni senza conquiste: 2 province passano ai ribelli, 3 eserciti sciolti (900 uomini).")
	t.assert_eq(_text(s, GameState.EV_HORDE_GONE, {"fazione": W.G, "motivo": "distrutta", "province": [], "eserciti": [], "uomini": 0}),
		"L'Orda d'Oro è distrutta: 0 province passano ai ribelli.")


func test_testi_della_vittoria_della_sconfitta_e_della_fine_della_campagna(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(_text(s, GameState.EV_VICTORY, {"fazione": W.A, "province": 6, "necessarie": 6, "totale": 9, "quota": 0.6667, "soglia": 0.6667}),
		"Vittoria per dominio! Alpha controlla 6 province su 9 (servivano 6).")
	t.assert_eq(_text(s, GameState.EV_DEFEAT, {"fazione": W.A, "motivo": "estinta"}), "Sconfitta: Alpha è caduta, la dinastia si è estinta.")
	t.assert_eq(_text(s, GameState.EV_DEFEAT, {"fazione": W.A, "motivo": "senza_province"}), "Sconfitta: Alpha è caduta, non restano né province né eserciti.")
	var ranking := [{"posizione": 1, "fazione": W.G, "province": 12, "reddito": 1, "netto": 1, "quota": 0.1667, "giocatore": false}]
	t.assert_eq(_text(s, GameState.EV_CAMPAIGN_END, {"fazione": W.G, "vincitore": W.G, "giocatore": W.A, "posizione_giocatore": 2, "classifica": ranking}),
		"Fine della campagna (anno 1000). Prima in classifica: Gamma con 12 province. Il giocatore è 2º.")
	t.assert_eq(_text(s, GameState.EV_CAMPAIGN_END, {"fazione": "", "vincitore": "", "giocatore": "", "posizione_giocatore": 0, "classifica": [], "testo": "Fine."}),
		"Fine.", "senza vincitore ripiega sul testo della simulazione")


func test_testo_di_ripiego_senza_i_campi_essenziali(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(_text(s, GameState.EV_FLOOD, {"testo": "Inondazione da qualche parte."}), "Inondazione da qualche parte.")
	t.assert_eq(_text(s, GameState.EV_VICTORY, {"testo": "Vittoria."}), "Vittoria.")
	t.assert_eq(_text(s, GameState.EV_HORDE_ARRIVES, {"testo": "Arriva l'Orda."}), "Arriva l'Orda.")
	t.assert_eq(CampaignUiEvents.format_event(s, "tipo_inesistente", {}), "", "non e' un evento della fase 6")
	t.assert_eq(CampaignUiEvents.format_event(s, GameState.EV_BATTLE, {}), "")


func test_il_testo_dell_evento_storico_nel_resoconto(t: TestContext) -> void:
	var s := _world()
	var data := {"fazione": "", "indice": 1, "chiave": "prova_uno", "effetto": "zelo", "valore": 10, "regioni": [W.NORD1], "fazioni": [], "provvisoria": false}
	t.assert_eq(_text(s, GameState.EV_HISTORICAL, data), "Evento storico «Titolo uno»: zelo +10: Nord1.")
	t.assert_eq(_text(s, GameState.EV_HISTORICAL, data, false), "Evento storico «Prova Uno»: zelo +10: Nord1.", "senza testi: la chiave")


# --- sezione «Eventi e storia» del resoconto ----------------------------------------------------------------------


func test_sezione_della_fase_6(t: TestContext) -> void:
	var sections := CampaignUiText.phase6_sections()
	t.assert_eq(sections.size(), 1)
	t.assert_eq(sections[0]["titolo"], "Eventi e storia")
	var kinds: PackedStringArray = sections[0]["tipi"]
	for kind in [GameState.EV_HISTORICAL, GameState.EV_AMERICAS_CONTACT, GameState.EV_FLOOD, GameState.EV_FAMINE, GameState.EV_QUAKE,
			GameState.EV_STORM, GameState.EV_PLAGUE, GameState.EV_BLACK_DEATH, GameState.EV_HORDE_ARRIVES, GameState.EV_HORDE_GONE,
			GameState.EV_VICTORY, GameState.EV_DEFEAT, GameState.EV_CAMPAIGN_END]:
		t.assert_true(kinds.has(kind), "nel resoconto: %s" % kind)
	t.assert_eq(kinds.size(), 13)
	var every := CampaignUiText.all_report_sections()
	t.assert_eq(every[every.size() - 1]["titolo"], "Eventi e storia", "in fondo, dopo le sezioni della fase 5")
	var always := CampaignUiText.always_reported_kinds()
	for kind in [GameState.EV_HISTORICAL, GameState.EV_BLACK_DEATH, GameState.EV_HORDE_ARRIVES, GameState.EV_HORDE_GONE,
			GameState.EV_VICTORY, GameState.EV_DEFEAT, GameState.EV_CAMPAIGN_END]:
		t.assert_true(always.has(kind), "riguarda tutti: %s" % kind)
	t.assert_false(always.has(GameState.EV_FLOOD), "un disastro altrui non riguarda il giocatore")


func test_resoconto_con_eventi_e_storia(t: TestContext) -> void:
	var s := _world()
	s.events.append(_ev(GameState.EV_HISTORICAL, {"fazione": "", "indice": 1, "chiave": "prova_uno", "effetto": "zelo", "valore": 10, "regioni": [W.NORD1], "fazioni": [], "provvisoria": false}))
	s.events.append(_ev(GameState.EV_FLOOD, {"fazione": W.A, "regione": W.NORD2, "provincia": W.NORD2, "proprietario": W.A}))
	# l'inondazione e la tempesta di Gamma non riguardano Alpha
	s.events.append(_ev(GameState.EV_FLOOD, {"fazione": W.G, "regione": W.EST, "provincia": W.EST, "proprietario": W.G}))
	s.events.append(_ev(GameState.EV_STORM, {"fazione": W.G, "regione": W.EST, "esercito": 3, "uomini": 50, "pile": 1}))
	s.events.append(_ev(GameState.EV_HORDE_ARRIVES, {"fazione": W.D, "regione": W.DELTA1, "provincia": W.DELTA1, "eserciti": [8], "pile": 8, "uomini": 4000}))
	CampaignUiEvents.set_texts(_mini())
	var lines := CampaignUiText.year_report(s, W.A, {"ok": true, "avvisi": [], "errori": []})
	CampaignUiEvents.reset_texts()
	t.assert_eq(lines, PackedStringArray([
		"— Eventi e storia —",
		"  Evento storico «Titolo uno»: zelo +10: Nord1.",
		"  Inondazione a Nord2 (Alpha): il raccolto dell'anno è dimezzato. «Prova di inondazione in Nord2.»",
		"  L'Orda d'Oro arriva a Delta1 con 8 pile (4000 uomini).",
	]))
	for line in lines:
		_no_raw_ids(t, line)


func test_eventi_veri_della_fase_6a_hanno_testo_leggibile(t: TestContext) -> void:
	# disastri veri, evento storico e Orda d'Oro del fine anno degli eventi, nel mondo con i dati dei disastri
	var s := E.world(5)
	var ev := s.rules.events
	ev.flood_chance = 1.0
	ev.famine_chance = 1.0
	ev.quake_chance = 1.0
	ev.plague_chance = 1.0
	E.add_history(s, 1, 1000, 1000, EventRules.EFFECT_ZEAL, 10, "", ["ID_NORD1"])
	E.add_history(s, 2, 1000, 1000, EventRules.EFFECT_TREASURY, 100, "FN_ALPHA")
	var all_events: Array[Dictionary] = []
	E.run_year(s)
	all_events.append_array(s.events)
	ev.flood_chance = 0.0
	ev.famine_chance = 0.0
	ev.quake_chance = 0.0
	ev.plague_chance = 0.0
	s.year = ev.horde_year
	E.run_year(s)
	all_events.append_array(s.events)
	CampaignUiEvents.set_texts(EventTexts.new())
	var seen := PackedStringArray()
	var wanted := PackedStringArray()
	for sec in CampaignUiText.phase6_sections():
		wanted.append_array(sec["tipi"])
	for e in all_events:
		var kind := str(e["tipo"])
		if not wanted.has(kind):
			continue
		seen.append(kind)
		var text := CampaignUiText.format_event(s, e)
		t.assert_true(text != "" and text != kind, "riga grezza per %s" % kind)
		_no_raw_ids(t, text)
	CampaignUiEvents.reset_texts()
	for kind in [GameState.EV_HISTORICAL, GameState.EV_FLOOD, GameState.EV_FAMINE, GameState.EV_QUAKE, GameState.EV_PLAGUE, GameState.EV_HORDE_ARRIVES]:
		t.assert_true(seen.has(kind), "evento '%s' nel registro di prova" % kind)
