extends RefCounted
## Test dei personaggi (fase 4a): creazione in GameSetup, accessi di GameState, attributi efficaci
## (titoli, cariche, vizi e virtu', valori fissi degli Auror), serializzazione e comandi
## assign_title, revoke_title e set_commander. Mondo di prova tests/fixtures/dynasty_*.txt:
##   ALPHA: ID_ALTA, ID_BASSA, capo Edward I (re famoso, indice 1, numerale 1), eredi 20 e 10 anni (maschi)
##   e 8 anni (femmina); titolo "Duca di Bassa" su ID_BASSA; carica sull'edificio CASTLE.
##   BETA: ID_MEZZA, capo senza re famoso (nome di indice 0), un erede di 5 anni. GAMMA: nessun dato.
## Gli attributi dei generali generati sono casuali (seme fisso): si controllano solo gli intervalli.

const STARTPOS := "res://tests/fixtures/dynasty_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const HEROES := "res://tests/fixtures/dynasty_heroes.txt"
const PLAIN_STARTPOS := "res://tests/fixtures/sim_startpos.txt"


func _world(seed_value: int = 7, with_heroes: bool = true) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var heroes: HeroesData = null
	if with_heroes:
		heroes = HeroesLoader.load_file(HEROES)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), seed_value, heroes)


func _army_in(s: GameState, faction: String, region: String, fleet: bool = false) -> Army:
	for a in s.armies_of(faction):
		if a.region == region and a.is_fleet == fleet:
			return a
	return null


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _adult_general(s: GameState, faction: String, region: String, birth_year: int = 960) -> Character:
	var c := s.create_character(faction)
	c.role = Character.ROLE_GENERAL
	c.forename = "Prova"
	c.birth_year = birth_year
	c.loyalty = 6
	c.region = region
	return c


# --- file di prova --------------------------------------------------------------------


