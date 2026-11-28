extends RefCounted
## Luoghi leggendari (richiesta di Federico del 26/11/2026): catalogo reale, posizioni sulla plancia lontane da castelli,
## porti e pedine, effetti per chi possiede il luogo, scoperta, eventi con e senza scelta, transito e presidio del mare,
## scelte del giocatore e salvataggi. Mondo di prova: agent_world.gd.

const W := preload("res://tests/unit/agent_world.gd")

const CATALOGO := """
[tempio]
categoria="storico"
simbolo="tempio"
regione="ID_ALTA"
nome="Tempio"
effetti={"agricoltura": 50, "lealta": 7, "valore_spie": 2, "mantenimento": 100, "tempeste": -100}
effetti_religione={"CATHOLIC": {"commercio": 10}, "altre": {"lealta": -20}}
scoperta={"tesoro": 500}
eventi=["tempio_scelta"]

[evento.tempio_scelta]
luogo="tempio"
tipo="ricorrente"
ogni=[1, 1]
titolo="Scelta"
testo="Testo"
opzioni=[{"testo": "Paga", "richiede": {"costo": 100}, "esiti": [{"p": 100, "tesoro": 1000}], "ia": 1}, {"testo": "Chiudi", "esiti": [{"p": 100, "fine_luogo": true}], "ia": 2}]

[gorgo]
categoria="marino"
simbolo="gorgo"
regione="ID_MARE_NORD"
nome="Gorgo"
transito={"perdite": 100}
presidio_anni=2
presidio={"commercio_marittimo": 50}
eventi=["gorgo_eroe"]

[evento.gorgo_eroe]
luogo="gorgo"
tipo="condizionato"
chi="flotta"
probabilita=100
attesa=3
titolo="Eroe"
testo="Testo"
esito={"tesoro": 300}
"""


func _world() -> GameState:
	var s := W.world()
	s.rules.sites = LegendarySites.parse_text(CATALOGO)
	return s


func test_il_catalogo_reale_e_senza_errori(t: TestContext) -> void:
	var sites := LegendarySites.load_file()
	t.assert_eq(sites.errors.size(), 0, "nessun errore: %s" % ", ".join(sites.errors))
	t.assert_eq(sites.sites.size(), 39, "38 luoghi piu' il Trono d'Oro")
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mappa_mondo/mondo.json"))
	var ids := {}
	for r in info["regions"]:
		ids[str(r["id"])] = bool(r.get("sea", false))
	var count := {}
	for s in sites.sites:
		t.assert_true(ids.has(s.region), "%s: regione %s nella mappa del mondo" % [s.id, s.region])
		t.assert_eq(bool(ids.get(s.region, false)), s.is_sea(), "%s: i luoghi marini stanno in mare" % s.id)
		t.assert_true(s.has_position, "%s: posizione sulla plancia" % s.id)
		t.assert_true(s.name != "" and s.name_en != "" and s.description != "" and s.description_en != "", "%s: testi nelle due lingue" % s.id)
		t.assert_true(FileAccess.file_exists("res://assets/luoghi/simboli/%s_%s.png" % [s.symbol, s.category]), "%s: simbolo del medaglione" % s.id)
		count[s.region] = int(count.get(s.region, 0)) + 1
	for r in count:
		t.assert_true(int(count[r]) <= 2, "al massimo due luoghi per regione (%s)" % r)
	t.assert_true(sites.site("trono_doro").auror_only, "il Trono d'Oro solo nella modalita' Auror")
	for eid in sites.events:
		var e: LegendarySites.SiteEvent = sites.events[eid]
		t.assert_true(e.title_en != "" and e.text_en != "", "evento %s: testi inglesi" % eid)
		for o in e.options:
			t.assert_true(str(o.get("testo_en", "")) != "", "evento %s: opzione in inglese" % eid)
			var total := 0
			for r in o.get("esiti", []):
				total += int(r.get("p", 0))
			t.assert_eq(total, 100, "evento %s: probabilita' degli esiti a 100" % eid)


