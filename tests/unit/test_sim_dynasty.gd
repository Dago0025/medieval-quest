extends RefCounted
## Test delle regole annuali dei personaggi (DynastyProcessor) sul mondo di prova
## tests/fixtures/dynasty_*.txt (vedi test_sim_characters.gd). Le situazioni si preparano a mano
## (eta' e soglie scelte in modo che l'esito sia certo) e si controllano gli eventi dell'anno.
## Il fine anno porta dall'anno Y a Y + 1; le eta' si contano all'anno nuovo.

const STARTPOS := "res://tests/fixtures/dynasty_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const HEROES := "res://tests/fixtures/dynasty_heroes.txt"
const PLAIN_STARTPOS := "res://tests/fixtures/sim_startpos.txt"


func _world(seed_value: int = 7) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	# Dalla fase 4b le province hanno lealta' e rivolte; qui si provano le dinastie, quindi niente sorteggi
	# di rivolta, propagazione, riemersione e guerra civile (test_sim_loyalty/rebellion/civil_war li provano).
	var rules := Rules.new()
	rules.province.calm()
	return GameSetup.new_game(campaign, units, buildings, rules, seed_value, HeroesLoader.load_file(HEROES))


## Mondo senza morti ne' nascite: nessun personaggio muore di vecchiaia e nessuno nasce.
func _calm_world(seed_value: int = 7) -> GameState:
	var s := _world(seed_value)
	s.rules.dynasty.birth_chance = 0.0
	for c in s.characters:
		c.old_age = 500
	return s


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _events_about(s: GameState, kind: String, character_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _events_of(s, kind):
		if int(e.get("personaggio", 0)) == character_id:
			out.append(e)
	return out


func _army_in(s: GameState, faction: String, region: String) -> Army:
	for a in s.armies_of(faction):
		if a.region == region and not a.is_fleet:
			return a
	return null


## Fa morire di vecchiaia il personaggio al prossimo fine anno (probabilita' 1).
func _doom(s: GameState, c: Character) -> void:
	c.old_age = 40
	c.birth_year = s.year + 1 - (c.old_age + 60)


func _add_prince(s: GameState, faction: String, age: int, command: int) -> Character:
	var c := s.create_character(faction)
	c.role = Character.ROLE_PRINCE
	c.royal_blood = true
	c.male = true
	c.forename = "Principe"
	c.birth_year = s.year - age
	c.command = command
	c.loyalty = 8
	c.old_age = 500
	c.region = "ID_ALTA"
	return c


# --- invecchiamento e morte ----------------------------------------------------------------


func test_probabilita_di_morte(t: TestContext) -> void:
	var d := DynastyRules.new()
	t.assert_eq(d.death_chance(40, 44), 0.0, "sotto la soglia")
	t.assert_eq(d.death_chance(44, 44), 0.0, "alla soglia")
	t.assert_eq(d.death_chance(54, 44), 0.2, "(54 - 44) / 50")
	t.assert_eq(d.death_chance(200, 44), 1.0, "limitata a 1")
	d.death_k = 5.0
	t.assert_eq(d.death_chance(54, 44), 0.3, "k si somma all'eta' oltre la soglia")


func test_la_soglia_di_vecchiaia(t: TestContext) -> void:
	var s := _world()
	var general := CharacterFactory.make_general(s, "FN_ALPHA", "ID_ALTA", s.year, s.rng)
	t.assert_true(general.old_age >= 40 and general.old_age <= 44, "generale: 40 + 0..4, e' %d" % general.old_age)
	for c in s.characters:
		if c.royal_blood or c.is_hero:
			t.assert_true(c.old_age >= 50 and c.old_age <= 54, "sangue reale o eroe: +10 (%s: %d)" % [c.full_name(), c.old_age])
		elif c != general:
			t.assert_true(c.old_age >= 40 and c.old_age <= 44, "%s: %d" % [c.full_name(), c.old_age])


func test_morte_di_vecchiaia_ed_evento(t: TestContext) -> void:
	var s := _calm_world()
	var general := s.governor_of("ID_BASSA")
	_doom(s, general)
	var bassa := _army_in(s, "FN_ALPHA", "ID_BASSA")
	var res := TurnProcessor.end_year(s)
	t.assert_true(bool(res["ok"]))
	t.assert_false(general.alive)
	t.assert_eq(general.death_year, 1001)
	t.assert_eq(general.death_cause, "vecchiaia")
	t.assert_eq(general.title, "", "il titolo si perde")
	var deaths := _events_about(s, GameState.EV_DEATH, general.id)
	t.assert_eq(deaths.size(), 1)
	t.assert_eq(deaths[0]["fazione"], "FN_ALPHA")
	t.assert_eq(deaths[0]["regione"], "ID_BASSA")
	t.assert_eq(deaths[0]["anno"], 1000)
	t.assert_eq(deaths[0]["eta"], 100, "nato nel 901")
	t.assert_true(str(deaths[0]["testo"]).contains("muore"))
	var new_commander := s.commander_of(bassa.id)
	t.assert_true(new_commander != null and new_commander != general and new_commander.alive, "l'esercito riceve un nuovo comandante")
	t.assert_eq(_events_of(s, GameState.EV_SUCCESSION).size(), 0, "un generale non e' un capo")


func test_nessuna_morte_sotto_la_soglia(t: TestContext) -> void:
	var s := _calm_world()
	for c in s.characters:
		c.old_age = 100
	# due anni soltanto: l'eroe del 1003 (soglia reale 50-54) compare dopo
	for i in 2:
		TurnProcessor.end_year(s)
		t.assert_eq(_events_of(s, GameState.EV_DEATH).size(), 0, "nessuno e' oltre la soglia")
	for c in s.characters:
		t.assert_true(c.alive)


func test_il_re_dei_auror_non_muore(t: TestContext) -> void:
	var s := _calm_world()
	var leader := s.leader_of("FN_ALPHA")
	s.rules.dynasty.fixed["FN_ALPHA"] = {"immortal_king": true}
	_doom(s, leader)
	TurnProcessor.end_year(s)
	t.assert_true(leader.alive, "capo di una fazione con re_immortale")
	t.assert_true(s.leader_of("FN_ALPHA") == leader)
	var heir := s.heir_of("FN_ALPHA")
	_doom(s, heir)
	TurnProcessor.end_year(s)
	t.assert_false(heir.alive, "gli altri membri invecchiano")


## Richiesta di Federico (2026-11-18): generali e agenti degli Auror vivono almeno 100-150 anni (`vecchiaia_minima`,
## `vecchiaia_massima` di auror.cfg): soglia stabile per personaggio nell'intervallo, mai sotto quella che avrebbe.
func test_longevita_degli_auror(t: TestContext) -> void:
	var s := _calm_world()
	s.rules.dynasty.fixed["FN_ALPHA"] = {"immortal_king": true, "longevity_min": 100, "longevity_max": 150}
	s.rules.dynasty.death_divisor = 0.0001   # oltre la soglia si muore di sicuro
	var seen := {}
	for i in 200:
		var th := s.rules.dynasty.longevity_threshold("FN_ALPHA", i)
		t.assert_true(th >= 100 and th <= 150, "soglia %d nell'intervallo" % th)
		seen[th] = true
	t.assert_true(seen.size() > 20, "soglie diverse tra i personaggi")
	t.assert_eq(s.rules.dynasty.longevity_threshold("FN_ALPHA", 7), s.rules.dynasty.longevity_threshold("FN_ALPHA", 7), "stabile")
	t.assert_eq(s.rules.dynasty.longevity_threshold("FN_BETA", 7), 0, "le altre fazioni no")
	var general := CharacterFactory.make_general(s, "FN_ALPHA", "ID_ALTA", s.year, s.rng)
	general.old_age = 40
	general.birth_year = s.year + 1 - 99
	TurnProcessor.end_year(s)
	t.assert_true(general.alive, "a 99 anni un generale degli Auror e' vivo")
	general.birth_year = s.year + 1 - 151
	TurnProcessor.end_year(s)
	t.assert_false(general.alive, "oltre i 150 anni muore")
	t.assert_eq(general.death_cause, "vecchiaia")
	var other := CharacterFactory.make_general(s, "FN_BETA", "ID_ALTA", s.year, s.rng)
	other.old_age = 40
	other.birth_year = s.year + 1 - 60
	TurnProcessor.end_year(s)
	t.assert_false(other.alive, "le altre fazioni invecchiano come prima")


func test_principesse_degli_auror_longeve(t: TestContext) -> void:
	var s := _calm_world()
	s.rules.dynasty.fixed["FN_ALPHA"] = {"longevity_min": 100, "longevity_max": 150}
	var princess := s.create_character("FN_ALPHA")
	princess.role = Character.ROLE_PRINCESS
	princess.royal_blood = true
	princess.male = false
	princess.forename = "Principessa"
	princess.birth_year = s.year + 1 - 80
	princess.old_age = 500
	TurnProcessor.end_year(s)
	t.assert_true(princess.alive, "a 80 anni una principessa degli Auror non si ritira")
	princess.birth_year = s.year + 1 - 151
	TurnProcessor.end_year(s)
	t.assert_false(princess.alive, "oltre la soglia di longevita' si ritira")


func test_ritiro_della_principessa(t: TestContext) -> void:
	var s := _calm_world()
	var princess: Character = null
	for c in s.characters_of("FN_ALPHA"):
		if c.role == Character.ROLE_PRINCESS:
			princess = c
	princess.birth_year = s.year + 1 - 32
	TurnProcessor.end_year(s)
	t.assert_false(princess.alive)
	t.assert_eq(princess.death_cause, "ritiro")
	var events := _events_about(s, GameState.EV_DEATH, princess.id)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["causa"], "ritiro")


