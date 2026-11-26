class_name ProvinceProcessor
extends RefCounted
## Province e lealta' (spec. fase 4 §4b). `TurnProcessor.end_year` chiama `process_year` dopo gli scontri e le
## regole annuali della dinastia, prima dell'economia. Come `DynastyProcessor`, nei mondi senza personaggi (dati di
## prova senza `SetStartLeader`) non succede nulla e non si estrae nessun numero casuale.
##
## Ordine fisso di ogni anno (province e fazioni in ordine di dichiarazione, personaggi in ordine di id; tutti i
## sorteggi passano da `state.rng`, uno per ogni probabilita' maggiore di zero e solo se l'effetto e' possibile):
##   1. lealta': cambi di proprietario, avvicinamento all'obiettivo, EV_LOYALTY_LOW
##   2. rivolte (un sorteggio per provincia sotto la soglia)  3. propagazione alle province confinanti
##   4. lealta' dei generali (nessun sorteggio)  5. guerre civili (un sorteggio per fazione con l'innesco)
##   6. riemersione delle fazioni estinte (un sorteggio per fazione con una provincia adatta).
##   7. insurrezioni lealiste delle fazioni estinte (ADR-114: un sorteggio per fazione nella finestra di anni, se c'e' un luogo).
## Prima del passo 1 (ADR-070, nessun sorteggio): le province prese dai ribelli lealisti passano alla fazione a cui sono
## fedeli (o la fanno riemergere se era estinta).
##
## Lealta' obiettivo di una provincia (catalogo "Province e lealta'", confidenza Media, parametri in province.cfg):
##   base + termine della tassa + guarnigione (+16 ogni 100 uomini del proprietario) + edifici (colonna "felicita'"
##   del file edifici, valore del livello costruito) - ribellione regionale - religione diversa dalla fazione
##   - distanza dal capo + terrore del governatore - occupazione (ADR-070: provincia tolta al padrone originario).
## Le province dei ribelli non hanno tassa, religione, distanza ne' governatore.
## Rivolta: sotto la soglia, probabilita' annua proporzionale ai punti mancanti (fase 5b: doppia se gli eretici superano
## `soglia_rivolta_eretica`; in quel caso i ribelli sono «eretici» e si aggiunge EV_HERETIC_REVOLT). Nasce un esercito ribelle (fazione
## `GameState.REBEL`, in guerra con tutti) nella provincia: da quel momento valgono le regole di guerra esistenti
## (battaglie, assedi, conquista) e la provincia, contesa, non produce reddito (`Economy.is_contested`).
## Guerra civile: i generali sleali, i loro eserciti e le province che governano passano ai ribelli; i generali
## escono dal gioco (PROVVISORIA, spec. 4b: la divisione completa con scelta del lato arriva piu' avanti).

const REBEL_PEASANTS := "contadini"
const REBEL_LOYALISTS := "lealisti"
const REBEL_BANDITS := "banditi"
const REBEL_HERETICS := "eretici"
const REBEL_MUSLIMS := "musulmani"
const REBEL_CATHOLICS := "cattolici"
const REBEL_ORTHODOX := "ortodossi"

## ADR-070, in `ProvinceState.counters`: anno in cui il proprietario attuale ha preso la provincia (assente = la possiede
## dall'inizio o dal salvataggio: nessuna penalita' di occupazione) e ultima fazione che la possedeva prima di lui.
const OWNER_YEAR_KEY := "anno_proprietario"
const PRIOR_OWNER_KEY := "proprietario_precedente"

## Contatore di pressione sulla lealta' di un generale e sconfitte gia' contate (in `Character.counters`).
const PRESSURE_KEY := "pressione_lealta"
const DEFEATS_SEEN_KEY := "sconfitte_viste"


# --- passo annuale -------------------------------------------------------------------------------


static func process_year(state: GameState) -> void:
	if state.characters.is_empty():
		return
	var new_year := state.year + 1
	var distances := _distance_tables(state)
	_loyalist_handover(state, new_year)
	_update_loyalty(state, distances)
	var revolted := _rebellions(state)
	_propagation(state, revolted)
	_general_loyalty(state)
	_civil_wars(state, new_year)
	_reemergence(state, new_year)
	_loyalist_uprisings(state, new_year)
	_destroy_empty_factions(state, new_year)


## Una fazione che con la guerra civile o le rivolte resta senza province ne' eserciti e' distrutta come dopo una
## conquista (EV_FACTION_DESTROYED); i suoi personaggi escono di scena subito, come fa la dinastia a inizio anno.
static func _destroy_empty_factions(state: GameState, new_year: int) -> void:
	WarProcessor.destroyed_factions(state)
	for c in state.characters:
		if not c.alive:
			continue
		var f := state.faction(c.faction)
		if f == null or not f.alive:
			DynastyProcessor.kill(state, c, new_year, "fazione_distrutta", false)


## Imposta la lealta' di ogni provincia al suo obiettivo (partita nuova, salvataggi vecchi). Nessun sorteggio.
static func init_loyalty(state: GameState) -> void:
	var distances := _distance_tables(state)
	for p in state.provinces:
		var terms := loyalty_terms(state, p, distances)
		p.loyalty = int(terms["obiettivo"])
		p.loyalty_owner = p.owner
		terms["corrente"] = p.loyalty
		p.last_loyalty = terms


# --- 1. lealta' -------------------------------------------------------------------------------------


