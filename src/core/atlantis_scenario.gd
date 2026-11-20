class_name AtlantisScenario
extends RefCounted
## Modalita' Auror sulla mappa del mondo (ADR-078, richiesta di Federico del 16/11/2026: «al centro dell'Atlantico
## un'isola non troppo grande, divisa in 5 territori, uno al centro che si rifaccia al mito di Atlantide; qui andranno
## spostati gli Auror e dovra' comparire solo se la god mode nascosta viene attivata»).
##
## Gli Auror restano FN_DANISH nei dati (tutte le regole di auror.cfg, le unita' esclusive, Darkos), ma lasciano la
## Scandinavia: Danimarca e Scania vanno ai Danesi dell'originale, che in questa modalita' diventano FN_DANES (scelta di
## Federico: «fazioni storiche»), Norvegia e Svezia a Norvegesi e Svedesi come nello scenario storico.
##
## Testo dello startpos: lo storico (ScenarioFilter) con FN_DANISH rinominato FN_DANES, poi (dopo le righe del mondo e
## dell'isola) le righe degli Auror prese dallo startpos dell'installazione, con le loro quattro regioni portate sull'isola.
## Nomi e prod: i Danesi ricevono i nomi e le unita'/edifici che FN_DANISH aveva nello storico.

const AUROR := "FN_DANISH"
const DANES := "FN_DANES"
## Regioni degli Auror nell'installazione -> territorio dell'isola. La Norvegia, regione natia (ADR-076), va ad Atlantide.
const MOVE := {"ID_NORWAY": "ID_ATLANTIS", "ID_DENMARK": "ID_GADEIRA", "ID_SCANIA": "ID_AMPHERIA", "ID_SWEDEN": "ID_MNESEIA"}
## Territori senza una regione d'origine: ricevono una copia degli edifici di quella indicata.
const COPY_BUILDINGS := {"ID_DIAPREPIA": "ID_SCANIA"}
const ISLAND := ["ID_ATLANTIS", "ID_GADEIRA", "ID_AMPHERIA", "ID_MNESEIA", "ID_DIAPREPIA"]
## Comandi di fazione degli Auror che si copiano dall'installazione cosi' come sono.
const FACTION_COMMANDS := ["DeclareFaction", "SetActiveFaction", "SetReligion", "SetCulture", "SetBehaviour",
	"SetFactionCol", "SetShieldImage", "SetFactionMusic", "SetTreasury", "SetStartLeader", "AddHeir", "AddOffice",
	"GGConquestReward"]

static var _token_rx: RegEx = null


## Startpos storico con i Danesi rinominati FN_DANES (da mettere prima delle righe del mondo).
static func historical_with_danes(historical: String) -> String:
	var out := PackedStringArray()
	for line in historical.replace("\r", "").split("\n"):
		out.append(rename_faction(line, AUROR, DANES))
	return "\n".join(out)


## Righe degli Auror dallo startpos dell'installazione (con la mod), spostate sull'isola (da mettere in fondo).
static func auror_lines(installation: String) -> String:
	var out := PackedStringArray(["// ---- Auror spostati su Atlantide (ADR-078), dalle righe della mod nell'installazione"])
	var copies := {}   # regione d'origine -> righe MakeBuilding da copiare
	for src in COPY_BUILDINGS.values():
		copies[src] = []
	for raw in installation.replace("\r", "").split("\n"):
		var code := ScriptTokenizer.strip_comment(raw).strip_edges()
		if code == "" or not code.contains("::"):
			continue
		var cmd := code.get_slice("::", 0).strip_edges()
		var args := ScriptTokenizer.split_args(code.substr(code.find("::") + 2))
		if args.is_empty():
			continue
		var first := str(args[0]).to_upper()
		if cmd in FACTION_COMMANDS:
			if first == AUROR:
				out.append(code)
			continue
		match cmd:
			"PlaceLeader":
				# la vecchia capitale portata sull'isola: Scenario.apply_home_regions sposta poi il re ad Atlantide (regione
				# natia) e vi copia gli edifici che solo la capitale aveva (cancelleria, palazzi, ammiragliato, cattedrale)
				if args.size() >= 2 and str(args[1]).to_upper() == AUROR:
					out.append("PlaceLeader::\t%s\t%s" % [MOVE.get(first, MOVE["ID_NORWAY"]), AUROR])
			"SetRegionOwner":
				if MOVE.has(first) and args.size() >= 2 and str(args[1]).to_upper() == AUROR:
					out.append("SetRegionOwner::\t%s\t%s" % [MOVE[first], AUROR])
			"MakeBuilding", "MakeUnit":
				if MOVE.has(first):
					var moved := code.replace(str(args[0]), MOVE[first])
					out.append(moved)
					if cmd == "MakeBuilding" and copies.has(first):
						(copies[first] as Array).append(code)
	for dst in COPY_BUILDINGS:
		var src: String = COPY_BUILDINGS[dst]
		out.append("SetRegionOwner::\t%s\t%s" % [dst, AUROR])
		for code in copies[src]:
			out.append((code as String).replace(src, dst).replace(src.to_lower(), dst))
	return "\n".join(out)


