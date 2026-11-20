extends RefCounted
## Test della diplomazia (fase 5a): stati delle coppie (guerra, alleanza, tregua, neutralita'), rottura dei trattati
## quando si attacca, scadenza delle tregue a fine anno, pulizia, formula di accettazione (PROVVISORIA), alleati che
## non combattono tra loro e non bloccano le zone di mare, parametri di data/regole/diplomazia.cfg.
## Mondo di prova: vedi agent_world.gd (FN_ALPHA, FN_BETA, FN_GAMMA e i ribelli).

const W := preload("res://tests/unit/agent_world.gd")


func _end_year(t: TestContext, s: GameState) -> void:
	var r := TurnProcessor.end_year(s)
	t.assert_true(bool(r["ok"]), "fine anno")
	t.assert_eq((r["errori"] as Array).size(), 0, "nessuna anomalia dei dati: %s" % str(r["errori"]))


# --- parametri ------------------------------------------------------------------------------


func test_i_parametri_predefiniti_sono_quelli_del_file(t: TestContext) -> void:
	var from_file := DiplomacyRules.load_file()
	t.assert_eq(from_file.errors, PackedStringArray(), "il file diplomazia.cfg si legge")
	t.assert_eq(DiplomacyRules.new().to_dict(), from_file.to_dict(), "predefiniti = file")
	var rules := Rules.new()
	t.assert_eq(rules.diplomacy.to_dict(), from_file.to_dict(), "Rules carica la diplomazia")
	t.assert_true(from_file.truce_years >= 1)
	t.assert_true(from_file.betrayal_malus >= 1)
	t.assert_true(from_file.p_min < from_file.p_max)


# --- stati delle coppie ---------------------------------------------------------------------------


func test_una_coppia_nuova_e_neutrale(t: TestContext) -> void:
	var s := W.world()
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_NEUTRAL)
	t.assert_eq(s.relation(W.B, W.A), GameState.REL_NEUTRAL, "simmetrica")
	t.assert_false(s.is_allied(W.A, W.B))
	t.assert_eq(s.truce_until(W.A, W.B), 0)
	t.assert_eq(s.relation(W.A, W.A), GameState.REL_NEUTRAL, "con se stessa: neutrale")
	t.assert_eq(s.relation(W.A, GameState.REBEL), GameState.REL_WAR, "i ribelli sono in guerra con tutti")


func test_la_guerra_e_l_alleanza_si_escludono(t: TestContext) -> void:
	var s := W.world()
	t.assert_true(s.declare_war(W.A, W.B))
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_WAR)
	t.assert_false(s.form_alliance(W.A, W.B), "in guerra non si fa un'alleanza")
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_WAR)
	t.assert_true(s.end_war(W.A, W.B))
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_NEUTRAL, "la fine della guerra senza tregua e' neutralita'")
	t.assert_true(s.form_alliance(W.A, W.B))
	t.assert_eq(s.relation(W.B, W.A), GameState.REL_ALLIANCE)
	t.assert_false(s.form_alliance(W.A, W.B), "gia' alleate")


func test_dichiarare_guerra_toglie_alleanza_e_tregua(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.A, W.B)
	t.assert_true(s.declare_war(W.A, W.B))
	t.assert_false(s.is_allied(W.A, W.B))
	t.assert_eq(s.alliances.size(), 0)
	s.end_war(W.A, W.B)
	s.make_truce(W.A, W.G, 1010)
	t.assert_true(s.declare_war(W.G, W.A))
	t.assert_eq(s.truce_until(W.A, W.G), 0)
	t.assert_eq(s.relation(W.A, W.G), GameState.REL_WAR)


func test_la_tregua_mette_fine_alla_guerra_e_all_alleanza(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	t.assert_true(s.make_truce(W.A, W.B, 1007))
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_TRUCE)
	t.assert_false(s.at_war(W.A, W.B))
	t.assert_eq(s.truce_until(W.B, W.A), 1007)
	t.assert_true(s.form_alliance(W.A, W.B), "l'alleanza sostituisce la tregua")
	t.assert_eq(s.truce_until(W.A, W.B), 0)
	t.assert_true(s.make_truce(W.A, W.B, 1008))
	t.assert_false(s.is_allied(W.A, W.B), "la tregua toglie l'alleanza")
	t.assert_true(s.break_truce(W.A, W.B))
	t.assert_false(s.break_truce(W.A, W.B), "gia' rotta")
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_NEUTRAL)


