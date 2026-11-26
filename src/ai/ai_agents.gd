class_name AiAgents
extends RefCounted
## Agenti dell'IA (fase 7b): reclutamento con un tetto per tipo in proporzione alle province e ordini agli agenti liberi.
##   - spie alla frontiera propria e nemica (e dove la fazione assedia: aprono le porte), una per regione;
##   - assassini contro i generali nemici (fazioni in guerra) e contro gli agenti stranieri nelle proprie terre;
##   - corruzione di eserciti di fazioni in guerra quando c'e' tesoro oltre la riserva (emissari rimasti liberi dalla diplomazia);
##   - religiosi nelle proprie province dove la religione del proprietario non e' la maggioranza, inquisitori dove crescono gli
##     eretici.
## Tutto passa dai comandi di `GameCommands` (`queue_unit`, `order_mission`, `order_agent_move`) dopo averne controllato la
## validita' con le stesse funzioni di `AgentMissions` (un comando rifiutato e' un difetto dell'IA). Regole PROVVISORIE, parametri
## in `data/regole/ia.cfg` ([agenti]). Gli agenti non cambiano regione durante la pianificazione: gli indici di `AiContext`
## (`characters_in`, `agents_in`) restano validi.

const GROUP_EMISSARY := "emissari"
const GROUP_SPY := "spie"
const GROUP_ASSASSIN := "assassini"
const GROUP_RELIGIOUS := "religiosi"
const GROUP_INQUISITOR := "inquisitori"
## Ordine in cui si assumono i gruppi.
const GROUP_ORDER := ["emissari", "spie", "assassini", "religiosi", "inquisitori"]
const GROUP_TYPES := {
	"emissari": ["EMISSARY"],
	"spie": ["SPY"],
	"assassini": ["ASSASSIN"],
	"religiosi": ["BISHOP", "CARDINAL", "PRIEST", "SHAMAN", "MONK", "ORTHODOX_BISHOP", "MULLAH", "ULAMA"],
	"inquisitori": ["INQUISITOR", "GRAND_INQUISITOR"],
}

## Cache delle unita' di agente reclutabili in una provincia: chiave (tabella, fazione, provincia, epoca, gruppo, edifici) -> elenco di
## UnitType che soddisfano fazione, epoca, regione, cultura ed edifici (restano da controllare coda e tesoro).
static var _option_cache := {}


# --- utilita' condivise con AiDiplomacy e AiCrusades ---------------------------------------------------------------


## Gruppo di reclutamento di un tipo di agente ("" per le principesse e per i tipi che l'IA non recluta).
static func group_of(type_name: String) -> String:
	for group in GROUP_ORDER:
		var types: Array = GROUP_TYPES[group]
		if types.has(type_name):
			return str(group)
	return ""


## Agenti della fazione (in ordine di id), calcolati una volta per piano.
static func own_agents(data: AiPlan) -> Array[AgentState]:
	if not data.own_agents_ready:
		data.own_agents = data.state.agents_of(data.id)
		data.own_agents_ready = true
	return data.own_agents


## Agenti liberi (vedi `AiPlan.is_agent_free`) del tipo indicato, in ordine di id.
static func free_of_type(data: AiPlan, type_name: String) -> Array[AgentState]:
	var out: Array[AgentState] = []
	for a in own_agents(data):
		if a.type_name == type_name and data.is_agent_free(a):
			out.append(a)
	return out


## Ricerca in ampiezza sulle regioni di terra da `start` fino a `radius` passi (gli agenti attraversano ogni territorio):
## {"padre": regione -> regione precedente (start -> ""), "ordine": regioni in ordine di scoperta (start escluso),
## "profondita": regione -> passi da start}.
static func bfs(ctx: AiContext, start: String, radius: int) -> Dictionary:
	var parent := {start: ""}
	var depth := {start: 0}
	var order: Array[String] = []
	var queue: Array[String] = [start]
	var i := 0
	while i < queue.size():
		var current := queue[i]
		i += 1
		if int(depth[current]) >= radius:
			continue
		for n in ctx.land_neighbours.get(current, PackedStringArray()):
			if parent.has(n):
				continue
			parent[n] = current
			depth[n] = int(depth[current]) + 1
			order.append(n)
			queue.append(n)
	return {"padre": parent, "ordine": order, "profondita": depth}


