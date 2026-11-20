class_name CampaignUiBuildingInfo
extends RefCounted
## Scheda di un edificio (segnalazione di Federico del 2026-11-10: mancava la finestra di dettaglio). Dal 2026-11-15
## (richiesta di Federico) senza le illustrazioni dell'originale: l'immagine e' l'icona rifatta ingrandita e i dati sono
## divisi in sezioni (effetti, costi, requisiti, unita' che il livello permette di arruolare, livelli vicini). Funzione
## pura sullo stato; `righe` resta l'elenco piatto di tutte le voci.

## Nomi brevi: la scheda ha quattro colonne strette (le reclute della provincia ricevono il miglioramento).
const UPGRADE_NAMES := {
	"UPGRADE_ARMOUR": "armatura",
	"UPGRADE_WEAPON": "armi",
	"UPGRADE_MORALE": "morale",
	"UPGRADE_VALOUR": "valore",
	"UPGRADE_LOYALTY": "lealtà",
	"UPGRADE_HAPPINESS": "lealtà",
}


## {"nome", "tipo", "righe": [[etichetta, valore]], "descrizione", "etichetta" (nome nel file prod), "infopic" (nome
## dell'illustrazione nella colonna 7), "famiglia", "livello", "livelli" (quanti ne ha la famiglia),
##  "effetti": [[etichetta, valore]], "costi": [[etichetta, valore]], "requisiti": [[etichetta, valore]],
##  "sblocca": ids delle unita' che diventano arruolabili a questo livello (per `faction_id`, se dato),
##  "successivo"/"precedente": nome del livello vicino ("" se non c'e')}. Vuoto se la famiglia o il livello non esistono.
static func info(state: GameState, family_id: String, level: int, faction_id: String = "") -> Dictionary:
	var fam: BuildingType = state.buildings.get_family(family_id) if state.buildings != null else null
	if fam == null:
		return {}
	var lv: BuildingType.Level = fam.get_level(maxi(1, level))
	if lv == null:
		return {}
	var levels := fam.levels.size()
	var effects: Array = []
	if lv.income != 0:
		effects.append([Lang.t("Rendita"), Lang.t("%d fiorini l'anno") % lv.income])
	if lv.happiness != 0:
		effects.append([Lang.t("Lealtà"), CampaignUiText.signed(lv.happiness)])
	if lv.capacity > 0:
		effects.append([Lang.t("Guarnigione"), Lang.t("%d unità") % lv.capacity])
	for up in lv.upgrades:
		var text := upgrade_text(str(up))
		if text != "":
			effects.append([Lang.t("Reclute"), text])
	if lv.faith > 0.0:
		effects.append([Lang.t("Fede"), Lang.t("si diffonde (%s)") % String.num(lv.faith, 2)])
	if lv.mercenary_magnetism > 0:
		effects.append([Lang.t("Mercenari"), Lang.t("li attira (%d)") % lv.mercenary_magnetism])
	var years := state.rules.traits.building_years(faction_id, lv) if state.rules != null else maxi(1, lv.build_time)   # ADR-089
	var price := state.rules.traits.building_cost(faction_id, lv) if state.rules != null else lv.cost
	var costs: Array = [[Lang.t("Costo"), Lang.t("%d fiorini") % price], [Lang.t("Costruzione"), "%d %s" % [years, Lang.t("anno") if years == 1 else Lang.t("anni")]]]
	var reqs: Array = []
	var needs := requires_text(state, lv.requires)
	reqs.append([Lang.t("Richiede"), needs if needs != "" else Lang.t("nessun edificio")])
	if not lv.resources.is_empty():
		var res := PackedStringArray()
		for r in lv.resources:
			res.append(UiIcons.label_for("risorse", str(r)))
		reqs.append([Lang.t("Giacimenti"), ", ".join(res)])
	var next: BuildingType.Level = fam.get_level(lv.level + 1)
	var prev: BuildingType.Level = fam.get_level(lv.level - 1) if lv.level > 1 else null
	var rows: Array = []
	if levels > 1:
		rows.append([Lang.t("Livello"), Lang.t("%d su %d") % [lv.level, levels]])
	rows.append_array(costs)
	rows.append_array(effects)
	if next != null:
		rows.append([Lang.t("Livello successivo"), CampaignUiText.building_name(state, family_id, next.level)])
	return {
		"nome": CampaignUiText.building_name(state, family_id, lv.level),
		"tipo": Lang.t("Edificio") if levels <= 1 else Lang.t("Edificio · livello %d su %d") % [lv.level, levels],
		"righe": rows,
		"descrizione": UnitTexts.description(lv.label),
		"etichetta": lv.label,
		"infopic": infopic_name(fam, lv.level),
		"famiglia": fam.id,
		"livello": lv.level,
		"livelli": levels,
		"effetti": effects,
		"costi": costs,
		"requisiti": reqs,
		"sblocca": unlocked_units(state, fam.id, lv.level, faction_id),
		"successivo": CampaignUiText.building_name(state, family_id, next.level) if next != null else "",
		"precedente": CampaignUiText.building_name(state, family_id, prev.level) if prev != null else "",
	}


