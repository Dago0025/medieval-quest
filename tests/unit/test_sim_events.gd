extends RefCounted
## Fase 6a: eventi storici, disastri naturali, Peste Nera e Orda d'Oro (EventRules, EventProcessor, EventTexts) su mondi di
## prova scritti apposta (nessun dato del gioco). Mondo: event_world.gd (il mondo del Papato con FN_ORDA e le regioni immuni).
## Le prove con i dati reali stanno in test_sim_events_reale.gd.

const E := preload("res://tests/unit/event_world.gd")
const W := preload("res://tests/unit/papacy_world.gd")

## Eventi storici di data/eventi/eventi_storici.cfg: i 71 dell'originale (0-70) e i 71 aggiunti il 28/11/2026 (71-141).
const STORICI := 142
const MINI_HISTORY := "res://tests/fixtures/mini_eventi_storici.cfg"
const MINI_EVENTS := "res://tests/fixtures/mini_events.txt"
const SIM_STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const SIM_UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const SIM_BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"

const ALL_PROVINCES := 9
const FLOOD_FREE := 2     ## ID_NORD3 e ID_SUD2
const QUAKE_FREE := 1     ## ID_NORD3


func _province_ids(s: GameState, kind: String) -> Array:
	var out: Array = []
	for e in E.events_of(s, kind):
		out.append(str(e["provincia"]))
	return out


# --- parametri e tabella ---------------------------------------------------------


func test_i_valori_predefiniti_sono_uguali_al_file(t: TestContext) -> void:
	var from_file := EventRules.load_file(EventRules.DEFAULT_PATH, "")
	t.assert_eq(from_file.errors, PackedStringArray(), "eventi.cfg si legge senza errori")
	t.assert_eq(from_file.to_dict(), EventRules.new().to_dict(), "eventi.cfg = valori predefiniti del codice")
	t.assert_true(from_file.history.is_empty(), "senza il file storico la tabella e' vuota")
	var missing := EventRules.load_file("res://data/regole/non_esiste.cfg", "")
	t.assert_eq(missing.errors.size(), 1, "file mancante: un errore")
	t.assert_eq(missing.to_dict(), EventRules.new().to_dict(), "file mancante: valori predefiniti")


func test_i_valori_della_specifica(t: TestContext) -> void:
	var r := EventRules.new()
	t.assert_eq(r.flood_farm, 0.5, "inondazione: agricoltura dimezzata")
	t.assert_eq(r.famine_loyalty, 10, "carestia: lealta' -10")
	t.assert_eq(r.plague_losses, 0.10, "peste: 10% degli uomini")
	t.assert_eq(r.black_death_from, 1346)
	t.assert_eq(r.black_death_to, 1353)
	t.assert_eq(r.black_death_event, 54)
	t.assert_eq(r.black_death_origin, PackedStringArray(["ID_CRIMEA"]), "la Peste Nera parte da Caffa")
	t.assert_eq(r.horde_faction, "FN_GOLDEN_HORDE")
	t.assert_eq(r.horde_year, 1230)


func test_rules_legge_gli_eventi_dal_file(t: TestContext) -> void:
	var rules := Rules.load_file()
	t.assert_eq(rules.errors, PackedStringArray(), "tutti i file delle regole senza errori")
	t.assert_eq(rules.events.history.size(), STORICI, "%d eventi storici" % STORICI)
	t.assert_eq(rules.events.errors, PackedStringArray())
	t.assert_true(Rules.new().events.history.is_empty(), "Rules.new() non ha eventi storici")
	t.assert_eq(Rules.new().events.to_dict(), rules.events.to_dict(), "la tabella non fa parte di to_dict")


func test_ogni_indice_ha_una_sezione_coerente(t: TestContext) -> void:
	var rules := EventRules.load_file(EventRules.DEFAULT_PATH, EventRules.DEFAULT_HISTORY_PATH)
	t.assert_eq(rules.errors, PackedStringArray())
	t.assert_eq(rules.history.size(), STORICI)
	var keys := {}
	for i in STORICI:
		var e := rules.historical(i)
		t.assert_true(e != null, "manca l'evento %d" % i)
		if e == null:
			continue
		t.assert_eq(e.index, i)
		t.assert_true(e.key != "" and not keys.has(e.key), "chiave vuota o ripetuta all'indice %d" % i)
		keys[e.key] = true
		t.assert_true(e.year_from >= 1000 and e.year_to <= 1700 and e.year_to >= e.year_from, "anni dell'evento %d: %d-%d" % [i, e.year_from, e.year_to])
		t.assert_true(EventRules.EFFECTS.has(e.effect), "effetto fuori dal vocabolario all'indice %d: %s" % [i, e.effect])
		t.assert_true(e.source != "", "evento %d senza fonte" % i)
		if e.effect == EventRules.EFFECT_GOODS:
			t.assert_false(e.goods.is_empty(), "evento %d: effetto merci senza merci" % i)
		else:
			t.assert_true(e.goods.is_empty(), "evento %d: merci senza l'effetto merci" % i)
		if e.effect == EventRules.EFFECT_ZEAL or e.effect == EventRules.EFFECT_HERETICS or e.effect == EventRules.EFFECT_LOYALTY or e.effect == EventRules.EFFECT_PIETY or e.effect == EventRules.EFFECT_TREASURY:
			t.assert_true(e.value != 0, "evento %d: effetto senza valore" % i)
			t.assert_true(e.faction != "" or not e.regions.is_empty() or e.culture != "", "evento %d: effetto senza ambito" % i)
	t.assert_eq(rules.historical(54).year_from, rules.black_death_from, "la Peste Nera ha la finestra dell'evento 54")
	t.assert_eq(rules.historical(54).year_to, rules.black_death_to)
	t.assert_true(rules.historical(STORICI) == null)


func test_tabella_sintetica_con_errori(t: TestContext) -> void:
	var r := EventRules.new()
	var problems := r.load_history(MINI_HISTORY)
	t.assert_eq(problems.size(), 4, "effetto sconosciuto, finestra rovesciata, senza indice, indice negativo: %s" % str(problems))
	t.assert_eq(r.history.size(), 3, "tre voci valide")
	t.assert_eq(r.history[0].index, 0, "ordinate per indice")
	t.assert_eq(r.history[1].index, 2)
	t.assert_eq(r.history[2].index, 5)
	var zero := r.historical(0)
	t.assert_true(zero.is_window() and zero.provisional)
	t.assert_eq(zero.year_from, 1200)
	t.assert_eq(zero.year_to, 1210)
	t.assert_eq(zero.goods, PackedStringArray(["GRAIN", "SPICES"]), "ID in maiuscolo")
	var two := r.historical(2)
	t.assert_eq(two.faction, "FN_ALPHA")
	t.assert_eq(two.regions, PackedStringArray(["ID_NORD1", "ID_EST"]))
	t.assert_eq(two.effect, EventRules.EFFECT_ZEAL)
	t.assert_eq(two.value, 10)
	t.assert_false(two.is_window())
	t.assert_eq(two.year_to, 1100)
	t.assert_eq(r.historical(5).effect, EventRules.EFFECT_NONE, "effetto sconosciuto: nessuno")
	t.assert_eq(r.historical(5).year_to, 1300, "anno_a mancante = anno_da")
	t.assert_true(r.historical(6) == null, "la finestra rovesciata e' scartata")
	var missing := EventRules.new().load_history("res://tests/fixtures/non_esiste.cfg")
	t.assert_eq(missing.size(), 1, "file storico mancante: un errore")


# --- dati dello startpos -----------------------------------------------------------


