extends RefCounted
## Test della religione (fase 5b): parametri (ReligionRules, data/regole/religione.cfg), composizione religiosa delle
## province (somma sempre 100), partita nuova, spostamenti, deriva, edifici, religiosi, zelo, eresia, inquisitori,
## penalita' di lealta' proporzionale, rivolta eretica, salvataggi. Mondo di prova: vedi agent_world.gd.
##   ALTA (ALPHA cattolica, cultura cattolica) 100% cattolica; BASSA (ALPHA, cultura ortodossa) 75% ortodossa e 25%
##   cattolica; MEZZA (BETA musulmana, cultura musulmana) 100% musulmana; SOLA (ribelli, cultura pagana) 100% pagana;
##   ORTO (GAMMA cattolica, cultura cattolica) 100% cattolica. Lo zelo parte da 50.
## I calcoli a mano usano i parametri predefiniti (uguali a religione.cfg). La lealta' delle province si porta a 150
## (`_world`) per spegnere la crescita dell'eresia, che i test dell'eresia riaccendono.

const W := preload("res://tests/unit/agent_world.gd")
const RULES_FILE := "res://data/regole/religione.cfg"
const C := ProvinceState.CATHOLIC
const O := ProvinceState.ORTHODOX
const M := ProvinceState.MUSLIM
const P := ProvinceState.PAGAN
const H := ProvinceState.HERETIC


func _world() -> GameState:
	var s := W.world()
	for p in s.provinces:
		p.loyalty = 150
	return s


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.000001


## Composizione valida: somma esatta 100, ogni valore in [0, 100] e multiplo del passo, zelo in [0, 100].
func _check_valid(t: TestContext, p: ProvinceState, label: String) -> void:
	t.assert_eq(p.religions_sum(), 100.0, "%s: %s somma 100 (%s)" % [label, p.id, str(p.religions)])
	for k in ProvinceState.RELIGIONS:
		var v := p.religion_pct(k)
		t.assert_true(v >= 0.0 and v <= 100.0, "%s: %s %s fuori da [0, 100] (%s)" % [label, p.id, k, str(v)])
		t.assert_eq(fposmod(v, ProvinceState.RELIGION_UNIT), 0.0, "%s: %s %s non e' multiplo del passo (%s)" % [label, p.id, k, str(v)])
	t.assert_true(p.zeal >= 0 and p.zeal <= 100, "%s: %s zelo %d fuori da [0, 100]" % [label, p.id, p.zeal])


func _set_mix(p: ProvinceState, values: Dictionary) -> void:
	p.religions = ProvinceState.normalize_religions(values)


func _year(s: GameState) -> void:
	ReligionProcessor.process_year(s)


# --- parametri ---------------------------------------------------------------------------------------


func test_i_valori_predefiniti_sono_uguali_al_file(t: TestContext) -> void:
	var from_file := ReligionRules.load_file(RULES_FILE)
	t.assert_eq(from_file.errors, PackedStringArray(), "religione.cfg si legge senza errori")
	t.assert_eq(from_file.to_dict(), ReligionRules.new().to_dict(), "il file e i valori predefiniti devono coincidere")
	var rules := Rules.load_file()
	t.assert_eq(rules.errors, PackedStringArray(), "tutti i file delle regole")
	t.assert_eq(rules.religion.to_dict(), ReligionRules.new().to_dict(), "Rules espone la religione")
	t.assert_eq(rules.to_dict(), Rules.new().to_dict(), "Rules.to_dict comprende la religione")
	t.assert_eq(Rules.new().to_dict()["religion"], ReligionRules.new().to_dict())


func test_i_parametri_della_specifica(t: TestContext) -> void:
	var r := ReligionRules.new()
	t.assert_eq(r.other_owner_share, 25)
	t.assert_eq(r.initial_zeal, 50)
	t.assert_eq(r.drift, 1.0)
	t.assert_eq(r.building_points, 1.0)
	t.assert_eq(r.big_building_points, 1.5)
	t.assert_eq(r.agent_points, 2.0)
	t.assert_eq(r.big_agent_points, 5.0)
	t.assert_eq(r.zeal_decay, 1)
	t.assert_eq(r.neutral_zeal, 50)
	t.assert_eq(r.heresy_growth, 1.0)
	t.assert_eq(r.heresy_tax_level, 3)
	t.assert_eq(r.heretic_revolt_threshold, 30.0)
	t.assert_eq(r.heretic_revolt_factor, 2.0)
	t.assert_eq(r.inquisitor_points, 3.0)
	t.assert_eq(r.grand_inquisitor_points, 6.0)
	t.assert_eq(r.inactive_malus, 3)
	t.assert_eq(r.trial_base, 0.3)
	t.assert_eq(r.trial_k_piety, 0.08)
	t.assert_true(_near(r.trial_chance(5), 0.3), "pieta' 5: la base")
	t.assert_true(_near(r.trial_chance(0), 0.7), "pieta' 0: 0,3 + 0,08 x 5")
	t.assert_true(_near(r.trial_chance(10), 0.05), "limite inferiore")
	t.assert_true(_near(r.trial_chance(-5), 0.9), "limite superiore")


func test_file_mancante_o_con_valori_fuori_scala(t: TestContext) -> void:
	var missing := ReligionRules.load_file("res://data/regole/non_esiste.cfg")
	t.assert_eq(missing.errors.size(), 1, "un errore di lettura")
	t.assert_eq(missing.drift, 1.0, "valori predefiniti")
	var path := "user://test_religione.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("deriva", "deriva", 2.5)
	cfg.set_value("composizione", "quota_religione_proprietario", 500)
	cfg.set_value("processo", "p_min_processo", 0.8)
	cfg.set_value("processo", "p_max_processo", 0.2)
	cfg.set_value("religiosi", "tipi_grandi", ["ulama"])
	cfg.set_value("religione_tipo", "priest", "orthodox")
	t.assert_eq(cfg.save(path), OK, "scrittura del file di prova")
	var r := ReligionRules.load_file(path)
	DirAccess.remove_absolute(path)
	t.assert_eq(r.errors.size(), 2, "quota fuori scala e probabilita' incoerenti: %s" % str(r.errors))
	t.assert_eq(r.drift, 2.5)
	t.assert_eq(r.other_owner_share, 25, "ripristinata")
	t.assert_true(_near(r.trial_p_min, 0.05) and _near(r.trial_p_max, 0.9), "ripristinate")
	t.assert_eq(r.big_agent_types, PackedStringArray(["ULAMA"]), "maiuscolo")
	t.assert_eq(r.type_religion, {"PRIEST": "ORTHODOX"}, "la tabella della sezione sostituisce quella predefinita")


