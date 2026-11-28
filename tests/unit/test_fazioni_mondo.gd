extends RefCounted
## Fazioni nuove della mappa del mondo e nomi propri (ADR-079), sui file reali dell'installazione: Giapponesi, Cinesi,
## Aztechi, Inca, Kanem e Cahokia (e, ADR-088, Coreani, Mongoli, Chola e Khmer) nelle loro regioni in tutte e due le modalita', con agenti ed edifici della
## fazione modello (truppe proprie, ADR-116) e nomi da data/nomi_personaggi.cfg; gli Auror con i loro nomi (non piu' quelli dei Danesi) solo in
## modalita' Auror. Senza installazione o senza mappa del mondo i test si saltano. Ogni test rimette la modalita' Auror.

const NEW := {"FN_JAPANESE": "ID_KINAI", "FN_CHINESE": "ID_KAIFENG", "FN_AZTECS": "ID_TOLLAN", "FN_INCA": "ID_CUZCO",
	"FN_KANEM": "ID_KANEM", "FN_MISSISSIPPIANS": "ID_MISSISSIPPI", "FN_KOREANS": "ID_KOREA", "FN_MONGOLS": "ID_MONGOLIA",
	"FN_CHOLA": "ID_CHOLA", "FN_KHMER": "ID_KHMER", "FN_MAYA": "ID_MAYA", "FN_KARAKHANIDS": "ID_SEMIRECHYE", "FN_PUEBLO": "ID_CHACO",
	"FN_GHANA": "ID_GHANA", "FN_ZIMBABWE": "ID_ZIMBABWE"}


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
	t.assert_eq(c2.faction("FN_JAPANESE").religion, Dharma.TOKEN, "ADR-118: i giapponesi seguono il Dharma")
	for r in ["ID_KYUSHU", "ID_TOHOKU"]:
		t.assert_eq(c2.region(r).owner, "FN_JAPANESE", r)
	t.assert_eq(c2.region("ID_LINGNAN").owner, "FN_CHINESE")
	t.assert_eq(c2.region("ID_LIAO").owner, "FN_REBEL", "Liao resta ai ribelli")
	t.assert_eq(c2.region("ID_EAST_MONGOLIA").owner, "FN_MONGOLS")
	for r in ["ID_DECCAN", "ID_CEYLON"]:
		t.assert_eq(c2.region(r).owner, "FN_CHOLA", r)
	# 27/11/2026: Maya nello Yucatan e in America centrale (gli Aztechi restano a Tollan), Karakhanidi musulmani in Asia centrale
	t.assert_eq(c2.region("ID_CENTRAL_AMERICA").owner, "FN_MAYA")
	t.assert_eq(c2.region("ID_TOLLAN").owner, "FN_AZTECS")
	for r in ["ID_KASHGAR", "ID_TRANSOXIANA"]:
		t.assert_eq(c2.region(r).owner, "FN_KARAKHANIDS", r)
	t.assert_eq(c2.faction("FN_KARAKHANIDS").religion, "REL_ISLAMIC")
	t.assert_eq(c2.region("ID_KHWAREZM").owner, "FN_REBEL", "Khwarezm resta ai ribelli")


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
		# ADR-116: truppe proprie; dal modello solo gli agenti (ADR-118: tranne quelli che il Dharma sostituisce)
		var dharma := Dharma.factions().has(fid)
		for u in units.agents():
			if dharma and Dharma.removed_agents().has(u.id):
				t.assert_false(u.factions.has(fid), "%s non recluta %s (Dharma)" % [fid, u.id])
				continue
			if not u.all_factions and u.factions.has(model):
				t.assert_true(u.factions.has(fid), "%s recluta %s come %s" % [fid, u.id, model])
	var kanem := {}
	for u in units.land_for("FN_KANEM"):
		kanem[u.id] = true
	t.assert_true(kanem.has("KanLancieri") and kanem.has("KanLifidi") and not kanem.has("NegroSpearmen"), "il Kanem arruola le sue unita'")
	t.assert_true(units.get_unit("Mullah").allows_faction("FN_KANEM"), "e i mullah come gli Almohadi")
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
	t.assert_true(bool(GameCommands.can_queue_unit(s, "FN_JAPANESE", "ID_KINAI", "JapKobaya")["ok"]), "Kinai arma le kobaya")
	t.assert_false(bool(GameCommands.can_queue_unit(s, "FN_JAPANESE", "ID_KINAI", "Dhow")["ok"]), "e non piu' i dhow (ADR-116)")


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
	# dal 28/11/2026 (regioni nuove) i bersagli sono sia sul Mar del Giappone (Corea, Ezo) sia sul Pacifico (Ezo, Kanto)
	var goal := fleet.path[fleet.path.size() - 1] if not fleet.path.is_empty() else ""
	t.assert_true(goal in ["ID_SEA_JAPAN", "ID_NW_PACIFIC"], "verso un mare con bersagli: %s" % str(fleet.path))
	t.assert_eq(ctx.rejected, 0, "nessun comando rifiutato: %s" % str(ctx.rejections))
	var again := AiPlan.create(AiContext.build(s, AiRules.load_file(AiRules.DEFAULT_PATH), ""), "FN_JAPANESE", "ORTHODOX_EXPANSIONIST")
	fleet.region = goal
	fleet.path = PackedStringArray()
	AiNavy.position_fleets(again, again.ctx.fleets_of("FN_JAPANESE"))
	t.assert_true(fleet.path.is_empty(), "gia' nella zona migliore: resta")


