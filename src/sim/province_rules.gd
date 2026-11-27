class_name ProvinceRules
extends RefCounted
## Parametri delle province della fase 4b (lealta', rivolte, propagazione, riemersione delle fazioni, guerra
## civile, lealta' dei generali; ADR-004), letti da data/regole/province.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file, cosi' i test girano anche senza file (un test
## controlla che restino uguali). Il codice della simulazione legge solo da questa classe, che `Rules` espone
## come `rules.province`. Dove una regola non ha fonte e' PROVVISORIA (catalogo: sezione "Province e lealta'"
## e "Personaggi e dinastie"); il file dice quali.

const DEFAULT_PATH := "res://data/regole/province.cfg"

# --- lealta' obiettivo (catalogo "Province e lealta'", confidenza Media) ---
var base := 100                      ## PROVVISORIA: valore base non pubblicato
var max_loyalty := 200               ## PROVVISORIA: limite superiore della lealta' (e dell'obiettivo)
var drift := 0.2                     ## PROVVISORIA: frazione del divario colmata ogni anno
## Termine della tassa per livello (0-4): +25/+10/0/-10/-25 (documentato, confidenza Media).
var tax_terms := PackedInt32Array([25, 10, 0, -10, -25])
var garrison_per_100 := 16           ## +16 ogni 100 uomini (documentato, confidenza Media)
var garrison_max := 48               ## PROVVISORIA: limite del termine della guarnigione
var religion_penalty := 15           ## PROVVISORIA: religione della regione diversa da quella della fazione
var distance_step := 3               ## PROVVISORIA: per passo di distanza dal capo
var distance_max := 8                ## PROVVISORIA: passi oltre i quali la distanza non pesa piu'
var dread_per_point := 2             ## PROVVISORIA: per punto di terrore del governatore
var acumen_per_point := 1            ## PROVVISORIA (ADR-150): per punto di acume del governatore
var regional_scale := 1.0            ## PROVVISORIA: moltiplicatore della tabella della ribellione regionale
var conquest_loyalty := 70           ## PROVVISORIA: lealta' massima di una provincia appena conquistata
## Occupazione (15/11, ADR-070): una provincia conquistata a chi la possedeva all'inizio della campagna perde
## `occupation_base` punti, che calano di `occupation_decay` l'anno, piu' `occupation_legit` finche' il padrone
## originario e' vivo. Cosi' le terre conquistate restano fedeli solo con una guarnigione.
var occupation_base := 20            ## PROVVISORIA
var occupation_decay := 1.0          ## PROVVISORIA: punti tolti alla penalita' ogni anno di possesso
var occupation_legit := 10           ## PROVVISORIA: finche' il padrone originario e' vivo (non cala)
## Ribellione regionale (catalogo, confidenza Media): regione -> punti di lealta' sottratti.
## Non viene da SetRegionRebels: nel file reale quel comando e' un indice dei nomi dei ribelli (0-92).
var regional_rebels := {
	"ID_LIVONIA": 40, "ID_PORTUGAL": 40, "ID_LITHUANIA": 30, "ID_PRUSSIA": 20, "ID_SCOTLAND": 20,
	"ID_IRELAND": 10, "ID_KHAZAR": 10, "ID_POMERANIA": 10, "ID_SERBIA": 10,
}
## Religione di ogni cultura delle regioni (le fazioni hanno la religione in `SetReligion`).
var culture_religion := {
	"CATHOLIC_CULTURE": "REL_CATHOLIC", "ORTHODOX_CULTURE": "REL_ORTHODOX",
	"MUSLIM_CULTURE": "REL_ISLAMIC", "PAGAN_CULTURE": "REL_PAGAN", "DHARMA_CULTURE": "REL_DHARMA",
}

# --- rivolta e propagazione ---
var revolt_threshold := 100          ## sotto questa lealta' puo' scoppiare una rivolta (manuale p22)
var revolt_k := 0.01                 ## PROVVISORIA: probabilita' annua per punto di lealta' mancante
var revolt_max_chance := 0.5         ## PROVVISORIA: limite della probabilita' annua
var rebels_per_income := 0.5         ## PROVVISORIA: uomini ribelli per punto di rendita della regione
var rebels_min := 100                ## PROVVISORIA
var rebels_max := 600                ## PROVVISORIA
var bandit_threshold := 50           ## PROVVISORIA: sotto questa lealta' i ribelli sono banditi (etichetta)
## Lealisti (15/11, ADR-070): in una provincia tolta a un'altra fazione i ribelli sono fedeli al padrone precedente (o
## a quello originario); se prendono la provincia la consegnano a lui, o lo fanno riemergere se era estinto.
var loyalists := true
var spread_chance := 0.25            ## PROVVISORIA: propagazione a una provincia confinante
var spread_threshold := 110          ## PROVVISORIA: la propagazione colpisce province sotto questa lealta'

