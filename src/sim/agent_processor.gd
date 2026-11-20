class_name AgentProcessor
extends RefCounted
## Agenti del fine anno (fase 5a, spec. fase 5 §5a, ADR-010): movimento, missioni, cattura degli agenti nemici e
## apertura delle porte delle spie, piu' la nascita degli agenti, il collegamento delle principesse ai personaggi
## e la pulizia di fine anno. `TurnProcessor.end_year` chiama `process_year` nel passo 1b (dopo il movimento degli
## eserciti, prima delle battaglie: un esercito corrotto o un generale assassinato cambiano lo scontro dello
## stesso anno), `sync_year` dopo le regole delle province e `spawn_recruit` quando una coda di reclutamento finisce.
##
## Ordine fisso del passo 1b (agenti in ordine di id, province in ordine di dichiarazione; ogni sorteggio passa da
## `state.rng`, uno per probabilita' maggiore di zero):
##   1. movimento degli agenti (una regione all'anno, come gli eserciti; le catene via mare si ricontrollano tutte
##      prima che si muova qualcuno)
##   2. missioni degli agenti arrivati nella regione del bersaglio, in ordine di id
##   3. cattura degli agenti nemici: per provincia, un solo catturatore (il valore massimo tra forte di confine, spie,
##      assassini, emissari del proprietario), un sorteggio per agente intruso, in ordine di id
##   4. porte aperte dalle spie negli assedi della propria fazione (un sorteggio per spia, fino al primo successo).
## Sorteggi delle missioni: accettazione (alleanza, tregua, corruzione, matrimonio) o riuscita (assassinio, processo
## dell'inquisitore: fase 5b), poi la morte dell'assassino se fallisce. La sposa generale non ha sorteggi.
## Le regole senza formula nota sono PROVVISORIE: vedi `data/regole/agenti.cfg` e `data/regole/diplomazia.cfg`.


# --- passo 1b -----------------------------------------------------------------------------------------------


static func process_year(state: GameState) -> void:
	if state.agents.is_empty():
		return
	_move_agents(state)
	_run_missions(state)
	_captures(state)
	_open_gates(state)


# --- 1. movimento ----------------------------------------------------------------------------------------------


## Ogni agente con un percorso avanza di una regione di terra (EV_AGENT_MOVED). Gli agenti entrano ovunque senza
## dichiarare guerra. Un trasporto via mare la cui catena non regge piu' e' interrotto (EV_TRANSPORT_BLOCKED):
## l'agente resta dov'e' e perde l'ordine.
static func _move_agents(state: GameState) -> void:
	var broken := {}
	for a in state.agents:
		if a.sea_route.is_empty():
			continue
		if a.path.size() != 1:
			a.sea_route = PackedStringArray()
			continue
		var problem := GameCommands.chain_problem(state, a.faction, a.region, a.sea_route, a.path[0], false)
		if problem != "":
			broken[a.id] = problem
	for a in state.agents:
		if a.path.is_empty():
			a.sea_route = PackedStringArray()
			continue
		var target := a.path[0]
		var region := state.campaign.region(target)
		if region == null or region.is_sea:
			_clear_path(a)
			continue
		var origin := state.campaign.region(a.region)
		var by_sea := not a.sea_route.is_empty()
		if not by_sea and (origin == null or not origin.neighbours.has(region.id)):
			_clear_path(a)
			continue
		if broken.has(a.id):
			var reason := str(broken[a.id])
			_clear_path(a)
			if a.destination != "":
				continue   # in viaggio: a fine anno `plan_journeys` cerca un'altra tappa (o ferma il viaggio)
			state.add_event(GameState.EV_TRANSPORT_BLOCKED, {
				"fazione": a.faction,
				"regione": a.region,
				"agente": a.id,
				"tipo_agente": a.type_name,
				"verso": target,
				"motivo": reason,
				"testo": Lang.t("Il trasporto via mare dell'agente %d (%s) di %s da %s a %s e' interrotto (%s).") % [
					a.id, a.type_name, SimUtil.faction_label(a.faction), WarProcessor.region_label(state, a.region), WarProcessor.region_label(state, target), reason],
			})
			continue
		var moved := {
			"fazione": a.faction,
			"regione": target,
			"agente": a.id,
			"tipo_agente": a.type_name,
			"da": a.region,
			"a": target,
		}
		var verb := Lang.t("si muove")
		if by_sea:
			moved["via_mare"] = true
			moved["catena"] = Array(a.sea_route)
			verb = Lang.t("sbarca")
		moved["testo"] = Lang.t("L'agente %d (%s) di %s %s da %s a %s.") % [
			a.id, a.type_name, SimUtil.faction_label(a.faction), verb, WarProcessor.region_label(state, a.region), WarProcessor.region_label(state, target)]
		a.region = target
		a.path.remove_at(0)
		a.sea_route = PackedStringArray()
		if a.destination != "":
			if a.region == a.destination:
				a.destination = ""
				moved["arrivato"] = true
			else:
				moved["destinazione"] = a.destination
		state.add_event(GameState.EV_AGENT_MOVED, moved)


