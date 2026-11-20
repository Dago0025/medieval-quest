class_name CombatRules
extends RefCounted
## Parametri degli scontri della fase 3 (ADR-004, ADR-009), letti da data/regole/scontri.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file, cosi' i test girano anche
## senza file (un test controlla che restino uguali). Il codice della simulazione legge solo
## da questa classe, che `Rules` espone come `rules.combat`.
##
## PROVVISORIA (catalogo r.105): la formula della risoluzione automatica non e' documentata.
## Ogni numero e' una stima da tarare con le prove di docs/laboratorio_scontri.md.

const DEFAULT_PATH := "res://data/regole/scontri.cfg"
const AUROR_PATH := "res://data/regole/auror.cfg"

## a: peso di carica + mischia + difesa.
var attack_weight := 0.05
## b: peso dell'armatura.
var armour_weight := 0.05
## c: peso di un livello di valore (catalogo r.74: +1 attacco, +1 difesa, +2 morale = 2a + 2d).
var valour_weight := 0.14
## d: peso del bonus di morale dell'unita'.
var morale_weight := 0.02
## e: peso dell'attacco navale.
var naval_weight := 0.15
## Fattore minimo di una pila.
var min_factor := 0.1

## f: peso di una stella di comando (catalogo r.119: ogni due stelle +1 attacco e +1 difesa).
var star_weight := 0.05
## Fazione -> stelle di tutti i suoi capi (da `comando_fisso` di auror.cfg).
var fixed_command := {"FN_DANISH": 9}
## Fazione -> valore con cui nasce ogni sua pila (da `valore_iniziale` di auror.cfg; assente = 0).
var start_valour := {"FN_DANISH": 9}
## Fazione -> livello di armi e armatura (0-4) di ogni sua pila di terra (da `armi_armatura_iniziali` di auror.cfg; assente = 0).
var start_upgrades := {"FN_DANISH": 4}

## g: bonus del difensore in campo e in mare.
var defender_bonus := 0.15
var sea_defender_bonus := 0.0
## Probabilita' di guadagnare un livello di valore per ogni pila vincitrice sopravvissuta.
var valour_chance := 0.2
var valour_max := 9

var loss_min := 0.30
var loss_max := 0.90
var winner_loss_factor := 0.5

## Famiglia degli edifici del castello nel file edifici (Fort ... Fortress, 15 livelli).
var castle_family := "CASTLE"
## Livelli del file edifici per ogni grado di castello (Fort, Keep, Castle, Citadel, Fortress).
var castle_levels_per_tier := 3
## Indice = grado (0 = Fort).
var castle_multipliers := PackedFloat64Array([1.5, 2.0, 2.5, 3.0, 4.0])
var starve_years := PackedInt32Array([1, 2, 3, 4, 5])
var garrison_max := 16
var cavalry_garrison_weight := 2
var assault_annihilates := true