func test_lo_startpos_legge_le_regioni_immuni(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(E.STARTPOS)
	t.assert_eq(campaign.unfloodable, PackedStringArray(["ID_NORD3", "ID_SUD2"]))
	t.assert_eq(campaign.unquakeable, PackedStringArray(["ID_NORD3"]))
	t.assert_true(campaign.is_unfloodable("id_sud2"), "senza distinzione di maiuscole")
	t.assert_false(campaign.is_unfloodable("ID_NORD1"))
	t.assert_true(campaign.is_unquakeable("ID_NORD3"))
	t.assert_false(campaign.is_unquakeable("ID_SUD2"))
	t.assert_true(campaign.has_disaster_data())
	t.assert_eq(campaign.errors, PackedStringArray(), "nessun riferimento sbagliato")
	var plain := StartposLoader.load_file(W.STARTPOS)
	t.assert_false(plain.has_disaster_data(), "senza le righe il mondo non ha disastri")
	t.assert_true(plain.unfloodable.is_empty() and plain.unquakeable.is_empty())


# --- anni degli eventi storici ------------------------------------------------------


func test_anni_fissi_finestre_e_finestre_passate(t: TestContext) -> void:
	var s := E.world()
	E.add_history(s, 1, 1100, 1100, EventRules.EFFECT_NONE)
	E.add_history(s, 2, 1100, 1110, EventRules.EFFECT_NONE)
	E.add_history(s, 3, 900, 950, EventRules.EFFECT_NONE)
	E.add_history(s, 4, 1000, 1000, EventRules.EFFECT_NONE)
	var before := s.rng.state
	EventProcessor.draw_years(s, s.rules.events)
	t.assert_eq(EventProcessor.drawn_year(s, 1), 1100, "anno fisso")
	var drawn := EventProcessor.drawn_year(s, 2)
	t.assert_true(drawn >= 1100 and drawn <= 1110, "finestra: %d" % drawn)
	t.assert_eq(EventProcessor.drawn_year(s, 3), 950, "finestra gia' passata: ultimo anno")
	t.assert_eq(EventProcessor.drawn_year(s, 4), 1000)
	t.assert_eq(EventProcessor.drawn_year(s, 99), 0, "indice sconosciuto")
	t.assert_true(s.rng.state != before, "la finestra consuma un sorteggio")
	var state_after := s.rng.state
	EventProcessor.draw_years(s, s.rules.events)
	t.assert_eq(EventProcessor.drawn_year(s, 2), drawn, "l'anno si decide una volta sola")
	t.assert_eq(s.rng.state, state_after, "e non consuma altro")
	var twin := E.world()
	E.add_history(twin, 2, 1100, 1110, EventRules.EFFECT_NONE)
	EventProcessor.draw_years(twin, twin.rules.events)
	var twin_other := E.world()
	E.add_history(twin_other, 1, 1100, 1100, EventRules.EFFECT_NONE)
	E.add_history(twin_other, 2, 1100, 1110, EventRules.EFFECT_NONE)
	EventProcessor.draw_years(twin_other, twin_other.rules.events)
	t.assert_eq(EventProcessor.drawn_year(twin, 2), EventProcessor.drawn_year(twin_other, 2), "stesso seme, stesso anno")


func test_una_finestra_comincia_dall_anno_corrente(t: TestContext) -> void:
	var s := E.world()
	s.year = 1105
	E.add_history(s, 2, 1100, 1110, EventRules.EFFECT_NONE)
	EventProcessor.draw_years(s, s.rules.events)
	var drawn := EventProcessor.drawn_year(s, 2)
	t.assert_true(drawn >= 1105 and drawn <= 1110, "mai prima dell'anno corrente: %d" % drawn)


func test_un_evento_accade_una_volta_nel_suo_anno(t: TestContext) -> void:
	var s := E.world()
	E.add_history(s, 7, 1001, 1001, EventRules.EFFECT_NONE)
	E.run_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_HISTORICAL).size(), 0, "non e' ancora il suo anno")
	s.year = 1001
	E.run_year(s)
	var found := E.events_of(s, GameState.EV_HISTORICAL)
	t.assert_eq(found.size(), 1)
	t.assert_eq(int(found[0]["indice"]), 7)
	t.assert_eq(str(found[0]["chiave"]), "prova_7")
	t.assert_eq(str(found[0]["effetto"]), EventRules.EFFECT_NONE)
	t.assert_true(str(found[0]["testo"]) != "")
	t.assert_eq(int(found[0]["anno"]), 1001)
	t.assert_eq(int(s.historical_done[7]), 1001)
	E.run_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_HISTORICAL).size(), 0, "mai due volte")
	s.year = 1002
	E.run_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_HISTORICAL).size(), 0)


func test_una_finestra_accade_una_volta_sola(t: TestContext) -> void:
	var s := E.world()
	E.add_history(s, 8, 1000, 1009, EventRules.EFFECT_NONE)
	var count := 0
	var year_seen := 0
	for i in 12:
		s.year = 1000 + i
		E.run_year(s)
		var found := E.events_of(s, GameState.EV_HISTORICAL)
		count += found.size()
		if found.size() > 0:
			year_seen = s.year
	t.assert_eq(count, 1, "una sola volta nella finestra")
	t.assert_eq(year_seen, EventProcessor.drawn_year(s, 8), "nell'anno estratto")


# --- i sei effetti -------------------------------------------------------------------


func test_effetto_zelo_regioni_cultura_e_fazione(t: TestContext) -> void:
	var s := E.world()
	E.add_history(s, 1, 1000, 1000, EventRules.EFFECT_ZEAL, 10, "", ["ID_NORD1", "id_est"])
	E.add_history(s, 2, 1000, 1000, EventRules.EFFECT_ZEAL, -20, "", [], "MUSLIM_CULTURE")
	E.add_history(s, 3, 1000, 1000, EventRules.EFFECT_ZEAL, 5, "FN_DELTA")
	for p in s.provinces:
		p.zeal = 50
	s.province("ID_EST").zeal = 95
	E.run_year(s)
	t.assert_eq(s.province("ID_NORD1").zeal, 60, "regione citata")
	t.assert_eq(s.province("ID_EST").zeal, 100, "tetto a 100")
	t.assert_eq(s.province("ID_SUD1").zeal, 30, "tutte le regioni della cultura")
	t.assert_eq(s.province("ID_SUD2").zeal, 30)
	t.assert_eq(s.province("ID_DELTA1").zeal, 55, "senza regioni: le province della fazione")
	t.assert_eq(s.province("ID_ROMA").zeal, 50, "le altre non cambiano")
	t.assert_eq(s.province("ID_NORD2").zeal, 50)
	var found := E.events_of(s, GameState.EV_HISTORICAL)
	t.assert_eq(found.size(), 3)
	t.assert_eq(found[0]["regioni"], ["ID_NORD1", "ID_EST"], "regioni toccate nell'evento")
	t.assert_eq(int(found[1]["valore"]), -20)
	s.province("ID_SUD1").zeal = 10
	E.add_history(s, 4, 1001, 1001, EventRules.EFFECT_ZEAL, -20, "", ["ID_SUD1"])
	s.year = 1001
	E.run_year(s)
	t.assert_eq(s.province("ID_SUD1").zeal, 0, "tetto a 0")


func test_effetto_eretici(t: TestContext) -> void:
	var s := E.world()
	var p := s.province("ID_NORD1")
	p.religions = {"CATHOLIC": 100.0, "ORTHODOX": 0.0, "MUSLIM": 0.0, "PAGAN": 0.0, "HERETIC": 0.0}
	E.add_history(s, 1, 1000, 1000, EventRules.EFFECT_HERETICS, 10, "", ["ID_NORD1"])
	E.run_year(s)
	t.assert_true(absf(float(p.religions["HERETIC"]) - 10.0) < 0.01, "eretici +10: %s" % str(p.religions))
	var total := 0.0
	for k in p.religions:
		total += float(p.religions[k])
	t.assert_true(absf(total - 100.0) < 0.01, "le percentuali sommano sempre a 100")
	t.assert_true(float(p.religions["CATHOLIC"]) < 100.0)


