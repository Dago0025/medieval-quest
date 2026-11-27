class_name PapacyProcessor
extends RefCounted
## Papato, scomuniche, crociate e jihad (fase 5c, spec. fase 5 §5c, ADR-010). `TurnProcessor.end_year` chiama
## `snapshot` all'inizio, `on_attack` per ogni attacco del movimento, `process_year` dopo la religione (5b) e prima
## del reddito, `spawn_crusade` quando una coda di reclutamento di `Crusade` o `Jihad` finisce.
##
## Il Papato e' la fazione `GameState.PAPAL` (FN_PAPIST), IA con un capo (il Papa). Senza quella fazione nel mondo
## (mondi di prova) o con il Papato distrutto non ci sono avvertimenti ne' nuove scomuniche, i doni non arrivano.
##
## Avvertimento: una fazione cattolica che dichiara guerra a un'altra cattolica ed e' la piu' grande delle due
## (province) viene ammonita (EV_PAPAL_WARNING): per `anni_avvertimento` anni non deve attaccare di nuovo (muovere un
## esercito in territorio o contro eserciti dell'altra); l'attacco dell'anno della dichiarazione non conta. Se
## rispetta il termine la guerra finisce con una tregua papale (EV_PAPAL_TRUCE); se attacca viene scomunicata. Attaccare
## il Papato = scomunica immediata. Gli eserciti crociati sono esenti (agiscono in nome del Papa).
##
## Ordine fisso di `process_year` (fazioni, avvertimenti ed eserciti in ordine fisso; l'unico sorteggio e' quello dei
## doni, piu' quelli di `CharacterFactory` quando il Papato riemerge; tutti da `state.rng`):
##   1. revoca delle scomuniche (morte del Papa, del capo scomunicato, fazione o Papato distrutti)
##   2. scadenza degli avvertimenti (tregua papale)
##   3. riemersione del Papato distrutto
##   4. eserciti crociati: distrutti dell'anno, bersaglio, esito, zelo, reclutamento, perdite e scioglimento
##   5. doni papali.
##
## Crociata e jihad (esercito con `Army.crusade`): vedi `new_crusade`. Si bandiscono reclutando l'unita' `Crusade` (cattolici
## non scomunicati, una alla volta per fazione) o `Jihad` (musulmani, piu' di una). Il bersaglio si sceglie con
## `GameCommands.set_crusade_target`. L'esercito attraversa i territori altrui senza dichiarare guerra e senza
## conquistarli; dichiara guerra solo al proprietario del bersaglio e conquista solo quello. Tutti i parametri sono
## in `rules.papacy` (data/regole/papato.cfg), PROVVISORI dove il catalogo non ha la formula.

const KIND_CRUSADE := "crociata"
const KIND_JIHAD := "jihad"

# motivi di scomunica
const REASON_PAPACY := "attacco_al_papato"
const REASON_WARNING := "attacco_durante_avvertimento"


# --- servizio ------------------------------------------------------------------------------------------------


## Vero se il Papato esiste nel mondo ed e' vivo.
static func papal_alive(state: GameState) -> bool:
	var f := state.faction(GameState.PAPAL)
	return f != null and f.alive


static func is_catholic(state: GameState, faction_id: String) -> bool:
	return ReligionProcessor.faction_religion(state, faction_id) == ProvinceState.CATHOLIC


static func is_excommunicated(state: GameState, faction_id: String) -> bool:
	var f := state.faction(faction_id)
	return f != null and f.excommunicated


## Genere dell'esercito crociato per un tipo di unita' ("CRUSADE" -> "crociata", "JIHAD" -> "jihad", altro -> "").
static func kind_of_unit(type_name: String) -> String:
	if type_name == AgentState.CRUSADE:
		return KIND_CRUSADE
	if type_name == AgentState.JIHAD:
		return KIND_JIHAD
	return ""


## Religione di una crociata (cattolica) o di un jihad (musulmano).
static func kind_religion(kind: String) -> String:
	return ProvinceState.MUSLIM if kind == KIND_JIHAD else ProvinceState.CATHOLIC


## Campo `Army.crusade` di un esercito crociato appena nato: senza bersaglio, zelo iniziale.
static func new_crusade(state: GameState, kind: String) -> Dictionary:
	return {
		"tipo": kind,
		"zelo": state.rules.papacy.initial_zeal,
		"bersaglio": "",
		"annunciato": "",
		"reclutate": [],
		"anno": state.year,
	}


## Fotografia degli eserciti crociati all'inizio del fine anno: serve a riconoscere quelli distrutti nel corso dell'anno.
static func snapshot(state: GameState) -> void:
	state.crusade_roster = {}
	for a in state.armies:
		if a.is_crusade():
			state.crusade_roster[a.id] = {"fazione": a.faction, "tipo": a.crusade_kind(), "regione": a.region}


## Stato papale di una fazione per l'interfaccia: "scomunicata", "anno", "papato_vivo", "papa" (id del capo del
## Papato, 0 se nessuno), "avvertimenti" (Array di {"contro", "anno", "scadenza"} in cui la fazione e' l'ammonita),
## "crociata" (id dell'esercito della crociata attiva, 0 se nessuna), "jihad" (id degli eserciti dei jihad attivi).
static func status(state: GameState, faction_id: String) -> Dictionary:
	var key := SimUtil.norm(faction_id)
	var f := state.faction(key)
	var warnings: Array = []
	var keys: Array = state.papal_warnings.keys()
	keys.sort()
	for k in keys:
		var pair := String(k).split(">")
		if pair.size() == 2 and pair[0] == key:
			var w := state.papal_warning(pair[0], pair[1])
			warnings.append({"contro": pair[1], "anno": int(w.get("anno", 0)), "scadenza": int(w.get("scadenza", 0))})
	var crusade_id := 0
	var jihads: Array = []
	for a in state.armies_of(key):
		if a.crusade_kind() == KIND_CRUSADE and crusade_id == 0:
			crusade_id = a.id
		elif a.crusade_kind() == KIND_JIHAD:
			jihads.append(a.id)
	var pope := state.leader_of(GameState.PAPAL)
	return {
		"scomunicata": f != null and f.excommunicated,
		"anno": f.excommunication_year if f != null else 0,
		"papato_vivo": papal_alive(state),
		"papa": pope.id if pope != null else 0,
		"avvertimenti": warnings,
		"crociata": crusade_id,
		"jihad": jihads,
	}


# --- avvertimenti e scomuniche -------------------------------------------------------------------------------