## Dettaglio dell'obiettivo di lealta' di una provincia (senza modificare lo stato): "base", "tassa", "guarnigione",
## "edifici", "ribellione_regionale" (<= 0), "religione" (<= 0, fase 5b: proporzionale alla quota della religione del
## proprietario), "distanza" (<= 0), "terrore", "spie" (fase 5a), "inquisitori" (<= 0, fase 5b), "scomunica" (<= 0, fase 5c), "somma" (senza limiti),
## "obiettivo" (somma limitata a 0..massimo), piu' "uomini" (guarnigione) e "passi" (distanza dal capo).
## `distances` e' la tabella annuale (fazione -> regione -> passi); vuota = si calcola qui.
static func loyalty_terms(state: GameState, p: ProvinceState, distances: Dictionary = {}) -> Dictionary:
	var pr := state.rules.province
	var is_rebel := p.owner == GameState.REBEL
	var men := garrison_men(state, p)
	var garrison := mini(floori(float(men) * float(pr.garrison_per_100) / 100.0), pr.garrison_max)
	var tax := 0
	var religion := 0
	var distance := 0
	var terror := 0
	var steps := 0
	if not is_rebel:
		tax = pr.tax_term(p.tax_level)
		religion = ReligionProcessor.loyalty_term(state, p)
		steps = _distance_steps(state, p, distances)
		distance = -steps * pr.distance_step
		var governor := state.governor_of(p.id)
		if governor != null and governor.faction == p.owner:
			terror = governor.effective(Character.ATTR_DREAD, state.rules, state.campaign) * pr.dread_per_point
	var buildings := _buildings_term(state, p)
	var regional := -pr.regional_penalty(p.id)
	var spies := spies_term(state, p)
	var inquisitors := ReligionProcessor.inquisitor_term(state, p)
	var excommunication := PapacyProcessor.loyalty_term(state, p)
	var occupation := -occupation_term(state, p)
	var traits := 0 if is_rebel else state.rules.traits.loyalty_bonus(p.owner)   # ADR-089: tratti della fazione
	var total := pr.base + tax + garrison + buildings + regional + religion + distance + terror + spies + inquisitors + excommunication + occupation + traits
	return {
		"base": pr.base,
		"tassa": tax,
		"guarnigione": garrison,
		"edifici": buildings,
		"ribellione_regionale": regional,
		"religione": religion,
		"distanza": distance,
		"terrore": terror,
		"spie": spies,
		"inquisitori": inquisitors,
		"scomunica": excommunication,
		"occupazione": occupation,
		"fazione": traits,
		"somma": total,
		"obiettivo": clampi(total, 0, pr.max_loyalty),
		"uomini": men,
		"passi": steps,
	}


## Proprietario della provincia all'inizio della campagna (dallo startpos; "" se non si conosce).
static func origin_owner(state: GameState, p: ProvinceState) -> String:
	if state.campaign == null:
		return ""
	var region := state.campaign.region(p.id)
	if region == null:
		return ""
	return region.owner.strip_edges().to_upper()


## Penalita' di occupazione (ADR-070, PROVVISORIA, [occupazione] di province.cfg), in punti da togliere (>= 0): solo se il
## proprietario ha preso la provincia durante la partita e non e' quello originario (le province ribelli all'inizio non
## contano). `penalita` - `calo_annuo` x anni di possesso (minimo 0), piu' `padrone_vivo` se la fazione originaria esiste.
static func occupation_term(state: GameState, p: ProvinceState) -> int:
	if p.owner == GameState.REBEL or not p.counters.has(OWNER_YEAR_KEY):
		return 0
	var origin := origin_owner(state, p)
	if origin == "" or origin == GameState.REBEL or origin == p.owner:
		return 0
	var pr := state.rules.province
	var years := maxi(0, state.year - int(p.counters[OWNER_YEAR_KEY]))
	var points := maxi(0, roundi(float(pr.occupation_base) - pr.occupation_decay * float(years)))
	var f := state.faction(origin)
	if f != null and f.alive:
		points += pr.occupation_legit
	return points


## Fazione a cui sarebbero fedeli i ribelli della provincia (ADR-070): il proprietario precedente, altrimenti quello
## originario, purche' diverso dal proprietario attuale e vivo, oppure estinto ma in grado di riemergere (non il
## giocatore, con una dinastia). "" = ribelli comuni (anche con `lealisti` spento).
static func loyalist_faction(state: GameState, p: ProvinceState) -> String:
	if not state.rules.province.loyalists or p.owner == GameState.REBEL:
		return ""
	for candidate in [str(p.counters.get(PRIOR_OWNER_KEY, "")), origin_owner(state, p)]:
		if candidate == "" or candidate == GameState.REBEL or candidate == p.owner:
			continue
		var f := state.faction(candidate)
		if f == null:
			continue
		if f.id == GameState.PAPAL and not f.alive:
			continue   # il Papato distrutto ricompare con la sua regola (ADR-072), non con le rivolte comuni
		if f.alive or (not f.is_player and state.has_dynasty(f.id)):
			return candidate
	return ""


## Termine delle spie (fase 5a, PROVVISORIA, parametri in agenti.cfg): +`bonus_lealta_spia` se il proprietario ha una spia
## nella provincia (una sola conta), -`malus_lealta_spia` se c'e' una spia di una fazione non alleata del proprietario
## (anche qui basta una). Le province dei ribelli non hanno il termine.
static func spies_term(state: GameState, p: ProvinceState) -> int:
	if p.owner == GameState.REBEL or state.agents.is_empty():
		return 0
	var ar := state.rules.agents
	var own := false
	var foreign := false
	for a in state.agents:
		if a.type_name != AgentState.SPY or a.region != p.id:
			continue
		if a.faction == p.owner:
			own = true
		elif not state.is_allied(a.faction, p.owner):
			foreign = true
	var term := 0
	if own:
		term += ar.spy_loyalty_bonus
	if foreign:
		term -= ar.spy_loyalty_malus
	# malcontento fomentato da una spia (missione del 18/11/2026), finche' dura
	if int(p.counters.get("malcontento_fino", 0)) >= state.year:
		term -= int(p.counters.get("malcontento", 0))
	return term


## Uomini degli eserciti di terra del proprietario nella provincia (anche nel castello).
static func garrison_men(state: GameState, p: ProvinceState) -> int:
	var total := 0
	for a in state.armies:
		if a.region == p.id and a.faction == p.owner and not a.is_fleet:
			total += a.men_total()
	return total


## Vero se la cultura della regione ha una religione diversa da quella della fazione proprietaria.
static func religion_differs(state: GameState, p: ProvinceState) -> bool:
	var region := state.campaign.region(p.id)
	var faction := state.campaign.faction(p.owner)
	if region == null or faction == null:
		return false
	var region_religion := state.rules.province.religion_of_culture(region.culture)
	var faction_religion := faction.religion.strip_edges().to_upper()
	if region_religion == "" or faction_religion == "":
		return false
	# il Culto Imperiale degli Auror nasce dal cattolicesimo: le terre di cultura cattolica non gli sono estranee
	return GameCommands.religion_base(GameCommands.religion_key(region_religion)) != GameCommands.religion_base(GameCommands.religion_key(faction_religion))


