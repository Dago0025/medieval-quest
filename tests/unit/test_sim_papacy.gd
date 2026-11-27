extends RefCounted
## Test del Papato e delle scomuniche (fase 5c): parametri (PapacyRules, data/regole/papato.cfg), avvertimenti,
## tregua papale, scomunica e i suoi effetti, revoca, riemersione del Papato, doni papali, salvataggi.
## Mondo di prova: vedi papacy_world.gd (ALPHA 3 province, GAMMA 1, DELTA 1, il Papato a ROMA, BETA musulmana).
## I calcoli a mano usano i parametri predefiniti (uguali a papato.cfg).

const W := preload("res://tests/unit/papacy_world.gd")
const RULES_FILE := "res://data/regole/papato.cfg"


func _warning_key(a: String, b: String) -> String:
	return GameState.warning_key(a, b)


func _move(s: GameState, faction_id: String, from_region: String, to_region: String) -> Army:
	var army := W.land_army(s, faction_id, from_region)
	var r := GameCommands.order_move(s, faction_id, army.id, PackedStringArray([to_region]))
	assert(bool(r["ok"]))
	return army


func _restore(data: Dictionary) -> GameState:
	var campaign := StartposLoader.load_file(W.STARTPOS)
	var units := UnitProdLoader.load_file(W.UNITS)
	var buildings := BuildingProdLoader.load_file(W.BUILDINGS)
	var r := SaveGame.from_dict(data, campaign, units, buildings, W.quiet_rules())
	return r["stato"]


## Il Papato distrutto: niente eserciti, provincia ribelle che era sua.
func _destroy_papacy(s: GameState) -> void:
	W.remove_armies(s, W.P)
	var roma := s.province(W.ROMA)
	roma.owner = GameState.REBEL
	roma.loyalty_owner = GameState.REBEL
	roma.former_owner = W.P
	roma.loyalty = 100
	s.faction(W.P).alive = false


# --- parametri ---------------------------------------------------------------------------------------


func test_i_valori_predefiniti_sono_uguali_al_file(t: TestContext) -> void:
	var from_file := PapacyRules.load_file(RULES_FILE)
	t.assert_eq(from_file.errors, PackedStringArray(), "papato.cfg si legge senza errori")
	t.assert_eq(from_file.to_dict(), PapacyRules.new().to_dict(), "il file e i valori predefiniti devono coincidere")
	var rules := Rules.load_file()
	t.assert_eq(rules.errors, PackedStringArray(), "tutti i file delle regole")
	t.assert_eq(rules.papacy.to_dict(), PapacyRules.new().to_dict(), "Rules espone il Papato")
	t.assert_eq(rules.to_dict(), Rules.new().to_dict(), "Rules.to_dict comprende il Papato")
	t.assert_eq(Rules.new().to_dict()["papacy"], PapacyRules.new().to_dict())


func test_i_valori_della_specifica(t: TestContext) -> void:
	var r := PapacyRules.new()
	t.assert_eq(r.warning_years, 2)
	t.assert_eq(r.papal_truce_years, 10)
	t.assert_eq(r.excommunication_influence, 2)
	t.assert_eq(r.excommunication_loyalty, 15)
	t.assert_true(r.elective)
	t.assert_eq(r.pope_age_min, 50)
	t.assert_eq(r.pope_age_max, 70)
	t.assert_eq(r.reemerge_years_min, 15)
	t.assert_eq(r.reemerge_years_max, 30)
	t.assert_eq(r.reemerge_stacks, 8)
	t.assert_eq(r.initial_stacks, 4)
	t.assert_eq(r.initial_zeal, 80)
	t.assert_eq(r.zeal_decay_year, 5)
	t.assert_eq(r.zeal_decay_no_target, 10)
	t.assert_eq(r.recruit_stacks, 4)
	t.assert_eq(r.recruit_zeal_threshold, 40)
	t.assert_eq(r.recruit_zeal_per_stack, 15)
	t.assert_eq(r.max_stacks, 32)
	t.assert_eq(r.zeal_losses, 40)
	t.assert_eq(r.zeal_desertion, 30)
	t.assert_eq(r.zeal_dissolve, 20)
	t.assert_eq(r.order_stacks, 2)
	t.assert_eq(r.crusade_success_influence, 1)
	t.assert_eq(r.crusade_failure_influence, 1)
	t.assert_eq(r.jihad_success_influence, 1)
	t.assert_eq(r.jihad_failure_influence, 2)
	t.assert_eq(r.gift_min_religious, 3)
	t.assert_eq(r.gift_chance, 0.05)
	t.assert_eq(r.gift_amount, 1000)


func test_la_riemersione_cresce_ed_e_limitata(t: TestContext) -> void:
	var r := PapacyRules.new()
	t.assert_eq(r.reemerge_army_stacks(0, 16), 8)
	t.assert_eq(r.reemerge_army_stacks(1, 16), 10)
	t.assert_eq(r.reemerge_army_stacks(3, 16), 14)
	t.assert_eq(r.reemerge_army_stacks(50, 16), 16, "limite del motore")
	t.assert_eq(r.reemerge_army_stacks(2, 5), 5)


func test_la_ricomparsa_cade_a_caso_tra_15_e_30_anni(t: TestContext) -> void:
	var r := PapacyRules.new()
	t.assert_eq(r.reemerge_chance(1), 0.0)
	t.assert_eq(r.reemerge_chance(14), 0.0)
	t.assert_eq(r.reemerge_chance(15), 1.0 / 16.0)
	t.assert_eq(r.reemerge_chance(29), 0.5)
	t.assert_eq(r.reemerge_chance(30), 1.0)
	t.assert_eq(r.reemerge_chance(45), 1.0, "senza luogo si riprova ogni anno")
	# l'anno della ricomparsa e' uniforme tra 15 e 30: ogni anno 1/16
	var still := 1.0
	for year in range(15, 31):
		var p := still * r.reemerge_chance(year)
		t.assert_true(absf(p - 1.0 / 16.0) < 0.000001, "anno %d: %f" % [year, p])
		still -= p
	t.assert_true(absf(still) < 0.000001, "entro 30 anni ricompare di sicuro")


