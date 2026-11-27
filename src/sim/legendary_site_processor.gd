class_name LegendarySiteProcessor
extends RefCounted
## Passo annuale dei luoghi leggendari (LegendarySites, richiesta di Federico del 26/11/2026): scoperta alla prima
## conquista, eventi ricorrenti, storici e condizionati (alcuni con una scelta), perdite di transito e presidio delle zone di
## mare. Le scelte del giocatore restano in attesa in `GameState.site_choices` (GameCommands.choose_site_option); quelle
## lasciate in sospeso si risolvono da sole all'inizio del fine anno seguente con l'opzione che sceglierebbe l'IA.
## I sorteggi usano un generatore proprio derivato dal seme e dall'anno, per non spostare i numeri casuali del resto del
## turno (come l'IA, ADR-012).
##
## Stato di ogni luogo in `GameState.sites_state[id]`: "conquistatori" (fazioni che lo hanno gia' posseduto), "prossimo"
## {id evento: anno}, "attesa" {id evento: {fazione: anno}}, "usato" {id evento: [id personaggi o fazioni]}, "presidio",
## "presidio_anni", "fine" (luogo chiuso da un esito), "ordine" {"punti", "fino"} (lealta' temporanea), "fatti" (eventi
## storici gia' accaduti).

const CATEGORY := "luoghi"     ## voce delle spese della fazione


## Prima volta: chi possiede i luoghi all'inizio della partita li conosce gia' (nessuna scoperta per loro).
static func ensure_init(state: GameState) -> void:
	if state.rules == null or state.rules.sites.is_empty() or bool(state.sites_state.get("_pronto", false)):
		return
	for s in state.rules.sites.sites:
		var st := _st(state, s.id)
		var owner := LegendarySites.owner_of(state, s) if state.campaign != null and state.campaign.region(s.region) != null else ""
		if owner != "":
			_add_unique(st, "conquistatori", owner)
	state.sites_state["_pronto"] = true


static func _st(state: GameState, site_id: String) -> Dictionary:
	if not state.sites_state.has(site_id):
		state.sites_state[site_id] = {}
	return state.sites_state[site_id]


static func _add_unique(st: Dictionary, key: String, value: Variant) -> void:
	var list: Array = st.get(key, [])
	if not list.has(value):
		list.append(value)
	st[key] = list


