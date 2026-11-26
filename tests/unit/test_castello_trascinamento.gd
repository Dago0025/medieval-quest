extends RefCounted
## Test del trascinamento sui castelli e della selezione del castello (richiesta di Federico del 2026-11-10):
## sul proprio castello si barricano le unita' che ci stanno (le altre restano fuori), anche arrivando da una provincia
## confinante; sul castello nemico si assedia (movimento) o si assalta (assedio gia' in corso). Il clic sul castello
## mostra la guarnigione nel pannello di rassegna. Anche: icone degli edifici nella cartella Christian, pedine a destra.
## Mondo piccolo tests/fixtures/sim_*.txt: ALPHA ha ID_ALTA (Castle3) e ID_BASSA (Castle); BETA ha ID_MEZZA (Castle2)
## con l'esercito 4; l'esercito 1 e' di ALPHA in ALTA, il 3 di ALPHA in BASSA. ALTA-BASSA-MEZZA-SOLA in fila.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const ArmyLayerScript := preload("res://scenes/army_layer.gd")


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


func _end_year(s: GameState) -> void:
	s.events.clear()
	TurnProcessor.end_year(s)


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


## Esercito di `faction` in `region` con `infantry` pile di fanti e `cavalry` di cavalieri (prima i cavalieri).
func _army(s: GameState, faction: String, region: String, infantry: int, cavalry: int) -> Army:
	var a := s.create_army(faction, region, false)
	for i in cavalry:
		a.stacks.append(UnitStack.new("Knights", 40, 0))
	for i in infantry:
		a.stacks.append(UnitStack.new("Spearmen", 100, 0))
	return a


func _garrison_weight(s: GameState, region: String) -> int:
	return Combat.garrison_load(s, region)


# --- barricarsi con le unita' che ci stanno ------------------------------------------------------------------------


func test_l_esercito_che_entra_tutto_si_barrica_intero(t: TestContext) -> void:
	var s := _world()
	var a := s.army(1)
	var before := a.stacks.size()
	var r := GameCommands.garrison_castle(s, "FN_ALPHA", a.id)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_true(a.in_castle)
	t.assert_eq(int(r["dentro"]), before)
	t.assert_eq(int(r["fuori"]), 0)
	t.assert_eq(int(r["rimasto_fuori"]), 0, "nessun esercito nuovo")


func test_entrano_le_unita_che_ci_stanno_le_altre_restano_fuori(t: TestContext) -> void:
	var s := _world()
	# 6 cavalieri (peso 12) e 10 fanti: 22 di peso, il castello ne tiene 16
	var a := _army(s, "FN_ALPHA", "ID_BASSA", 10, 6)
	var armies_before := s.armies_in("ID_BASSA").size()
	var r := GameCommands.garrison_castle(s, "FN_ALPHA", a.id)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_true(a.in_castle, "l'esercito resta lui, nel castello")
	t.assert_eq(_garrison_weight(s, "ID_BASSA"), 16)
	t.assert_true(_garrison_weight(s, "ID_BASSA") <= s.rules.combat.garrison_max, "mai oltre il massimo")
	var outside := s.army(int(r["rimasto_fuori"]))
	t.assert_true(outside != null, "le pile che non entrano formano un esercito fuori")
	t.assert_false(outside.in_castle)
	t.assert_eq(outside.region, "ID_BASSA")
	t.assert_eq(s.armies_in("ID_BASSA").size(), armies_before + 1)
	t.assert_eq(int(r["dentro"]) + int(r["fuori"]), 16)
	t.assert_eq(int(r["dentro"]), a.stacks.size())
	t.assert_eq(int(r["fuori"]), outside.stacks.size())


