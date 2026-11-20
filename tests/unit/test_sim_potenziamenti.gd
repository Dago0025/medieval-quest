extends RefCounted
## Potenziamenti delle truppe dagli edifici (TroopUpgrades, richiesta di Federico del 2026-11-13): armatura dall'Armaiolo,
## armi dal Fabbro, valore dal quarto livello delle botteghe, sui dati reali dell'installazione (saltati se manca).

var _campaign: CampaignData
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable


func _load(t: TestContext) -> bool:
	if _campaign != null:
		return true
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata")
		return false
	_campaign = StartposLoader.load_file(GameFiles.startpos())
	_units = UnitProdLoader.load_file(GameFiles.prod_file(_campaign.unit_prod_file))
	_buildings = BuildingProdLoader.load_file(GameFiles.prod_file(_campaign.building_prod_file))
	return true


func _game() -> GameState:
	return GameSetup.new_game(_campaign, _units, _buildings, Rules.load_file(), 3)


func test_lettura_dei_potenziamenti(t: TestContext) -> void:
	t.assert_eq(TroopUpgrades.parse("UPGRADE_ARMOUR(3)"), {"chiave": "armatura", "livello": 3})
	t.assert_eq(TroopUpgrades.parse(" {UPGRADE_WEAPON(2)} "), {"chiave": "armi", "livello": 2})
	t.assert_eq(TroopUpgrades.parse("UPGRADE_VALOUR(1)"), {"chiave": "valore", "livello": 1})
	t.assert_eq(TroopUpgrades.parse("UPGRADE_MORALE(1)"), {}, "il morale non ha icona: non si legge")
	var st := UnitStack.new("Spearmen", 100, 0)
	t.assert_eq(TroopUpgrades.describe(st), "")
	st.weapon = 3
	st.armour = 4
	t.assert_eq(TroopUpgrades.describe(st), "Armi: argento (+3) · armatura: oro (+4)")
	var back := UnitStack.from_dict(st.to_dict())
	t.assert_eq([back.weapon, back.armour], [3, 4], "salvati e riletti")
	t.assert_false(UnitStack.new("Spearmen", 10, 0).to_dict().has("armi"), "campi assenti senza potenziamenti")


func test_le_reclute_prendono_il_livello_degli_edifici(t: TestContext) -> void:
	if not _load(t):
		return
	var s := _game()
	s.rules.combat.start_upgrades = {}   # senza la regola degli Auror (oro per tutti): contano solo gli edifici
	var p := s.province("ID_DENMARK")
	p.buildings.erase("ARMOURER")
	p.buildings.erase("METALSMITH")
	t.assert_eq(TroopUpgrades.province_levels(s, p)["armatura"], 0, "senza armaiolo")
	p.set_level("ARMOURER", 3)
	p.set_level("METALSMITH", 4)
	var levels := TroopUpgrades.province_levels(s, p)
	t.assert_eq(levels["armatura"], 3, "armaiolo di livello 3")
	t.assert_eq(levels["armi"], 4, "fabbro di livello 4")
	var before := s.armies.size()
	var r := GameCommands.queue_unit(s, "FN_DANISH", "ID_DENMARK", "Spearmen")
	t.assert_true(bool(r["ok"]), str(r))
	TurnProcessor.end_year(s)
	var recruit: UnitStack = null
	for a in s.armies_in("ID_DENMARK"):
		for st in a.stacks:
			if st.unit_id == "Spearmen" and st.armour == 3:
				recruit = st
	t.assert_true(recruit != null, "la recluta di Danimarca ha armatura 3 (eserciti prima: %d)" % before)
	if recruit != null:
		t.assert_eq(recruit.weapon, 4, "e armi 4")


func test_effetto_negli_scontri_e_nel_riaddestramento(t: TestContext) -> void:
	if not _load(t):
		return
	var s := _game()
	var plain := UnitStack.new("Spearmen", 100, 0)
	var armed := UnitStack.new("Spearmen", 100, 0)
	armed.weapon = 2
	armed.armour = 2
	t.assert_true(Combat.stack_strength(s, armed) > Combat.stack_strength(s, plain), "le pile potenziate sono piu' forti")
	var p := s.province("ID_DENMARK")
	p.set_level("ARMOURER", 2)
	var st := UnitStack.new("Spearmen", 50, 0)
	st.armour = 3
	TroopUpgrades.upgrade_on_retrain(s, st, p)
	t.assert_eq(st.armour, 3, "il riaddestramento non abbassa il livello")
	p.set_level("ARMOURER", 4)
	TroopUpgrades.upgrade_on_retrain(s, st, p)
	t.assert_eq(st.armour, 4, "ma lo alza se la provincia ha di meglio")
	var ship := UnitStack.new("Galley", 1, 0)
	TroopUpgrades.equip_recruit(s, ship, p)
	t.assert_eq(ship.armour, 0, "le navi non ricevono potenziamenti")


func test_gli_auror_hanno_armi_e_armature_d_oro(t: TestContext) -> void:
	if not _load(t):
		return
	var s := _game()
	t.assert_eq(s.rules.combat.start_upgrades_of("FN_DANISH"), 4, "auror.cfg: armi_armatura_iniziali=4")
	var land := 0
	for a in s.armies:
		if a.faction != "FN_DANISH":
			continue
		for st in a.stacks:
			var unit := s.units.get_unit(st.unit_id)
			if TroopUpgrades.applies_to(unit):
				land += 1
				t.assert_eq([st.weapon, st.armour], [4, 4], "pila Auror %s in oro" % st.unit_id)
			else:
				t.assert_eq([st.weapon, st.armour], [0, 0], "le navi non hanno potenziamenti")
	t.assert_true(land > 0, "ci sono pile di terra Auror")
	var other := 0
	for a in s.armies:
		if a.faction != "FN_DANISH":
			for st in a.stacks:
				other += st.weapon + st.armour
	t.assert_eq(other, 0, "le altre fazioni partono senza potenziamenti")
	# salvataggio di prima di armi e armature: al caricamento le pile Auror prendono l'oro
	var data := SaveGame.to_dict(s)
	for ad in data["eserciti"]:
		for sd in ad["pile"]:
			sd.erase("armi")
			sd.erase("armatura")
	var r := SaveGame.from_dict(data, _campaign, _units, _buildings, s.rules)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	var back: GameState = r["stato"]
	var gold := true
	for a in back.armies:
		if a.faction == "FN_DANISH":
			for st in a.stacks:
				if TroopUpgrades.applies_to(back.units.get_unit(st.unit_id)) and (st.weapon != 4 or st.armour != 4):
					gold = false
	t.assert_true(gold, "salvataggio vecchio: tutte le pile di terra Auror in oro al caricamento")