# --- successione ------------------------------------------------------------------------------------


func test_successione_dell_erede(t: TestContext) -> void:
	var s := _calm_world()
	var old := s.leader_of("FN_ALPHA")
	var heir := s.heir_of("FN_ALPHA")
	var brother: Character = null
	for c in s.characters_of("FN_ALPHA"):
		if c.royal_blood and c.male and c.age(s.year) == 10:
			brother = c
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	_doom(s, old)
	TurnProcessor.end_year(s)
	t.assert_false(old.alive)
	t.assert_true(s.leader_of("FN_ALPHA") == heir, "sale al trono l'erede designato maggiorenne")
	t.assert_eq(heir.role, Character.ROLE_LEADER)
	t.assert_eq(heir.influence, s.rules.dynasty.successor_influence)
	t.assert_true(heir.numeral >= 1, "numerale del nuovo re")
	t.assert_eq(heir.army, alta.id, "prende l'esercito del predecessore")
	t.assert_true(s.commander_of(alta.id) == heir)
	t.assert_eq(brother.role, Character.ROLE_GENERAL, "i fratelli non sono piu' principi")
	var successions := _events_of(s, GameState.EV_SUCCESSION)
	t.assert_eq(successions.size(), 1)
	t.assert_eq(successions[0]["fazione"], "FN_ALPHA")
	t.assert_eq(successions[0]["personaggio"], heir.id)
	t.assert_eq(successions[0]["precedente"], old.id)
	t.assert_true(bool(successions[0]["per_eredita"]))
	t.assert_eq(successions[0]["contendenti"], 0)
	t.assert_eq(successions[0]["fratelli_declassati"], 1)
	t.assert_eq(_events_about(s, GameState.EV_DEATH, old.id).size(), 1)
	t.assert_true(s.faction("FN_ALPHA").alive)