var sally_threshold := 2.0
## Raggio delle flotte (manuale, campagna vichinga: «un raggio di movimento pari a 3 consente di raggiungere rapidamente
## lontane regioni marine»): zone di mare percorse in un anno = il raggio minore tra le navi (col. 33 della prod, primo valore),
## almeno `fleet_min_range`; dopo l'evento storico `compass_event` (la bussola) +`compass_bonus`. PROVVISORIA.
var fleet_min_range := 1
var compass_bonus := 1
## Distanza dalla costa (wiki «MTW Ships», segnalazione di Federico del 18/11/2026): il raggio della nave dice anche quanto
## puo' allontanarsi da terra. Raggio 1: solo zone che toccano terra; 2: anche quelle che confinano con una zona costiera;
## 3: ovunque. La flotta va dove arriva la sua nave piu' limitata (la bussola non cambia questo limite).
var coast_limit := true
## Blocco navale: anche le flotte delle fazioni neutrali (non alleate) chiudono le zone ai trasporti (vero), o solo le nemiche.
var neutral_blockade := true
## Emissari, principesse e gli altri agenti viaggiano via mare anche senza flotte proprie nelle zone (richiesta di Federico
## dell'11/11/2026, ADR-034); li ferma solo una flotta nemica. false = regola di prima: serve la catena di flotte.
var agents_free_sea := true
## Gli agenti si imbarcano da qualunque provincia con il porto costruito, anche non propria (richiesta di Federico
## dell'11/11/2026, ADR-035). false = solo dai propri porti.
var agents_any_port := true
## Zone di mare che sono oceani (richiesta di Federico del 16/11/2026, mappa del mondo): gli agenti senza navi attraversano
## i mari ma non gli oceani, dove serve una flotta propria nella zona come per le truppe. Id della zona -> true.
var oceans := {"ID_MID_ATLANTIC": true, "ID_EQ_ATLANTIC": true, "ID_S_ATLANTIC": true, "ID_SE_ATLANTIC": true, "ID_GREENLAND_SEA": true,
	"ID_SARGASSO_SEA": true, "ID_N_PACIFIC": true, "ID_EQ_PACIFIC": true, "ID_S_PACIFIC": true, "ID_C_INDIAN": true, "ID_S_INDIAN": true,
	"ID_SOUTHERN_OCEAN": true, "ID_ARCTIC_OCEAN": true}
# --- [ammiragli] (ADR-056) ---
var admirals_on := true              ## ogni flotta ha un ammiraglio
var admiral_start_stars := 0         ## stelle dell'ammiraglio di una flotta nuova
var admiral_max_stars := 10          ## stelle massime (gli Auror le hanno sempre)
var admiral_wins_per_star := 2       ## battaglie navali vinte per guadagnare una stella (PROVVISORIA)
# --- prigionieri e ritirata parziale (ADR-073, manuale p32 e p56) ---
var capture_share := 0.3             ## PROVVISORIA: quota degli uomini sopravvissuti di chi perde e si ritira che resta prigioniera
var ransom_share := 0.5              ## PROVVISORIA: riscatto per uomo = costo dell'unita' / uomini dell'unita' x questa quota
var ransom_general := 500            ## PROVVISORIA: riscatto in piu' per un generale catturato
var ransom_royal := 1500             ## PROVVISORIA: per un erede o un principe
var ransom_leader := 3000            ## PROVVISORIA: per il re
var ai_execute_dread := 8            ## PROVVISORIA: un capo dell'IA con almeno questo terrore giustizia invece di chiedere il riscatto
var compass_event := "BUSSOLA"   ## chiave dell'evento storico (in maiuscolo come gli altri testi delle regole)

## Solo per i test: 0 casuale, 1 vince l'attaccante, -1 vince il difensore.
var forced_outcome := 0

## Errori di lettura del file (chiave con tipo sbagliato e simili).
var errors := PackedStringArray()


