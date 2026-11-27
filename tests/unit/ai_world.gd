extends RefCounted
## Aiuti condivisi dai test dell'IA della fase 7a (test_ai_*): non e' un test (il nome non comincia per test_), si carica con
## preload. Mondo di prova: tests/fixtures/ai_startpos.txt (generato a mano) con ai_unit_prod.txt e ai_build_prod.txt
## (make_ai_fixtures.py), tutti con pesi INVENTATI per profilo.
##   ID_A1 (ALPHA, porto) - ID_A2 (ALPHA) - ID_A3 (ALPHA) - ID_B1 (BETA) - ID_B2 (BETA) - ID_P1 (PAPIST, il Papato)
##   ID_R1 (ribelli) confina con A3; ID_G1 (GAMMA, predoni, porto) confina solo con ID_MARE, come ID_A1.
##   ALPHA = CATHOLIC_EXPANSIONIST, BETA = CATHOLIC_DEFENSIVE, GAMMA = BARBARIAN_RAIDER, PAPIST = POPE; tutte cattoliche.
## Unita': Spearmen (100 denari, mantenimento 3), Archers (serve il Bowyer), Knights (serve Castle3), Galley (serve Shipyard1).
## Di partenza ogni regione ha un esercito di lancieri (A1 100 piu' una galea, A2 80, A3 60, B1 70, B2 50, P1 40, R1 30, G1 90
## piu' una galea); i test che vogliono forze precise usano `clear_armies` e `put`.

const STARTPOS := "res://tests/fixtures/ai_startpos.txt"
const UNITS := "res://tests/fixtures/ai_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/ai_build_prod.txt"

const A := "FN_ALPHA"
const B := "FN_BETA"
const G := "FN_GAMMA"
const P := "FN_PAPIST"
const A1 := "ID_A1"
const A2 := "ID_A2"
const A3 := "ID_A3"
const B1 := "ID_B1"
const B2 := "ID_B2"
const P1 := "ID_P1"
const R1 := "ID_R1"
const G1 := "ID_G1"
const MARE := "ID_MARE"


## Regole "quiete": nessun sorteggio di rivolte, nascite o catture.
static func quiet_rules() -> Rules:
	var rules := Rules.new()
	rules.province.calm()
	rules.dynasty.birth_chance = 0.0
	rules.agents.capture_max = 0.0
	# riaddestramento spento (0 pile per provincia): i test dell'IA che contano ordini, code e tesori non lo vedono; quelli
	# del riaddestramento (test_ai_riaddestramento.gd) lo riaccendono con `allow_retraining`
	rules.retrain.max_per_province = 0
	return rules


static func world(seed_value: int = 7) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var s := GameSetup.new_game(campaign, units, buildings, quiet_rules(), seed_value)
	for c in s.characters:
		c.old_age = 500
	return s


## Riaccende il riaddestramento (spento da `quiet_rules`) con il limite per provincia predefinito.
static func allow_retraining(s: GameState) -> void:
	s.rules.retrain.max_per_province = RetrainRules.new().max_per_province


## Toglie tutti gli eserciti e le flotte.
static func clear_armies(s: GameState) -> void:
	for a in s.armies.duplicate():
		s.remove_army(a)


## Esercito di lancieri (o dell'unita' indicata) nella regione.
static func put(s: GameState, faction_id: String, region_id: String, men: int, unit_id: String = "Spearmen") -> Army:
	var a := s.create_army(faction_id, region_id, false)
	a.stacks.append(UnitStack.new(unit_id, men, 0))
	return a


static func fleet(s: GameState, faction_id: String, zone: String) -> Army:
	var a := s.create_army(faction_id, zone, true)
	a.stacks.append(UnitStack.new("Galley", 1, 0))
	return a


static func land_army(s: GameState, faction_id: String, region_id: String) -> Army:
	for a in s.armies_in(region_id):
		if a.faction == faction_id and not a.is_fleet:
			return a
	return null


static func men_in(s: GameState, faction_id: String, region_id: String) -> int:
	var total := 0
	for a in s.armies_in(region_id):
		if a.faction == faction_id and not a.is_fleet:
			total += a.men_total()
	return total


