extends RefCounted
## Agenti e diplomazia sui dati reali dell'installazione (EARLY_XL.TXT, file prod, nomi), saltati se l'installazione
## manca. Non si fissano numeri che dipendono dai dati (quanti agenti, quali fazioni): solo coerenza, determinismo e
## assenza di errori. La simulazione lunga fa giocare agenti casuali: un generatore proprio del test (mai
## `state.rng`) sceglie missioni, movimenti, reclutamenti e marce, sempre nello stesso ordine.

const SEED := 20261108
const YEARS := 200

var _campaign: CampaignData
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable
var _heroes: HeroesData


## Carica i dati statici; falso (e test saltato) se l'installazione non c'e'.
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


## Controlli di coerenza validi in ogni momento della partita.
func _check_consistency(t: TestContext, s: GameState, label: String) -> void:
	# trattati
	for key in s.alliances.keys():
		var pair := GameState.pair_of(str(key))
		t.assert_eq(pair.size(), 2, "%s: chiave di alleanza %s" % [label, str(key)])
		if pair.size() != 2:
			continue
		t.assert_true(pair[0] != pair[1], "%s: alleanza con se stessa (%s)" % [label, str(key)])
		t.assert_false(pair[0] == GameState.REBEL or pair[1] == GameState.REBEL, "%s: alleanza con i ribelli (%s)" % [label, str(key)])
		t.assert_false(s.at_war(pair[0], pair[1]), "%s: alleati in guerra (%s)" % [label, str(key)])
		for f_id in pair:
			var f := s.faction(f_id)
			t.assert_true(f != null and f.alive, "%s: alleanza con una fazione scomparsa (%s)" % [label, f_id])
	for key in s.truces.keys():
		var pair := GameState.pair_of(str(key))
		t.assert_eq(pair.size(), 2, "%s: chiave di tregua %s" % [label, str(key)])
		if pair.size() != 2:
			continue
		t.assert_true(pair[0] != pair[1], "%s: tregua con se stessi (%s)" % [label, str(key)])
		t.assert_false(pair[0] == GameState.REBEL or pair[1] == GameState.REBEL, "%s: tregua con i ribelli (%s)" % [label, str(key)])
		t.assert_false(s.wars.has(str(key)), "%s: tregua e guerra insieme (%s)" % [label, str(key)])
		t.assert_false(s.alliances.has(str(key)), "%s: tregua e alleanza insieme (%s)" % [label, str(key)])
		t.assert_true(int(s.truces[key]) > s.year, "%s: tregua scaduta e non tolta (%s fino al %d)" % [label, str(key), int(s.truces[key])])
	# agenti
	var ids := {}
	var linked := {}
	var max_valour := s.rules.agents.max_valour
	for a in s.agents:
		t.assert_false(ids.has(a.id), "%s: id agente %d ripetuto" % [label, a.id])
		ids[a.id] = true
		var region := s.campaign.region(a.region)
		t.assert_true(region != null and not region.is_sea, "%s: agente %d in una regione non valida (%s)" % [label, a.id, a.region])
		var f := s.faction(a.faction)
		t.assert_true(f != null and f.alive and a.faction != GameState.REBEL, "%s: agente %d di una fazione non viva (%s)" % [label, a.id, a.faction])
		t.assert_true(a.valour >= 0 and a.valour <= max_valour, "%s: valore dell'agente %d fuori scala (%d)" % [label, a.id, a.valour])
		t.assert_true(a.name != "", "%s: agente %d senza nome" % [label, a.id])
		t.assert_true(a.type_name != AgentState.CRUSADE and a.type_name != AgentState.JIHAD, "%s: crociata o jihad come agente" % label)
		if a.has_mission():
			for key in ["tipo", "bersaglio", "regione", "avvicinamento"]:
				t.assert_true(a.mission.has(key), "%s: missione dell'agente %d senza '%s'" % [label, a.id, key])
		if a.type_name == AgentState.PRINCESS and a.character_id != 0:
			var c := s.character(a.character_id)
			t.assert_true(c != null and c.alive, "%s: la principessa %d non ha un personaggio vivo" % [label, a.id])
			if c != null:
				t.assert_eq(c.faction, a.faction, "%s: personaggio della principessa %d di un'altra fazione" % [label, a.id])
				t.assert_eq(c.role, Character.ROLE_PRINCESS, "%s: il personaggio della principessa %d non e' una principessa" % [label, a.id])
			t.assert_false(linked.has(a.character_id), "%s: due agenti per il personaggio %d" % [label, a.character_id])
			linked[a.character_id] = true
		elif a.character_id != 0:
			t.assert_true(false, "%s: l'agente %d (%s) e' collegato a un personaggio" % [label, a.id, a.type_name])