## Fine anno (dopo battaglie, conquiste e province, in `sync_year`): ogni agente in viaggio (`AgentState.destination`)
## riceve la tappa dell'anno dopo (`AgentTravel.set_next_leg`), calcolata sullo stato nuovo. Se non c'e' piu' un percorso
## il viaggio si ferma dov'e' (EV_AGENT_JOURNEY_STOPPED).
static func plan_journeys(state: GameState) -> void:
	for a in state.agents:
		if a.destination == "":
			continue
		if a.destination == a.region:
			a.destination = ""
			continue
		if not state.proposal_of_agent(a.id).is_empty():
			continue
		if AgentTravel.set_next_leg(state, a):
			continue
		var goal := a.destination
		a.destination = ""
		_clear_path(a)
		state.add_event(GameState.EV_AGENT_JOURNEY_STOPPED, _agent_data(a, a.region, {
			"verso": goal,
			"testo": Lang.t("L'agente %d (%s) di %s si ferma a %s: nessun percorso porta piu' a %s.") % [
				a.id, a.type_name, SimUtil.faction_label(a.faction), WarProcessor.region_label(state, a.region), WarProcessor.region_label(state, goal)],
		}))


static func _clear_path(a: AgentState) -> void:
	a.path = PackedStringArray()
	a.sea_route = PackedStringArray()


# --- 2. missioni -----------------------------------------------------------------------------------------------------


static func _run_missions(state: GameState) -> void:
	var ids: Array[int] = []
	for a in state.agents:
		if a.has_mission():
			ids.append(a.id)
	for agent_id in ids:
		var a := state.agent(agent_id)
		if a == null or not a.has_mission():
			continue
		_resolve_mission(state, a)


## Risolve la missione se l'agente e' nella regione del bersaglio. Il bersaglio si ricontrolla ogni anno: se e'
## sparito la missione cade (EV_MISSION_FAILED); se si e' spostato in una regione confinante l'agente la raggiunge
## e la missione si risolve l'anno dopo.
static func _resolve_mission(state: GameState, a: AgentState) -> void:
	var kind := str(a.mission.get("tipo", ""))
	var target: Variant = a.mission.get("bersaglio")
	var check := AgentMissions.validate(state, a, kind, target)
	if not bool(check["ok"]):
		_mission_failed(state, a, kind, str(check["errore"]))
		return
	var region_id := str(check["regione"])
	if region_id != a.region:
		if a.path.is_empty():
			a.path = PackedStringArray([region_id])
			a.sea_route = PackedStringArray()
			a.mission["regione"] = region_id
			a.mission["avvicinamento"] = true
		return
	a.mission = {}
	if kind == AgentMissions.ALLIANCE or kind == AgentMissions.TRUCE or kind == AgentMissions.MARRIAGE:
		_resolve_proposal(state, a, kind, SimUtil.norm(str(target)))
	elif kind == AgentMissions.BRIBE:
		_resolve_bribe(state, a, state.army(int(target)))
	elif kind == AgentMissions.BRIDE:
		_resolve_bride(state, a, state.character(int(target)))
	elif kind == AgentMissions.TRIAL:
		var trial_target: Dictionary = target
		_resolve_trial(state, a, trial_target)
	elif kind == AgentMissions.SPY_ON or kind == AgentMissions.UNREST or kind == AgentMissions.SABOTAGE or kind == AgentMissions.GATES:
		_resolve_spy(state, a, kind, target, region_id)
	else:
		var td: Dictionary = target
		_resolve_assassination(state, a, td)


static func _mission_failed(state: GameState, a: AgentState, kind: String, reason: String) -> void:
	if bool(a.mission.get("avvicinamento", false)):
		_clear_path(a)
	a.mission = {}
	state.add_event(GameState.EV_MISSION_FAILED, _agent_data(a, a.region, {
		"missione": kind,
		"motivo": reason,
		"testo": Lang.t("La missione %s dell'agente %d (%s) di %s fallisce: %s.") % [Lang.t(kind), a.id, a.type_name, SimUtil.faction_label(a.faction), reason],
	}))


## Alleanza, tregua o matrimonio: un sorteggio contro la probabilita' di accettazione. Se il destinatario e' la fazione di un
## giocatore e chi propone no (fase 7b), non c'e' sorteggio: nasce una proposta in attesa di risposta (`GameState.pending_proposals`)
## e l'agente aspetta dov'e'.
static func _resolve_proposal(state: GameState, a: AgentState, kind: String, recipient: String) -> void:
	var target := state.faction(recipient)
	var own := state.faction(a.faction)
	if target != null and target.is_player and own != null and not own.is_player:
		_queue_proposal(state, a, kind, recipient)
		return
	var p := DiplomacyProcessor.acceptance(state, kind, a.faction, recipient, a.valour)
	var accepted := state.rng.randf() < p
	settle_proposal(state, a, kind, recipient, accepted, p)


## Esito di una proposta (alleanza, tregua, matrimonio): eventi ed effetti, uguali per un sorteggio dell'IA e per la risposta di un
## giocatore (`GameCommands.answer_proposal`). `p` e' la probabilita' mostrata nell'evento (negativa: non si mostra).
static func settle_proposal(state: GameState, a: AgentState, kind: String, recipient: String, accepted: bool, p: float) -> void:
	var us := SimUtil.faction_label(a.faction)
	var them := SimUtil.faction_label(recipient)
	var where := WarProcessor.region_label(state, a.region)
	var data := _agent_data(a, a.region, {"con": recipient})
	if p >= 0.0:
		data["probabilita"] = p
	if not accepted:
		data["missione"] = kind
		data["testo"] = Lang.t("%s rifiuta la proposta di %s di %s (%s).") % [them, Lang.t(kind), us, where]
		state.add_event(GameState.EV_PROPOSAL_REFUSED, data)
		return
	if kind == AgentMissions.ALLIANCE:
		state.form_alliance(a.faction, recipient)
		data["testo"] = Lang.t("%s e %s stringono un'alleanza (%s).") % [us, them, where]
		state.add_event(GameState.EV_ALLIANCE_FORMED, data)
		grow_valour(state, a)
	elif kind == AgentMissions.TRUCE:
		var until := state.year + 1 + state.rules.diplomacy.truce_years
		state.make_truce(a.faction, recipient, until)
		data["fino_al"] = until
		data["testo"] = Lang.t("%s e %s firmano una tregua fino al %d (%s).") % [us, them, until, where]
		state.add_event(GameState.EV_TRUCE, data)
		grow_valour(state, a)
	else:
		var c := state.character(a.character_id)
		var new_alliance := state.form_alliance(a.faction, recipient)
		data["nuova_alleanza"] = new_alliance
		data["personaggio"] = a.character_id
		data["testo"] = Lang.t("Una principessa di %s sposa un nobile di %s (%s)%s.") % [us, them, where, Lang.t(": nasce un'alleanza") if new_alliance else ""]
		if c != null:
			data["nome"] = c.full_name()
		state.add_event(GameState.EV_MARRIAGE, data)
		remove_agent(state, a, "matrimonio")


