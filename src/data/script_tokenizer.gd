class_name ScriptTokenizer
extends RefCounted
## Scompone i file "a comandi" di MTW (startpos e simili).
##
## Ogni riga utile ha la forma `Comando:: arg1 arg2 ...`:
## - gli argomenti sono separati da spazi o tabulazioni, anche multipli;
## - un argomento tra virgolette può contenere spazi (le virgolette si tolgono);
## - `//` apre un commento fino a fine riga, ma non dentro le virgolette.
## Righe senza `::` (o vuote, o solo commento) vengono ignorate.


## Un comando letto dal file.
class Command:
	var name: String
	var args: PackedStringArray
	var line: int

	func _init(cmd_name: String, cmd_args: PackedStringArray, line_number: int) -> void:
		name = cmd_name
		args = cmd_args
		line = line_number

	func arg(i: int, fallback: String = "") -> String:
		return args[i] if i < args.size() else fallback


## Toglie il commento `//` da una riga, rispettando le virgolette.
static func strip_comment(s: String) -> String:
	var in_quotes := false
	var n := s.length()
	for i in n:
		var c: String = s[i]
		if c == "\"":
			in_quotes = not in_quotes
		elif not in_quotes and c == "/" and i + 1 < n and s[i + 1] == "/":
			return s.substr(0, i)
	return s


## Divide gli argomenti di un comando rispettando le virgolette.
static func split_args(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var in_quotes := false
	var has_token := false
	for i in s.length():
		var c: String = s[i]
		if c == "\"":
			in_quotes = not in_quotes
			has_token = true
		elif not in_quotes and (c == " " or c == "\t"):
			if has_token:
				out.append(current)
				current = ""
				has_token = false
		else:
			current += c
			has_token = true
	if has_token:
		out.append(current)
	return out


## Restituisce tutti i comandi del testo, con il numero di riga di origine.
static func parse(text: String) -> Array[Command]:
	var result: Array[Command] = []
	var lines := text.split("\n")
	for i in lines.size():
		var raw := strip_comment(lines[i]).strip_edges()
		if raw.is_empty():
			continue
		var sep := raw.find("::")
		if sep <= 0:
			continue
		var cmd_name := raw.substr(0, sep).strip_edges()
		var rest := raw.substr(sep + 2)
		result.append(Command.new(cmd_name, split_args(rest), i + 1))
	return result
