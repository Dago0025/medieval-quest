class_name Rules
extends RefCounted
## Parametri delle regole della simulazione (ADR-004), letti da data/regole/economia.cfg.
##
## I valori predefiniti qui sotto sono uguali a quelli del file, cosi' i test girano
## anche senza file (un test controlla che restino uguali). Il codice della
## simulazione legge solo da questa classe.
##
## Famiglie di edifici scelte guardando il file edifici reale (MTW_XL_EARLY_BUILD_PROD13.TXT:
## colonna 3 "tipo", colonna 22 "rendita", colonna 18 "risorse richieste"):
## - Coltivazioni (terreno): IMPROVED_FARMLAND, tipo FARM_INCOME, 4 livelli con rendita
##   120/140/160/180 (= Terreno I-IV del catalogo, r.35). E' l'unica famiglia FARM_INCOME.
##   Il livello 0 (nessuna coltivazione) vale 1,0.
## - Commercio: MERCHANT, tipo TRADING_POST, 4 livelli (Trading Post, Merchant, Merchants
##   Guild, Master Merchant), nessuna rendita nel file: il reddito si calcola dalle merci
##   della provincia (PROVVISORIA, catalogo r.38-r.41). Serve anche l'edificio PORT (tipo PORT).
## - Miniere: COPPER_MINE, SILVER_MINE, GOLD_MINE, SALT_MINE, tipo LEV1_INCOME, 2 livelli
##   con rendita 100/200, 150/300, 200/400, 50/100, risorsa richiesta nella regione.
## - Non contati (non sono nella specifica della fase 2): HOSPITAL, CATHEDRAL, GRAND_MOSQUE,
##   PAGAN_MONUMENT (tipo CATHEDRAL_INCOME, rendita 75/100/100/100).

const DEFAULT_PATH := "res://data/regole/economia.cfg"

## Anno in cui la partita finisce.
var final_year := 1700

## Scala annua dei valori dei file (valore settimanale x 100 -> x 0,52).
var annual_scale := 0.52
var farm_family := "IMPROVED_FARMLAND"
## Indice = livello delle coltivazioni (0-4).
var farm_multipliers := PackedFloat64Array([1.0, 1.2, 1.4, 1.6, 1.8])

var default_tax := 2
## Indice = livello di tassa (0-4).
var tax_multipliers := PackedFloat64Array([0.75, 0.9, 1.0, 1.1, 1.25])

var mine_families := PackedStringArray(["COPPER_MINE", "SILVER_MINE", "GOLD_MINE", "SALT_MINE"])
## PROVVISORIA (catalogo r.42): scala della rendita delle miniere.
var mine_scale := 1.0

var trade_families := PackedStringArray(["MERCHANT"])
## PROVVISORIA (catalogo r.39): indice = livello dell'edificio commerciale - 1.
var trade_multipliers := PackedFloat64Array([1.0, 1.2, 1.4, 1.6])
## PROVVISORIA (catalogo r.38 e r.41): fattore sulla somma dei valori delle merci.
var trade_factor := 1.0
var port_family := "PORT"
## Commercio marittimo (manuale p22, catalogo r.38; richiesta di Federico del 2026-11-13): rotte verso i porti stranieri
## raggiunti da catene di flotte proprie. PROVVISORIE le quote (la wiki dice «per ogni provincia straniera con porto»).
var sea_trade := true
## Quota del valore delle merci (non possedute dal partner) incassata per ogni porto straniero raggiunto.
var sea_trade_share := 1.0
## Imposta d'importazione: quota del valore delle merci del partner (non possedute qui) incassata dal porto (SetImportPercentage
## della campagna: 20%, «probabilmente non corretta» secondo la wiki).
var import_share := 0.2
## Peso di ogni porto raggiunto secondo la sua ricchezza (richiesta di Federico del 2026-11-13): valore economico del partner
## (agricoltura + miniere + commercio locale, `Economy.partner_value`) / `sea_trade_reference`, al massimo `sea_trade_max_weight`.
## Riferimento 0 = ogni porto vale 1 come prima.
var sea_trade_reference := 500.0
var sea_trade_max_weight := 2.0
## Il commercio locale (merci vendute nella provincia) non richiede il porto: le province dell'entroterra lo fanno comunque
## (manuale p22, wiki MTW Trade). Falso = come prima della correzione del 2026-11-13.
var local_trade_without_port := true

