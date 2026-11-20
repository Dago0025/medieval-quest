extends RefCounted
## Minimappa: i mari dove ci sono flotte del giocatore hanno una tinta leggermente diversa (richiesta di Federico del
## 18/11/2026: «sulla mini mappa avere un colore leggermente diverso per vedere i mari con le mie navi»).
## Mondo di prova: agent_world.gd (mari ID_MARE_NORD e ID_MARE_SUD).

const W := preload("res://tests/unit/agent_world.gd")


func test_mari_con_le_proprie_flotte(t: TestContext) -> void:
	var s := W.world()
	for a in s.armies.duplicate():
		if a.is_fleet:
			s.armies.erase(a)
	t.assert_true(OriginalHud.own_fleet_seas(s, W.A).is_empty(), "senza flotte nessun mare")
	W.fleet(s, W.A, W.NORD)
	W.fleet(s, W.B, W.SUD)
	var mine := OriginalHud.own_fleet_seas(s, "fn_alpha")
	t.assert_true(mine.has(W.NORD), "il mare della propria flotta")
	t.assert_false(mine.has(W.SUD), "non quello delle flotte altrui")
	var empty_fleet := W.fleet(s, W.A, W.SUD)
	empty_fleet.stacks.clear()
	t.assert_false(OriginalHud.own_fleet_seas(s, W.A).has(W.SUD), "una flotta senza navi non conta")


func test_colore_del_mare(t: TestContext) -> void:
	var plain := OriginalHud.sea_color(false, false)
	var seen := OriginalHud.sea_color(true, false)
	var own := OriginalHud.sea_color(true, true)
	t.assert_eq(plain, OriginalHud.SEA)
	t.assert_true(seen != plain)
	t.assert_true(own != seen and own != plain, "le proprie acque si distinguono")
	t.assert_true(own.b > seen.b, "tinta piu' azzurra")
	t.assert_true(absf(own.get_luminance() - seen.get_luminance()) < 0.12, "solo leggermente diversa")
	t.assert_eq(OriginalHud.sea_color(false, true), own, "con la flotta il mare si vede comunque")
