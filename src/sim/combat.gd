class_name Combat
extends RefCounted
## Risoluzione automatica degli scontri (spec. fase 3 §4, ADR-009). TUTTE le formule sono
## PROVVISORIE (catalogo r.105: la formula di MTW non e' documentata); i parametri stanno in
## data/regole/scontri.cfg e si leggono da `state.rules.combat` (CombatRules).
##
##   forza pila (terra)  = uomini x (1 + a x (carica + mischia + difesa + armi) + b x (armatura + livello armatura)
##                                     + c x valore + d x morale)            (minimo: fattore_minimo)
##   (armi e livello armatura: potenziamenti della pila dagli edifici, TroopUpgrades, da 0 a 4)
##   forza pila (nave)   = uomini x (1 + e x attacco navale)
##   forza esercito      = somma delle pile x (1 + f x stelle del capo)
##   forza del difensore = forza x (1 + g) in campo, x moltiplicatore del castello negli assalti
##   attaccante vince con probabilita' Fa^2 / (Fa^2 + Fd^2), un numero di state.rng
##   perdente perde      = perdita_min + (perdita_max - perdita_min) x Fv / (Fv + Fp)
##   vincitore perde     = quella frazione x (Fp / Fv) x fattore_vincitore, al massimo perdita_max
##   vincitore: ogni pila sopravvissuta guadagna +1 valore con probabilita' prob_valore (max 9)
##
## Ordine dei numeri casuali di una battaglia: prima il tiro dell'esito, poi un tiro per ogni pila
## sopravvissuta del vincitore (eserciti in ordine di id, pile nell'ordine dell'esercito).
## Le ritirate e le conquiste non sono qui: le gestisce `WarProcessor`.


# --- forza -----------------------------------------------------------------------------


## Stelle di comando del comandante dell'esercito (fase 4a: comando efficace con titolo, carica, vizi e virtu';
## 9 per gli Auror, comando fisso). Senza comandante (mondi senza personaggi, flotte nuove) valgono le stelle
## dei parametri: solo le fazioni con `comando_fisso` (Auror) ne hanno, le altre 0.
static func command_stars(state: GameState, army: Army) -> int:
	if army.is_fleet:
		var admiral := Admirals.stars(state, army)   # ADR-056: la flotta combatte con le stelle del suo ammiraglio
		if admiral >= 0:
			return admiral
	var commander := state.commander_of(army.id)
	if commander != null:
		return commander.stars(state.rules, state.campaign)
	return state.rules.combat.command_stars(army.faction)


## Forza di una pila. Un tipo di unita' sconosciuto vale uomini x 1.
static func stack_strength(state: GameState, stack: UnitStack) -> float:
	var c := state.rules.combat
	var unit: UnitType = state.units.get_unit(stack.unit_id)
	if unit == null:
		return float(stack.men)
	var factor := 1.0
	if unit.is_ship():
		factor += c.naval_weight * float(unit.ship_attack)
	else:
		factor += c.attack_weight * float(unit.charge_bonus + unit.melee_bonus + unit.defence_bonus)
		factor += c.armour_weight * float(unit.armour_level + stack.armour)   # armatura del tipo + livello dagli edifici
		factor += c.attack_weight * float(stack.weapon)                     # ogni livello di armi: un punto di attacco
		factor += c.valour_weight * float(stack.value)
		factor += c.morale_weight * float(unit.moral_bonus)
	return float(stack.men) * maxf(factor, c.min_factor) * unit.strength_multiplier   # ADR-074: unita' esclusive degli Auror


## Forza di un esercito o di una flotta, con le stelle del capo.
static func army_strength(state: GameState, army: Army) -> float:
	var total := 0.0
	var traits := state.rules.traits
	for s in army.stacks:
		var f := traits.strength_factor(army.faction, state.units.get_unit(s.unit_id)) if state.units != null else 1.0   # ADR-089
		total += stack_strength(state, s) * f
	return total * (1.0 + state.rules.combat.star_weight * float(command_stars(state, army)))


