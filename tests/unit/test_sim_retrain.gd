extends RefCounted
## Riaddestramento delle unita' (RetrainRules, RetrainProcessor, GameCommands.order_retrain / cancel_retrain / retrain_options),
## salvataggi di versione 11 e interazione con muovere, dividere e unire gli eserciti. Mondo di prova: agent_world.gd (in sola
## lettura). ALPHA (ALTA, BASSA), BETA (MEZZA), GAMMA (ORTO), ribelli (SOLA). Unita': Spearmen (100 uomini, 100 denari, nessun
## requisito), Archers (60 uomini, 150 denari, serve BOWYER), Alpine (80 uomini, 120 denari, solo ID_BASSA), Nizari (solo BETA).
## Nessun numero dipende dai dati Auror.

const W := preload("res://tests/unit/agent_world.gd")


func _world() -> GameState:
	var s := W.world()
	s.faction(W.A).treasury = 10000
	return s


## Esercito di ALPHA nella regione con una pila per ogni voce [unita, uomini, valore].
func _army(s: GameState, region: String, stacks: Array) -> Army:
	var a := s.create_army(W.A, region, false)
	for entry in stacks:
		var row: Array = entry
		a.stacks.append(UnitStack.new(str(row[0]), int(row[1]), int(row[2])))
	return a


func _men_total(s: GameState) -> int:
	var total := 0
	for a in s.armies:
		total += a.men_total()
	return total


func _treasury(s: GameState) -> int:
	return s.faction(W.A).treasury


# --- regole ------------------------------------------------------------------------------------------------------


func test_i_valori_predefiniti_sono_uguali_al_file(t: TestContext) -> void:
	var from_file := RetrainRules.load_file()
	t.assert_eq(from_file.errors, PackedStringArray(), "riaddestramento.cfg si legge senza errori")
	t.assert_eq(from_file.to_dict(), RetrainRules.new().to_dict(), "riaddestramento.cfg = valori predefiniti del codice")
	t.assert_eq(RetrainRules.new().max_per_province, 4)
	var missing := RetrainRules.load_file("res://data/regole/non_esiste.cfg")
	t.assert_eq(missing.errors.size(), 1, "file mancante: un errore")
	t.assert_eq(missing.to_dict(), RetrainRules.new().to_dict(), "file mancante: valori predefiniti")
	var rules := Rules.load_file()
	t.assert_eq(rules.errors, PackedStringArray(), "tutti i file delle regole senza errori")
	t.assert_eq(rules.retrain.to_dict(), RetrainRules.new().to_dict(), "Rules legge riaddestramento.cfg")
	t.assert_eq(rules.to_dict(), Rules.new().to_dict(), "Rules.to_dict comprende il riaddestramento")
	t.assert_true(Rules.new().to_dict().has("retrain"))


func test_costo_proporzionale_per_eccesso(t: TestContext) -> void:
	var r := RetrainRules.new()
	t.assert_eq(r.cost_for(100, 70, 100), 30)
	t.assert_eq(r.cost_for(100, 0, 100), 100, "pila distrutta: costo pieno")
	t.assert_eq(r.cost_for(150, 1, 60), 148, "150 x 59 / 60 = 147,5: per eccesso")
	t.assert_eq(r.cost_for(120, 79, 80), 2, "120 x 1 / 80 = 1,5: per eccesso")
	t.assert_eq(r.cost_for(100, 100, 100), 0, "pila piena: nulla da pagare")
	t.assert_eq(r.cost_for(100, 120, 100), 0, "oltre l'organico: nulla da pagare")
	t.assert_eq(r.cost_for(100, 50, 0), 0, "organico non valido")
	r.cost_factor = 1.5
	t.assert_eq(r.cost_for(100, 50, 100), 75)
	r.cost_factor = 1.1
	t.assert_eq(r.cost_for(100, 50, 100), 55, "il fattore non esatto in binario non fa salire il costo di un denaro")


func test_il_valore_si_dilusce(t: TestContext) -> void:
	t.assert_eq(RetrainRules.diluted_value(10, 50, 100), 5)
	t.assert_eq(RetrainRules.diluted_value(7, 33, 100), 2, "231 / 100 per difetto")
	t.assert_eq(RetrainRules.diluted_value(9, 100, 100), 9, "pila piena: invariato")
	t.assert_eq(RetrainRules.diluted_value(9, 0, 100), 0)
	t.assert_eq(RetrainRules.diluted_value(9, 150, 100), 9, "gli uomini oltre l'organico non aumentano il valore")
	t.assert_eq(RetrainRules.diluted_value(9, 50, 0), 9, "organico non valido: invariato")


# --- ordinare ----------------------------------------------------------------------------------------------------