## Percorso da `start` a `goal` secondo la ricerca di `bfs` (il primo passo confina con `start`); vuoto se `goal` non e' stato trovato.
static func path_to(search: Dictionary, start: String, goal: String) -> PackedStringArray:
	var parent: Dictionary = search["padre"]
	var path := PackedStringArray()
	if goal == start or not parent.has(goal):
		return path
	var current := goal
	var guard := 0
	while current != start and guard < 64:
		guard += 1
		path.insert(0, current)
		current = str(parent.get(current, start))
	return path


## Vero se la regione `region_id` e' di `faction_id` o confina con una sua provincia: un agente li' ha la fazione a portata di missione.
static func touches(ctx: AiContext, region_id: String, faction_id: String) -> bool:
	if ctx.owner_of(region_id) == faction_id:
		return true
	for n in ctx.land_neighbours.get(region_id, PackedStringArray()):
		if ctx.owner_of(n) == faction_id:
			return true
	return false


## Manda l'agente verso la regione piu' vicina di `goals` (id regione -> true) entro `agent_radius` passi. Vero se l'ordine di
## movimento e' stato dato. Se l'agente e' gia' in una regione di `goals` non fa nulla e restituisce falso.
static func walk_toward(data: AiPlan, agent: AgentState, goals: Dictionary, label: String) -> bool:
	if goals.has(agent.region):
		return false
	var search := bfs(data.ctx, agent.region, data.rules.agent_radius)
	var order: Array = search["ordine"]
	for region_id in order:
		if goals.has(region_id):
			var path := path_to(search, agent.region, str(region_id))
			if path.is_empty():
				return false
			if data.record(GameCommands.order_agent_move(data.state, data.id, agent.id, path), "%s %d -> %s" % [label, agent.id, str(region_id)]):
				data.agents_used[agent.id] = true
				return true
			return false
	return false


# --- piano dell'anno ------------------------------------------------------------------------------------------------


## Chiamato da `AiFaction.plan` dopo la guerra e le crociate (la diplomazia ha gia' scelto gli emissari e le principesse).
static func plan(data: AiPlan) -> void:
	if data.provinces.is_empty():
		return
	_recruit(data)
	_assassins(data)
	_bribes(data)
	_spies(data)
	_religious(data)


# --- reclutamento ---------------------------------------------------------------------------------------------------


static func _quota(data: AiPlan, group: String) -> float:
	if group == GROUP_EMISSARY:
		return data.rules.cap_emissary
	if group == GROUP_SPY:
		return data.rules.cap_spy
	if group == GROUP_ASSASSIN:
		return data.rules.cap_assassin
	if group == GROUP_RELIGIOUS:
		return data.rules.cap_religious
	return data.rules.cap_inquisitor


## Province che chiamano religiosi (la religione del proprietario non e' la maggioranza, piu' deboli per prime) e inquisitori
## (eretici almeno `eretici_min` %, piu' eretici per prime): {"religiosi": Array[ProvinceState], "inquisitori": Array[ProvinceState]}.
static func needs(data: AiPlan) -> Dictionary:
	var state := data.state
	var religious: Array[Dictionary] = []
	var inquisitors: Array[Dictionary] = []
	for i in data.provinces.size():
		var p := data.provinces[i]
		var owner_rel := ReligionProcessor.owner_religion(state, p)
		if owner_rel != "" and p.majority_religion() != owner_rel:
			religious.append({"p": p, "score": 100.0 - p.religion_pct(owner_rel), "k": i})
		var heretics := p.religion_pct(ProvinceState.HERETIC)
		if heretics >= data.rules.heresy_min:
			inquisitors.append({"p": p, "score": heretics, "k": i})
	religious.sort_custom(AiEconomy.before)
	inquisitors.sort_custom(AiEconomy.before)
	var out_religious: Array[ProvinceState] = []
	for entry in religious:
		out_religious.append(entry["p"])
	var out_inquisitors: Array[ProvinceState] = []
	for entry in inquisitors:
		out_inquisitors.append(entry["p"])
	return {GROUP_RELIGIOUS: out_religious, GROUP_INQUISITOR: out_inquisitors}