func test_i_ribelli_e_se_stessi_non_entrano_nei_trattati(t: TestContext) -> void:
	var s := W.world()
	t.assert_false(s.form_alliance(W.A, GameState.REBEL))
	t.assert_false(s.form_alliance(W.A, W.A))
	t.assert_false(s.make_truce(W.A, GameState.REBEL, 1010))
	t.assert_false(s.make_truce(W.B, W.B, 1010))
	t.assert_eq(s.alliances.size() + s.truces.size(), 0)
	t.assert_false(s.break_alliance(W.A, W.B), "niente da rompere")


# --- rottura dei trattati quando si attacca ---------------------------------------------------------------


func test_attaccare_un_alleato_rompe_l_alleanza_e_costa_influenza(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.A, W.B)
	var leader := s.leader_of(W.A)
	leader.influence = 6
	var kind := DiplomacyProcessor.break_for_attack(s, W.A, W.B, W.MEZZA)
	t.assert_eq(kind, GameState.EV_ALLIANCE_BROKEN)
	t.assert_false(s.is_allied(W.A, W.B))
	t.assert_eq(leader.influence, 6 - s.rules.diplomacy.betrayal_malus)
	var events := W.events_of(s, GameState.EV_ALLIANCE_BROKEN)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["fazione"], W.A)
	t.assert_eq(events[0]["con"], W.B)
	t.assert_eq(events[0]["influenza_persa"], s.rules.diplomacy.betrayal_malus)
	t.assert_true(str(events[0]["testo"]) != "")


func test_attaccare_chi_ha_una_tregua_rompe_la_tregua(t: TestContext) -> void:
	var s := W.world()
	s.make_truce(W.A, W.G, 1010)
	var kind := DiplomacyProcessor.break_for_attack(s, W.A, W.G, W.ORTO)
	t.assert_eq(kind, GameState.EV_TRUCE_BROKEN)
	t.assert_eq(s.truce_until(W.A, W.G), 0)
	t.assert_eq(W.events_of(s, GameState.EV_TRUCE_BROKEN).size(), 1)
	t.assert_eq(W.events_of(s, GameState.EV_ALLIANCE_BROKEN).size(), 0)


func test_attaccare_un_neutrale_non_rompe_nulla(t: TestContext) -> void:
	var s := W.world()
	var before := s.leader_of(W.A).influence
	t.assert_eq(DiplomacyProcessor.break_for_attack(s, W.A, W.B, W.MEZZA), "")
	t.assert_eq(s.leader_of(W.A).influence, before)
	t.assert_eq(s.events.size(), 0)
	s.declare_war(W.A, W.B)
	t.assert_eq(DiplomacyProcessor.break_for_attack(s, W.A, W.B, W.MEZZA), "", "in guerra non c'e' trattato")


func test_l_influenza_non_scende_sotto_zero(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.A, W.B)
	s.leader_of(W.A).influence = 0
	DiplomacyProcessor.break_for_attack(s, W.A, W.B, W.MEZZA)
	t.assert_eq(s.leader_of(W.A).influence, 0)
	t.assert_eq(W.events_of(s, GameState.EV_ALLIANCE_BROKEN)[0]["influenza_persa"], 0)


func test_il_movimento_contro_un_alleato_rompe_l_alleanza_nel_fine_anno(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.A, W.B)
	var army := W.land_army(s, W.A, W.BASSA)
	t.assert_true(army != null)
	t.assert_true(bool(GameCommands.order_move(s, W.A, army.id, PackedStringArray([W.MEZZA]))["ok"]))
	_end_year(t, s)
	t.assert_false(s.is_allied(W.A, W.B), "l'alleanza e' rotta")
	t.assert_eq(W.events_of(s, GameState.EV_ALLIANCE_BROKEN).size(), 1)
	t.assert_eq(W.events_of(s, GameState.EV_WAR_DECLARED).size(), 1, "poi la guerra")
	t.assert_true(s.at_war(W.A, W.B))


