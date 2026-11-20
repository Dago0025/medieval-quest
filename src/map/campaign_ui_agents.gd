class_name CampaignUiAgents
extends RefCounted
## Testi e scelte dell'interfaccia della fase 5a (agenti, missioni, diplomazia): funzioni pure che leggono lo stato
## e producono stringhe o liste, senza modificarlo. L'interfaccia (scenes/) mostra e invia solo comandi (ADR-003, 008).
##
## - tipi di agente: iniziale e nome italiano, testo del segnalino, descrizione, missione in corso;
## - menu delle missioni: da `GameCommands.mission_options` si scelgono le voci valide per il punto cliccato;
## - pannello della diplomazia: una riga per fazione viva, il giocatore in cima;
## - elenco degli agenti di una provincia e voci di reclutamento.

## Se vero, spie e assassini di altre fazioni (non alleate) non compaiono sulla mappa ne' tra i bersagli: nel gioco
## sono invisibili (catalogo). Spento: la simulazione li espone (mission_options li elenca) e la mappa li mostra.
const HIDE_FOREIGN_INVISIBLE := false

const TYPE_LABELS := {
	"EMISSARY": "Emissario",
	"PRINCESS": "Principessa",
	"SPY": "Spia",
	"ASSASSIN": "Assassino",
	"BISHOP": "Vescovo",
	"CARDINAL": "Cardinale",
	"PRIEST": "Sacerdote",
	"SHAMAN": "Sciamano",
	"ORTHODOX_BISHOP": "Vescovo ortodosso",
	"MULLAH": "Ulema",      ## nomi della versione italiana dell'originale (Loc/Italian/names.txt): Mullah = Ulema,
	"ULAMA": "Imam",        ## Ulama = Imam

	"INQUISITOR": "Inquisitore",
	"GRAND_INQUISITOR": "Gran inquisitore",
}

## Agenti con un tipo condiviso ma un nome proprio nell'originale: lo sciamano dei pagani e' di tipo PRIEST nel file delle
## unita' (aggiunto dalla XL), ma nel gioco si chiama Sciamano.
const UNIT_LABELS := {
	"SHAMAN": "Sciamano",
}

const MISSION_NAMES := {
	"alleanza": "alleanza",
	"tregua": "tregua",
	"matrimonio": "matrimonio",
	"corruzione": "corruzione",
	"sposa_generale": "nozze con un generale",
	"assassinio": "assassinio",
	"processo": "processo",
	"spionaggio": "spionaggio",
	"malcontento": "malcontento",
	"sabotaggio": "sabotaggio",
	"porte": "apertura delle porte",
}

const RELIGION_NAMES := {
	"CATHOLIC": "Cattolica",
	"ORTHODOX": "Ortodossa",
	"MUSLIM": "Musulmana",
	"PAGAN": "Pagana",
	"IMPERIAL": "Culto Imperiale",
}

## Azioni delle voci del menu (campo "azione").
const ACTION_MOVE := "muovi"
const ACTION_MISSION := "missione"
const ACTION_CANCEL := "annulla"
## Esiti di `click_plan` (campo "azione").
const PLAN_NONE := "nessuna"
const PLAN_MOVE := "muovi"
const PLAN_CANCEL := "annulla"
const PLAN_MENU := "menu"


# --- tipi di agente ---------------------------------------------------------------------------------------------


## Nome italiano del tipo ("SPY" -> "Spia"); tipi sconosciuti: l'id leggibile.
static func type_label(type_name: String) -> String:
	var key := type_name.strip_edges().to_upper()
	if TYPE_LABELS.has(key):
		return Lang.t(str(TYPE_LABELS[key]))
	return type_name.replace("_", " ").capitalize()


## Iniziale del segnalino: E emissario, P principessa, S spia, A assassino, V religiosi, I inquisitori.
static func type_letter(type_name: String) -> String:
	var key := type_name.strip_edges().to_upper()
	if key == AgentState.EMISSARY:
		return "E"
	if key == AgentState.PRINCESS:
		return "P"
	if key == AgentState.SPY:
		return "S"
	if key == AgentState.ASSASSIN:
		return "A"
	if key == "INQUISITOR" or key == "GRAND_INQUISITOR":
		return "I"
	if AgentState.is_religious_type(key):
		return "V"
	return "?"


## Valore in cifre ("-" se non ancora assegnato).
static func valour_text(agent: AgentState) -> String:
	if agent.valour < 0:
		return "-"
	return str(agent.valour)


## Testo del segnalino: iniziale e valore ("E3").
static func marker_text(agent: AgentState) -> String:
	return type_letter(agent.type_name) + valour_text(agent)


## Nome italiano dell'agente: quello della sua unita' se ne ha uno proprio (Sciamano), altrimenti quello del tipo.
static func agent_label(agent: AgentState) -> String:
	var own := AurorUnits.text(agent.unit_id, "singolare")   # cappellani degli Auror (18/11/2026)
	if own != "":
		return own
	var key := agent.unit_id.strip_edges().to_upper()
	if UNIT_LABELS.has(key):
		return Lang.t(str(UNIT_LABELS[key]))
	return type_label(agent.type_name)


## "Emissario Giovanni" (senza nome: "Emissario #5").
static func title(agent: AgentState) -> String:
	var label := agent_label(agent)
	if agent.name != "":
		return "%s %s" % [label, agent.name]
	return "%s #%d" % [label, agent.id]