static func _rng(state: GameState, salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d|%d|%s" % [state.seed_value, state.year, salt])
	return r


# --- passo annuale -----------------------------------------------------------------------------------------------------


static func process_year(state: GameState) -> void:
	if state.rules == null or state.rules.sites.is_empty():
		return
	ensure_init(state)
	var rng := _rng(state, "luoghi")
	# 27/11/2026: luoghi in ordine casuale ogni anno, cosi' il tetto di eventi per fazione non premia sempre i primi del file
	var order: Array = state.rules.sites.sites.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = order[i]
		order[i] = order[j]
		order[j] = tmp
	var fired := {}   # fazione -> eventi ricorrenti e condizionati gia' avvenuti quest'anno
	for item in order:
		var s: LegendarySites.Site = item
		if not LegendarySites.is_active(state, s):
			continue
		if s.is_sea():
			_sea_year(state, s, rng)
		else:
			_discovery(state, s)
		for eid in s.events:
			if not LegendarySites.is_active(state, s):
				break   # un esito ha chiuso il luogo
			var e: LegendarySites.SiteEvent = state.rules.sites.event(eid)
			if e != null:
				_event_year(state, s, e, rng, fired)


## Lealta' temporanea lasciata da un esito (`ordine`), letta da ProvinceProcessor.loyalty_terms.
static func temp_loyalty(state: GameState, region_id: String) -> int:
	if state.rules == null or state.rules.sites.is_empty():
		return 0
	var total := 0
	for item in state.rules.sites.in_region(region_id):
		var s: LegendarySites.Site = item
		var st: Dictionary = state.sites_state.get(s.id, {})
		var o: Dictionary = st.get("ordine", {})
		if not o.is_empty() and int(o.get("fino", 0)) >= state.year:
			total += int(o.get("punti", 0))
	return total


static func _discovery(state: GameState, s: LegendarySites.Site) -> void:
	var owner := LegendarySites.owner_of(state, s)
	if owner == "":
		return
	var st := _st(state, s.id)
	var known: Array = st.get("conquistatori", [])
	if known.has(owner):
		return
	_add_unique(st, "conquistatori", owner)
	var lines := apply_outcome(state, s, owner, {}, s.discovery) if not s.discovery.is_empty() else PackedStringArray()
	state.add_event(GameState.EV_SITE_DISCOVERED, {
		"fazione": owner,
		"regione": s.region,
		"luogo": s.id,
		"esito": "\n".join(lines),
		"testo": Lang.t("%s conquista %s.") % [SimUtil.faction_label(owner), s.label(state.year)],
	})


static func _sea_year(state: GameState, s: LegendarySites.Site, rng: RandomNumberGenerator) -> void:
	var st := _st(state, s.id)
	# presidio: una sola fazione con flotte nella zona, anno dopo anno
	var holders := {}
	for a in state.armies_in(s.region):
		if a.is_fleet and not a.stacks.is_empty() and a.faction != GameState.REBEL:
			holders[a.faction] = true
	if holders.size() == 1:
		var who := str(holders.keys()[0])
		if str(st.get("presidio", "")) == who:
			st["presidio_anni"] = int(st.get("presidio_anni", 0)) + 1
		else:
			st["presidio"] = who
			st["presidio_anni"] = 1
	else:
		st["presidio"] = ""
		st["presidio_anni"] = 0
	# perdite di transito: chi presidia e' immune
	var loss := int(s.transit.get("perdite", 0))
	if loss <= 0:
		return
	var holder := LegendarySites.garrison_holder(state, s)
	for a in state.armies_in(s.region).duplicate():
		if not a.is_fleet or a.stacks.is_empty() or a.faction == holder:
			continue
		if rng.randi_range(1, 100) <= loss:
			var men := _lose_ships(state, a, 1)
			if men >= 0:
				state.add_event(GameState.EV_SITE_TRANSIT, {
					"fazione": a.faction,
					"regione": s.region,
					"luogo": s.id,
					"esercito": a.id,
					"uomini": men,
					"testo": Lang.t("%s: la flotta di %s perde una nave (%d uomini).") % [s.label(state.year), SimUtil.faction_label(a.faction), men],
				})


## Vero se la fazione ha gia' avuto quest'anno gli eventi concessi (`max_eventi_fazione_anno`).
static func _capped(state: GameState, fired: Dictionary, faction: String) -> bool:
	var cap := state.rules.sites.max_per_faction
	return cap > 0 and int(fired.get(faction, 0)) >= cap


static func _event_year(state: GameState, s: LegendarySites.Site, e: LegendarySites.SiteEvent, rng: RandomNumberGenerator, fired: Dictionary = {}) -> void:
	var st := _st(state, s.id)
	var cat := state.rules.sites
	match e.kind:
		LegendarySites.KIND_HISTORICAL:
			var done: Array = st.get("fatti", [])
			if e.year != state.year or done.has(e.id):
				return
			_add_unique(st, "fatti", e.id)
			var owner := LegendarySites.owner_of(state, s)
			if owner == "" and not s.is_sea():
				# l'evento storico accade comunque: lo si annuncia a tutti senza esiti
				_emit(state, s, e, "", {}, PackedStringArray(), 0)
				return
			trigger(state, s, e, owner, {})
		LegendarySites.KIND_RECURRING:
			var owner := LegendarySites.owner_of(state, s)
			if owner == "" or (e.until_year > 0 and state.year > e.until_year):
				return
			if not e.religions.is_empty() and not e.religions.has(ReligionProcessor.faction_religion(state, owner)):
				return
			var next: Dictionary = st.get("prossimo", {})
			var every := cat.interval_of(e)
			if not next.has(e.id):
				next[e.id] = state.year + rng.randi_range(every.x, every.y)
				st["prossimo"] = next
				return
			if state.year < int(next[e.id]):
				return
			if _capped(state, fired, owner):
				return   # gia' un evento quest'anno: questo aspetta l'anno dopo
			next[e.id] = state.year + rng.randi_range(every.x, every.y)
			st["prossimo"] = next
			fired[owner] = int(fired.get(owner, 0)) + 1
			trigger(state, s, e, owner, {})
		LegendarySites.KIND_CONDITIONAL:
			if not LegendarySites.manifests(s, state.year):
				return
			for ctx in _candidates(state, s, e):
				var faction := str(ctx["fazione"])
				if not _may_fire(state, st, e, faction, ctx) or _capped(state, fired, faction):
					continue
				if rng.randi_range(1, 100) > cat.chance_of(e):
					continue
				fired[faction] = int(fired.get(faction, 0)) + 1
				_mark_fired(state, st, e, faction, ctx)
				trigger(state, s, e, faction, ctx)
				return   # un solo evento condizionato per luogo e anno


## Chi puo' far scattare un evento condizionato: {"fazione", "esercito" o "agente", "personaggio"}.
static func _candidates(state: GameState, s: LegendarySites.Site, e: LegendarySites.SiteEvent) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match e.who:
		LegendarySites.WHO_GENERAL, LegendarySites.WHO_FLEET:
			var fleet := e.who == LegendarySites.WHO_FLEET
			for a in state.armies_in(s.region):
				if a.stacks.is_empty() or a.is_fleet != fleet or a.faction == GameState.REBEL:
					continue
				var c := state.commander_of(a.id)
				if not fleet and c == null:
					continue
				out.append({"fazione": a.faction, "esercito": a.id, "personaggio": c.id if c != null else 0})
		LegendarySites.WHO_AGENT:
			for ag in state.agents_in(s.region):
				if ag.faction != GameState.REBEL:
					out.append({"fazione": ag.faction, "agente": ag.id, "personaggio": 0})
	if not e.religions.is_empty():
		var kept: Array[Dictionary] = []
		for ctx in out:
			if e.religions.has(ReligionProcessor.faction_religion(state, str(ctx["fazione"]))):
				kept.append(ctx)
		out = kept
	return out


static func _once_key(e: LegendarySites.SiteEvent, faction: String, ctx: Dictionary) -> String:
	if e.once == "personaggio":
		if int(ctx.get("personaggio", 0)) > 0:
			return "p%d" % int(ctx["personaggio"])
		if int(ctx.get("agente", 0)) > 0:
			return "a%d" % int(ctx["agente"])
		return "f" + faction
	if e.once == "fazione":
		return "f" + faction
	return ""


static func _may_fire(state: GameState, st: Dictionary, e: LegendarySites.SiteEvent, faction: String, ctx: Dictionary) -> bool:
	var key := _once_key(e, faction, ctx)
	if key != "":
		var used: Dictionary = st.get("usato", {})
		return not (used.get(e.id, []) as Array).has(key)
	var waits: Dictionary = st.get("attesa", {})
	var by_faction: Dictionary = waits.get(e.id, {})
	return state.year >= int(by_faction.get(faction, 0))


static func _mark_fired(state: GameState, st: Dictionary, e: LegendarySites.SiteEvent, faction: String, ctx: Dictionary) -> void:
	var key := _once_key(e, faction, ctx)
	if key != "":
		var used: Dictionary = st.get("usato", {})
		var list: Array = used.get(e.id, [])
		list.append(key)
		used[e.id] = list
		st["usato"] = used
		return
	var waits: Dictionary = st.get("attesa", {})
	var by_faction: Dictionary = waits.get(e.id, {})
	by_faction[faction] = state.year + maxi(1, e.wait)
	waits[e.id] = by_faction
	st["attesa"] = waits


# --- eventi e scelte ---------------------------------------------------------------------------------------------------


## L'evento `e` del luogo tocca alla fazione `faction`: esito diretto, scelta dell'IA o scelta in attesa del giocatore.
static func trigger(state: GameState, s: LegendarySites.Site, e: LegendarySites.SiteEvent, faction: String, ctx: Dictionary) -> void:
	var men := _men_of(state, ctx)
	if not e.has_choice():
		var lines := apply_outcome(state, s, faction, ctx, e.outcome) if faction != "" else PackedStringArray()
		_emit(state, s, e, faction, ctx, lines, 0, -1, men - _men_of(state, ctx))
		return
	var f := state.faction(faction)
	if f != null and f.is_player:
		var choice := {"id": state.next_site_choice_id, "luogo": s.id, "evento": e.id, "fazione": faction, "anno": state.year,
			"contesto": ctx.duplicate()}
		state.next_site_choice_id += 1
		state.site_choices.append(choice)
		_emit(state, s, e, faction, ctx, PackedStringArray(), int(choice["id"]))
		return
	var index := ai_option(state, e, faction, ctx)
	var lines := _apply_option(state, s, e, faction, ctx, index, _rng(state, "scelta|%s|%s" % [e.id, faction]))
	_emit(state, s, e, faction, ctx, lines, 0, index, men - _men_of(state, ctx))


## Uomini dell'esercito o della flotta del contesto (0 se non c'e' o se e' sparito): per dichiarare le perdite nell'evento.
static func _men_of(state: GameState, ctx: Dictionary) -> int:
	var army := state.army(int(ctx.get("esercito", 0)))
	if army == null or not state.armies.has(army):
		return 0
	var total := 0
	for st in army.stacks:
		total += st.men
	return total


static func _emit(state: GameState, s: LegendarySites.Site, e: LegendarySites.SiteEvent, faction: String, ctx: Dictionary, lines: PackedStringArray, choice_id: int, option: int = -1, men_lost: int = 0) -> void:
	var data := {
		"uomini": maxi(0, men_lost),
		"fazione": faction,
		"regione": s.region,
		"luogo": s.id,
		"evento": e.id,
		"titolo": e.label(),
		"testo": e.body(),
		"esito": "\n".join(lines),
		"scelta": choice_id,
		"opzione": option,
	}
	data.merge(ctx, false)
	state.add_event(GameState.EV_SITE_EVENT, data)


## Scelte in attesa per il giocatore `faction_id`, in ordine di id.
static func choices_for(state: GameState, faction_id: String) -> Array[Dictionary]:
	var key := SimUtil.norm(faction_id)
	var out: Array[Dictionary] = []
	for c in state.site_choices:
		if str(c["fazione"]) == key:
			out.append(c)
	return out


static func choice(state: GameState, choice_id: int) -> Dictionary:
	for c in state.site_choices:
		if int(c["id"]) == choice_id:
			return c
	return {}


## Perche' l'opzione non si puo' scegliere ("" = si puo').
static func option_problem(state: GameState, e: LegendarySites.SiteEvent, faction: String, ctx: Dictionary, index: int) -> String:
	if index < 0 or index >= e.options.size():
		return Lang.t("Opzione non valida")
	var req: Dictionary = e.options[index].get("richiede", {})
	var f := state.faction(faction)
	if f == null:
		return Lang.t("Fazione sconosciuta")
	var cost := int(req.get("costo", 0))
	if cost > 0 and f.treasury < cost:
		return Lang.t("Servono %d denari") % cost
	var stars := int(req.get("stelle", 0))
	if stars > 0 and _present_stars(state, ctx) < stars:
		return Lang.t("Serve un comandante con almeno %d stelle") % stars
	var rels: Array = req.get("religioni", [])
	if not rels.is_empty() and not rels.has(ReligionProcessor.faction_religion(state, faction)):
		return Lang.t("Non e' possibile per la vostra religione")
	var buildings: Dictionary = req.get("edificio", {})
	if not buildings.is_empty():
		var s := state.rules.sites.site(e.site)
		var p := state.province(s.region) if s != null else null
		for fam in buildings:
			if p == null or p.level_of(str(fam)) < int(buildings[fam]):
				return Lang.t("Manca l'edificio richiesto")
	return ""


## Opzione dell'IA: la possibile con `ia` piu' alto (a parita' la prima).
static func ai_option(state: GameState, e: LegendarySites.SiteEvent, faction: String, ctx: Dictionary) -> int:
	var best := -1
	var best_w := -1000
	for i in e.options.size():
		if option_problem(state, e, faction, ctx, i) != "":
			continue
		var w := int(e.options[i].get("ia", 0))
		if w > best_w:
			best_w = w
			best = i
	return maxi(best, 0) if best >= 0 else _first_free(state, e, faction, ctx)


static func _first_free(state: GameState, e: LegendarySites.SiteEvent, faction: String, ctx: Dictionary) -> int:
	for i in e.options.size():
		if option_problem(state, e, faction, ctx, i) == "":
			return i
	return -1


## Applica la scelta `index` di una voce in attesa (GameCommands.choose_site_option). Esito: righe dei risultati.
static func resolve_choice(state: GameState, c: Dictionary, index: int) -> PackedStringArray:
	var s := state.rules.sites.site(str(c["luogo"]))
	var e := state.rules.sites.event(str(c["evento"]))
	state.site_choices.erase(c)
	if s == null or e == null:
		return PackedStringArray()
	var ctx: Dictionary = c.get("contesto", {})
	return _apply_option(state, s, e, str(c["fazione"]), ctx, index, _rng(state, "scelta|%d" % int(c["id"])))


## All'inizio del fine anno: le scelte lasciate in sospeso negli anni passati si prendono da sole (opzione dell'IA).
static func settle_overdue(state: GameState) -> void:
	for c in state.site_choices.duplicate():
		if int(c["anno"]) >= state.year:
			continue
		var e := state.rules.sites.event(str(c["evento"])) if state.rules != null else null
		if e == null:
			state.site_choices.erase(c)
			continue
		var index := ai_option(state, e, str(c["fazione"]), c.get("contesto", {}))
		var men := _men_of(state, c.get("contesto", {}))
		var lines := resolve_choice(state, c, index)
		var s := state.rules.sites.site(str(c["luogo"]))
		if s != null:
			_emit(state, s, e, str(c["fazione"]), c.get("contesto", {}), lines, 0, index, men - _men_of(state, c.get("contesto", {})))


static func _apply_option(state: GameState, s: LegendarySites.Site, e: LegendarySites.SiteEvent, faction: String, ctx: Dictionary, index: int, rng: RandomNumberGenerator) -> PackedStringArray:
	if index < 0 or option_problem(state, e, faction, ctx, index) != "":
		return PackedStringArray([Lang.t("Nessuna scelta possibile: non succede nulla.")])
	var opt: Dictionary = e.options[index]
	var lines := PackedStringArray()
	var cost := int((opt.get("richiede", {}) as Dictionary).get("costo", 0))
	if cost > 0:
		var f := state.faction(faction)
		f.spend(cost, CATEGORY)
		lines.append(Lang.t("Spesi %d denari") % cost)
	var results: Array = opt.get("esiti", [])
	if results.is_empty():
		return lines
	var roll := rng.randi_range(1, 100)
	var acc := 0
	var picked: Dictionary = results[results.size() - 1]
	for r in results:
		acc += int(r.get("p", 0))
		if roll <= acc:
			picked = r
			break
	lines.append_array(apply_outcome(state, s, faction, ctx, picked))
	return lines


# --- esiti ---------------------------------------------------------------------------------------------------------------


## Applica un esito alla fazione (e al comandante, all'esercito o all'agente del contesto). Righe leggibili dei risultati.
static func apply_outcome(state: GameState, s: LegendarySites.Site, faction: String, ctx: Dictionary, outcome: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var f := state.faction(faction)
	if f == null:
		return lines
	var treasure := int(outcome.get("tesoro", 0))
	if treasure != 0:
		if treasure > 0:
			f.treasury += treasure
		else:
			f.spend(-treasure, CATEGORY)
		lines.append(Lang.t("Tesoro %+d denari") % treasure)
	var leader := state.leader_of(faction)
	for pair in [["pieta_capo", Character.ATTR_PIETY, "Pieta' del capo"], ["terrore_capo", Character.ATTR_DREAD, "Terrore del capo"],
			["influenza_capo", Character.ATTR_INFLUENCE, "Influenza del capo"], ["acume_capo", Character.ATTR_ACUMEN, "Acume del capo"]]:
		var n := int(outcome.get(pair[0], 0))
		if n != 0 and leader != null:
			_add_attr(state, leader, str(pair[1]), n)
			lines.append("%s %+d" % [Lang.t(str(pair[2])), n])
	var loyalty := int(outcome.get("lealta_generali", 0))
	if loyalty != 0:
		for c in state.characters_of(faction):
			if c.role == Character.ROLE_GENERAL:
				_add_attr(state, c, Character.ATTR_LOYALTY, loyalty)
		lines.append(Lang.t("Lealta' dei generali %+d") % loyalty)
	var commander := _present_character(state, ctx)
	var agent := state.agent(int(ctx.get("agente", 0)))
	var army := state.army(int(ctx.get("esercito", 0)))
	var stars := int(outcome.get("stelle", 0))
	if stars != 0:
		if army != null and army.is_fleet and not army.admiral.is_empty():
			army.admiral["stelle"] = clampi(int(army.admiral.get("stelle", 0)) + stars, 0, 10)
			lines.append(Lang.t("L'ammiraglio %s guadagna %d stelle") % [str(army.admiral.get("nome", "")), stars])
		elif commander != null:
			_add_attr(state, commander, Character.ATTR_COMMAND, stars)
			lines.append(Lang.t("%s guadagna %d stelle di comando") % [commander.full_name(), stars])
		elif agent != null:
			agent.valour = clampi(agent.valour + stars, 0, state.rules.agents.max_valour)
			lines.append(Lang.t("L'agente %s guadagna %d stelle") % [agent.name, stars])
	var life := int(outcome.get("vita", 0))
	if life != 0 and commander != null:
		commander.old_age += life
		lines.append(Lang.t("%s vivra' %d anni in piu'") % [commander.full_name(), life])
	if bool(outcome.get("muore", false)) and commander != null:
		if commander.role == Character.ROLE_GENERAL and not DynastyProcessor.is_invulnerable(state, commander):
			DynastyProcessor.kill(state, commander, state.year + 1, "luogo", false)
			lines.append(Lang.t("%s non e' piu' tornato") % commander.full_name())
		else:
			lines.append(Lang.t("%s e' tornato vivo per miracolo") % commander.full_name())
	var ships := int(outcome.get("navi_perse", 0))
	if ships > 0 and army != null and army.is_fleet:
		var men := _lose_ships(state, army, ships)
		if men >= 0:
			lines.append(Lang.t("Perse %d navi (%d uomini)") % [ships, men])
	var hurt := int(outcome.get("uomini_persi", 0))
	if hurt > 0 and army != null and not army.stacks.is_empty():
		EventProcessor._hurt_army(state, army, float(hurt) / 100.0)
		lines.append(Lang.t("L'esercito perde il %d%% degli uomini") % hurt)
	var order: Dictionary = outcome.get("ordine", {})
	if not order.is_empty() and not s.is_sea():
		var st := _st(state, s.id)
		st["ordine"] = {"punti": int(order.get("punti", 0)), "fino": state.year + maxi(1, int(order.get("anni", 1)))}
		lines.append(Lang.t("Lealta' della provincia %+d per %d anni") % [int(order.get("punti", 0)), maxi(1, int(order.get("anni", 1)))])
	var conv: Dictionary = outcome.get("conversione", {})
	if not conv.is_empty() and not s.is_sea():
		var p := state.province(s.region)
		if p != null:
			for r in conv:
				ReligionProcessor.shift(p, str(r), float(conv[r]))
			lines.append(Lang.t("La fede della provincia cambia"))
	if bool(outcome.get("fine_luogo", false)):
		_st(state, s.id)["fine"] = true
		lines.append(Lang.t("%s non esiste piu'") % s.label(state.year))
	return lines


static func _add_attr(state: GameState, c: Character, attr: String, delta: int) -> void:
	c.set_base_value(attr, clampi(c.base_value(attr) + delta, 0, state.rules.dynasty.max_attribute))


static func _present_character(state: GameState, ctx: Dictionary) -> Character:
	var cid := int(ctx.get("personaggio", 0))
	if cid > 0:
		var c := state.character(cid)
		if c != null and c.alive:
			return c
	var army := state.army(int(ctx.get("esercito", 0)))
	if army != null and not army.is_fleet:
		return state.commander_of(army.id)
	return null


## Stelle di chi e' presente: comandante, ammiraglio o agente (0 se nessuno).
static func _present_stars(state: GameState, ctx: Dictionary) -> int:
	var army := state.army(int(ctx.get("esercito", 0)))
	if army != null and army.is_fleet:
		return int(army.admiral.get("stelle", 0))
	var c := _present_character(state, ctx)
	if c != null:
		return c.stars(state.rules, state.campaign)
	var ag := state.agent(int(ctx.get("agente", 0)))
	return ag.valour if ag != null else 0


## Toglie fino a `count` navi alla flotta (le ultime, mai Ankalagon o simili): uomini persi, -1 se nessuna.
static func _lose_ships(state: GameState, fleet: Army, count: int) -> int:
	var men := 0
	var lost := 0
	for i in range(fleet.stacks.size() - 1, -1, -1):
		if lost >= count:
			break
		var st: UnitStack = fleet.stacks[i]
		if Combat.is_invulnerable(state.units, st):
			continue
		men += st.men
		fleet.stacks.remove_at(i)
		lost += 1
	if lost == 0:
		return -1
	if fleet.stacks.is_empty():
		state.remove_army(fleet)
	return men


# --- salvataggi ----------------------------------------------------------------------------------------------------------


static func save_data(state: GameState) -> Dictionary:
	var out := {}
	if not state.sites_state.is_empty():
		out["stato"] = state.sites_state.duplicate(true)
	if not state.site_choices.is_empty():
		out["scelte"] = state.site_choices.duplicate(true)
	out["prossima_scelta"] = state.next_site_choice_id
	if not state.sites_discovered.is_empty():
		out["scoperti"] = state.sites_discovered.duplicate(true)
	return out


static func load_data(state: GameState, data: Variant) -> void:
	state.sites_state = {}
	state.site_choices.clear()
	state.next_site_choice_id = 1
	state.sites_discovered = {}
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	var raw: Variant = d.get("stato", {})
	if typeof(raw) == TYPE_DICTIONARY:
		state.sites_state = _ints(raw)
	for c in d.get("scelte", []):
		if typeof(c) == TYPE_DICTIONARY:
			state.site_choices.append({"id": int(c.get("id", 0)), "luogo": str(c.get("luogo", "")), "evento": str(c.get("evento", "")),
				"fazione": str(c.get("fazione", "")), "anno": int(c.get("anno", 0)), "contesto": _ints(c.get("contesto", {}))})
	state.next_site_choice_id = maxi(1, int(d.get("prossima_scelta", 1)))
	var disc: Variant = d.get("scoperti", {})
	if typeof(disc) == TYPE_DICTIONARY:
		for k in disc:
			var list := PackedStringArray()
			for v in disc[k]:
				list.append(str(v))
			state.sites_discovered[str(k)] = list


## I numeri del JSON tornano float: quelli interi diventano int (anni, punti, id).
static func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if is_equal_approx(float(v), roundf(float(v))) else v
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[str(k)] = _ints(v[k])
			return out
		TYPE_ARRAY:
			var out: Array = []
			for item in v:
				out.append(_ints(item))
			return out
	return v


# --- scoperta sulla mappa (giocatore) -------------------------------------------------------------------------------------


## Segna come scoperti i luoghi delle regioni `seen` (regione -> true) per la fazione: un luogo si scopre andando sulla sua
## regione (vederla con la nebbia di guerra); i luoghi fantasma solo nell'anno in cui si manifestano. Vero se ne aggiunge.
static func discover_seen(state: GameState, faction_id: String, seen: Dictionary) -> bool:
	if state.rules == null or state.rules.sites.is_empty():
		return false
	var key := SimUtil.norm(faction_id)
	var list: PackedStringArray = state.sites_discovered.get(key, PackedStringArray())
	var added := false
	for s in state.rules.sites.sites:
		if list.has(s.id) or not LegendarySites.is_active(state, s) or not seen.has(s.region):
			continue
		if not LegendarySites.manifests(s, state.year):
			continue
		list.append(s.id)
		added = true
	state.sites_discovered[key] = list
	return added


static func is_discovered(state: GameState, faction_id: String, site_id: String) -> bool:
	var list: PackedStringArray = state.sites_discovered.get(SimUtil.norm(faction_id), PackedStringArray())
	return list.has(site_id)
