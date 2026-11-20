extends RefCounted
## Test della logica pura dell'interfaccia della fase 4 (personaggi e province): testi dei
## personaggi, sezioni della corte, comandante dell'esercito, governatore, lealtà e righe del
## resoconto di fine anno. Mondo di prova: tests/fixtures/dynasty_startpos.txt + dynasty_heroes.txt
## (ALPHA: capo Edward I, erede di 20 anni e fratello di 10, principessa di 8, titolo «Duca di Bassa»
## su ID_BASSA). Gli eventi sono costruiti a mano: i test non dipendono dal blocco 4b (lealtà,
## rivolte); i nomi delle sue costanti si leggono con CampaignUiText.event_kind.

const STARTPOS := "res://tests/fixtures/dynasty_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const HEROES := "res://tests/fixtures/dynasty_heroes.txt"
const PLAIN_STARTPOS := "res://tests/fixtures/sim_startpos.txt"


## Provincia di prova con i campi della lealtà come oggetto (non Dictionary).
class FakeProvince:
	var loyalty := 90
	var loyalty_target := 95.0


func _world(seed_value: int = 7) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), seed_value, HeroesLoader.load_file(HEROES))


func _plain_world() -> GameState:
	var campaign := StartposLoader.load_file(PLAIN_STARTPOS)
	return GameSetup.new_game(campaign, UnitProdLoader.load_file(UNITS), BuildingProdLoader.load_file(BUILDINGS), Rules.new(), 3)


func _army_in(s: GameState, faction: String, region: String) -> Army:
	for a in s.armies_of(faction):
		if a.region == region and not a.is_fleet:
			return a
	return null


func _ev(kind: String, data: Dictionary) -> Dictionary:
	var e := {"tipo": kind, "anno": 1000}
	e.merge(data)
	return e


## Generale adulto di ALPHA nella regione indicata, senza esercito.
func _general(s: GameState, region: String, forename: String) -> Character:
	var c := s.create_character("FN_ALPHA")
	c.role = Character.ROLE_GENERAL
	c.forename = forename
	c.birth_year = 960
	c.loyalty = 6
	c.region = region
	return c


# --- etichette e numeri ---------------------------------------------------------------


func test_stelle_ruoli_e_numeri(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.stars_text(0), "0 stelle")
	t.assert_eq(CampaignUiText.stars_text(1), "1 stella")
	t.assert_eq(CampaignUiText.stars_text(3), "3 stelle")
	t.assert_eq(CampaignUiText.role_label(Character.ROLE_LEADER), "Capo")
	t.assert_eq(CampaignUiText.role_label(Character.ROLE_HEIR), "Erede")
	t.assert_eq(CampaignUiText.role_label(Character.ROLE_PRINCE), "Principe")
	t.assert_eq(CampaignUiText.role_label(Character.ROLE_PRINCESS), "Principessa")
	t.assert_eq(CampaignUiText.role_label(Character.ROLE_GENERAL), "Generale")
	t.assert_eq(CampaignUiText.attr_label(Character.ATTR_PIETY), "Pietà")
	t.assert_eq(CampaignUiText.number_text(5), "5")
	t.assert_eq(CampaignUiText.number_text(92.0), "92")
	t.assert_eq(CampaignUiText.number_text(5.5), "5.5")
	t.assert_eq(CampaignUiText.number_text(10, true), "+10")
	t.assert_eq(CampaignUiText.number_text(-3, true), "-3")
	t.assert_eq(CampaignUiText.number_text(7.0, true), "+7")
	t.assert_eq(CampaignUiText.term_label("tax"), "Tassa")
	t.assert_eq(CampaignUiText.term_label("REBELS"), "Ribellione regionale")
	t.assert_eq(CampaignUiText.term_label("custom_thing"), "Custom Thing")


# --- lealtà della provincia (nomi opzionali della fase 4b) ------------------------------


func test_lealta_con_obiettivo_e_termini(t: TestContext) -> void:
	var province := {"loyalty": 80, "loyalty_target": 92.0, "loyalty_terms": {"base": 60, "tax": 10, "rebels": -5}}
	var expected := PackedStringArray([
		"Lealtà: 80 · obiettivo 92",
		"Termini dell'obiettivo:",
		"  Base: +60",
		"  Tassa: +10",
		"  Ribellione regionale: -5",
		"Sotto 100 la provincia rischia la rivolta.",
	])
	t.assert_eq(CampaignUiText.loyalty_lines(province), expected, "\n".join(CampaignUiText.loyalty_lines(province)))