## Tetto del gruppo: tetto x province (per eccesso); religiosi e inquisitori anche non oltre le province che ne hanno bisogno.
static func cap_of(data: AiPlan, group: String, need_lists: Dictionary) -> int:
	var cap := ceili(float(data.provinces.size()) * _quota(data, group))
	if data.rules.journey_caps.has(group):
		cap = mini(cap, int(data.rules.journey_caps[group]))   # tetto assoluto per fazione (ADR-053)
	if group == GROUP_RELIGIOUS or group == GROUP_INQUISITOR:
		var list: Array = need_lists.get(group, [])
		cap = mini(cap, list.size())
	return cap


static func _recruit(data: AiPlan) -> void:
	var state := data.state
	var rules := data.rules
	if data.income <= 0:
		return
	var budget := float(data.income) * rules.agent_budget * float(data.ctx.diff.get("budget", 1.0))
	budget = minf(budget, float(data.faction.treasury - data.reserve))
	if budget <= 0.0:
		return
	var counts := {}
	for a in own_agents(data):
		var g := group_of(a.type_name)
		if g != "":
			counts[g] = int(counts.get(g, 0)) + 1
	for p in data.provinces:
		for q in p.unit_queue:
			var queued := state.units.get_unit(q.key)
			if queued != null and queued.is_agent():
				var qg := group_of(queued.type_name)
				if qg != "":
					counts[qg] = int(counts.get(qg, 0)) + 1
	var need_lists := needs(data)
	var hired := 0
	for group in GROUP_ORDER:
		var cap := cap_of(data, str(group), need_lists)
		while hired < rules.agents_per_year and int(counts.get(group, 0)) < cap:
			var spent := _hire(data, str(group), need_lists, budget)
			if spent < 0:
				break
			budget -= float(spent)
			counts[group] = int(counts.get(group, 0)) + 1
			hired += 1
		if hired >= rules.agents_per_year:
			break


## Mette in coda un agente del gruppo nella prima provincia adatta (le province che ne hanno bisogno per prime). Restituisce il costo
## pagato, -1 se non e' stato possibile.
static func _hire(data: AiPlan, group: String, need_lists: Dictionary, budget: float) -> int:
	var state := data.state
	var order: Array[ProvinceState] = []
	var seen := {}
	if group == GROUP_RELIGIOUS or group == GROUP_INQUISITOR:
		var list: Array = need_lists.get(group, [])
		for item in list:
			var needy: ProvinceState = item
			order.append(needy)
			seen[needy.id] = true
	elif group == GROUP_EMISSARY:
		var capital := data.ctx.capital_of(data.id)
		for p in data.provinces:
			if p.id == capital:
				order.append(p)
				seen[p.id] = true
	else:
		for p in data.provinces:
			var t: Dictionary = data.threat.get(p.id, {})
			if bool(t.get("fronte", false)):
				order.append(p)
				seen[p.id] = true
	for p in data.provinces:
		if not seen.has(p.id):
			order.append(p)
	var tries := 0
	for province in order:
		if tries >= 6:
			break
		if province.unit_queue.size() >= data.rules.recruit_queue_max:
			continue
		tries += 1
		for u in _options(data, province, group):
			if float(u.cost) > budget:
				continue
			if not bool(GameCommands.can_queue_unit(state, data.id, province.id, u.id)["ok"]):
				continue
			if data.record(GameCommands.queue_unit(state, data.id, province.id, u.id), "agente %s %s" % [province.id, u.id]):
				return u.cost
			return -1
	return -1


## Unita' del gruppo che la fazione puo' reclutare nella provincia secondo fazione, epoca, regione, cultura ed edifici; dalla piu'
## economica. Memorizzate.
static func _options(data: AiPlan, p: ProvinceState, group: String) -> Array[UnitType]:
	var state := data.state
	var key := "%d|%s|%s|%s|%s|%s" % [state.units.get_instance_id(), data.id, p.id, state.era, group, str(p.buildings)]
	if _option_cache.has(key):
		var cached: Array = _option_cache[key]
		var again: Array[UnitType] = []
		for item in cached:
			again.append(item)
		return again
	var out: Array[UnitType] = []
	var region := state.campaign.region(p.id)
	if region != null:
		var culture := GameCommands.culture_key(region.culture)
		var types: Array = GROUP_TYPES[group]
		for type_name in types:
			for u in data.ctx.units_of_type(str(type_name)):
				var unit: UnitType = u
				if not unit.allows_faction(data.id) or not unit.available_in_period(state.era):
					continue
				if not unit.allows_region(region.id) or not unit.allows_culture(culture):
					continue
				if GameCommands.requirements_met(unit.requires, p, state.buildings):
					out.append(unit)
	out.sort_custom(_cheaper_first)
	if _option_cache.size() > 6000:
		_option_cache.clear()
	_option_cache[key] = out
	return out


