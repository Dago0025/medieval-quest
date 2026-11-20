class_name EventRules
extends RefCounted
## Parametri degli eventi della fase 6a (ADR-004, ADR-011): disastri, Peste Nera e Orda d'Oro, letti da
## data/regole/eventi.cfg, piu' la tabella degli eventi storici letta da data/eventi/eventi_storici.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file (un test lo verifica). La tabella degli eventi storici
## NON e' un parametro: `Rules.new()` ha la tabella vuota (nessun evento storico, mondi di prova inerti), `Rules.load_file()`
## la legge dal file; per questo `to_dict()` la lascia fuori. Tutti i numeri dei disastri e dell'Orda sono PROVVISORI
## (catalogo, sezione "Eventi e fazioni emergenti": «Probabilita' degli eventi: non pubblicate»); le date e gli effetti
## degli eventi storici stanno nel loro file con la fonte di ogni voce.

const DEFAULT_PATH := "res://data/regole/eventi.cfg"
const DEFAULT_HISTORY_PATH := "res://data/eventi/eventi_storici.cfg"

## Effetti ammessi degli eventi storici (vocabolario chiuso della specifica fase 6).
const EFFECT_GOODS := "merci"
const EFFECT_LOYALTY := "lealta"
const EFFECT_ZEAL := "zelo"
const EFFECT_HERETICS := "eretici"
const EFFECT_PIETY := "pieta_capo"
const EFFECT_TREASURY := "tesoro"
const EFFECT_NONE := "nessuno"
const EFFECTS := ["merci", "lealta", "zelo", "eretici", "pieta_capo", "tesoro", "nessuno"]

# --- disastri (probabilita' annue, PROVVISORIE) ---
var flood_chance := 0.01             ## per provincia e anno; non nelle regioni SetRegionUnfloodable
var flood_farm := 0.5                ## spec.: agricoltura dimezzata per un anno
var famine_chance := 0.006           ## per provincia e anno
var famine_loyalty := 10             ## spec.: agricoltura a zero e lealta' -10
var quake_chance := 0.003            ## per provincia e anno; non nelle regioni SetRegionUnquakeable
var storm_chance := 0.02             ## per flotta in mare e anno; la flotta perde una pila
var plague_chance := 0.004           ## per provincia e anno
var plague_losses := 0.10            ## spec.: 10% degli uomini di eserciti e guarnigioni della regione
var plague_spread := 0.25            ## probabilita' di propagarsi a ciascuna provincia confinante

# --- regioni immuni (richiesta di Federico del 18/11/2026: l'isola di Atlantide) ---
## Regioni senza inondazioni, carestie, peste, Peste Nera ed effetti avversi degli eventi storici; i terremoti restano
## ma con la probabilita' moltiplicata per `immune_quake_factor`. Una fazione con la capitale in una di queste regioni
## non subisce i cali di tesoro, lealta' e pieta' degli eventi storici. (sezione [immuni] di eventi.cfg)
var immune_regions := PackedStringArray(["ID_ATLANTIS", "ID_GADEIRA", "ID_AMPHERIA", "ID_MNESEIA", "ID_DIAPREPIA"])
var immune_quake_factor := 0.25

# --- Peste Nera (una sola volta) ---
var black_death_from := 1346         ## finestra storica dell'anno di inizio
var black_death_to := 1353
var black_death_event := 54          ## indice dell'evento storico «God's Judgement on the World» che la annuncia (-1 = nessuno)
var black_death_origin := PackedStringArray(["ID_CRIMEA"])   ## Caffa, 1346
var black_death_losses := 0.25       ## PROVVISORIA: perdite annue degli uomini nelle regioni colpite
var black_death_income := 0.5        ## PROVVISORIA: moltiplicatore del reddito nelle regioni colpite
var black_death_years := 2           ## PROVVISORIA: anni di contagio per regione
var black_death_spread := 0.6        ## PROVVISORIA: propagazione annua a ogni provincia confinante
var black_death_sea := 0.4           ## PROVVISORIA: propagazione annua tra porti che si affacciano sulla stessa zona di mare
var black_death_max_years := 12      ## PROVVISORIA: durata massima del contagio

