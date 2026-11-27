class_name ReligionProcessor
extends RefCounted
## Religione del fine anno (fase 5b, spec. fase 5 §5b, ADR-010). `TurnProcessor.end_year` chiama `process_year` dopo
## le regole delle province (4b) e prima del reddito. Nessun sorteggio: la religione e' deterministica (il solo
## sorteggio della 5b e' il processo dell'inquisitore, in `AgentProcessor`). Funziona anche nei mondi senza
## personaggi; le province dei ribelli non hanno una religione del proprietario (nessuna deriva), ma gli edifici e i
## religiosi presenti convertono comunque.
##
## Composizione di una provincia (`ProvinceState.religions`): CATHOLIC, ORTHODOX, MUSLIM, PAGAN, HERETIC in percentuale,
## somma sempre 100. Come si mantiene esatta: i valori sono multipli di 0,25 punti (esatti in virgola mobile) e ogni
## spostamento (`shift`) lavora su passi interi: i punti da spostare sono arrotondati al passo, tolti alle religioni
## di partenza in proporzione alla loro quota con il metodo del maggior resto (a parita' vince la prima nell'ordine
## `ProvinceState.RELIGIONS`) e dati alla religione di arrivo; non si sposta mai piu' di quanto le religioni di
## partenza hanno. Quindi non c'e' mai un arrotondamento che sposti la somma.
##
## Ordine fisso di ogni anno (province in ordine di dichiarazione, edifici in ordine alfabetico di famiglia, agenti
## in ordine di id; tutti i parametri sono in `rules.religion`, data/regole/religione.cfg, PROVVISORI dove il catalogo
## non ha la formula):
##   1. deriva verso la religione del proprietario
##   2. conversione degli edifici religiosi (colonna 14 del file edifici = religione, colonna 21 = propagazione della
##      fede > 0; edificio «grande» se la propagazione e' >= `soglia_fede_grande`)
##   3. conversione dei religiosi presenti (anche in province altrui; colonna 45 di unit_prod, altrimenti i parametri)
##   4. crescita dell'eresia (proprietario cattolico, tassa alta o lealta' bassa)
##   5. inquisitori del proprietario: gli eretici passano alla religione del proprietario
##   6. zelo: torna verso il valore neutro, poi salgono i religiosi e gli inquisitori presenti (colonna 44, altrimenti i
##      parametri).
## La lealta' (`loyalty_term`, `inquisitor_term`) e la rivolta eretica (`heretic_revolt`) sono agganciate da
## `ProvinceProcessor`; il processo dell'inquisitore e' una missione (`AgentMissions.TRIAL`).

const INQUISITOR := "INQUISITOR"
const GRAND_INQUISITOR := "GRAND_INQUISITOR"
## Colonne di unit_prod: effetto su zelo e conversione («PAGAN(0), CATHOLIC(2), ...»); la 43 (unita' temute) non si usa.
const COL_ZEAL := 44
const COL_CONVERSION := 45


# --- passo annuale -----------------------------------------------------------------------------------


static func process_year(state: GameState) -> void:
	var by_region := {}
	for a in state.agents:
		if not by_region.has(a.region):
			by_region[a.region] = []
		var list: Array = by_region[a.region]
		list.append(a)
	for p in state.provinces:
		var here: Array = by_region.get(p.id, [])
		_process_province(state, p, here)


