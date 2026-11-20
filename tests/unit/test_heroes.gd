extends RefCounted
## Test del lettore del file dei nomi, dei re famosi e degli eroi famosi:
## estratto di prova (righe reali ridotte, con tutte le sezioni) e file reale
## MTW_XL_EARLY_HEROES.TXT dell'installazione (saltato se manca).
## Sul file reale si controlla la struttura della XL; i valori che dipendono dalla
## parte Auror (fazione FN_DANISH: nomi, re ed eroi danesi, lista 2 dei nomi di
## battesimo, 8 principesse della lista 8) non vengono fissati.
## Numeri contati sul file del 2026-11-08.

const FIXTURE := "res://tests/fixtures/mini_heroes.txt"
const DANISH := "FN_DANISH"

var _fixture: HeroesData
var _real: HeroesData


func _mini() -> HeroesData:
	if _fixture == null:
		_fixture = HeroesLoader.load_file(FIXTURE)
	return _fixture


func _load_real(t: TestContext) -> HeroesData:
	var path := GameFiles.heroes_file(HeroesLoader.DEFAULT_FILE)
	if not GameFiles.is_available() or not FileAccess.file_exists(path):
		t.skip("file %s non trovato in %s" % [HeroesLoader.DEFAULT_FILE, GameFiles.game_dir()])
		return null
	if _real == null:
		_real = HeroesLoader.load_file(path)
	return _real


func _has_error(data: HeroesData, fragment: String) -> bool:
	for e in data.errors:
		if e.contains(fragment):
			return true
	return false


func _find_hero(data: HeroesData, faction: String, forename: String, surname: String) -> HeroesData.FamousHero:
	for h in data.heroes_of(faction):
		if h.forename == forename and h.surname == surname:
			return h
	return null


# --- percorso -----------------------------------------------------------------


func test_percorso_file_eroi(t: TestContext) -> void:
	t.assert_eq(GameFiles.heroes_file("X.TXT"), "res://data/campagna/X.TXT", "dati della campagna nel progetto (18/11/2026)")
	t.assert_eq(HeroesLoader.DEFAULT_FILE, "MTW_XL_EARLY_HEROES.TXT")


# --- lettori di base ----------------------------------------------------------


func test_campi_con_virgolette_e_virgole(t: TestContext) -> void:
	t.assert_eq(
		HeroesLoader.split_fields("\"Simon\",\t\"de Montfort, the Younger\",\t1208, 2 ,"),
		PackedStringArray(["Simon", "de Montfort, the Younger", "1208", "2", ""]))


func test_numeri_romani(t: TestContext) -> void:
	t.assert_eq(HeroesData.roman(1), "I")
	t.assert_eq(HeroesData.roman(4), "IV")
	t.assert_eq(HeroesData.roman(14), "XIV")
	t.assert_eq(HeroesData.roman(40), "XL")
	t.assert_eq(HeroesData.roman(1994), "MCMXCIV")
	t.assert_eq(HeroesData.roman(0), "0")


# --- estratto di prova ----------------------------------------------------------


func test_mini_senza_errori(t: TestContext) -> void:
	t.assert_eq(_mini().errors, PackedStringArray(), "errori di lettura")


func test_mini_liste_di_nomi(t: TestContext) -> void:
	var d := _mini()
	t.assert_eq(d.forename_lists.size(), 2, "liste dei nomi di battesimo")
	t.assert_eq(d.forenames(1).size(), 8)
	t.assert_eq(d.forenames(1)[0], "Henry")
	t.assert_eq(d.forenames(1)[4], "William")
	t.assert_eq(d.forenames(2), PackedStringArray(["Tarkhan"]), "commento dopo il nome tolto")
	t.assert_eq(d.forenames(3).size(), 0, "lista inesistente")
	t.assert_eq(d.forenames(0).size(), 0, "le liste partono da 1")
	t.assert_eq(d.surname_lists.size(), 1)
	t.assert_eq(d.surnames(1).size(), 6)
	t.assert_eq(d.surnames(1)[0], "Plantagenet")
	t.assert_eq(d.princess_lists.size(), 1, "intestazione ADD_PRINCESS con tab finale")
	t.assert_eq(d.princess_names(1), PackedStringArray(["Herleva", "Arlette", "Matilda", "Maud", "Adelaide"]))


