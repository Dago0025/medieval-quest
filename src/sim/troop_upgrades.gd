class_name TroopUpgrades
extends RefCounted
## Potenziamenti delle truppe dagli edifici della provincia (richiesta di Federico, 2026-11-13, meccanica dell'originale):
## le reclute ricevono il livello di armatura (scudo) e di armi (spada) degli edifici che ce l'hanno, nei dati della XL
## l'Armaiolo (`ARMOURER`, UPGRADE_ARMOUR 1-4) e il Fabbro (`METALSMITH`, UPGRADE_WEAPON 1-4), e il valore in piu' di
## UPGRADE_VALOUR (quarto livello di Arciere, Spadaio, Lanciaio, Armaiolo da fuoco, Ronda, Allevatore; Taverna, Bordello).
## Il livello sta nella pila (`UnitStack.weapon`, `UnitStack.armour`, da 0 a 4) e nell'interfaccia si vede con le icone dello
## scudo e della spada (ferro, bronzo, argento, oro). Il riaddestramento porta la pila al livello della provincia se e' piu'
## alto (PROVVISORIA: nell'originale non e' documentato).
## Effetto negli scontri: ogni livello di armi conta come un punto di attacco e ogni livello di armatura come un punto di
## armatura nella formula di `Combat.stack_strength` (pesi di scontri.cfg; PROVVISORIA come tutta la formula).

const MAX_LEVEL := 4
const ARMOUR := "UPGRADE_ARMOUR"
const WEAPON := "UPGRADE_WEAPON"
const VALOUR := "UPGRADE_VALOUR"

## Nomi dei quattro livelli, come i colori delle icone dell'originale (campmap/Armour_bonus e weapon_bonus).
const METALS := ["", "ferro", "bronzo", "argento", "oro"]


## Livelli che la provincia da' alle reclute: {"armi", "armatura", "valore"}, il massimo tra gli edifici costruiti (ogni
## livello di un edificio ha la sua voce nella colonna 16 del file prod, per esempio «UPGRADE_ARMOUR(3)»).
static func province_levels(state: GameState, province: ProvinceState) -> Dictionary:
	var out := {"armi": 0, "armatura": 0, "valore": 0}
	if state == null or province == null or state.buildings == null:
		return out
	for family_id in province.buildings:
		var family: BuildingType = state.buildings.get_family(str(family_id))
		if family == null:
			continue
		var level: BuildingType.Level = family.get_level(int(province.buildings[family_id]))
		if level == null:
			continue
		for token in level.upgrades:
			var parsed := parse(str(token))
			if parsed.is_empty():
				continue
			var key := str(parsed["chiave"])
			out[key] = maxi(int(out[key]), int(parsed["livello"]))
	out["armi"] = mini(int(out["armi"]) + LegendarySites.region_int(state, province.id, "armi_reclute"), MAX_LEVEL)   # luoghi leggendari (Fucina di Efesto)
	out["armatura"] = mini(int(out["armatura"]), MAX_LEVEL)
	return out


## «UPGRADE_ARMOUR(3)» -> {"chiave": "armatura", "livello": 3}; vuoto per gli altri potenziamenti (morale, disciplina...).
static func parse(token: String) -> Dictionary:
	var t := token.strip_edges().to_upper().replace("{", "").replace("}", "")
	var open := t.find("(")
	var name := t if open < 0 else t.left(open).strip_edges()
	var amount := 1
	if open >= 0:
		var inner := t.substr(open + 1).replace(")", "").strip_edges()
		if inner.is_valid_int():
			amount = inner.to_int()
	match name:
		ARMOUR:
			return {"chiave": "armatura", "livello": amount}
		WEAPON:
			return {"chiave": "armi", "livello": amount}
		VALOUR:
			return {"chiave": "valore", "livello": amount}
	return {}


## Vero se l'unita' riceve i potenziamenti: truppe di terra (non navi ne' agenti).
static func applies_to(unit: UnitType) -> bool:
	return unit != null and unit.is_military() and not unit.is_ship()


## Una recluta nata nella provincia: livelli di armi e armatura della provincia e valore in piu' (fino al massimo delle regole).
static func equip_recruit(state: GameState, stack: UnitStack, province: ProvinceState) -> void:
	var unit := state.units.get_unit(stack.unit_id) if state.units != null else null
	if not applies_to(unit):
		return
	var levels := province_levels(state, province)
	stack.weapon = maxi(stack.weapon, int(levels["armi"]))
	stack.armour = maxi(stack.armour, int(levels["armatura"]))
	if int(levels["valore"]) > 0:
		stack.value = mini(stack.value + int(levels["valore"]), maxi(stack.value, state.rules.combat.valour_max))


## Una pila riaddestrata nella provincia: armi e armatura salgono al livello della provincia se e' piu' alto (mai giu').
static func upgrade_on_retrain(state: GameState, stack: UnitStack, province: ProvinceState) -> void:
	var unit := state.units.get_unit(stack.unit_id) if state.units != null else null
	if not applies_to(unit):
		return
	var levels := province_levels(state, province)
	stack.weapon = maxi(stack.weapon, int(levels["armi"]))
	stack.armour = maxi(stack.armour, int(levels["armatura"]))


## Riga per i suggerimenti: «Armi: argento (+3) · armatura: bronzo (+2)»; vuota senza potenziamenti.
static func describe(stack: UnitStack) -> String:
	var parts := PackedStringArray()
	if stack.weapon > 0:
		parts.append(Lang.t("armi: %s (+%d)") % [Lang.t(METALS[clampi(stack.weapon, 1, MAX_LEVEL)]), stack.weapon])
	if stack.armour > 0:
		parts.append(Lang.t("armatura: %s (+%d)") % [Lang.t(METALS[clampi(stack.armour, 1, MAX_LEVEL)]), stack.armour])
	if parts.is_empty():
		return ""
	var text := " · ".join(parts)
	return text.left(1).to_upper() + text.substr(1)


## Livello minimo della fazione (auror.cfg `armi_armatura_iniziali`, gli Auror: 4 = oro) su una pila di terra: mai giu'.
static func apply_start(state: GameState, stack: UnitStack, faction_id: String) -> void:
	if state == null or state.rules == null or stack == null:
		return
	var level := state.rules.combat.start_upgrades_of(faction_id)
	if level <= 0:
		return
	var unit := state.units.get_unit(stack.unit_id) if state.units != null else null
	if not applies_to(unit):
		return
	stack.weapon = maxi(stack.weapon, level)
	stack.armour = maxi(stack.armour, level)


## Porta al livello minimo della fazione tutte le pile di terra delle fazioni che ce l'hanno (salvataggi precedenti, pile
## passate di mano, ogni fine anno). Restituisce quante pile sono cambiate.
static func apply_faction_minimum(state: GameState) -> int:
	if state == null or state.rules == null:
		return 0
	var changed := 0
	for a in state.armies:
		if state.rules.combat.start_upgrades_of(a.faction) <= 0:
			continue
		for st in a.stacks:
			var before := st.weapon * 10 + st.armour
			apply_start(state, st, a.faction)
			if st.weapon * 10 + st.armour != before:
				changed += 1
	return changed
