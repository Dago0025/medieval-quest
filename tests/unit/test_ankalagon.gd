extends RefCounted
## Ankalagon, il drago di Darkos (richiesta di Federico del 23/11/2026: «unita' unica e non arruolabile, le statistiche
## letteralmente devastanti», un solo membro, pedina propria): sezione [AurorAnkalagon] di data/unita_auror.cfg.
## Sui file reali dell'installazione in modalita' Auror; senza installazione i test si saltano.

const ID := "AurorAnkalagon"

var _campaign: CampaignData
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable
var _heroes: HeroesData


func _game(t: TestContext) -> GameState:
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata")
		return null
	Scenario.set_auror(true)
	if _campaign == null:
		_campaign = Scenario.load_startpos()
		_units = Scenario.load_units(GameFiles.prod_file(_campaign.unit_prod_file))
		_buildings = Scenario.load_buildings(GameFiles.prod_file(_campaign.building_prod_file))
		_heroes = Scenario.load_heroes(GameFiles.heroes_file(_campaign.name_data_basename()))
	var rules := Rules.load_file()
	Scenario.apply_rules(rules)
	return GameSetup.new_game(_campaign, _units, _buildings, rules, 11, _heroes)


func _king_army(s: GameState) -> Army:
	var king := s.leader_of("FN_DANISH")
	return s.army(king.army) if king != null and king.army > 0 else null


func _count(s: GameState) -> int:
	var n := 0
	for a in s.armies:
		for st in a.stacks:
			if st.unit_id == ID:
				n += 1
	return n


func test_un_solo_membro_unico_invulnerabile(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var u := s.units.get_unit(ID)
	t.assert_true(u != null, "unita' caricata")
	if u == null:
		return
	t.assert_eq(u.men, 1, "un solo membro")
	t.assert_true(u.unique and u.invulnerable and u.elite)
	t.assert_eq(u.piece, "ankalagon")
	t.assert_eq(CampaignUiText.unit_name(ID), "Ankalagon")


func test_nell_armata_di_darkos_e_una_sola(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var army := _king_army(s)
	t.assert_true(army != null, "Darkos comanda un'armata")
	if army == null:
		return
	t.assert_eq(army.stacks[0].unit_id, ID, "Ankalagon in testa all'armata del re")
	t.assert_eq(_count(s), 1, "uno solo in tutta la partita")
	t.assert_eq(army.stacks.size(), s.rules.max_stacks, "armata completa")


func test_non_si_arruola(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	s.faction("FN_DANISH").treasury = 10000000
	for p in s.provinces_of("FN_DANISH"):
		var r := GameCommands.can_queue_unit(s, "FN_DANISH", p.id, ID)
		t.assert_false(bool(r["ok"]), p.id)
		t.assert_true(RetrainProcessor.recruit_problem(s, "FN_DANISH", p, s.units.get_unit(ID)) != "", "ne' si riaddestra")


func test_piu_forte_di_tutto_il_resto_dell_armata(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var army := _king_army(s)
	var dragon := 0.0
	var rest := 0.0
	for st in army.stacks:
		if st.unit_id == ID:
			dragon += Combat.stack_strength(s, st)
		else:
			rest += Combat.stack_strength(s, st)
	t.assert_true(dragon > rest, "Ankalagon %.0f contro le altre 19 pile d'elite %.0f" % [dragon, rest])


func test_non_perde_mai_il_suo_membro(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var army := _king_army(s)
	var list: Array[Army] = [army]
	Combat.apply_losses(list, 1.0, s.units)
	t.assert_eq(army.stacks.size(), 1, "annientata l'armata, resta il drago")
	t.assert_eq(army.stacks[0].unit_id, ID)
	t.assert_eq(army.stacks[0].men, 1)


func test_e_la_guardia_di_darkos_e_non_se_ne_separa(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	t.assert_eq(AurorUnits.guard_unit(), ID, "Ankalagon al posto dei Corazzieri")
	var army := _king_army(s)
	t.assert_false(army.stacks.any(func(st): return st.unit_id == "AurorDragonCuirassiers"), "niente Corazzieri con Darkos")
	t.assert_eq(army.stacks[CampaignUiText.commander_stack(s, army)].unit_id, ID, "la carta di Darkos e' Ankalagon")
	var idx := PackedInt32Array([0])
	t.assert_false(bool(GameCommands.split_army(s, "FN_DANISH", army.id, idx)["ok"]), "non si stacca")
	t.assert_false(bool(GameCommands.disband_stacks(s, "FN_DANISH", army.id, idx)["ok"]), "non si congeda")
	t.assert_true(bool(GameCommands.split_army(s, "FN_DANISH", army.id, PackedInt32Array([1, 2]))["ok"]), "le altre pile si")
	# se finisse in un altro esercito, a fine anno torna da Darkos: la stessa pila, non una nuova
	var other := s.create_army("FN_DANISH", army.region, false)
	other.stacks.append(army.stacks[0])
	army.stacks.remove_at(0)
	AurorUnits.ensure_king_guard(s)
	t.assert_eq(_count(s), 1, "uno solo")
	t.assert_eq(_king_army(s).stacks[0].unit_id, ID, "di nuovo con Darkos")


func test_se_sparisce_torna_da_darkos(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	var army := _king_army(s)
	army.stacks.remove_at(0)
	t.assert_eq(_count(s), 0)
	AurorUnits.ensure_king_guard(s)
	t.assert_eq(_count(s), 1, "di nuovo nell'esercito di Darkos")
	t.assert_true(_king_army(s).stacks.any(func(st): return st.unit_id == ID))


func test_pedina_del_drago(t: TestContext) -> void:
	var s := _game(t)
	if s == null:
		return
	t.assert_eq(PieceArt.special_kind(s.units, _king_army(s)), "unica:ankalagon")
	for state in ["awaiting", "moving"]:
		t.assert_true(AssetLibrary.is_remade("%s/Units/Auror/ankalagon_held_%s.BIF" % [PieceArt.BASE, state]), state)
	t.assert_true(AssetLibrary.is_remade("campmap/review_panel/Units/%s.BIF" % ID) or AssetLibrary.unit_card_path(ID) != "", "carta")
