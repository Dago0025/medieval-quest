class_name AiJourneys
extends RefCounted
## Viaggi lunghi degli agenti dell'IA (ADR-053, specifica «IA: viaggi lunghi degli agenti e commercio navale» del 2026-11-13).
## Gli agenti dell'IA usano gli stessi viaggi del giocatore (`AgentTravel`, `GameCommands.order_agent_move` con un solo passo
## fuori portata): a piedi una provincia all'anno o un trasporto via mare anche senza navi (ADR-034/035). Nessuna regola
## propria: percorsi, anni di viaggio, probabilita' di riuscita e validita' delle missioni sono quelli della simulazione.
##
## Due momenti nel piano di una fazione (`AiFaction.plan`):
##   - `continue_orders`, prima della diplomazia: gli agenti con un ordine di lungo periodo (`AgentState.ai_order`, salvato)
##     proseguono, eseguono la missione quando il bersaglio e' a portata, inseguono un bersaglio che si e' spostato (al
##     massimo `max_ricalcoli` volte), cambiano obiettivo se ne compare uno molto migliore (`isteresi`) o abbandonano un
##     ordine non piu' valido o scaduto (`scadenza_ordine` anni);
##   - `plan`, dopo gli agenti a corto raggio (`AiAgents`): gli agenti rimasti liberi scelgono l'obiettivo migliore entro
##     `anni_<tipo>` anni di viaggio con
##         punteggio = valore x comportamento x probabilita' / (1 + peso_tempo x anni) x (1 - rischio x anni in terra nemica)
##     e partono se supera `soglia_assegnazione`.
## Scelta di progetto: l'IA dell'originale usa male gli agenti (forum totalwar.org t-153680): qui li usa meglio apposta, e mai
## contro la propria fazione o gli alleati. Regole PROVVISORIE, parametri in `data/regole/ia.cfg` [viaggi_agenti].

## Ordine di presidio (spie, religiosi, inquisitori): il bersaglio e' la regione in cui stare.
const STATION := "presidio"
## Agenti liberi valutati per fazione e anno (a rotazione per id): tiene basso il costo del piano quando una fazione ha molti agenti
## fermi senza obiettivi; ognuno viene riconsiderato entro pochi anni.
const EVALS_PER_YEAR := 4


# --- ordini in corso ---------------------------------------------------------------------------------------------------


## Prima della diplomazia: fa proseguire, eseguire, inseguire o abbandonare gli ordini di lungo periodo degli agenti.
static func continue_orders(data: AiPlan) -> void:
	var state := data.state
	var sea_cache := sea_cache_for(data)
	var memo := {}
	var taken := _taken(data)
	for a in AiAgents.own_agents(data):
		if a.ai_order.is_empty():
			continue
		if a.has_mission() or not state.proposal_of_agent(a.id).is_empty():
			a.ai_order = {}
			continue
		var order := a.ai_order
		var kind := str(order.get("tipo", ""))
		if state.year - int(order.get("anno", state.year)) > data.rules.journey_expiry:
			_drop(data, a, "scaduto")
			continue
		var region := target_region(data, a, order)
		if region == "":
			_drop(data, a, "non valido")
			continue
		# un obiettivo nuovo molto migliore sostituisce quello in corso (isteresi)
		var group := group_of(a)
		if group != "":
			var current_key := key_of(order)
			var options := evaluate(data, a, group, sea_cache, taken, current_key, memo)
			if not options.is_empty():
				var best: Dictionary = options[0]
				var current_score := float(order.get("punteggio", 0.0))
				for o in options:
					if str(o["chiave"]) == current_key:
						current_score = float(o["punteggio"])
						break
				if str(best["chiave"]) != current_key and float(best["punteggio"]) > current_score * data.rules.journey_hysteresis:
					_release(taken, current_key)
					a.ai_order = {}
					if _assign(data, a, best, taken, "cambia obiettivo"):
						continue
					a.ai_order = order
					taken[current_key] = int(taken.get(current_key, 0)) + 1
		if kind != STATION:
			var target: Variant = order.get("bersaglio")
			if bool(AgentMissions.validate(state, a, kind, target)["ok"]):
				if _proposal_blocked(data, kind, target):
					data.agents_used[a.id] = true   # aspetta vicino al bersaglio che si liberi un posto per la proposta
					continue
				if data.record(GameCommands.order_mission(state, data.id, a.id, kind, target), "viaggio: %s %d" % [kind, a.id]):
					data.agents_used[a.id] = true
					if typeof(target) == TYPE_STRING:
						data.courting[str(target)] = true
				a.ai_order = {}
				continue
		elif a.region == region:
			a.ai_order = {}
			data.agents_used[a.id] = true   # arrivato: resta li' quest'anno
			continue
		if a.destination == region or (not a.path.is_empty() and a.path[a.path.size() - 1] == region):
			data.agents_used[a.id] = true   # in viaggio verso il bersaglio
			continue
		if a.region == region:
			data.agents_used[a.id] = true   # missione non ancora possibile (es. proposta bloccata): aspetta
			continue
		# il bersaglio si e' spostato o il viaggio si e' fermato: si ricalcola, al massimo `max_ricalcoli` volte
		if int(order.get("ricalcoli", 0)) >= data.rules.journey_max_recalcs:
			_drop(data, a, "troppi inseguimenti")
			continue
		if not a.path.is_empty() or a.destination != "":
			data.record(GameCommands.cancel_agent_move(state, data.id, a.id), "viaggio: ferma %d" % a.id)
		if data.record(GameCommands.order_agent_move(state, data.id, a.id, PackedStringArray([region])), "viaggio: insegue %d -> %s" % [a.id, region]):
			order["ricalcoli"] = int(order.get("ricalcoli", 0)) + 1
			order["regione"] = region
			a.ai_order = order
			data.agents_used[a.id] = true
		else:
			a.ai_order = {}