func test_effetto_lealta_dei_generali(t: TestContext) -> void:
	var s := E.world()
	var limit := s.rules.dynasty.max_attribute
	var mine := s.create_character("FN_ALPHA")
	mine.role = Character.ROLE_GENERAL
	mine.loyalty = 2
	mine.old_age = 500
	var other := s.create_character("FN_GAMMA")
	other.role = Character.ROLE_GENERAL
	other.loyalty = 2
	other.old_age = 500
	var leader_before := s.leader_of("FN_ALPHA").loyalty
	E.add_history(s, 1, 1000, 1000, EventRules.EFFECT_LOYALTY, 3, "FN_ALPHA")
	E.run_year(s)
	t.assert_eq(mine.loyalty, mini(5, limit), "lealta' del generale della fazione")
	t.assert_eq(other.loyalty, 2, "le altre fazioni no")
	t.assert_eq(s.leader_of("FN_ALPHA").loyalty, leader_before, "il capo non e' un generale")
	var found := E.events_of(s, GameState.EV_HISTORICAL)
	t.assert_eq(found[0]["fazioni"], ["FN_ALPHA"])
	E.add_history(s, 2, 1001, 1001, EventRules.EFFECT_LOYALTY, -9, "FN_ALPHA")
	s.year = 1001
	E.run_year(s)
	t.assert_eq(mine.loyalty, 0, "tetto a 0")


func test_effetto_pieta_del_capo(t: TestContext) -> void:
	var s := E.world()
	var leader := s.leader_of("FN_ALPHA")
	leader.piety = 2
	var gamma_leader := s.leader_of("FN_GAMMA")
	var gamma_piety := gamma_leader.piety
	E.add_history(s, 1, 1000, 1000, EventRules.EFFECT_PIETY, 1, "", ["ID_NORD1"])
	E.run_year(s)
	t.assert_eq(leader.piety, 3, "senza fazione: il proprietario della prima regione")
	t.assert_eq(gamma_leader.piety, gamma_piety)
	E.add_history(s, 2, 1001, 1001, EventRules.EFFECT_PIETY, -5, "FN_ALPHA")
	s.year = 1001
	E.run_year(s)
	t.assert_eq(leader.piety, 0, "tetto a 0")


func test_effetto_tesoro(t: TestContext) -> void:
	var s := E.world()
	var before := s.faction("FN_GAMMA").treasury
	var alpha := s.faction("FN_ALPHA").treasury
	E.add_history(s, 1, 1000, 1000, EventRules.EFFECT_TREASURY, 500, "FN_GAMMA")
	E.run_year(s)
	t.assert_eq(s.faction("FN_GAMMA").treasury, before + 500)
	t.assert_eq(s.faction("FN_ALPHA").treasury, alpha)


func test_effetto_merci(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(SIM_STARTPOS)
	var units := UnitProdLoader.load_file(SIM_UNITS)
	var buildings := BuildingProdLoader.load_file(SIM_BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, E.quiet_rules(), 5)
	var p := s.province("ID_ALTA")
	var region := s.campaign.region("ID_ALTA")
	t.assert_true(region.has_port, "ID_ALTA e' un porto")
	var before := Economy.trade_income(s, p, region)
	t.assert_true(before > 0, "il porto commercia (porto e mercante nello startpos)")
	E.add_history(s, 1, 1000, 1000, EventRules.EFFECT_GOODS, 0, "", ["ID_ALTA"], "", ["SPICES", "SPICES"])
	E.run_year(s)
	t.assert_eq(p.extra_goods, PackedStringArray(["SPICES"]), "la merce nuova, una volta sola")
	t.assert_true(Economy.trade_income(s, p, region) > before, "il commercio rende di piu'")
	var found := E.events_of(s, GameState.EV_HISTORICAL)
	t.assert_eq(found[0]["regioni"], ["ID_ALTA"])
	t.assert_eq(region.trade_goods.has("SPICES"), false, "i dati della campagna non cambiano")
	# una merce che la regione ha gia' non conta due volte
	var owned := String(region.trade_goods[0]) if not region.trade_goods.is_empty() else ""
	if owned != "":
		var income := Economy.trade_income(s, p, region)
		E.add_history(s, 2, 1001, 1001, EventRules.EFFECT_GOODS, 0, "", ["ID_ALTA"], "", [owned])
		s.year = 1001
		E.run_year(s)
		t.assert_eq(Economy.trade_income(s, p, region), income, "merce gia' presente")


func test_effetto_nessuno_non_cambia_nulla(t: TestContext) -> void:
	var s := E.world()
	E.add_history(s, 1, 1000, 1000, EventRules.EFFECT_NONE, 0, "FN_ALPHA", ["ID_NORD1"])
	var zeal := s.province("ID_NORD1").zeal
	var treasury := s.faction("FN_ALPHA").treasury
	E.run_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_HISTORICAL).size(), 1, "l'evento si annuncia lo stesso")
	t.assert_eq(s.province("ID_NORD1").zeal, zeal)
	t.assert_eq(s.faction("FN_ALPHA").treasury, treasury)


# --- inerzia ------------------------------------------------------------------------


func test_senza_dati_il_mondo_resta_inerte(t: TestContext) -> void:
	var s := W.world()
	s.year = 1230
	t.assert_false(s.campaign.has_disaster_data())
	t.assert_true(s.rules.events.history.is_empty())
	s.rules.events.flood_chance = 1.0
	s.rules.events.famine_chance = 1.0
	s.rules.events.quake_chance = 1.0
	s.rules.events.plague_chance = 1.0
	s.rules.events.storm_chance = 1.0
	var before := s.rng.state
	var armies := s.armies.size()
	E.run_year(s)
	t.assert_eq(s.rng.state, before, "nessun numero casuale consumato")
	t.assert_eq(s.events.size(), 0, "nessun evento")
	t.assert_eq(s.armies.size(), armies)
	t.assert_true(s.black_death.is_empty() and s.horde.is_empty())


func test_probabilita_zero_non_consuma_numeri_casuali(t: TestContext) -> void:
	var s := E.world()
	E.add_history(s, 54, 1346, 1346, EventRules.EFFECT_NONE)
	var before := s.rng.state
	E.run_year(s)
	t.assert_eq(s.rng.state, before, "con tutte le probabilita' a zero e la Peste Nera collegata")
	t.assert_eq(s.events.size(), 0)
	t.assert_true(s.black_death.is_empty())


# --- disastri -------------------------------------------------------------------------


func test_inondazione_dimezza_l_agricoltura_e_non_colpisce_le_regioni_immuni(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.flood_chance = 1.0
	var p := s.province("ID_NORD1")
	var farm := int(Economy.province_income(s, p)["agricoltura"])
	t.assert_true(farm > 0, "la provincia ha un'agricoltura")
	E.run_year(s)
	var hit := _province_ids(s, GameState.EV_FLOOD)
	t.assert_eq(hit.size(), ALL_PROVINCES - FLOOD_FREE)
	t.assert_false(hit.has("ID_NORD3"), "ID_NORD3 e' immune")
	t.assert_false(hit.has("ID_SUD2"), "ID_SUD2 e' immune")
	t.assert_true(hit.has("ID_NORD1"))
	t.assert_eq(p.temp_factor(ProvinceState.TEMP_FARM), 0.5)
	t.assert_eq(s.province("ID_NORD3").temp_effects.size(), 0)
	var halved := int(Economy.province_income(s, p)["agricoltura"])
	t.assert_true(absi(halved * 2 - farm) <= 1, "agricoltura dimezzata: %d -> %d" % [farm, halved])
	var first := E.events_of(s, GameState.EV_FLOOD)[0]
	t.assert_eq(str(first["proprietario"]), s.province(str(first["provincia"])).owner)
	EventProcessor.clear_temporary(s)
	t.assert_eq(int(Economy.province_income(s, p)["agricoltura"]), farm, "a fine anno l'effetto sparisce")
	t.assert_true(p.temp_effects.is_empty())


func test_carestia_azzera_l_agricoltura_e_toglie_lealta(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.famine_chance = 1.0
	var p := s.province("ID_NORD1")
	p.loyalty = 80
	s.province("ID_ROMA").loyalty = 4
	E.run_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_FAMINE).size(), ALL_PROVINCES, "nessuna regione e' immune alla carestia")
	t.assert_eq(p.loyalty, 70, "lealta' -10")
	t.assert_eq(s.province("ID_ROMA").loyalty, 0, "non scende sotto zero")
	t.assert_eq(int(Economy.province_income(s, p)["agricoltura"]), 0, "nessun raccolto")
	for e in E.events_of(s, GameState.EV_FAMINE):
		if str(e["provincia"]) == "ID_ROMA":
			t.assert_eq(int(e["lealta_persa"]), 4)
		if str(e["provincia"]) == "ID_NORD1":
			t.assert_eq(int(e["lealta_persa"]), 10)


