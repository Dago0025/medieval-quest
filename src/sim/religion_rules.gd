class_name ReligionRules
extends RefCounted
## Parametri della religione della fase 5b (ADR-004, ADR-010), letti da data/regole/religione.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file, cosi' i test girano anche senza file (un test
## controlla che restino uguali). Il codice della simulazione legge solo da questa classe, che `Rules` espone come
## `rules.religion`. Dove una regola non ha formula nel catalogo (sezione "Religione e Papato") e' PROVVISORIA;
## il file dice quali parametri lo sono.
##
## Composizione religiosa di una provincia (`ProvinceState.religions`): percentuali che sommano sempre a 100. I valori
## sono multipli di `ProvinceState.RELIGION_UNIT` (0,25): sono numeri esatti in binario, quindi la somma e' esatta.
## Ogni punteggio di questo file (deriva, conversioni...) e' arrotondato a quel passo quando si applica.

const DEFAULT_PATH := "res://data/regole/religione.cfg"

# --- composizione della partita nuova (PROVVISORIA: i dati non hanno percentuali) ---
var other_owner_share := 25          ## PROVVISORIA: % della religione del proprietario se diversa da quella della cultura
var initial_zeal := 50

# --- deriva ---
var drift := 1.0                     ## punti all'anno verso la religione del proprietario (catalogo: deriva lenta)

# --- edifici (catalogo: 10% e 15%, interpretati come intensita'; PROVVISORIA) ---
var building_points := 1.0           ## chiesa, moschea, monastero, santuario pagano
var big_building_points := 1.5       ## cattedrale, grande moschea
var big_faith := 0.15                ## un livello con propagazione della fede (col. 21) >= questa soglia e' «grande»

# --- religiosi (catalogo: 2% e 5%, conflitto da verificare; PROVVISORIA) ---
var agent_points := 2.0              ## se la colonna 45 di unit_prod non dice altro
var big_agent_points := 5.0
var big_agent_types := PackedStringArray(["CARDINAL", "ULAMA", "ORTHODOX_BISHOP"])
## Religione di un tipo di agente quando unit_prod non la dice; i tipi assenti (PRIEST) usano quella della fazione.
var type_religion := {
	"BISHOP": "CATHOLIC", "CARDINAL": "CATHOLIC", "INQUISITOR": "CATHOLIC", "GRAND_INQUISITOR": "CATHOLIC",
	"ORTHODOX_BISHOP": "ORTHODOX", "MULLAH": "MUSLIM", "ULAMA": "MUSLIM", "SHAMAN": "PAGAN", "MONK": "DHARMA",
}

# --- zelo ---
var neutral_zeal := 50
var zeal_decay := 1                  ## punti all'anno verso lo zelo neutro (PROVVISORIA)
var religious_zeal := 2              ## religioso della religione del proprietario, se la colonna 44 non dice altro
var big_religious_zeal := 5
var inquisitor_zeal := 2             ## catalogo: +2% (inquisitore) o +5% (grande); colonna 44 quando c'e'
var grand_inquisitor_zeal := 5

# --- eresia (catalogo: eventi, tasse eccessive; PROVVISORIA) ---
var heresy_growth := 1.0
var heresy_tax_level := 3            ## tassa da questo livello in su
var heresy_loyalty := 100            ## o lealta' sotto questo valore
var heretic_revolt_threshold := 30.0 ## % di eretici oltre la quale la rivolta e' eretica
var heretic_revolt_factor := 2.0     ## moltiplicatore della probabilita' di rivolta

# --- inquisitori ---
var inquisitor_points := 3.0         ## eretici in meno all'anno
var grand_inquisitor_points := 6.0
var inactive_malus := 3              ## PROVVISORIA: lealta' obiettivo per inquisitore senza eretici ne' processi
var trial_base := 0.3                ## PROVVISORIA
var trial_k_piety := 0.08
var trial_p_min := 0.05
var trial_p_max := 0.9
var agent_piety := 5                 ## PROVVISORIA: pieta' attribuita a un agente processato

## Errori di lettura del file (chiave con tipo sbagliato e simili).
var errors := PackedStringArray()


