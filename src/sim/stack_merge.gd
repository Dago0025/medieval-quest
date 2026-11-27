class_name StackMerge
extends RefCounted
## Accorpamento delle pile dello stesso tipo (ADR-146, richiesta di Federico del 27/11/2026: «nel gioco originale quando si
## spostava una pila su un'altra propria il sistema puntava sempre a riempire quella di destinazione; faceva lo stesso dopo
## le battaglie, accorpando le truppe per compensare le unita' uguali che avevano perso uomini»).
##
## Manuale p29 «Unire armate e unita'»: un'unita' trascinata su un'altra «dello stesso identico tipo» la rifornisce di uomini
## fino all'organico pieno, gli uomini in eccedenza restano nell'unita' di partenza; il valore e' la media di quello degli
## uomini; il tasto M trasferisce gli uomini «dalle unita' piu' indebolite a quelle in migliori condizioni», e lo stesso
## avviene da solo trascinando un'armata su un'altra. Dopo le battaglie: ricordo di Federico (il manuale non ne parla).
##
## Si accorpano solo pile con la stessa unita' e lo stesso stato di mercenario (i mercenari costano di piu'); armi e armatura
## restano quelle della pila che si riempie (PROVVISORIA: il manuale non lo dice). Regole in economia.cfg [eserciti]:
## `riempi_unita_uguali` (unioni e trasferimenti) e `accorpa_dopo_battaglia`.


## Organico pieno di una pila (uomini del tipo di unita'); 0 se il tipo non si conosce.
static func full_men(state: GameState, st: UnitStack) -> int:
	if state == null or state.units == null:
		return 0
	var unit := state.units.get_unit(st.unit_id)
	return unit.men if unit != null else 0


## Chiave dei gruppi di pile che si possono accorpare.
static func _key(st: UnitStack) -> String:
	return "%s|%s" % [st.unit_id, "m" if st.mercenary else ""]


## Sposta da `donor` a `target` gli uomini che mancano a `target` per l'organico pieno `full` (al massimo tutti quelli di
## `donor`); il valore di `target` diventa la media pesata sugli uomini. Restituisce gli uomini spostati.
static func fill(target: UnitStack, donor: UnitStack, full: int) -> int:
	var moved := mini(maxi(0, full - target.men), donor.men)
	if moved <= 0:
		return 0
	target.value = roundi(float(target.value * target.men + donor.value * moved) / float(target.men + moved))
	target.men += moved
	donor.men -= moved
	return moved


## Accorpa le pile uguali dell'esercito: in ogni gruppo le piu' forti si riempiono con gli uomini delle piu' deboli, le pile
## rimaste vuote spariscono. Con `receivers` > 0 le prime `receivers` pile (quelle che l'esercito aveva gia', prima di un
## trasferimento) si riempiono per prime con gli uomini delle pile arrivate, come trascinando un'unita' su un'altra: gli uomini
## in eccedenza restano in quelle arrivate. L'ordine delle pile rimaste non cambia. Restituisce gli uomini spostati.
static func consolidate(state: GameState, army: Army, receivers: int = 0) -> int:
	if army == null or army.stacks.size() < 2:
		return 0
	var groups := {}
	for i in army.stacks.size():
		var k := _key(army.stacks[i])
		if not groups.has(k):
			groups[k] = []
		(groups[k] as Array).append(i)
	var moved := 0
	for k in groups:
		var idx: Array = groups[k]
		if idx.size() < 2:
			continue
		var full := full_men(state, army.stacks[idx[0]])
		if full <= 0:
			continue
		# prima le pile che c'erano gia' (se indicate), poi dalla piu' forte alla piu' debole; a parita' l'ordine nell'esercito
		idx.sort_custom(func(a: int, b: int) -> bool:
			var ra := a < receivers
			var rb := b < receivers
			if ra != rb:
				return ra
			var ma := army.stacks[a].men
			var mb := army.stacks[b].men
			return ma > mb or (ma == mb and a < b))
		var i := 0
		var j := idx.size() - 1
		while i < j:
			var target: UnitStack = army.stacks[idx[i]]
			if target.men >= full:
				i += 1
				continue
			var donor: UnitStack = army.stacks[idx[j]]
			moved += fill(target, donor, full)
			if donor.men <= 0:
				j -= 1
	if moved > 0:
		for n in range(army.stacks.size() - 1, -1, -1):
			if army.stacks[n].men <= 0:
				army.stacks.remove_at(n)
	return moved


## Pile che resterebbero accorpando `stacks` (senza modificarle): per ogni gruppo uguale, gli uomini divisi per l'organico
## pieno arrotondati per eccesso, mai piu' delle pile di partenza.
static func merged_count(state: GameState, stacks: Array[UnitStack]) -> int:
	var groups := {}
	var count := 0
	for st in stacks:
		var full := full_men(state, st)
		if full <= 0:
			count += 1
			continue
		var k := _key(st)
		if not groups.has(k):
			groups[k] = [0, 0, full]   # pile, uomini, organico
		groups[k][0] += 1
		groups[k][1] += st.men
	for k in groups:
		var g: Array = groups[k]
		count += mini(int(g[0]), maxi(1, ceili(float(g[1]) / float(g[2]))))
	return count


## Pile dell'esercito `target` dopo avergli aggiunto `extra`, accorpando se la regola e' accesa.
static func size_after_join(state: GameState, target: Army, extra: Array[UnitStack]) -> int:
	if not state.rules.merge_same_units:
		return target.stacks.size() + extra.size()
	var all: Array[UnitStack] = []
	all.append_array(target.stacks)
	all.append_array(extra)
	return merged_count(state, all)
