class_name RetrainProcessor
extends RefCounted
## Riaddestramento delle unita' (meccanica dell'originale MTW, manuale p26: una pila decimata torna all'organico pieno
## pagando). Regole in `data/regole/riaddestramento.cfg` (`RetrainRules`, `rules.retrain`); comandi in `GameCommands`
## (`order_retrain`, `cancel_retrain`, `retrain_options`); ordini in `GameState.retrain_orders`, salvati.
##
## Un ordine paga subito il costo e si applica nel reclutamento di fine anno (`process_year`, prima della nascita delle
## reclute dell'anno): la pila torna a `UnitType.men` uomini e il valore si diluisce (`RetrainRules.diluted_value`). Se a fine
## anno l'esercito non c'e' piu', si e' mosso, la provincia non e' piu' della fazione o la pila non e' piu' quella dell'ordine
## (indice, unita' e uomini uguali), l'ordine e' rimborsato per intero con un EV_RETRAIN_CANCELLED. Dividere, unire, spostare
## pile o muovere l'esercito annulla gli ordini subito (`cancel_army_orders`).
## Escluse: navi, agenti, Crociata e Jihad, e ogni unita' che oggi non si potrebbe reclutare nella provincia. NON si escludono le
## unita' con la colonna 49 «mercenario» = YES: nei dati vale per 105 unita' comuni (Spearmen compresi) e indica che possono
## comparire tra i mercenari, non che siano mercenarie (i mercenari della locanda non ci sono ancora). Gli ordini militari si
## riaddestrano solo dove sono reclutabili: nella mod Auror lo sono con la Chapter House (dizionario dati); quelli avuti come
## ricompensa di crociata senza l'edificio non passano il controllo di reclutabilita' (catalogo: «non riaddestrabili»).


# --- ordini ------------------------------------------------------------------------------------------------------