## Un attacco di `attacker` contro `enemy` entrando in `region_id` (da chiamare nel movimento prima di
## `GameState.declare_war`, per gli eserciti che non sono crociati): scomunica per l'attacco al Papato o durante un
## avvertimento; avvertimento se e' una dichiarazione di guerra della piu' grande tra due cattoliche. Restituisce
## l'evento registrato ("" se nessuno).
static func on_attack(state: GameState, attacker: String, enemy: String, region_id: String) -> String:
	var a := SimUtil.norm(attacker)
	var e := SimUtil.norm(enemy)
	if a == e or a == GameState.REBEL or a == GameState.PAPAL or e == GameState.REBEL or not papal_alive(state):
		return ""
	var fa := state.faction(a)
	var fe := state.faction(e)
	if fa == null or not fa.alive or fa.excommunicated or not is_catholic(state, a):
		return ""
	if e == GameState.PAPAL:
		return GameState.EV_EXCOMMUNICATION if excommunicate(state, a, REASON_PAPACY, region_id) else ""
	if fe == null or not fe.alive or fe.excommunicated or not is_catholic(state, e):
		return ""
	var warning := state.papal_warning(a, e)
	if not warning.is_empty():
		if state.year > int(warning.get("anno", 0)):
			return GameState.EV_EXCOMMUNICATION if excommunicate(state, a, REASON_WARNING, region_id) else ""
		return ""
	if state.at_war(a, e):
		return ""
	if state.provinces_of(a).size() <= state.provinces_of(e).size():
		return ""
	var until := state.year + state.rules.papacy.warning_years
	state.papal_warnings[GameState.warning_key(a, e)] = {"anno": state.year, "scadenza": until}
	state.add_event(GameState.EV_PAPAL_WARNING, {
		"fazione": a,
		"contro": e,
		"regione": region_id,
		"fino_al": until,
		"testo": Lang.t("Il Papa ammonisce %s: per %d anni non deve attaccare %s, o sara' scomunicata.") % [
			SimUtil.faction_label(a), state.rules.papacy.warning_years, SimUtil.faction_label(e)],
	})
	return GameState.EV_PAPAL_WARNING


## Scomunica la fazione (cattolica, viva, non gia' scomunicata): influenza del capo, alleanze con i cattolici rotte,
## avvertimenti a suo carico tolti, crociate in coda annullate (rimborsate) e crociata attiva privata dell'appoggio
## del Papa. Restituisce falso (nessun cambiamento) se la fazione non si puo' scomunicare. EV_EXCOMMUNICATION.
static func excommunicate(state: GameState, faction_id: String, reason: String, region_id: String = "") -> bool:
	var f := state.faction(faction_id)
	if f == null or not f.alive or f.excommunicated or f.id == GameState.REBEL or f.id == GameState.PAPAL:
		return false
	if not is_catholic(state, f.id):
		return false
	var pr := state.rules.papacy
	f.excommunicated = true
	f.excommunication_year = state.year
	var leader := state.leader_of(f.id)
	f.excommunication_leader = leader.id if leader != null else 0
	var lost := 0
	if leader != null:
		var before := leader.influence
		leader.influence = clampi(before - pr.excommunication_influence, 0, state.rules.dynasty.max_attribute)
		lost = before - leader.influence
	var prefix := f.id + ">"
	for key in state.papal_warnings.keys():
		if String(key).begins_with(prefix):
			state.papal_warnings.erase(key)
	var broken: Array[String] = []
	for g in state.factions:
		if g.id != f.id and g.alive and state.is_allied(f.id, g.id) and is_catholic(state, g.id):
			state.break_alliance(f.id, g.id)
			broken.append(g.id)
	var refunded := _purge_crusade_orders(state, f)
	state.add_event(GameState.EV_EXCOMMUNICATION, {
		"fazione": f.id,
		"regione": region_id,
		"motivo": reason,
		"influenza_persa": lost,
		"alleanze_rotte": Array(broken),
		"rimborso": refunded,
		"testo": Lang.t("%s e' scomunicata dal Papa (%s).") % [SimUtil.faction_label(f.id), _reason_label(reason)],
	})
	for g_id in broken:
		state.add_event(GameState.EV_ALLIANCE_BROKEN, {
			"fazione": f.id,
			"con": g_id,
			"regione": region_id,
			"motivo": "scomunica",
			"influenza_persa": 0,
			"testo": Lang.t("L'alleanza tra %s e %s cade per la scomunica.") % [SimUtil.faction_label(f.id), SimUtil.faction_label(g_id)],
		})
	for a in state.armies_of(f.id):
		if a.crusade_kind() == KIND_CRUSADE:
			_end_crusade(state, a, "scomunica", 0)
	return true


static func _reason_label(reason: String) -> String:
	if reason == REASON_PAPACY:
		return Lang.t("ha attaccato il Papato")
	if reason == REASON_WARNING:
		return Lang.t("ha ignorato l'avvertimento")
	return reason


## Toglie dalle code di reclutamento le crociate (rimborsando il costo pagato). Restituisce il totale rimborsato.
static func _purge_crusade_orders(state: GameState, f: FactionState) -> int:
	var refunded := 0
	for p in state.provinces_of(f.id):
		var kept: Array[QueueItem] = []
		for item in p.unit_queue:
			var unit: UnitType = null
			if state.units != null:
				unit = state.units.get_unit(item.key)
			if unit != null and unit.type_name == AgentState.CRUSADE:
				f.treasury += item.cost_paid
				refunded += item.cost_paid
			else:
				kept.append(item)
		p.unit_queue = kept
	return refunded


## Revoca la scomunica. Restituisce falso se la fazione non era scomunicata. EV_EXCOMMUNICATION_LIFTED.
static func lift_excommunication(state: GameState, faction_id: String, reason: String) -> bool:
	var f := state.faction(faction_id)
	if f == null or not f.excommunicated:
		return false
	f.excommunicated = false
	f.excommunication_year = 0
	f.excommunication_leader = 0
	state.add_event(GameState.EV_EXCOMMUNICATION_LIFTED, {
		"fazione": f.id,
		"regione": "",
		"motivo": reason,
		"testo": Lang.t("La scomunica di %s e' revocata (%s).") % [SimUtil.faction_label(f.id), Lang.t(reason.replace("_", " "))],
	})
	return true


