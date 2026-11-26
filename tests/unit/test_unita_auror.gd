extends RefCounted
## Unita' esclusive degli Auror (ADR-074) e immortalita' di Darkos (ADR-075), sui file reali dell'installazione: nove unita'
## da data/unita_auror.cfg solo in modalita' Auror, arruolabili solo dagli Auror e solo nei cinque territori di Atlantide (ADR-078; prima Danimarca, Svezia, Norvegia e
## Scania), «inarrestabili» (ognuna batte da sola la piu' forte unita' XL della sua classe in almeno il 95% degli scontri in
## campo aperto), il re con i Corazzieri del Drago, il re che non muore mai e che, giustiziato, ricompare in Danimarca.
## Senza installazione i test si saltano.

## ADR-078: sulla mappa del mondo le unita' esclusive si arruolano nei cinque territori di Atlantide
const HOME := ["ID_ATLANTIS", "ID_GADEIRA", "ID_AMPHERIA", "ID_MNESEIA", "ID_DIAPREPIA"]
## guardia del re: Ankalagon dal 23/11/2026 (prima i Corazzieri del Drago, che restano arruolabili)
const GUARD := "AurorAnkalagon"
const FRIGATE := "AurorDragonFrigate"

var _campaign: CampaignData
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable
var _heroes: HeroesData


func _load(t: TestContext) -> bool:
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata in %s" % GameFiles.game_dir())
		return false
	Scenario.set_auror(true)
	if _campaign == null:
		_campaign = Scenario.load_startpos()
		_units = Scenario.load_units(GameFiles.prod_file(_campaign.unit_prod_file))
		_buildings = Scenario.load_buildings(GameFiles.prod_file(_campaign.building_prod_file))
		_heroes = Scenario.load_heroes(GameFiles.heroes_file(_campaign.name_data_basename()))
	return true


func _game(t: TestContext) -> GameState:
	if not _load(t):
		return null
	var rules := Rules.load_file()
	Scenario.apply_rules(rules)
	return GameSetup.new_game(_campaign, _units, _buildings, rules, 11, _heroes)


# --- dati ---------------------------------------------------------------------------------------------------------


func test_nove_unita_lette_dal_file_con_i_loro_valori(t: TestContext) -> void:
	if not _load(t):
		return
	var cfg := ConfigFile.new()
	cfg.load(AurorUnits.FILE)
	t.assert_eq(AurorUnits.ids().size(), 12, "nove truppe, la Fregata del Drago, i cappellani (18/11/2026) e Ankalagon (23/11/2026)")
	t.assert_true(_units.errors.is_empty(), str(_units.errors))
	for uid in AurorUnits.ids():
		var u := _units.get_unit(uid)
		t.assert_true(u != null, uid)
		if u == null:
			continue
		t.assert_true(u.elite, uid)
		if AgentState.is_recruitable_type(u.type_name):
			continue   # i cappellani (agenti religiosi) hanno i loro test
		t.assert_true(u.is_military() or u.is_ship(), uid)
		t.assert_eq(u.factions, PackedStringArray(["FN_DANISH"]), uid)
		t.assert_false(u.all_factions, uid)
		t.assert_eq(u.regions, PackedStringArray() if u.is_ship() else PackedStringArray(HOME), uid)
		t.assert_eq(u.periods, PackedStringArray([UnitType.ALL_PERIODS]), "%s in ogni epoca" % uid)
		t.assert_eq(u.cost, int(cfg.get_value(uid, "costo")), uid)
		t.assert_true(UnitTexts.plural_name(uid) != "" and UnitTexts.description(uid) != "", uid)
		t.assert_true(AssetLibrary.unit_card_path(uid) != "", "carta rifatta (o del modello) di %s" % uid)
		if u.is_ship():
			continue
		t.assert_eq(u.men, int(cfg.get_value(uid, "uomini")), uid)
		t.assert_eq(u.charge_bonus, int(cfg.get_value(uid, "carica")), uid)
		t.assert_eq(u.melee_bonus, int(cfg.get_value(uid, "mischia")), uid)
		t.assert_eq(u.defence_bonus, int(cfg.get_value(uid, "difesa")), uid)
		t.assert_eq(u.armour_level, int(cfg.get_value(uid, "armatura")), uid)
		t.assert_eq(u.moral_bonus, 30 if u.unique else 12, "%s non rompe mai le righe" % uid)
		t.assert_true(u.requires.is_empty(), uid)
		t.assert_true(u.strength_multiplier > 1.0, uid)
	t.assert_eq(UnitTexts.plural_name("AurorDragonCuirassiers"), "Corazzieri del Drago")
	t.assert_eq(_units.get_unit(GUARD).general_candidate, "PREFERRED", "Ankalagon, la guardia del re")
	t.assert_eq(AurorUnits.guard_unit(), GUARD)
	t.assert_eq(_units.get_unit("AurorDragonBombard").type_name, UnitType.ARTILLERY)
	t.assert_eq(_units.get_unit("AurorSilentSisters").projectile, "ARBALEST")