## PROVVISORIA (catalogo r.43): moltiplicatore del mantenimento dei file.
var upkeep_multiplier := 1.0

var max_stacks := 20   ## unita' per esercito o flotta (16 nell'originale, 20 dal 22/11/2026)
## ADR-146 (StackMerge, manuale p29): unendo eserciti o spostando pile, le pile uguali si riempiono con gli uomini delle piu'
## deboli; dopo le battaglie si accorpano le pile uguali che hanno perso uomini (economia.cfg [eserciti]).
var merge_same_units := true
var merge_after_battle := true

## Demolizione (manuale p37 «Distruggere strutture»: «ti verra' restituita una parte del prezzo di costruzione»; nella campagna
## vichinga «solo la meta' del suo valore»). PROVVISORIA: quota del costo del livello demolito restituita.
var demolish_refund := 0.5

## Danni della conquista (PROVVISORIA: nell'originale alcuni edifici vanno persi quando la provincia cambia mano; fonte
## forum totalwar.org t-28232, nessuna formula nota). Per ogni famiglia costruita, probabilita' di perdere un livello:
## `conquest_building_chance` meno `conquest_castle_protection` per livello del castello, mai sotto `conquest_min_chance`,
## per il moltiplicatore del modo di conquista. Gli edifici religiosi di un'altra religione vanno sempre persi; con un assedio
## il castello perde un livello con probabilita' `conquest_castle_drop`.
var conquest_building_chance := 0.35
var conquest_castle_protection := 0.02
var conquest_min_chance := 0.05
var conquest_means := {"campo": 1.0, "assedio": 1.0, "porte": 0.4, "corruzione": 0.0}
var conquest_castle_drop := 0.5
var conquest_other_religion := true

var max_building_queue := 4
var max_unit_queue := 5

## Fazione -> passaggi della coda di reclutamento in un anno (da `reclutamenti_per_anno` di auror.cfg; assente = 1).
var recruit_rounds := {"FN_DANISH": 5}
## I passaggi in piu' valgono solo per la fazione del giocatore (`reclutamenti_solo_giocatore`).
var recruit_rounds_player_only := true
## Fazioni che arruolano OGNI truppa e nave senza limiti di fazione, epoca, regione e cultura (`tutte_le_unita` di
## auror.cfg; richiesta di Federico dell'11/11: gli Auror e solo loro). Restano edifici richiesti, porto per le navi, costo.
var all_units_factions := PackedStringArray(["FN_DANISH"])
## Fazioni i cui agenti (emissari, spie, assassini, religiosi, inquisitori, principesse) hanno sempre il valore massimo degli
## agenti, `valore_max` di agenti.cfg (`agenti_al_massimo` di auror.cfg; richiesta di Federico del 13/11: gli Auror).
var max_agents_factions := PackedStringArray(["FN_DANISH"])
## Fazioni con gli ammiragli sempre al massimo delle stelle (`ammiragli_al_massimo` di auror.cfg, ADR-056: gli Auror).
var max_admiral_factions := PackedStringArray(["FN_DANISH"])
## Fazioni i cui generali nati da truppe di altre fazioni prendono nome e ritratto della fazione dell'unita'
## (`generali_dalle_unita` di auror.cfg; richiesta di Federico del 22/11/2026: gli Auror).
var generals_from_units_factions := PackedStringArray(["FN_DANISH"])
## Fazioni le cui flotte non subiscono le tempeste (`flotte_immuni_tempeste` di auror.cfg; richiesta di Federico del
## 23/11/2026: gli Auror).
var storm_immune_factions := PackedStringArray(["FN_DANISH"])

## Regole degli scontri della fase 3 (data/regole/scontri.cfg), tutte PROVVISORIE.
var combat := CombatRules.new()

