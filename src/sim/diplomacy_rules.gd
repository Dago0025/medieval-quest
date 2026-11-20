class_name DiplomacyRules
extends RefCounted
## Parametri della diplomazia della fase 5a (ADR-004, ADR-010), letti da data/regole/diplomazia.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file, cosi' i test girano anche senza file (un test
## controlla che restino uguali). Il codice della simulazione legge solo da questa classe, che `Rules` espone come
## `rules.diplomacy`. La formula di accettazione e la durata delle tregue sono PROVVISORIE (catalogo, sezione
## "Agenti e diplomazia": formula ignota, cala con la dimensione dell'impero); il file dice quali parametri lo sono.

const DEFAULT_PATH := "res://data/regole/diplomazia.cfg"

# --- trattati ---
var betrayal_malus := 1              ## PROVVISORIA: influenza persa dal capo che attacca un alleato o una tregua
var truce_years := 6                 ## PROVVISORIA: anni interi di tregua dopo l'anno della firma
## Alleanze in conflitto (catalogo, MTW Diplomacy): chi e' alleato di due fazioni che si fanno guerra resta alleato di una sola.
var conflicting_alliances := true

# --- accettazione delle proposte (PROVVISORIA) ---
var p_min := 0.05
var p_max := 0.95
var base_alliance := 0.35
var base_truce := 0.30
var base_marriage := 0.45
var neutral_influence := 5
var k_influence := 0.04
var k_valour := 0.03
var same_religion_bonus := 0.10
var other_religion_malus := 0.15
var size_threshold := 0.25
var k_size := 2.0
var allies_war_malus := 0.20
var k_strength := 0.6
var k_weariness := 0.04              ## tregua: per anno di guerra senza svolte (PROVVISORIA)
var weariness_max_years := 10        ## anni oltre i quali la stanchezza non cresce piu'

## Errori di lettura del file (chiave con tipo sbagliato e simili).
var errors := PackedStringArray()


## Regole dal file `path`; le chiavi mancanti restano ai valori predefiniti. Se il file non c'e' o non si
## legge: valori predefiniti e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH) -> DiplomacyRules:
	var r := DiplomacyRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole della diplomazia non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	r.betrayal_malus = _int(cfg, "trattati", "malus_tradimento", r.betrayal_malus)
	r.truce_years = _int(cfg, "trattati", "durata_tregua", r.truce_years)
	r.conflicting_alliances = _bool(cfg, "trattati", "alleanze_in_conflitto", r.conflicting_alliances)
	r.p_min = _float(cfg, "accettazione", "p_min", r.p_min)
	r.p_max = _float(cfg, "accettazione", "p_max", r.p_max)
	r.base_alliance = _float(cfg, "accettazione", "base_alleanza", r.base_alliance)
	r.base_truce = _float(cfg, "accettazione", "base_tregua", r.base_truce)
	r.base_marriage = _float(cfg, "accettazione", "base_matrimonio", r.base_marriage)
	r.neutral_influence = _int(cfg, "accettazione", "influenza_neutra", r.neutral_influence)
	r.k_influence = _float(cfg, "accettazione", "k_influenza", r.k_influence)
	r.k_valour = _float(cfg, "accettazione", "k_valore", r.k_valour)
	r.same_religion_bonus = _float(cfg, "accettazione", "bonus_stessa_religione", r.same_religion_bonus)
	r.other_religion_malus = _float(cfg, "accettazione", "malus_religione_diversa", r.other_religion_malus)
	r.size_threshold = _float(cfg, "accettazione", "soglia_dimensione", r.size_threshold)
	r.k_size = _float(cfg, "accettazione", "k_dimensione", r.k_size)
	r.allies_war_malus = _float(cfg, "accettazione", "malus_guerra_alleati", r.allies_war_malus)
	r.k_strength = _float(cfg, "accettazione", "k_forza", r.k_strength)
	r.k_weariness = _float(cfg, "accettazione", "k_stanchezza", r.k_weariness)
	r.weariness_max_years = _int(cfg, "accettazione", "anni_stanchezza_max", r.weariness_max_years)
	r._check_consistency()
	return r


## Tutti i parametri in un Dictionary (per confronti nei test e per i rapporti).
func to_dict() -> Dictionary:
	return {
		"betrayal_malus": betrayal_malus,
		"truce_years": truce_years,
		"conflicting_alliances": conflicting_alliances,
		"p_min": p_min,
		"p_max": p_max,
		"base_alliance": base_alliance,
		"base_truce": base_truce,
		"base_marriage": base_marriage,
		"neutral_influence": neutral_influence,
		"k_influence": k_influence,
		"k_valour": k_valour,
		"same_religion_bonus": same_religion_bonus,
		"other_religion_malus": other_religion_malus,
		"size_threshold": size_threshold,
		"k_size": k_size,
		"allies_war_malus": allies_war_malus,
		"k_strength": k_strength,
		"k_weariness": k_weariness,
		"weariness_max_years": weariness_max_years,
	}


func _check_consistency() -> void:
	var defaults := DiplomacyRules.new()
	if truce_years < 1:
		errors.append("trattati/durata_tregua non valida: uso 6")
		truce_years = defaults.truce_years
	if p_min < 0.0 or p_max > 1.0 or p_min > p_max:
		errors.append("accettazione/p_min e p_max incoerenti: uso i predefiniti")
		p_min = defaults.p_min
		p_max = defaults.p_max
	if weariness_max_years < 0:
		errors.append("accettazione/anni_stanchezza_max negativo: uso 10")
		weariness_max_years = defaults.weariness_max_years
	if size_threshold < 0.0 or size_threshold > 1.0:
		errors.append("accettazione/soglia_dimensione fuori da [0, 1]: uso 0,25")
		size_threshold = defaults.size_threshold


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
	return fallback