func test_carestia_dopo_inondazione_resta_zero(t: TestContext) -> void:
	var s := E.world()
	var p := s.province("ID_NORD1")
	p.add_temp_factor(ProvinceState.TEMP_FARM, 0.5)
	p.add_temp_factor(ProvinceState.TEMP_FARM, 0.0)
	p.add_temp_factor(ProvinceState.TEMP_FARM, 0.5)
	t.assert_eq(p.temp_factor(ProvinceState.TEMP_FARM), 0.0, "vale il fattore minore")
	t.assert_eq(p.temp_factor(ProvinceState.TEMP_INCOME), 1.0, "senza effetto vale 1")


func test_terremoto_toglie_un_livello_ma_non_al_castello(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.quake_chance = 1.0
	var castle := s.rules.combat.castle_family
	var p := s.province("ID_NORD1")
	var castle_level := p.level_of(castle)
	t.assert_true(castle_level > 0)
	var others_before := 0
	for family in p.buildings:
		if str(family) != castle:
			others_before += int(p.buildings[family])
	t.assert_true(others_before > 0, "ID_NORD1 ha altri edifici")
	E.run_year(s)
	var hit := _province_ids(s, GameState.EV_QUAKE)
	t.assert_eq(hit.size(), ALL_PROVINCES - QUAKE_FREE)
	t.assert_false(hit.has("ID_NORD3"), "ID_NORD3 e' immune ai terremoti")
	t.assert_true(hit.has("ID_SUD2"), "ID_SUD2 e' immune solo alle inondazioni")
	t.assert_eq(p.level_of(castle), castle_level, "il castello non si tocca")
	var others_after := 0
	for family in p.buildings:
		if str(family) != castle:
			others_after += int(p.buildings[family])
	t.assert_eq(others_after, others_before - 1, "un edificio perde un livello")
	for e in E.events_of(s, GameState.EV_QUAKE):
		if str(e["provincia"]) == "ID_NORD1":
			t.assert_true(str(e["edificio"]) != "" and str(e["edificio"]) != castle)
		if str(e["provincia"]) == "ID_EST":
			t.assert_eq(str(e["edificio"]), "", "solo il castello: niente da colpire")


func test_tempesta_toglie_una_pila_alla_flotta(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.storm_chance = 1.0
	var fleet := s.create_army("FN_ALPHA", "ID_NORD1", true)
	fleet.stacks.append(UnitStack.new("Spearmen", 30, 0))
	fleet.stacks.append(UnitStack.new("Spearmen", 20, 0))
	fleet.stacks.append(UnitStack.new("Spearmen", 10, 0))
	var land := W.land_army(s, "FN_ALPHA", "ID_NORD1")
	var land_men := land.men_total()
	E.run_year(s)
	var found := E.events_of(s, GameState.EV_STORM)
	t.assert_eq(found.size(), 1, "una sola flotta")
	t.assert_eq(int(found[0]["esercito"]), fleet.id)
	t.assert_eq(int(found[0]["uomini"]), 10, "perde l'ultima pila")
	t.assert_eq(int(found[0]["pile"]), 1)
	t.assert_eq(fleet.stacks.size(), 2)
	t.assert_eq(land.men_total(), land_men, "gli eserciti di terra non sono toccati")
	E.run_year(s)
	E.run_year(s)
	t.assert_true(s.army(fleet.id) == null, "senza pile la flotta e' perduta")
	t.assert_eq(E.events_of(s, GameState.EV_STORM).size(), 1)


## Richiesta di Federico del 18/11/2026: le Fregate del Drago degli Auror affondano molto meno nelle tempeste.
func test_fregate_del_drago_resistono_alle_tempeste(t: TestContext) -> void:
	t.assert_eq(EventProcessor.ship_storm_factor("AurorDragonFrigate"), 0.1)
	t.assert_eq(EventProcessor.ship_storm_factor("Cog"), 1.0)
	var s := E.world()
	s.rules.events.storm_chance = 1.0
	var fleet := s.create_army("FN_ALPHA", "ID_NORD1", true)
	fleet.stacks.append(UnitStack.new("AurorDragonFrigate", 30, 0))
	t.assert_eq(EventProcessor.storm_factor(s, fleet), 0.1, "flotta di sole fregate")
	fleet.stacks.append(UnitStack.new("Spearmen", 20, 0))
	fleet.stacks.append(UnitStack.new("AurorDragonFrigate", 25, 0))
	t.assert_eq(EventProcessor.storm_factor(s, fleet), 1.0, "con una nave comune il rischio e' quello normale")
	E.run_year(s)
	var found := E.events_of(s, GameState.EV_STORM)
	t.assert_eq(found.size(), 1)
	t.assert_eq(int(found[0]["uomini"]), 20, "affonda prima la nave piu' fragile, non la fregata")
	t.assert_eq(fleet.stacks.size(), 2)


## Richiesta di Federico del 23/11/2026: le navi degli Auror non affondano nelle tempeste (`flotte_immuni_tempeste`).
func test_flotte_auror_immuni_alle_tempeste(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.storm_chance = 1.0
	s.rules.storm_immune_factions = PackedStringArray(["FN_ALPHA"])
	var fleet := s.create_army("FN_ALPHA", "ID_NORD1", true)
	fleet.stacks.append(UnitStack.new("Spearmen", 30, 0))
	fleet.stacks.append(UnitStack.new("AurorDragonFrigate", 25, 0))
	var other := s.create_army("FN_BETA", "ID_NORD1", true)
	other.stacks.append(UnitStack.new("Spearmen", 30, 0))
	other.stacks.append(UnitStack.new("Spearmen", 20, 0))
	E.run_year(s)
	t.assert_eq(fleet.stacks.size(), 2, "nessuna nave degli Auror perduta")
	t.assert_eq(other.stacks.size(), 1, "le altre fazioni perdono una pila come sempre")
	for e in E.events_of(s, GameState.EV_STORM):
		t.assert_true(str(e["fazione"]) != "FN_ALPHA", "nessuna tempesta registrata per gli Auror")
	t.assert_true(Rules.load_file().storm_immune_factions.has("FN_DANISH"), "auror.cfg: gli Auror")
	var historic := Rules.load_file()
	historic.remove_faction_powers()
	t.assert_true(historic.storm_immune_factions.is_empty(), "nello scenario storico nessuna fazione e' immune")


func test_peste_toglie_il_dieci_per_cento_e_il_conto_torna(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.plague_chance = 1.0
	var before := E.men(s)
	var armies := s.armies.size()
	E.run_year(s)
	var found := E.events_of(s, GameState.EV_PLAGUE)
	t.assert_eq(found.size(), ALL_PROVINCES)
	var lost := 0
	for e in found:
		lost += int(e["uomini"])
		t.assert_eq(str(e["origine"]), "", "senza propagazione")
		t.assert_false(bool(e["peste_nera"]))
	t.assert_true(lost > 0)
	t.assert_eq(E.men(s), before - lost, "gli uomini persi sono tutti dichiarati")
	t.assert_true(lost <= int(ceil(float(before) * 0.1)) + armies, "circa il 10%%: %d su %d" % [lost, before])
	t.assert_eq(s.armies.size(), armies, "nessun esercito sparisce")


func test_peste_si_propaga_alle_confinanti(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.plague_chance = 1.0
	s.rules.events.plague_spread = 1.0
	E.run_year(s)
	var found := E.events_of(s, GameState.EV_PLAGUE)
	t.assert_eq(found.size(), ALL_PROVINCES, "una peste per provincia, mai due")
	var seen := {}
	for e in found:
		t.assert_false(seen.has(str(e["provincia"])), "ripetuta: %s" % str(e["provincia"]))
		seen[str(e["provincia"])] = true
	var nord1: Dictionary = {}
	for e in found:
		if str(e["provincia"]) == "ID_NORD1":
			nord1 = e
	t.assert_eq(str(nord1["origine"]), "ID_ROMA", "ID_ROMA e' la prima e ID_NORD1 la sua unica confinante")
	t.assert_true(str(nord1["testo"]) != "")


func test_peste_non_uccide_l_ultima_pila_di_una_crociata(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.plague_chance = 1.0
	s.rules.events.plague_losses = 1.0
	var crusade := W.add_crusade(s, "FN_ALPHA", "ID_NORD1", "crociata", "", 2)
	var normal := W.land_army(s, "FN_GAMMA", "ID_EST")
	E.run_year(s)
	t.assert_true(s.army(normal.id) == null, "un esercito normale muore con perdite totali")
	t.assert_true(s.army(crusade.id) != null, "la crociata resta")
	t.assert_eq(crusade.stacks.size(), 2)
	for st in crusade.stacks:
		t.assert_eq(st.men, 1, "un uomo per pila")


func test_una_peste_totale_toglie_tutti_gli_eserciti(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.plague_chance = 1.0
	s.rules.events.plague_losses = 1.0
	E.run_year(s)
	for a in s.armies:
		t.assert_true(a.is_fleet or not a.stacks.is_empty(), "nessun esercito vuoto")
	t.assert_eq(s.armies.size(), 0, "tutti gli eserciti sono morti")
	for f in s.factions:
		if f.id == "FN_ALPHA":
			t.assert_true(f.alive, "ha ancora le province")


func test_un_anno_con_i_disastri_e_il_reddito_a_fine_anno(t: TestContext) -> void:
	var calm := E.world()
	var stormy := E.world()
	stormy.rules.events.flood_chance = 1.0
	var res_calm := TurnProcessor.end_year(calm)
	var res_stormy := TurnProcessor.end_year(stormy)
	t.assert_eq(res_calm["errori"].size(), 0, str(res_calm["errori"]))
	t.assert_eq(res_stormy["errori"].size(), 0, str(res_stormy["errori"]))
	t.assert_true(E.events_of(stormy, GameState.EV_FLOOD).size() > 0, "inondazioni nell'anno")
	t.assert_eq(E.events_of(calm, GameState.EV_FLOOD).size(), 0)
	t.assert_true(stormy.faction("FN_ALPHA").treasury < calm.faction("FN_ALPHA").treasury, "reddito agricolo ridotto nell'anno dell'inondazione")
	for p in stormy.provinces:
		t.assert_true(p.temp_effects.is_empty(), "effetti di un anno azzerati dopo il reddito: %s" % p.id)
	t.assert_eq(stormy.year, 1001)


func test_eventi_storici_nel_fine_anno(t: TestContext) -> void:
	var s := E.world()
	E.add_history(s, 3, 1000, 1000, EventRules.EFFECT_TREASURY, 1000, "FN_DELTA")
	var twin := E.world()
	TurnProcessor.end_year(twin)
	var res := TurnProcessor.end_year(s)
	t.assert_eq(res["errori"].size(), 0)
	t.assert_eq(E.events_of(s, GameState.EV_HISTORICAL).size(), 1)
	t.assert_eq(s.faction("FN_DELTA").treasury, twin.faction("FN_DELTA").treasury + 1000, "il tesoro sale prima del reddito")


# --- Peste Nera -----------------------------------------------------------------------


func _black_death_world() -> GameState:
	var s := E.world()
	var ev := s.rules.events
	ev.black_death_origin = PackedStringArray(["ID_ROMA"])
	ev.black_death_spread = 1.0
	ev.black_death_years = 2
	ev.black_death_losses = 0.25
	ev.black_death_income = 0.5
	E.add_history(s, 54, 1346, 1346, EventRules.EFFECT_NONE)
	return s


func test_peste_nera_comincia_nell_anno_dell_evento_storico(t: TestContext) -> void:
	var s := _black_death_world()
	s.year = 1345
	E.run_year(s)
	t.assert_true(s.black_death.is_empty(), "non ancora")
	var roma_men := 0
	s.year = 1346
	for a in s.armies_in("ID_ROMA"):
		roma_men += a.men_total()
	E.run_year(s)
	var start := E.events_of(s, GameState.EV_BLACK_DEATH)
	t.assert_eq(start.size(), 1)
	t.assert_eq(start[0]["regioni"], ["ID_ROMA"])
	t.assert_eq(int(start[0]["anno_inizio"]), 1346)
	t.assert_true(bool(s.black_death["iniziata"]))
	var roma := s.province("ID_ROMA")
	t.assert_eq(roma.temp_factor(ProvinceState.TEMP_INCOME), 0.5, "reddito dimezzato nelle regioni colpite")
	var plagues := E.events_of(s, GameState.EV_PLAGUE)
	t.assert_eq(plagues.size(), 1)
	t.assert_true(bool(plagues[0]["peste_nera"]))
	var after := 0
	for a in s.armies_in("ID_ROMA"):
		after += a.men_total()
	t.assert_true(after < roma_men, "perdite del 25%")
	t.assert_eq(int(plagues[0]["uomini"]), roma_men - after)
	var sick: Dictionary = s.black_death["colpite"]
	t.assert_true(sick.has("ID_NORD1"), "propagata alla confinante")
	t.assert_eq(int(sick["ID_NORD1"]), 2)
	t.assert_eq(int(sick["ID_ROMA"]), 1, "un anno di contagio fatto")


func test_peste_nera_si_propaga_finisce_e_non_torna(t: TestContext) -> void:
	var s := _black_death_world()
	s.year = 1346
	var starts := 0
	var touched := {}
	var years := 0
	for i in 40:
		s.year = 1346 + i
		E.run_year(s)
		EventProcessor.clear_temporary(s)
		starts += E.events_of(s, GameState.EV_BLACK_DEATH).size()
		for e in E.events_of(s, GameState.EV_PLAGUE):
			t.assert_true(bool(e["peste_nera"]))
			touched[str(e["provincia"])] = true
		if bool(s.black_death.get("finita", false)) and years == 0:
			years = i
	t.assert_eq(starts, 1, "una volta sola")
	t.assert_true(bool(s.black_death["finita"]), "il contagio finisce")
	t.assert_true(years > 0 and years <= 12, "dura al piu' anni_massimi: %d" % years)
	t.assert_eq(touched.size(), ALL_PROVINCES, "tutte le province collegate per terra sono colpite: %s" % str(touched.keys()))
	t.assert_true(s.black_death["colpite"].is_empty())
	t.assert_eq(E.events_of(s, GameState.EV_PLAGUE).size(), 0, "dopo la fine niente piu' peste")


func test_peste_nera_collegata_all_evento_non_si_estrae_da_sola(t: TestContext) -> void:
	var s := _black_death_world()
	var before := s.rng.state
	s.year = 1000
	E.run_year(s)
	t.assert_eq(s.rng.state, before, "nessun sorteggio finche' l'evento 54 non e' accaduto")
	t.assert_true(s.black_death.is_empty())


func test_peste_nera_senza_evento_storico_si_estrae_nella_finestra(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.black_death_origin = PackedStringArray(["ID_ROMA"])
	var starts := 0
	var start_year := 0
	for y in range(1340, 1365):
		s.year = y
		E.run_year(s)
		var found := E.events_of(s, GameState.EV_BLACK_DEATH)
		starts += found.size()
		if found.size() > 0:
			start_year = y
		EventProcessor.clear_temporary(s)
	t.assert_eq(starts, 1, "una volta sola")
	t.assert_true(start_year >= 1346 and start_year <= 1353, "nella finestra: %d" % start_year)
	t.assert_eq(int(s.black_death["programmata"]), start_year, "l'anno programmato e' quello dell'inizio")


func test_peste_nera_con_finestra_passata_non_comincia(t: TestContext) -> void:
	var s := E.world()
	s.year = 1400
	E.run_year(s)
	t.assert_true(bool(s.black_death["finita"]) and not bool(s.black_death["iniziata"]))
	for y in range(1401, 1410):
		s.year = y
		E.run_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_BLACK_DEATH).size(), 0)


func test_peste_nera_senza_regioni_di_origine_dichiarate_non_comincia(t: TestContext) -> void:
	var s := _black_death_world()
	s.rules.events.black_death_origin = PackedStringArray(["ID_NON_ESISTE"])
	s.year = 1346
	E.run_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_BLACK_DEATH).size(), 0)
	t.assert_eq(E.events_of(s, GameState.EV_PLAGUE).size(), 0)
	t.assert_eq(E.events_of(s, GameState.EV_HISTORICAL).size(), 1, "l'evento storico si annuncia lo stesso")


func test_peste_nera_per_mare(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(SIM_STARTPOS)
	var units := UnitProdLoader.load_file(SIM_UNITS)
	var buildings := BuildingProdLoader.load_file(SIM_BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, E.quiet_rules(), 5)
	var land_links := EventProcessor.black_death_links(s, "ID_ALTA")
	t.assert_eq(land_links.size(), 1, "ID_ALTA confina per terra solo con ID_BASSA")
	t.assert_eq(str(land_links[0]["id"]), "ID_BASSA")
	t.assert_false(bool(land_links[0]["mare"]))
	t.assert_true(s.campaign.region("ID_MEZZA").has_port)
	# ID_MEZZA si affaccia su un altro mare: nessun collegamento finche' non condividono una zona di mare
	t.assert_eq(EventProcessor.black_death_links(s, "ID_ALTA").size(), 1)
	s.campaign.region("ID_MEZZA").neighbours.append("ID_MARE_NORD")
	var links := EventProcessor.black_death_links(s, "ID_ALTA")
	t.assert_eq(links.size(), 2, "ora c'e' anche il collegamento per mare")
	t.assert_eq(str(links[1]["id"]), "ID_MEZZA")
	t.assert_true(bool(links[1]["mare"]))
	t.assert_eq(EventProcessor.black_death_links(s, "ID_NON_ESISTE").size(), 0)
	t.assert_eq(EventProcessor.black_death_links(s, "ID_SOLA").size(), 1, "senza porto solo i confini di terra")


# --- Orda d'Oro ----------------------------------------------------------------------


func test_l_orda_arriva_nel_1230_con_la_cavalleria(t: TestContext) -> void:
	var s := E.world()
	var horde := s.faction(E.HORDE)
	t.assert_false(horde.alive, "inattiva all'inizio")
	s.year = 1229
	E.run_year(s)
	t.assert_false(horde.alive, "non ancora")
	s.year = 1230
	E.run_year(s)
	var found := E.events_of(s, GameState.EV_HORDE_ARRIVES)
	t.assert_eq(found.size(), 1)
	t.assert_true(horde.alive)
	t.assert_true(horde.treasury >= 3000)
	t.assert_eq(str(found[0]["fazione"]), E.HORDE)
	t.assert_eq(str(found[0]["provincia"]), "ID_RIBELLE")
	t.assert_eq(int(found[0]["pile"]), 8)
	t.assert_eq(str(found[0]["unita"]), "Chevaliers", "la cavalleria migliore non degli ordini militari")
	var armies := s.armies_of(E.HORDE)
	t.assert_eq(armies.size(), 1)
	t.assert_eq(armies[0].region, "ID_RIBELLE")
	t.assert_eq(armies[0].stacks.size(), 8)
	t.assert_eq(armies[0].men_total(), int(found[0]["uomini"]), "gli uomini creati sono dichiarati")
	t.assert_eq(armies[0].men_total(), 8 * 40)
	t.assert_eq(str(s.horde["stato"]), "attiva")
	t.assert_eq(int(s.horde["arrivo"]), 1230)
	t.assert_eq(str(s.horde["ingresso"]), "ID_RIBELLE")
	s.year = 1231
	E.run_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_HORDE_ARRIVES).size(), 0, "arriva una volta sola")


func test_l_orda_non_arriva_se_la_fazione_e_viva_o_manca(t: TestContext) -> void:
	var s := E.world()
	s.year = 1230
	s.faction(E.HORDE).alive = true
	E.run_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_HORDE_ARRIVES).size(), 0, "gia' viva: niente arrivo")
	var other := E.world()
	other.year = 1230
	other.rules.events.horde_faction = "FN_NON_ESISTE"
	E.run_year(other)
	t.assert_eq(E.events_of(other, GameState.EV_HORDE_ARRIVES).size(), 0, "fazione non dichiarata")
	var no_entry := E.world()
	no_entry.year = 1230
	no_entry.rules.events.horde_entry = PackedStringArray(["ID_NON_ESISTE"])
	E.run_year(no_entry)
	t.assert_eq(E.events_of(no_entry, GameState.EV_HORDE_ARRIVES).size(), 0, "nessuna regione d'ingresso")
	t.assert_false(no_entry.faction(E.HORDE).alive)


func test_ingresso_dell_orda_la_regione_piu_debole(t: TestContext) -> void:
	var s := E.world()
	W.land_army(s, "FN_ALPHA", "ID_NORD1").stacks[0].men = 50
	W.land_army(s, "FN_GAMMA", "ID_EST").stacks[0].men = 40
	W.land_army(s, "FN_DELTA", "ID_DELTA1").stacks[0].men = 10
	s.rules.events.horde_entry = PackedStringArray(["ID_NORD1", "ID_DELTA1", "ID_EST"])
	var region := EventProcessor.horde_entry(s, s.rules.events)
	t.assert_eq(region.id, "ID_DELTA1", "la guarnigione piu' debole (10 contro 40 e 50)")
	s.rules.events.horde_entry = PackedStringArray(["ID_NORD1", "ID_RIBELLE", "ID_EST"])
	t.assert_eq(EventProcessor.horde_entry(s, s.rules.events).id, "ID_RIBELLE", "i ribelli hanno la precedenza")
	s.rules.events.horde_entry = PackedStringArray(["ID_NON_ESISTE"])
	t.assert_true(EventProcessor.horde_entry(s, s.rules.events) == null)


func test_arrivo_in_una_provincia_di_un_altra_fazione_e_guerra(t: TestContext) -> void:
	var s := E.world()
	s.year = 1230
	s.rules.events.horde_entry = PackedStringArray(["ID_DELTA1"])
	E.run_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_HORDE_ARRIVES).size(), 1)
	t.assert_true(s.at_war(E.HORDE, "FN_DELTA"), "l'Orda e' in guerra con il proprietario")
	t.assert_eq(E.events_of(s, GameState.EV_WAR_DECLARED).size(), 1)