## Regole dei personaggi e delle dinastie della fase 4a (data/regole/personaggi.cfg e auror.cfg).
var dynasty := DynastyRules.new()
## Vizi e virtu' del primo gruppo (data/regole/vizi_virtu.cfg).
var vnv := VnvRules.new()
## Regole delle province della fase 4b (data/regole/province.cfg): lealta', rivolte, riemersione, guerra civile.
var province := ProvinceRules.new()
## Diplomazia della fase 5a (data/regole/diplomazia.cfg): trattati e accettazione delle proposte, PROVVISORIE.
var diplomacy := DiplomacyRules.new()
## Agenti della fase 5a (data/regole/agenti.cfg): valore, missioni, cattura, spie.
var agents := AgentRules.new()
## Religione della fase 5b (data/regole/religione.cfg): composizione, conversioni, zelo, eresia, inquisitori.
var religion := ReligionRules.new()
## Papato, scomuniche, crociate e jihad della fase 5c (data/regole/papato.cfg), PROVVISORIE dove il catalogo non ha la formula.
var papacy := PapacyRules.new()
## Eventi della fase 6a (data/regole/eventi.cfg e data/eventi/eventi_storici.cfg): eventi storici, disastri, Peste Nera,
## Orda d'Oro. `Rules.new()` ha la tabella degli eventi storici vuota e il mondo senza dati dei disastri resta inerte.
var events := EventRules.new()

## Vittoria della fase 6b (data/regole/vittoria.cfg): soglia di dominio.
var victory := VictoryRules.new()

## Riaddestramento delle unita' (data/regole/riaddestramento.cfg): costo, limite per provincia, diluizione del valore.
var retrain := RetrainRules.new()
var mercenaries := MercenaryRules.new()   ## fase 8d: data/regole/mercenari.cfg
## Tratti storici delle fazioni (data/regole/tratti_fazioni.cfg, ADR-089): bonus e malus per fazione. Vuoti con `Rules.new()`.
var traits := FactionTraits.new()
## Luoghi leggendari (data/luoghi/luoghi.cfg, 26/11/2026): vuoti con `Rules.new()`.
var sites := LegendarySites.new()
## Limiti storici (data/regole/storia.cfg, ADR-114): invenzioni, cavalli nelle Americhe, guardia del capo.
var history := HistoryRules.new()

## Errori di lettura del file (chiave con tipo sbagliato e simili).
var errors := PackedStringArray()