# --- riemersione delle fazioni ---
var reemerge_threshold := 120        ## una fazione estinta puo' riemergere sotto questa lealta' (manuale p22)
var reemerge_chance := 0.1           ## PROVVISORIA: probabilita' annua per fazione estinta (0,02 fino al 15/11)
var reemerge_stacks := 3             ## PROVVISORIA: pile dell'esercito nuovo se non ci sono ribelli da arruolare
var reemerge_treasury := 1000        ## PROVVISORIA: tesoro minimo della fazione riemersa
## ADR-114, insurrezioni lealiste (PROVVISORIE): una fazione estinta (non del giocatore) ritenta di tornare dopo un numero di
## anni a caso tra `uprising_years_min` e `uprising_years_max` (come il Papato, ADR-072), con un'armata di
## `uprising_stacks` pile + `uprising_growth` per ogni insurrezione gia' tentata. 0 anni massimi = spente.
var uprising_years_min := 20
var uprising_years_max := 40
var uprising_stacks := 6
var uprising_growth := 2

# --- guerra civile (manuale p33, catalogo "Guerra civile") ---
var disloyal_loyalty := 3            ## lealta' massima di un generale sleale (manuale: <= 3)
var civil_share := 0.5               ## PROVVISORIA: quota di generali sleali che basta a innescare la guerra civile
var civil_min := 2                   ## PROVVISORIA: numero minimo di generali sleali per la quota
var promoter_command := 5            ## PROVVISORIA: comando minimo del promotore (forte e sleale)
var civil_chance := 0.25             ## PROVVISORIA: probabilita' annua quando c'e' l'innesco

# --- lealta' dei generali ---
var general_step := 4                ## PROVVISORIA: punti di pressione per ogni punto di lealta'
var general_title := 1               ## PROVVISORIA: pressione annua di chi governa una provincia
var general_tax := 1                 ## PROVVISORIA: pressione annua (negativa) con tasse alte nel reame
var general_defeat := 1              ## PROVVISORIA: pressione (negativa) per ogni sconfitta
var general_influence := 1           ## PROVVISORIA: pressione annua per influenza del capo alta o bassa
var influence_high := 7              ## PROVVISORIA: influenza del capo da cui la lealta' sale
var influence_low := 3               ## PROVVISORIA: influenza del capo sotto cui la lealta' scende

## Errori di lettura del file (chiave con tipo sbagliato e simili).
var errors := PackedStringArray()