static func _process_province(state: GameState, p: ProvinceState, here: Array) -> void:
	var rr := state.rules.religion
	# luoghi leggendari: la popolazione si sposta verso la religione indicata (Monte Athos)
	var conv := LegendarySites.region_conversion(state, p.id)
	for rel in conv:
		if int(conv[rel]) > 0:
			shift(p, str(rel), float(conv[rel]))
	var owner_rel := owner_religion(state, p)
	# 1. deriva (gli eretici di un proprietario cattolico non derivano: si spengono con inquisitori e religiosi)
	if owner_rel != "":
		var sources: Array = []
		for k in ProvinceState.RELIGIONS:
			if k != owner_rel and not (k == ProvinceState.HERETIC and owner_rel == ProvinceState.CATHOLIC):
				sources.append(k)
		shift(p, owner_rel, rr.drift, sources)
	# 2. edifici
	var families: Array = p.buildings.keys()
	families.sort()
	for key in families:
		var family_id := str(key)
		var family: BuildingType = state.buildings.get_family(family_id)
		if family == null:
			continue
		var level: BuildingType.Level = family.get_level(p.level_of(family_id))
		if level == null:
			continue
		var religion := building_religion(family, level, owner_rel)
		if religion == "":
			continue
		shift(p, religion, rr.big_building_points if level.faith >= rr.big_faith else rr.building_points)
	# 3. religiosi presenti
	for item in here:
		var agent: AgentState = item
		var points := agent_conversion(state, agent)
		for k in ProvinceState.RELIGIONS:
			if points.has(k):
				shift(p, k, float(points[k]))
	# 4. eresia
	if owner_rel == ProvinceState.CATHOLIC and (p.tax_level >= rr.heresy_tax_level or p.loyalty < rr.heresy_loyalty):
		shift(p, ProvinceState.HERETIC, rr.heresy_growth, [ProvinceState.CATHOLIC])
	# 5. inquisitori
	if p.owner != GameState.REBEL:
		var back := owner_rel if owner_rel != "" else ProvinceState.CATHOLIC
		for item in here:
			var agent: AgentState = item
			if agent.faction == p.owner and is_inquisitor(agent):
				shift(p, back, inquisitor_points(state, agent), [ProvinceState.HERETIC])
	# 6. zelo
	var zeal := p.zeal
	if zeal > rr.neutral_zeal:
		zeal = maxi(rr.neutral_zeal, zeal - rr.zeal_decay)
	elif zeal < rr.neutral_zeal:
		zeal = mini(rr.neutral_zeal, zeal + rr.zeal_decay)
	if owner_rel != "":
		for item in here:
			var agent: AgentState = item
			zeal += agent_zeal(state, agent, owner_rel)
	p.zeal = clampi(zeal, 0, 100)


# --- composizione --------------------------------------------------------------------------------------


## Composizione e zelo della partita nuova per ogni provincia (anche per i salvataggi precedenti alla versione 6).
static func init_religions(state: GameState) -> void:
	for p in state.provinces:
		p.religions = initial_composition(state, p)
		p.zeal = state.rules.religion.initial_zeal


## Composizione iniziale (PROVVISORIA, i dati non hanno percentuali): 100% della religione della cultura della regione;
## se il proprietario ha un'altra religione, `quota_religione_proprietario` (25%) a lui e il resto alla cultura. Cultura
## sconosciuta: tutta la religione del proprietario; senza nessuna delle due: tutta pagana.
static func initial_composition(state: GameState, p: ProvinceState) -> Dictionary:
	var rr := state.rules.religion
	var culture_rel := ""
	var region := state.campaign.region(p.id)
	if region != null:
		culture_rel = ReligionRules.religion_key(state.rules.province.religion_of_culture(region.culture))
	var owner_rel := owner_religion(state, p)
	var values := {}
	if culture_rel == "" and owner_rel == "":
		values[ProvinceState.PAGAN] = 100.0
	elif culture_rel == "":
		values[owner_rel] = 100.0
	elif owner_rel == "" or owner_rel == culture_rel:
		values[culture_rel] = 100.0
	elif GameCommands.religion_base(owner_rel) == culture_rel:
		values[owner_rel] = 100.0   # Culto Imperiale nelle terre cattoliche degli Auror: tutte al culto del proprietario
	else:
		values[owner_rel] = float(rr.other_owner_share)
		values[culture_rel] = float(100 - rr.other_owner_share)
	return ProvinceState.normalize_religions(values)


## Religione della fazione come chiave della provincia ("CATHOLIC"...), "" se sconosciuta (ribelli, ebrei).
static func faction_religion(state: GameState, faction_id: String) -> String:
	var key := DiplomacyProcessor.faction_religion(state, faction_id)
	return key if ProvinceState.RELIGIONS.has(key) else ""


## Religione del proprietario della provincia, "" se non ne ha.
static func owner_religion(state: GameState, p: ProvinceState) -> String:
	if p.owner == "" or p.owner == GameState.REBEL:
		return ""
	return faction_religion(state, p.owner)