func test_le_posizioni_non_coprono_castelli_ne_pedine(t: TestContext) -> void:
	var sites := LegendarySites.load_file()
	var castles := {}
	for path in ["res://data/mappa_mondo/startpos_mondo.txt", "res://data/mappa_mondo/startpos_atlantide.txt"]:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var parts := line.split("\t", false)
			if parts.size() >= 4 and parts[0].strip_edges() == "SetCastle::":
				castles[parts[1].strip_edges()] = Vector2(float(parts[2]), float(parts[3])) / 16.0
	# Roma sta a sud del porto della sua regione anche sotto castello e pedine (richiesta di Federico del 28/11/2026,
	# DAL_PORTO di tools/mondo/posiziona_luoghi.py): la regione e' piccola e la voleva li', non verso la Toscana
	var by_port := ["roma"]
	for s in sites.sites:
		if s.id in by_port:
			continue
		for rid in castles:
			var c: Vector2 = castles[rid]
			var d := s.position - c
			var scale := 2.6 if rid == "ID_ATLANTIS" else 1.0
			# castello sopra il punto e pedine alla sua destra: ingombri ridotti al 60% (tools/mondo/posiziona_luoghi.py)
			var on_castle := absf(d.x) < 42.0 * 0.6 * scale and d.y > -72.0 * 0.6 * scale and d.y < 30.0 * 0.6 * scale
			var on_pieces := d.x > 0.0 and d.x < 175.0 * 0.6 and d.y > -82.0 * 0.6 and d.y < 50.0 * 0.6
			t.assert_false(on_castle, "%s non copre il castello di %s" % [s.id, rid])
			# le pedine del castello della propria regione mai; quelle di un castello vicino solo se nella regione non c'e'
			# altro posto (Roma sotto la Corsica, Rodi sotto l'Anatolia, 28/11/2026: si vedono solo con eserciti fuori)
			t.assert_false(on_pieces and scale == 1.0 and rid == s.region, "%s non copre le pedine di %s" % [s.id, rid])
		for o in sites.sites:
			if o != s:
				t.assert_true(s.position.distance_to(o.position) >= 30.0, "%s lontano da %s" % [s.id, o.id])


func test_effetti_per_il_proprietario(t: TestContext) -> void:
	var s := _world()
	var p := s.province(W.ALTA)
	t.assert_eq(p.owner, W.A)
	var with_site := Economy.province_income(s, p)
	var plain := W.world()
	var without := Economy.province_income(plain, plain.province(W.ALTA))
	t.assert_true(absi(int(with_site["agricoltura"]) - roundi(float(without["agricoltura"]) * 1.5)) <= 1, "agricoltura +50%% (%d contro %d)" % [int(with_site["agricoltura"]), int(without["agricoltura"])])
	var rel := ReligionProcessor.faction_religion(s, W.A)
	var expected_loyalty := 7 + (0 if rel == "CATHOLIC" else -20)
	t.assert_eq(int(ProvinceProcessor.loyalty_terms(s, p)["luogo"]), expected_loyalty, "lealta' del luogo secondo la religione (%s)" % rel)
	t.assert_eq(LegendarySites.agent_bonus(s, W.ALTA, AgentState.SPY), 2)
	t.assert_eq(LegendarySites.agent_bonus(s, W.BASSA, AgentState.SPY), 0, "solo nella provincia del luogo")
	t.assert_eq(Economy.faction_upkeep(s, W.A) - Economy.faction_upkeep(plain, W.A), 100, "mantenimento del luogo")
	t.assert_eq(LegendarySites.faction_factor(s, W.A, "tempeste"), 0.0, "tempeste -100% per tutta la fazione")
	t.assert_eq(LegendarySites.faction_factor(s, W.B, "tempeste"), 1.0, "non per le altre")


func test_scoperta_alla_prima_conquista(t: TestContext) -> void:
	var s := _world()
	LegendarySiteProcessor.ensure_init(s)
	var gold := s.faction(W.B).treasury
	s.province(W.ALTA).owner = W.B
	s.events.clear()
	LegendarySiteProcessor.process_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_SITE_DISCOVERED).size(), 1, "la conquista si annuncia")
	t.assert_true(s.faction(W.B).treasury >= gold + 500, "esito della scoperta")
	s.events.clear()
	LegendarySiteProcessor.process_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_SITE_DISCOVERED).size(), 0, "una volta sola per fazione")


