class_name LegendarySites
extends RefCounted
## Luoghi leggendari (richiesta di Federico del 26/11/2026, doc di progetto specifiche/luoghi_leggendari.md): luoghi storici,
## mitologici e marini della mappa del mondo con effetti per chi li possiede (terra) o per chi presidia la zona (mare), una
## scoperta alla prima conquista ed eventi, alcuni con una scelta. Dati in data/luoghi/luoghi.cfg, posizioni sulla plancia in
## data/luoghi/posizioni.cfg (tools/mondo/posiziona_luoghi.py). `Rules.new()` ha il catalogo vuoto: senza file nessun effetto.
## Gli effetti valgono per chiunque possieda il luogo, giocatore o IA (parita', ADR-015). Valori PROVVISORI.
## Lo stato che cambia (prossimi eventi, presidi, conquistatori, scelte in attesa) sta in GameState e lo gestisce
## LegendarySiteProcessor; questa classe legge il catalogo e calcola gli effetti.

const DEFAULT_PATH := "res://data/luoghi/luoghi.cfg"
const POSITIONS_FILE := "posizioni.cfg"

const STORICO := "storico"
const MITOLOGICO := "mitologico"
const MARINO := "marino"
const CATEGORIES := [STORICO, MITOLOGICO, MARINO]

const KIND_RECURRING := "ricorrente"
const KIND_CONDITIONAL := "condizionato"
const KIND_HISTORICAL := "storico"
const WHO_GENERAL := "generale"
const WHO_FLEET := "flotta"
const WHO_AGENT := "agente"

## Effetti continui in percentuale (+20 = +20%).
const PERCENT_KEYS := ["agricoltura", "commercio", "miniere", "reddito", "commercio_marittimo", "difesa",
	"terremoti", "carestia", "peste", "inondazioni", "tempeste", "bersaglio_ia"]
## Effetti continui interi.
const INT_KEYS := ["lealta", "valore_emissari", "valore_spie", "valore_religiosi", "armi_reclute", "mantenimento", "anni_assedio"]
## Effetto continuo a dizionario {religione: punti l'anno}.
const DICT_KEYS := ["conversione"]
## Effetti che valgono per tutta la fazione proprietaria (non solo per la provincia).
const FACTION_KEYS := ["tempeste"]
## Esiti una tantum (scoperta, eventi).
const OUTCOME_KEYS := ["tesoro", "pieta_capo", "terrore_capo", "influenza_capo", "acume_capo", "lealta_generali", "stelle",
	"vita", "muore", "navi_perse", "uomini_persi", "ordine", "conversione", "fine_luogo", "p"]
const OTHER_RELIGIONS := "altre"


class Site:
	extends RefCounted
	var id := ""
	var category := "storico"
	var symbol := ""
	var region := ""
	var auror_only := false
	var phantom_every := 0       ## > 0: si manifesta un anno ogni tanti (Hy-Brasil, Shambhala)
	var name := ""
	var name_en := ""
	var description := ""
	var description_en := ""
	var effects := {}
	var effects_religion := {}
	var after_year := 0
	var effects_after := {}
	var name_after := ""
	var name_after_en := ""
	var transit := {}
	var garrison_years := 0
	var garrison := {}
	var discovery := {}
	var events := PackedStringArray()
	var position := Vector2.ZERO
	var has_position := false

	func is_sea() -> bool:
		return category == LegendarySites.MARINO

	## Nome nella lingua del gioco, alla data `year` (rovine dopo `after_year`).
	func label(year: int = 0) -> String:
		var en := Lang.is_english()
		if after_year > 0 and year >= after_year and name_after != "":
			return name_after_en if en and name_after_en != "" else name_after
		return name_en if en and name_en != "" else name

	func text() -> String:
		return description_en if Lang.is_english() and description_en != "" else description