func test_lettura_delle_colonne_di_unit_prod(t: TestContext) -> void:
	var listed := ReligionRules.parse_points("PAGAN(0), CATHOLIC(2), ORTHODOX(0), ISLAMIC(0), JEWISH(0), HERETIC(0)")
	t.assert_eq(listed, {"CATHOLIC": 2.0}, "solo i valori maggiori di zero")
	t.assert_eq(ReligionRules.parse_points("\"ISLAMIC(5)\""), {"MUSLIM": 5.0}, "ISLAMIC e' MUSLIM; virgolette ignorate")
	t.assert_eq(ReligionRules.parse_points("PAGAN(3)"), {"PAGAN": 3.0})
	t.assert_eq(ReligionRules.parse_points("CATHOLIC(2.5), JEWISH(9), REL_PAGAN(1), rotto, ORTHODOX(x), (4)"), {"CATHOLIC": 2.5, "PAGAN": 1.0}, "il resto si ignora")
	t.assert_eq(ReligionRules.parse_points(""), {})
	t.assert_eq(ReligionRules.religion_key("REL_ISLAMIC"), "MUSLIM")
	t.assert_eq(ReligionRules.religion_key("jewish"), "")


# --- composizione: normalizzazione e spostamenti ---------------------------------------------------------------


func test_normalizzazione_a_cento(t: TestContext) -> void:
	var n := ProvinceState.normalize_religions({"CATHOLIC": 1, "ORTHODOX": 1, "MUSLIM": 1})
	t.assert_eq(n["CATHOLIC"], 33.5, "il passo avanzato va al maggior resto, a parita' alla prima religione")
	t.assert_eq(n["ORTHODOX"], 33.25)
	t.assert_eq(n["MUSLIM"], 33.25)
	t.assert_eq(n["PAGAN"], 0.0)
	t.assert_eq(n["HERETIC"], 0.0)
	t.assert_eq(ProvinceState.normalize_religions({}), {"CATHOLIC": 0.0, "ORTHODOX": 0.0, "MUSLIM": 0.0, "PAGAN": 100.0, "HERETIC": 0.0, "IMPERIAL": 0.0, "DHARMA": 0.0}, "somma zero: tutta pagana")
	t.assert_eq(ProvinceState.normalize_religions({"CATHOLIC": -5, "PAGAN": "x"})["PAGAN"], 100.0, "negativi e testo valgono zero")
	var half := ProvinceState.normalize_religions({"CATHOLIC": 30, "PAGAN": 30})
	t.assert_eq(half["CATHOLIC"], 50.0)
	t.assert_eq(half["PAGAN"], 50.0)
	var exact := {"CATHOLIC": 25.0, "ORTHODOX": 75.0, "MUSLIM": 0.0, "PAGAN": 0.0, "HERETIC": 0.0, "IMPERIAL": 0.0, "DHARMA": 0.0}
	t.assert_eq(ProvinceState.normalize_religions(exact), exact, "una composizione valida non cambia")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 300:
		var values := {}
		for k in ProvinceState.RELIGIONS:
			values[k] = rng.randf_range(0.0, 50.0) if rng.randf() < 0.7 else 0
		var d := ProvinceState.normalize_religions(values)
		var sum := 0.0
		for k in ProvinceState.RELIGIONS:
			sum += float(d[k])
			t.assert_eq(fposmod(float(d[k]), ProvinceState.RELIGION_UNIT), 0.0, "multiplo del passo")
		t.assert_eq(sum, 100.0, "somma esatta: %s" % str(d))


func test_spostamento_in_proporzione(t: TestContext) -> void:
	var p := ProvinceState.new("ID_X", "FN_ALPHA")
	_set_mix(p, {"CATHOLIC": 25, "ORTHODOX": 75})
	t.assert_eq(ReligionProcessor.shift(p, M, 1.0), 1.0, "punti spostati")
	t.assert_eq(p.religion_pct(M), 1.0)
	t.assert_eq(p.religion_pct(C), 24.75, "1 punto in proporzione: 0,25 tolto ai cattolici")
	t.assert_eq(p.religion_pct(O), 74.25, "e 0,75 agli ortodossi")
	t.assert_eq(p.religions_sum(), 100.0)
	# resto: 4 passi su 104 e 296 danno 1,04 e 2,96: il passo avanzato va al resto piu' grande
	_set_mix(p, {"CATHOLIC": 26, "ORTHODOX": 74})
	ReligionProcessor.shift(p, M, 1.0)
	t.assert_eq(p.religion_pct(C), 25.75)
	t.assert_eq(p.religion_pct(O), 73.25)
	t.assert_eq(p.religion_pct(M), 1.0)
	t.assert_eq(p.religions_sum(), 100.0)


