extends RefCounted
## Fazioni nuove della mappa del mondo e nomi propri (ADR-079), sui file reali dell'installazione: Giapponesi, Cinesi,
## Aztechi, Inca, Kanem e Cahokia (e, ADR-088, Coreani, Mongoli, Chola e Khmer) nelle loro regioni in tutte e due le modalita', con unita' ed edifici della
## fazione modello e nomi da data/nomi_personaggi.cfg; gli Auror con i loro nomi (non piu' quelli dei Danesi) solo in
## modalita' Auror. Senza installazione o senza mappa del mondo i test si saltano. Ogni test rimette la modalita' Auror.

const NEW := {"FN_JAPANESE": "ID_KINAI", "FN_CHINESE": "ID_KAIFENG", "FN_AZTECS": "ID_TOLLAN", "FN_INCA": "ID_CUZCO",
	"FN_KANEM": "ID_KANEM", "FN_MISSISSIPPIANS": "ID_MISSISSIPPI", "FN_KOREANS": "ID_KOREA", "FN_MONGOLS": "ID_MONGOLIA",
	"FN_CHOLA": "ID_CHOLA", "FN_KHMER": "ID_KHMER"}


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
		"heroes": Scenario.load_heroes(GameFiles.heroes_file(c.name_data_basename())),
	}
	Scenario.set_auror(true)
	return out


func test_fazioni_nuove_nelle_loro_regioni(t: TestContext) -> void:
	if not _ready(t):
		return
	for mode in [true, false]:
		var d := _load(mode)
		var c: CampaignData = d["campaign"]
		t.assert_true(c.errors.is_empty(), str(c.errors))
		for fid in NEW:
			var f := c.faction(fid)
			t.assert_true(f != null, "%s dichiarata (auror=%s)" % [fid, mode])
			if f == null:
				continue
			t.assert_true(f.is_active(), fid)
			t.assert_true(f.has_leader_data(), fid)
			t.assert_eq(c.region(NEW[fid]).owner, fid, "capitale di %s" % fid)
	var c2: CampaignData = _load(true)["campaign"]
	t.assert_eq(c2.faction("FN_KANEM").religion, "REL_ISLAMIC")
	t.assert_eq(c2.faction("FN_JAPANESE").religion, "REL_PAGAN")
	for r in ["ID_KYUSHU", "ID_TOHOKU"]:
		t.assert_eq(c2.region(r).owner, "FN_JAPANESE", r)
	t.assert_eq(c2.region("ID_LINGNAN").owner, "FN_CHINESE")
	t.assert_eq(c2.region("ID_LIAO").owner, "FN_REBEL", "Liao resta ai ribelli")
	t.assert_eq(c2.region("ID_EAST_MONGOLIA").owner, "FN_MONGOLS")
	for r in ["ID_DECCAN", "ID_CEYLON"]:
		t.assert_eq(c2.region(r).owner, "FN_CHOLA", r)


