class_name DynastyRules
extends RefCounted
## Parametri dei personaggi e delle dinastie (fase 4a, ADR-004), letti da data/regole/personaggi.cfg
## e, per le regole degli Auror, da data/regole/auror.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file, cosi' i test girano anche senza
## file (un test controlla che restino uguali). Il codice della simulazione legge solo da questa
## classe, che `Rules` espone come `rules.dynasty`. Dove una regola non ha fonte e' PROVVISORIA
## (catalogo: sezione "Personaggi e dinastie"); il file dice quali.

const DEFAULT_PATH := "res://data/regole/personaggi.cfg"
const AUROR_PATH := "res://data/regole/auror.cfg"

## Valore massimo degli attributi (scala 0..massimo).
var max_attribute := 10

# --- invecchiamento e morte ---
var old_age := 40                  ## eta' di vecchiaia di base
var old_age_spread := 4            ## la soglia aggiunge un intero casuale 0..4
var royal_old_age_bonus := 10      ## sangue reale ed eroi: +10
var death_divisor := 50.0          ## probabilita' annua = (eta - soglia + k) / 50
var death_k := 0.0                 ## PROVVISORIA: piccolo k dell'eseguibile, non ricavato

# --- nascite ---
var birth_chance := 0.25           ## PROVVISORIA
var birth_age_min := 18
var birth_age_max := 55
var son_chance := 0.5

# --- maggiore eta' ---
var prince_age := 16
var princess_age := 15
var princess_retire_age := 32

# --- successione e valori iniziali ---
var inherit_spread := 3            ## PROVVISORIA: attributi del figlio entro +-3 da quelli del padre
var successor_influence := 2       ## PROVVISORIA
var start_influence := 5           ## PROVVISORIA
var start_age_min := 30            ## PROVVISORIA: eta' del capo iniziale
var start_age_max := 45
var start_attr_min := 2            ## PROVVISORIA: attributi del capo iniziale non famoso
var start_attr_max := 5
var general_age_min := 25          ## PROVVISORIA: generali generati
var general_age_max := 45
var general_attr_min := 0
var general_attr_max := 3
var general_loyalty_min := 4
var general_loyalty_max := 8
var child_loyalty := 8             ## PROVVISORIA: gli eredi sono sempre leali (manuale p17)
var hero_age_min := 25             ## PROVVISORIA: eta' degli eroi famosi alla comparsa
var hero_age_max := 40

# --- influenza, stelle, titoli, economia ---
var influence_step := 2            ## province perse o conquistate per ogni punto di influenza
var star_win_chance := 0.2         ## PROVVISORIA
var star_loss_chance := 0.15       ## PROVVISORIA
var revoke_loyalty_drop := 2       ## PROVVISORIA
var high_tax_level := 3            ## PROVVISORIA: livello di tassa "alta" per la catena Dread (0-4)
var high_tax_share := 0.5          ## PROVVISORIA: quota di province a tassa alta oltre la quale conta l'anno
var governor_acumen := 0.10        ## per punto di acume del governatore (agricoltura e commercio)
var king_acumen := 0.02            ## per punto di acume del re (agricoltura e commercio)

## Regole fisse per fazione (da auror.cfg, sezioni FN_*): fazione -> Dictionary con le chiavi
## "command", "loyalty", "influence" (interi), "immortal_king" (bool), "leader_name" (nome riservato al capo),
## "leader_title" (titolo del capo al posto di «re»), "longevity_min"/"longevity_max" (eta' minima di vecchiaia di
## generali, principi, principesse e agenti, da `vecchiaia_minima`/`vecchiaia_massima`).
## Le chiavi mancanti nel file non compaiono.
var fixed := {
	"FN_DANISH": {"command": 9, "loyalty": 9, "influence": 9, "immortal_king": true, "invulnerable_king": true,
		"king_refuge": "ID_ATLANTIS", "leader_name": "Darkos", "leader_title": "Imperatore Dio",
		"longevity_min": 100, "longevity_max": 150,
		"remarry_min": 20, "remarry_max": 30, "remarry_fertile": 10},
}

## Errori di lettura dei file (chiave con tipo sbagliato e simili).
var errors := PackedStringArray()