func test_mini_associazioni_per_fazione(t: TestContext) -> void:
	var d := _mini()
	t.assert_eq(d.faction_order, PackedStringArray(["FN_ENGLISH", "FN_GOLDEN_HORDE"]))
	var en := d.faction_names("fn_english")
	t.assert_true(en != null, "FN_ENGLISH presente (anche in minuscolo)")
	if en == null:
		return
	t.assert_eq(en.forename_list, 1)
	t.assert_eq(en.royal_count, 8)
	t.assert_eq(en.surname_list, 1)
	t.assert_eq(en.princess_list, 1)
	t.assert_eq(d.forenames_of("FN_ENGLISH")[1], "Edward")
	t.assert_eq(d.surnames_of("FN_ENGLISH")[1], "Howard")
	t.assert_eq(d.princess_names_of("FN_ENGLISH")[0], "Herleva")
	t.assert_eq(d.royal_names_of("FN_ENGLISH").size(), 8)
	# 8 nomi reali dichiarati ma la lista ne ha 1: vale la lunghezza della lista.
	var gh := d.faction_names("FN_GOLDEN_HORDE")
	t.assert_eq(gh.royal_count, 8)
	t.assert_eq(d.royal_names_of("FN_GOLDEN_HORDE"), PackedStringArray(["Tarkhan"]))
	t.assert_eq(gh.surname_list, 0, "nessuna lista di cognomi")
	t.assert_eq(d.surnames_of("FN_GOLDEN_HORDE").size(), 0)
	t.assert_true(d.faction_names("FN_FRENCH") == null, "fazione senza associazioni")
	t.assert_eq(d.forenames_of("FN_FRENCH").size(), 0)


func test_mini_ribelli(t: TestContext) -> void:
	var d := _mini()
	t.assert_eq(d.rebel_regions(), PackedStringArray(["ID_SCOTLAND", "ID_MERCIA"]))
	var s := d.rebel_names("id_scotland")
	t.assert_eq(s.forename_list, 14)
	t.assert_eq(s.surname_list, 13)
	t.assert_eq(d.rebel_names("ID_MERCIA").forename_list, 1)
	t.assert_true(d.rebel_names("ID_WALES") == null)


func test_mini_re_famosi(t: TestContext) -> void:
	var d := _mini()
	t.assert_eq(d.kings.size(), 4)
	t.assert_eq(d.king_factions(), PackedStringArray(["FN_ENGLISH"]))
	t.assert_eq(d.declared_kings, {"FN_ENGLISH": 4})
	var k := d.kings_of("FN_ENGLISH")[0]
	t.assert_eq(k.name_index, 4)
	t.assert_eq(k.number, 2)
	t.assert_eq(k.command, 3)
	t.assert_eq(k.dread, 7)
	t.assert_eq(k.piety, 3)
	t.assert_eq(k.acumen, 4)
	t.assert_eq(k.portrait, -1)
	t.assert_eq(k.vnv, "tyrant2")
	t.assert_eq(k.raw.size(), 8, "campi grezzi")
	t.assert_eq(d.king_forename(k), "William")
	t.assert_eq(d.king_label(k), "William II")
	t.assert_eq(d.king_label(d.kings[1]), "Henry I")
	t.assert_eq(d.king_label(d.kings[2]), "Stephen I")
	t.assert_eq(d.king_label(d.kings[3]), "Henry II")
	t.assert_eq(d.kings_of("FN_FRENCH").size(), 0)


func test_mini_eroi_famosi(t: TestContext) -> void:
	var d := _mini()
	t.assert_eq(d.heroes.size(), 5)
	t.assert_eq(d.hero_factions(), PackedStringArray(["FN_REBEL", "FN_ENGLISH"]))
	t.assert_eq(d.heroes_of(HeroesData.REBEL_FACTION).size(), 2)
	t.assert_eq(d.heroes_of("FN_ENGLISH").size(), 3)
	var cid := _find_hero(d, "FN_REBEL", "El", "Cid")
	t.assert_true(cid != null, "El Cid")
	if cid == null:
		return
	t.assert_eq(cid.full_name(), "El Cid")
	t.assert_eq(cid.year, 1054)
	t.assert_eq([cid.command, cid.dread, cid.piety, cid.acumen, cid.loyalty], [4, 5, 4, 3, 3])
	t.assert_eq(cid.vnv, "attacker2")
	t.assert_eq(cid.type_name, "GENERAL")
	t.assert_eq(cid.region, "ID_VALENCIA")
	t.assert_false(cid.is_anywhere())
	t.assert_eq(cid.portrait, 1, "ritratto con spazio davanti")
	t.assert_eq(cid.raw.size(), 12)
	# Commento con virgolette dopo // e commento con virgola.
	var dolcino := _find_hero(d, "FN_REBEL", "Fra", "Dolcino")
	t.assert_eq(dolcino.year, 1200)
	t.assert_eq(dolcino.region, "ID_MILAN")
	t.assert_eq(dolcino.vnv, "zealot4")
	var odon := _find_hero(d, "FN_ENGLISH", "Odon", "de Bayeux")
	t.assert_eq(odon.type_name, "BISHOP")
	t.assert_true(odon.is_anywhere(), "ID_LIMBO = ovunque")
	t.assert_eq([odon.year, odon.command, odon.dread, odon.piety, odon.acumen, odon.loyalty], [1036, 2, 3, 3, 4, 5])
	t.assert_eq(odon.vnv, "no_v")
	var strongbow := _find_hero(d, "FN_ENGLISH", "Strongbow", "FitzGilbert")
	t.assert_eq(strongbow.year, 1115)
	t.assert_eq(strongbow.vnv, "moneygrabber2")
	var beckett := _find_hero(d, "FN_ENGLISH", "Thomas", "Beckett")
	t.assert_eq(beckett.piety, 6)
	t.assert_eq(d.heroes_of_type("bishop").size(), 2)
	t.assert_eq(d.heroes_of_type("GENERAL").size(), 3)
	t.assert_eq(d.heroes_of_type("SPY").size(), 0)