func test_lealta_termini_come_elenco(t: TestContext) -> void:
	var province := {"lealta": 100, "lealta_obiettivo": 100, "lealta_termini": [{"nome": "garrison", "valore": 16}, ["buildings", 4], {"nome": "senza valore"}, "rumore"]}
	var lines := CampaignUiText.loyalty_lines(province)
	t.assert_eq(lines, PackedStringArray([
		"Lealtà: 100 · obiettivo 100",
		"Termini dell'obiettivo:",
		"  Guarnigione: +16",
		"  Edifici: +4",
	]), "\n".join(lines))


func test_lealta_solo_obiettivo_o_solo_corrente(t: TestContext) -> void:
	t.assert_eq(CampaignUiText.loyalty_lines({"loyalty_target": 70}), PackedStringArray(["Lealtà obiettivo: 70"]))
	t.assert_eq(CampaignUiText.loyalty_lines({"loyalty": 120}), PackedStringArray(["Lealtà: 120"]))


func test_lealta_non_esposta_non_produce_righe(t: TestContext) -> void:
	t.assert_true(CampaignUiText.loyalty_lines({}).is_empty())
	t.assert_true(CampaignUiText.loyalty_lines({"tax_level": 2}).is_empty())
	t.assert_true(CampaignUiText.loyalty_lines(null).is_empty())
	t.assert_true(CampaignUiText.loyalty_terms_of(null).is_empty())
	t.assert_true(CampaignUiText.loyalty_terms_of("testo").is_empty())


func test_lealta_da_oggetto(t: TestContext) -> void:
	var lines := CampaignUiText.loyalty_lines(FakeProvince.new())
	t.assert_eq(lines[0], "Lealtà: 90 · obiettivo 95")
	t.assert_eq(lines.size(), 2, "senza termini restano la riga e l'avviso sotto 100")


# --- personaggi e corte ---------------------------------------------------------------------


func test_righe_del_capo(t: TestContext) -> void:
	var s := _world()
	var leader := s.leader_of("FN_ALPHA")
	var lines := CampaignUiText.character_lines(s, leader)
	t.assert_eq(lines[0], "Edward I — capo, %d anni" % leader.age(s.year))
	t.assert_true(lines[1].begins_with("  Comando 3 stelle · Terrore "), lines[1])
	t.assert_true(lines[1].contains("Pietà 3 · Acume 4"), lines[1])
	t.assert_true(lines[1].ends_with("Influenza 5"), lines[1])
	t.assert_false(lines[1].contains("Lealtà"), "il capo non mostra la lealtà")
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	t.assert_true(lines.has("  Esercito: Esercito %d (Alta)" % alta.id), "\n".join(lines))
	t.assert_eq(lines[lines.size() - 1], "  Vizi e virtù: Autocrate")


func test_sezioni_della_corte(t: TestContext) -> void:
	var s := _world()
	var sections := CampaignUiText.court_sections(s, "FN_ALPHA")
	var titles := PackedStringArray()
	for sec in sections:
		titles.append(str(sec["titolo"]))
	t.assert_eq(titles, PackedStringArray(["Capo", "Erede", "Principi", "Principesse", "Generali"]))
	var roles := [Character.ROLE_LEADER, Character.ROLE_HEIR, Character.ROLE_PRINCE, Character.ROLE_PRINCESS, Character.ROLE_GENERAL]
	for i in range(sections.size()):
		var expected := 0
		for c in s.characters_of("FN_ALPHA"):
			if c.role == roles[i]:
				expected += 1
		var entries: Array = sections[i]["voci"]
		t.assert_eq(entries.size(), maxi(1, expected), "voci della sezione %s" % titles[i])
	var leader_entries: Array = sections[0]["voci"]
	var leader_entry: Dictionary = leader_entries[0]
	t.assert_eq(int(leader_entry["personaggio"]), s.leader_of("FN_ALPHA").id)
	t.assert_true(int(leader_entry["esercito"]) > 0, "il capo comanda un esercito")
	t.assert_true(str(leader_entry["testo"]).begins_with("Edward I — capo"))


