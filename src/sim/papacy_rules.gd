class_name PapacyRules
extends RefCounted
## Parametri del Papato, delle scomuniche, delle crociate e dei jihad della fase 5c (ADR-004, ADR-010), letti da
## data/regole/papato.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file, cosi' i test girano anche senza file (un test
## controlla che restino uguali). Il codice della simulazione legge solo da questa classe, che `Rules` espone come
## `rules.papacy`. Dove una regola non ha formula nel catalogo (sezione "Religione e Papato") e' PROVVISORIA; il file
## dice quali parametri lo sono.

const DEFAULT_PATH := "res://data/regole/papato.cfg"

# --- avvertimento e scomunica ---
var warning_years := 2               ## catalogo: due anni per fermarsi
var papal_truce_years := 10          ## catalogo: poi tregua di dieci anni (anni interi dopo l'anno della scadenza)
var excommunication_influence := 2   ## PROVVISORIA: influenza del capo persa una volta
var excommunication_loyalty := 15    ## PROVVISORIA: lealta' obiettivo persa dalle province, x % di cattolici / 100

# --- elezione del Papa (ADR-072) ---
var elective := true                 ## Federico, dal gioco originale: niente principi ne' principesse, morto un Papa se ne elegge un altro
var pope_age_min := 50               ## PROVVISORIA: eta' del Papa eletto
var pope_age_max := 70

# --- Papato distrutto (ADR-072) ---
var reemerge_years_min := 15         ## Federico, dal gioco originale: ricompare ogni 15-30 anni (il catalogo diceva circa 10)
var reemerge_years_max := 30
var reemerge_stacks := 8             ## PROVVISORIA: pile dell'esercito alla prima riemersione («una grande armata»)
var army_growth := 2                 ## PROVVISORIA (k_crescita_esercito): pile in piu' a ogni riemersione successiva

# --- crociata e jihad ---
var initial_stacks := 4              ## pile iniziali (le migliori unita' reclutabili nella provincia)
var initial_zeal := 80
var zeal_decay_year := 5
var zeal_decay_no_target := 10       ## in piu', ogni anno senza un bersaglio
var recruit_stacks := 4              ## PROVVISORIA (ADR-072): al massimo queste pile per provincia attraversata
var recruit_zeal_threshold := 40     ## zelo della provincia oltre il quale si recluta (PROVVISORIA, ADR-072)
var recruit_zeal_per_stack := 15     ## PROVVISORIA (ADR-072): una pila ogni tanti punti di zelo oltre la soglia
var max_stacks := 32                 ## catalogo (MTW Crusade): fino a 32 unita', oltre il limite degli eserciti normali
var zeal_losses := 40                ## sotto questo zelo si perde una pila all'anno (catalogo, confidenza Bassa)
var zeal_desertion := 30             ## sotto questo zelo diserzioni (catalogo)
var desertion_stacks := 2
var zeal_dissolve := 20              ## a questo zelo o meno l'esercito si scioglie (catalogo)
var order_stacks := 2                ## ricompensa della crociata: pile di un ordine militare
var order_stacks_jihad := 0          ## PROVVISORIA: il jihad non ha ricompensa di pile
var crusade_success_influence := 1
var crusade_failure_influence := 1   ## perdita
var jihad_success_influence := 1
var jihad_failure_influence := 2     ## perdita (catalogo)
var order_building := "CHAPTER_HOUSE"  ## edificio che distingue gli ordini militari

# --- doni papali (catalogo: trigger ignoto, PROVVISORIA) ---
var gift_min_religious := 3
var gift_types := PackedStringArray(["BISHOP", "PRIEST"])
var gift_chance := 0.05
var gift_amount := 1000

## Errori di lettura del file (chiave con tipo sbagliato e simili).
var errors := PackedStringArray()