func test_l_orda_senza_conquiste_si_scioglie(t: TestContext) -> void:
	var s := E.world()
	s.year = 1230
	s.rules.events.horde_years = 3
	E.run_year(s)
	var created := E.men(s)
	var horde_men := 0
	for a in s.armies_of(E.HORDE):
		horde_men += a.men_total()
	var gone := 0
	for y in range(1231, 1236):
		s.year = y
		E.run_year(s)
		gone += E.events_of(s, GameState.EV_HORDE_GONE).size()
		if gone > 0:
			break
	t.assert_eq(gone, 1)
	t.assert_eq(s.year, 1233, "dopo tre anni senza conquiste")
	t.assert_false(s.faction(E.HORDE).alive)
	t.assert_eq(s.armies_of(E.HORDE).size(), 0, "eserciti sciolti")
	t.assert_eq(str(s.horde["stato"]), "sciolta")
	t.assert_eq(E.men(s), created - horde_men)
	for y in range(1234, 1240):
		s.year = y
		E.run_year(s)
		t.assert_eq(E.events_of(s, GameState.EV_HORDE_ARRIVES).size() + E.events_of(s, GameState.EV_HORDE_GONE).size(), 0, "mai piu' eventi dell'Orda")


func test_le_conquiste_allungano_la_vita_dell_orda(t: TestContext) -> void:
	var s := E.world()
	s.year = 1230
	s.rules.events.horde_years = 3
	E.run_year(s)
	for y in range(1231, 1238):
		s.year = y
		s.events.clear()
		s.add_event(GameState.EV_PROVINCE_CAPTURED, {"fazione": E.HORDE, "regione": "ID_RIBELLE", "precedente": "FN_REBEL"})
		EventProcessor.process_year(s)
	t.assert_eq(E.events_of(s, GameState.EV_HORDE_GONE).size(), 0)
	t.assert_true(s.faction(E.HORDE).alive)
	t.assert_eq(int(s.horde["conquiste"]), 7)
	t.assert_eq(int(s.horde["senza_conquiste"]), 0)


