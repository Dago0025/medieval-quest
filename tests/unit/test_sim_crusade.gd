extends RefCounted
## Test delle crociate e dei jihad (fase 5c): reclutamento, nascita dell'esercito crociato, bersagli e comandi,
## movimento in transito, zelo, reclutamento per zelo, esito, salvataggi. Mondo di prova: vedi papacy_world.gd.
## I calcoli a mano usano i parametri predefiniti (uguali a papato.cfg).

const W := preload("res://tests/unit/papacy_world.gd")
const CRUSADE := PapacyProcessor.KIND_CRUSADE
const JIHAD := PapacyProcessor.KIND_JIHAD


func _units_of(a: Army) -> Array[String]:
	var out: Array[String] = []
	for st in a.stacks:
		out.append(st.unit_id.to_upper())
	return out


func _crusade_army(s: GameState, faction_id: String) -> Army:
	for a in s.armies_of(faction_id):
		if a.is_crusade():
			return a
	return null


func _restore(data: Dictionary) -> GameState:
	var campaign := StartposLoader.load_file(W.STARTPOS)
	var units := UnitProdLoader.load_file(W.UNITS)
	var buildings := BuildingProdLoader.load_file(W.BUILDINGS)
	var r := SaveGame.from_dict(data, campaign, units, buildings, W.quiet_rules())
	return r["stato"]


## Mondo con una crociata di ALPHA a NORD1 (4 pile di Spearmen) e l'influenza del capo a 5; una sola chiamata di
## `PapacyProcessor.process_year` per volta (niente fine anno).
## Zelo di tutte le province alla soglia del reclutamento per zelo (ADR-072: dalla soglia 40 lo zelo normale 50 recluta),
## per i test che non provano il reclutamento.
func _flat_zeal(s: GameState) -> void:
	for p in s.provinces:
		p.zeal = s.rules.papacy.recruit_zeal_threshold


func _crusade_world(zeal: int, target: String = "", kind: String = CRUSADE) -> Dictionary:
	var s := W.world()
	_flat_zeal(s)
	var owner_id := W.A if kind == CRUSADE else W.B
	var region := W.NORD3 if kind == CRUSADE else W.SUD2
	var army := W.add_crusade(s, owner_id, region, kind, target)
	army.crusade["zelo"] = zeal
	var leader := W.set_influence(s, owner_id, 5)
	return {"stato": s, "esercito": army, "capo": leader}


# --- reclutamento -----------------------------------------------------------------------------------


func test_condizioni_per_reclutare_una_crociata(t: TestContext) -> void:
	var s := W.world()
	var check := GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")
	t.assert_true(bool(check["ok"]), str(check["errore"]))
	t.assert_eq(check["costo"], 1000)
	t.assert_eq(check["anni"], 4)
	var no_house := GameCommands.can_queue_unit(s, W.G, W.EST, "Crusade")
	t.assert_false(bool(no_house["ok"]), "GAMMA e' cattolica ma a EST manca la Chapter House")
	t.assert_true(str(no_house["errore"]).find("Requisiti") >= 0, str(no_house["errore"]))
	var muslim := GameCommands.can_queue_unit(s, W.B, W.SUD1, "Crusade")
	t.assert_false(bool(muslim["ok"]), "i musulmani non bandiscono crociate")
	t.assert_true(str(muslim["errore"]).find("cattolici") >= 0, str(muslim["errore"]))
	t.assert_false(bool(GameCommands.can_queue_unit(s, W.A, W.NORD2, "Crusade")["ok"]), "NORD2 non ha la Chapter House")
	s.faction(W.A).treasury = 999
	t.assert_false(bool(GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")["ok"]), "mille denari")


func test_condizioni_per_reclutare_un_jihad(t: TestContext) -> void:
	var s := W.world()
	var check := GameCommands.can_queue_unit(s, W.B, W.SUD1, "Jihad")
	t.assert_true(bool(check["ok"]), str(check["errore"]))
	t.assert_eq(check["costo"], 500)
	t.assert_eq(check["anni"], 2)
	var catholic := GameCommands.can_queue_unit(s, W.A, W.NORD1, "Jihad")
	t.assert_false(bool(catholic["ok"]), "il jihad e' dei musulmani")
	t.assert_false(bool(GameCommands.can_queue_unit(s, W.B, W.SUD2, "Jihad")["ok"]), "SUD2 non ha il Ribat")
	# piu' jihad ammessi, anche in coda e attivi insieme
	t.assert_true(bool(GameCommands.queue_unit(s, W.B, W.SUD1, "Jihad")["ok"]))
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.B, W.SUD1, "Jihad")["ok"]), "un secondo jihad in coda")
	W.add_crusade(s, W.B, W.SUD2, JIHAD)
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.B, W.SUD1, "Jihad")["ok"]), "e con un jihad attivo")


