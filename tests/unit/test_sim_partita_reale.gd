extends RefCounted
## Partita nuova sui dati reali dell'installazione (EARLY_XL.TXT + prod unita' ed edifici),
## saltata se l'installazione manca. Contiene la parte Auror, ancora in evoluzione:
## non si fissano numeri che ne dipendono, si controllano coerenza, determinismo e assenza
## di errori. Scrive anche il rapporto del primo anno (user://esito_economia.txt e, se la
## cartella del progetto e' scrivibile, res://tests/esito_economia.txt).

const REPORT_USER := "user://esito_economia.txt"
const REPORT_PROJECT := "res://tests/esito_economia.txt"
const SEED := 20261108

var _campaign: CampaignData
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable


## Carica i dati statici; falso (e test saltato) se l'installazione non c'e'.
func _load_static(t: TestContext) -> bool:
	if _campaign != null:
		return true
	if not GameFiles.is_available() or not FileAccess.file_exists(GameFiles.startpos()):
		t.skip("installazione di MTW non trovata in %s" % GameFiles.game_dir())
		return false
	var campaign := StartposLoader.load_file(GameFiles.startpos())
	var unit_path := GameFiles.prod_file(campaign.unit_prod_file)
	var building_path := GameFiles.prod_file(campaign.building_prod_file)
	if not FileAccess.file_exists(unit_path) or not FileAccess.file_exists(building_path):
		t.skip("file prod non trovati in %s" % GameFiles.game_dir())
		return false
	_units = UnitProdLoader.load_file(unit_path)
	_buildings = BuildingProdLoader.load_file(building_path)
	_campaign = campaign
	return true


func _new_game(seed_value: int = SEED) -> GameState:
	return GameSetup.new_game(_campaign, _units, _buildings, Rules.load_file(), seed_value)


# --- le famiglie scelte per le regole esistono nel file reale --------------------


func test_famiglie_delle_regole_nel_file_edifici(t: TestContext) -> void:
	if not _load_static(t):
		return
	var rules := Rules.load_file()
	t.assert_eq(rules.errors, PackedStringArray(), "economia.cfg")
	var farm := _buildings.get_family(rules.farm_family)
	t.assert_true(farm != null, "coltivazioni: %s" % rules.farm_family)
	if farm != null:
		t.assert_true(farm.has_type("FARM_INCOME"), "tipo FARM_INCOME")
		t.assert_eq(farm.level_count(), rules.farm_multipliers.size() - 1, "4 livelli + il livello 0")
		for lv in farm.levels:
			t.assert_eq(float(lv.income) / 100.0, rules.farm_multipliers[lv.level], "rendita del livello %d = moltiplicatore del terreno" % lv.level)
	for mine_id in rules.mine_families:
		var mine := _buildings.get_family(mine_id)
		t.assert_true(mine != null, "miniera %s" % mine_id)
		if mine != null:
			t.assert_true(mine.has_type("LEV1_INCOME"), "%s: tipo LEV1_INCOME" % mine_id)
			t.assert_true(mine.get_level(1).income > 0, "%s: ha una rendita" % mine_id)
	for trade_id in rules.trade_families:
		var trade := _buildings.get_family(trade_id)
		t.assert_true(trade != null, "commercio %s" % trade_id)
		if trade != null:
			t.assert_true(trade.has_type("TRADING_POST"), "%s: tipo TRADING_POST" % trade_id)
			t.assert_eq(trade.level_count(), rules.trade_multipliers.size(), "un moltiplicatore per livello")
	var port := _buildings.get_family(rules.port_family)
	t.assert_true(port != null and port.has_type("PORT"), "edificio porto")
	# nessun'altra famiglia con rendita da coltivazione o miniera e' stata dimenticata
	for family in _buildings.families:
		if family.has_type("FARM_INCOME"):
			t.assert_eq(family.id, rules.farm_family, "unica famiglia FARM_INCOME")
		if family.has_type("LEV1_INCOME"):
			t.assert_true(rules.mine_families.has(family.id), "miniera non prevista dalle regole: %s" % family.id)
		if family.has_type("TRADING_POST"):
			t.assert_true(rules.trade_families.has(family.id), "famiglia commerciale non prevista: %s" % family.id)


