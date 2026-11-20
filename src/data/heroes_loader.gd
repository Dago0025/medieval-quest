class_name HeroesLoader
extends RefCounted
## Legge il file dei nomi, dei re famosi e degli eroi famosi
## (campmap/names/MTW_XL_EARLY_HEROES.TXT; lo startpos lo indica con SetNameData).
##
## Formato: righe di comando `SEZIONE::` seguite, quando serve, dai dati:
## - `SET_FORENAMES:: FN lista reali`, `SET_SURNAMES:: FN lista`, `SET_PRINCESS:: FN lista`
##   e `SET_REBELS:: ID_REGIONE lista_nomi lista_cognomi` stanno su una riga sola;
## - `FAMOUS_KINGS:: FN n` è seguita da n righe `nome, numero, c, d, p, a, ritratto, vnv`;
## - `FAMOUS_HEROES:: FN n` è seguita da n righe
##   `"nome", "cognome", anno, c, d, p, a, l, vnv, TIPO, ID_REGIONE, ritratto`;
## - `ADD_FORENAMES::`, `ADD_SURNAMES::`, `ADD_PRINCESS::` aprono una nuova lista
##   (numerata da 1 per tipo) fatta di righe `"Nome"`.
## I commenti `//` e le righe vuote si ignorano. Il testo è cp1252 con CRLF (TextIO).
## Le intestazioni dichiarano quante voci seguono: il lettore legge tutte le righe fino
## alla sezione successiva e segnala in `errors` le differenze.

const DEFAULT_FILE := "MTW_XL_EARLY_HEROES.TXT"
const KING_COLUMNS := 8
const HERO_COLUMNS := 12


static func load_file(path: String) -> HeroesData:
	var text := TextIO.read_latin1(path)
	var data := load_text(text)
	if text.is_empty():
		data.errors.append("File vuoto o non trovato: %s" % path)
	return data


static func load_text(text: String) -> HeroesData:
	var data := HeroesData.new()
	var section := ""
	var faction := ""
	var names := PackedStringArray()
	var lines := text.replace("\r", "").split("\n")
	for i in lines.size():
		var line_no := i + 1
		var line := ScriptTokenizer.strip_comment(lines[i]).strip_edges()
		if line.is_empty():
			continue
		var sep := line.find("::")
		if sep > 0 and not line.begins_with("\""):
			_flush_names(data, section, names)
			names = PackedStringArray()
			section = line.substr(0, sep).strip_edges().to_upper()
			var args := ScriptTokenizer.split_args(line.substr(sep + 2))
			faction = _start_section(data, section, args, line_no)
			continue
		match section:
			"ADD_FORENAMES", "ADD_SURNAMES", "ADD_PRINCESS":
				names.append(_name_from_line(line, line_no, data))
			"FAMOUS_KINGS":
				_read_king(data, faction, line, line_no)
			"FAMOUS_HEROES":
				_read_hero(data, faction, line, line_no)
			_:
				data.errors.append("Riga %d: dato fuori da una sezione di dati: %s" % [line_no, line])
	_flush_names(data, section, names)
	_check_declared(data)
	return data


## Apre una sezione. Restituisce la fazione per FAMOUS_KINGS e FAMOUS_HEROES, altrimenti "".
static func _start_section(data: HeroesData, section: String, args: PackedStringArray, line_no: int) -> String:
	match section:
		"SET_FORENAMES":
			if _enough(data, section, args, 3, line_no):
				var n := data.names_for(args[0])
				n.forename_list = _int(args[1], "lista dei nomi", line_no, data)
				n.royal_count = _int(args[2], "numero di nomi reali", line_no, data)
		"SET_SURNAMES":
			if _enough(data, section, args, 2, line_no):
				data.names_for(args[0]).surname_list = _int(args[1], "lista dei cognomi", line_no, data)
		"SET_PRINCESS":
			if _enough(data, section, args, 2, line_no):
				data.names_for(args[0]).princess_list = _int(args[1], "lista delle principesse", line_no, data)
		"SET_REBELS":
			if _enough(data, section, args, 3, line_no):
				data.add_rebels(
					args[0],
					_int(args[1], "lista dei nomi", line_no, data),
					_int(args[2], "lista dei cognomi", line_no, data))
		"FAMOUS_KINGS":
			if _enough(data, section, args, 2, line_no):
				var key := HeroesData.norm(args[0])
				var declared := _int(args[1], "numero di re", line_no, data)
				data.declared_kings[key] = int(data.declared_kings.get(key, 0)) + declared
				return key
		"FAMOUS_HEROES":
			if _enough(data, section, args, 2, line_no):
				var key := HeroesData.norm(args[0])
				var declared := _int(args[1], "numero di eroi", line_no, data)
				data.declared_heroes[key] = int(data.declared_heroes.get(key, 0)) + declared
				return key
		"ADD_FORENAMES", "ADD_SURNAMES", "ADD_PRINCESS":
			pass
		_:
			data.errors.append("Riga %d: sezione sconosciuta %s::" % [line_no, section])
	return ""


