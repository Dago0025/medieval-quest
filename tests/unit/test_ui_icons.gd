extends RefCounted
## Test delle icone della fase 8 (UiIcons, data/ui/icone.cfg): ogni merce e ogni giacimento dello startpos reale ha un'icona,
## ogni percorso della tabella esiste nell'esportazione delle immagini e le righe d'icona ripiegano sul testo senza immagini.
## Le prove sui dati reali si saltano senza l'installazione o senza _ASSET_EXPORT.


func _real_assets(t: TestContext) -> bool:
	AssetLibrary.reset()
	UiIcons.reset()
	if not GameFiles.is_available() or not AssetLibrary.is_available():
		t.skip("installazione o esportazione delle immagini non trovata")
		return false
	return true


func test_la_tabella_ha_tutte_le_sezioni(t: TestContext) -> void:
	UiIcons.reset()
	for section in ["merci", "risorse", "religioni", "attributi"]:
		t.assert_true(UiIcons.path_for(section, "x_inesistente") == "", "%s: un nome sconosciuto non ha icona" % section)
	t.assert_eq(UiIcons.path_for("merci", "glassware"), "campmap/parchments/Icons/goods_glass.BIF", "maiuscole indifferenti")
	t.assert_eq(UiIcons.label_for("merci", "OLIVEOIL"), "Olio d'oliva")
	t.assert_eq(UiIcons.label_for("risorse", "SALT"), "Salgemma", "il sale come giacimento e' salgemma")
	t.assert_eq(UiIcons.label_for("merci", "AMBRA"), "Ambra", "senza nome italiano: il nome dei dati")
	for attr in [Character.ATTR_COMMAND, Character.ATTR_DREAD, Character.ATTR_PIETY, Character.ATTR_ACUMEN, Character.ATTR_LOYALTY, Character.ATTR_INFLUENCE]:
		t.assert_true(UiIcons.path_for("attributi", attr) != "", "icona per l'attributo %s" % attr)
	for key in ProvinceState.RELIGIONS:
		t.assert_true(UiIcons.path_for("religioni", key) != "", "icona per la religione %s" % key)


func test_ogni_merce_e_giacimento_dello_startpos_ha_un_icona(t: TestContext) -> void:
	if not _real_assets(t):
		return
	var campaign := StartposLoader.load_file(GameFiles.startpos())
	var goods := {}
	var ores := {}
	for r in campaign.land_regions():
		for g in r.trade_goods:
			goods[g] = true
		for o in r.resources:
			ores[o] = true
	t.assert_true(goods.size() > 10, "lo startpos ha le merci")
	for g in goods:
		t.assert_true(UiIcons.texture("merci", g) != null, "icona della merce %s" % g)
	for o in ores:
		t.assert_true(UiIcons.texture("risorse", o) != null, "icona del giacimento %s" % o)
	AssetLibrary.reset()


func test_ogni_percorso_della_tabella_esiste(t: TestContext) -> void:
	if not _real_assets(t):
		return
	var cfg := ConfigFile.new()
	t.assert_eq(cfg.load(UiIcons.TABLE), OK)
	for section in ["merci", "risorse", "religioni", "attributi"]:
		for k in cfg.get_section_keys(section):
			var p := str(cfg.get_value(section, k))
			t.assert_true(AssetLibrary.has(p) or AssetLibrary.is_remade(p), "%s/%s: %s nell'esportazione o rifatta" % [section, k, p])
	AssetLibrary.reset()


func test_senza_immagini_le_icone_diventano_testo(t: TestContext) -> void:
	AssetLibrary.configure(ProjectSettings.globalize_path("user://cartella_che_non_esiste"), "")
	UiIcons.reset()
	var c := UiIcons.icon("merci", "WINE", "Vino")
	t.assert_true(c is Label, "un'etichetta al posto dell'immagine")
	t.assert_eq((c as Label).text, "Vino")
	var a := UiIcons.attribute(Character.ATTR_ACUMEN, 8, "Acume")
	t.assert_eq((a.get_child(0) as Label).text, "Acume 8")
	var s := UiIcons.stars(3)
	t.assert_eq((s.get_child(0) as Label).text, "3 stelle")
	for n in [c, a, s]:
		n.free()
	AssetLibrary.reset()

## ADR-071: ogni icona di merci e giacimenti della tabella ha la versione rifatta (tools/prepara_risorse.py), comprese
## osso di balena e peltro che nell'originale non ne avevano una propria. Le prove non chiedono l'esportazione delle immagini.
func test_merci_e_giacimenti_sono_rifatte(t: TestContext) -> void:
	var cfg := ConfigFile.new()
	t.assert_eq(cfg.load(UiIcons.TABLE), OK)
	var seen := {}
	## giacimenti: i cinque dello startpos e del file degli edifici (stagno, piombo, foreste e vigne non sono usati)
	var keys := {"merci": cfg.get_section_keys("merci"), "risorse": ["IRON", "COPPER", "SILVER", "GOLD", "SALT"]}
	for section in keys:
		for k in keys[section]:
			var p := str(cfg.get_value(section, k))
			t.assert_true(AssetLibrary.is_remade(p), "%s/%s: %s rifatta" % [section, k, p])
			seen[p] = true
	t.assert_eq(UiIcons.path_for("merci", "WHALEBONE"), "campmap/parchments/Icons/goods_whalebone.BIF", "osso di balena con icona propria")
	t.assert_eq(UiIcons.path_for("merci", "PEWTER"), "campmap/parchments/Icons/goods_pewter.BIF", "peltro con icona propria")
	t.assert_true(UiIcons.path_for("merci", "SALT") != UiIcons.path_for("risorse", "SALT"), "sale e salgemma restano diversi")
	t.assert_eq(seen.size(), 29, "29 icone distinte: 24 merci e 5 giacimenti")
