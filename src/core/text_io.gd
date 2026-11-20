class_name TextIO
extends RefCounted
## Lettura dei file di testo del gioco originale.
##
## I file di MTW sono in codifica ANSI (cp1252) con fine riga CRLF.
## Godot legge il testo come UTF-8, quindi i byte oltre 127 vanno convertiti
## a mano: qui ogni byte diventa il carattere Latin-1 con lo stesso codice,
## che coincide con cp1252 tranne per i rari simboli tra 0x80 e 0x9F.
## Il remake legge soltanto: non apre mai in scrittura i file del gioco (ADR-008).


## Restituisce il contenuto del file come testo, oppure "" se il file non esiste.
static func read_latin1(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("File non trovato: %s" % path)
		return ""
	var bytes := FileAccess.get_file_as_bytes(path)
	return decode_latin1(bytes)


## Converte byte Latin-1 in testo. Percorso veloce se il testo è tutto ASCII.
static func decode_latin1(bytes: PackedByteArray) -> String:
	var ascii := true
	for b in bytes:
		if b > 127:
			ascii = false
			break
	if ascii:
		return bytes.get_string_from_ascii()
	var parts := PackedStringArray()
	parts.resize(bytes.size())
	for i in bytes.size():
		parts[i] = String.chr(bytes[i])
	return "".join(parts)
