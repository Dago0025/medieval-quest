class_name Scenario
extends RefCounted
## Scenario della partita (ADR-068, richiesta di Federico del 15/11): di norma la campagna e' quella **storica**, con Danesi,
## Norvegesi e Svedesi come nell'originale; con un triplo clic sul logo del menu iniziale si attiva la **modalita' Auror**
## (una sorta di god mode), in cui gli Auror con tutti i loro potenziamenti prendono il posto dei Danesi (FN_DANISH) e
## tengono Danimarca, Svezia, Norvegia e Scania.
##
## I file dell'installazione contengono la mod Auror: la modalita' Auror li legge come sono, lo scenario storico li passa da
## ScenarioFilter con le correzioni di data/scenari/storico/ e toglie i poteri di auror.cfg (`Rules.remove_faction_powers`).
## La scelta vale per la sessione (non si salva nelle impostazioni); ogni salvataggio ricorda il suo scenario. Il valore
## predefinito resta la modalita' Auror (test, mappa avviata da sola): e' il menu iniziale, alla prima apertura della sessione,
## a portare il gioco allo scenario storico (`begin_session`).

const AUROR := "auror"
const STORICO := "storico"
const DIR := "res://data/scenari/storico/"
const STARTPOS_ADDITIONS := DIR + "startpos_aggiunte.txt"
const UNITS_FILE := DIR + "unita.json"
const BUILDINGS_FILE := DIR + "edifici.json"
const HEROES_FILE := DIR + "eroi.json"

## Vero in modalita' Auror (dopo il triplo clic sul logo, o caricando un salvataggio Auror).
static var auror := true
static var _session := false
static var _units := {}
static var _buildings := {}
static var _hero_rows: Array = []
static var _loaded := false


## Prima apertura del menu nella sessione: si parte dallo scenario storico (le volte dopo resta lo scenario in corso).
static func begin_session() -> void:
	if _session:
		return
	_session = true
	set_auror(false)


## "auror" o "storico".
static func id() -> String:
	return AUROR if auror else STORICO


## Cambia scenario e svuota le tabelle che ne dipendono (nomi, colori e stemmi delle fazioni, pedine, scudi).
static func set_auror(on: bool) -> void:
	if on == auror:
		return
	auror = on
	FactionStyle.reset()
	RegionNames.reset()
	AssetLibrary.forget_faction_shields()
	PieceArt.reset()


## Scenario di un salvataggio: i salvataggi senza la voce sono di prima di ADR-068, tutti con gli Auror.
static func set_from_id(scenario_id: String) -> void:
	set_auror(scenario_id != STORICO)


## Startpos dell'installazione (o `path`) per lo scenario corrente. In modalita' Auror il capo degli Auror parte dalla
## loro regione natia (`home_region`) invece che dalla regione di PlaceLeader dell'installazione.
static func load_startpos(path: String = "") -> CampaignData:
	var text := TextIO.read_latin1(path if path != "" else GameFiles.startpos())
	var data: CampaignData
	if path == "" and WorldMap.available():
		# ADR-077/078; in fondo le fazioni nuove del mondo (ADR-079)
		# Dharma dei popoli asiatici (22/11/2026): religione delle fazioni asiatiche e cultura delle loro terre
		data = StartposLoader.load_text(Dharma.startpos_text(world_startpos_text(text) + "\n" + WorldFactions.startpos_text()))
		CultureUnits.replace_start_units(data)   # ADR-116: guarnigioni del mondo delle fazioni nuove con le loro unita'
	else:
		data = StartposLoader.load_text(startpos_text(text))
	if auror:
		apply_faction_religions(data)
		apply_office_names(data)   # ADR-115: titoli di corte propri degli Auror
		apply_home_regions(data)
		AurorUnits.replace_start_units(data)   # ADR-076: flotte degli Auror di Fregate del Drago
	return data


