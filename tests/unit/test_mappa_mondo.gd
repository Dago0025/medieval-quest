extends RefCounted
## Mappa del mondo (ADR-077) e isola di Atlantide in modalita' Auror (ADR-078): dati di data/mappa_mondo, startpos del mondo
## nelle due modalita', Danesi FN_DANES, confini precalcolati, salvataggi della mappa d'Europa. I test che leggono lo
## startpos reale si saltano senza installazione. Ogni test rimette la modalita' Auror (valore predefinito nei test).

const ISLAND := ["ID_ATLANTIS", "ID_GADEIRA", "ID_AMPHERIA", "ID_MNESEIA", "ID_DIAPREPIA"]


func _ready(t: TestContext) -> bool:
	if not WorldMap.available():
		t.skip("dati della mappa del mondo assenti")
		return false
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata")
		return false
	return true


func test_bitmap_a_16_bit_e_regionmap(t: TestContext) -> void:
	if not WorldMap.available():
		t.skip("dati della mappa del mondo assenti")
		return
	var wm := WorldMap.load_map(false)
	t.assert_true(wm.is_valid(), wm.error)
	t.assert_eq(Vector2i(wm.width, wm.height), Vector2i(12960, 5396))
	t.assert_eq(wm.sea_first, 1024)
	t.assert_false(wm.index_of.has("ID_ATLANTIS"), "senza modalita' Auror l'isola non c'e'")
	var img := wm.to_image()
	t.assert_eq(img.get_format(), Image.FORMAT_RG8)
	var rome: int = wm.index_of["ID_ROME"]
	t.assert_true(rome > 0 and rome < wm.sea_first, "Roma e' terra")
	t.assert_true(int(wm.index_of["ID_TYRRHENIAN_SEA"]) >= wm.sea_first, "il Tirreno e' mare")
	t.assert_eq(wm.index_at(-1, 0), -1)
	t.assert_true(wm.anchors.has("ID_N_PACIFIC"), "ancora delle zone di mare")
	var auror := WorldMap.load_map(true)
	t.assert_true(auror.index_of.has("ID_ATLANTIS"), "con la modalita' Auror l'isola c'e'")
	# il centro dell'isola: terra di Atlantide nella variante Auror, mare nella mappa normale
	var c: Vector2 = auror.anchors["ID_ATLANTIS"]
	t.assert_eq(auror.index_at(int(c.x), int(c.y)), int(auror.index_of["ID_ATLANTIS"]))
	t.assert_true(wm.index_at(int(c.x), int(c.y)) >= wm.sea_first, "senza isola li' c'e' l'Atlantico")


func test_startpos_del_mondo_scenario_storico(t: TestContext) -> void:
	if not _ready(t):
		return
	Scenario.set_auror(false)
	var d := Scenario.load_startpos()
	t.assert_eq(d.errors.size(), 0, str(d.errors.slice(0, 3)))
	t.assert_eq(d.land_regions().size(), 228, "107 europee + 121 nuove")
	t.assert_eq(d.sea_regions().size(), 73, "36 europei + 50 nuovi, meno 13 zone del Mediterraneo unite ad altre (16/11/2026)")
	t.assert_eq(d.asymmetric_neighbours().size(), 0, "confinanti simmetrici")
	t.assert_true(d.region("ID_ATLANTIS") == null, "l'isola solo in modalita' Auror")
	# tutti i confinanti dello startpos originale restano (le zone unite contano come quella che le assorbe)
	var original := StartposLoader.load_file(GameFiles.startpos())
	var missing := 0
	for r in original.regions:
		var here := d.region(WorldMap.merged_id(r.id))
		for n in r.neighbours:
			var other := WorldMap.merged_id(n)
			if other != here.id and not here.neighbours.has(other):
				missing += 1
	t.assert_eq(missing, 0, "confinanti dell'originale mancanti")
	t.assert_true(d.region("ID_ICELAND").neighbours.has("ID_GREENLAND_SEA"), "Islanda sul suo mare")
	t.assert_eq(d.region("ID_LIAO").owner, "FN_REBEL", "le terre nuove sono dei ribelli")
	t.assert_eq(d.region("ID_KAIFENG").owner, "FN_CHINESE", "tranne quelle delle fazioni nuove (ADR-079)")
	# ogni castello cade nella sua regione sulla bitmap
	var rm := RegionMap.new(WorldMap.load_map(false), d)
	t.assert_true(RegionMap.world, "RegionMap in modalita' mondo")
	t.assert_eq(RegionMap.group_for_index(1500), 1500, "gruppo = indice")
	var wrong := PackedStringArray()
	for r in d.land_regions():
		var p := RegionMap.startpos_to_pixel(r.castle_pos)
		var at := rm.region_at_pixel(p.x, p.y)
		if at == null or at.id != r.id:
			wrong.append(r.id)
	t.assert_eq(wrong.size(), 0, "castelli fuori dalla regione: %s" % ", ".join(wrong))
	Scenario.set_auror(true)