## Abbandona l'ordine dell'agente; se era in viaggio lo ferma (cosi' torna libero per un altro obiettivo quest'anno).
static func _drop(data: AiPlan, a: AgentState, why: String) -> void:
	a.ai_order = {}
	if not a.path.is_empty() or a.destination != "":
		data.record(GameCommands.cancel_agent_move(data.state, data.id, a.id), "viaggio: abbandona %d (%s)" % [a.id, why])


# --- nuovi ordini ------------------------------------------------------------------------------------------------------


## Dopo gli agenti a corto raggio: ogni agente ancora libero sceglie un obiettivo anche lontano e ci va.
static func plan(data: AiPlan) -> void:
	if data.provinces.is_empty():
		return
	var state := data.state
	var free: Array[AgentState] = []
	for a in AiAgents.own_agents(data):
		if not a.ai_order.is_empty() or not data.is_agent_free(a) or group_of(a) == "":
			continue
		if a.type_name == AgentState.PRINCESS and AgentMissions.princess_problem(state, a) != "":
			continue
		free.append(a)
	if free.is_empty():
		return
	if free.size() > EVALS_PER_YEAR:
		var start := state.year % free.size()
		var turn: Array[AgentState] = []
		for i in EVALS_PER_YEAR:
			turn.append(free[(start + i) % free.size()])
		turn.sort_custom(func(x: AgentState, y: AgentState) -> bool: return x.id < y.id)
		free = turn
	var taken := _taken(data)
	var guard := _home_guard(data, free)
	var sea_cache := sea_cache_for(data)
	var memo := {}
	for a in free:
		if a.id == guard:
			continue
		var options := evaluate(data, a, group_of(a), sea_cache, taken, "", memo)
		if options.is_empty():
			continue
		var best: Dictionary = options[0]
		if float(best["punteggio"]) < data.rules.journey_threshold:
			continue
		_assign(data, a, best, taken, "parte")


