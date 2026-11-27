extends RefCounted
## Test della lealta' delle province (fase 4b, `ProvinceProcessor`, `ProvinceRules`) sul mondo di prova
## tests/fixtures/dynasty_*.txt: ALTA (capitale di ALPHA, cattolica) e BASSA (ortodossa, governata da un generale)
## sono di ALPHA, MEZZA e' di BETA, SOLA e' dei ribelli. Le situazioni si preparano a mano e i numeri si
## calcolano con i parametri di province.cfg (valori predefiniti uguali al file).
##
## Obiettivi del mondo di prova con il governatore di BASSA a terrore 3 e senza edifici di felicita':
##   ALTA   100 base + 25 guarnigione (160 uomini)                                             = 125
##   BASSA  100 + 12 (80 uomini) - 15 (religione ortodossa) - 3 (un passo dal capo) + 6 (terrore 3 x 2) = 100
##   MEZZA  100 + 9 (60 uomini)                                                                 = 109
##   SOLA   100 + 8 (50 uomini ribelli, senza tassa, religione e distanza)                       = 108

const STARTPOS := "res://tests/fixtures/dynasty_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const HEROES := "res://tests/fixtures/dynasty_heroes.txt"
const PLAIN_STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const RULES_FILE := "res://data/regole/province.cfg"


## Mondo senza sorteggi della fase 4b (`calm`), con il governatore di BASSA a terrore 3 e la lealta' al suo obiettivo.
func _world(seed_value: int = 7) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var rules := Rules.new()
	rules.province.calm()
	# Fase 5b: la partita nuova parte con 75/25 nelle province di religione diversa dal proprietario e la penalita' di
	# religione e' proporzionale (BASSA: -11). Questi test della 4b misurano le altre regole con la penalita' piena della
	# 4b (-15): ogni provincia parte tutta della religione della sua cultura. La regola nuova e' in test_sim_religion.gd.
	rules.religion.other_owner_share = 0
	# ADR-150: l'acume del governatore (termine nuovo) si misura a parte in test_governatore_terrore_e_acume_subito.
	rules.province.acumen_per_point = 0
	var s := GameSetup.new_game(campaign, units, buildings, rules, seed_value, HeroesLoader.load_file(HEROES))
	var governor := s.governor_of("ID_BASSA")
	governor.dread = 3
	governor.vnv = {}
	ProvinceProcessor.init_loyalty(s)
	return s


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _target(s: GameState, region_id: String) -> int:
	return int(ProvinceProcessor.loyalty_terms(s, s.province(region_id))["obiettivo"])


# --- parametri ---------------------------------------------------------------------------------------


func test_i_valori_predefiniti_sono_uguali_al_file(t: TestContext) -> void:
	var from_file := ProvinceRules.load_file(RULES_FILE)
	t.assert_eq(from_file.errors, PackedStringArray(), "province.cfg si legge senza errori")
	t.assert_eq(from_file.to_dict(), ProvinceRules.new().to_dict(), "il file e i valori predefiniti devono coincidere")
	var rules := Rules.load_file()
	t.assert_eq(rules.errors, PackedStringArray(), "tutti i file delle regole")
	t.assert_eq(rules.province.to_dict(), ProvinceRules.new().to_dict(), "Rules espone le regole delle province")
	t.assert_eq(rules.to_dict(), Rules.new().to_dict(), "Rules.to_dict comprende le province")
	t.assert_eq(Rules.new().to_dict()["province"], ProvinceRules.new().to_dict())