## Termine di scomunica dell'obiettivo di lealta' (<= 0, PROVVISORIA): le province di una fazione scomunicata perdono
## `malus_lealta` x % di cattolici / 100 (arrotondato). Agganciato da `ProvinceProcessor.loyalty_terms` come «scomunica».
static func loyalty_term(state: GameState, p: ProvinceState) -> int:
	if p.owner == "" or p.owner == GameState.REBEL:
		return 0
	var f := state.faction(p.owner)
	if f == null or not f.excommunicated:
		return 0
	return -roundi(float(state.rules.papacy.excommunication_loyalty) * p.religion_pct(ProvinceState.CATHOLIC) / 100.0)


# --- passo annuale ---------------------------------------------------------------------------------------------


static func process_year(state: GameState) -> void:
	_revocations(state)
	_warnings(state)
	_papacy_reemergence(state)
	_crusades(state)
	_gifts(state)
	state.crusade_roster = {}


## 1. Le scomuniche cadono alla morte del Papa (o se il Papato e' distrutto), alla morte del capo scomunicato e se la
## fazione scompare.
static func _revocations(state: GameState) -> void:
	var papal := state.faction(GameState.PAPAL)
	var reason := ""
	if papal != null:
		var current := 0
		if papal.alive:
			var pope := state.leader_of(GameState.PAPAL)
			if pope != null:
				current = pope.id
			if state.papal_leader != 0 and current != state.papal_leader:
				reason = "morte_del_papa"
		else:
			reason = "papato_distrutto"
		state.papal_leader = current
	for f in state.factions:
		if not f.excommunicated:
			continue
		var why := reason
		if why == "":
			if not f.alive:
				why = "fazione_distrutta"
			elif f.excommunication_leader != 0:
				var leader := state.leader_of(f.id)
				var current_id := leader.id if leader != null else 0
				var old := state.character(f.excommunication_leader)
				if (old != null and not old.alive) or (current_id != 0 and current_id != f.excommunication_leader):
					why = "morte_del_capo"
			elif state.leader_of(f.id) != null:
				f.excommunication_leader = state.leader_of(f.id).id
		if why != "":
			lift_excommunication(state, f.id, why)


## 2. Gli avvertimenti scaduti senza attacchi finiscono in una tregua papale; quelli senza piu' senso cadono.
static func _warnings(state: GameState) -> void:
	var keys: Array = state.papal_warnings.keys()
	keys.sort()
	for key in keys:
		var pair := String(key).split(">")
		var warning: Dictionary = {}
		if pair.size() == 2:
			warning = state.papal_warning(pair[0], pair[1])
		if pair.size() != 2 or warning.is_empty():
			state.papal_warnings.erase(key)
			continue
		var offender := state.faction(pair[0])
		var protected_faction := state.faction(pair[1])
		var valid := papal_alive(state) and offender != null and offender.alive and not offender.excommunicated
		valid = valid and protected_faction != null and protected_faction.alive and not protected_faction.excommunicated
		valid = valid and state.at_war(pair[0], pair[1])
		if not valid:
			state.papal_warnings.erase(key)
			continue
		if state.year < int(warning.get("scadenza", 0)):
			continue
		state.papal_warnings.erase(key)
		var until := state.year + 1 + state.rules.papacy.papal_truce_years
		state.make_truce(pair[0], pair[1], until)
		state.add_event(GameState.EV_PAPAL_TRUCE, {
			"fazione": pair[0],
			"con": pair[1],
			"regione": "",
			"fino_al": until,
			"testo": Lang.t("Il Papa impone una tregua tra %s e %s fino al %d.") % [SimUtil.faction_label(pair[0]), SimUtil.faction_label(pair[1]), until],
		})


# --- 3. riemersione del Papato -----------------------------------------------------------------------------------


## Il Papato distrutto ricompare (ADR-072, Federico dal gioco originale): dopo un numero di anni a caso tra
## `anni_riemersione_min` e `anni_riemersione_max` (`PapacyRules.reemerge_chance`, un sorteggio all'anno nella finestra,
## solo se c'e' un luogo), ignorando la soglia di lealta' della riemersione normale, con un'armata che cresce a ogni volta.
## Luogo (`papal_site`): una provincia ribelle sua all'inizio o prima dei ribelli, poi una ribelle confinante con le sue
## province d'inizio; li' riemerge subito. Altrimenti una sua provincia d'inizio in mano ad altri: l'armata compare li'
## come ribelli lealisti del Papato (`_papal_uprising`) e, se la prende, la consegna al Papato che riemerge
## (`ProvinceProcessor._loyalist_handover` -> `reemerge_at`).
static func _papacy_reemergence(state: GameState) -> void:
	var f := state.faction(GameState.PAPAL)
	if f == null:
		return
	if f.alive:
		state.papacy_dead_years = 0
		return
	state.papacy_dead_years += 1
	var chance := state.rules.papacy.reemerge_chance(state.papacy_dead_years)
	if chance <= 0.0:
		return
	var site := papal_site(state)
	if site == null:
		return
	if chance < 1.0 and state.rng.randf() >= chance:
		return
	if site.owner == GameState.REBEL:
		_reemerge_papacy(state, f, site)
	else:
		_papal_uprising(state, f, site)


## Vero se la provincia era del Papato all'inizio della campagna.
static func is_papal_origin(state: GameState, p: ProvinceState) -> bool:
	return ProvinceProcessor.origin_owner(state, p) == GameState.PAPAL


## Dove puo' ricomparire il Papato distrutto (ADR-072), nell'ordine delle province: una ribelle sua all'inizio o prima dei
## ribelli; una ribelle confinante con una sua provincia d'inizio; una sua provincia d'inizio di un'altra fazione viva
## (insurrezione). null se non ce n'e'.
static func papal_site(state: GameState) -> ProvinceState:
	for p in state.provinces:
		if p.owner == GameState.REBEL and (is_papal_origin(state, p) or p.former_owner == GameState.PAPAL):
			return p
	var cf := state.campaign.faction(GameState.PAPAL)
	if cf != null and cf.leader_region != "":
		var capital := state.province(cf.leader_region)
		if capital != null and capital.owner == GameState.REBEL:
			return capital
	var origins: Array[ProvinceState] = []
	for p in state.provinces:
		if is_papal_origin(state, p):
			origins.append(p)
	for p in state.provinces:
		if p.owner != GameState.REBEL:
			continue
		var region := state.campaign.region(p.id)
		if region == null:
			continue
		for o in origins:
			if region.neighbours.has(o.id):
				return p
	for o in origins:
		var owner := state.faction(o.owner)
		if owner != null and owner.alive and owner.id != GameState.REBEL and owner.id != GameState.PAPAL:
			return o
	return null


