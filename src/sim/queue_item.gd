class_name QueueItem
extends RefCounted
## Una voce di una coda di costruzione o di reclutamento di una provincia.

const KIND_BUILDING := "edificio"
const KIND_UNIT := "unita"

var kind := ""          ## KIND_BUILDING o KIND_UNIT
var key := ""           ## famiglia di edificio oppure id dell'unita'
var level := 0          ## livello che si ottiene (solo edifici)
var years_left := 0     ## anni rimanenti
var cost_paid := 0      ## costo gia' pagato (rimborsato se si annulla)


func _init(item_kind: String = "", item_key: String = "", item_level: int = 0, years: int = 0, cost: int = 0) -> void:
	kind = item_kind
	key = item_key
	level = item_level
	years_left = years
	cost_paid = cost


func to_dict() -> Dictionary:
	return {"tipo": kind, "chiave": key, "livello": level, "anni": years_left, "costo": cost_paid}


static func from_dict(d: Dictionary) -> QueueItem:
	return QueueItem.new(
		str(d.get("tipo", "")),
		str(d.get("chiave", "")),
		int(d.get("livello", 0)),
		int(d.get("anni", 0)),
		int(d.get("costo", 0)))