func test_orda_distrutta_in_battaglia(t: TestContext) -> void:
	var s := E.world()
	s.year = 1230
	E.run_year(s)
	for a in s.armies_of(E.HORDE):
		s.remove_army(a)
	s.faction(E.HORDE).alive = false
	s.year = 1231
	E.run_year(s)
	var found := E.events_of(s, GameState.EV_HORDE_GONE)
	t.assert_eq(found.size(), 1)
	t.assert_eq(str(found[0]["motivo"]), "distrutta")
	t.assert_eq(int(found[0]["uomini"]), 0)
	t.assert_eq(str(s.horde["stato"]), "sciolta")


func test_scioglimento_passa_le_province_ai_ribelli(t: TestContext) -> void:
	var s := E.world()
	s.year = 1230
	s.rules.events.horde_years = 1
	E.run_year(s)
	var p := s.province("ID_RIBELLE")
	p.owner = E.HORDE
	s.year = 1231
	E.run_year(s)
	var found := E.events_of(s, GameState.EV_HORDE_GONE)
	t.assert_eq(found.size(), 1)
	t.assert_eq(found[0]["province"], ["ID_RIBELLE"])
	t.assert_eq(p.owner, GameState.REBEL, "la provincia torna ai ribelli")


func test_regola_fissa_di_attacco_dell_orda(t: TestContext) -> void:
	var s := E.world()
	s.year = 1230
	E.run_year(s)
	t.assert_eq(EventProcessor.richest_neighbour(s, E.HORDE, "ID_RIBELLE"), "ID_SUD1", "SUD1 (250) piu' ricca di EST (200)")
	t.assert_eq(EventProcessor.richest_neighbour(s, "FN_BETA", "ID_RIBELLE"), "ID_EST", "non quelle della fazione")
	t.assert_eq(EventProcessor.richest_neighbour(s, E.HORDE, "ID_NON_ESISTE"), "")
	s.province("ID_RIBELLE").owner = E.HORDE
	var army := W.land_army(s, E.HORDE, "ID_RIBELLE")
	t.assert_true(army.path.is_empty())
	s.year = 1231
	E.run_year(s)
	t.assert_eq(army.path, PackedStringArray(["ID_SUD1"]), "ordine di attacco alla confinante piu' ricca")
	army.path = PackedStringArray(["ID_EST"])
	E.run_year(s)
	t.assert_eq(army.path, PackedStringArray(["ID_EST"]), "chi sta gia' marciando continua")