## Regole dal file `path`; le chiavi mancanti restano ai valori predefiniti. Se il file non c'e' o non si
## legge: valori predefiniti e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH) -> ProvinceRules:
	var r := ProvinceRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole delle province non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	r.base = _int(cfg, "lealta", "base", r.base)
	r.max_loyalty = _int(cfg, "lealta", "massima", r.max_loyalty)
	r.drift = _float(cfg, "lealta", "deriva", r.drift)
	r.tax_terms = _ints(cfg, "lealta", "termini_tassa", r.tax_terms)
	r.garrison_per_100 = _int(cfg, "lealta", "guarnigione_per_100", r.garrison_per_100)
	r.garrison_max = _int(cfg, "lealta", "guarnigione_max", r.garrison_max)
	r.religion_penalty = _int(cfg, "lealta", "penalita_religione", r.religion_penalty)
	r.distance_step = _int(cfg, "lealta", "penalita_distanza", r.distance_step)
	r.distance_max = _int(cfg, "lealta", "distanza_max", r.distance_max)
	r.dread_per_point = _int(cfg, "lealta", "terrore_per_punto", r.dread_per_point)
	r.acumen_per_point = _int(cfg, "lealta", "acume_per_punto", r.acumen_per_point)
	r.regional_scale = _float(cfg, "lealta", "scala_ribellione_regionale", r.regional_scale)
	r.conquest_loyalty = _int(cfg, "lealta", "lealta_conquista", r.conquest_loyalty)
	r.occupation_base = _int(cfg, "occupazione", "penalita", r.occupation_base)
	r.occupation_decay = _float(cfg, "occupazione", "calo_annuo", r.occupation_decay)
	r.occupation_legit = _int(cfg, "occupazione", "padrone_vivo", r.occupation_legit)
	r.regional_rebels = _table(cfg, "ribellione_regionale", r.regional_rebels, false)
	r.culture_religion = _table(cfg, "religione_cultura", r.culture_religion, true)
	r.revolt_threshold = _int(cfg, "rivolta", "soglia", r.revolt_threshold)
	r.revolt_k = _float(cfg, "rivolta", "k_rivolta", r.revolt_k)
	r.revolt_max_chance = _float(cfg, "rivolta", "p_massima", r.revolt_max_chance)
	r.rebels_per_income = _float(cfg, "rivolta", "ribelli_per_rendita", r.rebels_per_income)
	r.rebels_min = _int(cfg, "rivolta", "ribelli_min", r.rebels_min)
	r.rebels_max = _int(cfg, "rivolta", "ribelli_max", r.rebels_max)
	r.bandit_threshold = _int(cfg, "rivolta", "soglia_banditi", r.bandit_threshold)
	if cfg.has_section_key("rivolta", "lealisti"):
		r.loyalists = bool(cfg.get_value("rivolta", "lealisti"))
	r.spread_chance = _float(cfg, "propagazione", "p_propagazione", r.spread_chance)
	r.spread_threshold = _int(cfg, "propagazione", "soglia", r.spread_threshold)
	r.reemerge_threshold = _int(cfg, "riemersione", "soglia", r.reemerge_threshold)
	r.reemerge_chance = _float(cfg, "riemersione", "p_riemersione", r.reemerge_chance)
	r.reemerge_stacks = _int(cfg, "riemersione", "pile", r.reemerge_stacks)
	r.reemerge_treasury = _int(cfg, "riemersione", "tesoro", r.reemerge_treasury)
	r.uprising_years_min = _int(cfg, "insurrezioni", "anni_min", r.uprising_years_min)
	r.uprising_years_max = _int(cfg, "insurrezioni", "anni_max", r.uprising_years_max)
	r.uprising_stacks = _int(cfg, "insurrezioni", "pile", r.uprising_stacks)
	r.uprising_growth = _int(cfg, "insurrezioni", "pile_in_piu", r.uprising_growth)
	r.disloyal_loyalty = _int(cfg, "guerra_civile", "lealta_sleale", r.disloyal_loyalty)
	r.civil_share = _float(cfg, "guerra_civile", "quota_sleali", r.civil_share)
	r.civil_min = _int(cfg, "guerra_civile", "sleali_min", r.civil_min)
	r.promoter_command = _int(cfg, "guerra_civile", "comando_promotore", r.promoter_command)
	r.civil_chance = _float(cfg, "guerra_civile", "p_guerra_civile", r.civil_chance)
	r.general_step = _int(cfg, "lealta_generali", "pressione_per_punto", r.general_step)
	r.general_title = _int(cfg, "lealta_generali", "titolo", r.general_title)
	r.general_tax = _int(cfg, "lealta_generali", "tassa_alta", r.general_tax)
	r.general_defeat = _int(cfg, "lealta_generali", "sconfitta", r.general_defeat)
	r.general_influence = _int(cfg, "lealta_generali", "influenza", r.general_influence)
	r.influence_high = _int(cfg, "lealta_generali", "influenza_alta", r.influence_high)
	r.influence_low = _int(cfg, "lealta_generali", "influenza_bassa", r.influence_low)
	r._check_consistency()
	return r


## Termine della tassa per il livello `level` (0-4), limitato ai livelli della tabella.
func tax_term(level: int) -> int:
	return tax_terms[clampi(level, 0, tax_terms.size() - 1)]


## Punti di lealta' sottratti dalla ribellione regionale della regione (0 se non e' nella tabella).
func regional_penalty(region_id: String) -> int:
	var key := region_id.strip_edges().to_upper()
	if not regional_rebels.has(key):
		return 0
	return roundi(float(int(regional_rebels[key])) * regional_scale)


## Religione della cultura della regione ("" se sconosciuta).
func religion_of_culture(culture: String) -> String:
	var key := culture.strip_edges().to_upper()
	if not culture_religion.has(key):
		return ""
	return str(culture_religion[key]).to_upper()


## ADR-114: probabilita' dell'insurrezione lealista di una fazione estinta da `dead_years` anni: 0 prima di `anni_min`, poi
## uniforme sulla finestra (1 / anni rimasti), 1 da `anni_max` (come `PapacyRules.reemerge_chance`). 0 se spente.
func uprising_chance(dead_years: int) -> float:
	if uprising_years_max <= 0 or dead_years < uprising_years_min:
		return 0.0
	if dead_years >= uprising_years_max:
		return 1.0
	return 1.0 / float(uprising_years_max - dead_years + 1)


## Probabilita' annua di rivolta: 0 dalla soglia in su, poi `k_rivolta` per ogni punto mancante, al massimo `p_massima`.
func revolt_chance(loyalty: int) -> float:
	if loyalty >= revolt_threshold:
		return 0.0
	return minf(revolt_max_chance, revolt_k * float(revolt_threshold - loyalty))


