extends RefCounted
## Fase 6b sui dati reali dell'installazione (EARLY_XL.TXT, prod unita' ed edifici), saltata se l'installazione manca: una
## sola partita dal primo anno al 1700 (senza giocatore, nessun ordine; costa 20-45 secondi) con la fine della campagna una volta
## sola nel 1700 e la classifica coerente con lo stato. Il resto della 6b ha le sue prove in test_sim_victory.gd.

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


func test_la_soglia_sui_dati_reali(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := GameSetup.new_game(_campaign, _units, _buildings, Rules.load_file(), 1)
	var total := VictoryProcessor.total_provinces(s)
	t.assert_true(total > 0, "ci sono province di terra")
	var needed := s.rules.victory.provinces_needed(total)
	print("   %d province di terra, %d per il dominio" % [total, needed])
	var share := s.rules.victory.domination_threshold
	t.assert_true(needed >= int(total * share) and needed <= int(total * share) + 1, "quota di vittoria.cfg: %d su %d" % [needed, total])
	var rows := VictoryProcessor.standings(s)
	t.assert_true(rows.size() > 1, "piu' fazioni in classifica")
	var sum := 0
	for r in rows:
		sum += int(r["province"])
	t.assert_true(sum <= total)


func test_partita_fino_al_1700_con_la_fine_della_campagna(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := GameSetup.new_game(_campaign, _units, _buildings, Rules.load_file(), 20261108)
	var ends: Array[Dictionary] = []
	var other_outcomes := 0
	var guard := 0
	while not s.is_game_over() and guard < 800:
		guard += 1
		var res := TurnProcessor.end_year(s)
		var errs: Array = res["errori"]
		if errs.size() > 0 or not bool(res["ok"]):
			t.assert_true(false, "anno %d: errori %s" % [s.year, str(errs)])
			return
		for e in s.events:
			var kind := str(e["tipo"])
			if kind == GameState.EV_CAMPAIGN_END:
				ends.append(e)
			elif kind == GameState.EV_VICTORY or kind == GameState.EV_DEFEAT:
				other_outcomes += 1
	t.assert_eq(s.year, 1700, "arrivata al 1700")
	t.assert_true(s.is_game_over())
	t.assert_eq(other_outcomes, 0, "senza giocatore niente vittoria ne' sconfitta")
	t.assert_eq(ends.size(), 1, "la fine della campagna una volta sola")
	if ends.size() != 1:
		return
	var end_event := ends[0]
	t.assert_eq(int(end_event["anno"]), 1700)
	t.assert_eq(s.victory.outcome, VictoryState.CAMPAIGN_END)
	t.assert_eq(s.victory.year, 1700)
	# la classifica e' coerente con lo stato
	var ranking := s.victory.ranking
	t.assert_true(ranking.size() > 0, "classifica non vuota")
	t.assert_eq(str(ranking), str(VictoryProcessor.standings(s)), "la classifica dell'esito e' quella dello stato")
	t.assert_eq(str(end_event["classifica"]), str(ranking), "l'evento porta la stessa classifica")
	var total := VictoryProcessor.total_provinces(s)
	var sum := 0
	var seen := {}
	var previous_provinces := 1000000
	var position := 0
	for row in ranking:
		var r: Dictionary = row
		position += 1
		var id := str(r["fazione"])
		t.assert_false(seen.has(id), "fazione ripetuta in classifica: %s" % id)
		seen[id] = true
		t.assert_eq(int(r["posizione"]), position, "posizioni consecutive")
		t.assert_true(id != GameState.REBEL, "i ribelli non sono in classifica")
		t.assert_true(s.faction(id).alive, "solo fazioni vive: %s" % id)
		t.assert_eq(int(r["province"]), s.provinces_of(id).size(), "province di %s" % id)
		t.assert_true(int(r["province"]) <= previous_provinces, "ordinata per province")
		previous_provinces = int(r["province"])
		t.assert_true(absf(float(r["quota"]) - float(int(r["province"])) / float(total)) < 0.0001, "quota di %s" % id)
		sum += int(r["province"])
	t.assert_true(sum <= total, "le province in classifica non superano il totale")
	t.assert_eq(str(end_event["vincitore"]), str((ranking[0] as Dictionary)["fazione"]), "il vincitore e' il primo")
	var best := 0
	for f in s.factions:
		if f.id != GameState.REBEL:
			best = maxi(best, s.provinces_of(f.id).size())
	t.assert_eq(int((ranking[0] as Dictionary)["province"]), best, "il primo ha il massimo di province")
	print("   1700: primo %s con %d province su %d; fazioni in classifica: %d" % [str(end_event["vincitore"]), best, total, ranking.size()])
	var again := TurnProcessor.end_year(s)
	t.assert_false(bool(again["ok"]), "dopo il 1700 non si va avanti")
