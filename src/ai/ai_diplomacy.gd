class_name AiDiplomacy
extends RefCounted
## Diplomazia dell'IA (fase 7b): emissari e principesse (agenti liberi) e rottura delle alleanze. Tutto con i comandi pubblici
## (`order_mission`, `order_agent_move`); la risposta delle altre IA e' la formula d'accettazione di `DiplomacyProcessor`, quella
## di un giocatore e' una proposta in attesa (`GameState.pending_proposals`). Regole PROVVISORIE, parametri in `ia.cfg`
## ([diplomazia]).
##   - TREGUA: una guerra «va male» (province perse nell'ultimo anno, assedio nemico a una provincia propria, forza nemica entro un
##     passo superiore a `rapporto_tregua` volte la forza propria) -> emissario dal nemico; i profili non espansionisti la cercano
##     anche senza perdere, con probabilita' annua `prob_pace`;
##   - ALLEANZA: vicini neutrali con un nemico comune (in guerra con lo stesso nemico), probabilita' annua `prob_alleanza`, mai oltre
##     `alleanze_max`;
##   - NOZZE: una principessa libera sposa un vicino con cui si vuole l'alleanza, oppure un generale poco leale;
##   - TRADIMENTO (solo profili espansionisti, `plan_betrayal`): se conviene attaccare un alleato senza nemici comuni, l'IA lo
##     segna in `AiPlan.betray` e `AiWar` lo attacca (l'alleanza si rompe attaccando: nessun comando apposito).
## Ogni fazione verso cui parte un emissario entra in `AiPlan.courting` e quest'anno non la si attacca.


## Chiamato da `AiFaction.plan` prima della guerra: tregue, alleanze, nozze.
static func plan(data: AiPlan) -> void:
	var emissaries := AiAgents.free_of_type(data, AgentState.EMISSARY)
	var princesses := AiAgents.free_of_type(data, AgentState.PRINCESS)
	if emissaries.is_empty() and princesses.is_empty():
		return
	_truces(data, emissaries)
	var partners := alliance_candidates(data)
	_alliances(data, emissaries, partners)
	_marriages(data, princesses, partners)


# --- tregue -----------------------------------------------------------------------------------------------------------


static func _truces(data: AiPlan, emissaries: Array[AgentState]) -> void:
	if emissaries.is_empty():
		return
	var enemies := data.state.enemies_of(data.id)
	if enemies.is_empty():
		return
	var near := _near_forces(data, enemies)
	for enemy_id in enemies:
		var enemy := data.state.faction(enemy_id)
		if enemy == null or not enemy.alive or data.courting.has(enemy_id):
			continue
		if not wants_truce(data, enemy_id, near):
			continue
		_send(data, emissaries, AgentMissions.TRUCE, enemy_id)


## Vero se la fazione cerca la tregua con il nemico: la guerra va male, oppure e' in stallo da `anni_stallo` anni e lo dice un
## sorteggio (ogni profilo), oppure (profili non espansionisti) un sorteggio di pace.
static func wants_truce(data: AiPlan, enemy_id: String, near: Dictionary = {}) -> bool:
	if war_going_badly(data, enemy_id, near):
		return true
	if DiplomacyProcessor.stalemate_years(data.state, data.id, enemy_id) >= data.rules.stalemate_years:
		if data.rng.randf() < data.rules.stalemate_peace_prob:
			return true
	var lost := lost_trade(data, enemy_id)
	if lost > 0:
		# ADR-053 (PROVVISORIA, peso basso): il commercio via mare perso per questa guerra spinge verso la tregua
		var p_trade := minf(0.5, float(lost) * data.rules.trade_peace_weight * data.rules.behaviour_weight(data.profile, "commercio"))
		if data.rng.randf() < p_trade:
			return true
	if AiProfiles.is_expansionist(data.profile):
		return false
	return data.rng.randf() < data.rules.peace_prob


## Commercio via mare (denari l'anno) che la fazione perde per la guerra con `enemy_id`: differenza tra il commercio con le flotte
## presenti senza quella guerra (le sue flotte non chiudono le zone, i suoi porti tornano partner) e quello di oggi. Stessa
## funzione del giocatore (`Economy.sea_trade_of`, ADR-051/053).
static func lost_trade(data: AiPlan, enemy_id: String) -> int:
	if not data.state.rules.sea_trade:
		return 0
	var now := Economy.sea_trade_of(data.state, data.id)
	var without := Economy.sea_trade_of(data.state, data.id, {"ignora_guerra": enemy_id})
	return maxi(0, without - now)


