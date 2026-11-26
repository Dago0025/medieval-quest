extends RefCounted
## Nomi italiani della fase 8: regioni (data/province.cfg), titoli dei governatori tradotti per schema, fazioni
## (data/fazioni.cfg, gli Auror al posto dei Danesi).


func test_nomi_italiani_delle_regioni(t: TestContext) -> void:
	RegionNames.reset()
	t.assert_eq(RegionNames.italian("ID_DENMARK"), "Danimarca")
	t.assert_eq(RegionNames.italian("id_constantinople"), "Costantinopoli", "maiuscole indifferenti")
	t.assert_eq(RegionNames.italian("ID_NORTH_SEA"), "Mare del Nord", "anche le zone di mare")
	t.assert_eq(RegionNames.italian("ID_AFRICA"), "Mesopotamia", "conta il nome dei dati della XL, non l'id")
	t.assert_eq(RegionNames.italian("ID_ALTA"), "", "regione sconosciuta: nessun nome")


func test_tutte_le_regioni_dello_startpos_hanno_il_nome_italiano(t: TestContext) -> void:
	if not GameFiles.is_available():
		t.skip("installazione di MTW non trovata")
		return
	RegionNames.reset()
	var campaign := StartposLoader.load_file(GameFiles.startpos())
	for r in campaign.regions:
		t.assert_true(RegionNames.italian(r.id) != "", "nome italiano per %s" % r.id)


func test_titoli_dei_governatori_in_italiano(t: TestContext) -> void:
	RegionNames.reset()
	var campaign := StartposLoader.load_text("""
DeclareLandRegion:: "ID_SCOTLAND"
SetAttributes:: ID_SCOTLAND "Scotland" 0 x x x 0 0 0
DeclareLandRegion:: "ID_ILE_DE_FRANCE"
SetAttributes:: ID_ILE_DE_FRANCE "Ile" 0 x x x 0 0 0
""")
	t.assert_eq(RegionNames.translate_title(campaign, "Duke of Scotland"), "Duca di Scozia")
	t.assert_eq(RegionNames.translate_title(campaign, "Title Count of Scotland"), "Conte di Scozia", "rango di due parole")
	t.assert_eq(RegionNames.translate_title(campaign, "Count of Ile de France"), "Conte d'Île-de-France", "nome dall'id e «d'» davanti a vocale")
	t.assert_eq(RegionNames.translate_title(campaign, "Duca di Bassa"), "Duca di Bassa", "gia' in italiano: invariato")
	t.assert_eq(RegionNames.translate_title(campaign, "Bailiff of Nowhere"), "Bailiff of Nowhere", "rango sconosciuto: invariato")


func test_cariche_di_corte_in_italiano(t: TestContext) -> void:
	RegionNames.reset()
	var campaign := StartposLoader.load_text("""
DeclareLandRegion:: "ID_SCOTLAND"
SetAttributes:: ID_SCOTLAND "Scotland" 0 x x x 0 0 0
""")
	t.assert_eq(RegionNames.translate_office(campaign, "Archbishop of Lund"), "Arcivescovo di Lund")
	t.assert_eq(RegionNames.translate_office(campaign, "Admiral of the Fleet"), "Ammiraglio della Flotta")
	t.assert_eq(RegionNames.translate_office(campaign, "Master of the Khan's Horses"), "Maestro dei Cavalli del Khan", "apostrofi")
	t.assert_eq(RegionNames.translate_office(campaign, "Earl Marshal of Scotland"), "Conte Maresciallo di Scozia", "luogo dalla regione")
	t.assert_eq(RegionNames.translate_office(campaign, "Chancellor Of Great Russia"), "Cancelliere della Grande Russia", "«Of» maiuscolo")
	t.assert_eq(RegionNames.translate_office(campaign, "Grand Vizier"), "Gran Visir", "senza luogo")
	t.assert_eq(RegionNames.translate_office(campaign, "Bailiff of Nowhere"), "Bailiff di Nowhere", "parti sconosciute come sono")


