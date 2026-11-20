extends RefCounted
## Test del lettore dei testi localizzati: estratto di prova con le stranezze dei
## file reali (etichetta e testo sulla stessa riga, testi su più righe, array a
## indice, etichette chiuse male, etichette ripetute) e file reali di Loc/Italian.
## Numeri contati sui file del 2026-11-07; dove il file contiene anche parti
## aggiunte dalla mod Auror il controllo è con ">=".

const FIXTURE := "res://tests/fixtures/mini_loc.txt"

var _fixture: LocLoader.LocTable
var _real := {}


func _mini() -> LocLoader.LocTable:
	if _fixture == null:
		_fixture = LocLoader.load_file(FIXTURE)
	return _fixture


func _load_real(t: TestContext, file_name: String) -> LocLoader.LocTable:
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.loc_file(file_name)):
		t.skip("file %s non trovato in %s" % [file_name, GameFiles.game_dir()])
		return null
	if not _real.has(file_name):
		_real[file_name] = LocLoader.load_file(GameFiles.loc_file(file_name))
	return _real[file_name]


# --- estratto di prova ------------------------------------------------------


func test_estratto_voci_semplici(t: TestContext) -> void:
	var table := _mini()
	t.assert_eq(table.errors, PackedStringArray(), "errori")
	t.assert_eq(table.entries.size(), 13)
	t.assert_eq(table.text("Army"), "Armata", "etichetta e testo sulla stessa riga, con tab")
	t.assert_eq(table.text("Continue"), "Continua", "commento dopo il testo")
	t.assert_eq(table.text("GlobalTextData"), "Testo per l'intero gioco.")
	t.assert_eq(table.text("url"), "http://esempio // non e' un commento", "// dentro il testo")
	t.assert_eq(table.text("dopo_array"), "voce semplice dopo un array")
	t.assert_eq(table.text("manca", "?"), "?")
	t.assert_true(table.has_text("Army"))
	t.assert_false(table.has_text("army"))
	t.assert_eq(table.entries.keys()[0], "GlobalTextData", "ordine del file")


func test_estratto_testi_particolari(t: TestContext) -> void:
	var table := _mini()
	t.assert_eq(table.text("sieger2desc"), "\"He is an expert in the art of sieging. -2 years to siege duration. ", "virgolette in testa")
	t.assert_eq(table.text("legswordmes_xzy"), "One of your warriors has achieved the status of\n Legendary Swordsman.\nYou may now found a school.", "testo su due righe e \\n")
	var raw := LocLoader.load_text(FileAccess.get_file_as_string(FIXTURE), false)
	t.assert_true(raw.text("legswordmes_xzy").contains("Swordsman.\\nYou"), "senza unescape resta il \\n scritto nel file")


func test_estratto_array_a_indice(t: TestContext) -> void:
	var table := _mini()
	t.assert_eq(table.arrays.size(), 2)
	t.assert_true(table.has_array("country_xzy"))
	t.assert_eq(table.array("country_xzy"), PackedStringArray(["Region Zero", "Scotland", "Northumbria", "Mercia"]), "vince l'ultima definizione")
	t.assert_eq(table.array_item("country_xzy", 1), "Scotland")
	t.assert_eq(table.array_item("country_xzy", 9, "?"), "?")
	t.assert_eq(table.array_item("country_xzy", -1, "?"), "?")
	t.assert_eq(table.array("vuoto_xzy").size(), 0)
	t.assert_true(table.has_array("vuoto_xzy"))
	t.assert_eq(table.array("non_esiste").size(), 0)
	t.assert_false(table.entries.has("country_xzy"), "gli array non finiscono tra le voci")


