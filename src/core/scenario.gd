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
		data = StartposLoader.load_text(world_startpos_text(text) + "\n" + WorldFactions.startpos_text())
	else:
		data = StartposLoader.load_text(startpos_text(text))
	if auror:
		apply_faction_religions(data)
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
	var table := UnitProdLoader.load_file(path, _restored_units() if auror else _units)
	if auror:
		AurorUnits.append_to(table)   # ADR-074: unita' esclusive degli Auror, solo in modalita' Auror
	if atlantis():
		AtlantisScenario.add_danes_to_units(table, UnitProdLoader.load_file(path, _units))   # ADR-078
	if WorldMap.available():
		WorldFactions.add_to_units(table)   # ADR-079: le fazioni nuove arruolano come la loro fazione modello
	return table


## Modalita' Auror: le righe della XL originale per le sole unita' di `ripristina_originali` (la caracca, ADR-076).
static func _restored_units() -> Dictionary:
	var out := {}
	for uid in AurorUnits.restored_originals():
		if _units.has(uid):
			out[uid] = _units[uid]
	return out


static func load_buildings(path: String) -> BuildingProdLoader.BuildingTable:
	_ensure()
	var table := BuildingProdLoader.load_file(path, {} if auror else _buildings)
	if atlantis():
		AtlantisScenario.add_danes_to_buildings(table, BuildingProdLoader.load_file(path, _buildings))   # ADR-078
	if WorldMap.available():
		WorldFactions.add_to_buildings(table)   # ADR-079
	return table


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