## Forza di una parte (somma degli eserciti), senza bonus del difensore.
static func side_strength(state: GameState, armies: Array[Army]) -> float:
	var total := 0.0
	for a in armies:
		total += army_strength(state, a)
	return total


static func men_of(armies: Array[Army]) -> int:
	var total := 0
	for a in armies:
		total += a.men_total()
	return total


## Probabilita' che vinca l'attaccante: Fa^2 / (Fa^2 + Fd^2); 0,5 se entrambe le forze sono zero.
static func win_probability(attacker_strength: float, defender_strength: float) -> float:
	var fa := attacker_strength * attacker_strength
	var fd := defender_strength * defender_strength
	if fa + fd <= 0.0:
		return 0.5
	return fa / (fa + fd)


## Frazioni di perdita {"perdente", "vincitore"} dato il rapporto di forze (Fv forza del vincitore,
## Fp del perdente, bonus compresi).
static func loss_fractions(winner_strength: float, loser_strength: float, rules: CombatRules) -> Dictionary:
	var total := winner_strength + loser_strength
	var share := 0.5
	if total > 0.0:
		share = winner_strength / total
	var loser := rules.loss_min + (rules.loss_max - rules.loss_min) * share
	var winner := 0.0
	if winner_strength > 0.0:
		winner = minf(loser * (loser_strength / winner_strength) * rules.winner_loss_factor, rules.loss_max)
	return {"perdente": loser, "vincitore": winner}


## Moltiplicatore della forza del difensore: bonus del difensore (campo, sortita e mare) o
## moltiplicatore del castello (assalto, a seconda del livello del castello).
static func defender_multiplier(state: GameState, kind: String, level_of_castle: int) -> float:
	var c := state.rules.combat
	if kind == BattleResult.KIND_ASSAULT:
		return c.castle_multiplier(level_of_castle)
	if kind == BattleResult.KIND_NAVAL:
		return 1.0 + c.sea_defender_bonus
	return 1.0 + c.defender_bonus


# --- guarnigioni e castelli --------------------------------------------------------------


## Zone di mare che la flotta percorre in un anno (CombatRules: raggio minore tra le navi, bonus della bussola). 1 per gli
## eserciti di terra.
static func fleet_range(state: GameState, army: Army) -> int:
	if not army.is_fleet:
		return 1
	var c := state.rules.combat
	var best := -1
	for st in army.stacks:
		var unit := state.units.get_unit(st.unit_id) if state.units != null else null
		var r := unit.ship_range if unit != null and unit.is_ship_data else c.fleet_min_range
		best = r if best < 0 else mini(best, r)
	var out := maxi(c.fleet_min_range, best)
	if c.compass_bonus != 0 and compass_known(state):
		out += c.compass_bonus
	return out


## Profondita' di una zona di mare (distanza dalla costa, 18/11/2026): 1 se confina con una regione di terra, 2 se confina
## con una zona di profondita' 1, 3 oltre. Calcolata una volta per mappa. 0 per le regioni di terra o sconosciute.
static var _depths := {}
static var _depths_owner := 0

static func sea_depth(campaign: CampaignData, zone_id: String) -> int:
	if campaign == null:
		return 0
	if _depths_owner != campaign.get_instance_id():
		_depths = _compute_depths(campaign)
		_depths_owner = campaign.get_instance_id()
	return int(_depths.get(SimUtil.norm(zone_id), 0))


static func _compute_depths(campaign: CampaignData) -> Dictionary:
	var out := {}
	var seas: Array = []
	for r in campaign.regions:
		if r.is_sea:
			seas.append(r)
	for r in seas:
		for n in r.neighbours:
			var other := campaign.region(n)
			if other != null and not other.is_sea:
				out[r.id] = 1
				break
	for r in seas:
		if out.has(r.id):
			continue
		for n in r.neighbours:
			if int(out.get(SimUtil.norm(n), 0)) == 1:
				out[r.id] = 2
				break
	for r in seas:
		if not out.has(r.id):
			out[r.id] = 3
	return out