func test_estratto_tolleranze_e_ripetizioni(t: TestContext) -> void:
	var table := _mini()
	t.assert_eq(table.text("Barbary Coast"), "Barbary Coast", "etichetta chiusa con }")
	t.assert_eq(table.text("Kilij Arslan"), "Kilij Arslan", "testo senza virgolette finali")
	t.assert_false(table.has_text("Kaikawus"), "voce commentata")
	t.assert_eq(table.text("Cydwladwr"), "Cydwladwr\" (Compatriot)")
	t.assert_eq(table.text("Maria"), "Maria", "vince l'ultima")
	t.assert_eq(table.duplicates, 3, "Maria, Pierre e l'array country_xzy")
	t.assert_eq(table.conflicts, PackedStringArray(["Maria"]), "solo Maria cambia testo")
	t.assert_eq(table.warnings.size(), 4, "} al posto di ], due testi senza chiusura, array ridefinito")
	t.assert_eq(table.ignored_words, {"SetShowTransOn": 1, "SetShowTransOff": 1})


func test_estratto_ricerca_senza_maiuscole(t: TestContext) -> void:
	var table := _mini()
	t.assert_eq(table.find_text("Spearmen_desc"), "Lanceri")
	t.assert_eq(table.find_text("ARMY"), "Armata")
	t.assert_eq(table.find_text("Army"), "Armata")
	t.assert_eq(table.find_text("nulla", "?"), "?")


func test_testo_malformato_e_segnalato(t: TestContext) -> void:
	var table := LocLoader.load_text("[\"a\"] {\"uno\"}\n{\"orfano\"}\n@{\"orfano2\"}\nparola\n[\"b\"] {\"due")
	t.assert_eq(table.text("a"), "uno")
	t.assert_eq(table.entries.size(), 1)
	t.assert_eq(table.errors.size(), 4, "testo senza etichetta, elemento senza array, parola, testo non chiuso")


func test_latin1_e_crlf(t: TestContext) -> void:
	var bytes := "[\"Yes\"]\r\n{\"S".to_ascii_buffer()
	bytes.append(0xEC)
	bytes.append_array("\"}\r\n@[\"x\"]\r\n@{\"a\"}\r\n@{\"b\"}\r\n".to_ascii_buffer())
	var table := LocLoader.load_text(TextIO.decode_latin1(bytes))
	t.assert_eq(table.text("Yes"), "Sì")
	t.assert_eq(table.array("x"), PackedStringArray(["a", "b"]))
	t.assert_eq(table.errors, PackedStringArray())


# --- file reali -------------------------------------------------------------


func test_reale_global(t: TestContext) -> void:
	var table := _load_real(t, "global.txt")
	if table == null:
		return
	t.assert_eq(table.errors, PackedStringArray(), "errori")
	t.assert_eq(table.entries.size(), 93)
	t.assert_eq(table.arrays.size(), 0)
	t.assert_eq(table.text("Army"), "Armata")
	t.assert_eq(table.text("Yes"), "Sì", "cp1252 decodificato")
	t.assert_eq(table.text("OK"), "OK")


func test_reale_eventi(t: TestContext) -> void:
	var table := _load_real(t, "Events.txt")
	if table == null:
		return
	t.assert_eq(table.errors, PackedStringArray(), "errori")
	t.assert_eq(table.warnings.size(), 0)
	t.assert_eq(table.entries.size(), 1676, "voci semplici")
	t.assert_eq(table.arrays.size(), 54, "array")
	var items := 0
	for label in table.arrays:
		items += table.array(label).size()
	t.assert_eq(items, 610, "elementi degli array")
	t.assert_eq(table.entries.size() + table.arrays.size(), 1730, "etichette totali (dizionario dati)")
	# testi italiani (italiano_apply.py del 2026-11-09 sui Loc/Italian dell'installazione)
	t.assert_eq(table.text("legswordmes_xzy"), "Uno dei tuoi guerrieri ha ottenuto la fama di spadaccino leggendario.\nOra puoi fondare una scuola di scherma.")


func test_reale_glory_goals_e_variabili(t: TestContext) -> void:
	var goals := _load_real(t, "glorygoals.txt")
	if goals == null:
		return
	t.assert_eq(goals.errors, PackedStringArray())
	t.assert_eq(goals.entries.size(), 236)
	var vars := _load_real(t, "variables.txt")
	t.assert_eq(vars.errors, PackedStringArray())
	t.assert_true(vars.entries.size() >= 47)
	t.assert_eq(vars.arrays.size(), 7)
	t.assert_true(vars.has_array("factions_special_xzy"))