## Vero se la guerra contro `enemy_id` va male: ha preso almeno `perdite_tregua` province nell'ultimo anno, assedia una provincia
## propria o ha entro un passo dalle province proprie una forza superiore a `rapporto_tregua` volte la forza di terra propria.
## `near` (nemico -> forza entro un passo, vedi `_near_forces`) si calcola da solo se manca.
static func war_going_badly(data: AiPlan, enemy_id: String, near: Dictionary = {}) -> bool:
	var ctx := data.ctx
	var state := data.state
	if ctx.lost_provinces(data.id, enemy_id) >= data.rules.truce_losses:
		return true
	for key in state.sieges:
		var siege: SiegeState = state.sieges[key]
		if siege.faction == enemy_id and ctx.owner_of(siege.region) == data.id:
			return true
	var forces := near
	if forces.is_empty():
		forces = _near_forces(data, [enemy_id])
	var own := AiForce.sum_force(ctx, ctx.land_armies_of(data.id))
	return float(forces.get(enemy_id, 0.0)) > data.rules.truce_ratio * maxf(own, 1.0)


## Forza degli eserciti di terra dei nemici indicati che stanno nelle province della fazione o in quelle confinanti
## (ogni esercito si conta una volta): nemico -> forza.
static func _near_forces(data: AiPlan, enemies: Array) -> Dictionary:
	var ctx := data.ctx
	var seen := {}
	var out := {}
	for p in data.provinces:
		var region_ids := PackedStringArray([p.id])
		region_ids.append_array(ctx.land_neighbours.get(p.id, PackedStringArray()))
		for rid in region_ids:
			for item in ctx.armies_at(rid):
				var a: Army = item
				if seen.has(a.id) or not enemies.has(a.faction):
					continue
				seen[a.id] = true
				out[a.faction] = float(out.get(a.faction, 0.0)) + ctx.force(a)
	return out


# --- alleanze ---------------------------------------------------------------------------------------------------------


## Vicini neutrali con cui si vorrebbe un'alleanza: confinano con una provincia della fazione, sono in guerra con un nemico della
## fazione, non sono alleati ne' in tregua ne' il Papato; non se la fazione ha gia' `alleanze_max` alleati. Ordinati per probabilita'
## di accettazione (stimata con un agente di valore 2) decrescente: Array di {"id", "p"}.
static func alliance_candidates(data: AiPlan) -> Array[Dictionary]:
	var state := data.state
	var ctx := data.ctx
	var out: Array[Dictionary] = []
	var allies := 0
	for f in state.factions:
		if f.id != data.id and f.alive and state.is_allied(data.id, f.id):
			allies += 1
	if allies >= data.rules.alliances_max:
		return out
	var enemies := state.enemies_of(data.id)
	var my_religion := ReligionProcessor.faction_religion(state, data.id) if state.campaign != null else ""
	var neighbours := {}
	for p in data.provinces:
		for n in ctx.land_neighbours.get(p.id, PackedStringArray()):
			var owner_id := ctx.owner_of(n)
			if owner_id != "" and owner_id != data.id:
				neighbours[owner_id] = true
	for f in state.factions:
		if not neighbours.has(f.id) or not f.alive or f.id == GameState.REBEL or f.id == GameState.PAPAL:
			continue
		if state.relation(data.id, f.id) != GameState.REL_NEUTRAL:
			continue
		var common := false
		for enemy_id in enemies:
			if enemy_id != f.id and state.at_war(f.id, enemy_id):
				common = true
				break
		# PROVVISORIA: un nemico comune e' il motivo migliore; senza, si cerca un vicino della stessa religione (amicizia
		# di confine), con punteggio minore. Nella prima partita IA contro IA, col solo nemico comune, nessuna alleanza in 700 anni.
		var same_faith := my_religion != "" and ReligionProcessor.faction_religion(state, f.id) == my_religion
		if not common and not same_faith:
			continue
		var p_accept := DiplomacyProcessor.acceptance(state, DiplomacyProcessor.KIND_ALLIANCE, data.id, f.id, state.rules.agents.start_valour)
		var score := p_accept + (0.3 if common else 0.0)
		out.append({"id": f.id, "p": p_accept, "k": out.size(), "score": score})
	out.sort_custom(AiEconomy.before)
	return out