## Motivo per cui la proposta `kind` dell'agente al destinatario non si puo' piu' accettare ("" se si puo'): stessi requisiti
## della validazione della missione (alleanza solo tra neutrali, tregua solo tra fazioni in guerra, matrimonio non in guerra e con
## una principessa in eta'). Serve alla risposta di un giocatore, che puo' arrivare un anno dopo.
static func proposal_problem(state: GameState, agent: AgentState, kind: String, recipient: String) -> String:
	var rel := state.relation(agent.faction, recipient)
	if kind == AgentMissions.ALLIANCE and rel != GameState.REL_NEUTRAL:
		return Lang.t("%s e %s non sono piu' neutrali (%s): l'alleanza non si puo' stringere") % [SimUtil.faction_label(agent.faction), SimUtil.faction_label(recipient), Lang.t(rel)]
	if kind == AgentMissions.TRUCE and rel != GameState.REL_WAR:
		return Lang.t("%s e %s non sono piu' in guerra: la tregua non serve") % [SimUtil.faction_label(agent.faction), SimUtil.faction_label(recipient)]
	if kind == AgentMissions.MARRIAGE:
		if rel == GameState.REL_WAR:
			return Lang.t("%s e %s sono in guerra: niente matrimonio") % [SimUtil.faction_label(agent.faction), SimUtil.faction_label(recipient)]
		return AgentMissions.princess_problem(state, agent)
	return ""


## Crea la proposta in attesa (fase 7b) e il suo evento. Una proposta uguale (stessi proponente, destinatario e tipo) gia' in
## attesa non si ripete: la missione cade.
static func _queue_proposal(state: GameState, a: AgentState, kind: String, recipient: String) -> void:
	var them := SimUtil.faction_label(recipient)
	if state.has_proposal(a.faction, recipient, kind):
		_mission_failed(state, a, kind, Lang.t("una proposta uguale aspetta gia' la risposta di %s") % them)
		return
	var proposal_id := state.next_proposal_id
	state.next_proposal_id += 1
	var deadline := state.year + 1
	state.pending_proposals.append({
		"id": proposal_id,
		"da": a.faction,
		"a": recipient,
		"tipo": kind,
		"agente": a.id,
		"regione": a.region,
		"anno": state.year,
		"scadenza": deadline,
	})
	state.add_event(GameState.EV_PROPOSAL_RECEIVED, _agent_data(a, a.region, {
		"con": recipient,
		"id": proposal_id,
		"missione": kind,
		"scadenza": deadline,
		"testo": Lang.t("%s propone a %s: %s (risposta entro il %d) (%s).") % [
			SimUtil.faction_label(a.faction), them, Lang.t(kind), deadline, WarProcessor.region_label(state, a.region)],
	}))


## Toglie le proposte scadute o orfane (fase 7b), con un evento ciascuna: scadenza raggiunta (`scadenza` <= anno che finisce),
## agente morto, catturato o sposato altrove, proponente o destinatario scomparsi.
static func expire_proposals(state: GameState) -> void:
	if state.pending_proposals.is_empty():
		return
	var kept: Array[Dictionary] = []
	for p in state.pending_proposals:
		var reason := ""
		var from_faction := state.faction(str(p.get("da", "")))
		var to_faction := state.faction(str(p.get("a", "")))
		if from_faction == null or not from_faction.alive:
			reason = "proponente"
		elif to_faction == null or not to_faction.alive:
			reason = "destinatario"
		elif state.agent(int(p.get("agente", 0))) == null:
			reason = "agente"
		elif int(p.get("scadenza", 0)) <= state.year:
			reason = "scaduta"
		if reason == "":
			kept.append(p)
			continue
		var kind := str(p.get("tipo", ""))
		state.add_event(GameState.EV_PROPOSAL_EXPIRED, {
			"fazione": str(p.get("da", "")),
			"con": str(p.get("a", "")),
			"regione": str(p.get("regione", "")),
			"id": int(p.get("id", 0)),
			"missione": kind,
			"motivo": reason,
			"testo": Lang.t("La proposta di %s (%s) a %s decade: %s.") % [
				SimUtil.faction_label(str(p.get("da", ""))), Lang.t(kind), SimUtil.faction_label(str(p.get("a", ""))), Lang.t(str(EXPIRY_TEXTS.get(reason, reason)))],
		})
	state.pending_proposals = kept