## Somma dei punti di felicita' (colonna 23 del file edifici) del livello costruito di ogni famiglia della provincia.
static func _buildings_term(state: GameState, p: ProvinceState) -> int:
	var total := 0
	for family_id in p.buildings:
		var family: BuildingType = state.buildings.get_family(str(family_id))
		if family == null:
			continue
		var level: BuildingType.Level = family.get_level(int(p.buildings[family_id]))
		if level != null:
			total += level.happiness
	return total


static func _distance_steps(state: GameState, p: ProvinceState, distances: Dictionary) -> int:
	var pr := state.rules.province
	var leader := state.leader_of(p.owner)
	if leader == null:
		return 0
	var table: Dictionary
	if distances.has(p.owner):
		table = distances[p.owner]
	else:
		table = _bfs(state.campaign, state.character_region(leader))
	return mini(int(table.get(p.id, pr.distance_max)), pr.distance_max)


## Passi sulla mappa di terra dalla regione del capo di ogni fazione viva (fazione -> regione -> passi).
static func _distance_tables(state: GameState) -> Dictionary:
	var out := {}
	for f in state.factions:
		if not f.alive or f.id == GameState.REBEL:
			continue
		var leader := state.leader_of(f.id)
		if leader == null:
			continue
		var region_id := state.character_region(leader)
		if region_id != "":
			out[f.id] = _bfs(state.campaign, region_id)
	return out


## Ricerca in ampiezza sulle regioni di terra a partire da `start` (che puo' essere di mare: passo 0).
static func _bfs(campaign: CampaignData, start: String) -> Dictionary:
	var dist := {start: 0}
	var queue: Array[String] = [start]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		var region := campaign.region(current)
		if region == null:
			continue
		for n in region.neighbours:
			var key := SimUtil.norm(n)
			if dist.has(key):
				continue
			var other := campaign.region(key)
			if other == null or other.is_sea:
				continue
			dist[key] = int(dist[current]) + 1
			queue.append(key)
	return dist


## Un anno di avvicinamento all'obiettivo: si colma la frazione `deriva` del divario, almeno un punto, senza superarlo.
static func approach(current: int, target: int, drift: float) -> int:
	var gap := target - current
	if gap == 0:
		return current
	var step := mini(maxi(1, roundi(absf(float(gap)) * drift)), absi(gap))
	if gap > 0:
		return current + step
	return current - step


static func _update_loyalty(state: GameState, distances: Dictionary) -> void:
	var pr := state.rules.province
	for p in state.provinces:
		_handle_owner_change(state, p)
		var terms := loyalty_terms(state, p, distances)
		var target := int(terms["obiettivo"])
		p.loyalty = clampi(approach(p.loyalty, target, pr.drift), 0, pr.max_loyalty)
		terms["corrente"] = p.loyalty
		p.last_loyalty = terms
		if p.owner == GameState.REBEL:
			p.counters["anni_sotto_soglia"] = 0
			continue
		if p.loyalty >= pr.revolt_threshold:
			p.counters["anni_sotto_soglia"] = 0
			continue
		var years := int(p.counters.get("anni_sotto_soglia", 0)) + 1
		p.counters["anni_sotto_soglia"] = years
		if years == 1:
			state.add_event(GameState.EV_LOYALTY_LOW, {
				"fazione": p.owner,
				"regione": p.id,
				"provincia": p.id,
				"lealta": p.loyalty,
				"obiettivo": target,
				"soglia": pr.revolt_threshold,
				"testo": Lang.t("La lealta' di %s (%s) scende al %d%%, sotto la soglia di rivolta (%d%%).") % [
					WarProcessor.region_label(state, p.id), SimUtil.faction_label(p.owner), p.loyalty, pr.revolt_threshold],
			})


## Un cambio di proprietario avvenuto durante l'anno (conquista, estinzione, rivolta): ai ribelli si ricorda l'ultimo
## proprietario vero; a una fazione la lealta' parte al massimo da `lealta_conquista`.
static func _handle_owner_change(state: GameState, p: ProvinceState) -> void:
	if p.owner == p.loyalty_owner:
		return
	var previous := p.loyalty_owner
	p.loyalty_owner = p.owner
	p.counters["anni_sotto_soglia"] = 0
	if previous != "" and previous != GameState.REBEL and previous != p.owner:
		p.counters[PRIOR_OWNER_KEY] = previous
	if str(p.counters.get(PRIOR_OWNER_KEY, "")) == p.owner:
		p.counters.erase(PRIOR_OWNER_KEY)
	if p.owner == GameState.REBEL:
		p.counters.erase(OWNER_YEAR_KEY)
		if previous != "" and previous != GameState.REBEL:
			p.former_owner = previous
		return
	p.former_owner = ""
	p.counters[OWNER_YEAR_KEY] = state.year
	p.loyalty = mini(p.loyalty, state.rules.province.conquest_loyalty)


# --- 2-3. rivolte e propagazione ------------------------------------------------------------------


## Truppa dei ribelli: la fanteria piu' economica tra quelle disponibili alla fazione dei ribelli (e alla cultura della
## regione); in mancanza, la fanteria piu' economica della tabella. A parita' di costo vince la prima del file. Null se
## la tabella non ha fanteria.
static func rebel_unit(state: GameState, region: CampaignData.Region) -> UnitType:
	if state.units == null or region == null:
		return null
	var culture_key := region.culture.strip_edges().to_upper().trim_suffix("_CULTURE")
	var best: UnitType = null
	var fallback: UnitType = null
	for u in state.units.units:
		if u.type_name != UnitType.INFANTRY or u.men <= 0:
			continue
		if not u.all_factions and u.factions.is_empty():
			continue    # non reclutabile da nessuno (nelle tabelle di prova e' un segnaposto)
		if fallback == null or u.cost < fallback.cost:
			fallback = u
		if not u.factions.has(GameState.REBEL):
			continue
		if not u.cultures.is_empty() and not u.cultures.has(culture_key):
			continue
		if best == null or u.cost < best.cost:
			best = u
	if best != null:
		return best
	return fallback