func test_atlantide_e_danesi_in_modalita_auror(t: TestContext) -> void:
	if not _ready(t):
		return
	Scenario.set_auror(true)
	var d := Scenario.load_startpos()
	t.assert_eq(d.errors.size(), 0, str(d.errors.slice(0, 3)))
	t.assert_eq(d.land_regions().size(), 233, "con i cinque territori dell'isola")
	for r in ISLAND:
		t.assert_eq(d.region(r).owner, "FN_DANISH", "%s agli Auror" % r)
	t.assert_eq(d.faction("FN_DANISH").leader_region, "ID_ATLANTIS", "Darkos parte da Atlantide")
	t.assert_eq(d.faction("FN_DANISH").treasury[0], 99999, "tesoro degli Auror")
	t.assert_true(d.faction("FN_DANES") != null and d.faction("FN_DANES").is_active(), "Danesi storici come FN_DANES")
	t.assert_eq(d.region("ID_DENMARK").owner, "FN_DANES")
	t.assert_eq(d.region("ID_SCANIA").owner, "FN_DANES")
	t.assert_eq(d.region("ID_NORWAY").owner, "FN_NORWEGIAN")
	t.assert_eq(d.region("ID_SWEDEN").owner, "FN_SWEDISH")
	t.assert_eq(d.faction("FN_DANES").leader_region, "ID_DENMARK")
	t.assert_true(d.region("ID_ATLANTIS").has_port, "Atlantide ha il porto del canale")
	var auror_units := 0
	for u in d.start_units:
		if ISLAND.has(u.region):
			auror_units += 1
	t.assert_true(auror_units > 20, "eserciti e flotte degli Auror sull'isola (%d)" % auror_units)
	t.assert_eq(FactionStyle.name_of("FN_DANES"), "Danesi")
	Scenario.set_auror(true)


func test_danesi_reclutano_come_nello_storico(t: TestContext) -> void:
	if not _ready(t):
		return
	Scenario.set_auror(false)
	var plain := Scenario.load_startpos()
	var hist := Scenario.load_units(GameFiles.prod_file(plain.unit_prod_file))
	Scenario.set_auror(true)
	var d := Scenario.load_startpos()
	var table := Scenario.load_units(GameFiles.prod_file(d.unit_prod_file))
	var danish_hist := 0
	var danes_now := 0
	for u in hist.units:
		if u.is_military() and u.recruitable_by("FN_DANISH"):
			danish_hist += 1
			var now := table.get_unit(u.id)
			if now != null and now.recruitable_by("FN_DANES"):
				danes_now += 1
	t.assert_true(danish_hist > 0)
	t.assert_eq(danes_now, danish_hist, "le unita' dei Danesi storici valgono per FN_DANES")
	var heroes := Scenario.load_heroes(GameFiles.heroes_file(d.name_data_basename() if d.name_data_basename() != "" else HeroesLoader.DEFAULT_FILE))
	t.assert_true(heroes.kings_of("FN_DANES").size() > 0, "re famosi dei Danesi")
	t.assert_true(heroes.forenames_of("FN_DANES").size() > 0, "nomi dei Danesi")


func test_confini_precalcolati(t: TestContext) -> void:
	if not WorldMap.available():
		t.skip("dati della mappa del mondo assenti")
		return
	for auror in [false, true]:
		var list := BorderExtractor.load_world(WorldMap.borders_path(auror))
		t.assert_true(list.size() > 5000, "polilinee: %d" % list.size())
		var kinds := {}
		for b in list:
			kinds[b.kind] = true
			if b.group_a >= b.group_b or b.points.size() < 2:
				t.assert_true(false, "polilinea non valida %d-%d" % [b.group_a, b.group_b])
				return
		t.assert_true(kinds.has(BorderExtractor.KIND_LAND_LAND) and kinds.has(BorderExtractor.KIND_COAST) and kinds.has(BorderExtractor.KIND_SEA_SEA))
	t.assert_true(BorderExtractor.load_world("res://non_esiste.bin").is_empty())