## Ordini in attesa dell'esercito, in ordine di emissione.
static func orders_of(state: GameState, army_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in state.retrain_orders:
		if int(o["esercito"]) == army_id:
			out.append(o)
	return out


## Ordine dell'esercito per la pila `index`; {} se non c'e'.
static func order_at(state: GameState, army_id: int, index: int) -> Dictionary:
	for o in state.retrain_orders:
		if int(o["esercito"]) == army_id and int(o["pila"]) == index:
			return o
	return {}


## Ordini in attesa in una provincia (per il limite annuale).
static func orders_in(state: GameState, province_id: String) -> int:
	var n := 0
	for o in state.retrain_orders:
		if str(o["provincia"]) == province_id:
			n += 1
	return n


## Annulla gli ordini dell'esercito e rimborsa la fazione. Restituisce {"pile": n, "rimborso": fiorini}.
static func cancel_army_orders(state: GameState, army_id: int) -> Dictionary:
	var kept: Array[Dictionary] = []
	var count := 0
	var refund := 0
	for o in state.retrain_orders:
		if int(o["esercito"]) == army_id:
			count += 1
			refund += int(o["costo"])
			_refund(state, o)
		else:
			kept.append(o)
	if count > 0:
		state.retrain_orders = kept
	return {"pile": count, "rimborso": refund}


static func _refund(state: GameState, order: Dictionary) -> void:
	var f := state.faction(str(order["fazione"]))
	if f != null and f.alive:
		f.refund(int(order["costo"]), FactionState.SPEND_RETRAIN)


# --- controlli ---------------------------------------------------------------------------------------------------


## Perche' l'esercito non si puo' riaddestrare ("" se si puo'): proprio, di terra, non crociato, fermo, in una provincia della
## fazione non assediata (il castello va bene).
static func army_problem(state: GameState, faction_id: String, army: Army) -> String:
	var faction := state.faction(faction_id)
	if faction == null or not faction.alive:
		return Lang.t("Fazione sconosciuta o non attiva: %s") % faction_id
	if army == null:
		return Lang.t("Esercito inesistente")
	if army.faction != SimUtil.norm(faction_id):
		return Lang.t("Non e' un esercito di %s") % faction_id
	if army.is_fleet:
		return Lang.t("Le flotte non si riaddestrano")
	if army.is_crusade():
		return Lang.t("Un esercito crociato non si riaddestra")
	if army.stacks.is_empty():
		return Lang.t("L'esercito %d non ha pile") % army.id
	if not army.path.is_empty():
		return Lang.t("L'esercito %d e' in marcia: il riaddestramento richiede che stia fermo") % army.id
	var province := state.province(army.region)
	if province == null or province.owner != faction.id:
		return Lang.t("L'esercito %d non e' in una provincia di %s") % [army.id, faction.id]
	if state.is_besieged(province.id):
		return Lang.t("La provincia %s e' assediata") % province.id
	return ""



## Perche' l'unita' non si puo' reclutare oggi nella provincia, come in `GameCommands.can_queue_unit` ma senza coda ne'
## tesoro: fazione, epoca, regione, cultura, edifici richiesti. "" se si puo'.
static func recruit_problem(state: GameState, faction_id: String, province: ProvinceState, unit: UnitType) -> String:
	var faction := state.faction(faction_id)
	if faction == null:
		return Lang.t("Fazione sconosciuta: %s") % faction_id
	if unit.unique:
		return Lang.t("%s e' unico: non si arruola") % unit.id   # Ankalagon
	var free := state.rules.lifts_unit_limits(faction.id, unit)   # gli Auror: nessun limite di fazione, epoca, regione, cultura
	if not free and not unit.recruitable_by(faction.id):
		return Lang.t("%s non e' reclutabile da %s") % [unit.id, faction.id]
	if not free and not unit.available_in_period(state.era):
		return Lang.t("%s non e' disponibile nell'epoca %s") % [unit.id, state.era]
	var region := state.campaign.region(province.id)
	if region != null:
		if not free and not unit.allows_region(region.id):
			return Lang.t("%s non e' reclutabile in %s") % [unit.id, region.id]
		if not free and not unit.allows_culture(GameCommands.culture_key(region.culture)):
			return Lang.t("%s non e' reclutabile con la cultura %s") % [unit.id, region.culture]
	if not GameCommands.requirements_met(unit.requires, province, state.buildings):
		return Lang.t("Requisiti di %s non soddisfatti") % unit.id
	return ""


## Perche' la pila `index` dell'esercito non si riaddestra ("" se si puo'); l'esercito deve gia' aver superato `army_problem`.
## Non guarda il tesoro ne' il limite per provincia.
static func stack_problem(state: GameState, faction_id: String, army: Army, index: int) -> String:
	var st := army.stacks[index]
	var unit := state.units.get_unit(st.unit_id)
	if unit == null:
		return Lang.t("Unita' sconosciuta: %s") % st.unit_id
	if not unit.is_military() or unit.is_ship():
		return Lang.t("%s non e' una truppa di terra") % unit.id
	if unit.men <= 0:
		return Lang.t("%s non ha un organico valido") % unit.id
	if st.mercenary:
		return Lang.t("I mercenari non si riaddestrano")
	if st.men >= unit.men:
		return Lang.t("La pila e' gia' al completo")
	if not order_at(state, army.id, index).is_empty():
		return Lang.t("La pila e' gia' in riaddestramento")
	var province := state.province(army.region)
	if province == null:
		return Lang.t("Provincia sconosciuta: %s") % army.region
	return recruit_problem(state, faction_id, province, unit)


## Perche' la pila `index` non si ripristina con «Ripristina» ("" se si puo'; ADR-046): come `stack_problem`, ma la
## reclutabilita' nella provincia e i mercenari contano solo se `riaddestramento.cfg` lo chiede. Non guarda il tesoro.
static func restore_problem(state: GameState, faction_id: String, army: Army, index: int) -> String:
	var rt := state.rules.retrain
	var st := army.stacks[index]
	var unit := state.units.get_unit(st.unit_id)
	if unit == null:
		return Lang.t("Unita' sconosciuta: %s") % st.unit_id
	if not unit.is_military() or unit.is_ship():
		return Lang.t("%s non e' una truppa di terra") % unit.id
	if unit.men <= 0:
		return Lang.t("%s non ha un organico valido") % unit.id
	if st.men >= unit.men:
		return Lang.t("La pila e' gia' al completo")
	if not order_at(state, army.id, index).is_empty():
		return Lang.t("La pila e' gia' in riaddestramento")
	if st.mercenary and not rt.restore_mercenaries:
		return Lang.t("I mercenari non si riaddestrano")
	if rt.restore_needs_buildings:
		var province := state.province(army.region)
		if province == null:
			return Lang.t("Provincia sconosciuta: %s") % army.region
		return recruit_problem(state, faction_id, province, unit)
	return ""


## Costo di riaddestrare la pila (0 se piena o sconosciuta).
static func stack_cost(state: GameState, st: UnitStack) -> int:
	var unit := state.units.get_unit(st.unit_id)
	if unit == null:
		return 0
	return state.rules.retrain.cost_for(unit.cost, st.men, unit.men)


# --- fine anno ---------------------------------------------------------------------------------------------------


## Applica o rimborsa gli ordini; chiamato dal reclutamento di fine anno prima che nascano le reclute. Un evento per esercito:
## EV_RETRAINED con le pile riaddestrate, EV_RETRAIN_CANCELLED con quelle rimborsate. Ordine fisso: eserciti nell'ordine del
## primo ordine, pile nell'ordine di emissione.
static func process_year(state: GameState) -> void:
	if state.retrain_orders.is_empty():
		return
	var orders: Array[Dictionary] = []
	orders.append_array(state.retrain_orders)
	state.retrain_orders.clear()
	var ids: Array[int] = []
	var by_army := {}
	for o in orders:
		var army_id := int(o["esercito"])
		if not by_army.has(army_id):
			by_army[army_id] = []
			ids.append(army_id)
		var group: Array = by_army[army_id]
		group.append(o)
	for id in ids:
		var members: Array = by_army[id]
		_process_army(state, id, members)


static func _process_army(state: GameState, army_id: int, group: Array) -> void:
	var army := state.army(army_id)
	var first: Dictionary = group[0]
	var faction_id := str(first["fazione"])
	var province_id := str(first["provincia"])
	var done_units: Array = []
	var done_men := 0
	var done_cost := 0
	var done_stacks := 0
	var refunded_units: Array = []
	var refunded_cost := 0
	var refunded_stacks := 0
	var reason := ""
	for item in group:
		var o: Dictionary = item
		var why := _order_problem(state, army, o)
		if why != "":
			reason = why if reason == "" else reason
			refunded_stacks += 1
			refunded_cost += int(o["costo"])
			refunded_units.append(str(o["unita"]))
			_refund(state, o)
			continue
		var st := army.stacks[int(o["pila"])]
		var unit := state.units.get_unit(st.unit_id)
		done_men += unit.men - st.men
		st.value = RetrainRules.diluted_value(st.value, st.men, unit.men)
		# le reclute di una fazione con valore iniziale (Auror) arrivano a quel valore: la pila non scende sotto
		st.value = maxi(st.value, mini(state.rules.combat.start_valour_of(army.faction), state.rules.combat.valour_max))
		st.men = unit.men
		TroopUpgrades.upgrade_on_retrain(state, st, state.province(province_id))   # armi e armatura della provincia, se migliori
		done_stacks += 1
		done_cost += int(o["costo"])
		done_units.append(unit.id)
	var place := WarProcessor.region_label(state, province_id)
	if done_stacks > 0:
		state.add_event(GameState.EV_RETRAINED, {
			"fazione": faction_id,
			"provincia": province_id,
			"regione": province_id,
			"esercito": army_id,
			"pile": done_stacks,
			"unita": done_units,
			"uomini": done_men,
			"costo": done_cost,
			"testo": Lang.t("%d pile dell'esercito %d di %s tornano all'organico pieno a %s (%d uomini, %d fiorini).") % [
				done_stacks, army_id, SimUtil.faction_label(faction_id), place, done_men, done_cost],
		})
	if refunded_stacks > 0:
		state.add_event(GameState.EV_RETRAIN_CANCELLED, {
			"fazione": faction_id,
			"provincia": province_id,
			"regione": province_id,
			"esercito": army_id,
			"pile": refunded_stacks,
			"unita": refunded_units,
			"rimborso": refunded_cost,
			"motivo": reason,
			"testo": Lang.t("Riaddestramento annullato a %s (esercito %d di %s): %d fiorini rimborsati.") % [
				place, army_id, SimUtil.faction_label(faction_id), refunded_cost],
		})


## Motivo per cui l'ordine non si applica piu' ("" se si applica): "esercito_perso", "esercito_mosso", "provincia_persa",
## "pila_cambiata".
static func _order_problem(state: GameState, army: Army, order: Dictionary) -> String:
	if army == null or army.is_fleet or army.faction != str(order["fazione"]):
		return "esercito_perso"
	if army.region != str(order["provincia"]) or not army.path.is_empty():
		return "esercito_mosso"
	var province := state.province(army.region)
	if province == null or province.owner != army.faction:
		return "provincia_persa"
	var index := int(order["pila"])
	if index < 0 or index >= army.stacks.size():
		return "pila_cambiata"
	var st := army.stacks[index]
	if st.unit_id != str(order["unita"]) or st.men != int(order["uomini"]):
		return "pila_cambiata"
	var unit := state.units.get_unit(st.unit_id)
	if unit == null or unit.men <= st.men:
		return "pila_cambiata"
	return ""