func test_l_ordine_paga_subito_e_si_applica_a_fine_anno(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 10], ["Spearmen", 100, 3]])
	var before := _treasury(s)
	var r := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(int(r["pile"]), 1)
	t.assert_eq(int(r["costo"]), 60, "100 x 60 / 100")
	t.assert_eq(_treasury(s), before - 60, "pagato subito")
	t.assert_eq(s.retrain_orders.size(), 1)
	t.assert_eq(a.stacks[0].men, 40, "la pila non cambia prima della fine dell'anno")
	var order := s.retrain_orders[0]
	t.assert_eq(int(order["esercito"]), a.id)
	t.assert_eq(str(order["fazione"]), W.A)
	t.assert_eq(str(order["provincia"]), W.BASSA)
	t.assert_eq(int(order["pila"]), 0)
	t.assert_eq(str(order["unita"]), "Spearmen")
	t.assert_eq(int(order["uomini"]), 40)
	t.assert_eq(int(order["costo"]), 60)
	var men_before := _men_total(s)
	# una recluta in coda nasce nello stesso fine anno: il riaddestramento si applica prima, gli indici restano quelli dell'ordine
	GameCommands.queue_unit(s, W.A, W.BASSA, "Spearmen")
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]), str(res["errori"]))
	t.assert_eq(a.stacks[0].men, 100, "torna all'organico pieno")
	t.assert_eq(a.stacks[0].value, 4, "valore 10 x 40 / 100")
	t.assert_eq(a.stacks[1].men, 100)
	t.assert_eq(a.stacks[1].value, 3, "la pila piena non cambia")
	t.assert_true(s.retrain_orders.is_empty(), "gli ordini si consumano")
	var events := W.events_of(s, GameState.EV_RETRAINED)
	t.assert_eq(events.size(), 1)
	var e := events[0]
	t.assert_eq(str(e["fazione"]), W.A)
	t.assert_eq(str(e["provincia"]), W.BASSA)
	t.assert_eq(int(e["esercito"]), a.id)
	t.assert_eq(int(e["pile"]), 1)
	t.assert_eq(int(e["uomini"]), 60)
	t.assert_eq(int(e["costo"]), 60)
	t.assert_eq((e["unita"] as Array).size(), 1)
	t.assert_eq(_men_total(s), men_before + 60 + 100, "gli uomini aggiunti sono 60 piu' la recluta")
	t.assert_eq(W.events_of(s, GameState.EV_RETRAIN_CANCELLED).size(), 0)
	t.assert_eq(GameState.EV_RETRAINED, "riaddestramento")


func test_piu_pile_costo_totale_e_ordine_crescente(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 50, 0], ["Spearmen", 100, 0], ["Spearmen", 20, 0]])
	var r := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([2, 0, 1]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(int(r["pile"]), 2, "la pila piena e' saltata")
	t.assert_eq(int(r["costo"]), 50 + 80)
	var accepted: Array = r["indici"]
	t.assert_eq(accepted.size(), 2)
	t.assert_eq(int(accepted[0]), 0, "in ordine crescente")
	t.assert_eq(int(accepted[1]), 2)
	var skipped: Array = r["rifiutate"]
	t.assert_eq(skipped.size(), 1)
	var first: Dictionary = skipped[0]
	t.assert_eq(int(first["indice"]), 1)
	t.assert_true(str(first["motivo"]).contains("completo"), str(first["motivo"]))
	t.assert_eq(s.retrain_orders.size(), 2)


func test_la_pila_distrutta_costa_il_pieno(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 1, 5]])
	var r := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(int(r["costo"]), 99, "100 x 99 / 100")
	TurnProcessor.end_year(s)
	t.assert_eq(a.stacks[0].men, 100)
	t.assert_eq(a.stacks[0].value, 0, "valore 5 x 1 / 100 = 0: reclute senza esperienza")


