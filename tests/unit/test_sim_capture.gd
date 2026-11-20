extends RefCounted
## Test di conquiste, fazioni distrutte, coerenza dello stato in una guerra lunga e salvataggi
## (versione 2 e compatibilita' con la 1) sul mondo piccolo tests/fixtures/sim_*.txt.
##   Esercito 1 = ALPHA in ALTA (160), 2 = flotta ALPHA, 3 = ALPHA in BASSA (80), 4 = BETA in MEZZA (60),
##   5 = ribelli in SOLA (50). MEZZA ha Castle2 e porto; ALPHA ha ALTA e BASSA, BETA solo MEZZA.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"

var _campaign: CampaignData
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable
## Eventi contati dalle guerre lunghe (per sapere che la prova ha davvero provato qualcosa).
var _count_battles := 0
var _count_captures := 0


func _load_static() -> void:
	if _campaign == null:
		_campaign = StartposLoader.load_file(STARTPOS)
		_units = UnitProdLoader.load_file(UNITS)
		_buildings = BuildingProdLoader.load_file(BUILDINGS)


func _world(seed_value: int = 1) -> GameState:
	_load_static()
	return GameSetup.new_game(_campaign, _units, _buildings, Rules.new(), seed_value)


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _invade(s: GameState, army: Army, to_region: String) -> void:
	army.from_region = army.region
	army.region = to_region
	army.arrived_year = s.year


func _men_total(s: GameState) -> int:
	var total := 0
	for a in s.armies:
		total += a.men_total()
	return total


## Uomini persi in un anno secondo il registro (battaglie, catture, resa per fame).
func _men_lost(s: GameState) -> int:
	var total := 0
	for e in _events_of(s, GameState.EV_BATTLE):
		total += int(e["perdite_attaccante"]) + int(e["perdite_difensore"])
	for e in _events_of(s, GameState.EV_CAPTURED_UNITS):
		total += int(e["uomini"])
	for e in _events_of(s, GameState.EV_STARVED):
		total += int(e["uomini"])
	return total


## Uomini arrivati con i reclutamenti dell'anno e prigionieri tornati a casa (liberati o riscattati, ADR-073).
func _men_recruited(s: GameState) -> int:
	var total := 0
	for e in _events_of(s, GameState.EV_RECRUITED):
		total += s.units.get_unit(str(e["unita"])).men
	for e in _events_of(s, GameState.EV_PRISONERS):
		if str(e["esito"]) == PrisonerProcessor.OUTCOME_RELEASED or str(e["esito"]) == PrisonerProcessor.OUTCOME_RANSOMED:
			total += int(e["uomini"])
	return total


# --- conquista -----------------------------------------------------------------------------------


func test_provincia_senza_difensori_cade_subito(t: TestContext) -> void:
	var s := _world()
	# BETA tiene anche SOLA (cosi' non e' distrutta) e perde la guarnigione di MEZZA
	s.remove_army(s.army(5))
	s.province("ID_SOLA").owner = "FN_BETA"
	s.remove_army(s.army(4))
	var mezza := s.province("ID_MEZZA")
	mezza.tax_level = 4
	t.assert_true(bool(GameCommands.queue_building(s, "FN_BETA", "ID_MEZZA", "MOSQUE")["ok"]))
	t.assert_true(bool(GameCommands.queue_unit(s, "FN_BETA", "ID_MEZZA", "Nizari")["ok"]))
	t.assert_eq(mezza.building_queue.size(), 1)
	t.assert_true(bool(GameCommands.order_move(s, "FN_ALPHA", 3, PackedStringArray(["ID_MEZZA"]))["ok"]))
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0)
	t.assert_eq(mezza.owner, "FN_ALPHA", "conquista immediata: nessun esercito, nessuna guarnigione")
	t.assert_eq(mezza.building_queue.size(), 0, "code di costruzione svuotate")
	t.assert_eq(mezza.unit_queue.size(), 0, "code di reclutamento svuotate")
	t.assert_eq(mezza.tax_level, 2, "tassa normale")
	t.assert_eq(mezza.level_of("CASTLE"), 2, "edifici mantenuti")
	t.assert_eq(mezza.level_of("PORT"), 1)
	t.assert_eq(mezza.level_of("MOSQUE"), 0, "la moschea in coda non e' stata costruita")
	var captured := _events_of(s, GameState.EV_PROVINCE_CAPTURED)
	t.assert_eq(captured.size(), 1)
	t.assert_eq(captured[0]["fazione"], "FN_ALPHA")
	t.assert_eq(captured[0]["regione"], "ID_MEZZA")
	t.assert_eq(captured[0]["precedente"], "FN_BETA")
	t.assert_true(str(captured[0]["testo"]).contains("Mezza") and str(captured[0]["testo"]).contains("Beta"), str(captured[0]["testo"]))
	t.assert_eq(_events_of(s, GameState.EV_WAR_DECLARED).size(), 1)
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 0, "nessuno da combattere")
	# il nuovo proprietario incassa gia' quest'anno: 200 x 0,52 con tassa normale, provincia non contesa
	t.assert_eq(mezza.last_income["totale"], 104)
	t.assert_eq(mezza.last_income["conteso"], false)
	t.assert_true(s.faction("FN_BETA").alive, "BETA ha ancora SOLA")


