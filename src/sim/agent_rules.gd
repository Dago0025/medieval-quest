class_name AgentRules
extends RefCounted
## Parametri degli agenti della fase 5a (ADR-004, ADR-010), letti da data/regole/agenti.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file, cosi' i test girano anche senza file (un test
## controlla che restino uguali). Il codice della simulazione legge solo da questa classe, che `Rules` espone come
## `rules.agents`. Dove una regola non ha fonte e' PROVVISORIA (catalogo, sezione "Agenti e diplomazia"); il file
## dice quali parametri lo sono. Documentati (confidenza Media): la tabella a 16 gradini dell'assassino e i gradini
## di partenza per tipo di bersaglio.

const DEFAULT_PATH := "res://data/regole/agenti.cfg"

# --- reclutamento e valore ---
var base_valour := 1                 ## PROVVISORIA
var valour_per_level := 1            ## PROVVISORIA
var start_valour := 2                ## PROVVISORIA: emissari dello startpos
var max_valour := 10                 ## PROVVISORIA
var valour_growth := 1               ## PROVVISORIA: dopo una missione riuscita o la cattura di un agente nemico

# --- corruzione ---
var bribe_price_k := 3.0             ## PROVVISORIA
var bribe_base := 0.9                ## PROVVISORIA
var bribe_k_loyalty := 0.08          ## PROVVISORIA
var bribe_k_valour := 0.03           ## PROVVISORIA
var bribe_p_min := 0.05
var bribe_p_max := 0.95

# --- assassinio (tabella documentata, parametri di contorno PROVVISORI) ---
var kill_steps := PackedInt32Array([0, 7, 10, 14, 17, 24, 34, 50, 66, 76, 83, 86, 90, 93, 95, 97])
var step_leader := 4
var step_noble := 6                  ## erede, principe, generale
var step_princess := 7
var step_spy := 8                    ## spia e assassino
var step_religious := 9
var step_emissary := 10
var fail_death_chance := 0.5         ## PROVVISORIA

# --- spie ---
var spy_loyalty_bonus := 5           ## PROVVISORIA
var spy_loyalty_malus := 5           ## PROVVISORIA
var gates_k := 0.05                  ## PROVVISORIA: per punto di valore
# missioni delle spie (richiesta di Federico del 18/11/2026, tutte PROVVISORIE): probabilita' = base + k * valore
var intel_base := 0.5                ## spiare una provincia o un esercito
var intel_k := 0.05
var intel_years := 3                 ## anni in cui le informazioni restano valide
var unrest_base := 0.35              ## fomentare il malcontento
var unrest_k := 0.06
var unrest_base_loyalty := 5         ## malus di lealta' = base + per_stella * valore, per `unrest_years` anni
var unrest_per_star := 2
var unrest_years := 3
var sabotage_base := 0.2             ## sabotare un edificio (il castello no)
var sabotage_k := 0.05
var sabotage_max := 0.8
var sabotage_death := 0.3            ## se fallisce la spia muore con questa probabilita'
var gates_mission_factor := 2.0      ## la missione «apri le porte» vale il doppio della presenza passiva

# --- cattura (PROVVISORIA) ---
var capture_base := 0.10
var capture_k := 0.07
var capture_max := 0.8
var invisible_malus := 0.10
var border_fort_family := "WATCH_TOWERS"
var border_fort_per_level := 2

# --- matrimonio ---
var marriage_loyalty_bonus := 2

## Errori di lettura del file (chiave con tipo sbagliato e simili).
var errors := PackedStringArray()


