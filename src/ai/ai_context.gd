class_name AiContext
extends RefCounted
## Dati dell'anno condivisi da tutte le fazioni dell'IA (fase 7, ADR-012): eserciti per regione, forze (la formula di `Combat`),
## redditi e mantenimenti, personaggi, vicini. Si costruisce UNA volta per anno in `AiController.plan_year` (niente ricerche
## quadratiche sulle regioni). Le posizioni degli eserciti non cambiano durante la pianificazione (si muovono nel fine anno),
## quindi le tabelle restano valide anche dopo gli ordini; cambiano solo i percorsi (`Army.path`) e le code.
##
## L'IA legge lo stato e manda solo comandi (`GameCommands`): questo oggetto non modifica la simulazione.

var state: GameState
var rules: AiRules
## Parametri della difficolta' scelta: aggressivita', budget, soglia.
var diff: Dictionary = {}
## Regione -> elenco (Array di Army) degli eserciti di terra non vuoti, in ordine di id; idem le flotte per zona di mare.
var armies_by_region := {}
var fleets_by_zone := {}
## Fazione -> eserciti di terra / flotte non vuoti, in ordine di id.
var land_by_faction := {}
var fleets_by_faction := {}
## Id esercito -> Army, per tutti gli eserciti e le flotte (anche vuoti).
var army_by_id := {}
## Id esercito -> forza (`Combat.army_strength`).
var strength := {}
## Fazione -> mantenimento attuale (come `Economy.faction_upkeep`) e mantenimento delle reclute in coda.
var upkeep := {}
var pending_upkeep := {}
## Fazione -> reddito lordo stimato dell'anno (somma di `Economy.province_income`), provincia -> reddito.
var income := {}
var province_income := {}
## Provincia -> governatore (Character), fazione -> personaggi vivi.
var governors := {}
var chars_by_faction := {}
## Regione -> vicini di terra / di mare (PackedStringArray), dall'ordine di SetNeighbours.
var land_neighbours := {}
var sea_neighbours := {}
## Fazione -> indice nell'ordine di dichiarazione (per il generatore casuale).
var faction_index := {}
## Eserciti gia' impegnati dall'IA quest'anno (id -> true).
var busy := {}
## Destinazioni via mare degli agenti per i viaggi dell'IA (ADR-053, `AiJourneys.sea_cache`): firma -> regione -> province.
var journey_sea := {}
## Fase 7b: province perse nell'ultimo fine anno ("PERDENTE>VINCITORE" -> quante), dagli eventi dell'anno appena concluso.
var captures_lost := {}
## Fase 7b (costruiti alla prima richiesta, `ensure_index`): regione -> personaggi vivi / agenti presenti; tipo di agente -> unita'
## della tabella. Gli agenti non cambiano regione durante la pianificazione (si muovono nel fine anno).
var chars_by_region := {}
var agents_by_region := {}
var agent_units := {}
## Ordini accettati e rifiutati dai comandi; `rejections` conserva i primi messaggi di rifiuto (per i test e la taratura).
var orders := 0
var rejected := 0
var rejections: Array[String] = []
## Registro degli ordini (solo con `keep_log`): una riga per ordine accettato o rifiutato, in ordine.
var keep_log := false
var log: Array[String] = []

var _capitals := {}
var _indexed := false


static func build(game: GameState, ai_rules: AiRules, difficulty_name: String = "") -> AiContext:
	var ctx := AiContext.new()
	ctx.state = game
	ctx.rules = ai_rules
	ctx.diff = ai_rules.difficulty_params(difficulty_name)
	for i in game.factions.size():
		ctx.faction_index[game.factions[i].id] = i
	for r in game.campaign.regions:
		var land := PackedStringArray()
		var sea := PackedStringArray()
		for n in r.neighbours:
			var other := game.campaign.region(n)
			if other == null:
				continue
			if other.is_sea:
				sea.append(other.id)
			else:
				land.append(other.id)
		ctx.land_neighbours[r.id] = land
		ctx.sea_neighbours[r.id] = sea
	for a in game.armies:
		ctx.army_by_id[a.id] = a
		if a.stacks.is_empty():
			continue
		ctx.strength[a.id] = Combat.army_strength(game, a)
		var by_region: Dictionary = ctx.fleets_by_zone if a.is_fleet else ctx.armies_by_region
		var by_faction: Dictionary = ctx.fleets_by_faction if a.is_fleet else ctx.land_by_faction
		if not by_region.has(a.region):
			by_region[a.region] = []
		var region_list: Array = by_region[a.region]
		region_list.append(a)
		if not by_faction.has(a.faction):
			by_faction[a.faction] = []
		var faction_list: Array = by_faction[a.faction]
		faction_list.append(a)
		ctx.upkeep[a.faction] = int(ctx.upkeep.get(a.faction, 0)) + Economy.army_support_sum(game, a)
	for e in game.events:
		if str(e.get("tipo", "")) == GameState.EV_PROVINCE_CAPTURED:
			var lost_key := "%s>%s" % [str(e.get("precedente", "")), str(e.get("fazione", ""))]
			ctx.captures_lost[lost_key] = int(ctx.captures_lost.get(lost_key, 0)) + 1
	var acumen := Economy.acumen_table(game)
	for p in game.provinces:
		var f := game.faction(p.owner)
		if f == null or not f.alive:
			continue
		var inc := Economy.province_income(game, p, acumen)
		var total := int(inc["totale"])
		ctx.province_income[p.id] = total
		ctx.income[p.owner] = int(ctx.income.get(p.owner, 0)) + total
		for q in p.unit_queue:
			var u := game.units.get_unit(q.key)
			if u != null:
				ctx.pending_upkeep[p.owner] = int(ctx.pending_upkeep.get(p.owner, 0)) + u.support_cost
	for c in game.characters:
		if not c.alive:
			continue
		if not ctx.chars_by_faction.has(c.faction):
			ctx.chars_by_faction[c.faction] = []
		var list: Array = ctx.chars_by_faction[c.faction]
		list.append(c)
		if c.title != "":
			ctx.governors[c.title] = c
	return ctx


