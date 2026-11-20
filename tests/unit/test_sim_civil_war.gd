extends RefCounted
## Test della guerra civile e della lealta' dei generali (fase 4b, `ProvinceProcessor`) sul mondo di prova
## tests/fixtures/dynasty_*.txt (vedi test_sim_loyalty.gd). ALPHA ha il capo in ALTA, l'erede maggiorenne (ruolo
## erede: non conta come generale), il generale G che governa BASSA con il suo esercito e il comandante F della flotta.
## Altri generali si aggiungono a mano. Il sorteggio della guerra civile si rende certo con `civil_chance` 1.

const STARTPOS := "res://tests/fixtures/dynasty_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const HEROES := "res://tests/fixtures/dynasty_heroes.txt"


## Mondo senza sorteggi della fase 4b e senza morti per vecchiaia; G e F con lealta' 8 e comando 1.
func _world(seed_value: int = 7) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var rules := Rules.new()
	rules.province.calm()
	var s := GameSetup.new_game(campaign, units, buildings, rules, seed_value, HeroesLoader.load_file(HEROES))
	rules.dynasty.birth_chance = 0.0
	for c in s.characters:
		c.old_age = 500
	for c in [_governor(s), _fleet_commander(s)]:
		c.loyalty = 8
		c.command = 1
	var governor := _governor(s)
	governor.dread = 3
	governor.vnv = {}
	ProvinceProcessor.init_loyalty(s)
	return s


func _bassa_army(s: GameState) -> Army:
	for a in s.armies_of("FN_ALPHA"):
		if a.region == "ID_BASSA" and not a.is_fleet:
			return a
	return null


func _fleet(s: GameState) -> Army:
	for a in s.armies_of("FN_ALPHA"):
		if a.is_fleet:
			return a
	return null


func _governor(s: GameState) -> Character:
	return s.governor_of("ID_BASSA")


func _fleet_commander(s: GameState) -> Character:
	return s.commander_of(_fleet(s).id)


## Un generale adulto di ALPHA, con un esercito di 100 lancieri nella regione (o senza).
func _add_general(s: GameState, region_id: String, loyalty: int, command: int, with_army: bool = true) -> Character:
	var c := s.create_character("FN_ALPHA")
	c.role = Character.ROLE_GENERAL
	c.forename = "Generale"
	c.birth_year = s.year - 30
	c.command = command
	c.loyalty = loyalty
	c.old_age = 500
	c.region = region_id
	if with_army:
		var a := s.create_army("FN_ALPHA", region_id, false)
		a.stacks.append(UnitStack.new(s.units.get_unit("Spearmen").id, 100, 0))
		c.army = a.id
	return c


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _men_total(s: GameState) -> int:
	var total := 0
	for a in s.armies:
		total += a.men_total()
	return total


# --- l'innesco -------------------------------------------------------------------------------------------


func test_nessun_innesco_con_generali_leali(t: TestContext) -> void:
	var s := _world()
	var info := ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)
	t.assert_eq(info["motivo"], "")
	t.assert_eq((info["sleali"] as Array).size(), 0)
	t.assert_true(info["promotore"] == null)
	# senza capo nessun innesco
	var s2 := _world()
	DynastyProcessor.kill(s2, s2.leader_of("FN_ALPHA"), 1001, "vecchiaia", false)
	_governor(s2).loyalty = 0
	_fleet_commander(s2).loyalty = 0
	t.assert_eq(ProvinceProcessor.civil_war_trigger(s2, "FN_ALPHA", 1001)["motivo"], "")


