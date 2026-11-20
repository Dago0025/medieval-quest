extends RefCounted
## Test della versione inglese (ADR-066): Lang (tabella, lingua salvata), nomi dei dati e grammatica delle fazioni in inglese,
## copertura della tabella data/lingue/en.tsv per ogni frase di Lang.t nel codice. Ogni test torna all'italiano.

const TABLE := "res://data/lingue/en.tsv"
const PLACEHOLDER := "%(?:%|[-+ 0#]*\\d*(?:\\.\\d+)?[sdifxXc])"


func _back_to_italian() -> void:
	Lang.use_table(Lang.EN, null)
	Lang.set_language(Lang.IT)


func test_italiano_di_partenza_e_invariato(t: TestContext) -> void:
	t.assert_eq(Lang.current(), Lang.IT, "senza scelte la lingua e' l'italiano")
	t.assert_eq(Lang.t("Fine anno"), "Fine anno")
	t.assert_eq(Lang.pick("sì", "yes"), "sì")
	t.assert_eq(Lang.data_path("res://data/nomi_edifici.cfg"), "res://data/nomi_edifici.cfg")


func test_tabella_esplicita_in_inglese(t: TestContext) -> void:
	Lang.use_table(Lang.EN, {"Esercito %d: da %s a %s.": "Army %d: from %s to %s."})
	Lang.set_language(Lang.EN)
	t.assert_true(Lang.is_english())
	t.assert_eq(Lang.t("Esercito %d: da %s a %s.") % [3, "A", "B"], "Army 3: from A to B.")
	t.assert_eq(Lang.t("Frase che non c'e'"), "Frase che non c'e'", "senza traduzione resta l'italiano")
	t.assert_true(Lang.missing().has("Frase che non c'e'"), "e finisce tra le mancanti")
	t.assert_eq(Lang.pick("sì", "yes"), "yes")
	t.assert_eq(TranslationServer.get_locale(), "en", "traduzione automatica dei nodi in inglese")
	_back_to_italian()
	t.assert_eq(Lang.t("Esercito %d: da %s a %s."), "Esercito %d: da %s a %s.")
	t.assert_eq(TranslationServer.get_locale(), "it")


func test_lettura_della_tabella(t: TestContext) -> void:
	var path := "user://test_lingua.tsv"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("# commento\n\nUno\\nDue\tOne\\nTwo\nTab\\tqui\tTab\\there\nSenza traduzione\t\nBarra \\\\\tBackslash \\\\\n")
	f.close()
	var table := Lang.load_tsv(path)
	t.assert_eq(table.get("Uno\nDue", ""), "One\nTwo", "a capo")
	t.assert_eq(table.get("Tab\tqui", ""), "Tab\there", "tabulazione")
	t.assert_eq(table.get("Barra \\", ""), "Backslash \\", "barra rovescia")
	t.assert_false(table.has("Senza traduzione"), "le righe senza traduzione si saltano")
	t.assert_false(table.has("# commento"))
	DirAccess.remove_absolute(path)


func test_lingua_scelta_resta_salvata(t: TestContext) -> void:
	UserSettings.path = "user://test_lingua_impostazioni.cfg"
	DirAccess.remove_absolute(UserSettings.path)
	UserSettings.reset()
	t.assert_eq(Lang.saved(), Lang.IT, "primo avvio: italiano")
	t.assert_true(Lang.choose(Lang.EN), "scelta salvata")
	UserSettings.reset()
	Lang.set_language(Lang.IT)
	t.assert_eq(Lang.saved(), Lang.EN, "riletta dal file: vale nelle sessioni successive")
	Lang.apply_saved()
	t.assert_eq(Lang.current(), Lang.EN)
	UserSettings.set_value("lingua", "xx")
	t.assert_eq(Lang.saved(), Lang.IT, "valore sconosciuto: italiano")
	_back_to_italian()
	DirAccess.remove_absolute(UserSettings.path)
	UserSettings.path = UserSettings.PATH
	UserSettings.reset()


