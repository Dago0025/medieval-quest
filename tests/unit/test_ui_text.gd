extends RefCounted
## Test dei testi dell'interfaccia (CampaignUiText) sul mondo piccolo tests/fixtures/sim_*.txt.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


func test_nomi_delle_tasse(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.tax_name(0), "Molto bassa")
	t.assert_eq(CampaignUiText.tax_name(1), "Bassa")
	t.assert_eq(CampaignUiText.tax_name(2), "Normale")
	t.assert_eq(CampaignUiText.tax_name(3), "Alta")
	t.assert_eq(CampaignUiText.tax_name(4), "Molto alta")
	t.assert_eq(CampaignUiText.tax_name(7), "Livello 7")
	t.assert_eq(CampaignUiText.tax_name(-1), "Livello -1")


func test_nomi_delle_epoche_e_numeri_con_segno(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.era_name("EARLY"), "Primo Medioevo")
	t.assert_eq(CampaignUiText.era_name("high"), "Pieno Medioevo")
	t.assert_eq(CampaignUiText.era_name("LATE"), "Tardo Medioevo")
	t.assert_eq(CampaignUiText.era_name("X"), "X")
	t.assert_eq(CampaignUiText.signed(12), "+12")
	t.assert_eq(CampaignUiText.signed(-5), "-5")
	t.assert_eq(CampaignUiText.signed(0), "0")


func test_nomi_di_regioni_unita_edifici(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiText.region_name(s, "ID_ALTA"), "Alta")
	t.assert_eq(CampaignUiText.region_name(s, "ID_NON_ESISTE"), "ID_NON_ESISTE")
	t.assert_eq(CampaignUiText.unit_name("FEUDAL_KNIGHTS"), "Feudal Knights")
	t.assert_eq(CampaignUiText.building_name(s, "IMPROVED_FARMLAND", 2), "Disboscamento (livello 2)")
	t.assert_eq(CampaignUiText.building_name(s, "SCONOSCIUTO", 1), "Sconosciuto (livello 1)")
	t.assert_eq(CampaignUiText.faction_name("FN_DANISH"), "Auror", "la fazione del giocatore si chiama Auror")
	t.assert_eq(CampaignUiText.faction_name("FN_ENGLISH"), "Inglesi")
	t.assert_eq(CampaignUiText.faction_name("FN_ALPHA"), "Alpha", "senza voce nella tabella: dall'id")
	t.assert_eq(CampaignUiText.faction_name("FN_REBEL"), "ribelli")


func test_requisiti_in_parole(t: TestContext) -> void:
	var s := _world()
	var cond: Array[PackedStringArray] = [PackedStringArray(["CASTLE3"]), PackedStringArray(["CASTLE2", "BOWYER2"])]
	t.assert_eq(CampaignUiText.requires_text(s, cond), "Castle 3 oppure Castle 2 + Bowyer 2")
	var none: Array[PackedStringArray] = []
	t.assert_eq(CampaignUiText.requires_text(s, none), "")
	var unknown: Array[PackedStringArray] = [PackedStringArray(["MAGIA"])]
	t.assert_eq(CampaignUiText.requires_text(s, unknown), "Magia", "token sconosciuto lasciato com'e'")


func test_righe_del_reddito(t: TestContext) -> void:
	var lines := CampaignUiText.income_lines({"agricoltura": 291, "miniere": 0, "commercio": 62, "totale": 353, "conteso": false})
	t.assert_eq(lines.size(), 4)
	t.assert_eq(lines[0], "Agricoltura: 291")
	t.assert_eq(lines[3], "Totale annuo: 353")
	var contested := CampaignUiText.income_lines({"conteso": true})
	t.assert_eq(contested.size(), 1)
	t.assert_true(contested[0].contains("contesa"))