func test_i_file_di_prova_si_leggono_senza_errori(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(STARTPOS)
	t.assert_eq(campaign.errors, PackedStringArray())
	t.assert_eq(campaign.ignored_commands, {})
	var heroes := HeroesLoader.load_file(HEROES)
	t.assert_eq(heroes.errors, PackedStringArray())
	t.assert_eq(heroes.kings_of("FN_ALPHA").size(), 2)
	t.assert_eq(heroes.heroes_of("FN_ALPHA").size(), 4)


# --- creazione ---------------------------------------------------------------------------


func test_senza_dati_dei_capi_non_ci_sono_personaggi(t: TestContext) -> void:
	var campaign := StartposLoader.load_file(PLAIN_STARTPOS)
	var s := GameSetup.new_game(campaign, UnitProdLoader.load_file(UNITS), BuildingProdLoader.load_file(BUILDINGS), Rules.new(), 3)
	t.assert_eq(s.characters.size(), 0, "nessun SetStartLeader: nessun personaggio")
	t.assert_true(s.leader_of("FN_ALPHA") == null)
	t.assert_false(s.has_dynasty("FN_ALPHA"))
	t.assert_true(s.commander_of(1) == null)


func test_ogni_fazione_con_dati_ha_un_capo(t: TestContext) -> void:
	var s := _world()
	var alpha := s.leader_of("FN_ALPHA")
	var beta := s.leader_of("FN_BETA")
	t.assert_true(alpha != null and beta != null)
	t.assert_true(s.leader_of("FN_GAMMA") == null, "GAMMA non e' attiva e non ha dati")
	t.assert_true(s.leader_of("FN_REBEL") == null)
	t.assert_true(s.has_dynasty("FN_ALPHA"))
	t.assert_false(s.has_dynasty("FN_GAMMA"))
	t.assert_eq(alpha.role, Character.ROLE_LEADER)
	t.assert_true(alpha.royal_blood)
	t.assert_true(alpha.male)
	t.assert_true(alpha.alive)
	t.assert_eq(alpha.loyalty, 10)
	t.assert_eq(alpha.influence, 5)


func test_capo_con_re_famoso(t: TestContext) -> void:
	var s := _world()
	var c := s.leader_of("FN_ALPHA")
	t.assert_eq(c.forename, "Edward")
	t.assert_eq(c.numeral, 1)
	t.assert_eq(c.name_index, 1)
	t.assert_eq(c.full_name(), "Edward I")
	t.assert_eq(c.command, 3)
	t.assert_eq(c.dread, 7)
	t.assert_eq(c.piety, 3)
	t.assert_eq(c.acumen, 4)
	t.assert_eq(c.vnv, {"tyrant": 2}, "vizio del re famoso")
	t.assert_true(c.age(1000) >= 30 and c.age(1000) <= 45, "eta' iniziale %d" % c.age(1000))
	t.assert_true(c.old_age >= 50 and c.old_age <= 54, "soglia di vecchiaia con bonus reale: %d" % c.old_age)
	t.assert_eq(s.royal_counter("FN_ALPHA", 1), 1, "contatore del nome Edward")
	t.assert_eq(s.royal_counter("FN_ALPHA", 0), 0)
	t.assert_eq(s.next_numeral("FN_ALPHA", 1), 2, "il prossimo Edward e' il II")


func test_capo_senza_re_famoso(t: TestContext) -> void:
	var s := _world()
	var c := s.leader_of("FN_BETA")
	t.assert_eq(c.name_index, 0, "primo nome con contatore > 0")
	t.assert_eq(c.numeral, 1)
	t.assert_eq(c.forename, "Henry")
	t.assert_true(c.command >= 2 and c.command <= 5, "attributo casuale del capo: %d" % c.command)
	t.assert_true(c.acumen >= 2 and c.acumen <= 5)
	t.assert_true(c.vnv.is_empty())


func test_eredi_e_principesse(t: TestContext) -> void:
	var s := _world()
	var heir := s.heir_of("FN_ALPHA")
	t.assert_true(heir != null)
	t.assert_eq(heir.age(1000), 20, "il maschio piu' anziano e' l'erede designato")
	t.assert_eq(heir.role, Character.ROLE_HEIR)
	t.assert_true(heir.royal_blood and heir.male)
	t.assert_eq(heir.loyalty, 8)
	var young: Character = null
	var princess: Character = null
	for c in s.characters_of("FN_ALPHA"):
		if c.role == Character.ROLE_PRINCESS:
			princess = c
		elif c.royal_blood and c.male and c.age(1000) == 10:
			young = c
	t.assert_true(young != null, "il fratello di 10 anni c'e'")
	t.assert_eq(young.role, Character.ROLE_HEIR, "minorenne: resta erede finche' non e' maggiorenne")
	t.assert_true(princess != null and not princess.male)
	t.assert_eq(princess.age(1000), 8)
	t.assert_true(princess.old_age >= 50, "anche le principesse hanno sangue reale")
	t.assert_eq(s.heir_of("FN_BETA").age(1000), 5)
	t.assert_true(s.heir_of("FN_GAMMA") == null)


func test_ogni_esercito_ha_un_comandante_della_sua_fazione(t: TestContext) -> void:
	var s := _world()
	var checked := 0
	for a in s.armies:
		if a.faction == GameState.REBEL:
			t.assert_true(s.commander_of(a.id) == null, "i ribelli non hanno comandanti")
			continue
		var c := s.commander_of(a.id)
		t.assert_true(c != null, "esercito %d senza comandante" % a.id)
		if c == null:
			continue
		checked += 1
		t.assert_true(c.alive and c.faction == a.faction, "comandante di un'altra fazione")
		t.assert_eq(c.army, a.id)
		t.assert_eq(s.character_region(c), a.region)
		t.assert_true(c.can_command(s.rules.dynasty, s.year), "maggiorenne e non principessa")
	t.assert_true(checked >= 4, "ALPHA ha 3 eserciti e BETA almeno 1: %d" % checked)
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	t.assert_true(s.commander_of(alta.id) == s.leader_of("FN_ALPHA"), "il capo comanda l'esercito di PlaceLeader")
	t.assert_true(s.commander_of(0) == null)
	t.assert_true(s.commander_of(9999) == null)


func test_un_personaggio_comanda_al_massimo_un_esercito(t: TestContext) -> void:
	var s := _world()
	var seen := {}
	for a in s.armies:
		var c := s.commander_of(a.id)
		if c == null:
			continue
		t.assert_false(seen.has(c.id), "personaggio %d al comando di due eserciti" % c.id)
		seen[c.id] = true


func test_titoli_e_cariche_iniziali(t: TestContext) -> void:
	var s := _world()
	var bassa_army := _army_in(s, "FN_ALPHA", "ID_BASSA")
	var governor := s.governor_of("ID_BASSA")
	t.assert_true(governor != null, "il comandante fermo in BASSA ne e' il governatore")
	if governor != null:
		t.assert_eq(governor.army, bassa_army.id)
		t.assert_eq(governor.title, "ID_BASSA")
		t.assert_eq(governor.effective(Character.ATTR_COMMAND, s.rules, s.campaign), mini(10, governor.command + 1), "titolo: +1 al comando")
		t.assert_eq(governor.effective(Character.ATTR_ACUMEN, s.rules, s.campaign), mini(10, governor.acumen + 2), "titolo: +2 all'acume")
	t.assert_true(s.governor_of("ID_ALTA") == null, "ALTA e' del capo: nessun governatore")
	t.assert_true(s.governor_of("ID_MEZZA") == null or s.governor_of("ID_MEZZA").faction == "FN_BETA")
	var holder: Character = null
	for c in s.characters_of("FN_ALPHA"):
		if c.office == "castle":
			holder = c
	t.assert_true(holder != null, "la carica sul Castello e' assegnata")
	if holder != null:
		t.assert_true(holder.role != Character.ROLE_LEADER)
		t.assert_eq(holder.effective(Character.ATTR_COMMAND, s.rules, s.campaign), mini(10, holder.command + 2), "carica: +2 al comando")
	var def := s.campaign.title_for("id_bassa")
	t.assert_true(def != null and def.display_name == "Duca di Bassa")
	t.assert_eq(s.campaign.titles.size(), 2)
	t.assert_eq(s.campaign.offices.size(), 1)


func test_la_creazione_non_tocca_il_generatore_dello_stato(t: TestContext) -> void:
	var with_dynasty := _world(11)
	var campaign := StartposLoader.load_file(PLAIN_STARTPOS)
	var plain := GameSetup.new_game(campaign, UnitProdLoader.load_file(UNITS), BuildingProdLoader.load_file(BUILDINGS), Rules.new(), 11)
	t.assert_eq(with_dynasty.rng.state, plain.rng.state, "i personaggi usano un generatore proprio")


func test_la_creazione_e_deterministica(t: TestContext) -> void:
	var a := _world(21)
	var b := _world(21)
	var c := _world(22)
	t.assert_eq(JSON.stringify(SaveGame.to_dict(a), "", true), JSON.stringify(SaveGame.to_dict(b), "", true))
	t.assert_true(JSON.stringify(SaveGame.to_dict(a), "", true) != JSON.stringify(SaveGame.to_dict(c), "", true), "un altro seme cambia i personaggi")


func test_eroi_gia_disponibili_non_compaiono_all_inizio(t: TestContext) -> void:
	var s := _world()
	for c in s.characters:
		t.assert_false(c.is_hero, "all'inizio nessun eroe")
	t.assert_eq(s.heroes_done.size(), 1, "solo l'eroe del 990 e' gia' disponibile")


# --- attributi efficaci -----------------------------------------------------------------------


func test_attributi_efficaci_con_vizi_e_limiti(t: TestContext) -> void:
	var s := _world()
	var c := s.leader_of("FN_ALPHA")
	# tyrant2: il valore esatto dipende da vizi_virtu.cfg; si controlla che sia coerente con la tabella
	var expected_dread := clampi(c.dread + s.rules.vnv.delta("tyrant", 2, Character.ATTR_DREAD), 0, 10)
	t.assert_eq(c.effective(Character.ATTR_DREAD, s.rules, s.campaign), expected_dread)
	c.command = 9
	c.title = "ID_BASSA"
	t.assert_true(c.effective(Character.ATTR_COMMAND, s.rules, s.campaign) <= 10, "mai oltre il massimo")
	c.command = 0
	c.title = ""
	c.vnv = {}
	t.assert_eq(c.effective(Character.ATTR_COMMAND, s.rules, s.campaign), 0)
	t.assert_eq(c.stars(s.rules, s.campaign), 0)


func test_valori_fissi_dei_auror(t: TestContext) -> void:
	var rules := Rules.new()
	var campaign := CampaignData.new()
	var king := Character.new(1)
	king.faction = "FN_DANISH"
	king.role = Character.ROLE_LEADER
	king.command = 2
	king.loyalty = 3
	king.influence = 4
	t.assert_eq(king.effective(Character.ATTR_COMMAND, rules, campaign), 9)
	t.assert_eq(king.stars(rules, campaign), 9)
	t.assert_eq(king.effective(Character.ATTR_LOYALTY, rules, campaign), 9)
	t.assert_eq(king.effective(Character.ATTR_INFLUENCE, rules, campaign), 9, "influenza fissa per il capo")
	var general := Character.new(2)
	general.faction = "FN_DANISH"
	general.role = Character.ROLE_GENERAL
	general.command = 0
	general.influence = 4
	t.assert_eq(general.effective(Character.ATTR_COMMAND, rules, campaign), 9, "comando 9 per tutti gli Auror")
	t.assert_eq(general.effective(Character.ATTR_INFLUENCE, rules, campaign), 4, "l'influenza fissa vale solo per il capo")
	var other := Character.new(3)
	other.faction = "FN_ALPHA"
	other.command = 2
	t.assert_eq(other.effective(Character.ATTR_COMMAND, rules, campaign), 2)


func test_maggiore_eta(t: TestContext) -> void:
	var d := DynastyRules.new()
	var boy := Character.new(1)
	boy.male = true
	boy.role = Character.ROLE_HEIR
	boy.birth_year = 1000
	t.assert_false(boy.is_adult(d, 1015))
	t.assert_true(boy.is_adult(d, 1016))
	var girl := Character.new(2)
	girl.male = false
	girl.role = Character.ROLE_PRINCESS
	girl.birth_year = 1000
	t.assert_false(girl.is_adult(d, 1014))
	t.assert_true(girl.is_adult(d, 1015))
	t.assert_false(girl.can_command(d, 1020), "le principesse non comandano")
	t.assert_true(boy.can_command(d, 1016))
	boy.alive = false
	t.assert_false(boy.can_command(d, 1016))


# --- serializzazione -------------------------------------------------------------------------------


func test_personaggio_andata_e_ritorno(t: TestContext) -> void:
	var s := _world()
	for c in s.characters:
		var d := c.to_dict()
		var parsed: Variant = JSON.parse_string(JSON.stringify(d))
		t.assert_eq(typeof(parsed), TYPE_DICTIONARY)
		var back := Character.from_dict(SimUtil.fix_numbers(parsed))
		t.assert_eq(back.to_dict(), d, "personaggio %d" % c.id)
		t.assert_eq(back.full_name(), c.full_name())


func test_dizionario_del_personaggio_usa_chiavi_italiane(t: TestContext) -> void:
	var s := _world()
	var d := s.leader_of("FN_ALPHA").to_dict()
	for key in ["id", "nome", "numerale", "fazione", "ruolo", "nascita", "sangue_reale", "comando", "terrore", "pieta", "acume", "lealta", "influenza", "vnv", "titolo", "carica", "esercito", "vivo"]:
		t.assert_true(d.has(key), "chiave %s" % key)
	t.assert_eq(d["ruolo"], Character.ROLE_LEADER)


# --- comandi -------------------------------------------------------------------------------------------


func test_assegnare_un_titolo(t: TestContext) -> void:
	var s := _world()
	var heir := s.heir_of("FN_ALPHA")
	var r := GameCommands.assign_title(s, "FN_ALPHA", heir.id, "id_alta")
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(heir.title, "ID_ALTA")
	t.assert_true(s.governor_of("ID_ALTA") == heir)
	var events := _events_of(s, GameState.EV_TITLE_CHANGED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["azione"], "assegnato")
	t.assert_eq(events[0]["personaggio"], heir.id)
	t.assert_eq(events[0]["fazione"], "FN_ALPHA")
	t.assert_eq(events[0]["regione"], "ID_ALTA")
	t.assert_true(str(events[0]["testo"]).contains(heir.full_name()))
	var again := GameCommands.assign_title(s, "FN_ALPHA", heir.id, "ID_ALTA")
	t.assert_false(bool(again["ok"]), "lo ha gia'")


func test_il_nuovo_governatore_toglie_il_titolo_al_precedente(t: TestContext) -> void:
	var s := _world()
	var old := s.governor_of("ID_BASSA")
	var old_loyalty := old.loyalty
	var heir := s.heir_of("FN_ALPHA")
	var r := GameCommands.assign_title(s, "FN_ALPHA", heir.id, "ID_BASSA")
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(old.title, "")
	t.assert_eq(old.loyalty, maxi(0, old_loyalty - s.rules.dynasty.revoke_loyalty_drop), "la revoca costa lealta'")
	t.assert_true(s.governor_of("ID_BASSA") == heir)
	t.assert_eq(_events_of(s, GameState.EV_TITLE_CHANGED).size(), 2, "revoca e assegnazione")
	# chi cambia provincia lascia la precedente senza perdere lealta'
	var loyalty := heir.loyalty
	var move := GameCommands.assign_title(s, "FN_ALPHA", heir.id, "ID_ALTA")
	t.assert_true(bool(move["ok"]), str(move["errore"]))
	t.assert_true(s.governor_of("ID_BASSA") == null)
	t.assert_eq(heir.loyalty, loyalty)


func test_titolo_rifiutato(t: TestContext) -> void:
	var s := _world()
	var heir := s.heir_of("FN_ALPHA")
	var leader := s.leader_of("FN_ALPHA")
	t.assert_false(bool(GameCommands.assign_title(s, "FN_ALPHA", leader.id, "ID_ALTA")["ok"]), "il capo non governa")
	t.assert_false(bool(GameCommands.assign_title(s, "FN_ALPHA", heir.id, "ID_MEZZA")["ok"]), "provincia di un'altra fazione")
	t.assert_false(bool(GameCommands.assign_title(s, "FN_ALPHA", heir.id, "ID_MARE_NORD")["ok"]), "zona di mare")
	t.assert_false(bool(GameCommands.assign_title(s, "FN_ALPHA", 9999, "ID_ALTA")["ok"]), "personaggio sconosciuto")
	t.assert_false(bool(GameCommands.assign_title(s, "FN_BETA", heir.id, "ID_MEZZA")["ok"]), "personaggio di un'altra fazione")
	t.assert_false(bool(GameCommands.assign_title(s, "FN_GAMMA", heir.id, "ID_ALTA")["ok"]), "fazione non attiva")
	for c in s.characters_of("FN_ALPHA"):
		if c.role == Character.ROLE_PRINCESS or c.age(s.year) < 16 and c.role != Character.ROLE_GENERAL:
			t.assert_false(bool(GameCommands.assign_title(s, "FN_ALPHA", c.id, "ID_ALTA")["ok"]), "%s non puo' governare" % c.full_name())
	heir.alive = false
	t.assert_false(bool(GameCommands.assign_title(s, "FN_ALPHA", heir.id, "ID_ALTA")["ok"]), "morto")
	t.assert_eq(_events_of(s, GameState.EV_TITLE_CHANGED).size(), 0, "nessun evento per i rifiuti")


func test_revocare_un_titolo(t: TestContext) -> void:
	var s := _world()
	var governor := s.governor_of("ID_BASSA")
	var loyalty := governor.loyalty
	var r := GameCommands.revoke_title(s, "FN_ALPHA", governor.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(r["provincia"], "ID_BASSA")
	t.assert_eq(governor.title, "")
	t.assert_eq(governor.loyalty, maxi(0, loyalty - s.rules.dynasty.revoke_loyalty_drop))
	var events := _events_of(s, GameState.EV_TITLE_CHANGED)
	t.assert_eq(events.size(), 1)
	t.assert_eq(events[0]["azione"], "revocato")
	t.assert_false(bool(GameCommands.revoke_title(s, "FN_ALPHA", governor.id)["ok"]), "non ha piu' il titolo")
	t.assert_false(bool(GameCommands.revoke_title(s, "FN_BETA", governor.id)["ok"]), "non e' di BETA")
	t.assert_false(bool(GameCommands.revoke_title(s, "FN_ALPHA", 9999)["ok"]))


func test_la_lealta_non_scende_sotto_zero(t: TestContext) -> void:
	var s := _world()
	var governor := s.governor_of("ID_BASSA")
	governor.loyalty = 1
	GameCommands.revoke_title(s, "FN_ALPHA", governor.id)
	t.assert_eq(governor.loyalty, 0)


func test_cambiare_comandante(t: TestContext) -> void:
	var s := _world()
	var bassa := _army_in(s, "FN_ALPHA", "ID_BASSA")
	var old := s.commander_of(bassa.id)
	var newcomer := _adult_general(s, "FN_ALPHA", "ID_BASSA")
	var r := GameCommands.set_commander(s, "FN_ALPHA", bassa.id, newcomer.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(r["precedente"], old.id)
	t.assert_true(s.commander_of(bassa.id) == newcomer)
	t.assert_eq(newcomer.army, bassa.id)
	t.assert_eq(old.army, 0, "il vecchio comandante resta libero")
	t.assert_eq(s.character_region(old), "ID_BASSA")
	var again := GameCommands.set_commander(s, "FN_ALPHA", bassa.id, newcomer.id)
	t.assert_false(bool(again["ok"]), "lo comanda gia'")
	# riprende il comando: i due si scambiano
	var back := GameCommands.set_commander(s, "FN_ALPHA", bassa.id, old.id)
	t.assert_true(bool(back["ok"]), str(back["errore"]))
	t.assert_true(s.commander_of(bassa.id) == old)
	t.assert_eq(newcomer.army, 0)


func test_scambio_tra_due_eserciti_nella_stessa_regione(t: TestContext) -> void:
	var s := _world()
	var first := _army_in(s, "FN_ALPHA", "ID_BASSA")
	var second := s.create_army("FN_ALPHA", "ID_BASSA", false)
	second.stacks.append(UnitStack.new("Spearmen", 10, 0))
	DynastyProcessor.ensure_commanders(s, s.rng, s.year)
	var c1 := s.commander_of(first.id)
	var c2 := s.commander_of(second.id)
	t.assert_true(c1 != null and c2 != null and c1 != c2, "il nuovo esercito riceve un comandante")
	var r := GameCommands.set_commander(s, "FN_ALPHA", first.id, c2.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_true(s.commander_of(first.id) == c2)
	t.assert_true(s.commander_of(second.id) == c1, "scambio")


func test_cambio_di_comandante_rifiutato(t: TestContext) -> void:
	var s := _world()
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	var bassa := _army_in(s, "FN_ALPHA", "ID_BASSA")
	var heir := s.heir_of("FN_ALPHA")
	var leader := s.leader_of("FN_ALPHA")
	t.assert_false(bool(GameCommands.set_commander(s, "FN_ALPHA", alta.id, heir.id)["ok"]), "il capo non si sostituisce")
	t.assert_false(bool(GameCommands.set_commander(s, "FN_ALPHA", bassa.id, heir.id)["ok"]), "in un'altra regione")
	t.assert_false(bool(GameCommands.set_commander(s, "FN_ALPHA", 9999, heir.id)["ok"]), "esercito sconosciuto")
	t.assert_false(bool(GameCommands.set_commander(s, "FN_ALPHA", bassa.id, 9999)["ok"]), "personaggio sconosciuto")
	var beta_army := _army_in(s, "FN_BETA", "ID_MEZZA")
	t.assert_false(bool(GameCommands.set_commander(s, "FN_ALPHA", beta_army.id, heir.id)["ok"]), "esercito di un'altra fazione")
	t.assert_false(bool(GameCommands.set_commander(s, "FN_BETA", bassa.id, s.leader_of("FN_BETA").id)["ok"]), "non e' di BETA")
	var minor := _adult_general(s, "FN_ALPHA", "ID_BASSA", s.year - 10)
	t.assert_false(bool(GameCommands.set_commander(s, "FN_ALPHA", bassa.id, minor.id)["ok"]), "minorenne")
	var princess: Character = null
	for c in s.characters_of("FN_ALPHA"):
		if c.role == Character.ROLE_PRINCESS:
			princess = c
	princess.region = "ID_BASSA"
	t.assert_false(bool(GameCommands.set_commander(s, "FN_ALPHA", bassa.id, princess.id)["ok"]), "principessa")
	var dead := _adult_general(s, "FN_ALPHA", "ID_BASSA")
	dead.alive = false
	t.assert_false(bool(GameCommands.set_commander(s, "FN_ALPHA", bassa.id, dead.id)["ok"]), "morto")
	t.assert_true(s.leader_of("FN_ALPHA") == leader)
	t.assert_true(s.commander_of(alta.id) == leader, "nulla e' cambiato")


func test_il_capo_puo_prendere_il_comando_di_un_altro_esercito(t: TestContext) -> void:
	var s := _world()
	var leader := s.leader_of("FN_ALPHA")
	# il capo e il comandante dell'esercito di BASSA nella stessa regione: sposto il capo con un esercito nuovo
	var bassa := _army_in(s, "FN_ALPHA", "ID_BASSA")
	leader.army = 0
	leader.region = "ID_BASSA"
	var r := GameCommands.set_commander(s, "FN_ALPHA", bassa.id, leader.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_true(s.commander_of(bassa.id) == leader)
	# ora non si puo' piu' togliergli il comando
	var other := _adult_general(s, "FN_ALPHA", "ID_BASSA")
	t.assert_false(bool(GameCommands.set_commander(s, "FN_ALPHA", bassa.id, other.id)["ok"]))


# --- cariche di Stato (AddOffice, manuale p25) --------------------------------------------------------


func _office_holder(s: GameState, building: String) -> Character:
	return DynastyProcessor.office_holder(s, "FN_ALPHA", building)


## Aggiunge una carica di prova di ALPHA legata all'edificio (che si costruisce a parte).
func _add_office(s: GameState, building: String, label: String) -> CampaignData.OfficeDef:
	var o := CampaignData.OfficeDef.new()
	o.faction = "FN_ALPHA"
	o.building = building
	o.display_name = label
	o.loyalty = 3
	o.acumen = 1
	s.campaign.offices.append(o)
	return o


func test_la_carica_compare_dove_l_edificio_e_piu_alto(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(DynastyProcessor.office_seat(s, "FN_ALPHA", "castle"), "ID_ALTA", "Castle3 in ALTA batte Castle in BASSA")
	t.assert_eq(DynastyProcessor.available_offices(s, "FN_ALPHA").size(), 1)
	_add_office(s, "royal_palace", "Cancelliere di Prova")
	t.assert_eq(DynastyProcessor.available_offices(s, "FN_ALPHA").size(), 1, "il palazzo reale non c'e'")
	s.province("ID_BASSA").set_level("ROYAL_PALACE", 1)
	t.assert_eq(DynastyProcessor.office_seat(s, "FN_ALPHA", "royal_palace"), "ID_BASSA")
	t.assert_eq(DynastyProcessor.available_offices(s, "FN_ALPHA").size(), 2)


func test_concedere_una_carica(t: TestContext) -> void:
	var s := _world()
	var old := _office_holder(s, "castle")
	t.assert_true(old != null, "carica iniziale assegnata")
	var old_loyalty := old.loyalty
	var newcomer := _adult_general(s, "FN_ALPHA", "ID_ALTA")
	var r := GameCommands.assign_office(s, "FN_ALPHA", newcomer.id, "CASTLE")
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(r["provincia"], "ID_ALTA")
	t.assert_eq(newcomer.office, "castle")
	t.assert_true(_office_holder(s, "castle") == newcomer)
	t.assert_eq(old.office, "")
	t.assert_eq(old.loyalty, maxi(0, old_loyalty - s.rules.dynasty.revoke_loyalty_drop), "la revoca costa lealta'")
	t.assert_eq(newcomer.effective(Character.ATTR_COMMAND, s.rules, s.campaign), mini(10, newcomer.command + 2), "carica: +2 al comando")
	var events := _events_of(s, GameState.EV_OFFICE_CHANGED)
	t.assert_eq(events.size(), 2, "revoca e assegnazione")
	t.assert_eq(events[0]["azione"], "revocato")
	t.assert_eq(events[1]["azione"], "assegnato")
	t.assert_eq(events[1]["personaggio"], newcomer.id)
	t.assert_eq(events[1]["edificio"], "castle")
	t.assert_true(str(events[1]["testo"]).contains(newcomer.full_name()))
	t.assert_false(bool(GameCommands.assign_office(s, "FN_ALPHA", newcomer.id, "castle")["ok"]), "la detiene gia'")


func test_una_sola_carica_a_testa(t: TestContext) -> void:
	var s := _world()
	_add_office(s, "royal_palace", "Cancelliere di Prova")
	s.province("ID_ALTA").set_level("ROYAL_PALACE", 1)
	var holder := _office_holder(s, "castle")
	var loyalty := holder.loyalty
	var r := GameCommands.assign_office(s, "FN_ALPHA", holder.id, "royal_palace")
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(holder.office, "royal_palace")
	t.assert_true(_office_holder(s, "castle") == null, "la carica di prima resta vacante")
	t.assert_eq(holder.loyalty, loyalty, "chi passa a un'altra carica non perde lealta'")
	var events := _events_of(s, GameState.EV_OFFICE_CHANGED)
	t.assert_eq(events[0]["azione"], "ceduto")


func test_carica_rifiutata(t: TestContext) -> void:
	var s := _world()
	_add_office(s, "admiralty", "Ammiraglio di Prova")
	var general := _adult_general(s, "FN_ALPHA", "ID_ALTA")
	t.assert_false(bool(GameCommands.assign_office(s, "FN_ALPHA", s.leader_of("FN_ALPHA").id, "castle")["ok"]), "il capo no")
	t.assert_false(bool(GameCommands.assign_office(s, "FN_ALPHA", general.id, "admiralty")["ok"]), "ammiragliato non costruito")
	t.assert_false(bool(GameCommands.assign_office(s, "FN_ALPHA", general.id, "cathedral")["ok"]), "carica inesistente")
	t.assert_false(bool(GameCommands.assign_office(s, "FN_BETA", general.id, "castle")["ok"]), "BETA non ha cariche")
	t.assert_false(bool(GameCommands.assign_office(s, "FN_ALPHA", 9999, "castle")["ok"]), "personaggio sconosciuto")
	var minor := _adult_general(s, "FN_ALPHA", "ID_ALTA", s.year - 10)
	t.assert_false(bool(GameCommands.assign_office(s, "FN_ALPHA", minor.id, "castle")["ok"]), "minorenne")
	for c in s.characters_of("FN_ALPHA"):
		if c.role == Character.ROLE_PRINCESS:
			t.assert_false(bool(GameCommands.assign_office(s, "FN_ALPHA", c.id, "castle")["ok"]), "principessa")
	t.assert_eq(_events_of(s, GameState.EV_OFFICE_CHANGED).size(), 0, "nessun evento per i rifiuti")


func test_revocare_una_carica(t: TestContext) -> void:
	var s := _world()
	var holder := _office_holder(s, "castle")
	var loyalty := holder.loyalty
	var r := GameCommands.revoke_office(s, "FN_ALPHA", holder.id)
	t.assert_true(bool(r["ok"]), str(r["errore"]))
	t.assert_eq(r["edificio"], "castle")
	t.assert_eq(holder.office, "")
	t.assert_eq(holder.loyalty, maxi(0, loyalty - s.rules.dynasty.revoke_loyalty_drop))
	t.assert_false(bool(GameCommands.revoke_office(s, "FN_ALPHA", holder.id)["ok"]), "non ha piu' la carica")
	t.assert_false(bool(GameCommands.revoke_office(s, "FN_BETA", holder.id)["ok"]), "non e' di BETA")