func test_unita_ed_edifici_della_fazione_modello(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(false)
	var units: UnitProdLoader.UnitTable = d["units"]
	for fid in NEW:
		var model := WorldFactions.model_of(fid)
		t.assert_true(model != "", "%s ha un modello" % fid)
		var mine := {}
		for u in units.land_for(fid):
			mine[u.id] = true
		t.assert_true(mine.size() > 5, "%s arruola: %d unita'" % [fid, mine.size()])
		for u in units.land_for(model):
			t.assert_true(mine.has(u.id), "%s arruola %s come %s" % [fid, u.id, model])
	var kanem := {}
	for u in units.land_for("FN_KANEM"):
		kanem[u.id] = true
	t.assert_true(kanem.has("NegroSpearmen") and kanem.has("SaharanCavalry"), "il Kanem arruola come gli Almohadi")
	var buildings: BuildingProdLoader.BuildingTable = d["buildings"]
	var shared := 0
	for fam in buildings.families:
		for lv in fam.levels:
			if lv.factions.has("FN_LITHUANIANS"):
				t.assert_true(lv.factions.has("FN_CHINESE"), "edificio %s anche per i Cinesi" % lv.token)
				shared += 1
	t.assert_true(shared > 0, "edifici riservati ai Lituani")


func test_nomi_degli_auror_e_delle_fazioni_nuove(t: TestContext) -> void:
	if not _ready(t):
		return
	var auror: HeroesData = _load(true)["heroes"]
	var names := auror.forenames_of("FN_DANISH")
	t.assert_eq(names[0], "Darkos", "Darkos e' il primo nome reale")
	t.assert_true(names.has("Atlas") and not names.has("Harald") and not names.has("Knud"), "nomi degli Auror")
	t.assert_false(auror.surnames_of("FN_DANISH").has("Forkbeard"))
	t.assert_true(auror.princess_names_of("FN_DANISH").has("Kleito"))
	t.assert_true(auror.royal_names_of("FN_DANISH").size() == 12)
	for h in auror.heroes:
		t.assert_true(h.faction != "FN_DANISH", "eroi famosi danesi tolti agli Auror: %s" % h.full_name())
	t.assert_true(auror.forenames_of("FN_DANES").has("Harald"), "i Danesi del mondo tengono i loro nomi")
	var rebels := auror.rebel_names("ID_ATLANTIS")
	t.assert_true(rebels != null and auror.forenames(rebels.forename_list).has("Atlas"), "ribelli di Atlantide")
	var historical: HeroesData = _load(false)["heroes"]
	t.assert_true(historical.forenames_of("FN_DANISH").has("Harald"), "nello storico FN_DANISH sono i Danesi")
	t.assert_eq(historical.forenames_of("FN_JAPANESE")[0], "Michinaga")
	t.assert_true(historical.forenames_of("FN_INCA").has("Pachacuti"))
	t.assert_true(historical.princess_names_of("FN_KANEM").has("Kinta"))
	t.assert_true(historical.surnames_of("FN_MISSISSIPPIANS").has("Cahokia"))
	t.assert_eq(historical.forenames_of("FN_KOREANS")[0], "Song")
	t.assert_eq(historical.forenames_of("FN_MONGOLS")[0], "Khabul")
	t.assert_eq(historical.forenames_of("FN_CHOLA")[0], "Rajaraja")
	t.assert_eq(historical.forenames_of("FN_KHMER")[0], "Jayavarman")
	t.assert_true(historical.princess_names_of("FN_CHOLA").has("Kundavai"))


func test_partita_nuova_con_i_capi_delle_fazioni_nuove(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(false)
	Scenario.set_auror(false)
	var rules := Rules.load_file()
	Scenario.apply_rules(rules)
	var s := GameSetup.new_game(d["campaign"], d["units"], d["buildings"], rules, 11, d["heroes"])
	Scenario.set_auror(true)
	t.assert_true(s.setup_errors.is_empty(), str(s.setup_errors))
	var leader := s.leader_of("FN_JAPANESE")
	t.assert_true(leader != null, "i Giapponesi hanno un capo")
	if leader != null:
		t.assert_eq(leader.forename, "Michinaga")
	for fid in NEW:
		t.assert_true(s.leader_of(fid) != null, "capo di %s" % fid)
		var armies := 0
		for a in s.armies:
			if a.faction == fid:
				armies += 1
		t.assert_true(armies >= 1, "%s ha eserciti" % fid)


## Giapponesi navali (Federico, 18/11/2026: «dai almeno un porto ai giapponesi, restano troppo statici e passivi»): partono con
## porto, cantiere e una flotta a Kinai, e l'IA li tratta come fazione navale (`navale` in data/fazioni_mondo.cfg) anche se il
## loro profilo non lo e'.
func test_giapponesi_navali(t: TestContext) -> void:
	if not _ready(t):
		return
	t.assert_true(WorldFactions.naval("FN_JAPANESE"), "Giapponesi navali")
	t.assert_false(WorldFactions.naval("FN_INCA"), "gli Inca no")
	var d := _load(true)
	var rules := Rules.load_file()
	var s := GameSetup.new_game(d["campaign"], d["units"], d["buildings"], rules, 11, d["heroes"])
	var kinai := s.province("ID_KINAI")
	t.assert_true(kinai.buildings.has("PORT") and kinai.buildings.has("SHIPYARD"), "porto e cantiere a Kinai")
	var ships := 0
	for a in s.armies:
		if a.faction == "FN_JAPANESE" and a.is_fleet:
			ships += a.stacks.size()
	t.assert_true(ships >= 2, "i Giapponesi partono con una flotta (%d navi)" % ships)
	var ctx := AiContext.build(s, AiRules.load_file(AiRules.DEFAULT_PATH), "")
	var plan := AiPlan.create(ctx, "FN_JAPANESE", "ORTHODOX_EXPANSIONIST")
	t.assert_true(plan.flag("navale"), "piano navale per i Giapponesi")
	t.assert_false(AiPlan.create(ctx, "FN_RUSSIAN", "ORTHODOX_EXPANSIONIST").flag("navale"), "il profilo resta non navale per gli altri")
	t.assert_true(bool(GameCommands.can_queue_unit(s, "FN_JAPANESE", "ID_KINAI", "Dhow")["ok"]), "Kinai arma i dhow")


## Senza sbarchi possibili, la flotta giapponese si sposta dove si affacciano bersagli: con i Cinesi alleati il Mar Cinese
## Orientale non serve, il Mar del Giappone si affaccia sui ribelli di Amur e Manciuria (AiNavy.position_fleets).
func test_la_flotta_giapponese_va_dove_ci_sono_bersagli(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(true)
	var s := GameSetup.new_game(d["campaign"], d["units"], d["buildings"], Rules.load_file(), 11, d["heroes"])
	s.form_alliance("FN_JAPANESE", "FN_CHINESE")
	var fleet: Army = null
	for a in s.armies:
		if a.faction == "FN_JAPANESE" and a.is_fleet:
			fleet = a
	t.assert_true(fleet != null and fleet.region == "ID_EAST_CHINA_SEA", "la flotta parte nel Mar Cinese Orientale")
	if fleet == null:
		return
	var ctx := AiContext.build(s, AiRules.load_file(AiRules.DEFAULT_PATH), "")
	var plan := AiPlan.create(ctx, "FN_JAPANESE", "ORTHODOX_EXPANSIONIST")
	AiNavy.position_fleets(plan, ctx.fleets_of("FN_JAPANESE"))
	t.assert_true(not fleet.path.is_empty() and fleet.path[fleet.path.size() - 1] == "ID_SEA_JAPAN", "verso il Mar del Giappone: %s" % str(fleet.path))
	t.assert_eq(ctx.rejected, 0, "nessun comando rifiutato: %s" % str(ctx.rejections))
	var again := AiPlan.create(AiContext.build(s, AiRules.load_file(AiRules.DEFAULT_PATH), ""), "FN_JAPANESE", "ORTHODOX_EXPANSIONIST")
	fleet.region = "ID_SEA_JAPAN"
	fleet.path = PackedStringArray()
	AiNavy.position_fleets(again, again.ctx.fleets_of("FN_JAPANESE"))
	t.assert_true(fleet.path.is_empty(), "gia' nella zona migliore: resta")
