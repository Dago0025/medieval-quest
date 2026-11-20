extends RefCounted
## Personaggi e dinastie sui dati reali dell'installazione (EARLY_XL.TXT, file dei nomi, prod unita' ed
## edifici), saltati se l'installazione manca. Contengono la parte Auror, ancora in evoluzione: non si
## fissano numeri che ne dipendono (nomi, eta', eredi, numero di personaggi), solo coerenza, determinismo e
## assenza di errori.

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
	for f in s.factions:
		if f.id == GameState.REBEL:
			continue
		var leaders := 0
		for c in s.characters_of(f.id):
			if c.role == Character.ROLE_LEADER:
				leaders += 1
		if not f.alive:
			t.assert_eq(s.characters_of(f.id).size(), 0, "%s: %s e' estinta ma ha personaggi vivi" % [label, f.id])
			continue
		if s.has_dynasty(f.id):
			t.assert_eq(leaders, 1, "%s: %s deve avere esattamente un capo" % [label, f.id])
	var commanders := {}
	for a in s.armies:
		if a.faction == GameState.REBEL:
			continue
		var c := s.commander_of(a.id)
		if not s.has_dynasty(a.faction):
			continue
		t.assert_true(c != null, "%s: esercito %d di %s senza comandante" % [label, a.id, a.faction])
		if c == null:
			continue
		t.assert_true(c.alive and c.faction == a.faction, "%s: comandante dell'esercito %d" % [label, a.id])
		t.assert_false(commanders.has(c.id), "%s: personaggio %d al comando di due eserciti" % [label, c.id])
		commanders[c.id] = true
		t.assert_true(c.can_command(s.rules.dynasty, s.year), "%s: %s non puo' comandare" % [label, c.full_name()])
	var governors := {}
	for c in s.characters:
		if not c.alive:
			continue
		t.assert_true(c.command >= 0 and c.command <= 10 and c.dread >= 0 and c.dread <= 10 and c.loyalty >= 0 and c.loyalty <= 10 and c.influence >= 0 and c.influence <= 10, "%s: attributi di %s fuori scala" % [label, c.full_name()])
		if c.title != "":
			t.assert_false(governors.has(c.title), "%s: due governatori per %s" % [label, c.title])
			governors[c.title] = true
			var p := s.province(c.title)
			t.assert_true(p != null and p.owner == c.faction, "%s: titolo di una provincia non sua (%s)" % [label, c.title])


# --- partita nuova ----------------------------------------------------------------------------------


func test_ogni_fazione_attiva_ha_un_capo(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	t.assert_eq(s.setup_errors, PackedStringArray(), "errori di avvio")
	var active := 0
	for cf in _campaign.factions:
		if not cf.is_active():
			continue
		active += 1
		var leader := s.leader_of(cf.id)
		t.assert_true(leader != null, "%s senza capo" % cf.id)
		if leader == null:
			continue
		t.assert_true(leader.alive and leader.royal_blood and leader.male, cf.id)
		t.assert_true(leader.forename != "", "%s: nome del capo" % cf.id)
		t.assert_true(leader.old_age >= 50, "%s: soglia di vecchiaia del capo" % cf.id)
		t.assert_true(s.has_dynasty(cf.id))
		var expected_heirs := cf.heir_entries().size()
		var family := 0
		for c in s.characters_of(cf.id):
			# fase 5a: le principesse dello startpos (MakeUnit Princess) diventano anche personaggi, collegati a un agente:
			# non sono righe AddHeir e non si contano nella famiglia
			if c.role == Character.ROLE_PRINCESS and AgentMissions.princess_agent(s, c) != null:
				continue
			if c.royal_blood and c.role != Character.ROLE_LEADER:
				family += 1
		t.assert_eq(family, expected_heirs, "%s: membri della famiglia reale = righe AddHeir" % cf.id)
	t.assert_true(active >= 20, "fazioni attive: %d" % active)
	t.assert_true(s.leader_of(GameState.REBEL) == null)


func test_ogni_esercito_ha_un_comandante_vivo_della_sua_fazione(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	_check_consistency(t, s, "partita nuova")
	var with_commander := 0
	for a in s.armies:
		if a.faction != GameState.REBEL and s.commander_of(a.id) != null:
			with_commander += 1
	t.assert_true(with_commander > 0)


func test_il_capo_dei_auror(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	var king := s.leader_of("FN_DANISH")
	t.assert_true(king != null, "gli Auror hanno un capo")
	if king == null:
		return
	t.assert_eq(king.stars(s.rules, s.campaign), 9, "comando fisso")
	t.assert_eq(king.effective(Character.ATTR_LOYALTY, s.rules, s.campaign), 9)
	t.assert_eq(king.effective(Character.ATTR_INFLUENCE, s.rules, s.campaign), 9)
	t.assert_eq(king.forename, "Darkos", "unico nome reale")
	t.assert_true(king.numeral >= 1)


func test_stesso_seme_stessi_personaggi(t: TestContext) -> void:
	if not _load_static(t):
		return
	var a := _new_game(5)
	var b := _new_game(5)
	var c := _new_game(6)
	var json_a := SaveGame.to_json(a)
	t.assert_eq(json_a, SaveGame.to_json(b))
	t.assert_true(json_a != SaveGame.to_json(c))


# --- simulazione lunga --------------------------------------------------------------------------------


## Gioca `YEARS` anni. Restituisce il testo del salvataggio finale e i conteggi degli eventi.
func _simulate(t: TestContext, seed_value: int) -> Dictionary:
	var s := _new_game(seed_value)
	var counts := {}
	var errors := 0
	for i in YEARS:
		var res := TurnProcessor.end_year(s)
		if not bool(res["ok"]):
			break
		var errs: Array = res["errori"]
		errors += errs.size()
		for e in s.events:
			var kind := str(e["tipo"])
			counts[kind] = int(counts.get(kind, 0)) + 1
		if i % 40 == 39:
			_check_consistency(t, s, "anno %d" % s.year)
	_check_consistency(t, s, "fine")
	return {"json": SaveGame.to_json(s), "conteggi": counts, "errori": errors, "stato": s}


func test_duecento_anni_deterministici_con_una_successione(t: TestContext) -> void:
	if not _load_static(t):
		return
	var first := _simulate(t, SEED)
	var second := _simulate(t, SEED)
	t.assert_eq(first["errori"], 0, "errori dei dati durante la simulazione")
	t.assert_eq(first["json"], second["json"], "stesso seme, stesso stato dopo %d anni" % YEARS)
	t.assert_eq(first["conteggi"], second["conteggi"])
	var counts: Dictionary = first["conteggi"]
	t.assert_true(int(counts.get(GameState.EV_SUCCESSION, 0)) >= 1, "almeno una successione in %d anni" % YEARS)
	t.assert_true(int(counts.get(GameState.EV_DEATH, 0)) >= 1)
	t.assert_true(int(counts.get(GameState.EV_BIRTH, 0)) >= 1)
	var s: GameState = first["stato"]
	var king := s.leader_of("FN_DANISH")
	if king != null:
		t.assert_true(king.alive, "il re degli Auror non muore di vecchiaia")


func test_salvataggio_a_meta_su_dati_reali(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game(77)
	for i in 30:
		TurnProcessor.end_year(s)
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	var r := SaveGame.from_dict(data, _campaign, _units, _buildings, Rules.load_file(), _heroes)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_eq(SaveGame.to_json(back), text, "andata e ritorno")
	for i in 10:
		TurnProcessor.end_year(s)
		TurnProcessor.end_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "dopo 10 anni identici")