static func _enough(data: HeroesData, section: String, args: PackedStringArray, needed: int, line_no: int) -> bool:
	if args.size() < needed:
		data.errors.append("Riga %d: %s:: ha %d argomenti invece di %d" % [line_no, section, args.size(), needed])
		return false
	return true


## Chiude una lista di nomi (ADD_*) aggiungendola al modello.
static func _flush_names(data: HeroesData, section: String, names: PackedStringArray) -> void:
	match section:
		"ADD_FORENAMES":
			data.forename_lists.append(names)
		"ADD_SURNAMES":
			data.surname_lists.append(names)
		"ADD_PRINCESS":
			data.princess_lists.append(names)


static func _read_king(data: HeroesData, faction: String, line: String, line_no: int) -> void:
	var f := split_fields(line)
	if f.size() < KING_COLUMNS:
		data.errors.append("Riga %d: re con %d campi invece di %d" % [line_no, f.size(), KING_COLUMNS])
		return
	var k := HeroesData.FamousKing.new(faction)
	k.raw = f
	k.line = line_no
	k.name_index = _int(f[0], "indice del nome", line_no, data)
	k.number = _int(f[1], "numerale", line_no, data)
	k.command = _int(f[2], "comando", line_no, data)
	k.dread = _int(f[3], "terrore", line_no, data)
	k.piety = _int(f[4], "pietà", line_no, data)
	k.acumen = _int(f[5], "acume", line_no, data)
	k.portrait = _int(f[6], "ritratto", line_no, data)
	k.vnv = f[7]
	data.kings.append(k)


static func _read_hero(data: HeroesData, faction: String, line: String, line_no: int) -> void:
	var f := split_fields(line)
	if f.size() < HERO_COLUMNS:
		data.errors.append("Riga %d: eroe con %d campi invece di %d" % [line_no, f.size(), HERO_COLUMNS])
		return
	var h := HeroesData.FamousHero.new(faction)
	h.raw = f
	h.line = line_no
	h.forename = f[0]
	h.surname = f[1]
	h.year = _int(f[2], "anno", line_no, data)
	h.command = _int(f[3], "comando", line_no, data)
	h.dread = _int(f[4], "terrore", line_no, data)
	h.piety = _int(f[5], "pietà", line_no, data)
	h.acumen = _int(f[6], "acume", line_no, data)
	h.loyalty = _int(f[7], "lealtà", line_no, data)
	h.vnv = f[8]
	h.type_name = f[9].to_upper()
	h.region = f[10].to_upper()
	h.portrait = _int(f[11], "ritratto", line_no, data)
	data.heroes.append(h)


## Confronta il numero di voci dichiarato nelle intestazioni con quello letto.
static func _check_declared(data: HeroesData) -> void:
	for key in data.declared_kings:
		var fac: String = key
		var declared: int = data.declared_kings[key]
		var actual := data.kings_of(fac).size()
		if actual != declared:
			data.errors.append("%s: %d re dichiarati, %d letti" % [fac, declared, actual])
	for key in data.declared_heroes:
		var fac: String = key
		var declared: int = data.declared_heroes[key]
		var actual := data.heroes_of(fac).size()
		if actual != declared:
			data.errors.append("%s: %d eroi dichiarati, %d letti" % [fac, declared, actual])


## Nome di una lista: `"Henry"` -> Henry.
static func _name_from_line(line: String, line_no: int, data: HeroesData) -> String:
	if line.length() >= 2 and line.begins_with("\"") and line.ends_with("\""):
		return line.substr(1, line.length() - 2)
	data.errors.append("Riga %d: nome senza virgolette: %s" % [line_no, line])
	return line


## Divide una riga sulle virgole fuori dalle virgolette; toglie le virgolette e
## gli spazi ai bordi di ogni campo.
static func split_fields(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var in_quotes := false
	for i in s.length():
		var c: String = s[i]
		if c == "\"":
			in_quotes = not in_quotes
		elif c == "," and not in_quotes:
			out.append(current.strip_edges())
			current = ""
		else:
			current += c
	out.append(current.strip_edges())
	return out


## Intero di un campo; testo non numerico = 0 con errore.
static func _int(s: String, what: String, line_no: int, data: HeroesData) -> int:
	var t := s.strip_edges()
	if not t.is_valid_int():
		data.errors.append("Riga %d: %s non è un intero: '%s'" % [line_no, what, t])
		return 0
	return t.to_int()