func test_una_sola_crociata_per_fazione(t: TestContext) -> void:
	var s := W.world()
	t.assert_true(bool(GameCommands.queue_unit(s, W.A, W.NORD1, "Crusade")["ok"]))
	var second := GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")
	t.assert_false(bool(second["ok"]), "una crociata e' gia' in coda")
	t.assert_true(str(second["errore"]).find("in coda") >= 0, str(second["errore"]))
	GameCommands.cancel_queue_item(s, W.A, W.NORD1, GameCommands.QUEUE_UNIT, 0)
	t.assert_true(bool(GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")["ok"]), "annullata, si puo' di nuovo")
	W.add_crusade(s, W.A, W.NORD2)
	var active := GameCommands.can_queue_unit(s, W.A, W.NORD1, "Crusade")
	t.assert_false(bool(active["ok"]), "una crociata e' attiva")
	t.assert_true(str(active["errore"]).find("attiva") >= 0, str(active["errore"]))


func test_nasce_l_esercito_crociato(t: TestContext) -> void:
	var s := W.world()
	t.assert_true(bool(GameCommands.queue_unit(s, W.A, W.NORD1, "Crusade")["ok"]))
	t.assert_eq(s.faction(W.A).treasury, 4000)
	for i in 3:
		TurnProcessor.end_year(s)
		t.assert_true(_crusade_army(s, W.A) == null, "anno %d: non ancora" % (i + 1))
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0, "nessun errore")
	var army := _crusade_army(s, W.A)
	t.assert_true(army != null, "dopo quattro anni la crociata parte")
	t.assert_eq(army.region, W.NORD1)
	t.assert_eq(army.crusade_kind(), CRUSADE)
	t.assert_eq(int(army.crusade["zelo"]), 80)
	# bersaglio scelto alla partenza (Federico, 22/11/2026: l'avviso dice anche dove e' diretta)
	t.assert_eq(army.crusade_target(), PapacyProcessor.initial_target(s, army), "bersaglio alla partenza")
	t.assert_true(army.crusade_target() != "", "c'e' un bersaglio valido vicino")
	t.assert_eq(str(army.crusade["annunciato"]), army.crusade_target(), "annunciato con la partenza, non di nuovo")
	t.assert_eq(army.crusade["anno"], 1003)
	t.assert_eq(_units_of(army), ["TEMPLARS", "HOSPITALLERS", "CHEVALIERS", "HALBERDIERS"], "le quattro migliori truppe reclutabili, senza artiglieria")
	var events := W.events_of(s, GameState.EV_CRUSADE_LAUNCHED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["fazione"], W.A)
	t.assert_eq(events[0]["genere"], CRUSADE)
	t.assert_eq(events[0]["esercito"], army.id)
	t.assert_eq(events[0]["pile"], 4)
	t.assert_eq(events[0]["zelo"], 80)
	t.assert_eq(events[0]["provincia"], W.NORD1)
	t.assert_eq(events[0]["bersaglio"], army.crusade_target())
	t.assert_true(str(events[0]["testo"]).contains(", diretta a "), str(events[0]["testo"]))
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_TARGET).size(), 0, "nessun secondo annuncio del bersaglio")
	W.check_state(t, s, "dopo la partenza")
	# raggio 0: nessun bersaglio alla partenza (regola di prima)
	s.rules.papacy.initial_target_radius = 0
	t.assert_eq(PapacyProcessor.initial_target(s, army), "")
	var info := GameCommands.papal_status(s, W.A)
	t.assert_eq(info["crociata"], army.id)


func test_nasce_il_jihad(t: TestContext) -> void:
	var s := W.world()
	t.assert_true(bool(GameCommands.queue_unit(s, W.B, W.SUD1, "Jihad")["ok"]))
	TurnProcessor.end_year(s)
	t.assert_true(_crusade_army(s, W.B) == null)
	TurnProcessor.end_year(s)
	var army := _crusade_army(s, W.B)
	t.assert_true(army != null, "dopo due anni il jihad parte")
	t.assert_eq(army.crusade_kind(), JIHAD)
	t.assert_eq(_units_of(army), ["NIZARI", "HALBERDIERS", "SPEARMEN", "NIZARI"], "tre truppe reclutabili, in giro")
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_LAUNCHED)[0]["genere"], JIHAD)
	W.check_state(t, s, "dopo la partenza del jihad")


func test_la_scomunica_in_coda_rimborsa_e_la_nascita_si_ferma(t: TestContext) -> void:
	var s := W.world()
	GameCommands.queue_unit(s, W.A, W.NORD1, "Crusade")
	TurnProcessor.end_year(s)
	PapacyProcessor.excommunicate(s, W.A, "x")
	t.assert_eq(s.faction(W.A).treasury, 5000 + int(s.faction(W.A).last_income["netto"]), "rimborsati i mille denari")
	for i in 5:
		TurnProcessor.end_year(s)
	t.assert_true(_crusade_army(s, W.A) == null, "nessuna crociata")
	# un ultimo controllo alla nascita: la fazione scomunicata nel frattempo non fa nascere nulla e viene rimborsata
	var p := s.province(W.NORD1)
	p.unit_queue.append(QueueItem.new(QueueItem.KIND_UNIT, "Crusade", 0, 1, 1000))
	var before := s.faction(W.A).treasury
	var errors: Array[String] = []
	TurnProcessor._advance_recruitment(s, errors)
	t.assert_true(_crusade_army(s, W.A) == null)
	t.assert_eq(s.faction(W.A).treasury, before + 1000)
	t.assert_eq(errors.size(), 0)