# --- formati e errori ---------------------------------------------------------


func test_fine_riga_crlf(t: TestContext) -> void:
	var text := TextIO.read_latin1(FIXTURE).replace("\n", "\r\n")
	var d := HeroesLoader.load_text(text)
	t.assert_eq(d.errors, PackedStringArray())
	t.assert_eq(d.kings.size(), 4)
	t.assert_eq(d.heroes.size(), 5)
	t.assert_eq(d.forenames(1)[7], "Stephen")
	t.assert_eq(d.heroes[0].vnv, "attacker2", "nessun \\r in fondo ai campi")


func test_codifica_cp1252(t: TestContext) -> void:
	var bytes := "ADD_FORENAMES::\r\n\"Andr".to_ascii_buffer()
	bytes.append(0xE9)
	bytes.append_array("\"\r\n\"Zo".to_ascii_buffer())
	bytes.append(0xEB)
	bytes.append_array("\"\r\n".to_ascii_buffer())
	var d := HeroesLoader.load_text(TextIO.decode_latin1(bytes))
	t.assert_eq(d.errors, PackedStringArray())
	t.assert_eq(d.forenames(1), PackedStringArray(["Andr" + String.chr(0xE9), "Zo" + String.chr(0xEB)]))


func test_errori_segnalati(t: TestContext) -> void:
	var lines := PackedStringArray([
		"FAMOUS_KINGS::\tFN_X\t3",
		"1,\t\t1,\t3,\t3,\t5,\t5,\t-1,\t\t\teducated1",
		"1,\t\t1,\t3",
		"x,\t\t1,\t3,\t3,\t5,\t5,\t-1,\t\t\teducated1",
		"FAMOUS_HEROES::",
		"SET_FORENAMES::\tFN_X",
		"FOO::",
		"\"Mario\"",
		"ADD_FORENAMES::",
		"Luigi",
	])
	var d := HeroesLoader.load_text("\n".join(lines))
	t.assert_true(_has_error(d, "FN_X: 3 re dichiarati, 2 letti"), "conteggio dichiarato: %s" % str(d.errors))
	t.assert_true(_has_error(d, "re con 3 campi invece di 8"), "re corto")
	t.assert_true(_has_error(d, "non è un intero: 'x'"), "intero non valido")
	t.assert_true(_has_error(d, "FAMOUS_HEROES:: ha 0 argomenti invece di 2"), "intestazione senza argomenti")
	t.assert_true(_has_error(d, "SET_FORENAMES:: ha 1 argomenti invece di 3"), "SET_FORENAMES incompleto")
	t.assert_true(_has_error(d, "sezione sconosciuta FOO::"), "sezione sconosciuta")
	t.assert_true(_has_error(d, "dato fuori da una sezione di dati: \"Mario\""), "riga fuori sezione")
	t.assert_true(_has_error(d, "nome senza virgolette: Luigi"), "nome senza virgolette")
	t.assert_eq(d.kings.size(), 2, "il re corto si scarta, quello con intero non valido resta")
	t.assert_eq(d.kings[1].name_index, 0)
	t.assert_eq(d.forenames(1), PackedStringArray(["Luigi"]), "il nome senza virgolette si tiene")


