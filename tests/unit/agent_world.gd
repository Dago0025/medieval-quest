extends RefCounted
## Aiuti condivisi dai test della fase 5a (test_sim_diplomacy, test_sim_agents, test_sim_missions): non e' un test
## (il nome non comincia per test_), si carica con preload. Mondo di prova: tests/fixtures/agents_startpos.txt.
##   Fazioni FN_ALPHA, FN_BETA, FN_GAMMA (piu' FN_REBEL). Regioni: ID_ALTA (ALPHA, porto, Castle3) - ID_BASSA (ALPHA,
##   Castle) - ID_MEZZA (BETA, porto, Castle2) - ID_SOLA (ribelli); ID_ORTO (GAMMA, Castle) confina con MEZZA;
##   mari ID_MARE_NORD (confina con ALTA) e ID_MARE_SUD (confina con MEZZA).
##   Eserciti iniziali: ALPHA in ALTA (160 uomini piu' una galea), ALPHA in BASSA (80), BETA in MEZZA (60), ribelli in
##   SOLA (50), GAMMA in ORTO (70); si trovano con `land_army`. Il capo di ogni fazione comanda un esercito di terra.
##   Agenti iniziali: emissari di ALPHA (BASSA), BETA (MEZZA), GAMMA (ORTO) con valore 2, principesse di ALPHA (ALTA,
##   nata nel 980) e di BETA (MEZZA, nata nel 990), collegate a un personaggio; si trovano con `agent_of`.

const STARTPOS := "res://tests/fixtures/agents_startpos.txt"
const UNITS := "res://tests/fixtures/agents_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"

const A := "FN_ALPHA"
const B := "FN_BETA"
const G := "FN_GAMMA"
const ALTA := "ID_ALTA"
const BASSA := "ID_BASSA"
const MEZZA := "ID_MEZZA"
const SOLA := "ID_SOLA"
const ORTO := "ID_ORTO"
const NORD := "ID_MARE_NORD"
const SUD := "ID_MARE_SUD"


## Regole "quiete": nessun sorteggio di rivolte, nascite o catture (le morti per vecchiaia si evitano con `old_age`
## dei personaggi, che sta nello stato). I test che provano un sorteggio lo accendono o fissano la probabilita' a 0 o 1.
static func quiet_rules() -> Rules:
	var rules := Rules.new()
	rules.province.calm()
	rules.dynasty.birth_chance = 0.0
	rules.agents.capture_max = 0.0
	return rules


## Mondo "quieto" (vedi `quiet_rules`); con `quiet` falso le regole sono quelle predefinite.
static func world(seed_value: int = 7, quiet: bool = true) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var rules := Rules.new()
	if quiet:
		rules = quiet_rules()
	var s := GameSetup.new_game(campaign, units, buildings, rules, seed_value)
	if quiet:
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


## Primo agente del tipo e della fazione (null se non c'e').
static func agent_of(s: GameState, faction_id: String, type_name: String) -> AgentState:
	for a in s.agents:
		if a.faction == faction_id and a.type_name == type_name:
			return a
	return null


static func add_agent(s: GameState, faction_id: String, region_id: String, type_name: String, valour: int) -> AgentState:
	var a := s.create_agent(faction_id, region_id, type_name.capitalize(), type_name, 0)
	a.valour = valour
	a.name = "Prova"
	return a


static func fleet(s: GameState, faction_id: String, zone: String) -> Army:
	var a := s.create_army(faction_id, zone, true)
	a.stacks.append(UnitStack.new("Galley", 1, 0))
	return a


## Esercito con un generale di comando 3 e lealta' 5 (non e' ne' il capo ne' l'erede).
static func general_army(s: GameState, faction_id: String, region_id: String, men: int = 60, unit_id: String = "Nizari") -> Army:
	var a := s.create_army(faction_id, region_id, false)
	a.stacks.append(UnitStack.new(unit_id, men, 0))
	var c := add_general(s, faction_id, region_id)
	c.army = a.id
	return a


## Generale maggiorenne (comando 3, lealta' 5) nella regione, senza esercito.
static func add_general(s: GameState, faction_id: String, region_id: String) -> Character:
	var c := s.create_character(faction_id)
	c.role = Character.ROLE_GENERAL
	c.forename = "Generale"
	c.male = true
	c.birth_year = s.year - 35
	c.command = 3
	c.loyalty = 5
	c.old_age = 500
	c.region = region_id
	return c


## Tutte le proposte e le corruzioni riescono (probabilita' limitata a 1).
static func always_accept(s: GameState) -> void:
	s.rules.diplomacy.p_min = 1.0
	s.rules.diplomacy.p_max = 1.0
	s.rules.agents.bribe_p_min = 1.0
	s.rules.agents.bribe_p_max = 1.0


## Tutte le proposte e le corruzioni sono rifiutate (probabilita' 0).
static func never_accept(s: GameState) -> void:
	s.rules.diplomacy.p_min = 0.0
	s.rules.diplomacy.p_max = 0.0
	s.rules.agents.bribe_p_min = 0.0
	s.rules.agents.bribe_p_max = 0.0


## L'assassinio riesce sempre (tutti i gradini al 100%) o fallisce sempre (0%).
static func kill_always(s: GameState) -> void:
	s.rules.agents.kill_steps = PackedInt32Array([100])


static func kill_never(s: GameState) -> void:
	s.rules.agents.kill_steps = PackedInt32Array([0])


## Gli agenti catturano sempre / mai (probabilita' di cattura 1).
static func capture_always(s: GameState) -> void:
	s.rules.agents.capture_base = 1.0
	s.rules.agents.capture_k = 0.0
	s.rules.agents.invisible_malus = 0.0
	s.rules.agents.capture_max = 1.0