## Nome dell'agente con `agent_id` per i resoconti, se esiste ancora ("Emissario Giovanni"); altrimenti il tipo
## ("Emissario") o, senza nemmeno quello, "Un agente".
static func label_of(state: GameState, agent_id: int, type_name: String = "") -> String:
	var a := state.agent(agent_id)
	if a != null:
		return title(a)
	if type_name != "":
		return type_label(type_name)
	return Lang.t("Un agente")


## Vero se l'agente si mostra al giocatore `viewer`: i propri e gli alleati sempre; gli altri sempre, salvo
## `HIDE_FOREIGN_INVISIBLE` (spie e assassini di fazioni non alleate).
static func is_visible_to(state: GameState, agent: AgentState, viewer: String) -> bool:
	if not HIDE_FOREIGN_INVISIBLE:
		return true
	var key := SimUtil.norm(viewer)
	if agent.faction == key or not agent.is_invisible():
		return true
	return state.relation(key, agent.faction) == GameState.REL_ALLIANCE


## Agenti visibili al giocatore, in ordine di id.
static func visible_agents(state: GameState, viewer: String) -> Array[AgentState]:
	var out: Array[AgentState] = []
	for a in state.agents:
		if is_visible_to(state, a, viewer):
			out.append(a)
	return out


## Agenti visibili presenti in una regione, in ordine di id.
static func visible_agents_in(state: GameState, region_id: String, viewer: String) -> Array[AgentState]:
	var out: Array[AgentState] = []
	for a in state.agents_in(region_id):
		if is_visible_to(state, a, viewer):
			out.append(a)
	return out


## Id delle regioni lungo cui si disegna la freccia di un agente: partenza, (zone della catena via mare), tappe.
## Via mare: partenza, zone della catena, destinazione (la freccia e' tratteggiata). Vuoto senza percorso.
static func route_ids(agent: AgentState) -> PackedStringArray:
	var out := PackedStringArray()
	if agent.path.is_empty():
		return out
	out.append(agent.region)
	if not agent.sea_route.is_empty():
		out.append_array(agent.sea_route)
		out.append(agent.path[agent.path.size() - 1])
		return out
	out.append_array(agent.path)
	return out


# --- descrizione dell'agente ------------------------------------------------------------------------------------


## Nome del bersaglio di una missione (fazione, esercito, personaggio o agente); "?" se non esiste piu'.
static func target_name(state: GameState, kind: String, target: Variant) -> String:
	if kind == AgentMissions.ALLIANCE or kind == AgentMissions.TRUCE or kind == AgentMissions.MARRIAGE:
		return CampaignUiText.faction_name(SimUtil.norm(str(target)))
	if kind == AgentMissions.BRIBE:
		var army := state.army(CampaignUiText.int_of(target))
		if army == null:
			return Lang.t("esercito %s") % str(target)
		return Lang.t("%s di %s") % [CampaignUiText.army_title(army).to_lower(), CampaignUiText.faction_name(army.faction)]
	if kind == AgentMissions.BRIDE:
		var general := state.character(CampaignUiText.int_of(target))
		return general.full_name() if general != null else "?"
	if kind == AgentMissions.UNREST or kind == AgentMissions.SABOTAGE or kind == AgentMissions.GATES:
		return CampaignUiText.region_name(state, str(target))
	if kind == AgentMissions.SPY_ON and typeof(target) == TYPE_DICTIONARY:
		var sd: Dictionary = target
		if str(sd.get("tipo", "")) == AgentMissions.TARGET_ARMY:
			var spied := state.army(CampaignUiText.int_of(sd.get("id")))
			return Lang.t("l'esercito di %s") % CampaignUiText.faction_name(spied.faction) if spied != null else "?"
		return Lang.t("la provincia di %s") % CampaignUiText.region_name(state, str(sd.get("id", "")))
	if typeof(target) == TYPE_DICTIONARY:
		var td: Dictionary = target
		var id := CampaignUiText.int_of(td.get("id"))
		if str(td.get("tipo", "")) == AgentMissions.TARGET_CHARACTER:
			var c := state.character(id)
			return c.full_name() if c != null else "?"
		return label_of(state, id)
	return "?"


## Missione in parole: "Proporre un'alleanza a Beta", "Assassinare Edward I"...
static func mission_verb(state: GameState, kind: String, target: Variant) -> String:
	var who := target_name(state, kind, target)
	if kind == AgentMissions.ALLIANCE:
		return Lang.t("proporre un'alleanza a %s") % who
	if kind == AgentMissions.TRUCE:
		return Lang.t("proporre una tregua a %s") % who
	if kind == AgentMissions.MARRIAGE:
		return Lang.t("proporre un matrimonio a %s") % who
	if kind == AgentMissions.BRIBE:
		return Lang.t("corrompere l'%s") % who
	if kind == AgentMissions.BRIDE:
		return Lang.t("sposare %s") % who
	if kind == AgentMissions.ASSASSINATE:
		return Lang.t("assassinare %s") % who
	if kind == AgentMissions.TRIAL:
		return Lang.t("processare %s") % who
	if kind == AgentMissions.SPY_ON:
		return Lang.t("spiare %s") % who
	if kind == AgentMissions.UNREST:
		return Lang.t("fomentare il malcontento a %s") % who
	if kind == AgentMissions.SABOTAGE:
		return Lang.t("sabotare un edificio a %s") % who
	if kind == AgentMissions.GATES:
		return Lang.t("aprire le porte del castello di %s") % who
	return kind


