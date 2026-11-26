extends RefCounted
## Limiti storici, guardia del capo e insurrezioni lealiste (ADR-114, richiesta di Federico del 21/11/2026): invenzioni che
## sbloccano edifici e unita', niente cavalli nelle Americhe prima degli europei, il capo sempre con la guardia a cavallo,
## le fazioni sconfitte che ritentano di tornare. Mondo del Papato (tests/fixtures/papacy_*.txt); il file reale per la
## modalita' Auror si salta senza installazione.

const W := preload("res://tests/unit/papacy_world.gd")


## Evento storico della polvere da sparo (indice 37 come nella tabella reale), non ancora accaduto.
func _gunpowder(s: GameState) -> void:
	var ev := EventRules.HistoricalEvent.new()
	ev.index = 37
	ev.key = "polvere_da_sparo"
	ev.year_from = 1260
	ev.year_to = 1260
	s.rules.events.history.append(ev)
	s.rules.history.invention_free = PackedStringArray()


# --- invenzioni ------------------------------------------------------------------------------------------------------


func test_un_edificio_aspetta_la_sua_invenzione(t: TestContext) -> void:
	var s := W.world()
	_gunpowder(s)
	s.faction(W.A).treasury = 100000
	var castle2 := s.buildings.get_family("CASTLE").get_level(2)
	castle2.inventions = PackedStringArray(["GUNPOWDER"])
	var r := GameCommands.can_queue_building(s, W.A, W.NORD2, "CASTLE")
	t.assert_false(bool(r["ok"]), "prima della polvere da sparo")
	t.assert_true(str(r["errore"]).contains("polvere da sparo"), str(r["errore"]))
	s.rules.history.invention_free = PackedStringArray([W.A])
	t.assert_true(bool(GameCommands.can_queue_building(s, W.A, W.NORD2, "CASTLE")["ok"]), "chi ne e' esente (Auror) non aspetta")
	s.rules.history.invention_free = PackedStringArray()
	s.historical_done[37] = true
	t.assert_true(bool(GameCommands.can_queue_building(s, W.A, W.NORD2, "CASTLE")["ok"]), "dopo l'evento si costruisce")


func test_senza_evento_l_invenzione_non_limita(t: TestContext) -> void:
	var s := W.world()
	s.faction(W.A).treasury = 100000
	s.buildings.get_family("CASTLE").get_level(2).inventions = PackedStringArray(["GUNPOWDER"])
	t.assert_true(HistoricalLimits.invention_known(s, "GUNPOWDER"), "tabella senza l'evento")
	t.assert_true(bool(GameCommands.can_queue_building(s, W.A, W.NORD2, "CASTLE")["ok"]))


func test_le_unita_delle_invenzioni_mancanti_non_compaiono(t: TestContext) -> void:
	var s := W.world()
	_gunpowder(s)
	s.faction(W.G).treasury = 100000
	s.buildings.get_family("CASTLE").get_level(2).inventions = PackedStringArray(["GUNPOWDER"])
	var halberd := s.units.get_unit("Halberdiers")
	t.assert_false(HistoricalLimits.unit_inventions_ok(s, W.G, halberd), "richiede CASTLE2, che aspetta la polvere da sparo")
	t.assert_true(HistoricalLimits.unit_inventions_ok(s, W.G, s.units.get_unit("Spearmen")), "senza requisiti sempre")
	var r := GameCommands.can_queue_unit(s, W.G, W.EST, "Halberdiers")
	t.assert_false(bool(r["ok"]), "EST ha gia' Castle2, ma l'invenzione manca")
	t.assert_true(str(r["errore"]).contains("invenzione"), str(r["errore"]))
	for u in ProvinceProcessor.loyalist_units(s, W.G, s.campaign.region(W.EST)):
		t.assert_true(u.id != "Halberdiers", "nemmeno tra i lealisti")
	s.historical_done[37] = true
	t.assert_true(HistoricalLimits.unit_inventions_ok(s, W.G, halberd))
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.G, W.EST, "Halberdiers")["ok"]))


# --- cavalli nelle Americhe ----------------------------------------------------------------------------------------


