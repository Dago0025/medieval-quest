extends RefCounted
## Fase 6b: vittoria per dominio, sconfitta e fine della campagna (VictoryRules, VictoryState, VictoryProcessor,
## GameCommands.continue_after_victory) e salvataggi di versione 9, su un mondo di prova scritto apposta (agent_world.gd, in
## sola lettura): ALPHA (ALTA, BASSA), BETA (MEZZA), GAMMA (ORTO), ribelli (SOLA): 5 province di terra. ALPHA e' il giocatore.
## La prova sui dati reali sta in test_sim_victory_reale.gd.

const W := preload("res://tests/unit/agent_world.gd")


## Mondo quieto con ALPHA giocatore e soglia di dominio 0.4 (su 5 province: 2 bastano; ALPHA ne ha 2).
func _world(threshold: float = 0.4) -> GameState:
	var s := W.world()
	s.faction(W.A).is_player = true
	s.rules.victory.domination_threshold = threshold
	return s


## Porta la partita all'anno indicato spostando anche le nascite: senza, a fine anno i personaggi nati intorno al 1000
## morirebbero tutti di vecchiaia e la fazione del giocatore si estinguerebbe (sconfitta invece della fine campagna).
func _jump_to(s: GameState, year: int) -> void:
	var delta := year - s.year
	for c in s.characters:
		c.birth_year += delta
	s.year = year


func _events(s: GameState, kind: String) -> Array[Dictionary]:
	return W.events_of(s, kind)


func _lose_everything(s: GameState, faction_id: String) -> void:
	for p in s.provinces_of(faction_id):
		p.owner = GameState.REBEL
	for a in s.armies_of(faction_id):
		s.remove_army(a)


# --- regole -----------------------------------------------------------------------------------------------------


func test_i_valori_predefiniti_sono_uguali_al_file(t: TestContext) -> void:
	var from_file := VictoryRules.load_file()
	t.assert_eq(from_file.errors, PackedStringArray(), "vittoria.cfg si legge senza errori")
	t.assert_eq(from_file.to_dict(), VictoryRules.new().to_dict(), "vittoria.cfg = valori predefiniti del codice")
	t.assert_eq(VictoryRules.new().domination_threshold, 0.85, "scelta di Federico: 85%")
	var missing := VictoryRules.load_file("res://data/regole/non_esiste.cfg")
	t.assert_eq(missing.errors.size(), 1, "file mancante: un errore")
	t.assert_eq(missing.to_dict(), VictoryRules.new().to_dict(), "file mancante: valore predefinito")
	var rules := Rules.load_file()
	t.assert_eq(rules.errors, PackedStringArray(), "tutti i file delle regole senza errori")
	t.assert_eq(rules.victory.to_dict(), VictoryRules.new().to_dict(), "Rules legge vittoria.cfg")
	t.assert_eq(rules.to_dict(), Rules.new().to_dict(), "Rules.to_dict comprende la vittoria")
	t.assert_true(Rules.new().to_dict().has("victory"))


func test_province_necessarie(t: TestContext) -> void:
	var r := VictoryRules.new()
	t.assert_eq(r.provinces_needed(107), 91, "85% (predefinito) delle 107 province: 90,95 per eccesso")
	r.domination_threshold = 0.6667
	t.assert_eq(r.provinces_needed(72), 48, "due terzi di 72: 48, non 49")
	t.assert_eq(r.provinces_needed(9), 6)
	t.assert_eq(r.provinces_needed(0), 0, "nessuna provincia, nessun dominio")
	r.domination_threshold = 0.6
	t.assert_eq(r.provinces_needed(72), 44, "60%: 43,2 per eccesso")
	r.domination_threshold = 1.0
	t.assert_eq(r.provinces_needed(72), 72, "100%: tutte")
	r.domination_threshold = 0.01
	t.assert_eq(r.provinces_needed(5), 1, "almeno una")
	t.assert_eq(r.provinces_needed(1), 1)


