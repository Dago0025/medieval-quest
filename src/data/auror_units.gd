class_name AurorUnits
extends RefCounted
## Unita' esclusive degli Auror (ADR-074, richiesta di Federico del 15/11/2026; la Fregata del Drago, ADR-076, del 16/11):
## unita' d'elite descritte in
## `data/unita_auror.cfg`, aggiunte alla tabella delle unita' solo in modalita' Auror (ADR-068). Ogni unita' nasce dalla
## riga del suo `modello` nel prod dell'installazione (corpo, cavalcatura, arma, classi), con sopra i valori del file:
## costo, mantenimento, uomini, carica/mischia/difesa/armatura, morale, sola fazione degli Auror e sole quattro regioni
## d'origine, tutte le epoche. Sono `elite`: il potere «ogni unita'» degli Auror non toglie loro i limiti di fazione e di
## regione (Rules.lifts_unit_limits), e la loro forza nella risoluzione automatica e' moltiplicata da `moltiplicatore_forza`.
##
## Guardia del re: il capo della fazione (Darkos) ha sempre una pila della `guardia_del_re` nel suo esercito; se non
## comanda nessun esercito ne riceve uno con la sola guardia (`ensure_king_guard`, a inizio partita e a ogni fine anno).

const FILE := "res://data/unita_auror.cfg"
const COMMON := "comune"

static var _cfg: ConfigFile = null


static func reset() -> void:
	_cfg = null


## File esplicito (test); null torna a quello del progetto.
static func use_config(cfg: ConfigFile) -> void:
	_cfg = cfg


static func _ensure() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if _cfg.load(FILE) != OK:
			push_warning("Unita' degli Auror non lette da %s" % FILE)
	return _cfg


## Id delle unita' del file, nell'ordine.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in _ensure().get_sections():
		if s != COMMON:
			out.append(s)
	return out


static func is_auror_unit(unit_id: String) -> bool:
	return _section(unit_id) != ""


static func faction() -> String:
	return str(_ensure().get_value(COMMON, "fazione", "FN_DANISH")).to_upper()


static func regions() -> PackedStringArray:
	return PackedStringArray(_ensure().get_value(COMMON, "regioni", []))


static func guard_unit() -> String:
	return str(_ensure().get_value(COMMON, "guardia_del_re", ""))


## Sezione del file per l'id (senza distinguere maiuscole), "" se non c'e'.
static func _section(unit_id: String) -> String:
	var low := unit_id.strip_edges().to_lower()
	if low == "" or low == COMMON:
		return ""
	for s in _ensure().get_sections():
		if s.to_lower() == low:
			return s
	return ""


static func value(unit_id: String, key: String, fallback: Variant = null) -> Variant:
	var s := _section(unit_id)
	return fallback if s == "" else _ensure().get_value(s, key, fallback)


## Nome plurale, singolare o descrizione nella lingua corrente ("" se l'unita' non e' degli Auror).
static func text(unit_id: String, key: String) -> String:
	var s := _section(unit_id)
	if s == "":
		return ""
	var cfg := _ensure()
	if Lang.is_english() and cfg.has_section_key(s, key + "_en"):
		return str(cfg.get_value(s, key + "_en"))
	return str(cfg.get_value(s, key, ""))


## Aggiunge le unita' alla tabella (dopo quelle dell'installazione). Un modello che manca e' un errore della tabella.
static func append_to(table: UnitProdLoader.UnitTable) -> void:
	var cfg := _ensure()
	var index := table.units.size()
	for s in ids():
		if table.has_unit(s):
			continue
		var model := table.get_unit(str(cfg.get_value(s, "modello", "")))
		if model == null:
			table.errors.append("Unita' degli Auror %s: modello %s non trovato" % [s, cfg.get_value(s, "modello", "")])
			continue
		var u := UnitProdLoader.build_row(row_for(s, model.raw), index, table)
		if u == null:
			continue
		u.elite = true
		u.strength_multiplier = float(cfg.get_value(s, "moltiplicatore_forza", 1.0))
		u.unique = bool(cfg.get_value(s, "unica", false))            # Ankalagon (23/11/2026)
		u.invulnerable = bool(cfg.get_value(s, "invulnerabile", false))
		u.piece = str(cfg.get_value(s, "pedina", ""))
		table.add(u)
		index += 1