## Bitmap «da vedere» (23/11/2026): stesse dimensioni, pochi pixel cambiati e mai tra terra e mare (coste intatte).
func test_bitmap_da_vedere_levigata(t: TestContext) -> void:
	if not WorldMap.available():
		t.skip("dati della mappa del mondo assenti")
		return
	for auror in [false, true]:
		var m := WorldMap.load_map(auror)
		t.assert_true(FileAccess.file_exists(WorldMap.view_index_path(auror)), "manca %s" % WorldMap.view_index_path(auror))
		var logic := m.to_image()
		var view := m.view_image()
		t.assert_true(view != null and view.get_format() == Image.FORMAT_RG8, "formato RG8")
		t.assert_eq(view.get_size(), logic.get_size(), "stesse dimensioni")
		var a := logic.get_data()
		var b := view.get_data()
		var checked := 0
		var changed := 0
		var crossed := 0
		var i := 0
		while i < a.size():
			var la := a[i] | (a[i + 1] << 8)
			var lb := b[i] | (b[i + 1] << 8)
			checked += 1
			if la != lb:
				changed += 1
				if (la >= m.sea_first) != (lb >= m.sea_first) or la == 0 or lb == 0:
					crossed += 1
			i += 2 * 101
		t.assert_true(changed > 0, "qualche pixel riassegnato")
		t.assert_true(changed * 100 < checked, "meno dell'1%% dei pixel: %d su %d" % [changed, checked])
		t.assert_eq(crossed, 0, "nessun pixel tra terra e mare")


func test_startpos_text_sostituisce_le_posizioni(t: TestContext) -> void:
	if not WorldMap.available():
		t.skip("dati della mappa del mondo assenti")
		return
	var text := "SetCastle:: ID_X 1 2\nSetNeighbours:: ID_X ID_Y\nSetBorderInfo:: ID_X ID_Y 1 2\nSetTreasury:: FN_A 5"
	var out := WorldMap.startpos_text(text, false, "// coda")
	t.assert_false(out.contains("SetCastle:: ID_X 1 2"), "castelli dell'originale tolti")
	t.assert_false(out.contains("SetNeighbours:: ID_X"), "confinanti dell'originale tolti")
	t.assert_false(out.contains("SetBorderInfo:: ID_X"), "punti di confine tolti")
	t.assert_true(out.contains("SetTreasury:: FN_A 5"), "il resto resta")
	t.assert_true(out.contains("DeclareLandRegion::\t\"ID_KAIFENG\""), "regioni nuove aggiunte")
	t.assert_false(out.contains("ID_ATLANTIS"), "isola solo con auror")
	t.assert_true(WorldMap.startpos_text(text, true).contains("\"ID_ATLANTIS\""))
	t.assert_true(out.ends_with("// coda"), "righe extra in fondo")


func test_auror_spostati_sull_isola(t: TestContext) -> void:
	var inst := "SetRegionOwner:: ID_DENMARK\tFN_DANISH\nPlaceLeader:: ID_DENMARK\tFN_DANISH\n" + \
		"MakeBuilding:: ID_SCANIA\tCastle6\nMakeUnit::\tID_NORWAY\tLancers\t40\t//FN_DANISH\n" + \
		"SetTreasury:: FN_DANISH\t99999\nSetTreasury:: FN_FRENCH\t10000\nMakeUnit:: ID_FRANCE\tPeasants\t100\n" + \
		"//SetStartLeader:: FN_NORWEGIAN 0 1 1"
	var out := AtlantisScenario.auror_lines(inst)
	t.assert_true(out.contains("SetRegionOwner::\tID_GADEIRA\tFN_DANISH"), "Danimarca -> Gadira")
	t.assert_true(out.contains("PlaceLeader::\tID_GADEIRA\tFN_DANISH"), "vecchia capitale portata sull'isola")
	t.assert_true(out.contains("MakeBuilding:: ID_AMPHERIA\tCastle6"), "Scania -> Amferia")
	t.assert_true(out.contains("MakeBuilding:: ID_DIAPREPIA\tCastle6"), "Diaprepia con gli edifici della Scania")
	t.assert_true(out.contains("ID_ATLANTIS\tLancers"), "Norvegia -> Atlantide")
	t.assert_true(out.contains("SetTreasury:: FN_DANISH\t99999"), "righe di fazione degli Auror")
	t.assert_false(out.contains("FN_FRENCH") or out.contains("ID_FRANCE"), "le altre fazioni no")
	t.assert_eq(AtlantisScenario.rename_faction("SetTreasury:: FN_DANISH 1", "FN_DANISH", "FN_DANES"), "SetTreasury:: FN_DANES 1")
	t.assert_eq(AtlantisScenario.rename_faction("FN_DANISHX", "FN_DANISH", "FN_DANES"), "FN_DANISHX", "solo parole intere")


