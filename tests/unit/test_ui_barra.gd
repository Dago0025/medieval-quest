extends RefCounted
## Geometria della barra in basso (OriginalHud) rispetto ai riquadri di campmap/info_panel.BIF (240x115), misurati sui pixel
## (segnalazione di Federico del 2026-11-10: pulsanti, carte e scudo disallineati).


func test_i_pulsanti_informativi_stanno_nella_fascia_alta(t: TestContext) -> void:
	t.assert_true(OriginalHud.INFO_X >= 6.0, "dentro il bordo sinistro")
	t.assert_true(OriginalHud.INFO_X + 5.0 * 35.0 <= 219.0, "dentro il bordo destro")
	t.assert_true(absf((OriginalHud.INFO_X - 6.0) - (219.0 - OriginalHud.INFO_X - 5.0 * 35.0)) <= 1.0, "centrati")
	# veste nuova: i medaglioni sono distanziati, sempre dentro la fascia e centrati; barra dell'originale: accostati
	var before := OriginalHud.veste_nuova
	OriginalHud.veste_nuova = true
	t.assert_eq(OriginalHud.info_x(1) - OriginalHud.info_x(0), 35.0 + OriginalHud.INFO_GAP_NEW, "spazio tra i medaglioni")
	t.assert_true(OriginalHud.info_x(0) >= 6.0 and OriginalHud.info_x(4) + 35.0 <= 219.0, "dentro la fascia")
	t.assert_true(absf((OriginalHud.info_x(0) - 6.0) - (219.0 - OriginalHud.info_x(4) - 35.0)) <= 1.0, "centrati")
	OriginalHud.veste_nuova = false
	t.assert_eq(OriginalHud.info_x(0), OriginalHud.INFO_X, "barra dell'originale: come prima")
	t.assert_eq(OriginalHud.info_x(4), OriginalHud.INFO_X + 4.0 * 35.0)
	OriginalHud.veste_nuova = before


func test_carte_ai_lati_dello_scudo_dentro_la_fascia_bassa(t: TestContext) -> void:
	var shield := OriginalHud.SHIELD_RECT
	var build := Rect2(OriginalHud.BUILD_POS, OriginalHud.CARD_SIZE)
	var train := Rect2(OriginalHud.TRAIN_POS, OriginalHud.CARD_SIZE)
	t.assert_true(build.position.x >= 6.0 and build.end.x <= shield.position.x, "costruzione a sinistra dello scudo")
	t.assert_true(train.position.x >= shield.end.x and train.end.x <= OriginalHud.LEFT_W - 20.0, "addestramento a destra, prima della colonna")
	for r in [build, train]:
		t.assert_true(r.position.y >= 38.0 and r.end.y <= 111.0, "dentro la fascia bassa: %s" % r)
	t.assert_true(OriginalHud.CARD_INNER.end.x <= OriginalHud.CARD_SIZE.x and OriginalHud.CARD_INNER.end.y <= OriginalHud.CARD_SIZE.y)


func test_le_frecce_formano_la_colonna_di_destra(t: TestContext) -> void:
	t.assert_eq(58.0 + 57.0, OriginalHud.BAR_H, "ipprev 20x58 sopra, ipnext 20x57 sotto")


func test_medaglione_rotondo_dei_pulsanti(t: TestContext) -> void:
	var img := Image.create(35, 33, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.2, 0.2, 1.0))
	var round_tex := OriginalHud._round(ImageTexture.create_from_image(img))
	var out := round_tex.get_image()
	t.assert_eq(out.get_pixel(0, 0).a, 0.0, "angolo trasparente")
	t.assert_eq(out.get_pixel(34, 32).a, 0.0, "angolo opposto trasparente")
	t.assert_eq(out.get_pixel(17, 16).a, 1.0, "centro pieno")
	t.assert_true(OriginalHud._round(null) == null)