## Regole dal file `path`; le chiavi mancanti restano ai valori predefiniti. Se il file non c'e' o non si
## legge: valori predefiniti e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH) -> AgentRules:
	var r := AgentRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole degli agenti non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	r.base_valour = _int(cfg, "reclutamento", "valore_base", r.base_valour)
	r.valour_per_level = _int(cfg, "reclutamento", "valore_per_livello", r.valour_per_level)
	r.start_valour = _int(cfg, "reclutamento", "valore_iniziale_startpos", r.start_valour)
	r.max_valour = _int(cfg, "reclutamento", "valore_max", r.max_valour)
	r.valour_growth = _int(cfg, "crescita", "crescita_valore", r.valour_growth)
	r.bribe_price_k = _float(cfg, "corruzione", "k_prezzo", r.bribe_price_k)
	r.bribe_base = _float(cfg, "corruzione", "p_base", r.bribe_base)
	r.bribe_k_loyalty = _float(cfg, "corruzione", "k_lealta", r.bribe_k_loyalty)
	r.bribe_k_valour = _float(cfg, "corruzione", "k_valore", r.bribe_k_valour)
	r.bribe_p_min = _float(cfg, "corruzione", "p_min", r.bribe_p_min)
	r.bribe_p_max = _float(cfg, "corruzione", "p_max", r.bribe_p_max)
	r.kill_steps = _ints(cfg, "assassinio", "gradini", r.kill_steps)
	r.step_leader = _int(cfg, "assassinio", "gradino_capo", r.step_leader)
	r.step_noble = _int(cfg, "assassinio", "gradino_erede", r.step_noble)
	r.step_princess = _int(cfg, "assassinio", "gradino_principessa", r.step_princess)
	r.step_spy = _int(cfg, "assassinio", "gradino_spia", r.step_spy)
	r.step_religious = _int(cfg, "assassinio", "gradino_religioso", r.step_religious)
	r.step_emissary = _int(cfg, "assassinio", "gradino_emissario", r.step_emissary)
	r.fail_death_chance = _float(cfg, "assassinio", "p_morte_fallimento", r.fail_death_chance)
	r.spy_loyalty_bonus = _int(cfg, "spie", "bonus_lealta_spia", r.spy_loyalty_bonus)
	r.spy_loyalty_malus = _int(cfg, "spie", "malus_lealta_spia", r.spy_loyalty_malus)
	r.gates_k = _float(cfg, "spie", "k_porte", r.gates_k)
	r.intel_base = _float(cfg, "spie", "base_spionaggio", r.intel_base)
	r.intel_k = _float(cfg, "spie", "k_spionaggio", r.intel_k)
	r.intel_years = _int(cfg, "spie", "anni_informazioni", r.intel_years)
	r.unrest_base = _float(cfg, "spie", "base_malcontento", r.unrest_base)
	r.unrest_k = _float(cfg, "spie", "k_malcontento", r.unrest_k)
	r.unrest_base_loyalty = _int(cfg, "spie", "lealta_malcontento", r.unrest_base_loyalty)
	r.unrest_per_star = _int(cfg, "spie", "lealta_malcontento_per_stella", r.unrest_per_star)
	r.unrest_years = _int(cfg, "spie", "anni_malcontento", r.unrest_years)
	r.sabotage_base = _float(cfg, "spie", "base_sabotaggio", r.sabotage_base)
	r.sabotage_k = _float(cfg, "spie", "k_sabotaggio", r.sabotage_k)
	r.sabotage_max = _float(cfg, "spie", "p_max_sabotaggio", r.sabotage_max)
	r.sabotage_death = _float(cfg, "spie", "p_morte_sabotaggio", r.sabotage_death)
	r.gates_mission_factor = _float(cfg, "spie", "fattore_missione_porte", r.gates_mission_factor)
	r.capture_base = _float(cfg, "cattura", "base_cattura", r.capture_base)
	r.capture_k = _float(cfg, "cattura", "k_cattura", r.capture_k)
	r.capture_max = _float(cfg, "cattura", "p_max_cattura", r.capture_max)
	r.invisible_malus = _float(cfg, "cattura", "malus_invisibile", r.invisible_malus)
	r.border_fort_family = _text(cfg, "cattura", "forte_di_confine", r.border_fort_family)
	r.border_fort_per_level = _int(cfg, "cattura", "valore_forte_per_livello", r.border_fort_per_level)
	r.marriage_loyalty_bonus = _int(cfg, "matrimonio", "bonus_lealta_matrimonio", r.marriage_loyalty_bonus)
	r._check_consistency()
	return r