## Truppe dei ribelli lealisti (ADR-070, PROVVISORIA; manuale p23: «abbastanza versati nel combattimento, una buona
## combinazione di truppe»): per fanteria, tiratori (unita' con proiettili) e cavalleria la piu' economica tra quelle che
## la fazione `faction_id` puo' avere nel periodo, nella sua cultura e nella regione; per la fanteria la seconda piu'
## economica, se c'e' (la prima sono di solito i contadini). Niente ordini militari, crociati, artiglieria o navi. In
## ordine: fanteria, tiratori, cavalleria; vuoto se nessuna e' adatta (allora si usa la truppa dei ribelli).
static func loyalist_units(state: GameState, faction_id: String, region: CampaignData.Region) -> Array[UnitType]:
	var out: Array[UnitType] = []
	if state.units == null or region == null:
		return out
	var culture := region.culture
	var cf := state.campaign.faction(faction_id)
	if cf != null and cf.culture != "":
		culture = cf.culture
	var culture_key := GameCommands.culture_key(culture)
	var order_building := state.rules.papacy.order_building
	var groups := {"fanteria": [], "tiratori": [], "cavalleria": []}
	for u in state.units.military():
		if u.men <= 0 or not (u.is_infantry() or u.is_cavalry()):
			continue
		if not u.allows_faction(faction_id) or not u.allows_culture(culture_key) or not u.available_in_period(state.era):
			continue
		if not u.allows_region(region.id) or u.required_tokens().has(order_building):
			continue
		if not HistoricalLimits.unit_allowed(state, faction_id, u, region.id):
			continue   # ADR-114: niente armi da fuoco prima della polvere da sparo, niente cavalli nelle Americhe prima degli europei
		var key := "fanteria"
		if u.is_cavalry():
			key = "cavalleria"
		elif u.projectile != "" and u.projectile.to_upper() != "NONE":
			key = "tiratori"
		(groups[key] as Array).append(u)
	for key in ["fanteria", "tiratori", "cavalleria"]:
		var list: Array = groups[key]
		if list.is_empty():
			continue
		list.sort_custom(func(a: UnitType, b: UnitType) -> bool: return a.cost < b.cost or (a.cost == b.cost and a.index < b.index))
		out.append(list[1] if key == "fanteria" and list.size() > 1 else list[0])
	return out


## Vero se nella provincia puo' scoppiare una rivolta: di una fazione viva, non gia' contesa o in rivolta, con una
## truppa ribelle disponibile.
## Probabilita' annua che la provincia si ribelli con la lealta' `loyalty` (-1 = quella di adesso): quella delle regole sotto
## la soglia, doppia con gli eretici oltre la soglia (fase 5b), zero se la provincia non puo' ribellarsi (`can_rebel`). E' il
## valore che usa il sorteggio di fine anno; l'interfaccia lo mostra con la lealta' prevista a fine anno.
static func revolt_risk(state: GameState, p: ProvinceState, loyalty: int = -1) -> float:
	var chance := state.rules.province.revolt_chance(p.loyalty if loyalty < 0 else loyalty)
	if chance > 0.0 and ReligionProcessor.heretic_revolt(state, p):
		chance = minf(1.0, chance * state.rules.religion.heretic_revolt_factor)    # fase 5b: rivolta eretica
	if chance <= 0.0 or not can_rebel(state, p):
		return 0.0
	return chance


static func can_rebel(state: GameState, p: ProvinceState) -> bool:
	if p.owner == GameState.REBEL:
		return false
	var f := state.faction(p.owner)
	if f == null or not f.alive:
		return false
	if Economy.is_contested(state, p):
		return false
	return rebel_unit(state, state.campaign.region(p.id)) != null


## Etichetta del tipo di ribelli (manuale p24): religione della regione se diversa da quella del proprietario
## (musulmani, cattolici, ortodossi; eretici per gli altri culti), banditi se la lealta' e' molto bassa, altrimenti contadini.
## Fase 5b: con piu' eretici della soglia (`ReligionProcessor.heretic_revolt`) i ribelli sono sempre «eretici».
static func rebel_type(state: GameState, p: ProvinceState) -> String:
	var pr := state.rules.province
	if ReligionProcessor.heretic_revolt(state, p):
		return REBEL_HERETICS
	if loyalist_faction(state, p) != "":
		return REBEL_LOYALISTS
	if religion_differs(state, p):
		var region := state.campaign.region(p.id)
		var region_religion := pr.religion_of_culture(region.culture)
		if region_religion == "REL_ISLAMIC":
			return REBEL_MUSLIMS
		if region_religion == "REL_CATHOLIC":
			return REBEL_CATHOLICS
		if region_religion == "REL_ORTHODOX":
			return REBEL_ORTHODOX
		return REBEL_HERETICS
	if p.loyalty < pr.bandit_threshold:
		return REBEL_BANDITS
	return REBEL_PEASANTS


static func _rebellions(state: GameState) -> Array[String]:
	var revolted: Array[String] = []
	var pr := state.rules.province
	for p in state.provinces:
		if p.owner == GameState.REBEL:
			continue
		var chance := revolt_risk(state, p)
		if chance <= 0.0:
			continue
		if state.rng.randf() >= chance:
			continue
		if spawn_revolt(state, p, ""):
			revolted.append(p.id)
	return revolted


static func _propagation(state: GameState, revolted: Array[String]) -> void:
	var pr := state.rules.province
	if pr.spread_chance <= 0.0:
		return
	for origin in revolted:
		var region := state.campaign.region(origin)
		if region == null:
			continue
		for n in region.neighbours:
			var q := state.province(n)
			if q == null or q.owner == GameState.REBEL or q.loyalty >= pr.spread_threshold:
				continue
			if not can_rebel(state, q):
				continue
			if state.rng.randf() >= pr.spread_chance:
				continue
			spawn_revolt(state, q, origin)