## Regole dal file `path`; le chiavi mancanti restano ai valori predefiniti. Se il file non c'e' o non si
## legge: valori predefiniti e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH) -> ReligionRules:
	var r := ReligionRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole della religione non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	r.other_owner_share = _int(cfg, "composizione", "quota_religione_proprietario", r.other_owner_share)
	r.initial_zeal = _int(cfg, "composizione", "zelo_iniziale", r.initial_zeal)
	r.drift = _float(cfg, "deriva", "deriva", r.drift)
	r.building_points = _float(cfg, "edifici", "conv_edificio", r.building_points)
	r.big_building_points = _float(cfg, "edifici", "conv_edificio_grande", r.big_building_points)
	r.big_faith = _float(cfg, "edifici", "soglia_fede_grande", r.big_faith)
	r.agent_points = _float(cfg, "religiosi", "conv_agente", r.agent_points)
	r.big_agent_points = _float(cfg, "religiosi", "conv_agente_grande", r.big_agent_points)
	r.big_agent_types = _texts(cfg, "religiosi", "tipi_grandi", r.big_agent_types)
	r.type_religion = _table(cfg, "religione_tipo", r.type_religion)
	r.neutral_zeal = _int(cfg, "zelo", "zelo_neutro", r.neutral_zeal)
	r.zeal_decay = _int(cfg, "zelo", "calo_zelo", r.zeal_decay)
	r.religious_zeal = _int(cfg, "zelo", "zelo_religioso", r.religious_zeal)
	r.big_religious_zeal = _int(cfg, "zelo", "zelo_religioso_grande", r.big_religious_zeal)
	r.inquisitor_zeal = _int(cfg, "zelo", "zelo_inquisitore", r.inquisitor_zeal)
	r.grand_inquisitor_zeal = _int(cfg, "zelo", "zelo_gran_inquisitore", r.grand_inquisitor_zeal)
	r.heresy_growth = _float(cfg, "eresia", "crescita_eresia", r.heresy_growth)
	r.heresy_tax_level = _int(cfg, "eresia", "tassa_alta", r.heresy_tax_level)
	r.heresy_loyalty = _int(cfg, "eresia", "lealta_sotto", r.heresy_loyalty)
	r.heretic_revolt_threshold = _float(cfg, "eresia", "soglia_rivolta_eretica", r.heretic_revolt_threshold)
	r.heretic_revolt_factor = _float(cfg, "eresia", "moltiplicatore_rivolta_eretica", r.heretic_revolt_factor)
	r.inquisitor_points = _float(cfg, "inquisitori", "conv_inquisitore", r.inquisitor_points)
	r.grand_inquisitor_points = _float(cfg, "inquisitori", "conv_gran_inquisitore", r.grand_inquisitor_points)
	r.inactive_malus = _int(cfg, "inquisitori", "malus_inquisitore_inattivo", r.inactive_malus)
	r.trial_base = _float(cfg, "processo", "base_processo", r.trial_base)
	r.trial_k_piety = _float(cfg, "processo", "k_pieta", r.trial_k_piety)
	r.trial_p_min = _float(cfg, "processo", "p_min_processo", r.trial_p_min)
	r.trial_p_max = _float(cfg, "processo", "p_max_processo", r.trial_p_max)
	r.agent_piety = _int(cfg, "processo", "pieta_agente", r.agent_piety)
	r._check_consistency()
	return r


# --- calcoli ---------------------------------------------------------------------------------------------


## Probabilita' del processo a un bersaglio di pieta' `piety`: base + k * (5 - pieta'), limitata (PROVVISORIA).
func trial_chance(piety: int) -> float:
	return clampf(trial_base + trial_k_piety * float(5 - piety), trial_p_min, trial_p_max)


## Chiave di religione ("CATHOLIC", "MUSLIM"...) da un token dei file ("REL_ISLAMIC", "ISLAMIC", "catholic"); "" se
## non e' una delle cinque religioni della provincia (per esempio JEWISH).
static func religion_key(token: String) -> String:
	var key := GameCommands.religion_key(token)
	if ProvinceState.RELIGIONS.has(key):
		return key
	return ""