func test_file_assente_o_con_chiavi_sbagliate(t: TestContext) -> void:
	var missing := ProvinceRules.load_file("res://data/regole/non_esiste.cfg")
	t.assert_eq(missing.errors.size(), 1, "file assente: un errore")
	t.assert_eq(missing.to_dict(), ProvinceRules.new().to_dict(), "e valori predefiniti")
	var path := "user://province_prova.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("lealta", "base", 120)
	cfg.set_value("lealta", "deriva", 5.0)
	cfg.set_value("lealta", "termini_tassa", [])
	cfg.set_value("rivolta", "k_rivolta", "tanto")
	cfg.set_value("ribellione_regionale", "id_bassa", 30)
	t.assert_eq(cfg.save(path), OK)
	var loaded := ProvinceRules.load_file(path)
	DirAccess.remove_absolute(path)
	t.assert_eq(loaded.base, 120, "la chiave valida si legge")
	t.assert_eq(loaded.drift, 0.2, "deriva fuori da (0, 1]: predefinita")
	t.assert_eq(Array(loaded.tax_terms), [25, 10, 0, -10, -25], "termini della tassa vuoti: predefiniti")
	t.assert_eq(loaded.revolt_k, 0.01, "tipo sbagliato: predefinito")
	t.assert_eq(loaded.regional_rebels, {"ID_BASSA": 30}, "la tabella della sezione sostituisce quella predefinita, chiavi in maiuscolo")
	t.assert_true(loaded.errors.size() >= 2, "gli errori di coerenza sono segnalati")


func test_funzioni_dei_parametri(t: TestContext) -> void:
	var r := ProvinceRules.new()
	t.assert_eq(r.revolt_chance(100), 0.0, "alla soglia nessuna rivolta")
	t.assert_eq(r.revolt_chance(150), 0.0)
	t.assert_eq(r.revolt_chance(90), 0.1, "0,01 per punto mancante")
	t.assert_eq(r.revolt_chance(0), 0.5, "limitata a p_massima")
	t.assert_eq(r.tax_term(0), 25)
	t.assert_eq(r.tax_term(2), 0)
	t.assert_eq(r.tax_term(4), -25)
	t.assert_eq(r.tax_term(9), -25, "livello fuori scala: l'ultimo")
	t.assert_eq(r.regional_penalty("id_livonia"), 40)
	t.assert_eq(r.regional_penalty("ID_SCOTLAND"), 20)
	t.assert_eq(r.regional_penalty("ID_ALTA"), 0)
	r.regional_scale = 0.5
	t.assert_eq(r.regional_penalty("ID_LIVONIA"), 20)
	t.assert_eq(r.religion_of_culture("muslim_culture"), "REL_ISLAMIC")
	t.assert_eq(r.religion_of_culture("STRANA_CULTURE"), "")
	r.calm()
	t.assert_eq(r.revolt_chance(0), 0.0)
	t.assert_eq(r.spread_chance, 0.0)
	t.assert_eq(r.reemerge_chance, 0.0)
	t.assert_eq(r.civil_chance, 0.0)


# --- obiettivo -----------------------------------------------------------------------------------------


func test_termini_dell_obiettivo(t: TestContext) -> void:
	var s := _world()
	var alta := ProvinceProcessor.loyalty_terms(s, s.province("ID_ALTA"))
	t.assert_eq(alta["base"], 100)
	t.assert_eq(alta["tassa"], 0, "tassa normale")
	t.assert_eq(alta["uomini"], 160)
	t.assert_eq(alta["guarnigione"], 25, "+16 ogni 100 uomini, arrotondato per difetto")
	t.assert_eq(alta["edifici"], 0)
	t.assert_eq(alta["ribellione_regionale"], 0)
	t.assert_eq(alta["religione"], 0, "stessa religione")
	t.assert_eq(alta["passi"], 0)
	t.assert_eq(alta["distanza"], 0, "la capitale")
	t.assert_eq(alta["terrore"], 0, "senza governatore")
	t.assert_eq(alta["somma"], 125)
	t.assert_eq(alta["obiettivo"], 125)
	var bassa := ProvinceProcessor.loyalty_terms(s, s.province("ID_BASSA"))
	t.assert_eq(bassa["guarnigione"], 12)
	t.assert_eq(bassa["religione"], -15, "cultura ortodossa, fazione cattolica")
	t.assert_eq(bassa["passi"], 1)
	t.assert_eq(bassa["distanza"], -3)
	t.assert_eq(bassa["terrore"], 6, "terrore 3 del governatore x 2")
	t.assert_eq(bassa["obiettivo"], 100)
	t.assert_eq(_target(s, "ID_MEZZA"), 109, "BETA e' musulmana come la regione")
	t.assert_eq(_target(s, "ID_SOLA"), 108, "i ribelli: solo base e guarnigione")
	var sola := ProvinceProcessor.loyalty_terms(s, s.province("ID_SOLA"))
	t.assert_eq(sola["religione"], 0)
	t.assert_eq(sola["distanza"], 0)
	t.assert_eq(sola["terrore"], 0)
	t.assert_eq(sola["tassa"], 0)