## Manda l'agente verso l'obiettivo `option` (voce di `evaluate`): missione subito se il bersaglio e' gia' a portata, altrimenti
## movimento o viaggio verso la sua regione; un presidio nella regione in cui l'agente gia' sta lo ferma li'. Vero se riuscito.
static func _assign(data: AiPlan, a: AgentState, option: Dictionary, taken: Dictionary, label: String) -> bool:
	var state := data.state
	var kind := str(option["tipo"])
	var target: Variant = option["bersaglio"]
	var region := str(option["regione"])
	var key := str(option["chiave"])
	if kind != STATION and bool(AgentMissions.validate(state, a, kind, target)["ok"]):
		if not data.record(GameCommands.order_mission(state, data.id, a.id, kind, target), "viaggio %s: %s %d" % [label, kind, a.id]):
			return false
		data.agents_used[a.id] = true
		taken[key] = int(taken.get(key, 0)) + 1
		if typeof(target) == TYPE_STRING:
			data.courting[str(target)] = true
		return true
	if kind == STATION and a.region == region:
		data.agents_used[a.id] = true
		taken[key] = int(taken.get(key, 0)) + 1
		return true
	if not a.path.is_empty() or a.destination != "":
		data.record(GameCommands.cancel_agent_move(state, data.id, a.id), "viaggio: ferma %d" % a.id)
	if not data.record(GameCommands.order_agent_move(state, data.id, a.id, PackedStringArray([region])), "viaggio %s: %d -> %s" % [label, a.id, region]):
		return false
	a.ai_order = {"tipo": kind, "bersaglio": target, "regione": region, "anno": state.year, "ricalcoli": 0,
			"punteggio": float(option["punteggio"])}
	data.agents_used[a.id] = true
	taken[key] = int(taken.get(key, 0)) + 1
	if typeof(target) == TYPE_STRING and kind != STATION:
		data.courting[str(target)] = true
	return true


## Cache delle destinazioni via mare degli agenti della fazione, condivisa nell'anno (`AiContext.journey_sea`). Con gli agenti
## che viaggiano senza navi e si imbarcano da ogni porto (ADR-034/035) le destinazioni dipendono solo dalle fazioni in guerra
## con questa (le loro flotte chiudono le zone): le fazioni con gli stessi nemici condividono la cache. Con gli oceani della mappa
## del mondo contano anche le flotte proprie: cache della sola fazione.
static func sea_cache_for(data: AiPlan) -> Dictionary:
	var combat := data.state.rules.combat
	var key := data.id
	if combat.agents_free_sea and combat.agents_any_port and not GameCommands.map_has_oceans(data.state):
		var enemies := Array(data.state.enemies_of(data.id))
		enemies.sort()
		key = "nemici:" + ",".join(PackedStringArray(enemies))
	if not data.ctx.journey_sea.has(key):
		data.ctx.journey_sea[key] = {}
	return data.ctx.journey_sea[key]


# --- obiettivi e punteggio ---------------------------------------------------------------------------------------------


## Gruppo dei viaggi (chiave di `AiRules.journey_years`) del tipo di agente: emissario, principessa, assassino, spia, religioso,
## inquisitore; "" per i tipi senza viaggi dell'IA (crociate, jihad).
static func group_of(a: AgentState) -> String:
	var t := a.type_name
	if t == AgentState.EMISSARY:
		return "emissario"
	if t == AgentState.PRINCESS:
		return "principessa"
	if t == AgentState.ASSASSIN:
		return "assassino"
	if t == AgentState.SPY:
		return "spia"
	if t == "INQUISITOR" or t == "GRAND_INQUISITOR":
		return "inquisitore"
	if AgentState.RELIGIOUS_TYPES.has(t):
		return "religioso"
	return ""


