class_name EventProcessor
extends RefCounted
## Eventi storici, disastri, Peste Nera e Orda d'Oro (spec. fase 6 §6a). `TurnProcessor.end_year` chiama `process_year`
## dopo il Papato e prima della pulizia di agenti e trattati e del reddito.
##
## Ordine fisso di ogni anno (province in ordine di dichiarazione, eserciti in ordine di id; ogni sorteggio passa da
## `state.rng`, uno per ogni probabilita' maggiore di zero e solo se l'effetto e' possibile):
##   1. eventi storici (l'anno di ognuno e' deciso la prima volta, con un sorteggio per le finestre; accadono una sola
##      volta, nell'anno estratto; effetti nel vocabolario chiuso: merci, lealta, zelo, eretici, pieta_capo, tesoro, nessuno);
##   2. disastri, per provincia: inondazione, carestia, terremoto, peste (con propagazione alle confinanti); poi le tempeste
##      per flotta; poi la Peste Nera (una sola volta, annunciata dall'evento storico 54, con propagazione per confini e per mare);
##   3. Orda d'Oro: comparsa, regola fissa di attacco finche' non c'e' l'IA (fase 7), scioglimento.
## I disastri esistono solo se lo startpos dichiara le regioni immuni (`CampaignData.has_disaster_data`), l'Orda solo se
## la sua fazione e' dichiarata e inattiva, gli eventi storici solo se la tabella non e' vuota: gli altri mondi restano
## inerti e non consumano numeri casuali.
## Gli effetti di durata un anno (agricoltura dimezzata o a zero, reddito ridotto) stanno in `ProvinceState.temp_effects`,
## li legge `Economy.province_income` e li azzera `clear_temporary` subito dopo il calcolo del reddito.
## Tutti i parametri dei disastri e dell'Orda sono PROVVISORI (data/regole/eventi.cfg); le date e gli effetti degli eventi
## storici, con la fonte di ognuno, sono in data/eventi/eventi_storici.cfg.


static func process_year(state: GameState) -> void:
	if state.campaign == null:
		return
	var rules := state.rules.events
	var black_death_now := _historical(state, rules)
	var removed := false
	if state.campaign.has_disaster_data():
		removed = _disasters(state, rules, black_death_now)
	if _horde(state, rules):
		removed = true
	if removed:
		# un esercito sparito puo' chiudere un assedio e lasciare una fazione senza province ne' eserciti
		WarProcessor.refresh_sieges(state)
		ProvinceProcessor.destroy_empty_factions(state, state.year + 1)


## Azzera gli effetti di durata un anno di tutte le province (dopo il reddito).
static func clear_temporary(state: GameState) -> void:
	for p in state.provinces:
		if not p.temp_effects.is_empty():
			p.temp_effects = {}


# --- 1. eventi storici ----------------------------------------------------------------------------------


## Anno estratto per l'evento (0 se la tabella non lo conosce o non e' ancora stato deciso).
static func drawn_year(state: GameState, index: int) -> int:
	return int(state.historical_years.get(index, 0))


## Decide l'anno di ogni evento che non ce l'ha ancora: gli anni fissi senza sorteggio, le finestre con un sorteggio da
## `state.rng` tra il primo anno ancora possibile e l'ultimo (finestra gia' passata: l'ultimo anno, l'evento non accadra').
static func draw_years(state: GameState, rules: EventRules) -> void:
	for e in rules.history:
		if state.historical_years.has(e.index):
			continue
		if not e.is_window():
			state.historical_years[e.index] = e.year_from
			continue
		var lo := maxi(e.year_from, state.year)
		if lo > e.year_to:
			state.historical_years[e.index] = e.year_to
		else:
			state.historical_years[e.index] = state.rng.randi_range(lo, e.year_to)


## Fa accadere gli eventi storici dell'anno. Vero se e' accaduto l'evento che annuncia la Peste Nera.
static func _historical(state: GameState, rules: EventRules) -> bool:
	if rules.history.is_empty():
		return false
	draw_years(state, rules)
	var black_death := false
	for e in rules.history:
		if state.historical_done.has(e.index):
			continue
		if drawn_year(state, e.index) != state.year:
			continue
		apply_historical(state, e)
		state.historical_done[e.index] = state.year
		if e.index == rules.black_death_event:
			black_death = true
	return black_death