func test_innesco_per_quota_di_generali_sleali(t: TestContext) -> void:
	var s := _world()
	s.rules.province.civil_min = 1
	var g := _governor(s)
	var f := _fleet_commander(s)
	var x := _add_general(s, "ID_ALTA", 8, 1)
	var y := _add_general(s, "ID_ALTA", 8, 1)
	g.loyalty = 0      # lealta' efficace 1 (il titolo vale +1): sleale
	var info := ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)
	t.assert_eq(info["motivo"], "", "1 sleale su 4: sotto la quota del 50%")
	t.assert_eq((info["sleali"] as Array).size(), 1)
	f.loyalty = 3      # il limite e' compreso: lealta' <= 3
	info = ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)
	t.assert_eq(info["motivo"], "quota_sleali", "2 su 4: la meta'")
	t.assert_eq((info["sleali"] as Array).size(), 2)
	f.loyalty = 4
	info = ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)
	t.assert_eq(info["motivo"], "", "lealta' 4: non sleale")
	# il minimo di sleali: un solo sleale su due non basta con sleali_min 2
	s.rules.province.civil_min = 2
	x.loyalty = 0
	y.loyalty = 0
	g.loyalty = 8
	t.assert_eq(ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)["motivo"], "quota_sleali", "x e y: 2 su 4")
	y.loyalty = 8
	t.assert_eq(ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)["motivo"], "", "1 su 4")
	# gli sleali sono in ordine di id; chi e' morto o minorenne non conta
	x.loyalty = 0
	y.loyalty = 0
	var minor := _add_general(s, "ID_ALTA", 0, 1, false)
	minor.birth_year = s.year - 5
	var dead := _add_general(s, "ID_ALTA", 0, 1, false)
	dead.alive = false
	var info2 := ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)
	var ids: Array = []
	for item in (info2["sleali"] as Array):
		var c: Character = item
		ids.append(c.id)
	t.assert_eq(ids, [x.id, y.id])


func test_innesco_per_promotore_forte_e_sleale(t: TestContext) -> void:
	var s := _world()
	var g := _governor(s)
	g.loyalty = 0
	g.command = 7
	var info := ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)
	t.assert_eq(info["motivo"], "promotore", "sleale, comando 8 con il titolo, in BASSA e non dove sta il capo")
	t.assert_true(info["promotore"] == g)
	t.assert_eq((info["sleali"] as Array).size(), 1)
	# comando troppo basso: stelle efficaci 4 (3 + 1 del titolo) sotto il minimo di 5
	g.command = 3
	t.assert_eq(ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)["motivo"], "")
	g.command = 4
	t.assert_eq(ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)["motivo"], "promotore", "5 stelle: il minimo")
	# nella stessa regione del capo non e' un promotore
	var s2 := _world()
	var near := _add_general(s2, "ID_ALTA", 0, 9)
	var info2 := ProvinceProcessor.civil_war_trigger(s2, "FN_ALPHA", s2.year + 1)
	t.assert_eq(s2.character_region(near), s2.character_region(s2.leader_of("FN_ALPHA")))
	t.assert_eq(info2["motivo"], "", "stessa regione del capo, uno solo sleale")
	# i principi maggiorenni contano come generali, gli eredi no
	var prince := s2.create_character("FN_ALPHA")
	prince.role = Character.ROLE_PRINCE
	prince.royal_blood = true
	prince.birth_year = s2.year - 20
	prince.loyalty = 0
	prince.old_age = 500
	prince.region = "ID_ALTA"
	s2.heir_of("FN_ALPHA").loyalty = 0
	var info3 := ProvinceProcessor.civil_war_trigger(s2, "FN_ALPHA", s2.year + 1)
	t.assert_eq((info3["sleali"] as Array).size(), 2, "il generale vicino e il principe; l'erede non conta")
	t.assert_eq(info3["motivo"], "quota_sleali", "2 su 4 (G, F, il generale vicino, il principe)")


