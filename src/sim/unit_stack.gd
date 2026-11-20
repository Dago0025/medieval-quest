class_name UnitStack
extends RefCounted
## Una pila di un esercito o di una flotta: un'unita' con i suoi uomini e il valore (valour).

var unit_id := ""    ## id del tipo di unita' (UnitType.id)
var men := 0
var value := 0       ## valore (esperienza); attivo dalla fase 3
var mercenary := false   ## fase 8d: assoldata tra i mercenari (non si riaddestra, mantenimento maggiorato)
var weapon := 0          ## livello delle armi 0-4 (spada: ferro, bronzo, argento, oro), dagli edifici della provincia (TroopUpgrades)
var armour := 0          ## livello dell'armatura 0-4 (scudo), dagli edifici della provincia (TroopUpgrades)


func _init(type_id: String = "", men_count: int = 0, valour: int = 0) -> void:
	unit_id = type_id
	men = men_count
	value = valour


func to_dict() -> Dictionary:
	var d := {"unita": unit_id, "uomini": men, "valore": value}
	if mercenary:
		d["mercenario"] = true   # solo se vero: i salvataggi delle pile normali restano uguali
	if weapon > 0:
		d["armi"] = weapon       # campi facoltativi (2026-11-13): assenti senza potenziamenti
	if armour > 0:
		d["armatura"] = armour
	return d


static func from_dict(d: Dictionary) -> UnitStack:
	var st := UnitStack.new(str(d.get("unita", "")), int(d.get("uomini", 0)), int(d.get("valore", 0)))
	st.mercenary = bool(d.get("mercenario", false))
	st.weapon = int(d.get("armi", 0))
	st.armour = int(d.get("armatura", 0))
	return st