func test_le_pile_raccolte_per_zelo(t: TestContext) -> void:
	var r := PapacyRules.new()
	t.assert_eq(r.zeal_recruit_stacks(40), 0, "fino alla soglia niente")
	t.assert_eq(r.zeal_recruit_stacks(41), 1)
	t.assert_eq(r.zeal_recruit_stacks(55), 1)
	t.assert_eq(r.zeal_recruit_stacks(56), 2)
	t.assert_eq(r.zeal_recruit_stacks(70), 2)
	t.assert_eq(r.zeal_recruit_stacks(85), 3)
	t.assert_eq(r.zeal_recruit_stacks(100), 4, "al massimo 4")


func test_un_file_con_valori_incoerenti_torna_ai_predefiniti(t: TestContext) -> void:
	var r := PapacyRules.new()
	r.zeal_dissolve = 50
	r.warning_years = 0
	r.gift_chance = 2.0
	r._check_consistency()
	t.assert_eq(r.errors.size(), 3)
	t.assert_eq(r.zeal_dissolve, 20)
	t.assert_eq(r.warning_years, 2)
	t.assert_eq(r.gift_chance, 0.05)
	var missing := PapacyRules.load_file("res://data/regole/non_esiste.cfg")
	t.assert_eq(missing.errors.size(), 1, "file mancante: errore e predefiniti")
	t.assert_eq(missing.to_dict(), PapacyRules.new().to_dict())


func test_il_mondo_di_prova(t: TestContext) -> void:
	var s := W.world()
	t.assert_eq(s.setup_errors, PackedStringArray(), "dati di prova senza anomalie")
	t.assert_true(s.faction(W.P) != null and s.faction(W.P).alive)
	t.assert_true(s.leader_of(W.P) != null, "il Papa c'e'")
	for f_id in [W.A, W.B, W.G, W.D, W.P]:
		t.assert_true(s.leader_of(f_id) != null, "capo di %s" % f_id)
	t.assert_true(PapacyProcessor.is_catholic(s, W.A))
	t.assert_true(PapacyProcessor.is_catholic(s, W.P))
	t.assert_false(PapacyProcessor.is_catholic(s, W.B))
	t.assert_eq(s.provinces_of(W.A).size(), 3)
	t.assert_true(s.province(W.NORD1).level_of("CHAPTER_HOUSE") >= 1)
	W.check_state(t, s, "inizio")


# --- avvertimenti ------------------------------------------------------------------------------------------


func test_la_dichiarazione_della_piu_grande_cattolica_porta_un_avvertimento(t: TestContext) -> void:
	var s := W.world()
	_move(s, W.A, W.NORD1, W.EST)
	TurnProcessor.end_year(s)
	var warnings := W.events_of(s, GameState.EV_PAPAL_WARNING)
	t.assert_eq(warnings.size(), 1, "un avvertimento")
	t.assert_eq(warnings[0]["fazione"], W.A)
	t.assert_eq(warnings[0]["contro"], W.G)
	t.assert_eq(warnings[0]["fino_al"], 1002)
	t.assert_true(str(warnings[0]["testo"]) != "")
	var stored := s.papal_warning(W.A, W.G)
	t.assert_eq(stored["anno"], 1000)
	t.assert_eq(stored["scadenza"], 1002)
	t.assert_true(s.at_war(W.A, W.G), "la guerra e' dichiarata")
	t.assert_false(s.faction(W.A).excommunicated, "la dichiarazione non e' un attacco durante l'avvertimento")
	t.assert_eq(W.events_of(s, GameState.EV_EXCOMMUNICATION).size(), 0)
	W.check_state(t, s, "dopo l'avvertimento")


func test_altri_attacchi_dello_stesso_anno_non_scomunicano(t: TestContext) -> void:
	var s := W.world()
	_move(s, W.A, W.NORD1, W.EST)
	var second := s.create_army(W.A, W.NORD1, false)
	second.stacks.append(UnitStack.new("Spearmen", 50, 0))
	GameCommands.order_move(s, W.A, second.id, PackedStringArray([W.EST]))
	TurnProcessor.end_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_WARNING).size(), 1, "un solo avvertimento")
	t.assert_false(s.faction(W.A).excommunicated)


func test_la_piu_piccola_non_viene_ammonita(t: TestContext) -> void:
	var s := W.world()
	_move(s, W.G, W.EST, W.NORD1)
	TurnProcessor.end_year(s)
	t.assert_true(s.at_war(W.A, W.G))
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_WARNING).size(), 0, "GAMMA (1 provincia) attacca ALPHA (3)")
	t.assert_true(s.papal_warnings.is_empty())


func test_a_parita_di_province_nessun_avvertimento(t: TestContext) -> void:
	var s := W.world()
	_move(s, W.D, W.DELTA1, W.EST)
	TurnProcessor.end_year(s)
	t.assert_true(s.at_war(W.D, W.G))
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_WARNING).size(), 0)


func test_nessun_avvertimento_contro_i_non_cattolici(t: TestContext) -> void:
	var s := W.world()
	_move(s, W.A, W.NORD2, W.SUD1)
	TurnProcessor.end_year(s)
	t.assert_true(s.at_war(W.A, W.B))
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_WARNING).size(), 0)
	t.assert_false(s.faction(W.A).excommunicated)