func test_si_riempie_il_castello_anche_saltando_la_cavalleria_che_non_entra(t: TestContext) -> void:
	var s := _world()
	# l'esercito 3 (fanti) e' gia' dentro; restano 16 - peso dell'esercito 3 posti
	GameCommands.enter_castle(s, "FN_ALPHA", 3)
	var free := s.rules.combat.garrison_max - _garrison_weight(s, "ID_BASSA")
	# un cavaliere in testa (peso 2), poi fanti: con un solo posto libero il cavaliere resta fuori e un fante entra
	var a := s.create_army("FN_ALPHA", "ID_BASSA", false)
	for i in free - 1:
		a.stacks.append(UnitStack.new("Spearmen", 100, 0))
	a.stacks.append(UnitStack.new("Knights", 40, 0))
	a.stacks.append(UnitStack.new("Spearmen", 100, 0))
	var r := GameCommands.garrison_castle(s, "FN_ALPHA", a.id)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_eq(_garrison_weight(s, "ID_BASSA"), s.rules.combat.garrison_max, "castello pieno")
	var outside := s.army(int(r["rimasto_fuori"]))
	t.assert_eq(outside.stacks.size(), 1)
	t.assert_eq(outside.stacks[0].unit_id, "Knights")


func test_il_comandante_resta_con_la_parte_che_si_barrica(t: TestContext) -> void:
	var s := _world()
	var a := s.army(1)
	var commander := s.commander_of(a.id)
	while a.stacks.size() < 16:
		a.stacks.append(UnitStack.new("Knights", 40, 0))
	var r := GameCommands.garrison_castle(s, "FN_ALPHA", a.id)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_true(int(r["rimasto_fuori"]) > 0)
	t.assert_true(s.commander_of(a.id) == commander, "stesso comandante nel castello")


func test_il_controllo_dice_quante_pile_entrano_senza_cambiare_nulla(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, "FN_ALPHA", "ID_BASSA", 10, 6)
	var count := s.armies.size()
	var r := GameCommands.can_garrison_castle(s, "FN_ALPHA", a.id)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_eq(int(r["dentro"]), 10)
	t.assert_eq(int(r["fuori"]), 6)
	t.assert_false(a.in_castle)
	t.assert_eq(s.armies.size(), count)


func test_castello_pieno_nessuno_entra(t: TestContext) -> void:
	var s := _world()
	var full := _army(s, "FN_ALPHA", "ID_BASSA", 16, 0)
	GameCommands.enter_castle(s, "FN_ALPHA", full.id)
	var r := GameCommands.garrison_castle(s, "FN_ALPHA", 3)
	t.assert_false(bool(r["ok"]))
	t.assert_true(str(r["errore"]).contains("posto"))
	t.assert_false(s.army(3).in_castle)


func test_non_ci_si_barrica_nel_castello_altrui(t: TestContext) -> void:
	var s := _world()
	var a := s.army(3)
	a.region = "ID_MEZZA"
	t.assert_false(bool(GameCommands.garrison_castle(s, "FN_ALPHA", a.id)["ok"]))
	t.assert_false(bool(GameCommands.garrison_castle(s, "FN_ALPHA", 2)["ok"]), "flotta")


# --- le reclute nel castello (richiesta di Federico, 2026-11-10) ----------------------------------------------------


func _recruit_one(s: GameState, province: String, unit_id: String) -> Army:
	var before := {}
	for a in s.armies:
		before[a.id] = a.stacks.size()
	var r := GameCommands.queue_unit(s, s.province(province).owner, province, unit_id)
	assert(bool(r["ok"]), str(r.get("errore", "")))
	_end_year(s)
	for e in _events_of(s, GameState.EV_RECRUITED):
		if str(e["provincia"]) == province:
			return s.army(int(e["esercito"]))
	return null


func test_la_recluta_entra_nel_castello_se_c_e_posto(t: TestContext) -> void:
	var s := _world()
	var a := _recruit_one(s, "ID_ALTA", "Spearmen")
	t.assert_true(a != null, "reclutata")
	t.assert_true(a.in_castle, "nel castello")
	t.assert_eq(a.region, "ID_ALTA")
	t.assert_true(s.army(1).stacks.size() == 2 or not s.army(1).in_castle, "l'esercito in campo non la riceve")