func test_edifici_richiesti_e_castello(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Archers", 30, 0]])
	var no_bowyer := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_false(bool(no_bowyer["ok"]), "gli arcieri servono del Bowyer nella provincia")
	t.assert_true(str(no_bowyer["errore"]).contains("Requisiti"), str(no_bowyer["errore"]))
	s.province(W.BASSA).set_level("BOWYER", 1)
	var ok := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_true(bool(ok["ok"]), str(ok["errore"]))
	t.assert_eq(int(ok["costo"]), 75, "150 x 30 / 60")
	# nel castello va bene
	var b := _army(s, W.ALTA, [["Spearmen", 10, 0]])
	b.in_castle = true
	t.assert_true(bool(GameCommands.order_retrain(s, W.A, b.id, PackedInt32Array([0]))["ok"]), "anche nel castello")


func test_non_riaddestrabili(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 100, 0], ["Spearmen", 40, 0], ["Archers", 30, 0], ["Nizari", 10, 0], ["Alpine", 10, 0]])
	s.province(W.BASSA).set_level("BOWYER", 1)
	var treasury := _treasury(s)
	# pila piena
	var full := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_false(bool(full["ok"]))
	# la colonna «mercenario» dei dati non esclude (vale per molte unita' comuni): conta solo la reclutabilita'
	s.units.get_unit("Spearmen").mercenary = true
	t.assert_true(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([1]))["ok"]), "lancieri con il segno di mercenario")
	s.units.get_unit("Spearmen").mercenary = false
	t.assert_true(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([2]))["ok"]), "arcieri con l'arciere (BOWYER) in provincia")
	# unita' di un'altra fazione (Nizari e' di BETA) e unita' di un'altra regione (Alpine solo in BASSA, qui va bene)
	var other := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([3]))
	t.assert_false(bool(other["ok"]))
	t.assert_true(str(other["errore"]).contains("reclutabile"), str(other["errore"]))
	t.assert_true(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([4]))["ok"]), "Alpine in BASSA si riaddestra")
	var elsewhere := _army(s, W.ALTA, [["Alpine", 10, 0]])
	var wrong_region := GameCommands.order_retrain(s, W.A, elsewhere.id, PackedInt32Array([0]))
	t.assert_false(bool(wrong_region["ok"]), "Alpine non e' reclutabile in ALTA")
	t.assert_true(_treasury(s) < treasury, "gli ordini accettati sono stati pagati")
	t.assert_eq(s.retrain_orders.size(), 3, "lancieri, arcieri e Alpine in BASSA")


func test_l_epoca_conta(t: TestContext) -> void:
	var s := _world()
	s.units.get_unit("Spearmen").periods = PackedStringArray(["HIGH"])
	var a := _army(s, W.BASSA, [["Spearmen", 10, 0]])
	var r := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("epoca"), str(r["errore"]))


func test_navi_e_agenti_non_si_riaddestrano(t: TestContext) -> void:
	var s := _world()
	var fleet := W.fleet(s, W.A, W.NORD)
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, fleet.id, PackedInt32Array([0]))["ok"]), "le flotte no")
	var mixed := _army(s, W.BASSA, [["Galley", 0, 0]])
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, mixed.id, PackedInt32Array([0]))["ok"]), "una nave in un esercito di terra no")


func test_condizioni_dell_esercito(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 10, 0]])
	var treasury := _treasury(s)
	# esercito altrui o fazione sbagliata
	t.assert_false(bool(GameCommands.order_retrain(s, W.B, a.id, PackedInt32Array([0]))["ok"]), "non e' di BETA")
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, 9999, PackedInt32Array([0]))["ok"]), "esercito inesistente")
	# in marcia
	a.path = PackedStringArray([W.ALTA])
	var moving := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_false(bool(moving["ok"]))
	t.assert_true(str(moving["errore"]).contains("marcia"), str(moving["errore"]))
	a.path = PackedStringArray()
	# provincia di un altro
	var abroad := s.create_army(W.A, W.MEZZA, false)
	abroad.stacks.append(UnitStack.new("Spearmen", 10, 0))
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, abroad.id, PackedInt32Array([0]))["ok"]), "MEZZA e' di BETA")
	# provincia assediata
	s.sieges[W.BASSA] = SiegeState.new(W.BASSA, W.B)
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))["ok"]), "provincia assediata")
	s.sieges.erase(W.BASSA)
	# esercito crociato
	a.crusade = {"tipo": "crociata", "zelo": 80, "bersaglio": ""}
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))["ok"]), "crociati no")
	a.crusade = {}
	# indici non validi
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([]))["ok"]))
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([5]))["ok"]))
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 0]))["ok"]))
	t.assert_eq(_treasury(s), treasury, "nessun rifiuto tocca il tesoro")
	t.assert_true(s.retrain_orders.is_empty(), "nessun rifiuto lascia ordini")
	t.assert_true(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))["ok"]), "tolti gli ostacoli l'ordine passa")


func test_tesoro_insufficiente_rifiuta_tutto(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 10, 0], ["Spearmen", 10, 0]])
	s.faction(W.A).treasury = 100   # le due pile costano 90 + 90
	var r := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("Tesoro insufficiente"), str(r["errore"]))
	t.assert_eq(_treasury(s), 100)
	t.assert_true(s.retrain_orders.is_empty())
	t.assert_true(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))["ok"]), "una pila sola ci sta")
	t.assert_eq(_treasury(s), 10)


func test_la_pila_gia_ordinata_non_si_ordina_due_volte(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 10, 0]])
	t.assert_true(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))["ok"]))
	var again := GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_false(bool(again["ok"]))
	t.assert_true(str(again["errore"]).contains("gia'"), str(again["errore"]))
	t.assert_eq(s.retrain_orders.size(), 1)


