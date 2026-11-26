class_name SaveGame
extends RefCounted
## Salvataggi in JSON (ADR-008): versione del formato, anno, seme e stato del generatore
## casuale e tutto lo stato dinamico. I dati statici (campagna, tabelle, regole) non si
## salvano: si ricaricano dall'installazione e si passano a `from_dict` / `load_file`.
##
## Un salvataggio ricaricato produce esattamente lo stesso anno successivo dell'originale.
## Seme e stato del generatore sono interi a 64 bit: nel JSON sono testo (i numeri JSON
## sono float e perderebbero precisione).

## Versione 2 (fase 3): aggiunge guerre, assedi e, negli eserciti, castello, ordine d'assalto e
## regione di partenza. La versione 1 si legge ancora: guerre e assedi vuoti.
##
## Versione 3 (fase 4a): aggiunge i personaggi (`personaggi`, `prossimo_personaggio`), i contatori dei numerali
## reali (`contatori_reali`) e gli eroi famosi gia' comparsi (`eroi_apparsi`). Le versioni 1 e 2 si leggono
## ancora: i personaggi si creano come in una partita nuova (`GameSetup.create_characters`, solo per le fazioni
## con `SetStartLeader`). Nomi, re ed eroi famosi (`HeroesData`) non si salvano: vanno passati a `from_dict`.
##
## Versione 4 (fase 4b): le province hanno lealta' (`lealta`), proprietario del calcolo (`lealta_proprietario`),
## ex proprietario (`ex_proprietario`), contatori (`contatori`) e ultimo dettaglio (`ultima_lealta`); i personaggi
## portano nei contatori la pressione sulla lealta' dei generali. Le versioni 1-3 si leggono ancora: la lealta' di ogni
## provincia parte dal suo obiettivo (`ProvinceProcessor.init_loyalty`).
##
## Versione 5 (fase 5a): alleanze (`alleanze`, elenco di chiavi di coppia) e tregue (`tregue`, chiave -> anno di
## scadenza); gli agenti portano valore, nome, percorso, rotta via mare, missione e personaggio collegato.
## Le versioni 1-4 si leggono ancora: nessun trattato; gli agenti senza valore ricevono il valore iniziale
## (`AgentProcessor.default_valour`) e un nome; le principesse dello startpos senza personaggio ne ricevono uno
## (`GameSetup.link_start_princesses`).
##
## Versione 6 (fase 5b): le province portano la composizione religiosa (`religioni`, religione -> percentuale) e lo
## zelo (`zelo`). Le versioni 1-5 si leggono ancora: composizione e zelo della partita nuova
## (`ReligionProcessor.init_religions`), impostati prima del calcolo della lealta' perche' questa dipende dalla religione.
##
## Versione 7 (fase 5c): le fazioni portano la scomunica (`scomunicata`, `anno_scomunica`, `capo_scomunica`, solo se
## scomunicate), gli eserciti il campo crociato (`crociata`, solo per gli eserciti crociati); a livello dello stato
## `avvertimenti` (avvertimenti papali: chiave "CHI>CONTRO" -> {anno, scadenza}), `papa` (id del Papa all'ultimo
## controllo), `anni_senza_papato` e `riemersioni_papato`. Le versioni 1-6 si leggono ancora: nessuna scomunica, nessun
## avvertimento, nessun esercito crociato. La fotografia degli eserciti crociati (`crusade_roster`) non si salva.
##
## Versione 8 (fase 6a): `eventi_6a` (eventi storici accaduti con il loro anno, anno estratto per ciascuno, Peste Nera, Orda d'Oro:
## vedi `EventProcessor.save_data`), per le province gli effetti di un anno (`effetti_temporanei`) e le merci aggiunte da
## eventi storici (`merci_extra`, solo se ci sono). Le versioni 1-7 si leggono ancora: nessun evento accaduto, nessuna Peste Nera
## ne' Orda, nessun effetto temporaneo.
##
## Versione 9 (fase 6b): `vittoria` (esito, anno, classifica, scelta di continuare, anno del dominio: vedi `VictoryState`). Le
## versioni 1-8 si leggono ancora: nessun esito (la partita e' in corso, o finita solo per l'anno finale).
##
## Versione 10 (fase 7b): `proposte` (le proposte dell'IA al giocatore in attesa di risposta: `GameState.pending_proposals`) e
## `prossima_proposta` (contatore degli id). Le versioni 1-9 si leggono ancora: nessuna proposta in attesa.
##
## Versione 11 (riaddestramento): `ordini_riaddestramento` (gli ordini in attesa del fine anno: `GameState.retrain_orders`). Le
## versioni 1-10 si leggono ancora: nessun ordine.
##
## Versione 13 (mercenari, fase 8d): `mercenari` (compagnie in attesa d'ingaggio per provincia: `GameState.mercenaries`) e, nelle
## pile, `mercenario` (solo se vero). Le versioni 1-12 si leggono ancora: nessuna compagnia, nessuna pila mercenaria.
const VERSION := 13
const SAVE_DIR := "user://salvataggi"