## Corruzione: un sorteggio contro la probabilita' di accettazione; il tesoro paga solo se l'esercito accetta e, se
## non basta, la missione fallisce. L'esercito e il suo comandante passano alla fazione dell'agente (se era la
## guarnigione di un castello passa anche la provincia). Non dichiara guerra.
static func _resolve_bribe(state: GameState, a: AgentState, army: Army) -> void:
	var price := AgentMissions.bribe_price(state, army)
	var p := AgentMissions.bribe_chance(state, army, a.valour)
	var accepted := state.rng.randf() < p
	var previous := army.faction
	var data := _agent_data(a, army.region, {"esercito": army.id, "con": previous, "prezzo": price, "probabilita": p})
	if not accepted:
		data["testo"] = Lang.t("L'esercito %d di %s rifiuta la corruzione di %s (%s).") % [army.id, SimUtil.faction_label(previous), SimUtil.faction_label(a.faction), WarProcessor.region_label(state, army.region)]
		state.add_event(GameState.EV_BRIBE_REFUSED, data)
		return
	var faction := state.faction(a.faction)
	if faction.treasury < price:
		_mission_failed(state, a, AgentMissions.BRIBE, Lang.t("tesoro insufficiente: servono %d, ci sono %d") % [price, faction.treasury])
		return
	faction.spend(price, FactionState.SPEND_BRIBES)
	var province_id := transfer_army(state, army, a.faction)
	data["testo"] = Lang.t("%s corrompe l'esercito %d di %s per %d fiorini (%s).") % [SimUtil.faction_label(a.faction), army.id, SimUtil.faction_label(previous), price, WarProcessor.region_label(state, army.region)]
	if province_id != "":
		data["provincia"] = province_id
		data["testo"] = String(data["testo"]) + Lang.t(" Con la guarnigione passa la provincia.")
	state.add_event(GameState.EV_BRIBE, data)
	grow_valour(state, a)


## Missioni delle spie (richiesta di Federico del 18/11/2026, PROVVISORIE): un sorteggio contro `AgentMissions.spy_chance`.
## Spionaggio: informazioni complete sul bersaglio per `intel_years` anni (SpyIntel). Malcontento: lealta' obiettivo della
## provincia giu' di `unrest_loyalty` per `unrest_years` anni (contatori "malcontento" e "malcontento_fino", letti da
## ProvinceProcessor.spies_term). Sabotaggio: un edificio (non il castello, scelto a caso) perde un livello; se fallisce la
## spia muore con `sabotage_death`. Porte: come la spia passiva, con probabilita' piu' alta.
static func _resolve_spy(state: GameState, a: AgentState, kind: String, target: Variant, region_id: String) -> void:
	var ar := state.rules.agents
	var p := AgentMissions.spy_chance(state, kind, a.valour)
	var success := state.rng.randf() < p
	var place := WarProcessor.region_label(state, region_id)
	if not success:
		var dies := false
		if kind == AgentMissions.SABOTAGE and ar.sabotage_death > 0.0:
			dies = state.rng.randf() < ar.sabotage_death
		_mission_failed(state, a, kind, Lang.t("non riesce (probabilita' %d%%)") % roundi(p * 100.0) + (Lang.t(" e la spia viene uccisa") if dies else ""))
		if dies:
			remove_agent(state, a, "sabotaggio_fallito")
		return
	if kind == AgentMissions.SPY_ON:
		var td: Dictionary = target
		var until := state.year + maxi(1, ar.intel_years)   # valide per i prossimi `intel_years` anni di gioco
		var is_army := str(td.get("tipo", "")) == AgentMissions.TARGET_ARMY
		var key: String = SpyIntel.army_key(int(td.get("id", 0))) if is_army else SpyIntel.province_key(str(td.get("id", "")))
		SpyIntel.record(state, a.faction, key, until)
		state.add_event(GameState.EV_SPY_REPORT, _agent_data(a, region_id, {
			"bersaglio_tipo": str(td.get("tipo", "")), "bersaglio": td.get("id"), "fino_al": until, "probabilita": p,
			"testo": (Lang.t("Una spia di %s riferisce tutto sull'esercito %d a %s (informazioni valide fino al %d).") % [SimUtil.faction_label(a.faction), int(td.get("id", 0)), place, until]) if is_army
				else (Lang.t("Una spia di %s riferisce tutto sulla provincia di %s (informazioni valide fino al %d).") % [SimUtil.faction_label(a.faction), place, until]),
		}))
	elif kind == AgentMissions.UNREST:
		var prov := state.province(region_id)
		var loss := AgentMissions.unrest_loyalty(state, a.valour)
		var until_unrest := state.year + maxi(1, ar.unrest_years) - 1
		prov.counters["malcontento"] = maxi(int(prov.counters.get("malcontento", 0)) if int(prov.counters.get("malcontento_fino", 0)) >= state.year else 0, loss)
		prov.counters["malcontento_fino"] = maxi(int(prov.counters.get("malcontento_fino", 0)), until_unrest)
		state.add_event(GameState.EV_UNREST, _agent_data(a, region_id, {
			"provincia": prov.id, "proprietario": prov.owner, "lealta": loss, "fino_al": until_unrest, "probabilita": p,
			"testo": Lang.t("Una spia di %s fomenta il malcontento a %s (%s): lealta' -%d fino al %d.") % [SimUtil.faction_label(a.faction), place, SimUtil.faction_label(prov.owner), loss, until_unrest],
		}))
	elif kind == AgentMissions.SABOTAGE:
		var prov2 := state.province(region_id)
		var families := AgentMissions.sabotage_targets(state, prov2)
		var family := families[state.rng.randi_range(0, families.size() - 1)]
		var level := prov2.level_of(family) - 1
		prov2.set_level(family, level)
		state.add_event(GameState.EV_SABOTAGE, _agent_data(a, region_id, {
			"provincia": prov2.id, "proprietario": prov2.owner, "edificio": family, "livello": level, "probabilita": p,
			"testo": Lang.t("Una spia di %s sabota %s a %s (%s): l'edificio perde un livello.") % [SimUtil.faction_label(a.faction), family, place, SimUtil.faction_label(prov2.owner)],
		}))
	else:
		var prov3 := state.province(region_id)
		var besieged := prov3.owner
		state.add_event(GameState.EV_GATES_OPENED, _agent_data(a, region_id, {
			"assediata": besieged, "probabilita": p,
			"testo": Lang.t("Una spia di %s apre le porte del castello di %s (%s): l'assedio finisce con la conquista.") % [SimUtil.faction_label(a.faction), place, SimUtil.faction_label(besieged)],
		}))
		WarProcessor.transfer_province(state, prov3, a.faction, ConquestDamage.MEANS_GATES)
	grow_valour(state, a)