# --- bersagli e comandi ---------------------------------------------------------------------------------


func test_i_bersagli_di_una_crociata(t: TestContext) -> void:
	var s := W.world()
	var army := W.add_crusade(s, W.A, W.NORD1)
	var r := GameCommands.crusade_targets(s, W.A, army.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(r["genere"], CRUSADE)
	t.assert_eq(r["bersaglio"], "")
	t.assert_eq(r["zelo"], 80)
	var ids: Array[String] = []
	var reasons := {}
	for item in r["bersagli"]:
		var d: Dictionary = item
		ids.append(str(d["regione"]))
		reasons[str(d["regione"])] = str(d["motivo"])
		t.assert_true(str(d["nome"]) != "")
	t.assert_eq(ids, [W.SUD1, W.SUD2, W.RIBELLE], "non cattolici e ribelli, nell'ordine delle province")
	t.assert_eq(reasons[W.SUD1], "non_cattolico")
	t.assert_eq(reasons[W.RIBELLE], "ribelle")
	# uno scomunicato diventa un bersaglio
	PapacyProcessor.excommunicate(s, W.G, "x")
	var again := GameCommands.crusade_targets(s, W.A, army.id)["bersagli"] as Array
	t.assert_eq(again.size(), 4)
	t.assert_eq(again[0]["regione"], W.EST)
	t.assert_eq(again[0]["motivo"], "scomunicato")
	t.assert_eq(again[0]["proprietario"], W.G)
	# una provincia a maggioranza eretica di un cattolico pure
	s.province(W.DELTA1).religions = ProvinceState.normalize_religions({"HERETIC": 100.0})
	var heretic := GameCommands.crusade_targets(s, W.A, army.id)["bersagli"] as Array
	t.assert_eq(heretic.size(), 5)
	t.assert_eq(heretic[1]["regione"], W.DELTA1)
	t.assert_eq(heretic[1]["motivo"], "eretici")
	# ma mai il Papato
	s.province(W.ROMA).religions = ProvinceState.normalize_religions({"HERETIC": 100.0})
	t.assert_eq((GameCommands.crusade_targets(s, W.A, army.id)["bersagli"] as Array).size(), 5, "il Papato no")
	# ne' alleati ne' fazioni in tregua
	s.form_alliance(W.A, W.B)
	t.assert_eq((GameCommands.crusade_targets(s, W.A, army.id)["bersagli"] as Array).size(), 3, "BETA e' alleata: SUD1 e SUD2 escono")
	s.break_alliance(W.A, W.B)
	s.make_truce(W.A, W.B, 1010)
	t.assert_eq((GameCommands.crusade_targets(s, W.A, army.id)["bersagli"] as Array).size(), 3, "tregua: idem")


func test_i_bersagli_di_un_jihad(t: TestContext) -> void:
	var s := W.world()
	var army := W.add_crusade(s, W.B, W.SUD1, JIHAD)
	var r := GameCommands.crusade_targets(s, W.B, army.id)
	t.assert_true(bool(r["ok"]))
	t.assert_eq((r["bersagli"] as Array).size(), 0, "nessuna provincia musulmana in mani altrui")
	s.province(W.SUD2).owner = W.D    # SUD2 e' a maggioranza musulmana ma di DELTA
	var one := GameCommands.crusade_targets(s, W.B, army.id)["bersagli"] as Array
	t.assert_eq(one.size(), 1)
	t.assert_eq(one[0]["regione"], W.SUD2)
	t.assert_eq(one[0]["motivo"], "musulmana")
	# una provincia ribelle che era musulmana
	s.province(W.RIBELLE).former_owner = W.B
	var two := GameCommands.crusade_targets(s, W.B, army.id)["bersagli"] as Array
	t.assert_eq(two.size(), 2)
	t.assert_eq(two[1]["regione"], W.RIBELLE)
	# un alleato non si attacca
	s.form_alliance(W.B, W.D)
	t.assert_eq((GameCommands.crusade_targets(s, W.B, army.id)["bersagli"] as Array).size(), 1)
	# le province cattoliche non sono bersagli del jihad, nemmeno degli scomunicati
	PapacyProcessor.excommunicate(s, W.G, "x")
	for item in GameCommands.crusade_targets(s, W.B, army.id)["bersagli"]:
		t.assert_true(item["regione"] != W.EST)


func test_set_crusade_target(t: TestContext) -> void:
	var s := W.world()
	var army := W.add_crusade(s, W.A, W.NORD1)
	var r := GameCommands.set_crusade_target(s, W.A, army.id, "id_sud1")
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(r["bersaglio"], W.SUD1, "id normalizzato")
	t.assert_eq(r["genere"], CRUSADE)
	t.assert_eq(r["proprietario"], W.B)
	t.assert_eq(r["percorso"], [W.NORD2, W.SUD1], "percorso piu' corto per terra")
	t.assert_eq(army.path, PackedStringArray([W.NORD2, W.SUD1]))
	t.assert_eq(army.crusade_target(), W.SUD1)
	# con un ordine di movimento gia' dato il percorso non cambia
	var r2 := GameCommands.set_crusade_target(s, W.A, army.id, W.SUD2)
	t.assert_true(bool(r2["ok"]))
	t.assert_eq(r2["percorso"], [])
	t.assert_eq(army.path, PackedStringArray([W.NORD2, W.SUD1]))
	t.assert_eq(army.crusade_target(), W.SUD2)
	# tolto
	var r3 := GameCommands.set_crusade_target(s, W.A, army.id, "")
	t.assert_true(bool(r3["ok"]))
	t.assert_eq(army.crusade_target(), "")
	t.assert_eq(r3["bersaglio"], "")


func test_set_crusade_target_rifiuta_i_bersagli_non_validi(t: TestContext) -> void:
	var s := W.world()
	var army := W.add_crusade(s, W.A, W.NORD1)
	for region_id in [W.EST, W.NORD2, W.ROMA, W.DELTA1, "ID_NON_ESISTE"]:
		var r := GameCommands.set_crusade_target(s, W.A, army.id, region_id)
		t.assert_false(bool(r["ok"]), "%s non e' un bersaglio" % region_id)
		t.assert_true(str(r["errore"]) != "")
	t.assert_eq(army.crusade_target(), "", "nessun bersaglio impostato")
	t.assert_true(army.path.is_empty())
	# non e' un esercito crociato / non e' tuo / non esiste
	var normal := W.land_army(s, W.A, W.NORD2)
	t.assert_false(bool(GameCommands.set_crusade_target(s, W.A, normal.id, W.SUD1)["ok"]))
	t.assert_false(bool(GameCommands.set_crusade_target(s, W.G, army.id, W.SUD1)["ok"]))
	t.assert_false(bool(GameCommands.set_crusade_target(s, W.A, 9999, W.SUD1)["ok"]))
	t.assert_false(bool(GameCommands.crusade_targets(s, W.A, normal.id)["ok"]))
	# alleato
	s.form_alliance(W.A, W.B)
	var allied := GameCommands.set_crusade_target(s, W.A, army.id, W.SUD1)
	t.assert_false(bool(allied["ok"]))
	t.assert_true(str(allied["errore"]).find("alleanza") >= 0, str(allied["errore"]))


func test_percorsi_per_terra(t: TestContext) -> void:
	var s := W.world()
	t.assert_eq(PapacyProcessor.land_route(s, W.NORD1, W.DELTA1), PackedStringArray([W.EST, W.DELTA1]))
	t.assert_eq(PapacyProcessor.land_route(s, W.ROMA, W.SUD2), PackedStringArray([W.NORD1, W.NORD2, W.SUD1, W.SUD2]))
	t.assert_true(PapacyProcessor.land_route(s, W.NORD1, W.NORD1).is_empty(), "gia' li'")
	t.assert_true(PapacyProcessor.land_route(s, W.NORD1, "ID_NON_ESISTE").is_empty())


# --- movimento --------------------------------------------------------------------------------------------


func test_la_crociata_attraversa_senza_guerra_e_conquista_il_bersaglio(t: TestContext) -> void:
	var s := W.world()
	s.rules.papacy.recruit_zeal_threshold = 100   # niente reclutamento per zelo (lo zelo torna a 50 a fine anno)
	PapacyProcessor.excommunicate(s, W.D, "attacco_al_papato")
	W.remove_armies(s, W.D)
	var army := W.add_crusade(s, W.A, W.NORD1)
	W.set_influence(s, W.A, 5)
	var r := GameCommands.set_crusade_target(s, W.A, army.id, W.DELTA1)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(r["percorso"], [W.EST, W.DELTA1])
	# anno 1000: in transito per EST (di GAMMA, cattolica non scomunicata)
	TurnProcessor.end_year(s)
	t.assert_eq(army.region, W.EST)
	t.assert_false(s.at_war(W.A, W.G), "nessuna guerra con chi si attraversa")
	t.assert_eq(W.events_of(s, GameState.EV_WAR_DECLARED).size(), 0)
	t.assert_eq(s.province(W.EST).owner, W.G, "e nessuna conquista")
	t.assert_false(s.faction(W.A).excommunicated)
	t.assert_true(s.papal_warnings.is_empty())
	t.assert_eq(int(army.crusade["zelo"]), 75)
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_TARGET).size(), 1, "il bersaglio e' annunciato nel fine anno")
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_TARGET)[0]["bersaglio"], W.DELTA1)
	# anno 1001: entra nel bersaglio, dichiara guerra al suo proprietario e lo conquista
	var influence := s.leader_of(W.A).influence
	TurnProcessor.end_year(s)
	t.assert_eq(s.province(W.DELTA1).owner, W.A, "conquistata")
	var wars := W.events_of(s, GameState.EV_WAR_DECLARED)
	t.assert_eq(wars.size(), 1)
	t.assert_eq(wars[0]["contro"], W.D)
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_WARNING).size(), 0, "la crociata e' esente dall'avvertimento")
	t.assert_false(s.faction(W.A).excommunicated)
	t.assert_true(army.crusade.is_empty(), "l'esercito torna normale")
	var done := W.events_of(s, GameState.EV_CRUSADE_SUCCEEDED)
	t.assert_eq(done.size(), 1)
	t.assert_eq(done[0]["bersaglio"], W.DELTA1)
	t.assert_eq(done[0]["genere"], CRUSADE)
	t.assert_eq(done[0]["influenza"], 1)
	t.assert_eq(done[0]["pile_ordine"], 2)
	t.assert_eq(done[0]["unita_ordine"].to_upper(), "TEMPLARS")
	t.assert_true(s.leader_of(W.A).influence >= influence, "influenza +1 (e quella delle province conquistate)")
	t.assert_eq(army.stacks.size(), 6, "4 pile piu' 2 di un ordine militare")
	t.assert_eq(_units_of(army).slice(4), ["TEMPLARS", "HOSPITALLERS"])
	W.check_state(t, s, "dopo la conquista")