func test_limite_per_provincia(t: TestContext) -> void:
	var s := _world()
	var first := _army(s, W.BASSA, [["Spearmen", 10, 0], ["Spearmen", 10, 0], ["Spearmen", 10, 0]])
	var second := _army(s, W.BASSA, [["Spearmen", 10, 0], ["Spearmen", 10, 0], ["Spearmen", 10, 0]])
	var r1 := GameCommands.order_retrain(s, W.A, first.id, PackedInt32Array([0, 1, 2]))
	t.assert_eq(int(r1["pile"]), 3)
	var r2 := GameCommands.order_retrain(s, W.A, second.id, PackedInt32Array([0, 1, 2]))
	t.assert_true(bool(r2["ok"]), str(r2["errore"]))
	t.assert_eq(int(r2["pile"]), 1, "il quarto posto della provincia")
	t.assert_eq(int((r2["rifiutate"] as Array).size()), 2, "le altre due oltre il limite")
	var over: Dictionary = (r2["rifiutate"] as Array)[0]
	t.assert_true(str(over["motivo"]).contains("Limite"), str(over["motivo"]))
	t.assert_eq(RetrainProcessor.orders_in(s, W.BASSA), 4)
	var r3 := GameCommands.order_retrain(s, W.A, second.id, PackedInt32Array([1]))
	t.assert_false(bool(r3["ok"]), "limite raggiunto")
	# un'altra provincia ha il suo limite
	var elsewhere := _army(s, W.ALTA, [["Spearmen", 10, 0]])
	t.assert_true(bool(GameCommands.order_retrain(s, W.A, elsewhere.id, PackedInt32Array([0]))["ok"]))
	# il limite e' un parametro
	s.rules.retrain.max_per_province = 6
	t.assert_true(bool(GameCommands.order_retrain(s, W.A, second.id, PackedInt32Array([1]))["ok"]), "con limite 6 ci sta")
	s.rules.retrain.max_per_province = 0
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, second.id, PackedInt32Array([2]))["ok"]), "limite 0 = riaddestramento spento")


func test_il_limite_riparte_l_anno_dopo(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 10, 0], ["Spearmen", 10, 0], ["Spearmen", 10, 0], ["Spearmen", 10, 0], ["Spearmen", 10, 0]])
	t.assert_eq(int(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1, 2, 3, 4]))["pile"]), 4)
	TurnProcessor.end_year(s)
	t.assert_eq(RetrainProcessor.orders_in(s, W.BASSA), 0)
	t.assert_eq(a.stacks[4].men, 10, "la quinta aspetta")
	t.assert_true(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([4]))["ok"]), "l'anno dopo si puo'")


# --- anteprima ---------------------------------------------------------------------------------------------------


