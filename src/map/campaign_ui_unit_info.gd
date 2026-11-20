class_name CampaignUiUnitInfo
extends RefCounted
## Scheda informativa di una pila o di un tipo di unita'. Dal 2026-11-15 (richiesta di Federico) la scheda non usa piu' la
## pergamena e le illustrazioni dell'originale: l'immagine e' la carta rifatta ingrandita e i dati sono divisi in sezioni
## (stato della pila, combattimento, costi, arruolamento) invece della griglia a quattro colonne sulla pergamena.
## `righe` resta l'elenco piatto di tutte le voci, per chi lo legge ancora.

const TYPE_NAMES := {
	"INFANTRY": "Fanteria",
	"CAVALRY": "Cavalleria",
	"MISSILE": "Tiratori",
	"SIEGE": "Macchine d'assedio",
	"SHIP": "Nave",
}
const CLASS_NAMES := {
	"MISSILE": "tiratori",
	"ATTACKER": "d'assalto",
	"DEFENDER": "difensiva",
	"SKIRMISHER": "schermagliatori",
	"HEAVY": "pesante",
	"LIGHT": "leggera",
	"ARTILLERY": "artiglieria",
}
const SECTION_STACK := "La pila"
const SECTION_FIGHT := "In battaglia"
const SECTION_SEA := "In mare"
const SECTION_RECRUIT := "Arruolamento"


## {"nome", "tipo", "righe": [[etichetta, valore]], "descrizione", "uomini", "comandante" (nota o ""), "unita" (id),
##  "pila": {"uomini", "pieni", "valore", "armi", "armatura"} (vuoto per un tipo non arruolato),
##  "combattimento": [[etichetta, valore, suggerimento]], "costi": [[etichetta, valore]],
##  "arruolamento": [[etichetta, valore]]}. Vuoto se la pila non esiste.
static func info(state: GameState, army: Army, index: int) -> Dictionary:
	if army == null or index < 0 or index >= army.stacks.size():
		return {}
	var st := army.stacks[index]
	var unit := state.units.get_unit(st.unit_id) if state.units != null else null
	var full := unit.men if unit != null else st.men
	var stack := {"uomini": st.men, "pieni": full, "valore": st.value, "armi": st.weapon, "armatura": st.armour}
	var stack_rows: Array = []
	stack_rows.append([Lang.t("Uomini"), Lang.t("%d su %d") % [st.men, full] if full > 0 else str(st.men)])
	if st.value > 0:
		stack_rows.append([Lang.t("Valore"), "%d" % st.value])
	if st.weapon > 0:
		stack_rows.append([Lang.t("Armi"), "%s (+%d)" % [Lang.t(str(TroopUpgrades.METALS[clampi(st.weapon, 1, TroopUpgrades.MAX_LEVEL)])), st.weapon]])
	if st.armour > 0:
		stack_rows.append([Lang.t("Armatura"), "%s (+%d)" % [Lang.t(str(TroopUpgrades.METALS[clampi(st.armour, 1, TroopUpgrades.MAX_LEVEL)])), st.armour]])
	var fight := fight_rows(unit)
	var costs := cost_rows(unit, state, army.faction)
	var rows: Array = []
	rows.append_array(stack_rows)
	for r in fight:
		rows.append([r[0], r[1]])
	rows.append_array(costs.filter(func(r: Array) -> bool: return str(r[0]) != Lang.t("Addestramento")))
	var note := ""
	if index == CampaignUiText.commander_stack(state, army):
		note = CampaignUiText.commander_stack_note(state, army)
	return {
		"unita": st.unit_id,
		"nome": CampaignUiText.unit_name(st.unit_id),
		"tipo": type_text(unit),
		"righe": rows,
		"descrizione": UnitTexts.description(st.unit_id),
		"uomini": st.men,
		"comandante": note,
		"pila": stack,
		"combattimento": fight,
		"nave": unit != null and unit.is_ship(),
		"costi": costs,
		"arruolamento": recruit_rows(state, unit),
	}


## Scheda di un tipo di unita' non ancora arruolata (finestra di arruolamento): uomini pieni, niente stato della pila ne'
## comandante.
static func info_for_type(state: GameState, unit_id: String, faction_id: String = "") -> Dictionary:
	var unit := state.units.get_unit(unit_id) if state.units != null else null
	var probe := Army.new()
	probe.faction = faction_id   # ADR-089: costi con i tratti della fazione
	probe.stacks.append(UnitStack.new(unit_id, unit.men if unit != null else 0, 0))
	var out := info(state, probe, 0)
	out["comandante"] = ""
	out["pila"] = {}
	return out