# --- Orda d'Oro ---
var horde_faction := "FN_GOLDEN_HORDE"
var horde_year := 1230               ## catalogo (MTW Eras, Media)
var horde_entry := PackedStringArray(["ID_KHAZAR", "ID_VOLGA_BULGARIA", "ID_LESSER_KHAZAR"])   ## PROVVISORIA: ingresso a est
var horde_stacks := 8                ## PROVVISORIA: pile di cavalleria all'arrivo
var horde_years := 15                ## PROVVISORIA: anni senza conquiste dopo i quali l'Orda si scioglie
var horde_treasury := 3000           ## PROVVISORIA: tesoro alla comparsa

## Eventi storici (non salvati, fuori da `to_dict`): indice -> HistoricalEvent, in ordine di indice.
var history: Array[HistoricalEvent] = []

## Errori di lettura del file (chiave con tipo sbagliato e simili).
var errors := PackedStringArray()


## Un evento storico: indice nell'ordine di `Historical_event_titles` di Events.txt, anno (o finestra), fonte ed effetto.
## Nessun testo: titolo e testo si leggono da Events.txt (`EventTexts`).
class HistoricalEvent:
	var index := 0
	var key := ""                    ## chiave breve leggibile (non e' il titolo)
	var year_from := 0               ## primo anno della finestra
	var year_to := 0                 ## ultimo anno (uguale al primo = anno fisso)
	var source := ""                 ## fonte o motivazione dell'anno
	var provisional := false         ## data o effetto inventati (PROVVISORIA)
	var faction := ""                ## fazione a cui l'evento si lega, "" se nessuna
	var regions := PackedStringArray()   ## regioni citate dal testo (ID dello startpos)
	var culture := ""                ## per lo zelo: tutte le regioni di questa cultura (per esempio ORTHODOX_CULTURE)
	var effect := "nessuno"          ## uno di `EFFECTS`
	var value := 0                   ## variazione (lealta', zelo, eretici, pieta' del capo, tesoro)
	var goods := PackedStringArray() ## merci aggiunte (effetto `merci`)
	var note := ""                   ## effetti del testo non modellati o scelte dell'autore

	func is_window() -> bool:
		return year_to > year_from

	func to_dict() -> Dictionary:
		return {
			"index": index, "key": key, "year_from": year_from, "year_to": year_to, "source": source,
			"provisional": provisional, "faction": faction, "regions": Array(regions), "culture": culture,
			"effect": effect, "value": value, "goods": Array(goods), "note": note,
		}