func test_una_crociata_non_conquista_le_province_attraversate(t: TestContext) -> void:
	var s := W.world()
	s.declare_war(W.A, W.G)
	W.remove_armies(s, W.G)
	var army := W.add_crusade(s, W.A, W.NORD1)
	GameCommands.set_crusade_target(s, W.A, army.id, W.RIBELLE)
	t.assert_eq(army.path, PackedStringArray([W.EST, W.RIBELLE]))
	TurnProcessor.end_year(s)
	t.assert_eq(army.region, W.EST)
	t.assert_eq(s.province(W.EST).owner, W.G, "in guerra e senza difensori, ma la crociata non conquista in transito")
	# lo stesso esercito, non crociato, conquista
	var s2 := W.world()
	s2.declare_war(W.A, W.G)
	W.remove_armies(s2, W.G)
	var normal := s2.create_army(W.A, W.NORD1, false)
	normal.stacks.append(UnitStack.new("Spearmen", 50, 0))
	GameCommands.order_move(s2, W.A, normal.id, PackedStringArray([W.EST]))
	TurnProcessor.end_year(s2)
	t.assert_eq(s2.province(W.EST).owner, W.A, "un esercito normale conquista")


func test_un_esercito_normale_nella_stessa_mossa_viene_ammonito(t: TestContext) -> void:
	# stessa mossa della crociata, ma di un esercito normale: avvertimento
	var s := W.world()
	var normal := s.create_army(W.A, W.NORD1, false)
	normal.stacks.append(UnitStack.new("Spearmen", 50, 0))
	GameCommands.order_move(s, W.A, normal.id, PackedStringArray([W.EST]))
	TurnProcessor.end_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_PAPAL_WARNING).size(), 1)


