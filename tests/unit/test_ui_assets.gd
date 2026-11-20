extends RefCounted
## Test della fase 8: AssetLibrary (indice dal manifesto dell'esportazione, maiuscole indifferenti, fotogrammi, versione HD,
## immagini mancanti), scudi dallo startpos (SetShieldImage), PieceArt (colori chiave delle pedine) e UiTheme (tema completo
## anche senza immagini). Usa una finta esportazione in user://, quindi gira senza l'installazione del gioco.

const ROOT := "user://test_asset_export"
const HD := "user://test_asset_export_hd"


func _png(path: String, w: int, h: int, color: Color) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	img.save_png(path)


func _fake_export() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var lines := PackedStringArray([
		"﻿categoria;file_originale;png;larghezza;altezza;frame;formato",
		"04;campmap/shields/Denmark_lge.BIF;04/campmap/shields/Denmark_lge.BIF.png;34;40;1;bif",
		"04;campmap/shields/default_lge.BIF;04/campmap/shields/default_lge.BIF.png;34;40;1;bif",
		"04;campmap/buttons/ok.BIF;04/campmap/buttons/ok.BIF.png;20;20;2;bif",
		"03;campmap/review_panel/Units/Spearmen.BIF;03/campmap/review_panel/Units/Spearmen.BIF.png;50;50;1;bif",
		"03;campmap/review_panel/Ships/Cog.BIF;03/campmap/review_panel/Ships/Cog.BIF.png;50;50;1;bif",
		"05;frontend_files/seal.BIF;05/frontend_files/seal.BIF.png;40;41;1;bif",
		"03;campmap/review_panel/Agents/Spy.BIF;03/campmap/review_panel/Agents/Spy.BIF.png;50;50;1;bif",
		"03;campmap/review_panel/Agents/MUSLIM/Spy.BIF;03/campmap/review_panel/Agents/MUSLIM/Spy.BIF.png;50;50;1;bif",
		"03;campmap/review_panel/Agents/Pagan/Spy.BIF;03/campmap/review_panel/Agents/Pagan/Spy.BIF.png;50;50;1;bif",
		"03;campmap/review_panel/Agents/Bishop.BIF;03/campmap/review_panel/Agents/Bishop.BIF.png;50;50;1;bif",
		"03;campmap/review_panel/Agents/Pagan/Shaman.BIF;03/campmap/review_panel/Agents/Pagan/Shaman.BIF.png;50;50;1;bif",
	])
	var f := FileAccess.open(ROOT.path_join("_manifest.csv"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	_png(ROOT.path_join("04/campmap/shields/Denmark_lge.BIF.png"), 34, 40, Color.RED)
	_png(ROOT.path_join("04/campmap/shields/default_lge.BIF.png"), 34, 40, Color.GRAY)
	_png(ROOT.path_join("04/campmap/buttons/ok.BIF__f01.png"), 20, 20, Color.WHITE)
	_png(ROOT.path_join("04/campmap/buttons/ok.BIF__f02.png"), 20, 20, Color.BLACK)
	_png(ROOT.path_join("03/campmap/review_panel/Units/Spearmen.BIF.png"), 50, 50, Color.GREEN)
	_png(ROOT.path_join("03/campmap/review_panel/Ships/Cog.BIF.png"), 50, 50, Color.BLUE)
	_png(ROOT.path_join("05/frontend_files/seal.BIF.png"), 40, 41, Color.YELLOW)
	for agent in ["Spy", "MUSLIM/Spy", "Pagan/Spy", "Bishop", "Pagan/Shaman"]:
		_png(ROOT.path_join("03/campmap/review_panel/Agents/%s.BIF.png" % agent), 50, 50, Color.WHITE)
	# versione ingrandita (stesso percorso del gioco, nome che comincia con quello originale)
	_png(HD.path_join("frontend_files/seal.BIF_upscayl_2x.png"), 80, 82, Color.ORANGE)


func _setup() -> void:
	_fake_export()
	AssetLibrary.configure(ProjectSettings.globalize_path(ROOT), ProjectSettings.globalize_path(HD))


func _teardown() -> void:
	AssetLibrary.reset()


func test_indice_dal_manifesto_senza_badare_alle_maiuscole(t: TestContext) -> void:
	_setup()
	t.assert_true(AssetLibrary.is_available(), "manifesto letto")
	t.assert_eq(AssetLibrary.errors(), PackedStringArray())
	t.assert_true(AssetLibrary.has("CAMPMAP/SHIELDS/DENMARK_LGE.BIF"), "maiuscole indifferenti")
	t.assert_true(AssetLibrary.has("campmap\\shields\\denmark_lge.bif"), "barre rovesciate di Windows")
	var tex := AssetLibrary.texture("campmap/shields/denmark_lge.bif")
	t.assert_true(tex != null)
	t.assert_eq(tex.get_size(), Vector2(34, 40))
	t.assert_true(AssetLibrary.texture("campmap/shields/denmark_lge.bif") == tex, "la seconda volta dalla memoria")
	_teardown()


func test_fotogrammi_e_immagini_mancanti(t: TestContext) -> void:
	_setup()
	t.assert_eq(AssetLibrary.frame_count("campmap/buttons/ok.BIF"), 2)
	var first := AssetLibrary.texture("campmap/buttons/ok.BIF", 1)
	var second := AssetLibrary.texture("campmap/buttons/ok.BIF", 2)
	t.assert_true(first != null and second != null, "nome.BIF__f01.png e __f02.png")
	t.assert_eq(first.get_image().get_pixel(5, 5), Color.WHITE)
	t.assert_eq(second.get_image().get_pixel(5, 5), Color.BLACK)
	t.assert_true(AssetLibrary.texture("campmap/non_esiste.BIF") == null)
	t.assert_true(AssetLibrary.missing().has("campmap/non_esiste.BIF"), "la mancanza si annota")
	_teardown()


func test_la_versione_hd_ha_la_precedenza(t: TestContext) -> void:
	_setup()
	var tex := AssetLibrary.texture("frontend_files/seal.BIF")
	t.assert_eq(tex.get_size(), Vector2(80, 82), "PNG della cartella HD")
	_teardown()


func test_carte_delle_unita_e_delle_navi(t: TestContext) -> void:
	_setup()
	# carte rifatte (ADR-063): 4 volte la carta 50x50 dell'originale, che resta per chi non ha il rifatto
	var spear_path := AssetLibrary.unit_card_path("Spearmen")
	var expected := Vector2(200, 200) if AssetLibrary.is_remade(spear_path) else Vector2(50, 50)
	t.assert_eq(AssetLibrary.unit_card("Spearmen").get_size(), expected)
	t.assert_true(AssetLibrary.unit_card("Cog") != null, "le navi stanno in review_panel/Ships")
	t.assert_true(AssetLibrary.unit_card("Inesistenti") == null)
	_teardown()


func test_carte_degli_agenti_per_cultura(t: TestContext) -> void:
	_setup()
	# come le pedine: variante della cultura se c'e', altrimenti la carta comune; lo sciamano esiste solo in Agents/Pagan
	t.assert_eq(AssetLibrary.unit_card_path("Spy"), "campmap/review_panel/Agents/Spy.BIF")
	t.assert_eq(AssetLibrary.unit_card_path("Spy", "Muslim").to_lower(), "campmap/review_panel/agents/muslim/spy.bif")
	t.assert_eq(AssetLibrary.unit_card_path("Spy", "Pagan").to_lower(), "campmap/review_panel/agents/pagan/spy.bif")
	t.assert_eq(AssetLibrary.unit_card_path("Bishop", "Muslim"), "campmap/review_panel/Agents/Bishop.BIF", "senza variante: la comune")
	t.assert_eq(AssetLibrary.unit_card_path("Shaman").to_lower(), "campmap/review_panel/agents/pagan/shaman.bif")
	t.assert_true(AssetLibrary.unit_card("Shaman", "Pagan") != null)
	_teardown()


func test_scudi_dallo_startpos(t: TestContext) -> void:
	_setup()
	var campaign := StartposLoader.load_text("""
DeclareFaction:: "FN_NORDLAND"
SetShieldImage:: FN_NORDLAND "Denmark_lge" "Denmark_sml" "Denmark" "F1003" "F1003"
DeclareFaction:: "FN_SCOTS"
""")
	var dane := campaign.faction("FN_NORDLAND")
	t.assert_eq(dane.shield_large, "Denmark_lge")
	t.assert_eq(dane.shield_small, "Denmark_sml")
	t.assert_eq(dane.shield_piece, "F1003")
	AssetLibrary.use_campaign(campaign)
	t.assert_eq(AssetLibrary.shield_name("FN_NORDLAND"), "Denmark_lge")
	t.assert_eq(AssetLibrary.shield_name("FN_SCOTS"), AssetLibrary.DEFAULT_SHIELD_LARGE, "senza SetShieldImage: lo scudo predefinito")
	t.assert_eq(AssetLibrary.faction_shield("FN_NORDLAND").get_image().get_pixel(1, 1), Color.RED)
	# senza voce: lo scudo predefinito, dal 18/11/2026 disegnato a codice (tools/disegna_icone.py), non piu' dell'originale
	t.assert_true(AssetLibrary.is_remade("campmap/shields/default_lge.BIF"))
	t.assert_true(AssetLibrary.faction_shield("FN_NESSUNA") != null, "senza voce: lo scudo predefinito rifatto")
	_teardown()


func test_gli_auror_hanno_nome_colori_e_stemma_propri(t: TestContext) -> void:
	FactionStyle.reset()
	t.assert_eq(FactionStyle.name_of("FN_DANISH"), "Auror")
	t.assert_eq(FactionStyle.full_name_of("FN_DANISH"), "Gli Auror")
	t.assert_eq(FactionStyle.full_name_of("FN_ENGLISH"), "Inglesi", "senza nome esteso: il nome")
	t.assert_eq(SimUtil.faction_label("fn_danish"), "Auror", "anche nei testi degli eventi")
	var campaign := StartposLoader.load_text("""
DeclareFaction:: "FN_DANISH"
SetFactionCol:: FN_DANISH 255 255 255 255 0 0
""")
	FactionStyle.apply_overrides(campaign)
	t.assert_eq(campaign.faction("FN_DANISH").color_primary, Color("ffffff"))
	t.assert_eq(campaign.faction("FN_DANISH").color_secondary, Color("141414"), "nero al posto del rosso dei dati")
	var img := FactionStyle.shield_image("FN_DANISH", Vector2i(34, 40))
	t.assert_true(img != null, "stemma reso (auror.png, dall'11/11 un'immagine dipinta al posto dell'SVG)")
	t.assert_eq(img.get_size(), Vector2i(34, 40))
	t.assert_true(img.get_pixel(0, 39).a < 0.1, "fuori dallo scudo: trasparente")
	var light := 0
	var dark := 0
	for y in 40:
		for x in 34:
			var c := img.get_pixel(x, y)
			if c.a > 0.9 and c.get_luminance() > 0.7:
				light += 1
			elif c.a > 0.9 and c.get_luminance() < 0.3:
				dark += 1
	t.assert_true(light > 150, "campo d'argento: %d pixel chiari" % light)
	t.assert_true(dark > 150, "draghi e bordo neri: %d pixel scuri" % dark)
	t.assert_true(FactionStyle.shield_image("FN_ENGLISH", Vector2i(34, 40)) != null, "dal 15/11 anche le altre fazioni hanno lo stemma dipinto")
	t.assert_true(FactionStyle.shield_image("FN_REBEL", Vector2i(34, 40)) != null, "anche i ribelli: scudo grigio neutro dipinto")
	t.assert_true(FactionStyle.shield_image("FN_NESSUNA", Vector2i(34, 40)) == null, "senza voce: lo scudo dell'originale")
	# lo stemma proprio grande e' reso a 4 volte la misura dell'originale, con le riduzioni: nitido nella barra ingrandita
	var big := AssetLibrary.faction_shield("FN_DANISH")
	t.assert_eq(big.get_size(), Vector2(34, 40) * float(AssetLibrary.SHIELD_DETAIL), "stemma grande in alta definizione")
	t.assert_true(big.get_image().has_mipmaps(), "riduzioni intermedie")
	t.assert_eq(AssetLibrary.faction_shield("FN_DANISH", false).get_size(), Vector2(17, 20), "quello piccolo resta alla sua misura")


func test_esportazione_assente(t: TestContext) -> void:
	AssetLibrary.configure(ProjectSettings.globalize_path("user://cartella_che_non_esiste"), "")
	t.assert_false(AssetLibrary.is_available())
	t.assert_eq(AssetLibrary.errors().size(), 1)
	t.assert_true(AssetLibrary.errors()[0].contains("export.py"), "il messaggio dice come rimediare")
	t.assert_true(AssetLibrary.texture("frontend_files/seal.BIF") == null)
	t.assert_true(AssetLibrary.faction_shield("FN_NESSUNA") != null, "senza esportazione resta lo scudo predefinito rifatto")
	_teardown()


func test_colori_chiave_delle_pedine(t: TestContext) -> void:
	var img := Image.create(4, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color8(239, 0, 0))      # stendardo
	img.set_pixel(1, 0, Color8(0, 243, 247))    # anello ciano
	img.set_pixel(2, 0, Color8(247, 0, 247))    # anello magenta
	img.set_pixel(3, 0, Color8(120, 100, 80))   # figura: non cambia
	var primary := Color(0.2, 0.4, 0.8)
	var secondary := Color(0.9, 0.8, 0.1)
	PieceArt.recolor(img, primary, secondary)
	t.assert_true(_rgb_distance(img.get_pixel(0, 0), primary) < 0.03, "stendardo -> primario: %s" % img.get_pixel(0, 0))
	t.assert_true(_rgb_distance(img.get_pixel(1, 0), primary) < 0.03, "ciano -> primario")
	t.assert_true(_rgb_distance(img.get_pixel(2, 0), secondary) < 0.03, "magenta -> secondario")
	t.assert_eq(img.get_pixel(3, 0), Color8(120, 100, 80), "gli altri colori restano")


func test_lo_stendardo_si_riempie_con_le_pile(t: TestContext) -> void:
	var img := Image.create(1, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color8(239, 0, 0))   # stendardo di 10 righe
	var banner := Color(0.24, 0.24, 0.24)
	PieceArt.recolor_piece(img, banner, Color.WHITE, Color.BLACK, 0.5)
	t.assert_true(_rgb_distance(img.get_pixel(0, 9), banner) < 0.03, "si riempie dal basso")
	t.assert_true(_rgb_distance(img.get_pixel(0, 5), banner) < 0.03, "fino a meta'")
	t.assert_true(img.get_pixel(0, 4).a < 0.7, "sopra: pallido e trasparente")
	t.assert_true(img.get_pixel(0, 0).get_luminance() > img.get_pixel(0, 9).get_luminance(), "la parte vuota e' piu' chiara")
	FactionStyle.reset()
	t.assert_eq(FactionStyle.banner_color("FN_DANISH", Color.WHITE), Color("3c3c3c"), "gli Auror hanno lo stendardo grigio scuro")
	t.assert_eq(FactionStyle.banner_color("FN_ENGLISH", Color.RED), Color.RED, "gli altri il colore primario")


func test_pedine_rifatte_con_i_colori_della_fazione(t: TestContext) -> void:
	# pedine dipinte con AI Playground (tools/prepara_pedine.py): 2 volte l'originale, rettangoli in un .cfg accanto
	var original := "campmap/pieces/Units/Christian/army_held_awaiting.BIF"
	var layout := AssetLibrary.remade_layout(original)
	t.assert_true(layout.has("stendardo") and layout.has("base") and layout.has("scudo"), "rettangoli della pedina: %s" % layout)
	var campaign := StartposLoader.load_text("""
DeclareFaction:: "FN_ENGLISH"
SetFactionCol:: FN_ENGLISH 20 40 200 230 200 20
DeclareFaction:: "FN_EGYPTIAN"
SetFactionCol:: FN_EGYPTIAN 200 160 40 255 255 255
SetReligion:: FN_EGYPTIAN REL_MUSLIM
""")
	PieceArt.reset()
	var tex := PieceArt.army_piece(campaign, "FN_ENGLISH", "army", false, 1.0)
	t.assert_true(tex != null, "pedina rifatta")
	t.assert_eq(tex.get_height(), 460, "cornice comune delle pedine con stendardo (circa il doppio dell'originale, 224)")
	# a parita' di cornice la base e' larga uguale per tutti: sulla mappa nessuna pedina sembra piu' piccola delle altre
	for pair in [["campmap/pieces/Agents/bishop_held_awaiting.BIF", "campmap/pieces/Agents/grandinquisitor_held_moving.BIF"],
			["campmap/pieces/Units/Christian/army_held_awaiting.BIF", "campmap/pieces/Agents/Crusade_held_awaiting.Bif"]]:
		var a := AssetLibrary.texture(pair[0])
		var b := AssetLibrary.texture(pair[1])
		t.assert_eq(a.get_height(), b.get_height(), "stessa cornice: %s, %s" % pair)
		var wa: int = (AssetLibrary.remade_layout(pair[0])["base"] as Rect2i).size.x
		var wb: int = (AssetLibrary.remade_layout(pair[1])["base"] as Rect2i).size.x
		t.assert_true(absi(wa - wb) <= 8, "stessa base: %d e %d px" % [wa, wb])
	var img := tex.get_image()
	t.assert_true(img.has_mipmaps(), "con le riduzioni intermedie: si vede ridotta sulla mappa")
	var banner: Rect2i = layout["stendardo"]
	var blue := 0
	var red := 0
	var shield_top: int = (layout["scudo"] as Rect2i).position.y   # sotto c'e' lo stemma della fazione, con il suo rosso
	for y in range(banner.position.y, mini(banner.end.y, shield_top), 4):
		var c := img.get_pixel(banner.position.x + banner.size.x / 2, y)
		if c.b > c.r * 1.5:
			blue += 1
		elif PieceArt.key_of(c) == "rosso":
			red += 1
	t.assert_true(blue > 40, "stendardo del colore della fazione: %d campioni blu" % blue)
	t.assert_eq(red, 0, "nessun rosso chiave rimasto")
	var half := PieceArt.army_piece(campaign, "FN_ENGLISH", "army", false, 0.5)
	t.assert_true(half != tex, "riempimento diverso, pedina diversa")
	# agenti della cultura della fazione (Agents/Muslim) e, senza variante, quelli comuni
	t.assert_true(PieceArt.agent_piece(campaign, "FN_EGYPTIAN", "EMISSARY", false) != null, "emissario musulmano")
	t.assert_true(PieceArt.agent_piece(campaign, "FN_EGYPTIAN", "MULLAH", true) != null, "imam dalla cartella comune")
	PieceArt.reset()


func test_colori_chiave_delle_carte(t: TestContext) -> void:
	t.assert_eq(PieceArt.key_of(Color8(247, 0, 247)), "magenta")
	t.assert_eq(PieceArt.key_of(Color8(120, 0, 118)), "magenta", "anche nelle ombre")
	t.assert_eq(PieceArt.key_of(Color8(0, 230, 0)), "verde")
	t.assert_eq(PieceArt.key_of(Color8(0, 210, 214)), "ciano")
	t.assert_eq(PieceArt.key_of(Color8(222, 0, 0)), "rosso")
	t.assert_eq(PieceArt.key_of(Color8(150, 60, 40)), "", "un rosso naturale (mattone) non e' un colore chiave")
	t.assert_eq(PieceArt.key_of(Color8(30, 0, 30)), "", "troppo scuro per decidere")
	var img := Image.create(3, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color8(242, 0, 242))
	img.set_pixel(1, 0, Color8(0, 242, 0))
	img.set_pixel(2, 0, Color8(200, 170, 120))
	var primary := Color(1, 1, 1)
	var secondary := Color(0.8, 0, 0)
	PieceArt.recolor_card(img, primary, secondary)
	t.assert_true(_rgb_distance(img.get_pixel(0, 0), primary) < 0.03, "magenta -> primario")
	t.assert_true(_rgb_distance(img.get_pixel(1, 0), secondary) < 0.03, "verde -> secondario")
	t.assert_eq(img.get_pixel(2, 0), Color8(200, 170, 120), "la pelle resta")


func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func test_cartelle_delle_pedine_per_religione(t: TestContext) -> void:
	t.assert_eq(PieceArt.culture_folder("REL_CATHOLIC"), "Christian")
	t.assert_eq(PieceArt.culture_folder("REL_ORTHODOX"), "Christian")
	t.assert_eq(PieceArt.culture_folder("REL_MUSLIM"), "Muslim")
	t.assert_eq(PieceArt.culture_folder("REL_PAGAN"), "Pagan")
	t.assert_eq(PieceArt.ship_folder("REL_ORTHODOX"), "Orthodox")
	t.assert_eq(PieceArt.ship_folder("REL_CATHOLIC"), "Catholic")


func test_il_tema_si_costruisce_anche_senza_immagini(t: TestContext) -> void:
	OriginalHud.veste_nuova = false   # il pannello color carta di ADR-023; la cornice della veste nuova ha il suo test
	var theme := UiTheme.build(false)
	OriginalHud.veste_nuova = true
	t.assert_true(theme.default_font != null, "carattere del testo (Alegreya)")
	t.assert_true(theme.has_stylebox("panel", "PanelContainer"))
	t.assert_true(theme.get_stylebox("panel", "PanelContainer") is StyleBoxFlat, "senza immagini: pergamena disegnata")
	t.assert_eq(theme.get_color("font_color", "Label"), UiTheme.INK)
	t.assert_eq(theme.get_type_variation_base("Title"), &"Label")
	t.assert_eq(theme.get_type_variation_base("MapLabel"), &"Label")
	t.assert_eq(theme.get_type_variation_base("TopBar"), &"PanelContainer")
	t.assert_true(theme.get_font("font", "Title") != null, "Fondamento per i titoli")


func test_pannelli_rifiniti_con_gli_angoli_stondati_anche_con_le_immagini(t: TestContext) -> void:
	# richiesta di Federico (2026-11-10): niente effetto pergamena nei menu, un pannello color carta con gli angoli stondati
	_setup()
	var lines := FileAccess.get_file_as_string(ROOT.path_join("_manifest.csv"))
	var f := FileAccess.open(ROOT.path_join("_manifest.csv"), FileAccess.WRITE)
	f.store_string(lines + "05;frontend_files/wide_parchment_crop.BIF;05/frontend_files/wide_parchment_crop.BIF.png;600;560;1;bif\n")
	f.close()
	_png(ROOT.path_join("05/frontend_files/wide_parchment_crop.BIF.png"), 600, 560, Color.BEIGE)
	AssetLibrary.configure(ProjectSettings.globalize_path(ROOT), "")
	OriginalHud.veste_nuova = false   # veste originale: vale ADR-023
	var theme := UiTheme.build(true)
	OriginalHud.veste_nuova = true
	for type_name in ["PanelContainer", "Panel"]:
		var panel := theme.get_stylebox("panel", type_name) as StyleBoxFlat
		t.assert_true(panel != null, "%s: pannello disegnato, non la pergamena" % type_name)
		t.assert_eq(panel.bg_color, UiTheme.PAPER)
		t.assert_true(panel.corner_radius_top_left >= 8 and panel.corner_radius_bottom_right >= 8, "angoli stondati")
		t.assert_true(panel.border_width_left >= 1, "bordo")
		t.assert_true(panel.shadow_size > 0, "ombra")
	t.assert_true(theme.get_stylebox("panel", "TopBar") is StyleBoxFlat, "anche la barra in alto")
	t.assert_false(UiTheme.divider() is TextureRect, "separatore a linea, non il fregio")
	_teardown()


func test_pulsanti_rosso_scuro_con_testo_bianco(t: TestContext) -> void:
	var theme := UiTheme.build(false)
	for type_name in ["Button", "OptionButton"]:
		var normal := theme.get_stylebox("normal", type_name) as StyleBoxFlat
		t.assert_eq(normal.bg_color, UiTheme.BUTTON_BG, type_name)
		t.assert_eq(theme.get_color("font_color", type_name), Color.WHITE, type_name)
		t.assert_eq(theme.get_color("font_hover_color", type_name), Color.WHITE, type_name)
		t.assert_eq(theme.get_color("font_pressed_color", type_name), Color.WHITE, type_name)
	# contrasto WCAG del testo bianco sul fondo rosso scuro: almeno 4,5:1 (AA), qui oltre 7:1
	for bg in [UiTheme.BUTTON_BG, UiTheme.BUTTON_BG_HOVER, UiTheme.BUTTON_BG_PRESSED]:
		t.assert_true(_contrast(Color.WHITE, bg) >= 7.0, "contrasto %.1f" % _contrast(Color.WHITE, bg))
	# le tessere con immagine e le intestazioni richiudibili restano d'inchiostro
	t.assert_eq(theme.get_type_variation_base("Tile"), &"Button")
	t.assert_eq(theme.get_color("font_color", "Tile"), UiTheme.INK)
	t.assert_eq(theme.get_color("font_pressed_color", "Section"), UiTheme.INK_BAD)


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(c: Color) -> float:
	var out := 0.0
	var weights := [0.2126, 0.7152, 0.0722]
	var channels := [c.r, c.g, c.b]
	for i in 3:
		var v: float = channels[i]
		v = v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
		out += weights[i] * v
	return out


## Veste nuova (ADR-028): menu e finestre nella cornice a nove parti di legno e ottone, con il contenuto ben dentro.
func test_pannelli_con_la_cornice_della_veste_nuova(t: TestContext) -> void:
	if OriginalHud.skin_texture("pannello") == null:
		t.skip("assets/ui/veste/pannello.png non importata")
		return
	var before := OriginalHud.veste_nuova
	OriginalHud.veste_nuova = true
	var theme := UiTheme.build(false)
	OriginalHud.veste_nuova = before
	for type_name in ["PanelContainer", "Panel", "TopBar"]:
		var box := theme.get_stylebox("panel", type_name) as StyleBoxTexture
		t.assert_true(box != null, "%s: cornice a nove parti" % type_name)
		t.assert_eq(box.texture_margin_left, float(UiTheme.FRAME_EDGE))
		t.assert_eq(box.axis_stretch_horizontal, StyleBoxTexture.AXIS_STRETCH_MODE_TILE, "centro e bordi ripetuti, non stirati")
		t.assert_true(box.content_margin_left >= float(UiTheme.FRAME_EDGE), "il contenuto non tocca la cornice")
	var tex := OriginalHud.skin_texture("pannello")
	t.assert_eq(tex.get_width(), 256 + 2 * UiTheme.FRAME_EDGE, "margine + piastrella intera + margine")
	t.assert_eq(tex.get_image().get_pixel(0, 0).a, 0.0, "angoli stondati: l'angolo esterno e' trasparente")


## Immagini rifatte (ADR-043): il percorso nel progetto ricalca quello dell'originale, in minuscolo e in PNG.
func test_percorso_delle_immagini_rifatte(t: TestContext) -> void:
	t.assert_eq(AssetLibrary.remade_path("campmap/Portraits/Catholic/King/king58.tga"), "res://assets/rifatti/campmap/portraits/catholic/king/king58.png")
	t.assert_eq(AssetLibrary.remade_path("campmap\\review_panel\\buildings\\spearmaker.BIF"), "res://assets/rifatti/campmap/review_panel/buildings/spearmaker.png")
	t.assert_true(AssetLibrary.remade("campmap/che/non/esiste.tga") == null)
	var king := AssetLibrary.remade("campmap/Portraits/Catholic/King/king58.tga")
	t.assert_true(king != null and king.get_size() == Vector2(384, 568), "il re cattolico rifatto c'e'")
	if king != null:
		t.assert_true(king.get_image().has_mipmaps(), "con le riduzioni intermedie")


## Le fazioni musulmane (REL_ISLAMIC nei dati) prendono i ritratti musulmani.
func test_cartella_dei_ritratti_per_religione(t: TestContext) -> void:
	t.assert_eq(PortraitArt.religion_folder("REL_ISLAMIC"), "Muslim")
	t.assert_eq(PortraitArt.religion_folder("MUSLIM"), "Muslim")
	t.assert_eq(PortraitArt.religion_folder("REL_ORTHODOX"), "Orthodox")
	t.assert_eq(PortraitArt.religion_folder("REL_CATHOLIC"), "Catholic")
	t.assert_eq(PortraitArt.religion_folder(""), "Catholic")


## La prova dell'uscarlo vichingo sostituisce la miniatura degli eserciti, non l'illustrazione della scheda (Federico, 11/11).
func test_la_carta_rifatta_degli_uscarli(t: TestContext) -> void:
	t.assert_true(AssetLibrary.is_remade("campmap/review_panel/Units/VikingHuscarles.BIF"), "miniatura rifatta")
	t.assert_true(AssetLibrary.is_remade("campmap/Info_Pics/Units/VikingHuscarles.BIF"), "anche la scheda grande (ADR-063)")
	t.assert_true(AssetLibrary.is_remade("campmap/Info_Pics/Ships/Cog.BIF"), "e quella delle navi")
	t.assert_false(AssetLibrary.is_remade(""))
