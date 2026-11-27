extends RefCounted
## Unita' proprie delle fazioni nuove della mappa del mondo (ADR-116, data/unita_mondo.cfg): caricate dai modelli XL,
## solo loro tra le truppe e le navi delle fazioni nuove, edifici richiesti costruibili da ciascuna, ogni epoca coperta,
## unita' del capo, niente cavalli nelle Americhe, mercenari nelle loro terre, startpos con le unita' nuove, carte
## segnaposto dei modelli. Sui file reali; senza installazione o mappa del mondo i test si saltano.

const HORSELESS := ["FN_AZTECS", "FN_INCA", "FN_MISSISSIPPIANS"]
const LATE_HORSES := ["CahCavalieri"]   # cavalleria dei Cahokia, solo dopo l'arrivo dei cavalli (HistoricalLimits)


func _ready(t: TestContext) -> bool:
	if not WorldMap.available():
		t.skip("dati della mappa del mondo assenti")
		return false
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata")
		return false
	return true


func _load(auror: bool) -> Dictionary:
	Scenario.set_auror(auror)
	var c := Scenario.load_startpos()
	var out := {
		"campaign": c,
		"units": Scenario.load_units(GameFiles.prod_file(c.unit_prod_file)),
		"buildings": Scenario.load_buildings(GameFiles.prod_file(c.building_prod_file)),
	}
	Scenario.set_auror(true)
	return out


func test_unita_caricate_con_testi(t: TestContext) -> void:
	if not _ready(t):
		return
	for mode in [true, false]:
		var units: UnitProdLoader.UnitTable = _load(mode)["units"]
		for e in units.errors:
			t.assert_false(str(e).contains("fazioni nuove"), str(e))
		for uid in CultureUnits.ids():
			var u := units.get_unit(uid)
			t.assert_true(u != null, "%s caricata (auror=%s)" % [uid, mode])
			if u == null:
				continue
			t.assert_true(u.is_military(), "%s e' una truppa o una nave" % uid)
			t.assert_eq(u.cost, int(CultureUnits.value(uid, "costo", 0)), "costo di %s" % uid)
			t.assert_true(UnitTexts.plural_name(uid) != "" and UnitTexts.description(uid) != "", "testi di %s" % uid)
			t.assert_true(u.cultures.is_empty(), "%s senza limiti di cultura" % uid)
			var weight: Variant = CultureUnits.value(uid, "peso_ia", "")  # i mercenari non ne hanno
			if str(weight) != "":
				for profile in ["ORTHODOX_EXPANSIONIST", "BARBARIAN_RAIDER", "MUSLIM_EXPANSIONIST"]:
					t.assert_eq(u.ai_weight(profile, -1.0), float(weight), "peso IA di %s (%s)" % [uid, profile])
	t.assert_eq(CultureUnits.factions_with_units().size(), WorldFactions.ids().size(), "ogni fazione nuova ha unita' proprie")