## Truppe dell'armata del Papato che ricompare: il miscuglio dei lealisti del Papato nella regione
## (`ProvinceProcessor.loyalist_units`), altrimenti la truppa dei ribelli della regione. Vuoto se non ce n'e'.
static func papal_units(state: GameState, site: ProvinceState) -> Array[UnitType]:
	var region := state.campaign.region(site.id)
	var mix := ProvinceProcessor.loyalist_units(state, GameState.PAPAL, region)
	if mix.is_empty():
		var unit := ProvinceProcessor.rebel_unit(state, region)
		if unit != null:
			mix.append(unit)
	return mix


## Il Papato ricompare nella provincia `site` (ribelle) presa dai suoi lealisti (ADR-072): stessa riemersione, ma
## l'armata e' quella dei lealisti.
static func reemerge_at(state: GameState, site: ProvinceState) -> void:
	var f := state.faction(GameState.PAPAL)
	if f != null and not f.alive:
		_reemerge_papacy(state, f, site)


static func _reemerge_papacy(state: GameState, f: FactionState, site: ProvinceState) -> void:
	var pr := state.rules.papacy
	var new_year := state.year + 1
	f.alive = true
	f.excommunicated = false
	f.treasury = maxi(f.treasury, state.rules.province.reemerge_treasury)
	site.owner = f.id
	site.loyalty_owner = f.id
	site.former_owner = ""
	site.building_queue.clear()
	site.unit_queue.clear()
	site.tax_level = state.rules.default_tax
	site.counters["anni_sotto_soglia"] = 0
	var leader_id := 0
	if state.has_dynasty(f.id):
		var leader := CharacterFactory.make_new_leader(state, f.id, site.id, new_year, state.rng, pr.pope_age_min, pr.pope_age_max)
		leader_id = leader.id
	# i lealisti del Papato gia' nella provincia diventano il suo esercito (insurrezione riuscita), altrimenti un'armata nuova
	var army_id := 0
	var made := 0
	var created_men := 0
	for a in state.armies:
		if a.faction == GameState.REBEL and a.region == site.id and not a.is_fleet and a.loyal_to == f.id and not a.stacks.is_empty():
			a.faction = f.id
			a.loyal_to = ""
			if army_id == 0:
				army_id = a.id
			made += a.stacks.size()
	if army_id == 0:
		var stacks := pr.reemerge_army_stacks(state.papacy_reemergences, state.rules.max_stacks)
		var mix := papal_units(state, site)
		if not mix.is_empty():
			var army := state.create_army(f.id, site.id, false)
			for i in stacks:
				var u: UnitType = mix[i % mix.size()]
				army.stacks.append(state.new_stack(f.id, u.id, u.men))
			army_id = army.id
			made = stacks
			created_men = army.men_total()
		state.papacy_reemergences += 1
	for a in state.armies:
		if a.region == site.id and not a.is_fleet and a.in_castle and a.faction != site.owner:
			a.in_castle = false
	WarProcessor.refresh_sieges(state)
	state.papacy_dead_years = 0
	state.papal_leader = leader_id
	state.add_event(GameState.EV_PAPACY_REEMERGED, {
		"fazione": f.id,
		"regione": site.id,
		"provincia": site.id,
		"capo": leader_id,
		"esercito": army_id,
		"pile": made,
		"uomini": created_men,   # uomini creati (bilancio degli uomini nei test)
		"riemersioni": state.papacy_reemergences,
		"testo": Lang.t("Il Papato riemerge a %s con un esercito di %d pile (riemersione %d).") % [
			WarProcessor.region_label(state, site.id), made, state.papacy_reemergences],
	})


## Insurrezione papale (ADR-072): nella provincia d'inizio `site`, di un'altra fazione, compare un'armata di ribelli lealisti
## del Papato grande quanto quella della riemersione; il proprietario la deve battere. Se la prende, l'anno dopo il Papato
## riemerge li' (`reemerge_at`). Conta come riemersione (l'armata seguente e' piu' grande) e riazzera l'attesa.
## Registrata come EV_REBELLION con «papato» vero. Nessun sorteggio.
static func _papal_uprising(state: GameState, f: FactionState, site: ProvinceState) -> void:
	var pr := state.rules.papacy
	var mix := papal_units(state, site)
	if mix.is_empty():
		return
	var stacks := pr.reemerge_army_stacks(state.papacy_reemergences, state.rules.max_stacks)
	var army := state.create_army(GameState.REBEL, site.id, false)
	army.loyal_to = f.id
	for i in stacks:
		var u: UnitType = mix[i % mix.size()]
		army.stacks.append(state.new_stack(GameState.REBEL, u.id, u.men))
	state.papacy_reemergences += 1
	state.papacy_dead_years = 0
	WarProcessor.refresh_sieges(state)
	state.add_event(GameState.EV_REBELLION, {
		"fazione": site.owner,
		"regione": site.id,
		"provincia": site.id,
		"lealta": site.loyalty,
		"tipo_ribelli": ProvinceProcessor.REBEL_LOYALISTS,
		"lealisti_di": f.id,
		"papato": true,
		"esercito": army.id,
		"pile": stacks,
		"uomini": army.men_total(),
		"riemersioni": state.papacy_reemergences,
		"testo": Lang.t("Il Papato ricompare: un'armata di %d pile insorge a %s contro %s.") % [
			stacks, WarProcessor.region_label(state, site.id), SimUtil.faction_label(site.owner)],
	})


# --- 5. doni papali ---------------------------------------------------------------------------------------------------


## Una fazione cattolica non scomunicata con almeno `min_religiosi` religiosi cattolici (vescovi, sacerdoti) riceve
## `importo` denari con probabilita' `p_dono` all'anno (PROVVISORIA, catalogo: trigger ignoto). Un sorteggio per
## fazione adatta, in ordine di dichiarazione, solo con il Papato vivo.
static func _gifts(state: GameState) -> void:
	var pr := state.rules.papacy
	if pr.gift_chance <= 0.0 or not papal_alive(state):
		return
	var counts := {}
	for a in state.agents:
		if pr.gift_types.has(a.type_name) and ReligionProcessor.agent_religion(state, a) == ProvinceState.CATHOLIC:
			counts[a.faction] = int(counts.get(a.faction, 0)) + 1
	for f in state.factions:
		if not f.alive or f.id == GameState.REBEL or f.id == GameState.PAPAL or f.excommunicated:
			continue
		if int(counts.get(f.id, 0)) < pr.gift_min_religious or not is_catholic(state, f.id):
			continue
		if state.rng.randf() >= pr.gift_chance:
			continue
		f.treasury += pr.gift_amount
		state.add_event(GameState.EV_PAPAL_GIFT, {
			"fazione": f.id,
			"regione": "",
			"importo": pr.gift_amount,
			"religiosi": int(counts.get(f.id, 0)),
			"testo": Lang.t("Il Papa dona %d denari a %s.") % [pr.gift_amount, SimUtil.faction_label(f.id)],
		})