static func _cheaper_first(x: UnitType, y: UnitType) -> bool:
	if x.cost != y.cost:
		return x.cost < y.cost
	return x.index < y.index


# --- assassini --------------------------------------------------------------------------------------------------------


## Ogni assassino libero colpisce il bersaglio migliore a portata (probabilita' x valore, almeno `p_min_assassinio`): un generale, il
## capo, un principe di una fazione in guerra, oppure un agente straniero nelle proprie province. Senza bersagli a portata va verso
## il generale nemico piu' vicino (una regione diversa per assassino).
static func _assassins(data: AiPlan) -> void:
	var state := data.state
	var ctx := data.ctx
	var ar := state.rules.agents
	var assassins := free_of_type(data, AgentState.ASSASSIN)
	if assassins.is_empty():
		return
	var chasing := {}
	for a in assassins:
		var best_target := {}
		var best_score := 0.0
		for region_id in AgentMissions.reach(state, a):
			for item in ctx.characters_in(region_id):
				var c: Character = item
				if c.faction == data.id or c.faction == GameState.REBEL or not state.at_war(data.id, c.faction):
					continue
				if c.role == Character.ROLE_PRINCESS:
					continue
				var target := {"tipo": AgentMissions.TARGET_CHARACTER, "id": c.id}
				if not bool(AgentMissions.validate(state, a, AgentMissions.ASSASSINATE, target)["ok"]):
					continue
				var p := ar.kill_chance(AgentMissions.kill_step(state, a.valour, target))
				if p < data.rules.assassin_min_p:
					continue
				var value := 1.0 + float(c.stars(state.rules, state.campaign))
				if c.role == Character.ROLE_LEADER:
					value += 3.0
				if p * value > best_score:
					best_score = p * value
					best_target = target
			if ctx.owner_of(region_id) != data.id:
				continue
			for item in ctx.agents_in(region_id):
				var other: AgentState = item
				if other.faction == data.id or state.is_allied(data.id, other.faction):
					continue
				var agent_target := {"tipo": AgentMissions.TARGET_AGENT, "id": other.id}
				if not bool(AgentMissions.validate(state, a, AgentMissions.ASSASSINATE, agent_target)["ok"]):
					continue
				var pa := ar.kill_chance(AgentMissions.kill_step(state, a.valour, agent_target))
				if pa < data.rules.assassin_min_p:
					continue
				var agent_value := 1.0 + 0.5 * float(maxi(0, other.valour))
				if pa * agent_value > best_score:
					best_score = pa * agent_value
					best_target = agent_target
		if not best_target.is_empty():
			if data.record(GameCommands.order_mission(state, data.id, a.id, AgentMissions.ASSASSINATE, best_target), "assassino %d" % a.id):
				data.agents_used[a.id] = true
			continue
		_chase(data, a, chasing)


## Senza bersagli a portata: l'assassino va verso la regione con il generale nemico piu' vicino (entro `raggio_agenti`).
static func _chase(data: AiPlan, a: AgentState, chasing: Dictionary) -> void:
	var state := data.state
	var ctx := data.ctx
	var goals := {}
	var search := bfs(ctx, a.region, data.rules.agent_radius)
	var order: Array = search["ordine"]
	for region_id in order:
		if chasing.has(region_id):
			continue
		for item in ctx.characters_in(str(region_id)):
			var c: Character = item
			if c.faction == data.id or c.faction == GameState.REBEL or not state.at_war(data.id, c.faction):
				continue
			if c.role == Character.ROLE_GENERAL or c.role == Character.ROLE_PRINCE or c.role == Character.ROLE_HEIR or c.role == Character.ROLE_LEADER:
				goals[str(region_id)] = true
				break
		if not goals.is_empty():
			break
	if goals.is_empty():
		return
	for region_id in goals:
		var path := path_to(search, a.region, str(region_id))
		if path.is_empty():
			return
		if data.record(GameCommands.order_agent_move(state, data.id, a.id, path), "assassino %d verso %s" % [a.id, str(region_id)]):
			data.agents_used[a.id] = true
			chasing[region_id] = true
		return