## Regole dal file `path`; le chiavi mancanti restano ai valori predefiniti. Se il file non c'e' o non si
## legge: valori predefiniti e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH) -> PapacyRules:
	var r := PapacyRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole del Papato non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	r.warning_years = _int(cfg, "scomunica", "anni_avvertimento", r.warning_years)
	r.papal_truce_years = _int(cfg, "scomunica", "durata_tregua_papale", r.papal_truce_years)
	r.excommunication_influence = _int(cfg, "scomunica", "malus_influenza", r.excommunication_influence)
	r.excommunication_loyalty = _int(cfg, "scomunica", "malus_lealta", r.excommunication_loyalty)
	r.elective = _bool(cfg, "elezione", "elettivo", r.elective)
	r.pope_age_min = _int(cfg, "elezione", "eta_min", r.pope_age_min)
	r.pope_age_max = _int(cfg, "elezione", "eta_max", r.pope_age_max)
	r.reemerge_years_min = _int(cfg, "papato", "anni_riemersione_min", r.reemerge_years_min)
	r.reemerge_years_max = _int(cfg, "papato", "anni_riemersione_max", r.reemerge_years_max)
	r.reemerge_stacks = _int(cfg, "papato", "pile_riemersione", r.reemerge_stacks)
	r.army_growth = _int(cfg, "papato", "k_crescita_esercito", r.army_growth)
	r.initial_stacks = _int(cfg, "crociata", "pile_iniziali", r.initial_stacks)
	r.initial_zeal = _int(cfg, "crociata", "zelo_iniziale", r.initial_zeal)
	r.zeal_decay_year = _int(cfg, "crociata", "calo_zelo_anno", r.zeal_decay_year)
	r.zeal_decay_no_target = _int(cfg, "crociata", "calo_zelo_senza_bersaglio", r.zeal_decay_no_target)
	r.recruit_stacks = _int(cfg, "crociata", "pile_per_zelo", r.recruit_stacks)
	r.recruit_zeal_threshold = _int(cfg, "crociata", "soglia_zelo_provincia", r.recruit_zeal_threshold)
	r.recruit_zeal_per_stack = _int(cfg, "crociata", "zelo_per_pila", r.recruit_zeal_per_stack)
	r.max_stacks = _int(cfg, "crociata", "max_pile", r.max_stacks)
	r.zeal_losses = _int(cfg, "crociata", "soglia_perdite", r.zeal_losses)
	r.zeal_desertion = _int(cfg, "crociata", "soglia_diserzioni", r.zeal_desertion)
	r.desertion_stacks = _int(cfg, "crociata", "pile_diserzione", r.desertion_stacks)
	r.zeal_dissolve = _int(cfg, "crociata", "soglia_scioglimento", r.zeal_dissolve)
	r.order_stacks = _int(cfg, "esito", "pile_ordine", r.order_stacks)
	r.order_stacks_jihad = _int(cfg, "esito", "pile_ordine_jihad", r.order_stacks_jihad)
	r.crusade_success_influence = _int(cfg, "esito", "influenza_successo_crociata", r.crusade_success_influence)
	r.crusade_failure_influence = _int(cfg, "esito", "influenza_fallimento_crociata", r.crusade_failure_influence)
	r.jihad_success_influence = _int(cfg, "esito", "influenza_successo_jihad", r.jihad_success_influence)
	r.jihad_failure_influence = _int(cfg, "esito", "influenza_fallimento_jihad", r.jihad_failure_influence)
	r.order_building = _text(cfg, "esito", "edificio_ordini", r.order_building)
	r.gift_min_religious = _int(cfg, "doni", "min_religiosi", r.gift_min_religious)
	r.gift_types = _texts(cfg, "doni", "tipi", r.gift_types)
	r.gift_chance = _float(cfg, "doni", "p_dono", r.gift_chance)
	r.gift_amount = _int(cfg, "doni", "importo", r.gift_amount)
	r._check_consistency()
	return r


# --- calcoli ---------------------------------------------------------------------------------------------


## Pile dell'esercito del Papato alla `times`-esima riemersione (0 = la prima): base + crescita x riemersioni
## precedenti, limitata al limite del motore (`limit`).
func reemerge_army_stacks(times: int, limit: int) -> int:
	return clampi(reemerge_stacks + army_growth * maxi(0, times), 1, maxi(1, limit))


## Probabilita' che il Papato distrutto ricompaia nell'anno in cui e' distrutto da `dead_years` anni (ADR-072): 0 prima di
## `reemerge_years_min`, poi 1 / (anni rimasti fino a `reemerge_years_max`), cosi' l'anno della ricomparsa e' uniforme
## tra minimo e massimo; 1 dal massimo in poi (se manca il luogo si riprova ogni anno).
func reemerge_chance(dead_years: int) -> float:
	if dead_years < reemerge_years_min:
		return 0.0
	if dead_years >= reemerge_years_max:
		return 1.0
	return 1.0 / float(reemerge_years_max - dead_years + 1)


