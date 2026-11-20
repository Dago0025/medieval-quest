extends RefCounted
## Test della ritirata parziale e dei prigionieri (ADR-073): presa in battaglia, cattura per intero, decisioni dell'IA e del
## giocatore (liberare, riscatto, giustiziare), ritorno a casa, re catturato, salvataggi. Mondo di prova: papacy_world.gd.

const W := preload("res://tests/unit/papacy_world.gd")


func _restore(data: Dictionary) -> GameState:
	var campaign := StartposLoader.load_file(W.STARTPOS)
	var units := UnitProdLoader.load_file(W.UNITS)
	var buildings := BuildingProdLoader.load_file(W.BUILDINGS)
	var r := SaveGame.from_dict(data, campaign, units, buildings, W.quiet_rules())
	return r["stato"]


## ALPHA (il re al comando) attacca GAMMA a EST da NORD1 e perde (esito forzato).
func _lost_attack() -> Dictionary:
	var s := W.world()
	s.declare_war(W.A, W.G)
	s.rules.combat.forced_outcome = -1
	var army := W.land_army(s, W.A, W.NORD1)
	army.region = W.EST
	army.from_region = W.NORD1
	army.arrived_year = s.year
	return {"stato": s, "esercito": army, "re": s.leader_of(W.A)}