func test_il_bersaglio_che_cade_viene_tolto(t: TestContext) -> void:
	var s := W.world()
	var army := W.add_crusade(s, W.A, W.NORD1)
	GameCommands.set_crusade_target(s, W.A, army.id, W.SUD1)
	PapacyProcessor.process_year(s)
	var announced := W.events_of(s, GameState.EV_CRUSADE_TARGET)
	t.assert_eq(announced.size(), 1)
	t.assert_eq(announced[0]["bersaglio"], W.SUD1)
	t.assert_eq(announced[0]["proprietario"], W.B)
	t.assert_eq(announced[0]["esercito"], army.id)
	s.events.clear()
	PapacyProcessor.process_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_TARGET).size(), 0, "annunciato una volta sola")
	# BETA diventa alleata: il bersaglio non e' piu' valido
	s.form_alliance(W.A, W.B)
	PapacyProcessor.process_year(s)
	t.assert_eq(army.crusade_target(), "")
	var cleared := W.events_of(s, GameState.EV_CRUSADE_TARGET)
	t.assert_eq(cleared.size(), 1)
	t.assert_eq(cleared[0]["bersaglio"], "")
	t.assert_true(str(cleared[0]["motivo"]) != "")


# --- zelo ------------------------------------------------------------------------------------------------------


func test_lo_zelo_cala_ogni_anno(t: TestContext) -> void:
	var w := _crusade_world(80, W.SUD1)
	var s: GameState = w["stato"]
	var army: Army = w["esercito"]
	PapacyProcessor.process_year(s)
	t.assert_eq(int(army.crusade["zelo"]), 75, "-5 all'anno")
	PapacyProcessor.process_year(s)
	t.assert_eq(int(army.crusade["zelo"]), 70)
	t.assert_eq(army.stacks.size(), 4, "nessuna perdita sopra 40")
	# senza bersaglio -10 in piu'
	var other := _crusade_world(80)
	var s2: GameState = other["stato"]
	var army2: Army = other["esercito"]
	PapacyProcessor.process_year(s2)
	t.assert_eq(int(army2.crusade["zelo"]), 65, "-5 e -10 senza bersaglio")


func test_sotto_40_si_perde_una_pila(t: TestContext) -> void:
	for start in [44, 35]:
		var w := _crusade_world(start, W.SUD1)
		var s: GameState = w["stato"]
		var army: Army = w["esercito"]
		PapacyProcessor.process_year(s)
		t.assert_eq(army.stacks.size(), 3, "zelo %d -> %d: una pila" % [start, start - 5])
		var ev := W.events_of(s, GameState.EV_CRUSADE_DESERTION)
		t.assert_eq(ev.size(), 1)
		t.assert_eq(ev[0]["pile"], 1)
		t.assert_eq(ev[0]["motivo"], "perdite")
		t.assert_eq(ev[0]["zelo"], start - 5)
		t.assert_eq(ev[0]["genere"], CRUSADE)