func test_senza_il_papato_vivo_nessun_avvertimento(t: TestContext) -> void:
	var s := W.world()
	s.faction(W.P).alive = false
	_move(s, W.A, W.NORD1, W.EST)
	TurnProcessor.end_year(s)
	t.assert_true(s.at_war(W.A, W.G))
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_WARNING).size(), 0)
	t.assert_true(s.papal_warnings.is_empty())


func test_il_mondo_senza_papato_non_ha_avvertimenti(t: TestContext) -> void:
	# un mondo senza la fazione del Papato (come le altre fixture) non cambia comportamento
	var s := W.world()
	s.factions.erase(s.faction(W.P))
	s._faction_by_id.erase(W.P)
	t.assert_eq(PapacyProcessor.on_attack(s, W.A, W.G, W.EST), "")
	PapacyProcessor.process_year(s)
	t.assert_true(s.events.is_empty())


func test_gli_avvertimenti_non_si_ripetono(t: TestContext) -> void:
	var s := W.world()
	var before := {"anno": 1000, "scadenza": 1002}
	s.papal_warnings[_warning_key(W.A, W.G)] = before
	t.assert_eq(PapacyProcessor.on_attack(s, W.A, W.G, W.EST), "", "stesso anno: niente di nuovo")
	t.assert_eq(s.papal_warning(W.A, W.G), before)
	t.assert_false(s.faction(W.A).excommunicated)


# --- scomunica per l'attacco -----------------------------------------------------------------------------------


func test_attaccare_durante_l_avvertimento_porta_alla_scomunica(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.G)
	s.papal_warnings[_warning_key(W.A, W.G)] = {"anno": 1000, "scadenza": 1002}
	s.year = 1001
	var fresh := s.create_army(W.A, W.NORD1, false)
	fresh.stacks.append(UnitStack.new("Spearmen", 50, 0))
	GameCommands.order_move(s, W.A, fresh.id, PackedStringArray([W.EST]))
	TurnProcessor.end_year(s)
	t.assert_true(s.faction(W.A).excommunicated, "ALPHA e' scomunicata")
	var events := W.events_of(s, GameState.EV_EXCOMMUNICATION)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["fazione"], W.A)
	t.assert_eq(events[0]["motivo"], PapacyProcessor.REASON_WARNING)
	t.assert_eq(events[0]["regione"], W.EST)
	t.assert_true(s.papal_warnings.is_empty(), "l'avvertimento e' consumato")
	t.assert_eq(s.faction(W.A).excommunication_year, 1001)
	W.check_state(t, s, "dopo la scomunica")


func test_attaccare_il_papato_scomunica_subito(t: TestContext) -> void:
	var s := W.world()
	W.land_army(s, W.P, W.ROMA).stacks[0].men = 5000   # il Papato regge l'attacco
	_move(s, W.A, W.NORD1, W.ROMA)
	TurnProcessor.end_year(s)
	t.assert_true(s.faction(W.A).excommunicated)
	var events := W.events_of(s, GameState.EV_EXCOMMUNICATION)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["motivo"], PapacyProcessor.REASON_PAPACY)
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_WARNING).size(), 0, "nessun avvertimento per il Papato")


func test_chi_non_va_scomunicato(t: TestContext) -> void:
	var s := W.world()
	t.assert_eq(PapacyProcessor.on_attack(s, W.B, W.P, W.ROMA), "", "i musulmani non sono scomunicabili")
	t.assert_eq(PapacyProcessor.on_attack(s, W.P, W.A, W.NORD1), "", "il Papato non scomunica se stesso")
	t.assert_eq(PapacyProcessor.on_attack(s, W.A, GameState.REBEL, W.RIBELLE), "", "i ribelli non c'entrano")
	t.assert_false(PapacyProcessor.excommunicate(s, W.B, "x"), "BETA non e' cattolica")
	t.assert_false(PapacyProcessor.excommunicate(s, W.P, "x"), "il Papa non si scomunica")
	t.assert_false(PapacyProcessor.excommunicate(s, GameState.REBEL, "x"))
	t.assert_false(PapacyProcessor.excommunicate(s, "FN_NESSUNA", "x"))
	# attaccare uno scomunicato non e' sgradito al Papa
	PapacyProcessor.excommunicate(s, W.G, "attacco_al_papato")
	t.assert_eq(PapacyProcessor.on_attack(s, W.A, W.G, W.EST), "", "nessun avvertimento contro uno scomunicato")
	t.assert_true(s.papal_warnings.is_empty())


# --- tregua papale -------------------------------------------------------------------------------------------------


func test_rispettato_il_termine_il_papa_impone_la_tregua(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.G)
	s.papal_warnings[_warning_key(W.A, W.G)] = {"anno": 1000, "scadenza": 1002}
	s.year = 1001
	TurnProcessor.end_year(s)
	t.assert_true(s.at_war(W.A, W.G), "1001: l'avvertimento dura ancora")
	t.assert_false(s.papal_warning(W.A, W.G).is_empty())
	TurnProcessor.end_year(s)    # 1002: scade senza attacchi
	t.assert_eq(s.relation(W.A, W.G), GameState.REL_TRUCE, "tregua papale")
	t.assert_eq(s.truce_until(W.A, W.G), 1013, "10 anni interi dopo l'anno della scadenza")
	t.assert_true(s.papal_warnings.is_empty())
	var truces := W.events_of(s, GameState.EV_PAPAL_TRUCE)
	t.assert_eq(truces.size(), 1)
	t.assert_eq(truces[0]["fazione"], W.A)
	t.assert_eq(truces[0]["con"], W.G)
	t.assert_eq(truces[0]["fino_al"], 1013)
	t.assert_false(s.faction(W.A).excommunicated)
	W.check_state(t, s, "dopo la tregua")