## Regole dal file `path`; le chiavi mancanti restano ai valori predefiniti.
## Se il file non c'e' o non si legge: valori predefiniti e un errore in `errors`.
static func load_file(path: String = DEFAULT_PATH) -> Rules:
	var rules := Rules.new()
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		rules.errors.append("Regole non lette da %s (errore %d): uso i valori predefiniti" % [path, err])
		return rules
	rules.final_year = _int(cfg, "calendario", "anno_finale", rules.final_year)
	rules.annual_scale = _float(cfg, "agricoltura", "scala_annua", rules.annual_scale)
	rules.farm_family = _text(cfg, "agricoltura", "famiglia_terreno", rules.farm_family)
	rules.farm_multipliers = _floats(cfg, "agricoltura", "moltiplicatori_terreno", rules.farm_multipliers)
	rules.default_tax = _int(cfg, "tassa", "predefinita", rules.default_tax)
	rules.tax_multipliers = _floats(cfg, "tassa", "moltiplicatori", rules.tax_multipliers)
	rules.mine_families = _texts(cfg, "miniere", "famiglie", rules.mine_families)
	rules.mine_scale = _float(cfg, "miniere", "scala", rules.mine_scale)
	rules.trade_families = _texts(cfg, "commercio", "famiglie", rules.trade_families)
	rules.trade_multipliers = _floats(cfg, "commercio", "moltiplicatori", rules.trade_multipliers)
	rules.trade_factor = _float(cfg, "commercio", "fattore", rules.trade_factor)
	rules.port_family = _text(cfg, "commercio", "famiglia_porto", rules.port_family)
	if cfg.has_section_key("commercio", "marittimo"):
		rules.sea_trade = bool(cfg.get_value("commercio", "marittimo", rules.sea_trade))
	rules.sea_trade_share = _float(cfg, "commercio", "quota_marittima", rules.sea_trade_share)
	rules.import_share = _float(cfg, "commercio", "quota_importazione", rules.import_share)
	rules.sea_trade_reference = _float(cfg, "commercio", "valore_riferimento_partner", rules.sea_trade_reference)
	rules.sea_trade_max_weight = _float(cfg, "commercio", "peso_massimo_partner", rules.sea_trade_max_weight)
	if cfg.has_section_key("commercio", "locale_senza_porto"):
		rules.local_trade_without_port = bool(cfg.get_value("commercio", "locale_senza_porto", rules.local_trade_without_port))
	rules.upkeep_multiplier = _float(cfg, "mantenimento", "moltiplicatore", rules.upkeep_multiplier)
	rules.max_stacks = _int(cfg, "eserciti", "max_pile", rules.max_stacks)
	if cfg.has_section_key("eserciti", "riempi_unita_uguali"):
		rules.merge_same_units = bool(cfg.get_value("eserciti", "riempi_unita_uguali"))
	if cfg.has_section_key("eserciti", "accorpa_dopo_battaglia"):
		rules.merge_after_battle = bool(cfg.get_value("eserciti", "accorpa_dopo_battaglia"))
	rules.demolish_refund = _float(cfg, "demolizione", "rimborso", rules.demolish_refund)
	rules.conquest_building_chance = _float(cfg, "conquista", "probabilita_edificio", rules.conquest_building_chance)
	rules.conquest_castle_protection = _float(cfg, "conquista", "protezione_per_livello_castello", rules.conquest_castle_protection)
	rules.conquest_min_chance = _float(cfg, "conquista", "probabilita_minima", rules.conquest_min_chance)
	rules.conquest_castle_drop = _float(cfg, "conquista", "castello_perde_un_livello", rules.conquest_castle_drop)
	for means in rules.conquest_means.keys():
		rules.conquest_means[means] = _float(cfg, "conquista", "modo_" + str(means), float(rules.conquest_means[means]))
	if cfg.has_section_key("conquista", "religione_diversa_distrutta"):
		rules.conquest_other_religion = bool(cfg.get_value("conquista", "religione_diversa_distrutta", rules.conquest_other_religion))
	rules.max_building_queue = _int(cfg, "code", "costruzione", rules.max_building_queue)
	rules.max_unit_queue = _int(cfg, "code", "reclutamento", rules.max_unit_queue)
	rules._check_consistency()
	rules._read_recruit_rounds(path.get_base_dir().path_join("auror.cfg"))
	# Gli scontri stanno in scontri.cfg, accanto al file delle regole (assente = valori predefiniti).
	var combat_path := path.get_base_dir().path_join("scontri.cfg")
	if FileAccess.file_exists(combat_path):
		rules.combat = CombatRules.load_file(combat_path, path.get_base_dir().path_join("auror.cfg"))
		rules.errors.append_array(rules.combat.errors)
	# I personaggi stanno in personaggi.cfg e vizi_virtu.cfg, accanto al file delle regole (assenti = valori predefiniti).
	var dynasty_path := path.get_base_dir().path_join("personaggi.cfg")
	if FileAccess.file_exists(dynasty_path):
		rules.dynasty = DynastyRules.load_file(dynasty_path, path.get_base_dir().path_join("auror.cfg"))
		rules.errors.append_array(rules.dynasty.errors)
	var vnv_path := path.get_base_dir().path_join("vizi_virtu.cfg")
	if FileAccess.file_exists(vnv_path):
		rules.vnv = VnvRules.load_file(vnv_path)
		rules.errors.append_array(rules.vnv.errors)
	# Le province stanno in province.cfg, accanto al file delle regole (assente = valori predefiniti).
	var province_path := path.get_base_dir().path_join("province.cfg")
	if FileAccess.file_exists(province_path):
		rules.province = ProvinceRules.load_file(province_path)
		rules.errors.append_array(rules.province.errors)
	# Diplomazia e agenti (fase 5a) stanno in diplomazia.cfg e agenti.cfg (assenti = valori predefiniti).
	var diplomacy_path := path.get_base_dir().path_join("diplomazia.cfg")
	if FileAccess.file_exists(diplomacy_path):
		rules.diplomacy = DiplomacyRules.load_file(diplomacy_path)
		rules.errors.append_array(rules.diplomacy.errors)
	var agents_path := path.get_base_dir().path_join("agenti.cfg")
	if FileAccess.file_exists(agents_path):
		rules.agents = AgentRules.load_file(agents_path)
		rules.errors.append_array(rules.agents.errors)
	# La religione (fase 5b) sta in religione.cfg (assente = valori predefiniti).
	var religion_path := path.get_base_dir().path_join("religione.cfg")
	if FileAccess.file_exists(religion_path):
		rules.religion = ReligionRules.load_file(religion_path)
		rules.errors.append_array(rules.religion.errors)
	# Il Papato (fase 5c) sta in papato.cfg (assente = valori predefiniti).
	var papacy_path := path.get_base_dir().path_join("papato.cfg")
	if FileAccess.file_exists(papacy_path):
		rules.papacy = PapacyRules.load_file(papacy_path)
		rules.errors.append_array(rules.papacy.errors)
	# Gli eventi (fase 6a) stanno in eventi.cfg e, in ../eventi/eventi_storici.cfg, la tabella degli eventi storici
	# (assenti = valori predefiniti e nessun evento storico).
	var events_path := path.get_base_dir().path_join("eventi.cfg")
	if FileAccess.file_exists(events_path):
		var history_path := path.get_base_dir().get_base_dir().path_join("eventi/eventi_storici.cfg")
		rules.events = EventRules.load_file(events_path, history_path)
		rules.errors.append_array(rules.events.errors)
	# La vittoria (fase 6b) sta in vittoria.cfg (assente = valori predefiniti).
	var victory_path := path.get_base_dir().path_join("vittoria.cfg")
	if FileAccess.file_exists(victory_path):
		rules.victory = VictoryRules.load_file(victory_path)
		rules.errors.append_array(rules.victory.errors)
	# Il riaddestramento sta in riaddestramento.cfg (assente = valori predefiniti).
	var retrain_path := path.get_base_dir().path_join("riaddestramento.cfg")
	if FileAccess.file_exists(retrain_path):
		rules.retrain = RetrainRules.load_file(retrain_path)
		rules.errors.append_array(rules.retrain.errors)
	# I mercenari stanno in mercenari.cfg (assente = valori predefiniti).
	var merc_path := path.get_base_dir().path_join("mercenari.cfg")
	if FileAccess.file_exists(merc_path):
		rules.mercenaries = MercenaryRules.load_file(merc_path)
		rules.errors.append_array(rules.mercenaries.errors)
	# I tratti delle fazioni stanno in tratti_fazioni.cfg (assente = nessun tratto, ADR-089).
	var traits_path := path.get_base_dir().path_join("tratti_fazioni.cfg")
	if FileAccess.file_exists(traits_path):
		rules.traits = FactionTraits.load_file(traits_path)
		rules.errors.append_array(rules.traits.errors)
	# I luoghi leggendari stanno in data/luoghi/luoghi.cfg (assente = nessun luogo, 26/11/2026).
	if FileAccess.file_exists(LegendarySites.DEFAULT_PATH):
		rules.sites = LegendarySites.load_file(LegendarySites.DEFAULT_PATH)
		rules.errors.append_array(rules.sites.errors)
	# I limiti storici stanno in storia.cfg (assente = valori predefiniti, ADR-114).
	var history_path := path.get_base_dir().path_join("storia.cfg")
	if FileAccess.file_exists(history_path):
		rules.history = HistoryRules.load_file(history_path, path.get_base_dir().path_join("auror.cfg"))
		rules.errors.append_array(rules.history.errors)
	return rules


