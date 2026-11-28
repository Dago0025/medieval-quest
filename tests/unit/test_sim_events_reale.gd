extends RefCounted
## Fase 6a sui dati reali dell'installazione (EARLY_XL.TXT, prod unita' ed edifici, Loc/<lingua>/Events.txt), saltata se
## l'installazione manca: ogni regione, fazione, cultura e merce citata dai file dei dati esiste nello startpos, i titoli e i
## testi dei 142 eventi storici (71 dell'originale e 71 aggiunti il 28/11/2026) si leggono da data/testi, e una partita dal primo anno al 1700 (nessun ordine) fa accadere
## ogni evento storico al piu' una volta, la Peste Nera una volta sola e l'Orda d'Oro nel suo anno.
## I testi originali non stanno nel repository: qui si controlla solo che ci siano.

const STORICI := 142

var _campaign: CampaignData
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable


func _load_static(t: TestContext) -> bool:
	if _campaign != null:
		return true
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata in %s" % GameFiles.game_dir())
		return false
	var campaign := StartposLoader.load_file(GameFiles.startpos())
	var unit_path := GameFiles.prod_file(campaign.unit_prod_file)
	var building_path := GameFiles.prod_file(campaign.building_prod_file)
	if not FileAccess.file_exists(unit_path) or not FileAccess.file_exists(building_path):
		t.skip("file prod non trovati in %s" % GameFiles.game_dir())
		return false
	_units = UnitProdLoader.load_file(unit_path)
	_buildings = BuildingProdLoader.load_file(building_path)
	_campaign = campaign
	return true


func _new_game(seed_value: int) -> GameState:
	return GameSetup.new_game(_campaign, _units, _buildings, Rules.load_file(), seed_value)


func _land(region_id: String) -> bool:
	var r := _campaign.region(region_id)
	return r != null and not r.is_sea


# --- i dati citano solo cose che esistono -----------------------------------------------------------------


func test_le_regioni_immuni_dello_startpos(t: TestContext) -> void:
	if not _load_static(t):
		return
	t.assert_true(_campaign.has_disaster_data(), "lo startpos reale dichiara le regioni immuni")
	t.assert_true(_campaign.unfloodable.size() > 0 and _campaign.unquakeable.size() > 0)
	for id in _campaign.unfloodable:
		t.assert_true(_land(id), "regione immune alle inondazioni sconosciuta o di mare: %s" % id)
	for id in _campaign.unquakeable:
		t.assert_true(_land(id), "regione immune ai terremoti sconosciuta o di mare: %s" % id)


func test_ogni_regione_dei_file_di_dati_esiste_nello_startpos(t: TestContext) -> void:
	if not _load_static(t):
		return
	var rules := Rules.load_file()
	t.assert_eq(rules.errors, PackedStringArray())
	var ev := rules.events
	t.assert_eq(ev.history.size(), STORICI)
	var cultures := {}
	for r in _campaign.land_regions():
		cultures[r.culture.strip_edges().to_upper()] = true
	# gli eventi del 28/11/2026 citano anche regioni e fazioni della mappa del mondo (startpos_mondo.txt, fazioni_mondo.txt)
	var world := StartposLoader.load_text(Dharma.startpos_text(WorldMap.startpos_text(TextIO.read_latin1(GameFiles.startpos()), false) + "\n" + WorldFactions.startpos_text())) if WorldMap.available() else _campaign
	for e in ev.history:
		var in_europe := e.index < 71
		for id in e.regions:
			var region := (_campaign if in_europe else world).region(id)
			t.assert_true(region != null and not region.is_sea, "evento %d (%s): regione sconosciuta %s" % [e.index, e.key, id])
		if e.faction != "":
			t.assert_true((_campaign if in_europe else world).faction(e.faction) != null, "evento %d (%s): fazione sconosciuta %s" % [e.index, e.key, e.faction])
		if e.culture != "":
			t.assert_true(cultures.has(e.culture), "evento %d (%s): cultura sconosciuta %s" % [e.index, e.key, e.culture])
		for good in e.goods:
			t.assert_true(_campaign.trade_goods.has(good) or world.trade_goods.has(good), "evento %d (%s): merce sconosciuta %s" % [e.index, e.key, good])
	for id in ev.black_death_origin:
		t.assert_true(_land(id), "origine della Peste Nera sconosciuta: %s" % id)
	for id in ev.horde_entry:
		t.assert_true(_land(id), "ingresso dell'Orda sconosciuto: %s" % id)
	var horde := _campaign.faction(ev.horde_faction)
	t.assert_true(horde != null, "fazione dell'Orda dichiarata")
	if horde != null:
		t.assert_false(horde.is_active(), "l'Orda d'Oro non e' attiva all'inizio")


