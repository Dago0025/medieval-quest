extends RefCounted
## Avvisi degli eventi importanti (richiesta di Federico del 2026-11-20, CampaignUiAlerts): battaglie su terra e mare, assalti,
## conquiste e perdite, guerre, diplomazia, corte, disastri e fazioni distrutte hanno una finestra illustrata propria con tema,
## luogo (la mappa ci va) ed esito; ogni tema ha un'immagine (serie propria o tavola). Mondo: sim_startpos.txt.

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)
	s.events.clear()
	return s


func _battle(s: GameState, kind: String, region: String, attacker: String, defender: String, attacker_won: bool) -> void:
	s.add_event(GameState.EV_BATTLE, {"scontro": kind, "attaccante": attacker, "difensore": defender, "fazione": attacker,
		"regione": region, "vittoria_attaccante": attacker_won, "vincitore": attacker if attacker_won else defender,
		"perdente": defender if attacker_won else attacker, "uomini_attaccante": 800, "uomini_difensore": 600,
		"perdite_attaccante": 120, "perdite_difensore": 450, "catture": [], "ritirate": [], "testo": "Battaglia."})


func test_battaglia_vinta_dal_giocatore(t: TestContext) -> void:
	var s := _world()
	_battle(s, BattleResult.KIND_FIELD, "ID_SOLA", "FN_ALPHA", "FN_BETA", true)
	var w := CampaignUiAlerts.windows(s, "FN_ALPHA", 1000)
	t.assert_eq(w.size(), 1)
	t.assert_eq(str(w[0]["tema"]), "battaglia_vittoria")
	t.assert_eq(str(w[0]["luogo"]), "ID_SOLA", "la mappa va sul luogo della battaglia")
	t.assert_eq(str(w[0]["esito"]), CampaignUiAlerts.ESITO_GOOD)
	t.assert_true(CampaignUiAlerts.has_place(w[0]))
	t.assert_true(str(w[0]["effetto"]).contains("120") and str(w[0]["effetto"]).contains("450"), str(w[0]["effetto"]))
	t.assert_true(str(w[0]["categoria"]).contains("Vittoria"), str(w[0]["categoria"]))


func test_battaglia_persa_in_difesa_e_navale(t: TestContext) -> void:
	var s := _world()
	_battle(s, BattleResult.KIND_FIELD, "ID_ALTA", "FN_BETA", "FN_ALPHA", true)
	_battle(s, BattleResult.KIND_NAVAL, "ID_MARE_NORD", "FN_ALPHA", "FN_GAMMA", false)
	var w := CampaignUiAlerts.windows(s, "FN_ALPHA")
	t.assert_eq(w.size(), 2)
	t.assert_eq(str(w[0]["tema"]), "battaglia_sconfitta")
	t.assert_eq(str(w[0]["esito"]), CampaignUiAlerts.ESITO_BAD)
	t.assert_eq(str(w[1]["tema"]), "battaglia_navale_sconfitta")
	t.assert_eq(str(w[1]["luogo"]), "ID_MARE_NORD", "anche le zone di mare sono un luogo")


func test_le_battaglie_degli_altri_non_aprono_finestre(t: TestContext) -> void:
	var s := _world()
	_battle(s, BattleResult.KIND_FIELD, "ID_SOLA", "FN_BETA", "FN_GAMMA", true)
	t.assert_true(CampaignUiAlerts.windows(s, "FN_ALPHA").is_empty())


func test_assalto_vinto_e_conquista_in_una_finestra_sola(t: TestContext) -> void:
	var s := _world()
	_battle(s, BattleResult.KIND_ASSAULT, "ID_SOLA", "FN_ALPHA", "FN_BETA", true)
	s.add_event(GameState.EV_PROVINCE_CAPTURED, {"fazione": "FN_ALPHA", "regione": "ID_SOLA", "precedente": "FN_BETA", "modo": "assalto"})
	var w := CampaignUiAlerts.windows(s, "FN_ALPHA")
	t.assert_eq(w.size(), 1, "la conquista si aggiunge all'esito dell'assalto")
	t.assert_eq(str(w[0]["tema"]), "assalto_vittoria")
	t.assert_true(str(w[0]["effetto"]).contains("La provincia passa a voi."), str(w[0]["effetto"]))


func test_assalto_respinto_dal_giocatore_e_castello_tenuto(t: TestContext) -> void:
	var s := _world()
	_battle(s, BattleResult.KIND_ASSAULT, "ID_ALTA", "FN_BETA", "FN_ALPHA", false)
	var w := CampaignUiAlerts.windows(s, "FN_ALPHA")
	t.assert_eq(str(w[0]["tema"]), "assalto_sconfitta", "l'immagine racconta l'assalto respinto")
	t.assert_eq(str(w[0]["esito"]), CampaignUiAlerts.ESITO_GOOD, "ma per il giocatore e' una vittoria")


func test_provincia_persa_senza_battaglia(t: TestContext) -> void:
	var s := _world()
	s.add_event(GameState.EV_PROVINCE_CAPTURED, {"fazione": "FN_BETA", "regione": "ID_ALTA", "precedente": "FN_ALPHA", "modo": "fame"})
	var w := CampaignUiAlerts.windows(s, "FN_ALPHA")
	t.assert_eq(w.size(), 1)
	t.assert_eq(str(w[0]["tema"]), "provincia_persa")
	t.assert_eq(str(w[0]["luogo"]), "ID_ALTA")