## Obiettivi dell'agente entro gli anni di viaggio del suo gruppo, con il punteggio, dal migliore (a parita' l'ordine di
## generazione, deterministico). Ogni voce: "tipo" (missione o `STATION`), "bersaglio", "regione", "anni", "valore",
## "probabilita", "punteggio", "chiave". I bersagli gia' presi da `max_agenti_per_bersaglio` agenti si saltano, tranne `keep`.
static func evaluate(data: AiPlan, a: AgentState, group: String, sea_cache: Dictionary, taken: Dictionary, keep: String = "", memo: Dictionary = {}) -> Array[Dictionary]:
	var rules := data.rules
	var max_years := int(rules.journey_years.get(group, 0))
	var out: Array[Dictionary] = []
	if max_years <= 0:
		return out
	var years := AgentTravel.years_from(data.state, data.id, a.region, max_years, sea_cache)
	var raw: Array[Dictionary] = []
	match group:
		"emissario":
			raw = _diplomacy_targets(data, a, years, false, memo)
		"principessa":
			raw = _diplomacy_targets(data, a, years, true, memo)
		"assassino":
			raw = _assassin_targets(data, a, years)
		"spia":
			raw = _spy_targets(data, years)
		"religioso":
			raw = _need_targets(data, years, AiAgents.GROUP_RELIGIOUS, "conversione", memo)
		"inquisitore":
			raw = _need_targets(data, years, AiAgents.GROUP_INQUISITOR, "inquisizione", memo)
	for i in raw.size():
		var c: Dictionary = raw[i]
		var key := key_of(c)
		if key != keep and int(taken.get(key, 0)) >= rules.journey_max_per_target:
			continue
		var travel := int(years.get(str(c["regione"]), -1))
		if travel < 0:
			continue
		var hostile := travel if data.state.at_war(data.id, data.ctx.owner_of(str(c["regione"]))) else 0
		var score := float(c["valore"]) * float(c["probabilita"]) / (1.0 + rules.journey_time_weight * float(travel))
		score *= maxf(0.0, 1.0 - rules.journey_hostile_risk * float(hostile))
		c["anni"] = travel
		c["punteggio"] = score
		c["chiave"] = key
		c["k"] = i
		out.append(c)
	out.sort_custom(_better)
	return out


static func _better(x: Dictionary, y: Dictionary) -> bool:
	if float(x["punteggio"]) != float(y["punteggio"]):
		return float(x["punteggio"]) > float(y["punteggio"])
	return int(x["k"]) < int(y["k"])


## Chiave del bersaglio (stessa missione sullo stesso bersaglio = stessa chiave) per il limite di agenti per bersaglio.
static func key_of(order: Dictionary) -> String:
	return "%s|%s" % [str(order.get("tipo", "")), str(order.get("bersaglio", ""))]


## Alleanze e tregue (emissari) o matrimoni (principesse) con fazioni anche lontane: alleanza e matrimonio con una fazione
## neutrale che ha un nemico comune o la stessa fede (come `AiDiplomacy.alliance_candidates`, senza il vincolo del confine),
## sotto `alleanze_max` alleati, con il tiro annuo di `prob_alleanza` e probabilita' di accettazione almeno `alleanza_p_min`; tregua con un nemico quando
## `AiDiplomacy.wants_truce`. La regione e' la provincia della fazione piu' vicina in anni di viaggio.
static func _diplomacy_targets(data: AiPlan, a: AgentState, years: Dictionary, marriage: bool, memo: Dictionary = {}) -> Array[Dictionary]:
	var state := data.state
	var rules := data.rules
	var out: Array[Dictionary] = []
	var weight := rules.behaviour_weight(data.profile, "diplomazia")
	var allies := 0
	for f in state.factions:
		if f.id != data.id and f.alive and state.is_allied(data.id, f.id):
			allies += 1
	var enemies := state.enemies_of(data.id)
	var my_religion := _religion(data, data.id, memo)
	for f in state.factions:
		if f.id == data.id or not f.alive or f.id == GameState.REBEL or f.id == GameState.PAPAL:
			continue
		if data.courting.has(f.id) or _proposal_blocked(data, AgentMissions.ALLIANCE, f.id):
			continue
		var player := rules.journey_player_weight if f.is_player else 1.0
		var rel := state.relation(data.id, f.id)
		if not marriage and rel == GameState.REL_WAR and _wants_truce(data, f.id, memo):
			var region_t := _nearest_of(data, f.id, years, memo)
			if region_t != "":
				var pt := _acceptance(data, DiplomacyProcessor.KIND_TRUCE, f.id, a.valour, memo)
				out.append({"tipo": AgentMissions.TRUCE, "bersaglio": f.id, "regione": region_t, "probabilita": pt,
						"valore": float(rules.journey_values["tregua"]) * weight * player})
			continue
		if rel != GameState.REL_NEUTRAL or allies >= rules.alliances_max:
			continue
		var common := false
		for enemy_id in enemies:
			if enemy_id != f.id and state.at_war(f.id, enemy_id):
				common = true
				break
		var same_faith := my_religion != "" and _religion(data, f.id, memo) == my_religion
		if not common and not same_faith:
			continue
		var region := _nearest_of(data, f.id, years, memo)
		if region == "":
			continue
		# stessa cadenza di `AiDiplomacy`: ogni anno si cerca l'alleanza con un candidato con probabilita' `prob_alleanza`
		var roll_key := "tiro|%s|%s" % [f.id, str(marriage)]
		if not memo.has(roll_key):
			memo[roll_key] = data.rng.randf() < rules.alliance_prob
		if not bool(memo[roll_key]):
			continue
		var kind := AgentMissions.MARRIAGE if marriage else AgentMissions.ALLIANCE
		var dk := DiplomacyProcessor.KIND_MARRIAGE if marriage else DiplomacyProcessor.KIND_ALLIANCE
		var p := _acceptance(data, dk, f.id, a.valour, memo)
		if p < rules.alliance_min_p:
			continue
		var value := float(rules.journey_values["matrimonio" if marriage else "alleanza"]) * weight * player
		if common:
			value *= 1.3   # PROVVISORIA: come in AiDiplomacy, un nemico comune e' il motivo migliore
		out.append({"tipo": kind, "bersaglio": f.id, "regione": region, "probabilita": p, "valore": value})
	return out