func test_il_valore_fisso_della_fedelta_impedisce_la_guerra_civile(t: TestContext) -> void:
	var s := _world()
	_governor(s).loyalty = 0
	_governor(s).command = 9
	_fleet_commander(s).loyalty = 0
	t.assert_eq(ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)["motivo"], "promotore")
	s.rules.dynasty.fixed["FN_ALPHA"] = {"loyalty": 9}
	t.assert_eq(ProvinceProcessor.civil_war_trigger(s, "FN_ALPHA", s.year + 1)["motivo"], "", "fedelta' fissa a 9 come gli Auror")
	# le regole reali degli Auror
	var rules := Rules.load_file()
	t.assert_eq(rules.dynasty.fixed_value("FN_DANISH", Character.ATTR_LOYALTY), 9)


# --- la guerra civile ---------------------------------------------------------------------------------------------


func test_la_guerra_civile_passa_eserciti_e_province_ai_ribelli(t: TestContext) -> void:
	var s := _world()
	s.rules.province.civil_chance = 1.0
	var loyal := _add_general(s, "ID_ALTA", 8, 1)
	var g := _governor(s)
	var f := _fleet_commander(s)
	g.loyalty = 0
	f.loyalty = 0
	var bassa_army := _bassa_army(s)
	var fleet := _fleet(s)
	bassa_army.in_castle = true       # il castello di BASSA e' dei ribelli quando la provincia passa
	var men_expected := bassa_army.men_total() + fleet.men_total()
	var men_before := _men_total(s)
	var armies_before := s.armies.size()
	var rng_before := s.rng.state
	s.events.clear()
	ProvinceProcessor.process_year(s)
	t.assert_true(s.rng.state != rng_before, "un sorteggio per la guerra civile")
	var wars := _events_of(s, GameState.EV_CIVIL_WAR)
	t.assert_eq(wars.size(), 1)
	if wars.size() != 1:
		return
	var e := wars[0]
	t.assert_eq(e["fazione"], "FN_ALPHA")
	t.assert_eq(e["motivo"], "quota_sleali")
	t.assert_eq(e["promotore"], 0)
	t.assert_eq(e["tipo_ribelli"], ProvinceProcessor.REBEL_LOYALISTS)
	var generals: Array = e["generali"]
	t.assert_eq(generals.size(), 2)
	t.assert_true(generals.has(g.id) and generals.has(f.id))
	var armies: Array = e["eserciti"]
	t.assert_eq(armies.size(), 2)
	t.assert_true(armies.has(bassa_army.id) and armies.has(fleet.id))
	t.assert_eq(e["province"], ["ID_BASSA"])
	t.assert_eq(e["uomini"], men_expected)
	t.assert_true(str(e["testo"]).contains("Guerra civile"), "testo leggibile")
	# gli eserciti cambiano fazione, nessun uomo si perde o nasce
	t.assert_eq(bassa_army.faction, GameState.REBEL)
	t.assert_eq(fleet.faction, GameState.REBEL)
	t.assert_false(bassa_army.in_castle, "niente castello in una provincia che passa ai ribelli")
	t.assert_true(bassa_army.path.is_empty())
	t.assert_eq(s.armies.size(), armies_before)
	t.assert_eq(_men_total(s), men_before)
	# la provincia
	var bassa := s.province("ID_BASSA")
	t.assert_eq(bassa.owner, GameState.REBEL)
	t.assert_eq(bassa.former_owner, "FN_ALPHA")
	t.assert_eq(bassa.loyalty_owner, GameState.REBEL)
	t.assert_eq(bassa.tax_level, s.rules.default_tax)
	t.assert_eq(s.province("ID_ALTA").owner, "FN_ALPHA", "le altre province restano")
	# i generali sleali escono dal gioco, gli altri restano
	t.assert_false(g.alive)
	t.assert_false(f.alive)
	t.assert_eq(g.death_cause, "guerra_civile")
	t.assert_eq(g.title, "")
	t.assert_true(s.governor_of("ID_BASSA") == null)
	t.assert_true(loyal.alive and loyal.faction == "FN_ALPHA")
	t.assert_true(s.faction("FN_ALPHA").alive)
	t.assert_true(s.leader_of("FN_ALPHA") != null, "il capo resta")
	t.assert_eq(_events_of(s, GameState.EV_TITLE_CHANGED).size(), 0, "il titolo passa con la provincia, senza un evento per generale")
	# un anno dopo lo stato e' coerente: gli eserciti rimasti hanno un comandante
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0)
	for a in s.armies:
		if a.faction == GameState.REBEL:
			continue
		var c := s.commander_of(a.id)
		t.assert_true(c != null and c.alive and c.faction == a.faction, "esercito %d" % a.id)
		if a.in_castle:
			var p := s.province(a.region)
			t.assert_true(p != null and p.owner == a.faction, "nessun esercito nel castello di una provincia altrui")