## Fa nascere l'esercito ribelle nella provincia (uomini proporzionati alla rendita della regione, in pile della
## truppa ribelle) e registra EV_REBELLION, o EV_REBELLION_SPREAD se `origin` e' la provincia da cui la rivolta si e'
## estesa. Nessun sorteggio. Falso se non c'e' una truppa ribelle.
static func spawn_revolt(state: GameState, p: ProvinceState, origin: String) -> bool:
	var pr := state.rules.province
	var region := state.campaign.region(p.id)
	var unit := rebel_unit(state, region)
	if unit == null:
		return false
	var kind := rebel_type(state, p)
	var loyal_to := loyalist_faction(state, p) if kind == REBEL_LOYALISTS else ""
	var mix: Array[UnitType] = [unit]
	if loyal_to != "":
		var picked := loyalist_units(state, loyal_to, region)
		if not picked.is_empty():
			mix = picked
	var avg_men := 0.0
	for u in mix:
		avg_men += float(u.men)
	avg_men /= float(mix.size())
	var wanted := clampf(float(region.income) * pr.rebels_per_income, float(pr.rebels_min), float(pr.rebels_max))
	var count := clampi(roundi(wanted / avg_men), 1, maxi(1, state.rules.max_stacks))
	var army := state.create_army(GameState.REBEL, p.id, false)
	army.loyal_to = loyal_to
	for i in count:
		var u: UnitType = mix[i % mix.size()]
		army.stacks.append(state.new_stack(GameState.REBEL, u.id, u.men))
	var men := army.men_total()
	p.counters["rivolte"] = int(p.counters.get("rivolte", 0)) + 1
	var kind_text := Lang.t(kind)
	if loyal_to != "":
		kind_text = Lang.t("lealisti di %s") % SimUtil.faction_label(loyal_to)
	var place := WarProcessor.region_label(state, p.id)
	var data := {
		"fazione": p.owner,
		"regione": p.id,
		"provincia": p.id,
		"lealta": p.loyalty,
		"tipo_ribelli": kind,
		"esercito": army.id,
		"uomini": men,
	}
	if army.loyal_to != "":
		data["lealisti_di"] = army.loyal_to
	if origin == "":
		data["testo"] = Lang.t("Rivolta a %s (%s, lealta' %d%%): %d ribelli (%s).") % [place, SimUtil.faction_label(p.owner), p.loyalty, men, kind_text]
		state.add_event(GameState.EV_REBELLION, data)
	else:
		data["origine"] = origin
		data["testo"] = Lang.t("La rivolta di %s si estende a %s (%s, lealta' %d%%): %d ribelli (%s).") % [
			WarProcessor.region_label(state, origin), place, SimUtil.faction_label(p.owner), p.loyalty, men, kind_text]
		state.add_event(GameState.EV_REBELLION_SPREAD, data)
	if ReligionProcessor.heretic_revolt(state, p):
		state.add_event(GameState.EV_HERETIC_REVOLT, {
			"fazione": p.owner,
			"regione": p.id,
			"provincia": p.id,
			"eretici": p.religion_pct(ProvinceState.HERETIC),
			"esercito": army.id,
			"uomini": men,
			"testo": Lang.t("Gli eretici di %s (%s, %s%% della popolazione) si ribellano: %d ribelli.") % [
				place, SimUtil.faction_label(p.owner), str(p.religion_pct(ProvinceState.HERETIC)), men],
		})
	return true


# --- 4. lealta' dei generali -----------------------------------------------------------------------


## Pressione annua sulla lealta' di generali e principi (PROVVISORIA): + se governano una provincia, - se il reame ha
## piu' della meta' delle province a tassa alta, - per ogni sconfitta dell'anno, + o - per l'influenza del capo alta o
## bassa. Ogni `pressione_per_punto` punti la lealta' (0-10) cambia di uno. I valori fissi (Auror) non cambiano.
static func _general_loyalty(state: GameState) -> void:
	var pr := state.rules.province
	var d := state.rules.dynasty
	var high_tax := _high_tax_factions(state)
	for c in state.characters:
		if not c.alive or (c.role != Character.ROLE_GENERAL and c.role != Character.ROLE_PRINCE):
			continue
		var f := state.faction(c.faction)
		if f == null or not f.alive or f.id == GameState.REBEL:
			continue
		if d.fixed_value(c.faction, Character.ATTR_LOYALTY) >= 0:
			continue
		var pressure := int(c.counters.get(PRESSURE_KEY, 0))
		if c.title != "":
			pressure += pr.general_title
		if bool(high_tax.get(c.faction, false)):
			pressure -= pr.general_tax
		var defeats := int(c.counters.get("sconfitte", 0))
		var seen := int(c.counters.get(DEFEATS_SEEN_KEY, 0))
		if defeats > seen:
			pressure -= pr.general_defeat * (defeats - seen)
		c.counters[DEFEATS_SEEN_KEY] = defeats
		var leader := state.leader_of(c.faction)
		if leader != null:
			var influence := leader.effective(Character.ATTR_INFLUENCE, state.rules, state.campaign)
			if influence >= pr.influence_high:
				pressure += pr.general_influence
			elif influence <= pr.influence_low:
				pressure -= pr.general_influence
		while pressure >= pr.general_step:
			pressure -= pr.general_step
			if c.loyalty < d.max_attribute:
				c.loyalty += 1
			else:
				pressure = 0
		while pressure <= -pr.general_step:
			pressure += pr.general_step
			if c.loyalty > 0:
				c.loyalty -= 1
			else:
				pressure = 0
		c.counters[PRESSURE_KEY] = pressure


## Fazioni vive con piu' di `quota_province_tassa_alta` delle province a tassa alta (come la catena Dread).
static func _high_tax_factions(state: GameState) -> Dictionary:
	var d := state.rules.dynasty
	var out := {}
	for f in state.factions:
		if not f.alive or f.id == GameState.REBEL:
			continue
		var owned := state.provinces_of(f.id)
		if owned.is_empty():
			continue
		var high := 0
		for p in owned:
			if p.tax_level >= d.high_tax_level:
				high += 1
		out[f.id] = float(high) / float(owned.size()) > d.high_tax_share
	return out


# --- 5. guerra civile -------------------------------------------------------------------------------