## Riga del prod per la sezione `s`, dalla riga del modello.
static func row_for(s: String, model_row: PackedStringArray) -> PackedStringArray:
	var cfg := _ensure()
	var fid := faction()
	var cells := {
		UnitProdLoader.COL_NAME: s,
		UnitProdLoader.COL_COST: str(int(cfg.get_value(s, "costo", 0))),
		UnitProdLoader.COL_SUPPORT: str(int(cfg.get_value(s, "mantenimento", 0))),
		UnitProdLoader.COL_TIME: "1",
		10: "",                                   # niente unita' ribelli
		UnitProdLoader.COL_RULER: "",
		UnitProdLoader.COL_REGION_ADV: "",
		UnitProdLoader.COL_AI_CHOICES: "",
		UnitProdLoader.COL_REQUIRES: "",          # le quattro province d'origine hanno gia' tutto al massimo
		UnitProdLoader.COL_PERIODS: UnitType.ALL_PERIODS,
		UnitProdLoader.COL_STATS: _stats(UnitProdLoader.cell(model_row, UnitProdLoader.COL_STATS), s),
		UnitProdLoader.COL_LEADER_OF: fid if s == guard_unit() else "",
		UnitProdLoader.COL_FACTIONS: fid,
		UnitProdLoader.COL_REGIONS: ", ".join(PackedStringArray(cfg.get_value(s, "regioni", regions()))),
		UnitProdLoader.COL_CULTURES: "",
		43: "",                                   # non temono nessuno
		UnitProdLoader.COL_MERCENARY: "",
		51: fid,
	}
	if s == guard_unit():
		cells[UnitProdLoader.COL_GENERAL] = "PREFERRED"
	# requisiti del modello (cappellani, 18/11/2026: servono gli edifici religiosi come per i vescovi)
	if bool(cfg.get_value(s, "requisiti_modello", false)):
		cells.erase(UnitProdLoader.COL_REQUIRES)
		cells.erase(UnitProdLoader.COL_TIME)
	# uomini e morale solo se dati: le navi tengono quelli del modello
	if cfg.has_section_key(s, "uomini"):
		cells[UnitProdLoader.COL_MEN] = str(int(cfg.get_value(s, "uomini")))
	if cfg.has_section_key(s, "morale"):
		cells[UnitProdLoader.COL_MORAL] = str(int(cfg.get_value(s, "morale")))
	if cfg.has_section_key(s, "nave"):
		cells[UnitProdLoader.COL_SHIP] = str(cfg.get_value(s, "nave"))   # ADR-076: raggio, attacco e difesa della nave d'elite
	return ScenarioFilter.patch_row(model_row, cells)


## Colonna 21 del modello con carica, mischia, difesa e armatura della sezione.
static func _stats(text: String, s: String) -> String:
	var cfg := _ensure()
	var out := text
	for pair in [["CHARGE_BONUS", "carica"], ["MELEE_BONUS", "mischia"], ["DEFENCE_BONUS", "difesa"], ["ARMOUR_LEVEL", "armatura"]]:
		if not cfg.has_section_key(s, pair[1]):
			continue
		var rx := RegEx.create_from_string("%s\\(\\s*-?[0-9.]+\\s*\\)" % pair[0])
		var repl := "%s( %d )" % [pair[0], int(cfg.get_value(s, pair[1]))]
		if rx.search(out) != null:
			out = rx.sub(out, repl)
		else:
			out += ", " + repl
	return out


## Unita' dell'installazione da riportare alla XL originale in modalita' Auror (`ripristina_originali`, in maiuscolo).
static func restored_originals() -> PackedStringArray:
	var out := PackedStringArray()
	for uid in _ensure().get_value(COMMON, "ripristina_originali", []):
		out.append(str(uid).strip_edges().to_upper())
	return out


