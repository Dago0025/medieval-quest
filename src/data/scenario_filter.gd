class_name ScenarioFilter
extends RefCounted
## Filtri dello scenario storico (ADR-068) sui file dell'installazione, che contengono la XL 3.0 con la mod Auror applicata
## (`_MOD_BACKUP_ORIG/auror_apply.py` del gioco originale, poi il potenziamento del 7/11 e la caracca del 9/11). Funzioni pure:
## testo in ingresso, testo in uscita; nessun file del gioco viene scritto (ADR-002).
##
## Nello startpos la mod marcava le righe che aggiungeva con `// MOD Auror`: lo scenario storico le toglie, riattiva le righe
## che aveva commentato (fazioni disattivate, capitali di Norvegesi e Svedesi, loro eredi), toglie i blocchi di eserciti e
## flotte («// MOD Auror: esercito N», «flotta N») e aggiunge le righe di `data/scenari/storico/startpos_aggiunte.txt` al posto
## di quelle che la mod aveva cancellato. Per prod e nomi le correzioni stanno nei JSON della stessa cartella, scritti da
## `tools/ricostruisci_storico.py`.

const MARK := "MOD Auror"
const BLOCK_PREFIX := "// MOD Auror:"
const ARMY_SUFFIX := "//FN_DANISH"

static var _active_rx: RegEx = null
static var _heir_rx: RegEx = null
static var _moved_rx: RegEx = null


## Startpos senza la mod Auror, con le righe di `additions` in fondo.
static func startpos(text: String, additions: String = "") -> String:
	_compile()
	var lines := text.replace("\r", "").split("\n")
	# fazioni che la mod aveva disattivato: i loro eredi commentati tornano validi
	var revived := {}
	for line in lines:
		var s := line.strip_edges()
		if is_disabled_line(s):
			var m := _active_rx.search(uncomment(s))
			if m != null:
				revived[m.get_string(1).to_upper()] = true
	var out := PackedStringArray()
	var skipping := false
	for line in lines:
		var s := line.strip_edges()
		if skipping:
			if s.begins_with("MakeUnit") and s.ends_with(ARMY_SUFFIX):
				continue
			skipping = false
		if s.begins_with("//"):
			if s.begins_with(BLOCK_PREFIX) and (s.contains("esercito") or s.contains("flotta")):
				skipping = true
			elif is_disabled_line(s):
				out.append(uncomment(s))
			else:
				var heir := _heir_rx.search(s)
				if heir != null and revived.has(heir.get_string(1).to_upper()):
					out.append(s.substr(2).strip_edges())
				else:
					out.append(line)
			continue
		var at := s.find("//")
		if at >= 0 and s.substr(at).contains(MARK):
			# riga aggiunta o cambiata dalla mod: via; la capitale spostata (High/Late XL) torna dov'era
			var moved := _moved_rx.search(s)
			if moved != null:
				out.append("PlaceLeader:: %s\t\t%s" % [moved.get_string(3), moved.get_string(2)])
			continue
		out.append(line)
	if additions != "":
		out.append_array(additions.replace("\r", "").split("\n"))
	return "\n".join(out)


## Riga che la mod aveva commentato per disattivare una fazione rimasta senza territori (SetActiveFaction, SetStartLeader,
## PlaceLeader con il commento «fazione disattivata» o «regione agli Auror») o le truppe della XL nelle regioni degli Auror
## («truppe tolte»: gli Auror partono con le sole armate d'elite, richiesta di Federico del 23/11/2026, ADR-126).
static func is_disabled_line(s: String) -> bool:
	return s.begins_with("//") and s.contains(MARK) and (s.contains("fazione disattivata") or s.contains("regione agli Auror") \
		or s.contains("truppe tolte"))


## Riga commentata senza le barre iniziali e senza il commento della mod in coda.
static func uncomment(s: String) -> String:
	var code := s.strip_edges().substr(2)
	var at := code.find("//")
	if at >= 0:
		code = code.substr(0, at)
	return code.strip_edges()


## File degli eroi con le righe sostituite: `rows` = coppie [riga della mod, riga originale] confrontate senza spazi ai bordi.
static func heroes(text: String, rows: Array) -> String:
	if rows.is_empty():
		return text
	var table := {}
	for pair in rows:
		if pair is Array and (pair as Array).size() == 2:
			table[str(pair[0]).strip_edges()] = str(pair[1])
	var lines := text.replace("\r", "").split("\n")
	for i in lines.size():
		var key := lines[i].strip_edges()
		if table.has(key):
			lines[i] = str(table[key])
	return "\n".join(lines)


## Quante righe di `rows` si trovano nel testo (per i test e per accorgersi di un file cambiato).
static func heroes_matches(text: String, rows: Array) -> int:
	var present := {}
	for line in text.replace("\r", "").split("\n"):
		present[line.strip_edges()] = true
	var n := 0
	for pair in rows:
		if pair is Array and (pair as Array).size() == 2 and present.has(str(pair[0]).strip_edges()):
			n += 1
	return n


## Celle da correggere di un JSON di data/scenari/storico (`key` = "unita" o "edifici"): nome -> {colonna (int): valore}.
static func read_overrides(path: String, key: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var table: Variant = (parsed as Dictionary).get(key, {})
	if typeof(table) != TYPE_DICTIONARY:
		return out
	for name in table:
		var cells := {}
		var src: Variant = table[name]
		if typeof(src) != TYPE_DICTIONARY:
			continue
		for col in src:
			cells[int(str(col))] = str(src[col])
		out[str(name).strip_edges().to_upper()] = cells
	return out


## Righe sostituite del file degli eroi da eroi.json.
static func read_hero_rows(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var rows: Variant = (parsed as Dictionary).get("righe", [])
	return rows if rows is Array else []


## Copia dei campi di una riga di prod con le celle corrette (`cells`: colonna -> valore).
static func patch_row(fields: PackedStringArray, cells: Dictionary) -> PackedStringArray:
	var out := fields.duplicate()
	for col in cells:
		var c := int(col)
		while out.size() <= c:
			out.append("")
		out[c] = str(cells[col])
	return out


static func _compile() -> void:
	if _active_rx != null:
		return
	_active_rx = RegEx.create_from_string("^\\s*SetActiveFaction::\\s+(FN_\\w+)")
	_heir_rx = RegEx.create_from_string("^//\\s*AddHeir::\\s+(FN_\\w+)")
	_moved_rx = RegEx.create_from_string("^\\s*PlaceLeader::\\s+(\\S+)\\s+(FN_\\w+)\\s*//\\s*MOD Auror \\(era (\\w+)\\)")
