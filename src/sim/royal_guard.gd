class_name RoyalGuard
extends RefCounted
## Guardia del capo (ADR-114, richiesta di Federico del 21/11/2026: «re sempre con unita' di cavalleria tranne nelle
## popolazioni americane, dove i cavalli non dovrebbero esserci prima dell'arrivo degli europei»). Regole in
## data/regole/storia.cfg [guardia] (`Rules.history`).
##
## A inizio partita e a ogni fine anno, per ogni personaggio vivo e libero di un ruolo con la guardia (di norma solo il capo):
## se il suo esercito non ha un'unita' a cavallo (a piedi per i popoli senza cavalli, `HistoricalLimits.horses_allowed`)
## riceve la guardia (`guard_unit`); il capo senza esercito ne riceve uno con la sola guardia in una sua provincia. Un
## esercito pieno cede la pila meno costosa a un esercito nuovo nella stessa regione, come la guardia degli Auror
## (`AurorUnits.ensure_king_guard`, che resta per i Corazzieri del Drago). Nessun sorteggio. PROVVISORIA: la guardia persa
## torna l'anno dopo senza costo.


static func ensure(state: GameState) -> void:
	if state.rules == null or not state.rules.history.guard_enabled or state.units == null:
		return
	var units_by_kind := {}   # "fazione|a cavallo" -> UnitType (o null)
	for c in state.characters:
		if not c.alive or c.faction == "" or c.faction == GameState.REBEL:
			continue
		if not state.rules.history.guard_for_role(c.role):
			continue
		if c.role != Character.ROLE_LEADER and not c.can_command(state.rules.dynasty, state.year + 1):
			continue
		if PrisonerProcessor.is_captive(c):
			continue
		var f := state.faction(c.faction)
		if f == null or not f.alive:
			continue
		var mounted := HistoricalLimits.horses_allowed(state, f.id)
		var cache_key := "%s|%s" % [f.id, mounted]
		if not units_by_kind.has(cache_key):
			units_by_kind[cache_key] = guard_unit(state, f.id, mounted)
		var unit: UnitType = units_by_kind[cache_key]
		if unit == null and mounted:
			# ADR-116: chi non ha cavalleria propria (Aztechi e Inca anche dopo l'arrivo dei cavalli) tiene la guardia a piedi
			var foot_key := "%s|false" % f.id
			if not units_by_kind.has(foot_key):
				units_by_kind[foot_key] = guard_unit(state, f.id, false)
			unit = units_by_kind[foot_key]
			mounted = false
		if unit == null:
			continue
		_give_guard(state, c, unit, mounted)


## Unita' della guardia della fazione: a cavallo (`mounted`) o a piedi. Prima l'unita' del capo della colonna 27, poi le
## unita' indicate per i generali (colonna 9: PREFERRED, OK), poi le altre; a parita' la piu' costosa, poi l'ordine del
## file. Solo truppe che la fazione puo' avere nell'epoca e con le invenzioni note, niente ordini militari ne' artiglieria;
## null se non ce n'e'.
static func guard_unit(state: GameState, faction_id: String, mounted: bool) -> UnitType:
	var key := SimUtil.norm(faction_id)
	var best: UnitType = null
	var best_score := -1
	for u in state.units.units:
		if not u.is_military() or u.is_ship() or u.elite or u.men <= 0:
			continue
		if u.type_name == UnitType.ARTILLERY or HistoricalLimits.is_mounted(u) != mounted:
			continue
		var leader_unit := u.leader_of.has(key)
		if not leader_unit and not u.allows_faction(key):
			continue
		if not u.available_in_period(state.era) or not HistoricalLimits.unit_allowed(state, key, u):
			continue
		if u.required_tokens().has(state.rules.papacy.order_building):
			continue   # niente cavalieri degli ordini militari (Templari, Ospitalieri) come guardia
		var score := mini(u.cost, 999999)
		if leader_unit:
			score += 3000000
		elif u.general_candidate == "PREFERRED":
			score += 2000000
		elif u.general_candidate == "OK":
			score += 1000000
		if score > best_score:
			best = u
			best_score = score
	return best


## Vero se l'esercito ha gia' un'unita' adatta alla guardia: a cavallo, oppure a piedi per chi non ha cavalli.
static func has_guard(state: GameState, army: Army, mounted: bool) -> bool:
	for st in army.stacks:
		var u := state.units.get_unit(st.unit_id)
		if u == null or not u.is_military() or u.is_ship():
			continue
		if HistoricalLimits.is_mounted(u) == mounted:
			return true
	return false


static func _give_guard(state: GameState, c: Character, unit: UnitType, mounted: bool) -> void:
	var army: Army = state.army(c.army) if c.army > 0 else null
	if army != null and (army.is_fleet or army.faction != c.faction):
		army = null
	if army != null and has_guard(state, army, mounted):
		return
	if army == null:
		if c.role != Character.ROLE_LEADER:
			return   # solo il capo riceve un esercito nuovo: gli altri restano liberi finche' non comandano
		var region := _home_for(state, c)
		if region == "":
			return
		army = state.create_army(c.faction, region, false)
		c.army = army.id
		c.region = region
	if army.is_full(state.rules.max_stacks):
		var cheapest := -1
		var cheapest_cost := 0
		for i in army.stacks.size():
			var u := state.units.get_unit(army.stacks[i].unit_id)
			var cost := u.cost if u != null else 0
			if cheapest < 0 or cost < cheapest_cost:
				cheapest = i
				cheapest_cost = cost
		var moved := army.stacks[cheapest]
		army.stacks.remove_at(cheapest)
		var other := state.create_army(c.faction, army.region, false)
		other.in_castle = army.in_castle
		other.stacks.append(moved)
	var stack := state.new_stack(c.faction, unit.id, unit.men)
	army.stacks.append(stack)
	state.add_event(GameState.EV_ROYAL_GUARD, {
		"fazione": c.faction,
		"regione": army.region,
		"personaggio": c.id,
		"unita": unit.id,
		"esercito": army.id,
		"uomini": stack.men,   # uomini creati (bilancio degli uomini nei test)
		"testo": (Lang.t("%s riceve una guardia a cavallo.") if mounted else Lang.t("%s riceve una guardia a piedi.")) % c.full_name(),
	})


## Dove nasce l'esercito del capo che non ne ha: la regione in cui si trova se e' sua, altrimenti la regione del capo dello
## startpos se e' ancora sua, altrimenti la prima provincia della fazione. "" se la fazione non ha province.
static func _home_for(state: GameState, c: Character) -> String:
	var here := state.province(state.character_region(c))
	if here != null and here.owner == c.faction:
		return here.id
	var cf := state.campaign.faction(c.faction) if state.campaign != null else null
	if cf != null and cf.leader_region != "":
		var capital := state.province(cf.leader_region)
		if capital != null and capital.owner == c.faction:
			return capital.id
	var owned := state.provinces_of(c.faction)
	return owned[0].id if not owned.is_empty() else ""