## Stato dinamico come Dictionary (solo tipi JSON).
static func to_dict(state: GameState) -> Dictionary:
	var faction_list: Array = []
	for f in state.factions:
		faction_list.append(f.to_dict())
	var province_list: Array = []
	for p in state.provinces:
		province_list.append(_plain(p.to_dict()))   # religioni: 100.0 -> 100, andata e ritorno JSON stabile
	var army_list: Array = []
	for a in state.armies:
		army_list.append(a.to_dict())
	var agent_list: Array = []
	for ag in state.agents:
		agent_list.append(ag.to_dict())
	var event_list: Array = []
	for e in state.events:
		event_list.append(_plain(e.duplicate()))
	var war_list: Array = state.wars.keys()
	war_list.sort()
	var siege_list: Array = []
	for siege in state.sieges_in_order():
		siege_list.append(siege.to_dict())
	var character_list: Array = []
	for c in state.characters:
		character_list.append(c.to_dict())
	var done_list: Array = state.heroes_done.keys()
	done_list.sort()
	var alliance_list: Array = state.alliances.keys()
	alliance_list.sort()
	var out := {
		"versione": VERSION,
		"anno": state.year,
		"anno_finale": state.final_year,
		"epoca": state.era,
		"seme": str(state.seed_value),
		"rng_stato": str(state.rng.state),
		"prossimo_esercito": state.next_army_id,
		"prossimo_agente": state.next_agent_id,
		"fazioni": faction_list,
		"province": province_list,
		"eserciti": army_list,
		"agenti": agent_list,
		"eventi": event_list,
		"guerre": war_list,
		"guerre_svolta": state.wars.duplicate(),
		"assedi": siege_list,
		"errori_avvio": Array(state.setup_errors),
		"personaggi": character_list,
		"prossimo_personaggio": state.next_character_id,
		"contatori_reali": state.royal_counters.duplicate(true),
		"eroi_apparsi": done_list,
		"alleanze": alliance_list,
		"tregue": state.truces.duplicate(),
		"avvertimenti": _plain(state.papal_warnings.duplicate(true)),
		"papa": state.papal_leader,
		"anni_senza_papato": state.papacy_dead_years,
		"contatto_americhe": state.americas_contact_year,
		"riemersioni_papato": state.papacy_reemergences,
		"eventi_6a": _plain(EventProcessor.save_data(state)),
		"vittoria": _plain(state.victory.to_dict()),
		"proposte": _plain(state.pending_proposals.duplicate(true)),
		"prossima_proposta": state.next_proposal_id,
		"ordini_riaddestramento": _plain(state.retrain_orders.duplicate(true)),
		"mercenari": _plain(state.mercenaries.duplicate(true)),
	}
	if not state.prisoners.is_empty():
		out["prigionieri"] = _plain(state.prisoners.duplicate(true))   # ADR-073: senza la voce = nessun prigioniero
	if state.next_prisoner_id > 1:
		out["prossimo_prigioniero"] = state.next_prisoner_id
	if state.scenario != "":
		out["scenario"] = state.scenario   # ADR-068: senza la voce = salvataggio Auror (di prima)
	out["mappa"] = WorldMap.map_id()   # ADR-077: senza la voce = mappa d'Europa originale
	return out


