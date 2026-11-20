extends RefCounted
## Test dei salvataggi (SaveGame): formato JSON versione 13, andata e ritorno dello stato,
## salvataggio su file in user://salvataggi e, soprattutto, identita' dell'anno successivo
## tra la partita originale e quella ricaricata.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const SAVE_NAME := "test_sim_save_prova"

var _campaign: CampaignData
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable


func _load_static() -> void:
	if _campaign == null:
		_campaign = StartposLoader.load_file(STARTPOS)
		_units = UnitProdLoader.load_file(UNITS)
		_buildings = BuildingProdLoader.load_file(BUILDINGS)


func _world(seed_value: int = 5) -> GameState:
	_load_static()
	return GameSetup.new_game(_campaign, _units, _buildings, Rules.new(), seed_value)


func _restore(data: Dictionary) -> GameState:
	_load_static()
	var r := SaveGame.from_dict(data, _campaign, _units, _buildings, Rules.new())
	return r["stato"]


## Una partita a meta' con code, movimenti, tasse diverse e unita' appena reclutate.
func _busy_world() -> GameState:
	var s := _world(11)
	s.faction("FN_ALPHA").treasury = 20000
	s.province("ID_ALTA").set_level("BOWYER", 1)
	s.province("ID_ALTA").set_level("SHIPYARD", 1)
	GameCommands.set_tax(s, "FN_ALPHA", "ID_ALTA", 4)
	GameCommands.set_tax(s, "FN_ALPHA", "ID_BASSA", 1)
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "CHURCH")
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "UNIVERSITY")
	GameCommands.queue_building(s, "FN_ALPHA", "ID_BASSA", "SALT_MINE")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Archers")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Galley")
	GameCommands.queue_unit(s, "FN_BETA", "ID_MEZZA", "Nizari")
	GameCommands.order_move(s, "FN_ALPHA", 1, PackedStringArray(["ID_BASSA", "ID_MEZZA"]))
	GameCommands.order_move(s, "FN_ALPHA", 2, PackedStringArray(["ID_MARE_SUD", "ID_MARE_NORD"]))
	TurnProcessor.end_year(s)
	return s


# --- formato ---------------------------------------------------------------------


func test_formato_e_versione(t: TestContext) -> void:
	var s := _world(123456789)
	var d := SaveGame.to_dict(s)
	t.assert_eq(d["versione"], SaveGame.VERSION, "il salvataggio porta la versione corrente")
	t.assert_eq(SaveGame.VERSION, 13, "mercenari: versione 13")
	t.assert_eq((d["personaggi"] as Array).size(), 0, "il mondo di prova non ha dati dei capi")
	t.assert_eq(d["prossimo_personaggio"], 1)
	t.assert_eq(d["anno"], 1000)
	t.assert_eq(d["anno_finale"], 1700)
	t.assert_eq(d["epoca"], "EARLY")
	t.assert_eq(d["seme"], "123456789", "il seme e' testo (interi a 64 bit)")
	t.assert_eq(typeof(d["rng_stato"]), TYPE_STRING)
	t.assert_eq((d["fazioni"] as Array).size(), 4)
	t.assert_eq((d["province"] as Array).size(), 4)
	t.assert_eq((d["eserciti"] as Array).size(), 5)
	t.assert_eq((d["agenti"] as Array).size(), 2)
	t.assert_false(d.has("campagna"), "i dati statici non si salvano")
	t.assert_false(d.has("unita_tabella"))


func test_il_json_e_valido_e_ordinato(t: TestContext) -> void:
	var s := _busy_world()
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	t.assert_eq(typeof(parsed), TYPE_DICTIONARY, "JSON valido")
	t.assert_eq(text, SaveGame.to_json(s), "stesso stato, stesso testo")
	var other := _busy_world()
	t.assert_eq(SaveGame.to_json(other), text, "due partite uguali danno lo stesso testo")


# --- andata e ritorno -------------------------------------------------------------