func test_erede_designato_e_principessa(t: TestContext) -> void:
	var s := _world()
	var sections := CampaignUiText.court_sections(s, "FN_ALPHA")
	var heirs: Array = sections[1]["voci"]
	t.assert_eq(heirs.size(), 2, "erede di 20 anni e fratello di 10")
	var first: Dictionary = heirs[0]
	var second: Dictionary = heirs[1]
	t.assert_true(str(first["testo"]).contains("20 anni"), str(first["testo"]))
	t.assert_true(str(first["testo"]).contains("erede designato"))
	t.assert_true(str(first["testo"]).contains("sangue reale"))
	t.assert_true(str(second["testo"]).contains("10 anni"), str(second["testo"]))
	t.assert_false(str(second["testo"]).contains("erede designato"))
	var princesses: Array = sections[3]["voci"]
	var princess: Dictionary = princesses[0]
	t.assert_true(str(princess["testo"]).contains("principessa, 8 anni"), str(princess["testo"]))
	t.assert_eq(int(princess["esercito"]), 0)


func test_generale_con_titolo_ed_esercito(t: TestContext) -> void:
	var s := _world()
	var governor := s.governor_of("ID_BASSA")
	t.assert_true(governor != null)
	var found: Dictionary = {}
	for sec in CampaignUiText.court_sections(s, "FN_ALPHA"):
		var entries: Array = sec["voci"]
		for entry in entries:
			var data: Dictionary = entry
			if int(data["personaggio"]) == governor.id:
				found = data
	t.assert_false(found.is_empty(), "il governatore di BASSA è nella corte")
	var text := str(found["testo"])
	t.assert_true(text.contains("Titolo: Duca di Bassa"), text)
	t.assert_true(text.contains("Lealtà "), text)
	t.assert_eq(int(found["esercito"]), governor.army, "il pulsante porta all'esercito comandato")
	t.assert_true(text.contains("Esercito: Esercito %d (Bassa)" % governor.army), text)


func test_senza_dinastia_nessun_personaggio(t: TestContext) -> void:
	var s := _plain_world()
	for sec in CampaignUiText.court_sections(s, "FN_ALPHA"):
		var entries: Array = sec["voci"]
		t.assert_eq(entries.size(), 1)
		var entry: Dictionary = entries[0]
		t.assert_eq(int(entry["personaggio"]), 0, "solo il segnaposto «nessuno»")
	var army := s.create_army("FN_ALPHA", "ID_ALTA", false)
	t.assert_true(CampaignUiText.commander_lines(s, army).is_empty())
	t.assert_true(CampaignUiText.governor_lines(s, "ID_ALTA").is_empty())
	t.assert_true(CampaignUiText.eligible_commanders(s, army).is_empty())


# --- comandante dell'esercito ----------------------------------------------------------------


func test_comandante_nel_pannello_dell_esercito(t: TestContext) -> void:
	var s := _world()
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	var lines := CampaignUiText.commander_lines(s, alta)
	t.assert_eq(lines.size(), 2)
	t.assert_true(lines[0].begins_with("Comandante: Edward I (capo, "), lines[0])
	t.assert_true(lines[0].ends_with("— 3 stelle"), lines[0])
	t.assert_true(lines[1].begins_with("  Comando 3 stelle · Terrore "), lines[1])
	t.assert_false(lines[1].contains("Pietà"), "nel pannello dell'esercito gli attributi sono quelli principali")
	var orphan := s.create_army("FN_ALPHA", "ID_ALTA", false)
	t.assert_eq(CampaignUiText.commander_lines(s, orphan), PackedStringArray(["Comandante: nessuno"]))


func test_comandanti_idonei(t: TestContext) -> void:
	var s := _world()
	var bassa := _army_in(s, "FN_ALPHA", "ID_BASSA")
	var current := s.commander_of(bassa.id)
	var fresh := _general(s, "ID_BASSA", "Nuovo")
	var minor := _general(s, "ID_BASSA", "Giovane")
	minor.birth_year = s.year - 10
	var princess := _general(s, "ID_BASSA", "Principessa")
	princess.role = Character.ROLE_PRINCESS
	princess.male = false
	var elsewhere := _general(s, "ID_ALTA", "Lontano")
	var dead := _general(s, "ID_BASSA", "Morto")
	dead.alive = false
	var eligible := CampaignUiText.eligible_commanders(s, bassa)
	t.assert_true(eligible.has(fresh), "adulto nella stessa regione")
	t.assert_false(eligible.has(current), "il comandante attuale non si propone")
	t.assert_false(eligible.has(minor), "minorenne")
	t.assert_false(eligible.has(princess), "principessa")
	t.assert_false(eligible.has(elsewhere), "regione diversa")
	t.assert_false(eligible.has(dead), "morto")
	var alta := _army_in(s, "FN_ALPHA", "ID_ALTA")
	t.assert_true(CampaignUiText.eligible_commanders(s, alta).is_empty(), "l'esercito del capo non si cambia")
	t.assert_true(CampaignUiText.commander_option_text(s, fresh).begins_with("Nuovo · "), CampaignUiText.commander_option_text(s, fresh))
	t.assert_true(CampaignUiText.commander_option_text(s, current).contains("(guida l'esercito %d)" % bassa.id))