func test_il_movimento_contro_una_tregua_la_rompe_e_dichiara_guerra(t: TestContext) -> void:
	var s := W.world()
	s.make_truce(W.A, W.B, 1010)
	var army := W.land_army(s, W.A, W.BASSA)
	GameCommands.order_move(s, W.A, army.id, PackedStringArray([W.MEZZA]))
	_end_year(t, s)
	t.assert_eq(s.truce_until(W.A, W.B), 0)
	t.assert_eq(W.events_of(s, GameState.EV_TRUCE_BROKEN).size(), 1)
	t.assert_true(s.at_war(W.A, W.B))


# --- alleati: stessa regione, mare ------------------------------------------------------------------------


func test_gli_eserciti_alleati_non_sono_ostili_tra_loro(t: TestContext) -> void:
	var s := W.world()
	s.create_army(W.B, W.ORTO, false).stacks.append(UnitStack.new("Spearmen", 30, 0))
	var hostile := WarProcessor.hostile_factions(s, W.A, false, W.ORTO)
	t.assert_true(hostile.has(W.G) and hostile.has(W.B), "senza trattati entrambi sono ostili")
	s.form_alliance(W.A, W.B)
	hostile = WarProcessor.hostile_factions(s, W.A, false, W.ORTO)
	t.assert_true(hostile.has(W.G), "il proprietario della provincia resta ostile")
	t.assert_false(hostile.has(W.B), "l'esercito alleato non lo e'")


func test_entrare_in_una_provincia_alleata_resta_un_attacco(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.A, W.B)
	t.assert_true(GameCommands.is_hostile_target(s, W.A, W.MEZZA), "nessun diritto di passaggio (PROVVISORIA)")
	var army := W.land_army(s, W.A, W.BASSA)
	var r := GameCommands.order_move(s, W.A, army.id, PackedStringArray([W.MEZZA]))
	t.assert_true(bool(r["attacco"]))


func test_gli_alleati_nella_stessa_regione_non_combattono(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.A, W.B)
	var guest := s.create_army(W.A, W.MEZZA, false)
	guest.stacks.append(UnitStack.new("Spearmen", 80, 0))
	_end_year(t, s)
	t.assert_eq(W.events_of(s, GameState.EV_BATTLE).size(), 0, "nessuna battaglia")
	t.assert_eq(W.events_of(s, GameState.EV_SIEGE_STARTED).size(), 0, "nessun assedio")
	t.assert_true(s.is_allied(W.A, W.B), "l'alleanza regge")
	t.assert_eq(s.province(W.MEZZA).owner, W.B)


func test_la_flotta_alleata_non_blocca_la_zona_di_mare(t: TestContext) -> void:
	var s := W.world()
	# la galea di partenza di A (ALTA) sta nel mare del Nord: qui la zona deve partire senza flotte di A
	for a in s.armies:
		if a.is_fleet and a.faction == W.A and a.region == W.NORD:
			a.stacks.clear()
	W.fleet(s, W.B, W.NORD)
	s.rules.combat.neutral_blockade = false
	t.assert_eq(GameCommands.sea_zone_status(s, W.A, W.NORD), GameCommands.ZONE_NO_FLEET, "neutrale senza blocco navale: non blocca")
	s.rules.combat.neutral_blockade = true
	t.assert_eq(GameCommands.sea_zone_status(s, W.A, W.NORD), GameCommands.ZONE_BLOCKED, "neutrale con il blocco navale: blocca")
	s.declare_war(W.A, W.B)
	t.assert_eq(GameCommands.sea_zone_status(s, W.A, W.NORD), GameCommands.ZONE_BLOCKED, "in guerra: blocca")
	s.end_war(W.A, W.B)
	s.form_alliance(W.A, W.B)
	t.assert_eq(GameCommands.sea_zone_status(s, W.A, W.NORD), GameCommands.ZONE_NO_FLEET, "alleata: non blocca e non conta come propria")
	W.fleet(s, W.A, W.NORD)
	t.assert_eq(GameCommands.sea_zone_status(s, W.A, W.NORD), GameCommands.ZONE_PASSABLE, "con una flotta propria e' percorribile")


# --- scadenza delle tregue ---------------------------------------------------------------------------------