# --- crociate e jihad: reclutamento ---------------------------------------------------------------------------------------


## Motivo per cui la fazione non puo' bandire una crociata o un jihad (`kind`: KIND_CRUSADE o KIND_JIHAD), "" se puo'.
## Crociata: fazione cattolica, non scomunicata, nessun'altra crociata attiva ne' in coda (`check_queue`); jihad:
## fazione musulmana (piu' jihad ammessi). La religione della fazione viene dai dati (SetReligion).
static func launch_problem(state: GameState, faction_id: String, kind: String, check_queue: bool = true) -> String:
	var f := state.faction(faction_id)
	if f == null or not f.alive:
		return Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id
	var religion := ReligionProcessor.faction_religion(state, f.id)
	if kind == KIND_JIHAD:
		if religion != ProvinceState.MUSLIM:
			return Lang.t("Il jihad e' solo dei musulmani: %s non lo e'") % SimUtil.faction_label(f.id)
		return ""
	if religion != ProvinceState.CATHOLIC:
		return Lang.t("La crociata e' solo dei cattolici: %s non lo e'") % SimUtil.faction_label(f.id)
	if f.excommunicated:
		return Lang.t("%s e' scomunicata e non puo' bandire una crociata") % SimUtil.faction_label(f.id)
	for a in state.armies_of(f.id):
		if a.crusade_kind() == KIND_CRUSADE:
			return Lang.t("%s ha gia' una crociata attiva (esercito %d)") % [SimUtil.faction_label(f.id), a.id]
	if check_queue and state.units != null:
		for p in state.provinces_of(f.id):
			for item in p.unit_queue:
				var queued := state.units.get_unit(item.key)
				if queued != null and queued.type_name == AgentState.CRUSADE:
					return Lang.t("%s ha gia' una crociata in coda a %s") % [SimUtil.faction_label(f.id), p.id]
	return ""


## Le migliori truppe (fanteria e cavalleria) che la fazione puo' reclutare nella provincia: fazione, epoca, regione,
## cultura e requisiti dai dati, per costo decrescente (a parita' l'ordine del file). PROVVISORIA (spec.: «le migliori
## unita' reclutabili»); il tesoro e le code non contano.
static func best_units(state: GameState, faction_id: String, province: ProvinceState) -> Array[UnitType]:
	var out: Array[UnitType] = []
	if state.units == null:
		return out
	var region := state.campaign.region(province.id)
	for u in state.units.military():
		if u.type_name != UnitType.INFANTRY and u.type_name != UnitType.CAVALRY:
			continue
		if u.men <= 0 or not u.allows_faction(faction_id) or not u.available_in_period(state.era):
			continue
		if not HistoricalLimits.unit_allowed(state, faction_id, u):
			continue   # ADR-114
		if region != null and (not u.allows_region(region.id) or not u.allows_culture(GameCommands.culture_key(region.culture))):
			continue
		if not GameCommands.requirements_met(u.requires, province, state.buildings):
			continue
		out.append(u)
	out.sort_custom(_costlier_first)
	return out


## Ordine delle truppe: costo decrescente, a parita' l'ordine del file.
static func _costlier_first(x: UnitType, y: UnitType) -> bool:
	if x.cost != y.cost:
		return x.cost > y.cost
	return x.index < y.index


## Fanteria piu' economica ammessa dalla fazione, senza guardare edifici ne' epoca (ultima risorsa se `best_units` e' vuota).
static func _fallback_unit(state: GameState, faction_id: String) -> UnitType:
	var best: UnitType = null
	if state.units == null:
		return null
	for u in state.units.military():
		if u.type_name != UnitType.INFANTRY or u.men <= 0 or not u.allows_faction(faction_id):
			continue
		if best == null or u.cost < best.cost:
			best = u
	return best


## Alla fine della coda di `Crusade` o `Jihad` nasce l'esercito crociato nella provincia: `pile_iniziali` pile delle
## migliori truppe reclutabili, senza bersaglio, zelo iniziale. Un ultimo controllo (fazione scomunicata o crociata gia'
## attiva) rimborsa il costo senza far nascere nulla. EV_CRUSADE_LAUNCHED.
static func spawn_crusade(state: GameState, province: ProvinceState, unit: UnitType, item: QueueItem, errors: Array[String]) -> void:
	var kind := kind_of_unit(unit.type_name)
	var f := state.faction(province.owner)
	if kind == "" or f == null:
		errors.append("Reclutamento in %s: %s non e' una crociata ne' un jihad" % [province.id, unit.id])
		return
	if launch_problem(state, f.id, kind, false) != "":
		f.treasury += item.cost_paid
		return
	var pr := state.rules.papacy
	var pool := best_units(state, f.id, province)
	if pool.is_empty():
		var fallback := _fallback_unit(state, f.id)
		if fallback == null:
			errors.append("Reclutamento in %s: nessuna truppa per l'esercito crociato di %s" % [province.id, f.id])
			f.treasury += item.cost_paid
			return
		pool.append(fallback)
	var army := state.create_army(f.id, province.id, false)
	army.in_castle = state.is_besieged(province.id)
	var count := mini(pr.initial_stacks, mini(pr.max_stacks, state.rules.max_stacks))
	for i in maxi(1, count):
		var u: UnitType = pool[i % pool.size()]
		army.stacks.append(state.new_stack(f.id, u.id, u.men))
	army.crusade = new_crusade(state, kind)
	# bersaglio alla partenza (22/11/2026): l'avviso dice dove e' diretta; annunciato qui, non di nuovo a fine anno
	var target := initial_target(state, army)
	var target_owner := ""
	if target != "":
		army.crusade["bersaglio"] = target
		army.crusade["annunciato"] = target
		target_owner = state.province(target).owner
	var noun := Lang.t("La crociata") if kind == KIND_CRUSADE else Lang.t("Il jihad")
	var text := Lang.t("%s di %s parte da %s con %d pile") % [noun, SimUtil.faction_label(f.id), WarProcessor.region_label(state, province.id), army.stacks.size()]
	if target != "":
		text += Lang.t(", diretta a %s") % WarProcessor.region_label(state, target) if kind == KIND_CRUSADE else Lang.t(", diretto a %s") % WarProcessor.region_label(state, target)
	state.add_event(GameState.EV_CRUSADE_LAUNCHED, {
		"fazione": f.id,
		"regione": province.id,
		"genere": kind,
		"provincia": province.id,
		"esercito": army.id,
		"pile": army.stacks.size(),
		"uomini": army.men_total(),   # uomini creati
		"zelo": pr.initial_zeal,
		"bersaglio": target,
		"proprietario": target_owner,
		"testo": text + ".",
	})


