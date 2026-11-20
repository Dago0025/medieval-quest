class_name AiTrade
extends RefCounted
## Commercio navale dell'IA (ADR-053, specifica «IA: viaggi lunghi degli agenti e commercio navale» del 2026-11-13). L'IA non
## ha regole proprie: la rendita la calcola la stessa funzione del giocatore (`Economy.sea_trade_of` / `trade_breakdown`,
## ADR-051) usata in modalita' «ipotesi» («e se presidiassi queste zone?»).
##
## Ogni `anni_ripianificazione` anni (il primo piano scaglionato tra le fazioni; subito se una flotta in guerra entra in una zona
## del piano o le flotte sono meno delle zone) la fazione sceglie le zone di mare da presidiare con una flotta ciascuna:
##   1. rotte candidate: per ogni proprio porto, il percorso piu' corto sulle zone di mare fino a ogni porto straniero con cui
##      si puo' commerciare (Dijkstra, peso 1 per zona piu' `costo_zona_contesa` se c'e' una flotta di una fazione in guerra);
##   2. scelta greedy per rotta intera (una catena a meta' non rende): guadagno della rotta / mantenimento delle flotte nuove
##      almeno `soglia_convenienza`, finche' bastano le flotte libere;
##   3. le zone scelte si salvano in `FactionState.ai_trade_zones`.
## Poi ogni zona riceve una flotta: resta quella che c'e' gia', altrimenti la flotta libera piu' vicina che ci arriva entro
## `anni_max_raggiungimento` anni. Se manca una flotta per una rotta che rende almeno `soglia_costruzione_nave` l'anno si mette
## in coda una nave. Le flotte che `AiNavy` ha gia' usato quest'anno (attacchi) non si toccano; nell'anno di uno sbarco le
## flotte restano ferme per non rompere il ponte. Regole PROVVISORIE, parametri in `data/regole/ia.cfg` [commercio_navale].

## Rotte valutate da sole (le piu' corte) e rotte valutate a fondo nella scelta greedy (le migliori da sole): tengono il piano
## di una fazione grande entro pochi millisecondi.
const MAX_SCORED := 12
const MAX_CANDIDATES := 6


## Chiamato da `AiFaction.plan` dopo `AiNavy.plan`.
static func plan(data: AiPlan) -> void:
	var state := data.state
	if not state.rules.sea_trade or data.provinces.is_empty():
		return
	var f := data.faction
	var fleets := _free_fleets(data)
	if _needs_replan(data, fleets):
		var result := plan_zones(data, fleets.size() + _busy_in_plan(data))
		f.ai_trade_zones = result["zone"]
		f.ai_trade_year = state.year
		if bool(result.get("serve_nave", false)):
			_build_ship(data)
	if f.ai_trade_zones.is_empty():
		return
	if _transport_this_year(data):
		return
	var uncovered := _assign(data, fleets)
	if uncovered > 0:
		_build_ship(data)


# --- pianificazione --------------------------------------------------------------------------------------------------