func test_nomi_e_grammatica_delle_fazioni_in_inglese(t: TestContext) -> void:
	Lang.set_language(Lang.EN)
	t.assert_eq(FactionStyle.name_of("FN_ENGLISH"), "English")
	t.assert_eq(FactionStyle.full_name_of("FN_DANISH"), "The Auror")
	t.assert_eq(CampaignUiText.fsubj("FN_ENGLISH"), "The English")
	t.assert_eq(CampaignUiText.fart("FN_GERMAN_HRE"), "the Holy Roman Empire")
	t.assert_eq(CampaignUiText.fprep("di", "FN_ENGLISH"), "of the English")
	t.assert_eq(CampaignUiText.fprep("da", "FN_FRENCH", "by"), "by the French")
	t.assert_eq(CampaignUiText.fprep("contro", "FN_NOVGOROD"), "against the Republic of Novgorod")
	t.assert_eq(CampaignUiText.fverb("FN_ENGLISH", "declares", "declare"), "declare", "gli Inglesi: plurale")
	t.assert_eq(CampaignUiText.fverb("FN_GERMAN_HRE", "declares", "declare"), "declares", "il Sacro Romano Impero: singolare")
	t.assert_eq(CampaignUiText.building_label("CASTLE", 1), "Fort")
	t.assert_eq(CampaignUiText.building_label("SPEARMAKER", 2), "Spearmaker's Workshop")
	t.assert_eq(CampaignUiText.vnv_label(null, "fearsome", 3), "Great Leader")
	t.assert_eq(RegionNames.italian("ID_DENMARK"), "", "province: i nomi dei dati")
	t.assert_eq(RegionNames.translate_title(null, "Duke of Scotland"), "Duke of Scotland")
	_back_to_italian()
	t.assert_eq(FactionStyle.name_of("FN_ENGLISH"), "Inglesi", "di nuovo in italiano")
	t.assert_eq(CampaignUiText.fprep("di", "FN_ENGLISH"), "degli Inglesi")
	t.assert_eq(CampaignUiText.building_label("CASTLE", 1), "Fortino")
	t.assert_eq(RegionNames.italian("ID_DENMARK"), "Danimarca")


func test_ogni_frase_del_codice_ha_la_traduzione(t: TestContext) -> void:
	var table := Lang.load_tsv(TABLE)
	t.assert_true(table.size() > 100, "tabella inglese presente")
	var call := RegEx.create_from_string("Lang\\.t\\(\\s*\"((?:[^\"\\\\\\n]|\\\\.)*)\"\\s*\\)")
	var ph := RegEx.create_from_string(PLACEHOLDER)
	var missing := PackedStringArray()
	var bad := PackedStringArray()
	var seen := 0
	for path in _scripts(["res://src", "res://scenes"]):
		var lines := PackedStringArray()
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if not line.strip_edges().begins_with("#"):   # esempi nei commenti esclusi
				lines.append(line)
		var text := "\n".join(lines)
		for m in call.search_all(text):
			var key := _gd_unescape(m.get_string(1))
			seen += 1
			if not table.has(key):
				missing.append("%s: %s" % [path.get_file(), key])
			elif _placeholders(ph, key) != _placeholders(ph, str(table[key])):
				bad.append("%s: %s -> %s" % [path.get_file(), key, table[key]])
	t.assert_true(seen > 500, "frasi avvolte trovate: %d" % seen)
	t.assert_eq(missing.size(), 0, "frasi senza traduzione: %s" % ", ".join(missing.slice(0, 10)))
	t.assert_eq(bad.size(), 0, "segnaposto diversi: %s" % ", ".join(bad.slice(0, 10)))


func _placeholders(ph: RegEx, text: String) -> Array:
	var out := []
	for m in ph.search_all(text):
		out.append(m.get_string())
	out.sort()
	return out


func _scripts(roots: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array = roots.duplicate()
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for d in DirAccess.get_directories_at(dir):
			stack.append(dir.path_join(d))
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				out.append(dir.path_join(f))
	return out


func _gd_unescape(text: String) -> String:
	return text.replace("\\\\", "\u0001").replace("\\n", "\n").replace("\\t", "\t").replace("\\\"", "\"").replace("\\'", "'").replace("\u0001", "\\")