func test_guerra_diplomazia_e_corte(t: TestContext) -> void:
	var s := _world()
	s.add_event(GameState.EV_WAR_DECLARED, {"fazione": "FN_BETA", "contro": "FN_ALPHA", "regione": "ID_ALTA", "testo": "x"})
	s.add_event(GameState.EV_ALLIANCE_FORMED, {"fazione": "FN_ALPHA", "con": "FN_GAMMA", "testo": "x"})
	s.add_event(GameState.EV_DEATH, {"fazione": "FN_ALPHA", "personaggio": 1, "nome": "Re Uno", "ruolo": Character.ROLE_LEADER, "causa": "vecchiaia"})
	s.add_event(GameState.EV_DEATH, {"fazione": "FN_ALPHA", "personaggio": 2, "nome": "Generale Due", "ruolo": Character.ROLE_GENERAL, "causa": "battaglia"})
	s.add_event(GameState.EV_BIRTH, {"fazione": "FN_ALPHA", "personaggio": 3, "nome": "Principe Tre", "ruolo": Character.ROLE_PRINCE})
	var themes := PackedStringArray()
	for w in CampaignUiAlerts.windows(s, "FN_ALPHA"):
		themes.append(str(w["tema"]))
	t.assert_eq(themes, PackedStringArray(["guerra", "alleanza", "morte", "nascita"]), "la morte di un generale resta nel resoconto")


func test_disastri_nelle_proprie_province(t: TestContext) -> void:
	var s := _world()
	var own := ""
	var foreign := ""
	for p in s.provinces:
		if p.owner == "FN_ALPHA" and own == "":
			own = p.id
		elif p.owner != "FN_ALPHA" and foreign == "":
			foreign = p.id
	s.add_event(GameState.EV_FLOOD, {"provincia": own, "proprietario": "FN_ALPHA"})
	if foreign != "":
		s.add_event(GameState.EV_FAMINE, {"provincia": foreign, "proprietario": s.province(foreign).owner})
	var w := CampaignUiAlerts.windows(s, "FN_ALPHA")
	t.assert_eq(w.size(), 1, "solo il disastro nella propria provincia")
	t.assert_eq(str(w[0]["tema"]), "inondazione")
	t.assert_eq(str(w[0]["luogo"]), own)


func test_ogni_tema_ha_un_immagine(t: TestContext) -> void:
	EventArt.reset()
	for theme in CampaignUiAlerts.THEMES:
		var own := EventArt.own_paths(theme)
		var frame := EventArt.theme_exact_frame(theme, "prova")
		t.assert_true(not own.is_empty() or (frame > 0 and not EventArt.is_placeholder(frame)), "tema %s senza immagine" % theme)
	for theme in ["prigionia", "matrimonio", "alleanza", "tregua", "battaglia", "assedio", "nave", "erede"]:
		t.assert_true(not EventArt.own_paths(theme).is_empty() or EventArt.theme_exact_frame(theme, "x") > 0,
			"prigionieri, proposte e temi generici: %s" % theme)


func test_battaglie_assedi_e_navi_usano_le_scene_degli_avvisi(t: TestContext) -> void:
	# illustrazioni.cfg [serie]: i temi generici prendono le scene di assets/eventi al posto delle tavole dell'originale
	EventArt.reset()
	if EventArt.own_paths("battaglia_vittoria").is_empty():
		t.skip("scene degli avvisi non ancora in assets/eventi")
		return
	for theme in ["battaglia", "assedio", "nave", "erede"]:
		var own := EventArt.own_paths(theme)
		t.assert_false(own.is_empty(), "%s: scene proprie" % theme)
		t.assert_true(EventArt.theme_texture(theme, "x").resource_path.begins_with(EventArt.OWN_DIR), "%s: immagine dalla serie" % theme)


func test_le_tavole_di_ripiego_sono_tra_quelle_tenute(t: TestContext) -> void:
	# originale/ conserva solo le tavole elencate in tools/originale_necessari.txt (ADR-094/096)
	var f := FileAccess.open("res://tools/originale_necessari.txt", FileAccess.READ)
	if f == null:
		t.skip("elenco degli originali necessari non trovato")
		return
	var kept := f.get_as_text()
	var cfg := ConfigFile.new()
	cfg.load(EventArt.TABLE)
	for theme in CampaignUiAlerts.THEMES:
		if not cfg.has_section_key("temi", theme):
			continue
		for n in cfg.get_value("temi", theme):
			t.assert_true(kept.contains("EPIC.BIF__f%d.png" % int(n)), "tema %s: tavola %d tenuta in originale/" % [theme, int(n)])


func test_finestra_con_immagine_di_sfondo(t: TestContext) -> void:
	var m := IllustratedModal.new()
	m.set_category("Battaglia · Vittoria", CampaignUiAlerts.ESITO_GOOD)
	m.set_title("Battaglia di Sola")
	m.set_width(800.0)
	t.assert_eq(m.get_width(), 800.0)
	t.assert_eq(m.title_text(), "Battaglia di Sola")
	t.assert_false(m.has_picture(), "senza immagine resta il fondo di cuoio")
	var img := Image.create(16, 9, false, Image.FORMAT_RGB8)
	m.set_picture(ImageTexture.create_from_image(img))
	t.assert_true(m.has_picture())
	m.free()


## L'immagine aderisce alla cornice: niente giro di pergamena tra il filo d'ottone e la tavola (20/11/2026).
func test_la_tavola_aderisce_alla_cornice(t: TestContext) -> void:
	var box := IllustratedModal.frame_box()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		t.assert_true(box.get_content_margin(side) <= IllustratedModal.FRAME_INSET, "margine %d" % box.get_content_margin(side))
	var modal := IllustratedModal.new()
	t.assert_eq(modal.get_theme_stylebox("panel").get_content_margin(SIDE_LEFT), box.get_content_margin(SIDE_LEFT))
	modal.free()