## Missione in corso dell'agente per il pannello ("Proporre un'alleanza a Beta (Mezza)"); "" se non ne ha.
static func mission_line(state: GameState, agent: AgentState) -> String:
	if not agent.has_mission():
		return ""
	var kind := str(agent.mission.get("tipo", ""))
	var text := mission_verb(state, kind, agent.mission.get("bersaglio"))
	text = text.substr(0, 1).to_upper() + text.substr(1)
	var region_id := str(agent.mission.get("regione", ""))
	if region_id != "":
		text += " (%s)" % CampaignUiText.region_name(state, region_id)
	if bool(agent.mission.get("avvicinamento", false)):
		text += Lang.t(": in avvicinamento")
	else:
		text += Lang.t(": a fine anno")
	return text


## Elenco degli agenti propri per la scheda «Agenti» della finestra dei messaggi (richiesta di Federico del 18/11/2026:
## rintracciare gli agenti come i generali con «Vai all'esercito»). Ogni voce: "id", "titolo" («Emissario Giovanni»),
## "tipo", "regione" (id), "dove" (nome della provincia o del mare), "stelle", "attivita'" (missione, viaggio o «In attesa»).
## Ordine: per tipo (emissari, principesse, spie, assassini, religiosi...), poi per nome.
static func roster(state: GameState, faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in state.agents_of(faction_id):
		var doing := mission_line(state, a)
		if doing == "" and a.destination != "":
			doing = Lang.t("In viaggio verso %s") % CampaignUiText.region_name(state, a.destination)
		elif doing == "" and not a.path.is_empty():
			doing = Lang.t("In marcia verso %s") % CampaignUiText.region_name(state, a.path[a.path.size() - 1])
		if doing == "":
			doing = Lang.t("In attesa")
		out.append({
			"id": a.id,
			"titolo": title(a),
			"tipo": a.type_name,
			"regione": a.region,
			"dove": CampaignUiText.region_name(state, a.region),
			"stelle": valour_stars(a),
			"attivita": doing,
		})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if str(x["tipo"]) != str(y["tipo"]):
			return _type_rank(str(x["tipo"])) < _type_rank(str(y["tipo"]))
		return str(x["titolo"]) < str(y["titolo"]))
	return out


static func _type_rank(type_name: String) -> int:
	var order := ["EMISSARY", "PRINCESS", "SPY", "ASSASSIN", "BISHOP", "IMAM", "INQUISITOR"]
	var i := order.find(type_name)
	return i if i >= 0 else order.size()


## Descrizione dell'agente per il pannello: tipo e nome, fazione, valore, posizione, movimento e missione.
static func describe_agent(state: GameState, agent: AgentState) -> String:
	var lines := PackedStringArray()
	lines.append("%s (%s)" % [title(agent), CampaignUiText.faction_name(agent.faction)])
	lines.append(Lang.t("Valore: %s · posizione: %s") % [valour_text(agent), CampaignUiText.region_name(state, agent.region)])
	if agent.type_name == AgentState.PRINCESS and agent.character_id > 0:
		var c := state.character(agent.character_id)
		if c != null:
			lines.append(Lang.t("Principessa %s, %d anni") % [c.full_name(), c.age(state.year)])
	if agent.type_name == "INQUISITOR" or agent.type_name == "GRAND_INQUISITOR":
		lines.append(Lang.t("Inquisitore: nella provincia propria converte gli eretici; con un processo manda sul rogo un cattolico."))
	if agent.type_name == AgentState.SPY:
		lines.append(Lang.t("Spia: nella provincia propria alza la lealtà e cattura gli agenti nemici; in quella altrui la abbassa."))
	if agent.destination != "":
		var years := AgentTravel.years_to(state, agent, agent.destination)
		var eta := Lang.t(" · arrivo in %s") % years_text(years) if years > 0 else ""
		lines.append(Lang.t("In viaggio verso %s%s") % [CampaignUiText.region_name(state, agent.destination), eta])
	if not agent.path.is_empty():
		var names := PackedStringArray()
		for step in agent.path:
			names.append(CampaignUiText.region_name(state, step))
		lines.append("%s: %s" % [Lang.t("Tappa di quest'anno") if agent.destination != "" else Lang.t("Movimento"), " > ".join(names)])
		if not agent.sea_route.is_empty():
			lines.append(Lang.t("Trasporto via mare, attraverso: %s") % CampaignUiText.chain_names(state, Array(agent.sea_route)))
	var mission := mission_line(state, agent)
	if mission != "":
		lines.append(Lang.t("Missione: %s") % mission)
	elif not AgentMissions.missions_for(agent.type_name).is_empty():
		lines.append(Lang.t("Nessuna missione: clic destro su un bersaglio."))
	return "\n".join(lines)