func test_spostamento_limitato_e_con_fonti(t: TestContext) -> void:
	var p := ProvinceState.new("ID_X", "FN_ALPHA")
	_set_mix(p, {"CATHOLIC": 100})
	t.assert_eq(ReligionProcessor.shift(p, O, 150.0), 100.0, "non si sposta piu' di quanto c'e'")
	t.assert_eq(p.religion_pct(O), 100.0)
	t.assert_eq(p.religion_pct(C), 0.0)
	t.assert_eq(ReligionProcessor.shift(p, O, 5.0), 0.0, "nessuna altra religione da cui togliere")
	t.assert_eq(p.religion_pct(O), 100.0)
	_set_mix(p, {"CATHOLIC": 50, "ORTHODOX": 25, "HERETIC": 25})
	t.assert_eq(ReligionProcessor.shift(p, M, 10.0, [H]), 10.0)
	t.assert_eq(p.religion_pct(H), 15.0, "solo dalla fonte indicata")
	t.assert_eq(p.religion_pct(C), 50.0)
	t.assert_eq(ReligionProcessor.shift(p, M, 10.0, [P]), 0.0, "la fonte e' vuota")
	t.assert_eq(ReligionProcessor.shift(p, "ALTRO", 10.0), 0.0, "religione sconosciuta")
	# il passo e' 0,25: 0,1 non sposta nulla, 0,3 un passo
	t.assert_eq(ReligionProcessor.shift(p, M, 0.1), 0.0)
	t.assert_eq(ReligionProcessor.shift(p, M, 0.3), 0.25)


func test_spostamenti_casuali_tengono_la_somma(t: TestContext) -> void:
	var p := ProvinceState.new("ID_X", "FN_ALPHA")
	_set_mix(p, {"CATHOLIC": 40, "ORTHODOX": 30, "MUSLIM": 10, "PAGAN": 10, "HERETIC": 10})
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 500:
		var to: String = ProvinceState.RELIGIONS[rng.randi_range(0, 4)]
		var sources: Array = []
		if rng.randf() < 0.3:
			sources.append(ProvinceState.RELIGIONS[rng.randi_range(0, 4)])
		ReligionProcessor.shift(p, to, rng.randf_range(0.0, 12.0), sources)
		_check_valid(t, p, "spostamento %d" % i)
		if t.failed:
			return


# --- partita nuova ------------------------------------------------------------------------------------------------


func test_composizione_della_partita_nuova(t: TestContext) -> void:
	var s := W.world()
	var alta := s.province(W.ALTA)
	t.assert_eq(alta.religion_pct(C), 100.0, "cultura e proprietario cattolici")
	var bassa := s.province(W.BASSA)
	t.assert_eq(bassa.religion_pct(O), 75.0, "cultura ortodossa, proprietario cattolico: 75%")
	t.assert_eq(bassa.religion_pct(C), 25.0, "e 25% alla religione del proprietario")
	t.assert_eq(s.province(W.MEZZA).religion_pct(M), 100.0)
	t.assert_eq(s.province(W.SOLA).religion_pct(P), 100.0, "ribelli: la religione della cultura")
	t.assert_eq(s.province(W.ORTO).religion_pct(C), 100.0)
	for p in s.provinces:
		t.assert_eq(p.zeal, 50, "zelo iniziale di %s" % p.id)
		_check_valid(t, p, "partita nuova")


func test_composizione_con_parametri_e_dati_mancanti(t: TestContext) -> void:
	var s := W.world()
	s.rules.religion.other_owner_share = 40
	s.rules.religion.initial_zeal = 60
	ReligionProcessor.init_religions(s)
	t.assert_eq(s.province(W.BASSA).religion_pct(O), 60.0)
	t.assert_eq(s.province(W.BASSA).religion_pct(C), 40.0)
	t.assert_eq(s.province(W.BASSA).zeal, 60)
	# cultura sconosciuta: tutta la religione del proprietario; anche questa sconosciuta: tutta pagana
	s.campaign.region(W.ALTA).culture = "STRANA_CULTURE"
	ReligionProcessor.init_religions(s)
	t.assert_eq(s.province(W.ALTA).religion_pct(C), 100.0)
	s.campaign.faction(W.A).religion = ""
	ReligionProcessor.init_religions(s)
	t.assert_eq(s.province(W.ALTA).religion_pct(P), 100.0)
	t.assert_eq(s.province(W.BASSA).religion_pct(O), 100.0, "proprietario senza religione: quella della cultura")
	for p in s.provinces:
		_check_valid(t, p, "dati mancanti")


func test_religione_del_proprietario(t: TestContext) -> void:
	var s := W.world()
	t.assert_eq(ReligionProcessor.owner_religion(s, s.province(W.ALTA)), C)
	t.assert_eq(ReligionProcessor.owner_religion(s, s.province(W.MEZZA)), M, "REL_ISLAMIC e' MUSLIM")
	t.assert_eq(ReligionProcessor.owner_religion(s, s.province(W.SOLA)), "", "i ribelli non ne hanno")


# --- deriva ------------------------------------------------------------------------------------------------------


func test_deriva_verso_la_religione_del_proprietario(t: TestContext) -> void:
	var s := _world()
	_year(s)
	var bassa := s.province(W.BASSA)
	t.assert_eq(bassa.religion_pct(C), 26.0, "un punto all'anno dalle altre alla religione del proprietario")
	t.assert_eq(bassa.religion_pct(O), 74.0)
	for id in [W.ALTA, W.MEZZA, W.ORTO]:
		t.assert_eq(s.province(id).religion_pct(s.province(id).majority_religion()), 100.0, "%s resta com'e'" % id)
	t.assert_eq(s.province(W.SOLA).religion_pct(P), 100.0, "i ribelli non hanno deriva")
	for i in 80:
		_year(s)
	t.assert_eq(bassa.religion_pct(C), 100.0, "arriva al 100% e ci resta")
	t.assert_eq(bassa.religion_pct(O), 0.0)
	for p in s.provinces:
		_check_valid(t, p, "deriva")
	s.rules.religion.drift = 0.0
	_set_mix(bassa, {"ORTHODOX": 100})
	_year(s)
	t.assert_eq(bassa.religion_pct(O), 100.0, "deriva zero: niente")


func test_gli_eretici_di_un_proprietario_cattolico_non_derivano(t: TestContext) -> void:
	var s := _world()
	var alta := s.province(W.ALTA)
	_set_mix(alta, {"CATHOLIC": 90, "HERETIC": 10})
	_year(s)
	t.assert_eq(alta.religion_pct(H), 10.0, "l'eresia si spegne con inquisitori e religiosi, non da sola")
	t.assert_eq(alta.religion_pct(C), 90.0)
	# con un proprietario di un'altra religione gli eretici derivano come le altre
	var mezza := s.province(W.MEZZA)
	_set_mix(mezza, {"MUSLIM": 90, "HERETIC": 10})
	_year(s)
	t.assert_eq(mezza.religion_pct(M), 91.0)
	t.assert_eq(mezza.religion_pct(H), 9.0)