## Passaggi della coda di reclutamento in un anno per la fazione (almeno 1).
func recruit_rounds_of(faction_id: String, is_player: bool) -> int:
	if recruit_rounds_player_only and not is_player:
		return 1
	return maxi(1, int(recruit_rounds.get(faction_id.strip_edges().to_upper(), 1)))


## Vero se per la fazione cadono i limiti di fazione, epoca, regione e cultura di questa unita' (truppe e navi soltanto:
## agenti, crociate e jihad seguono le loro regole).
func lifts_unit_limits(faction_id: String, unit: UnitType) -> bool:
	# ADR-074: le unita' esclusive (elite) restano legate alla fazione e alle regioni d'origine anche per gli Auror
	return unit != null and unit.is_military() and not unit.elite and all_units_factions.has(faction_id.strip_edges().to_upper())


## Valore minimo degli agenti della fazione: `valore_max` degli agenti per le fazioni di `agenti_al_massimo`, altrimenti 0.
func agent_valour_floor(faction_id: String) -> int:
	return agents.max_valour if max_agents_factions.has(faction_id.strip_edges().to_upper()) else 0


## Scenario storico (ADR-068): nessuna fazione ha i poteri di auror.cfg (passaggi di reclutamento, ogni unita', agenti e
## ammiragli al massimo, flotte immuni alle tempeste, comando, valore, armi e armature, fedelta', influenza, re immortale, nome reale unico).
func remove_faction_powers() -> void:
	recruit_rounds = {}
	all_units_factions = PackedStringArray()
	history.invention_free = PackedStringArray()   # ADR-114: nello storico anche i Danesi aspettano la polvere da sparo
	max_agents_factions = PackedStringArray()
	max_admiral_factions = PackedStringArray()
	generals_from_units_factions = PackedStringArray()
	storm_immune_factions = PackedStringArray()
	combat.fixed_command = {}
	combat.start_valour = {}
	combat.start_upgrades = {}
	dynasty.fixed = {}


