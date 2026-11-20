class_name VictoryRules
extends RefCounted
## Parametri della vittoria della fase 6b (ADR-004, ADR-011), letti da data/regole/vittoria.cfg.
##
## Il valore predefinito qui sotto e' uguale a quello del file (un test lo verifica). Le imprese gloriose sono escluse dal
## remake per scelta di Federico: si vince solo per dominio (manuale: due terzi delle province; community: 60% o 100%).

const DEFAULT_PATH := "res://data/regole/vittoria.cfg"

## Quota delle province di terra da controllare per il dominio (manuale: due terzi).
var domination_threshold := 0.85   ## scelta di Federico (85%); il manuale diceva due terzi

## Errori di lettura del file (chiave con tipo sbagliato, valore fuori scala).
var errors := PackedStringArray()


## Regole dal file `path`; la chiave mancante resta al valore predefinito. Se il file non c'e' o non si legge: valore
## predefinito e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH) -> VictoryRules:
	var r := VictoryRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole della vittoria non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	if cfg.has_section_key("dominio", "soglia_dominio"):
		var v: Variant = cfg.get_value("dominio", "soglia_dominio", r.domination_threshold)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			r.domination_threshold = float(v)
		else:
			r.errors.append("dominio/soglia_dominio non e' un numero: uso il valore predefinito")
	r._check_consistency()
	return r


## Province necessarie per il dominio su `total` province di terra: la quota per il totale, arrotondata a due decimali e poi
## per eccesso (cosi' 0.6667 su 72 province dice 48 e non 49), almeno 1 e al piu' il totale. 0 se non ci sono province.
func provinces_needed(total: int) -> int:
	if total <= 0:
		return 0
	var raw := snappedf(float(total) * domination_threshold, 0.01)
	return clampi(ceili(raw), 1, total)


func to_dict() -> Dictionary:
	return {"domination_threshold": domination_threshold}


func _check_consistency() -> void:
	if domination_threshold < 0.01 or domination_threshold > 1.0:
		errors.append("dominio/soglia_dominio fuori da 0.01..1: uso 0.85")
		domination_threshold = 0.85
