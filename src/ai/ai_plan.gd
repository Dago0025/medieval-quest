class_name AiPlan
extends RefCounted
## Dati di lavoro di una fazione per un anno (fase 7): profilo effettivo, parametri, generatore casuale, mappa delle minacce,
## budget. Tutti i moduli ricevono un AiPlan. Ogni azione passa SOLO dai comandi pubblici di `GameCommands`: `record` registra
## l'esito (ordini accettati e rifiutati) e dice se il comando e' riuscito.

var ctx: AiContext
var state: GameState
var rules: AiRules
var faction: FactionState
var id := ""
var profile := ""
var params: Dictionary = {}
var rng: RandomNumberGenerator
## Province della fazione, in ordine di dichiarazione.
var provinces: Array[ProvinceState] = []
## Provincia -> {"propria", "nemica", "fronte", "assedio", "capitale"} (vedi `AiThreat.build`).
var threat: Dictionary = {}
## Provincia -> forza dei propri eserciti con un ordine che li porta li' (rinforzi gia' in marcia o decisi quest'anno).
var incoming: Dictionary = {}
## Reddito lordo stimato, mantenimento attuale (con le reclute in coda), riserva di tesoro.
var income := 0
var upkeep := 0
var reserve := 0
## Soglia d'attacco effettiva (profilo x difficolta') e probabilita' di una guerra nuova.
var threshold := 99.0
var aggression := 0.0
## Livello dei bersagli ammessi (0 nessuno, 1 ribelli, 2 guerra, 3 neutrali).
var target_level := 0
## Quota delle regioni di terra della fazione (`DiplomacyProcessor.land_share`): un impero esteso attacca i neutrali con piu' cautela.
var land_share := 0.0
## Fase 7b: fazioni alleate che l'IA ha deciso di tradire quest'anno (attaccandole l'alleanza si rompe) e fazioni verso cui ha
## mandato un emissario (tregua, alleanza o nozze): queste ultime non si attaccano quest'anno. Id fazione -> true.
var betray := {}
var courting := {}
## Agenti gia' impegnati da un modulo quest'anno (id -> true).
var agents_used := {}
## Agenti della fazione (`AiAgents.own_agents`, calcolati alla prima richiesta).
var own_agents: Array[AgentState] = []
var own_agents_ready := false


static func create(context: AiContext, faction_id: String, profile_name: String) -> AiPlan:
	var p := AiPlan.new()
	p.ctx = context
	p.state = context.state
	p.rules = context.rules
	p.faction = p.state.faction(faction_id)
	p.id = faction_id
	p.profile = profile_name
	p.params = context.rules.profile(profile_name)
	if not bool(p.params.get("navale", false)) and WorldFactions.naval(faction_id):
		p.params = p.params.duplicate()   # fazioni del mondo navali (data/fazioni_mondo.cfg): flotte nei porti e sbarchi
		p.params["navale"] = true
	p.rng = context.rng_for(faction_id)
	p.provinces = p.state.provinces_of(faction_id)
	p.income = context.income_of(faction_id)
	p.upkeep = context.upkeep_of(faction_id)
	p.reserve = AiProfiles.reserve_of(context, faction_id)
	p.threshold = p.num("soglia") * float(context.diff.get("soglia", 1.0))
	p.aggression = clampf(p.num("aggressione") * float(context.diff.get("aggressivita", 1.0)), 0.0, 1.0)
	p.target_level = context.rules.target_level(profile_name)
	if p.state.campaign != null:
		p.land_share = DiplomacyProcessor.land_share(p.state, faction_id)
	return p


## Agente libero: senza percorso ne' missione, che non aspetta una risposta e non e' gia' stato usato quest'anno.
func is_agent_free(a: AgentState) -> bool:
	if a.faction != id or not a.path.is_empty() or a.has_mission() or agents_used.has(a.id):
		return false
	return state.pending_proposals.is_empty() or state.proposal_of_agent(a.id).is_empty()


func num(key: String) -> float:
	return float(params.get(key, 0.0))


func flag(key: String) -> bool:
	return bool(params.get(key, false))


## Registra l'esito di un comando di `GameCommands`: vero se e' riuscito. I rifiuti si contano (un rifiuto inatteso e' un difetto
## dell'IA, i test lo controllano) e si ricordano i primi messaggi.
func record(result: Dictionary, label: String) -> bool:
	var ok := bool(result.get("ok", false))
	if ok:
		ctx.orders += 1
		if ctx.keep_log:
			ctx.log.append("%d %s %s" % [state.year, id, label])
		return true
	ctx.rejected += 1
	var message := "%d %s %s: %s" % [state.year, id, label, str(result.get("errore", ""))]
	if ctx.rejections.size() < 40:
		ctx.rejections.append(message)
	if ctx.keep_log:
		ctx.log.append("RIFIUTATO " + message)
	return false


## Esercito libero: esercito di terra della fazione senza ordine, non crociato, non assediato nel castello, non assediante e non
## gia' impegnato da un altro modulo quest'anno.
func is_free(a: Army) -> bool:
	if a.faction != id or a.is_fleet or a.stacks.is_empty() or not a.path.is_empty() or a.is_crusade():
		return false
	if ctx.busy.has(a.id):
		return false
	if a.in_castle and state.is_besieged(a.region):
		return false
	var siege := state.siege_in(a.region)
	if siege != null and siege.faction == id and not a.in_castle:
		return false
	return true


## Marca un esercito come impegnato e ne conta la forza tra i rinforzi in arrivo nella regione di destinazione.
func commit(a: Army, destination: String) -> void:
	ctx.busy[a.id] = true
	incoming[destination] = float(incoming.get(destination, 0.0)) + ctx.force(a)