func test_soglia_fuori_scala(t: TestContext) -> void:
	var low := VictoryRules.new()
	low.domination_threshold = 0.0
	low._check_consistency()
	t.assert_eq(low.errors.size(), 1)
	t.assert_eq(low.domination_threshold, 0.85, "torna al predefinito")
	var high := VictoryRules.new()
	high.domination_threshold = 1.5
	high._check_consistency()
	t.assert_eq(high.errors.size(), 1)
	t.assert_eq(high.domination_threshold, 0.85)


# --- avanzamento e classifica -----------------------------------------------------------------------------------


func test_avanzamento_verso_il_dominio(t: TestContext) -> void:
	var s := _world()
	var p := VictoryProcessor.domination_progress(s, W.A)
	t.assert_eq(p["province"], 2)
	t.assert_eq(p["necessarie"], 2)
	t.assert_eq(p["totale"], 5)
	t.assert_eq(p["quota"], 0.4)
	t.assert_eq(p["soglia"], 0.4)
	t.assert_true(bool(p["raggiunto"]))
	var q := VictoryProcessor.domination_progress(s, W.B)
	t.assert_eq(q["province"], 1)
	t.assert_false(bool(q["raggiunto"]))
	t.assert_eq(q["quota"], 0.2)
	var strict := _world(0.6667)
	t.assert_eq(VictoryProcessor.domination_progress(strict, W.A)["necessarie"], 4, "due terzi di 5: 3,33 per eccesso")
	t.assert_false(bool(VictoryProcessor.domination_progress(strict, W.A)["raggiunto"]))


func test_classifica_per_province_poi_reddito(t: TestContext) -> void:
	var s := _world()
	s.faction(W.B).last_income = {"agricoltura": 100, "miniere": 0, "commercio": 20, "netto": 50}
	s.faction(W.G).last_income = {"agricoltura": 300, "miniere": 10, "commercio": 0, "netto": -5}
	s.faction(W.A).last_income = {"agricoltura": 1, "miniere": 0, "commercio": 0, "netto": 1}
	var rows := VictoryProcessor.standings(s)
	t.assert_eq(rows.size(), 3, "senza i ribelli")
	t.assert_eq(rows[0]["fazione"], W.A, "piu' province")
	t.assert_eq(rows[0]["posizione"], 1)
	t.assert_eq(rows[0]["province"], 2)
	t.assert_true(bool(rows[0]["giocatore"]))
	t.assert_eq(rows[1]["fazione"], W.G, "a parita' di province, reddito lordo maggiore")
	t.assert_eq(rows[1]["reddito"], 310)
	t.assert_eq(rows[1]["netto"], -5)
	t.assert_eq(rows[2]["fazione"], W.B)
	t.assert_eq(rows[2]["reddito"], 120)
	t.assert_eq(rows[2]["posizione"], 3)
	t.assert_eq(rows[1]["quota"], 0.2)
	t.assert_false(rows[0].has("_ordine"), "nessun campo interno")


func test_classifica_a_parita_di_tutto_segue_l_ordine_delle_fazioni(t: TestContext) -> void:
	var s := _world()
	var rows := VictoryProcessor.standings(s)
	t.assert_eq(rows[1]["fazione"], W.B)
	t.assert_eq(rows[2]["fazione"], W.G)


func test_classifica_senza_fazioni_morte_e_con_il_giocatore_senza_province(t: TestContext) -> void:
	var s := _world()
	s.faction(W.G).alive = false
	_lose_everything(s, W.A)
	var rows := VictoryProcessor.standings(s)
	var ids: Array = []
	for r in rows:
		ids.append(str(r["fazione"]))
	t.assert_eq(ids, [W.B, W.A], "GAMMA morta non c'e', il giocatore resta anche senza province")
	t.assert_eq(rows[1]["province"], 0)


# --- sconfitta --------------------------------------------------------------------------------------------------