## Cosa fa ogni tipo di agente (scheda dell'agente, richiesta di Federico del 2026-11-13).
const ROLE_TEXTS := {
	"EMISSARY": "Propone alleanze, tregue e matrimoni ai capi, alle principesse, agli emissari e ai vescovi delle altre fazioni; corrompe eserciti e generali.",
	"PRINCESS": "Sposa un erede o un generale di un'altra fazione (alleanza per matrimonio) oppure un proprio generale poco leale, che diventa membro della famiglia.",
	"SPY": "Nella provincia propria alza la lealtà e cattura gli agenti nemici; in quella altrui la abbassa e, durante un assedio, può aprire le porte.",
	"ASSASSIN": "Uccide generali, principi, capi e agenti stranieri: le probabilità salgono con le sue stelle.",
	"INQUISITOR": "Nella provincia propria converte gli eretici; con un processo manda sul rogo un cattolico, anche della propria fazione.",
	"GRAND_INQUISITOR": "Nella provincia propria converte gli eretici; con un processo manda sul rogo un cattolico, anche della propria fazione.",
}
const RELIGIOUS_TEXT := "Nella provincia in cui si trova converte la popolazione alla sua fede, ogni anno un po' di più secondo il suo valore."


## Righe della scheda dell'agente (sotto il titolo e il ritratto): fazione, valore in stelle, eta' (se nota), ruolo, posizione,
## viaggio, movimento e missione. Funzione pura.
static func sheet_lines(state: GameState, agent: AgentState) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(Lang.t("Valore: %s") % valour_stars(agent, state.rules.agents.max_valour if state.rules != null else 10))
	var age := agent_age(state, agent)
	if age >= 0:
		lines.append(Lang.t("Età: %d anni") % age)
	var role := Lang.t(str(ROLE_TEXTS.get(agent.type_name, RELIGIOUS_TEXT if AgentState.is_religious_type(agent.type_name) else "")))
	if role != "":
		lines.append(role)
	lines.append(Lang.t("Posizione: %s") % CampaignUiText.region_name(state, agent.region))
	lines.append_array(religious_effect_lines(state, agent))
	var text := describe_agent(state, agent).split("\n")
	for i in range(1, text.size()):
		var line := str(text[i])
		if line.begins_with(Lang.t("Valore:")) or line.begins_with(Lang.t("Principessa ")) or line.begins_with(Lang.t("Inquisitore:")) or line.begins_with(Lang.t("Spia:")):
			continue
		lines.append(line)
	return lines


## Effetto di un religioso dove si trova (richiesta di Federico del 18/11/2026): conversione annua verso la sua fede e zelo,
## come li calcola ReligionProcessor. Vuoto per gli altri agenti e per i religiosi in mare.
static func religious_effect_lines(state: GameState, agent: AgentState) -> PackedStringArray:
	var out := PackedStringArray()
	if not agent.is_religious() or state.province(agent.region) == null:
		return out
	var place := CampaignUiText.region_name(state, agent.region)
	var conversion := ReligionProcessor.agent_conversion(state, agent)
	for rel in conversion:
		var points := float(conversion[rel])
		if points > 0.0:
			out.append(Lang.t("Conversione a %s: +%s punti all'anno a %s") % [religion_name(str(rel)), String.num(points, 1).trim_suffix(".0"), place])
	var p := state.province(agent.region)
	var zeal := ReligionProcessor.agent_zeal(state, agent, ReligionProcessor.faction_religion(state, p.owner))
	if zeal != 0:
		out.append(Lang.t("Zelo della provincia: %+d all'anno") % zeal)
	if out.is_empty():
		out.append(Lang.t("Nessuna conversione: l'inquisitore cerca gli eretici, non converte."))
	return out


## Valore come stelle piene e vuote fino al massimo ("★★★☆☆☆☆☆☆☆ (3)"); "-" se non assegnato.
static func valour_stars(agent: AgentState, max_valour: int = 10) -> String:
	if agent.valour < 0:
		return "-"
	var top := maxi(1, max_valour)
	var full := clampi(agent.valour, 0, top)
	return "%s%s (%d)" % ["★".repeat(full), "☆".repeat(top - full), agent.valour]


## Eta' dell'agente: solo per chi e' collegato a un personaggio (le principesse); -1 per gli altri (l'anno della MakeUnit degli
## emissari dello startpos darebbe eta' di pochi anni, poco credibili).
static func agent_age(state: GameState, agent: AgentState) -> int:
	if agent.character_id > 0:
		var c := state.character(agent.character_id)
		if c != null:
			return c.age(state.year)
	return -1


## Tooltip del segnalino: "Emissario Giovanni · valore 3".
static func marker_tooltip(agent: AgentState) -> String:
	return Lang.t("%s · valore %s") % [title(agent), valour_text(agent)]


## Righe dell'elenco degli agenti presenti nella provincia: [{"id", "testo", "mio"}], propri prima, poi gli altri.
static func province_lines(state: GameState, region_id: String, viewer: String) -> Array[Dictionary]:
	var key := SimUtil.norm(viewer)
	var out: Array[Dictionary] = []
	for pass_index in range(2):
		var mine := (pass_index == 0)
		for a in visible_agents_in(state, region_id, viewer):
			if (a.faction == key) != mine:
				continue
			var text := Lang.t("[%s] %s · valore %s") % [type_letter(a.type_name), title(a), valour_text(a)]
			if not mine:
				text += " · %s" % CampaignUiText.faction_name(a.faction)
			elif a.has_mission():
				text += Lang.t(" · in missione")
			out.append({"id": a.id, "testo": text, "mio": mine})
	return out


