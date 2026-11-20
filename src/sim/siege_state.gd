class_name SiegeState
extends RefCounted
## Assedio di un castello (fase 3): regione assediata, fazione assediante, anni trascorsi
## ed eserciti assedianti. Il giocatore e l'IA non lo modificano a mano: lo gestisce
## `WarProcessor` a ogni fine anno (si ricalcola dagli eserciti presenti nella regione).

var region := ""                 ## id della regione assediata
var faction := ""                ## fazione assediante
var years := 0                   ## anni di assedio completati (0 = appena iniziato)
var army_ids := PackedInt32Array()   ## eserciti assedianti, in ordine di id


func _init(region_id: String = "", besieger: String = "", elapsed_years: int = 0) -> void:
	region = region_id
	faction = besieger
	years = elapsed_years


func to_dict() -> Dictionary:
	var ids: Array = []
	for army_id in army_ids:
		ids.append(army_id)
	return {"regione": region, "fazione": faction, "anni": years, "eserciti": ids}


static func from_dict(d: Dictionary) -> SiegeState:
	var s := SiegeState.new(str(d.get("regione", "")), str(d.get("fazione", "")), int(d.get("anni", 0)))
	var ids: Array = d.get("eserciti", [])
	for item in ids:
		s.army_ids.append(int(item))
	return s