func test_il_numerale_dei_re_cresce(t: TestContext) -> void:
	var s := _calm_world()
	var heir := s.heir_of("FN_ALPHA")
	heir.name_index = 1
	var old := s.leader_of("FN_ALPHA")
	t.assert_eq(old.name_index, 1)
	_doom(s, old)
	TurnProcessor.end_year(s)
	t.assert_eq(heir.numeral, 2, "il secondo Edward della fazione")
	t.assert_eq(s.royal_counter("FN_ALPHA", 1), 2)


func test_un_re_famoso_per_nome_e_numerale(t: TestContext) -> void:
	var s := _calm_world()
	var heir := s.heir_of("FN_ALPHA")
	heir.name_index = 2
	heir.forename = "Richard"
	_doom(s, s.leader_of("FN_ALPHA"))
	TurnProcessor.end_year(s)
	t.assert_eq(heir.numeral, 1)
	t.assert_eq(heir.command, 6, "Richard I e' un re famoso: prende i suoi attributi")
	t.assert_eq(heir.dread, 2)
	t.assert_eq(heir.vnv, {"fearsome": 1})


func test_senza_erede_maggiorenne_sale_il_principe_migliore(t: TestContext) -> void:
	var s := _calm_world()
	var heir := s.heir_of("FN_ALPHA")
	heir.birth_year = s.year - 10
	var weak := _add_prince(s, "FN_ALPHA", 30, 2)
	var strong := _add_prince(s, "FN_ALPHA", 28, 6)
	var young := _add_prince(s, "FN_ALPHA", 12, 9)
	young.role = Character.ROLE_HEIR
	_doom(s, s.leader_of("FN_ALPHA"))
	TurnProcessor.end_year(s)
	t.assert_true(s.leader_of("FN_ALPHA") == strong, "piu' comando tra i maggiorenni di sangue reale")
	var successions := _events_of(s, GameState.EV_SUCCESSION)
	t.assert_eq(successions.size(), 1)
	t.assert_false(bool(successions[0]["per_eredita"]))
	t.assert_eq(successions[0]["contendenti"], 1, "l'altro principe maggiorenne")
	t.assert_eq(weak.role, Character.ROLE_PRINCE, "chi non sale non viene declassato")
	t.assert_true(s.faction("FN_ALPHA").alive)


func test_il_minorenne_non_eredita(t: TestContext) -> void:
	var s := _calm_world()
	var heir := s.heir_of("FN_ALPHA")
	heir.birth_year = s.year - 14
	var brother: Character = null
	for c in s.characters_of("FN_ALPHA"):
		if c.royal_blood and c.male and c != heir and c.role == Character.ROLE_HEIR:
			brother = c
	var prince := _add_prince(s, "FN_ALPHA", 40, 1)
	_doom(s, s.leader_of("FN_ALPHA"))
	TurnProcessor.end_year(s)
	t.assert_true(s.leader_of("FN_ALPHA") == prince)
	t.assert_eq(heir.role, Character.ROLE_HEIR)
	t.assert_true(brother.alive)


func test_estinzione_senza_eredi(t: TestContext) -> void:
	var s := _calm_world()
	var beta := s.faction("FN_BETA")
	var old := s.leader_of("FN_BETA")
	var mezza := _army_in(s, "FN_BETA", "ID_MEZZA")
	_doom(s, old)
	TurnProcessor.end_year(s)
	t.assert_false(beta.alive, "l'erede ha 6 anni: nessun successore")
	t.assert_eq(s.province("ID_MEZZA").owner, GameState.REBEL, "le province passano ai ribelli")
	t.assert_true(s.army(mezza.id) == null, "gli eserciti sono sciolti")
	t.assert_eq(s.armies_of("FN_BETA").size(), 0)
	t.assert_eq(s.characters_of("FN_BETA").size(), 0, "tutti i personaggi escono dal gioco")
	for a in s.agents:
		t.assert_true(a.faction != "FN_BETA", "anche gli agenti")
	var events := _events_of(s, GameState.EV_FACTION_EXTINCT)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["fazione"], "FN_BETA")
	t.assert_eq(events[0]["province"], ["ID_MEZZA"])
	t.assert_eq(_events_of(s, GameState.EV_SUCCESSION).size(), 0)
	t.assert_true(s.faction("FN_ALPHA").alive)
	# l'anno dopo non si ripete niente
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_FACTION_EXTINCT).size(), 0)
	t.assert_eq(_events_of(s, GameState.EV_FACTION_DESTROYED).size(), 0)


func test_il_titolo_si_perde_con_la_provincia(t: TestContext) -> void:
	var s := _calm_world()
	var governor := s.governor_of("ID_BASSA")
	s.province("ID_BASSA").owner = "FN_BETA"
	TurnProcessor.end_year(s)
	t.assert_eq(governor.title, "")
	t.assert_true(s.governor_of("ID_BASSA") == null)
	var events := _events_about(s, GameState.EV_TITLE_CHANGED, governor.id)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["azione"], "perso")