# --- corruzione -------------------------------------------------------------------------------------------------------


## Ogni emissario libero a portata di un esercito di una fazione in guerra lo corrompe se il prezzo sta nella quota del tesoro oltre
## la riserva e la probabilita' e' almeno `p_min_corruzione`: si sceglie il migliore per uomini x probabilita' / prezzo. Un emissario
## senza esercito a portata va verso il piu' vicino (entro `raggio_agenti`).
static func _bribes(data: AiPlan) -> void:
	var state := data.state
	var ctx := data.ctx
	var budget := float(data.faction.treasury - data.reserve) * data.rules.bribe_share
	if budget <= 0.0:
		return
	var enemies := state.enemies_of(data.id)
	if enemies.is_empty():
		return
	var emissaries := free_of_type(data, AgentState.EMISSARY)
	var bribed := {}
	for e in emissaries:
		var best_id := 0
		var best_score := 0.0
		var best_price := 0
		for region_id in AgentMissions.reach(state, e):
			for item in ctx.armies_at(region_id):
				var army: Army = item
				if army.faction == data.id or army.faction == GameState.REBEL or not enemies.has(army.faction) or bribed.has(army.id):
					continue
				if army.men_total() < data.rules.bribe_min_men:
					continue
				if AgentMissions.bribe_problem(state, data.id, army) != "":
					continue
				var price := AgentMissions.bribe_price(state, army)
				if float(price) > budget:
					continue
				var chance := AgentMissions.bribe_chance(state, army, e.valour)
				if chance < data.rules.bribe_min_p:
					continue
				if not bool(AgentMissions.validate(state, e, AgentMissions.BRIBE, army.id)["ok"]):
					continue
				var score := float(army.men_total()) * chance / float(price + 100)
				if score > best_score:
					best_score = score
					best_id = army.id
					best_price = price
		if best_id != 0:
			if data.record(GameCommands.order_mission(state, data.id, e.id, AgentMissions.BRIBE, best_id), "corruzione %d" % best_id):
				data.agents_used[e.id] = true
				bribed[best_id] = true
				budget -= float(best_price)
			continue
		var goals := {}
		var search := bfs(ctx, e.region, data.rules.agent_radius)
		var order: Array = search["ordine"]
		for region_id in order:
			for item in ctx.armies_at(str(region_id)):
				var enemy_army: Army = item
				if enemies.has(enemy_army.faction) and enemy_army.men_total() >= data.rules.bribe_min_men:
					goals[str(region_id)] = true
			if not goals.is_empty():
				break
		if not goals.is_empty():
			walk_toward(data, e, goals, "emissario")


# --- spie -------------------------------------------------------------------------------------------------------------


## Le spie libere si dispongono, una per regione, in quest'ordine di priorita': dove la fazione assedia un castello (aprono le
## porte), nelle province nemiche (di fazioni in guerra) che confinano con le proprie, nelle proprie province di frontiera.
static func _spies(data: AiPlan) -> void:
	var state := data.state
	var ctx := data.ctx
	var spies := free_of_type(data, AgentState.SPY)
	if spies.is_empty():
		return
	# missioni delle spie (18/11/2026, parita' con il giocatore): aprire le porte dei castelli assediati, poi nelle province
	# di fazioni in guerra sabotare (spie esperte) o fomentare il malcontento. Le altre si dispongono come prima.
	var still: Array[AgentState] = []
	for spy in spies:
		if not _spy_mission(data, spy):
			still.append(spy)
	spies = still
	if spies.is_empty():
		return
	var sieges := {}
	for key in state.sieges:
		var siege: SiegeState = state.sieges[key]
		if siege.faction == data.id:
			sieges[siege.region] = true
	var enemy_front := {}
	var own_front := {}
	for p in data.provinces:
		var t: Dictionary = data.threat.get(p.id, {})
		if not bool(t.get("fronte", false)):
			continue
		own_front[p.id] = true
		for n in ctx.land_neighbours.get(p.id, PackedStringArray()):
			if AiPolicy.target_kind(state, data.id, ctx.owner_of(n)) == AiPolicy.KIND_WAR:
				enemy_front[n] = true
	_station(data, spies, [sieges, enemy_front, own_front], "spia")