func test_un_avvertimento_senza_piu_senso_cade_senza_tregua(t: TestContext) -> void:
	var s := W.world()
	PapacyProcessor.excommunicate(s, W.A, "attacco_al_papato")
	# il colpevole e' scomunicato (anche se in guerra)
	s.declare_war(W.A, W.G)
	s.papal_warnings[_warning_key(W.A, W.G)] = {"anno": 1000, "scadenza": 1005}
	# non sono piu' in guerra
	s.papal_warnings[_warning_key(W.D, W.G)] = {"anno": 1000, "scadenza": 1005}
	# chiave illeggibile
	s.papal_warnings["senza_separatore"] = {"anno": 1, "scadenza": 2}
	PapacyProcessor.process_year(s)
	t.assert_true(s.papal_warnings.is_empty(), "tutti caduti")
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_TRUCE).size(), 0)
	t.assert_true(s.at_war(W.A, W.G), "e la guerra resta com'e'")


# --- effetti della scomunica ------------------------------------------------------------------------------------------


func test_gli_effetti_della_scomunica(t: TestContext) -> void:
	var s := W.world()
	var leader := W.set_influence(s, W.A, 5)
	s.form_alliance(W.A, W.G)
	s.form_alliance(W.A, W.B)
	s.papal_warnings[_warning_key(W.A, W.D)] = {"anno": 1000, "scadenza": 1002}
	t.assert_true(bool(GameCommands.queue_unit(s, W.A, W.NORD1, "Crusade")["ok"]))
	t.assert_eq(s.faction(W.A).treasury, 4000, "mille denari pagati")
	var army := W.add_crusade(s, W.A, W.NORD2)
	t.assert_true(PapacyProcessor.excommunicate(s, W.A, PapacyProcessor.REASON_PAPACY, W.ROMA))
	var f := s.faction(W.A)
	t.assert_true(f.excommunicated)
	t.assert_eq(f.excommunication_year, 1000)
	t.assert_eq(f.excommunication_leader, leader.id)
	t.assert_eq(leader.influence, 3, "influenza -2")
	t.assert_false(s.is_allied(W.A, W.G), "l'alleanza con una cattolica cade")
	t.assert_true(s.is_allied(W.A, W.B), "quella con una musulmana resta")
	t.assert_true(s.papal_warnings.is_empty(), "gli avvertimenti a suo carico cadono")
	t.assert_true(s.province(W.NORD1).unit_queue.is_empty(), "la crociata in coda e' annullata")
	t.assert_eq(f.treasury, 5000, "e rimborsata")
	t.assert_true(army.crusade.is_empty(), "la crociata attiva perde l'appoggio del Papa")
	t.assert_true(s.army(army.id) != null, "ma l'esercito resta")
	var ex := W.events_of(s, GameState.EV_EXCOMMUNICATION)
	t.assert_eq(ex.size(), 1)
	t.assert_eq(ex[0]["motivo"], PapacyProcessor.REASON_PAPACY)
	t.assert_eq(ex[0]["influenza_persa"], 2)
	t.assert_eq(ex[0]["alleanze_rotte"], [W.G])
	t.assert_eq(ex[0]["rimborso"], 1000)
	var broken := W.events_of(s, GameState.EV_ALLIANCE_BROKEN)
	t.assert_eq(broken.size(), 1)
	t.assert_eq(broken[0]["con"], W.G)
	t.assert_eq(broken[0]["motivo"], "scomunica")
	var failed := W.events_of(s, GameState.EV_CRUSADE_FAILED)
	t.assert_eq(failed.size(), 1)
	t.assert_eq(failed[0]["motivo"], "scomunica")
	t.assert_eq(failed[0]["influenza"], 0)
	t.assert_false(PapacyProcessor.excommunicate(s, W.A, "x"), "gia' scomunicata")
	t.assert_eq(W.events_of(s, GameState.EV_EXCOMMUNICATION).size(), 1)
	W.check_state(t, s, "dopo gli effetti")


func test_l_influenza_non_scende_sotto_zero(t: TestContext) -> void:
	var s := W.world()
	var leader := W.set_influence(s, W.G, 1)
	PapacyProcessor.excommunicate(s, W.G, "x")
	t.assert_eq(leader.influence, 0)
	t.assert_eq(W.events_of(s, GameState.EV_EXCOMMUNICATION)[0]["influenza_persa"], 1)


func test_la_scomunica_abbassa_la_lealta_delle_province(t: TestContext) -> void:
	var s := W.world()
	var p := s.province(W.NORD1)
	var before := ProvinceProcessor.loyalty_terms(s, p)
	t.assert_true(before.has("scomunica"))
	t.assert_eq(before["scomunica"], 0)
	PapacyProcessor.excommunicate(s, W.A, "x")
	var after := ProvinceProcessor.loyalty_terms(s, p)
	t.assert_eq(after["scomunica"], -15, "100% cattolici: -15")
	t.assert_eq(after["somma"], int(before["somma"]) - 15)
	p.religions = ProvinceState.normalize_religions({"CATHOLIC": 60.0, "PAGAN": 40.0})
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, p)["scomunica"], -9, "60% cattolici: -9")
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, s.province(W.EST))["scomunica"], 0, "le province di altri no")
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, s.province(W.RIBELLE))["scomunica"], 0, "nemmeno quelle dei ribelli")
	PapacyProcessor.lift_excommunication(s, W.A, "morte_del_papa")
	t.assert_eq(ProvinceProcessor.loyalty_terms(s, p)["scomunica"], 0, "revocata")


