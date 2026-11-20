extends RefCounted
## Test sul file reale EARLY_XL.TXT dell'installazione (XL 3.0 + Auror).
## Vengono saltati se l'installazione non si trova (vedi GameFiles).
## I valori attesi sono stati contati sul file del 2026-11-07. Solo la struttura della XL
## (fazioni, regioni, confini, rendite, porti) e' fissa: la parte Auror puo' crescere.

var _data: CampaignData


func _load(t: TestContext) -> CampaignData:
	if not GameFiles.is_available():
		t.skip("installazione di MTW non trovata in %s" % GameFiles.game_dir())
		return null
	if _data == null:
		_data = StartposLoader.load_file(GameFiles.startpos())
	return _data


func test_numeri_della_campagna(t: TestContext) -> void:
	var d := _load(t)
	if d == null:
		return
	t.assert_eq(d.factions.size(), 31, "fazioni dichiarate (ribelli compresi)")
	t.assert_eq(d.active_factions().size(), 27, "fazioni attive")
	t.assert_eq(d.land_regions().size(), 107, "regioni di terra")
	t.assert_eq(d.sea_regions().size(), 36, "zone di mare")
	t.assert_eq(d.adjacency_pairs().size(), 388, "confini")
	# Le unita' iniziali cambiano con la mod Auror (parte integrante, ancora in evoluzione):
	# 373 nella XL con il primo Auror, 549 dopo i 12 eserciti e le 3 flotte.
	t.assert_true(d.start_units.size() >= 373, "unita' iniziali: almeno quelle della XL (%d)" % d.start_units.size())


func test_date(t: TestContext) -> void:
	var d := _load(t)
	if d == null:
		return
	t.assert_eq(d.start_year, 1000)
	t.assert_eq(d.period_starts, {"EARLY": 1000, "HIGH": 1205, "LATE": 1321})
	t.assert_eq(d.unit_prod_file, "MTW_XL_EARLY_UNIT_PROD11.TXT")
	t.assert_eq(d.building_prod_file, "MTW_XL_EARLY_BUILD_PROD13.TXT")


func test_nessun_errore_e_confini_simmetrici(t: TestContext) -> void:
	var d := _load(t)
	if d == null:
		return
	t.assert_eq(d.errors, PackedStringArray(), "riferimenti non dichiarati")
	t.assert_eq(d.asymmetric_neighbours(), PackedStringArray(), "confini non reciproci")


func test_rendita_e_porti(t: TestContext) -> void:
	var d := _load(t)
	if d == null:
		return
	var total := 0
	var ports := 0
	for r in d.land_regions():
		total += r.income
		if r.has_port:
			ports += 1
	t.assert_eq(total, 44490, "somma delle rendite base")
	t.assert_eq(ports, 71, "regioni con porto")


func test_auror_integrata(t: TestContext) -> void:
	var d := _load(t)
	if d == null:
		return
	var owned := PackedStringArray()
	for r in d.regions_owned_by("FN_DANISH"):
		owned.append(r.id)
	owned.sort()
	t.assert_eq(owned, PackedStringArray(["ID_DENMARK", "ID_NORWAY", "ID_SCANIA", "ID_SWEDEN"]))
	var f := d.faction("FN_DANISH")
	t.assert_eq(f.treasury, PackedInt32Array([99999, 99999, 99999, 99999]))
	t.assert_eq(f.leader_region, "ID_DENMARK")
	t.assert_eq(d.region("ID_DENMARK").buildings.has("Castle15"), true, "fortezza al massimo")