func test_salvataggi_della_mappa_d_europa_rifiutati(t: TestContext) -> void:
	if not WorldMap.available():
		t.skip("dati della mappa del mondo assenti")
		return
	t.assert_eq(WorldMap.map_id(), "mondo")
	var campaign := StartposLoader.load_file("res://tests/fixtures/sim_startpos.txt")
	var units := UnitProdLoader.load_file("res://tests/fixtures/sim_unit_prod.txt")
	var buildings := BuildingProdLoader.load_file("res://tests/fixtures/sim_build_prod.txt")
	var rules := Rules.load_file()
	var s := GameSetup.new_game(campaign, units, buildings, rules, 7)
	var d := SaveGame.to_dict(s)
	t.assert_eq(str(d.get("mappa", "")), "mondo", "i salvataggi ricordano la mappa")
	var back := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)), campaign, units, buildings, rules)
	t.assert_true(bool(back["ok"]), str(back.get("errore", "")))
	d.erase("mappa")
	var old := SaveGame.from_dict(JSON.parse_string(JSON.stringify(d)), campaign, units, buildings, rules)
	t.assert_false(bool(old["ok"]), "salvataggio della mappa d'Europa rifiutato")
	t.assert_true(str(old.get("errore", "")) != "")


## Richiesta di Federico del 16/11/2026: sulla mappa del mondo gli agenti senza navi attraversano i mari ma non gli oceani
## (`[flotte] oceani` di scontri.cfg). Ogni oceano e' una zona di mare della mappa; nessuna rotta di soli mari collega
## l'Europa alle Americhe o Atlantide al resto del mondo.
func test_oceani_della_mappa_del_mondo(t: TestContext) -> void:
	if not _ready(t):
		return
	Scenario.set_auror(true)
	var d := Scenario.load_startpos()
	var oceans := CombatRules.load_file().oceans
	t.assert_true(oceans.size() >= 10, "oceani dichiarati (%d)" % oceans.size())
	for id in oceans:
		var z := d.region(str(id))
		t.assert_true(z != null and z.is_sea, "%s e' una zona di mare della mappa" % id)
	for r in ISLAND:
		for n in d.region(r).neighbours:
			var z := d.region(n)
			if z.is_sea:
				t.assert_true(oceans.has(z.id), "%s, confinante di %s, e' oceano" % [z.id, r])
	var europe := _sea_basin(d, "ID_NORTH_SEA", oceans)
	t.assert_true(europe.has("ID_BLACK_SEA") and europe.has("ID_GULF_GUINEA"), "Europa, Mediterraneo e coste d'Africa uniti")
	for z in ["ID_CARIBBEAN_SEA", "ID_W_ATLANTIC", "ID_GULF_MEXICO", "ID_SW_ATLANTIC", "ID_E_PACIFIC"]:
		t.assert_false(europe.has(z), "%s non si raggiunge dall'Europa senza navi" % z)
	t.assert_true(_sea_basin(d, "ID_W_ATLANTIC", oceans).has("ID_CARIBBEAN_SEA"), "le coste delle Americhe restano navigabili")