func test_motivo_della_sconfitta(t: TestContext) -> void:
	var s := _world()
	var f := s.faction(W.A)
	t.assert_eq(VictoryProcessor.defeat_reason(s, f), "", "ha province ed eserciti")
	_lose_everything(s, W.A)
	t.assert_eq(VictoryProcessor.defeat_reason(s, f), "senza_province")
	f.alive = false
	t.assert_eq(VictoryProcessor.defeat_reason(s, f), "estinta")
	var s2 := _world()
	for p in s2.provinces_of(W.A):
		p.owner = GameState.REBEL
	t.assert_eq(VictoryProcessor.defeat_reason(s2, s2.faction(W.A)), "", "senza province ma con eserciti non e' persa")


func test_sconfitta_chiude_la_partita(t: TestContext) -> void:
	var s := _world()
	_lose_everything(s, W.A)
	VictoryProcessor.check(s)
	var defeats := _events(s, GameState.EV_DEFEAT)
	t.assert_eq(defeats.size(), 1)
	t.assert_eq(defeats[0]["fazione"], W.A)
	t.assert_eq(defeats[0]["motivo"], "senza_province")
	t.assert_eq(s.victory.outcome, VictoryState.DEFEAT)
	t.assert_eq(s.victory.year, 1000)
	t.assert_true(s.victory.is_final())
	t.assert_true(s.is_game_over())
	t.assert_false(s.is_finished(), "l'anno finale non e' raggiunto")
	t.assert_eq(s.victory.ranking.size(), 3, "la classifica al momento della sconfitta")
	VictoryProcessor.check(s)
	t.assert_eq(_events(s, GameState.EV_DEFEAT).size(), 1, "una volta sola")
	var year := s.year
	var again := TurnProcessor.end_year(s)
	t.assert_false(bool(again["ok"]), "dopo la sconfitta non si va avanti")
	t.assert_true(bool(again["finita"]))
	t.assert_eq((again["errori"] as Array).size(), 1)
	t.assert_true(str((again["errori"] as Array)[0]).contains("sconfitta"))
	t.assert_eq(s.year, year, "stato invariato")


func test_la_sconfitta_arriva_dal_fine_anno(t: TestContext) -> void:
	var s := _world()
	_lose_everything(s, W.A)
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]))
	t.assert_true(bool(res["finita"]), "il fine anno della sconfitta dice partita finita")
	t.assert_eq(s.year, 1001)
	t.assert_eq(s.victory.outcome, VictoryState.DEFEAT)
	t.assert_eq(s.victory.year, 1001, "l'anno raggiunto")
	var defeats := _events(s, GameState.EV_DEFEAT)
	t.assert_eq(defeats.size(), 1)
	t.assert_eq(defeats[0]["anno"], 1001)
	t.assert_eq(defeats[0]["motivo"], "estinta", "il fine anno ha distrutto la fazione prima del controllo")


func test_senza_giocatore_non_ci_sono_ne_sconfitta_ne_vittoria(t: TestContext) -> void:
	var s := W.world()
	s.rules.victory.domination_threshold = 0.1
	_lose_everything(s, W.A)
	VictoryProcessor.check(s)
	t.assert_eq(s.events.size(), 0)
	t.assert_eq(s.victory.outcome, VictoryState.NONE)
	t.assert_false(s.is_game_over())


# --- dominio ---------------------------------------------------------------------------------------------------