## Copia del valore in cui i decimali interi diventano interi (182.0 -> 182) e gli altri sono arrotondati a 1e-9: il JSON non distingue i due
## casi e dopo il caricamento i numeri senza decimali tornano interi, quindi l'andata e ritorno resta stabile.
static func _plain(value: Variant) -> Variant:
	if value is float:
		var f: float = value
		if is_finite(f) and f == floorf(f) and absf(f) < 1.0e15:
			return int(f)
		# i decimali lunghi (per esempio le probabilita' negli eventi) perdono cifre nel testo JSON: arrotondati a 1e-9
		# il valore riletto e' identico e l'andata e ritorno resta stabile
		var snapped := snappedf(f, 1.0e-9)
		if snapped == floorf(snapped) and absf(snapped) < 1.0e15:
			return int(snapped)
		return snapped
	if value is Dictionary:
		var src: Dictionary = value
		var out := {}
		for k in src:
			out[k] = _plain(src[k])
		return out
	if value is Array:
		var src_list: Array = value
		var out_list: Array = []
		for item in src_list:
			out_list.append(_plain(item))
		return out_list
	return value


## Testo JSON dello stato (chiavi ordinate: due stati uguali danno lo stesso testo).
static func to_json(state: GameState) -> String:
	return JSON.stringify(to_dict(state), "\t", true)