# --- edifici -----------------------------------------------------------------------------------------------------


func test_edifici_religiosi_convertono(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province(W.BASSA)
	bassa.set_level("CHURCH", 1)
	_year(s)
	t.assert_eq(bassa.religion_pct(C), 26.0, "senza propagazione della fede (colonna 21) l'edificio non converte")
	# chiesa: propagazione 0,1 = edificio normale (+1); la religione e' quella del proprietario tra quelle dell'edificio
	s.buildings.get_family("CHURCH").get_level(1).faith = 0.1
	_set_mix(bassa, {"CATHOLIC": 25, "ORTHODOX": 75})
	_year(s)
	t.assert_eq(bassa.religion_pct(C), 27.0, "deriva +1 e chiesa +1")
	t.assert_eq(bassa.religion_pct(O), 73.0)
	# propagazione 0,15 = edificio grande (+1,5)
	s.buildings.get_family("CHURCH").get_level(1).faith = 0.15
	_set_mix(bassa, {"CATHOLIC": 25, "ORTHODOX": 75})
	_year(s)
	t.assert_eq(bassa.religion_pct(C), 27.5, "deriva +1 e edificio grande +1,5")
	t.assert_eq(bassa.religion_pct(O), 72.5)
	# i parametri comandano
	s.rules.religion.big_building_points = 3.0
	_set_mix(bassa, {"CATHOLIC": 25, "ORTHODOX": 75})
	_year(s)
	t.assert_eq(bassa.religion_pct(C), 29.0)
	_check_valid(t, bassa, "edifici")


func test_un_edificio_di_un_altro_culto_converte_al_suo(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province(W.BASSA)
	bassa.set_level("MOSQUE", 1)
	s.buildings.get_family("MOSQUE").get_level(1).faith = 0.1
	_year(s)
	t.assert_eq(bassa.religion_pct(M), 1.0, "una moschea in mano cattolica converte comunque all'islam")
	t.assert_eq(bassa.religion_pct(C), 25.75, "dopo la deriva (26 e 74) il punto viene tolto in proporzione")
	t.assert_eq(bassa.religion_pct(O), 73.25)
	t.assert_eq(bassa.religions_sum(), 100.0)
	# una chiesa in una provincia musulmana: il proprietario non e' tra le religioni dell'edificio, vale la prima
	var mezza := s.province(W.MEZZA)
	mezza.set_level("CHURCH", 1)
	s.buildings.get_family("CHURCH").get_level(1).faith = 0.1
	_year(s)
	t.assert_eq(mezza.religion_pct(C), 1.0)
	t.assert_eq(mezza.religion_pct(M), 99.0)
	# un edificio senza religioni (il castello) non converte anche se ha una propagazione
	var alta := s.province(W.ALTA)
	_set_mix(alta, {"MUSLIM": 100})
	s.buildings.get_family("CASTLE").get_level(1).faith = 0.1
	_year(s)
	t.assert_eq(alta.religion_pct(C), 1.0, "solo la deriva: il castello non converte")


# --- religiosi ---------------------------------------------------------------------------------------------------


func test_religiosi_convertono_la_provincia(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province(W.BASSA)
	var bishop := W.add_agent(s, W.A, W.BASSA, "BISHOP", 1)
	t.assert_eq(ReligionProcessor.agent_conversion(s, bishop), {"CATHOLIC": 2.0}, "vescovo: +2 (parametro, il file di prova non ha la colonna 45)")
	_year(s)
	t.assert_eq(bassa.religion_pct(C), 28.0, "deriva +1 e vescovo +2")
	t.assert_eq(bassa.religion_pct(O), 72.0)
	s.agents.erase(bishop)
	var cardinal := W.add_agent(s, W.A, W.BASSA, "CARDINAL", 1)
	t.assert_eq(ReligionProcessor.agent_conversion(s, cardinal), {"CATHOLIC": 5.0}, "cardinale: +5")
	_set_mix(bassa, {"CATHOLIC": 25, "ORTHODOX": 75})
	_year(s)
	t.assert_eq(bassa.religion_pct(C), 31.0)
	_check_valid(t, bassa, "religiosi")


func test_i_religiosi_convertono_anche_in_province_altrui(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province(W.BASSA)
	var mullah := W.add_agent(s, W.B, W.BASSA, "MULLAH", 1)
	t.assert_eq(ReligionProcessor.agent_religion(s, mullah), M)
	_year(s)
	t.assert_eq(bassa.religion_pct(M), 2.0, "un mullah musulmano in una provincia cattolica converte all'islam")
	t.assert_eq(bassa.religion_pct(C), 25.5)
	t.assert_eq(bassa.religion_pct(O), 72.5)
	t.assert_eq(bassa.religions_sum(), 100.0)
	# il sacerdote non ha una religione propria: quella della sua fazione
	var priest := W.add_agent(s, W.B, W.ALTA, "PRIEST", 1)
	t.assert_eq(ReligionProcessor.agent_religion(s, priest), M)
	_year(s)
	t.assert_eq(s.province(W.ALTA).religion_pct(M), 2.0)
	t.assert_eq(s.province(W.ALTA).religion_pct(C), 98.0)
	var alpha_priest := W.add_agent(s, W.A, W.ALTA, "PRIEST", 1)
	t.assert_eq(ReligionProcessor.agent_religion(s, alpha_priest), C)


func test_la_colonna_45_comanda(t: TestContext) -> void:
	var s := _world()
	var unit := s.units.get_unit("Bishop")
	var raw := unit.raw
	raw[ReligionProcessor.COL_CONVERSION] = "ORTHODOX(3)"
	unit.raw = raw
	var bishop := W.add_agent(s, W.A, W.BASSA, "BISHOP", 1)
	t.assert_eq(ReligionProcessor.agent_conversion(s, bishop), {"ORTHODOX": 3.0}, "la religione e i punti vengono dalla colonna")
	t.assert_eq(ReligionProcessor.agent_religion(s, bishop), O)
	_year(s)
	var bassa := s.province(W.BASSA)
	t.assert_eq(bassa.religion_pct(O), 77.0, "74 dopo la deriva, +3 dal vescovo")
	t.assert_eq(bassa.religion_pct(C), 23.0)


func test_gli_inquisitori_e_gli_altri_agenti_non_convertono(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(ReligionProcessor.agent_conversion(s, W.add_agent(s, W.A, W.BASSA, "INQUISITOR", 1)), {})
	t.assert_eq(ReligionProcessor.agent_conversion(s, W.add_agent(s, W.A, W.BASSA, "GRAND_INQUISITOR", 1)), {})
	t.assert_eq(ReligionProcessor.agent_conversion(s, W.add_agent(s, W.A, W.BASSA, "SPY", 1)), {})
	t.assert_eq(ReligionProcessor.agent_conversion(s, W.agent_of(s, W.A, AgentState.EMISSARY)), {})
	_year(s)
	t.assert_eq(s.province(W.BASSA).religion_pct(C), 26.0, "solo la deriva")


# --- zelo --------------------------------------------------------------------------------------------------------


func test_lo_zelo_torna_verso_il_valore_neutro(t: TestContext) -> void:
	var s := _world()
	var alta := s.province(W.ALTA)
	_year(s)
	t.assert_eq(alta.zeal, 50)
	alta.zeal = 80
	_year(s)
	t.assert_eq(alta.zeal, 79)
	alta.zeal = 20
	_year(s)
	t.assert_eq(alta.zeal, 21)
	alta.zeal = 51
	_year(s)
	t.assert_eq(alta.zeal, 50, "non oltre il valore neutro")
	s.rules.religion.zeal_decay = 10
	alta.zeal = 55
	_year(s)
	t.assert_eq(alta.zeal, 50)


func test_lo_zelo_sale_con_religiosi_e_inquisitori(t: TestContext) -> void:
	var s := _world()
	var alta := s.province(W.ALTA)
	var bishop := W.add_agent(s, W.A, W.ALTA, "BISHOP", 1)
	_year(s)
	t.assert_eq(alta.zeal, 52, "vescovo: +2")
	s.agents.erase(bishop)
	alta.zeal = 50
	W.add_agent(s, W.A, W.ALTA, "CARDINAL", 1)
	_year(s)
	t.assert_eq(alta.zeal, 55, "cardinale: +5")
	alta.zeal = 50
	s.agents.clear()
	W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 1)
	_year(s)
	t.assert_eq(alta.zeal, 52, "inquisitore: +2")
	alta.zeal = 50
	s.agents.clear()
	W.add_agent(s, W.A, W.ALTA, "GRAND_INQUISITOR", 1)
	_year(s)
	t.assert_eq(alta.zeal, 55, "grande inquisitore: +5")
	alta.zeal = 99
	s.agents.clear()
	W.add_agent(s, W.A, W.ALTA, "CARDINAL", 1)
	_year(s)
	t.assert_eq(alta.zeal, 100, "limite superiore")


func test_lo_zelo_segue_la_colonna_44_e_la_religione_del_proprietario(t: TestContext) -> void:
	var s := _world()
	var alta := s.province(W.ALTA)
	var unit := s.units.get_unit("Inquisitor")
	var raw := unit.raw
	raw[ReligionProcessor.COL_ZEAL] = "PAGAN(0), CATHOLIC(4), ORTHODOX(0), ISLAMIC(0), JEWISH(0), HERETIC(0)"
	unit.raw = raw
	var inquisitor := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 1)
	t.assert_eq(ReligionProcessor.agent_zeal(s, inquisitor, C), 4, "dalla colonna")
	t.assert_eq(ReligionProcessor.agent_zeal(s, inquisitor, M), 0, "per un'altra religione niente")
	_year(s)
	t.assert_eq(alta.zeal, 54)
	# un mullah musulmano in una provincia cattolica non ne alza lo zelo (ma la convertirebbe)
	s.agents.clear()
	alta.zeal = 50
	W.add_agent(s, W.B, W.ALTA, "MULLAH", 1)
	_year(s)
	t.assert_eq(alta.zeal, 50)
	# in una provincia musulmana si
	var mezza := s.province(W.MEZZA)
	_year(s)
	t.assert_eq(mezza.zeal, 50)
	W.add_agent(s, W.B, W.MEZZA, "MULLAH", 1)
	_year(s)
	t.assert_eq(mezza.zeal, 52)
	# nelle province dei ribelli lo zelo non sale (nessuna religione del proprietario)
	var sola := s.province(W.SOLA)
	W.add_agent(s, W.A, W.SOLA, "CARDINAL", 1)
	_year(s)
	t.assert_eq(sola.zeal, 50)


# --- eresia ----------------------------------------------------------------------------------------------------


func test_l_eresia_cresce_con_tasse_alte_o_lealta_bassa(t: TestContext) -> void:
	var s := _world()
	var alta := s.province(W.ALTA)
	_year(s)
	t.assert_eq(alta.religion_pct(H), 0.0, "tassa normale e lealta' alta: niente")
	alta.tax_level = 3
	_year(s)
	t.assert_eq(alta.religion_pct(H), 1.0, "tassa 3: +1 punto, tolto ai cattolici")
	t.assert_eq(alta.religion_pct(C), 99.0)
	_year(s)
	t.assert_eq(alta.religion_pct(H), 2.0)
	alta.tax_level = 2
	_year(s)
	t.assert_eq(alta.religion_pct(H), 2.0, "senza cause non cresce (e non derivano)")
	alta.loyalty = 99
	_year(s)
	t.assert_eq(alta.religion_pct(H), 3.0, "lealta' sotto 100")
	alta.loyalty = 100
	_year(s)
	t.assert_eq(alta.religion_pct(H), 3.0)
	# non in una provincia di un proprietario non cattolico
	var mezza := s.province(W.MEZZA)
	mezza.tax_level = 4
	_year(s)
	t.assert_eq(mezza.religion_pct(H), 0.0)
	# gli eretici vengono tolti solo ai cattolici
	var bassa := s.province(W.BASSA)
	bassa.tax_level = 4
	_set_mix(bassa, {"CATHOLIC": 25, "ORTHODOX": 75})
	_year(s)
	t.assert_eq(bassa.religion_pct(H), 1.0)
	t.assert_eq(bassa.religion_pct(O), 74.0, "la deriva ha tolto agli ortodossi, l'eresia ai cattolici")
	t.assert_eq(bassa.religion_pct(C), 25.0)
	for p in s.provinces:
		_check_valid(t, p, "eresia")


# --- inquisitori -----------------------------------------------------------------------------------------------


func test_gli_inquisitori_bruciano_gli_eretici(t: TestContext) -> void:
	var s := _world()
	var alta := s.province(W.ALTA)
	_set_mix(alta, {"CATHOLIC": 90, "HERETIC": 10})
	W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 1)
	_year(s)
	t.assert_eq(alta.religion_pct(H), 7.0, "inquisitore: -3 all'anno")
	t.assert_eq(alta.religion_pct(C), 93.0, "verso la religione del proprietario")
	W.add_agent(s, W.A, W.ALTA, "GRAND_INQUISITOR", 1)
	_year(s)
	t.assert_eq(alta.religion_pct(H), 0.0, "e il grande ne toglie 6 (ma non piu' di quanti ce ne sono)")
	t.assert_eq(alta.religion_pct(C), 100.0)
	# un inquisitore di un'altra fazione non brucia gli eretici di una provincia altrui
	_set_mix(alta, {"CATHOLIC": 90, "HERETIC": 10})
	s.agents.clear()
	alta.zeal = 50
	W.add_agent(s, W.G, W.ALTA, "INQUISITOR", 1)
	_year(s)
	t.assert_eq(alta.religion_pct(H), 10.0)
	t.assert_eq(alta.zeal, 52, "ma ne alza comunque lo zelo (stessa religione)")
	# i parametri comandano
	s.agents.clear()
	W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 1)
	s.rules.religion.inquisitor_points = 4.0
	_year(s)
	t.assert_eq(alta.religion_pct(H), 6.0)
	for p in s.provinces:
		_check_valid(t, p, "inquisitori")


func test_l_inquisitore_senza_eretici_ne_processi_abbassa_la_lealta(t: TestContext) -> void:
	var s := _world()
	var alta := s.province(W.ALTA)
	var before := ProvinceProcessor.loyalty_terms(s, alta)
	t.assert_eq(before["inquisitori"], 0)
	var ins := W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 1)
	var with := ProvinceProcessor.loyalty_terms(s, alta)
	t.assert_eq(with["inquisitori"], -3, "malus_inquisitore_inattivo")
	t.assert_eq(int(with["somma"]) - int(before["somma"]), -3, "entra nella somma")
	t.assert_eq(ReligionProcessor.inquisitor_term(s, alta), -3)
	W.add_agent(s, W.A, W.ALTA, "GRAND_INQUISITOR", 1)
	t.assert_eq(ReligionProcessor.inquisitor_term(s, alta), -6, "uno per ogni inquisitore inattivo")
	s.rules.religion.inactive_malus = 5
	t.assert_eq(ReligionProcessor.inquisitor_term(s, alta), -10)
	s.rules.religion.inactive_malus = 3
	# con un processo in corso l'inquisitore non e' inattivo
	ins.mission = {"tipo": AgentMissions.TRIAL, "bersaglio": {"tipo": "agente", "id": 1}, "regione": W.ALTA, "avvicinamento": false}
	t.assert_eq(ReligionProcessor.inquisitor_term(s, alta), -3)
	# con degli eretici nessuno lo e'
	_set_mix(alta, {"CATHOLIC": 99, "HERETIC": 1})
	t.assert_eq(ReligionProcessor.inquisitor_term(s, alta), 0)
	_set_mix(alta, {"CATHOLIC": 100})
	# un inquisitore straniero o in una provincia ribelle non conta
	s.agents.clear()
	W.add_agent(s, W.G, W.ALTA, "INQUISITOR", 1)
	t.assert_eq(ReligionProcessor.inquisitor_term(s, alta), 0)
	W.add_agent(s, W.A, W.SOLA, "INQUISITOR", 1)
	t.assert_eq(ReligionProcessor.inquisitor_term(s, s.province(W.SOLA)), 0)
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, s.province(W.SOLA))["inquisitori"], 0)


