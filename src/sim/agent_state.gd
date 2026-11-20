class_name AgentState
extends RefCounted
## Agente (emissario, principessa, spia, assassino, religiosi, inquisitori). Dalla fase 5a ha un valore (0-10), un
## nome, un percorso come gli eserciti, una missione e, per le principesse, il personaggio collegato.
## Le regole stanno in `AgentProcessor`, `AgentMissions` e `DiplomacyProcessor`; i parametri in `AgentRules`.

const EMISSARY := "EMISSARY"
const PRINCESS := "PRINCESS"
const SPY := "SPY"
const ASSASSIN := "ASSASSIN"
const CRUSADE := "CRUSADE"
const JIHAD := "JIHAD"
## Religiosi e inquisitori (fase 5b): convertono le province (`ReligionProcessor`), gli inquisitori bruciano gli eretici e
## fanno processi (`AgentMissions.TRIAL`); si reclutano, si muovono e si possono catturare o assassinare come gli altri.
const RELIGIOUS_TYPES := ["BISHOP", "CARDINAL", "PRIEST", "SHAMAN", "ORTHODOX_BISHOP", "MULLAH", "ULAMA", "INQUISITOR", "GRAND_INQUISITOR"]

var id := 0
var faction := ""
var region := ""
var unit_id := ""       ## id del tipo nel file prod unita' (per esempio Emissary)
var type_name := ""     ## EMISSARY, PRINCESS...
var birth_year := 0     ## per emissari e principesse dello startpos e' il valore della MakeUnit (anno di nascita)
## Fase 5a: valore (0-10); -1 = non ancora assegnato (salvataggi vecchi: lo assegna `SaveGame`).
var valour := -1
var name := ""
## Regioni ancora da attraversare, una per anno (come `Army.path`); gli agenti si muovono solo a terra.
var path := PackedStringArray()
## Trasporto via mare: catena di zone di mare quando `path` e' un'unica provincia raggiunta imbarcandosi.
var sea_route := PackedStringArray()
## Viaggio verso una provincia lontana (richiesta di Federico del 2026-11-13, `AgentTravel`): la meta finale; `path` e
## `sea_route` sono la tappa di quest'anno, ricalcolata a ogni fine anno fino all'arrivo. Vuota = nessun viaggio.
var destination := ""
## Missione ordinata: vuoto oppure {"tipo", "bersaglio", "regione", "avvicinamento"} (vedi `AgentMissions`).
var mission := {}
## Ordine di lungo periodo dato dall'IA (ADR-053, `AiJourneys`): vuoto oppure {"tipo", "bersaglio", "regione", "anno",
## "ricalcoli", "punteggio"}. La simulazione non lo legge: serve all'IA per ricordare l'obiettivo di un viaggio di piu' anni
## anche dopo un salvataggio. Il giocatore non lo usa.
var ai_order := {}
## Posizione scelta dal giocatore per la pedina nella sua regione (coordinate della mappa, richiesta di Federico: riordinare
## le pedine trascinandole). Vale solo finche' la pedina resta in `map_spot_region`; Vector2.INF = posizione automatica.
var map_spot := Vector2.INF
var map_spot_region := ""
## Solo principesse con una dinastia: id del `Character` collegato (0 = nessuno).
var character_id := 0


func _init(agent_id: int = 0, owner_id: String = "", at_region: String = "", type_id: String = "", kind: String = "", born: int = 0) -> void:
	id = agent_id
	faction = owner_id
	region = at_region
	unit_id = type_id
	type_name = kind
	birth_year = born


## Vero per i religiosi e gli inquisitori.
static func is_religious_type(kind: String) -> bool:
	return RELIGIOUS_TYPES.has(kind)


## Tipi che si reclutano dalla coda (non PRINCESS, che nasce con la dinastia, ne' CRUSADE e JIHAD, che sono eserciti: 5c).
static func is_recruitable_type(kind: String) -> bool:
	return kind == EMISSARY or kind == SPY or kind == ASSASSIN or is_religious_type(kind)


func is_religious() -> bool:
	return is_religious_type(type_name)


## Vero per spie e assassini (invisibili in mappa strategica: meno probabilita' di cattura).
func is_invisible() -> bool:
	return type_name == SPY or type_name == ASSASSIN


func has_mission() -> bool:
	return not mission.is_empty()


func to_dict() -> Dictionary:
	var d := {"id": id, "fazione": faction, "regione": region, "unita": unit_id, "tipo": type_name, "nascita": birth_year}
	# campi della fase 5a: i facoltativi compaiono solo se servono (i salvataggi precedenti non li hanno)
	d["valore"] = valour
	d["nome"] = name
	d["personaggio"] = character_id
	if not path.is_empty():
		d["percorso"] = Array(path)
	if not sea_route.is_empty():
		d["rotta_mare"] = Array(sea_route)
	if destination != "":
		d["destinazione"] = destination
	if not mission.is_empty():
		d["missione"] = mission.duplicate(true)
	if not ai_order.is_empty():
		d["ordine_ia"] = ai_order.duplicate(true)
	if map_spot != Vector2.INF and map_spot_region != "":
		d["posizione_mappa"] = {"regione": map_spot_region, "x": map_spot.x, "y": map_spot.y}
	return d


static func from_dict(d: Dictionary) -> AgentState:
	var a := AgentState.new(
		int(d.get("id", 0)),
		str(d.get("fazione", "")),
		str(d.get("regione", "")),
		str(d.get("unita", "")),
		str(d.get("tipo", "")),
		int(d.get("nascita", 0)))
	a.valour = int(d.get("valore", -1))
	a.name = str(d.get("nome", ""))
	a.character_id = int(d.get("personaggio", 0))
	a.path = SimUtil.strings_from(d.get("percorso", []))
	a.sea_route = SimUtil.strings_from(d.get("rotta_mare", []))
	a.destination = str(d.get("destinazione", ""))
	var m: Variant = d.get("missione", {})
	if typeof(m) == TYPE_DICTIONARY:
		var md: Dictionary = m
		a.mission = md.duplicate(true)
	var order: Variant = d.get("ordine_ia", {})
	if typeof(order) == TYPE_DICTIONARY:
		var od: Dictionary = order
		a.ai_order = od.duplicate(true)
	var spot: Variant = d.get("posizione_mappa", null)
	if typeof(spot) == TYPE_DICTIONARY:
		var sd: Dictionary = spot
		a.map_spot = Vector2(float(sd.get("x", 0.0)), float(sd.get("y", 0.0)))
		a.map_spot_region = str(sd.get("regione", ""))
	return a


## Posizione scelta sulla mappa, se vale ancora per la regione attuale (altrimenti Vector2.INF).
func spot_here() -> Vector2:
	return map_spot if map_spot != Vector2.INF and map_spot_region == region else Vector2.INF
