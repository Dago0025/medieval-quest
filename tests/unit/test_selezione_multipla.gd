extends RefCounted
## Selezione multipla degli eserciti (richiesta di Federico del 2026-11-10): con Alt si scelgono piu' pedine proprie
## (clic o riquadro) e le si manda insieme su un obiettivo trascinandone una o con il clic destro.
## La logica sta in CampaignUiGroup (src/map/campaign_ui_group.gd): qui si prova sul mondo degli agenti
## (tests/unit/agent_world.gd): ALPHA ha ALTA e BASSA (confinanti), BETA ha MEZZA (confina con BASSA), SOLA e' dei ribelli.

const W := preload("res://tests/unit/agent_world.gd")


func _world() -> GameState:
	var s := W.world()
	s.faction(W.A).is_player = true
	return s


func _extra_army(s: GameState, region_id: String) -> Army:
	var model := W.land_army(s, W.A, W.ALTA)
	var a := s.create_army(W.A, region_id, false)
	a.stacks.append(UnitStack.new(model.stacks[0].unit_id, 40, 0))
	return a


func _ids(armies: Array) -> Array[int]:
	var out: Array[int] = []
	for a in armies:
		out.append((a as Army).id)
	return out


# --- scelta delle pedine -------------------------------------------------------------------------------------------


func test_alt_clic_aggiunge_e_toglie(t: TestContext) -> void:
	var g: Array[int] = []
	g = CampaignUiGroup.toggle(g, 5)
	g = CampaignUiGroup.toggle(g, 7)
	t.assert_eq(g, [5, 7] as Array[int])
	g = CampaignUiGroup.toggle(g, 5)
	t.assert_eq(g, [7] as Array[int], "un secondo Alt+clic toglie la pedina")


func test_aggiungere_non_duplica(t: TestContext) -> void:
	var g: Array[int] = [3]
	g = CampaignUiGroup.add_all(g, [3, 4, 4] as Array[int])
	t.assert_eq(g, [3, 4] as Array[int])


func test_solo_eserciti_propri_e_vivi(t: TestContext) -> void:
	var s := _world()
	var mine := W.land_army(s, W.A, W.ALTA)
	var theirs := W.land_army(s, W.B, W.MEZZA)
	var empty := s.create_army(W.A, W.BASSA, false)
	var g: Array[int] = [mine.id, theirs.id, empty.id, 999]
	t.assert_eq(CampaignUiGroup.prune(s, W.A, g), [mine.id] as Array[int])


func test_truppe_e_navi_non_si_scelgono_insieme(t: TestContext) -> void:
	var s := _world()
	var land := W.land_army(s, W.A, W.ALTA)
	var ships := W.fleet(s, W.A, W.NORD)
	var g: Array[int] = [land.id]
	t.assert_true(CampaignUiGroup.join_problem(s, g, ships) != "", "una flotta non entra in un gruppo di truppe")
	t.assert_eq(CampaignUiGroup.join_problem(s, g, _extra_army(s, W.BASSA)), "")
	t.assert_eq(CampaignUiGroup.join_problem(s, [] as Array[int], ships), "", "il primo membro decide il genere")


func test_riquadro_tiene_solo_le_pedine_proprie_del_genere_giusto(t: TestContext) -> void:
	var s := _world()
	var land := W.land_army(s, W.A, W.ALTA)
	var other := _extra_army(s, W.BASSA)
	var ships := W.fleet(s, W.A, W.NORD)
	var theirs := W.land_army(s, W.B, W.MEZZA)
	var picked := CampaignUiGroup.from_box(s, W.A, [] as Array[int], [ships.id, land.id, theirs.id, other.id] as Array[int])
	t.assert_eq(picked, [land.id, other.id] as Array[int], "con truppe e navi nel riquadro vincono le truppe")
	var fleets_only := CampaignUiGroup.from_box(s, W.A, [] as Array[int], [ships.id] as Array[int])
	t.assert_eq(fleets_only, [ships.id] as Array[int])
	var kept := CampaignUiGroup.from_box(s, W.A, [ships.id] as Array[int], [land.id] as Array[int])
	t.assert_eq(kept, [ships.id] as Array[int], "un gruppo di navi non prende truppe")


# --- ordini di gruppo ----------------------------------------------------------------------------------------------


func test_movimento_di_gruppo_verso_una_regione(t: TestContext) -> void:
	var s := _world()
	var a := W.land_army(s, W.A, W.ALTA)
	var b := _extra_army(s, W.ALTA)
	var r := CampaignUiGroup.order_move_all(s, W.A, [a.id, b.id] as Array[int], W.BASSA)
	t.assert_eq(r["partiti"], [a.id, b.id])
	t.assert_true((r["falliti"] as Array).is_empty())
	t.assert_eq(a.path, PackedStringArray([W.BASSA]))
	t.assert_eq(b.path, PackedStringArray([W.BASSA]))