## L'esercito (con il comandante) passa a `new_faction`. Il comandante perde titolo e carica e, se era un principe,
## diventa un generale senza sangue reale. Se l'esercito era la guarnigione del castello della sua provincia passa
## anche la provincia (stesse conseguenze di una conquista). Restituisce la provincia passata ("" se nessuna).
static func transfer_army(state: GameState, army: Army, new_faction: String) -> String:
	var previous := army.faction
	var province := state.province(army.region)
	var takes_province := army.in_castle and province != null and province.owner == previous
	army.faction = new_faction
	TroopUpgrades.apply_faction_minimum(state)   # le pile passate di mano prendono subito armi e armature minime della fazione
	army.path = PackedStringArray()
	army.sea_route = PackedStringArray()
	army.assault_ordered = false
	var c := state.commander_of(army.id)
	if c != null:
		DynastyProcessor.release_title(state, c, "perso", false)
		c.office = ""
		c.faction = new_faction
		c.region = army.region
		if c.role == Character.ROLE_PRINCE:
			c.role = Character.ROLE_GENERAL
		c.royal_blood = false
	if takes_province:
		WarProcessor.transfer_province(state, province, new_faction, ConquestDamage.MEANS_BRIBE)   # guarnigione corrotta
		return province.id
	return ""


## Sposa generale: la lealta' del generale sale (fino al massimo), diventa di sangue reale e principe (entra nella
## successione); la principessa lascia la partita. Nessun sorteggio.
static func _resolve_bride(state: GameState, a: AgentState, general: Character) -> void:
	var ar := state.rules.agents
	general.loyalty = mini(general.loyalty + ar.marriage_loyalty_bonus, state.rules.dynasty.max_attribute)
	general.royal_blood = true
	general.role = Character.ROLE_PRINCE
	var data := _agent_data(a, a.region, {"con": "", "personaggio": general.id, "nome": general.full_name(), "nuova_alleanza": false})
	data["testo"] = Lang.t("Una principessa di %s sposa il generale %s: lealta' %d, entra nella linea di sangue (%s).") % [
		SimUtil.faction_label(a.faction), general.full_name(), general.loyalty, WarProcessor.region_label(state, a.region)]
	state.add_event(GameState.EV_MARRIAGE, data)
	remove_agent(state, a, "matrimonio")


## Assassinio: un sorteggio contro la tabella; se fallisce, un altro per la morte dell'assassino.
static func _resolve_assassination(state: GameState, a: AgentState, target: Dictionary) -> void:
	var ar := state.rules.agents
	var step := AgentMissions.kill_step(state, a.valour, target)
	var p := ar.kill_chance(step)
	var target_kind := str(target.get("tipo", ""))
	var target_id := int(target.get("id", 0))
	var victim_name := ""
	var victim_faction := ""
	var victim_label := ""
	if target_kind == AgentMissions.TARGET_CHARACTER:
		var c := state.character(target_id)
		victim_name = c.full_name()
		victim_faction = c.faction
		victim_label = "%s (%s)" % [c.full_name(), c.role]
	else:
		var other := state.agent(target_id)
		victim_name = other.name
		victim_faction = other.faction
		victim_label = Lang.t("l'agente %d (%s)") % [other.id, other.type_name]
	var data := _agent_data(a, a.region, {
		"bersaglio_tipo": target_kind,
		"bersaglio": target_id,
		"nome": victim_name,
		"con": victim_faction,
		"gradino": step,
		"probabilita": p,
	})
	var success := p > 0.0 and state.rng.randf() < p
	if success and target_kind == AgentMissions.TARGET_CHARACTER and DynastyProcessor.is_invulnerable(state, state.character(target_id)):
		success = false   # ADR-075: il re degli Auror non muore mai (il sorteggio resta, per l'ordine dei numeri casuali)
	if success:
		if target_kind == AgentMissions.TARGET_CHARACTER:
			DynastyProcessor.kill(state, state.character(target_id), state.year + 1, "assassinio", false)
		else:
			remove_agent(state, state.agent(target_id), "assassinio")
		data["testo"] = Lang.t("%s assassina %s di %s (%s).") % [SimUtil.faction_label(a.faction), victim_label, SimUtil.faction_label(victim_faction), WarProcessor.region_label(state, a.region)]
		state.add_event(GameState.EV_ASSASSINATION, data)
		grow_valour(state, a)
		return
	var dies := ar.fail_death_chance > 0.0 and state.rng.randf() < ar.fail_death_chance
	data["assassino_morto"] = dies
	data["testo"] = Lang.t("L'assassino %d di %s fallisce il colpo contro %s%s (%s).") % [
		a.id, SimUtil.faction_label(a.faction), victim_label, Lang.t(" e muore") if dies else "", WarProcessor.region_label(state, a.region)]
	state.add_event(GameState.EV_ASSASSINATION_FAILED, data)
	if dies:
		remove_agent(state, a, "assassinio_fallito")