## Regole dal file `path`; le chiavi mancanti restano ai valori predefiniti. Se il file non c'e' o
## non si legge: valori predefiniti e un errore in `errors`. Le regole fisse delle fazioni si
## leggono da `auror_path` (se il file non c'e', restano quelle predefinite).
static func load_file(path: String = DEFAULT_PATH, auror_path: String = AUROR_PATH) -> DynastyRules:
	var r := DynastyRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole dei personaggi non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return r
	r.max_attribute = _int(cfg, "attributi", "massimo", r.max_attribute)
	r.old_age = _int(cfg, "invecchiamento", "eta_vecchiaia", r.old_age)
	r.old_age_spread = _int(cfg, "invecchiamento", "scarto_soglia", r.old_age_spread)
	r.royal_old_age_bonus = _int(cfg, "invecchiamento", "bonus_sangue_reale", r.royal_old_age_bonus)
	r.death_divisor = _float(cfg, "invecchiamento", "divisore_morte", r.death_divisor)
	r.death_k = _float(cfg, "invecchiamento", "k_morte", r.death_k)
	r.birth_chance = _float(cfg, "nascite", "p_nascita", r.birth_chance)
	r.birth_age_min = _int(cfg, "nascite", "eta_capo_min", r.birth_age_min)
	r.birth_age_max = _int(cfg, "nascite", "eta_capo_max", r.birth_age_max)
	r.son_chance = _float(cfg, "nascite", "p_maschio", r.son_chance)
	r.prince_age = _int(cfg, "maggiore_eta", "eta_principe", r.prince_age)
	r.princess_age = _int(cfg, "maggiore_eta", "eta_principessa", r.princess_age)
	r.princess_retire_age = _int(cfg, "maggiore_eta", "eta_ritiro_principessa", r.princess_retire_age)
	r.inherit_spread = _int(cfg, "successione", "scarto_attributi", r.inherit_spread)
	r.successor_influence = _int(cfg, "successione", "influenza_successore", r.successor_influence)
	r.start_influence = _int(cfg, "iniziali", "influenza_capo", r.start_influence)
	r.start_age_min = _int(cfg, "iniziali", "eta_capo_min", r.start_age_min)
	r.start_age_max = _int(cfg, "iniziali", "eta_capo_max", r.start_age_max)
	r.start_attr_min = _int(cfg, "iniziali", "attributo_capo_min", r.start_attr_min)
	r.start_attr_max = _int(cfg, "iniziali", "attributo_capo_max", r.start_attr_max)
	r.general_age_min = _int(cfg, "iniziali", "eta_generale_min", r.general_age_min)
	r.general_age_max = _int(cfg, "iniziali", "eta_generale_max", r.general_age_max)
	r.general_attr_min = _int(cfg, "iniziali", "attributo_generale_min", r.general_attr_min)
	r.general_attr_max = _int(cfg, "iniziali", "attributo_generale_max", r.general_attr_max)
	r.general_loyalty_min = _int(cfg, "iniziali", "lealta_generale_min", r.general_loyalty_min)
	r.general_loyalty_max = _int(cfg, "iniziali", "lealta_generale_max", r.general_loyalty_max)
	r.child_loyalty = _int(cfg, "iniziali", "lealta_figli", r.child_loyalty)
	r.hero_age_min = _int(cfg, "iniziali", "eta_eroe_min", r.hero_age_min)
	r.hero_age_max = _int(cfg, "iniziali", "eta_eroe_max", r.hero_age_max)
	r.influence_step = _int(cfg, "influenza", "province_per_punto", r.influence_step)
	r.star_win_chance = _float(cfg, "generali", "p_stella_vittoria", r.star_win_chance)
	r.star_loss_chance = _float(cfg, "generali", "p_stella_sconfitta", r.star_loss_chance)
	r.revoke_loyalty_drop = _int(cfg, "titoli", "calo_lealta_revoca", r.revoke_loyalty_drop)
	r.high_tax_level = _int(cfg, "terrore", "livello_tassa_alta", r.high_tax_level)
	r.high_tax_share = _float(cfg, "terrore", "quota_province_tassa_alta", r.high_tax_share)
	r.governor_acumen = _float(cfg, "economia", "acume_governatore", r.governor_acumen)
	r.king_acumen = _float(cfg, "economia", "acume_re", r.king_acumen)
	r._read_fixed(auror_path)
	r._check_consistency()
	return r


## Valore fisso di un attributo per una fazione ("command", "loyalty", "influence"); -1 se non e' fisso.
func fixed_value(faction_id: String, attr: String) -> int:
	var entry: Variant = fixed.get(faction_id.strip_edges().to_upper())
	if typeof(entry) != TYPE_DICTIONARY:
		return -1
	var d: Dictionary = entry
	return int(d.get(attr, -1))


## Vero se il capo della fazione non muore di vecchiaia (`re_immortale`).
func is_king_immortal(faction_id: String) -> bool:
	var entry: Variant = fixed.get(faction_id.strip_edges().to_upper())
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = entry
	return bool(d.get("immortal_king", false))


