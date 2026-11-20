class_name AgentMissions
extends RefCounted
## Missioni degli agenti (fase 5a, spec. fase 5 §5a): quali esistono per tipo di agente, validazione dei bersagli,
## probabilita' e prezzi (anteprima per l'interfaccia e dati per la risoluzione di `AgentProcessor`).
## Solo calcoli: nessuna funzione qui estrae numeri casuali o modifica lo stato.
##
## Una missione ordinata e' `AgentState.mission` = {"tipo", "bersaglio", "regione", "avvicinamento"}:
## - `bersaglio` dipende dalla missione: id di fazione (alleanza, tregua, matrimonio), id di esercito (corruzione),
##   id di personaggio (sposa_generale), Dictionary {"tipo": "personaggio" | "agente", "id": n} (assassinio, processo);
## - `regione` e' dove si svolge (la regione dell'agente o una confinante);
## - `avvicinamento` e' vero se l'agente ci va prima (l'ordine ha impostato il suo percorso).
## Un bersaglio deve stare nella regione dell'agente o in una confinante di terra.

const ALLIANCE := "alleanza"
const TRUCE := "tregua"
const BRIBE := "corruzione"
const MARRIAGE := "matrimonio"
const BRIDE := "sposa_generale"
const ASSASSINATE := "assassinio"
## Fase 5b: processo dell'inquisitore a un generale, principe, capo o agente cattolico (anche della propria fazione).
const TRIAL := "processo"

const TARGET_CHARACTER := "personaggio"
const TARGET_AGENT := "agente"
## Missioni delle spie (richiesta di Federico del 18/11/2026). Bersaglio: id di provincia, oppure per lo spionaggio
## {"tipo": "provincia" | "esercito", "id": ...}. Si svolgono nella regione dell'agente o in una confinante di terra.
const SPY_ON := "spionaggio"
const UNREST := "malcontento"
const SABOTAGE := "sabotaggio"
const GATES := "porte"
const TARGET_PROVINCE := "provincia"
const TARGET_ARMY := "esercito"


## Missioni che un tipo di agente puo' ordinare, nell'ordine in cui compaiono nelle anteprime.
static func missions_for(type_name: String) -> PackedStringArray:
	if type_name == AgentState.EMISSARY:
		return PackedStringArray([ALLIANCE, TRUCE, BRIBE])
	if type_name == AgentState.PRINCESS:
		return PackedStringArray([MARRIAGE, BRIDE])
	if type_name == AgentState.ASSASSIN:
		return PackedStringArray([ASSASSINATE])
	if type_name == AgentState.SPY:
		return PackedStringArray([SPY_ON, UNREST, SABOTAGE, GATES])
	if type_name == ReligionProcessor.INQUISITOR or type_name == ReligionProcessor.GRAND_INQUISITOR:
		return PackedStringArray([TRIAL])
	return PackedStringArray()


## Regione dell'agente e regioni di terra confinanti, in questo ordine.
static func reach(state: GameState, agent: AgentState) -> PackedStringArray:
	var out := PackedStringArray([agent.region])
	var r := state.campaign.region(agent.region)
	if r == null:
		return out
	for n in r.neighbours:
		var other := state.campaign.region(n)
		if other != null and not other.is_sea:
			out.append(other.id)
	return out


## Bersaglio in forma canonica (id di fazione in maiuscolo, interi, Dictionary {"tipo", "id"}), cosi' resta uguale
## dopo un salvataggio.
static func normalize_target(kind: String, target: Variant) -> Variant:
	if kind == ALLIANCE or kind == TRUCE or kind == MARRIAGE:
		return SimUtil.norm(str(target))
	if kind == ASSASSINATE or kind == TRIAL:
		if typeof(target) == TYPE_DICTIONARY:
			var td: Dictionary = target
			return {"tipo": str(td.get("tipo", "")), "id": int(td.get("id", 0))}
		return target
	if kind == UNREST or kind == SABOTAGE or kind == GATES:
		return SimUtil.norm(str(target))
	if kind == SPY_ON:
		if typeof(target) == TYPE_DICTIONARY:
			var sd: Dictionary = target
			if str(sd.get("tipo", "")) == TARGET_ARMY:
				return {"tipo": TARGET_ARMY, "id": int(sd.get("id", 0))}
			return {"tipo": TARGET_PROVINCE, "id": SimUtil.norm(str(sd.get("id", "")))}
		return target
	return int(target)


