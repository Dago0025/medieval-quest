extends RefCounted
## Test della fase 8b sulle pile: unita' del comandante (pennacchio del re, dell'erede, del generale), scheda dell'unita' e
## vizi e virtu' in italiano. Mondo di prova: agent_world.gd (colonna 9 vuota: vince l'unita' piu' costosa).

const W := preload("res://tests/unit/agent_world.gd")


func _army(s: GameState, stacks: Array) -> Army:
	var a := s.create_army(W.A, W.BASSA, false)
	for entry in stacks:
		var row: Array = entry
		a.stacks.append(UnitStack.new(str(row[0]), int(row[1]), int(row[2])))
	return a


func test_la_pila_del_comandante(t: TestContext) -> void:
	var s := W.world()
	var a := _army(s, [["Spearmen", 100, 0], ["Knights", 40, 2], ["Archers", 60, 0]])
	t.assert_eq(CampaignUiText.commander_stack(s, a), -1, "senza comandante nessuna pila e' sua")
	t.assert_eq(CampaignUiText.commander_pennant(s, a), "")
	var c := W.add_general(s, W.A, W.BASSA)
	c.army = a.id
	t.assert_eq(CampaignUiText.commander_stack(s, a), 1, "il generale combatte con l'unita' piu' adatta (qui la piu' costosa)")
	t.assert_eq(CampaignUiText.commander_pennant(s, a), "campmap/is_noble_mon.BIF")
	t.assert_true(CampaignUiText.commander_stack_note(s, a).begins_with("Unità del generale"))
	c.role = Character.ROLE_LEADER
	t.assert_eq(CampaignUiText.commander_pennant(s, a), "campmap/is_king_mon.BIF", "la corona del re")
	t.assert_true(CampaignUiText.commander_stack_note(s, a).begins_with("Unità del re"))
	c.role = Character.ROLE_PRINCE
	t.assert_eq(CampaignUiText.commander_pennant(s, a), "campmap/is_heir_mon.BIF", "l'insegna dei principi")
	var u := s.units.get_unit("Spearmen")
	u.general_candidate = "PREFERRED"
	t.assert_eq(CampaignUiText.commander_stack(s, a), 0, "la colonna 9 PREFERRED vince sul costo")
	u.general_candidate = ""
	var fleet := s.create_army(W.A, W.NORD, true)
	fleet.stacks.append(UnitStack.new("Galley", 1, 0))
	t.assert_eq(CampaignUiText.commander_stack(s, fleet), -1, "le flotte no")


func test_scheda_dell_unita(t: TestContext) -> void:
	var s := W.world()
	var a := _army(s, [["Spearmen", 60, 3], ["Knights", 40, 0]])
	var info := CampaignUiUnitInfo.info(s, a, 0)
	t.assert_eq(str(info["unita"]), "Spearmen")
	t.assert_eq(str(info["tipo"]), "Fanteria")
	var rows := {}
	for r in info["righe"]:
		rows[str(r[0])] = str(r[1])
	t.assert_eq(rows.get("Uomini"), "60 su 100", "uomini attuali e pieni")
	t.assert_eq(rows.get("Valore"), "3")
	t.assert_eq(rows.get("Costo"), "100 fiorini")
	t.assert_true(rows.has("Carica") and rows.has("Mischia") and rows.has("Difesa") and rows.has("Armatura base"), str(rows))
	t.assert_eq(str(info["comandante"]), "", "nessun comandante")
	var c := W.add_general(s, W.A, W.BASSA)
	c.army = a.id
	c.role = Character.ROLE_LEADER
	t.assert_true(str(CampaignUiUnitInfo.info(s, a, 1)["comandante"]).begins_with("Unità del re"), "la scheda dice di chi e' la guardia")
	t.assert_true(CampaignUiUnitInfo.info(s, a, 5).is_empty(), "pila inesistente")
	t.assert_eq(str(CampaignUiUnitInfo.info(s, a, 1)["tipo"]), "Cavalleria")


