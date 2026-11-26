extends RefCounted
## Segnalazione di Federico del 22/11/2026: agli Auror nascevano principi ma mai principesse (nel suo salvataggio del 1199
## cinque maschi di fila: il caso). `nascite_stesso_sesso_max` di auror.cfg: oltre la serie il figlio e' dell'altro sesso.


func _ready(t: TestContext) -> bool:
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata")
		return false
	return true


func _state(auror: bool) -> GameState:
	Scenario.set_auror(auror)
	var c := Scenario.load_startpos()
	var rules := Rules.load_file()
	Scenario.apply_rules(rules)
	var s := GameSetup.new_game(c, Scenario.load_units(GameFiles.prod_file(c.unit_prod_file)), Scenario.load_buildings(GameFiles.prod_file(c.building_prod_file)), rules, 5)
	Scenario.set_auror(true)
	return s


func test_serie_dello_stesso_sesso(t: TestContext) -> void:
	if not _ready(t):
		return
	var s := _state(true)
	t.assert_eq(s.rules.dynasty.same_sex_max("FN_DANISH"), 2, "auror.cfg")
	var darkos := s.leader_of("FN_DANISH")
	darkos.counters[DynastyProcessor.COUNTER_BIRTH_STREAK] = 2
	t.assert_false(DynastyProcessor._balanced_sex(s, darkos, true), "dopo due maschi una femmina")
	darkos.counters[DynastyProcessor.COUNTER_BIRTH_STREAK] = 1
	t.assert_true(DynastyProcessor._balanced_sex(s, darkos, true), "un solo maschio: resta il sorteggio")
	darkos.counters[DynastyProcessor.COUNTER_BIRTH_STREAK] = -2
	t.assert_true(DynastyProcessor._balanced_sex(s, darkos, false), "dopo due femmine un maschio")
	t.assert_eq(DynastyProcessor._next_streak(2, true), 3)
	t.assert_eq(DynastyProcessor._next_streak(2, false), -1)
	# salvataggi di prima: la serie si ricava dai figli in ordine di nascita
	darkos.counters.erase(DynastyProcessor.COUNTER_BIRTH_STREAK)
	for i in 3:
		var son := CharacterFactory.make_child(s, darkos, true, 1100 + i, darkos.region, s.rng)
		t.assert_true(son.male)
	t.assert_eq(DynastyProcessor._birth_streak(s, darkos), 3, "tre maschi di fila")
	t.assert_false(DynastyProcessor._balanced_sex(s, darkos, true))
	var other := s.leader_of("FN_ENGLISH")
	other.counters[DynastyProcessor.COUNTER_BIRTH_STREAK] = 5
	t.assert_true(DynastyProcessor._balanced_sex(s, other, true), "le altre fazioni restano al caso")


func test_storico_senza_limite(t: TestContext) -> void:
	if not _ready(t):
		return
	t.assert_eq(_state(false).rules.dynasty.same_sex_max("FN_DANISH"), 0)