func test_anteprima(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 100, 0], ["Nizari", 30, 0]])
	var r := GameCommands.retrain_options(s, W.A, a.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var piles: Array = r["pile"]
	t.assert_eq(piles.size(), 3)
	var p0: Dictionary = piles[0]
	t.assert_eq(int(p0["indice"]), 0)
	t.assert_eq(str(p0["unita"]), "Spearmen")
	t.assert_eq(int(p0["uomini"]), 40)
	t.assert_eq(int(p0["pieni"]), 100)
	t.assert_eq(int(p0["mancanti"]), 60)
	t.assert_eq(int(p0["costo"]), 60)
	t.assert_true(bool(p0["si_puo"]))
	t.assert_eq(str(p0["motivo"]), "")
	t.assert_false(bool(p0["in_riaddestramento"]))
	var p1: Dictionary = piles[1]
	t.assert_false(bool(p1["si_puo"]))
	t.assert_eq(int(p1["costo"]), 0, "pila piena: niente da pagare")
	var p2: Dictionary = piles[2]
	t.assert_false(bool(p2["si_puo"]), "Nizari non e' reclutabile da ALPHA")
	t.assert_true(str(p2["motivo"]) != "")
	t.assert_eq(int(r["posti"]), 4)
	t.assert_eq(int(r["ordini"]), 0)
	var before := s.retrain_orders.size()
	t.assert_eq(before, 0, "l'anteprima non ordina nulla")
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	var after := GameCommands.retrain_options(s, W.A, a.id)
	var q0: Dictionary = (after["pile"] as Array)[0]
	t.assert_true(bool(q0["in_riaddestramento"]))
	t.assert_false(bool(q0["si_puo"]))
	t.assert_eq(int(q0["costo"]), 60, "il costo pagato")
	t.assert_eq(int(after["posti"]), 3)
	t.assert_eq(int(after["ordini"]), 1)
	# esercito che non si puo' riaddestrare: ok falso con il motivo
	a.path = PackedStringArray([W.ALTA])
	t.assert_false(bool(GameCommands.retrain_options(s, W.A, a.id)["ok"]))


# --- annullare e rimborsare ----------------------------------------------------------------------------------------


func test_annullare_rimborsa_tutto(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 70, 0]])
	var treasury := _treasury(s)
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
	t.assert_eq(_treasury(s), treasury - 90)
	t.assert_false(bool(GameCommands.cancel_retrain(s, W.B, a.id)["ok"]), "non e' di BETA")
	var r := GameCommands.cancel_retrain(s, W.A, a.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(int(r["rimborso"]), 90)
	t.assert_eq(int(r["pile"]), 2)
	t.assert_eq(_treasury(s), treasury)
	t.assert_true(s.retrain_orders.is_empty())
	t.assert_false(bool(GameCommands.cancel_retrain(s, W.A, a.id)["ok"]), "niente da annullare")
	t.assert_false(bool(GameCommands.cancel_retrain(s, W.A, 9999)["ok"]), "esercito inesistente")
	TurnProcessor.end_year(s)
	t.assert_eq(a.stacks[0].men, 40, "annullato: la pila resta com'era")


func test_muovere_l_esercito_rimborsa(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	var treasury := _treasury(s)
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	var r := GameCommands.order_move(s, W.A, a.id, PackedStringArray([W.ALTA]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(int(r["rimborso_riaddestramento"]), 60)
	t.assert_eq(_treasury(s), treasury)
	t.assert_true(s.retrain_orders.is_empty())
	# un movimento senza ordini non aggiunge nulla all'esito
	var b := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	t.assert_false(GameCommands.order_move(s, W.A, b.id, PackedStringArray([W.ALTA])).has("rimborso_riaddestramento"))
	# un movimento rifiutato non annulla niente
	var c := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	GameCommands.order_retrain(s, W.A, c.id, PackedInt32Array([0]))
	t.assert_false(bool(GameCommands.order_move(s, W.A, c.id, PackedStringArray([W.NORD]))["ok"]), "BASSA non confina col mare")
	t.assert_eq(s.retrain_orders.size(), 1)


func test_a_fine_anno_gli_ordini_non_applicabili_si_rimborsano(t: TestContext) -> void:
	# esercito sparito
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	var treasury := _treasury(s)
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	s.remove_army(a)
	RetrainProcessor.process_year(s)
	t.assert_eq(_treasury(s), treasury, "rimborsato")
	var gone := W.events_of(s, GameState.EV_RETRAIN_CANCELLED)
	t.assert_eq(gone.size(), 1)
	t.assert_eq(str(gone[0]["motivo"]), "esercito_perso")
	t.assert_eq(int(gone[0]["rimborso"]), 60)
	t.assert_eq(str(gone[0]["fazione"]), W.A)
	t.assert_eq(W.events_of(s, GameState.EV_RETRAINED).size(), 0)
	t.assert_true(s.retrain_orders.is_empty())
	t.assert_eq(GameState.EV_RETRAIN_CANCELLED, "riaddestramento_annullato")
	# esercito spostato (regione diversa) o in marcia
	var s2 := _world()
	var b := _army(s2, W.BASSA, [["Spearmen", 40, 0]])
	GameCommands.order_retrain(s2, W.A, b.id, PackedInt32Array([0]))
	b.region = W.ALTA
	RetrainProcessor.process_year(s2)
	t.assert_eq(str(W.events_of(s2, GameState.EV_RETRAIN_CANCELLED)[0]["motivo"]), "esercito_mosso")
	t.assert_eq(b.stacks[0].men, 40)
	var s3 := _world()
	var c := _army(s3, W.BASSA, [["Spearmen", 40, 0]])
	GameCommands.order_retrain(s3, W.A, c.id, PackedInt32Array([0]))
	c.path = PackedStringArray([W.ALTA])
	RetrainProcessor.process_year(s3)
	t.assert_eq(str(W.events_of(s3, GameState.EV_RETRAIN_CANCELLED)[0]["motivo"]), "esercito_mosso")
	# provincia persa
	var s4 := _world()
	var d := _army(s4, W.BASSA, [["Spearmen", 40, 0]])
	var treasury4 := s4.faction(W.A).treasury
	GameCommands.order_retrain(s4, W.A, d.id, PackedInt32Array([0]))
	s4.province(W.BASSA).owner = W.B
	RetrainProcessor.process_year(s4)
	t.assert_eq(str(W.events_of(s4, GameState.EV_RETRAIN_CANCELLED)[0]["motivo"]), "provincia_persa")
	t.assert_eq(s4.faction(W.A).treasury, treasury4, "il rimborso va a chi ha pagato")
	t.assert_eq(d.stacks[0].men, 40)


func test_la_pila_cambiata_si_rimborsa(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 30, 0]])
	var treasury := _treasury(s)
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
	a.stacks[0].men = 25            # perdite dopo l'ordine
	a.stacks.remove_at(1)           # l'altra pila e' sparita (indice non piu' valido)
	RetrainProcessor.process_year(s)
	t.assert_eq(a.stacks[0].men, 25, "la pila cambiata non si tocca")
	t.assert_eq(_treasury(s), treasury, "entrambi gli ordini rimborsati")
	var cancelled := W.events_of(s, GameState.EV_RETRAIN_CANCELLED)
	t.assert_eq(cancelled.size(), 1, "un evento per esercito")
	t.assert_eq(int(cancelled[0]["pile"]), 2)
	t.assert_eq(int(cancelled[0]["rimborso"]), 60 + 70)
	t.assert_eq(str(cancelled[0]["motivo"]), "pila_cambiata")


func test_ordini_in_parte_applicati_e_in_parte_rimborsati(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 8], ["Spearmen", 30, 8]])
	var treasury := _treasury(s)
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
	a.stacks[1].men = 20
	RetrainProcessor.process_year(s)
	t.assert_eq(a.stacks[0].men, 100)
	t.assert_eq(a.stacks[0].value, 3, "8 x 40 / 100")
	t.assert_eq(a.stacks[1].men, 20)
	t.assert_eq(_treasury(s), treasury - 60, "rimborsata solo la seconda")
	t.assert_eq(W.events_of(s, GameState.EV_RETRAINED).size(), 1)
	t.assert_eq(W.events_of(s, GameState.EV_RETRAIN_CANCELLED).size(), 1)