## Legge `reclutamenti_per_anno` e `reclutamenti_solo_giocatore` delle sezioni FN_* di auror.cfg (ADR-004).
func _read_recruit_rounds(auror_path: String) -> void:
	if not FileAccess.file_exists(auror_path):
		return
	var cfg := ConfigFile.new()
	if cfg.load(auror_path) != OK:
		errors.append("Regole del reclutamento non lette da %s" % auror_path)
		return
	var found := {}
	var everything := PackedStringArray()
	var top_agents := PackedStringArray()
	var top_admirals := PackedStringArray()
	var from_units := PackedStringArray()
	var storm_immune := PackedStringArray()
	for section in cfg.get_sections():
		if not section.begins_with("FN_"):
			continue
		var v: Variant = cfg.get_value(section, "reclutamenti_per_anno", null)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			found[section.to_upper()] = clampi(int(v), 1, 20)
		var po: Variant = cfg.get_value(section, "reclutamenti_solo_giocatore", null)
		if typeof(po) == TYPE_BOOL:
			recruit_rounds_player_only = po
		if cfg.get_value(section, "tutte_le_unita", false) == true:
			everything.append(section.to_upper())
		if cfg.get_value(section, "agenti_al_massimo", false) == true:
			top_agents.append(section.to_upper())
		if cfg.get_value(section, "ammiragli_al_massimo", false) == true:
			top_admirals.append(section.to_upper())
		if cfg.get_value(section, "generali_dalle_unita", false) == true:
			from_units.append(section.to_upper())
		if cfg.get_value(section, "flotte_immuni_tempeste", false) == true:
			storm_immune.append(section.to_upper())
	recruit_rounds = found
	all_units_factions = everything
	max_agents_factions = top_agents
	max_admiral_factions = top_admirals
	generals_from_units_factions = from_units
	storm_immune_factions = storm_immune


## Livello di tassa valido (0 .. numero di moltiplicatori - 1).
func is_valid_tax(level: int) -> bool:
	return level >= 0 and level < tax_multipliers.size()


func tax_multiplier(level: int) -> float:
	return tax_multipliers[clampi(level, 0, tax_multipliers.size() - 1)]


