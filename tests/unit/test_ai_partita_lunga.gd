extends RefCounted
## Partita IA contro IA dal 1000 al 1700 sui dati reali (tutte le fazioni giocate dall'IA, `CampaignTurn.advance`), saltata se
## l'installazione manca. Serve a tarare i parametri PROVVISORI di ia.cfg: ogni 50 anni stampa province per fazione, guerre,
## conquiste, tesori minimo e massimo, eserciti e uomini; dalla 7b anche alleanze, tregue, crociate, jihad e proposte rifiutate
## (cumulati e in vigore); poi controlla che la mappa cambi, che nessun tesoro diventi assurdo,
## che il mantenimento stia sotto il reddito per la maggior parte delle fazioni e che lo stato resti coerente.
## Durata PREVISTA (non misurata): la simulazione da sola costa 20-45 secondi, l'IA 20-60 ms l'anno (15-40 secondi in tutto):
## circa 60-100 secondi. Un'uscita di sicurezza ferma la partita a 110 secondi (la stampa lo dice e i controlli finali valgono
## per gli anni giocati) per restare sotto i 120 secondi del file.

const TIME_LIMIT_MS := 110000
const SANE_TREASURY := 50000000   ## PROVVISORIO: col mantenimento basso dei dati i tesori crescono in 700 anni (5 milioni nel 1500)

## Eventi diplomatici e religiosi cumulati dall'inizio (fase 7b): nome dell'evento -> quanti.
var _diplo := {}

var _campaign: CampaignData
var _units: UnitProdLoader.UnitTable
var _buildings: BuildingProdLoader.BuildingTable


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


## Riga di metriche dell'anno corrente.
func _metrics(s: GameState, conquests: int) -> String:
	var counts := {}
	for p in s.provinces:
		counts[p.owner] = int(counts.get(p.owner, 0)) + 1
	var ranking: Array[Dictionary] = []
	for owner_id in counts:
		ranking.append({"id": str(owner_id), "n": int(counts[owner_id])})
	ranking.sort_custom(_more_provinces)
	var top := PackedStringArray()
	for i in mini(5, ranking.size()):
		top.append("%s=%d" % [str(ranking[i]["id"]).trim_prefix("FN_"), int(ranking[i]["n"])])
	var low := 1 << 60
	var high := -(1 << 60)
	var alive := 0
	for f in s.factions:
		if f.alive and f.id != GameState.REBEL and counts.has(f.id):
			alive += 1
			low = mini(low, f.treasury)
			high = maxi(high, f.treasury)
	var men := 0
	var armies := 0
	var mercs := 0
	for a in s.armies:
		if not a.is_fleet:
			armies += 1
			men += a.men_total()
			for u in a.stacks:
				if u.mercenary:
					mercs += 1
	return "%d: fazioni con province %d, ribelli %d, guerre %d, conquiste %d, tesori %d..%d, eserciti %d, uomini %d, mercenari %d | prime: %s" % [
		s.year, alive, int(counts.get(GameState.REBEL, 0)), s.wars.size(), conquests, low, high, armies, men, mercs, ", ".join(top)]


## Conta gli eventi dell'anno che interessano la diplomazia, gli agenti e le crociate (jihad separati dalle crociate).
func _count_events(s: GameState) -> void:
	for e in s.events:
		var kind := str(e["tipo"])
		var key := ""
		if kind == GameState.EV_TRUCE:
			key = "tregue"
		elif kind == GameState.EV_ALLIANCE_FORMED:
			key = "alleanze"
		elif kind == GameState.EV_ALLIANCE_BROKEN:
			key = "alleanze rotte"
		elif kind == GameState.EV_MARRIAGE:
			key = "nozze"
		elif kind == GameState.EV_PROPOSAL_REFUSED:
			key = "proposte rifiutate"
		elif kind == GameState.EV_BRIBE:
			key = "corruzioni"
		elif kind == GameState.EV_ASSASSINATION:
			key = "assassinii"
		elif kind == GameState.EV_CRUSADE_LAUNCHED:
			key = "jihad" if str(e.get("genere", "")) == PapacyProcessor.KIND_JIHAD else "crociate"
		if key != "":
			_diplo[key] = int(_diplo.get(key, 0)) + 1