func test_andata_e_ritorno_in_memoria(t: TestContext) -> void:
	var s := _busy_world()
	var back := _restore(SaveGame.to_dict(s))
	t.assert_true(back != null, "ripristino")
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "stato identico")
	t.assert_eq(back.year, 1001)
	t.assert_eq(back.faction("FN_ALPHA").treasury, s.faction("FN_ALPHA").treasury)
	t.assert_eq(back.province("ID_ALTA").tax_level, 4)
	t.assert_eq(back.province("ID_ALTA").building_queue.size(), s.province("ID_ALTA").building_queue.size())
	t.assert_eq(back.province("ID_ALTA").level_of("CASTLE"), 3)
	t.assert_eq(back.army(1).path, s.army(1).path)
	t.assert_eq(back.next_army_id, s.next_army_id)
	t.assert_eq(back.agents.size(), 2)
	t.assert_eq(back.events.size(), s.events.size())


func test_andata_e_ritorno_attraverso_il_testo_json(t: TestContext) -> void:
	var s := _busy_world()
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	var back := _restore(data)
	t.assert_eq(SaveGame.to_json(back), text, "i float del JSON tornano interi")
	t.assert_eq(typeof(back.faction("FN_ALPHA").treasury), TYPE_INT)
	t.assert_eq(typeof(back.army(1).stacks[0].men), TYPE_INT)


func test_l_esito_della_partita_torna_dal_testo_json(t: TestContext) -> void:
	var s := _busy_world()
	s.victory.outcome = VictoryState.DOMINATION
	s.victory.year = 1001
	s.victory.domination_year = 1001
	s.victory.continues = true
	s.victory.set_ranking([
		{"posizione": 1, "fazione": "FN_ALPHA", "province": 2, "reddito": 120, "netto": 40, "quota": 0.3333, "giocatore": true},
		{"posizione": 2, "fazione": "FN_BETA", "province": 1, "reddito": 50, "netto": -3, "quota": 0.1667, "giocatore": false},
	])
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	var back := _restore(data)
	t.assert_true(back != null)
	t.assert_eq(back.victory.outcome, VictoryState.DOMINATION)
	t.assert_eq(back.victory.year, 1001)
	t.assert_eq(back.victory.domination_year, 1001)
	t.assert_true(back.victory.continues)
	t.assert_eq(back.victory.ranking.size(), 2)
	t.assert_eq(back.victory.ranking[0]["quota"], 0.3333, "la quota torna esatta")
	t.assert_eq(back.victory.ranking[1]["netto"], -3)
	t.assert_eq(typeof(back.victory.ranking[1]["province"]), TYPE_INT)
	t.assert_eq(SaveGame.to_json(back), text, "andata e ritorno stabile")


func test_seme_e_stato_del_generatore(t: TestContext) -> void:
	var s := _world(987654321012)
	for i in 5:
		s.rng.randi()
	var back := _restore(SaveGame.to_dict(s))
	t.assert_eq(back.seed_value, 987654321012)
	t.assert_eq(back.rng.state, s.rng.state, "stato a 64 bit conservato")
	var next_original := s.rng.randi()
	var next_loaded := back.rng.randi()
	t.assert_eq(next_loaded, next_original, "la sequenza continua uguale")
	# anche attraverso il testo, con un seme che non sta in un double
	var s2 := _world(9007199254740993)
	s2.rng.randi()
	var parsed: Variant = JSON.parse_string(SaveGame.to_json(s2))
	var data: Dictionary = parsed
	var back2 := _restore(data)
	t.assert_eq(back2.seed_value, 9007199254740993)
	t.assert_eq(back2.rng.state, s2.rng.state)


# --- l'anno successivo -------------------------------------------------------------


func test_un_salvataggio_ricaricato_da_lo_stesso_anno_successivo(t: TestContext) -> void:
	var original := _busy_world()
	var loaded := _restore(SaveGame.to_dict(original))
	for i in 8:
		var r1 := TurnProcessor.end_year(original)
		var r2 := TurnProcessor.end_year(loaded)
		t.assert_eq(str(r1), str(r2), "esito dell'anno %d" % (i + 1))
		t.assert_eq(SaveGame.to_json(loaded), SaveGame.to_json(original), "stato dopo %d anni" % (i + 1))
	t.assert_eq(original.year, 1009)
	# nel frattempo e' successo qualcosa: edifici costruiti e unita' nate
	t.assert_true(original.province("ID_ALTA").level_of("CHURCH") == 1, "la chiesa e' pronta")
	t.assert_eq(original.count_stacks("FN_ALPHA"), 7, "4 pile iniziali + 3 reclutate")