## Medaglioni dipinti (ADR-038): cinque pulsanti per tre stati, 140x132 (4 volte il 35x33 dell'originale), rotondi.
func test_i_medaglioni_dipinti_ci_sono_tutti(t: TestContext) -> void:
	for name in OriginalHud.INFO_BUTTONS:
		for state in ["", "_sopra", "_premuto"]:
			var tex := OriginalHud.medallion_texture(str(name), state)
			t.assert_true(tex != null, "medaglione_%s%s" % [name, state])
			if tex == null:
				continue
			t.assert_eq(tex.get_size(), Vector2(140, 132), "misura di medaglione_%s%s" % [name, state])
			var img := tex.get_image()
			t.assert_true(img.has_mipmaps(), "riduzioni intermedie per non sgranare")
			t.assert_eq(img.get_pixel(0, 0).a, 0.0, "angolo trasparente")
			t.assert_eq(img.get_pixel(70, 66).a, 1.0, "centro pieno")
			t.assert_eq(img.get_pixel(70, 3).a, 1.0, "anello pieno in alto")
	t.assert_true(OriginalHud.medallion_texture("inesistente") == null)


## Con la veste nuova i pulsanti informativi usano i medaglioni dipinti, con uno stato per il puntatore sopra e uno per il
## clic; con la barra dell'originale restano le immagini dell'installazione.
func test_i_pulsanti_informativi_usano_i_medaglioni_dipinti(t: TestContext) -> void:
	var before := OriginalHud.veste_nuova
	OriginalHud.veste_nuova = true
	var hud := OriginalHud.new()
	hud._ready()
	t.assert_eq(hud._info_buttons.size(), 5)
	for i in hud._info_buttons.size():
		var b := hud._info_buttons[i] as TextureButton
		var name := str(OriginalHud.INFO_BUTTONS[i])
		t.assert_true(b.texture_normal == OriginalHud.medallion_texture(name), "normale: %s" % name)
		t.assert_true(b.texture_hover == OriginalHud.medallion_texture(name, "_sopra"), "sopra: %s" % name)
		t.assert_true(b.texture_pressed == OriginalHud.medallion_texture(name, "_premuto"), "premuto: %s" % name)
		t.assert_eq(b.size, Vector2(35, 33), "stessa misura nella barra")
	hud.free()
	OriginalHud.veste_nuova = false
	hud = OriginalHud.new()
	hud._ready()
	for b in hud._info_buttons:
		t.assert_true((b as TextureButton).texture_normal != OriginalHud.medallion_texture("military"), "barra dell'originale")
	hud.free()
	OriginalHud.veste_nuova = before


## Veste nuova (ADR-027): stessa geometria, barra piu' grande; la veste originale resta disponibile.
func test_scala_della_veste_nuova_e_di_quella_originale(t: TestContext) -> void:
	var before := OriginalHud.veste_nuova
	OriginalHud.veste_nuova = true
	t.assert_eq(OriginalHud.scale_for(900.0), 1.5, "a 900 di altezza la barra e' 1200x172")
	t.assert_eq(OriginalHud.scale_for(480.0), 1.0, "mai sotto la misura dell'originale")
	t.assert_eq(OriginalHud.scale_for(2160.0), 2.2, "tetto della veste nuova")
	OriginalHud.veste_nuova = false
	t.assert_eq(OriginalHud.scale_for(900.0), 1.25, "veste originale: altezza / 720")
	t.assert_eq(OriginalHud.scale_for(2160.0), 2.0)
	OriginalHud.veste_nuova = before


func test_la_barra_si_costruisce_in_entrambe_le_vesti(t: TestContext) -> void:
	var before := OriginalHud.veste_nuova
	for nuova in [true, false]:
		OriginalHud.veste_nuova = nuova
		var hud := OriginalHud.new()
		hud._ready()
		hud.layout(Vector2(1600, 900))
		hud.set_status(1200, 1000, "", "", false, "")
		hud.show_review("Prova", [], PackedStringArray(["riga"]), true)
		var expected := (OriginalHud.BAR_H + 2.0 * OriginalHud.BAR_PAD + OriginalHud.BAR_GAP) * 1.5 if nuova else OriginalHud.BAR_H * 1.25
		t.assert_eq(hud.bar_height(), expected, "spazio occupato dalla barra, veste nuova = %s" % nuova)
		t.assert_true(hud.covers(Vector2(800, 860)), "la fascia in basso e' della barra")
		# la veste nuova sta staccata dal fondo: l'ultima striscia e' della mappa; quella originale arriva al bordo
		t.assert_eq(hud.covers(Vector2(800, 897)), not nuova, "striscia sotto la barra, veste nuova = %s" % nuova)
		t.assert_true(not hud.covers(Vector2(800, 400)), "il centro e' della mappa")
		hud.free()
	OriginalHud.veste_nuova = before


