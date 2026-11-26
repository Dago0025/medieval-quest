class_name MercenaryRules
extends RefCounted
## Parametri dei mercenari (fase 8d, ADR-004), letti da data/regole/mercenari.cfg. I predefiniti sono uguali al file.

const DEFAULT_PATH := "res://data/regole/mercenari.cfg"

var new_per_year := 8
var base_pull := 1
var hub_pull := 6
var max_per_province := 4
var max_age := 6
var move_chance := 0.3
var hire_factor := 1.5
var upkeep_factor := 2.0
var disbanded_join := true   ## le truppe congedate diventano compagnie di mercenari nella provincia (manuale p26 e p70; ADR-031)
## Regioni della mappa del mondo dove compaiono solo i mercenari del posto, cioe' le unita' che elencano la regione (ADR-116:
## niente compagnie europee della XL in Asia orientale, India del sud, Africa nera, Americhe, Oceania). Elenco della mappa,
## vuoto sulla mappa d'Europa e quindi fuori da `to_dict`.
var local_only_regions := PackedStringArray()

var errors := PackedStringArray()


static func load_file(path: String = DEFAULT_PATH) -> MercenaryRules:
	var r := MercenaryRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole dei mercenari non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	r.new_per_year = int(cfg.get_value("comparsa", "nuove_per_anno", r.new_per_year))
	r.base_pull = int(cfg.get_value("comparsa", "richiamo_base", r.base_pull))
	r.hub_pull = int(cfg.get_value("comparsa", "richiamo_hub", r.hub_pull))
	r.max_per_province = int(cfg.get_value("comparsa", "max_per_provincia", r.max_per_province))
	r.max_age = int(cfg.get_value("vita", "durata_massima", r.max_age))
	r.move_chance = float(cfg.get_value("vita", "prob_spostamento", r.move_chance))
	r.hire_factor = float(cfg.get_value("costi", "fattore_ingaggio", r.hire_factor))
	r.upkeep_factor = float(cfg.get_value("costi", "fattore_mantenimento", r.upkeep_factor))
	r.disbanded_join = bool(cfg.get_value("congedo", "diventano_mercenari", r.disbanded_join))
	for rid in cfg.get_value("mondo", "solo_mercenari_locali", []):
		r.local_only_regions.append(str(rid).strip_edges().to_upper())
	if r.new_per_year < 0 or r.max_per_province < 1 or r.max_age < 1 or r.move_chance < 0.0 or r.move_chance > 1.0:
		r.errors.append("Regole dei mercenari fuori scala in %s" % path)
	return r


## Vero se nella regione possono comparire solo i mercenari che la elencano (ADR-116).
func local_only(region_id: String) -> bool:
	return not local_only_regions.is_empty() and local_only_regions.has(region_id.strip_edges().to_upper())


## Costo di ingaggio di un'unita' di costo `unit_cost`.
func hire_cost(unit_cost: int) -> int:
	return ceili(float(unit_cost) * hire_factor)


func to_dict() -> Dictionary:
	return {"new_per_year": new_per_year, "base_pull": base_pull, "hub_pull": hub_pull, "max_per_province": max_per_province,
		"max_age": max_age, "move_chance": move_chance, "hire_factor": hire_factor, "upkeep_factor": upkeep_factor,
		"disbanded_join": disbanded_join}