## Regione natia della fazione (`regione_natia` nella sua sezione di data/regole/auror.cfg; richiesta di Federico del
## 16/11/2026: per gli Auror la Norvegia, non piu' la Danimarca): li' parte il re, li' ricompare se giustiziato, li' sorge
## la fortezza bianca degli Auror. "" nello scenario storico o se la fazione non ne ha una.
static func home_region(faction_id: String) -> String:
	if not auror:
		return ""
	return str(_auror_rules().get_value(faction_id.strip_edges().to_upper(), "regione_natia", "")).strip_edges().to_upper()


## Il capo di ogni fazione con una regione natia parte da li' (PlaceLeader), se la regione e' sua nello startpos. La regione
## natia riceve anche gli edifici della vecchia capitale che non ha (per gli Auror cancelleria, palazzo del connestabile e del
## maresciallo, ammiragliato e cattedrale, che la mod costruiva solo in Danimarca: segnalazione di Federico del 16/11).
static func apply_home_regions(data: CampaignData) -> void:
	for f in data.factions:
		var home := home_region(f.id)
		var r := data.region(home) if home != "" else null
		if r == null or r.is_sea or r.owner != f.id:
			continue
		var old := data.region(f.leader_region) if f.leader_region != "" else null
		if old != null and old != r:
			var families := {}
			for token in r.buildings:
				families[_building_family(token)] = true
			for token in old.buildings:
				if not families.has(_building_family(token)):
					r.buildings.append(token)
					families[_building_family(token)] = true
		f.leader_region = home


## Religione propria delle fazioni di auror.cfg (`religione`, token come SetReligion; richiesta di Federico del 16/11/2026:
## gli Auror seguono il Culto Imperiale, REL_IMPERIAL). Solo in modalita' Auror; le fazioni senza la chiave restano come sono.
static func apply_faction_religions(data: CampaignData) -> void:
	var cfg := _auror_rules()
	for f in data.factions:
		var token := str(cfg.get_value(f.id, "religione", "")).strip_edges().to_upper()
		if token != "":
			f.religion = token


## Titoli di corte propri delle fazioni di auror.cfg (`cariche`: edificio -> nome nella forma dei dati, ADR-115, richiesta di
## Federico del 21/11/2026: gli Auror avevano ancora le cariche dei Danesi). Cambia solo il nome dell'AddOffice; edificio e
## bonus restano. Solo in modalita' Auror; i salvataggi prendono i nomi nuovi al caricamento (si leggono dallo startpos).
static func apply_office_names(data: CampaignData) -> void:
	var cfg := _auror_rules()
	for section in cfg.get_sections():
		var names: Variant = cfg.get_value(section, "cariche", {})
		if typeof(names) != TYPE_DICTIONARY:
			continue
		for o in data.offices_of(section.strip_edges().to_upper()):
			var name := str((names as Dictionary).get(o.building, "")).strip_edges()
			if name != "":
				o.display_name = name


## Famiglia di un edificio di MakeBuilding ("Shipyard4" -> "shipyard", "Royal_palace" -> "royal_palace").
static func _building_family(token: String) -> String:
	var t := token.strip_edges().to_lower()
	while t != "" and t.right(1).is_valid_int():
		t = t.left(t.length() - 1)
	return t


static var _auror_cfg: ConfigFile = null
const AUROR_RULES := "res://data/regole/auror.cfg"


static func _auror_rules() -> ConfigFile:
	if _auror_cfg == null:
		_auror_cfg = ConfigFile.new()
		if _auror_cfg.load(AUROR_RULES) != OK:
			push_warning("Regole degli Auror non lette da %s" % AUROR_RULES)
	return _auror_cfg


## Mappa del mondo (ADR-077) con l'isola di Atlantide in modalita' Auror (ADR-078): sulla mappa del mondo la modalita' Auror
## parte dallo storico (Danesi come FN_DANES, Norvegesi, Svedesi) e porta gli Auror dell'installazione sull'isola.
static func atlantis() -> bool:
	return auror and WorldMap.available()