## File dei nomi della modalita' Auror: quello dell'installazione piu' le voci di FN_DANISH dello storico come FN_DANES.
static func heroes_text(installation: String, historical: String) -> String:
	var extra := PackedStringArray(["", "// ---- Danesi della modalita' Auror sulla mappa del mondo (ADR-078): nomi dello storico"])
	var copying := false
	for raw in historical.replace("\r", "").split("\n"):
		var code := ScriptTokenizer.strip_comment(raw).strip_edges()
		if code.contains("::") and not code.begins_with("\""):
			var args := ScriptTokenizer.split_args(code.substr(code.find("::") + 2))
			var section := code.get_slice("::", 0).strip_edges().to_upper()
			var mine := not args.is_empty() and str(args[0]).to_upper() == AUROR
			copying = mine and section in ["FAMOUS_KINGS", "FAMOUS_HEROES"]
			if mine and section in ["SET_FORENAMES", "SET_SURNAMES", "SET_PRINCESS", "FAMOUS_KINGS", "FAMOUS_HEROES"]:
				extra.append(rename_faction(code, AUROR, DANES))
			continue
		if copying and code != "":
			extra.append(code)
	return installation.replace("\r", "") + "\n" + "\n".join(extra) + "\n"


## Unita' della modalita' Auror: chi nello storico poteva arruolare FN_DANISH lo puo' anche FN_DANES.
static func add_danes_to_units(table: UnitProdLoader.UnitTable, historical: UnitProdLoader.UnitTable) -> void:
	if table == null or historical == null:
		return
	for u in table.units:
		var h := historical.get_unit(u.id)
		if h == null:
			continue
		if not u.all_factions and (h.all_factions or h.factions.has(AUROR)) and not u.factions.has(DANES):
			u.factions.append(DANES)
		if h.leader_of.has(AUROR) and not u.leader_of.has(DANES):
			u.leader_of.append(DANES)
	table._faction_cache.clear()


## Edifici della modalita' Auror: i livelli che nello storico erano di FN_DANISH valgono anche per FN_DANES.
static func add_danes_to_buildings(table: BuildingProdLoader.BuildingTable, historical: BuildingProdLoader.BuildingTable) -> void:
	if table == null or historical == null:
		return
	var hist_levels := {}
	for fam in historical.families:
		for lv in fam.levels:
			hist_levels[lv.token] = lv
	for fam in table.families:
		for lv in fam.levels:
			var h: Variant = hist_levels.get(lv.token)
			if h == null:
				continue
			if (h.factions as PackedStringArray).has(AUROR) and not lv.factions.has(DANES):
				lv.factions.append(DANES)


## Sostituisce l'id di una fazione come parola intera (FN_DANISH non tocca FN_DANISHX).
static func rename_faction(line: String, from_id: String, to_id: String) -> String:
	if not line.contains(from_id):
		return line
	if _token_rx == null:
		_token_rx = RegEx.create_from_string("\\bFN_DANISH\\b")
	return _token_rx.sub(line, to_id, true) if from_id == AUROR else line.replace(from_id, to_id)