## Processo dell'inquisitore (fase 5b, PROVVISORIA): un sorteggio contro `base_processo + k_pieta * (5 - pieta')`.
## Riuscito: il bersaglio muore sul rogo (causa «rogo», EV_INQUISITION); se era il capo la successione e' quella normale
## (la regola di `DynastyProcessor`, nel fine anno); il valore dell'inquisitore cresce. Fallito: EV_INQUISITION_FAILED,
## l'inquisitore non rischia nulla.
static func _resolve_trial(state: GameState, a: AgentState, target: Dictionary) -> void:
	var target_kind := str(target.get("tipo", ""))
	var target_id := int(target.get("id", 0))
	var p := AgentMissions.trial_chance(state, target)
	var victim_name := ""
	var victim_faction := ""
	var victim_label := ""
	var piety := state.rules.religion.agent_piety
	if target_kind == AgentMissions.TARGET_CHARACTER:
		var c := state.character(target_id)
		victim_name = c.full_name()
		victim_faction = c.faction
		victim_label = "%s (%s)" % [c.full_name(), c.role]
		piety = c.effective(Character.ATTR_PIETY, state.rules, state.campaign)
	else:
		var other := state.agent(target_id)
		victim_name = other.name
		victim_faction = other.faction
		victim_label = Lang.t("l'agente %d (%s)") % [other.id, other.type_name]
	var data := _agent_data(a, a.region, {
		"bersaglio_tipo": target_kind,
		"bersaglio": target_id,
		"nome": victim_name,
		"con": victim_faction,
		"pieta": piety,
		"probabilita": p,
	})
	var success := p > 0.0 and state.rng.randf() < p
	if success and target_kind == AgentMissions.TARGET_CHARACTER and DynastyProcessor.is_invulnerable(state, state.character(target_id)):
		success = false   # ADR-075: il re degli Auror non muore mai (il sorteggio resta, per l'ordine dei numeri casuali)
	if success:
		if target_kind == AgentMissions.TARGET_CHARACTER:
			DynastyProcessor.kill(state, state.character(target_id), state.year + 1, "rogo", false)
		else:
			remove_agent(state, state.agent(target_id), "rogo")
		data["testo"] = Lang.t("L'Inquisizione di %s manda sul rogo %s di %s (%s).") % [SimUtil.faction_label(a.faction), victim_label, SimUtil.faction_label(victim_faction), WarProcessor.region_label(state, a.region)]
		state.add_event(GameState.EV_INQUISITION, data)
		grow_valour(state, a)
		return
	data["testo"] = Lang.t("Il processo dell'inquisitore %d di %s contro %s di %s fallisce (%s).") % [
		a.id, SimUtil.faction_label(a.faction), victim_label, SimUtil.faction_label(victim_faction), WarProcessor.region_label(state, a.region)]
	state.add_event(GameState.EV_INQUISITION_FAILED, data)


# --- 3. cattura ------------------------------------------------------------------------------------------------------------


## In ogni provincia di una fazione, ogni agente di un'altra fazione (non alleata) rischia la cattura da parte
## dell'elemento di valore massimo del proprietario: forte di confine (`2 * livello`), spie, assassini, emissari nella
## provincia (a parita' vince il primo in questo ordine, poi l'id minore). `p = clamp(base + k * (V - valore), 0, max)`,
## meno `malus_invisibile` per spie e assassini. L'agente catturato muore; un catturatore agente guadagna valore.
## PROVVISORIA (catalogo, confidenza Bassa).
static func _captures(state: GameState) -> void:
	for p in state.provinces:
		if p.owner == GameState.REBEL or p.owner == "":
			continue
		var owner := state.faction(p.owner)
		if owner == null or not owner.alive:
			continue
		var intruders: Array[AgentState] = []
		for a in state.agents:
			if a.region == p.id and a.faction != p.owner and not state.is_allied(a.faction, p.owner):
				intruders.append(a)
		if intruders.is_empty():
			continue
		var best := best_capturer(state, p)
		if best.is_empty():
			continue
		var value := int(best["valore"])
		var capturer: AgentState = best["agente"]
		for victim in intruders:
			var chance := capture_chance(state, value, victim)
			if chance <= 0.0 or state.rng.randf() >= chance:
				continue
			var capturer_label := str(best["etichetta"])
			state.add_event(GameState.EV_AGENT_CAPTURED, {
				"fazione": p.owner,
				"con": victim.faction,
				"regione": p.id,
				"agente": victim.id,
				"tipo_agente": victim.type_name,
				"catturatore": capturer_label,
				"catturatore_agente": capturer.id if capturer != null else 0,
				"probabilita": chance,
				"testo": Lang.t("%s cattura l'agente %d (%s) di %s a %s (%s).") % [
					SimUtil.faction_label(p.owner), victim.id, victim.type_name, SimUtil.faction_label(victim.faction), WarProcessor.region_label(state, p.id), capturer_label],
			})
			remove_agent(state, victim, "catturato")
			if capturer != null:
				grow_valour(state, capturer)


## Probabilita' di cattura di `victim` da un catturatore di valore `value`.
static func capture_chance(state: GameState, value: int, victim: AgentState) -> float:
	var ar := state.rules.agents
	var chance := ar.capture_base + ar.capture_k * float(value - maxi(0, victim.valour))
	if victim.is_invisible():
		chance -= ar.invisible_malus
	return clampf(chance, 0.0, ar.capture_max)


