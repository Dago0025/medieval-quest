extends RefCounted
## Separare truppe o navi trascinandole dalla barra in basso sulla mappa (richiesta di Federico del 2026-11-10).
## Mondo piccolo tests/fixtures/sim_*.txt: ALPHA ha ID_ALTA (esercito 1, flotta 2 in ID_MARE_NORD) e ID_BASSA
## (esercito 3); BETA ha ID_MEZZA (esercito 4). ALTA-BASSA-MEZZA-SOLA in fila.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


## Esercito 1 con 4 pile di lancieri in piu' (6 in tutto).
func _big(s: GameState) -> Army:
	var a := s.army(1)
	for i in 4:
		a.stacks.append(UnitStack.new("Spearmen", 100, 0))
	return a


func test_nella_stessa_regione_diventano_un_esercito_nuovo(t: TestContext) -> void:
	var s := _world()
	var a := _big(s)
	var before := a.stacks.size()
	var r := CampaignUiSplit.apply(s, "FN_ALPHA", a.id, PackedInt32Array([4, 5]), "ID_ALTA", 0, Vector2(100, 100))
	t.assert_true(bool(r["ok"]), str(r["testo"]))
	t.assert_eq(str(r["azione"]), CampaignUiSplit.DIVIDI_QUI)
	var fresh := s.army(int(r["esercito"]))
	t.assert_eq(fresh.region, "ID_ALTA")
	t.assert_eq(fresh.stacks.size(), 2)
	t.assert_eq(a.stacks.size(), before - 2)
	t.assert_eq(fresh.spot_here(), Vector2(100, 100), "la pedina sta dove la si posa")


func test_dal_castello_la_parte_separata_esce(t: TestContext) -> void:
	var s := _world()
	var a := _big(s)
	GameCommands.enter_castle(s, "FN_ALPHA", a.id)
	var r := CampaignUiSplit.apply(s, "FN_ALPHA", a.id, PackedInt32Array([0]), "ID_ALTA", 0, Vector2(50, 50))
	t.assert_true(bool(r["ok"]), str(r["testo"]))
	t.assert_false(s.army(int(r["esercito"])).in_castle)
	t.assert_true(a.in_castle, "il resto resta dentro")


func test_su_un_altra_regione_partono(t: TestContext) -> void:
	var s := _world()
	var a := _big(s)
	var r := CampaignUiSplit.apply(s, "FN_ALPHA", a.id, PackedInt32Array([1, 2]), "ID_BASSA", 0)
	t.assert_true(bool(r["ok"]), str(r["testo"]))
	t.assert_eq(str(r["azione"]), CampaignUiSplit.DIVIDI_E_MUOVI)
	var fresh := s.army(int(r["esercito"]))
	t.assert_eq(fresh.path, PackedStringArray(["ID_BASSA"]))
	t.assert_true(a.path.is_empty(), "il resto resta fermo")


func test_movimento_impossibile_le_pile_tornano(t: TestContext) -> void:
	var s := _world()
	var a := _big(s)
	var count := s.armies.size()
	var before := a.stacks.size()
	var r := CampaignUiSplit.apply(s, "FN_ALPHA", a.id, PackedInt32Array([1]), "ID_SOLA", 0)   # non confina
	t.assert_false(bool(r["ok"]))
	t.assert_eq(a.stacks.size(), before)
	t.assert_eq(s.armies.size(), count, "nessun esercito nuovo rimasto")


func test_su_un_esercito_proprio_della_stessa_regione_passano_a_lui(t: TestContext) -> void:
	var s := _world()
	var a := _big(s)
	var other := s.create_army("FN_ALPHA", "ID_ALTA", false)
	other.stacks.append(UnitStack.new("Spearmen", 100, 0))
	var r := CampaignUiSplit.apply(s, "FN_ALPHA", a.id, PackedInt32Array([0, 1]), "ID_ALTA", other.id)
	t.assert_true(bool(r["ok"]), str(r["testo"]))
	t.assert_eq(str(r["azione"]), CampaignUiSplit.TRASFERISCI)
	t.assert_eq(other.stacks.size(), 3)


func test_su_un_esercito_proprio_della_regione_accanto_si_uniranno(t: TestContext) -> void:
	var s := _world()
	var a := _big(s)
	var r := CampaignUiSplit.apply(s, "FN_ALPHA", a.id, PackedInt32Array([0]), "ID_BASSA", 3)
	t.assert_true(bool(r["ok"]), str(r["testo"]))
	t.assert_eq(str(r["azione"]), CampaignUiSplit.DIVIDI_E_UNISCI)
	t.assert_eq(s.army(int(r["esercito"])).merge_target, 3)


func test_tutte_le_pile_valgono_come_la_pedina_intera(t: TestContext) -> void:
	var s := _world()
	var a := s.army(1)
	var all := PackedInt32Array()
	for i in a.stacks.size():
		all.append(i)
	t.assert_eq(str(CampaignUiSplit.plan(s, "FN_ALPHA", a, all, "ID_BASSA", 0)["azione"]), CampaignUiSplit.TUTTO)


func test_quando_non_si_puo(t: TestContext) -> void:
	var s := _world()
	var a := _big(s)
	t.assert_eq(str(CampaignUiSplit.plan(s, "FN_ALPHA", a, PackedInt32Array(), "ID_BASSA", 0)["azione"]), CampaignUiSplit.NIENTE, "nessuna scelta")
	t.assert_eq(str(CampaignUiSplit.plan(s, "FN_ALPHA", a, PackedInt32Array([0]), "ID_MARE_NORD", 0)["azione"]), CampaignUiSplit.NIENTE, "truppe in mare")
	t.assert_eq(str(CampaignUiSplit.plan(s, "FN_ALPHA", a, PackedInt32Array([0]), "ID_ALTA", 2)["azione"]), CampaignUiSplit.NIENTE, "su una flotta")
	t.assert_eq(str(CampaignUiSplit.plan(s, "FN_BETA", a, PackedInt32Array([0]), "ID_BASSA", 0)["azione"]), CampaignUiSplit.NIENTE, "esercito altrui")


func test_le_navi_si_separano_in_una_flotta_nuova(t: TestContext) -> void:
	var s := _world()
	var fleet := s.army(2)
	fleet.stacks.append(UnitStack.new("Galley", 1, 0))
	var r := CampaignUiSplit.apply(s, "FN_ALPHA", fleet.id, PackedInt32Array([1]), fleet.region, 0, Vector2(10, 10))
	t.assert_true(bool(r["ok"]), str(r["testo"]))
	var fresh := s.army(int(r["esercito"]))
	t.assert_true(fresh.is_fleet)
	t.assert_true(str(r["testo"]).contains("nave"), str(r["testo"]))