static func world_startpos_text(installation_text: String) -> String:
	if not auror:
		return WorldMap.startpos_text(startpos_text(installation_text), false)
	var historical := ScenarioFilter.startpos(installation_text, _historical_additions())
	return WorldMap.startpos_text(AtlantisScenario.historical_with_danes(historical), true,
		AtlantisScenario.auror_lines(installation_text))


static func _historical_additions() -> String:
	return TextIO.read_latin1(STARTPOS_ADDITIONS) if FileAccess.file_exists(STARTPOS_ADDITIONS) else ""


static func startpos_text(text: String) -> String:
	if auror:
		return text
	return ScenarioFilter.startpos(text, TextIO.read_latin1(STARTPOS_ADDITIONS) if FileAccess.file_exists(STARTPOS_ADDITIONS) else "")


static func load_units(path: String) -> UnitProdLoader.UnitTable:
	_ensure()
	var table := UnitProdLoader.load_file(path, _auror_units() if auror else _units)
	if auror:
		_add_historical_requirements(table)   # ADR-114
		AurorUnits.append_to(table)   # ADR-074: unita' esclusive degli Auror, solo in modalita' Auror
	if atlantis():
		AtlantisScenario.add_danes_to_units(table, UnitProdLoader.load_file(path, _units))   # ADR-078
	if WorldMap.available():
		CultureUnits.append_to(table)       # ADR-116: unita' proprie delle fazioni nuove
		WorldFactions.add_to_units(table)   # ADR-079: agenti (e navi, se mancano) della fazione modello
		Dharma.append_units(table)          # il monaco del Dharma al posto dello sciamano
	if auror:
		_add_equivalent_requirements(table)  # tempio del Dharma e santuario pagano -> chiesa del Culto Imperiale
	return table


## Edifici equivalenti per i requisiti delle unita' in modalita' Auror (`requisiti_equivalenti` di auror.cfg, edificio ->
## edificio, maiuscolo). Vuoto se la chiave manca.
static func auror_requirement_equivalents() -> Dictionary:
	var out := {}
	var cfg := _auror_rules()
	for section in cfg.get_sections():
		var eq: Variant = cfg.get_value(section, "requisiti_equivalenti", {})
		if typeof(eq) != TYPE_DICTIONARY:
			continue
		for k in eq:
			out[str(k).strip_edges().to_upper()] = str(eq[k]).strip_edges().to_upper()
	return out


## Modalita' Auror (richiesta di Federico del 23/11/2026: nelle regioni degli Auror si arruola tutto tranne i contadini):
## ogni gruppo di requisiti che chiede un edificio di un'altra religione (tempio del Dharma, santuario pagano) riceve
## un'alternativa (OR) con l'edificio equivalente del Culto Imperiale. Le altre fazioni restano legate alle liste di
## fazioni delle unita', quindi l'alternativa serve solo a chi arruola senza limiti (`tutte_le_unita`).
static func _add_equivalent_requirements(table: UnitProdLoader.UnitTable) -> void:
	var eq := auror_requirement_equivalents()
	if eq.is_empty():
		return
	for u in table.units:
		var extra: Array[PackedStringArray] = []
		for group in u.requires:
			var swapped := PackedStringArray()
			var changed := false
			for token in group:
				var key := str(token).strip_edges().to_upper()
				if eq.has(key):
					swapped.append(str(eq[key]))
					changed = true
				else:
					swapped.append(token)
			if changed and not u.requires.has(swapped) and not extra.has(swapped):
				extra.append(swapped)
		for g in extra:
			u.requires.append(g)


## Modalita' Auror (ADR-114, richiesta di Federico del 21/11/2026: progressione storica delle unita', armi da fuoco solo
## dopo la polvere da sparo, tranne che per gli Auror): le correzioni dello storico valgono per tutte le unita' (epoche,
## fazioni, regioni, culture), cosi' le altre fazioni tornano alla XL originale; gli Auror non le sentono perche' arruolano
## senza quei limiti (`tutte_le_unita`). Gli edifici richiesti (col. 16) restano quelli della mod, con quelli originali
## aggiunti come alternativa (`_add_historical_requirements`), cosi' agli Auror non manca nulla. Le unita' di
## `ripristina_originali` (la caracca, ADR-076) tornano per intero alla XL.
static func _auror_units() -> Dictionary:
	var out := {}
	var restored := AurorUnits.restored_originals()
	for uid in _units:
		var cells: Dictionary = (_units[uid] as Dictionary).duplicate()
		if not restored.has(uid):
			cells.erase(UnitProdLoader.COL_REQUIRES)
		out[uid] = cells
	return out


