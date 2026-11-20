extends RefCounted
## Ritratto proprio del capo di una fazione (data/fazioni.cfg [ritratti], richiesta di Federico dell'11/11/2026).


func _leader(faction_id: String, numeral: int) -> Character:
	var c := Character.new()
	c.faction = faction_id
	c.role = Character.ROLE_LEADER
	c.numeral = numeral
	return c


func test_darkos_i_ha_il_suo_ritratto(t: TestContext) -> void:
	FactionStyle.reset()
	var path := FactionStyle.leader_portrait("FN_DANISH", 1)
	t.assert_eq(path, "res://assets/ritratti/darkos_i.png")
	t.assert_true(FileAccess.file_exists(path), "l'immagine c'e'")
	t.assert_eq(PortraitArt.custom_portrait_path(_leader("FN_DANISH", 1)), path)


func test_il_ritratto_spetta_solo_a_quel_re(t: TestContext) -> void:
	FactionStyle.reset()
	t.assert_eq(FactionStyle.leader_portrait("FN_DANISH", 2), "", "Darkos II ha un ritratto dell'installazione")
	t.assert_eq(FactionStyle.leader_portrait("FN_FRENCH", 1), "", "le altre fazioni no")
	t.assert_eq(PortraitArt.custom_portrait_path(_leader("FN_DANISH", 2)), "")
	var prince := _leader("FN_DANISH", 1)
	prince.role = Character.ROLE_PRINCE
	t.assert_eq(PortraitArt.custom_portrait_path(prince), "", "solo il capo")
	t.assert_eq(PortraitArt.custom_portrait_path(null), "")


func test_la_cornice_della_minimappa_e_sottile(t: TestContext) -> void:
	var hud := OriginalHud.new()
	hud._ready()
	t.assert_true(hud._mini_frame() <= 3.0, "bordo sottile con la veste nuova")
	t.assert_eq(hud._minimap.size, Vector2(OriginalHud.MINI_W + hud._mini_frame() * 2.0, OriginalHud.MINI_H + hud._mini_frame() * 2.0), "niente fascia a destra")
	hud.free()


## Cornice comune dei ritratti (richiesta di Federico dell'11/11): ogni ritratto e' un riquadro con immagine e cornice;
## a quelli dell'originale (96x142) si toglie prima la cornice di pietra.
func test_la_cornice_comune_dei_ritratti(t: TestContext) -> void:
	var tex := ImageTexture.create_from_image(Image.create(96, 142, false, Image.FORMAT_RGBA8))
	var box := UiTheme.portrait(tex, Vector2(96, 142))
	t.assert_eq(box.custom_minimum_size, Vector2(96, 142))
	t.assert_true(box.get_node_or_null("Immagine") is TextureRect and box.get_node_or_null("Cornice") != null, "immagine e cornice")
	t.assert_true(UiTheme.portrait_frame_width(Vector2(96, 142)) <= 3.0, "cornice sottile")
	box.free()
	var inner := PortraitArt.without_stone_frame(tex)
	t.assert_true(inner is AtlasTexture, "ritratto dell'originale ritagliato")
	t.assert_eq(inner.get_size(), Vector2(96 - 2 * PortraitArt.STONE_FRAME, 142 - 2 * PortraitArt.STONE_FRAME))
	var big := ImageTexture.create_from_image(Image.create(384, 568, false, Image.FORMAT_RGBA8))
	t.assert_true(PortraitArt.without_stone_frame(big) == big, "i ritratti dipinti restano interi")
	t.assert_true(PortraitArt.without_stone_frame(null) == null)


## Serie nuove dei ritratti (ADR-044, Federico 13/11/2026): i 51 re cattolici nuovi prendono il posto dei 94 dell'originale.
func test_la_serie_dei_re_cattolici(t: TestContext) -> void:
	PortraitArt.reset()
	var kings := PortraitArt.series("Catholic", "King")
	t.assert_eq(kings.size(), 51, "re n. 0 (prova dell'11/11) e i 50 nuovi")
	t.assert_eq(kings[0], "res://assets/ritratti/catholic/king/00.png")
	t.assert_eq(kings[50], "res://assets/ritratti/catholic/king/50.png")
	var tex := PortraitArt.series_texture(kings[7])
	t.assert_true(tex != null and tex.get_size() == Vector2(384, 568), "ritratto dipinto intero")
	t.assert_true(tex.get_image().has_mipmaps(), "con le mipmap, ridotto non sgrana")


func test_i_re_cattolici_pescano_solo_dalla_serie_nuova(t: TestContext) -> void:
	PortraitArt.reset()
	var seen := {}
	for id in range(1, 400):
		var king := _leader("FN_FRENCH", 1)
		king.id = id
		var path := PortraitArt.portrait_path(null, king)   # senza campagna: religione cattolica
		t.assert_true(path.begins_with("res://assets/ritratti/catholic/king/"), "re %d dalla serie nuova" % id)
		seen[path] = true
	t.assert_eq(seen.size(), 51, "tutti i 51 ritratti escono")
	var heir := _leader("FN_FRENCH", 1)
	heir.role = Character.ROLE_HEIR
	t.assert_true(PortraitArt.portrait_path(null, heir).begins_with("res://assets/ritratti/catholic/prince/"), "eredi dalla serie dei principi")


## Tutte le serie nuove (Federico 13/11/2026: tutti i ritratti generati con AI Playground nel gioco): ogni religione ha
## regnanti, generali, principi ed eredi, principesse propri; nessuno pesca piu' dall'installazione e i pagani non
## ripiegano piu' sui cattolici.
const SERIE := {
	"catholic": {"king": 51, "general": 41, "prince": 31, "princess": 31},
	"muslim": {"king": 31, "general": 30, "prince": 15, "princess": 15},
	"orthodox": {"king": 21, "general": 20, "prince": 12, "princess": 12},
	"pagan": {"king": 15, "general": 15, "prince": 10, "princess": 10},
}
const RELIGIONI := {"catholic": "REL_CATHOLIC", "muslim": "REL_ISLAMIC", "orthodox": "REL_ORTHODOX", "pagan": "REL_PAGAN"}
const RUOLI := {"king": Character.ROLE_LEADER, "general": Character.ROLE_GENERAL, "prince": Character.ROLE_PRINCE, "princess": Character.ROLE_PRINCESS}


func test_tutte_le_serie_per_religione_e_ruolo(t: TestContext) -> void:
	PortraitArt.reset()
	for rel in SERIE:
		for role in SERIE[rel]:
			var files := PortraitArt.series(rel.capitalize(), role.capitalize())
			t.assert_eq(files.size(), SERIE[rel][role], "%s/%s" % [rel, role])


func test_ogni_religione_pesca_dalla_sua_serie(t: TestContext) -> void:
	PortraitArt.reset()
	var campaign := CampaignData.new()
	for rel in RELIGIONI:
		campaign.add_faction("FN_" + rel.to_upper()).religion = RELIGIONI[rel]
	for rel in RELIGIONI:
		for role in RUOLI:
			var seen := {}
			for id in range(1, 300):
				var c := Character.new(id)
				c.faction = "FN_" + rel.to_upper()
				c.role = RUOLI[role]
				var path := PortraitArt.portrait_path(campaign, c)
				t.assert_true(path.begins_with("res://assets/ritratti/%s/%s/" % [rel, role]), "%s %s %d: %s" % [rel, role, id, path])
				seen[path] = true
			t.assert_eq(seen.size(), SERIE[rel][role], "%s/%s: escono tutti" % [rel, role])