func test_expire_truces_toglie_le_tregue_scadute_in_ordine(t: TestContext) -> void:
	var s := W.world()
	s.make_truce(W.B, W.G, 1005)
	s.make_truce(W.A, W.B, 1003)
	s.make_truce(W.A, W.G, 1003)
	DiplomacyProcessor.expire_truces(s, 1003)
	t.assert_eq(s.truce_until(W.A, W.B), 0)
	t.assert_eq(s.truce_until(W.A, W.G), 0)
	t.assert_eq(s.truce_until(W.B, W.G), 1005, "non ancora scaduta")
	var events := W.events_of(s, GameState.EV_TRUCE_EXPIRED)
	t.assert_eq(events.size(), 2)
	t.assert_eq(events[0]["fazione"], W.A, "ordine alfabetico delle coppie")
	t.assert_eq(events[0]["con"], W.B)
	t.assert_eq(events[1]["con"], W.G)
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_NEUTRAL, "dopo la tregua: neutrale, non guerra")


func test_la_tregua_scade_a_fine_anno_nell_anno_di_scadenza(t: TestContext) -> void:
	var s := W.world()
	s.make_truce(W.A, W.B, 1002)
	_end_year(t, s)
	t.assert_eq(s.year, 1001)
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_TRUCE, "nel 1001 vale ancora")
	t.assert_eq(W.events_of(s, GameState.EV_TRUCE_EXPIRED).size(), 0)
	_end_year(t, s)
	t.assert_eq(s.year, 1002)
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_NEUTRAL, "all'inizio del 1002 e' scaduta")
	t.assert_eq(W.events_of(s, GameState.EV_TRUCE_EXPIRED).size(), 1)


func test_la_durata_della_tregua_firmata_da_un_emissario(t: TestContext) -> void:
	var s := W.world()
	W.always_accept(s)
	s.declare_war(W.A, W.B)
	var emissary := W.agent_of(s, W.A, AgentState.EMISSARY)
	t.assert_true(bool(GameCommands.order_mission(s, W.A, emissary.id, AgentMissions.TRUCE, W.B)["ok"]))
	_end_year(t, s)
	var years := s.rules.diplomacy.truce_years
	t.assert_eq(s.truce_until(W.A, W.B), 1000 + 1 + years, "scade dopo gli anni interi di durata_tregua dall'anno dopo la firma")
	for i in range(years):
		t.assert_eq(s.relation(W.A, W.B), GameState.REL_TRUCE, "anno %d" % s.year)
		_end_year(t, s)
	t.assert_eq(s.relation(W.A, W.B), GameState.REL_NEUTRAL)
	t.assert_eq(s.year, 1001 + years)


# --- pulizia -------------------------------------------------------------------------------------------------


func test_cleanup_toglie_i_trattati_non_validi_e_lascia_le_guerre(t: TestContext) -> void:
	var s := W.world()
	s.alliances[GameState.war_key(W.A, GameState.REBEL)] = true
	s.alliances[GameState.war_key(W.A, W.A)] = true
	s.truces[GameState.war_key(W.B, GameState.REBEL)] = 1010
	s.alliances[GameState.war_key(W.A, "FN_NESSUNA")] = true
	s.form_alliance(W.A, W.B)
	s.make_truce(W.B, W.G, 1010)
	s.declare_war(W.A, W.G)
	s.faction(W.G).alive = false
	DiplomacyProcessor.cleanup(s)
	t.assert_eq(s.alliances.keys(), [GameState.war_key(W.A, W.B)] as Array, "resta solo l'alleanza valida")
	t.assert_eq(s.truces.size(), 0, "la tregua con una fazione morta cade")
	t.assert_true(s.wars.has(GameState.war_key(W.A, W.G)), "le guerre restano")


func test_la_fazione_morta_perde_i_trattati_nella_pulizia_di_fine_anno(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.A, W.G)
	s.make_truce(W.B, W.G, 1010)
	s.faction(W.G).alive = false
	AgentProcessor.sync_year(s)
	t.assert_false(s.is_allied(W.A, W.G))
	t.assert_eq(s.truce_until(W.B, W.G), 0)


# --- accettazione (PROVVISORIA) ------------------------------------------------------------------------------