func test_conquista_di_una_provincia_ribelle_senza_dichiarare_guerra(t: TestContext) -> void:
	var s := _world()
	s.remove_army(s.army(5))
	GameCommands.order_move(s, "FN_BETA", 4, PackedStringArray(["ID_SOLA"]))
	s.faction("FN_REBEL").alive = true   # per provare che i ribelli non vengono mai distrutti
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_SOLA").owner, "FN_BETA")
	t.assert_eq(_events_of(s, GameState.EV_WAR_DECLARED).size(), 0)
	t.assert_eq(_events_of(s, GameState.EV_PROVINCE_CAPTURED)[0]["precedente"], "FN_REBEL")
	t.assert_eq(_events_of(s, GameState.EV_FACTION_DESTROYED).size(), 0, "i ribelli non si distruggono")
	t.assert_true(s.faction("FN_REBEL").alive)
	t.assert_eq(s.army(4).region, "ID_SOLA")
	# BETA ha lasciato MEZZA senza difensori, ma nessuno e' in guerra con lei che la prenda
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA")


func test_senza_guerra_nessuna_conquista(t: TestContext) -> void:
	var s := _world()
	s.remove_army(s.army(4))
	_invade(s, s.army(3), "ID_MEZZA")   # ALPHA e BETA sono in pace
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA")
	t.assert_eq(_events_of(s, GameState.EV_PROVINCE_CAPTURED).size(), 0)


func test_un_esercito_in_campo_difende_la_provincia(t: TestContext) -> void:
	# due eserciti di fazioni in guerra nella stessa provincia: finche' il proprietario ne ha uno, non cade
	var s := _world()
	s.declare_war("FN_ALPHA", "FN_BETA")
	s.army(3).region = "ID_MEZZA"
	s.rules.combat.forced_outcome = -1   # vince il proprietario: ALPHA si ritira in BASSA
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_BETA")
	t.assert_eq(s.army(3).region, "ID_BASSA")


# --- fazioni distrutte -----------------------------------------------------------------------------


func test_fazione_senza_province_ne_eserciti_e_distrutta(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.province("ID_MEZZA").buildings.erase("CASTLE")   # nessun castello: l'esercito sconfitto e' catturato
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_ALPHA")
	t.assert_true(s.army(4) == null)
	t.assert_false(s.faction("FN_BETA").alive, "BETA non ha piu' province ne' eserciti")
	var destroyed := _events_of(s, GameState.EV_FACTION_DESTROYED)
	t.assert_eq(destroyed.size(), 1)
	t.assert_eq(destroyed[0]["fazione"], "FN_BETA")
	t.assert_true(str(destroyed[0]["testo"]).contains("Beta"), str(destroyed[0]["testo"]))
	t.assert_true(s.faction("FN_ALPHA").alive)
	# l'anno dopo: nessun nuovo evento, il tesoro di BETA non cambia piu'
	var treasury := s.faction("FN_BETA").treasury
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_FACTION_DESTROYED).size(), 0)
	t.assert_eq(s.faction("FN_BETA").treasury, treasury, "una fazione distrutta non incassa")