# --- partita nuova ---------------------------------------------------------------


func test_partita_nuova_sui_dati_reali(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	t.assert_eq(s.setup_errors, PackedStringArray(), "anomalie dei dati all'avvio")
	t.assert_eq(s.year, _campaign.start_year)
	t.assert_eq(s.era, "EARLY")
	t.assert_eq(s.factions.size(), _campaign.factions.size())
	t.assert_eq(s.provinces.size(), _campaign.land_regions().size())
	var alive := 0
	for f in s.factions:
		if f.alive:
			alive += 1
	t.assert_eq(alive, _campaign.active_factions().size(), "fazioni vive = attive")
	# ogni unita' iniziale e' finita in un esercito, in una flotta o tra gli agenti
	var military := 0
	var others := 0
	for su in _campaign.start_units:
		var ut := _units.get_unit(su.unit_type)
		if ut != null and ut.is_military():
			military += 1
		else:
			others += 1
	var stacks := 0
	for a in s.armies:
		stacks += a.stack_count()
		t.assert_true(a.stack_count() >= 1 and a.stack_count() <= s.rules.max_stacks, "esercito %d: %d pile" % [a.id, a.stack_count()])
		var r := _campaign.region(a.region)
		t.assert_true(r != null and r.is_sea == a.is_fleet, "esercito %d nel posto giusto (%s)" % [a.id, a.region])
	# ADR-089: piu' le truppe e le navi in piu' dei tratti storici delle fazioni attive
	var extra := 0
	for f in _campaign.active_factions():
		extra += s.rules.traits.int_value(f.id, "truppe_iniziali") + s.rules.traits.int_value(f.id, "navi_iniziali")
	# ADR-114: piu' la guardia a cavallo dei capi che non ne avevano una
	for e in s.events:
		if str(e["tipo"]) == GameState.EV_ROYAL_GUARD:
			extra += 1
	t.assert_eq(stacks, military + extra, "tutte le unita' militari hanno una pila")
	t.assert_eq(s.agents.size(), others, "emissari, principesse e simili sono agenti")
	# la provincia ha i livelli degli edifici della startpos
	for p in s.provinces:
		var region := _campaign.region(p.id)
		t.assert_eq(p.owner, region.owner)
		for token in region.buildings:
			var lv := _buildings.resolve(token)
			t.assert_true(lv != null and p.level_of(lv.family) >= lv.level, "%s: %s" % [p.id, token])


# --- 50 anni senza ordini -----------------------------------------------------------


func test_cinquanta_fine_anno_senza_errori(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	var stacks_before := s.count_stacks("")
	var armies_before := s.armies.size()
	var changed := false    # dalla fase 4b le rivolte fanno nascere eserciti ribelli anche senza ordini
	for i in 50:
		var res := TurnProcessor.end_year(s)
		var errs: Array = res["errori"]
		t.assert_true(bool(res["ok"]), "anno %d" % s.year)
		t.assert_eq(errs.size(), 0, "anno %d: errori %s" % [s.year, str(errs)])
		if errs.size() > 0 or not bool(res["ok"]):
			return
		# Dalla fase 4a nascite, morti e successioni avvengono anche senza ordini: si controlla solo
		# che non ci siano eventi militari o economici, impossibili senza ordini.
		var forbidden := 0
		for kind in [GameState.EV_BUILT, GameState.EV_RECRUITED, GameState.EV_MOVED, GameState.EV_WAR_DECLARED]:
			forbidden += _count_events(s, kind)
		# dalla fase 4b i ribelli nati dalle rivolte combattono e assediano da soli: battaglie, assedi e conquiste
		# sono ammessi solo se vi compare la fazione dei ribelli (nessuna azione delle fazioni senza ordini)
		for e in s.events:
			var ek := str(e["tipo"])
			if ek == GameState.EV_BATTLE and not _involves_rebels(e, ["attaccante", "difensore"]):
				forbidden += 1
			elif ek == GameState.EV_PROVINCE_CAPTURED and not _involves_rebels(e, ["fazione", "precedente"]):
				forbidden += 1
			elif ek == GameState.EV_SIEGE_STARTED and not _involves_rebels(e, ["fazione", "assediata"]):
				forbidden += 1
		t.assert_eq(forbidden, 0, "senza ordini non ci sono costruzioni, reclutamenti, movimenti o battaglie")
		for kind in [GameState.EV_REBELLION, GameState.EV_REBELLION_SPREAD, GameState.EV_FACTION_REEMERGED, GameState.EV_CIVIL_WAR, GameState.EV_STARVED, GameState.EV_FACTION_EXTINCT, GameState.EV_PAPACY_REEMERGED, GameState.EV_PLAGUE, GameState.EV_STORM, GameState.EV_HORDE_ARRIVES, GameState.EV_HORDE_GONE]:
			if _count_events(s, kind) > 0:
				changed = true
	t.assert_eq(s.year, _campaign.start_year + 50)
	t.assert_eq(s.era, "EARLY")
	if not changed:
		t.assert_eq(s.armies.size(), armies_before, "nessun esercito nasce o muore senza ordini")
		t.assert_eq(s.count_stacks(""), stacks_before)
	t.assert_false(s.is_finished())


func test_il_tesoro_cambia_come_dice_il_rapporto(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	var before := {}
	for f in s.factions:
		before[f.id] = f.treasury
	TurnProcessor.end_year(s)
	var total_province := 0
	var total_faction := 0
	for f in s.factions:
		if not f.alive:
			t.assert_eq(f.treasury, int(before[f.id]), "%s non viva: tesoro invariato" % f.id)
			continue
		var li := f.last_income
		var net := int(li["agricoltura"]) + int(li["miniere"]) + int(li["commercio"]) - int(li["mantenimento"])
		t.assert_eq(int(li["netto"]), net, "%s: netto" % f.id)
		t.assert_eq(f.treasury, int(before[f.id]) + net, "%s: tesoro" % f.id)
		t.assert_true(int(li["mantenimento"]) >= 0 and int(li["agricoltura"]) >= 0 and int(li["miniere"]) >= 0 and int(li["commercio"]) >= 0, "%s: voci non negative" % f.id)
		total_faction += int(li["agricoltura"]) + int(li["miniere"]) + int(li["commercio"])
	for p in s.provinces:
		var owner_state := s.faction(p.owner)
		if owner_state != null and owner_state.alive:
			total_province += int(p.last_income["totale"])
	t.assert_eq(total_faction, total_province, "somma delle province = somma delle fazioni")


func test_determinismo_a_parita_di_seme(t: TestContext) -> void:
	if not _load_static(t):
		return
	var a := _new_game(77)
	var b := _new_game(77)
	for i in 10:
		TurnProcessor.end_year(a)
		TurnProcessor.end_year(b)
	for f in a.factions:
		t.assert_eq(b.faction(f.id).treasury, f.treasury, "tesoro di %s dopo 10 anni" % f.id)
	t.assert_eq(SaveGame.to_json(a), SaveGame.to_json(b), "stato intero identico")


func test_salvataggio_dei_dati_reali(t: TestContext) -> void:
	if not _load_static(t):
		return
	var original := _new_game(5)
	for i in 3:
		TurnProcessor.end_year(original)
	var restored := SaveGame.from_dict(SaveGame.to_dict(original), _campaign, _units, _buildings, Rules.load_file())
	t.assert_true(bool(restored["ok"]), str(restored["errore"]))
	if not bool(restored["ok"]):
		return
	var loaded: GameState = restored["stato"]
	TurnProcessor.end_year(original)
	TurnProcessor.end_year(loaded)
	t.assert_eq(SaveGame.to_json(loaded), SaveGame.to_json(original), "anno successivo dopo il ricarico")


# --- ordini sui dati reali -------------------------------------------------------------


func test_ordini_possibili_sui_dati_reali(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	var building_ok := 0
	var unit_ok := 0
	var move_ok := 0
	for f in s.factions:
		if not f.alive:
			continue
		f.treasury = 1000000
		for p in s.provinces_of(f.id):
			if bool(GameCommands.can_queue_building(s, f.id, p.id, "IMPROVED_FARMLAND")["ok"]):
				building_ok += 1
			for u in _units.military():
				if bool(GameCommands.can_queue_unit(s, f.id, p.id, u.id)["ok"]):
					unit_ok += 1
					break
	for a in s.armies:
		var f := s.faction(a.faction)
		if f == null or not f.alive or a.is_fleet:
			continue
		var region := _campaign.region(a.region)
		for n in region.neighbours:
			var neighbour := _campaign.region(n)
			if neighbour != null and not neighbour.is_sea:
				if bool(GameCommands.order_move(s, a.faction, a.id, PackedStringArray([n]))["ok"]):
					move_ok += 1
				break
	t.assert_true(building_ok > 0, "almeno una provincia puo' ampliare le coltivazioni")
	t.assert_true(unit_ok > 0, "almeno una provincia puo' reclutare qualcosa")
	t.assert_true(move_ok > 0, "almeno un esercito puo' muoversi in una provincia confinante")


# --- cento anni di guerre (fase 3) -----------------------------------------------------------------


## Ordini casuali di un giro di attacchi: ogni fazione viva manda un esercito libero verso una
## provincia confinante non sua, gli assedianti assaltano con probabilita' 0,5 e ogni tanto si recluta.
## Il generatore e' a parte (non state.rng), cosi' gli ordini sono gli stessi a parita' di seme.
func _attack_round(s: GameState, rng: RandomNumberGenerator, recruit: bool) -> int:
	var orders := 0
	for f in s.factions:
		if not f.alive or f.id == GameState.REBEL:
			continue
		var movable: Array[Army] = []
		for a in s.armies_of(f.id):
			if not a.is_fleet and not a.in_castle and a.path.is_empty() and s.siege_in(a.region) == null:
				movable.append(a)
		if not movable.is_empty():
			var army := movable[rng.randi_range(0, movable.size() - 1)]
			var region := _campaign.region(army.region)
			var targets: Array[String] = []
			for n in region.neighbours:
				var neighbour := _campaign.region(n)
				if neighbour == null or neighbour.is_sea:
					continue
				var province := s.province(neighbour.id)
				if province != null and province.owner != f.id:
					targets.append(neighbour.id)
			if not targets.is_empty():
				var target := targets[rng.randi_range(0, targets.size() - 1)]
				if bool(GameCommands.order_move(s, f.id, army.id, PackedStringArray([target]))["ok"]):
					orders += 1
		for a in s.armies_of(f.id):
			if rng.randf() < 0.5 and bool(GameCommands.can_order_assault(s, f.id, a.id)["ok"]):
				GameCommands.order_assault(s, f.id, a.id)
		if recruit:
			var mine := s.provinces_of(f.id)
			if not mine.is_empty():
				f.treasury = maxi(f.treasury, 100000)
				var province := mine[rng.randi_range(0, mine.size() - 1)]
				var military := _units.military()
				for _try in 12:
					var unit := military[rng.randi_range(0, military.size() - 1)]
					if not unit.is_ship() and bool(GameCommands.queue_unit(s, f.id, province.id, unit.id)["ok"]):
						break
	return orders


## Primo problema di coerenza dello stato a fine anno ("" se tutto regolare).
func _coherence_problem(s: GameState) -> String:
	for p in s.provinces:
		var owner_state := s.faction(p.owner)
		if owner_state == null:
			return "%s: proprietario sconosciuto %s" % [p.id, p.owner]
		if not owner_state.alive and owner_state.id != GameState.REBEL:
			return "%s: proprietario non vivo %s" % [p.id, p.owner]
	for a in s.armies:
		if a.stacks.is_empty():
			return "esercito %d senza pile" % a.id
		for st in a.stacks:
			if st.men < 1:
				return "esercito %d: pila con %d uomini" % [a.id, st.men]
		var region := _campaign.region(a.region)
		if region == null or region.is_sea != a.is_fleet:
			return "esercito %d in %s" % [a.id, a.region]
		var f := s.faction(a.faction)
		if f == null or (not f.alive and f.id != GameState.REBEL):
			return "esercito %d di una fazione non viva (%s)" % [a.id, a.faction]
		if a.in_castle:
			var in_province := s.province(a.region)
			if a.is_fleet or in_province == null or in_province.owner != a.faction:
				return "esercito %d nel castello di %s ma non e' del proprietario" % [a.id, a.region]
	for siege in s.sieges_in_order():
		var besieged := s.province(siege.region)
		if besieged == null or not s.at_war(siege.faction, besieged.owner):
			return "assedio di %s senza guerra" % siege.region
		var inside := 0
		var outside := 0
		for a in s.armies_in(siege.region):
			if a.in_castle:
				inside += 1
			elif a.faction == siege.faction:
				outside += 1
		if inside == 0 or outside == 0:
			return "assedio di %s senza guarnigione (%d) o assedianti (%d)" % [siege.region, inside, outside]
	for f in s.factions:
		if f.alive and f.id != GameState.REBEL and s.provinces_of(f.id).is_empty() and s.armies_of(f.id).is_empty():
			return "%s e' viva senza province ne' eserciti" % f.id
	return ""


func _men_total(s: GameState) -> int:
	var total := 0
	for a in s.armies:
		total += a.men_total()
	return total


## Uomini persi e reclutati in un anno secondo il registro; il bilancio deve quadrare.
func _men_balance(s: GameState) -> int:
	var balance := 0
	for e in s.events:
		var kind := str(e["tipo"])
		if kind == GameState.EV_BATTLE:
			balance -= int(e["perdite_attaccante"]) + int(e["perdite_difensore"])
		elif kind == GameState.EV_CAPTURED_UNITS or kind == GameState.EV_STARVED:
			balance -= int(e["uomini"])
		elif kind == GameState.EV_FACTION_EXTINCT:
			# dalla fase 4a: gli eserciti di una fazione estinta sono sciolti
			balance -= int(e.get("uomini", 0))
		elif kind == GameState.EV_RECRUITED:
			balance += _units.get_unit(str(e["unita"])).men
		elif kind == GameState.EV_REBELLION or kind == GameState.EV_REBELLION_SPREAD or kind == GameState.EV_FACTION_REEMERGED:
			# dalla fase 4b: i ribelli e le fazioni riemerse dichiarano gli uomini creati; la guerra civile
			# solo passa eserciti ai ribelli, senza creare ne' togliere uomini
			balance += int(e.get("uomini", 0))
		elif kind == GameState.EV_PAPACY_REEMERGED or kind == GameState.EV_CRUSADE_LAUNCHED or kind == GameState.EV_CRUSADE_RECRUITED or kind == GameState.EV_CRUSADE_SUCCEEDED:
			# dalla fase 5c: Papato riemerso, eserciti crociati, reclutamento per zelo e ordini militari creano uomini
			balance += int(e.get("uomini", 0))
		elif kind == GameState.EV_CRUSADE_DESERTION or kind == GameState.EV_CRUSADE_FAILED:
			# diserzioni e scioglimento li tolgono
			balance -= int(e.get("uomini", 0))
		elif kind == GameState.EV_PLAGUE or kind == GameState.EV_STORM or kind == GameState.EV_HORDE_GONE:
			# dalla fase 6a: peste (anche la Peste Nera), tempeste e scioglimento dell'Orda tolgono uomini
			balance -= int(e.get("uomini", 0))
		elif kind == GameState.EV_HORDE_ARRIVES:
			# l'arrivo dell'Orda d'Oro li crea
			balance += int(e.get("uomini", 0))
		elif kind == GameState.EV_PRISONERS and (str(e["esito"]) == PrisonerProcessor.OUTCOME_RELEASED or str(e["esito"]) == PrisonerProcessor.OUTCOME_RANSOMED):
			# ADR-073: i prigionieri catturati sono gia' tolti (catture); liberati o riscattati tornano
			balance += int(e.get("uomini", 0))
		elif kind == GameState.EV_RETRAINED or kind == GameState.EV_ROYAL_GUARD:
			# riaddestramento: le pile decimate tornano all'organico pieno, gli uomini aggiunti li dichiara l'evento;
			# ADR-114: la guardia del capo li crea
			balance += int(e.get("uomini", 0))
	return balance


func test_cento_anni_con_attacchi_casuali(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var orders := 0
	var battles := 0
	var captures := 0
	var sieges := 0
	var wars := 0
	for i in 100:
		if i % 5 == 0:
			orders += _attack_round(s, rng, i % 10 == 0)
		var before := _men_total(s)
		var res := TurnProcessor.end_year(s)
		var errs: Array = res["errori"]
		if errs.size() > 0 or not bool(res["ok"]):
			t.assert_true(false, "anno %d: errori %s" % [s.year, str(errs)])
			return
		for e in s.events:
			var kind := str(e["tipo"])
			if kind == GameState.EV_BATTLE:
				battles += 1
			elif kind == GameState.EV_PROVINCE_CAPTURED:
				captures += 1
			elif kind == GameState.EV_SIEGE_STARTED:
				sieges += 1
			elif kind == GameState.EV_WAR_DECLARED:
				wars += 1
		var expected := before + _men_balance(s)
		if _men_total(s) != expected:
			t.assert_true(false, "anno %d: gli uomini non quadrano (%d attesi, %d presenti)" % [s.year, expected, _men_total(s)])
			return
		var problem := _coherence_problem(s)
		if problem != "":
			t.assert_true(false, "anno %d: %s" % [s.year, problem])
			return
	t.assert_eq(s.year, _campaign.start_year + 100)
	t.assert_true(orders > 100, "gli attacchi sono stati ordinati (%d)" % orders)
	t.assert_true(wars > 0 and s.wars.size() > 0, "sono state dichiarate guerre")
	t.assert_true(battles > 0, "ci sono state battaglie")
	# rapporto leggibile dei cento anni nella console dei test
	var alive := 0
	for f in s.factions:
		if f.alive:
			alive += 1
	print("   100 anni: %d ordini, %d guerre, %d battaglie, %d assedi, %d conquiste, %d fazioni vive su %d" % [orders, wars, battles, sieges, captures, alive, _campaign.active_factions().size()])


## Partita sotto stress: sei fazioni (non gli Auror) con tasse massime e generali infedeli, guerra civile certa
## quando c'e' un innesco. Ogni anno: nessun errore, uomini che quadrano, nessuna incoerenza, ogni fazione viva con
## un capo, ogni esercito con un comandante vivo della sua fazione. Eseguita due volte: stesso stato finale.
func _run_stress(years: int, t: TestContext) -> Dictionary:
	var s := _new_game(31337)
	s.rules.province.civil_chance = 1.0
	var stressed: Array[String] = []
	for f in s.factions:
		if stressed.size() >= 6:
			break
		if f.alive and f.id != GameState.REBEL and f.id != "FN_DANISH" and not s.provinces_of(f.id).is_empty():
			stressed.append(f.id)
	for fid in stressed:
		for p in s.provinces_of(fid):
			p.tax_level = 4
		for c in s.characters_of(fid):
			if c.role == Character.ROLE_GENERAL:
				c.loyalty = 0
	var out := {"stato": s, "rivolte": 0, "guerre_civili": 0, "riemerse": 0, "estinte": 0, "problema": ""}
	for i in years:
		var before := _men_total(s)
		var res := TurnProcessor.end_year(s)
		var errs: Array = res["errori"]
		if errs.size() > 0 or not bool(res["ok"]):
			out["problema"] = "anno %d: errori %s" % [s.year, str(errs)]
			return out
		out["rivolte"] = int(out["rivolte"]) + _count_events(s, GameState.EV_REBELLION) + _count_events(s, GameState.EV_REBELLION_SPREAD)
		out["guerre_civili"] = int(out["guerre_civili"]) + _count_events(s, GameState.EV_CIVIL_WAR)
		out["riemerse"] = int(out["riemerse"]) + _count_events(s, GameState.EV_FACTION_REEMERGED)
		out["estinte"] = int(out["estinte"]) + _count_events(s, GameState.EV_FACTION_EXTINCT)
		var expected := before + _men_balance(s)
		if _men_total(s) != expected:
			out["problema"] = "anno %d: gli uomini non quadrano (%d attesi, %d presenti)" % [s.year, expected, _men_total(s)]
			return out
		var problem := _coherence_problem(s)
		if problem == "":
			problem = _leadership_problem(s)
		if problem != "":
			out["problema"] = "anno %d: %s" % [s.year, problem]
			return out
	return out


## Ogni fazione viva ha un capo vivo; ogni esercito non ribelle ha un comandante vivo della sua fazione.
func _leadership_problem(s: GameState) -> String:
	for f in s.factions:
		if f.alive and f.id != GameState.REBEL:
			var leader := s.leader_of(f.id)
			if leader == null or not leader.alive:
				return "%s e' viva senza capo" % f.id
	for a in s.armies:
		if a.faction == GameState.REBEL:
			continue
		var c := s.commander_of(a.id)
		if c == null or not c.alive or c.faction != a.faction:
			return "esercito %d di %s senza comandante vivo" % [a.id, a.faction]
	return ""


func test_duecento_anni_di_province_ribelli_e_guerre_civili(t: TestContext) -> void:
	if not _load_static(t):
		return
	var first := _run_stress(200, t)
	t.assert_eq(first["problema"], "")
	if first["problema"] != "":
		return
	var s: GameState = first["stato"]
	t.assert_eq(s.year, _campaign.start_year + 200)
	t.assert_true(int(first["rivolte"]) >= 1, "almeno una rivolta in 200 anni (%d)" % int(first["rivolte"]))
	t.assert_true(int(first["guerre_civili"]) + int(first["estinte"]) >= 1, "almeno una guerra civile o estinzione")
	print("   200 anni sotto stress: %d rivolte, %d guerre civili, %d riemersioni, %d estinzioni" % [first["rivolte"], first["guerre_civili"], first["riemerse"], first["estinte"]])
	var second := _run_stress(200, t)
	t.assert_eq(second["problema"], "")
	t.assert_eq(SaveGame.to_json(first["stato"]), SaveGame.to_json(second["stato"]), "stesso seme, stesso stato dopo 200 anni")


func test_guerre_deterministiche_sui_dati_reali(t: TestContext) -> void:
	if not _load_static(t):
		return
	var states: Array[GameState] = []
	for run in 2:
		var s := _new_game(31)
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for i in 25:
			if i % 5 == 0:
				_attack_round(s, rng, i % 10 == 0)
			TurnProcessor.end_year(s)
		states.append(s)
	t.assert_eq(SaveGame.to_json(states[0]), SaveGame.to_json(states[1]), "stesso seme, stesse guerre, stesso stato")
	# salvataggio e ricarico dopo 25 anni di guerra: l'anno successivo e' identico
	var restored := SaveGame.from_dict(SaveGame.to_dict(states[0]), _campaign, _units, _buildings, Rules.load_file())
	t.assert_true(bool(restored["ok"]), str(restored["errore"]))
	if not bool(restored["ok"]):
		return
	var loaded: GameState = restored["stato"]
	TurnProcessor.end_year(states[0])
	TurnProcessor.end_year(loaded)
	t.assert_eq(SaveGame.to_json(loaded), SaveGame.to_json(states[0]), "anno successivo dopo il ricarico, con guerre e assedi")


# --- rapporto del primo anno --------------------------------------------------------------


func test_rapporto_economia_del_primo_anno(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game()
	var before := {}
	for f in s.factions:
		before[f.id] = f.treasury
	var first_year := s.year
	TurnProcessor.end_year(s)
	var text := _build_report(s, before, first_year)
	t.assert_true(text.contains("FN_"), "il rapporto elenca le fazioni")
	var user_file := FileAccess.open(REPORT_USER, FileAccess.WRITE)
	t.assert_true(user_file != null, "rapporto scrivibile in %s" % REPORT_USER)
	if user_file != null:
		user_file.store_string(text)
		user_file.close()
	# copia nella cartella del progetto, se scrivibile (non in un'esportazione)
	var project_file := FileAccess.open(REPORT_PROJECT, FileAccess.WRITE)
	if project_file != null:
		project_file.store_string(text)
		project_file.close()


func _build_report(s: GameState, before: Dictionary, first_year: int) -> String:
	var lines := PackedStringArray()
	lines.append("Rapporto economia del primo anno (%d -> %d), seme %d" % [first_year, s.year, s.seed_value])
	lines.append("Reddito = agricoltura + miniere + commercio; netto = reddito - mantenimento. Fiorini.")
	lines.append("Da confrontare a mano con il gioco originale (catalogo, sezione Economia). Regole PROVVISORIE: miniere, commercio, mantenimento, arrotondamento.")
	lines.append("")
	lines.append("%-24s %4s %10s %8s %10s %13s %9s %12s %12s" % ["fazione", "prov", "agricolt.", "miniere", "commercio", "mantenimento", "netto", "tesoro prima", "tesoro dopo"])
	var sum_farm := 0
	var sum_mines := 0
	var sum_trade := 0
	var sum_upkeep := 0
	for f in s.factions:
		if not f.alive:
			continue
		var li := f.last_income
		var farm := int(li["agricoltura"])
		var mines := int(li["miniere"])
		var trade := int(li["commercio"])
		var upkeep := int(li["mantenimento"])
		sum_farm += farm
		sum_mines += mines
		sum_trade += trade
		sum_upkeep += upkeep
		lines.append("%-24s %4d %10d %8d %10d %13d %9d %12d %12d" % [f.id, s.provinces_of(f.id).size(), farm, mines, trade, upkeep, int(li["netto"]), int(before[f.id]), f.treasury])
	lines.append("%-24s %4s %10d %8d %10d %13d %9d" % ["totale", "", sum_farm, sum_mines, sum_trade, sum_upkeep, sum_farm + sum_mines + sum_trade - sum_upkeep])
	lines.append("")
	var contested := 0
	for p in s.provinces:
		if bool(p.last_income.get("conteso", false)):
			contested += 1
	lines.append("Province contese nel primo anno: %d" % contested)
	return "\n".join(lines) + "\n"


## Vero se una delle fazioni indicate dalle chiavi dell'evento e' quella dei ribelli.
func _involves_rebels(e: Dictionary, keys: Array) -> bool:
	for k in keys:
		if str(e.get(k, "")) == GameState.REBEL:
			return true
	return false


func _count_events(s: GameState, kind: String) -> int:
	var n := 0
	for e in s.events:
		if str(e["tipo"]) == kind:
			n += 1
	return n