## Riga della diplomazia: trattati in vigore e eventi cumulati.
func _diplomacy_line(s: GameState) -> String:
	var parts := PackedStringArray()
	for key in ["alleanze", "tregue", "nozze", "alleanze rotte", "proposte rifiutate", "corruzioni", "assassinii", "crociate", "jihad"]:
		parts.append("%s %d" % [key, int(_diplo.get(key, 0))])
	var crusading := 0
	for a in s.armies:
		if a.is_crusade():
			crusading += 1
	return "%d: in vigore alleanze %d, tregue %d, eserciti crociati %d | cumulati: %s" % [
		s.year, s.alliances.size(), s.truces.size(), crusading, ", ".join(parts)]


static func _more_provinces(x: Dictionary, y: Dictionary) -> bool:
	return int(x["n"]) > int(y["n"])


## Quante fazioni con province hanno mantenimento (senza coda) non oltre il reddito, e quante ne hanno.
func _support_balance(s: GameState, rules: AiRules) -> Vector2i:
	var ctx := AiContext.build(s, rules)
	var within := 0
	var total := 0
	for f in s.factions:
		if not f.alive or f.id == GameState.REBEL or s.provinces_of(f.id).is_empty():
			continue
		total += 1
		if ctx.upkeep_of(f.id, false) <= ctx.income_of(f.id):
			within += 1
	return Vector2i(within, total)


func _coherence_problem(s: GameState) -> String:
	for p in s.provinces:
		if s.faction(p.owner) == null:
			return "provincia %s con proprietario sconosciuto %s" % [p.id, p.owner]
	var seen := {}
	for a in s.armies:
		if seen.has(a.id):
			return "esercito %d duplicato" % a.id
		seen[a.id] = true
		if s.faction(a.faction) == null:
			return "esercito %d di una fazione sconosciuta %s" % [a.id, a.faction]
		if s.campaign.region(a.region) == null:
			return "esercito %d in una regione sconosciuta %s" % [a.id, a.region]
		if a.is_fleet != s.campaign.region(a.region).is_sea:
			return "esercito %d: flotta e terra confusi in %s" % [a.id, a.region]
		for st in a.stacks:
			if st.men <= 0:
				return "esercito %d con una pila vuota" % a.id
	for f in s.factions:
		if f.alive and f.id != GameState.REBEL and f.treasury > SANE_TREASURY:
			return "tesoro assurdo di %s: %d" % [f.id, f.treasury]
	return ""