func test_accettazione_somma_dei_termini_e_limiti(t: TestContext) -> void:
	var s := W.world()
	for kind in [DiplomacyProcessor.KIND_ALLIANCE, DiplomacyProcessor.KIND_TRUCE, DiplomacyProcessor.KIND_MARRIAGE]:
		var terms := DiplomacyProcessor.acceptance_terms(s, kind, W.A, W.G, 3)
		var sum := float(terms["base"]) + float(terms["influenza"]) + float(terms["valore"]) + float(terms["religione"]) + float(terms["dimensione"]) + float(terms["guerra"]) + float(terms["stanchezza"])
		t.assert_true(absf(sum - float(terms["somma"])) < 0.000001, "%s: la somma e' la somma dei termini" % kind)
		var dr := s.rules.diplomacy
		t.assert_true(float(terms["p"]) >= dr.p_min and float(terms["p"]) <= dr.p_max, "%s: p limitata" % kind)
		t.assert_eq(DiplomacyProcessor.acceptance(s, kind, W.A, W.G, 3), float(terms["p"]))


func test_accettazione_basi_per_tipo(t: TestContext) -> void:
	var s := W.world()
	var dr := s.rules.diplomacy
	t.assert_eq(float(DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 0)["base"]), dr.base_alliance)
	t.assert_eq(float(DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_TRUCE, W.A, W.G, 0)["base"]), dr.base_truce)
	t.assert_eq(float(DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_MARRIAGE, W.A, W.G, 0)["base"]), dr.base_marriage)


func test_accettazione_cresce_con_il_valore_e_con_l_influenza(t: TestContext) -> void:
	var s := W.world()
	var dr := s.rules.diplomacy
	dr.p_min = 0.0
	dr.p_max = 1.0
	var low := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 1)
	var high := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 5)
	t.assert_true(absf(float(high["valore"]) - float(low["valore"]) - 4.0 * dr.k_valour) < 0.000001, "k_valore per punto")
	var leader := s.leader_of(W.A)
	leader.influence = dr.neutral_influence
	var neutral := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 1)
	t.assert_true(absf(float(neutral["influenza"])) < 0.000001, "influenza neutra: nessun termine")
	leader.influence = dr.neutral_influence + 3
	var strong := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 1)
	t.assert_true(absf(float(strong["influenza"]) - 3.0 * dr.k_influence) < 0.000001)
	leader.influence = dr.neutral_influence - 2
	var weak := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 1)
	t.assert_true(float(weak["influenza"]) < 0.0, "influenza bassa: malus")


func test_accettazione_religione(t: TestContext) -> void:
	var s := W.world()
	var dr := s.rules.diplomacy
	t.assert_eq(DiplomacyProcessor.faction_religion(s, W.A), "CATHOLIC")
	t.assert_eq(DiplomacyProcessor.faction_religion(s, W.B), "MUSLIM")
	var same := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 0)
	var other := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.B, 0)
	t.assert_eq(float(same["religione"]), dr.same_religion_bonus)
	t.assert_eq(float(other["religione"]), -dr.other_religion_malus)


func test_accettazione_cala_con_la_dimensione_dell_impero(t: TestContext) -> void:
	var s := W.world()
	var dr := s.rules.diplomacy
	var share := DiplomacyProcessor.land_share(s, W.A)
	t.assert_true(absf(share - 2.0 / float(s.provinces.size())) < 0.000001, "ALPHA ha 2 province")
	var terms := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 0)
	if share > dr.size_threshold:
		t.assert_true(absf(float(terms["dimensione"]) + dr.k_size * (share - dr.size_threshold)) < 0.000001)
	else:
		t.assert_eq(float(terms["dimensione"]), 0.0)
	# ALPHA conquista tutto: il malus cresce
	var before := float(terms["dimensione"])
	for p in s.provinces:
		p.owner = W.A
	var after := float(DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 0)["dimensione"])
	t.assert_true(after < before, "un impero piu' grande ottiene meno")
	t.assert_eq(after, -dr.k_size * (1.0 - dr.size_threshold))


func test_accettazione_alleanza_con_il_nemico_di_un_alleato(t: TestContext) -> void:
	var s := W.world()
	var dr := s.rules.diplomacy
	var base := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 0)
	t.assert_eq(float(base["guerra"]), 0.0)
	s.form_alliance(W.G, W.B)
	s.declare_war(W.A, W.B)
	var terms := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 0)
	t.assert_eq(float(terms["guerra"]), -dr.allies_war_malus)