## Richiesta di Federico del 27/11/2026: le due civilta' nuove usano gli asset esistenti. I Maya hanno le carte, le schede,
## i ritratti, le pedine e i castelli degli Aztechi; i Karakhanidi le carte delle truppe turche e musulmane della XL.
func test_maya_e_karakhanidi_con_gli_asset_esistenti(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(false)
	var units: UnitProdLoader.UnitTable = d["units"]
	var maya := {}
	for u in units.land_for("FN_MAYA"):
		maya[u.id] = true
	t.assert_true(maya.has("MayLancieri") and maya.has("MayBalam") and not maya.has("AztTepoztopilli"), "i Maya arruolano le loro unita'")
	t.assert_false(units.get_unit("MayGuardia") == null, "guardia dei Maya")
	var krk := {}
	for u in units.land_for("FN_KARAKHANIDS"):
		krk[u.id] = true
	t.assert_true(krk.has("KrkArcieriCavallo") and krk.has("KrkGhulam") and not krk.has("GhulamCavalry"), "i Karakhanidi arruolano le loro unita'")
	t.assert_true(units.get_unit("Mullah").allows_faction("FN_KARAKHANIDS"), "e i mullah come i Turchi")
	t.assert_eq(CultureUnits.card_model("MayBalam"), "AztOcelomeh", "carta azteca")
	t.assert_eq(CultureUnits.card_model("KrkGhulam"), "GhulamCavalry", "carta della XL")
	t.assert_eq(PortraitArt.culture_of("FN_MAYA"), "aztec")
	t.assert_eq(PieceArt.own_culture("FN_MAYA"), "Aztec")
	t.assert_true(units.get_unit("MayBalam") != null and not units.get_unit("MayBalam").factions.has("FN_AZTECS"))
	if AssetLibrary.is_available():
		t.assert_eq(AssetLibrary.unit_card_path("MayBalam"), AssetLibrary.unit_card_path("AztOcelomeh"), "stessa carta degli Aztechi")
		t.assert_true(AssetLibrary.unit_card_path("KrkGhulam") != "", "carta della cavalleria ghulam")
		t.assert_true(AssetLibrary.unit_picture("MayCanoa") != null, "scheda della canoa (dalla canoa azteca o dal suo modello)")
	t.assert_true(FileAccess.file_exists("res://assets/stemmi/fn_maya.png") and FileAccess.file_exists("res://assets/stemmi/fn_karakhanids.png"), "stemmi")
	t.assert_eq(SimUtil.faction_label("FN_KARAKHANIDS"), "Karakhanidi")
	var heroes: HeroesData = d["heroes"]
	t.assert_eq(heroes.forenames_of("FN_MAYA")[0], "K'ak'upakal")
	t.assert_eq(heroes.forenames_of("FN_KARAKHANIDS")[0], "Bughra")


## Richiesta di Federico del 27/11/2026: i Cahokia prendevano in breve tutto il Nord America senza rivali. I Pueblo tengono
## Chaco, California e Grandi Pianure (confinanti con i Cahokia) con unita', ritratti, pedine e castelli dei Cahokia.
func test_pueblo_rivali_dei_cahokia(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(false)
	var c: CampaignData = d["campaign"]
	for r in ["ID_CHACO", "ID_CALIFORNIA", "ID_PLAINS"]:
		t.assert_eq(c.region(r).owner, "FN_PUEBLO", r)
	t.assert_true(c.region("ID_PLAINS").neighbours.has("ID_MISSISSIPPI"), "confinano con i Cahokia")
	var units: UnitProdLoader.UnitTable = d["units"]
	var mine := {}
	for u in units.land_for("FN_PUEBLO"):
		mine[u.id] = true
	t.assert_true(mine.has("PueLancieri") and mine.has("PueSocietaArco") and not mine.has("CahLancieri"), "unita' proprie")
	t.assert_eq(CultureUnits.card_model("PueSocietaArco"), "CahFalco", "carta dei Cahokia")
	t.assert_eq(PortraitArt.culture_of("FN_PUEBLO"), "mississippian")
	t.assert_eq(PieceArt.own_culture("FN_PUEBLO"), "Mississippian")
	t.assert_true(Rules.load_file().history.horseless_factions.has("FN_PUEBLO"), "senza cavalli fino agli stranieri")
	t.assert_true(FileAccess.file_exists("res://assets/stemmi/fn_pueblo.png"))
	t.assert_eq((d["heroes"] as HeroesData).forenames_of("FN_PUEBLO")[0], "Tawakwaptiwa")


## Richiesta di Federico del 28/11/2026: una fazione subsahariana che contenda l'Africa al Kanem e una dell'Africa
## australe, con gli asset grafici del Kanem e uno stemma proprio. Il Ghana tiene Ghana e Mali (confinanti con Gao, come il
## Kanem con Hausa); lo Zimbabwe l'altopiano e il Sudafrica. Le guarnigioni ribelli di partenza diventano le loro unita'.
func test_ghana_e_zimbabwe_rivali_del_kanem(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(false)
	var c: CampaignData = d["campaign"]
	var regions := {"FN_GHANA": ["ID_GHANA", "ID_MALI", "ID_BAMBUK"], "FN_ZIMBABWE": ["ID_ZIMBABWE", "ID_SOUTHERN_AFRICA", "ID_MAPUNGUBWE"]}
	for f in regions:
		for r in regions[f]:
			t.assert_eq(c.region(r).owner, f, r)
		t.assert_eq(c.faction(f).religion, "REL_PAGAN", f)
		t.assert_eq(PortraitArt.culture_of(f), "kanem", "ritratti del Kanem")
		t.assert_eq(PieceArt.own_culture(f), "African", "pedine del Kanem")
		t.assert_true(FileAccess.file_exists("res://assets/stemmi/%s.png" % f.to_lower()), "stemma proprio")
	t.assert_true(c.region("ID_GAO").neighbours.has("ID_GHANA") and c.region("ID_GAO").neighbours.has("ID_HAUSA"), "Gao conteso col Kanem")
	var units: UnitProdLoader.UnitTable = d["units"]
	var ghana := {}
	for u in units.land_for("FN_GHANA"):
		ghana[u.id] = true
	t.assert_true(ghana.has("GhaLancieri") and ghana.has("GhaCavLeggera") and not ghana.has("KanLancieri"), "unita' proprie del Ghana")
	var zim := {}
	for u in units.land_for("FN_ZIMBABWE"):
		zim[u.id] = true
		if u.id.begins_with("Zim"):
			t.assert_false(u.is_cavalry(), "niente cavalli sull'altopiano: " + u.id)
	t.assert_true(zim.has("ZimLancieri") and zim.has("ZimGuardia"), "unita' proprie dello Zimbabwe")
	t.assert_eq(CultureUnits.card_model("GhaLancieri"), "KanLancieri", "carta del Kanem")
	t.assert_eq(CultureUnits.card_model("ZimAsce"), "KanSao", "carta del Kanem")
	for su in c.start_units:
		if su.region == "ID_GHANA" or su.region == "ID_ZIMBABWE":
			t.assert_true(su.unit_type.begins_with("Gha") or su.unit_type.begins_with("Zim"), "guarnigione convertita: " + su.unit_type)
	var heroes: HeroesData = d["heroes"]
	t.assert_eq(heroes.forenames_of("FN_GHANA")[0], "Tunka Manin")
	t.assert_eq(heroes.forenames_of("FN_ZIMBABWE")[0], "Nyatsimba")
	t.assert_eq(SimUtil.faction_label("FN_ZIMBABWE"), "Zimbabwe")


## Richiesta di Federico del 28/11/2026: gli altri continenti piu' frammentati (221 regioni fuori Europa) e le regioni
## nuove assegnate alle fazioni che le tenevano nel 1000 (i Song, Heian, Goryeo, Chola, Khmer, Karakhanidi...).
func test_regioni_nuove_alle_fazioni_storiche(t: TestContext) -> void:
	if not _ready(t):
		return
	var d := _load(false)
	var c: CampaignData = d["campaign"]
	var owners := {"ID_HEBEI": "FN_CHINESE", "ID_SHANDONG": "FN_CHINESE", "ID_HUNAN": "FN_CHINESE", "ID_KANTO": "FN_JAPANESE",
		"ID_GYEONGSANG": "FN_KOREANS", "ID_KERALA": "FN_CHOLA", "ID_GANGAVADI": "FN_CHOLA", "ID_LAVO": "FN_KHMER",
		"ID_FERGHANA": "FN_KARAKHANIDS", "ID_YANYUN": "FN_REBEL", "ID_EZO": "FN_REBEL", "ID_CHARCAS": "FN_REBEL"}
	for r in owners:
		t.assert_true(c.region(r) != null, "esiste " + r)
		if c.region(r) != null:
			var own := c.region(r).owner
			t.assert_true(own == owners[r] or (owners[r] == "FN_REBEL" and own in ["", "FN_REBEL"]), "%s di %s" % [r, own])
	t.assert_true(c.region("ID_YANYUN").neighbours.has("ID_HEBEI"), "Sedici Prefetture contese tra Liao e Song")
	var names := ConfigFile.new()
	names.load("res://data/province.cfg")
	t.assert_eq(str(names.get_value("terra", "ID_YANYUN", "")), "Sedici Prefetture")