## Zone di mare raggiungibili da `start` senza passare per gli oceani.
func _sea_basin(d: CampaignData, start: String, oceans: Dictionary) -> Dictionary:
	var seen := {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var z := d.region(queue.pop_back())
		for n in z.neighbours:
			var other := d.region(n)
			if other != null and other.is_sea and not oceans.has(other.id) and not seen.has(other.id):
				seen[other.id] = true
				queue.append(other.id)
	return seen


## Segnalazione di Federico del 16/11/2026: gli agenti degli Auror arrivavano negli altri continenti anche senza navi di
## collegamento (le fregate di partenza nell'Atlantico centrale facevano da ponte da sole). Ora una rotta che attraversa un
## oceano vuole una flotta propria in ogni zona; senza il ponte fino alla costa gli agenti restano sull'isola.
func test_gli_agenti_auror_lasciano_atlantide_solo_con_il_ponte_di_navi(t: TestContext) -> void:
	if not _ready(t):
		return
	Scenario.set_auror(true)
	var c := Scenario.load_startpos()
	var rules := Rules.load_file()
	Scenario.apply_rules(rules)
	var s := GameSetup.new_game(c, Scenario.load_units(GameFiles.prod_file(c.unit_prod_file)),
			Scenario.load_buildings(GameFiles.prod_file(c.building_prod_file)), rules, 11,
			Scenario.load_heroes(GameFiles.heroes_file(c.name_data_basename())))
	var mid := 0
	for a in s.armies:
		if a.faction == "FN_DANISH" and a.is_fleet and a.region == "ID_MID_ATLANTIC":
			mid += 1
	t.assert_true(mid > 0, "fregate degli Auror nell'Atlantico centrale")
	for r in GameCommands.sea_destinations_from(s, "FN_DANISH", "ID_ATLANTIS", false):
		t.assert_true(ISLAND.has(r), "%s raggiunta senza il ponte di navi fino alla costa" % r)
	var bridge := s.create_army("FN_DANISH", "ID_ATLANTIC_OCEAN", true)
	bridge.stacks.append(UnitStack.new("AurorDragonFrigate", 1, 0))
	var dest := GameCommands.sea_destinations_from(s, "FN_DANISH", "ID_ATLANTIS", false)
	t.assert_true(dest.has("ID_IRELAND"), "con le fregate anche nell'Atlantico orientale si arriva in Irlanda")
	t.assert_false(dest.has("ID_APPALACHIA"), "ma non nelle Americhe")


## Richiesta di Federico del 16/11/2026: «il Mediterraneo e' fin troppo frammentato, riduci i segmenti di mare». Le zone di
## data/mappa_mondo/mari_uniti.cfg spariscono dalla bitmap e dallo startpos del mondo e lasciano il posto a quelle che le
## assorbono (da 22 zone a 10).
func test_mediterraneo_meno_frammentato(t: TestContext) -> void:
	var aliases := WorldMap.merged_seas()
	t.assert_eq(aliases.size(), 13, "zone tolte")
	t.assert_eq(WorldMap.merged_id("ID_NILE_COAST"), "ID_EASTERN_MED")
	t.assert_eq(WorldMap.merged_id("ID_BLACK_SEA"), "ID_BLACK_SEA", "le altre restano")
	var text := WorldMap.startpos_text("DeclareSeaRegion::\t\"ID_NILE_COAST\"\nDeclareSeaRegion::\t\"ID_EASTERN_MED\"\nMakeUnit::\tID_NILE_COAST\tGalley", false)
	t.assert_false(text.contains("\"ID_NILE_COAST\""), "la zona tolta non si dichiara")
	t.assert_true(text.contains("MakeUnit::\tID_EASTERN_MED\tGalley"), "le righe dell'installazione passano alla zona che la assorbe")
	if not _ready(t):
		return
	Scenario.set_auror(false)
	var d := Scenario.load_startpos()
	Scenario.set_auror(true)
	t.assert_eq(d.errors.size(), 0, str(d.errors.slice(0, 3)))
	for id in aliases:
		t.assert_true(d.region(str(id)) == null, "%s unita a %s" % [id, aliases[id]])
	t.assert_true(d.region("ID_AEGEAN_SEA").neighbours.has("ID_BLACK_SEA"), "l'Egeo arriva al Bosforo (era il Mar di Marmara)")
	t.assert_true(d.region("ID_EASTERN_MED").neighbours.has("ID_EGYPT"), "il Mediterraneo orientale bagna l'Egitto (era la Costa del Nilo)")
	t.assert_true(d.region("ID_STRAITS_SICILY").neighbours.has("ID_MALTA"))
	var wm := WorldMap.load_map(false)
	for id in aliases:
		t.assert_false(wm.index_of.has(str(id)), "%s non e' piu' nella bitmap" % id)


## Salvataggi del mondo di prima: flotte e agenti nelle zone unite passano in quelle che le assorbono; le rotte che le toccano
## si annullano. Le zone che la mappa della partita ha ancora (mappa d'Europa) restano come sono.
func test_salvataggi_con_le_zone_unite(t: TestContext) -> void:
	const AW := preload("res://tests/unit/agent_world.gd")
	var s := AW.world()
	var fleet := AW.fleet(s, AW.A, AW.NORD)
	fleet.region = "ID_NILE_COAST"
	fleet.path = PackedStringArray(["ID_SEA_CRETE"])
	var other := AW.fleet(s, AW.A, AW.SUD)
	SaveGame._remap_merged_seas(s)
	t.assert_eq(fleet.region, "ID_EASTERN_MED")
	t.assert_true(fleet.path.is_empty(), "rotta annullata")
	t.assert_eq(other.region, AW.SUD, "le zone che ci sono restano")