## Bersaglio dell'esercito crociato alla partenza (PROVVISORIA, 22/11/2026): tra i bersagli validi entro
## `raggio_bersaglio_iniziale` passi di terra, quello con il punteggio piu' alto: (rendita base + 50 x livello del castello
## + 100) x rapporto di forze (0,25-3) / (1 + 0,5 x passi), come la scelta dell'IA. "" se non ce n'e' o con raggio 0.
static func initial_target(state: GameState, army: Army) -> String:
	var radius := state.rules.papacy.initial_target_radius
	if radius <= 0 or army == null or not army.is_crusade():
		return ""
	var own := Combat.army_strength(state, army)
	var depth := {army.region: 0}
	var queue: Array[String] = [army.region]
	var head := 0
	var best := ""
	var best_score := -1.0
	while head < queue.size():
		var current := queue[head]
		head += 1
		var steps := int(depth[current])
		if current != army.region and target_problem(state, army, current) == "":
			var region := state.campaign.region(current)
			var worth := float(region.income if region != null else 0) + 50.0 * float(Combat.castle_level(state, current)) + 100.0
			var defence := 0.0
			for other in state.armies_in(current):
				if other.faction != army.faction and not other.is_fleet:
					defence += Combat.army_strength(state, other)
			var ratio := clampf(own / maxf(defence, 1.0), 0.25, 3.0) if defence > 0.0 else 3.0
			var score := worth * ratio / (1.0 + 0.5 * float(steps))
			if score > best_score:
				best_score = score
				best = current
		if steps >= radius:
			continue
		var r := state.campaign.region(current)
		if r == null:
			continue
		for n in r.neighbours:
			var key := SimUtil.norm(n)
			if depth.has(key):
				continue
			var other_region := state.campaign.region(key)
			if other_region == null or other_region.is_sea:
				continue
			depth[key] = steps + 1
			queue.append(key)
	return best


# --- crociate e jihad: bersagli e movimento -----------------------------------------------------------------------------------


## Motivo per cui la provincia e' un bersaglio valido per `kind` ("scomunicato", "ribelle", "non_cattolico", "eretici"
## per la crociata; "musulmana" per il jihad), "" se non lo e'. Non guarda trattati ne' proprieta' dell'esercito.
## Crociata: provincia di una fazione scomunicata, dei ribelli, di una fazione non cattolica o a maggioranza eretica;
## mai quella del Papato. Jihad: provincia non musulmana che un tempo lo era (`former_owner` musulmano o maggioranza musulmana).
static func target_reason(state: GameState, kind: String, p: ProvinceState) -> String:
	if p.owner == "" or p.owner == GameState.PAPAL:
		return ""
	if kind == KIND_JIHAD:
		var owner_religion := ReligionProcessor.owner_religion(state, p)
		if owner_religion == ProvinceState.MUSLIM:
			return ""
		var was_muslim := p.majority_religion() == ProvinceState.MUSLIM
		if p.former_owner != "" and ReligionProcessor.faction_religion(state, p.former_owner) == ProvinceState.MUSLIM:
			was_muslim = true
		return "musulmana" if was_muslim else ""
	if p.owner == GameState.REBEL:
		return "ribelle"
	var owner_faction := state.faction(p.owner)
	if owner_faction == null or not owner_faction.alive:
		return ""
	if owner_faction.excommunicated:
		return "scomunicato"
	if not is_catholic(state, p.owner):
		return "non_cattolico"
	if p.majority_religion() == ProvinceState.HERETIC:
		return "eretici"
	return ""


## Motivo per cui `region_id` non e' un bersaglio valido per l'esercito crociato `army` ("" se lo e'): provincia di
## terra, non propria, bersaglio per la regola del genere (`target_reason`), proprietario ne' alleato ne' in tregua.
static func target_problem(state: GameState, army: Army, region_id: String) -> String:
	var region := state.campaign.region(region_id)
	if region == null:
		return Lang.t("Regione sconosciuta: %s") % region_id
	if region.is_sea:
		return Lang.t("Il bersaglio deve essere una provincia di terra (%s e' mare)") % region.id
	var p := state.province(region.id)
	if p == null:
		return Lang.t("Provincia sconosciuta: %s") % region.id
	if p.owner == army.faction:
		return Lang.t("%s e' gia' di %s") % [region.id, SimUtil.faction_label(army.faction)]
	var kind := army.crusade_kind()
	if target_reason(state, kind, p) == "":
		if kind == KIND_JIHAD:
			return Lang.t("%s non e' una provincia da riconquistare con il jihad") % region.id
		return Lang.t("%s non e' un bersaglio di crociata (serve un proprietario scomunicato, ribelle o non cattolico, o una maggioranza eretica)") % region.id
	var rel := state.relation(army.faction, p.owner)
	if rel == GameState.REL_ALLIANCE or rel == GameState.REL_TRUCE:
		return Lang.t("%s e' di %s, con cui %s ha un trattato (%s)") % [region.id, SimUtil.faction_label(p.owner), SimUtil.faction_label(army.faction), rel]
	return ""


## Bersagli validi dell'esercito crociato, in ordine di dichiarazione delle province: Array di
## {"regione", "nome", "proprietario", "motivo"}.
static func targets_of(state: GameState, army: Army) -> Array:
	var out: Array = []
	for p in state.provinces:
		if target_problem(state, army, p.id) != "":
			continue
		out.append({
			"regione": p.id,
			"nome": WarProcessor.region_label(state, p.id),
			"proprietario": p.owner,
			"motivo": target_reason(state, army.crusade_kind(), p),
		})
	return out


## Percorso piu' corto per terra (ricerca in ampiezza, ordine di SetNeighbours) dalla regione dell'esercito a
## `to_id`, vuoto se non c'e' o se si e' gia' li'. Non entra nelle regioni di mare.
static func land_route(state: GameState, from_id: String, to_id: String) -> PackedStringArray:
	var none := PackedStringArray()
	var start := state.campaign.region(from_id)
	var goal := state.campaign.region(to_id)
	if start == null or goal == null or start.id == goal.id or goal.is_sea:
		return none
	var parent := {start.id: ""}
	var queue: Array[String] = [start.id]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		var region := state.campaign.region(current)
		if region == null:
			continue
		for n in region.neighbours:
			var key := SimUtil.norm(n)
			if parent.has(key):
				continue
			var other := state.campaign.region(key)
			if other == null or other.is_sea:
				continue
			parent[key] = current
			if key == goal.id:
				var route := PackedStringArray()
				var step := key
				while step != start.id:
					route.insert(0, step)
					step = str(parent[step])
				return route
			queue.append(key)
	return none