func test_niente_cavalli_prima_degli_europei(t: TestContext) -> void:
	var s := W.world()
	s.faction(W.A).treasury = 100000
	s.rules.history.horseless_factions = PackedStringArray([W.A])
	s.rules.history.americas = PackedStringArray([W.NORD1, W.NORD2, W.NORD3])
	t.assert_false(HistoricalLimits.update_contact(s), "le Americhe sono solo dei nativi")
	var r := GameCommands.can_queue_unit(s, W.A, W.NORD1, "Chevaliers")
	t.assert_false(bool(r["ok"]), "cavalleria vietata")
	t.assert_true(str(r["errore"]).contains("cavallo"), str(r["errore"]))
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.A, W.NORD1, "Spearmen")["ok"]), "la fanteria si'")
	s.province(W.NORD3).owner = W.G
	t.assert_true(HistoricalLimits.update_contact(s), "una fazione venuta da fuori in una regione delle Americhe")
	t.assert_eq(s.americas_contact_year, s.year)
	t.assert_eq(W.events_of(s, GameState.EV_AMERICAS_CONTACT).size(), 1)
	var line := CampaignUiText.format_event(s, W.events_of(s, GameState.EV_AMERICAS_CONTACT)[0])
	t.assert_true(line.begins_with("Primo approdo straniero nelle Americhe:") and line.contains("Nord3"), "testo leggibile, non la chiave: " + line)
	var window := CampaignUiAlerts.windows(s, W.A)
	t.assert_eq(str(window[0]["testo"]), line, "la finestra «Il Nuovo Mondo» mostra lo stesso testo")
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.A, W.NORD1, "Chevaliers")["ok"]), "da ora i cavalli ci sono")
	s.province(W.NORD3).owner = W.A
	t.assert_false(HistoricalLimits.update_contact(s), "l'arrivo resta, anche se gli europei se ne vanno")
	t.assert_true(HistoricalLimits.horses_allowed(s, W.A))


func test_i_ribelli_delle_americhe_non_hanno_cavalli(t: TestContext) -> void:
	var s := W.world()
	s.rules.history.americas = PackedStringArray([W.RIBELLE])
	var horse := s.units.get_unit("Chevaliers")
	t.assert_false(HistoricalLimits.unit_allowed(s, "", horse, W.RIBELLE))
	t.assert_true(HistoricalLimits.unit_allowed(s, "", horse, W.EST), "fuori dalle Americhe si'")
	s.americas_contact_year = 1100
	t.assert_true(HistoricalLimits.unit_allowed(s, "", horse, W.RIBELLE))


func test_l_arrivo_si_salva(t: TestContext) -> void:
	var s := W.world()
	s.americas_contact_year = 1492
	var d := SaveGame.to_dict(s)
	t.assert_eq(int(d["contatto_americhe"]), 1492)


# --- guardia del capo ------------------------------------------------------------------------------------------------


func test_il_capo_riceve_la_guardia_a_cavallo(t: TestContext) -> void:
	var s := W.world()
	s.rules.history.guard_enabled = true
	var king := s.leader_of(W.A)
	var army := s.army(king.army)
	army.stacks.clear()
	army.stacks.append(s.new_stack(W.A, "Spearmen", 100))
	s.events.clear()
	RoyalGuard.ensure(s)
	t.assert_true(RoyalGuard.has_guard(s, army, true), "una pila a cavallo nell'esercito del capo")
	t.assert_eq(army.stacks.size(), 2)
	var guard := s.units.get_unit(army.stacks[1].unit_id)
	t.assert_true(guard.is_cavalry() and not guard.required_tokens().has("CHAPTER_HOUSE"), "cavalleria, non un ordine militare: %s" % guard.id)
	var ev: Array[Dictionary] = []
	for e in W.events_of(s, GameState.EV_ROYAL_GUARD):
		if str(e["fazione"]) == W.A:
			ev.append(e)
	t.assert_eq(ev.size(), 1)
	t.assert_eq(int(ev[0]["uomini"]), army.stacks[1].men, "gli uomini creati sono dichiarati")
	RoyalGuard.ensure(s)
	t.assert_eq(army.stacks.size(), 2, "una sola guardia")
	t.assert_eq(CampaignUiText.commander_stack(s, army), 1, "il capo combatte con la guardia")


func test_il_capo_senza_esercito_ne_riceve_uno(t: TestContext) -> void:
	var s := W.world()
	s.rules.history.guard_enabled = true
	var king := s.leader_of(W.G)
	var old := s.army(king.army)
	s.armies.erase(old)
	king.army = 0
	RoyalGuard.ensure(s)
	var army := s.army(king.army)
	t.assert_true(army != null, "esercito nuovo")
	t.assert_eq(army.region, W.EST, "nella sua provincia")
	t.assert_eq(army.stacks.size(), 1)
	t.assert_true(RoyalGuard.has_guard(s, army, true))


func test_esercito_pieno_cede_una_pila(t: TestContext) -> void:
	var s := W.world()
	s.rules.history.guard_enabled = true
	var king := s.leader_of(W.A)
	var army := s.army(king.army)
	army.stacks.clear()
	for i in s.rules.max_stacks:
		army.stacks.append(s.new_stack(W.A, "Spearmen", 100))
	var before := s.armies.size()
	RoyalGuard.ensure(s)
	t.assert_eq(army.stacks.size(), s.rules.max_stacks)
	t.assert_true(RoyalGuard.has_guard(s, army, true))
	t.assert_eq(s.armies.size(), before + 1, "la pila tolta va in un esercito nuovo")