## Ricostruisce lo stato da un Dictionary. Restituisce {"ok", "errore", "stato"}.
static func from_dict(data: Dictionary, campaign: CampaignData, units: UnitProdLoader.UnitTable, buildings: BuildingProdLoader.BuildingTable, rules: Rules, heroes: HeroesData = null) -> Dictionary:
	var d: Dictionary = SimUtil.fix_numbers(data)
	var version := int(d.get("versione", 0))
	if version < 1 or version > VERSION:
		return _fail(Lang.t("Versione del salvataggio non supportata: %d (attese da 1 a %d)") % [version, VERSION])
	# ADR-077: province, posizioni e confini cambiano tra la mappa d'Europa e quella del mondo
	var saved_map := str(d.get("mappa", "europa"))
	if saved_map != WorldMap.map_id():
		return _fail(Lang.t("Salvataggio della mappa d'Europa: non si puo' caricare sulla mappa del mondo.") if saved_map == "europa"
			else Lang.t("Salvataggio di un'altra mappa (%s).") % saved_map)
	var state := GameState.new(campaign, units, buildings, rules)
	state.heroes = heroes
	state.year = int(d.get("anno", campaign.start_year))
	state.final_year = int(d.get("anno_finale", rules.final_year))
	state.era = str(d.get("epoca", "EARLY"))
	state.seed_value = int(str(d.get("seme", "0")))
	state.scenario = str(d.get("scenario", ""))
	# ADR-073: prigionieri in attesa (assenti nei salvataggi di prima)
	var prisoner_list: Variant = d.get("prigionieri", [])
	if typeof(prisoner_list) == TYPE_ARRAY:
		for item in prisoner_list:
			if typeof(item) == TYPE_DICTIONARY:
				state.prisoners.append(PrisonerProcessor.normalize(item))
	state.next_prisoner_id = maxi(1, int(d.get("prossimo_prigioniero", 1)))
	for existing in state.prisoners:
		state.next_prisoner_id = maxi(state.next_prisoner_id, int(existing["id"]) + 1)
	state.rng.seed = state.seed_value
	state.rng.state = int(str(d.get("rng_stato", "0")))
	state.next_army_id = int(d.get("prossimo_esercito", 1))
	state.next_agent_id = int(d.get("prossimo_agente", 1))
	state.setup_errors = SimUtil.strings_from(d.get("errori_avvio", []))
	var faction_list: Array = d.get("fazioni", [])
	for item in faction_list:
		var fd: Dictionary = item
		var f := FactionState.from_dict(fd)
		if campaign.faction(f.id) == null:
			return _fail(Lang.t("Fazione sconosciuta nel salvataggio: %s") % f.id)
		state.add_faction(f)
	var province_list: Array = d.get("province", [])
	for item in province_list:
		var pd: Dictionary = item
		var p := ProvinceState.from_dict(pd)
		if campaign.region(p.id) == null:
			return _fail(Lang.t("Provincia sconosciuta nel salvataggio: %s") % p.id)
		state.add_province(p)
	var army_list: Array = d.get("eserciti", [])
	for item in army_list:
		var ad: Dictionary = item
		var a := Army.from_dict(ad)
		if campaign.region(a.region) == null and WorldMap.available():
			a.region = WorldMap.merged_id(a.region)   # flotta in una zona del Mediterraneo unita a un'altra (16/11/2026)
		if campaign.region(a.region) == null:
			return _fail(Lang.t("Esercito %d in una regione sconosciuta: %s") % [a.id, a.region])
		state.armies.append(a)
	# versione 6: religioni e zelo; prima non ci sono e si imposta la composizione della partita nuova
	# (prima della lealta': la penalita' di religione ne dipende)
	if version < 6:
		ReligionProcessor.init_religions(state)
	var agent_list: Array = d.get("agenti", [])
	for item in agent_list:
		var gd: Dictionary = item
		var loaded_agent := AgentState.from_dict(gd)
		if version < 5:
			# prima della fase 5a nessuna principessa era collegata a un personaggio: si ricollegano dopo
			loaded_agent.character_id = 0
		state.agents.append(loaded_agent)
	var event_list: Array = d.get("eventi", [])
	for item in event_list:
		var ed: Dictionary = item
		state.events.append(ed.duplicate())
	# versione 2: guerre e assedi (nella versione 1 non ci sono: partita senza guerre ne' assedi)
	# versione 12: anno dell'ultima svolta di ogni guerra; prima non c'e' e vale l'anno del salvataggio
	var war_list: Array = d.get("guerre", [])
	var war_turns: Dictionary = d.get("guerre_svolta", {})
	for item in war_list:
		state.wars[str(item)] = int(war_turns.get(str(item), state.year))
	var siege_list: Array = d.get("assedi", [])
	for item in siege_list:
		var sd: Dictionary = item
		var siege := SiegeState.from_dict(sd)
		if campaign.region(siege.region) == null:
			return _fail(Lang.t("Assedio in una regione sconosciuta nel salvataggio: %s") % siege.region)
		state.sieges[siege.region] = siege
	# versione 3: personaggi; prima non ci sono e si creano come in una partita nuova
	if version >= 3:
		var character_list: Array = d.get("personaggi", [])
		for item in character_list:
			var cd: Dictionary = item
			state.add_character(Character.from_dict(cd))
		state.next_character_id = maxi(state.next_character_id, int(d.get("prossimo_personaggio", 1)))
		var counters: Dictionary = d.get("contatori_reali", {})
		state.royal_counters = counters
		var done_list: Array = d.get("eroi_apparsi", [])
		for item in done_list:
			state.heroes_done[str(item)] = true
	else:
		GameSetup.create_characters(state, heroes)
	# versione 4: lealta' delle province; prima non c'e' e parte dall'obiettivo
	if version < 4:
		ProvinceProcessor.init_loyalty(state)
	# versione 5: trattati (prima nessuno), valore e nome degli agenti, principesse collegate ai personaggi
	if version >= 5:
		var alliance_list: Array = d.get("alleanze", [])
		for item in alliance_list:
			state.alliances[str(item)] = true
		var truce_data: Dictionary = d.get("tregue", {})
		for key in truce_data:
			state.truces[str(key)] = int(truce_data[key])
	else:
		GameSetup.link_start_princesses(state)
	# versione 7: avvertimenti papali, Papa, riemersioni; prima nessuna scomunica, nessun avvertimento, nessuna crociata
	if version >= 7:
		var warning_data: Dictionary = d.get("avvertimenti", {})
		for key in warning_data:
			var w: Variant = warning_data[key]
			if typeof(w) == TYPE_DICTIONARY:
				var wd: Dictionary = w
				state.papal_warnings[str(key)] = {"anno": int(wd.get("anno", 0)), "scadenza": int(wd.get("scadenza", 0))}
		state.papal_leader = int(d.get("papa", 0))
		state.papacy_dead_years = int(d.get("anni_senza_papato", 0))
		state.americas_contact_year = int(d.get("contatto_americhe", 0))
		state.papacy_reemergences = int(d.get("riemersioni_papato", 0))
	else:
		for f in state.factions:
			f.excommunicated = false
			f.excommunication_year = 0
			f.excommunication_leader = 0
		for a in state.armies:
			a.crusade = {}
	# versione 8: eventi storici accaduti, Peste Nera, Orda d'Oro; prima nessun evento accaduto
	if version >= 8:
		EventProcessor.load_data(state, d.get("eventi_6a", {}))
	# versione 9: esito della partita; prima nessun esito
	if version >= 9:
		var victory_data: Dictionary = d.get("vittoria", {})
		state.victory = VictoryState.from_dict(victory_data)
	# versione 10: proposte dell'IA al giocatore in attesa; prima nessuna
	if version >= 10:
		var proposal_list: Array = d.get("proposte", [])
		for item in proposal_list:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var pd: Dictionary = item
			state.pending_proposals.append({
				"id": int(pd.get("id", 0)),
				"da": str(pd.get("da", "")),
				"a": str(pd.get("a", "")),
				"tipo": str(pd.get("tipo", "")),
				"agente": int(pd.get("agente", 0)),
				"regione": str(pd.get("regione", "")),
				"anno": int(pd.get("anno", 0)),
				"scadenza": int(pd.get("scadenza", 0)),
			})
		state.next_proposal_id = maxi(1, int(d.get("prossima_proposta", 1)))
		for existing in state.pending_proposals:
			state.next_proposal_id = maxi(state.next_proposal_id, int(existing["id"]) + 1)
	# versione 13: compagnie di mercenari; prima nessuna
	if version >= 13:
		var mercs: Variant = d.get("mercenari", {})
		if typeof(mercs) == TYPE_DICTIONARY:
			for pid in (mercs as Dictionary).keys():
				var list: Array = []
				for c in (mercs as Dictionary)[pid]:
					if typeof(c) != TYPE_DICTIONARY:
						continue
					var cd: Dictionary = c
					list.append({"unita": str(cd.get("unita", "")), "uomini": int(cd.get("uomini", 0)), "valore": int(cd.get("valore", 0)),
						"anni": int(cd.get("anni", 0))})
				if not list.is_empty():
					state.mercenaries[str(pid)] = list
	# versione 11: ordini di riaddestramento; prima nessuno
	if version >= 11:
		var retrain_list: Array = d.get("ordini_riaddestramento", [])
		for item in retrain_list:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var rd: Dictionary = item
			state.retrain_orders.append({
				"esercito": int(rd.get("esercito", 0)),
				"fazione": str(rd.get("fazione", "")),
				"provincia": str(rd.get("provincia", "")),
				"pila": int(rd.get("pila", 0)),
				"unita": str(rd.get("unita", "")),
				"uomini": int(rd.get("uomini", 0)),
				"costo": int(rd.get("costo", 0)),
				"anno": int(rd.get("anno", 0)),
			})
			if bool(rd.get("ripristino", false)):
				state.retrain_orders[state.retrain_orders.size() - 1]["ripristino"] = true   # ADR-046, facoltativo
	for ag in state.agents:
		if ag.valour < 0:
			ag.valour = AgentProcessor.default_valour(state, ag)
	AgentProcessor.name_agents(state)
	AgentProcessor.apply_faction_minimum(state)   # 2026-11-13: agenti degli Auror al massimo anche nelle partite salvate
	TroopUpgrades.apply_faction_minimum(state)   # 2026-11-13: le pile salvate prima di armi e armature prendono il livello della fazione
	Admirals.ensure(state)   # ADR-056: le flotte dei salvataggi di prima ricevono un ammiraglio
	_remap_merged_seas(state)   # 16/11/2026: flotte e rotte nelle zone del Mediterraneo unite ad altre
	CharacterFactory.rename_reserved_heirs(state)   # 16/11/2026: gli eredi Darkos degli Auror prendono un nome proprio
	return {"ok": true, "errore": "", "stato": state}