## Fazioni che un esercito crociato attacca entrando in `region_id`: solo il proprietario del suo bersaglio.
## Le province attraversate e gli eserciti presenti non sono nemici (movimento in transito).
static func crusade_enemies(state: GameState, a: Army, region_id: String) -> Array[String]:
	var out: Array[String] = []
	if a.crusade_target() != "" and a.crusade_target() == region_id:
		var p := state.province(region_id)
		if p != null and p.owner != "" and p.owner != a.faction:
			out.append(p.owner)
	return out


## Pile al massimo in un esercito crociato (ADR-072, catalogo: fino a 32 unita'): `[crociata] max_pile`, mai sotto il limite
## degli eserciti normali.
static func crusade_stack_limit(state: GameState) -> int:
	return maxi(state.rules.papacy.max_stacks, state.rules.max_stacks)


## Vero se l'esercito puo' conquistare la provincia `region_id`: un esercito crociato solo il suo bersaglio.
static func may_conquer(a: Army, region_id: String) -> bool:
	return a.crusade.is_empty() or a.crusade_target() == region_id


# --- crociate e jihad: passo annuale ---------------------------------------------------------------------------------


static func _crusades(state: GameState) -> void:
	# eserciti crociati spariti durante l'anno (distrutti, catturati, affamati): fallimento
	var ids: Array = state.crusade_roster.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = state.crusade_roster[id]
		var a := state.army(int(id))
		if a == null:
			_failed_without_army(state, str(entry.get("fazione", "")), str(entry.get("tipo", "")), int(id), str(entry.get("regione", "")), "distrutto")
		elif a.is_crusade() and a.faction != str(entry.get("fazione", "")):
			# passato ad altri (guerra civile): non e' piu' una crociata
			var former := str(entry.get("fazione", ""))
			var kind := a.crusade_kind()
			a.crusade = {}
			_failed_without_army(state, former, kind, a.id, a.region, "perso")
	for a in state.armies.duplicate():
		if a.is_crusade() and state.armies.has(a):
			_process_crusade(state, a)


static func _process_crusade(state: GameState, a: Army) -> void:
	var pr := state.rules.papacy
	var kind := a.crusade_kind()
	var f := state.faction(a.faction)
	if f == null or not f.alive or a.faction == GameState.REBEL or a.is_fleet:
		a.crusade = {}
		return
	if kind == KIND_CRUSADE and f.excommunicated:
		_end_crusade(state, a, "scomunica", 0)
		return
	# bersaglio: esito, validita', annuncio
	var target := a.crusade_target()
	if target != "":
		var province := state.province(target)
		if province != null and province.owner == a.faction:
			_succeed(state, a)
			return
		var problem := target_problem(state, a, target)
		if problem != "":
			var former_owner := province.owner if province != null else ""
			a.crusade["bersaglio"] = ""
			a.crusade["annunciato"] = ""
			state.add_event(GameState.EV_CRUSADE_TARGET, {
				"fazione": a.faction,
				"regione": a.region,
				"genere": kind,
				"esercito": a.id,
				"bersaglio": "",
				"proprietario": former_owner,
				"motivo": problem,
				"testo": Lang.t("Il bersaglio %s dell'esercito %d non e' piu' valido: %s.") % [WarProcessor.region_label(state, target), a.id, problem],
			})
			target = ""
	if str(a.crusade.get("annunciato", "")) != target:
		a.crusade["annunciato"] = target
		var owner_id := ""
		if target != "":
			var announced := state.province(target)
			owner_id = announced.owner if announced != null else ""
		state.add_event(GameState.EV_CRUSADE_TARGET, {
			"fazione": a.faction,
			"regione": a.region,
			"genere": kind,
			"esercito": a.id,
			"bersaglio": target,
			"proprietario": owner_id,
			"testo": Lang.t("L'esercito %d di %s ha come bersaglio %s.") % [a.id, SimUtil.faction_label(a.faction), WarProcessor.region_label(state, target)] if target != "" else Lang.t("L'esercito %d di %s non ha piu' un bersaglio.") % [a.id, SimUtil.faction_label(a.faction)],
		})
	# zelo
	var zeal := int(a.crusade.get("zelo", pr.initial_zeal)) - pr.zeal_decay_year
	if target == "":
		zeal -= pr.zeal_decay_no_target
	zeal = clampi(zeal, 0, 100)
	a.crusade["zelo"] = zeal
	# reclutamento per zelo nella provincia attraversata
	_recruit_by_zeal(state, a, kind)
	# soglie: scioglimento, diserzioni, perdite
	if zeal <= pr.zeal_dissolve:
		_end_crusade(state, a, "scioglimento", -_failure_influence(state, kind), true)
		return
	var lost := 0
	var why := ""
	if zeal < pr.zeal_desertion:
		lost = pr.desertion_stacks
		why = "diserzione"
	elif zeal < pr.zeal_losses:
		lost = 1
		why = "perdite"
	if lost > 0:
		lost = mini(lost, a.stacks.size())
		var men_lost := 0
		for i in lost:
			men_lost += a.stacks[a.stacks.size() - 1].men
			a.stacks.remove_at(a.stacks.size() - 1)
		state.add_event(GameState.EV_CRUSADE_DESERTION, {
			"fazione": a.faction,
			"regione": a.region,
			"genere": kind,
			"esercito": a.id,
			"pile": lost,
			"uomini": men_lost,   # uomini tolti
			"zelo": zeal,
			"motivo": why,
			"testo": Lang.t("L'esercito %d di %s perde %d pile (%s, zelo %d).") % [a.id, SimUtil.faction_label(a.faction), lost, Lang.t(why), zeal],
		})
	if a.stacks.is_empty():
		_end_crusade(state, a, "senza_pile", -_failure_influence(state, kind), true)