func test_l_orda_nel_fine_anno_completo(t: TestContext) -> void:
	var s := E.world()
	s.year = 1229
	var res := TurnProcessor.end_year(s)
	t.assert_eq(res["errori"].size(), 0)
	res = TurnProcessor.end_year(s)
	t.assert_eq(res["errori"].size(), 0, str(res["errori"]))
	t.assert_eq(E.events_of(s, GameState.EV_HORDE_ARRIVES).size(), 1, "arrivata nell'anno 1230")
	t.assert_true(s.faction(E.HORDE).alive)


# --- salvataggi -------------------------------------------------------------------------


func _restore(s: GameState, data: Dictionary) -> GameState:
	var campaign := StartposLoader.load_file(E.STARTPOS)
	var units := UnitProdLoader.load_file(E.UNITS)
	var buildings := BuildingProdLoader.load_file(E.BUILDINGS)
	var rules := E.quiet_rules()
	rules.events = s.rules.events
	var r := SaveGame.from_dict(data, campaign, units, buildings, rules)
	return r["stato"]


func test_la_versione_del_salvataggio(t: TestContext) -> void:
	t.assert_true(SaveGame.VERSION >= 8, "gli eventi (6a) si salvano dalla versione 8; la 6b e' alla 9 (test_sim_victory.gd)")


func test_andata_e_ritorno_degli_eventi_attraverso_il_testo_json(t: TestContext) -> void:
	var s := _black_death_world()
	E.add_history(s, 9, 1346, 1346, EventRules.EFFECT_ZEAL, 10, "", ["ID_NORD1"])
	E.add_history(s, 10, 1340, 1360, EventRules.EFFECT_NONE)
	s.year = 1346
	E.run_year(s)
	s.province("ID_NORD1").add_temp_factor(ProvinceState.TEMP_FARM, 0.5)
	s.province("ID_NORD1").extra_goods.append("SPICES")
	t.assert_true(s.historical_done.has(54) and s.historical_done.has(9))
	t.assert_true(s.historical_years.has(10))
	s.faction(E.HORDE).alive = true
	s.horde = {"stato": "attiva", "arrivo": 1230, "ingresso": "ID_RIBELLE", "senza_conquiste": 4, "conquiste": 2}
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	var back := _restore(s, data)
	t.assert_eq(SaveGame.to_json(back), text, "stesso testo dopo l'andata e ritorno")
	t.assert_eq(back.historical_done, s.historical_done)
	t.assert_eq(back.historical_years, s.historical_years)
	t.assert_eq(typeof(back.historical_done.keys()[0]), TYPE_INT, "chiavi intere")
	t.assert_eq(back.black_death["colpite"], s.black_death["colpite"])
	t.assert_eq(typeof(back.black_death["anno"]), TYPE_INT)
	t.assert_eq(back.horde, s.horde)
	t.assert_eq(back.province("ID_NORD1").temp_factor(ProvinceState.TEMP_FARM), 0.5)
	t.assert_eq(back.province("ID_NORD1").extra_goods, PackedStringArray(["SPICES"]))
	# l'anno dopo e' identico nell'originale e nella copia
	EventProcessor.clear_temporary(s)
	EventProcessor.clear_temporary(back)
	s.year = 1347
	back.year = 1347
	E.run_year(s)
	E.run_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "il contagio continua uguale")


func test_salvataggi_vecchi_senza_eventi(t: TestContext) -> void:
	var s := E.world()
	var data: Dictionary = SaveGame.to_dict(s)
	data["versione"] = 7
	data.erase("eventi_6a")
	var campaign := StartposLoader.load_file(E.STARTPOS)
	var units := UnitProdLoader.load_file(E.UNITS)
	var buildings := BuildingProdLoader.load_file(E.BUILDINGS)
	var r := SaveGame.from_dict(data, campaign, units, buildings, E.quiet_rules())
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_true(back.historical_done.is_empty() and back.historical_years.is_empty())
	t.assert_true(back.black_death.is_empty() and back.horde.is_empty())
	var future := SaveGame.to_dict(s)
	future["versione"] = SaveGame.VERSION + 1
	var bad := SaveGame.from_dict(future, campaign, units, buildings, E.quiet_rules())
	t.assert_false(bool(bad["ok"]), "versione futura rifiutata")