# --- partita nuova ------------------------------------------------------------------------------------


func test_gli_agenti_iniziali_sono_coerenti(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	t.assert_eq(s.setup_errors, PackedStringArray(), "errori di avvio")
	t.assert_true(s.agents.size() > 0, "lo startpos ha agenti")
	t.assert_eq(s.alliances.size() + s.truces.size(), 0, "nessun trattato alla partenza")
	_check_consistency(t, s, "partita nuova")
	var princesses := 0
	for a in s.agents:
		if a.type_name == AgentState.PRINCESS:
			princesses += 1
			if s.has_dynasty(a.faction):
				t.assert_true(a.character_id != 0, "principessa di %s senza personaggio" % a.faction)
	t.assert_true(princesses > 0, "lo startpos ha principesse")


func test_stesso_seme_stessi_agenti(t: TestContext) -> void:
	if not _load_static(t):
		return
	t.assert_eq(SaveGame.to_json(_new_game(5)), SaveGame.to_json(_new_game(5)))


func test_l_anteprima_delle_missioni_regge_sui_dati_reali(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	var checked := 0
	for a in s.agents.duplicate():
		var r := GameCommands.mission_options(s, a.faction, a.id)
		t.assert_true(bool(r["ok"]), str(r["errore"]))
		var list: Array = r["missioni"]
		for i in range(mini(list.size(), 4)):
			var o: Dictionary = list[i]
			var order := GameCommands.order_mission(s, a.faction, a.id, str(o["tipo"]), o["bersaglio"])
			t.assert_true(bool(order["ok"]), "agente %d (%s di %s): %s -> %s" % [a.id, a.type_name, a.faction, str(o["tipo"]), str(order["errore"])])
			checked += 1
		a.mission = {}
		a.path = PackedStringArray()
		a.sea_route = PackedStringArray()
	t.assert_true(checked > 0, "almeno una missione ordinabile")


# --- simulazione lunga con agenti casuali ------------------------------------------------------------------


## Ordini casuali di un anno, nell'ordine fisso delle fazioni e degli id: missioni e spostamenti degli agenti, qualche
## reclutamento di agenti, qualche marcia di eserciti (che dichiara guerre e rompe trattati). Il generatore e' del test.
func _drive(s: GameState, rng: RandomNumberGenerator, recruitable: Array[String]) -> void:
	for f in s.factions:
		if f.id == GameState.REBEL or not f.alive:
			continue
		for a in s.agents_of(f.id):
			if a.has_mission() or not a.path.is_empty():
				continue
			var roll := rng.randf()
			if roll < 0.55:
				var list: Array = GameCommands.mission_options(s, f.id, a.id)["missioni"]
				if not list.is_empty():
					var o: Dictionary = list[rng.randi_range(0, list.size() - 1)]
					GameCommands.order_mission(s, f.id, a.id, str(o["tipo"]), o["bersaglio"])
			elif roll < 0.85:
				var lands := _land_neighbours(s, a.region)
				if not lands.is_empty():
					GameCommands.order_agent_move(s, f.id, a.id, PackedStringArray([lands[rng.randi_range(0, lands.size() - 1)]]))
		var owned := s.provinces_of(f.id)
		if not owned.is_empty() and not recruitable.is_empty() and rng.randf() < 0.15:
			var p: ProvinceState = owned[rng.randi_range(0, owned.size() - 1)]
			GameCommands.queue_unit(s, f.id, p.id, recruitable[rng.randi_range(0, recruitable.size() - 1)])
		var armies := s.armies_of(f.id)
		if not armies.is_empty() and rng.randf() < 0.25:
			var army: Army = armies[rng.randi_range(0, armies.size() - 1)]
			if not army.is_fleet and army.path.is_empty():
				var lands := _land_neighbours(s, army.region)
				if not lands.is_empty():
					GameCommands.order_move(s, f.id, army.id, PackedStringArray([lands[rng.randi_range(0, lands.size() - 1)]]))


func _land_neighbours(s: GameState, region_id: String) -> Array[String]:
	var out: Array[String] = []
	var region := s.campaign.region(region_id)
	if region == null:
		return out
	for n in region.neighbours:
		var other := s.campaign.region(n)
		if other != null and not other.is_sea:
			out.append(other.id)
	return out


func _recruitable_ids() -> Array[String]:
	var out: Array[String] = []
	for u in _units.agents():
		if AgentState.is_recruitable_type(u.type_name):
			out.append(u.id)
	return out


## Gioca `YEARS` anni con ordini casuali. Restituisce il testo del salvataggio finale e i conteggi degli eventi.
func _simulate(t: TestContext, seed_value: int) -> Dictionary:
	var s := _new_game(seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	var recruitable := _recruitable_ids()
	var counts := {}
	var errors := 0
	var max_alliances := 0
	var max_truces := 0
	for i in YEARS:
		_drive(s, rng, recruitable)
		var res := TurnProcessor.end_year(s)
		if not bool(res["ok"]):
			break
		var errs: Array = res["errori"]
		errors += errs.size()
		max_alliances = maxi(max_alliances, s.alliances.size())
		max_truces = maxi(max_truces, s.truces.size())
		for e in s.events:
			var kind := str(e["tipo"])
			counts[kind] = int(counts.get(kind, 0)) + 1
		if i % 10 == 9:
			_check_consistency(t, s, "anno %d" % s.year)
	_check_consistency(t, s, "fine")
	return {"json": SaveGame.to_json(s), "conteggi": counts, "errori": errors, "stato": s, "alleanze": max_alliances, "tregue": max_truces}


func test_duecento_anni_di_agenti_casuali_deterministici(t: TestContext) -> void:
	if not _load_static(t):
		return
	var first := _simulate(t, SEED)
	var second := _simulate(t, SEED)
	t.assert_eq(first["errori"], 0, "errori dei dati durante la simulazione")
	t.assert_eq(first["json"], second["json"], "stesso seme, stesso stato dopo %d anni" % YEARS)
	t.assert_eq(first["conteggi"], second["conteggi"])
	var counts: Dictionary = first["conteggi"]
	var moved := int(counts.get(GameState.EV_AGENT_MOVED, 0))
	t.assert_true(moved >= 1, "gli agenti si muovono (%d spostamenti)" % moved)
	var outcomes := 0
	for kind in [GameState.EV_ALLIANCE_FORMED, GameState.EV_TRUCE, GameState.EV_PROPOSAL_REFUSED, GameState.EV_MARRIAGE,
			GameState.EV_BRIBE, GameState.EV_BRIBE_REFUSED, GameState.EV_ASSASSINATION, GameState.EV_ASSASSINATION_FAILED,
			GameState.EV_MISSION_FAILED]:
		outcomes += int(counts.get(kind, 0))
	t.assert_true(outcomes >= 1, "almeno una missione conclusa in %d anni" % YEARS)
	t.assert_true(int(counts.get(GameState.EV_AGENT_RECRUITED, 0)) >= 1, "almeno un agente nato")


func test_un_altro_seme_da_un_altra_partita(t: TestContext) -> void:
	if not _load_static(t):
		return
	var first := _simulate(t, SEED)
	var other := _simulate(t, SEED + 1)
	t.assert_true(first["json"] != other["json"])
	t.assert_eq(other["errori"], 0)


func test_salvataggio_a_meta_con_agenti_e_trattati(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game(77)
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	var recruitable := _recruitable_ids()
	for i in 40:
		_drive(s, rng, recruitable)
		TurnProcessor.end_year(s)
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	var r := SaveGame.from_dict(data, _campaign, _units, _buildings, Rules.load_file(), _heroes)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_eq(SaveGame.to_json(back), text, "andata e ritorno")
	t.assert_eq(back.agents.size(), s.agents.size())
	t.assert_eq(back.alliances.size(), s.alliances.size())
	t.assert_eq(back.truces.size(), s.truces.size())
	for i in 10:
		TurnProcessor.end_year(s)
		TurnProcessor.end_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "dopo 10 anni identici")
	_check_consistency(t, back, "ricaricata")