static func _recruit_by_zeal(state: GameState, a: Army, kind: String) -> void:
	var pr := state.rules.papacy
	var p := state.province(a.region)
	if p == null or a.in_castle:
		return
	var done: Array = a.crusade.get("reclutate", [])
	var wanted := pr.zeal_recruit_stacks(p.zeal)
	if done.has(p.id) or p.majority_religion() != kind_religion(kind) or wanted <= 0:
		return
	var cap := crusade_stack_limit(state)
	var room := cap - a.stacks.size()
	if room <= 0:
		return
	var pool := best_units(state, a.faction, p)
	if pool.is_empty():
		var fallback := _fallback_unit(state, a.faction)
		if fallback != null:
			pool.append(fallback)
	if pool.is_empty():
		return
	var count := mini(wanted, room)
	var men_added := 0
	for i in count:
		var u: UnitType = pool[i % pool.size()]
		a.stacks.append(state.new_stack(a.faction, u.id, u.men))
		men_added += u.men
	done.append(p.id)
	a.crusade["reclutate"] = done
	state.add_event(GameState.EV_CRUSADE_RECRUITED, {
		"fazione": a.faction,
		"regione": p.id,
		"genere": kind,
		"esercito": a.id,
		"provincia": p.id,
		"pile": count,
		"uomini": men_added,   # uomini creati
		"zelo_provincia": p.zeal,
		"testo": Lang.t("L'esercito %d di %s recluta %d pile a %s (zelo %d).") % [a.id, SimUtil.faction_label(a.faction), count, WarProcessor.region_label(state, p.id), p.zeal],
	})


static func _failure_influence(state: GameState, kind: String) -> int:
	var pr := state.rules.papacy
	return pr.jihad_failure_influence if kind == KIND_JIHAD else pr.crusade_failure_influence


## Variazione dell'influenza del capo (limitata a 0..massimo). Restituisce quella applicata.
static func _change_influence(state: GameState, faction_id: String, delta: int) -> int:
	var leader := state.leader_of(faction_id)
	if leader == null or delta == 0:
		return 0
	var before := leader.influence
	leader.influence = clampi(before + delta, 0, state.rules.dynasty.max_attribute)
	return leader.influence - before


## Fine di una crociata senza esito: con `remove` l'esercito sparisce (scioglimento, senza pile), altrimenti diventa un
## esercito normale (scomunica). `delta` e' la variazione di influenza. EV_CRUSADE_FAILED.
static func _end_crusade(state: GameState, a: Army, reason: String, delta: int, remove: bool = false) -> void:
	var kind := a.crusade_kind()
	var applied := _change_influence(state, a.faction, delta)
	var text := Lang.t("%s di %s finisce (%s).") % [Lang.t("La crociata") if kind == KIND_CRUSADE else Lang.t("Il jihad"), SimUtil.faction_label(a.faction), Lang.t(reason.replace("_", " "))]
	state.add_event(GameState.EV_CRUSADE_FAILED, {
		"fazione": a.faction,
		"regione": a.region,
		"genere": kind,
		"esercito": a.id,
		"motivo": reason,
		"influenza": applied,
		"uomini": a.men_total() if remove else 0,   # uomini tolti con l'esercito sciolto
		"testo": text,
	})
	a.crusade = {}
	if remove:
		state.remove_army(a)


## Esercito crociato sparito o passato ad altri: influenza e evento come un fallimento.
static func _failed_without_army(state: GameState, faction_id: String, kind: String, army_id: int, region_id: String, reason: String) -> void:
	var f := state.faction(faction_id)
	var applied := 0
	if f != null and f.alive:
		applied = _change_influence(state, faction_id, -_failure_influence(state, kind))
	state.add_event(GameState.EV_CRUSADE_FAILED, {
		"fazione": faction_id,
		"regione": region_id,
		"genere": kind,
		"esercito": army_id,
		"motivo": reason,
		"influenza": applied,
		"testo": Lang.t("%s di %s fallisce (%s).") % [Lang.t("La crociata") if kind == KIND_CRUSADE else Lang.t("Il jihad"), SimUtil.faction_label(faction_id), Lang.t(reason.replace("_", " "))],
	})


## Il bersaglio e' della fazione: influenza, ricompensa di pile di un ordine militare (crociata), l'esercito torna normale.
static func _succeed(state: GameState, a: Army) -> void:
	var pr := state.rules.papacy
	var kind := a.crusade_kind()
	var target := a.crusade_target()
	var delta := pr.jihad_success_influence if kind == KIND_JIHAD else pr.crusade_success_influence
	var applied := _change_influence(state, a.faction, delta)
	var wanted := pr.order_stacks_jihad if kind == KIND_JIHAD else pr.order_stacks
	var orders := order_units(state, a.faction)
	var given := 0
	var men_given := 0
	var cap := crusade_stack_limit(state)
	var unit_name := ""
	if not orders.is_empty():
		for i in wanted:
			if a.stacks.size() >= cap:
				break
			var u: UnitType = orders[i % orders.size()]
			a.stacks.append(state.new_stack(a.faction, u.id, u.men))
			given += 1
			men_given += u.men
			if unit_name == "":
				unit_name = u.id
	a.crusade = {}
	state.add_event(GameState.EV_CRUSADE_SUCCEEDED, {
		"fazione": a.faction,
		"regione": target,
		"genere": kind,
		"esercito": a.id,
		"bersaglio": target,
		"influenza": applied,
		"pile_ordine": given,
		"uomini": men_given,   # uomini creati (ricompensa)
		"unita_ordine": unit_name,
		"testo": Lang.t("%s di %s conquista %s.") % [Lang.t("La crociata") if kind == KIND_CRUSADE else Lang.t("Il jihad"), SimUtil.faction_label(a.faction), WarProcessor.region_label(state, target)],
	})


## Truppe degli ordini militari che la fazione puo' avere come ricompensa: fanteria o cavalleria ammessa dalla fazione e
## dall'epoca con l'edificio degli ordini (`edificio_ordini`, CHAPTER_HOUSE) nei requisiti. Costo decrescente, a parita'
## l'ordine del file. La ricompensa non chiede gli edifici nella provincia.
static func order_units(state: GameState, faction_id: String) -> Array[UnitType]:
	var out: Array[UnitType] = []
	if state.units == null or state.buildings == null:
		return out
	for u in state.units.military():
		if u.type_name != UnitType.INFANTRY and u.type_name != UnitType.CAVALRY:
			continue
		if u.men <= 0 or not u.allows_faction(faction_id) or not u.available_in_period(state.era):
			continue
		if not HistoricalLimits.unit_allowed(state, faction_id, u):
			continue   # ADR-114
		var is_order := false
		for token in u.required_tokens():
			var lv := state.buildings.resolve(token)
			if lv != null and lv.family == state.rules.papacy.order_building:
				is_order = true
				break
		if is_order:
			out.append(u)
	out.sort_custom(_costlier_first)
	return out