## Valori di combattimento: [etichetta, valore, suggerimento]. Per le navi attacco, difesa, velocita' e raggio.
static func fight_rows(unit: UnitType) -> Array:
	var out: Array = []
	if unit == null or unit.is_agent():
		return out
	if unit.is_ship_data and unit.is_ship():
		out.append([Lang.t("Attacco"), str(unit.ship_attack), Lang.t("Forza negli scontri navali")])
		out.append([Lang.t("Difesa"), str(unit.ship_defence), Lang.t("Resistenza negli scontri navali")])
		out.append([Lang.t("Velocità"), str(unit.ship_speed), Lang.t("Velocità della nave")])
		out.append([Lang.t("Raggio"), str(unit.ship_range), Lang.t("Zone di mare percorse in un anno")])
		return out
	out.append([Lang.pick("Carica", "Charge"), CampaignUiText.signed(unit.charge_bonus), Lang.t("Bonus all'impatto della carica")])
	out.append([Lang.t("Mischia"), CampaignUiText.signed(unit.melee_bonus), Lang.t("Bonus nel combattimento corpo a corpo")])
	out.append([Lang.t("Difesa"), CampaignUiText.signed(unit.defence_bonus), Lang.t("Bonus in difesa")])
	out.append([Lang.t("Armatura base"), str(unit.armour_level), Lang.t("Livello di armatura dell'unità, prima dell'armaiolo")])
	if unit.has_moral_bonus:
		out.append([Lang.t("Morale"), CampaignUiText.signed(unit.moral_bonus), Lang.t("Bonus al morale")])
	if unit.projectile != "" and unit.projectile != "NONE" and unit.ammo > 0:
		out.append([Lang.t("Munizioni"), str(unit.ammo), Lang.t("Tiri a disposizione in battaglia")])
	return out


## Costo, mantenimento e anni di addestramento del tipo di unita' (con i tratti della fazione, ADR-089, se data).
static func cost_rows(unit: UnitType, state: GameState = null, faction_id: String = "") -> Array:
	var out: Array = []
	if unit == null:
		return out
	var traits: FactionTraits = state.rules.traits if state != null and state.rules != null else FactionTraits.new()
	var years := traits.unit_years(faction_id, unit)
	out.append([Lang.t("Costo"), Lang.t("%d fiorini") % traits.unit_cost(faction_id, unit)])
	out.append([Lang.t("Mantenimento"), Lang.t("%d l'anno") % roundi(float(unit.support_cost) * traits.upkeep_factor(faction_id, unit))])
	out.append([Lang.t("Addestramento"), "%d %s" % [years, Lang.t("anno") if years == 1 else Lang.t("anni")]])
	return out


## Condizioni di arruolamento in parole: edifici richiesti (nomi italiani), epoche, regioni, cavalcatura.
static func recruit_rows(state: GameState, unit: UnitType) -> Array:
	var out: Array = []
	if unit == null:
		return out
	var needs := CampaignUiBuildingInfo.requires_text(state, unit.requires)
	out.append([Lang.t("Richiede"), needs if needs != "" else Lang.t("nessun edificio")])
	var eras := PackedStringArray()
	for p in unit.periods:
		var key := str(p).to_upper()
		if key == "ALL_PERIODS":
			eras.clear()
			break
		eras.append(CampaignUiText.era_name(key))
	out.append([Lang.t("Epoche"), Lang.t("tutte") if eras.is_empty() else ", ".join(eras)])
	if not unit.regions.is_empty():
		var names := PackedStringArray()
		for r in unit.regions:
			names.append(CampaignUiText.region_name(state, str(r)))
		out.append([Lang.t("Solo in"), ", ".join(names)])
	if unit.men > 0 and not unit.is_ship() and not unit.is_agent():
		out.append([Lang.t("Uomini"), str(unit.men)])
	return out


## «Cavalleria pesante», «Fanteria · tiratori»: tipo della colonna 1 con le classi della colonna 17.
static func type_text(unit: UnitType) -> String:
	if unit == null:
		return ""
	if unit.is_agent():
		return Lang.t("Agente")
	var base := Lang.t(str(TYPE_NAMES[unit.type_name.to_upper()])) if TYPE_NAMES.has(unit.type_name.to_upper()) else unit.type_name.capitalize()
	if unit.is_ship():
		base = Lang.t("Nave")
	var extra := PackedStringArray()
	for cls in unit.unit_classes:
		var key := str(cls).to_upper()
		if CLASS_NAMES.has(key) and not extra.has(Lang.t(str(CLASS_NAMES[key]))):
			extra.append(Lang.t(str(CLASS_NAMES[key])))
	if unit.mount_type == "CAMEL":
		extra.append(Lang.t("su cammello"))
	return base if extra.is_empty() else "%s · %s" % [base, ", ".join(extra)]