func test_solo_truppe_proprie(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(false)
	var units: UnitProdLoader.UnitTable = d["units"]
	for fid in WorldFactions.ids():
		var own := 0
		for u in units.units:
			if not u.is_military() or not u.allows_faction(fid):
				continue
			if CultureUnits.is_culture_unit(u.id):
				own += 1
			elif u.is_ship():
				t.assert_false(_has_own_ships(units, fid), "%s: nave %s del modello pur avendo navi proprie" % [fid, u.id])
			else:
				t.assert_true(false, "%s arruola ancora la truppa straniera %s" % [fid, u.id])
		t.assert_true(own >= 8, "%s: %d unita' proprie" % [fid, own])
		var agents := 0
		for u in units.agents():
			if u.allows_faction(fid):
				agents += 1
		t.assert_true(agents >= 3, "%s recluta ancora gli agenti (%d)" % [fid, agents])
		for u in units.units:
			if u.leader_of.has(fid):
				t.assert_true(CultureUnits.is_culture_unit(u.id), "%s: unita' del capo straniera %s" % [fid, u.id])
	# le macchine d'assedio europee (ALL_FACTIONS) restano agli altri
	var trebuchet := units.get_unit("TrebuchetCrew")
	t.assert_true(trebuchet.allows_faction("FN_ENGLISH") and not trebuchet.allows_faction("FN_AZTECS"))


func _has_own_ships(units: UnitProdLoader.UnitTable, fid: String) -> bool:
	for u in units.units:
		if u.is_ship() and CultureUnits.is_culture_unit(u.id) and u.factions.has(fid):
			return true
	return false


func test_edifici_richiesti_costruibili(t: TestContext) -> void:
	if not _ready(t):
		return
	for mode in [true, false]:
		var d := _load(mode)
		var c: CampaignData = d["campaign"]
		var units: UnitProdLoader.UnitTable = d["units"]
		var buildings: BuildingProdLoader.BuildingTable = d["buildings"]
		for uid in CultureUnits.ids():
			var u := units.get_unit(uid)
			for fid in CultureUnits.factions_of(uid):
				var religion := GameCommands.religion_key(c.faction(fid).religion)
				var ok := u.requires.is_empty()
				for group in u.requires:
					var all_ok := true
					for token in group:
						var lv := buildings.resolve(token)
						var fam := buildings.get_family(lv.family) if lv != null else null
						if lv == null or not lv.allows_faction(fid) or fam == null \
								or (not fam.religions.is_empty() and not GameCommands.building_allows_religion(fam, religion)):
							all_ok = false
					if all_ok:
						ok = true
				t.assert_true(ok, "%s: edifici di %s costruibili da %s (auror=%s)" % [uid, str(u.requires), fid, mode])


func test_epoche_guardie_e_cavalli(t: TestContext) -> void:
	if not _ready(t):
		return
	var units: UnitProdLoader.UnitTable = _load(false)["units"]
	for fid in WorldFactions.ids():
		for era in ["EARLY", "HIGH", "LATE"]:
			var land := 0
			var missile := 0
			var guard := false
			for u in units.land_for(fid):
				if not CultureUnits.is_culture_unit(u.id) or not u.available_in_period(era):
					continue
				land += 1
				if u.leader_of.has(fid):
					guard = true
				if u.ammo > 0 or u.projectile != "":
					missile += 1
			t.assert_true(land >= 5, "%s nell'epoca %s: %d truppe" % [fid, era, land])
			t.assert_true(guard, "%s ha l'unita' del capo nell'epoca %s" % [fid, era])
			t.assert_true(missile >= 1, "%s ha truppe da tiro nell'epoca %s" % [fid, era])
		for u in units.land_for(fid):
			if HORSELESS.has(fid) and u.allows_faction(fid) and HistoricalLimits.is_mounted(u):   # le regionali seguono le regioni
				t.assert_true(LATE_HORSES.has(u.id), "%s: niente cavalli prima degli europei (%s)" % [fid, u.id])


func test_mercenari_nelle_loro_terre(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(false)
	var c: CampaignData = d["campaign"]
	var units: UnitProdLoader.UnitTable = d["units"]
	var count := 0
	for uid in CultureUnits.ids():
		var u := units.get_unit(uid)
		if not CultureUnits.factions_of(uid).is_empty():
			t.assert_false(u.mercenary, "%s non e' un mercenario" % uid)
			continue
		count += 1
		t.assert_true(u.mercenary and not u.regions.is_empty(), "%s: mercenario con regioni" % uid)
		t.assert_false(u.is_regional(), "%s non e' arruolabile da chi possiede le regioni" % uid)
		for r in u.regions:
			t.assert_true(c.region(r) != null, "%s: regione %s" % [uid, r])
	t.assert_true(count >= 6, "mercenari delle fazioni nuove: %d" % count)


func test_startpos_e_carte(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(true)
	var c: CampaignData = d["campaign"]
	var units: UnitProdLoader.UnitTable = d["units"]
	var news := WorldFactions.ids()
	var seen := 0
	for su in c.start_units:
		var r := c.region(su.region)
		if r == null or not news.has(r.owner):
			continue
		var u := units.get_unit(su.unit_type)
		t.assert_true(u != null and CultureUnits.is_culture_unit(su.unit_type), "%s parte con %s" % [r.owner, su.unit_type])
		if u != null:
			t.assert_true(u.allows_faction(r.owner), "%s arruola %s" % [r.owner, su.unit_type])
			seen += 1
	t.assert_true(seen > 50, "unita' di partenza delle fazioni nuove: %d" % seen)
	for uid in CultureUnits.ids():
		var model := CultureUnits.card_model(uid)
		# 27/11/2026: la carta puo' essere quella rifatta di un'altra unita' delle fazioni nuove (i Maya usano le azteche)
		var shared := CultureUnits.is_culture_unit(model) and AssetLibrary.is_remade("campmap/review_panel/Units/%s.BIF" % model)
		t.assert_true(units.get_unit(model) != null and (shared or not CultureUnits.is_culture_unit(model)), "carta segnaposto di %s: %s" % [uid, model])
	if GameFiles.is_available():
		t.assert_true(AssetLibrary.unit_card_path("JapKatanaSamurai") != "", "carta del modello per i samurai")
		t.assert_eq(AssetLibrary.unit_card_path("ChoLancieri"), "campmap/review_panel/Units/ChoLancieri.BIF", "dal 23/11/2026 tutte le 152 unita' hanno la carta propria (il segnaposto resta per quelle future)")


func test_lontano_dall_europa_solo_mercenari_del_posto(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(false)
	var rules := Rules.load_file()
	t.assert_true(rules.mercenaries.local_only("ID_KINAI") and not rules.mercenaries.local_only("ID_NORMANDY"))
	var s := GameSetup.new_game(d["campaign"], d["units"], d["buildings"], rules, 7)
	for era in ["EARLY", "HIGH", "LATE"]:
		s.era = era
		for rid in ["ID_KINAI", "ID_TOLLAN", "ID_CHOLA", "ID_KANEM"]:
			for u in MercenaryProcessor.candidates(s, rid):
				t.assert_true(CultureUnits.is_culture_unit(u.id), "%s %s: mercenario %s del posto" % [rid, era, u.id])
		t.assert_false(MercenaryProcessor.candidates(s, "ID_NORMANDY").is_empty() and era != "EARLY", "in Europa restano le compagnie della XL (%s)" % era)
	s.era = "LATE"
	var kyushu := []
	for u in MercenaryProcessor.candidates(s, "ID_KYUSHU"):
		kyushu.append(u.id)
	t.assert_true(kyushu.has("JapRonin") and kyushu.has("JapWako"), "ronin e wako nel Kyushu: %s" % str(kyushu))

## Carte e schede rifatte delle unita' delle fazioni nuove (AI Playground, tools/prepara_unita_mondo.py): le fazioni gia'
## fatte usano ognuna la propria immagine e non piu' il segnaposto del modello.
const CARTE_FATTE := {"Jap": 27, "Chn": 25, "Kor": 15, "Mon": 8, "Azt": 16, "Inc": 14, "Kan": 13, "Cah": 11, "Cho": 12, "Asia": 1, "Khm": 10}


func test_carte_fazioni_nuove_rifatte(t: TestContext) -> void:
	if not _ready(t):
		return
	_load(true)
	for prefix in CARTE_FATTE:
		var count := 0
		for uid in CultureUnits.ids():
			if not str(uid).begins_with(prefix):
				continue
			count += 1
			var path := AssetLibrary.unit_card_path(uid)
			t.assert_eq(path, "campmap/review_panel/Units/%s.BIF" % uid, "carta propria di %s" % uid)
			t.assert_true(AssetLibrary.is_remade(path), "carta rifatta di %s" % uid)
			t.assert_true(AssetLibrary.is_remade("campmap/Info_Pics/Units/%s.BIF" % uid), "scheda rifatta di %s" % uid)
		t.assert_eq(count, CARTE_FATTE[prefix], "unita' %s" % prefix)