## Startpos in modalita' Auror: le unita' di partenza dei tipi di `sostituisce_nello_startpos` (una o piu') nelle regioni
## degli Auror diventano l'unita' esclusiva: le 48 caracche delle flotte -> Fregate del Drago (ADR-076) e, su richiesta di
## Federico del 16/11/2026, anche le navi lunghe delle flotte degli Auror. Le navi delle altre fazioni (le navi lunghe di
## Danesi, Norvegesi e Svedesi) restano. Restituisce quante unita' ha cambiato.
static func replace_start_units(data: CampaignData) -> int:
	var swaps := {}
	for s in ids():
		var old: Variant = _ensure().get_value(s, "sostituisce_nello_startpos", [])
		var olds: Array = old if old is Array else [old]
		for o in olds:
			var key := str(o).strip_edges().to_lower()
			if key != "":
				swaps[key] = s
	var count := 0
	if swaps.is_empty():
		return count
	var owner := faction()
	for su in data.start_units:
		var key := su.unit_type.strip_edges().to_lower()
		if not swaps.has(key):
			continue
		var r := data.region(su.region)
		if r == null or r.owner != owner:
			continue
		su.unit_type = swaps[key]
		count += 1
	return count


## Le unita' esclusive prima di tutte le altre (finestra di arruolamento degli Auror), ciascun gruppo nell'ordine dato.
static func elite_first(units: Array[UnitType]) -> Array[UnitType]:
	var out: Array[UnitType] = []
	for u in units:
		if u.elite:
			out.append(u)
	for u in units:
		if not u.elite:
			out.append(u)
	return out


# --- armata iniziale del re -------------------------------------------------------------------------------------------


## Partita nuova (GameSetup.new_game): il re della fazione comanda un'armata completa di sole unita' esclusive
## (`armata_iniziale_re`, al massimo `max_pile`) nella sua regione; l'esercito che comandava nello startpos resta dov'e'
## e riceve un generale (`DynastyProcessor.ensure_commanders` con un generatore proprio: quello dello stato non si tocca).
## ADR-126: `armate_iniziali_altre` armate di `armata_iniziale_altre` (senza la guardia del re, che resta solo sua; se
## l'elenco manca, quello del re), ciascuna con un generale, nelle altre province della fazione nell'ordine dello startpos
## (una per provincia, poi si ricomincia; nella regione del re se non ne ha altre).
## Nessun effetto senza le unita' (scenario storico), senza re o con l'elenco vuoto.
static func setup_king_army(state: GameState) -> void:
	var list := PackedStringArray(_ensure().get_value(COMMON, "armata_iniziale_re", []))
	if list.is_empty() or state.units == null:
		return
	var fid := faction()
	var king := state.leader_of(fid)
	if king == null or not king.alive:
		return
	var region := state.character_region(king)
	if region == "" or state.campaign.region(region) == null or state.campaign.region(region).is_sea:
		var owned := state.provinces_of(fid)
		if owned.is_empty():
			return
		region = owned[0].id
	var stacks: Array[UnitStack] = []
	for uid in list:
		var u := state.units.get_unit(uid)
		if u == null:
			return   # scenario senza le unita' degli Auror
		if stacks.size() < state.rules.max_stacks:
			stacks.append(state.new_stack(fid, u.id, u.men))
	var old: Army = state.army(king.army) if king.army > 0 else null
	var army := state.create_army(fid, region, false)
	army.in_castle = old != null and old.in_castle and old.region == region
	army.stacks = stacks
	king.army = army.id
	king.region = region
	var extra := int(_ensure().get_value(COMMON, "armate_iniziali_altre", 0))
	var others := PackedStringArray()
	for p in state.provinces_of(fid):
		if p.id != region:
			others.append(p.id)
	if others.is_empty():
		others.append(region)
	var other_list := PackedStringArray(_ensure().get_value(COMMON, "armata_iniziale_altre", list))
	for i in extra:
		var more := state.create_army(fid, others[i % others.size()], false)
		for uid in other_list:
			var u := state.units.get_unit(uid)
			if u != null and more.stacks.size() < state.rules.max_stacks:
				more.stacks.append(state.new_stack(fid, u.id, u.men))
	if old != null or extra > 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = state.seed_value + 7919 + 74
		DynastyProcessor.ensure_commanders(state, rng, state.year)


# --- guardia del re ---------------------------------------------------------------------------------------------------


