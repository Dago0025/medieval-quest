extends RefCounted
## Test delle regole dei personaggi da file (personaggi.cfg, vizi_virtu.cfg) e dei vizi e virtu'
## del primo gruppo (VnvRules). I valori delle soglie e degli effetti sono quelli di vizi_virtu.cfg
## (PROVVISORIA: soglie e scale ricavate dai testi del gioco, non dall'eseguibile).


func test_regole_dei_personaggi_predefinite_uguali_al_file(t: TestContext) -> void:
	var from_file := DynastyRules.load_file()
	t.assert_eq(from_file.errors, PackedStringArray(), "errori di lettura di personaggi.cfg e auror.cfg")
	t.assert_eq(from_file.to_dict(), DynastyRules.new().to_dict(), "il file e i valori predefiniti devono coincidere")
	var rules := Rules.load_file()
	t.assert_eq(rules.errors, PackedStringArray())
	t.assert_eq(rules.dynasty.to_dict(), DynastyRules.new().to_dict())
	t.assert_eq(rules.to_dict(), Rules.new().to_dict(), "Rules.to_dict comprende personaggi e vizi")


func test_regole_dei_vizi_predefinite_uguali_al_file(t: TestContext) -> void:
	var from_file := VnvRules.load_file()
	t.assert_eq(from_file.errors, PackedStringArray(), "errori di lettura di vizi_virtu.cfg")
	t.assert_eq(from_file.to_dict(), VnvRules.new().to_dict(), "il file e i valori predefiniti devono coincidere")
	t.assert_eq(Rules.new().to_dict()["vnv"], VnvRules.new().to_dict())


func test_valori_della_specifica(t: TestContext) -> void:
	var d := DynastyRules.new()
	t.assert_eq(d.max_attribute, 10)
	t.assert_eq(d.old_age, 40)
	t.assert_eq(d.old_age_spread, 4)
	t.assert_eq(d.royal_old_age_bonus, 10)
	t.assert_eq(d.death_divisor, 50.0)
	t.assert_eq(d.death_k, 0.0)
	t.assert_eq(d.prince_age, 16)
	t.assert_eq(d.princess_age, 15)
	t.assert_eq(d.princess_retire_age, 32)
	t.assert_eq(d.governor_acumen, 0.10)
	t.assert_eq(d.king_acumen, 0.02)
	t.assert_eq(d.fixed_value("FN_DANISH", "command"), 9)
	t.assert_eq(d.fixed_value("FN_DANISH", "loyalty"), 9)
	t.assert_eq(d.fixed_value("FN_DANISH", "influence"), 9)
	t.assert_eq(d.fixed_value("fn_danish", "command"), 9, "id senza distinzione di maiuscole")
	t.assert_eq(d.fixed_value("FN_ENGLISH", "command"), -1)
	t.assert_true(d.is_king_immortal("FN_DANISH"))
	t.assert_false(d.is_king_immortal("FN_ENGLISH"))
	t.assert_eq(d.leader_name("FN_DANISH"), "Darkos", "nome riservato al capo (16/11/2026)")
	t.assert_eq(d.leader_name("FN_ENGLISH"), "")
	t.assert_eq(d.leader_title("FN_DANISH"), "Imperatore Dio")


func test_i_parametri_del_file_si_leggono(t: TestContext) -> void:
	var path := "user://regole_personaggi_prova.cfg"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[invecchiamento]\neta_vecchiaia=30\nk_morte=2.5\n[nascite]\np_nascita=0.9\n[economia]\nacume_re=0.5\n")
	f.close()
	var r := DynastyRules.load_file(path, "")
	DirAccess.remove_absolute(path)
	t.assert_eq(r.errors, PackedStringArray())
	t.assert_eq(r.old_age, 30)
	t.assert_eq(r.death_k, 2.5)
	t.assert_eq(r.birth_chance, 0.9)
	t.assert_eq(r.king_acumen, 0.5)
	t.assert_eq(r.prince_age, 16, "chiavi mancanti: valore predefinito")
	t.assert_eq(r.death_chance(40, 30), (10.0 + 2.5) / 50.0)


func test_file_mancante_usa_i_valori_predefiniti(t: TestContext) -> void:
	var r := DynastyRules.load_file("user://non_esiste.cfg")
	t.assert_eq(r.errors.size(), 1)
	t.assert_eq(r.old_age, 40)
	var v := VnvRules.load_file("user://non_esiste.cfg")
	t.assert_eq(v.errors.size(), 1)
	t.assert_eq(v.order, VnvRules.new().order)


