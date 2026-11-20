extends RefCounted
## Guerra e governo dell'IA (fase 7a): mappa delle minacce, difesa, attacco (bersagli ammessi), capitale mai vuota, assalti,
## flotte e sbarchi, comandanti e titoli, predoni e Orda, Papato, ribelli, giocatore, determinismo e `CampaignTurn.advance`.
## Mondo di prova: ai_world.gd (FN_ALPHA espansionista, FN_BETA difensiva, FN_GAMMA predoni, FN_PAPIST il Papato).

const W := preload("res://tests/unit/ai_world.gd")


func _last(path: PackedStringArray) -> String:
	return path[path.size() - 1] if not path.is_empty() else ""


## Vero se la fazione ha un esercito di terra con un percorso che finisce nella regione.
func _heads_to(s: GameState, faction_id: String, region_id: String) -> bool:
	for a in s.armies_of(faction_id):
		if not a.is_fleet and _last(a.path) == region_id:
			return true
	return false


## Regole con aggressione certa per i profili espansionisti (niente sorteggi nei test sugli attacchi ai neutrali).
func _sure_rules() -> AiRules:
	var r := W.quiet_ai_rules()
	for name in ["CATHOLIC_EXPANSIONIST", "CATHOLIC_DEFENSIVE", "BARBARIAN_RAIDER"]:
		var row: Dictionary = r.profiles[name]
		row["aggressione"] = 1.0
	return r


# --- minacce -------------------------------------------------------------------------------------