## Probabilita' di riuscita dell'assassinio al gradino `step` (limitato alla tabella), da 0 a 1.
func kill_chance(step: int) -> float:
	return float(kill_steps[clampi(step, 0, kill_steps.size() - 1)]) / 100.0


## Ultimo gradino valido della tabella.
func max_step() -> int:
	return kill_steps.size() - 1


## Tutti i parametri in un Dictionary (per confronti nei test e per i rapporti).
func to_dict() -> Dictionary:
	return {
		"base_valour": base_valour,
		"valour_per_level": valour_per_level,
		"start_valour": start_valour,
		"max_valour": max_valour,
		"valour_growth": valour_growth,
		"bribe_price_k": bribe_price_k,
		"bribe_base": bribe_base,
		"bribe_k_loyalty": bribe_k_loyalty,
		"bribe_k_valour": bribe_k_valour,
		"bribe_p_min": bribe_p_min,
		"bribe_p_max": bribe_p_max,
		"kill_steps": Array(kill_steps),
		"step_leader": step_leader,
		"step_noble": step_noble,
		"step_princess": step_princess,
		"step_spy": step_spy,
		"step_religious": step_religious,
		"step_emissary": step_emissary,
		"fail_death_chance": fail_death_chance,
		"spy_loyalty_bonus": spy_loyalty_bonus,
		"spy_loyalty_malus": spy_loyalty_malus,
		"gates_k": gates_k,
		"intel_base": intel_base, "intel_k": intel_k, "intel_years": intel_years,
		"unrest_base": unrest_base, "unrest_k": unrest_k, "unrest_base_loyalty": unrest_base_loyalty,
		"unrest_per_star": unrest_per_star, "unrest_years": unrest_years,
		"sabotage_base": sabotage_base, "sabotage_k": sabotage_k, "sabotage_max": sabotage_max, "sabotage_death": sabotage_death,
		"gates_mission_factor": gates_mission_factor,
		"capture_base": capture_base,
		"capture_k": capture_k,
		"capture_max": capture_max,
		"invisible_malus": invisible_malus,
		"border_fort_family": border_fort_family,
		"border_fort_per_level": border_fort_per_level,
		"marriage_loyalty_bonus": marriage_loyalty_bonus,
	}


func _check_consistency() -> void:
	var defaults := AgentRules.new()
	if kill_steps.is_empty():
		errors.append("assassinio/gradini vuoto: uso i predefiniti")
		kill_steps = defaults.kill_steps
	if max_valour < 1:
		errors.append("reclutamento/valore_max non valido: uso 10")
		max_valour = defaults.max_valour
	if bribe_p_min < 0.0 or bribe_p_max > 1.0 or bribe_p_min > bribe_p_max:
		errors.append("corruzione/p_min e p_max incoerenti: uso i predefiniti")
		bribe_p_min = defaults.bribe_p_min
		bribe_p_max = defaults.bribe_p_max
	if capture_max < 0.0 or capture_max > 1.0:
		errors.append("cattura/p_max_cattura fuori da [0, 1]: uso 0,8")
		capture_max = defaults.capture_max


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


static func _text(cfg: ConfigFile, section: String, key: String, fallback: String) -> String:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key)
	if typeof(v) == TYPE_STRING:
		return String(v).strip_edges().to_upper()
	return fallback


static func _ints(cfg: ConfigFile, section: String, key: String, fallback: PackedInt32Array) -> PackedInt32Array:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key)
	if typeof(v) != TYPE_ARRAY:
		return fallback
	var out := PackedInt32Array()
	var items: Array = v
	for item in items:
		out.append(int(item))
	return out