# --- validazione ------------------------------------------------------------------------------------------


## Controlla se l'agente puo' svolgere la missione `kind` sul bersaglio. Esito: "ok", "errore" (testo italiano) e,
## se ok, "regione" (dove si svolge). Non modifica lo stato.
static func validate(state: GameState, agent: AgentState, kind: String, target: Variant) -> Dictionary:
	if not missions_for(agent.type_name).has(kind):
		return _fail(Lang.t("Un agente %s non puo' svolgere la missione %s") % [agent.type_name, Lang.t(kind)])
	var own := state.faction(agent.faction)
	if own == null or not own.alive:
		return _fail(Lang.t("Fazione sconosciuta o non attiva: %s") % agent.faction)
	if kind == ALLIANCE or kind == TRUCE or kind == MARRIAGE:
		return _validate_proposal(state, agent, kind, target)
	if kind == BRIBE:
		return _validate_bribe(state, agent, target)
	if kind == BRIDE:
		return _validate_bride(state, agent, target)
	if kind == TRIAL:
		return _validate_trial(state, agent, target)
	if kind == SPY_ON or kind == UNREST or kind == SABOTAGE or kind == GATES:
		return _validate_spy(state, agent, kind, target)
	return _validate_assassination(state, agent, target)


## Missioni delle spie: bersaglio a portata, di una fazione che non e' la propria ne' alleata (lo spionaggio anche dei
## ribelli no: si conoscono gia'); porte: castello assediato dalla propria fazione, in guerra con il proprietario;
## sabotaggio: almeno un edificio che non sia il castello.
static func _validate_spy(state: GameState, agent: AgentState, kind: String, target: Variant) -> Dictionary:
	var region_id := ""
	var owner_id := ""
	if kind == SPY_ON and typeof(target) == TYPE_DICTIONARY and str((target as Dictionary).get("tipo", "")) == TARGET_ARMY:
		var army := state.army(int((target as Dictionary).get("id", 0)))
		if army == null or army.stacks.is_empty():
			return _fail(Lang.t("Esercito sconosciuto: %s") % str(target))
		region_id = army.region
		owner_id = army.faction
	else:
		var pid := str((target as Dictionary).get("id", "")) if typeof(target) == TYPE_DICTIONARY else str(target)
		var p := state.province(pid)
		if p == null:
			return _fail(Lang.t("Provincia sconosciuta: %s") % pid)
		region_id = p.id
		owner_id = p.owner
	if not reach(state, agent).has(region_id):
		return _fail(Lang.t("%s e' fuori dalla portata dell'agente") % region_id)
	if owner_id == agent.faction or state.is_allied(agent.faction, owner_id):
		return _fail(Lang.t("Bersaglio della propria fazione o di un alleato"))
	if owner_id == GameState.REBEL and kind != GATES:
		return _fail(Lang.t("Dei ribelli si sa gia' tutto"))
	if kind == GATES:
		if not state.at_war(agent.faction, owner_id) or not _besieged_by(state, region_id, agent.faction):
			return _fail(Lang.t("Nessun assedio della propria fazione a %s") % region_id)
	if kind == SABOTAGE and sabotage_targets(state, state.province(region_id)).is_empty():
		return _fail(Lang.t("Nessun edificio da sabotare a %s") % region_id)
	return {"ok": true, "errore": "", "regione": region_id}


static func _besieged_by(state: GameState, region_id: String, faction_id: String) -> bool:
	for siege in state.sieges_in_order():
		if siege.region == region_id and siege.faction == faction_id:
			return true
	return false


## Edifici sabotabili di una provincia (tutti tranne il castello), in ordine alfabetico di famiglia.
static func sabotage_targets(state: GameState, p: ProvinceState) -> PackedStringArray:
	var out := PackedStringArray()
	if p == null:
		return out
	var castle := state.rules.combat.castle_family
	for family in p.buildings:
		if str(family) != castle and int(p.buildings[family]) > 0:
			out.append(str(family))
	out.sort()
	return out