func _prisoners_of(s: GameState, captor: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.prisoners:
		if str(e["vincitore"]) == captor:
			out.append(e)
	return out


func _outcomes(s: GameState) -> Array[String]:
	var out: Array[String] = []
	for e in W.events_of(s, GameState.EV_PRISONERS):
		out.append(str(e["esito"]))
	return out


# --- parametri ---------------------------------------------------------------------------------------------------


func test_i_parametri_dei_prigionieri(t: TestContext) -> void:
	var from_file := CombatRules.load_file()
	t.assert_eq(from_file.errors, PackedStringArray(), "scontri.cfg si legge senza errori")
	var c := CombatRules.new()
	t.assert_eq(from_file.capture_share, c.capture_share, "quota_catturati uguale al predefinito")
	t.assert_eq(from_file.ransom_leader, c.ransom_leader)
	t.assert_eq(c.capture_share, 0.3)
	t.assert_eq(c.ransom_share, 0.5)
	t.assert_eq(c.ransom_general, 500)
	t.assert_eq(c.ransom_royal, 1500)
	t.assert_eq(c.ransom_leader, 3000)
	t.assert_eq(c.ai_execute_dread, 8)


# --- presa ---------------------------------------------------------------------------------------------------------


func test_chi_perde_e_si_ritira_lascia_dei_prigionieri(t: TestContext) -> void:
	var w := _lost_attack()
	var s: GameState = w["stato"]
	var army: Army = w["esercito"]
	var king: Character = w["re"]
	WarProcessor.field_battles(s)
	t.assert_true(s.armies.has(army), "l'esercito sconfitto c'e' ancora")
	t.assert_eq(army.region, W.NORD1, "si ritira nella provincia confinante propria")
	t.assert_eq(s.commander_of(army.id), king, "il re si ritira con il suo esercito")
	t.assert_false(PrisonerProcessor.is_captive(king))
	var taken := _prisoners_of(s, W.G)
	t.assert_eq(taken.size(), 1, "una voce di prigionieri per GAMMA")
	var e := taken[0]
	t.assert_eq(e["perdente"], W.A)
	t.assert_eq(e["regione"], W.EST)
	t.assert_eq(e["stato"], PrisonerProcessor.STATE_PENDING)
	t.assert_eq(e["personaggi"], [])
	var captured := PrisonerProcessor.men_of(e)
	t.assert_true(captured > 0, "qualche prigioniero")
	t.assert_eq(captured, floori(float(captured + army.men_total()) * 0.3), "il 30% dei sopravvissuti")


func test_take_share_lascia_almeno_un_uomo_per_pila(t: TestContext) -> void:
	var s := W.world()
	s.rules.combat.capture_share = 1.0
	var army := W.land_army(s, W.A, W.NORD1)
	var before := army.stacks.size()
	var men := PrisonerProcessor.take_share(s, army, W.NORD1, W.G, 0)
	t.assert_eq(army.stacks.size(), before)
	for st in army.stacks:
		t.assert_eq(st.men, 1)
	t.assert_true(men > 0)


func test_senza_vie_di_ritirata_tutto_catturato_re_compreso(t: TestContext) -> void:
	var w := _lost_attack()
	var s: GameState = w["stato"]
	var army: Army = w["esercito"]
	var king: Character = w["re"]
	army.from_region = ""
	s.province(W.NORD1).owner = W.D   # nessuna provincia propria confinante con EST
	var men := army.men_total()
	WarProcessor.field_battles(s)
	t.assert_false(s.armies.has(army), "catturato")
	var e := _prisoners_of(s, W.G)[0]
	t.assert_eq(e["personaggi"], [king.id], "il re e' prigioniero")
	t.assert_true(PrisonerProcessor.is_captive(king))
	t.assert_eq(king.army, 0)
	t.assert_eq(king.region, "", "non sta in nessuna regione")
	t.assert_eq(king.role, Character.ROLE_LEADER, "resta re")
	t.assert_true(PrisonerProcessor.men_of(e) > 0 and PrisonerProcessor.men_of(e) <= men)
	# nessuno lo prende per comandare un esercito
	DynastyProcessor.ensure_commanders(s, s.rng, s.year + 1)
	t.assert_eq(king.army, 0)


func test_il_comandante_di_un_esercito_annientato_e_catturato(t: TestContext) -> void:
	var s := W.world()
	var army := W.land_army(s, W.A, W.NORD1)
	var king := s.commander_of(army.id)
	s.remove_army(army)
	t.assert_true(PrisonerProcessor.capture_commander(s, army.id, W.A, W.NORD1, W.G, 0))
	t.assert_true(PrisonerProcessor.is_captive(king))
	t.assert_eq(_prisoners_of(s, W.G)[0]["personaggi"], [king.id])


func test_i_ribelli_sconfitti_non_fanno_prigionieri(t: TestContext) -> void:
	var s := W.world()
	var rebels := W.land_army(s, GameState.REBEL, W.RIBELLE)
	t.assert_eq(PrisonerProcessor.take_share(s, rebels, W.RIBELLE, W.A, 0), 0)
	t.assert_eq(PrisonerProcessor.capture_army(s, rebels, W.RIBELLE, W.A, 0), 0)
	t.assert_true(s.prisoners.is_empty())


func test_le_catture_dello_stesso_scontro_stanno_in_una_voce(t: TestContext) -> void:
	var s := W.world()
	var army := W.land_army(s, W.A, W.NORD1)
	PrisonerProcessor.take_share(s, army, W.NORD1, W.G, 0)
	PrisonerProcessor.take_share(s, army, W.NORD1, W.G, 0)
	t.assert_eq(s.prisoners.size(), 1)
	t.assert_eq((s.prisoners[0]["pile"] as Array).size(), 2)


func test_il_riscatto(t: TestContext) -> void:
	var s := W.world()
	var e := {"pile": [UnitStack.new("Spearmen", 40, 0).to_dict()], "personaggi": []}
	t.assert_eq(PrisonerProcessor.price(s, e), 20, "Spearmen 100 fiorini per 100 uomini: 40 uomini x 1 x 0,5")
	e["personaggi"] = [s.leader_of(W.A).id]
	t.assert_eq(PrisonerProcessor.price(s, e), 3020, "piu' il re")


# --- decisioni dell'IA ---------------------------------------------------------------------------------------------


func test_l_ia_chiede_il_riscatto_e_l_ia_paga_per_il_re(t: TestContext) -> void:
	var w := _lost_attack()
	var s: GameState = w["stato"]
	var king: Character = w["re"]
	w["esercito"].from_region = ""
	s.province(W.NORD1).owner = W.D
	s.province(W.NORD2).owner = W.A
	s.leader_of(W.G).dread = 0
	s.faction(W.A).treasury = 0
	var g_before := s.faction(W.G).treasury
	WarProcessor.field_battles(s)
	var price := PrisonerProcessor.price(s, s.prisoners[0])
	PrisonerProcessor.process_year(s)
	t.assert_true(s.prisoners.is_empty(), "deciso subito")
	t.assert_eq(_outcomes(s), [PrisonerProcessor.OUTCOME_TAKEN, PrisonerProcessor.OUTCOME_RANSOMED])
	t.assert_eq(s.faction(W.A).treasury, -price, "paga anche a debito per il re")
	t.assert_eq(s.faction(W.G).treasury, g_before + price)
	t.assert_false(PrisonerProcessor.is_captive(king))
	t.assert_eq(king.region, W.NORD2, "torna nella provincia propria piu' vicina")
	var back := s.army(king.army)
	t.assert_true(back != null and back.region == W.NORD2 and back.faction == W.A, "al comando dei suoi uomini riscattati")


func test_l_ia_senza_fiorini_rifiuta_e_i_prigionieri_muoiono(t: TestContext) -> void:
	var w := _lost_attack()
	var s: GameState = w["stato"]
	s.leader_of(W.G).dread = 0
	s.faction(W.A).treasury = 0
	WarProcessor.field_battles(s)
	PrisonerProcessor.process_year(s)
	t.assert_true(s.prisoners.is_empty())
	t.assert_eq(_outcomes(s), [PrisonerProcessor.OUTCOME_TAKEN, PrisonerProcessor.OUTCOME_REFUSED])
	t.assert_eq(s.faction(W.A).treasury, 0)


func test_l_ia_crudele_giustizia_anche_il_re(t: TestContext) -> void:
	var w := _lost_attack()
	var s: GameState = w["stato"]
	var king: Character = w["re"]
	w["esercito"].from_region = ""
	s.province(W.NORD1).owner = W.D
	s.leader_of(W.G).dread = 10
	var g_commander := s.commander_of(W.land_army(s, W.G, W.EST).id)
	WarProcessor.field_battles(s)
	var men := PrisonerProcessor.men_of(s.prisoners[0])
	PrisonerProcessor.process_year(s)
	t.assert_eq(_outcomes(s), [PrisonerProcessor.OUTCOME_TAKEN, PrisonerProcessor.OUTCOME_EXECUTED])
	t.assert_false(king.alive, "il re e' giustiziato")
	t.assert_eq(king.death_cause, "giustiziato")
	t.assert_eq(int(g_commander.counters.get("prigionieri", 0)), men, "il comandante vincitore conta i giustiziati")
	# l'anno dopo sale un successore (o la fazione si estingue): la dinastia lo tratta come ogni morte
	DynastyProcessor.process_year(s)
	t.assert_true(s.leader_of(W.A) != king)


# --- decisioni del giocatore -----------------------------------------------------------------------------------------


func test_il_giocatore_vincitore_decide(t: TestContext) -> void:
	for choice in ["libera", "riscatto", "giustizia"]:
		var w := _lost_attack()
		var s: GameState = w["stato"]
		s.faction(W.G).is_player = true
		s.faction(W.A).treasury = 0
		WarProcessor.field_battles(s)
		PrisonerProcessor.process_year(s)
		t.assert_eq(PrisonerProcessor.decisions_for(s, W.G).size(), 1, "%s: in attesa del giocatore" % choice)
		var id := int(s.prisoners[0]["id"])
		var losses := PrisonerProcessor.men_of(s.prisoners[0])
		var a_men := 0
		for a in s.armies_of(W.A):
			a_men += a.men_total()
		var r := GameCommands.decide_prisoners(s, W.G, id, choice)
		t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
		t.assert_true(s.prisoners.is_empty(), "%s: deciso" % choice)
		var after := 0
		for a in s.armies_of(W.A):
			after += a.men_total()
		if choice == "libera":
			t.assert_eq(r["esito"], PrisonerProcessor.OUTCOME_RELEASED)
			t.assert_eq(after, a_men + losses, "gli uomini tornano")
		elif choice == "riscatto":
			t.assert_eq(r["esito"], PrisonerProcessor.OUTCOME_REFUSED, "ALPHA senza fiorini rifiuta")
			t.assert_eq(after, a_men)
		else:
			t.assert_eq(r["esito"], PrisonerProcessor.OUTCOME_EXECUTED)
			t.assert_eq(after, a_men)
	var w2 := _lost_attack()
	var s2: GameState = w2["stato"]
	s2.faction(W.G).is_player = true
	WarProcessor.field_battles(s2)
	PrisonerProcessor.process_year(s2)
	var wrong := GameCommands.decide_prisoners(s2, W.A, int(s2.prisoners[0]["id"]), "libera")
	t.assert_false(bool(wrong["ok"]), "decide solo il vincitore")
	t.assert_false(bool(GameCommands.decide_prisoners(s2, W.G, int(s2.prisoners[0]["id"]), "boh")["ok"]))


func test_al_giocatore_sconfitto_si_chiede_il_riscatto(t: TestContext) -> void:
	for pay in [true, false]:
		var w := _lost_attack()
		var s: GameState = w["stato"]
		s.faction(W.A).is_player = true
		s.leader_of(W.G).dread = 0
		s.faction(W.A).treasury = 0
		WarProcessor.field_battles(s)
		PrisonerProcessor.process_year(s)
		var e := s.prisoners[0]
		t.assert_eq(e["stato"], PrisonerProcessor.STATE_RANSOM)
		t.assert_eq(PrisonerProcessor.decisions_for(s, W.A).size(), 1)
		t.assert_eq(PrisonerProcessor.decisions_for(s, W.G).size(), 0)
		var price := int(e["prezzo"])
		t.assert_true(price > 0)
		var r := GameCommands.answer_ransom(s, W.A, int(e["id"]), pay)
		t.assert_true(bool(r["ok"]))
		t.assert_eq(r["esito"], PrisonerProcessor.OUTCOME_RANSOMED if pay else PrisonerProcessor.OUTCOME_REFUSED)
		t.assert_eq(s.faction(W.A).treasury, -price if pay else 0, "si paga anche a debito")


func test_le_decisioni_lasciate_in_sospeso_si_prendono_da_sole(t: TestContext) -> void:
	var w := _lost_attack()
	var s: GameState = w["stato"]
	s.faction(W.G).is_player = true
	s.faction(W.A).treasury = 100000
	WarProcessor.field_battles(s)
	PrisonerProcessor.process_year(s)
	PrisonerProcessor.settle_overdue(s)
	t.assert_eq(s.prisoners.size(), 1, "nello stesso anno resta in attesa")
	s.year += 1
	PrisonerProcessor.settle_overdue(s)
	t.assert_true(s.prisoners.is_empty(), "l'anno dopo il riscatto si chiede da solo")
	t.assert_true(_outcomes(s).has(PrisonerProcessor.OUTCOME_RANSOMED), "ALPHA ricca paga")


# --- partita e salvataggi -------------------------------------------------------------------------------------------


func test_nel_fine_anno(t: TestContext) -> void:
	var w := _lost_attack()
	var s: GameState = w["stato"]
	s.faction(W.G).is_player = true
	TurnProcessor.end_year(s)
	t.assert_eq(PrisonerProcessor.decisions_for(s, W.G).size(), 1, "dopo il fine anno il giocatore decide")
	t.assert_true(_outcomes(s).has(PrisonerProcessor.OUTCOME_TAKEN))
	W.check_state(t, s, "con i prigionieri")


func test_andata_e_ritorno_con_i_prigionieri(t: TestContext) -> void:
	var w := _lost_attack()
	var s: GameState = w["stato"]
	w["esercito"].from_region = ""
	s.province(W.NORD1).owner = W.D
	s.faction(W.G).is_player = true
	WarProcessor.field_battles(s)
	PrisonerProcessor.process_year(s)
	var text := SaveGame.to_json(s)
	var back := _restore(JSON.parse_string(text))
	t.assert_eq(SaveGame.to_json(back), text, "stato identico attraverso il testo JSON")
	t.assert_eq(back.prisoners.size(), 1)
	t.assert_eq(back.next_prisoner_id, s.next_prisoner_id)
	t.assert_true(PrisonerProcessor.is_captive(back.leader_of(W.A)), "il re resta prigioniero")
	var r := GameCommands.decide_prisoners(back, W.G, int(back.prisoners[0]["id"]), "libera")
	t.assert_true(bool(r["ok"]))
	t.assert_false(PrisonerProcessor.is_captive(back.leader_of(W.A)))