func test_i_popoli_senza_cavalli_hanno_la_guardia_a_piedi(t: TestContext) -> void:
	var s := W.world()
	s.rules.history.guard_enabled = true
	s.rules.history.horseless_factions = PackedStringArray([W.G])
	var king := s.leader_of(W.G)
	s.armies.erase(s.army(king.army))
	king.army = 0
	RoyalGuard.ensure(s)
	var army := s.army(king.army)
	t.assert_true(army != null)
	var u := s.units.get_unit(army.stacks[0].unit_id)
	t.assert_false(HistoricalLimits.is_mounted(u), "a piedi: %s" % u.id)
	t.assert_true(RoyalGuard.guard_unit(s, W.G, true) == null, "la cavalleria non e' ammessa")
	t.assert_true(RoyalGuard.guard_unit(s, W.A, true) != null, "per gli altri si'")


func test_guardia_spenta_nei_mondi_di_prova(t: TestContext) -> void:
	var s := W.world()
	var king := s.leader_of(W.A)
	var army := s.army(king.army)
	army.stacks.clear()
	army.stacks.append(s.new_stack(W.A, "Spearmen", 100))
	RoyalGuard.ensure(s)
	t.assert_eq(army.stacks.size(), 1, "Rules.new() senza storia.cfg")
	t.assert_true(Rules.load_file().history.guard_enabled, "accesa nel gioco")


# --- insurrezioni lealiste -------------------------------------------------------------------------------------------


## BETA sconfitta: SUD1 e SUD2 passano ad ALPHA, BETA estinta; insurrezioni dopo un anno.
func _beta_defeated() -> GameState:
	var s := W.world()
	for a in s.armies_of(W.B):
		s.armies.erase(a)
	s.faction(W.B).alive = false
	s.province(W.SUD1).owner = W.A
	s.province(W.SUD2).owner = W.A
	s.province(W.SUD1).loyalty = 90
	s.province(W.SUD2).loyalty = 60
	s.rules.province.uprising_years_min = 1
	s.rules.province.uprising_years_max = 1
	return s


func test_la_fazione_sconfitta_insorge_nelle_sue_terre(t: TestContext) -> void:
	var s := _beta_defeated()
	s.events.clear()
	ProvinceProcessor._loyalist_uprisings(s, s.year + 1)
	var ev := W.events_of(s, GameState.EV_REBELLION)
	t.assert_eq(ev.size(), 1, "un'insurrezione")
	t.assert_eq(str(ev[0]["provincia"]), W.SUD2, "la sua provincia d'inizio con la lealta' piu' bassa")
	t.assert_true(bool(ev[0]["insurrezione"]))
	t.assert_eq(str(ev[0]["lealisti_di"]), W.B)
	var rebels: Army = s.army(int(ev[0]["esercito"]))
	t.assert_eq(rebels.faction, GameState.REBEL)
	t.assert_eq(rebels.loyal_to, W.B)
	t.assert_eq(rebels.stacks.size(), s.rules.province.uprising_stacks)
	t.assert_eq(int(ev[0]["uomini"]), rebels.men_total())
	t.assert_eq(s.faction(W.B).uprisings, 1)
	t.assert_eq(s.faction(W.B).dead_years, 0, "l'attesa riparte")
	# i lealisti prendono la provincia: l'anno dopo la consegnano alla fazione, che riemerge
	s.province(W.SUD2).owner = GameState.REBEL
	s.events.clear()
	ProvinceProcessor._loyalist_handover(s, s.year + 1)
	t.assert_true(s.faction(W.B).alive, "la fazione riemerge")
	t.assert_eq(s.province(W.SUD2).owner, W.B)
	t.assert_eq(W.events_of(s, GameState.EV_FACTION_REEMERGED).size(), 1)


func test_in_una_provincia_ribelle_riemerge_subito(t: TestContext) -> void:
	var s := _beta_defeated()
	s.province(W.SUD1).owner = GameState.REBEL
	ProvinceProcessor._loyalist_uprisings(s, s.year + 1)
	t.assert_true(s.faction(W.B).alive)
	t.assert_eq(s.province(W.SUD1).owner, W.B)


func test_l_armata_cresce_a_ogni_tentativo(t: TestContext) -> void:
	var s := _beta_defeated()
	s.faction(W.B).uprisings = 2
	s.events.clear()
	ProvinceProcessor._loyalist_uprisings(s, s.year + 1)
	var ev := W.events_of(s, GameState.EV_REBELLION)
	t.assert_eq(int(ev[0]["pile"]), s.rules.province.uprising_stacks + 2 * s.rules.province.uprising_growth)


