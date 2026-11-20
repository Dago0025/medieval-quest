class_name AiForce
extends RefCounted
## Stime di forza dell'IA (fase 7a): la stessa formula di `Combat` (forza delle pile, stelle del capo, bonus del difensore e
## moltiplicatore del castello) senza casualita'. Il rapporto stimato = forza dell'attaccante / forza efficace del difensore.


## Stima dei difensori di `region_id` per l'attaccante `attacker`: gli eserciti di chiunque non sia l'attaccante o un suo
## alleato. Restituisce {"campo": forza fuori dal castello, "castello": forza della guarnigione, "totale": forza efficace
## (campo x (1 + bonus del difensore) + guarnigione x moltiplicatore del castello), "uomini", "eserciti"}. `foes` (fase 7b,
## id fazione -> true): alleati che si stanno per tradire, i cui eserciti contano come difensori.
static func defenders(ctx: AiContext, region_id: String, attacker: String, foes: Dictionary = {}) -> Dictionary:
	var state := ctx.state
	var c := state.rules.combat
	var field := 0.0
	var castle := 0.0
	var men := 0
	var count := 0
	for item in ctx.armies_at(region_id):
		var a: Army = item
		if a.faction == attacker or (state.is_allied(attacker, a.faction) and not foes.has(a.faction)):
			continue
		if a.in_castle:
			castle += ctx.force(a)
		else:
			field += ctx.force(a)
		men += a.men_total()
		count += 1
	var mult := c.castle_multiplier(Combat.castle_level(state, region_id))
	return {"campo": field, "castello": castle, "totale": field * (1.0 + c.defender_bonus) + castle * mult, "uomini": men, "eserciti": count}


## Forza efficace della guarnigione assediata di `region_id` in un assalto (forza x moltiplicatore del castello).
static func garrison_in_assault(ctx: AiContext, region_id: String) -> float:
	var total := 0.0
	for item in ctx.armies_at(region_id):
		var a: Army = item
		if a.in_castle:
			total += ctx.force(a)
	return total * ctx.state.rules.combat.castle_multiplier(Combat.castle_level(ctx.state, region_id))


## Rapporto attaccante / difensore (un difensore a forza zero dà un rapporto enorme).
static func ratio(attack_force: float, defence_force: float) -> float:
	if defence_force <= 0.0:
		return 1000000.0 if attack_force > 0.0 else 0.0
	return attack_force / defence_force


## Forza totale di un elenco di eserciti (Array di Army).
static func sum_force(ctx: AiContext, armies: Array) -> float:
	var total := 0.0
	for item in armies:
		var a: Army = item
		total += ctx.force(a)
	return total
