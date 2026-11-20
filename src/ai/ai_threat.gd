class_name AiThreat
extends RefCounted
## Mappa delle minacce (fase 7a). Per ogni provincia della fazione: forza propria (eserciti di terra e guarnigione), forza
## nemica nella provincia e in quelle confinanti (eserciti di fazioni in guerra; i ribelli solo nella provincia stessa, perche' non si
## muovono; per i profili espansionisti anche di
## tutte le non alleate e senza tregua), se confina con una provincia attaccabile ("fronte"), se e' assediata, se e' la capitale.
## Si calcola una volta per fazione e anno da `AiFaction.plan`.


## PROVVISORIA: peso di un esercito neutrale nella minaccia (non e' in guerra: puo' attaccare, ma e' meno probabile).
const NEUTRAL_WEIGHT := 0.25


static func build(plan: AiPlan) -> void:
	var ctx := plan.ctx
	var state := plan.state
	var vigilant := AiProfiles.is_expansionist(plan.profile)
	var hostile_cache := {}
	var capital := ctx.capital_of(plan.id)
	plan.threat = {}
	plan.incoming = {}
	for item in ctx.land_armies_of(plan.id):
		var mine: Army = item
		if not mine.path.is_empty():
			var destination: String = mine.path[mine.path.size() - 1]
			plan.incoming[destination] = float(plan.incoming.get(destination, 0.0)) + ctx.force(mine)
	for p in plan.provinces:
		var own := ctx.own_force_in(p.id, plan.id)
		var enemy := 0.0
		var here := 0.0
		var front := false
		var region_ids := PackedStringArray([p.id])
		region_ids.append_array(ctx.land_neighbours.get(p.id, PackedStringArray()))
		for rid in region_ids:
			if rid != p.id and AiPolicy.target_kind(state, plan.id, ctx.owner_of(rid)) != "":
				front = true
			for entry in ctx.armies_at(rid):
				var a: Army = entry
				if a.faction == plan.id or not _is_hostile(plan, a.faction, vigilant, hostile_cache):
					continue
				if rid != p.id and a.faction == GameState.REBEL:
					continue   # i ribelli non ricevono ordini (profilo REBELS): non escono dalla loro provincia
				# PROVVISORIA: i neutrali (contano solo per i profili espansionisti) pesano un quarto di un nemico in guerra
				var weight := 1.0 if plan.state.at_war(plan.id, a.faction) else NEUTRAL_WEIGHT
				enemy += ctx.force(a) * weight
				if rid == p.id and not a.in_castle:
					here += ctx.force(a) * weight
		var siege := state.siege_in(p.id)
		plan.threat[p.id] = {
			"propria": own,
			"nemica": enemy,
			"qui": here,
			"fronte": front,
			"assedio": siege != null and siege.faction != plan.id,
			"capitale": p.id == capital,
		}


static func _is_hostile(plan: AiPlan, other: String, vigilant: bool, cache: Dictionary) -> bool:
	if cache.has(other):
		return bool(cache[other])
	var hostile := plan.state.at_war(plan.id, other)
	if not hostile and vigilant:
		hostile = plan.state.relation(plan.id, other) == GameState.REL_NEUTRAL
	cache[other] = hostile
	return hostile