# --- lealta' -----------------------------------------------------------------------------------------------------


func test_la_penalita_di_religione_e_proporzionale(t: TestContext) -> void:
	var s := W.world()
	var bassa := s.province(W.BASSA)
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, bassa)["religione"], -11, "15 x 75 / 100 = 11,25: arrotondato")
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, s.province(W.ALTA))["religione"], 0, "100% della religione del proprietario")
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, s.province(W.MEZZA))["religione"], 0)
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, s.province(W.SOLA))["religione"], 0, "ribelli: niente")
	var target_before := int(ProvinceProcessor.loyalty_terms(s, bassa)["obiettivo"])
	_set_mix(bassa, {"CATHOLIC": 100})
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, bassa)["religione"], 0)
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, bassa)["obiettivo"]), target_before + 11, "il termine entra nell'obiettivo")
	_set_mix(bassa, {"ORTHODOX": 100})
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, bassa)["religione"], -15, "nessun cattolico: la penalita' intera")
	_set_mix(bassa, {"CATHOLIC": 50, "ORTHODOX": 50})
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, bassa)["religione"], -8, "15 x 50 / 100 = 7,5")
	s.rules.province.religion_penalty = 20
	_set_mix(bassa, {"CATHOLIC": 25, "ORTHODOX": 75})
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, bassa)["religione"], -15, "20 x 75 / 100")
	s.campaign.faction(W.A).religion = ""
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, bassa)["religione"], 0, "proprietario senza religione")