## Una missione per la spia, se ne trova una utile a portata: porte di un castello che la fazione assedia, oppure (in una
## provincia di una fazione in guerra) sabotaggio con valore almeno 5 e un edificio da colpire, altrimenti malcontento.
static func _spy_mission(data: AiPlan, spy: AgentState) -> bool:
	var state := data.state
	for region_id in AgentMissions.reach(state, spy):
		if bool(AgentMissions.validate(state, spy, AgentMissions.GATES, region_id)["ok"]):
			if data.record(GameCommands.order_mission(state, data.id, spy.id, AgentMissions.GATES, region_id), "porte %s" % region_id):
				data.agents_used[spy.id] = true
				return true
	var p := state.province(spy.region)
	if p == null or p.owner == data.id or not state.at_war(data.id, p.owner):
		return false
	var kind := AgentMissions.UNREST
	if spy.valour >= 5 and bool(AgentMissions.validate(state, spy, AgentMissions.SABOTAGE, p.id)["ok"]):
		kind = AgentMissions.SABOTAGE
	if not bool(AgentMissions.validate(state, spy, kind, p.id)["ok"]):
		return false
	if data.record(GameCommands.order_mission(state, data.id, spy.id, kind, p.id), "%s %s" % [kind, p.id]):
		data.agents_used[spy.id] = true
		return true
	return false


## Manda ogni agente libero alla regione piu' vicina dei gruppi di destinazione (in ordine di priorita'), una regione per agente.
## Le regioni dove gia' sta un altro agente dello stesso tipo (fermo o in viaggio) non si riassegnano.
static func _station(data: AiPlan, agents: Array[AgentState], groups: Array, label: String) -> void:
	var taken := {}
	var free_ids := {}
	for a in agents:
		free_ids[a.id] = true
	var group := group_of(agents[0].type_name)
	for other in own_agents(data):
		if group_of(other.type_name) != group or free_ids.has(other.id):
			continue
		if other.path.is_empty():
			taken[other.region] = true
		else:
			taken[other.path[other.path.size() - 1]] = true
	for a in agents:
		var stays := false
		for g in groups:
			var goals: Dictionary = g
			if goals.has(a.region) and not taken.has(a.region):
				stays = true
				break
		if stays:
			taken[a.region] = true
			data.agents_used[a.id] = true
			continue
		var search := bfs(data.ctx, a.region, data.rules.agent_radius)
		var order: Array = search["ordine"]
		var goal := ""
		for g in groups:
			var goals2: Dictionary = g
			for region_id in order:
				if goals2.has(region_id) and not taken.has(region_id):
					goal = str(region_id)
					break
			if goal != "":
				break
		if goal == "":
			continue
		var path := path_to(search, a.region, goal)
		if path.is_empty():
			continue
		if data.record(GameCommands.order_agent_move(data.state, data.id, a.id, path), "%s %d -> %s" % [label, a.id, goal]):
			taken[goal] = true
			data.agents_used[a.id] = true


# --- religiosi e inquisitori --------------------------------------------------------------------------------------------


## I religiosi liberi vanno nelle proprie province dove la religione del proprietario non e' la maggioranza, gli inquisitori dove gli
## eretici sono almeno `eretici_min` %: una provincia per agente, dalla piu' bisognosa.
static func _religious(data: AiPlan) -> void:
	var need_lists := needs(data)
	for group in [GROUP_RELIGIOUS, GROUP_INQUISITOR]:
		var wanted := {}
		var list: Array = need_lists.get(group, [])
		for item in list:
			var p: ProvinceState = item
			wanted[p.id] = true
		if wanted.is_empty():
			continue
		var agents: Array[AgentState] = []
		var types: Array = GROUP_TYPES[group]
		for t in types:
			agents.append_array(free_of_type(data, str(t)))
		if agents.is_empty():
			continue
		agents.sort_custom(_by_id)
		_station(data, agents, [wanted], "religioso")


static func _by_id(x: AgentState, y: AgentState) -> bool:
	return x.id < y.id