func test_sotto_30_diserzioni(t: TestContext) -> void:
	var w := _crusade_world(34, W.SUD1)
	var s: GameState = w["stato"]
	var army: Army = w["esercito"]
	PapacyProcessor.process_year(s)
	t.assert_eq(army.stacks.size(), 2, "due pile disertano")
	var ev := W.events_of(s, GameState.EV_CRUSADE_DESERTION)
	t.assert_eq(ev[0]["pile"], 2)
	t.assert_eq(ev[0]["motivo"], "diserzione")
	t.assert_eq(ev[0]["zelo"], 29)


func test_a_zelo_20_la_crociata_si_scioglie(t: TestContext) -> void:
	var w := _crusade_world(25, W.SUD1)
	var s: GameState = w["stato"]
	var army: Army = w["esercito"]
	var leader: Character = w["capo"]
	PapacyProcessor.process_year(s)
	t.assert_true(s.army(army.id) == null, "l'esercito e' sciolto")
	var ev := W.events_of(s, GameState.EV_CRUSADE_FAILED)
	t.assert_eq(ev.size(), 1)
	t.assert_eq(ev[0]["motivo"], "scioglimento")
	t.assert_eq(ev[0]["genere"], CRUSADE)
	t.assert_eq(ev[0]["influenza"], -1)
	t.assert_eq(leader.influence, 4)
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_DESERTION).size(), 0)


func test_il_jihad_fallito_costa_due_di_influenza(t: TestContext) -> void:
	var w := _crusade_world(25, "", JIHAD)
	var s: GameState = w["stato"]
	var army: Army = w["esercito"]
	var leader: Character = w["capo"]
	PapacyProcessor.process_year(s)
	t.assert_true(s.army(army.id) == null)
	var ev := W.events_of(s, GameState.EV_CRUSADE_FAILED)
	t.assert_eq(ev[0]["genere"], JIHAD)
	t.assert_eq(ev[0]["influenza"], -2)
	t.assert_eq(leader.influence, 3)


func test_l_esercito_distrutto_e_un_fallimento(t: TestContext) -> void:
	var w := _crusade_world(80, W.SUD1)
	var s: GameState = w["stato"]
	var army: Army = w["esercito"]
	var leader: Character = w["capo"]
	PapacyProcessor.snapshot(s)
	var id := army.id
	s.remove_army(army)    # sconfitto e catturato nel corso dell'anno
	PapacyProcessor.process_year(s)
	var ev := W.events_of(s, GameState.EV_CRUSADE_FAILED)
	t.assert_eq(ev.size(), 1)
	t.assert_eq(ev[0]["motivo"], "distrutto")
	t.assert_eq(ev[0]["esercito"], id)
	t.assert_eq(ev[0]["fazione"], W.A)
	t.assert_eq(ev[0]["influenza"], -1)
	t.assert_eq(leader.influence, 4)
	s.events.clear()
	PapacyProcessor.process_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_FAILED).size(), 0, "la fotografia si consuma")


func test_l_esercito_passato_ad_altri_non_e_piu_una_crociata(t: TestContext) -> void:
	var w := _crusade_world(80, W.SUD1)
	var s: GameState = w["stato"]
	var army: Army = w["esercito"]
	PapacyProcessor.snapshot(s)
	army.faction = GameState.REBEL    # per esempio una guerra civile
	PapacyProcessor.process_year(s)
	t.assert_true(army.crusade.is_empty())
	var ev := W.events_of(s, GameState.EV_CRUSADE_FAILED)
	t.assert_eq(ev[0]["motivo"], "perso")
	t.assert_eq(ev[0]["fazione"], W.A)
	# un esercito crociato dei ribelli non nato da una fotografia viene comunque ripulito
	var stray := W.add_crusade(s, GameState.REBEL, W.RIBELLE)
	PapacyProcessor.process_year(s)
	t.assert_true(stray.crusade.is_empty())


func test_un_esercito_senza_pile_e_un_fallimento(t: TestContext) -> void:
	var w := _crusade_world(34, W.SUD1)
	var s: GameState = w["stato"]
	var army: Army = w["esercito"]
	army.stacks.resize(1)
	PapacyProcessor.process_year(s)
	t.assert_true(s.army(army.id) == null, "l'ultima pila diserta e l'esercito sparisce")
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_FAILED)[0]["motivo"], "senza_pile")


# --- reclutamento per zelo ---------------------------------------------------------------------------------


