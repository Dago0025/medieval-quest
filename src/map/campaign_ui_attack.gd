class_name CampaignUiAttack
extends RefCounted
## Conferma degli attacchi e attacco a una flotta precisa (richiesta di Federico, 2026-11-13: «se trascino una flotta sopra la
## pedina di una flotta nemica mi dovrebbe chiedere se attaccarla o meno, come nel gioco originale»). Funzioni pure sullo stato:
## - la conferma serve solo quando l'attacco apre una guerra nuova (pace, alleanza o tregua); con chi e' gia' in guerra con
##   noi (e con i ribelli) l'ordine parte subito, come nell'originale;
## - una flotta lasciata sulla pedina di una flotta altrui, o sulla sua zona di mare, attacca quella flotta
##   (GameCommands.order_naval_attack): anche nella propria zona, anche se alleata (dopo la conferma), e la insegue a fine
##   anno se si sposta entro il raggio delle navi.


## Fazioni con cui l'esercito aprirebbe una guerra entrando in `region_id` (proprietario della provincia e forze presenti, non
## gia' in guerra con noi), nell'ordine di WarProcessor.hostile_factions. Vuoto per i crociati: attaccano solo il proprietario
## del loro bersaglio e hanno un ordine a parte.
static func new_wars_entering(state: GameState, army: Army, region_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if state == null or army == null or army.is_crusade():
		return out
	for f in WarProcessor.hostile_factions(state, army.faction, army.is_fleet, region_id):
		if not state.at_war(army.faction, f) and not out.has(f):
			out.append(f)
	return out


## Fazioni con cui si aprirebbe una guerra attaccando la flotta `target` (la sua, se non c'e' gia' la guerra).
static func new_wars_naval(state: GameState, army: Army, target: Army) -> PackedStringArray:
	var out := PackedStringArray()
	if state == null or army == null or target == null or target.faction == army.faction:
		return out
	if not state.at_war(army.faction, target.faction):
		out.append(target.faction)
	return out


## Le fazioni nuove di un gruppo di eserciti che va in `region_id` (senza doppioni, nell'ordine in cui compaiono).
static func new_wars_group(state: GameState, ids: Array[int], region_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids:
		var army := state.army(id)
		if army == null or army.region == region_id:
			continue
		for f in new_wars_entering(state, army, region_id):
			if not out.has(f):
				out.append(f)
	return out


## Flotta che una flotta di `army` attacca se la si lascia sulla zona di mare `region_id`: la prima (in ordine di id) di
## una fazione in guerra con noi, visibile (`seen`: regioni visibili, vuoto = tutte) e con unita'; la flotta la insegue se si
## sposta. Le flotte neutrali e alleate no (segnalazione di Federico, 2026-11-13): sulla zona e' un movimento normale e si
## convive; per attaccarle si lascia la flotta sulla loro pedina. Null se non ce ne sono o se `army` non e' una flotta.
static func fleet_target_in(state: GameState, army: Army, region_id: String, seen: Dictionary = {}) -> Army:
	if state == null or army == null or not army.is_fleet:
		return null
	if not seen.is_empty() and not seen.has(region_id):
		return null
	for a in state.armies_in(region_id):
		if a.is_fleet and a.faction != army.faction and not a.stacks.is_empty() and state.at_war(army.faction, a.faction):
			return a
	return null


## Domanda della conferma per una flotta: «Attaccare la flotta degli Inglesi (Mare del Nord)?».
static func naval_subject(state: GameState, target: Army) -> String:
	return Lang.t("Attaccare la flotta %s (%s)?") % [CampaignUiText.fprep("di", target.faction), CampaignUiText.region_name(state, target.region)]


## Domanda della conferma per una regione: «Attaccare Normandia?».
static func region_subject(state: GameState, region_id: String) -> String:
	return Lang.t("Attaccare %s?") % CampaignUiText.region_name(state, region_id)


## Testo della conferma: la domanda e una riga per fazione secondo il rapporto con lei (pace, alleanza, tregua), piu'
## l'avvertimento del Papa se tra le fazioni c'e' il Papato. Vuoto se non si apre nessuna guerra (niente conferma).
static func prompt_text(state: GameState, player_id: String, factions: PackedStringArray, subject: String) -> String:
	if factions.is_empty():
		return ""
	var lines := PackedStringArray([subject, ""])
	for f in factions:
		var who := CampaignUiText.fprep("con", f)
		match state.relation(player_id, f):
			GameState.REL_ALLIANCE:
				lines.append(Lang.t("Siete alleati %s: l'attacco rompe l'alleanza ed è una dichiarazione di guerra.") % who)
			GameState.REL_TRUCE:
				lines.append(Lang.t("C'è una tregua %s: l'attacco la rompe ed è una dichiarazione di guerra.") % who)
			_:
				lines.append(Lang.t("Siete in pace %s: l'attacco è una dichiarazione di guerra.") % who)
		if f == GameState.PAPAL:
			lines.append(Lang.t("Attaccare il Papato porta alla scomunica."))
	return "\n".join(lines)


## Messaggio dell'ordine di attacco a una flotta (esito di GameCommands.order_naval_attack).
static func naval_order_text(state: GameState, army: Army, target: Army, result: Dictionary) -> String:
	var whom := Lang.t("la flotta %s") % CampaignUiText.fprep("di", target.faction)
	var where := CampaignUiText.region_name(state, str(result.get("bersaglio", target.region)))
	var text := ""
	if bool(result.get("stessa_zona", false)):
		text = Lang.t("%s attaccherà a fine anno %s, qui in %s.") % [CampaignUiText.army_title(army), whom, where]
	elif int(result.get("anni", 1)) <= 1:
		text = Lang.t("%s: attacco alla flotta %s (%s); se si sposta entro il raggio delle navi, la insegue.") % [
			CampaignUiText.army_title(army), CampaignUiText.fprep("di", target.faction), where]
	else:
		text = Lang.t("%s insegue %s (%s): la raggiunge in circa %d anni, se resta a portata.") % [CampaignUiText.army_title(army), whom, where, int(result["anni"])]
	if bool(result.get("guerra_nuova", false)):
		text += Lang.t(" La guerra si dichiara a fine anno.")
	return text


## Riga della scheda della flotta con un bersaglio («All'attacco della flotta 6 degli Inglesi»), vuota senza bersaglio.
static func target_line(state: GameState, army: Army) -> String:
	if army == null or army.attack_target <= 0:
		return ""
	var target := state.army(army.attack_target)
	if target == null:
		return ""
	return Lang.t("All'attacco della flotta %d %s") % [target.id, CampaignUiText.fprep("di", target.faction)]