func test_gli_eretici_pesano_sulla_lealta_come_non_fedeli(t: TestContext) -> void:
	var s := W.world()
	var alta := s.province(W.ALTA)
	_set_mix(alta, {"CATHOLIC": 80, "HERETIC": 20})
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, alta)["religione"], -3, "15 x 20 / 100")


# --- rivolta eretica -----------------------------------------------------------------------------------------------


func test_soglia_della_rivolta_eretica(t: TestContext) -> void:
	var s := W.world()
	var alta := s.province(W.ALTA)
	_set_mix(alta, {"CATHOLIC": 70, "HERETIC": 30})
	t.assert_false(ReligionProcessor.heretic_revolt(s, alta), "30% non basta: oltre la soglia")
	_set_mix(alta, {"CATHOLIC": 69.75, "HERETIC": 30.25})
	t.assert_true(ReligionProcessor.heretic_revolt(s, alta))
	s.rules.religion.heretic_revolt_threshold = 40.0
	t.assert_false(ReligionProcessor.heretic_revolt(s, alta))
	var sola := s.province(W.SOLA)
	_set_mix(sola, {"PAGAN": 40, "HERETIC": 60})
	s.rules.religion.heretic_revolt_threshold = 30.0
	t.assert_false(ReligionProcessor.heretic_revolt(s, sola), "una provincia ribelle non si rivolta")