## Il catturatore della provincia: Dictionary {"valore", "agente" (AgentState o null per il forte), "etichetta"};
## vuoto se il proprietario non ha ne' forte ne' agenti adatti.
static func best_capturer(state: GameState, p: ProvinceState) -> Dictionary:
	var ar := state.rules.agents
	var best := {}
	var best_value := -1
	var fort_level := p.level_of(ar.border_fort_family)
	if fort_level > 0:
		best_value = ar.border_fort_per_level * fort_level
		best = {"valore": best_value, "agente": null, "etichetta": Lang.t("il forte di confine")}
	for type_name in [AgentState.SPY, AgentState.ASSASSIN, AgentState.EMISSARY]:
		for a in state.agents:
			if a.region == p.id and a.faction == p.owner and a.type_name == type_name and a.valour > best_value:
				best_value = a.valour
				best = {"valore": best_value, "agente": a, "etichetta": Lang.t("l'agente %d (%s)") % [a.id, a.type_name]}
	return best


# --- 4. porte aperte ------------------------------------------------------------------------------------------------------------


## Una spia nella regione di un castello assediato dalla propria fazione apre le porte con probabilita'
## `k_porte * valore` all'anno (PROVVISORIA, catalogo: «apre le porte»): l'assedio finisce con la conquista
## (EV_GATES_OPENED); la guarnigione, fuori dal castello, combatte nello scontro dello stesso anno.
static func _open_gates(state: GameState) -> void:
	var ar := state.rules.agents
	for siege in state.sieges_in_order():
		var p := state.province(siege.region)
		if p == null or p.owner == siege.faction or not state.at_war(siege.faction, p.owner):
			continue
		for spy in state.agents:
			if spy.type_name != AgentState.SPY or spy.region != siege.region or spy.faction != siege.faction:
				continue
			var chance := minf(1.0, ar.gates_k * float(maxi(0, spy.valour)))
			if chance <= 0.0 or state.rng.randf() >= chance:
				continue
			var besieged := p.owner
			state.add_event(GameState.EV_GATES_OPENED, _agent_data(spy, siege.region, {
				"assediata": besieged,
				"probabilita": chance,
				"testo": Lang.t("Una spia di %s apre le porte del castello di %s (%s): l'assedio finisce con la conquista.") % [
					SimUtil.faction_label(siege.faction), WarProcessor.region_label(state, siege.region), SimUtil.faction_label(besieged)],
			}))
			grow_valour(state, spy)
			WarProcessor.transfer_province(state, p, siege.faction, ConquestDamage.MEANS_GATES)   # porte aperte da una spia
			break


# --- nascita, principesse, pulizia ----------------------------------------------------------------------------------------------


## Un agente reclutato nasce nella provincia (fine della coda di reclutamento): valore iniziale dell'edificio
## produttore, nome dalla lista della fazione (EV_AGENT_RECRUITED).
static func spawn_recruit(state: GameState, province: ProvinceState, unit: UnitType) -> AgentState:
	var a := state.create_agent(province.owner, province.id, unit.id, unit.type_name, state.year + 1)
	a.valour = clampi(initial_valour(state, province, unit) + state.rules.traits.agent_bonus(province.owner, unit.type_name), 0, state.rules.agents.max_valour)   # ADR-089
	apply_valour_floor(state, a)
	a.name = agent_name(state, a)
	state.add_event(GameState.EV_AGENT_RECRUITED, _agent_data(a, province.id, {
		"provincia": province.id,
		"valore": a.valour,
		"origine": "coda",
		"testo": Lang.t("%s recluta %s (%s) a %s.") % [SimUtil.faction_label(province.owner), a.name, a.type_name, WarProcessor.region_label(state, province.id)],
	}))
	return a


## Valore di un agente reclutato (PROVVISORIA): `valore_base + valore_per_livello * (livello - 1)`, con il livello
## piu' alto dell'edificio che soddisfa i requisiti dell'unita' nella provincia (1 se non ci sono requisiti).
static func initial_valour(state: GameState, province: ProvinceState, unit: UnitType) -> int:
	var ar := state.rules.agents
	var level := 1
	if province != null and unit != null:
		var best := 0
		for group in unit.requires:
			var satisfied := true
			var group_level := 0
			for token in group:
				var lv := state.buildings.resolve(token)
				if lv == null or province.level_of(lv.family) < lv.level:
					satisfied = false
					break
				group_level = maxi(group_level, province.level_of(lv.family))
			if satisfied:
				best = maxi(best, group_level)
		level = maxi(1, best)
	return clampi(ar.base_valour + ar.valour_per_level * (level - 1), 0, ar.max_valour)


## Valore di un agente senza valore (startpos o salvataggio precedente alla fase 5a): `valore_iniziale_startpos` per
## emissari e principesse, altrimenti il valore di un agente reclutato in quella provincia.
static func default_valour(state: GameState, a: AgentState) -> int:
	var ar := state.rules.agents
	if a.type_name == AgentState.EMISSARY or a.type_name == AgentState.PRINCESS:
		return clampi(ar.start_valour, 0, ar.max_valour)
	var unit: UnitType = null
	if state.units != null:
		unit = state.units.get_unit(a.unit_id)
	return initial_valour(state, state.province(a.region), unit)


## Nome dalla lista dei nomi della fazione, scelto con l'id (nessun sorteggio).
static func agent_name(state: GameState, a: AgentState) -> String:
	var names := CharacterFactory.forenames_of(state, a.faction)
	if names.is_empty():
		return ""
	return names[posmod(a.id - 1, names.size())]


## Da chiamare quando i nomi sono disponibili (partita nuova, salvataggi vecchi): dopo la creazione dei personaggi
## gli agenti senza nome ne ricevono uno.
static func name_agents(state: GameState) -> void:
	for a in state.agents:
		if a.name == "":
			a.name = agent_name(state, a)