static func _alliances(data: AiPlan, emissaries: Array[AgentState], partners: Array[Dictionary]) -> void:
	var allies := 0
	for f in data.state.factions:
		if f.id != data.id and f.alive and data.state.is_allied(data.id, f.id):
			allies += 1
	var sent := 0
	for cand in partners:
		if allies + sent >= data.rules.alliances_max:
			break
		var faction_id := str(cand["id"])
		if data.courting.has(faction_id) or _approaching(data, faction_id):
			continue
		if data.rng.randf() >= data.rules.alliance_prob:
			continue
		if _send(data, emissaries, AgentMissions.ALLIANCE, faction_id):
			sent += 1


# --- nozze ------------------------------------------------------------------------------------------------------------


static func _marriages(data: AiPlan, princesses: Array[AgentState], partners: Array[Dictionary]) -> void:
	for princess in princesses:
		if not data.is_agent_free(princess) or AgentMissions.princess_problem(data.state, princess) != "":
			continue
		var done := false
		for cand in partners:
			var faction_id := str(cand["id"])
			if _approaching(data, faction_id):
				continue
			if data.state.relation(data.id, faction_id) != GameState.REL_NEUTRAL:
				continue
			if data.rng.randf() >= data.rules.alliance_prob:
				continue
			if _send(data, [princess], AgentMissions.MARRIAGE, faction_id):
				done = true
				break
		if done:
			continue
		if data.rng.randf() < data.rules.marriage_prob:
			_bride(data, princess)


## La principessa sposa il generale della fazione con la lealta' piu' bassa (non oltre `lealta_nozze`): se non e' a portata, gli va
## incontro.
static func _bride(data: AiPlan, princess: AgentState) -> void:
	var state := data.state
	var ctx := data.ctx
	var chars: Array = ctx.chars_by_faction.get(data.id, [])
	var best: Character = null
	var best_loyalty := 1000
	for item in chars:
		var c: Character = item
		if c.role != Character.ROLE_GENERAL or not c.male or not c.can_command(state.rules.dynasty, state.year):
			continue
		var loyalty := c.effective(Character.ATTR_LOYALTY, state.rules, state.campaign)
		if loyalty <= data.rules.marriage_loyalty and loyalty < best_loyalty:
			best = c
			best_loyalty = loyalty
	if best == null:
		return
	var check := AgentMissions.validate(state, princess, AgentMissions.BRIDE, best.id)
	if bool(check["ok"]):
		if data.record(GameCommands.order_mission(state, data.id, princess.id, AgentMissions.BRIDE, best.id), "nozze generale %d" % best.id):
			data.agents_used[princess.id] = true
		return
	var general_region := ctx.char_region(best)
	var goals := {general_region: true}
	for n in ctx.land_neighbours.get(general_region, PackedStringArray()):
		goals[n] = true
	AiAgents.walk_toward(data, princess, goals, "principessa")


# --- invio di un agente ------------------------------------------------------------------------------------------------


## Vero se un nostro agente in viaggio (senza missione) sta andando verso una regione da cui `faction_id` e' a portata.
static func _approaching(data: AiPlan, faction_id: String) -> bool:
	for a in AiAgents.own_agents(data):
		if a.path.is_empty() or a.has_mission() or (a.type_name != AgentState.EMISSARY and a.type_name != AgentState.PRINCESS):
			continue
		if AiAgents.touches(data.ctx, a.path[a.path.size() - 1], faction_id):
			return true
	return false