func test_le_reclute_si_sommano_alla_guarnigione(t: TestContext) -> void:
	var s := _world()
	var first := _recruit_one(s, "ID_ALTA", "Spearmen")
	var second := _recruit_one(s, "ID_ALTA", "Spearmen")
	t.assert_eq(second.id, first.id, "stessa guarnigione")
	t.assert_eq(first.stacks.size(), 2)


func test_castello_pieno_la_recluta_va_in_campo(t: TestContext) -> void:
	var s := _world()
	var full := _army(s, "FN_ALPHA", "ID_ALTA", 16, 0)
	GameCommands.enter_castle(s, "FN_ALPHA", full.id)
	var a := _recruit_one(s, "ID_ALTA", "Spearmen")
	t.assert_false(a.in_castle, "fuori: il castello e' pieno")
	t.assert_true(full.in_castle and full.stacks.size() == 16)


func test_la_cavalleria_che_non_entra_va_in_campo(t: TestContext) -> void:
	var s := _world()
	var g := _army(s, "FN_ALPHA", "ID_ALTA", 15, 0)
	GameCommands.enter_castle(s, "FN_ALPHA", g.id)
	# un posto libero: un cavaliere (peso 2) non entra
	var p := s.province("ID_ALTA")
	p.unit_queue.append(QueueItem.new(QueueItem.KIND_UNIT, "Knights", 0, 1, 0))
	_end_year(s)
	var knights: Army = null
	for a in s.armies_in("ID_ALTA"):
		for st in a.stacks:
			if st.unit_id == "Knights":
				knights = a
	t.assert_true(knights != null, "cavaliere reclutato")
	t.assert_false(knights.in_castle, "fuori dal castello")


func test_senza_castello_la_recluta_va_in_campo(t: TestContext) -> void:
	var s := _world()
	s.province("ID_BASSA").buildings.erase("CASTLE")
	var p := s.province("ID_BASSA")
	p.unit_queue.append(QueueItem.new(QueueItem.KIND_UNIT, "Spearmen", 0, 1, 0))
	_end_year(s)
	for a in s.armies_in("ID_BASSA"):
		t.assert_false(a.in_castle)


func test_la_guarnigione_resta_nel_castello_anche_senza_nemici(t: TestContext) -> void:
	var s := _world()
	var a := _recruit_one(s, "ID_ALTA", "Spearmen")
	_end_year(s)
	_end_year(s)
	t.assert_true(a.in_castle, "resta dentro finche' non la si fa uscire o muovere")
	t.assert_true(bool(GameCommands.order_move(s, "FN_ALPHA", a.id, PackedStringArray(["ID_BASSA"]))["ok"]), "puo' partire")
	_end_year(s)
	t.assert_eq(a.region, "ID_BASSA")
	t.assert_false(a.in_castle, "chi si muove esce dal castello")


# --- barricarsi all'arrivo ---------------------------------------------------------------------------------------


func test_trascinato_sul_castello_di_una_provincia_confinante_vi_si_barrica_all_arrivo(t: TestContext) -> void:
	var s := _world()
	var a := s.army(1)   # ALPHA in ALTA, BASSA confina
	var r := GameCommands.order_garrison_move(s, "FN_ALPHA", a.id, "ID_BASSA")
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_eq(a.path, PackedStringArray(["ID_BASSA"]))
	t.assert_true(a.garrison_on_arrival)
	_end_year(s)
	t.assert_eq(a.region, "ID_BASSA")
	t.assert_false(a.garrison_on_arrival, "l'ordine si consuma all'arrivo")
	t.assert_eq(_events_of(s, GameState.EV_ARMY_GARRISONED).size(), 1)


func test_barricato_all_arrivo_il_nemico_che_arriva_assedia(t: TestContext) -> void:
	var s := _world()
	s.declare_war("FN_ALPHA", "FN_BETA")
	GameCommands.order_garrison_move(s, "FN_ALPHA", 1, "ID_BASSA")
	var enemy := s.army(4)   # BETA in MEZZA, confina con BASSA
	GameCommands.order_move(s, "FN_BETA", enemy.id, PackedStringArray(["ID_BASSA"]))
	# la guarnigione dell'esercito 3 lascia il posto: fuori, va altrove
	GameCommands.order_move(s, "FN_ALPHA", 3, PackedStringArray(["ID_ALTA"]))
	_end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_BATTLE).size(), 0, "nessuna battaglia in campo")
	t.assert_true(s.army(1).in_castle)
	t.assert_true(s.is_besieged("ID_BASSA"))


