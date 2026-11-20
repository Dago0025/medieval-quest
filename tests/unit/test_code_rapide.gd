extends RefCounted
## Code di produzione a colpo d'occhio (richiesta di Federico del 2026-11-10): voci in coda di una provincia, elenco di
## tutte le province con le code, scorrimento rapido tra le province (anche solo quelle con qualcosa in coda).
## Mondo piccolo tests/fixtures/sim_*.txt: ALPHA ha ID_ALTA e ID_BASSA, BETA ha ID_MEZZA.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


func test_le_voci_in_coda_prima_gli_edifici_poi_le_unita(t: TestContext) -> void:
	var s := _world()
	t.assert_true(bool(GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")["ok"]))
	t.assert_true(bool(GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER")["ok"]))
	t.assert_true(bool(GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")["ok"]))
	var items := CampaignUiQueues.entries(s.province("ID_ALTA"))
	t.assert_eq(items.size(), 3)
	t.assert_eq(str(items[0]["tipo"]), QueueItem.KIND_BUILDING)
	t.assert_eq(str(items[0]["chiave"]), "BOWYER")
	t.assert_eq(int(items[0]["livello"]), 1)
	t.assert_true(int(items[0]["anni"]) > 0)
	t.assert_eq(str(items[1]["chiave"]), "Spearmen")
	t.assert_eq(int(items[1]["posizione"]), 1)
	t.assert_eq(str(items[2]["chiave"]), "Spearmen")
	t.assert_eq(int(items[2]["posizione"]), 2)
	t.assert_eq(CampaignUiQueues.entries(s.province("ID_BASSA")).size(), 0)


func test_le_unita_in_attesa_di_fondi_della_coda_ripetuta(t: TestContext) -> void:
	var s := _world()
	var p := s.province("ID_ALTA")
	GameCommands.set_unit_queue_repeat(s, "FN_ALPHA", "ID_ALTA", true)
	p.repeat_pending = PackedStringArray(["Spearmen"])
	var items := CampaignUiQueues.entries(p)
	t.assert_eq(items.size(), 1)
	t.assert_true(bool(items[0]["attesa"]))
	t.assert_true(CampaignUiQueues.summary(p) == "" or CampaignUiQueues.summary(p).contains("ripete"))


func test_elenco_delle_code_di_tutte_le_province(t: TestContext) -> void:
	var s := _world()
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_BASSA", "Spearmen")
	var all := CampaignUiQueues.rows(s, "FN_ALPHA")
	t.assert_eq(all.size(), 2, "tutte le province proprie")
	t.assert_eq(str(all[0]["provincia"]), "ID_ALTA")
	t.assert_eq((all[0]["voci"] as Array).size(), 0)
	t.assert_eq(int(all[1]["unita"]), 1)
	var busy := CampaignUiQueues.rows(s, "FN_ALPHA", true)
	t.assert_eq(busy.size(), 1)
	t.assert_eq(str(busy[0]["provincia"]), "ID_BASSA")
	var idle := CampaignUiQueues.rows(s, "FN_ALPHA", false, true)
	t.assert_eq(idle.size(), 1)
	t.assert_eq(str(idle[0]["provincia"]), "ID_ALTA")


func test_scorrere_le_province_proprie(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiQueues.next_province(s, "FN_ALPHA", "ID_ALTA", 1), "ID_BASSA")
	t.assert_eq(CampaignUiQueues.next_province(s, "FN_ALPHA", "ID_BASSA", 1), "ID_ALTA", "si ricomincia")
	t.assert_eq(CampaignUiQueues.next_province(s, "FN_ALPHA", "ID_ALTA", -1), "ID_BASSA")
	t.assert_eq(CampaignUiQueues.next_province(s, "FN_ALPHA", "ID_MEZZA", 1), "ID_ALTA", "da una provincia altrui: la prima")
	t.assert_eq(CampaignUiQueues.next_province(s, "FN_ALPHA", "ID_MEZZA", -1), "ID_BASSA", "indietro: l'ultima")


func test_scorrere_solo_le_province_con_qualcosa_in_coda(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiQueues.next_province(s, "FN_ALPHA", "ID_ALTA", 1, true), "", "nessuna coda")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	t.assert_eq(CampaignUiQueues.next_province(s, "FN_ALPHA", "ID_ALTA", 1, true), "ID_ALTA", "resta sull'unica")
	t.assert_eq(CampaignUiQueues.next_province(s, "FN_ALPHA", "ID_BASSA", 1, true), "ID_ALTA")


func test_riassunto_per_il_titolo(t: TestContext) -> void:
	var s := _world()
	var p := s.province("ID_ALTA")
	t.assert_eq(CampaignUiQueues.summary(p), "")
	GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", "BOWYER")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	t.assert_eq(CampaignUiQueues.summary(p), "in coda: 1 edificio, 2 unità")


# --- scheda dell'edificio costruito (segnalazione di Federico, 2026-11-10) ------------------------------------------------


func test_scheda_dell_edificio(t: TestContext) -> void:
	var s := _world()
	var data := CampaignUiBuildingInfo.info(s, "CASTLE", 3)
	t.assert_false(data.is_empty())
	t.assert_eq(str(data["nome"]), CampaignUiText.building_name(s, "CASTLE", 3))
	t.assert_eq(int(data["livello"]), 3)
	var labels := PackedStringArray()
	for r in data["righe"]:
		labels.append(str(r[0]))
	t.assert_true(labels.has("Costo"), str(labels))
	t.assert_true(labels.has("Costruzione"), str(labels))
	t.assert_true(labels.has("Livello"), "famiglia a piu' livelli")
	t.assert_true(CampaignUiBuildingInfo.info(s, "NON_ESISTE", 1).is_empty())


func test_testo_dei_miglioramenti(t: TestContext) -> void:
	t.assert_eq(CampaignUiBuildingInfo.upgrade_text("UPGRADE_ARMOUR(1)"), "armatura +1")
	t.assert_eq(CampaignUiBuildingInfo.upgrade_text("{}"), "")
	t.assert_eq(CampaignUiBuildingInfo.upgrade_text("UPGRADE_MORALE(2)"), "morale +2")


func test_nome_dell_illustrazione_dalla_colonna_infopic(t: TestContext) -> void:
	var fam := BuildingType.new("ARMOURER")
	fam.raw = PackedStringArray(["3", "ARMOURER", "x", "NON_PRODUCER", "400", "4", "{}", "\"Workshop Level 1, Workshop Level 2\""])
	t.assert_eq(CampaignUiBuildingInfo.infopic_name(fam, 1), "Workshop Level 1")
	t.assert_eq(CampaignUiBuildingInfo.infopic_name(fam, 2), "Workshop Level 2")
	t.assert_eq(CampaignUiBuildingInfo.infopic_name(fam, 3), "", "livello senza voce")
	t.assert_eq(CampaignUiBuildingInfo.infopic_name(null, 1), "")


# --- proventi delle province (pulsante Economia) ----------------------------------------------------------------------


func test_proventi_delle_province_nel_dettaglio(t: TestContext) -> void:
	var s := _world()
	var r := CampaignUiEconomy.report(s, "FN_ALPHA")
	var rows: Array = r["righe"]
	t.assert_eq(rows.size(), 2)
	var sum := 0
	for row in rows:
		var d: Dictionary = row
		t.assert_eq(int(d["totale"]), int(d["agricoltura"]) + int(d["miniere"]) + int(d["commercio"]), str(d["nome"]))
		var expected := Economy.province_income(s, s.province(str(d["provincia"])))
		t.assert_eq(int(d["totale"]), int(expected["totale"]), "stesse regole del fine anno")
		sum += int(d["totale"])
	t.assert_eq(int(r["totale"]), sum)
	t.assert_true(int((rows[0] as Dictionary)["totale"]) >= int((rows[1] as Dictionary)["totale"]), "ordinate per totale")
	t.assert_eq(int(r["mantenimento"]), Economy.faction_upkeep(s, "FN_ALPHA"))
	t.assert_eq(int(r["saldo"]), sum - int(r["mantenimento"]))


func test_provincia_contesa_senza_reddito_con_il_motivo(t: TestContext) -> void:
	var s := _world()
	var enemy := s.create_army("FN_BETA", "ID_BASSA", false)
	enemy.stacks.append(UnitStack.new("Spearmen", 100, 0))
	var r := CampaignUiEconomy.report(s, "FN_ALPHA")
	for row in r["righe"]:
		var d: Dictionary = row
		if str(d["provincia"]) == "ID_BASSA":
			t.assert_eq(int(d["totale"]), 0)
			t.assert_true(str(d["nota"]).contains("contesa"))


## Richiesta di Federico dell'11/11/2026: l'edificio scelto passa, con la sua icona, da quelli da costruire a quelli in
## costruzione; un clic li' lo riporta tra quelli da costruire.
func test_gli_edifici_in_coda_sono_tessere_e_spariscono_da_quelli_da_costruire(t: TestContext) -> void:
	var s := _world()
	s.faction("FN_ALPHA").treasury = 100000
	var p := s.province("ID_ALTA")
	var queued := ""
	var families: Array[Dictionary] = []
	for fam in s.buildings.families:
		families.append({"family": fam.id})
		if queued == "" and bool(GameCommands.queue_building(s, "FN_ALPHA", "ID_ALTA", fam.id)["ok"]):
			queued = fam.id
	t.assert_true(queued != "", "almeno un edificio si puo' mettere in coda")
	var tiles := CampaignUiQueues.building_tiles(p)
	t.assert_eq(tiles.size(), 1)
	t.assert_eq(str(tiles[0]["famiglia"]), queued)
	t.assert_eq(int(tiles[0]["indice"]), 0)
	t.assert_true(bool(tiles[0]["in_corso"]), "il primo e' quello in corso")
	t.assert_eq(int(tiles[0]["rimborso"]), p.building_queue[0].cost_paid)
	var left := CampaignUiQueues.not_queued(families, p)
	t.assert_eq(left.size(), families.size() - 1, "quello in coda non e' piu' tra quelli da costruire")
	for e in left:
		t.assert_true(str(e["family"]) != queued)
	# il clic sulla tessera annulla: torna tra quelli da costruire
	var cancel := GameCommands.cancel_queue_item(s, "FN_ALPHA", "ID_ALTA", GameCommands.QUEUE_BUILDING, int(tiles[0]["indice"]))
	t.assert_true(bool(cancel["ok"]), str(cancel["errore"]))
	t.assert_eq(CampaignUiQueues.building_tiles(p).size(), 0)
	t.assert_eq(CampaignUiQueues.not_queued(families, p).size(), families.size())


func test_il_testo_della_tessera_in_coda(t: TestContext) -> void:
	var first := CampaignUiQueues.building_tile_text({"anni": 3, "in_corso": true, "rimborso": 400}, "Forte (livello 1)")
	t.assert_eq(str(first["didascalia"]), "in corso · 3 anni")
	t.assert_true(str(first["suggerimento"]).contains("400") and str(first["suggerimento"]).contains("Forte"), str(first["suggerimento"]))
	var waiting := CampaignUiQueues.building_tile_text({"anni": 1, "in_corso": false, "rimborso": 0}, "Chiesa")
	t.assert_eq(str(waiting["didascalia"]), "in attesa · 1 anno")


func test_le_unita_in_coda_sono_tessere(t: TestContext) -> void:
	var s := _world()
	t.assert_true(bool(GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")["ok"]))
	t.assert_true(bool(GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")["ok"]))
	var p := s.province("ID_ALTA")
	var tiles := CampaignUiQueues.unit_tiles(p)
	t.assert_eq(tiles.size(), 2)
	t.assert_eq(str(tiles[0]["unita"]), "Spearmen")
	t.assert_true(bool(tiles[0]["in_corso"]) and not bool(tiles[1]["in_corso"]))
	t.assert_eq(int(tiles[1]["indice"]), 1)
	t.assert_eq(int(tiles[0]["rimborso"]), p.unit_queue[0].cost_paid)
	p.repeat_faction = "FN_ALPHA"
	p.repeat_pending.append("Spearmen")
	var with_pending := CampaignUiQueues.unit_tiles(p)
	t.assert_eq(with_pending.size(), 3)
	t.assert_true(bool(with_pending[2]["attesa"]), "quella senza fondi in fondo")
	t.assert_eq(int(with_pending[2]["indice"]), -1, "non si annulla da qui")
	t.assert_eq(str(CampaignUiQueues.unit_tile_text(with_pending[2], "Lancieri")["didascalia"]), "senza fondi")
	t.assert_eq(str(CampaignUiQueues.unit_tile_text(tiles[1], "Lancieri")["didascalia"]), "in attesa · %d %s" % [int(tiles[1]["anni"]), "anno" if int(tiles[1]["anni"]) == 1 else "anni"])


# --- scheda nuova di unita' ed edifici (richiesta di Federico del 2026-11-15) -------------------------------------------


func test_la_scheda_dell_edificio_dice_cosa_permette_di_arruolare(t: TestContext) -> void:
	var s := _world()
	var bowyer := CampaignUiBuildingInfo.info(s, "BOWYER", 1)
	t.assert_true((bowyer["sblocca"] as PackedStringArray).has("Archers"), str(bowyer["sblocca"]))
	t.assert_false((bowyer["sblocca"] as PackedStringArray).has("Knights"), "i cavalieri chiedono l'arcaio di livello 2")
	t.assert_true((CampaignUiBuildingInfo.info(s, "BOWYER", 2)["sblocca"] as PackedStringArray).has("Knights"))
	t.assert_true((CampaignUiBuildingInfo.info(s, "CASTLE", 3)["sblocca"] as PackedStringArray).has("Knights"))
	t.assert_false((CampaignUiBuildingInfo.info(s, "CASTLE", 1)["sblocca"] as PackedStringArray).has("Knights"))


func test_la_scheda_dell_edificio_divide_i_dati_e_conosce_i_livelli_vicini(t: TestContext) -> void:
	var s := _world()
	var data := CampaignUiBuildingInfo.info(s, "CASTLE", 2)
	var last := int(data["livelli"])
	t.assert_eq(last, s.buildings.get_family("CASTLE").levels.size())
	t.assert_eq(str(data["precedente"]), CampaignUiText.building_name(s, "CASTLE", 1))
	t.assert_eq(str(data["successivo"]), CampaignUiText.building_name(s, "CASTLE", 3))
	t.assert_eq(str(CampaignUiBuildingInfo.info(s, "CASTLE", 1)["precedente"]), "", "nessun livello prima del primo")
	t.assert_eq(str(CampaignUiBuildingInfo.info(s, "CASTLE", last)["successivo"]), "", "nessuno dopo l'ultimo")
	var cost_labels := PackedStringArray()
	for r in data["costi"]:
		cost_labels.append(str(r[0]))
	t.assert_eq(cost_labels, PackedStringArray(["Costo", "Costruzione"]))
	t.assert_eq(str((data["requisiti"] as Array)[0][0]), "Richiede")


func test_requisiti_con_i_nomi_italiani(t: TestContext) -> void:
	var s := _world()
	var knights := s.units.get_unit("Knights")
	var text := CampaignUiBuildingInfo.requires_text(s, knights.requires)
	t.assert_true(text.contains(CampaignUiText.building_name(s, "CASTLE", 3)), text)
	t.assert_true(text.contains(" oppure "), text)
	t.assert_true(text.contains(" e "), "due edifici nello stesso gruppo: " + text)
	t.assert_eq(CampaignUiBuildingInfo.requires_text(s, s.units.get_unit("Spearmen").requires), "")
	var rows := {}
	for r in CampaignUiUnitInfo.recruit_rows(s, s.units.get_unit("Spearmen")):
		rows[str(r[0])] = str(r[1])
	t.assert_eq(rows.get("Richiede"), "nessun edificio")