## Moltiplicatore del terreno per il livello delle coltivazioni (0 = nessuna).
func farm_multiplier(level: int) -> float:
	return farm_multipliers[clampi(level, 0, farm_multipliers.size() - 1)]


## Moltiplicatore dell'edificio commerciale per livello (>= 1); 0 se non c'e' (livello 0).
func trade_multiplier(level: int) -> float:
	if level <= 0:
		return 0.0
	return trade_multipliers[clampi(level - 1, 0, trade_multipliers.size() - 1)]


## Tutti i parametri in un Dictionary (per confronti nei test e per i rapporti).
func to_dict() -> Dictionary:
	return {
		"final_year": final_year,
		"annual_scale": annual_scale,
		"farm_family": farm_family,
		"farm_multipliers": Array(farm_multipliers),
		"default_tax": default_tax,
		"tax_multipliers": Array(tax_multipliers),
		"mine_families": Array(mine_families),
		"mine_scale": mine_scale,
		"trade_families": Array(trade_families),
		"trade_multipliers": Array(trade_multipliers),
		"trade_factor": trade_factor,
		"port_family": port_family,
		"sea_trade": sea_trade,
		"sea_trade_share": sea_trade_share,
		"import_share": import_share,
		"sea_trade_reference": sea_trade_reference,
		"sea_trade_max_weight": sea_trade_max_weight,
		"local_trade_without_port": local_trade_without_port,
		"upkeep_multiplier": upkeep_multiplier,
		"max_stacks": max_stacks,
		"merge_same_units": merge_same_units,
		"merge_after_battle": merge_after_battle,
		"max_building_queue": max_building_queue,
		"max_unit_queue": max_unit_queue,
		"recruit_rounds": recruit_rounds.duplicate(),
		"recruit_rounds_player_only": recruit_rounds_player_only,
		"all_units_factions": Array(all_units_factions),
		"max_agents_factions": Array(max_agents_factions),
		"max_admiral_factions": Array(max_admiral_factions),
		"storm_immune_factions": Array(storm_immune_factions),
		"combat": combat.to_dict(),
		"dynasty": dynasty.to_dict(),
		"vnv": vnv.to_dict(),
		"province": province.to_dict(),
		"diplomacy": diplomacy.to_dict(),
		"agents": agents.to_dict(),
		"religion": religion.to_dict(),
		"papacy": papacy.to_dict(),
		"events": events.to_dict(),
		"victory": victory.to_dict(),
		"retrain": retrain.to_dict(),
		"mercenaries": mercenaries.to_dict(),
	}


func _check_consistency() -> void:
	if tax_multipliers.is_empty():
		errors.append("tassa/moltiplicatori vuoto: uso i predefiniti")
		tax_multipliers = Rules.new().tax_multipliers
	if farm_multipliers.is_empty():
		errors.append("agricoltura/moltiplicatori_terreno vuoto: uso i predefiniti")
		farm_multipliers = Rules.new().farm_multipliers
	if trade_multipliers.is_empty():
		errors.append("commercio/moltiplicatori vuoto: uso i predefiniti")
		trade_multipliers = Rules.new().trade_multipliers
	if default_tax < 0 or default_tax >= tax_multipliers.size():
		errors.append("tassa/predefinita fuori scala: uso 2")
		default_tax = mini(2, tax_multipliers.size() - 1)


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


static func _floats(cfg: ConfigFile, section: String, key: String, fallback: PackedFloat64Array) -> PackedFloat64Array:
	var v: Variant = cfg.get_value(section, key, null)
	if typeof(v) != TYPE_ARRAY:
		return fallback
	var out := PackedFloat64Array()
	var items: Array = v
	for item in items:
		out.append(float(item))
	return out


static func _texts(cfg: ConfigFile, section: String, key: String, fallback: PackedStringArray) -> PackedStringArray:
	var v: Variant = cfg.get_value(section, key, null)
	if typeof(v) != TYPE_ARRAY:
		return fallback
	var out := PackedStringArray()
	var items: Array = v
	for item in items:
		out.append(String(item).strip_edges().to_upper())
	return out