func test_dominio_una_volta_e_si_puo_continuare(t: TestContext) -> void:
	var s := _world()
	t.assert_false(s.is_game_over())
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]))
	var wins := _events(s, GameState.EV_VICTORY)
	t.assert_eq(wins.size(), 1)
	t.assert_eq(wins[0]["fazione"], W.A)
	t.assert_eq(wins[0]["province"], 2)
	t.assert_eq(wins[0]["necessarie"], 2)
	t.assert_eq(wins[0]["totale"], 5)
	t.assert_eq(wins[0]["anno"], 1001)
	t.assert_eq(s.victory.outcome, VictoryState.DOMINATION)
	t.assert_eq(s.victory.domination_year, 1001)
	t.assert_true(s.victory.awaits_choice())
	t.assert_true(s.is_game_over(), "in attesa della scelta la partita non va avanti")
	t.assert_true(bool(res["finita"]))
	var blocked := TurnProcessor.end_year(s)
	t.assert_false(bool(blocked["ok"]))
	t.assert_true(str((blocked["errori"] as Array)[0]).contains("continuare"))
	t.assert_eq(s.year, 1001)
	# la scelta
	var other := GameCommands.continue_after_victory(s, W.B)
	t.assert_false(bool(other["ok"]), "solo il giocatore sceglie")
	var chosen := GameCommands.continue_after_victory(s, W.A)
	t.assert_true(bool(chosen["ok"]), str(chosen["errore"]))
	t.assert_true(s.victory.continues)
	t.assert_false(s.is_game_over())
	t.assert_eq(s.victory.outcome, VictoryState.DOMINATION, "la vittoria resta registrata")
	t.assert_false(bool(GameCommands.continue_after_victory(s, W.A)["ok"]), "non si sceglie due volte")
	for i in 3:
		var next := TurnProcessor.end_year(s)
		t.assert_true(bool(next["ok"]), "si va avanti dopo la scelta")
		t.assert_eq(_events(s, GameState.EV_VICTORY).size(), 0, "la vittoria non si ripete")
	t.assert_eq(s.year, 1004)


func test_continuare_senza_vittoria_non_si_puo(t: TestContext) -> void:
	var s := _world(0.9)
	var r := GameCommands.continue_after_victory(s, W.A)
	t.assert_false(bool(r["ok"]))
	t.assert_false(str(r["errore"]) == "")
	t.assert_false(bool(GameCommands.continue_after_victory(s, "FN_NESSUNA")["ok"]))
	t.assert_false(s.victory.continues)


func test_sotto_la_soglia_non_si_vince(t: TestContext) -> void:
	var s := _world(0.6667)
	for i in 3:
		TurnProcessor.end_year(s)
	t.assert_eq(s.victory.outcome, VictoryState.NONE)
	t.assert_eq(s.victory.domination_year, 0)
	t.assert_false(s.is_game_over())


func test_il_dominio_si_raggiunge_conquistando(t: TestContext) -> void:
	var s := _world(0.6)
	t.assert_eq(VictoryProcessor.domination_progress(s, W.A)["necessarie"], 3)
	VictoryProcessor.check(s)
	t.assert_eq(s.victory.outcome, VictoryState.NONE, "2 province su 5 non bastano")
	s.province(W.SOLA).owner = W.A
	VictoryProcessor.check(s)
	t.assert_eq(s.victory.outcome, VictoryState.DOMINATION)
	t.assert_eq(_events(s, GameState.EV_VICTORY)[0]["province"], 3)


# --- fine della campagna ---------------------------------------------------------------------------------------


func test_fine_della_campagna_nell_anno_finale(t: TestContext) -> void:
	var s := _world(0.9)
	_jump_to(s, s.final_year - 1)
	s.faction(W.G).last_income = {"agricoltura": 50}
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]))
	t.assert_true(bool(res["finita"]))
	t.assert_eq(s.year, 1700)
	var ends := _events(s, GameState.EV_CAMPAIGN_END)
	t.assert_eq(ends.size(), 1)
	t.assert_eq(ends[0]["anno"], 1700)
	t.assert_eq(ends[0]["vincitore"], W.A, "ALPHA ha due province")
	t.assert_eq(ends[0]["fazione"], W.A)
	t.assert_eq(ends[0]["giocatore"], W.A)
	t.assert_eq(ends[0]["posizione_giocatore"], 1)
	t.assert_eq((ends[0]["classifica"] as Array).size(), 3)
	t.assert_eq(s.victory.outcome, VictoryState.CAMPAIGN_END)
	t.assert_eq(s.victory.year, 1700)
	t.assert_true(s.victory.is_final())
	t.assert_eq(str(s.victory.ranking), str(VictoryProcessor.standings(s)), "la classifica dell'esito e' quella dello stato")
	var again := TurnProcessor.end_year(s)
	t.assert_false(bool(again["ok"]))
	t.assert_eq(_events(s, GameState.EV_CAMPAIGN_END).size(), 1, "il registro non cambia")