## Modalita' Auror: gli edifici richiesti della XL originale si aggiungono come alternativa (OR) a quelli della mod
## (la moschea dei Ghazi accanto alla chiesa messa dalla mod).
static func _add_historical_requirements(table: UnitProdLoader.UnitTable) -> void:
	var restored := AurorUnits.restored_originals()
	var col := UnitProdLoader.COL_REQUIRES
	for uid in _units:
		var cells: Dictionary = _units[uid]
		if restored.has(uid) or not cells.has(col):
			continue
		var u := table.get_unit(str(uid))
		if u == null:
			continue
		for group in UnitProdLoader.parse_condition(str(cells[col])):
			if not u.requires.has(group):
				u.requires.append(group)


static func load_buildings(path: String) -> BuildingProdLoader.BuildingTable:
	_ensure()
	var table := BuildingProdLoader.load_file(path, _auror_buildings() if auror else _buildings)
	if atlantis():
		AtlantisScenario.add_danes_to_buildings(table, BuildingProdLoader.load_file(path, _buildings))   # ADR-078
	if WorldMap.available():
		WorldFactions.add_to_buildings(table)   # ADR-079
		Dharma.append_buildings(table)          # tempio, monastero e grande pagoda del Dharma
	return table


## Modalita' Auror (ADR-114): degli edifici dello storico tornano solo le invenzioni (col. 26: polvere da sparo per armaiolo
## d'armi da fuoco e fonderia, bussola per il cantiere navale); le fazioni ammesse restano quelle della mod.
static func _auror_buildings() -> Dictionary:
	var out := {}
	for family in _buildings:
		var cells: Dictionary = _buildings[family]
		if cells.has(BuildingProdLoader.COL_INVENTIONS):
			out[family] = {BuildingProdLoader.COL_INVENTIONS: cells[BuildingProdLoader.COL_INVENTIONS]}
	return out


static func load_heroes(path: String) -> HeroesData:
	_ensure()
	var text := TextIO.read_latin1(path)
	var source := text if auror else ScenarioFilter.heroes(text, _hero_rows)
	if atlantis():
		source = AtlantisScenario.heroes_text(text, ScenarioFilter.heroes(text, _hero_rows))   # ADR-078: nomi dei Danesi
	var data := HeroesLoader.load_text(source)
	CharacterNames.apply(data, auror)   # ADR-079: nomi propri degli Auror (solo in modalita' Auror) e delle fazioni nuove
	if text.is_empty():
		data.errors.append("File vuoto o non trovato: %s" % path)
	return data


## Regole della partita per lo scenario: nello storico nessuna fazione ha i poteri di auror.cfg.
static func apply_rules(rules: Rules) -> void:
	if not auror and rules != null:
		rules.remove_faction_powers()
	if auror and rules != null:
		rules.traits.drop("FN_DANISH")   # ADR-089: gli Auror hanno i poteri di auror.cfg, non i tratti dei Danesi


## Correzioni dei prod e degli eroi (per i test).
static func unit_overrides() -> Dictionary:
	_ensure()
	return _units


static func building_overrides() -> Dictionary:
	_ensure()
	return _buildings


static func hero_rows() -> Array:
	_ensure()
	return _hero_rows


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_units = ScenarioFilter.read_overrides(UNITS_FILE, "unita")
	_buildings = ScenarioFilter.read_overrides(BUILDINGS_FILE, "edifici")
	_hero_rows = ScenarioFilter.read_hero_rows(HEROES_FILE)