## Applica l'effetto di un evento storico e registra EV_HISTORICAL. Non controlla se e' gia' accaduto.
static func apply_historical(state: GameState, e: EventRules.HistoricalEvent) -> void:
	var regions: Array = []
	var factions: Array = []
	match e.effect:
		EventRules.EFFECT_GOODS:
			for region_id in e.regions:
				var p := state.province(region_id)
				var region := state.campaign.region(region_id)
				if p == null or region == null:
					continue
				for good in e.goods:
					if not region.trade_goods.has(good) and not p.extra_goods.has(good):
						p.extra_goods.append(good)
				regions.append(p.id)
		EventRules.EFFECT_ZEAL:
			for p in _scope_provinces(state, e):
				p.zeal = clampi(p.zeal + e.value, 0, 100)
				regions.append(p.id)
		EventRules.EFFECT_HERETICS:
			if e.value > 0:
				for p in _scope_provinces(state, e):
					if state.rules.events.is_immune(p.id):
						continue   # Atlantide (18/11/2026): niente eretici
					ReligionProcessor.shift(p, ProvinceState.HERETIC, float(e.value))
					regions.append(p.id)
		EventRules.EFFECT_LOYALTY:
			var target := _target_faction(state, e)
			var f := state.faction(target)
			if f != null and f.alive and not (e.value < 0 and _immune_faction(state, target)):
				var limit := state.rules.dynasty.max_attribute
				for c in state.characters:
					if c.alive and c.faction == target and (c.role == Character.ROLE_GENERAL or c.role == Character.ROLE_PRINCE):
						c.loyalty = clampi(c.loyalty + e.value, 0, limit)
				factions.append(target)
		EventRules.EFFECT_PIETY:
			var target_piety := _target_faction(state, e)
			var leader := state.leader_of(target_piety)
			if leader != null and not (e.value < 0 and _immune_faction(state, target_piety)):
				leader.piety = clampi(leader.piety + e.value, 0, state.rules.dynasty.max_attribute)
				factions.append(target_piety)
		EventRules.EFFECT_TREASURY:
			var target_treasury := _target_faction(state, e)
			var tf := state.faction(target_treasury)
			if tf != null and tf.alive and not (e.value < 0 and _immune_faction(state, target_treasury)):
				tf.treasury += e.value
				factions.append(target_treasury)
	var first_region := ""
	if not e.regions.is_empty():
		first_region = e.regions[0]
	state.add_event(GameState.EV_HISTORICAL, {
		"fazione": e.faction,
		"regione": first_region,
		"indice": e.index,
		"chiave": e.key,
		"effetto": e.effect,
		"valore": e.value,
		"regioni": regions,
		"fazioni": factions,
		"provvisoria": e.provisional,
		"testo": Lang.t("Evento storico «%s»: %s.") % [e.key.replace("_", " "), _effect_text(e, regions, factions)],
	})


## Vero se la capitale della fazione e' in una regione immune (Atlantide): gli eventi storici avversi non la toccano.
static func _immune_faction(state: GameState, faction_id: String) -> bool:
	var capital := AgentProcessor.capital_of(state, faction_id)
	return capital != "" and state.rules.events.is_immune(capital)


## Province colpite da un effetto su regioni: le regioni elencate, altrimenti tutte quelle della cultura, altrimenti
## quelle della fazione (al momento dell'evento).
static func _scope_provinces(state: GameState, e: EventRules.HistoricalEvent) -> Array[ProvinceState]:
	var out: Array[ProvinceState] = []
	if not e.regions.is_empty():
		for region_id in e.regions:
			var p := state.province(region_id)
			if p != null:
				out.append(p)
		return out
	if e.culture != "":
		for p in state.provinces:
			var region := state.campaign.region(p.id)
			if region != null and region.culture.strip_edges().to_upper() == e.culture:
				out.append(p)
		return out
	if e.faction != "":
		for p in state.provinces:
			if p.owner == e.faction:
				out.append(p)
	return out


## Fazione a cui vale l'effetto: quella dell'evento, altrimenti il proprietario della prima regione citata ("" se nessuno).
static func _target_faction(state: GameState, e: EventRules.HistoricalEvent) -> String:
	if e.faction != "":
		return e.faction
	for region_id in e.regions:
		var p := state.province(region_id)
		if p != null:
			return p.owner
	return ""