class SiteEvent:
	extends RefCounted
	var id := ""
	var site := ""
	var kind := "ricorrente"
	var every := Vector2i(10, 15)
	var until_year := 0
	var who := ""
	var chance := 0
	var once := ""               ## "personaggio" | "fazione" | "" (ripetibile dopo `wait` anni)
	var wait := 0
	var religions := PackedStringArray()
	var year := 0
	var title := ""
	var title_en := ""
	var text := ""
	var text_en := ""
	var options: Array[Dictionary] = []
	var outcome := {}
	var has_outcome := false

	func has_choice() -> bool:
		return not options.is_empty()

	func label() -> String:
		return title_en if Lang.is_english() and title_en != "" else title

	func body() -> String:
		return text_en if Lang.is_english() and text_en != "" else text

	static func option_label(option: Dictionary) -> String:
		var en := str(option.get("testo_en", ""))
		return en if Lang.is_english() and en != "" else str(option.get("testo", ""))


var sites: Array[Site] = []
var events := {}               ## id -> SiteEvent
var errors := PackedStringArray()
var _by_id := {}
var _by_region := {}           ## id regione -> Array[Site]
var _by_key := {}              ## effetto -> Array[Site] che lo hanno (presidio del mare o effetti di terra): calcoli piu' rapidi


static func load_file(path: String = DEFAULT_PATH) -> LegendarySites:
	var t := LegendarySites.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		t.errors.append("Luoghi leggendari non letti da %s (errore %d)" % [path, err])
		return t
	var positions := ConfigFile.new()
	var pos_ok := positions.load(path.get_base_dir().path_join(POSITIONS_FILE)) == OK
	t._read_all(cfg, positions if pos_ok else null)
	return t


## Catalogo da un testo nel formato di luoghi.cfg (per i test).
static func parse_text(text: String) -> LegendarySites:
	var t := LegendarySites.new()
	var cfg := ConfigFile.new()
	var err := cfg.parse(text)
	if err != OK:
		t.errors.append("Luoghi leggendari non leggibili (errore %d)" % err)
		return t
	t._read_all(cfg, null)
	return t


func _read_all(cfg: ConfigFile, positions: ConfigFile) -> void:
	for section in cfg.get_sections():
		if section.begins_with("evento."):
			_read_event(cfg, section)
		else:
			_read_site(cfg, section, positions)
	for s in sites:
		var keys := {}
		for d in [s.effects, s.effects_after, s.garrison]:
			for k in d:
				keys[k] = true
		for k in s.effects_religion:
			for kk in s.effects_religion[k]:
				keys[kk] = true
		for k in keys:
			var list: Array = _by_key.get(k, [])
			list.append(s)
			_by_key[k] = list


	for s in sites:
		for eid in s.events:
			if not events.has(eid):
				errors.append("%s: evento %s inesistente" % [s.id, eid])
	for eid in events:
		var e: SiteEvent = events[eid]
		if not _by_id.has(e.site):
			errors.append("evento %s: luogo %s inesistente" % [eid, e.site])


## Luoghi che hanno l'effetto `key` (in qualsiasi forma).
func with_key(key: String) -> Array:
	return _by_key.get(key, [])


func _read_site(cfg: ConfigFile, section: String, positions: ConfigFile) -> void:
	var s := Site.new()
	s.id = section.strip_edges()
	s.category = str(cfg.get_value(section, "categoria", STORICO))
	if not CATEGORIES.has(s.category):
		errors.append("%s: categoria sconosciuta %s" % [s.id, s.category])
	s.symbol = str(cfg.get_value(section, "simbolo", ""))
	s.region = SimUtil.norm(str(cfg.get_value(section, "regione", "")))
	s.auror_only = bool(cfg.get_value(section, "solo_auror", false))
	s.phantom_every = int(cfg.get_value(section, "fantasma_ogni", 0))
	s.name = str(cfg.get_value(section, "nome", s.id))
	s.name_en = str(cfg.get_value(section, "nome_en", ""))
	s.description = str(cfg.get_value(section, "descrizione", ""))
	s.description_en = str(cfg.get_value(section, "descrizione_en", ""))
	s.effects = _effects(s.id, cfg.get_value(section, "effetti", {}))
	var by_rel: Variant = cfg.get_value(section, "effetti_religione", {})
	if typeof(by_rel) == TYPE_DICTIONARY:
		for k in by_rel:
			s.effects_religion[str(k)] = _effects(s.id, by_rel[k])
	s.after_year = int(cfg.get_value(section, "dopo_anno", 0))
	s.effects_after = _effects(s.id, cfg.get_value(section, "effetti_dopo", {}))
	s.name_after = str(cfg.get_value(section, "nome_dopo", ""))
	s.name_after_en = str(cfg.get_value(section, "nome_dopo_en", ""))
	var tr: Variant = cfg.get_value(section, "transito", {})
	s.transit = tr if typeof(tr) == TYPE_DICTIONARY else {}
	s.garrison_years = int(cfg.get_value(section, "presidio_anni", 0))
	s.garrison = _effects(s.id, cfg.get_value(section, "presidio", {}))
	var disc: Variant = cfg.get_value(section, "scoperta", {})
	s.discovery = disc if typeof(disc) == TYPE_DICTIONARY else {}
	for eid in cfg.get_value(section, "eventi", []):
		s.events.append(str(eid))
	if positions != null and positions.has_section_key("posizioni", s.id):
		var v: Variant = positions.get_value("posizioni", s.id)
		if typeof(v) == TYPE_VECTOR2:
			s.position = v
			s.has_position = true
	if s.region == "":
		errors.append("%s: regione mancante" % s.id)
	sites.append(s)
	_by_id[s.id] = s
	var list: Array = _by_region.get(s.region, [])
	list.append(s)
	_by_region[s.region] = list