func test_la_lealta_di_partenza_e_l_obiettivo(t: TestContext) -> void:
	var s := _world()
	for p in s.provinces:
		t.assert_eq(p.loyalty, _target(s, p.id), "%s parte dal suo obiettivo" % p.id)
		t.assert_eq(p.loyalty_owner, p.owner)
		t.assert_eq(int(p.last_loyalty["corrente"]), p.loyalty, "il dettaglio porta la lealta' corrente")
		t.assert_eq(int(p.last_loyalty["obiettivo"]), p.loyalty)
	t.assert_eq(s.province("ID_BASSA").former_owner, "")


func test_termine_della_tassa(t: TestContext) -> void:
	var s := _world()
	var expected := {0: 125, 1: 110, 2: 100, 3: 90, 4: 75}
	for level in expected:
		s.province("ID_BASSA").tax_level = level
		t.assert_eq(_target(s, "ID_BASSA"), int(expected[level]), "tassa %d" % level)


func test_guarnigione_con_limite_e_solo_del_proprietario(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	var spearmen := s.units.get_unit("Spearmen")
	var extra := s.create_army("FN_ALPHA", "ID_BASSA", false)
	extra.stacks.append(UnitStack.new(spearmen.id, 100, 0))
	t.assert_eq(ProvinceProcessor.garrison_men(s, bassa), 180)
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, bassa)["guarnigione"]), 28, "180 uomini: 28")
	for i in 5:
		var more := s.create_army("FN_ALPHA", "ID_BASSA", false)
		more.stacks.append(UnitStack.new(spearmen.id, 100, 0))
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, bassa)["guarnigione"]), 48, "limite del termine")
	# un esercito nemico non conta come guarnigione, una flotta non e' in provincia
	var enemy := s.create_army("FN_BETA", "ID_BASSA", false)
	enemy.stacks.append(UnitStack.new(spearmen.id, 100, 0))
	t.assert_eq(ProvinceProcessor.garrison_men(s, bassa), 680)
	var empty := s.province("ID_ALTA")
	for a in s.armies_in("ID_ALTA"):
		s.remove_army(a)
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, empty)["guarnigione"]), 0, "senza esercito niente guarnigione")
	t.assert_eq(_target(s, "ID_ALTA"), 100)


func test_edifici_e_ribellione_regionale(t: TestContext) -> void:
	var s := _world()
	# la colonna felicita' del file edifici: il livello costruito
	s.buildings.get_family("CHURCH").get_level(1).happiness = 20
	s.buildings.get_family("GOLD_MINE").get_level(2).happiness = 7
	s.province("ID_ALTA").set_level("CHURCH", 1)
	s.province("ID_ALTA").set_level("GOLD_MINE", 2)
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_ALTA"))["edifici"]), 27)
	t.assert_eq(_target(s, "ID_ALTA"), 152)
	# famiglie sconosciute o livelli oltre la tabella non contano
	s.province("ID_ALTA").set_level("INESISTENTE", 3)
	s.province("ID_ALTA").set_level("CHURCH", 9)
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_ALTA"))["edifici"]), 7)
	# ribellione regionale: tabella del catalogo, in punti
	# le felicita' impostate sopra valgono anche per gli edifici gia' presenti in BASSA: si confronta con
	# l'obiettivo prima della ribellione regionale invece di fissare un numero
	var bassa_before := _target(s, "ID_BASSA")
	s.rules.province.regional_rebels["ID_BASSA"] = 40
	var bassa := ProvinceProcessor.loyalty_terms(s, s.province("ID_BASSA"))
	t.assert_eq(bassa["ribellione_regionale"], -40)
	t.assert_eq(bassa["obiettivo"], bassa_before - 40)
	s.rules.province.regional_scale = 0.5
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_BASSA"))["ribellione_regionale"]), -20)