## Pile che un esercito crociato raccoglie in una provincia della sua religione con zelo `zeal` (ADR-072): nessuna fino
## alla soglia, poi una ogni `recruit_zeal_per_stack` punti oltre la soglia (arrotondando in su), al massimo `recruit_stacks`.
func zeal_recruit_stacks(zeal: int) -> int:
	if zeal <= recruit_zeal_threshold:
		return 0
	var per := maxi(1, recruit_zeal_per_stack)
	return clampi(ceili(float(zeal - recruit_zeal_threshold) / float(per)), 1, maxi(1, recruit_stacks))


## Tutti i parametri in un Dictionary (per confronti nei test e per i rapporti).
func to_dict() -> Dictionary:
	return {
		"warning_years": warning_years,
		"papal_truce_years": papal_truce_years,
		"excommunication_influence": excommunication_influence,
		"excommunication_loyalty": excommunication_loyalty,
		"elective": elective,
		"pope_age_min": pope_age_min,
		"pope_age_max": pope_age_max,
		"reemerge_years_min": reemerge_years_min,
		"reemerge_years_max": reemerge_years_max,
		"reemerge_stacks": reemerge_stacks,
		"army_growth": army_growth,
		"initial_stacks": initial_stacks,
		"initial_zeal": initial_zeal,
		"zeal_decay_year": zeal_decay_year,
		"zeal_decay_no_target": zeal_decay_no_target,
		"recruit_stacks": recruit_stacks,
		"recruit_zeal_threshold": recruit_zeal_threshold,
		"recruit_zeal_per_stack": recruit_zeal_per_stack,
		"max_stacks": max_stacks,
		"zeal_losses": zeal_losses,
		"zeal_desertion": zeal_desertion,
		"desertion_stacks": desertion_stacks,
		"zeal_dissolve": zeal_dissolve,
		"order_stacks": order_stacks,
		"order_stacks_jihad": order_stacks_jihad,
		"crusade_success_influence": crusade_success_influence,
		"crusade_failure_influence": crusade_failure_influence,
		"jihad_success_influence": jihad_success_influence,
		"jihad_failure_influence": jihad_failure_influence,
		"order_building": order_building,
		"gift_min_religious": gift_min_religious,
		"gift_types": Array(gift_types),
		"gift_chance": gift_chance,
		"gift_amount": gift_amount,
	}


func _check_consistency() -> void:
	var defaults := PapacyRules.new()
	if warning_years < 1:
		errors.append("scomunica/anni_avvertimento minore di 1: uso 2")
		warning_years = defaults.warning_years
	if papal_truce_years < 1:
		errors.append("scomunica/durata_tregua_papale minore di 1: uso 10")
		papal_truce_years = defaults.papal_truce_years
	if reemerge_years_min < 1 or reemerge_years_max < reemerge_years_min:
		errors.append("papato: anni_riemersione_min deve essere almeno 1 e non oltre anni_riemersione_max: uso 15-30")
		reemerge_years_min = defaults.reemerge_years_min
		reemerge_years_max = defaults.reemerge_years_max
	if pope_age_min < 1 or pope_age_max < pope_age_min:
		errors.append("elezione: eta_min deve essere almeno 1 e non oltre eta_max: uso 50-70")
		pope_age_min = defaults.pope_age_min
		pope_age_max = defaults.pope_age_max
	if initial_zeal < 0 or initial_zeal > 100:
		errors.append("crociata/zelo_iniziale fuori da [0, 100]: uso 80")
		initial_zeal = defaults.initial_zeal
	if max_stacks < 1:
		errors.append("crociata/max_pile minore di 1: uso 32")
		max_stacks = defaults.max_stacks
	if not (zeal_dissolve <= zeal_desertion and zeal_desertion <= zeal_losses):
		errors.append("crociata: le soglie di zelo devono valere scioglimento <= diserzioni <= perdite: uso i predefiniti")
		zeal_dissolve = defaults.zeal_dissolve
		zeal_desertion = defaults.zeal_desertion
		zeal_losses = defaults.zeal_losses
	if gift_chance < 0.0 or gift_chance > 1.0:
		errors.append("doni/p_dono fuori da [0, 1]: uso 0.05")
		gift_chance = defaults.gift_chance


# I valori mancanti restano al predefinito; si legge il valore solo dopo aver controllato che la chiave esista.
static func _int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return fallback


static func _bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key)
	if typeof(v) == TYPE_BOOL:
		return bool(v)
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