func test_partita_ia_contro_ia_1000_1700(t: TestContext) -> void:
	if not _load_static(t):
		return
	var rules := AiRules.load_file(AiRules.DEFAULT_PATH)
	var s := GameSetup.new_game(_campaign, _units, _buildings, Rules.load_file(), 20261108)
	var owners_at_start := {}
	for p in s.provinces:
		owners_at_start[p.id] = p.owner
	_diplo = {}
	var started := Time.get_ticks_msec()
	var conquests := 0
	var rejected := 0
	var orders := 0
	var rejections: Array = []
	var ai_total := 0.0
	var ai_max := 0.0
	var years := 0
	var cut := false
	var max_treasury := 0
	var support_ok := Vector2i.ZERO
	var sampled := 0
	var guard := 0
	print("   inizio: %s" % _metrics(s, 0))
	while not s.is_game_over() and guard < 800:
		guard += 1
		var report := AiController.plan_year(s, "", rules)
		var res := TurnProcessor.end_year(s)
		s.ai_orders_horde = false
		years += 1
		orders += int(report["ordini"])
		rejected += int(report["rifiutati"])
		for line in report["rifiuti"]:
			if rejections.size() < 20:
				rejections.append(line)
		ai_total += float(report["ms"])
		ai_max = maxf(ai_max, float(report["ms"]))
		var errs: Array = res["errori"]
		if errs.size() > 0 or not bool(res["ok"]):
			t.assert_true(false, "anno %d: errori %s" % [s.year, str(errs)])
			return
		for e in s.events:
			if str(e["tipo"]) == GameState.EV_PROVINCE_CAPTURED:
				conquests += 1
		_count_events(s)
		for f in s.factions:
			if f.alive and f.treasury > max_treasury:
				max_treasury = f.treasury
		if (s.year - 1000) % 50 == 0:
			print("   " + _metrics(s, conquests))
			print("   " + _diplomacy_line(s))
			var problem := _coherence_problem(s)
			if problem != "":
				t.assert_true(false, "anno %d: stato incoerente: %s" % [s.year, problem])
				return
		if s.year >= 1100 and (s.year - 1000) % 100 == 0:
			var balance := _support_balance(s, rules)
			support_ok += balance
			sampled += 1
			print("   %d: mantenimento entro il reddito in %d fazioni su %d" % [s.year, balance.x, balance.y])
		if Time.get_ticks_msec() - started > TIME_LIMIT_MS:
			cut = true
			break
	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	print("   %d anni giocati in %.1f s (IA: media %.1f ms, massimo %.1f ms l'anno); ordini %d, rifiutati %d, conquiste %d, tesoro massimo %d%s" % [
		years, elapsed, ai_total / maxf(1.0, float(years)), ai_max, orders, rejected, conquests, max_treasury,
		" - INTERROTTA al limite di tempo" if cut else ""])
	print("   diplomazia e agenti: %s" % _diplomacy_line(s))
	for line in rejections:
		print("   rifiuto: %s" % str(line))
	if not cut:
		t.assert_eq(s.year, 1700, "arrivata al 1700")
		t.assert_true(s.is_game_over())
	var problem_end := _coherence_problem(s)
	t.assert_eq(problem_end, "", "stato coerente alla fine")
	# la mappa cambia
	var changed := 0
	for p in s.provinces:
		if str(owners_at_start[p.id]) != p.owner:
			changed += 1
	print("   province che hanno cambiato proprietario tra inizio e fine: %d su %d" % [changed, s.provinces.size()])
	t.assert_true(conquests >= 5, "la mappa cambia: %d conquiste" % conquests)
	t.assert_true(changed >= 3, "alla fine almeno 3 province hanno un altro proprietario (%d)" % changed)
	# fase 7b: nascono tregue e alleanze (nei dati reali le guerre non finivano mai e non c'erano alleanze)
	if not cut:
		t.assert_true(int(_diplo.get("tregue", 0)) >= 3, "nascono tregue: %d" % int(_diplo.get("tregue", 0)))
		t.assert_true(int(_diplo.get("alleanze", 0)) + int(_diplo.get("nozze", 0)) >= 3, "nascono alleanze: %d + nozze %d" % [int(_diplo.get("alleanze", 0)), int(_diplo.get("nozze", 0))])
	# nessun tesoro assurdo
	t.assert_true(max_treasury <= SANE_TREASURY, "tesoro massimo %d" % max_treasury)
	# l'IA non produce comandi rifiutati (un rifiuto e' un difetto dell'IA): al massimo una frazione trascurabile
	t.assert_true(float(rejected) <= maxf(5.0, float(orders) / 200.0), "comandi rifiutati %d su %d ordini" % [rejected, orders])
	# il mantenimento sta sotto il reddito per la maggior parte delle fazioni
	if sampled > 0:
		t.assert_true(support_ok.x * 2 >= support_ok.y, "mantenimento entro il reddito in %d casi su %d" % [support_ok.x, support_ok.y])
	# la pianificazione resta sotto il budget in media
	t.assert_true(ai_total / maxf(1.0, float(years)) < float(rules.budget_ms), "tempo medio di pianificazione sotto il budget")
