extends RefCounted
## Papato, scomunica, crociate e jihad (fase 5c) sui dati reali, saltati se l'installazione manca. Nessun numero dipende
## dai dati: solo invarianti (scomunicati solo cattolici, al piu' una crociata attiva per fazione, eserciti crociati
## della religione giusta, nessuna coppia insieme alleata e in guerra), determinismo, salvataggio e assenza di errori.
## Gli ordini casuali (crociate, bersagli, attacchi) vengono da un generatore del test, mai da `state.rng`.

const W := preload("res://tests/unit/papacy_world.gd")
const SEED := 20261109
const YEARS := 200

var _campaign: CampaignData
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable
var _heroes: HeroesData


func _load_static(t: TestContext) -> bool:
	if _campaign != null:
		return true
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata in %s" % GameFiles.game_dir())
		return false
	var campaign := StartposLoader.load_file(GameFiles.startpos())
	var unit_path := GameFiles.prod_file(campaign.unit_prod_file)
	var building_path := GameFiles.prod_file(campaign.building_prod_file)
	var heroes_path := GameFiles.heroes_file(HeroesLoader.DEFAULT_FILE)
	if not FileAccess.file_exists(unit_path) or not FileAccess.file_exists(building_path) or not FileAccess.file_exists(heroes_path):
		t.skip("file prod o dei nomi non trovati in %s" % GameFiles.game_dir())
		return false
	_units = UnitProdLoader.load_file(unit_path)
	_buildings = BuildingProdLoader.load_file(building_path)
	_heroes = HeroesLoader.load_file(heroes_path)
	_campaign = campaign
	return true


func _new_game(seed_value: int = SEED) -> GameState:
	return GameSetup.new_game(_campaign, _units, _buildings, Rules.load_file(), seed_value, _heroes)


## Ordini casuali di un anno, nell'ordine fisso delle fazioni: crociate e jihad in coda, bersagli per gli eserciti
## crociati, qualche attacco per terra (che puo' provocare avvertimenti e scomuniche) e religiosi in coda.
func _drive(s: GameState, rng: RandomNumberGenerator) -> void:
	for f in s.factions:
		if f.id == GameState.REBEL or not f.alive:
			continue
		var owned := s.provinces_of(f.id)
		if owned.is_empty():
			continue
		if rng.randf() < 0.3:
			var p: ProvinceState = owned[rng.randi_range(0, owned.size() - 1)]
			GameCommands.queue_unit(s, f.id, p.id, "Crusade" if rng.randf() < 0.5 else "Jihad")
	for a in s.armies:
		if a.is_fleet or a.faction == GameState.REBEL or s.faction(a.faction) == null or not s.faction(a.faction).alive:
			continue
		if a.is_crusade():
			if a.crusade_target() == "" and a.path.is_empty():
				var list: Array = GameCommands.crusade_targets(s, a.faction, a.id)["bersagli"]
				if not list.is_empty():
					var o: Dictionary = list[rng.randi_range(0, list.size() - 1)]
					GameCommands.set_crusade_target(s, a.faction, a.id, str(o["regione"]))
		elif a.path.is_empty() and rng.randf() < 0.05:
			var region := s.campaign.region(a.region)
			if region != null and not region.neighbours.is_empty():
				var n: String = region.neighbours[rng.randi_range(0, region.neighbours.size() - 1)]
				var target := s.campaign.region(n)
				if target != null and not target.is_sea:
					GameCommands.order_move(s, a.faction, a.id, PackedStringArray([SimUtil.norm(n)]))


func _simulate(t: TestContext, seed_value: int) -> Dictionary:
	var s := _new_game(seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	var counts := {}
	var errors := 0
	for i in YEARS:
		_drive(s, rng)
		var res := TurnProcessor.end_year(s)
		if not bool(res["ok"]):
			break
		errors += (res["errori"] as Array).size()
		for e in s.events:
			var kind := str(e["tipo"])
			counts[kind] = int(counts.get(kind, 0)) + 1
		if i % 10 == 9:
			W.check_state(t, s, "anno %d" % s.year)
	W.check_state(t, s, "fine")
	return {"json": SaveGame.to_json(s), "conteggi": counts, "errori": errors, "stato": s}


func test_il_papato_c_e_nei_dati(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	t.assert_true(s.faction(GameState.PAPAL) != null, "FN_PAPIST esiste nei dati")
	t.assert_true(PapacyProcessor.papal_alive(s))
	t.assert_true(PapacyProcessor.is_catholic(s, GameState.PAPAL))
	for f in s.factions:
		t.assert_false(f.excommunicated, "nessuno e' scomunicato all'inizio")
	t.assert_true(s.papal_warnings.is_empty())
	for a in s.armies:
		t.assert_false(a.is_crusade(), "nessuna crociata all'inizio")
	W.check_state(t, s, "inizio")


func test_duecento_anni_di_papato_deterministici(t: TestContext) -> void:
	if not _load_static(t):
		return
	var first := _simulate(t, SEED)
	var second := _simulate(t, SEED)
	t.assert_eq(first["errori"], 0, "errori dei dati durante la simulazione")
	t.assert_eq(first["json"], second["json"], "stesso seme, stesso stato dopo %d anni" % YEARS)
	t.assert_eq(first["conteggi"], second["conteggi"])


func test_un_altro_seme_da_un_altra_partita(t: TestContext) -> void:
	if not _load_static(t):
		return
	var first := _simulate(t, SEED)
	var other := _simulate(t, SEED + 1)
	t.assert_true(first["json"] != other["json"])
	t.assert_eq(other["errori"], 0)


func test_salvataggio_a_meta_con_papato(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game(91)
	var rng := RandomNumberGenerator.new()
	rng.seed = 92
	for i in 60:
		_drive(s, rng)
		TurnProcessor.end_year(s)
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	var r := SaveGame.from_dict(data, _campaign, _units, _buildings, Rules.load_file(), _heroes)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_eq(SaveGame.to_json(back), text, "andata e ritorno")
	for i in s.factions.size():
		t.assert_eq(back.factions[i].excommunicated, s.factions[i].excommunicated, "scomunica di %s" % s.factions[i].id)
	t.assert_eq(back.papal_warnings.size(), s.papal_warnings.size())
	for i in 10:
		TurnProcessor.end_year(s)
		TurnProcessor.end_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "dopo 10 anni identici")
	W.check_state(t, back, "ricaricata")