## Unita' (truppe, navi, agenti) che hanno tra i requisiti proprio questo livello della famiglia: quelle che il livello
## rende arruolabili. Con `faction_id` solo quelle che la fazione puo' arruolare (gli Auror tutte le truppe e navi).
static func unlocked_units(state: GameState, family_id: String, level: int, faction_id: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	if state.units == null or state.buildings == null:
		return out
	for u in state.units.units:
		if not (u.is_military() or u.is_agent()):
			continue
		if faction_id != "" and not (u.recruitable_by(faction_id) or state.rules.lifts_unit_limits(faction_id, u)):
			continue
		var hit := false
		for token in u.required_tokens():
			var lv: BuildingType.Level = state.buildings.resolve(token)
			if lv != null and lv.family == family_id and lv.level == level:
				hit = true
				break
		if hit:
			out.append(u.id)
	return out


## Condizione sugli edifici con i nomi italiani: gruppi alternativi separati da « oppure », edifici di un gruppo da « e ».
static func requires_text(state: GameState, condition: Array[PackedStringArray]) -> String:
	var groups := PackedStringArray()
	for group in condition:
		var parts := PackedStringArray()
		for token in group:
			var lv: BuildingType.Level = state.buildings.resolve(token) if state.buildings != null else null
			parts.append(CampaignUiText.building_name(state, lv.family, lv.level) if lv != null else str(token).capitalize())
		if not parts.is_empty():
			groups.append(Lang.t(" e ").join(parts))
	return Lang.t(" oppure ").join(groups)


## Nome dell'illustrazione del livello nella colonna 7 del file prod («Strategy map infopic filename»: una voce per livello,
## separate da virgole), "" se manca.
static func infopic_name(fam: BuildingType, level: int) -> String:
	if fam == null or fam.raw.size() <= 7:
		return ""
	var parts := fam.raw[7].replace("\"", "").split(",")
	var i := level - 1
	if i < 0 or i >= parts.size():
		return ""
	return parts[i].strip_edges()


## «armatura +1» da «UPGRADE_ARMOUR(1)»; "" per le voci vuote.
static func upgrade_text(raw: String) -> String:
	var clean := raw.strip_edges().replace("{", "").replace("}", "")
	if clean == "":
		return ""
	var key := clean.get_slice("(", 0).strip_edges().to_upper()
	var amount := clean.get_slice("(", 1).trim_suffix(")").strip_edges() if clean.contains("(") else ""
	var name := Lang.t(str(UPGRADE_NAMES[key])) if UPGRADE_NAMES.has(key) else key.trim_prefix("UPGRADE_").to_lower().replace("_", " ")
	return "%s +%s" % [name, amount] if amount != "" else name
