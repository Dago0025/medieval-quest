class_name DiplomacyProcessor
extends RefCounted
## Diplomazia della fase 5a (spec. fase 5 §5a): rottura dei trattati quando si attacca, scadenza delle tregue,
## pulizia dei trattati di fazioni scomparse e accettazione delle proposte.
##
## Stati di una coppia: guerra, alleanza, tregua, neutralita' (`GameState.relation`); i ribelli sono in guerra con
## tutti e non entrano in trattati. Le IA non prendono iniziative (fase 7): rispondono alle proposte degli
## emissari e delle principesse con la formula di accettazione qui sotto.
##
## Accettazione delle proposte, PROVVISORIA (catalogo: formula ignota, cala con la dimensione dell'impero),
## parametri in `rules.diplomacy` (data/regole/diplomazia.cfg):
##   p = base + k_influenza * (influenza - influenza_neutra) + k_valore * valore dell'agente + religione
##       + dimensione + guerra, limitata a [p_min, p_max]
## - base: alleanza, tregua o matrimonio;
## - influenza: del capo del proponente (senza capo: neutra);
## - religione: + se stessa religione, - se diversa (religione sconosciuta: niente);
## - dimensione: se le regioni di terra del proponente superano `soglia_dimensione` del totale,
##   -k_dimensione * (quota - soglia);
## - guerra: alleanza, -malus se il proponente e' in guerra con un alleato del destinatario; tregua,
##   +k_forza * (forza del proponente / (forza dei due) - 0,5), con le forze in uomini totali;
## - stanchezza (solo tregua): +k_stanchezza per anno di guerra senza svolte (`GameState.war_turn_year`), fino a
##   anni_stanchezza_max anni.

const KIND_ALLIANCE := "alleanza"
const KIND_TRUCE := "tregua"
const KIND_MARRIAGE := "matrimonio"


# --- attacchi e trattati ---------------------------------------------------------------------------


## Chi attacca una fazione con cui ha un'alleanza o una tregua rompe il trattato: l'influenza del suo capo
## scende di `malus_tradimento` (PROVVISORIA; catalogo: «tradire un alleato costa influenza») e si registra
## EV_ALLIANCE_BROKEN o EV_TRUCE_BROKEN. Da chiamare prima di `GameState.declare_war`. Restituisce il tipo di evento
## registrato ("" se la coppia non aveva trattati).
static func break_for_attack(state: GameState, attacker: String, defender: String, region_id: String) -> String:
	var rel := state.relation(attacker, defender)
	if rel != GameState.REL_ALLIANCE and rel != GameState.REL_TRUCE:
		return ""
	var event_type := GameState.EV_ALLIANCE_BROKEN
	var noun := Lang.t("l'alleanza")
	if rel == GameState.REL_ALLIANCE:
		state.break_alliance(attacker, defender)
	else:
		state.break_truce(attacker, defender)
		event_type = GameState.EV_TRUCE_BROKEN
		noun = Lang.t("la tregua")
	var lost := 0
	var leader := state.leader_of(attacker)
	if leader != null:
		var before := leader.influence
		leader.influence = clampi(leader.influence - state.rules.diplomacy.betrayal_malus, 0, state.rules.dynasty.max_attribute)
		lost = before - leader.influence
	state.add_event(event_type, {
		"fazione": attacker,
		"con": defender,
		"regione": region_id,
		"influenza_persa": lost,
		"testo": Lang.t("%s rompe %s con %s attaccando in %s.") % [SimUtil.faction_label(attacker), noun, SimUtil.faction_label(defender), WarProcessor.region_label(state, region_id)],
	})
	return event_type