## Scheda nuova (richiesta di Federico del 2026-11-15): dati divisi in stato della pila, combattimento, costi e arruolamento.
func test_la_scheda_divide_i_dati_in_sezioni(t: TestContext) -> void:
	var s := W.world()
	var a := _army(s, [["Spearmen", 60, 3]])
	a.stacks[0].weapon = 2
	var info := CampaignUiUnitInfo.info(s, a, 0)
	var stack: Dictionary = info["pila"]
	t.assert_eq(int(stack["uomini"]), 60)
	t.assert_eq(int(stack["pieni"]), 100)
	t.assert_eq(int(stack["valore"]), 3)
	t.assert_eq(int(stack["armi"]), 2)
	var fight := PackedStringArray()
	for r in info["combattimento"]:
		fight.append(str(r[0]))
		t.assert_eq((r as Array).size(), 3, "ogni valore ha il suo suggerimento")
	t.assert_true(fight.has("Carica") and fight.has("Mischia") and fight.has("Difesa") and fight.has("Armatura base"), str(fight))
	var costs := PackedStringArray()
	for r in info["costi"]:
		costs.append(str(r[0]))
	t.assert_eq(costs, PackedStringArray(["Costo", "Mantenimento", "Addestramento"]))
	var recruit := PackedStringArray()
	for r in info["arruolamento"]:
		recruit.append(str(r[0]))
	t.assert_true(recruit.has("Richiede") and recruit.has("Epoche"), str(recruit))
	var probe := CampaignUiUnitInfo.info_for_type(s, "Spearmen")
	t.assert_true((probe["pila"] as Dictionary).is_empty(), "un tipo non arruolato non ha lo stato della pila")
	t.assert_false((probe["combattimento"] as Array).is_empty())


func test_vizi_e_virtu_in_italiano(t: TestContext) -> void:
	var s := W.world()
	t.assert_eq(CampaignUiText.vnv_name(s, "fearsome"), "Capacità di comando")
	t.assert_eq(CampaignUiText.vnv_label(s, "fearsome", 3), "Grande condottiero")
	t.assert_eq(CampaignUiText.vnv_label(s, "fearsome", 9), "Condottiero leggendario", "oltre l'ultimo livello: l'ultimo titolo")
	t.assert_eq(CampaignUiText.vnv_label(s, "educated", 2), "Istruzione (livello 2)", "senza titoli: nome e livello")
	t.assert_eq(CampaignUiText.vnv_name(s, "secret_tyrant"), "Tirannia (segreto)")
	t.assert_eq(CampaignUiText.vnv_name(s, "catena_inventata"), "Catena Inventata", "sconosciuta: id leggibile")
	var cfg := ConfigFile.new()
	cfg.load("res://data/ui/vizi_virtu.cfg")
	for chain in s.rules.vnv.chains:
		t.assert_true(cfg.has_section_key("nomi", str(chain)), "nome italiano per la catena modellata %s" % chain)
		t.assert_true(cfg.has_section_key("livelli", str(chain)), "titoli dei livelli per %s" % chain)
		var titles: Array = cfg.get_value("livelli", str(chain))
		t.assert_eq(titles.size(), s.rules.vnv.level_count(str(chain)), "un titolo per livello: %s" % chain)