## Vero se il capo della fazione non muore mai (`re_invulnerabile`, ADR-075): niente assassini, roghi ne' esecuzioni.
func is_king_invulnerable(faction_id: String) -> bool:
	var entry: Variant = fixed.get(faction_id.strip_edges().to_upper())
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = entry
	return bool(d.get("invulnerable_king", false))


## Provincia dove ricompare il capo invulnerabile giustiziato (`rifugio_re`), "" se non c'e'.
func king_refuge(faction_id: String) -> String:
	var entry: Variant = fixed.get(faction_id.strip_edges().to_upper())
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	var d: Dictionary = entry
	return str(d.get("king_refuge", "")).to_upper()


## Eta' di vecchiaia minima di un personaggio della fazione (`vecchiaia_minima`..`vecchiaia_massima`, richiesta di Federico
## del 18/11/2026: generali e agenti degli Auror vivono almeno 100-150 anni), 0 se la fazione non ce l'ha. Il valore e'
## stabile per personaggio (dall'id, nessun sorteggio: non sposta il generatore della partita).
func longevity_threshold(faction_id: String, character_id: int) -> int:
	var entry: Variant = fixed.get(faction_id.strip_edges().to_upper())
	if typeof(entry) != TYPE_DICTIONARY:
		return 0
	var d: Dictionary = entry
	var low := int(d.get("longevity_min", 0))
	if low <= 0:
		return 0
	var high := maxi(int(d.get("longevity_max", low)), low)
	return low + posmod(character_id * 7919 + 104729, high - low + 1)


## Nuove nozze del capo immortale (`nozze_capo_ogni_min`, `nozze_capo_ogni_max`, `nozze_capo_anni_fertili`; richiesta di
## Federico del 20/11/2026): {"min", "max", "fertile"} oppure vuoto se la fazione non ce le ha.
func remarriage(faction_id: String) -> Dictionary:
	var entry: Variant = fixed.get(faction_id.strip_edges().to_upper())
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = entry
	var low := int(d.get("remarry_min", 0))
	if low <= 0:
		return {}
	return {"min": low, "max": maxi(int(d.get("remarry_max", low)), low), "fertile": maxi(int(d.get("remarry_fertile", 10)), 0)}


## Anni fino alle nozze successive del capo, tra `min` e `max` di `remarriage`: stabile per personaggio e anno (dall'id,
## nessun sorteggio), 0 se la fazione non ha nuove nozze.
func remarriage_interval(faction_id: String, character_id: int, year: int) -> int:
	var plan := remarriage(faction_id)
	if plan.is_empty():
		return 0
	var low := int(plan["min"])
	return low + posmod(character_id * 7919 + year * 104729, int(plan["max"]) - low + 1)


## Nome riservato al capo della fazione (`nome_solo_capo`: per gli Auror Darkos, che nessun erede o principe riceve;
## richiesta di Federico del 16/11/2026), "" se non c'e'.
func leader_name(faction_id: String) -> String:
	return _fixed_text(faction_id, "leader_name")


## Titolo del capo della fazione al posto di «re» (`titolo_capo`: per gli Auror «Imperatore Dio»; richiesta di Federico
## del 16/11/2026), "" se non c'e'.
func leader_title(faction_id: String) -> String:
	return _fixed_text(faction_id, "leader_title")


func _fixed_text(faction_id: String, key: String) -> String:
	var entry: Variant = fixed.get(faction_id.strip_edges().to_upper())
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	var d: Dictionary = entry
	return str(d.get(key, ""))


## Probabilita' annua di morte per vecchiaia: (eta - soglia + k) / divisore, tra 0 e 1;
## 0 fino alla soglia compresa.
func death_chance(age: int, threshold: int) -> float:
	if age <= threshold:
		return 0.0
	return clampf((float(age - threshold) + death_k) / death_divisor, 0.0, 1.0)