# --- governatore ---------------------------------------------------------------------------------


func test_governatore_della_provincia(t: TestContext) -> void:
	var s := _world()
	var governor := s.governor_of("ID_BASSA")
	var lines := CampaignUiText.governor_lines(s, "ID_BASSA")
	t.assert_true(lines[0].begins_with("Governatore: %s (" % governor.full_name()), lines[0])
	t.assert_eq(lines[1], "  Titolo: Duca di Bassa")
	t.assert_true(lines[2].contains("acume"), lines[2])
	t.assert_eq(CampaignUiText.governor_lines(s, "ID_ALTA"), PackedStringArray(["Governatore: nessuno"]))
	t.assert_true(CampaignUiText.governor_lines(s, "ID_SOLA").is_empty(), "i ribelli non hanno dinastia")


func test_governatori_idonei(t: TestContext) -> void:
	var s := _world()
	var governor := s.governor_of("ID_BASSA")
	var fresh := _general(s, "ID_ALTA", "Nuovo")
	var minor := _general(s, "ID_ALTA", "Giovane")
	minor.birth_year = s.year - 10
	var alta := s.province("ID_ALTA")
	var candidates := CampaignUiText.eligible_governors(s, alta)
	t.assert_true(candidates.has(fresh))
	t.assert_true(candidates.has(governor), "chi governa un'altra provincia si può spostare")
	t.assert_false(candidates.has(s.leader_of("FN_ALPHA")), "il capo non governa")
	t.assert_false(candidates.has(minor))
	for c in candidates:
		t.assert_true(c.faction == "FN_ALPHA" and c.alive, "solo personaggi vivi della fazione")
	t.assert_true(CampaignUiText.governor_option_text(s, governor).ends_with("(governa Bassa)"), CampaignUiText.governor_option_text(s, governor))
	var bassa := s.province("ID_BASSA")
	t.assert_false(CampaignUiText.eligible_governors(s, bassa).has(governor), "il governatore attuale non si ripropone")


## Richiesta di Federico del 20/11/2026: prima i presenti nella provincia, chi ha gia' un titolo segnato.
func test_scelte_del_governatore_prima_i_presenti(t: TestContext) -> void:
	var s := _world()
	var governor := s.governor_of("ID_BASSA")
	var away := _general(s, "ID_BASSA", "Lontano")
	var here_titled := governor
	here_titled.army = 0
	here_titled.region = "ID_ALTA"
	var here := _general(s, "ID_ALTA", "Presente")
	here.acumen = 1
	var sharp := _general(s, "ID_ALTA", "Acuto")
	sharp.acumen = 8
	var choices := CampaignUiText.governor_choices(s, s.province("ID_ALTA"))
	var ids: Array = []
	for ch in choices:
		ids.append((ch["personaggio"] as Character).id)
	t.assert_eq(ids.size(), CampaignUiText.eligible_governors(s, s.province("ID_ALTA")).size(), "tutti gli idonei")
	t.assert_true(ids.find(sharp.id) < ids.find(here.id), "senza titolo, per acume")
	t.assert_true(ids.find(here.id) < ids.find(here_titled.id), "chi governa gia' dopo chi e' libero")
	t.assert_true(bool(choices[ids.find(here_titled.id)]["titolato"]), "il governatore di Bassa e' segnato")
	t.assert_false(bool(choices[ids.find(sharp.id)]["titolato"]))
	var last_here := -1
	var first_away := ids.size()
	for i in choices.size():
		if bool(choices[i]["qui"]):
			last_here = i
		else:
			first_away = mini(first_away, i)
	t.assert_true(bool(choices[ids.find(here_titled.id)]["qui"]) and not bool(choices[ids.find(away.id)]["qui"]))
	t.assert_true(last_here < first_away, "prima tutti i presenti, poi chi sta altrove")