# --- nascite ----------------------------------------------------------------------------------------


func test_nascite_certe(t: TestContext) -> void:
	var s := _world()
	s.rules.dynasty.birth_chance = 1.0
	for c in s.characters:
		c.old_age = 500
	var before := s.characters.size()
	TurnProcessor.end_year(s)
	var births := _events_of(s, GameState.EV_BIRTH)
	t.assert_eq(births.size(), 2, "un figlio per ognuno dei due capi")
	t.assert_eq(s.characters.size(), before + 2)
	var factions := {}
	for e in births:
		factions[str(e["fazione"])] = true
		var child := s.character(int(e["personaggio"]))
		var father := s.leader_of(str(e["fazione"]))
		t.assert_true(child != null and father != null)
		t.assert_eq(child.birth_year, 1001)
		t.assert_true(child.royal_blood and child.alive)
		t.assert_eq(child.loyalty, s.rules.dynasty.child_loyalty)
		t.assert_eq(child.male, bool(e["maschio"]))
		t.assert_eq(child.role, Character.ROLE_HEIR if child.male else Character.ROLE_PRINCESS)
		t.assert_eq(int(e["padre"]), father.id)
		t.assert_true(absi(child.command - father.command) <= s.rules.dynasty.inherit_spread or child.command == 0 or child.command == 10)
		t.assert_true(child.old_age >= 50 and child.old_age <= 54)
		t.assert_true(str(e["testo"]).contains(child.full_name()))
	t.assert_eq(factions.size(), 2)


func test_nessuna_nascita_fuori_dall_eta_del_capo(t: TestContext) -> void:
	var s := _world()
	s.rules.dynasty.birth_chance = 1.0
	for c in s.characters:
		c.old_age = 500
	var leader := s.leader_of("FN_ALPHA")
	leader.birth_year = s.year - 60
	var beta := s.leader_of("FN_BETA")
	beta.birth_year = s.year + 1 - 17
	TurnProcessor.end_year(s)
	t.assert_eq(_events_of(s, GameState.EV_BIRTH).size(), 0, "troppo vecchio o troppo giovane")


## Richiesta di Federico (2026-11-20): Darkos I non muore ma, passata l'eta' delle nascite, restava senza eredi. Il capo
## di una fazione con nuove nozze si risposa subito, ha figli per gli anni fertili, poi si risposa dopo l'intervallo.
func test_il_capo_immortale_si_risposa_e_ha_figli(t: TestContext) -> void:
	var s := _world()
	s.rules.dynasty.birth_chance = 1.0
	for c in s.characters:
		c.old_age = 500
	var leader := s.leader_of("FN_ALPHA")
	leader.birth_year = s.year - 150
	s.leader_of("FN_BETA").birth_year = s.year - 150   # senza nuove nozze: niente figli
	s.rules.dynasty.fixed["FN_ALPHA"] = {"immortal_king": true, "remarry_min": 20, "remarry_max": 20, "remarry_fertile": 10}
	var start := s.year
	var weddings: Array[int] = []
	var births_by_year := {}
	for i in 21:
		TurnProcessor.end_year(s)
		for e in _events_of(s, GameState.EV_MARRIAGE):
			if bool(e.get("nozze_capo", false)):
				t.assert_eq(int(e["personaggio"]), leader.id)
				t.assert_eq(str(e["fazione"]), "FN_ALPHA")
				t.assert_true(str(e["sposa"]) != "" and str(e["testo"]).contains(str(e["sposa"])))
				t.assert_true(str(e["da"]) != "FN_ALPHA", "sposa di un'altra fazione")
				t.assert_true(CampaignUiText.format_event(s, e).contains(Lang.t("prende in moglie").split(" ")[0]), CampaignUiText.format_event(s, e))
				weddings.append(s.year)
		for e in _events_of(s, GameState.EV_BIRTH):
			t.assert_eq(str(e["fazione"]), "FN_ALPHA", "BETA non ha nuove nozze")
			births_by_year[s.year] = int(births_by_year.get(s.year, 0)) + 1
	t.assert_eq(weddings, [start + 1, start + 21] as Array[int], "nozze subito e dopo 20 anni")
	t.assert_false(births_by_year.has(start + 1), "nessun figlio nell'anno delle nozze")
	for y in range(start + 2, start + 12):
		t.assert_eq(int(births_by_year.get(y, 0)), 1, "figlio nel %d (anni fertili)" % y)
	for y in range(start + 12, start + 22):
		t.assert_false(births_by_year.has(y), "nessun figlio nel %d (oltre gli anni fertili)" % y)
	t.assert_true(leader.alive and s.leader_of("FN_ALPHA") == leader)
	t.assert_eq(int(leader.counters.get("nozze_prossime", 0)), start + 41)
	t.assert_eq(int(Character.from_dict(leader.to_dict()).counters.get("nozze_prossime", 0)), start + 41, "contatori salvati")


func test_nuove_nozze_dai_dati_degli_auror(t: TestContext) -> void:
	var r := DynastyRules.load_file()
	var plan := r.remarriage("FN_DANISH")
	t.assert_false(plan.is_empty(), "auror.cfg ha le nuove nozze del capo")
	t.assert_true(int(plan["min"]) > 0 and int(plan["max"]) >= int(plan["min"]) and int(plan["fertile"]) > 0)
	for y in range(1000, 1100):
		var gap := r.remarriage_interval("FN_DANISH", 3, y)
		t.assert_true(gap >= int(plan["min"]) and gap <= int(plan["max"]))
	t.assert_true(r.remarriage("FN_ENGLISH").is_empty(), "solo gli Auror")