func test_evento_con_scelta_ia_e_giocatore(t: TestContext) -> void:
	var s := _world()
	LegendarySiteProcessor.ensure_init(s)
	LegendarySiteProcessor.process_year(s)   # primo anno: si fissa il prossimo evento
	s.year += 1
	s.events.clear()
	LegendarySiteProcessor.process_year(s)
	# IA: sceglie l'opzione con `ia` piu' alto (chiudere il luogo)
	t.assert_eq(W.events_of(s, GameState.EV_SITE_EVENT).size(), 1)
	t.assert_false(LegendarySites.is_active(s, s.rules.sites.site("tempio")), "l'IA ha chiuso il luogo")
	t.assert_eq(LegendarySites.region_value(s, W.ALTA, "agricoltura"), 0.0, "un luogo chiuso non ha piu' effetti")
	# giocatore: la scelta resta in attesa
	var s2 := _world()
	s2.faction(W.A).is_player = true
	LegendarySiteProcessor.ensure_init(s2)
	LegendarySiteProcessor.process_year(s2)
	s2.year += 1
	LegendarySiteProcessor.process_year(s2)
	var pending := LegendarySiteProcessor.choices_for(s2, W.A)
	t.assert_eq(pending.size(), 1, "scelta in attesa")
	var gold := s2.faction(W.A).treasury
	var r := GameCommands.choose_site_option(s2, W.A, int(pending[0]["id"]), 0)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(s2.faction(W.A).treasury, gold - 100 + 1000, "costo e tesoro")
	t.assert_eq(LegendarySiteProcessor.choices_for(s2, W.A).size(), 0)
	t.assert_false(bool(GameCommands.choose_site_option(s2, W.B, 999, 0)["ok"]), "scelta inesistente")


func test_scelta_lasciata_in_sospeso(t: TestContext) -> void:
	var s := _world()
	s.faction(W.A).is_player = true
	LegendarySiteProcessor.ensure_init(s)
	LegendarySiteProcessor.process_year(s)
	s.year += 1
	LegendarySiteProcessor.process_year(s)
	t.assert_eq(LegendarySiteProcessor.choices_for(s, W.A).size(), 1)
	s.year += 1
	LegendarySiteProcessor.settle_overdue(s)
	t.assert_eq(LegendarySiteProcessor.choices_for(s, W.A).size(), 0, "presa da sola")
	t.assert_false(LegendarySites.is_active(s, s.rules.sites.site("tempio")), "con l'opzione dell'IA")


func test_transito_presidio_ed_evento_della_flotta(t: TestContext) -> void:
	var s := _world()
	for a in s.armies_in(W.NORD).duplicate():
		s.remove_army(a)
	var f := W.fleet(s, W.A, W.NORD)
	f.stacks.append(UnitStack.new("Galley", 1, 0))
	f.stacks.append(UnitStack.new("Galley", 1, 0))
	var gold := s.faction(W.A).treasury
	LegendarySiteProcessor.process_year(s)
	t.assert_eq(f.stacks.size(), 2, "primo anno: transito al 100% (una nave persa)")
	t.assert_eq(W.events_of(s, GameState.EV_SITE_TRANSIT).size(), 1)
	t.assert_eq(s.faction(W.A).treasury, gold + 300, "evento condizionato della flotta")
	s.year += 1
	s.events.clear()
	LegendarySiteProcessor.process_year(s)
	t.assert_eq(LegendarySites.garrison_holder(s, s.rules.sites.site("gorgo")), W.A, "presidio dopo due anni")
	t.assert_eq(LegendarySites.faction_value(s, W.A, "commercio_marittimo"), 50.0)
	var gorgo := 0
	for e in W.events_of(s, GameState.EV_SITE_EVENT):
		if str(e["luogo"]) == "gorgo":
			gorgo += 1
	t.assert_eq(gorgo, 0, "attesa di tre anni tra due eventi")
	s.year += 1
	s.events.clear()
	LegendarySiteProcessor.process_year(s)
	t.assert_eq(W.events_of(s, GameState.EV_SITE_TRANSIT).size(), 0, "chi presidia e' immune al transito")
	var other := W.fleet(s, W.B, W.NORD)
	LegendarySiteProcessor.process_year(s)
	t.assert_eq(LegendarySites.garrison_holder(s, s.rules.sites.site("gorgo")), "", "zona contesa: niente presidio")
	t.assert_true(other.stacks.is_empty() or not s.armies.has(other), "la flotta straniera paga il transito")