func test_ordini_di_piu_eserciti_in_ordine_fisso(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	var b := _army(s, W.ALTA, [["Spearmen", 50, 0]])
	GameCommands.order_retrain(s, W.A, b.id, PackedInt32Array([0]))
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	RetrainProcessor.process_year(s)
	var done := W.events_of(s, GameState.EV_RETRAINED)
	t.assert_eq(done.size(), 2)
	t.assert_eq(int(done[0]["esercito"]), b.id, "nell'ordine in cui sono stati dati")
	t.assert_eq(int(done[1]["esercito"]), a.id)


# --- dividere e unire ----------------------------------------------------------------------------------------------


func test_dividere_annulla_gli_ordini_di_quell_esercito(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 50, 0], ["Spearmen", 100, 0]])
	var treasury := _treasury(s)
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
	var r := GameCommands.split_army(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(int(r["rimborso_riaddestramento"]), 110)
	t.assert_eq(int(r["pile_riaddestramento"]), 2)
	t.assert_eq(_treasury(s), treasury)
	t.assert_true(s.retrain_orders.is_empty())
	t.assert_eq(a.stacks.size(), 2, "la divisione e' avvenuta come sempre")
	t.assert_eq(s.army(int(r["esercito"])).stacks.size(), 1)
	# senza ordini l'esito non cambia
	var plain := GameCommands.split_army(s, W.A, a.id, PackedInt32Array([0]))
	t.assert_false(plain.has("rimborso_riaddestramento"))
	# una divisione rifiutata non annulla gli ordini
	var b := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	GameCommands.order_retrain(s, W.A, b.id, PackedInt32Array([0]))
	t.assert_false(bool(GameCommands.split_army(s, W.A, b.id, PackedInt32Array([0]))["ok"]), "deve restare una pila")
	t.assert_eq(s.retrain_orders.size(), 1)


func test_spostare_e_unire_annullano_gli_ordini_dell_esercito_di_partenza(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 60, 0]])
	var b := _army(s, W.BASSA, [["Spearmen", 30, 0]])
	var treasury := _treasury(s)
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
	GameCommands.order_retrain(s, W.A, b.id, PackedInt32Array([0]))
	t.assert_eq(_treasury(s), treasury - 60 - 40 - 70)
	var moved := GameCommands.transfer_stacks(s, W.A, a.id, b.id, PackedInt32Array([0]))
	t.assert_true(bool(moved["ok"]), str(moved["errore"]))
	t.assert_eq(int(moved["rimborso_riaddestramento"]), 100, "gli ordini dell'esercito di partenza")
	t.assert_eq(RetrainProcessor.orders_of(s, a.id).size(), 0)
	t.assert_eq(RetrainProcessor.orders_of(s, b.id).size(), 1, "l'esercito di arrivo conserva il suo: le sue pile non cambiano indice")
	t.assert_eq(_treasury(s), treasury - 70)
	# unire tutto l'esercito di partenza in un altro
	var c := _army(s, W.BASSA, [["Spearmen", 20, 0]])
	GameCommands.order_retrain(s, W.A, c.id, PackedInt32Array([0]))
	var merged := GameCommands.merge_armies(s, W.A, c.id, b.id)
	t.assert_true(bool(merged["ok"]), str(merged["errore"]))
	t.assert_eq(int(merged["rimborso_riaddestramento"]), 80)
	t.assert_true(s.army(c.id) == null, "l'esercito unito sparisce")
	for o in s.retrain_orders:
		t.assert_true(int(o["esercito"]) != c.id, "nessun ordine orfano")
	# il trasferimento rifiutato (regioni diverse) non annulla niente
	var far := _army(s, W.ALTA, [["Spearmen", 20, 0]])
	GameCommands.order_retrain(s, W.A, far.id, PackedInt32Array([0]))
	t.assert_false(bool(GameCommands.merge_armies(s, W.A, far.id, b.id)["ok"]))
	t.assert_eq(RetrainProcessor.orders_of(s, far.id).size(), 1)