func test_nessuna_nascita_con_probabilita_zero(t: TestContext) -> void:
	var s := _calm_world()
	for i in 10:
		TurnProcessor.end_year(s)
		t.assert_eq(_events_of(s, GameState.EV_BIRTH).size(), 0)


# --- maggiore eta' ------------------------------------------------------------------------------------


func test_maggiore_eta_del_principe_e_della_principessa(t: TestContext) -> void:
	var s := _calm_world()
	var brother: Character = null
	var princess: Character = null
	for c in s.characters_of("FN_ALPHA"):
		if c.role == Character.ROLE_PRINCESS:
			princess = c
		elif c.royal_blood and c.male and c.age(s.year) == 10:
			brother = c
	var prince_event := false
	var princess_event := false
	for i in 8:
		TurnProcessor.end_year(s)
		for e in _events_of(s, GameState.EV_COMING_OF_AGE):
			if int(e["personaggio"]) == brother.id:
				prince_event = true
				t.assert_eq(s.year, 1006, "16 anni nel 1006 (nato nel 990)")
				t.assert_eq(e["eta"], 16)
			elif int(e["personaggio"]) == princess.id:
				princess_event = true
				t.assert_eq(s.year, 1007, "15 anni nel 1007 (nata nel 992)")
	t.assert_true(prince_event, "evento di maggiore eta' del fratello")
	t.assert_true(princess_event, "evento di maggiore eta' della principessa")
	t.assert_eq(brother.role, Character.ROLE_PRINCE, "non e' l'erede designato: diventa principe")
	t.assert_eq(s.heir_of("FN_ALPHA").age(s.year), 28, "l'erede designato resta lo stesso")


# --- eroi famosi -----------------------------------------------------------------------------------------


func test_compare_l_eroe_famoso(t: TestContext) -> void:
	var s := _calm_world()
	var appeared := 0
	for i in 12:
		TurnProcessor.end_year(s)
		for e in _events_of(s, GameState.EV_HERO_APPEARS):
			appeared += 1
			var hero := s.character(int(e["personaggio"]))
			t.assert_true(hero.is_hero and hero.alive)
			t.assert_eq(hero.role, Character.ROLE_GENERAL)
			if hero.forename == "Guy":
				t.assert_eq(s.year, 1003, "l'anno 1003 del file")
				t.assert_eq(e["fazione"], "FN_ALPHA")
				t.assert_eq(e["regione"], "ID_BASSA")
				t.assert_eq(hero.surname, "Senzaterra")
				t.assert_eq(hero.command, 4)
				t.assert_eq(hero.dread, 5)
				t.assert_eq(hero.loyalty, 6)
				t.assert_eq(hero.vnv, {"attacker": 2})
				t.assert_true(hero.old_age >= 50 and hero.old_age <= 54)
				t.assert_true(hero.age(s.year) >= 25 and hero.age(s.year) <= 40)
			else:
				t.assert_eq(hero.forename, "Yusuf")
				t.assert_eq(s.year, 1010)
				t.assert_eq(e["fazione"], "FN_BETA")
				t.assert_eq(e["regione"], "ID_MEZZA", "ID_LIMBO: nella capitale")
	t.assert_eq(appeared, 2, "Guy (1003) e Yusuf (1010): niente vescovi, niente eroi del 1050, nessuna ripetizione")
	t.assert_eq(s.heroes_done.size(), 3)


func test_l_eroe_aspetta_se_la_fazione_non_ha_province(t: TestContext) -> void:
	var s := _calm_world()
	s.province("ID_MEZZA").owner = GameState.REBEL
	# senza togliere i suoi eserciti BETA riconquisterebbe subito la provincia rimasta sguarnita
	for a in s.armies_of("FN_BETA"):
		s.remove_army(a)
	for i in 12:
		TurnProcessor.end_year(s)
	for c in s.characters:
		t.assert_true(c.forename != "Yusuf", "BETA e' estinta o senza province")


# --- influenza, battaglie, vizi e virtu' --------------------------------------------------------------------


func _captures(s: GameState, winner: String, loser: String, count: int) -> void:
	for i in count:
		s.add_event(GameState.EV_PROVINCE_CAPTURED, {"fazione": winner, "regione": "ID_SOLA", "precedente": loser, "testo": "prova"})


func test_influenza_del_capo(t: TestContext) -> void:
	var s := _calm_world()
	var alpha := s.leader_of("FN_ALPHA")
	var beta := s.leader_of("FN_BETA")
	s.events.clear()
	_captures(s, "FN_BETA", "FN_ALPHA", 3)
	DynastyProcessor.process_year(s)
	t.assert_eq(alpha.influence, 4, "-1 ogni 2 province perse")
	t.assert_eq(beta.influence, 6, "+1 ogni 2 province conquistate")
	t.assert_eq(int(alpha.counters.get("province_perse", 0)), 1, "ne resta una da contare")
	s.events.clear()
	_captures(s, "FN_BETA", "FN_ALPHA", 1)
	DynastyProcessor.process_year(s)
	t.assert_eq(alpha.influence, 3)
	t.assert_eq(beta.influence, 7)
	s.events.clear()
	_captures(s, "FN_BETA", GameState.REBEL, 2)
	DynastyProcessor.process_year(s)
	t.assert_eq(beta.influence, 8, "i ribelli non hanno un capo")