# --- reclutamento -----------------------------------------------------------------------------------------------


## Vero se l'unita' del file prod e' un agente reclutabile dalla coda (non principesse, crociate, jihad).
static func is_recruitable_agent(unit: UnitType) -> bool:
	return unit.is_agent() and AgentState.is_recruitable_type(unit.type_name)


## Voce di reclutamento di un agente: l'etichetta lo distingue dalle truppe.
static func recruit_text(unit: UnitType, cost: int, years: int) -> String:
	return Lang.t("[Agente] %s · %d fiorini, %d anni") % [CampaignUiText.agent_unit_name(unit.id), cost, years]


## Tooltip della voce di reclutamento: tipo, costo e aiuto sull'uso.
static func recruit_tip(unit: UnitType, base_tip: String) -> String:
	var extra := Lang.t("Agente: %s.") % (Lang.t(str(UNIT_LABELS[unit.id.to_upper()])) if UNIT_LABELS.has(unit.id.to_upper()) else type_label(unit.type_name))
	if unit.type_name == AgentState.EMISSARY:
		extra += Lang.t(" Propone alleanze e tregue e corrompe eserciti.")
	elif unit.type_name == AgentState.SPY:
		extra += Lang.t(" Spia province ed eserciti, fomenta il malcontento, sabota edifici e apre le porte dei castelli assediati; nelle province proprie cattura gli agenti nemici.")
	elif unit.type_name == AgentState.ASSASSIN:
		extra += Lang.t(" Uccide personaggi e agenti nemici.")
	return "%s\n%s" % [base_tip, extra]


## Nome di una voce della coda di reclutamento: gli agenti portano l'etichetta.
static func queue_label(state: GameState, unit_id: String) -> String:
	var unit := state.units.get_unit(unit_id)
	if unit != null and is_recruitable_agent(unit):
		return Lang.t("[Agente] %s") % CampaignUiText.agent_unit_name(unit_id)
	return CampaignUiText.unit_name(unit_id)


# --- menu delle missioni -----------------------------------------------------------------------------------------


## Probabilita' in percentuale ("45%"); da 1 in su "certa".
static func chance_text(p: float) -> String:
	if p >= 0.9999:
		return Lang.t("certa")
	return "%d%%" % roundi(p * 100.0)


