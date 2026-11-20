extends RefCounted
## Aiuti condivisi dai test della fase 6a (test_sim_events, test_sim_events_reale): non e' un test (il nome non comincia
## per test_), si carica con preload. Mondo di prova: tests/fixtures/events_startpos.txt, il mondo del Papato (vedi
## papacy_world.gd per fazioni, strade ed eserciti) con in piu':
##   FN_ORDA (fazione inattiva: l'Orda d'Oro dei test, `rules.events.horde_faction`),
##   ID_NORD3 e ID_SUD2 immuni alle inondazioni, ID_NORD3 immune ai terremoti (cosi' il mondo ha i dati dei disastri).
## Le regole sono "quiete": nessun disastro (tutte le probabilita' a zero), tabella storica vuota, Orda d'Oro nel 1230 con
## ingresso a ID_RIBELLE (la regione dei ribelli). Ogni test accende solo cio' che prova.

const W := preload("res://tests/unit/papacy_world.gd")

const STARTPOS := "res://tests/fixtures/events_startpos.txt"
const UNITS := "res://tests/fixtures/papacy_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/papacy_build_prod.txt"

const HORDE := "FN_ORDA"


static func quiet_rules() -> Rules:
	var rules := W.quiet_rules()
	var ev := rules.events
	ev.flood_chance = 0.0
	ev.famine_chance = 0.0
	ev.quake_chance = 0.0
	ev.storm_chance = 0.0
	ev.plague_chance = 0.0
	ev.plague_spread = 0.0
	ev.black_death_spread = 0.0
	ev.black_death_sea = 0.0
	ev.horde_entry = PackedStringArray(["ID_RIBELLE"])
	ev.horde_faction = HORDE
	return rules


static func world(seed_value: int = 7) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, quiet_rules(), seed_value)
	for c in s.characters:
		c.old_age = 500
	return s


## Aggiunge un evento storico alla tabella delle regole dello stato e lo restituisce.
static func add_history(s: GameState, index: int, year_from: int, year_to: int, effect: String, value: int = 0, faction: String = "", regions: Array = [], culture: String = "", goods: Array = []) -> EventRules.HistoricalEvent:
	var e := EventRules.HistoricalEvent.new()
	e.index = index
	e.key = "prova_%d" % index
	e.year_from = year_from
	e.year_to = year_to
	e.effect = effect
	e.value = value
	e.faction = faction
	e.regions = PackedStringArray(regions)
	e.culture = culture
	e.goods = PackedStringArray(goods)
	s.rules.events.history.append(e)
	return e


static func events_of(s: GameState, kind: String) -> Array[Dictionary]:
	return W.events_of(s, kind)


## Un fine anno degli eventi: registro azzerato, poi `EventProcessor.process_year`.
static func run_year(s: GameState) -> void:
	s.events.clear()
	EventProcessor.process_year(s)


## Uomini di tutti gli eserciti (flotte comprese).
static func men(s: GameState) -> int:
	var total := 0
	for a in s.armies:
		total += a.men_total()
	return total