## Scrive lo stato in user://salvataggi/<nome>.json. Restituisce {"ok", "errore", "percorso"}.
static func save_file(state: GameState, save_name: String) -> Dictionary:
	if not is_valid_name(save_name):
		return {"ok": false, "errore": Lang.t("Nome di salvataggio non valido: %s (solo lettere, cifre, - e _)") % save_name, "percorso": ""}
	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK:
		return {"ok": false, "errore": Lang.t("Cartella %s non creata (errore %d)") % [SAVE_DIR, err], "percorso": ""}
	var path := path_of(save_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errore": Lang.t("File %s non scrivibile (errore %d)") % [path, FileAccess.get_open_error()], "percorso": path}
	file.store_string(to_json(state))
	file.close()
	return {"ok": true, "errore": "", "percorso": path}


## Legge un salvataggio. Restituisce {"ok", "errore", "stato"}.
static func load_file(save_name: String, campaign: CampaignData, units: UnitProdLoader.UnitTable, buildings: BuildingProdLoader.BuildingTable, rules: Rules, heroes: HeroesData = null) -> Dictionary:
	if not is_valid_name(save_name):
		return _fail(Lang.t("Nome di salvataggio non valido: %s") % save_name)
	var path := path_of(save_name)
	if not FileAccess.file_exists(path):
		return _fail(Lang.t("Salvataggio non trovato: %s") % path)
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail(Lang.t("Salvataggio non leggibile (JSON non valido): %s") % path)
	var data: Dictionary = parsed
	return from_dict(data, campaign, units, buildings, rules, heroes)


## Elimina un salvataggio (usato dai test per ripulire). Vero se il file e' stato rimosso.
static func delete_file(save_name: String) -> bool:
	if not is_valid_name(save_name):
		return false
	return DirAccess.remove_absolute(path_of(save_name)) == OK


## Nomi dei salvataggi presenti, in ordine alfabetico.
static func list_saves() -> PackedStringArray:
	var out := PackedStringArray()
	for file_name in DirAccess.get_files_at(SAVE_DIR):
		if file_name.get_extension() == "json":
			out.append(file_name.get_basename())
	out.sort()
	return out


## Riepilogo di un salvataggio per i menu (fase 8c): {"nome", "anno", "fazione" (id del giocatore, "" se non c'e'),
## "versione", "scenario" ("auror" o "storico", ADR-068), "modificato" (secondi Unix)}; vuoto se il file manca o non si legge.
static func summary(save_name: String) -> Dictionary:
	if not is_valid_name(save_name):
		return {}
	var path := path_of(save_name)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed
	var player := ""
	for f in data.get("fazioni", []):
		if typeof(f) == TYPE_DICTIONARY and bool((f as Dictionary).get("giocatore", false)):
			player = str((f as Dictionary).get("id", ""))
	return {
		"nome": save_name,
		"anno": int(data.get("anno", 0)),
		"fazione": player,
		"versione": int(data.get("versione", 0)),
		"scenario": scenario_of(data),
		"modificato": FileAccess.get_modified_time(path),
	}


## Scenario di un salvataggio (ADR-068): "storico" o "auror"; i salvataggi senza la voce sono di prima, tutti Auror.
static func scenario_of(data: Dictionary) -> String:
	return Scenario.STORICO if str(data.get("scenario", "")) == Scenario.STORICO else Scenario.AUROR


## Riepiloghi di tutti i salvataggi leggibili, dal piu' recente.
static func list_summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for save_name in list_saves():
		var s := summary(save_name)
		if not s.is_empty():
			out.append(s)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["modificato"]) > int(b["modificato"]))
	return out