# --- fine anno nel mondo ---------------------------------------------------------------------------------------------


func test_il_conto_degli_uomini_quadra_con_gli_eventi(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 10, 0]])
	var b := _army(s, W.ALTA, [["Spearmen", 90, 0]])
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
	GameCommands.order_retrain(s, W.A, b.id, PackedInt32Array([0]))
	var before := _men_total(s)
	TurnProcessor.end_year(s)
	var added := 0
	for e in W.events_of(s, GameState.EV_RETRAINED):
		added += int(e["uomini"])
	t.assert_eq(added, 60 + 90 + 10)
	t.assert_eq(_men_total(s), before + added)


# --- ripristino delle forze (richiesta di Federico, 2026-11-13, ADR-046) ---------------------------------------------


func test_ripristino_riporta_tutto_l_esercito_al_completo_in_un_anno(t: TestContext) -> void:
	var s := _world()
	# BASSA senza Bowyer: il riaddestramento dell'originale rifiuta gli arcieri, il ripristino no; compagnia di mercenari compresa
	var a := _army(s, W.BASSA, [["Spearmen", 100, 0], ["Spearmen", 40, 3], ["Archers", 30, 0], ["Spearmen", 50, 0]])
	a.stacks[3].mercenary = true
	t.assert_false(bool(GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([2]))["ok"]), "riaddestramento: servono gli edifici")
	var preview := GameCommands.restore_preview(s, W.A, a.id)
	t.assert_true(bool(preview["ok"]), str(preview))
	t.assert_eq(preview["indici"], [1, 2, 3], "la pila piena resta fuori")
	t.assert_eq(int(preview["uomini"]), 60 + 30 + 50)
	t.assert_eq(int(preview["costo"]), 60 + 75 + 50, "100 x 60/100 + 150 x 30/60 + 100 x 50/100")
	var treasury := _treasury(s)
	var r := GameCommands.restore_army(s, W.A, a.id)
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_eq(int(r["pile"]), 3)
	t.assert_eq(int(r["costo"]), 185)
	t.assert_eq(_treasury(s), treasury - 185, "pagato subito")
	t.assert_true(bool(s.retrain_orders[0].get("ripristino", false)), "ordini segnati come ripristino")
	RetrainProcessor.process_year(s)
	for st in a.stacks:
		t.assert_eq(st.men, s.units.get_unit(st.unit_id).men, "%s al completo" % st.unit_id)
	t.assert_eq(a.stacks[1].value, 1, "il valore si diluisce come nel riaddestramento: 3 x 40 / 100")


func test_ripristino_senza_limite_di_pile_per_provincia(t: TestContext) -> void:
	var s := _world()
	var stacks := []
	for i in 6:
		stacks.append(["Spearmen", 10, 0])
	var a := _army(s, W.ALTA, stacks)
	var r := GameCommands.restore_army(s, W.A, a.id)
	t.assert_eq(int(r["pile"]), 6, "tutte e sei, oltre il limite di 4 del riaddestramento")
	s.rules.retrain.restore_uses_limit = true
	GameCommands.cancel_retrain(s, W.A, a.id)
	var limited := GameCommands.restore_army(s, W.A, a.id)
	t.assert_eq(int(limited["pile"]), 4, "con limite_per_provincia=true")
	t.assert_eq((limited["escluse"] as Array).size(), 2)


func test_ripristino_rifiutato_o_parziale(t: TestContext) -> void:
	var s := _world()
	var full := _army(s, W.ALTA, [["Spearmen", 100, 0]])
	var r := GameCommands.restore_army(s, W.A, full.id)
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("pieno delle forze"), str(r["errore"]))
	var abroad := _army(s, W.MEZZA, [["Spearmen", 10, 0]])
	t.assert_false(bool(GameCommands.restore_army(s, W.A, abroad.id)["ok"]), "solo in una provincia propria")
	var a := _army(s, W.ALTA, [["Spearmen", 50, 0], ["Spearmen", 50, 0]])
	s.faction(W.A).treasury = 60
	var partial := GameCommands.restore_army(s, W.A, a.id)
	t.assert_true(bool(partial["ok"]), str(partial))
	t.assert_eq(int(partial["pile"]), 1, "si paga quel che si puo'")
	t.assert_eq(int(partial["rimaste"]), 1)
	t.assert_eq(_treasury(s), 10)
	var again := GameCommands.restore_army(s, W.A, a.id)
	t.assert_false(bool(again["ok"]), "tesoro insufficiente per l'altra")
	t.assert_true(str(again["errore"]).contains("Tesoro"), str(again["errore"]))
	s.rules.retrain.restore_mercenaries = false
	var merc := _army(s, W.ALTA, [["Spearmen", 10, 0]])
	merc.stacks[0].mercenary = true
	t.assert_false(bool(GameCommands.restore_army(s, W.A, merc.id)["ok"]), "mercenari esclusi con mercenari=false")