func test_guerra_civile_per_promotore_porta_via_solo_gli_sleali(t: TestContext) -> void:
	var s := _world()
	s.rules.province.civil_chance = 1.0
	var g := _governor(s)
	var f := _fleet_commander(s)
	g.loyalty = 0
	g.command = 7
	var fleet := _fleet(s)
	var bassa_army := _bassa_army(s)
	s.events.clear()
	ProvinceProcessor.process_year(s)
	var wars := _events_of(s, GameState.EV_CIVIL_WAR)
	t.assert_eq(wars.size(), 1)
	if wars.size() != 1:
		return
	t.assert_eq(wars[0]["motivo"], "promotore")
	t.assert_eq(wars[0]["promotore"], g.id)
	t.assert_eq(wars[0]["generali"], [g.id])
	t.assert_eq(wars[0]["eserciti"], [bassa_army.id])
	t.assert_eq(wars[0]["province"], ["ID_BASSA"])
	t.assert_eq(wars[0]["regione"], "ID_BASSA", "la regione del promotore")
	t.assert_eq(bassa_army.faction, GameState.REBEL)
	t.assert_eq(fleet.faction, "FN_ALPHA", "la flotta del comandante leale resta")
	t.assert_true(f.alive)
	t.assert_false(g.alive)


func test_senza_eserciti_ne_province_la_guerra_civile_non_cambierebbe_nulla(t: TestContext) -> void:
	var s := _world()
	s.rules.province.civil_chance = 1.0
	var a := _add_general(s, "ID_ALTA", 0, 1, false)
	var b := _add_general(s, "ID_ALTA", 0, 1, false)
	var rng_before := s.rng.state
	s.events.clear()
	ProvinceProcessor.process_year(s)
	t.assert_eq(_events_of(s, GameState.EV_CIVIL_WAR).size(), 0, "due sleali senza beni: niente")
	t.assert_eq(s.rng.state, rng_before, "e nessun sorteggio")
	t.assert_true(a.alive and b.alive)
	# con un esercito la guerra civile scoppia
	var own := s.create_army("FN_ALPHA", "ID_ALTA", false)
	own.stacks.append(UnitStack.new(s.units.get_unit("Spearmen").id, 100, 0))
	b.army = own.id
	_governor(s).loyalty = 0
	_fleet_commander(s).loyalty = 0
	ProvinceProcessor.process_year(s)
	t.assert_eq(_events_of(s, GameState.EV_CIVIL_WAR).size(), 1)


func test_probabilita_zero_o_nessun_innesco_nessun_sorteggio(t: TestContext) -> void:
	var s := _world()
	_governor(s).loyalty = 0
	_governor(s).command = 9
	_fleet_commander(s).loyalty = 0
	# calm(): probabilita' zero
	var rng_before := s.rng.state
	ProvinceProcessor.process_year(s)
	t.assert_eq(_events_of(s, GameState.EV_CIVIL_WAR).size(), 0)
	t.assert_eq(s.rng.state, rng_before)
	# probabilita' bassa: il sorteggio c'e' e puo' non riuscire
	s.rules.province.civil_chance = 0.0001
	ProvinceProcessor.process_year(s)
	t.assert_true(s.rng.state != rng_before, "con l'innesco si sorteggia")
	# nessun innesco: nessun sorteggio
	var calm := _world()
	calm.rules.province.civil_chance = 1.0
	var calm_rng := calm.rng.state
	ProvinceProcessor.process_year(calm)
	t.assert_eq(calm.rng.state, calm_rng)