func test_stato_degli_eventi_senza_dati(t: TestContext) -> void:
	var s := E.world()
	EventProcessor.load_data(s, "non un dizionario")
	t.assert_true(s.historical_done.is_empty() and s.black_death.is_empty() and s.horde.is_empty())
	EventProcessor.load_data(s, {"accaduti": {"3": 1100.0}, "anni": {"3": 1100.0, "x": 1}, "peste_nera": {"iniziata": true, "colpite": {"ID_ROMA": 2.0}}, "orda": {}})
	t.assert_eq(s.historical_done, {3: 1100})
	t.assert_eq(int(s.historical_years[3]), 1100)
	t.assert_eq(typeof(s.black_death["colpite"]["ID_ROMA"]), TYPE_INT)
	t.assert_true(s.horde.is_empty())
	var saved := EventProcessor.save_data(s)
	t.assert_eq(saved["accaduti"], {"3": 1100})


# --- testi ------------------------------------------------------------------------------


func test_titoli_e_testi_dal_file_di_prova(t: TestContext) -> void:
	var texts := EventTexts.load_file(MINI_EVENTS)
	t.assert_eq(texts.historical_count(), 3)
	t.assert_true(texts.has_historical(0) and texts.has_historical(2))
	t.assert_false(texts.has_historical(3))
	t.assert_false(texts.has_historical(-1))
	t.assert_eq(texts.historical_title(0), "Titolo zero")
	t.assert_eq(texts.historical_title(1), "Titolo uno", "il commento dopo l'elemento non conta")
	t.assert_eq(texts.historical_title(2), "Titolo due")
	t.assert_eq(texts.historical_title(3), "", "fuori limite")
	t.assert_true(texts.historical_text(0).begins_with("Testo zero"))
	t.assert_true(texts.historical_text(0).contains("su due righe"))
	t.assert_eq(texts.historical_text(2), "Testo due.")
	t.assert_eq(texts.historical_text(-1), "")


func test_messaggi_dei_disastri_dal_file_di_prova(t: TestContext) -> void:
	var texts := EventTexts.load_file(MINI_EVENTS)
	t.assert_eq(texts.disaster_message(GameState.EV_FLOOD, "Nord1"), "Prova di inondazione in Nord1.")
	t.assert_eq(texts.disaster_message(GameState.EV_FAMINE, "Est"), "Prova di carestia in Est.")
	t.assert_eq(texts.disaster_message(GameState.EV_QUAKE, "Roma"), "Prova di terremoto in Roma.")
	t.assert_eq(texts.disaster_message(GameState.EV_STORM, "Mare"), "Prova di tempesta in Mare.")
	t.assert_eq(texts.disaster_message(GameState.EV_PLAGUE, "Roma", 0), "Prima malattia in Roma.")
	t.assert_eq(texts.disaster_message(GameState.EV_PLAGUE, "Roma", 2), "Terza malattia in Roma.")
	t.assert_eq(texts.disaster_message(GameState.EV_PLAGUE, "Roma", 4), "Seconda malattia in Roma.", "le varianti girano")
	t.assert_eq(texts.disaster_message(GameState.EV_BLACK_DEATH, "Roma"), "Prova di Peste Nera ovunque, anche in Roma.")
	t.assert_eq(texts.disaster_message(GameState.EV_HISTORICAL, "Roma"), "", "non e' un disastro")
	t.assert_eq(texts.disaster_title(GameState.EV_FLOOD), "Inondazione")
	t.assert_eq(texts.disaster_title(GameState.EV_BLACK_DEATH), "La Peste Nera")
	t.assert_eq(texts.disaster_title(GameState.EV_FAMINE), "", "titolo mancante nel file di prova")
	var none := EventTexts.load_file("res://tests/fixtures/non_esiste.txt")
	t.assert_eq(none.historical_count(), 0, "file mancante: tabella vuota")
	t.assert_eq(none.historical_title(0), "")


# --- regioni immuni (Atlantide) ---------------------------------------------------------------------------------------
## Richiesta di Federico (2026-11-18): l'isola di Atlantide e' immune a tutti i disastri e agli eventi avversi tranne i
## terremoti, che restano poco frequenti (`[immuni]` di eventi.cfg: regioni, fattore_terremoto).


func test_regioni_immuni_ai_disastri(t: TestContext) -> void:
	var s := E.world()
	var ev := s.rules.events
	ev.immune_regions = PackedStringArray(["ID_NORD1"])
	ev.immune_quake_factor = 0.0
	ev.flood_chance = 1.0
	ev.famine_chance = 1.0
	ev.plague_chance = 1.0
	ev.plague_spread = 1.0
	ev.quake_chance = 1.0
	var p := s.province("ID_NORD1")
	p.loyalty = 80
	var men_before := 0
	for a in s.armies_in("ID_NORD1"):
		men_before += a.men_total()
	E.run_year(s)
	for kind in [GameState.EV_FLOOD, GameState.EV_FAMINE, GameState.EV_PLAGUE, GameState.EV_QUAKE]:
		t.assert_false(_province_ids(s, kind).has("ID_NORD1"), "%s non colpisce la regione immune" % kind)
		t.assert_true(not E.events_of(s, kind).is_empty(), "%s colpisce le altre" % kind)
	t.assert_eq(p.loyalty, 80, "niente carestia")
	t.assert_true(p.temp_effects.is_empty(), "nessun effetto temporaneo")
	var men_after := 0
	for a in s.armies_in("ID_NORD1"):
		men_after += a.men_total()
	t.assert_eq(men_after, men_before, "la peste non la raggiunge nemmeno dalle confinanti")


func test_regioni_immuni_hanno_terremoti_rari(t: TestContext) -> void:
	var s := E.world()
	var ev := s.rules.events
	ev.immune_regions = PackedStringArray(["ID_NORD1"])
	ev.immune_quake_factor = 1.0
	ev.quake_chance = 1.0
	E.run_year(s)
	t.assert_true(_province_ids(s, GameState.EV_QUAKE).has("ID_NORD1"), "i terremoti restano possibili")
	t.assert_eq(EventRules.new().immune_quake_factor, 0.25, "di norma un quarto della probabilita' comune")
	t.assert_true(ev.quake_chance_for("ID_NORD1") == 1.0 and ev.quake_chance_for("ID_ROMA") == 1.0)
	ev.immune_quake_factor = 0.25
	ev.quake_chance = 0.004
	t.assert_true(absf(ev.quake_chance_for("ID_NORD1") - 0.001) < 0.000001)
	t.assert_true(absf(ev.quake_chance_for("ID_ROMA") - 0.004) < 0.000001)


func test_la_peste_nera_non_entra_nelle_regioni_immuni(t: TestContext) -> void:
	var s := _black_death_world()
	s.rules.events.immune_regions = PackedStringArray(["ID_NORD1"])
	s.year = 1346
	E.run_year(s)
	var sick: Dictionary = s.black_death["colpite"]
	t.assert_false(sick.has("ID_NORD1"), "la regione immune non si contagia")
	for i in 6:
		s.year += 1
		E.run_year(s)
	t.assert_false(_province_ids(s, GameState.EV_PLAGUE).has("ID_NORD1"))


func test_eventi_storici_avversi_risparmiano_le_regioni_immuni(t: TestContext) -> void:
	var s := E.world()
	s.rules.events.immune_regions = PackedStringArray(["ID_NORD1"])
	var p := s.province("ID_NORD1")
	p.religions = {"CATHOLIC": 100.0, "ORTHODOX": 0.0, "MUSLIM": 0.0, "PAGAN": 0.0, "HERETIC": 0.0}
	E.add_history(s, 1, 1000, 1000, EventRules.EFFECT_HERETICS, 10, "", ["ID_NORD1"])
	var owner := p.owner
	s.rules.events.immune_regions.append(AgentProcessor.capital_of(s, owner))
	var treasury := s.faction(owner).treasury
	E.add_history(s, 2, 1000, 1000, EventRules.EFFECT_TREASURY, -500, owner)
	E.run_year(s)
	t.assert_eq(float(p.religions["HERETIC"]), 0.0, "niente eretici sull'isola")
	t.assert_eq(s.faction(owner).treasury, treasury, "niente perdite per la fazione con la capitale sull'isola")