func test_l_influenza_resta_tra_zero_e_dieci(t: TestContext) -> void:
	var s := _calm_world()
	var alpha := s.leader_of("FN_ALPHA")
	alpha.influence = 0
	s.events.clear()
	_captures(s, "FN_BETA", "FN_ALPHA", 4)
	DynastyProcessor.process_year(s)
	t.assert_eq(alpha.influence, 0)
	var beta := s.leader_of("FN_BETA")
	beta.influence = 10
	t.assert_true(beta.influence <= 10)
	s.events.clear()
	_captures(s, "FN_BETA", "FN_ALPHA", 4)
	DynastyProcessor.process_year(s)
	t.assert_eq(beta.influence, 10)


func _battle(s: GameState, winner_army: int, loser_army: int, attacker_won: bool, retreated: bool) -> void:
	var attackers: Array = [winner_army] if attacker_won else [loser_army]
	var defenders: Array = [loser_army] if attacker_won else [winner_army]
	var retreats: Array = []
	if retreated:
		retreats.append({"esercito": loser_army})
	s.add_event(GameState.EV_BATTLE, {
		"fazione": "FN_ALPHA",
		"regione": "ID_MEZZA",
		"vittoria_attaccante": attacker_won,
		"eserciti_attaccanti": attackers,
		"eserciti_difensori": defenders,
		"perdite_attaccante": 10 if attacker_won else 40,
		"perdite_difensore": 40 if attacker_won else 10,
		"ritirate": retreats,
		"catture": [{"esercito": 99, "uomini": 5}],
		"testo": "prova",
	})


func test_contatori_dopo_una_battaglia(t: TestContext) -> void:
	var s := _calm_world()
	s.rules.dynasty.star_win_chance = 0.0
	s.rules.dynasty.star_loss_chance = 0.0
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	var mezza := _army_in(s, "FN_BETA", "ID_MEZZA")
	var winner := s.commander_of(alta.id)
	var loser := s.commander_of(mezza.id)
	s.events.clear()
	_battle(s, alta.id, mezza.id, true, true)
	DynastyProcessor.process_year(s)
	t.assert_eq(int(winner.counters.get("vittorie", 0)), 1)
	t.assert_eq(int(winner.counters.get("uccisioni", 0)), 40, "gli uomini uccisi vanno al vincitore")
	t.assert_eq(int(winner.counters.get("prigionieri", 0)), 0, "ADR-073: i prigionieri contano solo quando si giustiziano")
	t.assert_eq(int(loser.counters.get("sconfitte", 0)), 1)
	t.assert_eq(int(loser.counters.get("ritirate", 0)), 1)
	t.assert_eq(int(loser.counters.get("vittorie", 0)), 0)
	t.assert_eq(_events_of(s, GameState.EV_STAR_CHANGED).size(), 0, "probabilita' zero: nessuna stella")


func test_stelle_dopo_vittoria_e_sconfitta(t: TestContext) -> void:
	var s := _calm_world()
	s.rules.dynasty.star_win_chance = 1.0
	s.rules.dynasty.star_loss_chance = 1.0
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	var mezza := _army_in(s, "FN_BETA", "ID_MEZZA")
	var winner := s.commander_of(alta.id)
	var loser := s.commander_of(mezza.id)
	loser.command = 4
	var winner_before := winner.command
	s.events.clear()
	_battle(s, alta.id, mezza.id, true, false)
	DynastyProcessor.process_year(s)
	t.assert_eq(winner.command, winner_before + 1)
	t.assert_eq(loser.command, 3)
	var events := _events_of(s, GameState.EV_STAR_CHANGED)
	t.assert_eq(events.size(), 2)
	var up := _events_about(s, GameState.EV_STAR_CHANGED, winner.id)
	t.assert_eq(up.size(), 1)
	t.assert_eq(up[0]["motivo"], "vittoria")
	t.assert_eq(up[0]["stelle_dopo"], up[0]["stelle_prima"] + 1)
	var down := _events_about(s, GameState.EV_STAR_CHANGED, loser.id)
	t.assert_eq(down[0]["motivo"], "sconfitta")
	t.assert_eq(down[0]["stelle_dopo"], down[0]["stelle_prima"] - 1)
	t.assert_eq(down[0]["fazione"], "FN_BETA")
	t.assert_eq(down[0]["regione"], "ID_MEZZA")


func test_le_stelle_restano_tra_zero_e_dieci(t: TestContext) -> void:
	var s := _calm_world()
	s.rules.dynasty.star_win_chance = 1.0
	s.rules.dynasty.star_loss_chance = 1.0
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	var mezza := _army_in(s, "FN_BETA", "ID_MEZZA")
	var winner := s.commander_of(alta.id)
	var loser := s.commander_of(mezza.id)
	winner.command = 10
	loser.command = 0
	s.events.clear()
	_battle(s, alta.id, mezza.id, true, false)
	DynastyProcessor.process_year(s)
	t.assert_eq(winner.command, 10)
	t.assert_eq(loser.command, 0)
	t.assert_eq(_events_of(s, GameState.EV_STAR_CHANGED).size(), 0)


func test_vince_il_difensore(t: TestContext) -> void:
	var s := _calm_world()
	s.rules.dynasty.star_win_chance = 0.0
	s.rules.dynasty.star_loss_chance = 0.0
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	var mezza := _army_in(s, "FN_BETA", "ID_MEZZA")
	var defender := s.commander_of(mezza.id)
	var attacker := s.commander_of(alta.id)
	s.events.clear()
	_battle(s, mezza.id, alta.id, false, true)
	DynastyProcessor.process_year(s)
	t.assert_eq(int(defender.counters.get("vittorie", 0)), 1)
	t.assert_eq(int(defender.counters.get("uccisioni", 0)), 40, "perdite dell'attaccante")
	t.assert_eq(int(attacker.counters.get("sconfitte", 0)), 1)