## Zone da presidiare per massimizzare il commercio via mare con al massimo `max_zones` flotte. Esito: "zone" (PackedStringArray,
## nell'ordine in cui sono entrate nel piano), "rendita" (commercio via mare stimato con il piano, fiorini l'anno), "base" (senza
## nessuna zona presidiata), "rotte" (Array di {"zone", "guadagno"} scelte), "serve_nave" (vero se una rotta rimasta fuori per
## mancanza di flotte renderebbe almeno `soglia_costruzione_nave`).
static func plan_zones(data: AiPlan, max_zones: int) -> Dictionary:
	var rules := data.rules
	var out := {"zone": PackedStringArray(), "rendita": 0, "base": 0, "rotte": [], "serve_nave": false}
	var ports := _own_ports(data)
	if ports.is_empty():
		return out
	var candidates := candidate_routes(data)
	if candidates.is_empty():
		return out
	candidates.sort_custom(func(x: PackedStringArray, y: PackedStringArray) -> bool: return x.size() < y.size())
	var weight := rules.behaviour_weight(data.profile, "commercio")
	var ship_cost := _ship_upkeep(data)
	var memo := {}
	# valutazione delle rotte da sole (senza zone presidiate il commercio via mare e' 0); senza flotte basta sapere se la
	# rotta piu' corta che rende varrebbe una nave nuova
	var scored: Array[Dictionary] = []
	var probes := 0
	for i in candidates.size():
		var route: PackedStringArray = candidates[i]
		if route.size() > max_zones:
			# rotta troppo lunga per le flotte che ci sono: conta solo per decidere se una nave in piu' la aprirebbe
			if route.size() > max_zones + 2 or probes >= 3:
				continue
			probes += 1
			var extra := _value(data, ports, _zone_set(route, {}), memo)
			if float(extra) * weight >= rules.trade_build_threshold:
				out["serve_nave"] = true
			continue
		if scored.size() >= MAX_SCORED:
			break
		var gain := _value(data, ports, _zone_set(route, {}), memo)
		if gain <= 0:
			continue
		scored.append({"zone": route, "guadagno": gain, "k": i,
				"r": float(gain) * weight / maxf(1.0, ship_cost * float(route.size()))})
	if max_zones <= 0 or scored.is_empty():
		return out
	scored.sort_custom(_by_ratio)
	if scored.size() > MAX_CANDIDATES:
		scored.resize(MAX_CANDIDATES)
	var chosen := {}
	var order := PackedStringArray()
	var current := 0
	var best_missing := 0
	while true:
		var best: Dictionary = {}
		var best_ratio := 0.0
		var best_total := 0
		for c in scored:
			var route2: PackedStringArray = c["zone"]
			var added := 0
			for z in route2:
				if not chosen.has(z):
					added += 1
			if added == 0:
				continue
			if chosen.size() + added > max_zones:
				best_missing = maxi(best_missing, int(c["guadagno"]))
				continue
			var total := _value(data, ports, _zone_set(route2, chosen), memo)
			var gain2 := total - current
			if gain2 <= 0:
				continue
			var ratio := float(gain2) * weight / maxf(1.0, ship_cost * float(added))
			if ratio > best_ratio:
				best_ratio = ratio
				best = c
				best_total = total
		if best.is_empty() or best_ratio < rules.trade_min_ratio:
			break
		var picked: PackedStringArray = best["zone"]
		for z in picked:
			if not chosen.has(z):
				chosen[z] = true
				order.append(z)
		(out["rotte"] as Array).append({"zone": picked, "guadagno": best_total - current})
		current = best_total
	out["zone"] = order
	out["rendita"] = current
	if float(best_missing) * weight >= rules.trade_build_threshold:
		out["serve_nave"] = true
	return out


## Commercio via mare (marittimo + importazioni) della fazione se fossero presidiate solo le zone `zones`: la stessa formula
## di `Economy.sea_trade_of` con l'ipotesi, ma calcolata solo per i porti che confinano con una zona dell'ipotesi (gli altri
## con l'ipotesi «solo queste zone» non raggiungono nessuno e valgono 0). Il valore di un porto dipende solo dalle zone
## dell'ipotesi collegate alle sue: `memo` lo ricorda per porto e insieme di zone collegate (la scelta greedy prova molte
## ipotesi che cambiano solo una parte della mappa).
static func _value(data: AiPlan, ports: Array[ProvinceState], zones: Dictionary, memo: Dictionary = {}) -> int:
	var state := data.state
	var total := 0
	for p in ports:
		var start := PackedStringArray()
		for z in data.ctx.sea_neighbours.get(p.id, PackedStringArray()):
			if zones.has(z):
				start.append(z)
		if start.is_empty():
			continue
		var linked := {}
		var queue: Array[String] = []
		for z in start:
			linked[z] = true
			queue.append(z)
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			for n in data.ctx.sea_neighbours.get(current, PackedStringArray()):
				if zones.has(n) and not linked.has(n):
					linked[n] = true
					queue.append(n)
		var keys := linked.keys()
		keys.sort()
		var key := p.id + "|" + ",".join(PackedStringArray(keys))
		if not memo.has(key):
			var parts := Economy.trade_breakdown(state, p, state.campaign.region(p.id), 1.0, _hypothesis(linked))
			memo[key] = int(parts["marittimo"]) + int(parts["importazioni"])
		total += int(memo[key])
	return total


