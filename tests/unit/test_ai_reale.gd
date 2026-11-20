extends RefCounted
## IA della fase 7a sui dati reali dell'installazione (EARLY_XL.TXT, prod unita' ed edifici), saltata se l'installazione manca:
## un anno di pianificazione di tutte le fazioni sotto il budget di tempo (`budget_ms` di ia.cfg, con stampa dei millisecondi),
## nessun comando rifiutato, e il determinismo su 50 anni di partita (la durata del file deve restare sotto i 120 s) (due partite con lo stesso seme, stesso testo di
## salvataggio). La partita lunga 1000-1700 sta in test_ai_partita_lunga.gd. Durata prevista del file: 20-60 secondi.

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


func _new_game(seed_value: int) -> GameState:
	return GameSetup.new_game(_campaign, _units, _buildings, Rules.load_file(), seed_value)


func test_un_anno_di_tutte_le_fazioni_sotto_il_budget(t: TestContext) -> void:
	if not _load_static(t):
		return
	var rules := AiRules.load_file(AiRules.DEFAULT_PATH)
	t.assert_eq(rules.errors, PackedStringArray(), "ia.cfg letto senza errori")
	var s := _new_game(20261108)
	var cold := AiController.plan_year(s, "", rules)
	print("   pianificazione dell'anno %d, %d fazioni: %.1f ms (a freddo, cache vuote), %d ordini, %d rifiutati" % [
		s.year, int(cold["fazioni"]), float(cold["ms"]), int(cold["ordini"]), int(cold["rifiutati"])])
	t.assert_true(int(cold["fazioni"]) >= 10, "molte fazioni pianificate")
	t.assert_true(int(cold["ordini"]) > 0, "qualche ordine")
	t.assert_eq(int(cold["rifiutati"]), 0, "nessun comando rifiutato: %s" % str(cold["rifiuti"]))
	var warm_game := _new_game(20261108)
	var warm := AiController.plan_year(warm_game, "", rules)
	print("   stessa pianificazione a caldo: %.1f ms (budget %d ms)" % [float(warm["ms"]), rules.budget_ms])
	t.assert_true(float(warm["ms"]) < float(rules.budget_ms), "anno pianificato in %.1f ms, budget %d ms" % [float(warm["ms"]), rules.budget_ms])
	t.assert_true(float(cold["ms"]) < float(rules.budget_ms) * 4.0, "anche a freddo entro 4 volte il budget")
	t.assert_eq(_footprint(s), _footprint(warm_game), "stessa partita, stessi ordini")
	t.assert_true(s.ai_orders_horde)


func test_le_difficolta_cambiano_gli_ordini_senza_errori(t: TestContext) -> void:
	if not _load_static(t):
		return
	var rules := AiRules.load_file(AiRules.DEFAULT_PATH)
	for name in AiRules.DIFFICULTIES:
		var s := _new_game(77)
		var report := AiController.plan_year(s, name, rules)
		print("   difficolta' %s: %d ordini in %.1f ms" % [name, int(report["ordini"]), float(report["ms"])])
		t.assert_eq(int(report["rifiutati"]), 0, "%s: %s" % [name, str(report["rifiuti"])])


func test_il_giocatore_non_riceve_ordini_sui_dati_reali(t: TestContext) -> void:
	if not _load_static(t):
		return
	var s := _new_game(5)
	var player := ""
	for f in s.factions:
		if f.alive and f.id != GameState.REBEL and not s.provinces_of(f.id).is_empty():
			player = f.id
			break
	t.assert_true(player != "")
	s.faction(player).is_player = true
	var before_treasury := s.faction(player).treasury
	AiController.plan_year(s)
	t.assert_eq(s.faction(player).treasury, before_treasury, "tesoro del giocatore intatto")
	for p in s.provinces_of(player):
		t.assert_true(p.unit_queue.is_empty() and p.building_queue.is_empty(), "nessuna coda ordinata al giocatore in %s" % p.id)
	for a in s.armies_of(player):
		t.assert_true(a.path.is_empty() and not a.assault_ordered, "nessun ordine agli eserciti del giocatore")


func test_cinquanta_anni_deterministici(t: TestContext) -> void:
	if not _load_static(t):
		return
	var started := Time.get_ticks_msec()
	var first := _new_game(31337)
	var second := _new_game(31337)
	for i in 50:
		var r1 := CampaignTurn.advance(first)
		var r2 := CampaignTurn.advance(second)
		if not bool(r1["ok"]) or (r1["errori"] as Array).size() > 0:
			t.assert_true(false, "anno %d: %s" % [first.year, str(r1["errori"])])
			return
		t.assert_eq(int(r1["anno"]), int(r2["anno"]))
	var text1 := SaveGame.to_json(first)
	var text2 := SaveGame.to_json(second)
	t.assert_eq(first.year, 1050, "cinquanta anni")
	t.assert_true(text1 == text2, "due partite con lo stesso seme hanno lo stesso testo di salvataggio")
	var other := _new_game(31338)
	for i in 5:
		CampaignTurn.advance(other)
	var third := _new_game(31337)
	for i in 5:
		CampaignTurn.advance(third)
	t.assert_true(SaveGame.to_json(other) != SaveGame.to_json(third), "un altro seme, un'altra partita")
	print("   2 partite da 50 anni (+10 anni) in %.1f s" % [float(Time.get_ticks_msec() - started) / 1000.0])


## Impronta degli ordini dell'anno (code, tasse, percorsi, tesori) per confrontare due partite.
func _footprint(s: GameState) -> String:
	var parts: Array[String] = []
	for a in s.armies:
		parts.append("%d:%s:%s:%s" % [a.id, a.faction, a.region, str(a.path)])
	for p in s.provinces:
		var queue: Array[String] = []
		for q in p.building_queue:
			queue.append(q.key)
		for q in p.unit_queue:
			queue.append(q.key)
		parts.append("%s:%d:%s" % [p.id, p.tax_level, str(queue)])
	for f in s.factions:
		parts.append("%s:%d" % [f.id, f.treasury])
	return "|".join(parts)