## Regole dal file `path`; le chiavi mancanti restano ai valori predefiniti. Se il file non
## c'e' o non si legge: valori predefiniti e un errore in `errors`. Le stelle fisse dei capi
## si leggono da `auror_path` (se il file non c'e', restano quelle predefinite).
static func load_file(path: String = DEFAULT_PATH, auror_path: String = AUROR_PATH) -> CombatRules:
	var rules := CombatRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		rules.errors.append("Regole degli scontri non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return rules
	rules.attack_weight = _float(cfg, "forza", "attacco", rules.attack_weight)
	rules.armour_weight = _float(cfg, "forza", "armatura", rules.armour_weight)
	rules.valour_weight = _float(cfg, "forza", "valore", rules.valour_weight)
	rules.morale_weight = _float(cfg, "forza", "morale", rules.morale_weight)
	rules.naval_weight = _float(cfg, "forza", "navale", rules.naval_weight)
	rules.min_factor = _float(cfg, "forza", "fattore_minimo", rules.min_factor)
	rules.star_weight = _float(cfg, "comando", "peso_stella", rules.star_weight)
	rules.defender_bonus = _float(cfg, "campo", "bonus_difensore", rules.defender_bonus)
	rules.sea_defender_bonus = _float(cfg, "campo", "bonus_difensore_mare", rules.sea_defender_bonus)
	rules.valour_chance = _float(cfg, "campo", "prob_valore", rules.valour_chance)
	rules.valour_max = _int(cfg, "campo", "valore_massimo", rules.valour_max)
	rules.loss_min = _float(cfg, "perdite", "perdita_min", rules.loss_min)
	rules.loss_max = _float(cfg, "perdite", "perdita_max", rules.loss_max)
	rules.winner_loss_factor = _float(cfg, "perdite", "fattore_vincitore", rules.winner_loss_factor)
	rules.castle_family = _text(cfg, "castello", "famiglia", rules.castle_family)
	rules.castle_levels_per_tier = _int(cfg, "castello", "livelli_per_grado", rules.castle_levels_per_tier)
	rules.castle_multipliers = _floats(cfg, "castello", "moltiplicatore_assalto", rules.castle_multipliers)
	rules.starve_years = _ints(cfg, "castello", "anni_fame", rules.starve_years)
	rules.garrison_max = _int(cfg, "castello", "guarnigione_max", rules.garrison_max)
	rules.cavalry_garrison_weight = _int(cfg, "castello", "peso_cavalleria", rules.cavalry_garrison_weight)
	rules.assault_annihilates = _bool(cfg, "castello", "assalto_annienta", rules.assault_annihilates)
	rules.sally_threshold = _float(cfg, "assedio", "soglia_sortita", rules.sally_threshold)
	rules.fleet_min_range = _int(cfg, "flotte", "raggio_minimo", rules.fleet_min_range)
	rules.compass_bonus = _int(cfg, "flotte", "bonus_bussola", rules.compass_bonus)
	var limit_value: Variant = cfg.get_value("flotte", "limite_costa", rules.coast_limit)
	if typeof(limit_value) == TYPE_BOOL:
		rules.coast_limit = limit_value
	rules.compass_event = _text(cfg, "flotte", "evento_bussola", rules.compass_event)
	var nb: Variant = cfg.get_value("flotte", "blocco_neutrali", rules.neutral_blockade)
	if typeof(nb) == TYPE_BOOL:
		rules.neutral_blockade = nb
	var fs: Variant = cfg.get_value("flotte", "agenti_senza_navi", rules.agents_free_sea)
	if typeof(fs) == TYPE_BOOL:
		rules.agents_free_sea = fs
	var ap: Variant = cfg.get_value("flotte", "agenti_da_ogni_porto", rules.agents_any_port)
	if typeof(ap) == TYPE_BOOL:
		rules.agents_any_port = ap
	var oc: Variant = cfg.get_value("flotte", "oceani", null)
	if typeof(oc) == TYPE_ARRAY or typeof(oc) == TYPE_PACKED_STRING_ARRAY:
		rules.oceans = {}
		for z in oc:
			rules.oceans[str(z).strip_edges().to_upper()] = true
	elif oc != null:
		rules.errors.append("flotte/oceani non e' un elenco: nessun oceano")
	var adm_on: Variant = cfg.get_value("ammiragli", "attivi", rules.admirals_on)
	if typeof(adm_on) == TYPE_BOOL:
		rules.admirals_on = adm_on
	rules.admiral_start_stars = _int(cfg, "ammiragli", "stelle_iniziali", rules.admiral_start_stars)
	rules.admiral_max_stars = _int(cfg, "ammiragli", "stelle_max", rules.admiral_max_stars)
	rules.admiral_wins_per_star = _int(cfg, "ammiragli", "vittorie_per_stella", rules.admiral_wins_per_star)
	rules.capture_share = _float(cfg, "prigionieri", "quota_catturati", rules.capture_share)
	rules.ransom_share = _float(cfg, "prigionieri", "quota_riscatto", rules.ransom_share)
	rules.ransom_general = _int(cfg, "prigionieri", "riscatto_generale", rules.ransom_general)
	rules.ransom_royal = _int(cfg, "prigionieri", "riscatto_principe", rules.ransom_royal)
	rules.ransom_leader = _int(cfg, "prigionieri", "riscatto_re", rules.ransom_leader)
	rules.ai_execute_dread = _int(cfg, "prigionieri", "terrore_esecuzione_ia", rules.ai_execute_dread)
	rules.forced_outcome = _int(cfg, "prova", "esito_forzato", rules.forced_outcome)
	rules._read_command(auror_path)
	rules._check_consistency()
	return rules


## Stelle di comando dei capi di una fazione (0 se la fazione non ha un comando fisso).
func command_stars(faction_id: String) -> int:
	return int(fixed_command.get(faction_id.strip_edges().to_upper(), 0))


## Grado del castello (0 = Fort ... 4 = Fortress) per il livello del file edifici; -1 senza castello.
func castle_tier(castle_level: int) -> int:
	if castle_level <= 0:
		return -1
	var per_tier := maxi(1, castle_levels_per_tier)
	var tier := floori(float(castle_level - 1) / float(per_tier))
	return mini(tier, castle_multipliers.size() - 1)


## Moltiplicatore della guarnigione negli assalti (1.0 senza castello).
func castle_multiplier(castle_level: int) -> float:
	var tier := castle_tier(castle_level)
	if tier < 0:
		return 1.0
	return castle_multipliers[tier]


## Anni di assedio dopo i quali la guarnigione cede per fame (0 senza castello).
func starve_after(castle_level: int) -> int:
	var tier := castle_tier(castle_level)
	if tier < 0:
		return 0
	return starve_years[mini(tier, starve_years.size() - 1)]


## Tutti i parametri in un Dictionary (per confronti nei test e per i rapporti).
func to_dict() -> Dictionary:
	return {
		"capture_share": capture_share,
		"ransom_share": ransom_share,
		"ransom_general": ransom_general,
		"ransom_royal": ransom_royal,
		"ransom_leader": ransom_leader,
		"ai_execute_dread": ai_execute_dread,
		"attack_weight": attack_weight,
		"armour_weight": armour_weight,
		"valour_weight": valour_weight,
		"morale_weight": morale_weight,
		"naval_weight": naval_weight,
		"min_factor": min_factor,
		"star_weight": star_weight,
		"fixed_command": fixed_command.duplicate(),
		"start_valour": start_valour.duplicate(),
		"start_upgrades": start_upgrades.duplicate(),
		"defender_bonus": defender_bonus,
		"sea_defender_bonus": sea_defender_bonus,
		"valour_chance": valour_chance,
		"valour_max": valour_max,
		"loss_min": loss_min,
		"loss_max": loss_max,
		"winner_loss_factor": winner_loss_factor,
		"castle_family": castle_family,
		"castle_levels_per_tier": castle_levels_per_tier,
		"castle_multipliers": Array(castle_multipliers),
		"starve_years": Array(starve_years),
		"garrison_max": garrison_max,
		"cavalry_garrison_weight": cavalry_garrison_weight,
		"assault_annihilates": assault_annihilates,
		"sally_threshold": sally_threshold,
		"fleet_min_range": fleet_min_range,
		"compass_bonus": compass_bonus,
		"compass_event": compass_event,
		"neutral_blockade": neutral_blockade,
		"agents_free_sea": agents_free_sea,
		"agents_any_port": agents_any_port,
		"oceans": oceans.keys(),
		"admirals_on": admirals_on,
		"admiral_start_stars": admiral_start_stars,
		"admiral_max_stars": admiral_max_stars,
		"admiral_wins_per_star": admiral_wins_per_star,
		"forced_outcome": forced_outcome,
	}


## Valore con cui nasce una pila della fazione (0 se non ha un valore iniziale in auror.cfg).
func start_valour_of(faction_id: String) -> int:
	return int(start_valour.get(faction_id.strip_edges().to_upper(), 0))


## Livello di armi e armatura con cui nasce una pila di terra della fazione (0 se auror.cfg non lo da').
func start_upgrades_of(faction_id: String) -> int:
	return int(start_upgrades.get(faction_id.strip_edges().to_upper(), 0))


## Legge `comando_fisso` di ogni sezione FN_* di auror.cfg (ADR-004).
func _read_command(auror_path: String) -> void:
	if auror_path == "" or not FileAccess.file_exists(auror_path):
		return
	var cfg := ConfigFile.new()
	if cfg.load(auror_path) != OK:
		errors.append("Regole dei capi non lette da %s" % auror_path)
		return
	var found := {}
	var valour := {}
	var upgrades := {}
	for section in cfg.get_sections():
		if not section.begins_with("FN_"):
			continue
		var v: Variant = cfg.get_value(section, "comando_fisso", null)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			found[section.to_upper()] = int(v)
		var sv: Variant = cfg.get_value(section, "valore_iniziale", null)
		if typeof(sv) == TYPE_INT or typeof(sv) == TYPE_FLOAT:
			valour[section.to_upper()] = clampi(int(sv), 0, valour_max)
		var uv: Variant = cfg.get_value(section, "armi_armatura_iniziali", null)
		if typeof(uv) == TYPE_INT or typeof(uv) == TYPE_FLOAT:
			upgrades[section.to_upper()] = clampi(int(uv), 0, TroopUpgrades.MAX_LEVEL)
	if not found.is_empty():
		fixed_command = found
	start_valour = valour
	start_upgrades = upgrades


func _check_consistency() -> void:
	if castle_multipliers.is_empty():
		errors.append("castello/moltiplicatore_assalto vuoto: uso i predefiniti")
		castle_multipliers = CombatRules.new().castle_multipliers
	if starve_years.is_empty():
		errors.append("castello/anni_fame vuoto: uso i predefiniti")
		starve_years = CombatRules.new().starve_years
	if capture_share < 0.0 or capture_share > 1.0:
		errors.append("prigionieri/quota_catturati fuori da [0, 1]: uso 0.3")
		capture_share = CombatRules.new().capture_share
	if loss_min < 0.0 or loss_max > 1.0 or loss_min > loss_max:
		errors.append("perdite/perdita_min e perdita_max incoerenti: uso i predefiniti")
		var defaults := CombatRules.new()
		loss_min = defaults.loss_min
		loss_max = defaults.loss_max
	if castle_levels_per_tier < 1:
		errors.append("castello/livelli_per_grado non valido: uso 3")
		castle_levels_per_tier = 3


static func _int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return fallback


static func _float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v)
	return fallback


static func _text(cfg: ConfigFile, section: String, key: String, fallback: String) -> String:
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_STRING:
		return String(v).strip_edges().to_upper()
	return fallback


static func _bool(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_BOOL:
		return bool(v)
	return fallback


static func _floats(cfg: ConfigFile, section: String, key: String, fallback: PackedFloat64Array) -> PackedFloat64Array:
	var v: Variant = cfg.get_value(section, key, null)
	if typeof(v) != TYPE_ARRAY:
		return fallback
	var out := PackedFloat64Array()
	var items: Array = v
	for item in items:
		out.append(float(item))
	return out


static func _ints(cfg: ConfigFile, section: String, key: String, fallback: PackedInt32Array) -> PackedInt32Array:
	var v: Variant = cfg.get_value(section, key, null)
	if typeof(v) != TYPE_ARRAY:
		return fallback
	var out := PackedInt32Array()
	var items: Array = v
	for item in items:
		out.append(int(item))
	return out
