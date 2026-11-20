extends RefCounted
## Finestra Economia: i porti raggiunti via mare non sono piu' un elenco in una riga ma il dettaglio della provincia, dal
## porto piu' redditizio, con la ricchezza di ciascuno (richiesta di Federico del 2026-11-13, ADR-054). Mondo di prova:
## sim_startpos.txt (ALTA di ALPHA con porto e Merchant2 e una flotta in MARE_NORD; MEZZA di BETA con porto).

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)
	var chain := s.create_army("FN_ALPHA", "ID_MARE_SUD", true)
	chain.stacks.append(UnitStack.new("Galley", 1, 0))
	return s


func test_il_dettaglio_per_porto_somma_al_commercio_della_provincia(t: TestContext) -> void:
	var s := _world()
	var alta := s.province("ID_ALTA")
	var region := s.campaign.region("ID_ALTA")
	var details := Economy.trade_partner_details(s, alta, region)
	t.assert_eq(details.size(), 1, "un porto raggiunto")
	var d: Dictionary = details[0]
	t.assert_eq(str(d["provincia"]), "ID_MEZZA")
	t.assert_eq(str(d["fazione"]), "FN_BETA")
	var parts := Economy.trade_breakdown(s, alta, region)
	t.assert_eq(roundi(float(d["merci"])), int(parts["marittimo"]), "stessa formula: merci vendute")
	t.assert_eq(roundi(float(d["importazioni"])), int(parts["importazioni"]), "stessa formula: importazioni")
	t.assert_eq(int(d["fiorini"]), 15, "13 + 2 con il peso per ricchezza di MEZZA (0,208)")


func test_i_porti_sono_ordinati_dal_piu_redditizio(t: TestContext) -> void:
	var s := _world()
	s.rules.sea_trade_reference = 0.0
	var alta := s.province("ID_ALTA")
	var details := Economy.trade_partner_details(s, alta, s.campaign.region("ID_ALTA"))
	t.assert_eq(int(details[0]["fiorini"]), 71, "senza peso per ricchezza: 62,4 + 8,32 = 70,72 (le due parti arrotondate insieme)")
	t.assert_true(Economy.trade_partner_details(s, s.province("ID_BASSA"), s.campaign.region("ID_BASSA")).is_empty(), "entroterra: nessun porto")


func test_la_finestra_economia_mostra_i_porti_nel_dettaglio(t: TestContext) -> void:
	var s := _world()
	var r := CampaignUiEconomy.report(s, "FN_ALPHA")
	var alta: Dictionary = {}
	for row in r["righe"]:
		if str((row as Dictionary)["provincia"]) == "ID_ALTA":
			alta = row
	t.assert_false(alta.is_empty(), "ALTA nella finestra")
	t.assert_eq(str(alta["nota"]), "", "nessun elenco di rotte nella nota")
	var ports: Array = alta["porti"]
	t.assert_eq(ports.size(), 1)
	var port: Dictionary = ports[0]
	t.assert_eq(str(port["nome"]), CampaignUiText.region_name(s, "ID_MEZZA"))
	t.assert_eq(str(port["ricchezza"]), "povero", "peso 0,208")
	t.assert_eq(int(port["fiorini"]), 15)
	t.assert_eq(int(alta["commercio_marittimo"]) + int(alta["importazioni"]), 15, "le parti del commercio nella riga")


func test_etichette_della_ricchezza(t: TestContext) -> void:
	t.assert_eq(CampaignUiEconomy.wealth_label(2.0), "ricchissimo")
	t.assert_eq(CampaignUiEconomy.wealth_label(1.0), "ricco")
	t.assert_eq(CampaignUiEconomy.wealth_label(0.5), "medio")
	t.assert_eq(CampaignUiEconomy.wealth_label(0.1), "povero")