func test_salvataggio_dello_stato_dei_luoghi(t: TestContext) -> void:
	var s := _world()
	s.faction(W.A).is_player = true
	LegendarySiteProcessor.ensure_init(s)
	LegendarySiteProcessor.process_year(s)
	s.year += 1
	LegendarySiteProcessor.process_year(s)
	LegendarySiteProcessor.discover_seen(s, W.A, {W.ALTA: true})
	var data: Variant = JSON.parse_string(JSON.stringify(LegendarySiteProcessor.save_data(s)))
	var s2 := _world()
	LegendarySiteProcessor.load_data(s2, data)
	t.assert_eq(s2.site_choices.size(), 1, "scelta in attesa salvata")
	t.assert_eq(typeof(s2.site_choices[0]["id"]), TYPE_INT)
	t.assert_true(LegendarySiteProcessor.is_discovered(s2, W.A, "tempio"), "luoghi scoperti salvati")
	t.assert_false(LegendarySiteProcessor.is_discovered(s2, W.A, "gorgo"), "il mare non visto resta nascosto")
	t.assert_eq(int((s2.sites_state["tempio"]["prossimo"] as Dictionary)["tempio_scelta"]), int((s.sites_state["tempio"]["prossimo"] as Dictionary)["tempio_scelta"]))


func test_luogo_fantasma(t: TestContext) -> void:
	var site := LegendarySites.Site.new()
	site.id = "isola"
	site.phantom_every = 7
	var seen := 0
	for y in range(1000, 1070):
		if LegendarySites.manifests(site, y):
			seen += 1
	t.assert_eq(seen, 10, "un anno ogni sette")