## Alleanze in conflitto (catalogo, MTW Diplomacy): quando `attacker` dichiara una guerra nuova a `defender`, chi e' alleato di
## entrambi resta alleato di chi e' attaccato e torna neutrale con chi attacca (EV_ALLIANCE_BROKEN con "motivo" =
## "alleanze_in_conflitto", "difensore" = chi e' attaccato, senza perdita di influenza). PROVVISORIO: nell'originale sceglie il giocatore. Da chiamare dopo
## `GameState.declare_war`. Restituisce le fazioni che hanno rotto, in ordine di dichiarazione.
static func resolve_conflicting_alliances(state: GameState, attacker: String, defender: String, region_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not state.rules.diplomacy.conflicting_alliances:
		return out
	for f in state.factions:
		if f.id == attacker or f.id == defender or not f.alive:
			continue
		if not (state.is_allied(f.id, attacker) and state.is_allied(f.id, defender)):
			continue
		state.break_alliance(f.id, attacker)
		out.append(f.id)
		state.add_event(GameState.EV_ALLIANCE_BROKEN, {
			"fazione": f.id,
			"con": attacker,
			"difensore": defender,
			"regione": region_id,
			"influenza_persa": 0,
			"motivo": "alleanze_in_conflitto",
			"testo": Lang.t("%s non puo' restare alleata di %s e di %s, che si fanno guerra: resta con %s e rompe con %s.") % [
				SimUtil.faction_label(f.id), SimUtil.faction_label(attacker), SimUtil.faction_label(defender),
				SimUtil.faction_label(defender), SimUtil.faction_label(attacker)],
		})
	return out


## Anni di guerra senza svolte tra le due fazioni (0 se non sono in guerra).
static func stalemate_years(state: GameState, faction_a: String, faction_b: String) -> int:
	if not state.wars.has(GameState.war_key(faction_a, faction_b)):
		return 0
	return maxi(0, state.year - state.war_turn_year(faction_a, faction_b))


## Scadenza delle tregue (ultimo passo del fine anno): una tregua con anno di scadenza <= `new_year` cade e la
## coppia torna neutrale (EV_TRUCE_EXPIRED). Ordine delle chiavi: alfabetico.
static func expire_truces(state: GameState, new_year: int) -> void:
	var keys: Array = state.truces.keys()
	keys.sort()
	for key in keys:
		if int(state.truces[key]) > new_year:
			continue
		state.truces.erase(key)
		var pair := GameState.pair_of(str(key))
		if pair.size() < 2:
			continue
		state.add_event(GameState.EV_TRUCE_EXPIRED, {
			"fazione": pair[0],
			"con": pair[1],
			"regione": "",
			"testo": Lang.t("La tregua tra %s e %s e' scaduta.") % [SimUtil.faction_label(pair[0]), SimUtil.faction_label(pair[1])],
		})


## Toglie alleanze e tregue che coinvolgono ribelli, fazioni morte o sconosciute, o una fazione con se stessa.
## Le guerre restano come sono (una fazione risorta ritrova le sue). Nessun evento.
static func cleanup(state: GameState) -> void:
	for table in [state.alliances, state.truces]:
		var dict: Dictionary = table
		var keys: Array = dict.keys()
		keys.sort()
		for key in keys:
			var pair := GameState.pair_of(str(key))
			var valid := pair.size() == 2 and pair[0] != pair[1]
			if valid:
				for f_id in pair:
					var f := state.faction(f_id)
					if f_id == GameState.REBEL or f == null or not f.alive:
						valid = false
			if not valid:
				dict.erase(key)


# --- accettazione delle proposte -----------------------------------------------------------------------


## Dettaglio della probabilita' che `recipient` accetti una proposta di `kind` fatta da `proposer` tramite un agente di
## valore `agent_valour`: "base", "influenza", "valore", "religione", "dimensione", "guerra", "somma" (senza
## limiti) e "p" (limitata). Solo calcolo, nessun sorteggio.
static func acceptance_terms(state: GameState, kind: String, proposer: String, recipient: String, agent_valour: int) -> Dictionary:
	var dr := state.rules.diplomacy
	var base := dr.base_alliance
	if kind == KIND_TRUCE:
		base = dr.base_truce
	elif kind == KIND_MARRIAGE:
		base = dr.base_marriage
	var influence_term := 0.0
	var leader := state.leader_of(proposer)
	if leader != null:
		var influence := leader.effective(Character.ATTR_INFLUENCE, state.rules, state.campaign)
		influence_term = dr.k_influence * float(influence - dr.neutral_influence)
	var valour_term := dr.k_valour * float(agent_valour)
	var religion_term := 0.0
	var religion_a := faction_religion(state, proposer)
	var religion_b := faction_religion(state, recipient)
	if religion_a != "" and religion_b != "":
		religion_term = dr.same_religion_bonus if religion_a == religion_b else -dr.other_religion_malus
	var size_term := 0.0
	var share := land_share(state, proposer)
	if share > dr.size_threshold:
		size_term = -dr.k_size * (share - dr.size_threshold)
	var war_term := 0.0
	if kind == KIND_ALLIANCE:
		for f in state.factions:
			if f.id != recipient and state.is_allied(recipient, f.id) and state.at_war(proposer, f.id):
				war_term = -dr.allies_war_malus
				break
	elif kind == KIND_TRUCE:
		var own := float(faction_men(state, proposer))
		var other := float(faction_men(state, recipient))
		var strength := 0.5
		if own + other > 0.0:
			strength = own / (own + other)
		war_term = dr.k_strength * (strength - 0.5)
	var weariness_term := 0.0
	if kind == KIND_TRUCE:
		weariness_term = dr.k_weariness * float(mini(stalemate_years(state, proposer, recipient), dr.weariness_max_years))
	var total := base + influence_term + valour_term + religion_term + size_term + war_term + weariness_term
	return {
		"base": base,
		"influenza": influence_term,
		"valore": valour_term,
		"religione": religion_term,
		"dimensione": size_term,
		"guerra": war_term,
		"stanchezza": weariness_term,
		"somma": total,
		"p": clampf(total, dr.p_min, dr.p_max),
	}


## Probabilita' di accettazione (vedi `acceptance_terms`).
static func acceptance(state: GameState, kind: String, proposer: String, recipient: String, agent_valour: int) -> float:
	return float(acceptance_terms(state, kind, proposer, recipient, agent_valour)["p"])


## Religione della fazione come nei file edifici ("CATHOLIC", "MUSLIM"...), "" se sconosciuta.
static func faction_religion(state: GameState, faction_id: String) -> String:
	var cf := state.campaign.faction(faction_id)
	if cf == null or cf.religion == "":
		return ""
	return GameCommands.religion_key(cf.religion)


## Quota delle regioni di terra possedute dalla fazione (0..1).
static func land_share(state: GameState, faction_id: String) -> float:
	if state.provinces.is_empty():
		return 0.0
	return float(state.provinces_of(faction_id).size()) / float(state.provinces.size())


## Uomini di tutti gli eserciti e le flotte della fazione.
static func faction_men(state: GameState, faction_id: String) -> int:
	var total := 0
	for a in state.armies_of(faction_id):
		total += a.men_total()
	return total