## Quanto lontano dalla costa puo' andare la flotta: il raggio minore delle sue navi (senza la bussola), almeno
## `fleet_min_range`. Senza navi (o non flotta) nessun limite.
static func fleet_depth(state: GameState, army: Army) -> int:
	if army == null or not army.is_fleet or army.stacks.is_empty():
		return 99
	var c := state.rules.combat
	var best := 99
	for st in army.stacks:
		var unit := state.units.get_unit(st.unit_id) if state.units != null else null
		var r := unit.ship_range if unit != null and unit.is_ship_data else c.fleet_min_range
		best = mini(best, r)
	return maxi(c.fleet_min_range, best)


## Vero se la flotta puo' entrare nella zona di mare (limite dalla costa, `limite_costa` di scontri.cfg).
static func can_enter(state: GameState, army: Army, zone_id: String) -> bool:
	if not state.rules.combat.coast_limit or army == null or not army.is_fleet:
		return true
	return sea_depth(state.campaign, zone_id) <= fleet_depth(state, army)


## Vero se l'evento storico della bussola e' gia' accaduto.
static func compass_known(state: GameState) -> bool:
	var key := state.rules.combat.compass_event.to_upper()
	if key == "":
		return false
	for e in state.rules.events.history:
		if e.key.to_upper() == key:
			return state.historical_done.has(e.index)
	return false


## Livello del castello della provincia (0 = nessun castello).
static func castle_level(state: GameState, region_id: String) -> int:
	var p := state.province(region_id)
	if p == null:
		return 0
	return p.level_of(state.rules.combat.castle_family)


## Peso di un esercito in guarnigione: una unita' per pila, la cavalleria conta doppio (catalogo r.103).
static func garrison_weight(state: GameState, army: Army) -> int:
	var c := state.rules.combat
	var total := 0
	for s in army.stacks:
		var unit: UnitType = state.units.get_unit(s.unit_id)
		if unit != null and unit.is_cavalry():
			total += c.cavalry_garrison_weight
		else:
			total += 1
	return total


## Peso totale della guarnigione gia' nel castello della regione.
static func garrison_load(state: GameState, region_id: String) -> int:
	var total := 0
	for a in state.armies_in(region_id):
		if a.in_castle and not a.is_fleet:
			total += garrison_weight(state, a)
	return total


## Anni di assedio ancora necessari prima che la guarnigione ceda per fame (0 = cede quest'anno
## o non c'e' un castello). Per l'interfaccia.
static func years_to_starve(state: GameState, siege: SiegeState) -> int:
	var limit := state.rules.combat.starve_after(castle_level(state, siege.region))
	return maxi(0, limit - siege.years)


# --- perdite -----------------------------------------------------------------------------


## Toglie dagli eserciti una frazione degli uomini, distribuita sulle pile in proporzione agli uomini
## (resto maggiore: il totale perso e' round(uomini x frazione), senza mai superare gli uomini di una
## pila). Le pile rimaste senza uomini spariscono dall'esercito; gli eserciti vuoti restano nella lista
## (li toglie il chiamante). Restituisce gli uomini persi.
static func apply_losses(armies: Array[Army], fraction: float) -> int:
	var frac := clampf(fraction, 0.0, 1.0)
	var stacks: Array[UnitStack] = []
	var total := 0
	for a in armies:
		for s in a.stacks:
			stacks.append(s)
			total += s.men
	if total <= 0 or frac <= 0.0:
		return 0
	var loss: Array[int] = []
	var remainder: Array[float] = []
	var assigned := 0
	for s in stacks:
		var exact := float(s.men) * frac
		var whole := mini(s.men, floori(exact))
		loss.append(whole)
		remainder.append(exact - float(whole))
		assigned += whole
	var target := maxi(assigned, mini(total, roundi(float(total) * frac)))
	while assigned < target:
		var best := -1
		var best_remainder := -1.0
		for i in stacks.size():
			if loss[i] < stacks[i].men and remainder[i] > best_remainder:
				best = i
				best_remainder = remainder[i]
		if best < 0:
			break
		loss[best] += 1
		remainder[best] = -0.5
		assigned += 1
	for i in stacks.size():
		stacks[i].men -= loss[i]
	for a in armies:
		for i in range(a.stacks.size() - 1, -1, -1):
			if a.stacks[i].men < 1:
				a.stacks.remove_at(i)
	return assigned