func test_reale_descrizioni(t: TestContext) -> void:
	var table := _load_real(t, "Descriptions.txt")
	if table == null:
		return
	t.assert_eq(table.errors, PackedStringArray())
	t.assert_true(table.entries.size() >= 834, "descrizioni di unita' ed edifici")
	t.assert_true(table.text("Spearmen_desc").begins_with("I lancieri sono utili in quasi ogni esercito"))
	t.assert_eq(table.text("Fort_Completed"), "Forte completato.")


func test_reale_array_di_regioni(t: TestContext) -> void:
	var table := _load_real(t, "MTW_XL_EARLY_REGION_SPECIFIC.TXT")
	if table == null:
		return
	t.assert_eq(table.errors, PackedStringArray())
	t.assert_eq(table.arrays.size(), 12)
	# 1 "Regione Zero" + 107 regioni di terra + 36 di mare, nell'ordine di dichiarazione dello startpos.
	t.assert_eq(table.array("country_xzy").size(), 144)
	t.assert_eq(table.array_item("country_xzy", 0), "Regione Zero")
	t.assert_eq(table.array_item("country_xzy", 1), "Scozia")
	t.assert_eq(table.array_item("country_xzy", 143), "Costa atlantica")
	t.assert_eq(table.array("province_of_xzy").size(), 144)
	t.assert_eq(table.array("of_Clan_Districts").size(), 31)
	t.assert_eq(table.array("goods_names").size(), 24)
	t.assert_eq(table.array("castle_size_txt_xzy").size(), 15)
	t.assert_eq(table.array_item("castle_size_txt_xzy", 0), "240 fanti o 120 cavalieri")
	t.assert_eq(table.text("Barbary Coast"), "Costa Berbera", "etichetta chiusa male nel file")
	t.assert_eq(table.warnings.size(), 1)


func test_reale_array_di_fazioni(t: TestContext) -> void:
	var table := _load_real(t, "MTW_XL_EARLY_FACTION_SPECIFIC.TXT")
	if table == null:
		return
	t.assert_eq(table.errors, PackedStringArray())
	t.assert_eq(table.arrays.size(), 10)
	t.assert_eq(table.entries.size(), 13, "messaggi di vittoria e sconfitta")
	# 31 fazioni dichiarate (ribelli compresi), nello stesso ordine di DeclareFaction.
	for label in ["faction_leaders_xzy", "king_titles", "factions_xzy", "factions_posessive_xzy", "of_Clan_Names"]:
		t.assert_eq(table.array(label).size(), 31, label)
	t.assert_eq(table.array("rebel_factions_xzy").size(), 93)
	t.assert_eq(table.array_item("factions_xzy", 0), "I ribelli")
	t.assert_eq(table.array_item("factions_xzy", 1), "Gli Almoravidi")
	t.assert_true(table.text("Victory_60").contains("\n"), "testo su più righe con \\n convertiti")
	t.assert_false(table.text("Victory_60").contains("\\n"), "nessun \\n letterale rimasto")


func test_reale_nomi_e_startpos(t: TestContext) -> void:
	var names := _load_real(t, "names.txt")
	if names == null:
		return
	t.assert_eq(names.errors, PackedStringArray())
	t.assert_true(names.entries.size() >= 4903)
	t.assert_eq(names.arrays.size(), 13)
	t.assert_true(names.duplicates >= 214, "nomi ripetuti tra le liste")
	# nei nomi italiani fusi da italiano_apply.py le definizioni ripetute hanno lo stesso testo: nessun conflitto
	t.assert_eq(names.text("Maria"), "Maria")
	t.assert_eq(names.text("Kilij Arslan"), "Kilij Arslan", "testo senza virgolette finali")
	var sp := _load_real(t, "startpos.txt")
	t.assert_eq(sp.errors, PackedStringArray())
	t.assert_true(sp.arrays.size() >= 87)
	t.assert_true(sp.has_array("FSM_faction_info_faction_RUSSIAN_EARLY"))
	t.assert_eq(sp.array("FSM_faction_info_faction_RUSSIAN_EARLY").size(), 3, "definita due volte: vale l'ultima")
