class_name Army
extends RefCounted
## Esercito di terra o flotta: pile di unita', posizione e percorso ordinato.

var id := 0
var faction := ""            ## id della fazione (maiuscolo)
var region := ""             ## regione di terra (esercito) o di mare (flotta)
var is_fleet := false
var stacks: Array[UnitStack] = []
## Regioni ancora da attraversare, nell'ordine; la prima e' il prossimo passo.
var path := PackedStringArray()
## Trasporto via mare (spec. fase 3 §9): catena di zone di mare (ognuna con una flotta propria) da
## percorrere nel movimento di fine anno. Non vuota solo se `path` e' un'unica provincia di terra
## raggiunta imbarcandosi; vuota per i movimenti normali.
var sea_route := PackedStringArray()
## Obsoleto dalla fase 3 (non viene piu' impostato): restano il campo e il salvataggio per compatibilita'.
var pending_conflict := ""
## Fase 3: l'esercito sta nel castello della provincia (guarnigione, di solito assediata).
var in_castle := false
## Fase 3: ordine di assalto al castello assediato (vale per tutti gli assedianti della regione).
var assault_ordered := false
## Fase 3: regione da cui l'esercito e' partito con l'ultimo movimento ("" se mai mosso o dopo una ritirata).
var from_region := ""
## Fase 3: anno dell'ultimo movimento (0 se mai mosso); chi e' arrivato quest'anno e' l'attaccante.
var arrived_year := 0
## Fase 5c: esercito crociato. Vuoto = esercito normale; altrimenti {"tipo": "crociata" | "jihad", "zelo" (int),
## "bersaglio" (id della regione, "" = nessuno), "annunciato" (ultimo bersaglio comunicato con EV_CRUSADE_TARGET),
## "reclutate" (province dove ha gia' reclutato per zelo), "anno" (di nascita)}. Vedi `PapacyProcessor`.
var crusade := {}
## Unione ordinata trascinando l'esercito su un altro proprio in una regione confinante: id dell'esercito in cui confluire
## all'arrivo (0 = nessuna). Vedi `GameCommands.order_merge` e `TurnProcessor._merge_arrivals`.
var merge_target := 0
## Esercito trascinato sul castello di una propria provincia confinante (richiesta di Federico, 2026-11-10): all'arrivo si
## barrica con le unita' che ci stanno. Vedi `GameCommands.order_garrison_move` e `TurnProcessor._garrison_arrivals`.
var garrison_on_arrival := false
## Flotta trascinata sulla pedina di una flotta di un'altra fazione (richiesta di Federico, 2026-11-13: come nell'originale si
## attacca la flotta, con conferma se non c'e' gia' la guerra): id della flotta bersaglio (0 = nessuna). A fine anno la flotta
## la raggiunge dove si trova, anche nella propria zona, e la attacca. Vedi `GameCommands.order_naval_attack` e
## `TurnProcessor._pursue`.
var attack_target := 0
## Ammiraglio della flotta (ADR-056, `Admirals`): {"nome", "stelle", "vinte", "perse"}; vuoto per gli eserciti di terra.
var admiral := {}
## Posizione scelta dal giocatore per la pedina nella sua regione (coordinate della mappa, richiesta di Federico: riordinare
## le pedine trascinandole). Vale solo finche' la pedina resta in `map_spot_region`; Vector2.INF = posizione automatica.
## Ribelli lealisti (ADR-070): fazione a cui l'esercito ribelle consegna la provincia se la prende ("" = ribelli comuni).
var loyal_to := ""
var map_spot := Vector2.INF
var map_spot_region := ""

const CRUSADE_KIND := "crociata"
const JIHAD_KIND := "jihad"


func _init(army_id: int = 0, owner_id: String = "", at_region: String = "", fleet: bool = false) -> void:
	id = army_id
	faction = owner_id
	region = at_region
	is_fleet = fleet


## Vero per gli eserciti crociati (crociata o jihad).
func is_crusade() -> bool:
	return not crusade.is_empty()


## "crociata", "jihad" o "" per un esercito normale.
func crusade_kind() -> String:
	return str(crusade.get("tipo", ""))