# --- testi degli eventi della corte ------------------------------------------------------------


func test_testi_degli_eventi_della_corte(t: TestContext) -> void:
	var s := _world()
	var f := func(kind: String, data: Dictionary) -> String:
		return CampaignUiText.format_event(s, _ev(kind, data))
	t.assert_eq(f.call(GameState.EV_BIRTH, {"nome": "Edmund", "ruolo": "erede"}), "Nasce Edmund, erede al trono.")
	t.assert_eq(f.call(GameState.EV_BIRTH, {"nome": "Herleva", "ruolo": "principessa"}), "Nasce Herleva, principessa.")
	t.assert_eq(f.call(GameState.EV_COMING_OF_AGE, {"nome": "Edmund", "ruolo": "principe", "eta": 16}), "Edmund compie 16 anni ed è maggiorenne.")
	t.assert_eq(f.call(GameState.EV_COMING_OF_AGE, {"nome": "Herleva", "ruolo": "principessa", "eta": 15}), "Herleva compie 15 anni ed è in età da marito.")
	t.assert_eq(f.call(GameState.EV_DEATH, {"nome": "Edward I", "ruolo": "capo", "eta": 52, "causa": "vecchiaia"}), "Muore Edward I (capo, 52 anni) di vecchiaia.")
	t.assert_eq(f.call(GameState.EV_DEATH, {"nome": "Herleva", "ruolo": "principessa", "eta": 32, "causa": "ritiro"}), "Herleva si ritira a vita privata (32 anni).")
	t.assert_eq(f.call(GameState.EV_DEATH, {"nome": "Guy", "ruolo": "generale", "eta": 40, "causa": "estinzione"}), "Muore Guy (generale, 40 anni) con l'estinzione della dinastia.")
	t.assert_eq(f.call(GameState.EV_SUCCESSION, {"nome": "Edmund", "precedente_nome": "Edward I", "per_eredita": true}), "Edmund sale al trono dopo Edward I (erede).")
	t.assert_eq(f.call(GameState.EV_SUCCESSION, {"nome": "Guy", "precedente_nome": "Edward I", "per_eredita": false, "contendenti": 2}), "Guy sale al trono dopo Edward I (senza erede maggiorenne: altri 2 contendenti).")
	t.assert_eq(f.call(GameState.EV_HERO_APPEARS, {"nome": "Guy Senzaterra", "regione": "ID_BASSA"}), "Compare l'eroe Guy Senzaterra a Bassa.")
	t.assert_eq(f.call(GameState.EV_VNV_GAINED, {"nome": "Edward I", "catena": "tyrant", "livello": 2}), "Edward I ottiene Autocrate.")
	t.assert_eq(f.call(GameState.EV_STAR_CHANGED, {"nome": "Guy", "stelle_prima": 2, "stelle_dopo": 3, "motivo": "vittoria"}), "Guy guadagna una stella di comando dopo la vittoria (ora 3 stelle).")
	t.assert_eq(f.call(GameState.EV_STAR_CHANGED, {"nome": "Guy", "stelle_prima": 2, "stelle_dopo": 1, "motivo": "sconfitta"}), "Guy perde una stella di comando dopo la sconfitta (ora 1 stella).")


func test_testi_dei_titoli(t: TestContext) -> void:
	var s := _world()
	var give := _ev(GameState.EV_TITLE_CHANGED, {"nome": "Guy", "azione": "assegnato", "provincia": "ID_BASSA", "titolo": "Duca di Bassa"})
	t.assert_eq(CampaignUiText.format_event(s, give), "Guy riceve il titolo di Duca di Bassa.")
	var revoked := _ev(GameState.EV_TITLE_CHANGED, {"nome": "Guy", "azione": "revocato", "provincia": "ID_BASSA", "titolo": "Duca di Bassa"})
	t.assert_eq(CampaignUiText.format_event(s, revoked), "Il titolo di Duca di Bassa è revocato a Guy.")
	var lost := _ev(GameState.EV_TITLE_CHANGED, {"nome": "Guy", "azione": "perso", "provincia": "ID_ALTA", "titolo": "Conte"})
	t.assert_eq(CampaignUiText.format_event(s, lost), "Guy perde il titolo di Conte (Alta).", "la provincia si aggiunge se il titolo non la nomina")
	var unnamed := _ev(GameState.EV_TITLE_CHANGED, {"nome": "Guy", "azione": "ceduto", "provincia": "ID_BASSA"})
	t.assert_eq(CampaignUiText.format_event(s, unnamed), "Guy lascia il titolo di Duca di Bassa.", "il nome del titolo viene dalla campagna")