## Probabilita' di accettazione di una proposta (stessa funzione della simulazione), memorizzata nel piano dell'anno.
static func _acceptance(data: AiPlan, kind: String, faction_id: String, valour: int, memo: Dictionary) -> float:
	var key := "accetta|%s|%s|%d" % [kind, faction_id, valour]
	if not memo.has(key):
		memo[key] = DiplomacyProcessor.acceptance(data.state, kind, data.id, faction_id, valour)
	return float(memo[key])


static func _religion(data: AiPlan, faction_id: String, memo: Dictionary) -> String:
	var key := "fede|" + faction_id
	if not memo.has(key):
		memo[key] = ReligionProcessor.faction_religion(data.state, faction_id)
	return str(memo[key])


static func _wants_truce(data: AiPlan, enemy_id: String, memo: Dictionary) -> bool:
	var key := "tregua|" + enemy_id
	if not memo.has(key):
		memo[key] = AiDiplomacy.wants_truce(data, enemy_id)
	return bool(memo[key])


## Capi, eredi, principi e generali delle fazioni in guerra (mai la propria, gli alleati o i ribelli) e agenti stranieri nelle
## proprie province; probabilita' = tabella dell'assassino, almeno `p_min_assassinio`.
static func _assassin_targets(data: AiPlan, a: AgentState, years: Dictionary) -> Array[Dictionary]:
	var state := data.state
	var ctx := data.ctx
	var rules := data.rules
	var ar := state.rules.agents
	var out: Array[Dictionary] = []
	var weight := rules.behaviour_weight(data.profile, "assassinio")
	for enemy_id in state.enemies_of(data.id):
		if enemy_id == GameState.REBEL or state.is_allied(data.id, enemy_id):
			continue
		var enemy := state.faction(enemy_id)
		var player := rules.journey_player_weight if enemy != null and enemy.is_player else 1.0
		for item in ctx.chars_by_faction.get(enemy_id, []):
			var c: Character = item
			if not c.alive or c.role == Character.ROLE_PRINCESS:
				continue
			var region := ctx.char_region(c)
			if region == "" or not years.has(region):
				continue
			var value_key := "assassinio_generale"
			if c.role == Character.ROLE_LEADER:
				value_key = "assassinio_capo"
			elif c.role == Character.ROLE_HEIR:
				value_key = "assassinio_erede"
			var target := {"tipo": AgentMissions.TARGET_CHARACTER, "id": c.id}
			var p := ar.kill_chance(AgentMissions.kill_step(state, a.valour, target))
			if p < rules.assassin_min_p:
				continue
			out.append({"tipo": AgentMissions.ASSASSINATE, "bersaglio": target, "regione": region, "probabilita": p,
					"valore": float(rules.journey_values[value_key]) * weight * player})
	for p_own in data.provinces:
		if not years.has(p_own.id):
			continue
		for item in ctx.agents_in(p_own.id):
			var other: AgentState = item
			if other.faction == data.id or other.faction == GameState.REBEL or state.is_allied(data.id, other.faction):
				continue
			var agent_target := {"tipo": AgentMissions.TARGET_AGENT, "id": other.id}
			var pa := ar.kill_chance(AgentMissions.kill_step(state, a.valour, agent_target))
			if pa < rules.assassin_min_p:
				continue
			out.append({"tipo": AgentMissions.ASSASSINATE, "bersaglio": agent_target, "regione": p_own.id, "probabilita": pa,
					"valore": float(rules.journey_values["assassinio_agente"]) * weight})
	return out