## Sposta fino a `amount` punti verso la religione `to`, togliendoli alle religioni di `sources` (vuoto = tutte le altre)
## in proporzione alla loro quota. Restituisce i punti spostati davvero (0 se non c'era nulla da togliere).
@warning_ignore("integer_division")
static func shift(p: ProvinceState, to: String, amount: float, sources: Array = []) -> float:
	if not ProvinceState.RELIGIONS.has(to):
		return 0.0
	var want := roundi(amount / ProvinceState.RELIGION_UNIT)
	if want <= 0:
		return 0.0
	var pool: Array[String] = []
	var avail: Array[int] = []
	var total := 0
	for k in ProvinceState.RELIGIONS:
		if k == to or (not sources.is_empty() and not sources.has(k)):
			continue
		var units := p.religion_units(k)
		if units > 0:
			pool.append(k)
			avail.append(units)
			total += units
	var move := mini(want, total)
	if move <= 0:
		return 0.0
	var shares: Array[int] = []
	var rests: Array[int] = []
	var given := 0
	for i in pool.size():
		var numerator := move * avail[i]
		shares.append(numerator / total)
		rests.append(numerator % total)
		given += shares[i]
	var left := move - given
	while left > 0:
		var best := -1
		for i in pool.size():
			if shares[i] < avail[i] and (best < 0 or rests[i] > rests[best]):
				best = i
		if best < 0:
			break
		shares[best] += 1
		rests[best] = -1
		left -= 1
	var moved := 0
	for i in pool.size():
		p.religions[pool[i]] = float(avail[i] - shares[i]) * ProvinceState.RELIGION_UNIT
		moved += shares[i]
	p.religions[to] = float(p.religion_units(to) + moved) * ProvinceState.RELIGION_UNIT
	return float(moved) * ProvinceState.RELIGION_UNIT


# --- edifici -------------------------------------------------------------------------------------------


## Religione verso cui converte un livello di edificio: serve una propagazione della fede maggiore di zero e almeno una
## religione nella colonna 14; vale quella del proprietario se e' tra le religioni dell'edificio, altrimenti la prima.
## "" se l'edificio non converte.
static func building_religion(family: BuildingType, level: BuildingType.Level, owner_rel: String) -> String:
	if level.faith <= 0.0 or family.religions.is_empty():
		return ""
	var first := ""
	for r in family.religions:
		var key := ReligionRules.religion_key(r)
		if key == "":
			continue
		if key == owner_rel:
			return key
		if owner_rel != "" and key == GameCommands.religion_base(owner_rel):
			return owner_rel   # Culto Imperiale: le chiese cattoliche degli Auror convertono al loro culto
		if first == "":
			first = key
	return first


# --- religiosi e inquisitori ----------------------------------------------------------------------------


static func is_inquisitor(a: AgentState) -> bool:
	return a.type_name == INQUISITOR or a.type_name == GRAND_INQUISITOR


static func _unit_cell(state: GameState, a: AgentState, col: int) -> String:
	if state.units == null:
		return ""
	var unit: UnitType = state.units.get_unit(a.unit_id)
	if unit == null:
		return ""
	return UnitProdLoader.cell(unit.raw, col)


## Religione con piu' punti in un elenco `parse_points` ("" se vuoto; a parita' la prima nell'ordine delle religioni).
static func _best_key(points: Dictionary) -> String:
	var best := ""
	for k in ProvinceState.RELIGIONS:
		if points.has(k) and (best == "" or float(points[k]) > float(points[best])):
			best = k
	return best


## Religione di un agente: per i religiosi quella della colonna 45 (poi 44) di unit_prod, poi quella del tipo
## (`type_religion`), poi quella della fazione; per gli altri agenti quella della fazione. "" se sconosciuta.
static func agent_religion(state: GameState, a: AgentState) -> String:
	if a.is_religious():
		var key := _best_key(ReligionRules.parse_points(_unit_cell(state, a, COL_CONVERSION)))
		if key == "":
			key = _best_key(ReligionRules.parse_points(_unit_cell(state, a, COL_ZEAL)))
		if key == "":
			key = ReligionRules.religion_key(str(state.rules.religion.type_religion.get(a.type_name, "")))
		if key != "":
			return _own_cult(state, a, key)
	return faction_religion(state, a.faction)


## Religione `key` di un religioso vista dalla sua fazione: se la fazione ha un culto che usa gli agenti di `key` (il Culto
## Imperiale degli Auror con vescovi e cardinali cattolici), quella della fazione; altrimenti `key`.
static func _own_cult(state: GameState, a: AgentState, key: String) -> String:
	var own := faction_religion(state, a.faction)
	if own != "" and own != key and GameCommands.religion_base(own) == key:
		return own
	return key