## Bersaglio della crociata ("" se non ne ha o se non e' una crociata).
func crusade_target() -> String:
	return str(crusade.get("bersaglio", ""))


func stack_count() -> int:
	return stacks.size()


func men_total() -> int:
	var total := 0
	for s in stacks:
		total += s.men
	return total


func is_full(max_stacks: int) -> bool:
	return stacks.size() >= max_stacks


## Vero se l'esercito si e' mosso nell'anno `year` (e' quindi l'attaccante in quella regione).
func arrived_in(year: int) -> bool:
	return arrived_year == year and from_region != ""


func to_dict() -> Dictionary:
	var stack_list: Array = []
	for s in stacks:
		stack_list.append(s.to_dict())
	var d := {
		"id": id,
		"fazione": faction,
		"regione": region,
		"flotta": is_fleet,
		"pile": stack_list,
		"percorso": Array(path),
		"conflitto": pending_conflict,
		"nel_castello": in_castle,
		"assalto": assault_ordered,
		"da_regione": from_region,
		"anno_arrivo": arrived_year,
	}
	# campo facoltativo (spec. fase 3 §9): assente se non c'e' un trasporto in corso
	if not sea_route.is_empty():
		d["rotta_mare"] = Array(sea_route)
	# campo facoltativo (fase 5c): assente per gli eserciti normali
	if not crusade.is_empty():
		d["crociata"] = crusade.duplicate(true)
	if merge_target > 0:
		d["unisci_a"] = merge_target
	if garrison_on_arrival:
		d["barrica_all_arrivo"] = true
	if attack_target > 0:
		d["attacca_flotta"] = attack_target
	if not admiral.is_empty():
		d["ammiraglio"] = admiral.duplicate()
	if loyal_to != "":
		d["lealisti"] = loyal_to
	if map_spot != Vector2.INF and map_spot_region != "":
		d["posizione_mappa"] = {"regione": map_spot_region, "x": map_spot.x, "y": map_spot.y}
	return d


static func from_dict(d: Dictionary) -> Army:
	var a := Army.new(int(d.get("id", 0)), str(d.get("fazione", "")), str(d.get("regione", "")), bool(d.get("flotta", false)))
	var stack_list: Array = d.get("pile", [])
	for item in stack_list:
		var sd: Dictionary = item
		a.stacks.append(UnitStack.from_dict(sd))
	a.path = SimUtil.strings_from(d.get("percorso", []))
	a.sea_route = SimUtil.strings_from(d.get("rotta_mare", []))
	a.pending_conflict = str(d.get("conflitto", ""))
	a.in_castle = bool(d.get("nel_castello", false))
	a.assault_ordered = bool(d.get("assalto", false))
	a.from_region = str(d.get("da_regione", ""))
	a.arrived_year = int(d.get("anno_arrivo", 0))
	var adm: Variant = d.get("ammiraglio", {})
	if typeof(adm) == TYPE_DICTIONARY:
		var admd: Dictionary = adm
		a.admiral = admd.duplicate()
	var cd: Variant = d.get("crociata", {})
	if typeof(cd) == TYPE_DICTIONARY:
		var crusade_data: Dictionary = cd
		a.crusade = crusade_data.duplicate(true)
	a.merge_target = int(d.get("unisci_a", 0))
	a.garrison_on_arrival = bool(d.get("barrica_all_arrivo", false))
	a.attack_target = int(d.get("attacca_flotta", 0))
	a.loyal_to = str(d.get("lealisti", ""))
	var spot: Variant = d.get("posizione_mappa", null)
	if typeof(spot) == TYPE_DICTIONARY:
		var sd: Dictionary = spot
		a.map_spot = Vector2(float(sd.get("x", 0.0)), float(sd.get("y", 0.0)))
		a.map_spot_region = str(sd.get("regione", ""))
	return a


## Posizione scelta sulla mappa, se vale ancora per la regione attuale (altrimenti Vector2.INF).
func spot_here() -> Vector2:
	return map_spot if map_spot != Vector2.INF and map_spot_region == region else Vector2.INF