func test_mappa_delle_minacce(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	W.put(s, W.A, W.A3, 60)
	W.put(s, W.B, W.B1, 100)
	var expansionist := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	var a3: Dictionary = expansionist.threat[W.A3]
	t.assert_true(float(a3["nemica"]) > 0.0, "l'espansionista vede un neutrale armato come minaccia")
	t.assert_true(float(a3["propria"]) > 0.0)
	t.assert_true(bool(a3["fronte"]), "A3 confina con province attaccabili")
	t.assert_eq(float(expansionist.threat[W.A1]["nemica"]), 0.0, "A1 e' lontana")
	t.assert_true(bool(expansionist.threat[W.A1]["capitale"]), "A1 e' la capitale (PlaceLeader)")
	var defensive := W.plan_for(s, W.A, "CATHOLIC_DEFENSIVE")
	t.assert_eq(float(defensive.threat[W.A3]["nemica"]), 0.0, "il difensivo teme solo chi e' in guerra")
	s.declare_war(W.A, W.B)
	var at_war := W.plan_for(s, W.A, "CATHOLIC_DEFENSIVE")
	t.assert_true(float(at_war.threat[W.A3]["nemica"]) > 0.0, "in guerra anche il difensivo la vede")


func test_difende_la_provincia_minacciata(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.declare_war(W.A, W.B)
	var weak := W.put(s, W.A, W.A3, 30)
	var reserve_army := W.put(s, W.A, W.A2, 200)
	W.put(s, W.A, W.A1, 100)
	W.put(s, W.B, W.B1, 300)
	var ctx := W.run_faction(s, W.A)
	t.assert_eq(ctx.rejected, 0, "nessun rifiuto: %s" % str(ctx.rejections))
	t.assert_eq(_last(reserve_army.path), W.A3, "i rinforzi di A2 vanno nella provincia minacciata")
	t.assert_true(weak.path.is_empty(), "chi e' gia' li' resta")


func test_non_lascia_la_capitale_vuota(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.declare_war(W.B, W.A)
	# B1 e' la capitale di BETA e confina con A3, debolissima: tre eserciti da 30, ne devono restare almeno 40 uomini
	for i in 3:
		W.put(s, W.B, W.B1, 30)
	W.put(s, W.A, W.A3, 5)
	var plan := W.plan_for(s, W.B, "CATHOLIC_EXPANSIONIST")
	t.assert_true(bool(plan.threat[W.B1]["capitale"]))
	AiWar.plan(plan)
	var staying := 0
	var leaving := 0
	for a in s.armies_in(W.B1):
		if a.faction == W.B:
			if a.path.is_empty():
				staying += a.men_total()
			else:
				leaving += a.men_total()
	t.assert_true(staying >= plan.rules.capital_min_men, "restano %d uomini, minimo %d" % [staying, plan.rules.capital_min_men])
	t.assert_true(leaving > 0, "gli altri attaccano A3")
	t.assert_eq(plan.ctx.rejected, 0, str(plan.ctx.rejections))


func test_un_solo_esercito_in_capitale_non_parte(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.declare_war(W.B, W.A)
	var only := W.put(s, W.B, W.B1, 100)
	W.put(s, W.A, W.A3, 5)
	var plan := W.plan_for(s, W.B, "CATHOLIC_EXPANSIONIST")
	AiWar.plan(plan)
	t.assert_true(only.path.is_empty(), "l'unico esercito della capitale resta")


# --- attacco ------------------------------------------------------------------------------------


## Tre eserciti uguali nella regione: il piu' forte resta a guardia (la minaccia e' coperta), gli altri possono partire.
func _stack(s: GameState, faction_id: String, region_id: String, men_each: int) -> void:
	for i in 3:
		W.put(s, faction_id, region_id, men_each)


func test_attacca_il_confinante_in_guerra_piu_debole(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.declare_war(W.A, W.B)
	_stack(s, W.A, W.A3, 200)
	W.put(s, W.A, W.A1, 100)
	W.put(s, W.B, W.B1, 30)       # debole
	W.put(s, "FN_REBEL", W.R1, 400)   # forte: non conviene
	var ctx := W.run_faction(s, W.A)
	t.assert_eq(ctx.rejected, 0, str(ctx.rejections))
	t.assert_true(_heads_to(s, W.A, W.B1), "attacca B1")
	t.assert_false(_heads_to(s, W.A, W.R1), "non i ribelli di R1")


func test_attacca_i_ribelli_se_sono_deboli(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	_stack(s, W.A, W.A3, 200)
	W.put(s, W.A, W.A1, 100)
	W.put(s, W.B, W.B1, 900)      # il vicino neutrale e' fortissimo
	W.put(s, "FN_REBEL", W.R1, 20)
	W.run_faction(s, W.A, _sure_rules())
	t.assert_true(_heads_to(s, W.A, W.R1))
	t.assert_false(_heads_to(s, W.A, W.B1))


func test_non_attacca_un_alleato(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	t.assert_true(s.form_alliance(W.A, W.B))
	_stack(s, W.A, W.A3, 200)
	W.put(s, W.A, W.A1, 100)
	W.put(s, W.B, W.B1, 10)
	var ctx := W.run_faction(s, W.A, _sure_rules())
	t.assert_false(_heads_to(s, W.A, W.B1), "mai un alleato")
	t.assert_eq(ctx.rejected, 0, str(ctx.rejections))


func test_non_attacca_una_fazione_in_tregua(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	t.assert_true(s.make_truce(W.A, W.B, s.year + 5))
	_stack(s, W.A, W.A3, 200)
	W.put(s, W.A, W.A1, 100)
	W.put(s, W.B, W.B1, 10)
	W.run_faction(s, W.A, _sure_rules())
	t.assert_false(_heads_to(s, W.A, W.B1), "la tregua si rispetta")


func test_attacca_un_neutrale_debole_solo_se_il_profilo_lo_vuole(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	_stack(s, W.A, W.A3, 200)
	W.put(s, W.A, W.A1, 100)
	W.put(s, W.B, W.B1, 10)
	W.run_faction(s, W.A, _sure_rules())
	t.assert_true(_heads_to(s, W.A, W.B1), "l'espansionista attacca il vicino neutrale debole")
	var s2 := W.world()
	W.clear_armies(s2)
	_stack(s2, W.A, W.A3, 200)
	W.put(s2, W.A, W.A1, 100)
	W.put(s2, W.B, W.B1, 10)
	var cautious := _sure_rules()
	var plan := W.plan_for(s2, W.A, "CATHOLIC_DEFENSIVE", W.context(s2, cautious))
	t.assert_true(AiPolicy.threshold_for(plan, AiPolicy.KIND_NEUTRAL) > plan.threshold, "il difensivo vuole piu' vantaggio contro un neutrale")
	AiWar.plan(plan)
	t.assert_true(_heads_to(s2, W.A, W.B1), "il difensivo attacca il neutrale solo se molto debole (qui 300 contro 10)")
	var s3 := W.world()
	W.clear_armies(s3)
	_stack(s3, W.A, W.A3, 200)
	W.put(s3, W.A, W.A1, 100)
	W.put(s3, W.B, W.B1, 10)
	cautious.cautious_neutral_factor = 1000.0
	var plan3 := W.plan_for(s3, W.A, "CATHOLIC_DEFENSIVE", W.context(s3, cautious))
	AiWar.plan(plan3)
	t.assert_false(_heads_to(s3, W.A, W.B1), "con una soglia altissima il difensivo non attacca chi non e' in guerra")
	var s4 := W.world()
	W.clear_armies(s4)
	_stack(s4, W.A, W.A3, 200)
	W.put(s4, W.A, W.A1, 100)
	W.put(s4, W.B, W.B1, 10)
	var plan4 := W.plan_for(s4, W.A, "CATHOLIC_ISOLATIONIST", W.context(s4, _sure_rules()))
	AiWar.plan(plan4)
	t.assert_false(_heads_to(s4, W.A, W.B1), "l'isolazionista attacca solo i ribelli")


func test_non_attacca_se_il_rapporto_non_basta(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.declare_war(W.A, W.B)
	_stack(s, W.A, W.A3, 60)
	W.put(s, W.A, W.A1, 100)
	W.put(s, W.B, W.B1, 80)
	W.run_faction(s, W.A, _sure_rules())
	t.assert_false(_heads_to(s, W.A, W.B1), "meno forti del difensore: niente attacco")


func test_il_papato_non_si_attacca_da_cattolici(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	W.put(s, W.B, W.B2, 300)
	W.put(s, W.B, W.B1, 100)
	W.put(s, W.P, W.P1, 10)
	var plan := W.plan_for(s, W.B, "CATHOLIC_EXPANSIONIST", W.context(s, _sure_rules()))
	t.assert_true(AiPolicy.papal_blocks(s, W.B, W.P, "CATHOLIC_EXPANSIONIST"))
	t.assert_eq(AiPolicy.attackable(plan, W.P), "")
	AiWar.plan(plan)
	t.assert_false(_heads_to(s, W.B, W.P1))


func test_avvertimento_papale_e_scomunica(t: TestContext) -> void:
	var s := W.world()
	s.papal_warnings[GameState.warning_key(W.A, W.B)] = {"anno": s.year, "scadenza": s.year + 3}
	t.assert_true(AiPolicy.papal_blocks(s, W.A, W.B, "CATHOLIC_EXPANSIONIST"), "avvertimento in corso: si rispetta")
	t.assert_false(AiPolicy.papal_blocks(s, W.B, W.A, "CATHOLIC_EXPANSIONIST"), "l'avvertimento e' a senso unico")
	s.faction(W.A).excommunicated = true
	t.assert_false(AiPolicy.papal_blocks(s, W.A, W.B, "CATHOLIC_EXPANSIONIST"), "scomunicata e aggressiva: non rispetta piu' nulla")
	t.assert_true(AiPolicy.papal_blocks(s, W.A, W.B, "CATHOLIC_DEFENSIVE"), "scomunicata ma prudente: rispetta")


# --- assedi ------------------------------------------------------------------------------------


func _siege(s: GameState, besiegers: int, garrison: int) -> Army:
	W.clear_armies(s)
	s.declare_war(W.A, W.B)
	s.province(W.B1).set_level("CASTLE", 4)
	var army := W.put(s, W.A, W.B1, besiegers)
	var inside := W.put(s, W.B, W.B1, garrison)
	inside.in_castle = true
	var siege := SiegeState.new(W.B1, W.A, 0)
	siege.army_ids = PackedInt32Array([army.id])
	s.sieges[W.B1] = siege
	return army


func test_assalta_solo_con_rapporto_favorevole(t: TestContext) -> void:
	var s := W.world()
	var strong := _siege(s, 400, 40)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	AiWar.plan(plan)
	t.assert_true(strong.assault_ordered, "400 contro 40 dietro mura: si assalta")
	t.assert_true(strong.path.is_empty(), "gli assedianti restano")
	t.assert_eq(plan.ctx.rejected, 0, str(plan.ctx.rejections))
	var s2 := W.world()
	var weak := _siege(s2, 50, 40)
	var plan2 := W.plan_for(s2, W.A, "CATHOLIC_EXPANSIONIST")
	AiWar.plan(plan2)
	t.assert_false(weak.assault_ordered, "50 contro 40 x castello: si aspetta")
	t.assert_true(weak.path.is_empty(), "e si resta ad assediare")


# --- flotte e sbarchi -----------------------------------------------------------------------------


func test_costruisce_una_flotta_se_il_profilo_e_navale(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	W.enrich(s, W.A)
	s.province(W.A1).set_level("SHIPYARD", 1)
	W.set_treasury(s, W.A, 8000)
	var plan := W.plan_for(s, W.A, "CATHOLIC_NAVAL_EXPANSIONIST")
	AiNavy.plan(plan)
	var queued := PackedStringArray()
	for q in s.province(W.A1).unit_queue:
		queued.append(q.key)
	t.assert_true(queued.has("Galley"), "una galea in coda: %s" % str(queued))
	t.assert_eq(plan.ctx.rejected, 0, str(plan.ctx.rejections))
	var land_profile := W.plan_for(s, W.B, "CATHOLIC_DEFENSIVE")
	AiNavy.plan(land_profile)
	t.assert_eq(W.queued_units(s, W.B), 0, "un profilo di terra senza flotte non costruisce navi")


func test_sbarca_verso_un_nemico_via_mare(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.declare_war(W.A, W.G)
	W.put(s, W.A, W.A1, 100)
	W.put(s, W.A, W.A1, 100)
	W.fleet(s, W.A, W.MARE)
	W.put(s, W.G, W.G1, 20)
	var ctx := W.run_faction(s, W.A)
	t.assert_eq(ctx.rejected, 0, str(ctx.rejections))
	var sailed: Army = null
	for a in s.armies_of(W.A):
		if not a.is_fleet and _last(a.path) == W.G1:
			sailed = a
	t.assert_true(sailed != null, "uno sbarco a G1")
	if sailed != null:
		t.assert_eq(sailed.sea_route, PackedStringArray([W.MARE]), "via la zona di mare con la flotta")
	t.assert_true(_count_staying(s, W.A, W.A1) >= 1, "la capitale non resta scoperta")


func _count_staying(s: GameState, faction_id: String, region_id: String) -> int:
	var n := 0
	for a in s.armies_in(region_id):
		if a.faction == faction_id and not a.is_fleet and a.path.is_empty():
			n += 1
	return n


func test_senza_flotta_niente_sbarchi(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.declare_war(W.A, W.G)
	W.put(s, W.A, W.A1, 100)
	W.put(s, W.A, W.A1, 100)
	W.put(s, W.G, W.G1, 20)
	W.run_faction(s, W.A)
	t.assert_false(_heads_to(s, W.A, W.G1))


# --- comandanti e titoli -------------------------------------------------------------------------


func test_mette_il_generale_migliore_al_comando(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	var army := W.put(s, W.A, W.A2, 100)
	var low := W.add_general(s, W.A, W.A2, 2, 5)
	var high := W.add_general(s, W.A, W.A2, 5, 5)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	AiStaff.plan(plan)
	t.assert_eq(high.army, army.id, "il comando migliore guida l'esercito")
	t.assert_eq(low.army, 0)
	t.assert_eq(plan.ctx.rejected, 0, str(plan.ctx.rejections))


func test_assegna_titoli_ai_generali_leali(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	var loyal := W.add_general(s, W.A, W.A2, 3, 9)
	var disloyal := W.add_general(s, W.A, W.A3, 3, 0)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	AiStaff.plan(plan)
	t.assert_true(loyal.title != "", "il leale governa una provincia")
	t.assert_eq(disloyal.title, "", "chi ha lealta' 0 no")
	t.assert_eq(plan.ctx.rejected, 0, str(plan.ctx.rejections))


# --- predoni, Orda, Papato, ribelli, giocatore --------------------------------------------------------


func test_il_predone_razzia_la_provincia_vicina(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.campaign.faction(W.B).behaviour = "BARBARIAN_RAIDER"
	_stack(s, W.B, W.B1, 80)
	W.put(s, W.A, W.A3, 30)
	var ctx := W.run_faction(s, W.B, _sure_rules())
	t.assert_eq(ctx.rejected, 0, str(ctx.rejections))
	t.assert_true(_heads_to(s, W.B, W.A3), "il predone attacca il vicino neutrale")


func test_l_orda_con_l_ia_attiva_la_guida_l_ia(t: TestContext) -> void:
	# senza IA la regola fissa dell'Orda manda l'esercito fermo contro la confinante piu' ricca; con l'IA no
	for ai_active in [false, true]:
		var s := W.world()
		W.clear_armies(s)
		s.rules.events.horde_faction = W.B
		s.rules.events.horde_years = 50
		s.horde = {"stato": "attiva", "arrivo": s.year, "ingresso": W.B1, "conquiste": 0, "senza_conquiste": 0}
		var army := W.put(s, W.B, W.B1, 100)
		s.ai_orders_horde = ai_active
		EventProcessor._horde(s, s.rules.events)
		if ai_active:
			t.assert_true(army.path.is_empty(), "con l'IA la regola fissa tace")
		else:
			t.assert_eq(army.path, PackedStringArray([W.A3]), "senza l'IA vale la regola fissa")


func test_il_flag_dell_orda_segue_l_ia(t: TestContext) -> void:
	var s := W.world()
	t.assert_false(s.ai_orders_horde)
	AiController.plan_year(s)
	t.assert_true(s.ai_orders_horde, "plan_year prende gli ordini dell'Orda")
	var s2 := W.world()
	CampaignTurn.advance(s2)
	t.assert_false(s2.ai_orders_horde, "advance li restituisce al fine anno")


func test_il_papato_non_attacca(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	var army := W.put(s, W.P, W.P1, 400)
	W.put(s, W.B, W.B2, 10)
	W.run_faction(s, W.P, _sure_rules())
	t.assert_true(army.path.is_empty())
	t.assert_eq(W.paths_of(s, W.P).size(), 0)


func test_i_ribelli_non_ricevono_ordini(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	var army := W.put(s, "FN_REBEL", W.R1, 400)
	W.put(s, W.A, W.A3, 10)
	var report := AiController.plan_year(s)
	t.assert_true(army.path.is_empty(), "ordini ai ribelli: nessuno")
	t.assert_eq(AiFaction.plan(W.context(s), "FN_REBEL"), "")
	t.assert_eq(int(report["rifiutati"]), 0, str(report["rifiuti"]))


func test_il_giocatore_non_riceve_ordini(t: TestContext) -> void:
	var s := W.world()
	s.faction(W.A).is_player = true
	W.set_treasury(s, W.A, 9000)
	W.enrich(s, W.A)
	var report := AiController.plan_year(s, "", null, true)
	t.assert_eq(int(report["fazioni"]), 3, "BETA, GAMMA e PAPIST; non il giocatore ne' i ribelli")
	t.assert_eq(W.queued_units(s, W.A), 0)
	t.assert_eq(W.queued_buildings(s, W.A), 0)
	t.assert_eq(W.paths_of(s, W.A).size(), 0)
	t.assert_eq(s.faction(W.A).treasury, 9000)
	for line in report["registro"]:
		t.assert_false(str(line).contains(" %s " % W.A), "nel registro non compare il giocatore: %s" % str(line))
	t.assert_eq(int(report["rifiutati"]), 0, str(report["rifiuti"]))


# --- determinismo e avanzamento ---------------------------------------------------------------------


func test_stesso_stato_stessi_ordini(t: TestContext) -> void:
	var first := W.world(11)
	var second := W.world(11)
	var report1 := AiController.plan_year(first)
	var report2 := AiController.plan_year(second)
	t.assert_eq(W.footprint(first), W.footprint(second), "stessi ordini")
	t.assert_eq(int(report1["ordini"]), int(report2["ordini"]))
	var third := W.world(12)
	AiController.plan_year(third)
	t.assert_eq(third.seed_value, 12)


func test_l_ia_non_tocca_il_generatore_della_partita(t: TestContext) -> void:
	var s := W.world(5)
	var before := s.rng.state
	AiController.plan_year(s)
	t.assert_eq(s.rng.state, before, "state.rng non si consuma")


func test_il_generatore_dipende_da_fazione_e_anno(t: TestContext) -> void:
	var s := W.world(5)
	var ctx := W.context(s)
	var a1 := ctx.rng_for(W.A).randi()
	var a2 := ctx.rng_for(W.A).randi()
	t.assert_eq(a1, a2, "stesso seme, stessa sequenza")
	t.assert_true(ctx.rng_for(W.B).randi() != a1, "un'altra fazione ha un'altra sequenza")
	s.year += 1
	t.assert_true(W.context(s).rng_for(W.A).randi() != a1, "un altro anno, un'altra sequenza")


func test_advance_e_l_ia_piu_il_fine_anno(t: TestContext) -> void:
	var manual := W.world(3)
	AiController.plan_year(manual)
	var expected := TurnProcessor.end_year(manual)
	manual.ai_orders_horde = false
	var auto := W.world(3)
	var result := CampaignTurn.advance(auto)
	t.assert_eq(str(result.keys()), str(expected.keys()), "stesso dizionario di ritorno")
	t.assert_eq(bool(result["ok"]), bool(expected["ok"]))
	t.assert_eq(int(result["anno"]), int(expected["anno"]))
	t.assert_eq(SaveGame.to_json(auto), SaveGame.to_json(manual), "stesso stato dopo l'anno")
	t.assert_eq(auto.year, 1001)
	t.assert_eq((result["errori"] as Array).size(), 0, str(result["errori"]))


func test_advance_a_partita_finita_non_pianifica(t: TestContext) -> void:
	var s := W.world(3)
	s.year = s.final_year
	s.victory.outcome = VictoryState.CAMPAIGN_END
	if not s.is_game_over():
		t.skip("la fine della campagna non si forza cosi'")
		return
	var result := CampaignTurn.advance(s)
	t.assert_false(bool(result["ok"]))
	t.assert_false(s.ai_orders_horde)


func test_pochi_anni_di_fila_senza_rifiuti(t: TestContext) -> void:
	var s := W.world(21)
	for i in 12:
		var report := AiController.plan_year(s)
		t.assert_eq(int(report["rifiutati"]), 0, "anno %d: %s" % [s.year, str(report["rifiuti"])])
		var result := TurnProcessor.end_year(s)
		s.ai_orders_horde = false
		t.assert_eq((result["errori"] as Array).size(), 0, str(result["errori"]))
		if s.is_game_over():
			break


# --- guarnigione volontaria (2026-11-09) ---------------------------------------------------------------


func test_senza_speranza_in_campo_si_barrica_nel_castello(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.declare_war(W.B, W.A)
	var weak := W.put(s, W.A, W.A2, 30)
	W.put(s, W.B, W.A3, 400)   # un grande esercito nemico gia' nella provincia accanto
	t.assert_true(Combat.castle_level(s, W.A2) > 0, "A2 ha un castello")
	var ctx := W.run_faction(s, W.A)
	t.assert_eq(ctx.rejected, 0, str(ctx.rejections))
	t.assert_true(weak.in_castle, "trenta uomini contro quattrocento: ci si chiude nel castello")
	t.assert_true(weak.path.is_empty())


func test_con_forze_pari_resta_in_campo(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.declare_war(W.B, W.A)
	var strong := W.put(s, W.A, W.A2, 300)
	W.put(s, W.B, W.A3, 250)
	W.run_faction(s, W.A)
	t.assert_false(strong.in_castle, "puo' vincere in campo: non si barrica")


func test_barricata_dell_ia_e_poi_assedio(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	s.declare_war(W.B, W.A)
	var weak := W.put(s, W.A, W.A2, 30)
	var big := W.put(s, W.B, W.A3, 400)
	W.run_faction(s, W.A)
	t.assert_true(weak.in_castle)
	big.path = PackedStringArray([W.A2])
	TurnProcessor.end_year(s)
	t.assert_true(s.is_besieged(W.A2), "il nemico arriva e assedia")
	t.assert_true(s.army(weak.id) != null and weak.in_castle, "la guarnigione resiste nel castello")


func test_assegna_le_cariche_vacanti(t: TestContext) -> void:
	var s := W.world()
	W.clear_armies(s)
	var o := CampaignData.OfficeDef.new()
	o.faction = W.A
	o.building = "royal_palace"
	o.display_name = "Cancelliere di Prova"
	o.loyalty = 2
	s.campaign.offices.append(o)
	var high := W.add_general(s, W.A, W.A2, 10, 5)
	var plan := W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	AiStaff.plan(plan)
	t.assert_true(DynastyProcessor.office_holder(s, W.A, "royal_palace") == null, "senza palazzo reale nessuna carica")
	s.province(W.A1).set_level("ROYAL_PALACE", 1)
	plan = W.plan_for(s, W.A, "CATHOLIC_EXPANSIONIST")
	AiStaff.plan(plan)
	t.assert_true(DynastyProcessor.office_holder(s, W.A, "royal_palace") == high, "la carica va al comandante migliore")
	t.assert_eq(plan.ctx.rejected, 0, str(plan.ctx.rejections))