func test_la_rivolta_eretica_ha_i_ribelli_eretici_e_un_evento(t: TestContext) -> void:
	var s := W.world()
	var alta := s.province(W.ALTA)
	_set_mix(alta, {"CATHOLIC": 60, "HERETIC": 40})
	alta.loyalty = 10      # sotto la soglia dei banditi: gli eretici hanno la precedenza
	t.assert_eq(ProvinceProcessor.rebel_type(s, alta), ProvinceProcessor.REBEL_HERETICS)
	s.events.clear()
	t.assert_true(ProvinceProcessor.spawn_revolt(s, alta, ""))
	var revolts := W.events_of(s, GameState.EV_REBELLION)
	var heretic := W.events_of(s, GameState.EV_HERETIC_REVOLT)
	t.assert_eq(revolts.size(), 1, "EV_REBELLION resta")
	t.assert_eq(heretic.size(), 1, "e si aggiunge EV_HERETIC_REVOLT")
	if revolts.size() == 1 and heretic.size() == 1:
		t.assert_eq(revolts[0]["tipo_ribelli"], ProvinceProcessor.REBEL_HERETICS)
		t.assert_eq(heretic[0]["fazione"], W.A)
		t.assert_eq(heretic[0]["regione"], W.ALTA)
		t.assert_eq(heretic[0]["provincia"], W.ALTA)
		t.assert_eq(heretic[0]["eretici"], 40.0)
		t.assert_eq(heretic[0]["esercito"], revolts[0]["esercito"])
		t.assert_eq(heretic[0]["uomini"], revolts[0]["uomini"])
		t.assert_true(str(heretic[0]["testo"]) != "")
	# senza eretici oltre la soglia: la rivolta normale, nessun evento in piu'
	var orto := s.province(W.ORTO)
	s.events.clear()
	ProvinceProcessor.spawn_revolt(s, orto, "")
	t.assert_eq(W.events_of(s, GameState.EV_REBELLION).size(), 1)
	t.assert_eq(W.events_of(s, GameState.EV_HERETIC_REVOLT).size(), 0)
	t.assert_true(ProvinceProcessor.rebel_type(s, orto) != ProvinceProcessor.REBEL_HERETICS)
	# anche la rivolta che si estende da un'altra provincia e' eretica se la provincia lo e'
	s.events.clear()
	var other := s.province(W.BASSA)
	_set_mix(other, {"CATHOLIC": 50, "HERETIC": 50})
	ProvinceProcessor.spawn_revolt(s, other, W.ALTA)
	t.assert_eq(W.events_of(s, GameState.EV_REBELLION_SPREAD).size(), 1)
	t.assert_eq(W.events_of(s, GameState.EV_HERETIC_REVOLT).size(), 1)


## Quante volte, su `trials` anni, la provincia ALTA si rivolta con la lealta' a 30 (probabilita' di base 0,3).
func _revolts_in_alta(s: GameState, trials: int) -> int:
	var pr := s.rules.province
	pr.base = 20
	pr.revolt_k = 1.0
	pr.revolt_max_chance = 0.3
	var alta := s.province(W.ALTA)
	var count := 0
	for i in trials:
		alta.loyalty = 30
		ProvinceProcessor.process_year(s)
		for a in s.armies.duplicate():
			if a.faction == GameState.REBEL:
				if a.region == W.ALTA:
					count += 1
				s.remove_army(a)
	return count


func test_con_gli_eretici_la_rivolta_ha_probabilita_doppia(t: TestContext) -> void:
	var normal := _revolts_in_alta(W.world(21), 400)
	var s := W.world(21)
	_set_mix(s.province(W.ALTA), {"CATHOLIC": 60, "HERETIC": 40})
	var doubled := _revolts_in_alta(s, 400)
	t.assert_true(normal >= 80 and normal <= 160, "circa il 30%%: %d su 400" % normal)
	t.assert_true(doubled >= 190 and doubled <= 290, "circa il 60%%: %d su 400" % doubled)
	t.assert_true(doubled > normal)


# --- invarianti, determinismo, fine anno ----------------------------------------------------------------------------


func test_la_religione_non_usa_il_generatore_casuale(t: TestContext) -> void:
	var s := _world()
	W.add_agent(s, W.A, W.BASSA, "BISHOP", 1)
	W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 1)
	s.province(W.ALTA).tax_level = 4
	var rng_before := s.rng.state
	for i in 30:
		_year(s)
	t.assert_eq(s.rng.state, rng_before, "nessun sorteggio")
	t.assert_eq(s.events.size(), 0, "e nessun evento")