static func add_general(s: GameState, faction_id: String, region_id: String, command: int = 3, loyalty: int = 5) -> Character:
	var c := s.create_character(faction_id)
	c.role = Character.ROLE_GENERAL
	c.forename = "Generale"
	c.male = true
	c.birth_year = s.year - 35
	c.command = command
	c.loyalty = loyalty
	c.old_age = 500
	c.region = region_id
	return c


## Fine della simulazione per tutti i test che non vogliono rumore: ricchezza identica, nessuna coda.
static func set_treasury(s: GameState, faction_id: String, value: int) -> void:
	s.faction(faction_id).treasury = value


## Contesto dell'anno con le regole predefinite dell'IA (o quelle passate).
static func context(s: GameState, ai_rules: AiRules = null, difficulty: String = "") -> AiContext:
	var r := ai_rules if ai_rules != null else AiRules.default_rules()
	return AiContext.build(s, r, difficulty)


## Dai gli ordini di un anno a una sola fazione; restituisce il contesto (ordini e rifiuti contati).
static func run_faction(s: GameState, faction_id: String, ai_rules: AiRules = null, difficulty: String = "", keep_log: bool = true) -> AiContext:
	var ctx := context(s, ai_rules, difficulty)
	ctx.keep_log = keep_log
	AiFaction.plan(ctx, faction_id)
	return ctx


## Impronta degli ordini dati (percorsi, code, tasse, tesori, comandanti, titoli): due stati uguali con gli stessi ordini hanno la
## stessa impronta.
static func footprint(s: GameState) -> String:
	var parts: Array[String] = []
	for a in s.armies:
		parts.append("%d:%s:%s:%s:%s:%d" % [a.id, a.faction, a.region, str(a.path), str(a.assault_ordered), a.stacks.size()])
	for p in s.provinces:
		var queue: Array[String] = []
		for q in p.building_queue:
			queue.append(q.key)
		for q in p.unit_queue:
			queue.append(q.key)
		parts.append("%s:%d:%s" % [p.id, p.tax_level, str(queue)])
	for f in s.factions:
		parts.append("%s:%d" % [f.id, f.treasury])
	for c in s.characters:
		parts.append("%d:%s:%s" % [c.id, c.title, str(c.army)])
	return "|".join(parts)


## Numero di voci della coda di reclutamento di tutte le province di una fazione.
static func queued_units(s: GameState, faction_id: String) -> int:
	var n := 0
	for p in s.provinces_of(faction_id):
		n += p.unit_queue.size()
	return n


static func queued_buildings(s: GameState, faction_id: String) -> int:
	var n := 0
	for p in s.provinces_of(faction_id):
		n += p.building_queue.size()
	return n


## Gli ordini di movimento di una fazione: id esercito -> percorso.
static func paths_of(s: GameState, faction_id: String) -> Dictionary:
	var out := {}
	for a in s.armies_of(faction_id):
		if not a.path.is_empty():
			out[a.id] = a.path
	return out


## Piano di una fazione con il profilo indicato (vuoto = quello effettivo dell'anno) e la mappa delle minacce gia' costruita.
static func plan_for(s: GameState, faction_id: String, profile: String = "", ctx: AiContext = null) -> AiPlan:
	var c := ctx if ctx != null else context(s)
	var name := profile if profile != "" else AiProfiles.effective(c, faction_id)
	var p := AiPlan.create(c, faction_id, name)
	AiThreat.build(p)
	return p


## Regole dell'IA senza rumore (punteggi confrontabili).
static func quiet_ai_rules() -> AiRules:
	var r := AiRules.load_file(AiRules.DEFAULT_PATH)
	r.build_noise = 0.0
	r.recruit_noise = 0.0
	return r


## Alza il reddito di tutte le province della fazione (fattorie al massimo).
static func enrich(s: GameState, faction_id: String) -> void:
	for p in s.provinces_of(faction_id):
		p.set_level("IMPROVED_FARMLAND", 4)