func test_la_cavalleria_dell_orda_esiste(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game(1)
	s.year = s.rules.events.horde_year
	var region := EventProcessor.horde_entry(s, s.rules.events)
	t.assert_true(region != null, "una regione d'ingresso")
	if region == null:
		return
	var unit := EventProcessor.horde_unit(s, s.rules.events, region)
	t.assert_true(unit != null, "un'unita' per l'Orda")
	if unit != null:
		print("   Orda d'Oro: ingresso %s, unita' %s (%s, %d uomini)" % [region.id, unit.id, unit.type_name, unit.men])
		t.assert_eq(unit.type_name, UnitType.CAVALRY, "cavalleria")


# --- testi propri del remake (data/testi, dal 18/11/2026) ---------------------------------------------------------


func test_titoli_e_testi_degli_eventi_storici(t: TestContext) -> void:
	ItalianTexts.reset()
	var texts := EventTexts.load_file()
	t.assert_eq(texts.historical_count(), STORICI, "%d titoli" % STORICI)
	for i in STORICI:
		t.assert_true(texts.has_historical(i), "evento %d senza titolo o testo" % i)
		t.assert_true(texts.historical_title(i).strip_edges() != "", "titolo vuoto: %d" % i)
		t.assert_true(texts.historical_text(i).strip_edges() != "", "testo vuoto: %d" % i)
	t.assert_false(texts.has_historical(STORICI))
	for kind in [GameState.EV_FLOOD, GameState.EV_FAMINE, GameState.EV_QUAKE, GameState.EV_STORM, GameState.EV_PLAGUE, GameState.EV_BLACK_DEATH]:
		var message := texts.disaster_message(kind, "Prova")
		t.assert_true(message != "", "messaggio mancante: %s" % kind)
		t.assert_false(message.contains("%s"), "segnaposto non sostituito: %s" % kind)
		t.assert_true(texts.disaster_title(kind) != "", "titolo mancante: %s" % kind)
	t.assert_true(ItalianTexts.array("peste", "varianti").size() >= 2, "la peste ha piu' varianti")
	var it := ConfigFile.new()
	var en := ConfigFile.new()
	t.assert_eq(it.load("res://data/testi/it/eventi.cfg"), OK)
	t.assert_eq(en.load("res://data/testi/en/eventi.cfg"), OK, "testi inglesi")
	for section in ["eventi_titoli", "eventi_testi", "disastri", "peste", "popoli_ribelli"]:
		t.assert_eq(en.get_section_keys(section), it.get_section_keys(section), "stesse chiavi in inglese: %s" % section)
	t.assert_eq((en.get_value("popoli_ribelli", "nomi") as Array).size(), (it.get_value("popoli_ribelli", "nomi") as Array).size())


# --- partita dal primo anno al 1700 ------------------------------------------------------------------------


func _count_kinds(s: GameState, counts: Dictionary) -> void:
	for e in s.events:
		var kind := str(e["tipo"])
		counts[kind] = int(counts.get(kind, 0)) + 1


func test_partita_dal_primo_anno_al_1700(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game(20261108)
	var counts := {}
	var historical := {}
	var black_death_years: Array = []
	var horde_years: Array = []
	var guard := 0
	while not s.is_finished() and guard < 800:
		guard += 1
		var res := TurnProcessor.end_year(s)
		var errs: Array = res["errori"]
		if errs.size() > 0 or not bool(res["ok"]):
			t.assert_true(false, "anno %d: errori %s" % [s.year, str(errs)])
			return
		_count_kinds(s, counts)
		for e in s.events:
			var kind := str(e["tipo"])
			if kind == GameState.EV_HISTORICAL:
				var index := int(e["indice"])
				if historical.has(index):
					t.assert_true(false, "evento storico %d accaduto due volte" % index)
					return
				historical[index] = int(e["anno"])
			elif kind == GameState.EV_BLACK_DEATH:
				black_death_years.append(int(e["anno"]))
			elif kind == GameState.EV_HORDE_ARRIVES:
				horde_years.append(int(e["anno"]))
	t.assert_eq(s.year, 1700, "arrivata al 1700")
	t.assert_eq(historical.size(), STORICI, "tutti gli eventi storici con anno entro il 1700 sono accaduti")
	for index in historical:
		var e := s.rules.events.historical(index)
		t.assert_true(e != null, "evento %d sconosciuto" % index)
		if e == null:
			continue
		var year := int(historical[index])
		t.assert_true(year >= e.year_from and year <= e.year_to, "evento %d (%s) nell'anno %d fuori dalla finestra %d-%d" % [index, e.key, year, e.year_from, e.year_to])
		if not e.is_window():
			t.assert_eq(year, e.year_from, "evento %d (%s) ha un anno fisso" % [index, e.key])
		t.assert_eq(int(s.historical_done.get(index, 0)), year, "lo stato ricorda l'anno dell'evento %d" % index)
	t.assert_eq(black_death_years.size(), 1, "la Peste Nera comincia una volta sola")
	if black_death_years.size() == 1:
		t.assert_true(int(black_death_years[0]) >= 1346 and int(black_death_years[0]) <= 1353, "nella finestra: %d" % int(black_death_years[0]))
		t.assert_eq(int(black_death_years[0]), int(historical.get(54, 0)), "nell'anno dell'evento storico 54")
	t.assert_true(bool(s.black_death.get("finita", false)), "la Peste Nera finisce")
	t.assert_eq(horde_years, [1230], "l'Orda d'Oro arriva nel 1230, una volta sola")
	t.assert_true(s.horde.has("stato"))
	for p in s.provinces:
		t.assert_true(p.temp_effects.is_empty(), "effetti di un anno rimasti in %s" % p.id)
	for kind in [GameState.EV_FLOOD, GameState.EV_FAMINE, GameState.EV_QUAKE, GameState.EV_PLAGUE]:
		t.assert_true(int(counts.get(kind, 0)) > 0, "in 700 anni almeno un evento '%s'" % kind)
	print("   1000-1700: %s" % str(counts))


func test_partita_con_eventi_e_deterministica(t: TestContext) -> void:
	if not _load_static(t):
		return
	var texts: Array[String] = []
	for run in 2:
		var s := _new_game(777)
		for i in 260:
			TurnProcessor.end_year(s)
		texts.append(SaveGame.to_json(s))
	t.assert_eq(texts[0], texts[1], "stesso seme, stessa partita (compresi eventi, Peste e Orda)")
	var parsed: Variant = JSON.parse_string(texts[0])
	var data: Dictionary = parsed
	var r := SaveGame.from_dict(data, _campaign, _units, _buildings, Rules.load_file())
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	if bool(r["ok"]):
		var back: GameState = r["stato"]
		t.assert_eq(SaveGame.to_json(back), texts[0], "il salvataggio dopo l'Orda si ricarica uguale")
		t.assert_true(back.horde.has("stato"), "l'Orda e' nel salvataggio")