## Innesco della guerra civile per una fazione: Dictionary con "motivo" ("" = nessun innesco, "promotore" o
## "quota_sleali"), "sleali" (Array di Character vivi con lealta' efficace <= `lealta_sleale`, generali e principi
## maggiorenni, in ordine di id) e "promotore" (Character o null). Il promotore e' il primo sleale con comando
## >= `comando_promotore` che si trova in una regione diversa da quella del capo; la quota e' di almeno `sleali_min`
## generali e `quota_sleali` di tutti. Nessun sorteggio.
static func civil_war_trigger(state: GameState, faction_id: String, at_year: int) -> Dictionary:
	var out := {"motivo": "", "sleali": [], "promotore": null}
	var pr := state.rules.province
	var leader := state.leader_of(faction_id)
	if leader == null:
		return out
	var eligible := 0
	var disloyal: Array = []
	for c in state.characters:
		if not c.alive or c.faction != faction_id:
			continue
		if c.role != Character.ROLE_GENERAL and c.role != Character.ROLE_PRINCE:
			continue
		if not c.can_command(state.rules.dynasty, at_year):
			continue
		eligible += 1
		if c.effective(Character.ATTR_LOYALTY, state.rules, state.campaign) <= pr.disloyal_loyalty:
			disloyal.append(c)
	if disloyal.is_empty():
		return out
	out["sleali"] = disloyal
	var leader_region := state.character_region(leader)
	for item in disloyal:
		var g: Character = item
		if g.stars(state.rules, state.campaign) >= pr.promoter_command and state.character_region(g) != leader_region:
			out["promotore"] = g
			out["motivo"] = "promotore"
			return out
	if disloyal.size() >= pr.civil_min and float(disloyal.size()) >= pr.civil_share * float(eligible):
		out["motivo"] = "quota_sleali"
	return out


static func _civil_wars(state: GameState, new_year: int) -> void:
	var pr := state.rules.province
	if pr.civil_chance <= 0.0:
		return
	for f in state.factions:
		if not f.alive or f.id == GameState.REBEL:
			continue
		var info := civil_war_trigger(state, f.id, new_year)
		if str(info["motivo"]) == "":
			continue
		var rebels: Array = info["sleali"]
		if not _has_assets(state, f.id, rebels):
			continue
		if state.rng.randf() >= pr.civil_chance:
			continue
		_split_faction(state, f, info, new_year)


## Vero se almeno uno dei generali sleali ha un esercito o governa una provincia della fazione (altrimenti la guerra
## civile non cambierebbe nulla).
static func _has_assets(state: GameState, faction_id: String, rebels: Array) -> bool:
	for item in rebels:
		var g: Character = item
		if g.army > 0:
			var a := state.army(g.army)
			if a != null and a.faction == faction_id:
				return true
		if g.title != "":
			var p := state.province(g.title)
			if p != null and p.owner == faction_id:
				return true
	return false


## La guerra civile (PROVVISORIA): gli eserciti dei generali sleali e le province che governano passano ai ribelli,
## i generali escono dal gioco (causa "guerra_civile"). Gli uomini non cambiano: gli eserciti cambiano solo fazione.
static func _split_faction(state: GameState, f: FactionState, info: Dictionary, new_year: int) -> void:
	var rebels: Array = info["sleali"]
	var promoter_value: Variant = info["promotore"]
	var general_ids: Array = []
	var names := PackedStringArray()
	var army_ids: Array = []
	var province_ids: Array = []
	var men := 0
	var first_region := ""
	for item in rebels:
		var g: Character = item
		general_ids.append(g.id)
		names.append(g.full_name())
		if first_region == "":
			first_region = state.character_region(g)
		if g.army > 0:
			var a := state.army(g.army)
			if a != null and a.faction == f.id:
				a.faction = GameState.REBEL
				a.in_castle = false
				a.path = PackedStringArray()
				a.sea_route = PackedStringArray()
				a.assault_ordered = false
				army_ids.append(a.id)
				men += a.men_total()
		if g.title != "":
			var p := state.province(g.title)
			if p != null and p.owner == f.id:
				_make_rebel(state, p, f.id)
				province_ids.append(p.id)
			g.title = ""
		DynastyProcessor.kill(state, g, new_year, "guerra_civile", false)
		g.army = 0
	_fix_castle_flags(state)
	WarProcessor.refresh_sieges(state)
	var promoter_id := 0
	var region_id := first_region
	if promoter_value != null:
		var promoter: Character = promoter_value
		promoter_id = promoter.id
		region_id = promoter.region
	state.add_event(GameState.EV_CIVIL_WAR, {
		"fazione": f.id,
		"regione": region_id,
		"motivo": str(info["motivo"]),
		"tipo_ribelli": REBEL_LOYALISTS,
		"promotore": promoter_id,
		"generali": general_ids,
		"eserciti": army_ids,
		"province": province_ids,
		"uomini": men,
		"testo": Lang.t("Guerra civile in %s: %d generali sleali (%s) passano ai ribelli con %d eserciti e %d province.") % [
			SimUtil.faction_label(f.id), general_ids.size(), ", ".join(names), army_ids.size(), province_ids.size()],
	})


## Versione pubblica di `_make_rebel` per chi sta fuori dal processore (fase 6a: scioglimento dell'Orda d'Oro).
static func make_rebel(state: GameState, p: ProvinceState, previous_owner: String) -> void:
	_make_rebel(state, p, previous_owner)


## Versione pubblica di `_destroy_empty_factions` (fase 6a: disastri che lasciano una fazione senza province ne' eserciti).
static func destroy_empty_factions(state: GameState, new_year: int) -> void:
	_destroy_empty_factions(state, new_year)


## La provincia passa ai ribelli: code svuotate, tassa normale, la lealta' resta com'e'.
static func _make_rebel(state: GameState, p: ProvinceState, previous_owner: String) -> void:
	p.owner = GameState.REBEL
	p.loyalty_owner = GameState.REBEL
	p.former_owner = previous_owner
	p.building_queue.clear()
	p.unit_queue.clear()
	p.tax_level = state.rules.default_tax
	p.counters["anni_sotto_soglia"] = 0


## Un esercito di terra non puo' stare nel castello di una provincia che non e' del suo proprietario.
static func _fix_castle_flags(state: GameState) -> void:
	for a in state.armies:
		if not a.in_castle:
			continue
		var p := state.province(a.region)
		if a.is_fleet or p == null or p.owner != a.faction:
			a.in_castle = false