func test_in_una_provincia_cattolica_di_zelo_alto_si_recluta(t: TestContext) -> void:
	var s := W.world()
	var army := W.add_crusade(s, W.A, W.NORD1, CRUSADE, W.SUD1)
	s.province(W.NORD1).zeal = 70
	PapacyProcessor.process_year(s)
	t.assert_eq(army.stacks.size(), 6, "+2 pile")
	t.assert_eq(_units_of(army).slice(4), ["TEMPLARS", "HOSPITALLERS"], "le migliori reclutabili a NORD1")
	var ev := W.events_of(s, GameState.EV_CRUSADE_RECRUITED)
	t.assert_eq(ev.size(), 1)
	t.assert_eq(ev[0]["provincia"], W.NORD1)
	t.assert_eq(ev[0]["pile"], 2)
	t.assert_eq(ev[0]["zelo_provincia"], 70)
	t.assert_eq(ev[0]["genere"], CRUSADE)
	t.assert_eq(army.crusade["reclutate"], [W.NORD1])
	s.events.clear()
	PapacyProcessor.process_year(s)
	t.assert_eq(army.stacks.size(), 6, "una volta sola per provincia")
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_RECRUITED).size(), 0)


func test_il_reclutamento_per_zelo_ha_le_sue_condizioni(t: TestContext) -> void:
	var s := W.world()
	var army := W.add_crusade(s, W.A, W.NORD2, CRUSADE, W.SUD1)
	s.province(W.NORD2).zeal = 40
	PapacyProcessor.process_year(s)
	t.assert_eq(army.stacks.size(), 4, "lo zelo deve superare 40")
	s.province(W.NORD2).zeal = 90
	s.province(W.NORD2).religions = ProvinceState.normalize_religions({"CATHOLIC": 40.0, "PAGAN": 60.0})
	PapacyProcessor.process_year(s)
	t.assert_eq(army.stacks.size(), 4, "la provincia deve essere a maggioranza della religione giusta")
	s.province(W.NORD2).religions = ProvinceState.normalize_religions({"CATHOLIC": 100.0})
	while army.stacks.size() < 31:
		army.stacks.append(UnitStack.new("Spearmen", 50, 0))
	PapacyProcessor.process_year(s)
	t.assert_eq(army.stacks.size(), 32, "al massimo 32 pile (ADR-072)")
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_RECRUITED)[0]["pile"], 1)


func test_la_crociata_supera_il_limite_degli_eserciti_normali(t: TestContext) -> void:
	# ADR-072 (Federico, dal gioco originale): passando in terre della sua religione assorbe molte piu' unita'
	var s := W.world()
	var army := W.add_crusade(s, W.A, W.NORD1, CRUSADE, W.SUD1, 18)
	s.province(W.NORD1).zeal = 100
	PapacyProcessor.process_year(s)
	t.assert_eq(army.stacks.size(), 22, "zelo 100: +4, oltre le 20 pile")
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_RECRUITED)[0]["pile"], 4)
	t.assert_true(s.rules.max_stacks < army.stacks.size(), "gli eserciti normali restano a 20")
	W.check_state(t, s, "crociata grande")


func test_il_jihad_recluta_in_province_musulmane(t: TestContext) -> void:
	var s := W.world()
	var jihad := W.add_crusade(s, W.B, W.SUD1, JIHAD)
	s.province(W.SUD1).zeal = 75
	PapacyProcessor.process_year(s)
	t.assert_eq(jihad.stacks.size(), 7, "zelo 75: 3 pile")
	var cath := W.add_crusade(s, W.B, W.NORD2, JIHAD)    # in una provincia cattolica non recluta
	s.province(W.NORD2).zeal = 90
	PapacyProcessor.process_year(s)
	t.assert_eq(cath.stacks.size(), 4)


# --- esito ---------------------------------------------------------------------------------------------------------


func test_il_jihad_riuscito(t: TestContext) -> void:
	var s := W.world()
	s.province(W.SUD2).owner = W.D
	var jihad := W.add_crusade(s, W.B, W.SUD1, JIHAD, W.SUD2)
	var leader := W.set_influence(s, W.B, 5)
	s.province(W.SUD2).owner = W.B    # riconquistata
	PapacyProcessor.process_year(s)
	t.assert_true(jihad.crusade.is_empty())
	t.assert_eq(leader.influence, 6, "+1")
	var ev := W.events_of(s, GameState.EV_CRUSADE_SUCCEEDED)
	t.assert_eq(ev.size(), 1)
	t.assert_eq(ev[0]["genere"], JIHAD)
	t.assert_eq(ev[0]["pile_ordine"], 0, "il jihad non ha ricompensa di pile")
	t.assert_eq(jihad.stacks.size(), 4)


func test_la_ricompensa_non_supera_il_limite_di_pile(t: TestContext) -> void:
	var s := W.world()
	var army := W.add_crusade(s, W.A, W.NORD1, CRUSADE, W.SUD1, 31)
	s.province(W.SUD1).owner = W.A
	PapacyProcessor.process_year(s)
	t.assert_eq(army.stacks.size(), 32)
	t.assert_eq(W.events_of(s, GameState.EV_CRUSADE_SUCCEEDED)[0]["pile_ordine"], 1)