func test_fine_della_campagna_senza_giocatore_e_a_parita_di_province(t: TestContext) -> void:
	var s := W.world()
	s.province(W.BASSA).owner = W.B    # ALPHA (ALTA) 1, BETA (MEZZA, BASSA) 2, GAMMA (ORTO) 1
	s.faction(W.A).last_income = {"agricoltura": 10}
	s.faction(W.G).last_income = {"agricoltura": 30}
	s.faction(W.B).last_income = {"agricoltura": 5}
	s.year = s.final_year
	VictoryProcessor.check(s)
	var ends := _events(s, GameState.EV_CAMPAIGN_END)
	t.assert_eq(ends.size(), 1)
	t.assert_eq(ends[0]["vincitore"], W.B, "BETA ha piu' province")
	t.assert_eq(ends[0]["giocatore"], "", "nessun giocatore")
	t.assert_eq(ends[0]["posizione_giocatore"], 0)
	t.assert_eq(_events(s, GameState.EV_VICTORY).size(), 0, "senza giocatore niente vittoria")
	var rows := s.victory.ranking
	t.assert_eq(rows.size(), 3)
	t.assert_eq(str(rows[1]["fazione"]), W.G, "a parita' di province decide il reddito")
	t.assert_eq(str(rows[2]["fazione"]), W.A)
	# il pareggio al primo posto: ALPHA e GAMMA con due province, vince il reddito maggiore
	var s2 := W.world()
	s2.province(W.SOLA).owner = W.G    # ALPHA 2, BETA 1, GAMMA 2
	s2.faction(W.A).last_income = {"agricoltura": 10}
	s2.faction(W.G).last_income = {"agricoltura": 30}
	s2.year = s2.final_year
	VictoryProcessor.check(s2)
	t.assert_eq(_events(s2, GameState.EV_CAMPAIGN_END)[0]["vincitore"], W.G, "a parita' di province vince il reddito maggiore")


func test_dominio_e_fine_campagna_nello_stesso_anno(t: TestContext) -> void:
	var s := _world()
	s.year = s.final_year
	VictoryProcessor.check(s)
	t.assert_eq(_events(s, GameState.EV_VICTORY).size(), 1)
	t.assert_eq(_events(s, GameState.EV_CAMPAIGN_END).size(), 1)
	t.assert_eq(s.victory.outcome, VictoryState.CAMPAIGN_END, "la fine della campagna chiude")
	t.assert_eq(s.victory.domination_year, 1700, "la vittoria per dominio resta ricordata")


func test_dopo_il_dominio_si_continua_fino_alla_fine_della_campagna(t: TestContext) -> void:
	var s := _world()
	TurnProcessor.end_year(s)
	t.assert_true(s.victory.awaits_choice())
	GameCommands.continue_after_victory(s, W.A)
	_jump_to(s, s.final_year - 1)
	TurnProcessor.end_year(s)
	t.assert_eq(s.victory.outcome, VictoryState.CAMPAIGN_END)
	t.assert_eq(s.victory.domination_year, 1001, "il dominio e' del 1001")
	t.assert_eq(_events(s, GameState.EV_VICTORY).size(), 0)
	t.assert_eq(_events(s, GameState.EV_CAMPAIGN_END).size(), 1)
	t.assert_true(s.is_game_over())


func test_is_game_over(t: TestContext) -> void:
	var s := W.world()
	t.assert_false(s.is_game_over())
	s.year = s.final_year
	t.assert_true(s.is_game_over(), "anno finale")
	var s2 := W.world()
	s2.victory.outcome = VictoryState.DOMINATION
	t.assert_true(s2.is_game_over(), "in attesa della scelta")
	s2.victory.continues = true
	t.assert_false(s2.is_game_over())
	s2.victory.outcome = VictoryState.DEFEAT
	t.assert_true(s2.is_game_over())