func test_fregata_del_drago_con_i_valori_della_vecchia_caracca(t: TestContext) -> void:
	if not _load(t):
		return
	var f := _units.get_unit(FRIGATE)
	t.assert_true(f != null and f.is_ship() and f.is_ship_data, "nave con i dati della colonna 33")
	if f == null:
		return
	# i valori che la caracca aveva nella mod Auror fino al 16/11/2026
	t.assert_eq([f.cost, f.support_cost, f.build_time], [300, 3, 1])
	t.assert_eq([f.ship_range, f.ship_attack, f.ship_defence, f.ship_speed], [3, 9, 6, 4])
	t.assert_eq(f.factions, PackedStringArray(["FN_DANISH"]))
	t.assert_true(f.regions.is_empty(), "in ogni provincia degli Auror con un porto")
	t.assert_true(f.requires.is_empty(), "nessun edificio: basta il porto")
	t.assert_eq(f.men, _units.get_unit("Carrack").men, "equipaggio del modello")
	t.assert_eq(UnitTexts.singular_name(FRIGATE), "Fregata del Drago")


func test_caracca_di_nuovo_come_nella_xl_originale(t: TestContext) -> void:
	if not _load(t):
		return
	var c := _units.get_unit("Carrack")
	t.assert_eq([c.cost, c.support_cost, c.build_time], [1500, 50, 4])
	t.assert_eq([c.ship_range, c.ship_attack, c.ship_defence, c.ship_speed], [3, 6, 3, 3])
	t.assert_true(c.factions.has("FN_ENGLISH") and c.factions.has("FN_DANISH"), "di tutte le fazioni dell'originale")
	t.assert_false(c.requires.is_empty(), "cantiere e fonderia come nella XL")
	t.assert_false(c.elite)
	var carracks := 0
	var frigates := 0
	var auror_longboats := 0
	var other_longboats := 0
	for su in _campaign.start_units:
		var mine := _campaign.region(su.region) != null and _campaign.region(su.region).owner == "FN_DANISH"
		if su.unit_type == "Carrack":
			carracks += 1
		elif su.unit_type == FRIGATE:
			frigates += 1
			t.assert_true(mine, "fregata fuori dalle regioni degli Auror: %s" % su.region)
		elif su.unit_type == "Longboat":
			if mine:
				auror_longboats += 1
			else:
				other_longboats += 1
	t.assert_eq(carracks, 0, "nessuna caracca nelle flotte di partenza")
	# 96 caracche e 4 navi lunghe (richiesta di Federico del 16/11/2026: niente navi lunghe nelle flotte Auror): cinque flotte
	# da 20 (ADR-126, 23/11/2026; prima tre flotte, 48 caracche)
	t.assert_eq(frigates, 100, "le flotte degli Auror sono di Fregate del Drago")
	t.assert_eq(auror_longboats, 0, "nessuna nave lunga degli Auror")
	t.assert_true(other_longboats > 0, "le navi lunghe delle altre fazioni restano")