func test_un_nuovo_ordine_toglie_la_barricata_all_arrivo(t: TestContext) -> void:
	var s := _world()
	var a := s.army(1)
	GameCommands.order_garrison_move(s, "FN_ALPHA", a.id, "ID_BASSA")
	GameCommands.order_move(s, "FN_ALPHA", a.id, PackedStringArray(["ID_BASSA"]))
	t.assert_false(a.garrison_on_arrival)
	GameCommands.order_garrison_move(s, "FN_ALPHA", a.id, "ID_BASSA")
	GameCommands.cancel_move(s, "FN_ALPHA", a.id)
	t.assert_false(a.garrison_on_arrival)


func test_la_barricata_all_arrivo_cade_se_la_provincia_non_e_piu_propria(t: TestContext) -> void:
	var s := _world()
	var a := s.army(1)
	GameCommands.order_garrison_move(s, "FN_ALPHA", a.id, "ID_BASSA")
	s.province("ID_BASSA").owner = "FN_BETA"
	s.declare_war("FN_ALPHA", "FN_BETA")
	_end_year(s)
	t.assert_false(a.in_castle and a.region == "ID_BASSA" and s.province("ID_BASSA").owner == "FN_BETA", "non si barrica nel castello altrui")
	t.assert_false(a.garrison_on_arrival)


func test_barricata_all_arrivo_solo_verso_un_proprio_castello(t: TestContext) -> void:
	var s := _world()
	t.assert_false(bool(GameCommands.order_garrison_move(s, "FN_ALPHA", 3, "ID_MEZZA")["ok"]), "castello altrui")
	t.assert_false(bool(GameCommands.order_garrison_move(s, "FN_ALPHA", 1, "ID_ALTA")["ok"]), "e' gia' li': si barrica subito")
	t.assert_false(bool(GameCommands.order_garrison_move(s, "FN_ALPHA", 2, "ID_BASSA")["ok"]), "flotta")


func test_la_barricata_all_arrivo_si_salva(t: TestContext) -> void:
	var s := _world()
	var a := s.army(1)
	GameCommands.order_garrison_move(s, "FN_ALPHA", a.id, "ID_BASSA")
	t.assert_true(Army.from_dict(a.to_dict()).garrison_on_arrival)
	t.assert_false(s.army(3).to_dict().has("barrica_all_arrivo"), "la chiave compare solo se serve")


# --- piano del rilascio sul castello (interfaccia) -----------------------------------------------------------------