func test_una_fazione_scomunicata_non_bandisce_crociate(t: TestContext) -> void:
	var s := W.world()
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")["ok"]))
	PapacyProcessor.excommunicate(s, W.A, "x")
	var check := GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")
	t.assert_false(bool(check["ok"]))
	t.assert_true(str(check["errore"]).find("scomunicata") >= 0, str(check["errore"]))


# --- revoca -----------------------------------------------------------------------------------------------------------------


func test_alla_morte_del_papa_cadono_tutte_le_scomuniche(t: TestContext) -> void:
	var s := W.world()
	TurnProcessor.end_year(s)
	var pope := s.leader_of(W.P)
	t.assert_eq(s.papal_leader, pope.id, "il Papa e' registrato")
	PapacyProcessor.excommunicate(s, W.A, "x")
	PapacyProcessor.excommunicate(s, W.G, "x")
	DynastyProcessor.kill(s, pope, s.year + 1, "vecchiaia", false)
	TurnProcessor.end_year(s)
	t.assert_false(s.faction(W.A).excommunicated)
	t.assert_false(s.faction(W.G).excommunicated)
	var lifted := W.events_of(s, GameState.EV_EXCOMMUNICATION_LIFTED)
	t.assert_eq(lifted.size(), 2)
	t.assert_eq(lifted[0]["motivo"], "morte_del_papa")
	t.assert_eq(lifted[0]["fazione"], W.A)
	t.assert_eq(lifted[1]["fazione"], W.G)
	t.assert_true(s.papal_leader != pope.id, "un nuovo Papa")
	t.assert_eq(s.faction(W.A).excommunication_year, 0)
	W.check_state(t, s, "dopo la morte del Papa")


func test_alla_morte_del_capo_scomunicato_cade_la_sua_scomunica(t: TestContext) -> void:
	var s := W.world()
	TurnProcessor.end_year(s)
	PapacyProcessor.excommunicate(s, W.A, "x")
	PapacyProcessor.excommunicate(s, W.G, "x")
	var old := s.leader_of(W.A)
	DynastyProcessor.kill(s, old, s.year + 1, "vecchiaia", false)
	TurnProcessor.end_year(s)
	t.assert_false(s.faction(W.A).excommunicated, "il nuovo capo di ALPHA e' libero")
	t.assert_true(s.faction(W.G).excommunicated, "GAMMA no: il suo capo e il Papa sono gli stessi")
	var lifted := W.events_of(s, GameState.EV_EXCOMMUNICATION_LIFTED)
	t.assert_eq(lifted.size(), 1)
	t.assert_eq(lifted[0]["motivo"], "morte_del_capo")
	t.assert_true(s.leader_of(W.A) != null and s.leader_of(W.A).id != old.id)


func test_se_il_papato_e_distrutto_le_scomuniche_cadono(t: TestContext) -> void:
	var s := W.world()
	TurnProcessor.end_year(s)
	PapacyProcessor.excommunicate(s, W.G, "x")
	s.faction(W.P).alive = false
	TurnProcessor.end_year(s)
	t.assert_false(s.faction(W.G).excommunicated)
	t.assert_eq(W.events_of(s, GameState.EV_EXCOMMUNICATION_LIFTED)[0]["motivo"], "papato_distrutto")
	t.assert_eq(s.papal_leader, 0)
	# senza Papa nessuno viene ammonito
	t.assert_eq(PapacyProcessor.on_attack(s, W.A, W.D, W.DELTA1), "")


func test_una_fazione_distrutta_non_resta_scomunicata(t: TestContext) -> void:
	var s := W.world()
	PapacyProcessor.excommunicate(s, W.D, "x")
	s.faction(W.D).alive = false
	TurnProcessor.end_year(s)
	t.assert_false(s.faction(W.D).excommunicated)
	t.assert_eq(W.events_of(s, GameState.EV_EXCOMMUNICATION_LIFTED)[0]["motivo"], "fazione_distrutta")


func test_la_scomunica_resta_finche_nessuno_muore(t: TestContext) -> void:
	var s := W.world()
	PapacyProcessor.excommunicate(s, W.A, "x")
	for i in 5:
		TurnProcessor.end_year(s)
	t.assert_true(s.faction(W.A).excommunicated)
	t.assert_eq(W.events_of(s, GameState.EV_EXCOMMUNICATION_LIFTED).size(), 0)
	W.check_state(t, s, "dopo cinque anni")


# --- riemersione del Papato -----------------------------------------------------------------------------------------------------


func test_il_papato_distrutto_riemerge_con_un_esercito_che_cresce(t: TestContext) -> void:
	var s := W.world()
	s.rules.papacy.reemerge_years_min = 3
	s.rules.papacy.reemerge_years_max = 3
	_destroy_papacy(s)
	for i in 2:
		TurnProcessor.end_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_PAPACY_REEMERGED).size(), 0, "non ancora")
	t.assert_false(s.faction(W.P).alive)
	t.assert_eq(s.papacy_dead_years, 2)
	TurnProcessor.end_year(s)
	var events := W.events_of(s, GameState.EV_PAPACY_REEMERGED)
	t.assert_eq(events.size(), 1, "riemerge al terzo anno")
	t.assert_eq(events[0]["provincia"], W.ROMA)
	t.assert_eq(events[0]["pile"], 8)
	t.assert_eq(events[0]["riemersioni"], 1)
	t.assert_true(s.faction(W.P).alive)
	t.assert_eq(s.province(W.ROMA).owner, W.P)
	t.assert_eq(s.province(W.ROMA).former_owner, "")
	t.assert_eq(s.papacy_reemergences, 1)
	t.assert_eq(s.papacy_dead_years, 0)
	t.assert_true(s.leader_of(W.P) != null, "un nuovo Papa")
	var army := s.army(int(events[0]["esercito"]))
	t.assert_true(army != null and army.faction == W.P, "l'esercito del Papato")
	t.assert_eq(army.stacks.size(), 8)
	var pope := s.leader_of(W.P)
	t.assert_true(pope.age(s.year) >= 50 and pope.age(s.year) <= 71, "un Papa anziano")
	# la seconda volta e' piu' grande
	_destroy_papacy(s)
	for i in 3:
		TurnProcessor.end_year(s)
	var second := W.events_of(s, GameState.EV_PAPACY_REEMERGED)
	t.assert_eq(second.size(), 1)
	t.assert_eq(second[0]["pile"], 10, "8 + 2")
	t.assert_eq(second[0]["riemersioni"], 2)
	t.assert_eq(s.army(int(second[0]["esercito"])).stacks.size(), 10)
	W.check_state(t, s, "dopo le riemersioni")