## Probabilita' di una missione di spia con valore `valour` (PROVVISORIA, agenti.cfg [spie]).
static func spy_chance(state: GameState, kind: String, valour: int) -> float:
	var ar := state.rules.agents
	var v := float(maxi(0, valour))
	if kind == SPY_ON:
		return clampf(ar.intel_base + ar.intel_k * v, 0.0, 1.0)
	if kind == UNREST:
		return clampf(ar.unrest_base + ar.unrest_k * v, 0.0, 0.95)
	if kind == SABOTAGE:
		return clampf(ar.sabotage_base + ar.sabotage_k * v, 0.0, ar.sabotage_max)
	if kind == GATES:
		return clampf(ar.gates_k * v * ar.gates_mission_factor, 0.0, 1.0)
	return 0.0


## Calo di lealta' obiettivo del malcontento fomentato da una spia di valore `valour`.
static func unrest_loyalty(state: GameState, valour: int) -> int:
	var ar := state.rules.agents
	return ar.unrest_base_loyalty + ar.unrest_per_star * maxi(0, valour)


static func _validate_proposal(state: GameState, agent: AgentState, kind: String, target: Variant) -> Dictionary:
	var own := state.faction(agent.faction)
	if typeof(target) != TYPE_STRING:
		return _fail(Lang.t("Il bersaglio di %s e' una fazione") % Lang.t(kind))
	var target_id := SimUtil.norm(str(target))
	var other := state.faction(target_id)
	if other == null or not other.alive:
		return _fail(Lang.t("Fazione sconosciuta o non attiva: %s") % target_id)
	if target_id == agent.faction:
		return _fail(Lang.t("Non si tratta con la propria fazione"))
	if target_id == GameState.REBEL:
		return _fail(Lang.t("I ribelli non entrano in trattati"))
	if other.is_player and own.is_player:
		return _fail(Lang.t("Le proposte tra giocatori non esistono: un giocatore tratta solo con le IA (fase 7b)"))
	var rel := state.relation(agent.faction, target_id)
	if kind == ALLIANCE and rel != GameState.REL_NEUTRAL:
		return _fail(Lang.t("%s non e' neutrale (%s): l'alleanza si propone solo a una fazione neutrale") % [SimUtil.faction_label(target_id), Lang.t(rel)])
	if kind == TRUCE and rel != GameState.REL_WAR:
		return _fail(Lang.t("%s non e' in guerra con %s: la tregua si propone a una fazione in guerra") % [SimUtil.faction_label(target_id), SimUtil.faction_label(agent.faction)])
	if kind == MARRIAGE:
		if rel == GameState.REL_WAR:
			return _fail(Lang.t("Non si propone un matrimonio a una fazione in guerra"))
		var problem := princess_problem(state, agent)
		if problem != "":
			return _fail(problem)
	var region_id := faction_region(state, agent, target_id, kind == TRUCE)
	if region_id == "":
		return _fail(Lang.t("Nessuna regione di %s nella regione dell'agente o in una confinante") % SimUtil.faction_label(target_id))
	return {"ok": true, "errore": "", "regione": region_id}


static func _validate_bribe(state: GameState, agent: AgentState, target: Variant) -> Dictionary:
	if typeof(target) != TYPE_INT and typeof(target) != TYPE_FLOAT:
		return _fail(Lang.t("Il bersaglio della corruzione e' un esercito (id)"))
	var army := state.army(int(target))
	if army == null or army.stacks.is_empty():
		return _fail(Lang.t("Esercito sconosciuto: %s") % str(target))
	var problem := bribe_problem(state, agent.faction, army)
	if problem != "":
		return _fail(problem)
	if not reach(state, agent).has(army.region):
		return _fail(Lang.t("L'esercito %d e' in %s, fuori dalla portata dell'agente") % [army.id, army.region])
	return {"ok": true, "errore": "", "regione": army.region}


## Motivo per cui `army` non si puo' corrompere per `faction_id` ("" se si puo'): non propri, non alleati, solo
## eserciti di terra (PROVVISORIA), mai quelli del capo o dell'erede (catalogo).
static func bribe_problem(state: GameState, faction_id: String, army: Army) -> String:
	if army.faction == faction_id:
		return Lang.t("L'esercito %d e' gia' della tua fazione") % army.id
	if army.is_fleet:
		return Lang.t("Le flotte non si corrompono (PROVVISORIA)")
	if army.is_crusade():
		return Lang.t("Un esercito crociato non si corrompe (PROVVISORIA, fase 5c)")
	if state.relation(faction_id, army.faction) == GameState.REL_ALLIANCE:
		return Lang.t("L'esercito %d e' di un alleato") % army.id
	var commander := state.commander_of(army.id)
	if commander != null and (commander.role == Character.ROLE_LEADER or commander.role == Character.ROLE_HEIR):
		return Lang.t("L'esercito %d e' comandato dal capo o dall'erede: non si corrompe") % army.id
	return ""


