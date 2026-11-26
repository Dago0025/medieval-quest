extends RefCounted
## Nelle regioni d'origine degli Auror (modalita' Auror, mappa del mondo) si arruola ogni truppa e nave del gioco tranne i
## contadini (richiesta di Federico del 23/11/2026: alcune unita' delle fazioni nuove non erano creabili perche' chiedevano
## il tempio del Dharma o il santuario pagano, che gli Auror del Culto Imperiale non possono costruire). La regola
## `requisiti_equivalenti` di auror.cfg aggiunge come alternativa l'edificio equivalente del Culto (la chiesa).
## Senza installazione o senza mappa del mondo il test si salta.

const ESCLUSE := ["Peasants", "MuslimPeasants"]


func _game() -> GameState:
	Scenario.set_auror(true)
	var c := Scenario.load_startpos()
	var units := Scenario.load_units(GameFiles.prod_file(c.unit_prod_file))
	var buildings := Scenario.load_buildings(GameFiles.prod_file(c.building_prod_file))
	var heroes := Scenario.load_heroes(GameFiles.heroes_file(c.name_data_basename()))
	return GameSetup.new_game(c, units, buildings, Rules.load_file(), 11, heroes)


## Costruisce nella provincia, livello per livello, tutto cio' che la fazione puo' costruire.
func _build_everything(s: GameState, faction_id: String, p: ProvinceState) -> void:
	var changed := true
	var rounds := 0
	while changed and rounds < 60:
		changed = false
		rounds += 1
		for fam in s.buildings.families:
			p.building_queue.clear()
			if bool(GameCommands.can_queue_building(s, faction_id, p.id, fam.id)["ok"]):
				p.set_level(fam.id, p.level_of(fam.id) + 1)
				changed = true
	p.building_queue.clear()


func test_ogni_truppa_nelle_regioni_degli_auror(t: TestContext) -> void:
	if not WorldMap.available() or not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione o mappa del mondo assenti")
		return
	var s := _game()
	s.faction("FN_DANISH").treasury = 100000000
	var provinces := 0
	for p in s.provinces:
		if p.owner != "FN_DANISH":
			continue
		provinces += 1
		_build_everything(s, "FN_DANISH", p)
		for u in s.units.units:
			if not u.is_military() or ESCLUSE.has(u.id) or u.unique:
				continue
			p.unit_queue.clear()
			var r := GameCommands.can_queue_unit(s, "FN_DANISH", p.id, u.id)
			t.assert_true(bool(r["ok"]), "%s in %s: %s" % [u.id, p.id, str(r.get("errore", ""))])
	t.assert_true(provinces >= 1, "gli Auror hanno le loro regioni")


func test_equivalenze_solo_in_modalita_auror(t: TestContext) -> void:
	if not WorldMap.available() or not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione o mappa del mondo assenti")
		return
	var eq := Scenario.auror_requirement_equivalents()
	t.assert_eq(str(eq.get("DHARMA_TEMPLE", "")), "CHURCH")
	t.assert_eq(str(eq.get("PAGAN_SHRINE", "")), "CHURCH")
	Scenario.set_auror(false)
	var c := Scenario.load_startpos()
	var units := Scenario.load_units(GameFiles.prod_file(c.unit_prod_file))
	Scenario.set_auror(true)
	var sohei := units.get_unit("JapSohei")
	t.assert_true(sohei != null, "JapSohei")
	if sohei != null:
		for group in sohei.requires:
			t.assert_false(group.has("CHURCH"), "nello storico i Sohei vogliono il tempio: %s" % str(group))