# --- 6. riemersione ----------------------------------------------------------------------------------


## Una fazione estinta (non del giocatore, non estinta quest'anno) puo' riemergere in una provincia ribelle che
## possedeva con lealta' sotto la soglia: la provincia torna sua con un capo nuovo (`CharacterFactory.make_new_leader`)
## e un esercito (i ribelli presenti, altrimenti `pile` pile della truppa ribelle). Un sorteggio per fazione adatta.
static func _reemergence(state: GameState, new_year: int) -> void:
	var pr := state.rules.province
	if pr.reemerge_chance <= 0.0:
		return
	var fresh := _fresh_extinctions(state)
	for f in state.factions:
		if f.alive or f.id == GameState.REBEL or f.id == GameState.PAPAL or f.is_player or fresh.has(f.id):
			continue   # il Papato ha la sua riemersione (PapacyProcessor, ADR-072)
		if not state.has_dynasty(f.id):
			continue
		var site := reemergence_site(state, f.id)
		if site == null:
			continue
		if state.rng.randf() >= pr.reemerge_chance:
			continue
		_reemerge(state, f, site, new_year)


## Prima provincia ribelle (nell'ordine delle province) con lealta' sotto la soglia di riemersione che la fazione
## possedeva all'inizio della campagna (ADR-070, le terre d'origine vengono prima) o prima che passasse ai ribelli;
## null se non ce n'e'.
static func reemergence_site(state: GameState, faction_id: String) -> ProvinceState:
	var threshold := state.rules.province.reemerge_threshold
	for p in state.provinces:
		if p.owner == GameState.REBEL and p.loyalty < threshold and origin_owner(state, p) == faction_id:
			return p
	for p in state.provinces:
		if p.owner == GameState.REBEL and p.former_owner == faction_id and p.loyalty < threshold:
			return p
	return null


## Fazioni estinte o distrutte durante questo fine anno.
static func _fresh_extinctions(state: GameState) -> Dictionary:
	var out := {}
	for e in state.events:
		var kind := str(e.get("tipo", ""))
		if kind == GameState.EV_FACTION_EXTINCT or kind == GameState.EV_FACTION_DESTROYED:
			out[str(e.get("fazione", ""))] = true
	return out


static func _reemerge(state: GameState, f: FactionState, site: ProvinceState, new_year: int) -> void:
	var pr := state.rules.province
	f.alive = true
	f.treasury = maxi(f.treasury, pr.reemerge_treasury)
	site.owner = f.id
	site.loyalty_owner = f.id
	site.former_owner = ""
	site.building_queue.clear()
	site.unit_queue.clear()
	site.tax_level = state.rules.default_tax
	site.counters["anni_sotto_soglia"] = 0
	var leader := CharacterFactory.make_new_leader(state, f.id, site.id, new_year, state.rng)
	var army_ids: Array = []
	var created := 0
	for a in state.armies:
		if a.faction == GameState.REBEL and a.region == site.id and not a.is_fleet and not a.stacks.is_empty():
			a.faction = f.id
			a.loyal_to = ""
			army_ids.append(a.id)
	if army_ids.is_empty():
		var unit := rebel_unit(state, state.campaign.region(site.id))
		if unit != null:
			var army := state.create_army(f.id, site.id, false)
			for i in pr.reemerge_stacks:
				army.stacks.append(state.new_stack(f.id, unit.id, unit.men))
			created = army.men_total()
			army_ids.append(army.id)
	_fix_castle_flags(state)
	WarProcessor.refresh_sieges(state)
	state.add_event(GameState.EV_FACTION_REEMERGED, {
		"fazione": f.id,
		"regione": site.id,
		"provincia": site.id,
		"capo": leader.id,
		"nome_capo": leader.full_name(),
		"eserciti": army_ids,
		"uomini": created,
		"testo": Lang.t("%s riemerge a %s con %s e %d eserciti.") % [
			SimUtil.faction_label(f.id), WarProcessor.region_label(state, site.id), leader.full_name(), army_ids.size()],
	})


# --- 7. insurrezioni lealiste (ADR-114) -----------------------------------------------------------


## Le fazioni estinte tornano a farsi vedere (richiesta di Federico del 21/11/2026; regola del Papato, ADR-072, estesa a
## tutte): per ogni fazione estinta, non del giocatore e con una dinastia, gli anni da estinta crescono di uno; nella
## finestra di `[insurrezioni]` (`ProvinceRules.uprising_chance`, un sorteggio all'anno e solo se c'e' un luogo) insorge.
## Luogo (`uprising_site`): una provincia ribelle sua (d'inizio o persa ai ribelli) -> riemerge subito (`_reemerge`);
## altrimenti una sua provincia in mano ad altri -> armata di ribelli lealisti a lei fedeli (`_uprising`): se la prende,
## l'anno dopo la consegna alla fazione, che riemerge (`_loyalist_handover`). Ogni tentativo riazzera l'attesa.
static func _loyalist_uprisings(state: GameState, new_year: int) -> void:
	var pr := state.rules.province
	var fresh := {}
	var fresh_ready := false
	for f in state.factions:
		if f.alive or f.id == GameState.REBEL or f.id == GameState.PAPAL or f.is_player:
			f.dead_years = 0
			continue
		if not state.has_dynasty(f.id):
			continue
		if not fresh_ready:
			fresh = _fresh_extinctions(state)
			fresh_ready = true
		if fresh.has(f.id):
			continue
		f.dead_years += 1
		var chance := pr.uprising_chance(f.dead_years)
		if chance <= 0.0:
			continue
		var site := uprising_site(state, f.id)
		if site == null:
			continue
		if chance < 1.0 and state.rng.randf() >= chance:
			continue
		f.dead_years = 0
		if site.owner == GameState.REBEL:
			_reemerge(state, f, site, new_year)
		else:
			_uprising(state, f, site)