## Province delle fazioni in guerra che confinano con le proprie, senza una propria spia (ferma o diretta li').
static func _spy_targets(data: AiPlan, years: Dictionary) -> Array[Dictionary]:
	var state := data.state
	var ctx := data.ctx
	var out: Array[Dictionary] = []
	var covered := _covered(data, [AgentState.SPY])
	var seen := {}
	for p in data.provinces:
		for n in ctx.land_neighbours.get(p.id, PackedStringArray()):
			if seen.has(n) or covered.has(n) or not years.has(n):
				continue
			var owner_id := ctx.owner_of(n)
			if owner_id == "" or owner_id == data.id or owner_id == GameState.REBEL or not state.at_war(data.id, owner_id):
				continue
			seen[n] = true
			out.append({"tipo": STATION, "bersaglio": n, "regione": n, "probabilita": 1.0,
					"valore": float(data.rules.journey_values["spionaggio"])})
	return out


## Province proprie che chiamano religiosi o inquisitori (`AiAgents.needs`), senza un agente dello stesso gruppo.
static func _need_targets(data: AiPlan, years: Dictionary, need_group: String, value_key: String, memo: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var types: Array = AiAgents.GROUP_TYPES[need_group]
	var covered := _covered(data, types)
	if not memo.has("bisogni"):
		memo["bisogni"] = AiAgents.needs(data)
	var lists: Dictionary = memo["bisogni"]
	for item in lists.get(need_group, []):
		var p: ProvinceState = item
		if covered.has(p.id) or not years.has(p.id):
			continue
		out.append({"tipo": STATION, "bersaglio": p.id, "regione": p.id, "probabilita": 1.0,
				"valore": float(data.rules.journey_values[value_key])})
	return out


## Regioni dove sta o e' diretto un proprio agente dei tipi indicati.
static func _covered(data: AiPlan, types: Array) -> Dictionary:
	var out := {}
	for a in AiAgents.own_agents(data):
		if not types.has(a.type_name):
			continue
		out[a.region] = true
		if a.destination != "":
			out[a.destination] = true
		elif not a.path.is_empty():
			out[a.path[a.path.size() - 1]] = true
	return out


## Provincia di `faction_id` piu' vicina in anni di viaggio ("" se nessuna e' raggiungibile); a parita' l'ordine del file.
static func _nearest_of(data: AiPlan, faction_id: String, years: Dictionary, memo: Dictionary = {}) -> String:
	var best := ""
	var best_years := 1 << 20
	var key := "province|" + faction_id
	if not memo.has(key):
		memo[key] = data.state.provinces_of(faction_id)
	for p in memo[key]:
		var y := int(years.get(p.id, -1))
		if y >= 0 and y < best_years:
			best = p.id
			best_years = y
	return best


## Regione in cui si trova ora il bersaglio dell'ordine, "" se l'ordine non e' piu' valido (bersaglio morto o sparito, pace
## firmata, alleanza gia' fatta, provincia non piu' da presidiare).
static func target_region(data: AiPlan, a: AgentState, order: Dictionary) -> String:
	var state := data.state
	var ctx := data.ctx
	var kind := str(order.get("tipo", ""))
	var target: Variant = order.get("bersaglio")
	var region := str(order.get("regione", ""))
	if kind == AgentMissions.ASSASSINATE:
		if typeof(target) != TYPE_DICTIONARY:
			return ""
		var td: Dictionary = target
		if str(td.get("tipo", "")) == AgentMissions.TARGET_CHARACTER:
			var c := state.character(int(td.get("id", 0)))
			if c == null or not c.alive or c.faction == data.id or not state.at_war(data.id, c.faction):
				return ""
			return ctx.char_region(c)
		var other := state.agent(int(td.get("id", 0)))
		if other == null or other.faction == data.id or state.is_allied(data.id, other.faction):
			return ""
		if ctx.owner_of(other.region) != data.id:
			return ""   # fuori dalle proprie terre non e' piu' una minaccia da inseguire
		return other.region
	if kind == AgentMissions.ALLIANCE or kind == AgentMissions.TRUCE or kind == AgentMissions.MARRIAGE:
		var faction_id := str(target)
		var f := state.faction(faction_id)
		if f == null or not f.alive:
			return ""
		var rel := state.relation(data.id, faction_id)
		if kind == AgentMissions.ALLIANCE and rel != GameState.REL_NEUTRAL:
			return ""
		if kind == AgentMissions.TRUCE and rel != GameState.REL_WAR:
			return ""
		if kind == AgentMissions.MARRIAGE and (rel == GameState.REL_WAR or AgentMissions.princess_problem(state, a) != ""):
			return ""
		if ctx.owner_of(region) == faction_id:
			return region
		var group := group_of(a)
		var years := AgentTravel.years_from(state, data.id, a.region, int(data.rules.journey_years.get(group, 0)), sea_cache_for(data))
		return _nearest_of(data, faction_id, years)
	if kind == STATION:
		var station := str(target)
		if a.type_name == AgentState.SPY:
			var owner_id := ctx.owner_of(station)
			return station if owner_id != "" and owner_id != data.id and state.at_war(data.id, owner_id) else ""
		var need_group := AiAgents.GROUP_INQUISITOR if group_of(a) == "inquisitore" else AiAgents.GROUP_RELIGIOUS
		for item in AiAgents.needs(data).get(need_group, []):
			var p: ProvinceState = item
			if p.id == station:
				return station
		return ""
	return ""


## Bersagli presi: chiave -> agenti della fazione con un ordine di lungo periodo o una missione su quel bersaglio.
static func _taken(data: AiPlan) -> Dictionary:
	var out := {}
	for a in AiAgents.own_agents(data):
		var key := ""
		if not a.ai_order.is_empty():
			key = key_of(a.ai_order)
		elif a.has_mission():
			key = key_of(a.mission)
		if key != "":
			out[key] = int(out.get(key, 0)) + 1
	return out


static func _release(taken: Dictionary, key: String) -> void:
	if taken.has(key):
		taken[key] = maxi(0, int(taken[key]) - 1)


## Vero se una proposta a un giocatore non si puo' mandare ora: ce n'e' gia' una uguale o troppe in attesa (come `AiDiplomacy`).
static func _proposal_blocked(data: AiPlan, kind: String, target: Variant) -> bool:
	if typeof(target) != TYPE_STRING:
		return false
	var f := data.state.faction(str(target))
	if f == null or not f.is_player:
		return false
	return data.state.has_proposal(data.id, f.id, kind) or data.state.proposals_for(f.id).size() >= data.rules.player_proposals_max


## Riserva difensiva: se un assassino di una fazione in guerra sta entro `raggio_minaccia` passi di terra dal capo o dall'erede,
## il primo assassino libero (id minore) resta a casa. Restituisce il suo id (0 se non serve).
static func _home_guard(data: AiPlan, free: Array[AgentState]) -> int:
	var guard: AgentState = null
	for a in free:
		if a.type_name == AgentState.ASSASSIN:
			guard = a
			break
	if guard == null:
		return 0
	var ctx := data.ctx
	var state := data.state
	for item in ctx.chars_by_faction.get(data.id, []):
		var c: Character = item
		if not c.alive or (c.role != Character.ROLE_LEADER and c.role != Character.ROLE_HEIR):
			continue
		var home := ctx.char_region(c)
		if home == "":
			continue
		var search := AiAgents.bfs(ctx, home, data.rules.journey_threat_radius)
		var regions: Array = [home]
		regions.append_array(search["ordine"])
		for region_id in regions:
			for item2 in ctx.agents_in(str(region_id)):
				var other: AgentState = item2
				if other.type_name == AgentState.ASSASSIN and other.faction != data.id and state.at_war(data.id, other.faction):
					return guard.id
	return 0