## Manda la missione `kind` verso `target_id` con l'agente libero a portata che ha la probabilita' migliore; se nessuno e' a portata
## manda verso la fazione l'agente piu' vicino. Per un giocatore l'invio avviene con probabilita' `prob_proposta_giocatore`, mai
## con troppe proposte gia' in attesa o una uguale. Vero se e' partito un ordine.
static func _send(data: AiPlan, agents: Array, kind: String, target_id: String) -> bool:
	var state := data.state
	var target := state.faction(target_id)
	if target == null or not target.alive:
		return false
	if target.is_player:
		if state.has_proposal(data.id, target_id, kind) or state.proposals_for(target_id).size() >= data.rules.player_proposals_max:
			return false
		if data.rng.randf() >= data.rules.player_proposal_prob:
			return false
	var chosen: AgentState = null
	var chosen_p := -1.0
	for item in agents:
		var a: AgentState = item
		if not data.is_agent_free(a):
			continue
		if not bool(AgentMissions.validate(state, a, kind, target_id)["ok"]):
			continue
		var p := AgentMissions.chance(state, a, kind, target_id)
		if p > chosen_p:
			chosen = a
			chosen_p = p
	if chosen != null:
		if (kind == AgentMissions.ALLIANCE or kind == AgentMissions.MARRIAGE) and not target.is_player and chosen_p < data.rules.alliance_min_p:
			return false
		if data.record(GameCommands.order_mission(state, data.id, chosen.id, kind, target_id), "%s con %s" % [kind, target_id]):
			data.agents_used[chosen.id] = true
			data.courting[target_id] = true
			return true
		return false
	# nessuno a portata: va incontro il piu' vicino
	var best_agent: AgentState = null
	var best_search := {}
	var best_goal := ""
	var best_steps := 1000
	for item in agents:
		var a2: AgentState = item
		if not data.is_agent_free(a2) or (a2.type_name == AgentState.PRINCESS and AgentMissions.princess_problem(state, a2) != ""):
			continue
		var search := AiAgents.bfs(data.ctx, a2.region, data.rules.agent_radius)
		var order: Array = search["ordine"]
		for region_id in order:
			if AiAgents.touches(data.ctx, str(region_id), target_id):
				var steps := int((search["profondita"] as Dictionary).get(region_id, 1000))
				if steps < best_steps:
					best_steps = steps
					best_agent = a2
					best_search = search
					best_goal = str(region_id)
				break
	if best_agent == null:
		return false
	var path := AiAgents.path_to(best_search, best_agent.region, best_goal)
	if path.is_empty():
		return false
	if data.record(GameCommands.order_agent_move(state, data.id, best_agent.id, path), "%s verso %s" % [kind, target_id]):
		data.agents_used[best_agent.id] = true
		data.courting[target_id] = true
		return true
	return false


# --- tradimento -------------------------------------------------------------------------------------------------------


## Chiamato da `AiFaction.plan` prima della guerra. Profili espansionisti (non i predoni) con bersagli neutrali ammessi, probabilita'
## annua `prob_tradimento`; altri profili non difensivi che attaccano almeno chi e' gia' in guerra, `prob_tradimento_altri` (catalogo: l'IA attacca
## anche un alleato quando lo sente debole). Probabilita' x aggressivita' della difficolta'; si cerca tra gli alleati senza nemici
## comuni quello da cui conviene prendere una provincia confinante: rapporto di forza (eserciti liberi di una regione propria contro
## tutti i difensori dell'alleato) sopra la soglia del profilo x `fattore_tradimento`, senza blocchi papali. Il migliore va in
## `AiPlan.betray`; `AiWar` lo attacca come un neutrale piu' difficile e l'alleanza si rompe attaccando.
static func plan_betrayal(data: AiPlan) -> void:
	var expansionist := AiProfiles.is_expansionist(data.profile)
	if data.profile == AiProfiles.RAIDER or data.target_level < (3 if expansionist else 2):
		return
	if not expansionist and data.profile.contains("DEFENSIVE"):
		return
	var state := data.state
	var ctx := data.ctx
	var allies: Array[String] = []
	for f in state.factions:
		if f.id != data.id and f.alive and f.id != GameState.PAPAL and state.is_allied(data.id, f.id):
			allies.append(f.id)
	if allies.is_empty():
		return
	var chance := (data.rules.betray_prob if expansionist else data.rules.betray_prob_other) * float(ctx.diff.get("aggressivita", 1.0))
	if data.rng.randf() >= chance:
		return
	var enemies := state.enemies_of(data.id)
	var best_ally := ""
	var best_ratio := 0.0
	var need := AiPolicy.threshold_for(data, AiPolicy.KIND_BETRAYAL)
	var checked := {}
	for item in ctx.land_armies_of(data.id):
		var army: Army = item
		if checked.has(army.region):
			continue
		checked[army.region] = true
		var movers := AiWar.spare(data, army.region)
		if movers.is_empty():
			continue
		var attack_force := AiForce.sum_force(ctx, movers)
		for n in ctx.land_neighbours.get(army.region, PackedStringArray()):
			var owner_id := ctx.owner_of(n)
			if not allies.has(owner_id):
				continue
			if _shares_enemy(state, owner_id, enemies) or AiPolicy.papal_blocks(state, data.id, owner_id, data.profile):
				continue
			var defence := AiForce.defenders(ctx, n, data.id, {owner_id: true})
			var r := AiForce.ratio(attack_force, float(defence["totale"]))
			if r >= need and r > best_ratio:
				best_ratio = r
				best_ally = owner_id
	if best_ally != "":
		data.betray[best_ally] = true


static func _shares_enemy(state: GameState, ally_id: String, enemies: Array[String]) -> bool:
	for enemy_id in enemies:
		if enemy_id != ally_id and state.at_war(ally_id, enemy_id):
			return true
	return false