func test_fregata_in_ogni_porto_degli_auror(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var coast := ""
	for p in s.provinces:
		var r := s.campaign.region(p.id)
		if not HOME.has(p.id) and not r.is_sea and r.has_port:
			coast = p.id
			break
	var owner := s.province(coast).owner
	s.province(coast).owner = "FN_DANISH"
	var ok := GameCommands.can_queue_unit(s, "FN_DANISH", coast, FRIGATE)
	t.assert_true(bool(ok["ok"]), "%s: %s" % [coast, ok.get("errore", ok)])
	s.province(coast).owner = owner
	t.assert_true(s.armies_of("FN_DANISH").any(func(a: Army) -> bool: return a.is_fleet and a.stacks.any(func(st: UnitStack) -> bool: return st.unit_id == FRIGATE)), "flotte di partenza con le fregate")


func test_nello_scenario_storico_non_esistono(t: TestContext) -> void:
	if not _load(t):
		return
	Scenario.set_auror(false)
	var plain := Scenario.load_units(GameFiles.prod_file(_campaign.unit_prod_file))
	Scenario.set_auror(true)
	for uid in AurorUnits.ids():
		t.assert_false(plain.has_unit(uid), uid)


# --- arruolamento ---------------------------------------------------------------------------------------------------


func test_solo_gli_auror_e_solo_nelle_quattro_province_d_origine(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var away := ""
	for p in s.provinces:
		if not HOME.has(p.id) and p.owner != "FN_DANISH" and not s.campaign.region(p.id).is_sea:
			away = p.id
			break
	var french := s.provinces_of("FN_FRENCH")[0].id
	for uid in AurorUnits.ids():
		if s.units.get_unit(uid).unique:
			continue   # Ankalagon non si arruola (test_ankalagon)
		for rid in HOME:
			var ok := GameCommands.can_queue_unit(s, "FN_DANISH", rid, uid)
			t.assert_true(bool(ok["ok"]), "%s in %s: %s" % [uid, rid, ok.get("errore", ok)])
		t.assert_false(bool(GameCommands.can_queue_unit(s, "FN_FRENCH", french, uid)["ok"]), "%s non e' dei Francesi" % uid)
	var owner := s.province(away).owner
	s.province(away).owner = "FN_DANISH"
	for uid in AurorUnits.ids():
		if s.units.get_unit(uid).is_ship():
			continue   # la fregata si vara in ogni porto degli Auror (test_fregata_in_ogni_porto_degli_auror)
		t.assert_false(bool(GameCommands.can_queue_unit(s, "FN_DANISH", away, uid)["ok"]), "%s non si arruola in %s" % [uid, away])
	s.province(away).owner = owner


# --- forza ----------------------------------------------------------------------------------------------------------


## Fattore di forza piu' alto che un tratto storico (ADR-089) da' a questa unita' (1 senza tratti).
static func _best_trait(s: GameState, u: UnitType) -> float:
	var top := 1.0
	for id in s.rules.traits.table.keys():
		top = maxf(top, s.rules.traits.strength_factor(str(id), u))
	return top


static func _class_of(u: UnitType) -> String:
	if u.is_artillery():
		return "ARTIGLIERIA"
	var missile := u.projectile != "" and u.projectile != "NONE"
	return "%s%s" % [u.type_name, "_TIRO" if missile else ""]


func test_inarrestabili_contro_la_migliore_unita_xl_della_classe(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var region := HOME[0]
	var best := {}
	for u in s.units.military():
		if u.elite or u.is_ship() or u.men <= 0:
			continue
		var probe := s.create_army("FN_FRENCH", region, false)
		probe.stacks.append(s.new_stack("FN_FRENCH", u.id, u.men))
		# ADR-089: la migliore unita' XL con il tratto storico piu' forte per la sua classe (Francesi, Mongoli, Inglesi...)
		var strength := Combat.army_strength(s, probe) / s.rules.traits.strength_factor("FN_FRENCH", u) * _best_trait(s, u)
		s.remove_army(probe)
		var key := _class_of(u)
		if not best.has(key) or strength > float(best[key][1]):
			best[key] = [u.id, strength]
	var mult := Combat.defender_multiplier(s, BattleResult.KIND_FIELD, 0)
	for uid in AurorUnits.ids():
		var u := s.units.get_unit(uid)
		if u.is_ship() or AgentState.is_recruitable_type(u.type_name):
			continue   # la fregata ha i valori della vecchia caracca, non e' «inarrestabile»; i cappellani sono agenti
		var army := s.create_army("FN_DANISH", region, false)
		army.stacks.append(s.new_stack("FN_DANISH", uid, u.men))
		var fa := Combat.army_strength(s, army)
		s.remove_army(army)
		var rival: Array = best[_class_of(u)]
		var p := Combat.win_probability(fa, float(rival[1]) * mult)
		t.assert_true(p >= 0.95, "%s contro %s in difesa: %.3f" % [uid, rival[0], p])


# --- guardia del re -------------------------------------------------------------------------------------------------


static func _has_guard(army: Army) -> bool:
	if army == null:
		return false
	for st in army.stacks:
		if st.unit_id == GUARD:
			return true
	return false


func test_darkos_comincia_con_ankalagon(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var king := s.leader_of("FN_DANISH")
	t.assert_true(king != null and king.full_name().contains("Darkos"))
	var army := s.army(king.army)
	t.assert_true(_has_guard(army), "esercito del re con la guardia")
	t.assert_true(army.stacks.size() <= s.rules.max_stacks)
	t.assert_eq(army.stacks[CampaignUiText.commander_stack(s, army)].unit_id, GUARD, "la carta del re e' quella di Ankalagon")
	t.assert_eq(army.stacks.size(), s.rules.max_stacks, "armata completa")
	for st in army.stacks:
		t.assert_true(AurorUnits.is_auror_unit(st.unit_id), "solo unita' esclusive: %s" % st.unit_id)
		t.assert_eq(st.value, 9, st.unit_id)
	for a in s.armies:
		if a != army:
			t.assert_false(_has_guard(a), "una sola guardia")


## ADR-126 (richiesta di Federico del 23/11/2026): alla partenza gli Auror hanno solo tre armate d'elite complete (quella di
## Darkos e due con un generale nelle altre province) e cinque flotte complete di Fregate del Drago.
func test_alla_partenza_tre_armate_d_elite_e_cinque_flotte(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var king := s.leader_of("FN_DANISH")
	var land: Array[Army] = []
	var fleets: Array[Army] = []
	for a in s.armies_of("FN_DANISH"):
		if a.is_fleet:
			fleets.append(a)
		else:
			land.append(a)
	t.assert_eq(land.size(), 3, "tre armate")
	var regions := {}
	for a in land:
		t.assert_eq(a.stacks.size(), s.rules.max_stacks, "armata completa")
		for st in a.stacks:
			t.assert_true(AurorUnits.is_auror_unit(st.unit_id), "solo unita' esclusive: %s" % st.unit_id)
		t.assert_true(s.commander_of(a.id) != null, "ogni armata ha un comandante")
		regions[a.region] = true
	t.assert_true(land.any(func(a: Army) -> bool: return a.id == king.army), "una e' quella di Darkos")
	t.assert_eq(regions.size(), 3, "una per provincia")
	t.assert_eq(fleets.size(), 5, "cinque flotte")
	for f in fleets:
		t.assert_eq(f.stacks.size(), s.rules.max_stacks, "flotta completa")
		for st in f.stacks:
			t.assert_eq(st.unit_id, FRIGATE)


func test_le_unita_esclusive_vengono_prima_nell_arruolamento(t: TestContext) -> void:
	if not _load(t):
		return
	var ordered := AurorUnits.elite_first(_units.military())
	t.assert_eq(ordered.size(), _units.military().size())
	var elite := 0
	for u in _units.military():
		if u.elite:
			elite += 1
	t.assert_true(elite >= 9)
	for i in elite:
		t.assert_true(ordered[i].elite, "posizione %d: %s" % [i, ordered[i].id])
	t.assert_false(ordered[elite].elite)


func test_la_guardia_torna_se_manca_e_il_re_senza_esercito_ne_riceve_uno(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var king := s.leader_of("FN_DANISH")
	var army := s.army(king.army)
	var men_before := 0
	for a in s.armies_of("FN_DANISH"):
		men_before += a.men_total()
	for i in range(army.stacks.size() - 1, -1, -1):
		if army.stacks[i].unit_id == GUARD:
			army.stacks.remove_at(i)
	while army.stacks.size() < s.rules.max_stacks:
		army.stacks.append(s.new_stack("FN_DANISH", "Spearmen", 100))
	AurorUnits.ensure_king_guard(s)
	t.assert_true(_has_guard(army), "guardia rimessa anche nell'esercito pieno")
	t.assert_eq(army.stacks.size(), s.rules.max_stacks)
	king.army = 0
	king.region = "ID_AMPHERIA"
	AurorUnits.ensure_king_guard(s)
	var fresh := s.army(king.army)
	t.assert_true(fresh != null and fresh != army and fresh.region == "ID_AMPHERIA" and _has_guard(fresh), "esercito nuovo con la sola guardia")
	TurnProcessor.end_year(s)
	t.assert_true(_has_guard(s.army(s.leader_of("FN_DANISH").army)), "dopo il fine anno")


# --- immortalita' ---------------------------------------------------------------------------------------------------


func test_regole_del_re_invulnerabile(t: TestContext) -> void:
	var r := Rules.load_file()
	t.assert_true(r.dynasty.is_king_invulnerable("FN_DANISH"))
	t.assert_eq(r.dynasty.king_refuge("FN_DANISH"), "ID_ATLANTIS", "la regione natia (Atlantide, ADR-078)")
	t.assert_false(r.dynasty.is_king_invulnerable("FN_FRENCH"))
	r.remove_faction_powers()
	t.assert_false(r.dynasty.is_king_invulnerable("FN_DANISH"), "scenario storico: re mortale")


func test_darkos_non_muore_mai(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var king := s.leader_of("FN_DANISH")
	for cause in ["assassinio", "rogo", "giustiziato", "guerra_civile", "vecchiaia"]:
		DynastyProcessor.kill(s, king, s.year + 1, cause, true)
		t.assert_true(king.alive, cause)
	var other := s.leader_of("FN_FRENCH")
	DynastyProcessor.kill(s, other, s.year + 1, "assassinio", false)
	t.assert_false(other.alive, "gli altri re restano mortali")


func test_giustiziato_ricompare_libero_in_norvegia_nello_stesso_anno(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var king := s.leader_of("FN_DANISH")
	var far := s.provinces_of("FN_FRENCH")[0].id
	s.army(king.army).region = far
	t.assert_true(PrisonerProcessor.capture_commander(s, king.army, "FN_DANISH", far, "FN_FRENCH", 0))
	t.assert_true(PrisonerProcessor.is_captive(king))
	var entry: Dictionary = s.prisoners[s.prisoners.size() - 1]
	PrisonerProcessor._execute(s, entry, PrisonerProcessor.OUTCOME_EXECUTED)
	t.assert_true(king.alive, "vivo dopo l'esecuzione")
	t.assert_false(PrisonerProcessor.is_captive(king), "libero")
	t.assert_eq(king.region, "ID_ATLANTIS", "ricompare ad Atlantide, la regione natia")
	AurorUnits.ensure_king_guard(s)
	var army := s.army(king.army)
	t.assert_true(army != null and army.region == "ID_ATLANTIS" and _has_guard(army), "con i Corazzieri")
	var last: Dictionary = s.events[s.events.size() - 1]
	t.assert_true(str(last.get("testo", "")).contains("ricompare"), str(last.get("testo", "")))
	# senza la Norvegia: la provincia degli Auror piu' vicina
	s.province("ID_ATLANTIS").owner = "FN_FRENCH"
	t.assert_true(PrisonerProcessor.refuge_of(s, "FN_DANISH", far) != "ID_ATLANTIS")
	t.assert_eq(s.province(PrisonerProcessor.refuge_of(s, "FN_DANISH", far)).owner, "FN_DANISH")


# --- regione natia ---------------------------------------------------------------------------------------------------


func test_regione_natia_in_norvegia_solo_in_modalita_auror(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	t.assert_eq(Scenario.home_region("FN_DANISH"), "ID_ATLANTIS")
	t.assert_eq(Scenario.home_region("FN_FRENCH"), "")
	t.assert_eq(_campaign.faction("FN_DANISH").leader_region, "ID_ATLANTIS", "il re parte da Atlantide")
	var king := s.leader_of("FN_DANISH")
	t.assert_eq(s.character_region(king), "ID_ATLANTIS")
	t.assert_eq(s.army(king.army).region, "ID_ATLANTIS", "l'armata del re e' ad Atlantide")
	# la regione natia ha tutti gli edifici della vecchia capitale (cariche di corte e cattedrale)
	for family in ["CHANCELLERY", "CONSTABLES_PALACE", "MARSHALS_PALACE", "ADMIRALTY", "CATHEDRAL"]:
		t.assert_true(s.province("ID_ATLANTIS").level_of(family) >= 1, "%s ad Atlantide" % family)
		t.assert_true(s.province("ID_GADEIRA").level_of(family) >= 1, "%s resta a Gadira (la vecchia capitale)" % family)
	for fam in s.buildings.families:
		t.assert_true(s.province("ID_ATLANTIS").level_of(fam.id) >= s.province("ID_GADEIRA").level_of(fam.id), "%s ad Atlantide almeno come a Gadira" % fam.id)
	Scenario.set_auror(false)
	t.assert_eq(Scenario.home_region("FN_DANISH"), "", "scenario storico: nessuna regione natia")
	var plain := Scenario.load_startpos()
	Scenario.set_auror(true)
	t.assert_eq(plain.faction("FN_DANISH").leader_region, "ID_DENMARK", "i Danesi storici restano in Danimarca")


## Cappellani del Culto Imperiale (richiesta di Federico del 18/11/2026): religiosi degli Auror che diffondono la fede imperiale.
func test_cappellani_degli_auror(t: TestContext) -> void:
	var u := _units.get_unit("AurorChaplain")
	t.assert_true(u != null, "unita' dei cappellani")
	if u == null:
		return
	t.assert_eq(u.type_name, "BISHOP", "agente religioso come il vescovo")
	t.assert_eq(u.factions, PackedStringArray(["FN_DANISH"]), "solo gli Auror")
	t.assert_true(u.regions.is_empty(), "in ogni provincia degli Auror")
	t.assert_eq(u.requires, _units.get_unit("Bishop").requires, "con gli edifici del vescovo")
	t.assert_eq(UnitTexts.singular_name("AurorChaplain"), "Cappellano")
	t.assert_eq(AssetLibrary.unit_card_path("AurorChaplain"), AssetLibrary.unit_card_path("Bishop"), "per ora la carta del vescovo")
	var a := AgentState.new(1, "FN_DANISH", "ID_X", "AurorChaplain", "BISHOP", 1000)
	t.assert_eq(CampaignUiAgents.agent_label(a), "Cappellano")