func test_testo_vuoto(t: TestContext) -> void:
	var d := HeroesLoader.load_text("// solo un commento\r\n\r\n")
	t.assert_eq(d.errors, PackedStringArray())
	t.assert_eq(d.kings.size(), 0)
	t.assert_eq(d.heroes.size(), 0)
	t.assert_eq(d.forename_lists.size(), 0)


# --- file reale ---------------------------------------------------------------


func test_reale_senza_errori(t: TestContext) -> void:
	var d := _load_real(t)
	if d == null:
		return
	t.assert_eq(d.errors, PackedStringArray(), "errori di lettura")


func test_reale_associazioni(t: TestContext) -> void:
	var d := _load_real(t)
	if d == null:
		return
	var with_forenames := 0
	var with_surnames := 0
	var with_princess := 0
	for f in d.faction_order:
		var n := d.faction_names(f)
		if n.forename_list > 0:
			with_forenames += 1
			t.assert_true(n.forename_list <= d.forename_lists.size(), "%s: lista dei nomi inesistente" % f)
		if n.surname_list > 0:
			with_surnames += 1
			t.assert_true(n.surname_list <= d.surname_lists.size(), "%s: lista dei cognomi inesistente" % f)
		if n.princess_list > 0:
			with_princess += 1
			t.assert_true(n.princess_list <= d.princess_lists.size(), "%s: lista delle principesse inesistente" % f)
	t.assert_eq(with_forenames, 30, "fazioni con nomi di battesimo")
	t.assert_eq(with_surnames, 29, "fazioni con cognomi")
	t.assert_eq(with_princess, 27, "fazioni con principesse")
	t.assert_eq(d.faction_order.size(), 30, "fazioni con almeno un'associazione")
	t.assert_eq(d.rebel_regions().size(), 107, "regioni con nomi dei ribelli")
	var scotland := d.rebel_names("ID_SCOTLAND")
	t.assert_eq([scotland.forename_list, scotland.surname_list], [14, 13])
	for r in d.rebel_regions():
		var rn := d.rebel_names(r)
		t.assert_true(rn.forename_list >= 1 and rn.forename_list <= d.forename_lists.size(), "%s: lista dei nomi" % r)
		t.assert_true(rn.surname_list >= 1 and rn.surname_list <= d.surname_lists.size(), "%s: lista dei cognomi" % r)
	t.assert_eq(d.royal_names_of("FN_ENGLISH").size(), 8)
	t.assert_eq(d.forenames_of("FN_ENGLISH")[0], "Henry")


func test_reale_liste_di_nomi(t: TestContext) -> void:
	var d := _load_real(t)
	if d == null:
		return
	t.assert_true(d.forename_lists.size() >= 33, "liste dei nomi di battesimo: %d" % d.forename_lists.size())
	t.assert_true(d.surname_lists.size() >= 24, "liste dei cognomi: %d" % d.surname_lists.size())
	t.assert_true(d.princess_lists.size() >= 17, "liste delle principesse: %d" % d.princess_lists.size())
	# Le liste 2 dei nomi e dei cognomi e la lista 8 delle principesse sono danesi (Auror): escluse.
	for n in [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]:
		t.assert_eq(d.forenames(n).size(), 48, "nomi di battesimo, lista %d" % n)
	for n in [1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]:
		t.assert_eq(d.surnames(n).size(), 48, "cognomi, lista %d" % n)
	for n in [1, 2, 3, 4, 5, 6, 7, 9, 10, 11]:
		t.assert_eq(d.princess_names(n).size(), 16, "principesse, lista %d" % n)
	var with_48 := 0
	for names in d.forename_lists:
		if names.size() == 48:
			with_48 += 1
	t.assert_true(with_48 >= 18, "liste di nomi di battesimo da 48 voci: %d" % with_48)
	t.assert_eq(d.forenames(18), PackedStringArray(["Tarkhan"]), "lista khazara con un solo nome")
	t.assert_eq(d.forenames(1)[4], "William")
	t.assert_eq(d.surnames(1)[0], "Plantagenet")
	t.assert_eq(d.princess_names(1)[0], "Herleva")


