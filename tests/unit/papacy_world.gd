extends RefCounted
## Aiuti condivisi dai test della fase 5c (test_sim_papacy, test_sim_crusade, test_sim_papacy_reale): non e' un test
## (il nome non comincia per test_), si carica con preload. Mondo di prova: tests/fixtures/papacy_startpos.txt.
##   Fazioni: FN_ALPHA (cattolica, NORD1 NORD2 NORD3), FN_GAMMA (cattolica, EST), FN_DELTA (cattolica, DELTA1),
##   FN_PAPIST (il Papato, cattolico, ROMA), FN_BETA (musulmana, SUD1 SUD2), ribelli in RIBELLE (cultura pagana).
##   Strade: ROMA - NORD1 - NORD2 - NORD3; NORD1 - EST - DELTA1; NORD2 - SUD1 - SUD2; EST - RIBELLE - SUD1.
##   ALPHA ha CHAPTER_HOUSE e Castle3 a NORD1 (puo' bandire una crociata); BETA ha RIBAT e Castle2 a SUD1 (jihad).
##   Eserciti iniziali: uno per regione (capo di ogni fazione al comando nella sua regione: ALPHA a NORD1, BETA a
##   SUD1, GAMMA a EST, DELTA a DELTA1, PAPIST a ROMA), trovati con `land_army`.
##   Truppe: Spearmen 100, Halberdiers 200 (Castle2), Chevaliers 400 (Castle3), Nizari 250 (solo BETA),
##   Templars 500 e Hospitallers 450 (ALPHA, GAMMA; ordini militari, CHAPTER_HOUSE), Catapult (artiglieria, mai scelta).

const STARTPOS := "res://tests/fixtures/papacy_startpos.txt"
const UNITS := "res://tests/fixtures/papacy_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/papacy_build_prod.txt"

const A := "FN_ALPHA"
const B := "FN_BETA"
const G := "FN_GAMMA"
const D := "FN_DELTA"
const P := "FN_PAPIST"
const ROMA := "ID_ROMA"
const NORD1 := "ID_NORD1"
const NORD2 := "ID_NORD2"
const NORD3 := "ID_NORD3"
const EST := "ID_EST"
const DELTA1 := "ID_DELTA1"
const SUD1 := "ID_SUD1"
const SUD2 := "ID_SUD2"
const RIBELLE := "ID_RIBELLE"


## Regole "quiete": nessun sorteggio di rivolte, nascite, catture o doni (le morti per vecchiaia si evitano con
## `old_age` dei personaggi). I test che provano un sorteggio lo accendono.
static func quiet_rules() -> Rules:
	var rules := Rules.new()
	rules.province.calm()
	rules.dynasty.birth_chance = 0.0
	rules.agents.capture_max = 0.0
	rules.papacy.gift_chance = 0.0
	return rules


static func world(seed_value: int = 7) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, quiet_rules(), seed_value)
	for c in s.characters:
		c.old_age = 500
	return s


static func land_army(s: GameState, faction_id: String, region_id: String) -> Army:
	for a in s.armies_in(region_id):
		if a.faction == faction_id and not a.is_fleet:
			return a
	return null


static func events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


## Esercito crociato (crociata o jihad) con `stacks` pile di `unit_id` nella regione, zelo iniziale e il bersaglio dato.
static func add_crusade(s: GameState, faction_id: String, region_id: String, kind: String = "crociata", target: String = "", stacks: int = 4, unit_id: String = "Spearmen") -> Army:
	var a := s.create_army(faction_id, region_id, false)
	for i in stacks:
		a.stacks.append(UnitStack.new(unit_id, 50, 0))
	a.crusade = PapacyProcessor.new_crusade(s, kind)
	a.crusade["bersaglio"] = target
	a.crusade["annunciato"] = target
	return a


static func add_agent(s: GameState, faction_id: String, region_id: String, type_name: String) -> AgentState:
	var a := s.create_agent(faction_id, region_id, type_name.capitalize(), type_name, 0)
	a.valour = 1
	a.name = "Prova"
	return a


## Toglie tutti gli eserciti della fazione (per lasciare una provincia senza difensori).
static func remove_armies(s: GameState, faction_id: String) -> void:
	for a in s.armies_of(faction_id):
		s.remove_army(a)


## Capo della fazione (maggiorenne, vivo) con l'influenza data.
static func set_influence(s: GameState, faction_id: String, value: int) -> Character:
	var c := s.leader_of(faction_id)
	c.influence = value
	return c


## Controlli di coerenza validi in ogni momento della partita (fase 5c).
static func check_state(t: TestContext, s: GameState, label: String) -> void:
	var crusades := {}
	for f in s.factions:
		if f.excommunicated:
			t.assert_true(PapacyProcessor.is_catholic(s, f.id), "%s: %s e' scomunicata ma non cattolica" % [label, f.id])
			t.assert_true(f.alive, "%s: %s e' scomunicata ma non viva" % [label, f.id])
			t.assert_true(f.excommunication_year > 0, "%s: %s scomunicata senza anno" % [label, f.id])
		else:
			t.assert_eq(f.excommunication_leader, 0, "%s: %s non scomunicata ma con un capo di scomunica" % [label, f.id])
	for a in s.armies:
		if not a.is_crusade():
			continue
		var kind := a.crusade_kind()
		t.assert_true(kind == PapacyProcessor.KIND_CRUSADE or kind == PapacyProcessor.KIND_JIHAD, "%s: esercito %d con genere '%s'" % [label, a.id, kind])
		t.assert_true(a.faction != GameState.REBEL and not a.is_fleet, "%s: esercito crociato %d dei ribelli o flotta" % [label, a.id])
		var religion := ReligionProcessor.faction_religion(s, a.faction)
		t.assert_eq(religion, PapacyProcessor.kind_religion(kind), "%s: %s dell'esercito %d ha la religione sbagliata" % [label, a.faction, a.id])
		var zeal := int(a.crusade.get("zelo", -1))
		t.assert_true(zeal >= 0 and zeal <= 100, "%s: zelo %d dell'esercito %d fuori scala" % [label, zeal, a.id])
		t.assert_true(a.stacks.size() <= PapacyProcessor.crusade_stack_limit(s), "%s: esercito %d con troppe pile" % [label, a.id])
		var target := a.crusade_target()
		t.assert_true(target == "" or s.province(target) != null, "%s: bersaglio sconosciuto '%s'" % [label, target])
		if kind == PapacyProcessor.KIND_CRUSADE:
			crusades[a.faction] = int(crusades.get(a.faction, 0)) + 1
			t.assert_true(int(crusades[a.faction]) <= 1, "%s: %s ha piu' di una crociata attiva" % [label, a.faction])
			t.assert_false(PapacyProcessor.is_excommunicated(s, a.faction), "%s: crociata di una fazione scomunicata (%s)" % [label, a.faction])
	for key in s.alliances:
		t.assert_false(s.wars.has(str(key)), "%s: alleati e in guerra (%s)" % [label, str(key)])
	for key in s.papal_warnings:
		var pair := String(key).split(">")
		t.assert_eq(pair.size(), 2, "%s: chiave di avvertimento '%s'" % [label, str(key)])
		if pair.size() == 2:
			t.assert_true(s.faction(pair[0]) != null and s.faction(pair[1]) != null, "%s: avvertimento tra fazioni sconosciute (%s)" % [label, str(key)])
			var w: Dictionary = s.papal_warnings[key]
			t.assert_true(int(w.get("scadenza", 0)) >= int(w.get("anno", 0)), "%s: avvertimento %s con scadenza prima dell'anno" % [label, str(key)])