# --- battaglia ---------------------------------------------------------------------------


## Risolve uno scontro tra due parti (ognuna di una sola fazione). `kind` e' una BattleResult.KIND_*.
## `defender_mult` e' il moltiplicatore della forza del difensore (vedi `defender_multiplier`).
## Modifica lo stato: perdite, valore dei vincitori, eserciti rimasti senza pile tolti da `state.armies`.
## Non muove nessuno: le ritirate sono compito del chiamante.
## Nell'assalto (difensore = guarnigione) e nella sortita (attaccante = guarnigione) una guarnigione
## sconfitta e' annientata: perde il 100% (manuale p31; per l'assalto vedi `assalto_annienta`).
static func resolve(state: GameState, region_id: String, attackers: Array[Army], defenders: Array[Army], kind: String, defender_mult: float) -> BattleResult:
	var c := state.rules.combat
	var r := BattleResult.new()
	r.kind = kind
	r.region = SimUtil.norm(region_id)
	if not attackers.is_empty():
		r.attacker_faction = attackers[0].faction
	if not defenders.is_empty():
		r.defender_faction = defenders[0].faction
	for a in attackers:
		r.attacker_army_ids.append(a.id)
	for a in defenders:
		r.defender_army_ids.append(a.id)
	r.attacker_men_before = men_of(attackers)
	r.defender_men_before = men_of(defenders)
	r.attacker_strength = side_strength(state, attackers)
	r.defender_base_strength = side_strength(state, defenders)
	r.defender_multiplier = defender_mult
	r.defender_strength = r.defender_base_strength * defender_mult
	r.attacker_win_probability = win_probability(r.attacker_strength, r.defender_strength)
	r.roll = state.rng.randf()
	r.attacker_won = r.roll < r.attacker_win_probability
	if c.forced_outcome > 0:
		r.attacker_won = true
	elif c.forced_outcome < 0:
		r.attacker_won = false
	var winner_strength := r.defender_strength
	var loser_strength := r.attacker_strength
	if r.attacker_won:
		winner_strength = r.attacker_strength
		loser_strength = r.defender_strength
	var fractions := loss_fractions(winner_strength, loser_strength, c)
	var loser_fraction: float = fractions["perdente"]
	var winner_fraction: float = fractions["vincitore"]
	var garrison_lost := (kind == BattleResult.KIND_ASSAULT and r.attacker_won) or (kind == BattleResult.KIND_SALLY and not r.attacker_won)
	if garrison_lost and (kind == BattleResult.KIND_SALLY or c.assault_annihilates):
		loser_fraction = 1.0
	var winners := defenders
	var losers := attackers
	if r.attacker_won:
		winners = attackers
		losers = defenders
		r.attacker_loss_fraction = winner_fraction
		r.defender_loss_fraction = loser_fraction
	else:
		r.attacker_loss_fraction = loser_fraction
		r.defender_loss_fraction = winner_fraction
	r.attacker_losses = apply_losses(attackers, r.attacker_loss_fraction)
	r.defender_losses = apply_losses(defenders, r.defender_loss_fraction)
	# valore: un tiro per ogni pila sopravvissuta del vincitore, sempre (anche al massimo)
	for a in winners:
		for s in a.stacks:
			var gain := state.rng.randf() < c.valour_chance
			if gain and s.value < c.valour_max:
				s.value += 1
	for a in losers:
		if a.stacks.is_empty():
			state.remove_army(a)
	for a in winners:
		if a.stacks.is_empty():
			state.remove_army(a)
	return r
