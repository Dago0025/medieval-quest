extends RefCounted
## ADR-070 (richiesta di Federico, 15/11): occupazione, ribelli lealisti e riemersione nelle terre d'origine, sul mondo di
## prova di test_sim_rebellion.gd: ALTA e BASSA sono di ALPHA all'inizio, MEZZA di BETA, SOLA dei ribelli. Nessun sorteggio
## nuovo: lealisti e consegna delle province sono deterministici.

const STARTPOS := "res://tests/fixtures/dynasty_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const HEROES := "res://tests/fixtures/dynasty_heroes.txt"


func _world(seed_value: int = 7) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var rules := Rules.new()
	rules.province.calm()
	rules.religion.other_owner_share = 0
	var s := GameSetup.new_game(campaign, UnitProdLoader.load_file(UNITS), BuildingProdLoader.load_file(BUILDINGS), rules,
		seed_value, HeroesLoader.load_file(HEROES))
	ProvinceProcessor.init_loyalty(s)
	return s


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _rebels(s: GameState, region_id: String, loyal_to: String, men: int) -> Army:
	var a := s.create_army(GameState.REBEL, region_id, false)
	a.stacks.append(UnitStack.new(s.units.get_unit("Spearmen").id, men, 0))
	a.loyal_to = loyal_to
	return a


func _clear(s: GameState, region_id: String) -> void:
	for a in s.armies_in(region_id):
		s.remove_army(a)


func _men(s: GameState) -> int:
	var n := 0
	for a in s.armies:
		n += a.men_total()
	return n


func test_occupazione_penalizza_le_terre_conquistate(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	t.assert_eq(ProvinceProcessor.occupation_term(s, bassa), 0, "dall'inizio: nessuna occupazione")
	t.assert_eq(ProvinceProcessor.origin_owner(s, bassa), "FN_ALPHA")
	bassa.owner = "FN_BETA"
	ProvinceProcessor.process_year(s)
	t.assert_eq(int(bassa.counters[ProvinceProcessor.OWNER_YEAR_KEY]), s.year)
	t.assert_eq(str(bassa.counters[ProvinceProcessor.PRIOR_OWNER_KEY]), "FN_ALPHA")
	t.assert_eq(ProvinceProcessor.occupation_term(s, bassa), 30, "20 + 10 finche' ALPHA e' viva")
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, bassa)["occupazione"], -30)
	s.year += 5
	t.assert_eq(ProvinceProcessor.occupation_term(s, bassa), 25, "un punto in meno l'anno")
	s.faction("FN_ALPHA").alive = false
	t.assert_eq(ProvinceProcessor.occupation_term(s, bassa), 15, "senza il padrone originario resta solo la parte che cala")
	s.year += 40
	t.assert_eq(ProvinceProcessor.occupation_term(s, bassa), 0, "dopo vent'anni la conquista e' accettata")
	s.faction("FN_ALPHA").alive = true
	t.assert_eq(ProvinceProcessor.occupation_term(s, bassa), 10, "il padrone vivo pesa sempre")
	# torna al padrone originario: niente penalita'
	bassa.owner = "FN_ALPHA"
	ProvinceProcessor.process_year(s)
	t.assert_eq(ProvinceProcessor.occupation_term(s, bassa), 0)
	t.assert_eq(str(bassa.counters[ProvinceProcessor.PRIOR_OWNER_KEY]), "FN_BETA")
	# ribelle all'inizio: nessun padrone da rimpiangere
	var sola := s.province("ID_SOLA")
	sola.owner = "FN_BETA"
	ProvinceProcessor.process_year(s)
	t.assert_eq(ProvinceProcessor.occupation_term(s, sola), 0)
	t.assert_eq(ProvinceProcessor.loyalist_faction(s, sola), "", "i ribelli di prima non sono una fazione")