## Tutti i parametri in un Dictionary (per confronti nei test e per i rapporti).
func to_dict() -> Dictionary:
	return {
		"max_attribute": max_attribute,
		"old_age": old_age,
		"old_age_spread": old_age_spread,
		"royal_old_age_bonus": royal_old_age_bonus,
		"death_divisor": death_divisor,
		"death_k": death_k,
		"birth_chance": birth_chance,
		"birth_age_min": birth_age_min,
		"birth_age_max": birth_age_max,
		"son_chance": son_chance,
		"prince_age": prince_age,
		"princess_age": princess_age,
		"princess_retire_age": princess_retire_age,
		"inherit_spread": inherit_spread,
		"successor_influence": successor_influence,
		"start_influence": start_influence,
		"start_age_min": start_age_min,
		"start_age_max": start_age_max,
		"start_attr_min": start_attr_min,
		"start_attr_max": start_attr_max,
		"general_age_min": general_age_min,
		"general_age_max": general_age_max,
		"general_attr_min": general_attr_min,
		"general_attr_max": general_attr_max,
		"general_loyalty_min": general_loyalty_min,
		"general_loyalty_max": general_loyalty_max,
		"child_loyalty": child_loyalty,
		"hero_age_min": hero_age_min,
		"hero_age_max": hero_age_max,
		"influence_step": influence_step,
		"star_win_chance": star_win_chance,
		"star_loss_chance": star_loss_chance,
		"revoke_loyalty_drop": revoke_loyalty_drop,
		"high_tax_level": high_tax_level,
		"high_tax_share": high_tax_share,
		"governor_acumen": governor_acumen,
		"king_acumen": king_acumen,
		"fixed": fixed.duplicate(true),
	}


## Legge command/loyalty/influence/immortal_king/leader_name/leader_title di ogni sezione FN_* di auror.cfg.
func _read_fixed(auror_path: String) -> void:
	if auror_path == "" or not FileAccess.file_exists(auror_path):
		return
	var cfg := ConfigFile.new()
	if cfg.load(auror_path) != OK:
		errors.append("Regole dei capi non lette da %s" % auror_path)
		return
	var found := {}
	for section in cfg.get_sections():
		if not section.begins_with("FN_"):
			continue
		var entry := {}
		var v: Variant = cfg.get_value(section, "comando_fisso", null)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			entry["command"] = int(v)
		v = cfg.get_value(section, "fedelta_fissa", null)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			entry["loyalty"] = int(v)
		v = cfg.get_value(section, "influenza_fissa", null)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			entry["influence"] = int(v)
		v = cfg.get_value(section, "re_immortale", null)
		if typeof(v) == TYPE_BOOL:
			entry["immortal_king"] = bool(v)
		v = cfg.get_value(section, "re_invulnerabile", null)
		if typeof(v) == TYPE_BOOL:
			entry["invulnerable_king"] = bool(v)
		v = cfg.get_value(section, "rifugio_re", null)
		if typeof(v) == TYPE_STRING:
			entry["king_refuge"] = str(v).to_upper()
		v = cfg.get_value(section, "nome_solo_capo", null)
		if typeof(v) == TYPE_STRING and str(v).strip_edges() != "":
			entry["leader_name"] = str(v).strip_edges()
		v = cfg.get_value(section, "vecchiaia_minima", null)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			entry["longevity_min"] = int(v)
			var top: Variant = cfg.get_value(section, "vecchiaia_massima", v)
			entry["longevity_max"] = maxi(int(top), int(v)) if typeof(top) == TYPE_INT or typeof(top) == TYPE_FLOAT else int(v)
		v = cfg.get_value(section, "nozze_capo_ogni_min", null)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			entry["remarry_min"] = int(v)
			var most: Variant = cfg.get_value(section, "nozze_capo_ogni_max", v)
			entry["remarry_max"] = maxi(int(most), int(v)) if typeof(most) == TYPE_INT or typeof(most) == TYPE_FLOAT else int(v)
			var fertile: Variant = cfg.get_value(section, "nozze_capo_anni_fertili", 10)
			entry["remarry_fertile"] = int(fertile) if typeof(fertile) == TYPE_INT or typeof(fertile) == TYPE_FLOAT else 10
		v = cfg.get_value(section, "titolo_capo", null)
		if typeof(v) == TYPE_STRING and str(v).strip_edges() != "":
			entry["leader_title"] = str(v).strip_edges()
		if not entry.is_empty():
			found[section.to_upper()] = entry
	if not found.is_empty():
		fixed = found


func _check_consistency() -> void:
	var defaults := DynastyRules.new()
	if max_attribute < 1:
		errors.append("attributi/massimo non valido: uso 10")
		max_attribute = defaults.max_attribute
	if death_divisor <= 0.0:
		errors.append("invecchiamento/divisore_morte non valido: uso 50")
		death_divisor = defaults.death_divisor
	if birth_age_min > birth_age_max:
		errors.append("nascite/eta_capo_min e eta_capo_max incoerenti: uso i predefiniti")
		birth_age_min = defaults.birth_age_min
		birth_age_max = defaults.birth_age_max
	if influence_step < 1:
		errors.append("influenza/province_per_punto non valido: uso 2")
		influence_step = defaults.influence_step
	if old_age_spread < 0:
		errors.append("invecchiamento/scarto_soglia negativo: uso 4")
		old_age_spread = defaults.old_age_spread


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