## Nome di file valido ricavato da un testo libero: spazi e simboli diventano «_», lettere accentate senza accento.
static func safe_name(text: String) -> String:
	var plain := text.strip_edges()
	var swaps := {"à": "a", "è": "e", "é": "e", "ì": "i", "ò": "o", "ù": "u", "'": "_", " ": "_"}
	for k in swaps:
		plain = plain.replace(k, swaps[k])
	var out := ""
	for i in plain.length():
		var c := plain.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 45 or c == 95
		out += plain[i] if ok else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_").left(48)


static func path_of(save_name: String) -> String:
	return SAVE_DIR.path_join(save_name + ".json")


static func is_valid_name(save_name: String) -> bool:
	if save_name.is_empty():
		return false
	for i in save_name.length():
		var c := save_name.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 45 or c == 95
		if not ok:
			return false
	return true


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "errore": message, "stato": null}


## Salvataggi della mappa del mondo di prima dell'unione delle zone del Mediterraneo (16/11/2026, data/mappa_mondo/mari_uniti.cfg):
## flotte e agenti nelle zone tolte passano nella zona che le assorbe; percorsi e rotte che le toccano si annullano.
static func _remap_merged_seas(state: GameState) -> void:
	if not WorldMap.available():
		return
	var aliases := {}
	for id in WorldMap.merged_seas():
		if state.campaign.region(str(id)) == null:   # solo le zone che nella mappa della partita non ci sono piu'
			aliases[id] = WorldMap.merged_id(str(id))
	if aliases.is_empty():
		return
	for a in state.armies:
		a.region = str(aliases.get(a.region, a.region))
		if _touches(a.path, aliases) or _touches(a.sea_route, aliases):
			a.path = PackedStringArray()
			a.sea_route = PackedStringArray()
	for ag in state.agents:
		ag.region = str(aliases.get(ag.region, ag.region))
		if _touches(ag.path, aliases) or _touches(ag.sea_route, aliases):
			ag.path = PackedStringArray()
			ag.sea_route = PackedStringArray()


static func _touches(ids: PackedStringArray, aliases: Dictionary) -> bool:
	for id in ids:
		if aliases.has(id):
			return true
	return false