## Elenco religione -> punti della prod (colonne 44 e 45) visto dalla fazione dell'agente (vedi `_own_cult`).
static func _own_points(state: GameState, a: AgentState, listed: Dictionary) -> Dictionary:
	var out := {}
	for k in listed:
		var key := _own_cult(state, a, str(k))
		out[key] = float(out.get(key, 0.0)) + float(listed[k])
	return out


## Conversione annua di un religioso: religione -> punti. Dalla colonna 45 di unit_prod quando c'e'; altrimenti
## `conv_agente` (o `conv_agente_grande` per cardinale, ulema, vescovo ortodosso) alla sua religione. Gli inquisitori
## non convertono (vuoto per i non religiosi).
static func agent_conversion(state: GameState, a: AgentState) -> Dictionary:
	if not a.is_religious():
		return {}
	var listed := ReligionRules.parse_points(_unit_cell(state, a, COL_CONVERSION))
	if not listed.is_empty():
		return _own_points(state, a, listed)
	if is_inquisitor(a):
		return {}
	var rel := agent_religion(state, a)
	if rel == "":
		return {}
	var rr := state.rules.religion
	return {rel: rr.big_agent_points if rr.big_agent_types.has(a.type_name) else rr.agent_points}


## Zelo guadagnato in un anno da un agente presente in una provincia la cui religione e' `religion`: la colonna 44 di
## unit_prod quando c'e'; altrimenti i parametri per un religioso o un inquisitore della stessa religione. Gli altri
## agenti: 0.
static func agent_zeal(state: GameState, a: AgentState, religion: String) -> int:
	var listed := ReligionRules.parse_points(_unit_cell(state, a, COL_ZEAL))
	if not listed.is_empty():
		return roundi(float(_own_points(state, a, listed).get(religion, 0.0)))
	if not a.is_religious() or agent_religion(state, a) != religion:
		return 0
	var rr := state.rules.religion
	if a.type_name == GRAND_INQUISITOR:
		return rr.grand_inquisitor_zeal
	if a.type_name == INQUISITOR:
		return rr.inquisitor_zeal
	if rr.big_agent_types.has(a.type_name):
		return rr.big_religious_zeal
	return rr.religious_zeal


## Eretici che un inquisitore converte in un anno.
static func inquisitor_points(state: GameState, a: AgentState) -> float:
	var rr := state.rules.religion
	return rr.grand_inquisitor_points if a.type_name == GRAND_INQUISITOR else rr.inquisitor_points


# --- aggancio con la lealta' e le rivolte (ProvinceProcessor) -------------------------------------------


## Termine di religione della lealta' obiettivo (<= 0): `penalita_religione` x (100 - % della religione del proprietario)
## / 100, arrotondato. Senza religione del proprietario (ribelli, religione ignota): 0.
static func loyalty_term(state: GameState, p: ProvinceState) -> int:
	var rel := owner_religion(state, p)
	if rel == "":
		return 0
	var penalty := float(state.rules.province.religion_penalty) * (100.0 - p.religion_pct(rel)) / 100.0
	return -roundi(penalty)


## Termine degli inquisitori inattivi (<= 0, PROVVISORIA, catalogo: «bruciano la popolazione»): per ogni inquisitore del
## proprietario nella provincia, se non ci sono eretici, senza una missione di processo in corso.
static func inquisitor_term(state: GameState, p: ProvinceState) -> int:
	if p.owner == GameState.REBEL or state.agents.is_empty() or p.religion_pct(ProvinceState.HERETIC) > 0.0:
		return 0
	var inactive := 0
	for a in state.agents:
		if a.region == p.id and a.faction == p.owner and is_inquisitor(a) and str(a.mission.get("tipo", "")) != AgentMissions.TRIAL:
			inactive += 1
	return -inactive * state.rules.religion.inactive_malus


## Vero se la rivolta di questa provincia e' eretica: eretici oltre `soglia_rivolta_eretica`.
static func heretic_revolt(state: GameState, p: ProvinceState) -> bool:
	return p.owner != GameState.REBEL and p.religion_pct(ProvinceState.HERETIC) > state.rules.religion.heretic_revolt_threshold