func test_reale_re_famosi(t: TestContext) -> void:
	var d := _load_real(t)
	if d == null:
		return
	t.assert_eq(d.king_factions().size(), 30, "fazioni con re famosi")
	t.assert_true(d.kings_of(DANISH).size() >= 1, "re famosi danesi (Auror) presenti")
	var others := 0
	for k in d.kings:
		if k.faction == DANISH:
			continue
		others += 1
		t.assert_true(k.name_index >= 0 and k.name_index < d.forenames_of(k.faction).size(),
				"%s riga %d: indice del nome fuori dalla lista" % [k.faction, k.line])
		t.assert_true(k.number >= 1, "%s riga %d: numerale" % [k.faction, k.line])
		t.assert_true(k.command >= 0 and k.command <= 9 and k.dread >= 0 and k.dread <= 9
				and k.piety >= 0 and k.piety <= 9 and k.acumen >= 0 and k.acumen <= 9,
				"%s riga %d: attributi fuori da 0-9" % [k.faction, k.line])
		t.assert_false(k.vnv.is_empty(), "%s riga %d: vizio/virtù mancante" % [k.faction, k.line])
	t.assert_eq(others, 164, "re famosi non danesi (172 nel file con 8 danesi)")
	t.assert_true(d.kings.size() >= 164, "re famosi in tutto: %d" % d.kings.size())
	t.assert_eq(d.kings_of("FN_ENGLISH").size(), 12)
	t.assert_eq(d.kings_of("FN_ALMOHAD").size(), 9)


func test_reale_re_inglese_noto(t: TestContext) -> void:
	var d := _load_real(t)
	if d == null:
		return
	var kings := d.kings_of("FN_ENGLISH")
	if kings.is_empty():
		t.assert_true(false, "nessun re inglese")
		return
	# Primo re inglese famoso: William II.
	var k := kings[0]
	t.assert_eq(k.name_index, 4)
	t.assert_eq(k.number, 2)
	t.assert_eq([k.command, k.dread, k.piety, k.acumen], [3, 7, 3, 4])
	t.assert_eq(k.portrait, -1)
	t.assert_eq(k.vnv, "tyrant2")
	t.assert_eq(d.king_label(k), "William II")
	t.assert_eq(d.king_label(kings[1]), "Henry I")
	t.assert_eq(d.king_label(kings[9]), "Edward III")
	t.assert_eq(d.king_label(kings[11]), "Henry V")
	t.assert_eq(kings[4].vnv, "mightywarrior3")


func test_reale_eroi_famosi(t: TestContext) -> void:
	var d := _load_real(t)
	if d == null:
		return
	t.assert_eq(d.hero_factions().size(), 24, "fazioni con eroi famosi")
	t.assert_true(d.heroes_of(DANISH).size() >= 1, "eroi danesi (Auror) presenti")
	var types := {}
	var others := 0
	for h in d.heroes:
		if h.faction == DANISH:
			continue
		others += 1
		types[h.type_name] = int(types.get(h.type_name, 0)) + 1
		t.assert_true(h.year >= 1000 and h.year <= 1500, "%s riga %d: anno %d" % [h.faction, h.line, h.year])
		t.assert_true(h.region.begins_with("ID_"), "%s riga %d: regione %s" % [h.faction, h.line, h.region])
		t.assert_false(h.vnv.is_empty(), "%s riga %d: vizio/virtù mancante" % [h.faction, h.line])
		t.assert_false(h.forename.is_empty(), "%s riga %d: nome mancante" % [h.faction, h.line])
	t.assert_eq(others, 195, "eroi famosi non danesi (218 nel file con 23 danesi)")
	t.assert_true(d.heroes.size() >= 195, "eroi famosi in tutto: %d" % d.heroes.size())
	t.assert_eq(types, {"GENERAL": 138, "EMISSARY": 21, "BISHOP": 18, "INQUISITOR": 15, "CARDINAL": 2, "ASSASSIN": 1})
	t.assert_eq(d.heroes_of(HeroesData.REBEL_FACTION).size(), 18, "eroi dei ribelli")
	t.assert_eq(d.heroes_of("FN_ENGLISH").size(), 20)
	t.assert_eq(d.heroes_of("FN_SWEDISH").size(), 7)


func test_reale_eroe_noto(t: TestContext) -> void:
	var d := _load_real(t)
	if d == null:
		return
	var cid := _find_hero(d, "FN_REBEL", "El", "Cid")
	t.assert_true(cid != null, "El Cid tra gli eroi dei ribelli")
	if cid == null:
		return
	t.assert_eq(cid.year, 1054)
	t.assert_eq([cid.command, cid.dread, cid.piety, cid.acumen, cid.loyalty], [4, 5, 4, 3, 3])
	t.assert_eq(cid.vnv, "attacker2")
	t.assert_eq(cid.type_name, "GENERAL")
	t.assert_eq(cid.region, "ID_VALENCIA")
	t.assert_eq(cid.portrait, 1)
	var odon := _find_hero(d, "FN_ENGLISH", "Odon", "de Bayeux")
	t.assert_true(odon != null and odon.type_name == "BISHOP" and odon.is_anywhere(), "Odon, vescovo ovunque")