func test_la_guarnigione_compensa_l_occupazione(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	bassa.owner = "FN_BETA"
	_clear(s, "ID_BASSA")
	ProvinceProcessor.process_year(s)
	var empty := int(ProvinceProcessor.loyalty_terms(s, bassa)["obiettivo"])
	t.assert_true(empty < s.rules.province.revolt_threshold, "sguarnita e occupata: sotto la soglia (%d)" % empty)
	var army := s.create_army("FN_BETA", "ID_BASSA", false)
	army.stacks.append(UnitStack.new(s.units.get_unit("Spearmen").id, 100, 0))
	army.stacks.append(UnitStack.new(s.units.get_unit("Spearmen").id, 100, 0))
	army.stacks.append(UnitStack.new(s.units.get_unit("Spearmen").id, 100, 0))
	var held := int(ProvinceProcessor.loyalty_terms(s, bassa)["obiettivo"])
	t.assert_eq(held - empty, s.rules.province.garrison_max, "300 uomini danno il massimo della guarnigione")


func test_nelle_terre_tolte_i_ribelli_sono_lealisti(t: TestContext) -> void:
	var s := _world()
	s.rules.province.revolt_k = 1.0
	s.rules.province.revolt_max_chance = 1.0
	var bassa := s.province("ID_BASSA")
	bassa.owner = "FN_BETA"
	bassa.loyalty = 30
	_clear(s, "ID_BASSA")
	ProvinceProcessor.process_year(s)
	var events := _events_of(s, GameState.EV_REBELLION)
	t.assert_eq(events.size(), 1)
	if events.size() == 1:
		t.assert_eq(events[0]["tipo_ribelli"], ProvinceProcessor.REBEL_LOYALISTS)
		t.assert_eq(events[0]["lealisti_di"], "FN_ALPHA")
		var army := s.army(int(events[0]["esercito"]))
		t.assert_true(army != null and army.faction == GameState.REBEL and army.loyal_to == "FN_ALPHA")
		t.assert_true(str(events[0]["testo"]).contains("lealisti"), str(events[0]["testo"]))
		var mix := ProvinceProcessor.loyalist_units(s, "FN_ALPHA", s.campaign.region("ID_BASSA"))
		t.assert_false(mix.is_empty(), "ALPHA ha truppe adatte")
		var ids := PackedStringArray()
		for u in mix:
			ids.append(u.id)
		if army != null:
			for st in army.stacks:
				t.assert_true(ids.has(st.unit_id), "pila %s tra le truppe dei lealisti %s" % [st.unit_id, str(ids)])
			t.assert_eq(army.stacks[0].unit_id, mix[0].id, "prima la fanteria")
	# con i lealisti spenti: ribelli comuni
	var off := _world()
	off.rules.province.revolt_k = 1.0
	off.rules.province.revolt_max_chance = 1.0
	off.rules.province.loyalists = false
	var b2 := off.province("ID_BASSA")
	b2.owner = "FN_BETA"
	b2.loyalty = 30
	_clear(off, "ID_BASSA")
	ProvinceProcessor.process_year(off)
	var ev2 := _events_of(off, GameState.EV_REBELLION)
	t.assert_eq(ev2.size(), 1)
	if ev2.size() == 1:
		t.assert_true(ev2[0]["tipo_ribelli"] != ProvinceProcessor.REBEL_LOYALISTS)
		t.assert_false(ev2[0].has("lealisti_di"))
	# nelle proprie terre d'origine nessun lealista
	t.assert_eq(ProvinceProcessor.loyalist_faction(s, s.province("ID_MEZZA")), "")


func test_il_proprietario_precedente_viene_prima_di_quello_originario(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	bassa.owner = "FN_BETA"
	ProvinceProcessor.process_year(s)
	bassa.owner = "FN_GAMMA"
	s.faction("FN_GAMMA").alive = true
	ProvinceProcessor.process_year(s)
	t.assert_eq(ProvinceProcessor.loyalist_faction(s, bassa), "FN_BETA", "fedeli a chi l'aveva prima")
	s.faction("FN_BETA").alive = false
	s.faction("FN_BETA").is_player = true
	t.assert_eq(ProvinceProcessor.loyalist_faction(s, bassa), "FN_ALPHA", "il precedente non puo' tornare: il padrone originario")


func test_i_lealisti_consegnano_la_provincia(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	_clear(s, "ID_BASSA")
	ProvinceProcessor.make_rebel(s, bassa, "FN_BETA")
	var loyal := _rebels(s, "ID_BASSA", "FN_ALPHA", 100)
	var plain := _rebels(s, "ID_BASSA", "", 60)
	var men := _men(s)
	ProvinceProcessor.process_year(s)
	t.assert_eq(bassa.owner, "FN_ALPHA", "la provincia torna ad ALPHA")
	t.assert_eq(loyal.faction, "FN_ALPHA")
	t.assert_eq(loyal.loyal_to, "")
	t.assert_eq(plain.faction, GameState.REBEL, "i ribelli comuni restano ribelli")
	t.assert_eq(_men(s), men, "nessun uomo creato")
	var events := _events_of(s, GameState.EV_LOYALISTS_RETURN)
	t.assert_eq(events.size(), 1)
	if events.size() == 1:
		t.assert_eq(events[0]["fazione"], "FN_ALPHA")
		t.assert_eq(events[0]["eserciti"], [loyal.id])
		t.assert_eq(events[0]["uomini"], 0)
		var text := CampaignUiText.format_event(s, events[0])
		t.assert_true(text.contains("lealisti"), text)
	t.assert_eq(ProvinceProcessor.occupation_term(s, bassa), 0, "e' terra d'origine di ALPHA")


func test_i_lealisti_di_una_fazione_estinta_la_fanno_riemergere(t: TestContext) -> void:
	var s := _world()
	for c in s.characters_of("FN_ALPHA"):
		DynastyProcessor.kill(s, c, s.year + 1, "vecchiaia", false)
	TurnProcessor.end_year(s)
	t.assert_false(s.faction("FN_ALPHA").alive)
	t.assert_eq(s.rules.province.reemerge_chance, 0.0, "nessun sorteggio: la riemersione viene dai lealisti")
	var loyal := _rebels(s, "ID_BASSA", "FN_ALPHA", 100)
	TurnProcessor.end_year(s)
	var events := _events_of(s, GameState.EV_FACTION_REEMERGED)
	t.assert_eq(events.size(), 1)
	if events.size() == 1:
		t.assert_eq(events[0]["provincia"], "ID_BASSA")
		# nome del capo, non il suo numero (segnalazione di Federico del 22/11/2026)
		var leader := s.leader_of("FN_ALPHA")
		var text := CampaignUiText.format_event(s, events[0])
		t.assert_true(leader != null and text.contains(leader.full_name()), text)
		var old := events[0].duplicate()
		old.erase("nome_capo")
		old["capo"] = float(leader.id)   # salvataggi di prima: solo il numero, decimale dal JSON
		var old_text := CampaignUiText.format_event(s, old)
		t.assert_true(old_text.contains(leader.full_name()) and not old_text.contains(str(leader.id) + " come"), old_text)
	t.assert_true(s.faction("FN_ALPHA").alive)
	t.assert_eq(loyal.faction, "FN_ALPHA")
	t.assert_eq(loyal.loyal_to, "")
	# fazione del giocatore: i lealisti tornano ribelli comuni
	var p := _world()
	p.faction("FN_ALPHA").is_player = true
	for c in p.characters_of("FN_ALPHA"):
		DynastyProcessor.kill(p, c, p.year + 1, "vecchiaia", false)
	p.victory = VictoryState.new()
	TurnProcessor.end_year(p)
	var l2 := _rebels(p, "ID_BASSA", "FN_ALPHA", 100)
	p.victory = VictoryState.new()
	TurnProcessor.end_year(p)
	t.assert_false(p.faction("FN_ALPHA").alive)
	t.assert_eq(l2.faction, GameState.REBEL)
	t.assert_eq(l2.loyal_to, "")


func test_riemersione_nelle_terre_d_origine(t: TestContext) -> void:
	var s := _world()
	for c in s.characters_of("FN_ALPHA"):
		DynastyProcessor.kill(s, c, s.year + 1, "vecchiaia", false)
	TurnProcessor.end_year(s)
	var alta := s.province("ID_ALTA")
	var bassa := s.province("ID_BASSA")
	alta.former_owner = "FN_BETA"
	bassa.former_owner = "FN_BETA"
	alta.loyalty = 100
	bassa.loyalty = 100
	var site := ProvinceProcessor.reemergence_site(s, "FN_ALPHA")
	t.assert_true(site != null and site.id == "ID_ALTA", "le terre d'origine contano anche se le aveva perse")
	t.assert_true(ProvinceProcessor.reemergence_site(s, "FN_GAMMA") == null)


func test_salvataggio_dei_lealisti(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	bassa.owner = "FN_BETA"
	ProvinceProcessor.process_year(s)
	var a := _rebels(s, "ID_BASSA", "FN_ALPHA", 100)
	t.assert_eq(Army.from_dict(a.to_dict()).loyal_to, "FN_ALPHA")
	var plain := _rebels(s, "ID_BASSA", "", 10)
	t.assert_false(plain.to_dict().has("lealisti"), "campo assente per i ribelli comuni")
	t.assert_true(CampaignUiText.describe_army(s, a).contains("lealisti"), "la scheda dell'esercito lo dice")
	t.assert_false(CampaignUiText.describe_army(s, plain).contains("lealisti"))
	var r := SaveGame.from_dict(SaveGame.to_dict(s), s.campaign, s.units, s.buildings, Rules.new(), HeroesLoader.load_file(HEROES))
	var back: GameState = r["stato"]
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "andata e ritorno identici")
	t.assert_eq(str(back.province("ID_BASSA").counters[ProvinceProcessor.PRIOR_OWNER_KEY]), "FN_ALPHA")
