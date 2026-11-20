class_name ConquestDamage
extends RefCounted
## Edifici distrutti o danneggiati quando una provincia cambia mano (richiesta di Federico del 15/11: «poteva capitare
## conquistando una provincia che alcuni edifici venissero distrutti»). Regole PROVVISORIE in economia.cfg [conquista]
## (`Rules.conquest_*`): ogni famiglia costruita perde un livello con una probabilita' che cala con il livello del castello e
## dipende dal modo (campo, assedio, porte aperte da una spia, guarnigione corrotta); gli edifici di un'altra religione vanno
## sempre persi; dopo un assedio il castello puo' perdere un livello. Livello 1 perso = edificio distrutto.

const MEANS_FIELD := "campo"
const MEANS_SIEGE := "assedio"
const MEANS_GATES := "porte"
const MEANS_BRIBE := "corruzione"


## Applica i danni e restituisce {"distrutti": [token], "danneggiati": [token]} (token del livello perso, es. "BOWYER2").
static func apply(state: GameState, province: ProvinceState, conqueror: String, means: String) -> Dictionary:
	var out := {"distrutti": PackedStringArray(), "danneggiati": PackedStringArray()}
	var rules := state.rules
	var castle := rules.combat.castle_family
	var castle_level := province.level_of(castle)
	var factor := float(rules.conquest_means.get(means, 1.0))
	var chance := maxf(rules.conquest_min_chance, rules.conquest_building_chance - rules.conquest_castle_protection * castle_level) * factor
	var cf := state.campaign.faction(conqueror)
	var religion := GameCommands.religion_key(cf.religion) if cf != null and cf.religion != "" else ""
	var families: Array = province.buildings.keys()
	families.sort()   # ordine fisso: il generatore casuale resta deterministico
	for fam_id in families:
		var level := province.level_of(str(fam_id))
		if level <= 0:
			continue
		var family := state.buildings.get_family(str(fam_id))
		if family == null:
			continue
		if family.id == castle:
			if means == MEANS_SIEGE and level > 1 and state.rng.randf() < rules.conquest_castle_drop:
				_lose(province, family, level, out)
			continue
		if rules.conquest_other_religion and religion != "" and not family.religions.is_empty() and not GameCommands.building_allows_religion(family, religion):
			var gone: PackedStringArray = out["distrutti"]   # gli array impacchettati si copiano: si rimette la copia
			for lv in range(level, 0, -1):
				gone.append(family.token(lv))
			out["distrutti"] = gone
			province.set_level(family.id, 0)
			continue
		if chance > 0.0 and state.rng.randf() < chance:
			_lose(province, family, level, out)
	return out


static func _lose(province: ProvinceState, family: BuildingType, level: int, out: Dictionary) -> void:
	province.set_level(family.id, level - 1)
	var key := "distrutti" if level == 1 else "danneggiati"
	var list: PackedStringArray = out[key]   # gli array impacchettati si copiano: si rimette la copia
	list.append(family.token(level))
	out[key] = list


## Frase per il resoconto («Distrutti: Arciere. Danneggiati: Fortezza (ora Castello).»), "" se nessun danno.
static func describe(state: GameState, damage: Dictionary) -> String:
	var parts := PackedStringArray()
	var gone: PackedStringArray = damage.get("distrutti", PackedStringArray())
	var hit: PackedStringArray = damage.get("danneggiati", PackedStringArray())
	if not gone.is_empty():
		parts.append(Lang.t("Edifici distrutti: %s.") % ", ".join(_names(state, gone)))
	if not hit.is_empty():
		parts.append(Lang.t("Edifici danneggiati (un livello in meno): %s.") % ", ".join(_names(state, hit)))
	return " ".join(parts)


static func _names(state: GameState, tokens: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for t in tokens:
		var lv := state.buildings.resolve(t)
		out.append(CampaignUiText.building_name(state, lv.family, lv.level) if lv != null else t)
	return out