func test_salvataggio_su_file_e_ricarico(t: TestContext) -> void:
	var original := _busy_world()
	var saved := SaveGame.save_file(original, SAVE_NAME)
	t.assert_true(bool(saved["ok"]), "scrittura: %s" % str(saved["errore"]))
	t.assert_true(FileAccess.file_exists(SaveGame.path_of(SAVE_NAME)))
	t.assert_true(SaveGame.list_saves().has(SAVE_NAME))
	_load_static()
	var r := SaveGame.load_file(SAVE_NAME, _campaign, _units, _buildings, Rules.new())
	t.assert_true(bool(r["ok"]), "lettura: %s" % str(r["errore"]))
	if bool(r["ok"]):
		var loaded: GameState = r["stato"]
		for i in 3:
			TurnProcessor.end_year(original)
			TurnProcessor.end_year(loaded)
		t.assert_eq(SaveGame.to_json(loaded), SaveGame.to_json(original), "tre anni dopo il ricarico da file")
	t.assert_true(SaveGame.delete_file(SAVE_NAME), "pulizia")
	t.assert_false(FileAccess.file_exists(SaveGame.path_of(SAVE_NAME)))


func test_determinismo_a_parita_di_seme_e_ordini(t: TestContext) -> void:
	var a := _busy_world()
	var b := _busy_world()
	for i in 10:
		TurnProcessor.end_year(a)
		TurnProcessor.end_year(b)
	t.assert_eq(SaveGame.to_json(a), SaveGame.to_json(b))


# --- errori ---------------------------------------------------------------------------


func test_versione_non_supportata(t: TestContext) -> void:
	_load_static()
	var d := SaveGame.to_dict(_world())
	d["versione"] = 99
	var r := SaveGame.from_dict(d, _campaign, _units, _buildings, Rules.new())
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("Versione"))
	t.assert_true(r["stato"] == null)
	var empty := SaveGame.from_dict({}, _campaign, _units, _buildings, Rules.new())
	t.assert_false(bool(empty["ok"]), "senza versione")


func test_salvataggio_di_un_altra_campagna(t: TestContext) -> void:
	_load_static()
	var d := SaveGame.to_dict(_world())
	var provinces: Array = d["province"]
	var first: Dictionary = provinces[0]
	first["id"] = "ID_ATLANTIDE"
	var r := SaveGame.from_dict(d, _campaign, _units, _buildings, Rules.new())
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("ID_ATLANTIDE"))
	var d2 := SaveGame.to_dict(_world())
	var armies: Array = d2["eserciti"]
	var army: Dictionary = armies[0]
	army["regione"] = "ID_NESSUNA"
	t.assert_false(bool(SaveGame.from_dict(d2, _campaign, _units, _buildings, Rules.new())["ok"]))
	var d3 := SaveGame.to_dict(_world())
	var factions: Array = d3["fazioni"]
	var fd: Dictionary = factions[0]
	fd["id"] = "FN_SCONOSCIUTA"
	t.assert_false(bool(SaveGame.from_dict(d3, _campaign, _units, _buildings, Rules.new())["ok"]))


func test_file_mancante_o_rovinato(t: TestContext) -> void:
	_load_static()
	var missing := SaveGame.load_file("non_esiste_mai", _campaign, _units, _buildings, Rules.new())
	t.assert_false(bool(missing["ok"]))
	var broken_name := "test_sim_save_rovinato"
	DirAccess.make_dir_recursive_absolute(SaveGame.SAVE_DIR)
	var f := FileAccess.open(SaveGame.path_of(broken_name), FileAccess.WRITE)
	t.assert_true(f != null, "file di prova scrivibile")
	if f != null:
		f.store_string("{ questo non e' json")
		f.close()
		var broken := SaveGame.load_file(broken_name, _campaign, _units, _buildings, Rules.new())
		t.assert_false(bool(broken["ok"]))
		t.assert_true(str(broken["errore"]).contains("JSON"))
		SaveGame.delete_file(broken_name)


func test_nomi_di_salvataggio(t: TestContext) -> void:
	t.assert_true(SaveGame.is_valid_name("partita_1-bis"))
	t.assert_false(SaveGame.is_valid_name(""))
	t.assert_false(SaveGame.is_valid_name("../fuori"))
	t.assert_false(SaveGame.is_valid_name("con spazio"))
	t.assert_false(SaveGame.is_valid_name("a/b"))
	var bad := SaveGame.save_file(_world(), "../fuori")
	t.assert_false(bool(bad["ok"]))
	t.assert_eq(SaveGame.path_of("x"), "user://salvataggi/x.json")