# --- salvataggi ------------------------------------------------------------------------------------------------


func _restore(data: Dictionary, rules: Rules) -> Dictionary:
	var campaign := StartposLoader.load_file(W.STARTPOS)
	var units := UnitProdLoader.load_file(W.UNITS)
	var buildings := BuildingProdLoader.load_file(W.BUILDINGS)
	return SaveGame.from_dict(data, campaign, units, buildings, rules)


func test_versione_9(t: TestContext) -> void:
	t.assert_true(SaveGame.VERSION >= 9, "dalla fase 6b (versione 9) i salvataggi hanno l'esito della partita")
	var d := SaveGame.to_dict(W.world())
	t.assert_eq(d["versione"], SaveGame.VERSION)
	t.assert_true(d.has("vittoria"))
	t.assert_eq((d["vittoria"] as Dictionary)["esito"], "")


func test_andata_e_ritorno_dell_esito_attraverso_il_testo_json(t: TestContext) -> void:
	var s := _world()
	s.faction(W.G).last_income = {"agricoltura": 77, "miniere": 3, "commercio": 1, "netto": 9}
	TurnProcessor.end_year(s)
	GameCommands.continue_after_victory(s, W.A)
	_jump_to(s, s.final_year - 1)
	s.victory.continues = true
	TurnProcessor.end_year(s)
	t.assert_eq(s.victory.outcome, VictoryState.CAMPAIGN_END)
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	t.assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	var r := _restore(data, s.rules)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	if not bool(r["ok"]):
		return
	var back: GameState = r["stato"]
	t.assert_eq(back.victory.outcome, VictoryState.CAMPAIGN_END)
	t.assert_eq(back.victory.year, 1700)
	t.assert_eq(back.victory.domination_year, 1001)
	t.assert_true(back.victory.continues)
	t.assert_eq(back.victory.ranking.size(), s.victory.ranking.size())
	t.assert_eq(back.victory.ranking, s.victory.ranking, "classifica identica, tipi compresi")
	t.assert_true(back.is_game_over())
	t.assert_eq(SaveGame.to_json(back), text, "andata e ritorno stabile")


func test_andata_e_ritorno_con_la_scelta_in_attesa(t: TestContext) -> void:
	var s := _world()
	TurnProcessor.end_year(s)
	t.assert_true(s.victory.awaits_choice())
	var data: Dictionary = JSON.parse_string(SaveGame.to_json(s))
	var r := _restore(data, s.rules)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_true(back.victory.awaits_choice(), "il salvataggio ricorda che la partita aspetta la scelta")
	t.assert_true(back.is_game_over())
	t.assert_false(bool(TurnProcessor.end_year(back)["ok"]))
	t.assert_true(bool(GameCommands.continue_after_victory(back, W.A)["ok"]), "il giocatore e' ricordato nel salvataggio")
	t.assert_true(bool(TurnProcessor.end_year(back)["ok"]))


func test_i_salvataggi_precedenti_non_hanno_esito(t: TestContext) -> void:
	var s := W.world()
	var d := SaveGame.to_dict(s)
	d["versione"] = 8
	d.erase("vittoria")
	var r := _restore(d, s.rules)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_eq(back.victory.outcome, VictoryState.NONE)
	t.assert_false(back.victory.continues)
	t.assert_eq(back.victory.ranking.size(), 0)
	t.assert_false(back.is_game_over())
	# una partita di versione 8 gia' all'anno finale e' finita per l'anno, senza esito
	d["anno"] = 1700
	var late := _restore(d, s.rules)
	var back_late: GameState = late["stato"]
	t.assert_true(back_late.is_game_over())
	t.assert_eq(back_late.victory.outcome, VictoryState.NONE)