func test_un_vizio_o_una_virtu_si_ottiene_alla_soglia(t: TestContext) -> void:
	var s := _calm_world()
	s.rules.dynasty.star_win_chance = 0.0
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	var mezza := _army_in(s, "FN_BETA", "ID_MEZZA")
	var winner := s.commander_of(alta.id)
	winner.vnv = {}
	winner.counters = {"vittorie": 2}
	var base := winner.effective(Character.ATTR_COMMAND, s.rules, s.campaign)
	s.events.clear()
	_battle(s, alta.id, mezza.id, true, false)
	DynastyProcessor.process_year(s)
	t.assert_eq(winner.vnv, {"fearsome": 1}, "3 vittorie: Leadership di primo livello")
	var events := _events_about(s, GameState.EV_VNV_GAINED, winner.id)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["vnv"], "fearsome1")
	t.assert_eq(events[0]["livello"], 1)
	t.assert_true(str(events[0]["testo"]).contains("Leadership"))
	t.assert_eq(winner.effective(Character.ATTR_COMMAND, s.rules, s.campaign), mini(10, base + s.rules.vnv.delta("fearsome", 1, Character.ATTR_COMMAND)))
	# una seconda battaglia non rimette lo stesso livello
	s.events.clear()
	_battle(s, alta.id, mezza.id, true, false)
	DynastyProcessor.process_year(s)
	t.assert_eq(_events_of(s, GameState.EV_VNV_GAINED).size(), 0)
	t.assert_eq(int(winner.counters["vittorie"]), 4)


func test_la_catena_del_terrore_vale_solo_per_il_capo(t: TestContext) -> void:
	var s := _calm_world()
	var leader := s.leader_of("FN_ALPHA")
	leader.vnv = {}
	leader.counters = {"anni_tassa_alta": 4}
	for p in s.provinces_of("FN_ALPHA"):
		p.tax_level = 4
	s.events.clear()
	DynastyProcessor.process_year(s)
	t.assert_eq(int(leader.counters["anni_tassa_alta"]), 5)
	t.assert_eq(leader.vnv, {"tyrant": 1}, "5 anni di tassa alta")
	var general := s.governor_of("ID_BASSA")
	general.vnv = {}
	general.counters = {"anni_tassa_alta": 50}
	DynastyProcessor.check_vnv(s, general)
	t.assert_eq(general.vnv, {}, "solo il capo")
	# la tassa normale non conta
	for p in s.provinces_of("FN_ALPHA"):
		p.tax_level = 2
	s.events.clear()
	DynastyProcessor.process_year(s)
	t.assert_eq(int(leader.counters["anni_tassa_alta"]), 5)


# --- comandanti ----------------------------------------------------------------------------------------


func test_ogni_esercito_nuovo_riceve_un_comandante(t: TestContext) -> void:
	var s := _calm_world()
	s.faction("FN_ALPHA").treasury = 50000
	GameCommands.queue_unit(s, "FN_ALPHA", "ID_ALTA", "Spearmen")
	for i in 5:
		TurnProcessor.end_year(s)
	for a in s.armies:
		if a.faction == GameState.REBEL:
			continue
		var c := s.commander_of(a.id)
		t.assert_true(c != null and c.alive and c.faction == a.faction, "esercito %d" % a.id)


func test_un_esercito_distrutto_libera_il_comandante(t: TestContext) -> void:
	var s := _calm_world()
	var bassa := _army_in(s, "FN_ALPHA", "ID_BASSA")
	var c := s.commander_of(bassa.id)
	s.remove_army(bassa)
	TurnProcessor.end_year(s)
	t.assert_true(c.alive)
	t.assert_eq(c.army, 0)
	t.assert_eq(s.character_region(c), "ID_BASSA")


func test_le_posizioni_seguono_gli_eserciti(t: TestContext) -> void:
	var s := _calm_world()
	var bassa := _army_in(s, "FN_ALPHA", "ID_BASSA")
	var c := s.commander_of(bassa.id)
	GameCommands.order_move(s, "FN_ALPHA", bassa.id, PackedStringArray(["ID_ALTA"]))
	TurnProcessor.end_year(s)
	t.assert_eq(bassa.region, "ID_ALTA")
	t.assert_eq(c.region, "ID_ALTA")
	t.assert_eq(s.character_region(c), "ID_ALTA")


# --- economia e scontri ----------------------------------------------------------------------------------


func test_l_acume_aumenta_agricoltura_e_commercio(t: TestContext) -> void:
	var plain := GameSetup.new_game(StartposLoader.load_file(PLAIN_STARTPOS), UnitProdLoader.load_file(UNITS), BuildingProdLoader.load_file(BUILDINGS), Rules.new(), 7)
	var s := _world()
	var province := s.province("ID_ALTA")
	var base := Economy.province_income(plain, plain.province("ID_ALTA"))
	for c in s.characters:
		c.acumen = 0
		c.vnv = {}
		c.title = ""
		c.office = ""
	var zero := Economy.province_income(s, province)
	t.assert_eq(zero["agricoltura"], base["agricoltura"], "acume 0: nessuna variazione")
	var leader := s.leader_of("FN_ALPHA")
	leader.acumen = 5
	var king := Economy.province_income(s, province)
	t.assert_eq(king["agricoltura"], roundi(float(base["agricoltura"]) * 1.10), "5 punti x 2% = +10% (re)")
	var heir := s.heir_of("FN_ALPHA")
	heir.acumen = 4
	heir.title = "ID_ALTA"
	var both := Economy.province_income(s, province)
	t.assert_true(int(both["agricoltura"]) > int(king["agricoltura"]), "il governatore conta di piu'")
	t.assert_eq(both["miniere"], base["miniere"], "le miniere non dipendono dall'acume")
	var table := Economy.acumen_table(s)
	t.assert_eq(Economy.province_income(s, province, table), both, "con la tabella annuale il risultato e' lo stesso")
	t.assert_eq(Economy.acumen_multiplier(plain, plain.province("ID_ALTA")), 1.0, "senza personaggi vale 1")