## Capitale della fazione: la regione del capo (`PlaceLeader`) se e' sua, altrimenti la prima provincia posseduta,
## "" se non ne ha.
static func capital_of(state: GameState, faction_id: String) -> String:
	var cf := state.campaign.faction(faction_id)
	if cf != null:
		var own := state.province(cf.leader_region)
		if own != null and own.owner == SimUtil.norm(faction_id):
			return own.id
	var owned := state.provinces_of(faction_id)
	if owned.is_empty():
		return ""
	return owned[0].id


## Valore minimo della fazione (auror.cfg `agenti_al_massimo`: gli Auror hanno ogni agente al valore massimo): mai giu'.
static func apply_valour_floor(state: GameState, a: AgentState) -> void:
	var floor_value := state.rules.agent_valour_floor(a.faction)
	if floor_value > 0 and a.valour < floor_value:
		a.valour = floor_value


## Il valore minimo della fazione su tutti gli agenti in gioco: a fine anno (dopo le principesse, il cui valore segue
## l'acume), all'inizio della partita e al caricamento di un salvataggio.
static func apply_faction_minimum(state: GameState) -> void:
	for a in state.agents:
		apply_valour_floor(state, a)


## Il valore sale di `crescita_valore` (fino al massimo): missione riuscita o agente nemico catturato.
static func grow_valour(state: GameState, a: AgentState) -> void:
	var ar := state.rules.agents
	a.valour = mini(a.valour + ar.valour_growth, ar.max_valour)


## Toglie l'agente dal gioco; una principessa collegata a un personaggio porta via anche il personaggio (che esce
## dal gioco con la stessa causa: matrimonio, assassinio, catturato...).
static func remove_agent(state: GameState, a: AgentState, cause: String) -> void:
	if a.character_id != 0:
		var c := state.character(a.character_id)
		if c != null and c.alive:
			DynastyProcessor.kill(state, c, state.year + 1, cause, false)
	state.remove_agent(a)


## Fine anno, dopo le regole di dinastia e province: trattati e agenti di fazioni scomparse spariscono, gli agenti
## il cui personaggio e' morto o ritirato (principesse) spariscono, ogni principessa maggiorenne senza agente ne
## riceve uno nella capitale (valore = acume), il valore delle principesse segue l'acume.
static func sync_year(state: GameState) -> void:
	DiplomacyProcessor.cleanup(state)
	var kept: Array[AgentState] = []
	for a in state.agents:
		var f := state.faction(a.faction)
		var region := state.campaign.region(a.region)
		if f == null or not f.alive or a.faction == GameState.REBEL or region == null or region.is_sea:
			continue
		if a.type_name == AgentState.PRINCESS and a.character_id != 0:
			var c := state.character(a.character_id)
			if c == null or not c.alive or c.faction != a.faction or c.role != Character.ROLE_PRINCESS:
				continue
		kept.append(a)
	if kept.size() != state.agents.size():
		state.agents = kept
	expire_proposals(state)
	plan_journeys(state)
	if state.characters.is_empty():
		apply_faction_minimum(state)
		return
	var ar := state.rules.agents
	var new_year := state.year + 1
	for a in state.agents:
		if a.type_name == AgentState.PRINCESS and a.character_id != 0:
			var c := state.character(a.character_id)
			a.valour = clampi(c.effective(Character.ATTR_ACUMEN, state.rules, state.campaign), 0, ar.max_valour)
			a.name = c.full_name()
	for c in state.characters:
		if not c.alive or c.role != Character.ROLE_PRINCESS or c.male:
			continue
		var f := state.faction(c.faction)
		if f == null or not f.alive or c.age(new_year) < state.rules.dynasty.princess_age:
			continue
		if AgentMissions.princess_agent(state, c) != null:
			continue
		var capital := capital_of(state, c.faction)
		if capital == "":
			continue
		var unit_id := ""
		if state.units != null:
			var princess_unit := state.units.of_type(AgentState.PRINCESS)
			if not princess_unit.is_empty():
				unit_id = princess_unit[0].id
		var a := state.create_agent(c.faction, capital, unit_id, AgentState.PRINCESS, c.birth_year)
		a.character_id = c.id
		a.name = c.full_name()
		a.valour = clampi(c.effective(Character.ATTR_ACUMEN, state.rules, state.campaign), 0, ar.max_valour)
		state.add_event(GameState.EV_AGENT_RECRUITED, _agent_data(a, capital, {
			"provincia": capital,
			"valore": a.valour,
			"origine": "principessa",
			"personaggio": c.id,
			"testo": Lang.t("%s, principessa di %s, e' in eta' da marito: diventa un'agente a %s.") % [c.full_name(), SimUtil.faction_label(c.faction), WarProcessor.region_label(state, capital)],
		}))
	apply_faction_minimum(state)


# --- eventi -------------------------------------------------------------------------------------------------------------------


## Campi comuni degli eventi sugli agenti: fazione, regione, id e tipo dell'agente, piu' `extra`.
static func _agent_data(a: AgentState, region_id: String, extra: Dictionary) -> Dictionary:
	var data := {
		"fazione": a.faction,
		"regione": region_id,
		"agente": a.id,
		"tipo_agente": a.type_name,
	}
	data.merge(extra, true)
	return data


## Motivi di decadenza delle proposte nel testo dell'evento (stesse frasi di CampaignUiProposals.EXPIRY_REASONS).
const EXPIRY_TEXTS := {
	"scaduta": "il tempo per rispondere è finito",
	"agente": "l'emissario non c'è più",
	"proponente": "chi la proponeva è scomparso",
	"destinatario": "il destinatario è scomparso",
}