## Mantenimento attuale della fazione (arrotondato come nel fine anno) piu' quello delle reclute in coda.
func upkeep_of(faction_id: String, with_pending: bool = true) -> int:
	var total := int(upkeep.get(faction_id, 0))
	if with_pending:
		total += int(pending_upkeep.get(faction_id, 0))
	return roundi(float(total) * state.rules.upkeep_multiplier)


## Province che `loser` ha perso contro `winner` nell'ultimo fine anno (eventi EV_PROVINCE_CAPTURED).
func lost_provinces(loser: String, winner: String) -> int:
	return int(captures_lost.get("%s>%s" % [loser, winner], 0))


## Costruisce una volta sola gli indici dei personaggi e degli agenti per regione (usati dagli agenti dell'IA, fase 7b).
func ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	for c in state.characters:
		if not c.alive:
			continue
		var region := char_region(c)
		if not chars_by_region.has(region):
			chars_by_region[region] = []
		var list: Array = chars_by_region[region]
		list.append(c)
	for a in state.agents:
		if not agents_by_region.has(a.region):
			agents_by_region[a.region] = []
		var agent_list: Array = agents_by_region[a.region]
		agent_list.append(a)


func characters_in(region_id: String) -> Array:
	ensure_index()
	return chars_by_region.get(region_id, [])


func agents_in(region_id: String) -> Array:
	ensure_index()
	return agents_by_region.get(region_id, [])


## Unita' della tabella del tipo di agente indicato (EMISSARY, SPY...), in ordine del file.
func units_of_type(type_name: String) -> Array:
	if not agent_units.has(type_name):
		agent_units[type_name] = state.units.of_type(type_name)
	return agent_units[type_name]


func income_of(faction_id: String) -> int:
	return int(income.get(faction_id, 0))


## Eserciti di terra non vuoti della regione (elementi Army, in ordine di id).
func armies_at(region_id: String) -> Array:
	return armies_by_region.get(region_id, [])


func fleets_at(zone_id: String) -> Array:
	return fleets_by_zone.get(zone_id, [])


## Dove si trova il personaggio (la regione dell'esercito che comanda, altrimenti l'ultima nota): come
## `GameState.character_region` ma senza cercare l'esercito nell'elenco.
func char_region(c: Character) -> String:
	if c.army > 0 and army_by_id.has(c.army):
		var a: Army = army_by_id[c.army]
		return a.region
	return c.region


func force(a: Army) -> float:
	return float(strength.get(a.id, 0.0))


## Forza degli eserciti di terra della fazione nella regione (guarnigione compresa).
func own_force_in(region_id: String, faction_id: String) -> float:
	var total := 0.0
	for item in armies_at(region_id):
		var a: Army = item
		if a.faction == faction_id:
			total += force(a)
	return total


func land_armies_of(faction_id: String) -> Array:
	return land_by_faction.get(faction_id, [])


func fleets_of(faction_id: String) -> Array:
	return fleets_by_faction.get(faction_id, [])


func owner_of(region_id: String) -> String:
	var p := state.province(region_id)
	return p.owner if p != null else ""


## Capitale della fazione: la regione di PlaceLeader se e' ancora sua; altrimenti dove si trova il capo; altrimenti la sua
## provincia piu' ricca. "" se la fazione non ha province.
func capital_of(faction_id: String) -> String:
	if _capitals.has(faction_id):
		return _capitals[faction_id]
	var best := ""
	var cf := state.campaign.faction(faction_id)
	if cf != null and cf.leader_region != "":
		var home := state.province(cf.leader_region)
		if home != null and home.owner == faction_id:
			best = home.id
	if best == "":
		var leader := state.leader_of(faction_id)
		if leader != null:
			var here := state.province(state.character_region(leader))
			if here != null and here.owner == faction_id:
				best = here.id
	if best == "":
		var best_income := -1
		for p in state.provinces:
			if p.owner != faction_id:
				continue
			var inc := int(province_income.get(p.id, 0))
			if inc > best_income:
				best_income = inc
				best = p.id
	_capitals[faction_id] = best
	return best


## Generatore dell'IA per fazione e anno: seme derivato dal seme della partita, dall'anno e dall'indice della fazione. Non
## consuma `state.rng` e non si salva: stesso stato = stesse decisioni, anche dopo un caricamento.
func rng_for(faction_id: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = state.seed_value * 1000003 + state.year * 7919 + int(faction_index.get(faction_id, 0)) * 104729 + 31337
	return r