func test_ripristino_rimborsato_se_l_esercito_parte(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, W.ALTA, [["Spearmen", 40, 0]])
	var treasury := _treasury(s)
	t.assert_true(bool(GameCommands.restore_army(s, W.A, a.id)["ok"]))
	var moved := GameCommands.order_move(s, W.A, a.id, PackedStringArray([W.BASSA]))
	t.assert_eq(int(moved.get("rimborso_riaddestramento", 0)), 60, "rimborsato alla partenza")
	t.assert_eq(_treasury(s), treasury)


func test_stesso_stato_stesso_esito(t: TestContext) -> void:
	var texts: Array[String] = []
	for i in 2:
		var s := _world()
		var a := _army(s, W.BASSA, [["Spearmen", 40, 6], ["Spearmen", 55, 2]])
		GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
		TurnProcessor.end_year(s)
		texts.append(SaveGame.to_json(s))
	t.assert_eq(texts[0], texts[1])


# --- salvataggi --------------------------------------------------------------------------------------------------


func _restore(data: Dictionary, rules: Rules) -> Dictionary:
	var campaign := StartposLoader.load_file(W.STARTPOS)
	var units := UnitProdLoader.load_file(W.UNITS)
	var buildings := BuildingProdLoader.load_file(W.BUILDINGS)
	return SaveGame.from_dict(data, campaign, units, buildings, rules)


func test_andata_e_ritorno_attraverso_il_testo_json(t: TestContext) -> void:
	t.assert_true(SaveGame.VERSION >= 11, "dal riaddestramento (versione 11) i salvataggi hanno gli ordini")
	var s := _world()
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0], ["Spearmen", 55, 0]])
	var b := _army(s, W.ALTA, [["Spearmen", 10, 0]])
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0, 1]))
	GameCommands.order_retrain(s, W.A, b.id, PackedInt32Array([0]))
	var d := SaveGame.to_dict(s)
	t.assert_eq(d["versione"], SaveGame.VERSION)
	t.assert_eq((d["ordini_riaddestramento"] as Array).size(), 3)
	var text := SaveGame.to_json(s)
	var parsed: Variant = JSON.parse_string(text)
	t.assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	var r := _restore(data, s.rules)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	if not bool(r["ok"]):
		return
	var back: GameState = r["stato"]
	t.assert_eq(back.retrain_orders.size(), 3)
	for i in 3:
		var x := s.retrain_orders[i]
		var y := back.retrain_orders[i]
		for key in ["esercito", "pila", "uomini", "costo", "anno"]:
			t.assert_eq(y[key], x[key], "ordine %d: %s (intero, non decimale)" % [i, key])
		for key in ["fazione", "provincia", "unita"]:
			t.assert_eq(y[key], x[key], "ordine %d: %s" % [i, key])
	t.assert_eq(SaveGame.to_json(back), text, "andata e ritorno stabile")
	# lo stato ricaricato produce lo stesso fine anno dell'originale
	TurnProcessor.end_year(s)
	TurnProcessor.end_year(back)
	t.assert_eq(SaveGame.to_json(back), SaveGame.to_json(s), "stesso anno successivo")
	t.assert_eq(W.events_of(back, GameState.EV_RETRAINED).size(), 2)


func test_i_salvataggi_precedenti_non_hanno_ordini(t: TestContext) -> void:
	var s := _world()
	var d := SaveGame.to_dict(s)
	d["versione"] = 10
	d.erase("ordini_riaddestramento")
	var r := _restore(d, s.rules)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var back: GameState = r["stato"]
	t.assert_true(back.retrain_orders.is_empty())
	# una versione precedente non puo' avere ordini nemmeno se il campo c'e'
	var a := _army(s, W.BASSA, [["Spearmen", 40, 0]])
	GameCommands.order_retrain(s, W.A, a.id, PackedInt32Array([0]))
	var odd := SaveGame.to_dict(s)
	odd["versione"] = 10
	var r2 := _restore(odd, s.rules)
	t.assert_true(bool(r2["ok"]), str(r2["errore"]))
	var back2: GameState = r2["stato"]
	t.assert_true(back2.retrain_orders.is_empty(), "la versione 10 non legge gli ordini")