func test_religione_distanza_e_terrore(t: TestContext) -> void:
	var s := _world()
	var pr := s.rules.province
	# religione: se la fazione cambia culto la penalita' cambia lato
	s.campaign.faction("FN_ALPHA").religion = "REL_ORTHODOX"
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_BASSA"))["religione"]), 0, "ora BASSA ha la religione del proprietario")
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_ALTA"))["religione"]), -15, "e ALTA no")
	pr.religion_penalty = 4
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_ALTA"))["religione"]), -4)
	# distanza: passi di terra dalla regione del capo, con limite
	var leader := s.leader_of("FN_ALPHA")
	leader.army = 0
	leader.region = "ID_MEZZA"
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_ALTA"))["passi"]), 2, "MEZZA - BASSA - ALTA")
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_BASSA"))["distanza"]), -3)
	pr.distance_max = 1
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_ALTA"))["passi"]), 1, "limite di passi")
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_ALTA"))["distanza"]), -3)
	# senza capo nessuna distanza
	var gamma := s.province("ID_ALTA")
	DynastyProcessor.kill(s, leader, 1001, "vecchiaia", false)
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, gamma)["passi"]), 0)
	# terrore: solo del governatore della provincia, del proprietario
	var governor := s.governor_of("ID_BASSA")
	governor.dread = 9
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_BASSA"))["terrore"]), 18)
	governor.dread = 10
	pr.dread_per_point = 1
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_BASSA"))["terrore"]), 10)
	governor.faction = "FN_BETA"
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_BASSA"))["terrore"]), 0, "un governatore di un'altra fazione non conta")


func test_l_obiettivo_e_limitato(t: TestContext) -> void:
	var s := _world()
	s.province("ID_ALTA").tax_level = 0
	s.rules.province.base = 400
	t.assert_eq(_target(s, "ID_ALTA"), 200, "limite superiore")
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, s.province("ID_ALTA"))["somma"]), 450, "la somma resta visibile")
	s.rules.province.base = -400
	t.assert_eq(_target(s, "ID_ALTA"), 0, "limite inferiore")


# --- deriva e eventi --------------------------------------------------------------------------------------


func test_avvicinamento_all_obiettivo(t: TestContext) -> void:
	t.assert_eq(ProvinceProcessor.approach(50, 125, 0.2), 65, "il 20% del divario di 75")
	t.assert_eq(ProvinceProcessor.approach(150, 100, 0.2), 140)
	t.assert_eq(ProvinceProcessor.approach(99, 100, 0.2), 100, "almeno un punto")
	t.assert_eq(ProvinceProcessor.approach(101, 100, 0.2), 100)
	t.assert_eq(ProvinceProcessor.approach(100, 100, 0.2), 100)
	t.assert_eq(ProvinceProcessor.approach(0, 3, 1.0), 3, "mai oltre l'obiettivo")
	t.assert_eq(ProvinceProcessor.approach(10, 5, 1.0), 5)
	var s := _world()
	var alta := s.province("ID_ALTA")
	alta.loyalty = 50
	ProvinceProcessor.process_year(s)
	t.assert_eq(alta.loyalty, 65, "un anno di deriva verso 125")
	ProvinceProcessor.process_year(s)
	t.assert_eq(alta.loyalty, 77, "gap 60: 12 punti")
	t.assert_eq(int(alta.last_loyalty["corrente"]), 77)
	for i in 60:
		ProvinceProcessor.process_year(s)
	t.assert_eq(alta.loyalty, 125, "arriva all'obiettivo e ci resta")