## Bussola nell'angolo in basso a sinistra della minimappa (richiesta di Federico del 26/11/2026): nascosta finche' la
## mappa non la mostra, dentro la minimappa, e un clic apre i medaglioni di tutti i luoghi scoperti.
func test_bussola_della_minimappa_apre_tutti_i_medaglioni(t: TestContext) -> void:
	var hud := OriginalHud.new()
	hud._ready()
	var b := hud.sites_button()
	t.assert_true(b != null and not b.visible, "nascosta finche' non ci sono luoghi")
	hud.set_sites_button(true, false, "Luoghi")
	t.assert_true(b.visible)
	t.assert_eq(b.tooltip_text, "Luoghi")
	var mini := Rect2(Vector2(hud._mini_frame(), hud._mini_frame()), Vector2(OriginalHud.MINI_W, OriginalHud.MINI_H))
	t.assert_true(mini.encloses(Rect2(b.position, b.size)), "dentro la minimappa")
	t.assert_true(b.position.x - mini.position.x < 8.0 and mini.end.y - (b.position.y + b.size.y) < 8.0, "angolo in basso a sinistra")
	var hits := [0]
	hud.sites_pressed.connect(func() -> void: hits[0] += 1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	hud._on_compass_input(click)
	t.assert_eq(hits[0], 1, "il clic manda il segnale")
	hud.free()
	var layer := SiteLayer.new()
	layer.set_view(Vector2(400, 300), 1.0, Vector2(800, 600))
	var list: Array[Dictionary] = [{"id": "a", "pos": Vector2(400, 300), "categoria": "storico", "simbolo": "tempio", "nome": "A"}]
	layer.set_sites(list)
	var p := layer.screen_point("a")
	t.assert_eq(layer.site_at(p + Vector2(15, 0)), "", "col pallino a 15 px non c'e' il luogo")
	layer.set_show_all(true)
	t.assert_true(layer.show_all())
	t.assert_eq(layer.site_at(p + Vector2(15, 0)), "a", "col medaglione aperto si'")
	layer.free()


## Richiesta di Federico del 27/11/2026: eventi dei luoghi meno frequenti. [generale] allunga gli intervalli, abbassa le
## probabilita' sotto il 100% e limita gli eventi per fazione e anno; senza la sezione nulla cambia.
func test_frequenza_degli_eventi(t: TestContext) -> void:
	var plain := LegendarySites.parse_text(CATALOGO)
	t.assert_eq(plain.interval_of(plain.event("tempio_scelta")), Vector2i(1, 1), "senza [generale]")
	t.assert_eq(plain.max_per_faction, 0)
	var cat := LegendarySites.parse_text("[generale]\nscala_intervalli=1.5\nscala_probabilita=0.5\nmax_eventi_fazione_anno=1\n" + CATALOGO + """
[evento.tempio_raro]
luogo="tempio"
tipo="condizionato"
chi="generale"
probabilita=30
titolo="Raro"
testo="Testo"
esito={"tesoro": 1}
""")
	t.assert_true(cat.errors.is_empty(), str(cat.errors))
	t.assert_true(cat.site("generale") == null, "[generale] non e' un luogo")
	t.assert_eq(cat.interval_of(cat.event("tempio_scelta")), Vector2i(2, 2), "1 x 1,5 arrotondato")
	t.assert_eq(cat.chance_of(cat.event("tempio_raro")), 15, "30% x 0,5")
	t.assert_eq(cat.chance_of(cat.event("gorgo_eroe")), 100, "gli eventi certi restano certi")
	# tetto: due eventi ricorrenti pronti nello stesso anno per la stessa fazione -> ne avviene uno solo
	for cap in [0, 1]:
		var s := W.world()
		s.rules.sites = LegendarySites.parse_text(("[generale]\nmax_eventi_fazione_anno=%d\n" % cap) + """
[fonte]
categoria="storico"
simbolo="tempio"
regione="ID_ALTA"
nome="Fonte"
eventi=["fonte_uno", "fonte_due"]

[evento.fonte_uno]
luogo="fonte"
tipo="ricorrente"
ogni=[1, 1]
titolo="Uno"
testo="Testo"
esito={"tesoro": 10}

[evento.fonte_due]
luogo="fonte"
tipo="ricorrente"
ogni=[1, 1]
titolo="Due"
testo="Testo"
esito={"tesoro": 10}
""")
		t.assert_true(s.rules.sites.errors.is_empty(), str(s.rules.sites.errors))
		LegendarySiteProcessor.ensure_init(s)
		LegendarySiteProcessor.process_year(s)
		for year in 3:
			s.year += 1
			s.events.clear()
			LegendarySiteProcessor.process_year(s)
			t.assert_eq(W.events_of(s, GameState.EV_SITE_EVENT).size(), 2 if cap == 0 else 1, "tetto %d, anno %d" % [cap, year])



## Richiesta di Federico del 28/11/2026: Roma a sud del porto della regione di Roma.
func test_roma_a_sud_del_porto(t: TestContext) -> void:
	var sites := LegendarySites.load_file()
	var port := Vector2.ZERO
	for line in FileAccess.get_file_as_string("res://data/mappa_mondo/startpos_mondo.txt").split("\n"):
		var parts := line.split("\t", false)
		if parts.size() >= 4 and parts[0].strip_edges() == "SetPort::" and parts[1].strip_edges() == "ID_ROME":
			port = Vector2(float(parts[2]), float(parts[3])) / 16.0
	var roma = sites.site("roma")
	t.assert_true(port != Vector2.ZERO, "Roma ha il porto")
	t.assert_true(roma.position.y > port.y and roma.position.distance_to(port) < 40.0, "a sud del porto: %s, porto %s" % [roma.position, port])