func test_cinquanta_anni_tengono_la_somma_e_sono_deterministici(t: TestContext) -> void:
	var texts: Array[String] = []
	for run in 2:
		var s := _world()
		for p in s.provinces:
			p.tax_level = 4
		W.add_agent(s, W.A, W.BASSA, "BISHOP", 1)
		W.add_agent(s, W.B, W.BASSA, "MULLAH", 1)
		W.add_agent(s, W.A, W.ALTA, "INQUISITOR", 1)
		s.buildings.get_family("MOSQUE").get_level(1).faith = 0.15
		s.province(W.BASSA).set_level("MOSQUE", 1)
		for i in 50:
			_year(s)
			for p in s.provinces:
				_check_valid(t, p, "anno %d" % i)
			if t.failed:
				return
		texts.append(SaveGame.to_json(s))
	t.assert_eq(texts[0], texts[1], "stessi dati, stessa religione")


func test_il_fine_anno_aggiorna_la_religione(t: TestContext) -> void:
	var s := W.world()
	var bassa := s.province(W.BASSA)
	var before := bassa.religion_pct(O)
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0)
	t.assert_true(bassa.religion_pct(O) < before, "la deriva e' nel fine anno")
	for p in s.provinces:
		_check_valid(t, p, "fine anno")


# --- salvataggi -------------------------------------------------------------------------------------------------------


func test_religioni_e_zelo_nel_salvataggio(t: TestContext) -> void:
	var s := _world()
	_set_mix(s.province(W.BASSA), {"CATHOLIC": 20.25, "ORTHODOX": 60, "HERETIC": 19.75})
	s.province(W.BASSA).zeal = 73
	var data := SaveGame.to_dict(s)
	t.assert_eq(data["versione"], SaveGame.VERSION)
	t.assert_true(SaveGame.VERSION >= 6)
	var province_data: Dictionary = {}
	for item in (data["province"] as Array):
		var pd: Dictionary = item
		if pd["id"] == W.BASSA:
			province_data = pd
	t.assert_eq(province_data["zelo"], 73)
	var saved: Dictionary = province_data["religioni"]
	t.assert_eq(saved["HERETIC"], 19.75)
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var back_data: Dictionary = parsed
	var r := SaveGame.from_dict(back_data, s.campaign, s.units, s.buildings, W.quiet_rules(), s.heroes)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "andata e ritorno")
	t.assert_eq(back.province(W.BASSA).religions, s.province(W.BASSA).religions)
	t.assert_eq(back.province(W.BASSA).zeal, 73)
	for i in 10:
		TurnProcessor.end_year(s)
		TurnProcessor.end_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "dopo 10 anni identici")


func test_le_versioni_precedenti_hanno_la_composizione_della_partita_nuova(t: TestContext) -> void:
	var s := W.world()
	var data := SaveGame.to_dict(s)
	for version in [4, 5]:
		var old := data.duplicate(true)
		old["versione"] = version
		for item in (old["province"] as Array):
			var pd: Dictionary = item
			pd.erase("religioni")
			pd.erase("zelo")
		var parsed: Variant = JSON.parse_string(JSON.stringify(old))
		var old_data: Dictionary = parsed
		var r := SaveGame.from_dict(old_data, s.campaign, s.units, s.buildings, Rules.new(), s.heroes)
		t.assert_true(bool(r["ok"]), "v%d: %s" % [version, str(r["errore"])])
		if not bool(r["ok"]):
			continue
		var loaded: GameState = r["stato"]
		t.assert_eq(loaded.province(W.BASSA).religion_pct(O), 75.0, "v%d: 75/25" % version)
		t.assert_eq(loaded.province(W.BASSA).religion_pct(C), 25.0)
		t.assert_eq(loaded.province(W.ALTA).religion_pct(C), 100.0)
		t.assert_eq(loaded.province(W.MEZZA).religion_pct(M), 100.0)
		for p in loaded.provinces:
			t.assert_eq(p.zeal, 50, "v%d: zelo %s" % [version, p.id])
			_check_valid(t, loaded.province(p.id), "v%d" % version)
		t.assert_eq(SaveGame.to_dict(loaded)["versione"], SaveGame.VERSION, "si riscrive nella versione corrente")
	# anche se il vecchio salvataggio portava dei valori (versione cambiata a mano), contano quelli della partita nuova
	var odd := data.duplicate(true)
	odd["versione"] = 5
	for item in (odd["province"] as Array):
		var pd: Dictionary = item
		pd["religioni"] = {"HERETIC": 100}
	var odd_parsed: Variant = JSON.parse_string(JSON.stringify(odd))
	var odd_data: Dictionary = odd_parsed
	var odd_r := SaveGame.from_dict(odd_data, s.campaign, s.units, s.buildings, Rules.new(), s.heroes)
	var odd_loaded: GameState = odd_r["stato"]
	t.assert_eq(odd_loaded.province(W.ALTA).religion_pct(C), 100.0)


func test_un_salvataggio_con_composizione_sbagliata_si_riporta_a_cento(t: TestContext) -> void:
	var s := W.world()
	var data := SaveGame.to_dict(s)
	for item in (data["province"] as Array):
		var pd: Dictionary = item
		if pd["id"] == W.BASSA:
			pd["religioni"] = {"CATHOLIC": 30, "PAGAN": 30}
			pd["zelo"] = 500
		elif pd["id"] == W.ALTA:
			pd["religioni"] = {}
			pd["zelo"] = -4
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var bad: Dictionary = parsed
	var r := SaveGame.from_dict(bad, s.campaign, s.units, s.buildings, Rules.new(), s.heroes)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var loaded: GameState = r["stato"]
	t.assert_eq(loaded.province(W.BASSA).religion_pct(C), 50.0)
	t.assert_eq(loaded.province(W.BASSA).religion_pct(P), 50.0)
	t.assert_eq(loaded.province(W.BASSA).zeal, 100)
	t.assert_eq(loaded.province(W.ALTA).religion_pct(P), 100.0, "composizione vuota: tutta pagana")
	t.assert_eq(loaded.province(W.ALTA).zeal, 0)
	for p in loaded.provinces:
		_check_valid(t, p, "riportata a cento")