func test_accettazione_tregua_dipende_dalla_forza(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.B)
	var terms := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_TRUCE, W.A, W.B, 0)
	var own := DiplomacyProcessor.faction_men(s, W.A)
	var other := DiplomacyProcessor.faction_men(s, W.B)
	t.assert_true(own > other, "ALPHA e' piu' forte di BETA")
	t.assert_true(float(terms["guerra"]) > 0.0, "il piu' forte ottiene di piu'")
	var reverse := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_TRUCE, W.B, W.A, 0)
	t.assert_true(float(reverse["guerra"]) < 0.0, "il piu' debole ottiene di meno")
	t.assert_true(absf(float(terms["guerra"]) + float(reverse["guerra"])) < 0.000001, "simmetrici")


func test_accettazione_tregua_cresce_con_la_stanchezza(t: TestContext) -> void:
	var s := W.world()
	var dr := s.rules.diplomacy
	s.declare_war(W.A, W.B)
	var fresh := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_TRUCE, W.B, W.A, 0)
	t.assert_eq(float(fresh["stanchezza"]), 0.0, "guerra appena dichiarata")
	s.year += 3
	var tired := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_TRUCE, W.B, W.A, 0)
	t.assert_true(absf(float(tired["stanchezza"]) - 3.0 * dr.k_weariness) < 0.000001, "tre anni senza svolte")
	t.assert_true(float(tired["somma"]) > float(fresh["somma"]), "la tregua diventa piu' accettabile")
	s.year += 100
	var capped := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_TRUCE, W.B, W.A, 0)
	t.assert_true(absf(float(capped["stanchezza"]) - float(dr.weariness_max_years) * dr.k_weariness) < 0.000001, "oltre il massimo non cresce")
	s.mark_war_turn(W.A, W.B)
	t.assert_eq(float(DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_TRUCE, W.B, W.A, 0)["stanchezza"]), 0.0, "una svolta azzera la stanchezza")
	var alliance := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.B, W.G, 0)
	t.assert_eq(float(alliance["stanchezza"]), 0.0, "solo per le tregue")


func test_l_anno_della_svolta_segue_la_guerra(t: TestContext) -> void:
	var s := W.world()
	t.assert_eq(s.war_turn_year(W.A, W.B), 0, "nessuna guerra")
	s.declare_war(W.A, W.B)
	t.assert_eq(s.war_turn_year(W.B, W.A), s.year, "la dichiarazione e' la prima svolta")
	var start := s.year
	s.year += 4
	t.assert_eq(DiplomacyProcessor.stalemate_years(s, W.A, W.B), 4)
	s.mark_war_turn(W.B, W.A)
	t.assert_eq(s.war_turn_year(W.A, W.B), start + 4, "una provincia passata di mano")
	s.mark_war_turn(W.A, W.G)
	t.assert_false(s.at_war(W.A, W.G), "segnare una svolta non dichiara guerra")
	s.make_truce(W.A, W.B, s.year + 6)
	t.assert_eq(s.war_turn_year(W.A, W.B), 0, "la tregua chiude la guerra")
	t.assert_eq(DiplomacyProcessor.stalemate_years(s, W.A, W.B), 0)


func test_alleanze_in_conflitto(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.G, W.A)
	s.form_alliance(W.G, W.B)
	s.events.clear()
	t.assert_true(s.declare_war(W.A, W.B))
	var broken := DiplomacyProcessor.resolve_conflicting_alliances(s, W.A, W.B, W.MEZZA)
	t.assert_eq(broken, PackedStringArray([W.G]), "GAMMA e' alleata di entrambe")
	t.assert_false(s.is_allied(W.G, W.A), "rompe con chi attacca")
	t.assert_true(s.is_allied(W.G, W.B), "resta con chi e' attaccato")
	t.assert_eq(s.events.size(), 1)
	t.assert_eq(str(s.events[0]["tipo"]), GameState.EV_ALLIANCE_BROKEN)
	t.assert_eq(str(s.events[0]["motivo"]), "alleanze_in_conflitto")
	t.assert_eq(int(s.events[0]["influenza_persa"]), 0, "nessuna perdita di influenza")
	var off := W.world()
	off.rules.diplomacy.conflicting_alliances = false
	off.form_alliance(W.G, W.A)
	off.form_alliance(W.G, W.B)
	off.declare_war(W.A, W.B)
	t.assert_eq(DiplomacyProcessor.resolve_conflicting_alliances(off, W.A, W.B, W.MEZZA).size(), 0, "regola spenta")
	t.assert_true(off.is_allied(W.G, W.A))