func test_la_guerra_civile_e_deterministica(t: TestContext) -> void:
	var texts: Array[String] = []
	for run in 2:
		var s := _world(19)
		s.rules.province = ProvinceRules.new()
		s.rules.province.civil_chance = 0.5
		for p in s.provinces_of("FN_ALPHA"):
			p.tax_level = 4
		_governor(s).loyalty = 1
		_fleet_commander(s).loyalty = 1
		for i in 30:
			TurnProcessor.end_year(s)
		texts.append(SaveGame.to_json(s))
	t.assert_eq(texts[0], texts[1])


# --- la lealta' dei generali ---------------------------------------------------------------------------------------------


func test_chi_governa_una_provincia_diventa_piu_leale(t: TestContext) -> void:
	var s := _world()
	var g := _governor(s)
	var f := _fleet_commander(s)
	g.loyalty = 5
	f.loyalty = 5
	for i in 3:
		ProvinceProcessor.process_year(s)
	t.assert_eq(g.loyalty, 5, "3 punti di pressione: ancora niente")
	t.assert_eq(int(g.counters[ProvinceProcessor.PRESSURE_KEY]), 3)
	ProvinceProcessor.process_year(s)
	t.assert_eq(g.loyalty, 6, "ogni 4 punti di pressione la lealta' sale di uno")
	t.assert_eq(int(g.counters[ProvinceProcessor.PRESSURE_KEY]), 0)
	t.assert_eq(f.loyalty, 5, "senza titolo e con influenza media nulla cambia")
	# oltre il massimo non si va e la pressione non si accumula
	g.loyalty = 10
	for i in 9:
		ProvinceProcessor.process_year(s)
	t.assert_eq(g.loyalty, 10)
	t.assert_true(int(g.counters[ProvinceProcessor.PRESSURE_KEY]) < 4)


func test_le_tasse_alte_logorano_i_generali_senza_titolo(t: TestContext) -> void:
	var s := _world()
	for p in s.provinces_of("FN_ALPHA"):
		p.tax_level = 4
	var g := _governor(s)
	var f := _fleet_commander(s)
	g.loyalty = 5
	f.loyalty = 5
	for i in 4:
		ProvinceProcessor.process_year(s)
	t.assert_eq(f.loyalty, 4, "-1 all'anno per 4 anni")
	t.assert_eq(g.loyalty, 5, "il titolo (+1) compensa le tasse (-1)")
	# sotto la meta' delle province a tassa alta non conta
	var s2 := _world()
	s2.province("ID_ALTA").tax_level = 4
	_fleet_commander(s2).loyalty = 5
	for i in 8:
		ProvinceProcessor.process_year(s2)
	t.assert_eq(_fleet_commander(s2).loyalty, 5, "meta' esatta delle province: non piu' della meta'")
	# non scende sotto zero
	var s3 := _world()
	for p in s3.provinces_of("FN_ALPHA"):
		p.tax_level = 4
	_fleet_commander(s3).loyalty = 0
	for i in 12:
		ProvinceProcessor.process_year(s3)
	t.assert_eq(_fleet_commander(s3).loyalty, 0)
	t.assert_true(int(_fleet_commander(s3).counters[ProvinceProcessor.PRESSURE_KEY]) > -4)