## Dove insorge la fazione estinta (ADR-114), nell'ordine delle province: una ribelle sua all'inizio o persa ai ribelli;
## la sua provincia d'inizio in mano a un'altra fazione viva con la lealta' piu' bassa; l'ultima provincia che ha perso
## (`proprietario_precedente`) in mano a un'altra fazione viva, con la lealta' piu' bassa. Mai una provincia dove i suoi
## lealisti sono gia' in armi. null se non ce n'e'.
static func uprising_site(state: GameState, faction_id: String) -> ProvinceState:
	for p in state.provinces:
		if p.owner == GameState.REBEL and (origin_owner(state, p) == faction_id or p.former_owner == faction_id):
			return p
	var best: ProvinceState = null
	for pass_index in 2:
		for p in state.provinces:
			if p.owner == "" or p.owner == GameState.REBEL or p.owner == faction_id:
				continue
			var owner := state.faction(p.owner)
			if owner == null or not owner.alive:
				continue
			var ours := origin_owner(state, p) == faction_id if pass_index == 0 else str(p.counters.get(PRIOR_OWNER_KEY, "")) == faction_id
			if not ours or _has_loyalists(state, p.id, faction_id):
				continue
			if best == null or p.loyalty < best.loyalty:
				best = p
		if best != null:
			return best
	return null


static func _has_loyalists(state: GameState, region_id: String, faction_id: String) -> bool:
	for a in state.armies:
		if a.faction == GameState.REBEL and a.region == region_id and a.loyal_to == faction_id and not a.stacks.is_empty():
			return true
	return false


## Armata di ribelli lealisti della fazione estinta `f` nella provincia `site` di un'altra fazione (ADR-114): truppe dei
## lealisti (`loyalist_units`, altrimenti la truppa dei ribelli), `pile` + `pile_in_piu` per ogni tentativo gia' fatto,
## entro il limite degli eserciti. EV_REBELLION con «lealisti_di» e «insurrezione» vero.
static func _uprising(state: GameState, f: FactionState, site: ProvinceState) -> void:
	var pr := state.rules.province
	var region := state.campaign.region(site.id)
	var mix := loyalist_units(state, f.id, region)
	if mix.is_empty():
		var unit := rebel_unit(state, region)
		if unit != null:
			mix.append(unit)
	if mix.is_empty():
		return
	var stacks := clampi(pr.uprising_stacks + pr.uprising_growth * f.uprisings, 1, state.rules.max_stacks)
	var army := state.create_army(GameState.REBEL, site.id, false)
	army.loyal_to = f.id
	for i in stacks:
		var u: UnitType = mix[i % mix.size()]
		army.stacks.append(state.new_stack(GameState.REBEL, u.id, u.men))
	f.uprisings += 1
	WarProcessor.refresh_sieges(state)
	state.add_event(GameState.EV_REBELLION, {
		"fazione": site.owner,
		"regione": site.id,
		"provincia": site.id,
		"lealta": site.loyalty,
		"tipo_ribelli": REBEL_LOYALISTS,
		"lealisti_di": f.id,
		"insurrezione": true,
		"esercito": army.id,
		"pile": stacks,
		"uomini": army.men_total(),
		"testo": Lang.t("I lealisti di %s insorgono a %s contro %s con un'armata di %d pile.") % [
			SimUtil.faction_label(f.id), WarProcessor.region_label(state, site.id), SimUtil.faction_label(site.owner), stacks],
	})


# --- 0. lealisti (ADR-070) ---------------------------------------------------------------------------


## Le province dei ribelli in cui c'e' un esercito ribelle lealista (in ordine di id, vale il primo) passano alla fazione a
## cui e' fedele: se e' viva prende la provincia e gli eserciti lealisti a lei fedeli (EV_LOYALISTS_RETURN); se e' estinta
## e puo' riemergere riemerge li' (`_reemerge`, con tutti gli eserciti ribelli presenti); altrimenti i lealisti tornano
## ribelli comuni. Nessun sorteggio.
static func _loyalist_handover(state: GameState, new_year: int) -> void:
	var fresh := {}
	var fresh_ready := false
	for p in state.provinces:
		if p.owner != GameState.REBEL:
			continue
		var target := ""
		for a in state.armies:
			if a.faction == GameState.REBEL and a.region == p.id and not a.is_fleet and a.loyal_to != "" and not a.stacks.is_empty():
				target = a.loyal_to
				break
		if target == "":
			continue
		var f := state.faction(target)
		if f != null and f.alive and f.id != GameState.REBEL:
			_return_to_loyal(state, p, f)
			continue
		if f != null and f.id == GameState.PAPAL:
			PapacyProcessor.reemerge_at(state, p)   # insurrezione papale riuscita (ADR-072)
			continue
		if not fresh_ready:
			fresh = _fresh_extinctions(state)
			fresh_ready = true
		if f != null and not f.is_player and state.has_dynasty(f.id) and not fresh.has(f.id):
			_reemerge(state, f, p, new_year)
			continue
		for a in state.armies:
			if a.faction == GameState.REBEL and a.region == p.id and a.loyal_to == target:
				a.loyal_to = ""


## La provincia ribelle passa alla fazione viva `f` con gli eserciti ribelli a lei fedeli (stessi uomini).
static func _return_to_loyal(state: GameState, p: ProvinceState, f: FactionState) -> void:
	p.owner = f.id
	p.former_owner = ""
	p.building_queue.clear()
	p.unit_queue.clear()
	p.tax_level = state.rules.default_tax
	var army_ids: Array = []
	var men := 0
	for a in state.armies:
		if a.faction == GameState.REBEL and a.region == p.id and not a.is_fleet and a.loyal_to == f.id:
			a.faction = f.id
			a.loyal_to = ""
			army_ids.append(a.id)
			men += a.men_total()
	TroopUpgrades.apply_faction_minimum(state)
	_fix_castle_flags(state)
	WarProcessor.refresh_sieges(state)
	state.add_event(GameState.EV_LOYALISTS_RETURN, {
		"fazione": f.id,
		"regione": p.id,
		"provincia": p.id,
		"precedente": GameState.REBEL,
		"eserciti": army_ids,
		"uomini": 0,
		"testo": Lang.t("I ribelli lealisti consegnano %s a %s: la provincia torna sua con %d uomini.") % [
			WarProcessor.region_label(state, p.id), SimUtil.faction_label(f.id), men],
	})