## Voci di `GameCommands.mission_options` valide per il punto cliccato con il destro o in cui si lascia la pedina:
## - su una pedina di esercito (`army_id` > 0): la corruzione di quell'esercito, l'assassinio o il processo del suo comandante,
##   le proposte (alleanza, tregua, matrimonio) alla sua fazione e, per una principessa, le nozze con il suo generale;
## - su una pedina di agente (`agent_id` > 0, richiesta di Federico: emissario sopra un emissario): le proposte alla sua
##   fazione, l'assassinio o il processo di quell'agente;
## - su una regione: ogni voce che si svolge li' (`regione`) e le proposte alla fazione che possiede la regione, anche se
##   l'agente le farebbe in una regione confinante.
static func select_options(state: GameState, options: Array, region_id: String, army_id: int, agent_id: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var commander_id := 0
	var army_faction := ""
	if army_id > 0:
		var commander := state.commander_of(army_id)
		if commander != null:
			commander_id = commander.id
		var hit := state.army(army_id)
		if hit != null:
			army_faction = hit.faction
	var agent_faction := ""
	if agent_id > 0:
		var other := state.agent(agent_id)
		if other != null:
			agent_faction = other.faction
	var province := state.province(region_id)
	var owner_id := province.owner if province != null else ""
	for item in options:
		var opt: Dictionary = item
		var kind := str(opt.get("tipo", ""))
		var target: Variant = opt.get("bersaglio")
		var proposal := kind == AgentMissions.ALLIANCE or kind == AgentMissions.TRUCE or kind == AgentMissions.MARRIAGE
		if agent_id > 0:
			if proposal and agent_faction != "" and SimUtil.norm(str(target)) == agent_faction:
				out.append(opt)
			elif (kind == AgentMissions.ASSASSINATE or kind == AgentMissions.TRIAL) and typeof(target) == TYPE_DICTIONARY:
				var ad: Dictionary = target
				if str(ad.get("tipo", "")) == AgentMissions.TARGET_AGENT and CampaignUiText.int_of(ad.get("id")) == agent_id:
					out.append(opt)
			continue
		if army_id > 0:
			if kind == AgentMissions.BRIBE and CampaignUiText.int_of(target) == army_id:
				out.append(opt)
			elif kind == AgentMissions.SPY_ON and typeof(target) == TYPE_DICTIONARY and str((target as Dictionary).get("tipo", "")) == AgentMissions.TARGET_ARMY and CampaignUiText.int_of((target as Dictionary).get("id")) == army_id:
				out.append(opt)
			elif (kind == AgentMissions.ASSASSINATE or kind == AgentMissions.TRIAL) and commander_id > 0 and typeof(target) == TYPE_DICTIONARY:
				var td: Dictionary = target
				if str(td.get("tipo", "")) == AgentMissions.TARGET_CHARACTER and CampaignUiText.int_of(td.get("id")) == commander_id:
					out.append(opt)
			elif proposal and army_faction != "" and SimUtil.norm(str(target)) == army_faction:
				out.append(opt)
			elif kind == AgentMissions.BRIDE and commander_id > 0 and CampaignUiText.int_of(target) == commander_id:
				out.append(opt)
			continue
		if proposal and owner_id != "" and SimUtil.norm(str(target)) == owner_id:
			out.append(opt)
		elif str(opt.get("regione", "")) == region_id:
			out.append(opt)
	return out


## Testo di una voce del menu: azione, bersaglio, probabilita' e prezzo.
static func option_text(state: GameState, opt: Dictionary) -> String:
	var kind := str(opt.get("tipo", ""))
	var target: Variant = opt.get("bersaglio")
	var text := ""
	if kind == AgentMissions.ALLIANCE:
		text = Lang.t("Proponi un'alleanza a %s") % target_name(state, kind, target)
	elif kind == AgentMissions.TRUCE:
		text = Lang.t("Proponi una tregua a %s") % target_name(state, kind, target)
	elif kind == AgentMissions.MARRIAGE:
		text = Lang.t("Proponi un matrimonio a %s") % target_name(state, kind, target)
	elif kind == AgentMissions.BRIBE:
		var army := state.army(CampaignUiText.int_of(target))
		var men := army.men_total() if army != null else 0
		text = Lang.t("Corrompi l'%s (%d uomini)") % [target_name(state, kind, target), men]
	elif kind == AgentMissions.BRIDE:
		var general := state.character(CampaignUiText.int_of(target))
		var place := ""
		if general != null:
			place = " (%s)" % CampaignUiText.character_role_text(state, general)
		text = Lang.t("Concedi la mano a %s%s") % [target_name(state, kind, target), place]
	elif kind == AgentMissions.ASSASSINATE:
		text = Lang.t("Assassina %s") % _victim_text(state, target)
	elif kind == AgentMissions.TRIAL:
		return Lang.t("Processo a %s: %s") % [_trial_victim_text(state, target), chance_text(float(opt.get("probabilita", 0.0)))]
	else:
		text = str(opt.get("etichetta", kind))
	var p := float(opt.get("probabilita", 0.0))
	text += " · %s" % chance_text(p)
	var price := CampaignUiText.int_of(opt.get("prezzo"))
	if kind == AgentMissions.BRIBE:
		text += Lang.t(" · %d fiorini") % price
		if not bool(opt.get("tesoro_sufficiente", true)):
			text += Lang.t(" (tesoro insufficiente)")
	return text


static func _victim_text(state: GameState, target: Variant) -> String:
	if typeof(target) != TYPE_DICTIONARY:
		return "?"
	var td: Dictionary = target
	var id := CampaignUiText.int_of(td.get("id"))
	if str(td.get("tipo", "")) == AgentMissions.TARGET_CHARACTER:
		var c := state.character(id)
		if c == null:
			return "?"
		return Lang.t("%s (%s di %s)") % [c.full_name(), CampaignUiText.character_role_text(state, c), CampaignUiText.faction_name(c.faction)]
	var other := state.agent(id)
	if other == null:
		return "?"
	return Lang.t("%s (valore %s, %s)") % [title(other), valour_text(other), CampaignUiText.faction_name(other.faction)]


## Bersaglio di un processo: «Edward I (capo di Beta)» per un personaggio, «Spia Giovanni (agente, valore 3, Beta)» per un
## agente.
static func _trial_victim_text(state: GameState, target: Variant) -> String:
	if typeof(target) != TYPE_DICTIONARY:
		return "?"
	var td: Dictionary = target
	var id := CampaignUiText.int_of(td.get("id"))
	if str(td.get("tipo", "")) == AgentMissions.TARGET_CHARACTER:
		return _victim_text(state, target)
	var other := state.agent(id)
	if other == null:
		return "?"
	return Lang.t("%s (agente, valore %s, %s)") % [title(other), valour_text(other), CampaignUiText.faction_name(other.faction)]


## Fazione del bersaglio di un assassinio o di un processo ("" se non esiste piu').
static func _target_faction(state: GameState, target: Variant) -> String:
	if typeof(target) != TYPE_DICTIONARY:
		return ""
	var td: Dictionary = target
	var id := CampaignUiText.int_of(td.get("id"))
	if str(td.get("tipo", "")) == AgentMissions.TARGET_CHARACTER:
		var c := state.character(id)
		return c.faction if c != null else ""
	var other := state.agent(id)
	return other.faction if other != null else ""


## Spiegazione di una voce: dove si svolge e, per la corruzione, quando si paga.
static func option_tooltip(state: GameState, agent: AgentState, opt: Dictionary) -> String:
	var kind := str(opt.get("tipo", ""))
	var region_id := str(opt.get("regione", ""))
	var lines := PackedStringArray()
	if region_id != "" and region_id != agent.region:
		lines.append(Lang.t("Si svolge a %s: l'agente ci va prima (un anno di cammino) e agisce a fine anno.") % CampaignUiText.region_name(state, region_id))
	else:
		lines.append(Lang.t("Si svolge a fine anno, a %s.") % CampaignUiText.region_name(state, region_id))
	if kind == AgentMissions.BRIBE:
		lines.append(Lang.t("Il prezzo si paga a fine anno solo se l'esercito accetta; se il tesoro non basta la missione fallisce."))
	if kind == AgentMissions.ASSASSINATE:
		lines.append(Lang.t("Se il colpo fallisce l'assassino può morire."))
	if kind == AgentMissions.TRIAL:
		lines.append(Lang.t("Se il processo riesce il bersaglio muore sul rogo; se fallisce l'inquisitore non rischia nulla."))
		if _target_faction(state, opt.get("bersaglio")) == agent.faction:
			lines.append(Lang.t("Il bersaglio è della tua stessa fazione."))
	if kind == AgentMissions.BRIDE or kind == AgentMissions.MARRIAGE:
		lines.append(Lang.t("La principessa lascia la partita."))
	if kind == AgentMissions.SPY_ON:
		lines.append(Lang.t("Se riesce vedi edifici, guarnigione, lealtà ed eserciti del bersaglio per %d anni.") % state.rules.agents.intel_years)
	if kind == AgentMissions.UNREST:
		lines.append(Lang.t("Se riesce la lealtà della provincia scende di %d per %d anni.") % [AgentMissions.unrest_loyalty(state, agent.valour), state.rules.agents.unrest_years])
	if kind == AgentMissions.SABOTAGE:
		lines.append(Lang.t("Se riesce un edificio (mai il castello) perde un livello; se fallisce la spia può morire."))
	if kind == AgentMissions.GATES:
		lines.append(Lang.t("Se riesce l'assedio finisce subito con la conquista del castello."))
	return "\n".join(lines)


## Voce del menu per una missione.
static func mission_entry(state: GameState, agent: AgentState, opt: Dictionary) -> Dictionary:
	return {
		"azione": ACTION_MISSION,
		"testo": option_text(state, opt),
		"tooltip": option_tooltip(state, agent, opt),
		"tipo": str(opt.get("tipo", "")),
		"bersaglio": opt.get("bersaglio"),
		"regione": str(opt.get("regione", "")),
	}


## Cosa fa il clic destro dell'agente selezionato su una regione (con `army_id` > 0 se ha colpito un segnalino di
## esercito). `options` e' l'elenco di `GameCommands.mission_options`.
## Esito: {"azione": PLAN_*, "regione", "voci"}:
## - PLAN_MOVE: nessuna missione possibile li': ordine di movimento verso la regione;
## - PLAN_CANCEL: clic sulla regione dell'agente senza missioni: annulla movimento o missione;
## - PLAN_MENU: menu con (se la regione e' un'altra) "Muovi", poi le missioni, poi l'eventuale annullamento;
## - PLAN_NONE: nessuna regione.
static func click_plan(state: GameState, agent: AgentState, options: Array, region_id: String, army_id: int = 0, agent_id: int = 0) -> Dictionary:
	var plan := {"azione": PLAN_NONE, "regione": region_id, "voci": []}
	if region_id == "":
		return plan
	var picked := select_options(state, options, region_id, army_id, agent_id)
	var same := region_id == agent.region
	if picked.is_empty():
		plan["azione"] = PLAN_CANCEL if same else PLAN_MOVE
		return plan
	var entries: Array[Dictionary] = []
	if not same:
		entries.append({
			"azione": ACTION_MOVE,
			"testo": Lang.t("Muovi a %s") % CampaignUiText.region_name(state, region_id),
			"tooltip": Lang.t("Un passo all'anno; via mare se la regione non confina e la catena di flotte regge."),
			"tipo": "",
			"bersaglio": null,
			"regione": region_id,
		})
	for opt in picked:
		entries.append(mission_entry(state, agent, opt))
	if same and (not agent.path.is_empty() or agent.has_mission()):
		entries.append({
			"azione": ACTION_CANCEL,
			"testo": Lang.t("Annulla movimento e missione"),
			"tooltip": Lang.t("L'agente resta dov'è senza ordini."),
			"tipo": "",
			"bersaglio": null,
			"regione": region_id,
		})
	plan["azione"] = PLAN_MENU
	plan["voci"] = entries
	return plan


## Messaggio dopo un ordine di missione riuscito (`result` e' l'esito di `GameCommands.order_mission`).
static func ordered_text(state: GameState, agent: AgentState, result: Dictionary) -> String:
	var kind := str(result.get("tipo", ""))
	var region_id := str(result.get("regione", ""))
	var text := Lang.t("%s: %s a %s") % [title(agent), mission_verb(state, kind, result.get("bersaglio")), CampaignUiText.region_name(state, region_id)]
	var extras := PackedStringArray()
	extras.append(Lang.t("riuscita %s") % chance_text(float(result.get("probabilita", 0.0))))
	var price := CampaignUiText.int_of(result.get("prezzo"))
	if kind == AgentMissions.BRIBE:
		extras.append(Lang.t("%d fiorini a fine anno se accetta") % price)
	text += " (%s)." % ", ".join(extras)
	if region_id != agent.region:
		text += Lang.t(" L'agente ci va prima.")
	return text


## Messaggio dopo un ordine di movimento riuscito (`result` e' l'esito di `GameCommands.order_agent_move`).
static func moved_text(state: GameState, agent: AgentState, region_id: String, result: Dictionary) -> String:
	var place := CampaignUiText.region_name(state, region_id)
	if bool(result.get("viaggio", false)):
		var years := int(result.get("anni", 1))
		var first := CampaignUiText.region_name(state, str(result.get("tappa", "")))
		var leg := Lang.t("prima tappa %s") % first
		if bool(result.get("via_mare", false)):
			leg += Lang.t(", via mare")   # la catena intera allungherebbe troppo il messaggio: e' nella descrizione dell'agente
		return Lang.t("%s: in viaggio verso %s, arrivo in %s (%s).") % [title(agent), place, years_text(years), leg]
	if bool(result.get("via_mare", false)):
		return Lang.t("%s: trasporto via mare verso %s (%s).") % [title(agent), place, CampaignUiText.chain_names(state, result.get("catena", []))]
	return Lang.t("%s: movimento verso %s.") % [title(agent), place]


## "1 anno", "3 anni".
static func years_text(years: int) -> String:
	return Lang.t("1 anno") if years == 1 else Lang.t("%d anni") % years


# --- diplomazia -------------------------------------------------------------------------------------------------


## "CATHOLIC" / "REL_CATHOLIC" / "REL_ISLAMIC" -> "Cattolica", "Musulmana"...; "" -> "sconosciuta".
static func religion_name(raw: String) -> String:
	if raw.strip_edges() == "":
		return Lang.t("sconosciuta")
	var key := GameCommands.religion_key(raw)
	if RELIGION_NAMES.has(key):
		return Lang.t(str(RELIGION_NAMES[key]))
	return key.replace("_", " ").capitalize()


## Relazione con il giocatore in parole ("In guerra", "Alleata", "Tregua fino al 1010", "Neutrale").
static func relation_text(relation: String, truce_until: int = 0) -> String:
	if relation == GameState.REL_WAR:
		return Lang.t("In guerra")
	if relation == GameState.REL_ALLIANCE:
		return Lang.t("Alleata")
	if relation == GameState.REL_TRUCE:
		if truce_until > 0:
			return Lang.t("Tregua fino al %d") % truce_until
		return Lang.t("Tregua")
	if relation == GameState.REL_NEUTRAL:
		return Lang.t("Neutrale")
	return relation


## Righe del pannello della diplomazia: il giocatore in cima, poi le altre fazioni vive (non i ribelli) per numero di
## province decrescente e nome. Ogni riga: "fazione", "nome", "giocatore" (bool), "relazione" (REL_* o "" per il
## giocatore), "testo_relazione", "fino_al" (anno della tregua, 0 se non c'e'), "religione", "guerre" (fazioni vive con
## cui e' in guerra, ribelli esclusi, nell'ordine delle righe), "testo_guerre" (i loro nomi, "-" se nessuna), "province".
## Richiesta di Federico (2026-11-18): chi e' in guerra con chi al posto dell'influenza del capo.
static func diplomacy_rows(state: GameState, player_id: String) -> Array[Dictionary]:
	var player := SimUtil.norm(player_id)
	var rows: Array[Dictionary] = []
	for f in state.factions:
		if f.id == GameState.REBEL or not f.alive:
			continue
		var is_me := f.id == player
		var relation := ""
		var until := 0
		var rel_text := Lang.t("Tu")
		if not is_me:
			relation = state.relation(player, f.id)
			if relation == GameState.REL_TRUCE:
				until = state.truce_until(player, f.id)
			rel_text = relation_text(relation, until)
		var campaign_faction := state.campaign.faction(f.id)
		var religion := religion_name(campaign_faction.religion if campaign_faction != null else "")
		rows.append({
			"fazione": f.id,
			"nome": CampaignUiText.faction_name(f.id),
			"giocatore": is_me,
			"relazione": relation,
			"testo_relazione": rel_text,
			"fino_al": until,
			"religione": religion,
			"chiave_religione": GameCommands.religion_key(campaign_faction.religion if campaign_faction != null else ""),
			"guerre": [],
			"testo_guerre": "-",
			"province": state.provinces_of(f.id).size(),
		})
	rows.sort_custom(_row_before)
	for row in rows:
		var enemies: Array = []
		var names := PackedStringArray()
		for other in rows:
			if other["fazione"] != row["fazione"] and state.relation(str(row["fazione"]), str(other["fazione"])) == GameState.REL_WAR:
				enemies.append(other["fazione"])
				names.append(str(other["nome"]))
		row["guerre"] = enemies
		row["testo_guerre"] = ", ".join(names) if not names.is_empty() else "-"
	return rows


static func _row_before(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["giocatore"]) != bool(b["giocatore"]):
		return bool(a["giocatore"])
	if int(a["province"]) != int(b["province"]):
		return int(a["province"]) > int(b["province"])
	return str(a["nome"]) < str(b["nome"])


## Titoli delle colonne del pannello della diplomazia.
static func diplomacy_headers() -> PackedStringArray:
	return PackedStringArray([Lang.t("Fazione"), Lang.t("Relazione"), Lang.t("Religione"), Lang.t("In guerra con"), Lang.t("Province")])


## Celle di una riga, nell'ordine delle colonne.
static func diplomacy_cells(row: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		str(row["nome"]) + (Lang.t(" (tu)") if bool(row["giocatore"]) else ""),
		str(row["testo_relazione"]),
		str(row["religione"]),
		str(row["testo_guerre"]),
		str(row["province"]),
	])
