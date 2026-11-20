class_name AiProfiles
extends RefCounted
## Profili dell'IA (fase 7): i 17 comportamenti di `SetBehaviour` e i tre profili di stato che «vari fattori di gioco»
## attivano (commento dello startpos). Il profilo effettivo dell'anno sostituisce quello dello startpos quando valgono le
## condizioni di `ia.cfg` (soglie PROVVISORIE).

const REBELS := "REBELS"
const POPE := "POPE"
const RAIDER := "BARBARIAN_RAIDER"
const POVERTY := "POVERTY_STRICKEN"
const DESPERATE := "DESPERATE_DEFENCE"
const SUPPORT_LIMIT := "CLOSE_TO_SUPPORT_LIMIT"

## Profili che guardano tutti i non alleati come minaccia (espansionisti e predoni).
const EXPANSIONIST := ["CATHOLIC_EXPANSIONIST_CRUSADER", "CATHOLIC_EXPANSIONIST", "CATHOLIC_NAVAL_EXPANSIONIST", "ORTHODOX_EXPANSIONIST", "MUSLIM_EXPANSIONIST", "BARBARIAN_RAIDER"]
## Profili che, a scomunica gia' subita, non rispettano piu' gli avvertimenti papali (specifica 7a).
const AGGRESSIVE := ["CATHOLIC_EXPANSIONIST_CRUSADER", "CATHOLIC_EXPANSIONIST", "CATHOLIC_NAVAL_EXPANSIONIST", "BARBARIAN_RAIDER"]


static func is_expansionist(profile: String) -> bool:
	return EXPANSIONIST.has(profile)


static func is_aggressive(profile: String) -> bool:
	return AGGRESSIVE.has(profile)


## Comportamento di SetBehaviour della fazione, oppure il profilo predefinito se manca o non e' dichiarato in `ia.cfg`.
static func base(ctx: AiContext, faction_id: String) -> String:
	var cf := ctx.state.campaign.faction(faction_id)
	if cf != null and cf.behaviour != "" and ctx.rules.has_profile(cf.behaviour):
		return cf.behaviour
	return ctx.rules.default_profile


## Profilo effettivo dell'anno. I profili POPE, BARBARIAN_RAIDER e REBELS non cambiano. Altrimenti, in quest'ordine:
## DESPERATE_DEFENCE se le forze nemiche (fazioni in guerra, ribelli compresi) a un passo dalle sue province superano
## `rapporto_disperato` volte le proprie forze di terra; POVERTY_STRICKEN se il tesoro e' sotto `soglia_poverta` oppure il
## reddito netto stimato e' negativo con il tesoro sotto la riserva; CLOSE_TO_SUPPORT_LIMIT se il mantenimento (con le reclute
## in coda) supera `limite_mantenimento` volte il reddito.
static func effective(ctx: AiContext, faction_id: String) -> String:
	var profile := base(ctx, faction_id)
	if profile == POPE or profile == RAIDER or profile == REBELS:
		return profile
	var state := ctx.state
	var f := state.faction(faction_id)
	if f == null:
		return profile
	var rules := ctx.rules
	if state.provinces_of(faction_id).is_empty():
		return profile
	if _hostile_near_force(ctx, faction_id) > rules.desperate_ratio * maxf(_own_force(ctx, faction_id), 1.0):
		return DESPERATE
	var income := ctx.income_of(faction_id)
	var upkeep := ctx.upkeep_of(faction_id)
	var reserve := reserve_of(ctx, faction_id)
	if f.treasury < rules.poverty_treasury or (income - upkeep < 0 and f.treasury < reserve):
		return POVERTY
	if income > 0 and float(upkeep) > rules.support_limit * float(income):
		return SUPPORT_LIMIT
	return profile


## Riserva di tesoro che la fazione non spende: fissa piu' anni di mantenimento.
static func reserve_of(ctx: AiContext, faction_id: String) -> int:
	return ctx.rules.reserve_fixed + roundi(ctx.rules.reserve_upkeep_years * float(ctx.upkeep_of(faction_id, false)))


static func _own_force(ctx: AiContext, faction_id: String) -> float:
	var total := 0.0
	for item in ctx.land_armies_of(faction_id):
		var a: Army = item
		total += ctx.force(a)
	return total


## Forza degli eserciti di fazioni in guerra con `faction_id` (o dei ribelli) che stanno nelle sue province o in quelle
## confinanti; ogni esercito si conta una volta sola.
static func _hostile_near_force(ctx: AiContext, faction_id: String) -> float:
	var state := ctx.state
	var seen := {}
	var total := 0.0
	for p in state.provinces:
		if p.owner != faction_id:
			continue
		var region_ids := PackedStringArray([p.id])
		region_ids.append_array(ctx.land_neighbours.get(p.id, PackedStringArray()))
		for rid in region_ids:
			for item in ctx.armies_at(rid):
				var a: Army = item
				if a.faction == faction_id or seen.has(a.id) or not state.at_war(faction_id, a.faction):
					continue
				seen[a.id] = true
				total += ctx.force(a)
	return total