static func _zone_set(route: PackedStringArray, base: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for z in route:
		out[z] = true
	return out


## Province proprie con il porto costruito.
static func _own_ports(data: AiPlan) -> Array[ProvinceState]:
	var state := data.state
	var out: Array[ProvinceState] = []
	for p in data.provinces:
		var region := state.campaign.region(p.id)
		if region != null and region.has_port and p.level_of(state.rules.port_family) > 0:
			out.append(p)
	return out


## Rotte candidate (PackedStringArray di zone di mare, dalla zona del proprio porto a quella del porto straniero), senza
## doppioni, nell'ordine dei propri porti e dei porti stranieri nel file.
static func candidate_routes(data: AiPlan) -> Array[PackedStringArray]:
	var state := data.state
	var out: Array[PackedStringArray] = []
	var seen := {}
	var partners: Array[String] = []
	for p in state.provinces:
		if p.owner == "" or p.owner == data.id or p.owner == GameState.REBEL or state.at_war(data.id, p.owner):
			continue
		var region := state.campaign.region(p.id)
		if region != null and region.has_port and p.level_of(state.rules.port_family) > 0:
			partners.append(p.id)
	if partners.is_empty():
		return out
	for own in data.provinces:
		var region := state.campaign.region(own.id)
		if region == null or not region.has_port or own.level_of(state.rules.port_family) <= 0:
			continue
		var search := _sea_search(data, region)
		var dist: Dictionary = search["dist"]
		var parent: Dictionary = search["padre"]
		var ends := {}
		for pid in partners:
			var target := state.campaign.region(pid)
			var best_zone := ""
			var best_d := INF
			for n in data.ctx.sea_neighbours.get(target.id, PackedStringArray()):
				if dist.has(n) and float(dist[n]) < best_d:
					best_d = float(dist[n])
					best_zone = n
			if best_zone == "" or ends.has(best_zone):
				continue   # stessa zona d'arrivo = stessa rotta
			ends[best_zone] = true
			var route := PackedStringArray()
			var at := best_zone
			var guard := 0
			while at != "" and guard < 64:
				guard += 1
				route.insert(0, at)
				at = str(parent.get(at, ""))
			var sorted := Array(route)
			sorted.sort()
			var key := ",".join(PackedStringArray(sorted))
			if seen.has(key):
				continue
			seen[key] = true
			out.append(route)
	return out


## Dijkstra sulle zone di mare a partire da quelle che confinano con il porto: {"dist": zona -> costo, "padre": zona -> zona
## precedente ("" per le zone di partenza)}. Peso di una zona: 1, piu' `costo_zona_contesa` con flotte di fazioni in guerra.
static func _sea_search(data: AiPlan, port_region: CampaignData.Region) -> Dictionary:
	var ctx := data.ctx
	var dist := {}
	var parent := {}
	var open: Array[String] = []
	for n in ctx.sea_neighbours.get(port_region.id, PackedStringArray()):
		dist[n] = _zone_cost(data, n)
		parent[n] = ""
		open.append(n)
	while not open.is_empty():
		var best_i := 0
		for i in range(1, open.size()):
			if float(dist[open[i]]) < float(dist[open[best_i]]):
				best_i = i
		var current := open[best_i]
		open.remove_at(best_i)
		for n in ctx.sea_neighbours.get(current, PackedStringArray()):
			var d := float(dist[current]) + _zone_cost(data, n)
			if not dist.has(n) or d < float(dist[n]):
				if not dist.has(n):
					open.append(n)
				dist[n] = d
				parent[n] = current
	return {"dist": dist, "padre": parent}


static func _zone_cost(data: AiPlan, zone: String) -> float:
	return 1.0 + (data.rules.trade_contested_cost if _contested(data, zone) else 0.0)


## Vero se nella zona c'e' una flotta di una fazione in guerra con questa.
static func _contested(data: AiPlan, zone: String) -> bool:
	for item in data.ctx.fleets_at(zone):
		var e: Army = item
		if e.faction != data.id and not e.stacks.is_empty() and data.state.at_war(data.id, e.faction):
			return true
	return false


## Ipotesi per `Economy.sea_trade_of`: contano solo le zone date (le flotte presenti no), cosi' piani diversi si confrontano
## tra loro indipendentemente da dove stanno oggi le flotte.
static func _hypothesis(zones: Dictionary) -> Dictionary:
	return {"zone": zones, "solo_ipotesi": true}


## Mantenimento annuo stimato di una flotta (media delle flotte proprie; senza flotte la nave piu' economica del file).
static func _ship_upkeep(data: AiPlan) -> float:
	var state := data.state
	var fleets := data.ctx.fleets_of(data.id)
	var total := 0
	var n := 0
	for item in fleets:
		var a: Army = item
		total += Economy.army_support_sum(state, a)
		n += 1
	if n > 0:
		return maxf(1.0, float(total) / float(n) * state.rules.upkeep_multiplier)
	var cheapest := INF
	for unit in state.units.units:
		if unit.is_ship() and float(unit.support_cost) < cheapest:
			cheapest = float(unit.support_cost)
	return maxf(1.0, (cheapest if cheapest < INF else 10.0) * state.rules.upkeep_multiplier)


static func _by_ratio(x: Dictionary, y: Dictionary) -> bool:
	if float(x["r"]) != float(y["r"]):
		return float(x["r"]) > float(y["r"])
	return int(x["k"]) < int(y["k"])


# --- quando ripianificare ----------------------------------------------------------------------------------------------


static func _needs_replan(data: AiPlan, fleets: Array[Army]) -> bool:
	var f := data.faction
	var every := maxi(1, data.rules.trade_replan_years)
	if f.ai_trade_year < 0:
		# primo piano scaglionato tra le fazioni (indice di dichiarazione): ogni anno ripianifica circa una fazione su `every`
		return (data.state.year + int(data.ctx.faction_index.get(data.id, 0))) % every == 0
	if data.state.year - f.ai_trade_year >= every:
		return true
	if f.ai_trade_zones.size() > fleets.size() + _busy_in_plan(data):
		return true   # una flotta del piano e' stata affondata, corrotta o usata altrove
	for z in f.ai_trade_zones:
		if _contested(data, z):
			return true
	return false


## Flotte proprie che quest'anno `AiNavy` ha gia' impegnato e che stanno in una zona del piano (contano come presidio).
static func _busy_in_plan(data: AiPlan) -> int:
	var n := 0
	var zones := {}
	for z in data.faction.ai_trade_zones:
		zones[z] = true
	for item in data.ctx.fleets_of(data.id):
		var a: Army = item
		if data.ctx.busy.has(a.id) and zones.has(a.region) and a.path.is_empty():
			n += 1
	return n


## Flotte proprie libere: senza ordini e non usate quest'anno da altri moduli, in ordine di id.
static func _free_fleets(data: AiPlan) -> Array[Army]:
	var out: Array[Army] = []
	for item in data.ctx.fleets_of(data.id):
		var a: Army = item
		if a.stacks.is_empty() or not a.path.is_empty() or data.ctx.busy.has(a.id):
			continue
		out.append(a)
	out.sort_custom(func(x: Army, y: Army) -> bool: return x.id < y.id)
	return out


## Vero se quest'anno un proprio esercito ha ordinato uno sbarco: le flotte fanno da ponte e non si spostano.
static func _transport_this_year(data: AiPlan) -> bool:
	for item in data.ctx.land_armies_of(data.id):
		var a: Army = item
		if not a.sea_route.is_empty():
			return true
	return false


# --- assegnazione delle flotte -----------------------------------------------------------------------------------------


## Una flotta per zona del piano: resta quella che c'e' gia', altrimenti la piu' vicina che ci arriva entro
## `anni_max_raggiungimento` anni (si muove di al massimo il suo raggio all'anno). Restituisce le zone rimaste senza flotta.
static func _assign(data: AiPlan, fleets: Array[Army]) -> int:
	var state := data.state
	var ctx := data.ctx
	var used := {}
	var covered := {}
	var zones := data.faction.ai_trade_zones
	for z in zones:
		for item in ctx.fleets_at(z):
			var a: Army = item
			if a.faction == data.id and not a.stacks.is_empty() and a.path.is_empty():
				if ctx.busy.has(a.id) or not used.has(a.id):
					covered[z] = true
					if not ctx.busy.has(a.id):
						used[a.id] = true
						ctx.busy[a.id] = true
					break
	var uncovered := 0
	for z in zones:
		if covered.has(z):
			continue
		var best: Army = null
		var best_route := PackedStringArray()
		for a in fleets:
			if used.has(a.id):
				continue
			var route := GameCommands.fleet_path(state, a.id, z)
			if route.is_empty():
				continue
			var reach := maxi(1, Combat.fleet_range(state, a))
			if route.size() > reach * data.rules.trade_reach_years:
				continue
			if best == null or route.size() < best_route.size():
				best = a
				best_route = route
		if best == null:
			uncovered += 1
			continue
		var reach2 := maxi(1, Combat.fleet_range(state, best))
		var step := best_route
		if step.size() > reach2:
			step = step.slice(0, reach2)
		if data.record(GameCommands.order_move(state, data.id, best.id, step), "commercio: flotta %d -> %s" % [best.id, z]):
			used[best.id] = true
			ctx.busy[best.id] = true
		else:
			uncovered += 1
	return uncovered


## Mette in coda una nave nel primo porto adatto (al massimo una all'anno e mai se ce n'e' gia' una in coda); spesa entro la
## meta' del tesoro oltre la riserva e il tetto del mantenimento, come `AiNavy`.
static func _build_ship(data: AiPlan) -> void:
	var state := data.state
	var ports: Array[ProvinceState] = []
	for p in data.provinces:
		var region := state.campaign.region(p.id)
		if region == null or not region.has_port:
			continue
		for q in p.unit_queue:
			var u := state.units.get_unit(q.key)
			if u != null and u.is_ship():
				return
		ports.append(p)
	var budget := float(data.faction.treasury - data.reserve) * 0.5
	if budget <= 0.0:
		return
	var support_room := data.num("tetto_mantenimento") * float(data.income) - float(data.upkeep)
	for p in ports:
		if p.unit_queue.size() >= data.rules.recruit_queue_max:
			continue
		var ship := AiEconomy.pick_unit(data, p, budget, support_room, true)
		if ship == null or not bool(GameCommands.can_queue_unit(state, data.id, p.id, ship.id)["ok"]):
			continue
		if data.record(GameCommands.queue_unit(state, data.id, p.id, ship.id), "commercio: nave %s %s" % [p.id, ship.id]):
			data.upkeep += ship.support_cost
			return