func test_tutte_le_cariche_dello_startpos_sono_tradotte(t: TestContext) -> void:
	if not GameFiles.is_available():
		t.skip("installazione di MTW non trovata")
		return
	RegionNames.reset()
	var campaign := StartposLoader.load_file(GameFiles.startpos())
	t.assert_true(campaign.offices.size() > 100, "lo startpos ha le cariche")
	for o in campaign.offices:
		var it := RegionNames.translate_office(campaign, o.display_name)
		t.assert_false(it.contains(" of ") or it.contains(" Of "), "%s -> %s" % [o.display_name, it])


func test_nessuna_traccia_dei_danesi_nei_nomi(t: TestContext) -> void:
	FactionStyle.reset()
	t.assert_eq(FactionStyle.name_of("FN_DANISH"), "Auror")
	t.assert_false(FactionStyle.full_name_of("FN_DANISH").to_lower().contains("dan"))


func test_articoli_e_accordo_delle_fazioni(t: TestContext) -> void:
	FactionStyle.reset()
	t.assert_eq(CampaignUiText.fsubj("FN_ENGLISH"), "Gli Inglesi")
	t.assert_eq(CampaignUiText.fart("FN_GERMAN_HRE"), "il Sacro Romano Impero")
	t.assert_eq(CampaignUiText.fprep("di", "FN_ENGLISH"), "degli Inglesi")
	t.assert_eq(CampaignUiText.fprep("a", "FN_FRENCH"), "ai Francesi")
	t.assert_eq(CampaignUiText.fprep("di", "FN_GOLDEN_HORDE"), "dell'Orda d'Oro")
	t.assert_eq(CampaignUiText.fprep("di", "FN_PAPIST"), "dello Stato Pontificio")
	t.assert_eq(CampaignUiText.fprep("di", "FN_NOVGOROD"), "della Repubblica di Novgorod")
	t.assert_eq(CampaignUiText.fprep("contro", "FN_TURKISH"), "contro i Turchi", "preposizione senza forma articolata")
	t.assert_eq(CampaignUiText.fprep("di", "FN_ALPHA"), "di Alpha", "senza articolo")
	t.assert_eq(CampaignUiText.fverb("FN_ENGLISH", "vince", "vincono"), "vincono")
	t.assert_eq(CampaignUiText.fverb("FN_GERMAN_HRE", "vince", "vincono"), "vince")
	t.assert_eq(CampaignUiText.fnames(PackedStringArray(["FN_ENGLISH", "FN_FRENCH", "FN_GERMAN_HRE"]), "a"), "agli Inglesi, ai Francesi e al Sacro Romano Impero")
	t.assert_eq(CampaignUiText.fverbs(PackedStringArray(["FN_GERMAN_HRE", "FN_PAPIST"]), "dichiara", "dichiarano"), "dichiarano")
	t.assert_eq(CampaignUiText.fsubj("FN_DANISH"), "Gli Auror")


## ADR-115 (richiesta di Federico del 21/11/2026): gli Auror hanno titoli di corte propri, non quelli dei Danesi.
func test_cariche_di_corte_degli_auror(t: TestContext) -> void:
	if not GameFiles.is_available():
		t.skip("installazione di MTW non trovata")
		return
	Scenario.set_auror(true)
	RegionNames.reset()
	var d := Scenario.load_startpos()
	var expected := {
		"royal_palace": "Gran Ciambellano del Trono del Drago",
		"constables_palace": "Maestro dei Destrieri del Drago",
		"marshals_palace": "Maresciallo delle Legioni del Drago",
		"chancellery": "Gran Cancelliere dell'Impero",
		"admiralty": "Grande Ammiraglio della Flotta del Drago",
		"cathedral": "Sommo sacerdote del Culto Imperiale",
	}
	var seen := 0
	for o in d.offices_of("FN_DANISH"):
		var it := RegionNames.translate_office(d, o.display_name)
		t.assert_false(it.to_lower().contains("dan") or it.contains("Lund") or it.contains("Nord"), it)
		if expected.has(o.building):
			t.assert_eq(it, expected[o.building], o.building)
			seen += 1
	t.assert_eq(seen, expected.size(), "tutte le cariche degli Auror")
	t.assert_eq(RegionNames.translate_office(d, "Chancellor of Denmark"), "Cancelliere di Danimarca", "i Danesi restano danesi")
	RegionNames.reset()