func test_una_flotta_basta_a_restare_in_vita(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.province("ID_MEZZA").buildings.erase("CASTLE")
	var fleet := s.create_army("FN_BETA", "ID_MARE_SUD", true)
	fleet.stacks.append(UnitStack.new("Galley", 2, 0))
	s.declare_war("FN_ALPHA", "FN_BETA")
	_invade(s, s.army(3), "ID_MEZZA")
	TurnProcessor.end_year(s)
	t.assert_eq(s.province("ID_MEZZA").owner, "FN_ALPHA")
	t.assert_true(s.faction("FN_BETA").alive, "ha ancora una flotta")
	t.assert_eq(_events_of(s, GameState.EV_FACTION_DESTROYED).size(), 0)
	# senza flotta e senza province: distrutta
	s.remove_army(fleet)
	TurnProcessor.end_year(s)
	t.assert_false(s.faction("FN_BETA").alive)


func test_una_provincia_basta_a_restare_in_vita(t: TestContext) -> void:
	var s := _world()
	s.remove_army(s.army(4))   # nessun esercito, ma MEZZA e' ancora sua
	TurnProcessor.end_year(s)
	t.assert_true(s.faction("FN_BETA").alive)
	t.assert_eq(_events_of(s, GameState.EV_FACTION_DESTROYED).size(), 0)


# --- coerenza in una guerra lunga --------------------------------------------------------------------


## Controlla le proprieta' che devono valere alla fine di ogni anno. Restituisce il primo problema o "".
func _problem(s: GameState) -> String:
	for p in s.provinces:
		var owner_state := s.faction(p.owner)
		if owner_state == null:
			return "%s: proprietario sconosciuto %s" % [p.id, p.owner]
		if not owner_state.alive and owner_state.id != GameState.REBEL:
			return "%s: proprietario non vivo %s" % [p.id, p.owner]
	var ids := {}
	for a in s.armies:
		if ids.has(a.id):
			return "esercito %d duplicato" % a.id
		ids[a.id] = true
		if a.stacks.is_empty():
			return "esercito %d senza pile" % a.id
		for st in a.stacks:
			if st.men < 1:
				return "esercito %d: pila con %d uomini" % [a.id, st.men]
		var region := _campaign.region(a.region)
		if region == null or region.is_sea != a.is_fleet:
			return "esercito %d in %s" % [a.id, a.region]
		var f := s.faction(a.faction)
		if f == null or (not f.alive and f.id != GameState.REBEL):
			return "esercito %d di una fazione non viva (%s)" % [a.id, a.faction]
		if a.in_castle:
			var province := s.province(a.region)
			if a.is_fleet or province == null or province.owner != a.faction:
				return "esercito %d nel castello di %s ma non e' del proprietario" % [a.id, a.region]
	for siege in s.sieges_in_order():
		var province := s.province(siege.region)
		if province == null or not s.at_war(siege.faction, province.owner):
			return "assedio di %s senza guerra" % siege.region
		var inside := 0
		var outside := 0
		for a in s.armies_in(siege.region):
			if a.in_castle:
				inside += 1
			elif a.faction == siege.faction:
				outside += 1
		if inside == 0 or outside == 0:
			return "assedio di %s senza guarnigione (%d) o assedianti (%d)" % [siege.region, inside, outside]
		for army_id in siege.army_ids:
			var besieger := s.army(army_id)
			if besieger == null or besieger.region != siege.region or besieger.in_castle:
				return "assedio di %s: esercito assediante %d non valido" % [siege.region, army_id]
	for f in s.factions:
		if f.alive and f.id != GameState.REBEL and s.provinces_of(f.id).is_empty() and s.armies_of(f.id).is_empty():
			return "%s e' viva senza nulla" % f.id
	return ""


## Ordini casuali (generatore a parte, non state.rng): ogni fazione attacca a caso un vicino.
func _random_orders(s: GameState, rng: RandomNumberGenerator, assault_chance: float) -> void:
	for f in s.factions:
		if not f.alive or f.id == GameState.REBEL:
			continue
		var movable: Array[Army] = []
		for a in s.armies_of(f.id):
			if not a.is_fleet and not a.in_castle and a.path.is_empty() and s.siege_in(a.region) == null:
				movable.append(a)
		if not movable.is_empty():
			var army := movable[rng.randi_range(0, movable.size() - 1)]
			var region := _campaign.region(army.region)
			var targets: Array[String] = []
			for n in region.neighbours:
				var neighbour := _campaign.region(n)
				if neighbour != null and not neighbour.is_sea:
					targets.append(neighbour.id)
			if not targets.is_empty():
				GameCommands.order_move(s, f.id, army.id, PackedStringArray([targets[rng.randi_range(0, targets.size() - 1)]]))
		for a in s.armies_of(f.id):
			if rng.randf() < assault_chance and bool(GameCommands.can_order_assault(s, f.id, a.id)["ok"]):
				GameCommands.order_assault(s, f.id, a.id)
		# di tanto in tanto si recluta
		if rng.randf() < 0.3:
			var mine := s.provinces_of(f.id)
			if not mine.is_empty():
				var province := mine[rng.randi_range(0, mine.size() - 1)]
				GameCommands.queue_unit(s, f.id, province.id, "Spearmen")


func _war_game(seed_value: int, years: int, t: TestContext) -> GameState:
	var s := _world(seed_value)
	# castelli di gradi diversi e truppe piu' numerose, per avere assedi, assalti e sortite
	s.province("ID_ALTA").set_level("CASTLE", 4)
	s.province("ID_BASSA").set_level("CASTLE", 7)
	s.faction("FN_ALPHA").treasury = 100000
	s.faction("FN_BETA").treasury = 100000
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 1
	for i in years:
		if i % 2 == 0:
			_random_orders(s, rng, 0.4)
		var before := _men_total(s)
		var res := TurnProcessor.end_year(s)
		var errs: Array = res["errori"]
		if errs.size() > 0 or not bool(res["ok"]):
			t.assert_true(false, "anno %d: errori %s" % [s.year, str(errs)])
			return s
		_count_battles += _events_of(s, GameState.EV_BATTLE).size()
		_count_captures += _events_of(s, GameState.EV_PROVINCE_CAPTURED).size()
		var after := _men_total(s)
		var expected := before + _men_recruited(s) - _men_lost(s)
		if after != expected:
			t.assert_true(false, "anno %d: uomini prima %d + reclutati %d - persi %d = %d, ma ce ne sono %d" % [s.year, before, _men_recruited(s), _men_lost(s), expected, after])
			return s
		var problem := _problem(s)
		if problem != "":
			t.assert_true(false, "anno %d: %s" % [s.year, problem])
			return s
	return s


func test_guerra_lunga_stato_coerente_e_uomini_conservati(t: TestContext) -> void:
	_load_static()
	_count_battles = 0
	_count_captures = 0
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var s := _war_game(seed_value, 60, t)
		if t.failed:
			return
		t.assert_eq(s.year, 1060)
	# le partite di prova producono davvero scontri (altrimenti la prova non proverebbe niente)
	t.assert_true(_count_battles > 0, "almeno una battaglia nelle partite di prova")
	t.assert_true(_count_captures > 0, "almeno una conquista")


func test_guerra_lunga_deterministica_e_salvabile(t: TestContext) -> void:
	_load_static()
	var a := _war_game(9, 40, t)
	var b := _war_game(9, 40, t)
	t.assert_eq(SaveGame.to_json(a), SaveGame.to_json(b), "stesso seme, stessa guerra, stesso stato")
	var c := _war_game(10, 40, t)
	t.assert_true(SaveGame.to_json(a) != SaveGame.to_json(c), "un altro seme porta a un'altra guerra")
	# salva a meta' e continua: il ricaricato e l'originale arrivano allo stesso stato
	var original := _war_game(11, 25, t)
	var restored := SaveGame.from_dict(SaveGame.to_dict(original), _campaign, _units, _buildings, Rules.new())
	t.assert_true(bool(restored["ok"]), str(restored["errore"]))
	if not bool(restored["ok"]):
		return
	var loaded: GameState = restored["stato"]
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 5
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 5
	for i in 10:
		_random_orders(original, rng_a, 0.4)
		_random_orders(loaded, rng_b, 0.4)
		TurnProcessor.end_year(original)
		TurnProcessor.end_year(loaded)
		t.assert_eq(SaveGame.to_json(loaded), SaveGame.to_json(original), "anno %d dopo il ricarico" % original.year)


# --- salvataggi ----------------------------------------------------------------------------------------------


func test_salvataggio_versione_1_si_carica_senza_guerre_ne_assedi(t: TestContext) -> void:
	_load_static()
	var s := _world()
	s.army(1).path = PackedStringArray(["ID_BASSA"])
	var d := SaveGame.to_dict(s)
	d["versione"] = 1
	d.erase("guerre")
	d.erase("assedi")
	var army_list: Array = d["eserciti"]
	for item in army_list:
		var ad: Dictionary = item
		ad.erase("nel_castello")
		ad.erase("assalto")
		ad.erase("da_regione")
		ad.erase("anno_arrivo")
	var r := SaveGame.from_dict(d, _campaign, _units, _buildings, Rules.new())
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var loaded: GameState = r["stato"]
	t.assert_true(loaded.wars.is_empty(), "guerre vuote")
	t.assert_true(loaded.sieges.is_empty(), "assedi vuoti")
	t.assert_eq(loaded.armies.size(), 5)
	for a in loaded.armies:
		t.assert_false(a.in_castle)
		t.assert_false(a.assault_ordered)
		t.assert_eq(a.from_region, "")
		t.assert_eq(a.arrived_year, 0)
	t.assert_eq(loaded.army(1).path, PackedStringArray(["ID_BASSA"]), "il resto dello stato e' intatto")
	var res := TurnProcessor.end_year(loaded)
	t.assert_true(bool(res["ok"]))
	t.assert_eq(loaded.army(1).region, "ID_BASSA")
	# il salvataggio riscritto e' della versione corrente (3 dalla fase 4a)
	t.assert_eq(SaveGame.to_dict(loaded)["versione"], SaveGame.VERSION)


func test_salvataggio_versione_2_conserva_guerre_e_stato_degli_eserciti(t: TestContext) -> void:
	_load_static()
	var s := _world()
	s.declare_war("FN_BETA", "FN_ALPHA")
	s.army(3).in_castle = true
	s.army(3).assault_ordered = true
	s.army(3).from_region = "ID_MEZZA"
	s.army(3).arrived_year = 1000
	var d := SaveGame.to_dict(s)
	t.assert_eq(d["guerre"], ["FN_ALPHA|FN_BETA"])
	t.assert_eq((d["assedi"] as Array).size(), 0)
	var r := SaveGame.from_dict(d, _campaign, _units, _buildings, Rules.new())
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var loaded: GameState = r["stato"]
	t.assert_true(loaded.at_war("FN_ALPHA", "FN_BETA"))
	t.assert_true(loaded.army(3).in_castle)
	t.assert_true(loaded.army(3).assault_ordered)
	t.assert_eq(loaded.army(3).from_region, "ID_MEZZA")
	t.assert_eq(loaded.army(3).arrived_year, 1000)
	t.assert_eq(SaveGame.to_json(loaded), SaveGame.to_json(s))
	# un assedio in una regione sconosciuta e' un errore
	var bad := SaveGame.to_dict(s)
	bad["assedi"] = [{"regione": "ID_ATLANTIDE", "fazione": "FN_ALPHA", "anni": 0, "eserciti": []}]
	var rb := SaveGame.from_dict(bad, _campaign, _units, _buildings, Rules.new())
	t.assert_false(bool(rb["ok"]))
	t.assert_true(str(rb["errore"]).contains("Assedio"), str(rb["errore"]))
