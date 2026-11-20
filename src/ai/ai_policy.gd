class_name AiPolicy
extends RefCounted
## Chi l'IA puo' attaccare (fase 7a): mai alleati ne' fazioni in tregua; bersagli ammessi dal profilo; avvertimenti papali
## rispettati salvo i profili aggressivi a scomunica gia' subita (specifica 7a); il Papato non si attacca da cattolici.

const KIND_REBEL := "ribelle"
const KIND_WAR := "guerra"
const KIND_NEUTRAL := "neutrale"
## Fase 7b: un alleato che il piano ha deciso di tradire quest'anno (`AiPlan.betray`): si attacca come un neutrale, con una soglia piu' alta.
const KIND_BETRAYAL := "tradimento"


## Natura del bersaglio per la fazione: ribelle, guerra (gia' in guerra), neutrale; "" se non si puo' mai attaccare
## (se stessa, alleato, tregua, fazione morta o senza id).
static func target_kind(state: GameState, faction_id: String, owner_id: String) -> String:
	if owner_id == "" or owner_id == faction_id:
		return ""
	if owner_id == GameState.REBEL:
		return KIND_REBEL
	var other := state.faction(owner_id)
	if other == null or not other.alive:
		return ""
	var rel := state.relation(faction_id, owner_id)
	if rel == GameState.REL_WAR:
		return KIND_WAR
	if rel == GameState.REL_NEUTRAL:
		return KIND_NEUTRAL
	return ""


## Vero se attaccare `owner_id` porterebbe a un avvertimento in corso o alla scomunica: la fazione e' cattolica, il Papato e' vivo
## e c'e' un avvertimento papale a suo carico contro il bersaglio, oppure il bersaglio e' il Papato. Una fazione gia' scomunicata
## con un profilo aggressivo non rispetta piu' nulla.
static func papal_blocks(state: GameState, faction_id: String, owner_id: String, profile: String) -> bool:
	if not PapacyProcessor.papal_alive(state) or not PapacyProcessor.is_catholic(state, faction_id):
		return false
	var f := state.faction(faction_id)
	if f == null or (f.excommunicated and AiProfiles.is_aggressive(profile)):
		return false
	if owner_id == GameState.PAPAL:
		return true
	var other := state.faction(owner_id)
	if other == null or other.excommunicated or not PapacyProcessor.is_catholic(state, owner_id):
		return false
	return not state.papal_warning(faction_id, owner_id).is_empty()


## Soglia d'attacco per la natura del bersaglio, a partire dalla soglia del piano (profilo x difficolta').
static func threshold_for(plan: AiPlan, kind: String) -> float:
	if kind == KIND_REBEL:
		return plan.threshold * plan.rules.rebel_factor
	if kind == KIND_WAR:
		return plan.threshold * plan.rules.war_factor
	if kind == KIND_BETRAYAL:
		return plan.threshold * plan.rules.betray_factor * overextension(plan)
	if kind == KIND_NEUTRAL and plan.target_level < 3:
		return plan.threshold * plan.rules.cautious_neutral_factor * overextension(plan)
	return plan.threshold * overextension(plan)


## Moltiplicatore della soglia contro neutrali e alleati per un impero esteso: 1 + k_estensione x (quota - soglia_estensione), almeno 1.
static func overextension(plan: AiPlan) -> float:
	return 1.0 + plan.rules.overextension_k * maxf(0.0, plan.land_share - plan.rules.overextension_share)


## Natura del bersaglio se il piano puo' attaccare la provincia di `owner_id`, "" altrimenti (livello dei bersagli del profilo,
## alleati, tregue, politica papale).
static func attackable(plan: AiPlan, owner_id: String) -> String:
	var kind := target_kind(plan.state, plan.id, owner_id)
	if kind == "" and plan.betray.has(owner_id) and plan.state.relation(plan.id, owner_id) == GameState.REL_ALLIANCE:
		kind = KIND_BETRAYAL
	if kind == "":
		return ""
	if plan.courting.has(owner_id):
		return ""
	var needed := 1
	if kind == KIND_WAR:
		needed = 2
	elif kind == KIND_NEUTRAL:
		needed = 2  # con bersagli «guerra» la soglia e' piu' alta (threshold_for)
	elif kind == KIND_BETRAYAL:
		needed = 2 if not AiProfiles.is_expansionist(plan.profile) else 3
	if plan.target_level < needed:
		return ""
	if kind != KIND_REBEL and papal_blocks(plan.state, plan.id, owner_id, plan.profile):
		return ""
	return kind