func test_sul_proprio_castello_della_stessa_regione_ci_si_barrica(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(str(CampaignUiCastle.drop_plan(s, "FN_ALPHA", s.army(1), "ID_ALTA")["azione"]), CampaignUiCastle.BARRICATA)


func test_sul_proprio_castello_confinante_si_va_e_ci_si_barrica(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(str(CampaignUiCastle.drop_plan(s, "FN_ALPHA", s.army(1), "ID_BASSA")["azione"]), CampaignUiCastle.VAI_E_BARRICATI)


func test_dentro_il_proprio_castello_non_cambia_nulla(t: TestContext) -> void:
	var s := _world()
	GameCommands.enter_castle(s, "FN_ALPHA", 1)
	var plan := CampaignUiCastle.drop_plan(s, "FN_ALPHA", s.army(1), "ID_ALTA")
	t.assert_eq(str(plan["azione"]), CampaignUiCastle.NIENTE)
	t.assert_true(str(plan["testo"]).contains("già"))


func test_sul_castello_nemico_si_va_ad_assediarlo(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(str(CampaignUiCastle.drop_plan(s, "FN_ALPHA", s.army(3), "ID_MEZZA")["azione"]), CampaignUiCastle.ASSEDIO)


func test_sul_castello_assediato_dalla_propria_regione_si_ordina_l_assalto(t: TestContext) -> void:
	var s := _world()
	s.declare_war("FN_ALPHA", "FN_BETA")
	GameCommands.enter_castle(s, "FN_BETA", 4)
	var a := s.army(3)
	a.region = "ID_MEZZA"
	WarProcessor.refresh_sieges(s)
	t.assert_true(s.is_besieged("ID_MEZZA"))
	t.assert_eq(str(CampaignUiCastle.drop_plan(s, "FN_ALPHA", a, "ID_MEZZA")["azione"]), CampaignUiCastle.ASSALTO)
	GameCommands.order_assault(s, "FN_ALPHA", a.id)
	var again := CampaignUiCastle.drop_plan(s, "FN_ALPHA", a, "ID_MEZZA")
	t.assert_eq(str(again["azione"]), CampaignUiCastle.NIENTE)
	t.assert_true(str(again["testo"]).contains("assalto"))


func test_le_flotte_non_vanno_nei_castelli(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(str(CampaignUiCastle.drop_plan(s, "FN_ALPHA", s.army(2), "ID_ALTA")["azione"]), CampaignUiCastle.NIENTE)


# --- rassegna del castello (clic) ----------------------------------------------------------------------------------


func test_la_rassegna_del_castello_mostra_tutte_le_unita_della_guarnigione(t: TestContext) -> void:
	var s := _world()
	GameCommands.enter_castle(s, "FN_ALPHA", 3)
	var extra := _army(s, "FN_ALPHA", "ID_BASSA", 2, 1)
	GameCommands.enter_castle(s, "FN_ALPHA", extra.id)
	var info := CampaignUiCastle.review(s, "ID_BASSA", "FN_ALPHA", true)
	var cards: Array = info["carte"]
	t.assert_eq(cards.size(), s.army(3).stacks.size() + 3)
	t.assert_eq(int(cards[0]["esercito"]), 3)
	t.assert_eq(int(cards[cards.size() - 1]["esercito"]), extra.id)
	t.assert_true(str(info["titolo"]).begins_with("Castello"))
	var joined := "\n".join(PackedStringArray(info["righe"]))
	t.assert_true(joined.contains("%d/%d" % [Combat.garrison_load(s, "ID_BASSA"), s.rules.combat.garrison_max]), joined)


func test_castello_vuoto_lo_dice(t: TestContext) -> void:
	var s := _world()
	var info := CampaignUiCastle.review(s, "ID_ALTA", "FN_ALPHA", true)
	t.assert_eq((info["carte"] as Array).size(), 0)
	t.assert_true("\n".join(PackedStringArray(info["righe"])).contains("Nessuna"))


func test_castello_altrui_fuori_vista_non_mostra_la_guarnigione(t: TestContext) -> void:
	var s := _world()
	GameCommands.enter_castle(s, "FN_BETA", 4)
	var info := CampaignUiCastle.review(s, "ID_MEZZA", "FN_ALPHA", false)
	t.assert_eq((info["carte"] as Array).size(), 0)
	t.assert_true("\n".join(PackedStringArray(info["righe"])).contains("fuori vista"))
	var seen := CampaignUiCastle.review(s, "ID_MEZZA", "FN_ALPHA", true)
	t.assert_eq((seen["carte"] as Array).size(), s.army(4).stacks.size())


## Richiesta di Federico dell'11/11/2026: nella barra il castello ha la sua icona, il nome del tipo in grassetto e, accanto,
## le armate che ci stanno dentro, una per gruppo.
func test_la_rassegna_del_castello_da_tipo_livello_e_nota_della_guarnigione(t: TestContext) -> void:
	var s := _world()
	var info := CampaignUiCastle.review(s, "ID_BASSA", "FN_ALPHA", true)
	var level := s.province("ID_BASSA").level_of(s.rules.combat.castle_family)
	t.assert_eq(int(info["livello"]), level)
	t.assert_eq(str(info["famiglia"]), s.rules.combat.castle_family)
	t.assert_true(str(info["tipo"]) != "", "nome del tipo di castello")
	t.assert_false(str(info["tipo"]).contains("livello"), "senza il livello tra parentesi: " + str(info["tipo"]))
	t.assert_eq(str(info["nota"]), "Guarnigione %d/%d" % [Combat.garrison_load(s, "ID_BASSA"), s.rules.combat.garrison_max])
	t.assert_false(str(info["titolo"]).contains(str(info["tipo"])), "il tipo non si ripete nel titolo: " + str(info["titolo"]))
	t.assert_true(str(info["titolo"]).begins_with("Castello"))


func test_le_armate_nel_castello_sono_un_gruppo_ciascuna(t: TestContext) -> void:
	var s := _world()
	GameCommands.enter_castle(s, "FN_ALPHA", 3)
	var extra := _army(s, "FN_ALPHA", "ID_BASSA", 2, 1)
	GameCommands.enter_castle(s, "FN_ALPHA", extra.id)
	var info := CampaignUiCastle.review(s, "ID_BASSA", "FN_ALPHA", true)
	var entries := CampaignUiCastle.review_entries(s, info)
	var cards: Array = info["carte"]
	t.assert_eq(entries.size(), cards.size() + 2, "una intestazione per armata, poi le sue carte")
	t.assert_eq(str(entries[0]["intestazione"]), "Esercito 3")
	t.assert_eq(int(entries[0]["esercito"]), 3)
	t.assert_false(entries[1].has("intestazione"))
	t.assert_eq(int(entries[1]["esercito"]), 3)
	t.assert_eq(int(entries[1]["pila"]), 0)
	var second := s.army(3).stacks.size() + 1
	t.assert_eq(str(entries[second]["intestazione"]), "Esercito %d" % extra.id)
	t.assert_eq(int(entries[second + 1]["esercito"]), extra.id)
	var headers := 0
	for e in entries:
		if e.has("intestazione"):
			headers += 1
	t.assert_eq(headers, 2)


func test_l_intestazione_dell_armata_nomina_il_comandante_nel_suggerimento(t: TestContext) -> void:
	var s := _world()
	GameCommands.enter_castle(s, "FN_ALPHA", 3)
	var c := s.commander_of(3)
	if c == null:
		c = s.create_character("FN_ALPHA")
		c.role = Character.ROLE_GENERAL
		c.forename = "Ugo"
		c.male = true
		c.birth_year = s.year - 30
		c.army = 3
	var info := CampaignUiCastle.review(s, "ID_BASSA", "FN_ALPHA", true)
	var entries := CampaignUiCastle.review_entries(s, info)
	t.assert_true(str(entries[0]["suggerimento"]).contains(c.full_name()), str(entries[0]["suggerimento"]))


func test_castello_vuoto_non_ha_gruppi(t: TestContext) -> void:
	var s := _world()
	var info := CampaignUiCastle.review(s, "ID_ALTA", "FN_ALPHA", true)
	t.assert_eq(CampaignUiCastle.review_entries(s, info).size(), 0)


# --- pedine a destra del castello, icone degli edifici ----------------------------------------------------------------


func test_le_pedine_di_campo_stanno_tutte_a_destra_del_castello(t: TestContext) -> void:
	for count in [1, 3, 6, 9]:
		var layout := MarkerLayout.mixed_slots(count, 2, ArmyLayerScript.SLOT_SPACING)
		var side := ArmyLayerScript.castle_side_offset()
		var shift := MarkerLayout.castle_shift(layout, side)
		var all: PackedVector2Array = layout["eserciti"] + layout["agenti"]
		for slot in all:
			t.assert_true(slot.x + shift.x >= side.x - 0.001, "slot %s con %d pedine a sinistra del bordo" % [slot, count])


## Federico (15/11/2026): zoomando sulle regioni i castelli non devono diventare minuscoli. Fino al limite delle pedine
## castelli e porti crescono con loro; oltre continuano fino a STRUCTURE_MAX_SCALE,
## e le pedine a destra del castello si spostano di conseguenza.
func test_castelli_e_porti_crescono_con_lo_zoom_oltre_le_pedine(t: TestContext) -> void:
	var near := 1.0
	t.assert_eq(ArmyLayerScript.structure_scale_at(near), clampf(ArmyLayerScript.PIECE_WORLD_HEIGHT * near / ArmyLayerScript.BASE_HEIGHT, ArmyLayerScript.PIECE_MIN_SCALE, ArmyLayerScript.PIECE_MAX_SCALE), "a zoom normale come le pedine")
	t.assert_true(ArmyLayerScript.structure_scale_at(3.0) > ArmyLayerScript.PIECE_MAX_SCALE, "da vicino piu' grandi del limite delle pedine")
	t.assert_true(ArmyLayerScript.CASTLE_HEIGHT * ArmyLayerScript.structure_scale_at(8.0) > 66.0 * ArmyLayerScript.PIECE_MAX_SCALE, "allo zoom massimo piu' grande del castello di prima del -40%")
	t.assert_eq(ArmyLayerScript.structure_scale_at(100.0), ArmyLayerScript.STRUCTURE_MAX_SCALE, "con un limite")
	t.assert_true(ArmyLayerScript.castle_side_offset(1.6).x > ArmyLayerScript.castle_side_offset().x, "castello piu' grande: pedine piu' a destra")


func test_corti_e_tenute_cattoliche_e_ortodosse_dalla_cartella_christian(t: TestContext) -> void:
	var root := BuildingArt.ROOT
	var paths := [root + "baronial estate.bif", root + "christian/baronial estate.bif", root + "muslim/baronial estate.bif", root + "pagan/baronial estate.bif"]
	t.assert_eq(BuildingArt.choose(paths, "CATHOLIC"), root + "christian/baronial estate.bif")
	t.assert_eq(BuildingArt.choose(paths, "ORTHODOX"), root + "christian/baronial estate.bif")
	t.assert_eq(BuildingArt.choose(paths, "MUSLIM"), root + "muslim/baronial estate.bif")
	t.assert_eq(BuildingArt.choose(paths, ""), root + "christian/baronial estate.bif", "senza religione: mai il segnaposto")
	var church := [root + "church.bif", root + "catholic/church.bif", root + "orthodox/church.bif"]
	t.assert_eq(BuildingArt.choose(church, "CATHOLIC"), root + "catholic/church.bif", "la cartella della religione prima di Christian")
	t.assert_eq(BuildingArt.choose(church, "ORTHODOX"), root + "orthodox/church.bif")
	var mosque := [root + "mosque.bif", root + "muslim/mosque.bif"]
	t.assert_eq(BuildingArt.choose(mosque, "CATHOLIC"), root + "muslim/mosque.bif", "edificio di un'altra religione: la sua variante, non il segnaposto")
	var plain := [root + "bowyer.bif"]
	t.assert_eq(BuildingArt.choose(plain, "CATHOLIC"), root + "bowyer.bif")


# --- pedine dentro i confini della regione ----------------------------------------------------------------------------


func test_le_pedine_restano_dentro_la_regione(t: TestContext) -> void:
	# regione a forma di striscia verticale 20 x 200 attorno all'ancora: a destra c'e' il mare
	var inside := func(p: Vector2) -> bool: return p.x >= -10.0 and p.x <= 10.0 and p.y >= -100.0 and p.y <= 100.0
	var offsets := PackedVector2Array([Vector2(40, 0), Vector2(70, 0), Vector2(100, 0), Vector2(0, 0)])
	var out := MarkerLayout.fit_positions(Vector2.ZERO, offsets, inside, 15.0, Rect2(-8, -20, 16, 20))
	t.assert_eq(out.size(), 4)
	for i in out.size():
		t.assert_true(bool(inside.call(out[i])), "pedina %d in %s fuori dalla regione" % [i, out[i]])
		t.assert_false(Rect2(-8, -20, 16, 20).has_point(out[i]), "pedina %d sul castello" % i)
		for j in i:
			t.assert_true(out[i].distance_to(out[j]) >= 15.0 * 0.8 - 0.01, "pedine %d e %d sovrapposte" % [i, j])


func test_le_pedine_gia_dentro_non_si_spostano(t: TestContext) -> void:
	var inside := func(_p: Vector2) -> bool: return true
	var offsets := PackedVector2Array([Vector2(30, 0), Vector2(60, 0)])
	var out := MarkerLayout.fit_positions(Vector2(100, 100), offsets, inside, 20.0)
	t.assert_eq(out[0], Vector2(130, 100))
	t.assert_eq(out[1], Vector2(160, 100))


func test_regione_minuscola_le_pedine_si_stringono_dentro(t: TestContext) -> void:
	var inside := func(p: Vector2) -> bool: return p.length() <= 5.0
	var out := MarkerLayout.fit_positions(Vector2.ZERO, PackedVector2Array([Vector2(30, 0), Vector2(60, 0), Vector2(90, 0)]), inside, 20.0)
	for p in out:
		t.assert_true(p.length() <= 5.0, "%s dentro" % p)


# --- pedine: solo il re ha la pedina del re ---------------------------------------------------------------------------


func test_le_dimensioni_delle_pedine(t: TestContext) -> void:
	t.assert_true(ArmyLayerScript.PIECE_HEIGHT < ArmyLayerScript.BASE_HEIGHT, "pedine piu' piccole della scala di castelli e porti")
	# agenti non piu' grandi delle figure degli eserciti: la cornice degli agenti rifatti e' meno alta (268 contro 460 px) ma la
	# base e' quasi uguale (148 e 150 px), quindi a schermo la base dell'agente resta entro il 10% di quella dell'esercito
	t.assert_true(ArmyLayerScript.AGENT_PIECE_HEIGHT / 268.0 * 148.0 <= ArmyLayerScript.PIECE_HEIGHT / 460.0 * 150.0 * 1.1, "agenti non piu' grandi delle figure degli eserciti")


# --- fortezze: un'intera armata (richiesta di Federico del 26/11/2026) ---------------------------------------------


func test_nella_fortezza_entra_un_intera_armata_anche_di_cavalleria(t: TestContext) -> void:
	var s := _world()
	var c := s.rules.combat
	t.assert_false(Combat.is_fortress(s, "ID_BASSA"), "il Castle non e' una fortezza")
	t.assert_eq(Combat.garrison_capacity(s, "ID_BASSA"), c.garrison_max)
	# grado Fortress = primo livello del grado fortress_tier
	s.province("ID_BASSA").set_level(c.castle_family, c.fortress_tier * c.castle_levels_per_tier + 1)
	t.assert_true(Combat.is_fortress(s, "ID_BASSA"))
	t.assert_eq(Combat.garrison_capacity(s, "ID_BASSA"), 20)
	for a in s.armies_in("ID_BASSA"):
		a.in_castle = false
	# armata piena: 12 cavalieri e 8 fanti (fuori dalle fortezze peserebbe 32)
	var a := _army(s, "FN_ALPHA", "ID_BASSA", 8, 12)
	t.assert_eq(a.stacks.size(), s.rules.max_stacks, "armata piena")
	t.assert_eq(Combat.garrison_weight(s, a), 20, "nella fortezza la cavalleria conta uno")
	var r := GameCommands.garrison_castle(s, "FN_ALPHA", a.id)
	t.assert_true(bool(r["ok"]), str(r.get("errore", "")))
	t.assert_eq(int(r["dentro"]), 20)
	t.assert_eq(int(r["fuori"]), 0, "nessuna pila resta fuori")
	# piena: un'altra pila non entra, con il messaggio della fortezza
	var b := _army(s, "FN_ALPHA", "ID_BASSA", 1, 0)
	var no := GameCommands.enter_castle(s, "FN_ALPHA", b.id)
	t.assert_false(bool(no["ok"]))
	t.assert_true(str(no["errore"]).contains("20"), str(no["errore"]))