## Regole dal file `path` (e la tabella storica da `history_path`, "" = nessuna); le chiavi mancanti restano ai valori
## predefiniti. Se il file delle regole non c'e' o non si legge: valori predefiniti e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH, history_path: String = DEFAULT_HISTORY_PATH) -> EventRules:
	var r := EventRules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		r.errors.append("Regole degli eventi non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
	else:
		r.flood_chance = _float(cfg, "inondazione", "p_inondazione", r.flood_chance)
		r.flood_farm = _float(cfg, "inondazione", "agricoltura_inondazione", r.flood_farm)
		r.famine_chance = _float(cfg, "carestia", "p_carestia", r.famine_chance)
		r.famine_loyalty = _int(cfg, "carestia", "lealta_carestia", r.famine_loyalty)
		r.quake_chance = _float(cfg, "terremoto", "p_terremoto", r.quake_chance)
		r.storm_chance = _float(cfg, "tempesta", "p_tempesta", r.storm_chance)
		r.plague_chance = _float(cfg, "peste", "p_peste", r.plague_chance)
		r.plague_losses = _float(cfg, "peste", "perdite_peste", r.plague_losses)
		r.plague_spread = _float(cfg, "peste", "p_propagazione_peste", r.plague_spread)
		r.black_death_from = _int(cfg, "peste_nera", "anno_da", r.black_death_from)
		r.black_death_to = _int(cfg, "peste_nera", "anno_a", r.black_death_to)
		r.black_death_event = _int(cfg, "peste_nera", "evento_storico", r.black_death_event)
		r.black_death_origin = _texts(cfg, "peste_nera", "regioni_origine", r.black_death_origin)
		r.black_death_losses = _float(cfg, "peste_nera", "perdite", r.black_death_losses)
		r.black_death_income = _float(cfg, "peste_nera", "reddito", r.black_death_income)
		r.black_death_years = _int(cfg, "peste_nera", "anni_per_regione", r.black_death_years)
		r.black_death_spread = _float(cfg, "peste_nera", "p_propagazione", r.black_death_spread)
		r.black_death_sea = _float(cfg, "peste_nera", "p_via_mare", r.black_death_sea)
		r.black_death_max_years = _int(cfg, "peste_nera", "anni_massimi", r.black_death_max_years)
		r.immune_regions = _texts(cfg, "immuni", "regioni", r.immune_regions)
		r.immune_quake_factor = _float(cfg, "immuni", "fattore_terremoto", r.immune_quake_factor)
		r.horde_faction = _text(cfg, "orda", "fazione", r.horde_faction)
		r.horde_year = _int(cfg, "orda", "anno_orda", r.horde_year)
		r.horde_entry = _texts(cfg, "orda", "regioni_ingresso", r.horde_entry)
		r.horde_stacks = _int(cfg, "orda", "pile_orda", r.horde_stacks)
		r.horde_years = _int(cfg, "orda", "anni_orda", r.horde_years)
		r.horde_treasury = _int(cfg, "orda", "tesoro_orda", r.horde_treasury)
		r._check_consistency()
	if history_path != "" and FileAccess.file_exists(history_path):
		r.errors.append_array(r.load_history(history_path))
	return r


## Legge la tabella degli eventi storici (`eventi_storici.cfg`: una sezione per indice). Sostituisce `history`.
## Restituisce gli errori trovati (sezione senza indice, effetto sconosciuto, finestra rovesciata...).
func load_history(path: String) -> PackedStringArray:
	var problems := PackedStringArray()
	history.clear()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		problems.append("Eventi storici non letti da %s (errore %d)" % [path, err])
		return problems
	var found: Array[HistoricalEvent] = []
	for section in cfg.get_sections():
		var e := HistoricalEvent.new()
		if not cfg.has_section_key(section, "indice"):
			problems.append("Eventi storici: la sezione %s non ha l'indice" % section)
			continue
		e.index = _int(cfg, section, "indice", -1)
		e.key = _text_raw(cfg, section, "chiave", "")
		e.year_from = _int(cfg, section, "anno_da", 0)
		e.year_to = _int(cfg, section, "anno_a", e.year_from)
		e.source = _text_raw(cfg, section, "fonte", "")
		e.provisional = bool(cfg.get_value(section, "provvisoria", false)) if cfg.has_section_key(section, "provvisoria") else false
		e.faction = _text(cfg, section, "fazione", "")
		e.regions = _texts(cfg, section, "regioni", PackedStringArray())
		e.culture = _text(cfg, section, "cultura", "")
		e.effect = _text_raw(cfg, section, "effetto", EFFECT_NONE)
		e.value = _int(cfg, section, "valore", 0)
		e.goods = _texts(cfg, section, "merci", PackedStringArray())
		e.note = _text_raw(cfg, section, "nota", "")
		if e.index < 0:
			problems.append("Eventi storici: la sezione %s ha un indice non valido" % section)
			continue
		if e.year_from <= 0 or e.year_to < e.year_from:
			problems.append("Eventi storici: l'evento %d ha una finestra di anni non valida (%d-%d)" % [e.index, e.year_from, e.year_to])
			continue
		if not EFFECTS.has(e.effect):
			problems.append("Eventi storici: l'evento %d ha un effetto sconosciuto (%s)" % [e.index, e.effect])
			e.effect = EFFECT_NONE
		found.append(e)
	found.sort_custom(_by_index)
	var seen := {}
	for e in found:
		if seen.has(e.index):
			problems.append("Eventi storici: l'indice %d e' ripetuto" % e.index)
			continue
		seen[e.index] = true
		history.append(e)
	return problems


static func _by_index(a: HistoricalEvent, b: HistoricalEvent) -> bool:
	return a.index < b.index


## Vero se la regione e' immune ai disastri e agli eventi avversi (`[immuni]`, Atlantide).
func is_immune(region_id: String) -> bool:
	return immune_regions.has(region_id.strip_edges().to_upper())


## Probabilita' annua di terremoto nella regione: quella comune, ridotta nelle regioni immuni.
func quake_chance_for(region_id: String) -> float:
	return quake_chance * immune_quake_factor if is_immune(region_id) else quake_chance


## Evento storico di indice `index`, null se non c'e'.
func historical(index: int) -> HistoricalEvent:
	for e in history:
		if e.index == index:
			return e
	return null


## Tutti i parametri (esclusa la tabella storica) in un Dictionary, per confronti nei test e per i rapporti.
func to_dict() -> Dictionary:
	return {
		"flood_chance": flood_chance,
		"flood_farm": flood_farm,
		"famine_chance": famine_chance,
		"famine_loyalty": famine_loyalty,
		"quake_chance": quake_chance,
		"immune_regions": Array(immune_regions),
		"immune_quake_factor": immune_quake_factor,
		"storm_chance": storm_chance,
		"plague_chance": plague_chance,
		"plague_losses": plague_losses,
		"plague_spread": plague_spread,
		"black_death_from": black_death_from,
		"black_death_to": black_death_to,
		"black_death_event": black_death_event,
		"black_death_origin": Array(black_death_origin),
		"black_death_losses": black_death_losses,
		"black_death_income": black_death_income,
		"black_death_years": black_death_years,
		"black_death_spread": black_death_spread,
		"black_death_sea": black_death_sea,
		"black_death_max_years": black_death_max_years,
		"horde_faction": horde_faction,
		"horde_year": horde_year,
		"horde_entry": Array(horde_entry),
		"horde_stacks": horde_stacks,
		"horde_years": horde_years,
		"horde_treasury": horde_treasury,
	}


func _check_consistency() -> void:
	flood_chance = _probability("p_inondazione", flood_chance)
	flood_farm = clampf(flood_farm, 0.0, 1.0)
	famine_chance = _probability("p_carestia", famine_chance)
	quake_chance = _probability("p_terremoto", quake_chance)
	immune_quake_factor = clampf(immune_quake_factor, 0.0, 1.0)
	var upper := PackedStringArray()
	for region_id in immune_regions:
		upper.append(region_id.strip_edges().to_upper())
	immune_regions = upper
	storm_chance = _probability("p_tempesta", storm_chance)
	plague_chance = _probability("p_peste", plague_chance)
	plague_losses = clampf(plague_losses, 0.0, 1.0)
	plague_spread = _probability("p_propagazione_peste", plague_spread)
	black_death_losses = clampf(black_death_losses, 0.0, 1.0)
	black_death_income = clampf(black_death_income, 0.0, 1.0)
	black_death_spread = _probability("p_propagazione", black_death_spread)
	black_death_sea = _probability("p_via_mare", black_death_sea)
	if black_death_to < black_death_from:
		errors.append("peste_nera: la finestra e' rovesciata, la scambio")
		var tmp := black_death_from
		black_death_from = black_death_to
		black_death_to = tmp
	if black_death_years < 1:
		errors.append("peste_nera/anni_per_regione sotto 1: uso 1")
		black_death_years = 1
	if black_death_max_years < 1:
		errors.append("peste_nera/anni_massimi sotto 1: uso 1")
		black_death_max_years = 1
	if horde_stacks < 1:
		errors.append("orda/pile_orda sotto 1: uso 1")
		horde_stacks = 1
	if horde_years < 1:
		errors.append("orda/anni_orda sotto 1: uso 1")
		horde_years = 1
	if famine_loyalty < 0:
		errors.append("carestia/lealta_carestia negativa: uso 0")
		famine_loyalty = 0


func _probability(label: String, value: float) -> float:
	if value < 0.0 or value > 1.0:
		errors.append("%s fuori da 0..1: la limito" % label)
		return clampf(value, 0.0, 1.0)
	return value


static func _int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return fallback


static func _float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v)
	return fallback


## Testo in maiuscolo (ID di fazioni, regioni, merci, culture).
static func _text(cfg: ConfigFile, section: String, key: String, fallback: String) -> String:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_STRING:
		return String(v).strip_edges().to_upper()
	return fallback


## Testo come scritto (chiavi, fonti, note, nomi degli effetti).
static func _text_raw(cfg: ConfigFile, section: String, key: String, fallback: String) -> String:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, fallback)
	if typeof(v) == TYPE_STRING:
		return String(v).strip_edges()
	return fallback


static func _texts(cfg: ConfigFile, section: String, key: String, fallback: PackedStringArray) -> PackedStringArray:
	if not cfg.has_section_key(section, key):
		return fallback
	var v: Variant = cfg.get_value(section, key, null)
	if typeof(v) != TYPE_ARRAY:
		return fallback
	var out := PackedStringArray()
	var items: Array = v
	for item in items:
		out.append(String(item).strip_edges().to_upper())
	return out