func test_il_movimento_contro_un_vicino_applica_le_alleanze_in_conflitto(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.G, W.A)
	s.form_alliance(W.G, W.B)
	var army := W.land_army(s, W.A, W.BASSA)
	t.assert_true(bool(GameCommands.order_move(s, W.A, army.id, PackedStringArray([W.MEZZA]))["ok"]))
	_end_year(t, s)
	t.assert_true(s.at_war(W.A, W.B), "ALPHA attacca BETA")
	t.assert_false(s.is_allied(W.G, W.A))
	t.assert_true(s.is_allied(W.G, W.B))


## Segnalazione di Federico (2026-11-20): attacchi inesistenti che rompevano trattati. Due eserciti di fazioni non in guerra
## che entrano nella stessa regione nello stesso fine anno convivono: chi arriva dopo non attacca chi e' appena arrivato.
func test_chi_arriva_insieme_non_si_attacca(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.A, W.B)
	s.form_alliance(W.G, W.B)
	s.make_truce(W.A, W.G, 1020)
	var first := s.create_army(W.G, W.MEZZA, false)   # si muove per primo (id piu' basso)
	first.stacks.append(UnitStack.new("Spearmen", 200, 0))
	var second := s.create_army(W.A, W.MEZZA, false)
	second.stacks.append(UnitStack.new("Spearmen", 200, 0))
	t.assert_false(CampaignUiAttack.new_wars_entering(s, second, W.SOLA).has(W.G), "all'ordine GAMMA non c'e'")
	t.assert_true(bool(GameCommands.order_move(s, W.G, first.id, PackedStringArray([W.SOLA]))["ok"]))
	t.assert_true(bool(GameCommands.order_move(s, W.A, second.id, PackedStringArray([W.SOLA]))["ok"]))
	_end_year(t, s)
	t.assert_eq(W.events_of(s, GameState.EV_TRUCE_BROKEN).size(), 0, "nessuna tregua rotta")
	t.assert_false(s.at_war(W.A, W.G), "nessuna guerra tra ALPHA e GAMMA")
	t.assert_true(s.truce_until(W.A, W.G) > 0, "la tregua regge")
	for e in W.events_of(s, GameState.EV_WAR_DECLARED):
		t.assert_true(str(e["contro"]) == GameState.REBEL or str(e["contro"]) == "", "guerra solo ai ribelli: %s" % str(e))


func test_chi_c_era_gia_resta_un_bersaglio(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.A, W.B)
	s.make_truce(W.A, W.G, 1020)
	var camp := s.create_army(W.G, W.SOLA, false)
	camp.stacks.append(UnitStack.new("Spearmen", 200, 0))
	var mover := s.create_army(W.A, W.MEZZA, false)
	mover.stacks.append(UnitStack.new("Spearmen", 200, 0))
	t.assert_true(CampaignUiAttack.new_wars_entering(s, mover, W.SOLA).has(W.G), "l'interfaccia chiede conferma")
	t.assert_true(bool(GameCommands.order_move(s, W.A, mover.id, PackedStringArray([W.SOLA]))["ok"]))
	_end_year(t, s)
	t.assert_eq(W.events_of(s, GameState.EV_TRUCE_BROKEN).size(), 1, "entrare dove GAMMA stava gia' e' un attacco")
	t.assert_true(s.at_war(W.A, W.G))


func test_le_alleanze_in_conflitto_dicono_chi_e_attaccato(t: TestContext) -> void:
	var s := W.world()
	s.form_alliance(W.G, W.A)
	s.form_alliance(W.G, W.B)
	s.events.clear()
	s.declare_war(W.A, W.B)
	DiplomacyProcessor.resolve_conflicting_alliances(s, W.A, W.B, W.MEZZA)
	t.assert_eq(str(s.events[0]["difensore"]), W.B)
	var text := CampaignUiText.format_event(s, s.events[0])
	t.assert_false(text.contains("attaccando"), "chi rompe non ha attaccato nessuno: %s" % text)
	t.assert_true(text.contains("Alpha") and text.contains("Beta"), text)


func test_accettazione_senza_capo_usa_influenza_neutra(t: TestContext) -> void:
	var s := W.world()
	s.leader_of(W.A).alive = false
	var terms := DiplomacyProcessor.acceptance_terms(s, DiplomacyProcessor.KIND_ALLIANCE, W.A, W.G, 0)
	t.assert_eq(float(terms["influenza"]), 0.0)
