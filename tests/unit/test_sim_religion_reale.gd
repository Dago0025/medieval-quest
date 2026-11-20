extends RefCounted
## Religione e Inquisizione (fase 5b) sui dati reali dell'installazione, saltati se l'installazione manca. Non si fissano
## numeri che dipendono dai dati: solo invarianti (somma delle religioni esattamente 100, valori in [0, 100] e multipli
## di RELIGION_UNIT, zelo in [0, 100]), determinismo, salvataggio e assenza di errori. La simulazione lunga fa giocare
## ordini casuali (reclutamenti di religiosi, processi): il generatore e' del test, mai `state.rng`.

const SEED := 20261108
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


## Invarianti validi in ogni momento della partita.
func _check_religions(t: TestContext, s: GameState, label: String) -> void:
	for p in s.provinces:
		var sum := 0.0
		for k in ProvinceState.RELIGIONS:
			var v := p.religion_pct(k)
			t.assert_true(v >= 0.0 and v <= 100.0, "%s: %s ha %s al %s" % [label, p.id, k, str(v)])
			t.assert_eq(fmod(v, ProvinceState.RELIGION_UNIT), 0.0, "%s: %s/%s non e' un multiplo dell'unita'" % [label, p.id, k])
			sum += v
		t.assert_eq(sum, 100.0, "%s: le religioni di %s sommano %s" % [label, p.id, str(sum)])
		t.assert_true(p.zeal >= 0 and p.zeal <= 100, "%s: zelo di %s fuori scala (%d)" % [label, p.id, p.zeal])


## Ordini casuali di un anno, nell'ordine fisso delle fazioni: reclutamento di religiosi nelle province proprie e
## processi degli inquisitori.
func _drive(s: GameState, rng: RandomNumberGenerator, religious: Array[String]) -> void:
	for f in s.factions:
		if f.id == GameState.REBEL or not f.alive:
			continue
		for a in s.agents_of(f.id):
			if a.has_mission() or not a.path.is_empty():
				continue
			if ReligionProcessor.is_inquisitor(a) and rng.randf() < 0.6:
				var list: Array = GameCommands.mission_options(s, f.id, a.id)["missioni"]
				if not list.is_empty():
					var o: Dictionary = list[rng.randi_range(0, list.size() - 1)]
					GameCommands.order_mission(s, f.id, a.id, str(o["tipo"]), o["bersaglio"])
		var owned := s.provinces_of(f.id)
		if not owned.is_empty() and not religious.is_empty() and rng.randf() < 0.4:
			var p: ProvinceState = owned[rng.randi_range(0, owned.size() - 1)]
			GameCommands.queue_unit(s, f.id, p.id, religious[rng.randi_range(0, religious.size() - 1)])


func _religious_ids() -> Array[String]:
	var out: Array[String] = []
	for u in _units.agents():
		if AgentState.is_recruitable_type(u.type_name) and AgentState.RELIGIOUS_TYPES.has(u.type_name):
			out.append(u.id)
	return out


func _simulate(t: TestContext, seed_value: int) -> Dictionary:
	var s := _new_game(seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	var religious := _religious_ids()
	var counts := {}
	var errors := 0
	for i in YEARS:
		_drive(s, rng, religious)
		var res := TurnProcessor.end_year(s)
		if not bool(res["ok"]):
			break
		errors += (res["errori"] as Array).size()
		for e in s.events:
			var kind := str(e["tipo"])
			counts[kind] = int(counts.get(kind, 0)) + 1
		if i % 10 == 9:
			_check_religions(t, s, "anno %d" % s.year)
	_check_religions(t, s, "fine")
	return {"json": SaveGame.to_json(s), "conteggi": counts, "errori": errors, "stato": s}


func test_la_composizione_iniziale(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	_check_religions(t, s, "inizio")
	var share := 100.0 - s.rules.religion.other_owner_share
	for p in s.provinces:
		t.assert_eq(p.zeal, s.rules.religion.initial_zeal, "zelo iniziale di %s" % p.id)
		var major := p.majority_religion()
		t.assert_true(p.religion_pct(major) >= share, "%s: la religione principale ha almeno il %s%%" % [p.id, str(share)])
		var owner_rel := ReligionProcessor.owner_religion(s, p)
		if owner_rel != "" and owner_rel != major:
			t.assert_eq(p.religion_pct(owner_rel), float(s.rules.religion.other_owner_share), "%s: quota della religione del padrone" % p.id)


func test_le_colonne_reali_si_leggono(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	var religious := 0
	var with_conversion := 0
	for u in _units.agents():
		if not AgentState.RELIGIOUS_TYPES.has(u.type_name):
			continue
		religious += 1
		var conv := ReligionRules.parse_points(UnitProdLoader.cell(u.raw, ReligionProcessor.COL_CONVERSION))
		var zeal := ReligionRules.parse_points(UnitProdLoader.cell(u.raw, ReligionProcessor.COL_ZEAL))
		if not conv.is_empty():
			with_conversion += 1
		for k in conv.keys():
			t.assert_true(ProvinceState.RELIGIONS.has(k), "%s: religione sconosciuta '%s' in colonna 45" % [u.id, str(k)])
		for k in zeal.keys():
			t.assert_true(ProvinceState.RELIGIONS.has(k), "%s: religione sconosciuta '%s' in colonna 44" % [u.id, str(k)])
	t.assert_true(religious >= 1, "ci sono agenti religiosi nei dati")
	# ogni agente iniziale religioso ha una religione riconoscibile
	for a in s.agents:
		if a.is_religious():
			t.assert_true(ReligionProcessor.agent_religion(s, a) != "", "religione dell'agente %d (%s)" % [a.id, a.type_name])


func test_duecento_anni_di_religione_deterministici(t: TestContext) -> void:
	if not _load_static(t):
		return
	var first := _simulate(t, SEED)
	var second := _simulate(t, SEED)
	t.assert_eq(first["errori"], 0, "errori dei dati durante la simulazione")
	t.assert_eq(first["json"], second["json"], "stesso seme, stesso stato dopo %d anni" % YEARS)
	t.assert_eq(first["conteggi"], second["conteggi"])
	var s: GameState = first["stato"]
	_check_religions(t, s, "stato finale")


func test_un_altro_seme_da_un_altra_partita(t: TestContext) -> void:
	if not _load_static(t):
		return
	var first := _simulate(t, SEED)
	var other := _simulate(t, SEED + 1)
	t.assert_true(first["json"] != other["json"])
	t.assert_eq(other["errori"], 0)


func test_salvataggio_a_meta_con_religioni(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game(77)
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	var religious := _religious_ids()
	for i in 40:
		_drive(s, rng, religious)
		TurnProcessor.end_year(s)
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	var r := SaveGame.from_dict(data, _campaign, _units, _buildings, Rules.load_file(), _heroes)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_eq(SaveGame.to_json(back), text, "andata e ritorno")
	for i in s.provinces.size():
		t.assert_eq(back.provinces[i].religions, s.provinces[i].religions, "religioni di %s" % s.provinces[i].id)
		t.assert_eq(back.provinces[i].zeal, s.provinces[i].zeal)
	for i in 10:
		TurnProcessor.end_year(s)
		TurnProcessor.end_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "dopo 10 anni identici")
	_check_religions(t, back, "ricaricata")