## Spegne tutti i sorteggi della fase 4b (rivolte, propagazione, riemersione, guerra civile): la lealta' si
## calcola ancora ma nulla accade per caso. Usato dai test che non vogliono rivolte in mezzo.
func calm() -> void:
	revolt_k = 0.0
	spread_chance = 0.0
	reemerge_chance = 0.0
	uprising_years_max = 0
	civil_chance = 0.0


## Tutti i parametri in un Dictionary (per confronti nei test e per i rapporti).
func to_dict() -> Dictionary:
	return {
		"base": base,
		"max_loyalty": max_loyalty,
		"drift": drift,
		"tax_terms": Array(tax_terms),
		"garrison_per_100": garrison_per_100,
		"garrison_max": garrison_max,
		"religion_penalty": religion_penalty,
		"distance_step": distance_step,
		"distance_max": distance_max,
		"dread_per_point": dread_per_point,
		"acumen_per_point": acumen_per_point,
		"regional_scale": regional_scale,
		"conquest_loyalty": conquest_loyalty,
		"occupation_base": occupation_base,
		"occupation_decay": occupation_decay,
		"occupation_legit": occupation_legit,
		"regional_rebels": regional_rebels.duplicate(),
		"culture_religion": culture_religion.duplicate(),
		"revolt_threshold": revolt_threshold,
		"revolt_k": revolt_k,
		"revolt_max_chance": revolt_max_chance,
		"rebels_per_income": rebels_per_income,
		"rebels_min": rebels_min,
		"rebels_max": rebels_max,
		"bandit_threshold": bandit_threshold,
		"loyalists": loyalists,
		"spread_chance": spread_chance,
		"spread_threshold": spread_threshold,
		"reemerge_threshold": reemerge_threshold,
		"reemerge_chance": reemerge_chance,
		"reemerge_stacks": reemerge_stacks,
		"reemerge_treasury": reemerge_treasury,
		"uprising_years_min": uprising_years_min,
		"uprising_years_max": uprising_years_max,
		"uprising_stacks": uprising_stacks,
		"uprising_growth": uprising_growth,
		"disloyal_loyalty": disloyal_loyalty,
		"civil_share": civil_share,
		"civil_min": civil_min,
		"promoter_command": promoter_command,
		"civil_chance": civil_chance,
		"general_step": general_step,
		"general_title": general_title,
		"general_tax": general_tax,
		"general_defeat": general_defeat,
		"general_influence": general_influence,
		"influence_high": influence_high,
		"influence_low": influence_low,
	}


func _check_consistency() -> void:
	var defaults := ProvinceRules.new()
	if tax_terms.is_empty():
		errors.append("lealta/termini_tassa vuoto: uso i predefiniti")
		tax_terms = defaults.tax_terms
	if max_loyalty < 1:
		errors.append("lealta/massima non valida: uso 200")
		max_loyalty = defaults.max_loyalty
	if drift <= 0.0 or drift > 1.0:
		errors.append("lealta/deriva fuori da (0, 1]: uso 0,2")
		drift = defaults.drift
	if rebels_min > rebels_max:
		errors.append("rivolta/ribelli_min e ribelli_max incoerenti: uso i predefiniti")
		rebels_min = defaults.rebels_min
		rebels_max = defaults.rebels_max
	if general_step < 1:
		errors.append("lealta_generali/pressione_per_punto non valido: uso 4")
		general_step = defaults.general_step
	if occupation_base < 0 or occupation_legit < 0 or occupation_decay < 0.0:
		errors.append("occupazione: valori negativi, uso i predefiniti")
		occupation_base = defaults.occupation_base
		occupation_decay = defaults.occupation_decay
		occupation_legit = defaults.occupation_legit
	if reemerge_stacks < 1:
		errors.append("riemersione/pile non valido: uso 3")
		reemerge_stacks = defaults.reemerge_stacks


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


## Sezione di coppie chiave -> valore (chiavi in maiuscolo); `as_text`: valori testo (maiuscolo), altrimenti interi.
## Una sezione assente lascia il predefinito.
static func _table(cfg: ConfigFile, section: String, fallback: Dictionary, as_text: bool) -> Dictionary:
	if not cfg.has_section(section):
		return fallback
	var out := {}
	for key in cfg.get_section_keys(section):
		var v: Variant = cfg.get_value(section, key)
		if as_text:
			if typeof(v) == TYPE_STRING:
				out[key.to_upper()] = String(v).strip_edges().to_upper()
		elif typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			out[key.to_upper()] = int(v)
	return out