static func _validate_bride(state: GameState, agent: AgentState, target: Variant) -> Dictionary:
	if typeof(target) != TYPE_INT and typeof(target) != TYPE_FLOAT:
		return _fail(Lang.t("Il bersaglio di sposa_generale e' un generale (id del personaggio)"))
	var problem := princess_problem(state, agent)
	if problem != "":
		return _fail(problem)
	var c := state.character(int(target))
	if c == null or not c.alive or c.faction != agent.faction:
		return _fail(Lang.t("Generale sconosciuto o non della tua fazione: %s") % str(target))
	if c.role != Character.ROLE_GENERAL or not c.male:
		return _fail(Lang.t("%s non e' un generale (non si sposano il capo, l'erede, i principi)") % c.full_name())
	if not c.can_command(state.rules.dynasty, state.year):
		return _fail(Lang.t("%s e' minorenne") % c.full_name())
	var region_id := state.character_region(c)
	if not reach(state, agent).has(region_id):
		return _fail(Lang.t("%s e' in %s, fuori dalla portata dell'agente") % [c.full_name(), region_id])
	return {"ok": true, "errore": "", "regione": region_id}


static func _validate_assassination(state: GameState, agent: AgentState, target: Variant) -> Dictionary:
	if typeof(target) != TYPE_DICTIONARY:
		return _fail(Lang.t("Il bersaglio dell'assassinio e' {\"tipo\": \"personaggio\" o \"agente\", \"id\": n}"))
	var td: Dictionary = target
	var target_kind := str(td.get("tipo", ""))
	var target_id := int(td.get("id", 0))
	var region_id := ""
	var other_faction := ""
	if target_kind == TARGET_CHARACTER:
		var c := state.character(target_id)
		if c == null or not c.alive:
			return _fail(Lang.t("Personaggio sconosciuto o morto: %d") % target_id)
		if c.role == Character.ROLE_PRINCESS and princess_agent(state, c) != null:
			return _fail(Lang.t("%s e' un'agente: il bersaglio e' l'agente") % c.full_name())
		region_id = state.character_region(c)
		other_faction = c.faction
	elif target_kind == TARGET_AGENT:
		var other := state.agent(target_id)
		if other == null:
			return _fail(Lang.t("Agente sconosciuto: %d") % target_id)
		region_id = other.region
		other_faction = other.faction
	else:
		return _fail(Lang.t("Tipo di bersaglio sconosciuto: %s") % target_kind)
	if other_faction == agent.faction:
		return _fail(Lang.t("Il bersaglio e' della tua fazione"))
	if state.relation(agent.faction, other_faction) == GameState.REL_ALLIANCE:
		return _fail(Lang.t("Il bersaglio e' di un alleato"))
	if not reach(state, agent).has(region_id):
		return _fail(Lang.t("Il bersaglio e' in %s, fuori dalla portata dell'agente") % region_id)
	return {"ok": true, "errore": "", "regione": region_id}