func test_catene_del_primo_gruppo(t: TestContext) -> void:
	var v := VnvRules.new()
	t.assert_eq(v.order, PackedStringArray(["fearsome", "tyrant", "vaccilator", "killer", "butcher"]))
	for chain in v.order:
		t.assert_true(v.has_chain(chain))
		t.assert_true(v.level_count(chain) >= 1)
		t.assert_true(v.chain_name(chain) != chain, "nome leggibile per %s" % chain)
	t.assert_eq(v.counter_of("fearsome"), "vittorie")
	t.assert_eq(v.counter_of("tyrant"), "anni_tassa_alta")
	t.assert_eq(v.counter_of("vaccilator"), "ritirate")
	t.assert_eq(v.counter_of("killer"), "uccisioni")
	t.assert_eq(v.counter_of("butcher"), "prigionieri")
	t.assert_true(v.leader_only("tyrant"))
	t.assert_false(v.leader_only("fearsome"))
	t.assert_false(v.has_chain("pride"))
	t.assert_eq(v.counter_of("pride"), "")
	t.assert_eq(v.level_count("pride"), 0)


func test_soglie_e_livelli(t: TestContext) -> void:
	var v := VnvRules.new()
	t.assert_eq(v.threshold("fearsome", 1), 3)
	t.assert_eq(v.threshold("fearsome", 4), 20)
	t.assert_eq(v.threshold("fearsome", 5), -1)
	t.assert_eq(v.threshold("fearsome", 0), -1)
	t.assert_eq(v.threshold("killer", 1), 400, "soglia 40 x scala 10")
	t.assert_eq(v.level_for_count("fearsome", 0), 0)
	t.assert_eq(v.level_for_count("fearsome", 2), 0)
	t.assert_eq(v.level_for_count("fearsome", 3), 1)
	t.assert_eq(v.level_for_count("fearsome", 11), 2)
	t.assert_eq(v.level_for_count("fearsome", 1000), 4)
	t.assert_eq(v.level_for_count("pride", 1000), 0)


func test_effetti_sugli_attributi(t: TestContext) -> void:
	var v := VnvRules.new()
	t.assert_eq(v.delta("fearsome", 1, Character.ATTR_COMMAND), 1)
	t.assert_eq(v.delta("fearsome", 4, Character.ATTR_COMMAND), 3)
	t.assert_eq(v.delta("fearsome", 9, Character.ATTR_COMMAND), 3, "oltre l'ultimo livello vale l'ultimo")
	t.assert_eq(v.delta("fearsome", 2, Character.ATTR_LOYALTY), 2)
	t.assert_eq(v.delta("fearsome", 2, Character.ATTR_DREAD), 0, "attributo senza effetto")
	t.assert_eq(v.delta("tyrant", 3, Character.ATTR_DREAD), 3)
	t.assert_eq(v.delta("vaccilator", 2, Character.ATTR_COMMAND), -1)
	t.assert_eq(v.delta("vaccilator", 3, Character.ATTR_LOYALTY), -3)
	t.assert_eq(v.delta("butcher", 1, Character.ATTR_DREAD), 2)
	t.assert_eq(v.delta("fearsome", 0, Character.ATTR_COMMAND), 0)
	t.assert_eq(v.delta("pride", 1, Character.ATTR_COMMAND), 0)


func test_id_dei_vizi_del_gioco(t: TestContext) -> void:
	var p := VnvRules.parse_id("tyrant2")
	t.assert_eq(p["catena"], "tyrant")
	t.assert_eq(p["livello"], 2)
	t.assert_false(p["segreto"])
	var s := VnvRules.parse_id("secret_lust1")
	t.assert_eq(s["catena"], "lust")
	t.assert_true(s["segreto"])
	var plain := VnvRules.parse_id("Pride")
	t.assert_eq(plain["catena"], "pride")
	t.assert_eq(plain["livello"], 1)
	t.assert_eq(VnvRules.parse_id("")["catena"], "")
	t.assert_eq(VnvRules.parse_id("no_v")["catena"], "no_v")


func test_aggiungere_un_vizio_solo_se_migliora(t: TestContext) -> void:
	var c := Character.new(1)
	t.assert_true(CharacterFactory.add_vnv(c, "tyrant2"))
	t.assert_eq(c.vnv, {"tyrant": 2})
	t.assert_false(CharacterFactory.add_vnv(c, "tyrant1"), "livello piu' basso: nulla")
	t.assert_false(CharacterFactory.add_vnv(c, "tyrant2"))
	t.assert_true(CharacterFactory.add_vnv(c, "tyrant4"))
	t.assert_eq(c.vnv, {"tyrant": 4})
	t.assert_false(CharacterFactory.add_vnv(c, ""))