## Elenco «PAGAN(0), CATHOLIC(2), ISLAMIC(0)» delle colonne 44 e 45 di unit_prod: religione -> punti, solo i valori
## maggiori di zero e le religioni note. Testo vuoto o illeggibile = Dictionary vuoto.
static func parse_points(text: String) -> Dictionary:
	var out := {}
	for part in text.split(",", false):
		var item := part.strip_edges().replace("\"", "")
		var open := item.find("(")
		var close := item.rfind(")")
		if open <= 0 or close < open:
			continue
		var key := religion_key(item.substr(0, open))
		var number := item.substr(open + 1, close - open - 1).strip_edges()
		if key == "" or not number.is_valid_float():
			continue
		var points := number.to_float()
		if points > 0.0:
			out[key] = points
	return out


## Tutti i parametri in un Dictionary (per confronti nei test e per i rapporti).
func to_dict() -> Dictionary:
	return {
		"other_owner_share": other_owner_share,
		"initial_zeal": initial_zeal,
		"drift": drift,
		"building_points": building_points,
		"big_building_points": big_building_points,
		"big_faith": big_faith,
		"agent_points": agent_points,
		"big_agent_points": big_agent_points,
		"big_agent_types": Array(big_agent_types),
		"type_religion": type_religion.duplicate(),
		"neutral_zeal": neutral_zeal,
		"zeal_decay": zeal_decay,
		"religious_zeal": religious_zeal,
		"big_religious_zeal": big_religious_zeal,
		"inquisitor_zeal": inquisitor_zeal,
		"grand_inquisitor_zeal": grand_inquisitor_zeal,
		"heresy_growth": heresy_growth,
		"heresy_tax_level": heresy_tax_level,
		"heresy_loyalty": heresy_loyalty,
		"heretic_revolt_threshold": heretic_revolt_threshold,
		"heretic_revolt_factor": heretic_revolt_factor,
		"inquisitor_points": inquisitor_points,
		"grand_inquisitor_points": grand_inquisitor_points,
		"inactive_malus": inactive_malus,
		"trial_base": trial_base,
		"trial_k_piety": trial_k_piety,
		"trial_p_min": trial_p_min,
		"trial_p_max": trial_p_max,
		"agent_piety": agent_piety,
	}


func _check_consistency() -> void:
	var defaults := ReligionRules.new()
	if other_owner_share < 0 or other_owner_share > 100:
		errors.append("composizione/quota_religione_proprietario fuori da [0, 100]: uso 25")
		other_owner_share = defaults.other_owner_share
	if initial_zeal < 0 or initial_zeal > 100:
		errors.append("composizione/zelo_iniziale fuori da [0, 100]: uso 50")
		initial_zeal = defaults.initial_zeal
	if neutral_zeal < 0 or neutral_zeal > 100:
		errors.append("zelo/zelo_neutro fuori da [0, 100]: uso 50")
		neutral_zeal = defaults.neutral_zeal
	if trial_p_min < 0.0 or trial_p_max > 1.0 or trial_p_min > trial_p_max:
		errors.append("processo/p_min_processo e p_max_processo incoerenti: uso i predefiniti")
		trial_p_min = defaults.trial_p_min
		trial_p_max = defaults.trial_p_max
	if heretic_revolt_factor < 0.0:
		errors.append("eresia/moltiplicatore_rivolta_eretica negativo: uso 2")
		heretic_revolt_factor = defaults.heretic_revolt_factor


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


static func _texts(cfg: ConfigFile, section: String, key: String, fallback: PackedStringArray) -> PackedStringArray:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key)
	if typeof(v) != TYPE_ARRAY:
		return fallback
	var out := PackedStringArray()
	var items: Array = v
	for item in items:
		out.append(String(item).strip_edges().to_upper())
	return out


## Sezione di coppie TIPO -> RELIGIONE (maiuscolo); una sezione assente lascia il predefinito.
static func _table(cfg: ConfigFile, section: String, fallback: Dictionary) -> Dictionary:
	if not cfg.has_section(section):
		return fallback
	var out := {}
	for key in cfg.get_section_keys(section):
		var v: Variant = cfg.get_value(section, key)
		if typeof(v) == TYPE_STRING:
			out[key.to_upper()] = String(v).strip_edges().to_upper()
	return out