## Processo (fase 5b): bersaglio {"tipo": "personaggio", "id"} (capo, principe o generale vivo di una fazione cattolica) o
## {"tipo": "agente", "id"} (agente cattolico, non l'inquisitore stesso), nella regione dell'inquisitore o in una confinante.
## Anche della propria fazione e anche il capo (catalogo); nessun vincolo di guerra o alleanza.
static func _validate_trial(state: GameState, agent: AgentState, target: Variant) -> Dictionary:
	if typeof(target) != TYPE_DICTIONARY:
		return _fail(Lang.t("Il bersaglio del processo e' {\"tipo\": \"personaggio\" o \"agente\", \"id\": n}"))
	var td: Dictionary = target
	var target_kind := str(td.get("tipo", ""))
	var target_id := int(td.get("id", 0))
	var region_id := ""
	if target_kind == TARGET_CHARACTER:
		var c := state.character(target_id)
		if c == null or not c.alive:
			return _fail(Lang.t("Personaggio sconosciuto o morto: %d") % target_id)
		if c.role != Character.ROLE_LEADER and c.role != Character.ROLE_PRINCE and c.role != Character.ROLE_GENERAL:
			return _fail(Lang.t("%s non e' un capo, un principe o un generale (%s): non si processa") % [c.full_name(), c.role])
		if ReligionProcessor.faction_religion(state, c.faction) != ProvinceState.CATHOLIC:
			return _fail(Lang.t("%s non e' cattolico: l'Inquisizione processa solo i cattolici") % c.full_name())
		region_id = state.character_region(c)
	elif target_kind == TARGET_AGENT:
		var other := state.agent(target_id)
		if other == null:
			return _fail(Lang.t("Agente sconosciuto: %d") % target_id)
		if other.id == agent.id:
			return _fail(Lang.t("Un inquisitore non processa se stesso"))
		if ReligionProcessor.agent_religion(state, other) != ProvinceState.CATHOLIC:
			return _fail(Lang.t("L'agente %d non e' cattolico: l'Inquisizione processa solo i cattolici") % other.id)
		region_id = other.region
	else:
		return _fail(Lang.t("Tipo di bersaglio sconosciuto: %s") % target_kind)
	if not reach(state, agent).has(region_id):
		return _fail(Lang.t("Il bersaglio e' in %s, fuori dalla portata dell'agente") % region_id)
	return {"ok": true, "errore": "", "regione": region_id}


## Prima regione (la regione dell'agente, poi le confinanti) in cui la fazione `target_id` possiede la provincia o,
## con `or_army`, ha un esercito di terra. "" se non ce n'e'.
static func faction_region(state: GameState, agent: AgentState, target_id: String, or_army: bool) -> String:
	for region_id in reach(state, agent):
		var p := state.province(region_id)
		if p != null and p.owner == target_id:
			return region_id
		if or_army:
			for a in state.armies_in(region_id):
				if a.faction == target_id and not a.is_fleet and not a.stacks.is_empty():
					return region_id
	return ""


## Motivo per cui la principessa non puo' sposarsi ("" se puo'): se e' collegata a un personaggio, deve essere viva e
## maggiorenne (PROVVISORIA: l'eta' da marito e' quella della maggiore eta' delle principesse).
static func princess_problem(state: GameState, agent: AgentState) -> String:
	if agent.character_id == 0:
		return ""
	var c := state.character(agent.character_id)
	if c == null or not c.alive:
		return Lang.t("La principessa non e' piu' in gioco")
	if c.age(state.year + 1) < state.rules.dynasty.princess_age:
		return Lang.t("%s e' troppo giovane per sposarsi") % c.full_name()
	return ""


## Agente PRINCESS collegato al personaggio, null se non ce n'e'.
static func princess_agent(state: GameState, c: Character) -> AgentState:
	for a in state.agents:
		if a.type_name == AgentState.PRINCESS and a.character_id == c.id:
			return a
	return null


# --- probabilita' e prezzi -------------------------------------------------------------------------------------


## Probabilita' di riuscita della missione (0..1) per un bersaglio gia' validato.
static func chance(state: GameState, agent: AgentState, kind: String, target: Variant) -> float:
	if kind == ALLIANCE:
		return DiplomacyProcessor.acceptance(state, DiplomacyProcessor.KIND_ALLIANCE, agent.faction, SimUtil.norm(str(target)), agent.valour)
	if kind == TRUCE:
		return DiplomacyProcessor.acceptance(state, DiplomacyProcessor.KIND_TRUCE, agent.faction, SimUtil.norm(str(target)), agent.valour)
	if kind == MARRIAGE:
		return DiplomacyProcessor.acceptance(state, DiplomacyProcessor.KIND_MARRIAGE, agent.faction, SimUtil.norm(str(target)), agent.valour)
	if kind == BRIBE:
		var army := state.army(int(target))
		if army == null:
			return 0.0
		return bribe_chance(state, army, agent.valour)
	if kind == ASSASSINATE:
		var td: Dictionary = target
		return state.rules.agents.kill_chance(kill_step(state, agent.valour, td))
	if kind == TRIAL:
		var trial_target: Dictionary = target
		return trial_chance(state, trial_target)
	if kind == SPY_ON or kind == UNREST or kind == SABOTAGE or kind == GATES:
		return spy_chance(state, kind, agent.valour)
	return 1.0


