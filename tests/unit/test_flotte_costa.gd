extends RefCounted
## Distanza dalla costa delle navi (segnalazione di Federico del 18/11/2026: «nel gioco originale solo alcuni tipi di nave
## potevano andare nell'oceano»). Wiki «MTW Ships»: le galee (raggio 1) non entrano nell'Oceano Atlantico ne' nel
## Mediterraneo occidentale e centrale; raggio 2 anche le zone vicine alle coste; raggio 3 ovunque.

const W := preload("res://tests/unit/agent_world.gd")


func test_profondita_delle_zone_d_europa(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(GameFiles.startpos())
	t.assert_eq(Combat.sea_depth(campaign, "ID_ATLANTIC_OCEAN"), 2, "Oceano Atlantico lontano dalla costa")
	t.assert_eq(Combat.sea_depth(campaign, "ID_WESTERN_MED"), 2)
	t.assert_eq(Combat.sea_depth(campaign, "ID_CENTRAL_MED"), 2)
	t.assert_eq(Combat.sea_depth(campaign, "ID_IRISH_SEA"), 1, "mare costiero")
	t.assert_eq(Combat.sea_depth(campaign, "ID_FRANCE"), 0, "una regione di terra non ha profondita'")


func test_la_flotta_segue_la_nave_piu_limitata(t: TestContext) -> void:
	var s := W.world()
	var fleet := W.fleet(s, W.A, W.NORD)
	s.units = UnitProdLoader.load_file(GameFiles.prod_file("MTW_XL_EARLY_UNIT_PROD11.TXT"))   # navi vere: galea 1, cocca 2
	t.assert_eq(s.units.get_unit("Galley").ship_range, 1)
	t.assert_eq(s.units.get_unit("Cog").ship_range, 2)
	fleet.stacks.clear()
	fleet.stacks.append(UnitStack.new("Cog", 1, 0))
	var deep := Combat.fleet_depth(s, fleet)
	t.assert_true(deep >= 2)
	fleet.stacks.append(UnitStack.new("Galley", 1, 0))
	t.assert_eq(Combat.fleet_depth(s, fleet), 1, "con una galea la flotta resta sotto costa")
	t.assert_true(Combat.can_enter(s, fleet, W.SUD), "le zone costiere vanno sempre bene")
	var land := W.land_army(s, W.A, W.ALTA)
	t.assert_true(Combat.can_enter(s, land, W.SUD), "gli eserciti di terra non hanno questo limite")
	s.rules.combat.coast_limit = false
	t.assert_true(Combat.can_enter(s, fleet, W.SUD))