func test_nelle_sue_terre_in_mano_ad_altri_il_papato_insorge(t: TestContext) -> void:
	# ADR-072: gli Stati Pontifici sono di un'altra fazione: l'armata compare li' come lealisti e la deve conquistare
	var s := W.world()
	s.rules.papacy.reemerge_years_min = 2
	s.rules.papacy.reemerge_years_max = 2
	_destroy_papacy(s)
	var roma := s.province(W.ROMA)
	roma.owner = W.G
	roma.loyalty_owner = W.G
	roma.former_owner = ""
	TurnProcessor.end_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_REBELLION).filter(func(e: Dictionary) -> bool: return bool(e.get("papato", false))).size(), 0, "non ancora")
	TurnProcessor.end_year(s)
	var uprising := W.events_of(s, GameState.EV_REBELLION).filter(func(e: Dictionary) -> bool: return bool(e.get("papato", false)))
	t.assert_eq(uprising.size(), 1, "al secondo anno insorge")
	t.assert_eq(uprising[0]["provincia"], W.ROMA)
	t.assert_eq(uprising[0]["fazione"], W.G)
	t.assert_eq(uprising[0]["lealisti_di"], W.P)
	t.assert_eq(uprising[0]["pile"], 8)
	var army := s.army(int(uprising[0]["esercito"]))
	t.assert_true(army != null and army.faction == GameState.REBEL and army.loyal_to == W.P, "ribelli lealisti del Papato")
	t.assert_eq(army.stacks.size(), 8)
	t.assert_false(s.faction(W.P).alive, "il Papato non c'e' ancora")
	t.assert_eq(s.papacy_reemergences, 1, "conta come riemersione")
	t.assert_eq(s.papacy_dead_years, 0, "l'attesa ricomincia")
	# nessuna difesa a Roma: i lealisti la prendono e il Papato riemerge con la loro armata
	for i in 3:
		if s.faction(W.P).alive:
			break
		TurnProcessor.end_year(s)
	t.assert_true(s.faction(W.P).alive, "il Papato riemerge dove hanno vinto i lealisti")
	t.assert_eq(s.province(W.ROMA).owner, W.P)
	var back := W.events_of(s, GameState.EV_PAPACY_REEMERGED)
	t.assert_eq(back.size(), 1)
	t.assert_eq(back[0]["uomini"], 0, "nessun uomo nuovo: e' l'armata dei lealisti")
	t.assert_eq(back[0]["riemersioni"], 1, "non conta due volte")
	t.assert_true(s.leader_of(W.P) != null, "un nuovo Papa")
	W.check_state(t, s, "dopo l'insurrezione")


func test_il_papato_ricompare_vicino_alle_sue_terre(t: TestContext) -> void:
	var s := W.world()
	s.rules.papacy.reemerge_years_min = 1
	s.rules.papacy.reemerge_years_max = 1
	_destroy_papacy(s)
	var roma := s.province(W.ROMA)
	roma.owner = W.G
	roma.former_owner = ""
	W.remove_armies(s, W.A)
	var nord1 := s.province(W.NORD1)
	nord1.owner = GameState.REBEL
	nord1.former_owner = W.A
	t.assert_eq(PapacyProcessor.papal_site(s), nord1, "la provincia ribelle confinante con Roma")
	TurnProcessor.end_year(s)
	var events := W.events_of(s, GameState.EV_PAPACY_REEMERGED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["provincia"], W.NORD1)
	t.assert_eq(s.province(W.NORD1).owner, W.P)


func test_il_papato_distrutto_non_guida_le_rivolte_comuni(t: TestContext) -> void:
	var s := W.world()
	_destroy_papacy(s)
	var roma := s.province(W.ROMA)
	roma.owner = W.G
	roma.counters[ProvinceProcessor.PRIOR_OWNER_KEY] = W.P
	t.assert_eq(ProvinceProcessor.loyalist_faction(s, roma), "", "ricompare solo con la sua regola")
	s.faction(W.P).alive = true
	t.assert_eq(ProvinceProcessor.loyalist_faction(s, roma), W.P, "vivo, i lealisti lo servono come gli altri")


# --- elezione del Papa (ADR-072) ------------------------------------------------------------------------------


func test_morto_il_papa_se_ne_elegge_un_altro(t: TestContext) -> void:
	var s := W.world()
	var pope := s.leader_of(W.P)
	DynastyProcessor.kill(s, pope, s.year, "vecchiaia", false)
	TurnProcessor.end_year(s)
	t.assert_true(s.faction(W.P).alive, "il Papato non si estingue")
	t.assert_eq(W.events_of(s, GameState.EV_FACTION_EXTINCT).size(), 0)
	var new_pope := s.leader_of(W.P)
	t.assert_true(new_pope != null and new_pope != pope, "un Papa nuovo")
	t.assert_true(new_pope.age(s.year) >= 50 and new_pope.age(s.year) <= 71, "eletto anziano: %d" % new_pope.age(s.year))
	t.assert_eq(new_pope.region, W.ROMA, "alla sede")
	var ev := W.events_of(s, GameState.EV_SUCCESSION).filter(func(e: Dictionary) -> bool: return str(e.get("fazione", "")) == W.P)
	t.assert_eq(ev.size(), 1)
	t.assert_true(bool(ev[0].get("elezione", false)))
	t.assert_eq(ev[0]["precedente"], pope.id)