## Prezzo della corruzione dell'esercito (PROVVISORIA, catalogo: campioni 2.000 - 70.000):
## k_prezzo * somma(costo * uomini / uomini base) * (1 + lealta' del comandante / 10) * (1 + comando / 10).
## Un esercito senza comandante conta lealta' e comando 0.
static func bribe_price(state: GameState, army: Army) -> int:
	var total := 0.0
	for s in army.stacks:
		var u := state.units.get_unit(s.unit_id)
		if u == null:
			continue
		total += float(u.cost) * float(s.men) / float(maxi(1, u.men))
	var loyalty := 0
	var command := 0
	var c := state.commander_of(army.id)
	if c != null:
		loyalty = c.effective(Character.ATTR_LOYALTY, state.rules, state.campaign)
		command = c.stars(state.rules, state.campaign)
	var price := total * state.rules.agents.bribe_price_k * (1.0 + float(loyalty) / 10.0) * (1.0 + float(command) / 10.0)
	return roundi(price)


## Probabilita' che l'esercito accetti la corruzione: p_base - k_lealta * lealta' + k_valore * valore, limitata.
static func bribe_chance(state: GameState, army: Army, valour: int) -> float:
	var ar := state.rules.agents
	var loyalty := 0
	var c := state.commander_of(army.id)
	if c != null:
		loyalty = c.effective(Character.ATTR_LOYALTY, state.rules, state.campaign)
	return clampf(ar.bribe_base - ar.bribe_k_loyalty * float(loyalty) + ar.bribe_k_valour * float(valour), ar.bribe_p_min, ar.bribe_p_max)


## Gradino della tabella dell'assassino contro il bersaglio {"tipo", "id"}: gradino di partenza per tipo di
## bersaglio piu' (valore dell'assassino - valore del bersaglio), limitato alla tabella. Il valore di un personaggio
## e' il suo comando efficace, quello di un agente il suo valore. Bersaglio sconosciuto: gradino 0.
static func kill_step(state: GameState, assassin_valour: int, target: Dictionary) -> int:
	var ar := state.rules.agents
	var base := 0
	var value := 0
	if str(target.get("tipo", "")) == TARGET_CHARACTER:
		var c := state.character(int(target.get("id", 0)))
		if c == null:
			return 0
		base = ar.step_noble
		if c.role == Character.ROLE_LEADER:
			base = ar.step_leader
		elif c.role == Character.ROLE_PRINCESS:
			base = ar.step_princess
		value = c.stars(state.rules, state.campaign)
	else:
		var other := state.agent(int(target.get("id", 0)))
		if other == null:
			return 0
		base = ar.step_emissary
		if other.type_name == AgentState.SPY or other.type_name == AgentState.ASSASSIN:
			base = ar.step_spy
		elif other.is_religious():
			base = ar.step_religious
		elif other.type_name == AgentState.PRINCESS:
			base = ar.step_princess
		value = maxi(0, other.valour)
	return clampi(base + assassin_valour - value, 0, ar.max_step())


## Probabilita' del processo (PROVVISORIA): `base_processo + k_pieta * (5 - pieta')`, limitata a [p_min, p_max]. La pieta'
## di un personaggio e' quella efficace; quella di un agente `pieta_agente`. Bersaglio sconosciuto: 0.
static func trial_chance(state: GameState, target: Dictionary) -> float:
	var rr := state.rules.religion
	if str(target.get("tipo", "")) == TARGET_CHARACTER:
		var c := state.character(int(target.get("id", 0)))
		if c == null:
			return 0.0
		return rr.trial_chance(c.effective(Character.ATTR_PIETY, state.rules, state.campaign))
	if state.agent(int(target.get("id", 0))) == null:
		return 0.0
	return rr.trial_chance(rr.agent_piety)


# --- anteprima per l'interfaccia ----------------------------------------------------------------------------------