## Il capo vivo e libero della fazione degli Auror ha sempre una pila della guardia nel suo esercito: se l'esercito non ce
## l'ha la si aggiunge (se e' pieno, la pila meno costosa passa a un esercito nuovo nella stessa regione, nessuna truppa si
## perde); se il re non comanda nessun esercito, ne riceve uno con la sola guardia nella regione dove si trova. Le flotte
## non contano. Nessun effetto se l'unita' non c'e' (scenario storico) o la fazione non ha un capo.
static func ensure_king_guard(state: GameState) -> void:
	var guard := guard_unit()
	if guard == "" or state.units == null or state.units.get_unit(guard) == null:
		return
	var fid := faction()
	var f := state.faction(fid)
	if f == null or not f.alive:
		return
	var king := state.leader_of(fid)
	if king == null or not king.alive or PrisonerProcessor.is_captive(king):
		return
	var unit := state.units.get_unit(guard)
	var army: Army = state.army(king.army) if king.army > 0 else null
	if army != null and (army.is_fleet or army.faction != fid):
		army = null
	if army == null:
		var region := state.character_region(king)
		if region == "" or state.campaign.region(region) == null or state.campaign.region(region).is_sea:
			var owned := state.provinces_of(fid)
			if owned.is_empty():
				return
			region = owned[0].id
		army = state.create_army(fid, region, false)
		king.army = army.id
		king.region = region
	if unit.unique:
		_pull_unique(state, army, unit)   # Ankalagon: la stessa pila torna da Darkos, non se ne crea un'altra
	_ensure_stack(state, army, unit)


## Vero se la pila e' la guardia unica del re (Ankalagon, 23/11/2026): non si separa dall'esercito del re.
static func is_bound_to_king(state: GameState, army: Army, stack: UnitStack) -> bool:
	if state == null or army == null or stack == null or state.units == null:
		return false
	var u := state.units.get_unit(stack.unit_id)
	if u == null or not u.unique or u.id.to_lower() != guard_unit().to_lower():
		return false
	var c := state.commander_of(army.id)
	return c != null and c.role == Character.ROLE_LEADER and c.faction == faction()


## Porta nell'esercito del re la pila dell'unita' unica che si trova in un altro esercito della fazione (un esercito che
## resta vuoto sparisce e il suo comandante resta senza esercito).
static func _pull_unique(state: GameState, army: Army, unit: UnitType) -> void:
	for st in army.stacks:
		if st.unit_id.to_lower() == unit.id.to_lower():
			return
	for other: Army in state.armies.duplicate():
		if other == army or other.faction != army.faction:
			continue
		for i in other.stacks.size():
			if other.stacks[i].unit_id.to_lower() != unit.id.to_lower():
				continue
			var st: UnitStack = other.stacks[i]
			other.stacks.remove_at(i)
			if other.stacks.is_empty():
				var c := state.commander_of(other.id)
				if c != null:
					c.army = 0
				state.remove_army(other)
			_make_room(state, army)
			army.stacks.insert(0, st)
			return


## Aggiunge una pila di `unit` all'esercito se non ce l'ha; se e' pieno, la pila meno costosa (mai un'unita' unica) passa
## a un esercito nuovo nella stessa regione.
static func _ensure_stack(state: GameState, army: Army, unit: UnitType) -> void:
	for st in army.stacks:
		if st.unit_id.to_lower() == unit.id.to_lower():
			return
	_make_room(state, army)
	if unit.unique:
		army.stacks.insert(0, state.new_stack(army.faction, unit.id, unit.men))
	else:
		army.stacks.append(state.new_stack(army.faction, unit.id, unit.men))


## Se l'esercito e' pieno, la pila meno costosa (mai un'unita' unica) passa a un esercito nuovo nella stessa regione.
static func _make_room(state: GameState, army: Army) -> void:
	var fid := army.faction
	if army.is_full(state.rules.max_stacks):
		var cheapest := -1
		var cheapest_cost := 0
		for i in army.stacks.size():
			var u := state.units.get_unit(army.stacks[i].unit_id)
			if u != null and u.unique:
				continue
			var cost := u.cost if u != null else 0
			if cheapest < 0 or cost < cheapest_cost:
				cheapest = i
				cheapest_cost = cost
		var moved := army.stacks[cheapest]
		army.stacks.remove_at(cheapest)
		var other := state.create_army(fid, army.region, false)
		other.in_castle = army.in_castle
		other.stacks.append(moved)