func test_il_papa_non_ha_principi_ne_principesse(t: TestContext) -> void:
	var s := W.world()
	s.rules.dynasty.birth_chance = 1.0
	for c in s.characters:
		if c.role == Character.ROLE_LEADER:
			c.birth_year = s.year - 30
	for i in 3:
		TurnProcessor.end_year(s)
	for c in s.characters:
		if c.faction == W.P:
			t.assert_false(c.role == Character.ROLE_HEIR or c.role == Character.ROLE_PRINCE or c.role == Character.ROLE_PRINCESS, "%s del Papato" % c.role)
	var births := W.events_of(s, GameState.EV_BIRTH)
	t.assert_eq(births.filter(func(e: Dictionary) -> bool: return str(e.get("fazione", "")) == W.P).size(), 0, "nessuna nascita nel Papato")
	t.assert_true(births.filter(func(e: Dictionary) -> bool: return str(e.get("fazione", "")) == W.A).size() > 0, "le altre fazioni hanno figli come prima")


func test_senza_elezione_il_papa_e_un_re_qualsiasi(t: TestContext) -> void:
	var s := W.world()
	s.rules.papacy.elective = false
	DynastyProcessor.kill(s, s.leader_of(W.P), s.year, "vecchiaia", false)
	TurnProcessor.end_year(s)
	t.assert_false(s.faction(W.P).alive, "nessun erede: si estingue come prima")


func test_il_papato_vivo_azzera_il_conto(t: TestContext) -> void:
	var s := W.world()
	s.papacy_dead_years = 7
	TurnProcessor.end_year(s)
	t.assert_eq(s.papacy_dead_years, 0)


# --- doni papali -------------------------------------------------------------------------------------------------------------------


func test_i_doni_papali(t: TestContext) -> void:
	var s := W.world()
	s.rules.papacy.gift_chance = 1.0
	for i in 3:
		W.add_agent(s, W.A, W.NORD1, "BISHOP")
	W.add_agent(s, W.G, W.EST, "BISHOP")
	W.add_agent(s, W.G, W.EST, "PRIEST")
	W.add_agent(s, W.G, W.EST, "PRIEST")
	W.add_agent(s, W.D, W.DELTA1, "BISHOP")
	W.add_agent(s, W.D, W.DELTA1, "BISHOP")
	for i in 3:
		W.add_agent(s, W.B, W.SUD1, "MULLAH")
	var alpha := s.faction(W.A).treasury
	var gamma := s.faction(W.G).treasury
	var delta := s.faction(W.D).treasury
	var beta := s.faction(W.B).treasury
	PapacyProcessor.process_year(s)
	var gifts := W.events_of(s, GameState.EV_PAPAL_GIFT)
	t.assert_eq(gifts.size(), 2, "ALPHA (3 vescovi) e GAMMA (vescovo e 2 sacerdoti)")
	t.assert_eq(gifts[0]["fazione"], W.A)
	t.assert_eq(gifts[0]["importo"], 1000)
	t.assert_eq(gifts[0]["religiosi"], 3)
	t.assert_eq(gifts[1]["fazione"], W.G)
	t.assert_eq(s.faction(W.A).treasury, alpha + 1000)
	t.assert_eq(s.faction(W.G).treasury, gamma + 1000)
	t.assert_eq(s.faction(W.D).treasury, delta, "DELTA ne ha solo 2")
	t.assert_eq(s.faction(W.B).treasury, beta, "i mullah non contano e BETA non e' cattolica")


func test_niente_doni_agli_scomunicati_ne_senza_papato_ne_senza_probabilita(t: TestContext) -> void:
	var s := W.world()
	s.rules.papacy.gift_chance = 1.0
	for i in 3:
		W.add_agent(s, W.A, W.NORD1, "BISHOP")
	PapacyProcessor.excommunicate(s, W.A, "x")
	s.events.clear()
	PapacyProcessor.process_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_GIFT).size(), 0, "scomunicata")
	PapacyProcessor.lift_excommunication(s, W.A, "morte_del_papa")
	s.faction(W.P).alive = false
	s.events.clear()
	PapacyProcessor.process_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_GIFT).size(), 0, "Papato distrutto")
	s.faction(W.P).alive = true
	s.rules.papacy.gift_chance = 0.0
	PapacyProcessor.process_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_GIFT).size(), 0, "probabilita' 0")
	s.rules.papacy.gift_chance = 1.0
	PapacyProcessor.process_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_GIFT).size(), 1, "e adesso si")


func test_i_doni_usano_il_generatore_dello_stato(t: TestContext) -> void:
	var s := W.world()
	s.rules.papacy.gift_chance = 0.5
	for i in 3:
		W.add_agent(s, W.A, W.NORD1, "BISHOP")
	var state_before := s.rng.state
	PapacyProcessor.process_year(s)
	t.assert_true(s.rng.state != state_before, "un sorteggio per la fazione adatta")
	s.rules.papacy.gift_chance = 0.0
	var state_quiet := s.rng.state
	PapacyProcessor.process_year(s)
	t.assert_eq(s.rng.state, state_quiet, "nessun sorteggio con probabilita' 0")


# --- stato per l'interfaccia --------------------------------------------------------------------------------------------------------------


