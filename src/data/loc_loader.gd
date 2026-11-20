class_name LocLoader
extends RefCounted
## Legge i file di testi localizzati (Loc/Italian/*.txt e i *_SPECIFIC.TXT).
##
## Formato reale (verificato su tutti i file di Loc/Italian):
## - `["etichetta"]` seguita da `{"testo"}`: voce semplice, etichetta -> testo.
##   Etichetta e testo possono stare sulla stessa riga o su righe diverse.
## - `@["nome"]` seguita da più `@{"testo"}`: ARRAY a indice. Gli elementi si
##   leggono per posizione (0 = primo) e le posizioni corrispondono all'ordine
##   di dichiarazione di fazioni, regioni ecc. (es. `country_xzy`: 0 = "Region Zero",
##   poi le 107 regioni di terra e le 36 di mare). Vanno in `LocTable.arrays`.
## - `//` apre un commento fino a fine riga (fuori dai testi). Parole nude come
##   `SetShowTransOn` sono direttive e si ignorano.
## - Un testo può andare a capo (resta il carattere di a capo) e può contenere
##   virgolette: finisce al primo `"}`.
## - La sequenza `\n` scritta nel testo diventa un a capo (`unescape`).
## - File in cp1252 con CRLF (si legge con TextIO).
##
## Tolleranze per errori presenti nei file reali (tutte segnalate in `warnings`):
## - etichetta chiusa con `}` invece di `]` (`["Barbary Coast"}`);
## - testo senza virgolette finali che termina con `}` a fine riga
##   (`{"Kilij Arslan}`, `{"Cydwladwr" (Compatriot)}`).
## Etichette ripetute: vince l'ULTIMA definizione (ipotesi: il gioco potrebbe
## tenere la prima); i casi con testo diverso finiscono in `conflicts`.


## Contenuto di un file di testi.
class LocTable:
	var entries := {}                   ## etichetta -> testo
	var arrays := {}                    ## etichetta -> PackedStringArray
	var duplicates := 0                 ## etichette (voci o array) ridefinite
	var conflicts := PackedStringArray()   ## voci ridefinite con testo diverso
	var warnings := PackedStringArray()
	var errors := PackedStringArray()
	var ignored_words := {}             ## direttive nude -> conteggio
	var _lower := {}                    ## indice minuscolo -> etichetta, creato al bisogno

	func has_text(key: String) -> bool:
		return entries.has(key)

	## Testo di una voce, `fallback` se manca.
	func text(key: String, fallback: String = "") -> String:
		return String(entries.get(key, fallback))

	## Come text(), ma se la chiave esatta manca prova senza distinguere maiuscole.
	func find_text(key: String, fallback: String = "") -> String:
		if entries.has(key):
			return String(entries[key])
		if _lower.is_empty():
			for k in entries.keys():
				var low := String(k).to_lower()
				if not _lower.has(low):
					_lower[low] = k
		var found: Variant = _lower.get(key.to_lower())
		if found == null:
			return fallback
		return String(entries[found])

	func has_array(label: String) -> bool:
		return arrays.has(label)

	## Array a indice; vuoto se l'etichetta non esiste.
	func array(label: String) -> PackedStringArray:
		if arrays.has(label):
			return arrays[label]
		return PackedStringArray()

	## Elemento `i` (da 0) di un array, `fallback` se fuori limite.
	func array_item(label: String, i: int, fallback: String = "") -> String:
		var a := array(label)
		if i < 0 or i >= a.size():
			return fallback
		return a[i]


static func load_file(path: String, unescape: bool = true) -> LocTable:
	return load_text(TextIO.read_latin1(path), unescape)


## Solo il dizionario etichetta -> testo (senza gli array).
static func load_dictionary(path: String) -> Dictionary:
	return load_file(path).entries


static func load_text(text: String, unescape: bool = true) -> LocTable:
	var p := Parser.new(text, unescape)
	p.run()
	return p.table