func test_gli_ordini_militari_della_ricompensa(t: TestContext) -> void:
	var s := W.world()
	var alpha: Array[String] = []
	for u in PapacyProcessor.order_units(s, W.A):
		alpha.append(u.id.to_upper())
	t.assert_eq(alpha, ["TEMPLARS", "HOSPITALLERS"], "con CHAPTER_HOUSE nei requisiti, per costo")
	var delta: Array[String] = []
	for u in PapacyProcessor.order_units(s, W.D):
		delta.append(u.id.to_upper())
	t.assert_eq(delta, ["TEMPLARS"], "gli Ospitalieri sono di ALPHA e GAMMA")
	var army := W.add_crusade(s, W.D, W.DELTA1, CRUSADE, W.SUD1)
	s.province(W.SUD1).owner = W.D
	PapacyProcessor.process_year(s)
	t.assert_eq(_units_of(army).slice(4), ["TEMPLARS", "TEMPLARS"], "due pile dello stesso ordine")


# --- altre regole ------------------------------------------------------------------------------------------------------


func test_un_esercito_crociato_non_si_corrompe(t: TestContext) -> void:
	var s := W.world()
	var army := W.add_crusade(s, W.A, W.NORD1)
	var reason := AgentMissions.bribe_problem(s, W.B, army)
	t.assert_true(reason.find("crociato") >= 0, reason)
	t.assert_false(bool(GameCommands.bribe_price(s, army.id)["corruttibile"]))
	var normal := W.land_army(s, W.A, W.NORD2)
	t.assert_eq(AgentMissions.bribe_problem(s, W.B, normal), "", "gli altri si")


func test_le_truppe_nuove_non_entrano_nell_esercito_crociato(t: TestContext) -> void:
	var s := W.world()
	s.rules.papacy.recruit_zeal_threshold = 100   # niente reclutamento per zelo (lo zelo torna a 50 a fine anno)
	s.remove_army(W.land_army(s, W.A, W.NORD1))    # la guarnigione normale non c'e'
	var crusade := W.add_crusade(s, W.A, W.NORD1)
	GameCommands.queue_unit(s, W.A, W.NORD1, "Spearmen")
	TurnProcessor.end_year(s)
	t.assert_eq(crusade.stacks.size(), 4, "l'esercito crociato non assorbe le truppe nuove")
	var fresh := 0
	for a in s.armies_in(W.NORD1):
		if a.faction == W.A and not a.is_crusade():
			fresh += a.stacks.size()
	t.assert_eq(fresh, 1)


func test_ogni_esercito_crociato_ha_un_comandante(t: TestContext) -> void:
	var s := W.world()
	var crusade := W.add_crusade(s, W.A, W.NORD1)
	TurnProcessor.end_year(s)
	t.assert_true(s.commander_of(crusade.id) != null)


# --- salvataggi e determinismo -------------------------------------------------------------------------------------------


func _play(seed_value: int, years: int) -> GameState:
	var s := W.world(seed_value)
	GameCommands.queue_unit(s, W.A, W.NORD1, "Crusade")
	GameCommands.queue_unit(s, W.B, W.SUD1, "Jihad")
	for i in years:
		for a in s.armies:
			if a.is_crusade() and a.crusade_target() == "" and a.path.is_empty():
				var targets: Array = GameCommands.crusade_targets(s, a.faction, a.id)["bersagli"]
				if not targets.is_empty():
					GameCommands.set_crusade_target(s, a.faction, a.id, str(targets[0]["regione"]))
		TurnProcessor.end_year(s)
	return s


func test_andata_e_ritorno_con_un_esercito_crociato(t: TestContext) -> void:
	var s := W.world(5)
	var army := W.add_crusade(s, W.A, W.NORD1, CRUSADE, W.SUD1)
	army.crusade["reclutate"] = [W.NORD1, W.NORD2]
	army.crusade["zelo"] = 61
	army.path = PackedStringArray([W.NORD2, W.SUD1])
	W.add_crusade(s, W.B, W.SUD1, JIHAD)
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	var data: Dictionary = parsed
	var back := _restore(data)
	t.assert_true(back != null)
	t.assert_eq(SaveGame.to_json(back), text, "stato identico")
	var again := back.army(army.id)
	t.assert_true(again.is_crusade())
	t.assert_eq(again.crusade_kind(), CRUSADE)
	t.assert_eq(again.crusade_target(), W.SUD1)
	t.assert_eq(int(again.crusade["zelo"]), 61)
	t.assert_eq(again.crusade["reclutate"], [W.NORD1, W.NORD2])
	t.assert_eq(typeof(again.crusade["zelo"]), TYPE_INT, "interi dopo il JSON")
	t.assert_eq(again.path, army.path)
	# il fine anno dopo il ricarico e' lo stesso
	for i in 3:
		TurnProcessor.end_year(s)
		TurnProcessor.end_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "tre anni dopo identici")
	W.check_state(t, back, "ricaricata")


func test_stesso_seme_stessa_partita(t: TestContext) -> void:
	var first := _play(77, 8)
	var second := _play(77, 8)
	t.assert_eq(SaveGame.to_json(first), SaveGame.to_json(second), "deterministico")
	W.check_state(t, first, "dopo otto anni")
	var launched := 0
	for a in first.armies:
		if a.is_crusade():
			launched += 1
	t.assert_true(launched >= 1, "almeno un esercito crociato in campo (o sciolto): il test gioca davvero")