func test_attacco_di_gruppo_da_province_diverse(t: TestContext) -> void:
	var s := _world()
	var from_bassa := _extra_army(s, W.BASSA)
	var from_alta := W.land_army(s, W.A, W.ALTA)
	var r := CampaignUiGroup.order_move_all(s, W.A, [from_bassa.id, from_alta.id] as Array[int], W.MEZZA)
	t.assert_true(bool(r["attacco"]), "MEZZA e' di BETA")
	t.assert_eq(r["partiti"], [from_bassa.id], "da BASSA si arriva")
	t.assert_eq((r["falliti"] as Array).size(), 1, "da ALTA no: non confina")
	t.assert_eq(int((r["falliti"] as Array)[0]["id"]), from_alta.id)
	t.assert_true(from_alta.path.is_empty(), "chi non arriva resta fermo")
	var text := CampaignUiGroup.result_text(s, r, W.MEZZA)
	t.assert_true(text.contains("attacco"), text)
	t.assert_true(text.contains("Esercito %d" % from_alta.id), "nomina chi non parte: " + text)


func test_chi_e_gia_nella_regione_resta(t: TestContext) -> void:
	var s := _world()
	var here := _extra_army(s, W.BASSA)
	GameCommands.order_move(s, W.A, here.id, PackedStringArray([W.ALTA]))
	var mover := W.land_army(s, W.A, W.ALTA)
	var r := CampaignUiGroup.order_move_all(s, W.A, [here.id, mover.id] as Array[int], W.BASSA)
	t.assert_eq(r["restano"], [here.id])
	t.assert_true(here.path.is_empty(), "il suo movimento si annulla, come col clic destro sulla propria regione")
	t.assert_eq(r["partiti"], [mover.id])


func test_flotte_di_gruppo_seguono_la_rotta(t: TestContext) -> void:
	var s := _world()
	var f1 := W.fleet(s, W.A, W.NORD)
	var f2 := W.fleet(s, W.A, W.NORD)
	var r := CampaignUiGroup.order_move_all(s, W.A, [f1.id, f2.id] as Array[int], W.SUD)
	t.assert_eq(r["partiti"], [f1.id, f2.id])
	t.assert_eq(f2.path, PackedStringArray([W.SUD]))


func test_unione_di_gruppo_su_un_esercito(t: TestContext) -> void:
	var s := _world()
	var target := W.land_army(s, W.A, W.ALTA)
	var near := _extra_army(s, W.ALTA)
	var far := _extra_army(s, W.BASSA)
	var before := target.stacks.size()
	var r := CampaignUiGroup.merge_all(s, W.A, [near.id, far.id, target.id] as Array[int], target.id)
	t.assert_eq(r["subito"], [near.id], "nella stessa regione si unisce subito")
	t.assert_eq(r["in_arrivo"], [far.id], "dalla regione accanto all'arrivo")
	t.assert_true(s.army(near.id) == null)
	t.assert_eq(target.stacks.size(), before + 1)
	t.assert_eq(far.merge_target, target.id)
	t.assert_true(CampaignUiGroup.merge_text(s, r, target).contains("Esercito %d" % target.id))


func test_unione_senza_posto_per_tutti(t: TestContext) -> void:
	var s := _world()
	var target := W.land_army(s, W.A, W.ALTA)
	while target.stacks.size() < s.rules.max_stacks - 1:
		target.stacks.append(UnitStack.new(target.stacks[0].unit_id, 10, 0))
	var first := _extra_army(s, W.ALTA)
	var second := _extra_army(s, W.ALTA)
	var r := CampaignUiGroup.merge_all(s, W.A, [first.id, second.id] as Array[int], target.id)
	t.assert_eq(r["subito"], [first.id])
	t.assert_eq((r["falliti"] as Array).size(), 1, "il secondo non trova posto")
	t.assert_true(s.army(second.id) != null)


func test_testo_del_movimento_riuscito(t: TestContext) -> void:
	var s := _world()
	var a := W.land_army(s, W.A, W.ALTA)
	var b := _extra_army(s, W.ALTA)
	var r := CampaignUiGroup.order_move_all(s, W.A, [a.id, b.id] as Array[int], W.BASSA)
	var text := CampaignUiGroup.result_text(s, r, W.BASSA)
	t.assert_true(text.begins_with("2 eserciti"), text)
	t.assert_true(text.contains(CampaignUiText.region_name(s, W.BASSA)), text)