func test_il_riquadro_delle_carte_nuove_sta_dentro_la_carta(t: TestContext) -> void:
	var card := Rect2(Vector2.ZERO, OriginalHud.CARD_SIZE)
	t.assert_true(card.encloses(OriginalHud.NEW_CARD_WELL), "la cornice d'ottone non esce dalla carta 80x61")
	t.assert_true(OriginalHud.NEW_CARD_WELL.size.x >= OriginalHud.CARD_INNER.size.x, "non piu' piccolo del riquadro dell'originale")


## Richiesta di Federico dell'11/11/2026: il castello scelto ha nella barra la sua icona, il nome del tipo in grassetto e le
## armate accanto. La colonna dell'icona c'e' solo quando serve.
func test_la_rassegna_con_l_icona_a_fianco(t: TestContext) -> void:
	var hud := OriginalHud.new()
	hud._ready()
	hud.layout(Vector2(1600, 900))
	var img := Image.create(54, 40, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	hud.show_review("Castello · Prova", [], PackedStringArray(["Nessuna truppa nel castello."]), true,
		{"immagine": tex, "nome": "Fortezza", "nota": "Guarnigione 0/16", "suggerimento": "Fortezza"})
	t.assert_true(hud._side_icon.visible, "icona del castello visibile")
	t.assert_eq(hud._side_icon.texture, tex)
	t.assert_true(hud._side_head.visible)
	t.assert_eq(hud._side_name.text, "Fortezza")
	t.assert_eq(hud._side_note.text, "Guarnigione 0/16")
	t.assert_true(hud._side_name.has_theme_font_override("font"), "nome del tipo in grassetto")
	hud.show_review("Provincia", [], PackedStringArray(["riga"]), true)
	t.assert_false(hud._side_icon.visible, "senza castello la colonna sparisce")
	t.assert_false(hud._side_head.visible)
	hud.free()


func test_il_pulsante_congeda_si_accende_e_si_spegne(t: TestContext) -> void:
	var hud := OriginalHud.new()
	hud._ready()
	t.assert_false(hud._dismiss_button.visible, "nascosto finche' non serve")
	hud.set_dismiss(true, false, "Congeda", "Scegli")
	t.assert_true(hud._dismiss_button.visible and hud._dismiss_button.disabled)
	hud.set_dismiss(true, true, "Congeda (2)", "")
	t.assert_false(hud._dismiss_button.disabled)
	t.assert_eq(hud._dismiss_button.text, "Congeda (2)")
	hud.set_dismiss(false)
	t.assert_false(hud._dismiss_button.visible)
	hud.free()


## ADR-035: i comandi dell'esercito stanno nella barra, non in una pergamena a parte.
func test_i_comandi_dell_esercito_nella_barra(t: TestContext) -> void:
	var hud := OriginalHud.new()
	hud._ready()
	var got := []
	hud.action_pressed.connect(func(id: String) -> void: got.append(id))
	hud.set_actions([{"id": "castello", "testo": "Barricati", "suggerimento": "Nel castello", "attivo": true},
		{"id": "riaddestra", "testo": "Riaddestra", "suggerimento": "", "attivo": false}])
	t.assert_eq(hud._actions_box.get_child_count(), 2)
	var first := hud._actions_box.get_child(0) as Button
	var second := hud._actions_box.get_child(1) as Button
	t.assert_eq(first.text, "Barricati")
	t.assert_true(second.disabled and not first.disabled)
	first.pressed.emit()
	t.assert_eq(got, ["castello"])
	hud.set_actions([])
	t.assert_eq(hud._actions_box.get_child_count(), 0, "senza esercito nessun comando")
	hud.free()


func test_il_pennacchio_del_comandante_sta_in_alto_a_sinistra(t: TestContext) -> void:
	var hud := OriginalHud.new()
	hud._ready()
	var img := Image.create(14, 31, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	hud.show_review("Esercito", [{"immagine": tex, "misura": Vector2(38, 38), "didascalia": "40", "distintivo": tex}], PackedStringArray(), false)
	var flag := hud._review_flow.get_child(0).get_node_or_null("Distintivo") as Control
	t.assert_true(flag != null, "la carta del comandante ha il pennacchio")
	if flag != null:
		t.assert_true(flag.position.x < 19.0, "nella meta' sinistra della carta: x = %s" % flag.position.x)
	hud.free()


## Carte, freccia e pennacchi dipinti (ADR-040): ci sono tutti, alla loro misura e con le riduzioni intermedie.
func test_le_immagini_dipinte_della_barra_ci_sono(t: TestContext) -> void:
	var sizes := {"carta_build": Vector2(232, 212), "carta_trainunit": Vector2(232, 212), "freccia": Vector2(64, 208),
		"pennacchio_king": Vector2(112, 248), "pennacchio_heir": Vector2(112, 248), "pennacchio_noble": Vector2(112, 248),
		"pennacchio_merc": Vector2(112, 248)}
	for name in sizes:
		var tex := OriginalHud.painted_texture(str(name))
		t.assert_true(tex != null, str(name))
		if tex != null:
			t.assert_eq(tex.get_size(), sizes[name], "misura di %s" % name)
			t.assert_true(tex.get_image().has_mipmaps(), "riduzioni intermedie: %s" % name)
	t.assert_true(OriginalHud.painted_texture("inesistente") == null)


## Il pennacchio del comandante: dipinto con la veste nuova, dell'installazione con la barra dell'originale.
func test_il_pennacchio_dipinto_per_ruolo(t: TestContext) -> void:
	var before := OriginalHud.veste_nuova
	OriginalHud.veste_nuova = true
	for kind in ["king", "heir", "noble"]:
		var tex := OriginalHud.pennant_texture("campmap/is_%s_mon.BIF" % kind)
		t.assert_true(tex != null and tex == OriginalHud.painted_texture("pennacchio_" + kind), "pennacchio dipinto: %s" % kind)
	t.assert_true(OriginalHud.pennant_texture("") == null, "senza comandante nessun pennacchio")
	OriginalHud.veste_nuova = false
	t.assert_true(OriginalHud.pennant_texture("campmap/is_king_mon.BIF") != OriginalHud.painted_texture("pennacchio_king"), "barra dell'originale")
	OriginalHud.veste_nuova = before


## Con la veste nuova le due carte mostrano il disegno dipinto (o l'icona della prima voce in coda) e le frecce la punta
## d'ottone dipinta, una in su e una in giu'.
func test_carte_e_frecce_dipinte_nella_veste_nuova(t: TestContext) -> void:
	var before := OriginalHud.veste_nuova
	OriginalHud.veste_nuova = true
	var hud := OriginalHud.new()
	hud._ready()
	hud.set_cards(null, "", null, "")
	t.assert_true(hud._build_card.texture == OriginalHud.painted_texture("carta_build"), "carta di costruzione dipinta")
	t.assert_true(hud._train_card.texture == OriginalHud.painted_texture("carta_trainunit"), "carta di addestramento dipinta")
	var queued := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	hud.set_cards(queued, "", null, "")
	t.assert_true(hud._build_card.texture == queued, "con una voce in coda la carta mostra la sua icona")
	t.assert_true(hud._train_card.texture == OriginalHud.painted_texture("carta_trainunit"))
	var heads := hud._bar.find_children("Freccia", "TextureRect", true, false)
	t.assert_eq(heads.size(), 2, "due frecce dipinte")
	if heads.size() == 2:
		t.assert_true((heads[0] as TextureRect).flip_v != (heads[1] as TextureRect).flip_v, "una in su e una in giu'")
	hud.free()
	OriginalHud.veste_nuova = before