func test_il_comando_del_comandante_conta_negli_scontri(t: TestContext) -> void:
	var s := _world()
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	var leader := s.commander_of(alta.id)
	leader.command = 4
	leader.vnv = {}
	leader.title = ""
	leader.office = ""
	t.assert_eq(Combat.command_stars(s, alta), 4)
	leader.command = 7
	t.assert_eq(Combat.command_stars(s, alta), 7)
	var mezza := _army_in(s, "FN_BETA", "ID_MEZZA")
	s.commander_of(mezza.id).command = 0
	s.commander_of(mezza.id).vnv = {}
	t.assert_eq(Combat.command_stars(s, mezza), 0)
	var fleet: Army = null
	for a in s.armies_of("FN_ALPHA"):
		if a.is_fleet:
			fleet = a
	t.assert_true(fleet != null and s.commander_of(fleet.id) != null, "anche le flotte hanno un comandante")


# --- determinismo e salvataggi ---------------------------------------------------------------------------


func _run(seed_value: int, years: int) -> String:
	var s := _world(seed_value)
	s.rules.dynasty.birth_chance = 0.6
	for i in years:
		var res := TurnProcessor.end_year(s)
		if not bool(res["ok"]):
			break
	return SaveGame.to_json(s)


func test_la_simulazione_e_deterministica(t: TestContext) -> void:
	t.assert_eq(_run(31, 80), _run(31, 80), "stesso seme, stesso stato")
	t.assert_true(_run(31, 80) != _run(32, 80), "un altro seme cambia le dinastie")


func test_salvare_e_ricaricare_a_meta_partita(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var heroes := HeroesLoader.load_file(HEROES)
	var s := GameSetup.new_game(campaign, units, buildings, Rules.new(), 41, heroes)
	s.rules.dynasty.birth_chance = 0.6
	for i in 40:
		TurnProcessor.end_year(s)
	var data := SaveGame.to_dict(s)
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	var r := SaveGame.from_dict(parsed, campaign, units, buildings, Rules.new(), heroes)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	var copy: GameState = r["stato"]
	copy.rules.dynasty.birth_chance = 0.6
	t.assert_eq(copy.characters.size(), s.characters.size())
	t.assert_eq(JSON.stringify(SaveGame.to_dict(copy), "", true), JSON.stringify(data, "", true), "andata e ritorno")
	for i in 40:
		TurnProcessor.end_year(s)
		TurnProcessor.end_year(copy)
	t.assert_eq(JSON.stringify(SaveGame.to_dict(copy), "", true), JSON.stringify(SaveGame.to_dict(s), "", true), "dopo 40 anni identici")
	t.assert_eq(copy.heroes_done, s.heroes_done)
	t.assert_eq(copy.royal_counters, s.royal_counters)


func test_i_salvataggi_vecchi_creano_i_personaggi(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var heroes := HeroesLoader.load_file(HEROES)
	var s := GameSetup.new_game(campaign, units, buildings, Rules.new(), 51, heroes)
	var data := SaveGame.to_dict(s)
	for version in [1, 2]:
		var old := data.duplicate(true)
		old["versione"] = version
		for key in ["personaggi", "prossimo_personaggio", "contatori_reali", "eroi_apparsi"]:
			old.erase(key)
		var parsed: Variant = JSON.parse_string(JSON.stringify(old))
		var r := SaveGame.from_dict(parsed, campaign, units, buildings, Rules.new(), heroes)
		t.assert_true(bool(r["ok"]), "v%d: %s" % [version, str(r["errore"])])
		var loaded: GameState = r["stato"]
		t.assert_true(loaded.leader_of("FN_ALPHA") != null, "v%d: capo di ALPHA" % version)
		t.assert_true(loaded.leader_of("FN_BETA") != null)
		for a in loaded.armies:
			if a.faction != GameState.REBEL:
				t.assert_true(loaded.commander_of(a.id) != null, "v%d: comandante dell'esercito %d" % [version, a.id])
		t.assert_eq(loaded.characters.size(), s.characters.size(), "come in una partita nuova")


func test_la_carica_si_perde_con_l_edificio(t: TestContext) -> void:
	var s := _calm_world()
	var holder := DynastyProcessor.office_holder(s, "FN_ALPHA", "castle")
	t.assert_true(holder != null)
	TurnProcessor.end_year(s)
	t.assert_eq(holder.office, "castle", "con l'edificio la carica resta")
	for p in s.provinces_of("FN_ALPHA"):
		p.set_level("CASTLE", 0)
	TurnProcessor.end_year(s)
	t.assert_eq(holder.office, "")
	var events := _events_about(s, GameState.EV_OFFICE_CHANGED, holder.id)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["azione"], "perso")