## Richiesta di Federico dell'11/11/2026: re e principi si riconoscono dalle carte della barra in basso, senza aprire la
## pergamena dell'esercito.
func test_il_distintivo_del_comandante_per_le_carte_della_barra(t: TestContext) -> void:
	var s := W.world()
	var a := _army(s, [["Spearmen", 100, 0], ["Knights", 40, 2], ["Archers", 60, 0]])
	t.assert_true(CampaignUiText.commander_badge(s, a, 1).is_empty(), "senza comandante nessun distintivo")
	var c := W.add_general(s, W.A, W.BASSA)
	c.army = a.id
	var badge := CampaignUiText.commander_badge(s, a, 1)
	t.assert_eq(str(badge["immagine"]), "campmap/is_noble_mon.BIF")
	t.assert_true(str(badge["nota"]).begins_with("Unità del generale"), str(badge["nota"]))
	t.assert_true(CampaignUiText.commander_badge(s, a, 0).is_empty(), "solo la pila del comandante")
	t.assert_true(CampaignUiText.commander_badge(s, a, 2).is_empty())
	c.role = Character.ROLE_LEADER
	t.assert_eq(str(CampaignUiText.commander_badge(s, a, 1)["immagine"]), "campmap/is_king_mon.BIF", "la corona del re")
	c.role = Character.ROLE_HEIR
	t.assert_eq(str(CampaignUiText.commander_badge(s, a, 1)["immagine"]), "campmap/is_heir_mon.BIF")
	t.assert_true(CampaignUiText.commander_badge(s, null, 0).is_empty())


func test_il_titolo_della_barra_dice_chi_comanda(t: TestContext) -> void:
	var s := W.world()
	var a := _army(s, [["Spearmen", 100, 0]])
	t.assert_eq(CampaignUiText.commander_caption(s, a), "", "senza comandante")
	var c := W.add_general(s, W.A, W.BASSA)
	c.army = a.id
	t.assert_eq(CampaignUiText.commander_caption(s, a), "generale %s" % c.full_name())
	c.role = Character.ROLE_LEADER
	t.assert_eq(CampaignUiText.commander_caption(s, a), "re %s" % c.full_name())
	c.role = Character.ROLE_HEIR
	t.assert_eq(CampaignUiText.commander_caption(s, a), "erede %s" % c.full_name())
	c.role = Character.ROLE_PRINCE
	t.assert_eq(CampaignUiText.commander_caption(s, a), "principe %s" % c.full_name())


func test_il_clic_destro_sulla_carta_del_comandante_apre_la_sua_scheda(t: TestContext) -> void:
	var s := W.world()
	var a := _army(s, [["Spearmen", 100, 0], ["Knights", 40, 2]])
	t.assert_eq(CampaignUiText.card_character(s, a, 1), 0, "senza comandante: la scheda dell'unita'")
	var c := W.add_general(s, W.A, W.BASSA)
	c.army = a.id
	t.assert_eq(CampaignUiText.card_character(s, a, 1), c.id)
	t.assert_eq(CampaignUiText.card_character(s, a, 0), 0, "le altre carte restano schede dell'unita'")
	t.assert_eq(CampaignUiText.card_character(s, null, 0), 0)


func test_la_sala_dei_regnanti(t: TestContext) -> void:
	var s := W.world()
	var list := CampaignUiText.rulers(s, W.A)
	t.assert_true(list.size() >= 2, "almeno due fazioni con un capo")
	t.assert_eq(str(list[0]["fazione"]), W.A, "il giocatore per primo")
	t.assert_eq(str(list[0]["tono"]), "proprio")
	var mine := s.leader_of(W.A)
	t.assert_eq(int(list[0]["personaggio"]), mine.id)
	t.assert_eq(str(list[0]["nome"]), mine.full_name())
	t.assert_eq(int(list[0]["province"]), s.provinces_of(W.A).size())
	s.declare_war(W.A, W.B)
	var seen := {}
	for e in CampaignUiText.rulers(s, W.A):
		seen[str(e["fazione"])] = str(e["tono"])
		t.assert_true(str(e["nome_fazione"]) != "" and int(e["eta"]) > 0)
	t.assert_eq(str(seen.get(W.B, "")), "guerra")
	# una fazione senza capo vivo non siede nella sala
	s.leader_of(W.B).alive = false
	for e in CampaignUiText.rulers(s, W.A):
		t.assert_true(str(e["fazione"]) != W.B)