## Scansione del testo. Tiene lo stato dell'etichetta corrente.
class Parser:
	var table := LocTable.new()
	var _s: String
	var _n: int
	var _i := 0
	var _unescape: bool
	var _label := ""
	var _label_is_array := false
	var _awaiting := false              ## etichetta semplice in attesa del testo
	var _items := PackedStringArray()   ## elementi dell'array in corso

	func _init(text: String, unescape: bool) -> void:
		_s = text.replace("\r", "")
		_n = _s.length()
		_unescape = unescape

	func run() -> void:
		while _i < _n:
			var c: int = _s.unicode_at(_i)
			if c == 32 or c == 9 or c == 10:
				_i += 1
				continue
			if c == 47 and _i + 1 < _n and _s.unicode_at(_i + 1) == 47:
				var eol := _s.find("\n", _i)
				if eol < 0:
					break
				_i = eol
				continue
			var is_array := false
			if c == 64 and _i + 1 < _n:
				var nxt: int = _s.unicode_at(_i + 1)
				if nxt == 91 or nxt == 123:
					is_array = true
					_i += 1
					c = nxt
			if c == 91:
				_read_label(is_array)
			elif c == 123:
				if not _read_value(is_array):
					break
			else:
				_skip_word()
		_flush_array()

	func _line_of(pos: int) -> int:
		return _s.substr(0, pos).count("\n") + 1

	func _skip_blanks(pos: int) -> int:
		while pos < _n:
			var c: int = _s.unicode_at(pos)
			if c != 32 and c != 9:
				break
			pos += 1
		return pos

	func _skip_word() -> void:
		var j := _i
		while j < _n:
			var c: int = _s.unicode_at(j)
			if c == 32 or c == 9 or c == 10:
				break
			j += 1
		var word := _s.substr(_i, j - _i)
		if word.begins_with("SetShowTrans"):
			table.ignored_words[word] = int(table.ignored_words.get(word, 0)) + 1
		else:
			table.errors.append("Riga %d: testo fuori da etichette: %s" % [_line_of(_i), word])
		_i = j

	func _read_label(is_array: bool) -> void:
		var q := _skip_blanks(_i + 1)
		if q >= _n or _s.unicode_at(q) != 34:
			table.errors.append("Riga %d: etichetta senza virgolette" % _line_of(_i))
			_i += 1
			return
		var e := _s.find("\"", q + 1)
		if e < 0:
			table.errors.append("Riga %d: etichetta non chiusa" % _line_of(_i))
			_i = _n
			return
		var lab := _s.substr(q + 1, e - q - 1)
		var k := _skip_blanks(e + 1)
		var closer: int = _s.unicode_at(k) if k < _n else 0
		if closer != 93 and closer != 125:
			table.errors.append("Riga %d: etichetta senza chiusura: %s" % [_line_of(_i), lab])
			_i = e + 1
			return
		if closer == 125:
			table.warnings.append("Riga %d: etichetta chiusa con } invece di ]: %s" % [_line_of(_i), lab])
		_i = k + 1
		_flush_array()
		_label = lab
		_label_is_array = is_array
		_awaiting = not is_array

	## Restituisce false se il testo non finisce mai (fine file).
	func _read_value(is_array: bool) -> bool:
		var q := _skip_blanks(_i + 1)
		if q >= _n or _s.unicode_at(q) != 34:
			table.errors.append("Riga %d: valore senza virgolette" % _line_of(_i))
			_i += 1
			return true
		var close_at := _s.find("\"}", q + 1)
		var pos := q + 1
		var end := -1
		var close_len := 0
		while true:
			var le := _s.find("\n", pos)
			var stop := _n if le < 0 else le
			if close_at >= 0 and close_at < stop:
				end = close_at
				close_len = 2
				break
			var seg := _s.substr(pos, stop - pos).strip_edges(false, true)
			if seg.ends_with("}"):
				end = pos + seg.length() - 1
				close_len = 1
				table.warnings.append("Riga %d: testo senza virgolette finali" % _line_of(pos))
				break
			if le < 0:
				break
			pos = le + 1
		if end < 0:
			table.errors.append("Riga %d: testo non chiuso" % _line_of(_i))
			_i = _n
			return false
		var value := _s.substr(q + 1, end - q - 1)
		if _unescape:
			value = value.replace("\\n", "\n")
		var at := _i
		_i = end + close_len
		if is_array:
			if _label != "" and _label_is_array:
				_items.append(value)
			else:
				table.errors.append("Riga %d: elemento di array senza etichetta" % _line_of(at))
		elif _awaiting and not _label_is_array:
			_store(_label, value)
			_awaiting = false
		else:
			table.errors.append("Riga %d: testo senza etichetta" % _line_of(at))
		return true

	func _store(lab: String, value: String) -> void:
		if table.entries.has(lab):
			table.duplicates += 1
			if String(table.entries[lab]) != value:
				table.conflicts.append(lab)
		table.entries[lab] = value

	func _flush_array() -> void:
		if _label_is_array and _label != "":
			if table.arrays.has(_label):
				table.duplicates += 1
				table.warnings.append("Array ridefinito: %s" % _label)
			table.arrays[_label] = _items
		_items = PackedStringArray()
		_label_is_array = false
