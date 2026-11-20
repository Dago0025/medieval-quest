class_name SimUtil
extends RefCounted
## Funzioni di servizio della simulazione.


## Dopo JSON.parse_string tutti i numeri sono float: i float con valore intero tornano int.
## Lo stato di gioco contiene solo interi, quindi la conversione e' sicura.
static func fix_numbers(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if f == floorf(f) and absf(f) < 9.0e15:
				return int(f)
			return f
		TYPE_ARRAY:
			var out_array: Array = []
			var src_array: Array = v
			for item in src_array:
				out_array.append(fix_numbers(item))
			return out_array
		TYPE_DICTIONARY:
			var out_dict := {}
			var src_dict: Dictionary = v
			for key in src_dict:
				out_dict[key] = fix_numbers(src_dict[key])
			return out_dict
	return v


## "ID_Sweden" -> "ID_SWEDEN": gli ID sono sempre confrontati in maiuscolo.
static func norm(id: String) -> String:
	return id.strip_edges().to_upper()


## Elenco di stringhe da un valore letto da JSON (Array di String).
static func strings_from(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(v) != TYPE_ARRAY:
		return out
	var items: Array = v
	for item in items:
		out.append(str(item))
	return out


## "FN_HOLY_ROMAN_EMPIRE" -> "Holy Roman Empire": nome leggibile per i testi degli eventi.
static func faction_label(faction_id: String) -> String:
	return FactionStyle.name_of(norm(faction_id))   # fase 8: nomi di data/fazioni.cfg (la fazione del giocatore e' Auror)