func test_estinzione_e_ripiego_sul_testo(t: TestContext) -> void:
	var s := _world()
	var one := _ev(GameState.EV_FACTION_EXTINCT, {"fazione": "FN_GAMMA", "province": ["ID_SOLA"]})
	t.assert_eq(CampaignUiText.format_event(s, one), "La dinastia di Gamma si estingue senza eredi: 1 provincia diventa ribelle.")
	var many := _ev(GameState.EV_FACTION_EXTINCT, {"fazione": "FN_GAMMA", "province": ["ID_SOLA", "ID_ALTA"]})
	t.assert_eq(CampaignUiText.format_event(s, many), "La dinastia di Gamma si estingue senza eredi: 2 province diventano ribelli.")
	# Senza i campi essenziali si usa il campo "testo" della simulazione.
	var birth := _ev(GameState.EV_BIRTH, {"testo": "Nasce qualcuno."})
	t.assert_eq(CampaignUiText.format_event(s, birth), "Nasce qualcuno.")
	var death := _ev(GameState.EV_DEATH, {"testo": "Qualcuno muore."})
	t.assert_eq(CampaignUiText.format_event(s, death), "Qualcuno muore.")
	var star := _ev(GameState.EV_STAR_CHANGED, {"nome": "Guy", "testo": "Guy cambia."})
	t.assert_eq(CampaignUiText.format_event(s, star), "Guy cambia.", "mancano le stelle prima e dopo")


# --- testi degli eventi delle province (nomi della 4b letti con event_kind) -----------------------


func test_testi_degli_eventi_delle_province(t: TestContext) -> void:
	var s := _world()
	var low := _ev(CampaignUiText.event_kind("EV_LOYALTY_LOW"), {"fazione": "FN_ALPHA", "regione": "ID_BASSA", "lealta": 42})
	t.assert_eq(CampaignUiText.format_event(s, low), "Lealtà bassa a Bassa: 42.")
	var revolt := _ev(CampaignUiText.event_kind("EV_REBELLION"), {"fazione": "FN_REBEL", "regione": "ID_MEZZA", "uomini": 120})
	t.assert_eq(CampaignUiText.format_event(s, revolt), "Rivolta a Mezza (120 ribelli).")
	var taken := _ev(CampaignUiText.event_kind("EV_REBELLION"), {"regione": "ID_MEZZA", "conquistata": true})
	t.assert_eq(CampaignUiText.format_event(s, taken), "Rivolta a Mezza: la provincia passa ai ribelli.")
	var spread := _ev(CampaignUiText.event_kind("EV_REBELLION_SPREAD"), {"regione": "ID_ALTA", "da": "ID_BASSA"})
	t.assert_eq(CampaignUiText.format_event(s, spread), "Rivolta propagata da Bassa a Alta.")
	var back := _ev(CampaignUiText.event_kind("EV_FACTION_REEMERGED"), {"fazione": "FN_GAMMA", "regione": "ID_SOLA"})
	t.assert_eq(CampaignUiText.format_event(s, back), "Gamma riemerge a Sola.")
	var civil := _ev(CampaignUiText.event_kind("EV_CIVIL_WAR"), {"fazione": "FN_ALPHA", "generali": [3, 4]})
	t.assert_eq(CampaignUiText.format_event(s, civil), "Guerra civile di Alpha: 2 generali passano ai ribelli.")
	var only_text := _ev(CampaignUiText.event_kind("EV_REBELLION"), {"testo": "Scoppia una rivolta."})
	t.assert_eq(CampaignUiText.format_event(s, only_text), "Scoppia una rivolta.", "senza luogo si usa il testo della simulazione")


# --- resoconto di fine anno -----------------------------------------------------------------------