## Missioni valide dell'agente con bersagli, probabilita' e prezzo. Ogni voce: "tipo", "bersaglio" (da passare a
## `GameCommands.order_mission`), "regione", "etichetta" (testo italiano), "probabilita" (0..1), "prezzo" (solo
## corruzione, 0 altrimenti), "tesoro_sufficiente" (bool, il prezzo e' pagato a fine anno solo se l'esercito accetta)
## e "gradino" (solo assassinio, -1 altrimenti). Ordine: tipo di missione come in `missions_for`, poi id/ordine
## di dichiarazione. Le proposte di un giocatore a un altro giocatore non compaiono; quelle di un'IA a un giocatore si'
## (al passo 1b diventano una proposta in attesa di risposta: `GameState.pending_proposals`, fase 7b).
static func options(state: GameState, agent: AgentState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var own := state.faction(agent.faction)
	if own == null or not own.alive:
		return out
	for kind in missions_for(agent.type_name):
		if kind == ALLIANCE or kind == TRUCE or kind == MARRIAGE:
			for f in state.factions:
				_add_option(state, agent, out, kind, f.id, Lang.t("%s con %s") % [_kind_label(kind), SimUtil.faction_label(f.id)])
		elif kind == BRIBE:
			for region_id in reach(state, agent):
				for a in state.armies_in(region_id):
					_add_option(state, agent, out, kind, a.id, Lang.t("Corrompi l'esercito %d di %s (%d uomini)") % [a.id, SimUtil.faction_label(a.faction), a.men_total()])
		elif kind == BRIDE:
			for c in state.characters_of(agent.faction):
				_add_option(state, agent, out, kind, c.id, Lang.t("Sposa %s") % c.full_name())
		elif kind == SPY_ON:
			for region_id in reach(state, agent):
				var sp := state.province(region_id)
				if sp != null:
					_add_option(state, agent, out, kind, {"tipo": TARGET_PROVINCE, "id": sp.id}, Lang.t("Spia la provincia di %s") % WarProcessor.region_label(state, sp.id))
				for a in state.armies_in(region_id):
					_add_option(state, agent, out, kind, {"tipo": TARGET_ARMY, "id": a.id}, Lang.t("Spia l'esercito %d di %s") % [a.id, SimUtil.faction_label(a.faction)])
		elif kind == UNREST or kind == SABOTAGE or kind == GATES:
			var verbs := {UNREST: Lang.t("Fomenta il malcontento a %s"), SABOTAGE: Lang.t("Sabota un edificio a %s"), GATES: Lang.t("Apri le porte del castello di %s")}
			for region_id in reach(state, agent):
				if state.province(region_id) != null:
					_add_option(state, agent, out, kind, region_id, str(verbs[kind]) % WarProcessor.region_label(state, region_id))
		elif kind == TRIAL:
			for c in state.characters:
				if c.alive:
					_add_option(state, agent, out, kind, {"tipo": TARGET_CHARACTER, "id": c.id}, Lang.t("Processa %s (%s di %s)") % [c.full_name(), c.role, SimUtil.faction_label(c.faction)])
			for other in state.agents:
				_add_option(state, agent, out, kind, {"tipo": TARGET_AGENT, "id": other.id}, Lang.t("Processa l'agente %d (%s di %s)") % [other.id, other.type_name, SimUtil.faction_label(other.faction)])
		else:
			for c in state.characters:
				if c.alive:
					_add_option(state, agent, out, kind, {"tipo": TARGET_CHARACTER, "id": c.id}, Lang.t("Assassina %s (%s di %s)") % [c.full_name(), c.role, SimUtil.faction_label(c.faction)])
			for other in state.agents:
				_add_option(state, agent, out, kind, {"tipo": TARGET_AGENT, "id": other.id}, Lang.t("Assassina l'agente %d (%s di %s)") % [other.id, other.type_name, SimUtil.faction_label(other.faction)])
	return out


static func _add_option(state: GameState, agent: AgentState, out: Array[Dictionary], kind: String, target: Variant, label: String) -> void:
	var check := validate(state, agent, kind, target)
	if not bool(check["ok"]):
		return
	var price := 0
	var step := -1
	if kind == BRIBE:
		price = bribe_price(state, state.army(int(target)))
	elif kind == ASSASSINATE:
		var td: Dictionary = target
		step = kill_step(state, agent.valour, td)
	var entry := {
		"tipo": kind,
		"bersaglio": target,
		"regione": check["regione"],
		"etichetta": label,
		"probabilita": chance(state, agent, kind, target),
		"prezzo": price,
		"tesoro_sufficiente": state.faction(agent.faction).treasury >= price,
		"gradino": step,
	}
	out.append(entry)


static func _kind_label(kind: String) -> String:
	if kind == ALLIANCE:
		return Lang.t("Alleanza")
	if kind == TRUCE:
		return Lang.t("Tregua")
	return Lang.t("Matrimonio")


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "errore": message}