func test_mai_il_giocatore_e_rispetta_l_attesa(t: TestContext) -> void:
	var s := _beta_defeated()
	s.faction(W.B).is_player = true
	ProvinceProcessor._loyalist_uprisings(s, s.year + 1)
	t.assert_eq(W.events_of(s, GameState.EV_REBELLION).size(), 0, "la fazione del giocatore non torna da sola")
	s.faction(W.B).is_player = false
	s.rules.province.uprising_years_min = 20
	s.rules.province.uprising_years_max = 40
	for i in 19:
		ProvinceProcessor._loyalist_uprisings(s, s.year + 1)
	t.assert_eq(W.events_of(s, GameState.EV_REBELLION).size(), 0, "prima di 20 anni nulla")
	t.assert_eq(s.faction(W.B).dead_years, 19)
	t.assert_eq(s.rules.province.uprising_chance(40), 1.0)
	t.assert_eq(s.rules.province.uprising_chance(30), 1.0 / 11.0)


func test_gli_anni_da_estinta_si_salvano(t: TestContext) -> void:
	var f := FactionState.new("FN_X", 0, false)
	f.dead_years = 12
	f.uprisings = 3
	var back := FactionState.from_dict(f.to_dict())
	t.assert_eq(back.dead_years, 12)
	t.assert_eq(back.uprisings, 3)
	t.assert_false(FactionState.new("FN_Y", 0, true).to_dict().has("anni_estinta"), "le vive non scrivono nulla")


func test_il_ritorno_ha_la_sua_finestra(t: TestContext) -> void:
	var s := W.world()
	s.events.clear()
	s.add_event(GameState.EV_FACTION_REEMERGED, {"fazione": W.B, "regione": W.SUD1, "testo": "torna"})
	s.add_event(GameState.EV_PAPACY_REEMERGED, {"fazione": W.P, "regione": W.ROMA, "testo": "torna il Papa"})
	var out := CampaignUiAlerts.windows(s, W.A)
	t.assert_eq(out.size(), 2)
	t.assert_eq(str(out[0]["tema"]), "fazione_riemersa")
	t.assert_eq(str(out[1]["luogo"]), W.ROMA)
	t.assert_eq(CampaignUiAlerts.windows(s, W.B).size(), 1, "il proprio ritorno non si annuncia")


func rules_for_test() -> Rules:
	var rules := Rules.load_file()
	Scenario.apply_rules(rules)
	return rules


# --- modalita' Auror sui dati reali --------------------------------------------------------------------------------


func test_modalita_auror_progressione_storica(t: TestContext) -> void:
	if not GameFiles.is_available():
		t.skip("installazione di MTW non trovata")
		return
	Scenario.set_auror(true)
	var d := Scenario.load_startpos()
	var units := Scenario.load_units(GameFiles.prod_file(d.unit_prod_file))
	var buildings := Scenario.load_buildings(GameFiles.prod_file(d.building_prod_file))
	for uid in ["Arquebusier", "Handgun", "BombardCrew"]:
		var u := units.get_unit(uid)
		t.assert_false(u.available_in_period("EARLY"), "%s non nell'epoca antica" % uid)
		t.assert_true(u.available_in_period("HIGH"), uid)
	t.assert_true(buildings.get_family("GUNSMITH").get_level(1).inventions.has("GUNPOWDER"))
	t.assert_true(buildings.get_family("SHIPYARD").get_level(3).inventions.has("COMPASS"))
	# le unita' dei livelli che richiedono un livello con l'invenzione aspettano anche loro (dati reali, anno 1000)
	var st := GameSetup.new_game(d, units, buildings, rules_for_test(), 7)
	for uid in ["Arquebusier", "BombardCrew", "Carrack"]:
		t.assert_false(HistoricalLimits.unit_inventions_ok(st, "FN_ENGLISH", units.get_unit(uid)), "%s prima delle invenzioni" % uid)
		t.assert_true(HistoricalLimits.unit_inventions_ok(st, "FN_DANISH", units.get_unit(uid)), "%s per gli Auror" % uid)
	t.assert_true(HistoricalLimits.unit_inventions_ok(st, "FN_ENGLISH", units.get_unit("Longbows")))
	var ghazi := units.get_unit("GhaziInfantry")
	var with_mosque := false
	for group in ghazi.requires:
		if group.has("MOSQUE"):
			with_mosque = true
	t.assert_true(with_mosque, "di nuovo con la moschea per i musulmani")
	t.assert_true(ghazi.requires.size() >= 2, "e l'alternativa della mod per gli Auror")
	var rules := Rules.load_file()
	Scenario.apply_rules(rules)
	t.assert_true(rules.history.ignores_inventions("FN_DANISH"), "gli Auror non aspettano la polvere da sparo")
	t.assert_true(rules.lifts_unit_limits("FN_DANISH", units.get_unit("Arquebusier")), "e arruolano gli archibugieri da subito")
	t.assert_false(rules.history.ignores_inventions("FN_ENGLISH"))