func test_lealta_bassa_un_solo_evento(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	bassa.tax_level = 4          # obiettivo 75
	ProvinceProcessor.sync_loyalty(s, bassa)   # ADR-150: la tassa nuova e' gia' registrata, resta solo la deriva
	bassa.loyalty = 105
	s.events.clear()
	ProvinceProcessor.process_year(s)
	t.assert_eq(bassa.loyalty, 99, "105 -> 99 (gap 30: 6 punti)")
	var low := _events_of(s, GameState.EV_LOYALTY_LOW)
	t.assert_eq(low.size(), 1)
	if low.size() == 1:
		var e := low[0]
		t.assert_eq(e["fazione"], "FN_ALPHA")
		t.assert_eq(e["regione"], "ID_BASSA")
		t.assert_eq(e["provincia"], "ID_BASSA")
		t.assert_eq(e["lealta"], 99)
		t.assert_eq(e["obiettivo"], 75)
		t.assert_eq(e["soglia"], 100)
		t.assert_true(str(e["testo"]).contains("99"), "testo leggibile")
		t.assert_eq(e["anno"], 1000)
	t.assert_eq(int(bassa.counters["anni_sotto_soglia"]), 1)
	s.events.clear()
	ProvinceProcessor.process_year(s)
	t.assert_eq(_events_of(s, GameState.EV_LOYALTY_LOW).size(), 0, "l'evento esce solo al primo anno sotto la soglia")
	t.assert_eq(int(bassa.counters["anni_sotto_soglia"]), 2)
	# risale: il contatore riparte
	bassa.tax_level = 0
	bassa.loyalty = 99
	ProvinceProcessor.process_year(s)
	t.assert_true(bassa.loyalty >= 100)
	t.assert_eq(int(bassa.counters["anni_sotto_soglia"]), 0)


func test_le_province_dei_ribelli_non_segnalano_lealta_bassa(t: TestContext) -> void:
	var s := _world()
	var sola := s.province("ID_SOLA")
	sola.loyalty = 10
	s.events.clear()
	ProvinceProcessor.process_year(s)
	t.assert_eq(_events_of(s, GameState.EV_LOYALTY_LOW).size(), 0)
	t.assert_true(sola.loyalty > 10, "ma la lealta' si muove verso l'obiettivo")


# --- cambi di proprietario -----------------------------------------------------------------------------------


func test_passaggio_ai_ribelli_ricorda_l_ultimo_proprietario(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	var before := bassa.loyalty
	bassa.owner = GameState.REBEL
	ProvinceProcessor.process_year(s)
	t.assert_eq(bassa.loyalty_owner, GameState.REBEL)
	t.assert_eq(bassa.former_owner, "FN_ALPHA")
	t.assert_true(absi(bassa.loyalty - before) <= 20, "la lealta' non si azzera: segue la deriva")
	# un secondo passaggio tra i ribelli non cancella chi la possedeva
	ProvinceProcessor.process_year(s)
	t.assert_eq(bassa.former_owner, "FN_ALPHA")
	# i ribelli non hanno termini legati alla fazione
	var terms := ProvinceProcessor.loyalty_terms(s, bassa)
	t.assert_eq(terms["religione"], 0)
	t.assert_eq(terms["distanza"], 0)
	t.assert_eq(terms["terrore"], 0)


func test_conquista_limita_la_lealta(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	bassa.loyalty = 140
	bassa.owner = "FN_BETA"
	bassa.former_owner = "FN_ALPHA"
	ProvinceProcessor.process_year(s)
	t.assert_eq(bassa.loyalty_owner, "FN_BETA")
	t.assert_eq(bassa.former_owner, "", "una fazione vera non ha un ex proprietario")
	# parte da min(140, 70) = 70 e fa un anno di deriva verso 52 (100 - 15 religione - 3 distanza da BETA - 30
	# occupazione, ADR-070: BASSA era di ALPHA all'inizio e ALPHA e' viva)
	t.assert_eq(bassa.loyalty, 66, "al massimo lealta_conquista, poi la deriva")
	var terms := ProvinceProcessor.loyalty_terms(s, bassa)
	t.assert_eq(terms["religione"], -15, "BETA e' musulmana, BASSA ortodossa")
	t.assert_eq(terms["terrore"], 0, "il governatore e' di ALPHA")
	t.assert_eq(terms["occupazione"], -30, "ADR-070: tolta ad ALPHA, che e' viva")
	# lealta' piu' bassa del limite: resta
	var s2 := _world()
	var p2 := s2.province("ID_BASSA")
	p2.loyalty = 30
	p2.owner = "FN_BETA"
	ProvinceProcessor.process_year(s2)
	t.assert_true(p2.loyalty > 30 and p2.loyalty <= 70, "sotto il limite non si tocca, poi la deriva")


# --- mondi senza personaggi, salvataggi -------------------------------------------------------------------------


func test_mondo_senza_personaggi_non_fa_nulla(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(PLAIN_STARTPOS)
	var s := GameSetup.new_game(campaign, UnitProdLoader.load_file(UNITS), BuildingProdLoader.load_file(BUILDINGS), Rules.new(), 3)
	t.assert_true(s.characters.is_empty())
	var rng_before := s.rng.state
	var json_before := SaveGame.to_json(s)
	s.province("ID_BASSA").tax_level = 4
	var changed_before := SaveGame.to_json(s)
	ProvinceProcessor.process_year(s)
	t.assert_eq(s.rng.state, rng_before, "nessun sorteggio")
	t.assert_eq(SaveGame.to_json(s), changed_before, "nessun cambiamento")
	t.assert_true(json_before != changed_before)
	t.assert_eq(s.events.size(), 0)
	# la lealta' iniziale c'e' comunque
	for p in s.provinces:
		t.assert_true(p.loyalty > 0, "%s ha una lealta'" % p.id)


func test_lealta_nel_salvataggio(t: TestContext) -> void:
	var s := _world(9)
	s.province("ID_BASSA").tax_level = 4
	for i in 3:
		TurnProcessor.end_year(s)
	var bassa := s.province("ID_BASSA")
	bassa.former_owner = "FN_GAMMA"
	var data := SaveGame.to_dict(s)
	t.assert_eq(data["versione"], SaveGame.VERSION)
	var province_data: Dictionary = (data["province"] as Array)[1]
	t.assert_eq(province_data["id"], "ID_BASSA")
	t.assert_eq(province_data["lealta"], bassa.loyalty)
	t.assert_eq(province_data["ex_proprietario"], "FN_GAMMA")
	t.assert_eq(province_data["lealta_proprietario"], "FN_ALPHA")
	t.assert_true((province_data["contatori"] as Dictionary).has("anni_sotto_soglia") or bassa.loyalty >= 100)
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var back_data: Dictionary = parsed
	var r := SaveGame.from_dict(back_data, s.campaign, s.units, s.buildings, Rules.new(), s.heroes)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "andata e ritorno con lealta' e contatori")
	t.assert_eq(back.province("ID_BASSA").loyalty, bassa.loyalty)
	t.assert_eq(back.province("ID_BASSA").last_loyalty, bassa.last_loyalty)
	# l'anno dopo e' identico anche con i sorteggi attivi
	s.rules.province = ProvinceRules.new()
	back.rules.province = ProvinceRules.new()
	for i in 20:
		TurnProcessor.end_year(s)
		TurnProcessor.end_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "20 anni dopo il ricarico")


func test_i_salvataggi_della_versione_3_calcolano_la_lealta(t: TestContext) -> void:
	var s := _world(13)
	var data := SaveGame.to_dict(s)
	for version in [1, 2, 3]:
		var old := data.duplicate(true)
		old["versione"] = version
		var old_provinces: Array = old["province"]
		for item in old_provinces:
			var pd: Dictionary = item
			for key in ["lealta", "lealta_proprietario", "ex_proprietario", "contatori", "ultima_lealta"]:
				pd.erase(key)
			pd["tassa"] = 4 if str(pd["id"]) == "ID_BASSA" else 2
		if version < 3:
			for key in ["personaggi", "prossimo_personaggio", "contatori_reali", "eroi_apparsi"]:
				old.erase(key)
		var parsed: Variant = JSON.parse_string(JSON.stringify(old))
		var old_rules := Rules.new()
		old_rules.religion.other_owner_share = 0     # come _world (le versioni vecchie non hanno le religioni: partita nuova)
		old_rules.province.acumen_per_point = 0      # come _world (ADR-150)
		var r := SaveGame.from_dict(parsed, s.campaign, s.units, s.buildings, old_rules, s.heroes)
		t.assert_true(bool(r["ok"]), "v%d: %s" % [version, str(r["errore"])])
		if not bool(r["ok"]):
			continue
		var loaded: GameState = r["stato"]
		t.assert_eq(loaded.province("ID_BASSA").loyalty, _target(loaded, "ID_BASSA"), "v%d: la lealta' parte dall'obiettivo" % version)
		t.assert_eq(loaded.province("ID_ALTA").loyalty, 125, "v%d" % version)
		if version == 3:
			t.assert_eq(loaded.province("ID_BASSA").loyalty, 75, "v3: governatore a terrore 3, tassa massima (100 - 25)")
		t.assert_eq(loaded.province("ID_BASSA").loyalty_owner, "FN_ALPHA")
		t.assert_eq(SaveGame.to_dict(loaded)["versione"], SaveGame.VERSION, "si riscrive nella versione corrente")


# --- ADR-150: leve immediate ------------------------------------------------------------------------------


## Richiesta di Federico del 27/11/2026: alzando la tassa l'effetto sulla lealta' si vede subito, e il fine anno non lo
## conta una seconda volta.
func test_la_tassa_pesa_subito(t: TestContext) -> void:
	var s := _world()
	var alta := s.province("ID_ALTA")
	t.assert_eq(alta.loyalty, 125, "partenza all'obiettivo (tassa normale)")
	var r := GameCommands.set_tax(s, "FN_ALPHA", "ID_ALTA", 4)
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_eq(alta.loyalty, 100, "125 - 25 subito")
	t.assert_eq(int(alta.last_loyalty["tassa"]), -25, "dettaglio aggiornato")
	t.assert_eq(int(CampaignUiText.loyalty_status(s, alta)["valore"]), 100, "la scheda mostra il valore nuovo")
	ProvinceProcessor.process_year(s)
	t.assert_eq(alta.loyalty, 100, "gia' all'obiettivo: nessun doppio calo")
	GameCommands.set_tax(s, "FN_ALPHA", "ID_ALTA", 0)
	t.assert_eq(alta.loyalty, 150, "tassa minima: +50 rispetto alla massima")


## Una leva cambiata fuori dai comandi (truppe entrate o uscite, tassa toccata dall'IA) si vede nell'anteprima e conta a
## fine anno, prima della deriva del resto.
func test_le_leve_cambiate_contano_a_fine_anno(t: TestContext) -> void:
	var s := _world()
	var alta := s.province("ID_ALTA")
	alta.tax_level = 4
	var live := ProvinceProcessor.live_loyalty(s, alta)
	t.assert_eq(int(live["variazione_immediata"]), -25)
	t.assert_eq(int(live["corrente"]), 100)
	t.assert_eq(alta.loyalty, 125, "l'anteprima non cambia lo stato")
	t.assert_eq(int(CampaignUiText.loyalty_status(s, alta)["variazione"]), -25)
	ProvinceProcessor.process_year(s)
	t.assert_eq(alta.loyalty, 100)
	var extra := s.create_army("FN_ALPHA", "ID_ALTA", false)
	t.assert_true(extra != null, "esercito in piu'")
	t.assert_eq(alta.loyalty, 100, "la guarnigione non muta lo stato prima del fine anno")


## Terrore e acume del governatore (acume: termine nuovo, PROVVISORIO) contano subito quando lo si nomina o lo si revoca.
func test_governatore_terrore_e_acume_subito(t: TestContext) -> void:
	var s := _world()
	s.rules.province.acumen_per_point = 1
	var bassa := s.province("ID_BASSA")
	var governor := s.governor_of("ID_BASSA")
	governor.acumen = 4
	ProvinceProcessor.sync_loyalty(s, bassa)
	var terms := ProvinceProcessor.loyalty_terms(s, bassa)
	var acumen := governor.effective(Character.ATTR_ACUMEN, s.rules, s.campaign)
	t.assert_eq(int(terms["acume"]), acumen, "un punto di lealta' per punto di acume")
	t.assert_eq(CampaignUiText.governor_loyalty_effect(s, governor), int(terms["terrore"]) + int(terms["acume"]))
	t.assert_true(CampaignUiText.governor_option_text(s, governor, true).contains(" · provincia +"), CampaignUiText.governor_option_text(s, governor, true))
	var before := bassa.loyalty
	var r := GameCommands.revoke_title(s, "FN_ALPHA", governor.id)
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_eq(bassa.loyalty, before - int(terms["terrore"]) - int(terms["acume"]), "senza governatore si perdono subito")
	r = GameCommands.assign_title(s, "FN_ALPHA", governor.id, "ID_BASSA")
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_eq(bassa.loyalty, before, "di nuovo governata: torna com'era")