static func _signed(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return str(value)


static func _effect_text(e: EventRules.HistoricalEvent, regions: Array, factions: Array) -> String:
	match e.effect:
		EventRules.EFFECT_GOODS:
			return Lang.t("nuove merci (%s) in %d province") % [", ".join(e.goods), regions.size()]
		EventRules.EFFECT_ZEAL:
			return Lang.t("zelo %s in %d province") % [_signed(e.value), regions.size()]
		EventRules.EFFECT_HERETICS:
			return Lang.t("eretici %s in %d province") % [_signed(e.value), regions.size()]
		EventRules.EFFECT_LOYALTY:
			return Lang.t("lealta' dei generali %s (%d fazioni)") % [_signed(e.value), factions.size()]
		EventRules.EFFECT_PIETY:
			return Lang.t("pieta' del capo %s (%d fazioni)") % [_signed(e.value), factions.size()]
		EventRules.EFFECT_TREASURY:
			return Lang.t("tesoro %s (%d fazioni)") % [_signed(e.value), factions.size()]
	return Lang.t("nessun effetto")


# --- 2. disastri -------------------------------------------------------------------------------------------


## Disastri dell'anno. Vero se e' sparito un esercito (per le conseguenze sugli assedi e sulle fazioni).
static func _disasters(state: GameState, rules: EventRules, black_death_now: bool) -> bool:
	var removed := false
	var plagued := {}
	for p in state.provinces:
		# regioni immuni (Atlantide, 18/11/2026): il sorteggio resta, per non spostare i numeri casuali delle altre
		var immune := rules.is_immune(p.id)
		if rules.flood_chance > 0.0 and not state.campaign.is_unfloodable(p.id):
			if state.rng.randf() < rules.flood_chance and not immune:
				_flood(state, rules, p)
		if rules.famine_chance > 0.0:
			if state.rng.randf() < rules.famine_chance and not immune:
				_famine(state, rules, p)
		if rules.quake_chance > 0.0 and not state.campaign.is_unquakeable(p.id):
			if state.rng.randf() < rules.quake_chance_for(p.id):
				_quake(state, p)
		if rules.plague_chance > 0.0 and not plagued.has(p.id):
			if state.rng.randf() < rules.plague_chance and not immune:
				if _plague(state, rules, p, "", false, plagued):
					removed = true
				if rules.plague_spread > 0.0:
					var region := state.campaign.region(p.id)
					for n in region.neighbours:
						var q := state.province(n)
						if q == null or plagued.has(q.id):
							continue
						if state.rng.randf() < rules.plague_spread and not rules.is_immune(q.id):
							if _plague(state, rules, q, p.id, false, plagued):
								removed = true
	if rules.storm_chance > 0.0:
		for a in state.armies.duplicate():
			if not a.is_fleet or a.stacks.is_empty():
				continue
			if state.rules.storm_immune_factions.has(SimUtil.norm(a.faction)):
				continue   # flotte_immuni_tempeste (auror.cfg): gli Auror non affondano nelle tempeste (23/11/2026)
			if state.rng.randf() < rules.storm_chance * storm_factor(state, a):
				if _storm(state, a):
					removed = true
	if _black_death(state, rules, black_death_now):
		removed = true
	return removed


static func _flood(state: GameState, rules: EventRules, p: ProvinceState) -> void:
	p.add_temp_factor(ProvinceState.TEMP_FARM, rules.flood_farm)
	state.add_event(GameState.EV_FLOOD, {
		"fazione": p.owner,
		"regione": p.id,
		"provincia": p.id,
		"proprietario": p.owner,
		"testo": Lang.t("Inondazione a %s: il raccolto dell'anno e' dimezzato.") % WarProcessor.region_label(state, p.id),
	})


static func _famine(state: GameState, rules: EventRules, p: ProvinceState) -> void:
	p.add_temp_factor(ProvinceState.TEMP_FARM, 0.0)
	var before := p.loyalty
	p.loyalty = maxi(0, p.loyalty - rules.famine_loyalty)
	state.add_event(GameState.EV_FAMINE, {
		"fazione": p.owner,
		"regione": p.id,
		"provincia": p.id,
		"proprietario": p.owner,
		"lealta_persa": before - p.loyalty,
		"testo": Lang.t("Carestia a %s: nessun raccolto quest'anno e lealta' in calo.") % WarProcessor.region_label(state, p.id),
	})


## Un edificio casuale (non il castello) perde un livello. Un sorteggio solo se c'e' un edificio da colpire.
static func _quake(state: GameState, p: ProvinceState) -> void:
	var castle := state.rules.combat.castle_family
	var candidates: Array[String] = []
	for family in p.buildings:
		if str(family) != castle and int(p.buildings[family]) > 0:
			candidates.append(str(family))
	candidates.sort()
	var hit := ""
	var level := 0
	if not candidates.is_empty():
		hit = candidates[state.rng.randi_range(0, candidates.size() - 1)]
		level = int(p.buildings[hit]) - 1
		if level <= 0:
			p.buildings.erase(hit)
			level = 0
		else:
			p.buildings[hit] = level
	state.add_event(GameState.EV_QUAKE, {
		"fazione": p.owner,
		"regione": p.id,
		"provincia": p.id,
		"proprietario": p.owner,
		"edificio": hit,
		"livello": level,
		"testo": Lang.t("Terremoto a %s%s.") % [WarProcessor.region_label(state, p.id), (Lang.t(": %s perde un livello") % hit) if hit != "" else ""],
	})


## Quanto la flotta rischia le tempeste: il fattore della nave piu' fragile (`fattore_tempeste` delle unita' degli Auror,
## 1 per tutte le altre). Richiesta di Federico del 18/11/2026: le Fregate del Drago affondavano troppo spesso.
static func storm_factor(state: GameState, fleet: Army) -> float:
	var worst := 0.0
	for st in fleet.stacks:
		worst = maxf(worst, ship_storm_factor(st.unit_id))
	return worst


static func ship_storm_factor(unit_id: String) -> float:
	return clampf(float(AurorUnits.value(unit_id, "fattore_tempeste", 1.0)), 0.0, 1.0)


## La flotta perde la sua ultima pila tra le navi piu' fragili. Vero se la flotta sparisce.
static func _storm(state: GameState, fleet: Army) -> bool:
	var pick := fleet.stacks.size() - 1
	for i in range(fleet.stacks.size() - 1, -1, -1):
		if ship_storm_factor(fleet.stacks[i].unit_id) > ship_storm_factor(fleet.stacks[pick].unit_id):
			pick = i
	var lost_stack: UnitStack = fleet.stacks[pick]
	fleet.stacks.remove_at(pick)
	var men := lost_stack.men
	var gone := fleet.stacks.is_empty()
	if gone:
		state.remove_army(fleet)
	state.add_event(GameState.EV_STORM, {
		"fazione": fleet.faction,
		"regione": fleet.region,
		"esercito": fleet.id,
		"uomini": men,
		"pile": 1,
		"testo": Lang.t("Tempesta in %s: la flotta di %s perde una pila (%d uomini)%s.") % [
			WarProcessor.region_label(state, fleet.region), SimUtil.faction_label(fleet.faction), men, Lang.t(" ed e' perduta") if gone else ""],
	})
	return gone


## Peste in una provincia: eserciti e guarnigioni perdono la frazione `fraction`. Vero se e' sparito un esercito.
static func _plague(state: GameState, rules: EventRules, p: ProvinceState, origin: String, black: bool, plagued: Dictionary) -> bool:
	plagued[p.id] = true
	var fraction := rules.black_death_losses if black else rules.plague_losses
	var lost := 0
	var touched := 0
	var removed := false
	for a in state.armies_in(p.id):
		if a.is_fleet:
			continue
		var before := a.men_total()
		if _hurt_army(state, a, fraction):
			removed = true
		var delta := before - a.men_total()
		if delta > 0:
			lost += delta
			touched += 1
	var place := WarProcessor.region_label(state, p.id)
	var text := Lang.t("Peste a %s: %d uomini morti.") % [place, lost]
	if black:
		text = Lang.t("La Peste Nera colpisce %s: %d uomini morti.") % [place, lost]
	elif origin != "":
		text = Lang.t("La peste si propaga a %s (da %s): %d uomini morti.") % [place, WarProcessor.region_label(state, origin), lost]
	state.add_event(GameState.EV_PLAGUE, {
		"fazione": p.owner,
		"regione": p.id,
		"provincia": p.id,
		"proprietario": p.owner,
		"uomini": lost,
		"eserciti": touched,
		"origine": origin,
		"peste_nera": black,
		"testo": text,
	})
	return removed


## Ogni pila perde `fraction` dei suoi uomini (arrotondato); le pile a zero spariscono e un esercito senza pile e' sciolto.
## Un esercito crociato non perde mai la sua ultima pila ne' scende sotto un uomo per pila (la crociata finisce
## con le sue regole, `PapacyProcessor`). Vero se l'esercito e' sparito.
static func _hurt_army(state: GameState, a: Army, fraction: float) -> bool:
	var keep := a.is_crusade()
	var kept: Array[UnitStack] = []
	for s in a.stacks:
		var cap := s.men - 1 if keep else s.men
		if Combat.is_invulnerable(state.units, s):
			cap = 0   # Ankalagon non perde il suo unico membro
		var loss := clampi(roundi(float(s.men) * fraction), 0, maxi(0, cap))
		s.men -= loss
		if s.men > 0:
			kept.append(s)
	a.stacks = kept
	if kept.is_empty():
		state.remove_army(a)
		return true
	return false


# --- Peste Nera -----------------------------------------------------------------------------------------------


## Peste Nera dell'anno. `announced` e' vero se l'evento storico che la annuncia e' accaduto quest'anno. Vero se e' sparito
## un esercito.
static func _black_death(state: GameState, rules: EventRules, announced: bool) -> bool:
	var bd := state.black_death
	var linked := rules.black_death_event >= 0 and rules.historical(rules.black_death_event) != null
	if bd.is_empty() and not linked:
		# senza evento storico che la annunci l'anno si estrae qui, una volta (finestra gia' passata: mai)
		var lo := maxi(rules.black_death_from, state.year)
		if lo > rules.black_death_to:
			bd = {"iniziata": false, "finita": true}
		else:
			bd = {"iniziata": false, "finita": false, "programmata": state.rng.randi_range(lo, rules.black_death_to)}
		state.black_death = bd
	if bd.is_empty() and not announced:
		return false
	if not bool(bd.get("iniziata", false)) and not bool(bd.get("finita", false)):
		var due := announced or (not linked and int(bd.get("programmata", 0)) == state.year)
		if not due:
			return false
		if not _start_black_death(state, rules):
			return false
		bd = state.black_death
	if not bool(bd.get("iniziata", false)) or bool(bd.get("finita", false)):
		return false
	return _black_death_year(state, rules)


## Comincia la Peste Nera nelle regioni di origine (solo le dichiarate). Falso se nessuna lo e'.
static func _start_black_death(state: GameState, rules: EventRules) -> bool:
	var sick := {}
	var origin: Array = []
	for region_id in rules.black_death_origin:
		if state.province(region_id) != null and not rules.is_immune(region_id):
			sick[state.province(region_id).id] = rules.black_death_years
			origin.append(state.province(region_id).id)
	if sick.is_empty():
		return false
	var planned: int = int(state.black_death.get("programmata", 0))
	state.black_death = {
		"iniziata": true,
		"finita": false,
		"anno": state.year,
		"colpite": sick,
		"guarite": [],
		"anni": 0,
	}
	if planned > 0:
		state.black_death["programmata"] = planned   # resta nei salvataggi: l'anno estratto quando non c'e' l'evento storico
	state.add_event(GameState.EV_BLACK_DEATH, {
		"fazione": "",
		"regione": origin[0],
		"regioni": origin,
		"anno_inizio": state.year,
		"testo": Lang.t("La Peste Nera comincia a %s.") % WarProcessor.region_label(state, str(origin[0])),
	})
	return true


## Un anno di Peste Nera: perdite e reddito ridotto nelle regioni colpite, poi propagazione per confini e per mare.
static func _black_death_year(state: GameState, rules: EventRules) -> bool:
	var bd := state.black_death
	var sick: Dictionary = bd["colpite"]
	var cured: Array = bd["guarite"]
	var removed := false
	var plagued := {}
	var newly: Array[String] = []
	for p in state.provinces:
		if not sick.has(p.id):
			continue
		if _plague(state, rules, p, "", true, plagued):
			removed = true
		p.add_temp_factor(ProvinceState.TEMP_INCOME, rules.black_death_income)
		for link in black_death_links(state, p.id):
			var target := str(link["id"])
			if sick.has(target) or cured.has(target) or newly.has(target):
				continue
			var chance := rules.black_death_sea if bool(link["mare"]) else rules.black_death_spread
			if chance > 0.0 and state.rng.randf() < chance and not rules.is_immune(target):
				newly.append(target)
	for p in state.provinces:
		if sick.has(p.id):
			sick[p.id] = int(sick[p.id]) - 1
			if int(sick[p.id]) <= 0:
				sick.erase(p.id)
				cured.append(p.id)
	for target in newly:
		sick[target] = rules.black_death_years
	bd["anni"] = int(bd.get("anni", 0)) + 1
	if sick.is_empty() or int(bd["anni"]) >= rules.black_death_max_years:
		bd["finita"] = true
		sick.clear()
	return removed


## Province a cui la Peste Nera puo' passare dalla regione: prima i confini di terra (nell'ordine del file), poi i porti
## che si affacciano su una delle stesse zone di mare (nell'ordine di dichiarazione delle regioni). Elenco di
## {"id", "mare"}, senza ripetizioni.
static func black_death_links(state: GameState, region_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var region := state.campaign.region(region_id)
	if region == null:
		return out
	for n in region.neighbours:
		var other := state.campaign.region(n)
		if other != null and not other.is_sea and state.province(other.id) != null and not seen.has(other.id):
			seen[other.id] = true
			out.append({"id": other.id, "mare": false})
	if not region.has_port:
		return out
	for n in region.neighbours:
		var sea := state.campaign.region(n)
		if sea == null or not sea.is_sea:
			continue
		for other in state.campaign.regions:
			if other.is_sea or not other.has_port or other.id == region.id or seen.has(other.id):
				continue
			if other.neighbours.has(sea.id) and state.province(other.id) != null:
				seen[other.id] = true
				out.append({"id": other.id, "mare": true})
	return out


# --- 3. Orda d'Oro ---------------------------------------------------------------------------------------------


## Orda d'Oro dell'anno. Vero se e' sparito un esercito.
static func _horde(state: GameState, rules: EventRules) -> bool:
	var f := state.faction(rules.horde_faction)
	if f == null:
		return false
	if state.horde.is_empty():
		if state.year == rules.horde_year and not f.alive:
			_horde_arrives(state, rules, f)
		return false
	if str(state.horde.get("stato", "")) != "attiva":
		return false
	if not f.alive:
		# distrutta in battaglia: le sue province erano gia' passate ad altri
		_horde_dissolve(state, f, "distrutta")
		return false
	var conquests := 0
	for e in state.events:
		if str(e.get("tipo", "")) == GameState.EV_PROVINCE_CAPTURED and str(e.get("fazione", "")) == f.id:
			conquests += 1
	if conquests > 0:
		state.horde["conquiste"] = int(state.horde.get("conquiste", 0)) + conquests
		state.horde["senza_conquiste"] = 0
	else:
		state.horde["senza_conquiste"] = int(state.horde.get("senza_conquiste", 0)) + 1
	if int(state.horde["senza_conquiste"]) >= rules.horde_years:
		return _horde_dissolve(state, f, "senza_conquiste")
	if not state.ai_orders_horde:
		# fase 7: con l'IA attiva gli ordini dell'Orda li da' l'IA (BARBARIAN_RAIDER), non questa regola fissa
		_horde_orders(state, f)
	return false


## Cavalleria migliore per l'Orda (PROVVISORIA): cavalli (non cammelli) di cultura e periodo giusti, preferendo le unita'
## che nominano la fazione dell'Orda, poi le piu' costose; non gli ordini militari; senza cavalleria adatta la fanteria
## dei ribelli. Gli edifici richiesti non contano (l'Orda non recluta).
static func horde_unit(state: GameState, rules: EventRules, region: CampaignData.Region) -> UnitType:
	if state.units == null:
		return null
	var cf := state.campaign.faction(rules.horde_faction)
	var culture_key := ""
	if cf != null:
		culture_key = GameCommands.culture_key(cf.culture)
	var order_building := state.rules.papacy.order_building
	for faction_must_match in [true, false]:
		var best: UnitType = null
		var best_named := false
		for u in state.units.military():
			if u.type_name != UnitType.CAVALRY or u.men <= 0 or u.mount_type == "CAMEL":
				continue
			if faction_must_match and not u.allows_faction(rules.horde_faction):
				continue
			if culture_key != "" and not u.allows_culture(culture_key):
				continue
			if not u.available_in_period(state.era):
				continue
			if _needs_building(u, order_building):
				continue
			var named := u.factions.has(rules.horde_faction)
			if best == null or (named and not best_named) or (named == best_named and u.cost > best.cost):
				best = u
				best_named = named
		if best != null:
			return best
	return ProvinceProcessor.rebel_unit(state, region)


static func _needs_building(u: UnitType, building: String) -> bool:
	for group in u.requires:
		if group.has(building):
			return true
	return false


## Regione di ingresso: la prima dei ribelli, altrimenti quella con la guarnigione piu' debole (a parita' la prima).
static func horde_entry(state: GameState, rules: EventRules) -> CampaignData.Region:
	var weakest: CampaignData.Region = null
	var weakest_men := 0
	for region_id in rules.horde_entry:
		var region := state.campaign.region(region_id)
		var p := state.province(region_id)
		if region == null or region.is_sea or p == null:
			continue
		if p.owner == GameState.REBEL:
			return region
		var men := 0
		for a in state.armies_in(region.id):
			if a.faction == p.owner and not a.is_fleet:
				men += a.men_total()
		if weakest == null or men < weakest_men:
			weakest = region
			weakest_men = men
	return weakest


static func _horde_arrives(state: GameState, rules: EventRules, f: FactionState) -> void:
	var region := horde_entry(state, rules)
	if region == null:
		return
	var unit := horde_unit(state, rules, region)
	if unit == null:
		return
	var p := state.province(region.id)
	f.alive = true
	f.treasury = maxi(f.treasury, rules.horde_treasury)
	var ids: Array = []
	var men := 0
	var left := rules.horde_stacks
	while left > 0:
		var count := mini(left, maxi(1, state.rules.max_stacks))
		var army := state.create_army(f.id, region.id, false)
		for i in count:
			army.stacks.append(state.new_stack(f.id, unit.id, unit.men))
		army.arrived_year = state.year + 1
		men += army.men_total()
		ids.append(army.id)
		left -= count
	state.horde = {"stato": "attiva", "arrivo": state.year, "ingresso": region.id, "senza_conquiste": 0, "conquiste": 0}
	if p.owner != GameState.REBEL and p.owner != f.id:
		DiplomacyProcessor.break_for_attack(state, f.id, p.owner, region.id)
		if state.declare_war(f.id, p.owner):
			state.add_event(GameState.EV_WAR_DECLARED, {
				"fazione": f.id,
				"contro": p.owner,
				"regione": region.id,
				"esercito": int(ids[0]),
				"testo": Lang.t("%s dichiara guerra a %s (invasione di %s).") % [SimUtil.faction_label(f.id), SimUtil.faction_label(p.owner), WarProcessor.region_label(state, region.id)],
			})
			DiplomacyProcessor.resolve_conflicting_alliances(state, f.id, p.owner, region.id)
	state.add_event(GameState.EV_HORDE_ARRIVES, {
		"fazione": f.id,
		"regione": region.id,
		"provincia": region.id,
		"eserciti": ids,
		"pile": rules.horde_stacks,
		"unita": unit.id,
		"uomini": men,
		"testo": Lang.t("L'Orda d'Oro arriva a %s con %d pile (%d uomini).") % [WarProcessor.region_label(state, region.id), rules.horde_stacks, men],
	})


## Regola fissa dell'Orda finche' non c'e' l'IA: ogni esercito fermo in una provincia dell'Orda attacca la confinante
## di terra piu' ricca (rendita della regione) che non e' sua; un esercito che sta ancora conquistando resta dov'e'.
static func _horde_orders(state: GameState, f: FactionState) -> void:
	for a in state.armies_of(f.id):
		if a.is_fleet or a.in_castle or not a.path.is_empty() or a.stacks.is_empty():
			continue
		var here := state.province(a.region)
		if here == null or here.owner != f.id or state.siege_in(a.region) != null:
			continue
		var target := richest_neighbour(state, f.id, a.region)
		if target != "":
			a.path = PackedStringArray([target])


## Confinante di terra piu' ricca (rendita di SetAttributes, a parita' la prima del file) che non e' della fazione;
## "" se non ce n'e'.
static func richest_neighbour(state: GameState, faction_id: String, region_id: String) -> String:
	var region := state.campaign.region(region_id)
	if region == null:
		return ""
	var best := ""
	var best_income := -1
	for n in region.neighbours:
		var other := state.campaign.region(n)
		var p := state.province(n)
		if other == null or other.is_sea or p == null or p.owner == faction_id:
			continue
		if other.income > best_income:
			best = other.id
			best_income = other.income
	return best


## L'Orda sparisce: le sue province diventano ribelli, i suoi eserciti sono sciolti, la fazione torna inattiva.
## Vero se sono spariti eserciti.
static func _horde_dissolve(state: GameState, f: FactionState, reason: String) -> bool:
	var provinces: Array = []
	for p in state.provinces:
		if p.owner == f.id:
			ProvinceProcessor.make_rebel(state, p, f.id)
			provinces.append(p.id)
	var ids: Array = []
	var men := 0
	for a in state.armies_of(f.id):
		men += a.men_total()
		ids.append(a.id)
		state.remove_army(a)
	f.alive = false
	state.horde["stato"] = "sciolta"
	var why := Lang.t("dopo anni senza conquiste") if reason == "senza_conquiste" else Lang.t("distrutta in battaglia")
	state.add_event(GameState.EV_HORDE_GONE, {
		"fazione": f.id,
		"regione": "",
		"motivo": reason,
		"province": provinces,
		"eserciti": ids,
		"uomini": men,
		"testo": Lang.t("L'Orda d'Oro scompare (%s): %d province passano ai ribelli.") % [why, provinces.size()],
	})
	return not ids.is_empty()


# --- salvataggi -------------------------------------------------------------------------------------------------


## Stato degli eventi come Dictionary di soli tipi JSON (chiavi di testo): eventi storici accaduti e anni estratti, Peste
## Nera, Orda d'Oro.
static func save_data(state: GameState) -> Dictionary:
	var done := {}
	for index in state.historical_done:
		done[str(index)] = int(state.historical_done[index])
	var years := {}
	for index in state.historical_years:
		years[str(index)] = int(state.historical_years[index])
	return {
		"accaduti": done,
		"anni": years,
		"peste_nera": state.black_death.duplicate(true),
		"orda": state.horde.duplicate(true),
	}


## Ricostruisce lo stato degli eventi da `save_data` (anche dopo il passaggio dal testo JSON: i numeri sono float).
static func load_data(state: GameState, data: Variant) -> void:
	state.historical_done = {}
	state.historical_years = {}
	state.black_death = {}
	state.horde = {}
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	var done: Variant = d.get("accaduti", {})
	if typeof(done) == TYPE_DICTIONARY:
		var done_dict: Dictionary = done
		for key in done_dict:
			state.historical_done[int(str(key))] = int(done_dict[key])
	var years: Variant = d.get("anni", {})
	if typeof(years) == TYPE_DICTIONARY:
		var years_dict: Dictionary = years
		for key in years_dict:
			state.historical_years[int(str(key))] = int(years_dict[key])
	var bd: Variant = d.get("peste_nera", {})
	if typeof(bd) == TYPE_DICTIONARY:
		state.black_death = _clean_black_death(bd)
	var horde_data: Variant = d.get("orda", {})
	if typeof(horde_data) == TYPE_DICTIONARY:
		var hd: Dictionary = horde_data
		if not hd.is_empty():
			state.horde = {
				"stato": str(hd.get("stato", "attiva")),
				"arrivo": int(hd.get("arrivo", 0)),
				"ingresso": str(hd.get("ingresso", "")),
				"senza_conquiste": int(hd.get("senza_conquiste", 0)),
				"conquiste": int(hd.get("conquiste", 0)),
			}


## Peste Nera con i tipi giusti (interi, testi, bool).
static func _clean_black_death(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	var out := {
		"iniziata": bool(raw.get("iniziata", false)),
		"finita": bool(raw.get("finita", false)),
	}
	if raw.has("programmata"):
		out["programmata"] = int(raw["programmata"])
	if raw.has("anno"):
		out["anno"] = int(raw["anno"])
	if raw.has("anni"):
		out["anni"] = int(raw["anni"])
	if raw.has("colpite"):
		var sick := {}
		var sick_raw: Variant = raw["colpite"]
		if typeof(sick_raw) == TYPE_DICTIONARY:
			var sick_dict: Dictionary = sick_raw
			for key in sick_dict:
				sick[str(key)] = int(sick_dict[key])
		out["colpite"] = sick
	if raw.has("guarite"):
		var cured: Array = []
		var cured_raw: Variant = raw["guarite"]
		if typeof(cured_raw) == TYPE_ARRAY:
			var cured_list: Array = cured_raw
			for item in cured_list:
				cured.append(str(item))
		out["guarite"] = cured
	return out