func test_righe_degli_eventi(t: TestContext) -> void:
	var s := _world()
	var built := CampaignUiText.format_event(s, {"tipo": GameState.EV_BUILT, "provincia": "ID_ALTA", "edificio": "MERCHANT", "livello": 3})
	t.assert_eq(built, "Costruzione completata a Alta: Gilda dei mercanti (livello 3).")
	var recruited := CampaignUiText.format_event(s, {"tipo": GameState.EV_RECRUITED, "provincia": "ID_BASSA", "unita": "SPEARMEN", "esercito": 4})
	t.assert_eq(recruited, "Reclutata a Bassa l'unità Lancieri (esercito 4).")
	var moved := CampaignUiText.format_event(s, {"tipo": GameState.EV_MOVED, "esercito": 2, "da": "ID_ALTA", "a": "ID_BASSA"})
	t.assert_eq(moved, "Esercito 2: da Alta a Bassa.")
	var conflict := CampaignUiText.format_event(s, {"tipo": GameState.EV_PENDING_CONFLICT, "esercito": 2, "da": "ID_BASSA", "verso": "ID_MEZZA"})
	t.assert_true(conflict.contains("Mezza") and conflict.contains("conflitto in sospeso"), conflict)
	var negative := CampaignUiText.format_event(s, {"tipo": GameState.EV_NEGATIVE_TREASURY, "tesoro": -40})
	t.assert_eq(negative, "Tesoro negativo: -40 denari.")
	t.assert_eq(CampaignUiText.format_event(s, {"tipo": "altro"}), "altro", "tipo sconosciuto: il nome del tipo")


func test_resoconto_filtra_la_fazione_e_aggiunge_avvisi_ed_errori(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	s.add_event(GameState.EV_BUILT, {"fazione": "FN_ALPHA", "provincia": "ID_ALTA", "edificio": "PORT", "livello": 1})
	s.add_event(GameState.EV_BUILT, {"fazione": "FN_BETA", "provincia": "ID_MEZZA", "edificio": "PORT", "livello": 1})
	s.add_event(GameState.EV_NEGATIVE_TREASURY, {"fazione": "FN_ALPHA", "tesoro": -3})
	var result := {
		"ok": true,
		"avvisi": ["FN_ALPHA: tesoro negativo (-3) nell'anno 1000", "altro avviso"],
		"errori": ["unità sconosciuta"],
	}
	var lines := CampaignUiText.year_report(s, "fn_alpha", result)
	t.assert_eq(lines.size(), 4, "\n".join(lines))
	t.assert_true(lines[0].contains("Alta"))
	t.assert_true(lines[1].contains("Tesoro negativo"))
	t.assert_eq(lines[2], "Avviso: altro avviso")
	t.assert_eq(lines[3], "Errore nei dati: unità sconosciuta")


func test_resoconto_senza_eventi_e_vuoto(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	var lines := CampaignUiText.year_report(s, "FN_ALPHA", {"ok": true, "avvisi": [], "errori": []})
	t.assert_true(lines.is_empty())


func test_resoconto_di_un_vero_fine_anno(t: TestContext) -> void:
	var s := _world()
	var result := TurnProcessor.end_year(s)
	var lines := CampaignUiText.year_report(s, "FN_ALPHA", result)
	# Niente ordini: non ci sono eventi per ALPHA (reddito positivo, code vuote).
	t.assert_true(lines.is_empty(), "\n".join(lines))


func test_descrizione_di_un_esercito(t: TestContext) -> void:
	var s := _world()
	var army := s.create_army("FN_ALPHA", "ID_ALTA", false)
	army.stacks.append(UnitStack.new("SPEARMEN", 60, 0))
	army.path = PackedStringArray(["ID_BASSA"])
	var text := CampaignUiText.describe_army(s, army)
	t.assert_true(text.begins_with("Esercito %d (Alpha)" % army.id), text)
	t.assert_true(text.contains("Posizione: Alta"))
	t.assert_true(text.contains("uomini: 60"))
	t.assert_true(text.contains("Lancieri × 60"))
	t.assert_true(text.contains("Movimento: Bassa"))
	var fleet := s.create_army("FN_ALPHA", "ID_MARE_NORD", true)
	t.assert_eq(CampaignUiText.army_title(fleet), "Flotta %d" % fleet.id)