func test_sezioni_del_resoconto(t: TestContext) -> void:
	var titles := PackedStringArray()
	for sec in CampaignUiText.report_sections():
		titles.append(str(sec["titolo"]))
	t.assert_eq(titles, PackedStringArray(["Battaglie", "Conquiste", "Assedi", "Ritirate e catture", "Fazioni distrutte", "Guerre dichiarate", "Corte", "Province"]))
	var court: PackedStringArray = CampaignUiText.phase4_sections()[0]["tipi"]
	t.assert_eq(court.size(), 9, "con le cariche di Stato (EV_OFFICE_CHANGED)")
	t.assert_true(court.has(GameState.EV_BIRTH) and court.has(GameState.EV_STAR_CHANGED) and court.has(GameState.EV_OFFICE_CHANGED))
	var provinces: PackedStringArray = CampaignUiText.phase4_sections()[1]["tipi"]
	t.assert_true(provinces.has(GameState.EV_FACTION_EXTINCT))
	t.assert_true(CampaignUiText.always_reported_kinds().has(GameState.EV_FACTION_EXTINCT))


func test_resoconto_con_corte_e_province(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	s.events.append(_ev(GameState.EV_BIRTH, {"fazione": "FN_ALPHA", "nome": "Edmund", "ruolo": "erede"}))
	s.events.append(_ev(GameState.EV_BIRTH, {"fazione": "FN_BETA", "nome": "Henry", "ruolo": "erede"}))
	s.events.append(_ev(CampaignUiText.event_kind("EV_LOYALTY_LOW"), {"fazione": "FN_ALPHA", "regione": "ID_BASSA", "lealta": 42}))
	s.events.append(_ev(GameState.EV_FACTION_EXTINCT, {"fazione": "FN_GAMMA", "province": ["ID_SOLA"]}))
	s.events.append({"tipo": GameState.EV_MOVED, "anno": 1000, "fazione": "FN_ALPHA", "esercito": 2, "da": "ID_ALTA", "a": "ID_BASSA"})
	var result := {"ok": true, "avvisi": [], "errori": []}
	var lines := CampaignUiText.year_report(s, "fn_alpha", result)
	var expected := PackedStringArray([
		"— Corte —",
		"  Nasce Edmund, erede al trono.",
		"— Province —",
		"  Lealtà bassa a Bassa: 42.",
		"  La dinastia di Gamma si estingue senza eredi: 1 provincia diventa ribelle.",
		"— Altri eventi —",
		"Esercito 2: da Alta a Bassa.",
	])
	t.assert_eq(lines, expected, "\n".join(lines))
	var beta_lines := CampaignUiText.year_report(s, "FN_BETA", result)
	t.assert_eq(beta_lines, PackedStringArray([
		"— Corte —",
		"  Nasce Henry, erede al trono.",
		"— Province —",
		"  La dinastia di Gamma si estingue senza eredi: 1 provincia diventa ribelle.",
	]), "\n".join(beta_lines))


func test_resoconto_delle_fasi_precedenti_resta_uguale(t: TestContext) -> void:
	var s := _world()
	s.events.clear()
	s.events.append({"tipo": GameState.EV_MOVED, "anno": 1000, "fazione": "FN_ALPHA", "esercito": 2, "da": "ID_ALTA", "a": "ID_BASSA"})
	s.events.append(_ev(GameState.EV_BIRTH, {"fazione": "FN_BETA", "nome": "Henry", "ruolo": "erede"}))
	var lines := CampaignUiText.year_report(s, "FN_ALPHA", {"ok": true, "avvisi": [], "errori": []})
	t.assert_eq(lines, PackedStringArray(["Esercito 2: da Alta a Bassa."]), "gli eventi altrui non creano intestazioni")


func test_resoconto_di_anni_veri_non_ha_righe_grezze(t: TestContext) -> void:
	var s := _world()
	var raw_kinds := PackedStringArray([GameState.EV_BIRTH, GameState.EV_COMING_OF_AGE, GameState.EV_DEATH, GameState.EV_SUCCESSION, GameState.EV_FACTION_EXTINCT, GameState.EV_HERO_APPEARS, GameState.EV_VNV_GAINED, GameState.EV_TITLE_CHANGED, GameState.EV_STAR_CHANGED])
	var court_lines := 0
	for i in range(40):
		var result := TurnProcessor.end_year(s)
		for faction in ["FN_ALPHA", "FN_BETA"]:
			for line in CampaignUiText.year_report(s, faction, result):
				var plain := line.strip_edges()
				t.assert_false(raw_kinds.has(plain), "riga grezza: %s" % plain)
				if plain.begins_with("Nasce") or plain.begins_with("Muore") or plain.contains("sale al trono"):
					court_lines += 1
	t.assert_true(court_lines > 0, "in 40 anni la corte vede almeno una nascita, una morte o una successione")