func _effects(site_id: String, raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for k in raw:
		var key := str(k)
		var v: Variant = raw[k]
		if PERCENT_KEYS.has(key) or INT_KEYS.has(key):
			if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
				errors.append("%s: %s non e' un numero" % [site_id, key])
				continue
			out[key] = float(v) if PERCENT_KEYS.has(key) else int(v)
		elif DICT_KEYS.has(key) and typeof(v) == TYPE_DICTIONARY:
			out[key] = (v as Dictionary).duplicate()
		else:
			errors.append("%s: effetto sconosciuto %s" % [site_id, key])
	return out


func _read_event(cfg: ConfigFile, section: String) -> void:
	var e := SiteEvent.new()
	e.id = section.substr("evento.".length()).strip_edges()
	e.site = str(cfg.get_value(section, "luogo", ""))
	e.kind = str(cfg.get_value(section, "tipo", KIND_RECURRING))
	var every: Variant = cfg.get_value(section, "ogni", [10, 15])
	if typeof(every) == TYPE_ARRAY and (every as Array).size() == 2:
		e.every = Vector2i(int(every[0]), maxi(int(every[0]), int(every[1])))
	e.until_year = int(cfg.get_value(section, "fino_a", 0))
	e.who = str(cfg.get_value(section, "chi", ""))
	e.chance = int(cfg.get_value(section, "probabilita", 0))
	e.once = str(cfg.get_value(section, "una_volta", ""))
	e.wait = int(cfg.get_value(section, "attesa", 0))
	for r in cfg.get_value(section, "religioni", []):
		e.religions.append(str(r).to_upper())
	e.year = int(cfg.get_value(section, "anno", 0))
	e.title = str(cfg.get_value(section, "titolo", e.id))
	e.title_en = str(cfg.get_value(section, "titolo_en", ""))
	e.text = str(cfg.get_value(section, "testo", ""))
	e.text_en = str(cfg.get_value(section, "testo_en", ""))
	var opts: Variant = cfg.get_value(section, "opzioni", [])
	if typeof(opts) == TYPE_ARRAY:
		for o in opts:
			if typeof(o) == TYPE_DICTIONARY:
				e.options.append(o)
			else:
				errors.append("evento %s: opzione non valida" % e.id)
	if cfg.has_section_key(section, "esito"):
		var out: Variant = cfg.get_value(section, "esito")
		e.outcome = out if typeof(out) == TYPE_DICTIONARY else {}
		e.has_outcome = true
	if not [KIND_RECURRING, KIND_CONDITIONAL, KIND_HISTORICAL].has(e.kind):
		errors.append("evento %s: tipo sconosciuto %s" % [e.id, e.kind])
	if e.options.is_empty() and not e.has_outcome:
		errors.append("evento %s: ne' opzioni ne' esito" % e.id)
	for o in e.options:
		for res in o.get("esiti", []):
			_check_outcome(e.id, res)
	if e.has_outcome:
		_check_outcome(e.id, e.outcome)
	events[e.id] = e


func _check_outcome(event_id: String, outcome: Variant) -> void:
	if typeof(outcome) != TYPE_DICTIONARY:
		errors.append("evento %s: esito non valido" % event_id)
		return
	for k in outcome:
		if not OUTCOME_KEYS.has(str(k)):
			errors.append("evento %s: esito sconosciuto %s" % [event_id, k])


func site(site_id: String) -> Site:
	return _by_id.get(site_id, null)


func event(event_id: String) -> SiteEvent:
	return events.get(event_id, null)


func in_region(region_id: String) -> Array:
	return _by_region.get(region_id, [])


func is_empty() -> bool:
	return sites.is_empty()


# --- luoghi attivi nella partita -------------------------------------------------------------------------------------


## Vero se il luogo esiste nella partita (la sua regione c'e': il Trono d'Oro solo nella modalita' Auror) e non e' finito.
static func is_active(state: GameState, s: Site) -> bool:
	if s == null or state == null or state.campaign == null or state.campaign.region(s.region) == null:
		return false
	var st: Dictionary = state.sites_state.get(s.id, {})
	return not bool(st.get("fine", false))


## Vero se un luogo fantasma si manifesta nell'anno (sempre vero per gli altri).
static func manifests(s: Site, year: int) -> bool:
	if s.phantom_every <= 0:
		return true
	return posmod(year + phantom_phase(s), s.phantom_every) == 0


static func phantom_phase(s: Site) -> int:
	return posmod(hash(s.id), maxi(1, s.phantom_every))


## Effetti continui del luogo per un proprietario di religione `religion` nell'anno `year`: base (o rovine) + religione.
static func effects_for(s: Site, religion: String, year: int) -> Dictionary:
	var out := (s.effects_after if s.after_year > 0 and year >= s.after_year else s.effects).duplicate(true)
	if not s.effects_religion.is_empty():
		var extra: Dictionary = s.effects_religion.get(religion, s.effects_religion.get(OTHER_RELIGIONS, {}))
		_add_effects(out, extra)
	return out


## Valore di un solo effetto (senza costruire il dizionario: e' il calcolo piu' frequente, chiamato dal reddito e dall'IA).
static func effect_value(s: Site, religion: String, year: int, key: String) -> float:
	var base: Dictionary = s.effects_after if s.after_year > 0 and year >= s.after_year else s.effects
	var v := float(base.get(key, 0))
	if not s.effects_religion.is_empty():
		var extra: Dictionary = s.effects_religion.get(religion, s.effects_religion.get(OTHER_RELIGIONS, {}))
		v += float(extra.get(key, 0))
	return v


static func _add_effects(into: Dictionary, extra: Dictionary) -> void:
	for k in extra:
		var v: Variant = extra[k]
		if typeof(v) == TYPE_DICTIONARY:
			var d: Dictionary = into.get(k, {})
			d = d.duplicate()
			for r in v:
				d[r] = int(d.get(r, 0)) + int(v[r])
			into[k] = d
		elif typeof(v) == TYPE_INT:
			into[k] = int(into.get(k, 0)) + int(v)
		else:
			into[k] = float(into.get(k, 0.0)) + float(v)


## Somma di un effetto continuo dei luoghi di terra della regione per il suo proprietario (0 = nessuno).
static func region_value(state: GameState, region_id: String, key: String) -> float:
	if state == null or state.rules == null or state.rules.sites.is_empty():
		return 0.0
	var list := state.rules.sites.in_region(region_id)
	if list.is_empty():
		return 0.0
	var p := state.province(region_id)
	if p == null or p.owner == GameState.REBEL:
		return 0.0
	var religion := ReligionProcessor.faction_religion(state, p.owner)
	var total := 0.0
	for item in list:
		var s: Site = item
		if s.is_sea() or not is_active(state, s):
			continue
		total += effect_value(s, religion, state.year, key)
	return total


static func region_int(state: GameState, region_id: String, key: String) -> int:
	return roundi(region_value(state, region_id, key))


## Moltiplicatore di un effetto in percentuale della regione (1 = nessun effetto, mai sotto 0).
static func region_factor(state: GameState, region_id: String, key: String) -> float:
	return maxf(0.0, 1.0 + region_value(state, region_id, key) / 100.0)


## Conversione della regione {religione: punti l'anno} per il suo proprietario.
static func region_conversion(state: GameState, region_id: String) -> Dictionary:
	var out := {}
	if state == null or state.rules == null or state.rules.sites.is_empty():
		return out
	var p := state.province(region_id)
	if p == null or p.owner == GameState.REBEL:
		return out
	var religion := ReligionProcessor.faction_religion(state, p.owner)
	for item in state.rules.sites.in_region(region_id):
		var s: Site = item
		if s.is_sea() or not is_active(state, s):
			continue
		var conv: Dictionary = effects_for(s, religion, state.year).get("conversione", {})
		for r in conv:
			out[str(r)] = int(out.get(str(r), 0)) + int(conv[r])
	return out


## Somma di un effetto per tutta la fazione: le chiavi FACTION_KEYS dei luoghi di terra posseduti e gli effetti di presidio
## delle zone di mare presidiate.
static func faction_value(state: GameState, faction_id: String, key: String) -> float:
	if state == null or state.rules == null or state.rules.sites.is_empty():
		return 0.0
	var fid := SimUtil.norm(faction_id)
	var total := 0.0
	var land := FACTION_KEYS.has(key)
	for item in state.rules.sites.with_key(key):
		var s: Site = item
		if s.is_sea():
			if s.garrison.has(key) and garrison_holder(state, s) == fid and is_active(state, s):
				total += float(s.garrison[key])
		elif land:
			var p := state.province(s.region)
			if p != null and p.owner == fid and is_active(state, s):
				total += effect_value(s, ReligionProcessor.faction_religion(state, fid), state.year, key)
	return total


static func faction_factor(state: GameState, faction_id: String, key: String) -> float:
	return maxf(0.0, 1.0 + faction_value(state, faction_id, key) / 100.0)


## Denari l'anno di mantenimento dei luoghi della fazione.
static func upkeep(state: GameState, faction_id: String) -> int:
	if state == null or state.rules == null or state.rules.sites.is_empty():
		return 0
	var fid := SimUtil.norm(faction_id)
	var total := 0
	for item in state.rules.sites.with_key("mantenimento"):
		var s: Site = item
		if s.is_sea():
			continue
		var p := state.province(s.region)
		if p != null and p.owner == fid and is_active(state, s):
			total += roundi(effect_value(s, ReligionProcessor.faction_religion(state, fid), state.year, "mantenimento"))
	return total


## Stelle in piu' degli agenti reclutati nella regione, secondo il tipo (come FactionTraits.agent_bonus).
static func agent_bonus(state: GameState, region_id: String, type_name: String) -> int:
	var t := type_name.strip_edges().to_upper()
	if t == AgentState.EMISSARY or t == AgentState.PRINCESS:
		return region_int(state, region_id, "valore_emissari")
	if t == AgentState.SPY or t == AgentState.ASSASSIN:
		return region_int(state, region_id, "valore_spie")
	if AgentState.RELIGIOUS_TYPES.has(t):
		return region_int(state, region_id, "valore_religiosi")
	return 0


## Fazione che presidia la zona di mare del luogo ("" se nessuna o non ancora per abbastanza anni).
static func garrison_holder(state: GameState, s: Site) -> String:
	if not s.is_sea() or s.garrison_years <= 0:
		return ""
	var st: Dictionary = state.sites_state.get(s.id, {})
	if int(st.get("presidio_anni", 0)) >= s.garrison_years:
		return str(st.get("presidio", ""))
	return ""


## Proprietario attuale di un luogo di terra ("" per il mare o la regione dei ribelli).
static func owner_of(state: GameState, s: Site) -> String:
	if s.is_sea():
		return ""
	var p := state.province(s.region)
	if p == null or p.owner == GameState.REBEL:
		return ""
	return p.owner


## Luoghi che la fazione possiede (terra) o presidia (mare), attivi.
static func held_by(state: GameState, faction_id: String) -> Array[Site]:
	var out: Array[Site] = []
	if state == null or state.rules == null:
		return out
	var fid := SimUtil.norm(faction_id)
	for s in state.rules.sites.sites:
		if not is_active(state, s):
			continue
		if (s.is_sea() and garrison_holder(state, s) == fid) or (not s.is_sea() and owner_of(state, s) == fid):
			out.append(s)
	return out