func test_lo_stato_papale_per_l_interfaccia(t: TestContext) -> void:
	var s := W.world()
	var status := GameCommands.papal_status(s, W.A)
	t.assert_true(bool(status["ok"]))
	t.assert_false(status["scomunicata"])
	t.assert_true(status["papato_vivo"])
	t.assert_eq(status["papa"], s.leader_of(W.P).id)
	t.assert_eq((status["avvertimenti"] as Array).size(), 0)
	t.assert_eq(status["crociata"], 0)
	t.assert_eq((status["jihad"] as Array).size(), 0)
	s.papal_warnings[_warning_key(W.A, W.G)] = {"anno": 1000, "scadenza": 1002}
	s.papal_warnings[_warning_key(W.G, W.A)] = {"anno": 1000, "scadenza": 1002}
	var crusade := W.add_crusade(s, W.A, W.NORD1)
	status = GameCommands.papal_status(s, W.A)
	var list: Array = status["avvertimenti"]
	t.assert_eq(list.size(), 1, "solo quelli di cui e' il colpevole")
	t.assert_eq(list[0]["contro"], W.G)
	t.assert_eq(list[0]["scadenza"], 1002)
	t.assert_eq(status["crociata"], crusade.id)
	PapacyProcessor.excommunicate(s, W.G, "x")
	status = GameCommands.papal_status(s, W.G)
	t.assert_true(status["scomunicata"])
	t.assert_eq(status["anno"], 1000)
	t.assert_false(bool(GameCommands.papal_status(s, "FN_NESSUNA")["ok"]))


# --- salvataggi -------------------------------------------------------------------------------------------------------------------------------


func _busy_world() -> GameState:
	var s := W.world(31)
	PapacyProcessor.excommunicate(s, W.G, PapacyProcessor.REASON_PAPACY, W.ROMA)
	s.declare_war(W.A, W.D)
	s.papal_warnings[_warning_key(W.A, W.D)] = {"anno": 1000, "scadenza": 1002}
	s.papacy_dead_years = 3
	s.papacy_reemergences = 2
	TurnProcessor.end_year(s)
	return s


func test_andata_e_ritorno_del_papato(t: TestContext) -> void:
	var s := _busy_world()
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	t.assert_eq(int(data["versione"]), SaveGame.VERSION)
	var back := _restore(data)
	t.assert_true(back != null)
	t.assert_eq(SaveGame.to_json(back), text, "stato identico attraverso il testo JSON")
	var f := back.faction(W.G)
	t.assert_true(f.excommunicated)
	t.assert_eq(f.excommunication_year, 1000)
	t.assert_eq(f.excommunication_leader, s.faction(W.G).excommunication_leader)
	t.assert_false(back.faction(W.A).excommunicated)
	t.assert_eq(back.papal_warning(W.A, W.D), s.papal_warning(W.A, W.D))
	t.assert_eq(typeof(back.papal_warning(W.A, W.D)["scadenza"]), TYPE_INT)
	t.assert_eq(back.papal_leader, s.papal_leader)
	t.assert_eq(back.papacy_reemergences, 2)
	t.assert_eq(back.papacy_dead_years, s.papacy_dead_years)
	# l'anno dopo e' lo stesso
	TurnProcessor.end_year(s)
	TurnProcessor.end_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "anno successivo identico")


func test_le_versioni_precedenti_non_hanno_scomuniche_ne_crociate(t: TestContext) -> void:
	var s := _busy_world()
	W.add_crusade(s, W.A, W.NORD2)
	var old := SaveGame.to_dict(s)
	old["versione"] = 6
	for key in ["avvertimenti", "papa", "anni_senza_papato", "riemersioni_papato"]:
		old.erase(key)
	var back := _restore(old)
	t.assert_true(back != null, "la versione 6 si legge")
	for f in back.factions:
		t.assert_false(f.excommunicated, "%s: nessuna scomunica" % f.id)
		t.assert_eq(f.excommunication_leader, 0)
	t.assert_true(back.papal_warnings.is_empty())
	t.assert_eq(back.papal_leader, 0)
	t.assert_eq(back.papacy_dead_years, 0)
	t.assert_eq(back.papacy_reemergences, 0)
	for a in back.armies:
		t.assert_false(a.is_crusade(), "esercito %d: nessuna crociata" % a.id)
	t.assert_eq(SaveGame.to_dict(back)["versione"], SaveGame.VERSION, "si riscrive nella versione corrente")
	TurnProcessor.end_year(back)    # e si gioca
	W.check_state(t, back, "dopo il ricarico")


func test_il_formato_del_salvataggio(t: TestContext) -> void:
	var s := W.world()
	var d := SaveGame.to_dict(s)
	t.assert_true(d.has("avvertimenti") and d.has("papa") and d.has("anni_senza_papato") and d.has("riemersioni_papato"))
	for fd in d["fazioni"]:
		t.assert_false((fd as Dictionary).has("scomunicata"), "il campo c'e' solo per le scomunicate")
	for ad in d["eserciti"]:
		t.assert_false((ad as Dictionary).has("crociata"), "il campo c'e' solo per i crociati")
	PapacyProcessor.excommunicate(s, W.A, "x")
	W.add_crusade(s, W.G, W.EST)
	d = SaveGame.to_dict(s)
	var found := false
	for fd in d["fazioni"]:
		var fdict: Dictionary = fd
		if fdict["id"] == W.A:
			found = true
			t.assert_eq(fdict["scomunicata"], true)
			t.assert_eq(fdict["anno_scomunica"], 1000)
	t.assert_true(found)
	var crusaders := 0
	for ad in d["eserciti"]:
		if (ad as Dictionary).has("crociata"):
			crusaders += 1
	t.assert_eq(crusaders, 1)
