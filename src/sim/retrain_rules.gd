class_name RetrainRules
extends RefCounted
## Parametri del riaddestramento delle unita' (ADR-004, ADR-010), letti da data/regole/riaddestramento.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file, cosi' i test girano anche senza file (un test lo
## controlla). Il codice della simulazione legge solo da questa classe, che `Rules` espone come `rules.retrain`.
## La meccanica (una pila decimata torna all'organico pieno pagando) e' quella dell'originale; la formula del costo, il
## limite per provincia e la diluizione del valore sono PROVVISORI (il file dice perche').

const DEFAULT_PATH := "res://data/regole/riaddestramento.cfg"

## PROVVISORIA: pile riaddestrabili in una provincia in un anno (contando gli ordini gia' dati).
var max_per_province := 4
## PROVVISORIA: fattore sul costo proporzionale `costo x uomini mancanti / uomini pieni`.
var cost_factor := 1.0
## Ripristino delle forze (richiesta di Federico, 2026-11-13, ADR-046): un clic riporta all'organico pieno, entro fine anno,
## tutte le pile dell'esercito fermo in una provincia propria. Scelte di Federico, non dell'originale:
## vero = solo le unita' reclutabili nella provincia (come il riaddestramento); falso = in qualsiasi provincia propria.
var restore_needs_buildings := false
## vero = conta il limite di pile per provincia e anno; falso = tutte le pile insieme.
var restore_uses_limit := false
## vero = anche le compagnie di mercenari tornano piene.
var restore_mercenaries := true

## Errori di lettura del file (chiave con tipo sbagliato, valore fuori scala).
var errors := PackedStringArray()


## Regole dal file `path`; le chiavi mancanti restano ai valori predefiniti. Se il file non c'e' o non si legge: valori
## predefiniti e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH) -> RetrainRules:
	var r := RetrainRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole del riaddestramento non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	r.max_per_province = _int(cfg, "limiti", "max_per_provincia", r.max_per_province)
	r.cost_factor = _float(cfg, "costo", "fattore", r.cost_factor)
	r.restore_needs_buildings = _bool(cfg, "ripristino", "edifici_richiesti", r.restore_needs_buildings)
	r.restore_uses_limit = _bool(cfg, "ripristino", "limite_per_provincia", r.restore_uses_limit)
	r.restore_mercenaries = _bool(cfg, "ripristino", "mercenari", r.restore_mercenaries)
	r._check_consistency()
	return r


## Costo di riaddestrare una pila di `men` uomini su `full` (uomini pieni dell'unita') di costo `unit_cost`:
## ceil(costo x fattore x uomini mancanti / uomini pieni). 0 se la pila e' piena (o l'organico non e' valido).
func cost_for(unit_cost: int, men: int, full: int) -> int:
	if full <= 0 or men >= full:
		return 0
	var missing := full - maxi(0, men)
	# snappedf: un fattore non esatto in binario non deve far salire il risultato di un fiorino
	return ceili(snappedf(float(unit_cost) * cost_factor * float(missing) / float(full), 0.000001))


## Valore (esperienza) di una pila dopo il riaddestramento: floor(valore x uomini prima / uomini pieni), in interi.
@warning_ignore("integer_division")
static func diluted_value(value: int, men_before: int, full: int) -> int:
	if full <= 0:
		return value
	return maxi(0, value) * clampi(men_before, 0, full) / full


## Tutti i parametri in un Dictionary (per confronti nei test e per i rapporti).
func to_dict() -> Dictionary:
	return {"max_per_province": max_per_province, "cost_factor": cost_factor, "restore_needs_buildings": restore_needs_buildings,
		"restore_uses_limit": restore_uses_limit, "restore_mercenaries": restore_mercenaries}


func _check_consistency() -> void:
	var defaults := RetrainRules.new()
	if max_per_province < 0:
		errors.append("limiti/max_per_provincia negativo: uso 4")
		max_per_province = defaults.max_per_province
	if cost_factor < 0.0:
		errors.append("costo/fattore negativo: uso 1.0")
		cost_factor = defaults.cost_factor


# I valori mancanti restano al predefinito; si legge il valore solo dopo aver controllato che la chiave esista.
static func _int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return fallback


static func _float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v)
	return fallback


static func _bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key)
	if typeof(v) == TYPE_BOOL:
		return bool(v)
	if typeof(v) == TYPE_INT:
		return int(v) != 0
	return fallback