func test_le_sconfitte_e_l_influenza_del_capo(t: TestContext) -> void:
	var s := _world()
	var f := _fleet_commander(s)
	f.loyalty = 5
	f.counters["sconfitte"] = 4
	ProvinceProcessor.process_year(s)
	t.assert_eq(f.loyalty, 4, "4 sconfitte: -4 di pressione, un punto di lealta'")
	t.assert_eq(int(f.counters[ProvinceProcessor.DEFEATS_SEEN_KEY]), 4)
	ProvinceProcessor.process_year(s)
	t.assert_eq(f.loyalty, 4, "le sconfitte gia' contate non pesano due volte")
	f.counters["sconfitte"] = 5
	ProvinceProcessor.process_year(s)
	t.assert_eq(int(f.counters[ProvinceProcessor.PRESSURE_KEY]), -1, "una sconfitta nuova")
	# influenza del capo alta o bassa
	var s2 := _world()
	var f2 := _fleet_commander(s2)
	f2.loyalty = 5
	s2.leader_of("FN_ALPHA").influence = 8
	for i in 4:
		ProvinceProcessor.process_year(s2)
	t.assert_eq(f2.loyalty, 6, "influenza >= 7: +1 all'anno")
	s2.leader_of("FN_ALPHA").influence = 3
	for i in 8:
		ProvinceProcessor.process_year(s2)
	t.assert_eq(f2.loyalty, 4, "influenza <= 3: -1 all'anno")


func test_nessuno_cambia_lealta_fuori_dai_generali(t: TestContext) -> void:
	var s := _world()
	for p in s.provinces_of("FN_ALPHA"):
		p.tax_level = 4
	var leader := s.leader_of("FN_ALPHA")
	var heir := s.heir_of("FN_ALPHA")
	var leader_loyalty := leader.loyalty
	var heir_loyalty := heir.loyalty
	for i in 8:
		ProvinceProcessor.process_year(s)
	t.assert_eq(leader.loyalty, leader_loyalty, "il capo")
	t.assert_eq(heir.loyalty, heir_loyalty, "l'erede")
	t.assert_false(leader.counters.has(ProvinceProcessor.PRESSURE_KEY))
	# i valori fissi (Auror) non si muovono
	var s2 := _world()
	s2.rules.dynasty.fixed["FN_ALPHA"] = {"loyalty": 9}
	for p in s2.provinces_of("FN_ALPHA"):
		p.tax_level = 4
	var f := _fleet_commander(s2)
	f.loyalty = 5
	f.counters["sconfitte"] = 8
	for i in 8:
		ProvinceProcessor.process_year(s2)
	t.assert_eq(f.loyalty, 5, "fedelta' fissa: nessuna pressione")
	t.assert_false(f.counters.has(ProvinceProcessor.PRESSURE_KEY))
	t.assert_eq(f.effective(Character.ATTR_LOYALTY, s2.rules, s2.campaign), 9)
	# i generali di una fazione non viva e i morti non cambiano
	var s3 := _world()
	var dead := _fleet_commander(s3)
	dead.loyalty = 5
	DynastyProcessor.kill(s3, dead, 1001, "vecchiaia", false)
	for p in s3.provinces_of("FN_ALPHA"):
		p.tax_level = 4
	for i in 8:
		ProvinceProcessor.process_year(s3)
	t.assert_eq(dead.loyalty, 5)


func test_tasse_alte_a_lungo_portano_alla_guerra_civile(t: TestContext) -> void:
	# catena completa: tasse massime -> pressione sui generali senza titolo -> lealta' <= 3 -> guerra civile
	var s := _world(3)
	s.rules.province.civil_chance = 1.0
	for p in s.provinces_of("FN_ALPHA"):
		p.tax_level = 4
	var f := _fleet_commander(s)
	var extra := _add_general(s, "ID_ALTA", 4, 1)
	f.loyalty = 4
	var year_of_war := 0
	for i in 20:
		s.events.clear()
		ProvinceProcessor.process_year(s)
		if not _events_of(s, GameState.EV_CIVIL_WAR).is_empty():
			year_of_war = i + 1
			break
	t.assert_true(year_of_war >= 4 and year_of_war <= 8, "F ed extra scendono da 4 a 3 in 4 anni, G resta leale: guerra civile all'anno %d" % year_of_war)
	t.assert_false(f.alive)
	t.assert_false(extra.alive)
