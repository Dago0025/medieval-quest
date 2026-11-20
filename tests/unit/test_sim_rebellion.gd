extends RefCounted
## Test delle rivolte, della propagazione e della riemersione delle fazioni (fase 4b, `ProvinceProcessor`) sul
## mondo di prova tests/fixtures/dynasty_*.txt (vedi test_sim_loyalty.gd): ALTA (rendita 400) e BASSA (300) sono di
## ALPHA, MEZZA (200) di BETA, SOLA (100) dei ribelli. Truppa ribelle del mondo di prova: le lancieri (100 uomini
## a pila). I sorteggi si rendono certi o impossibili con i parametri (`calm`, `revolt_k` 1 e `p_massima` 1).

const STARTPOS := "res://tests/fixtures/dynasty_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const HEROES := "res://tests/fixtures/dynasty_heroes.txt"


## Mondo senza sorteggi della fase 4b, governatore di BASSA a terrore 3 (obiettivi: ALTA 125, BASSA 100, MEZZA 109).
func _world(seed_value: int = 7) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	var rules := Rules.new()
	rules.province.calm()
	# Fase 5b: la partita nuova parte con 75/25 nelle province di religione diversa dal proprietario e la penalita' di
	# religione e' proporzionale (BASSA: -11). Questi test della 4b misurano le altre regole con la penalita' piena della
	# 4b (-15): ogni provincia parte tutta della religione della sua cultura. La regola nuova e' in test_sim_religion.gd.
	rules.religion.other_owner_share = 0
	var s := GameSetup.new_game(campaign, units, buildings, rules, seed_value, HeroesLoader.load_file(HEROES))
	var governor := s.governor_of("ID_BASSA")
	governor.dread = 3
	governor.vnv = {}
	ProvinceProcessor.init_loyalty(s)
	return s


## Ogni provincia sotto la soglia si rivolta di sicuro; niente propagazione, riemersione o guerra civile.
func _force(s: GameState) -> void:
	var pr := s.rules.province
	pr.revolt_k = 1.0
	pr.revolt_max_chance = 1.0


## Tassa massima e lealta' bassa: dopo l'anno di deriva la provincia e' sotto la soglia.
func _restive(s: GameState, region_id: String) -> void:
	var p := s.province(region_id)
	p.tax_level = 4
	p.loyalty = 30


func _events_of(s: GameState, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in s.events:
		if str(e["tipo"]) == kind:
			out.append(e)
	return out


func _rebel_armies_in(s: GameState, region_id: String) -> Array[Army]:
	var out: Array[Army] = []
	for a in s.armies_in(region_id):
		if a.faction == GameState.REBEL:
			out.append(a)
	return out


func _army_in(s: GameState, faction: String, region: String) -> Army:
	for a in s.armies_of(faction):
		if a.region == region and not a.is_fleet:
			return a
	return null


# --- la rivolta --------------------------------------------------------------------------------------


func test_una_rivolta_certa_crea_l_esercito_ribelle(t: TestContext) -> void:
	var s := _world()
	_force(s)
	_restive(s, "ID_BASSA")
	var armies_before := s.armies.size()
	s.events.clear()
	ProvinceProcessor.process_year(s)
	var revolts := _events_of(s, GameState.EV_REBELLION)
	t.assert_eq(revolts.size(), 1, "solo BASSA e' sotto la soglia")
	t.assert_eq(_events_of(s, GameState.EV_REBELLION_SPREAD).size(), 0)
	t.assert_eq(s.armies.size(), armies_before + 1)
	var rebels := _rebel_armies_in(s, "ID_BASSA")
	t.assert_eq(rebels.size(), 1)
	if revolts.size() != 1 or rebels.size() != 1:
		return
	var e := revolts[0]
	var army := rebels[0]
	t.assert_eq(e["fazione"], "FN_ALPHA", "la fazione che perde il controllo")
	t.assert_eq(e["regione"], "ID_BASSA")
	t.assert_eq(e["provincia"], "ID_BASSA")
	t.assert_eq(e["lealta"], s.province("ID_BASSA").loyalty, "lealta' dopo l'anno di deriva (30 + 9)")
	t.assert_eq(e["lealta"], 39)
	t.assert_eq(e["tipo_ribelli"], ProvinceProcessor.REBEL_ORTHODOX, "regione ortodossa, fazione cattolica")
	t.assert_eq(e["esercito"], army.id)
	t.assert_eq(e["uomini"], 200, "rendita 300 x 0,5 = 150 uomini: due pile da 100")
	t.assert_eq(army.men_total(), 200)
	t.assert_eq(army.stack_count(), 2)
	t.assert_eq(army.stacks[0].unit_id, s.units.get_unit("Spearmen").id)
	t.assert_eq(army.faction, GameState.REBEL)
	t.assert_false(army.is_fleet)
	t.assert_false(army.in_castle)
	t.assert_true(str(e["testo"]).contains("Rivolta"), "testo leggibile")
	t.assert_eq(int(s.province("ID_BASSA").counters["rivolte"]), 1)
	t.assert_eq(s.province("ID_BASSA").owner, "FN_ALPHA", "la provincia cambia padrone solo con le regole di guerra")
	t.assert_true(s.at_war(GameState.REBEL, "FN_ALPHA"))


func test_senza_rivolta_sopra_la_soglia_niente_sorteggi(t: TestContext) -> void:
	var s := _world()
	s.rules.province = ProvinceRules.new()
	var rng_before := s.rng.state
	s.events.clear()
	ProvinceProcessor.process_year(s)
	t.assert_eq(s.rng.state, rng_before, "nessuna provincia sotto 100 e nessun innesco: nessun sorteggio")
	t.assert_eq(s.events.size(), 0)
	t.assert_eq(_rebel_armies_in(s, "ID_BASSA").size(), 0)
	# alla soglia (BASSA vale 100) la probabilita' e' zero
	t.assert_eq(s.province("ID_BASSA").loyalty, 100)


func test_probabilita_di_rivolta(t: TestContext) -> void:
	var s := _world(21)
	s.rules.province.revolt_k = 0.0625   # da 92 mancano 8 punti: probabilita' 0,5
	var bassa := s.province("ID_BASSA")
	var revolts := 0
	for i in 400:
		bassa.loyalty = 90
		var before := s.armies.size()
		ProvinceProcessor.process_year(s)
		if s.armies.size() > before:
			revolts += 1
			s.remove_army(s.armies[s.armies.size() - 1])
	t.assert_true(revolts >= 140 and revolts <= 260, "circa meta' delle prove: %d su 400" % revolts)


func test_province_contese_o_senza_truppa_non_si_rivoltano(t: TestContext) -> void:
	var s := _world()
	_force(s)
	_restive(s, "ID_BASSA")
	# un esercito di un'altra fazione nella provincia: gia' contesa
	var spearmen := s.units.get_unit("Spearmen")
	var enemy := s.create_army("FN_BETA", "ID_BASSA", false)
	enemy.stacks.append(UnitStack.new(spearmen.id, 50, 0))
	var rng_before := s.rng.state
	s.events.clear()
	ProvinceProcessor.process_year(s)
	t.assert_eq(_events_of(s, GameState.EV_REBELLION).size(), 0, "provincia contesa")
	t.assert_eq(s.rng.state, rng_before, "e nessun sorteggio")
	s.remove_army(enemy)
	# gia' in rivolta: un solo esercito ribelle alla volta
	var again := _world()
	_force(again)
	_restive(again, "ID_BASSA")
	ProvinceProcessor.process_year(again)
	again.province("ID_BASSA").loyalty = 30
	ProvinceProcessor.process_year(again)
	t.assert_eq(_rebel_armies_in(again, "ID_BASSA").size(), 1, "la provincia in rivolta non ne genera un'altra")
	t.assert_eq(_events_of(again, GameState.EV_REBELLION).size(), 1)
	# senza fanteria nella tabella non c'e' una truppa ribelle
	var empty := _world()
	_force(empty)
	_restive(empty, "ID_BASSA")
	empty.units.units.clear()
	t.assert_true(ProvinceProcessor.rebel_unit(empty, empty.campaign.region("ID_BASSA")) == null)
	empty.events.clear()
	ProvinceProcessor.process_year(empty)
	t.assert_eq(_events_of(empty, GameState.EV_REBELLION).size(), 0)
	# i ribelli non si rivoltano contro se stessi
	var rebels := _world()
	_force(rebels)
	rebels.province("ID_SOLA").loyalty = 0
	rebels.events.clear()
	ProvinceProcessor.process_year(rebels)
	t.assert_eq(_events_of(rebels, GameState.EV_REBELLION).size(), 0)


func test_truppa_ribelle_per_fazione_e_cultura(t: TestContext) -> void:
	var s := _world()
	var bassa := s.campaign.region("ID_BASSA")
	t.assert_eq(ProvinceProcessor.rebel_unit(s, bassa).id, s.units.get_unit("Spearmen").id, "senza truppe ribelli: la fanteria piu' economica")
	var peasants := UnitType.new("PEASANTS")
	peasants.type_name = UnitType.INFANTRY
	peasants.cost = 50
	peasants.men = 80
	peasants.factions = PackedStringArray(["FN_REBEL", "FN_DANISH"])
	peasants.cultures = PackedStringArray(["CATHOLIC", "ORTHODOX"])
	s.units.add(peasants)
	var muslim := UnitType.new("MUSLIMPEASANTS")
	muslim.type_name = UnitType.INFANTRY
	muslim.cost = 50
	muslim.men = 80
	muslim.factions = PackedStringArray(["FN_REBEL"])
	muslim.cultures = PackedStringArray(["MUSLIM", "CATHOLIC"])
	s.units.add(muslim)
	var cavalry := UnitType.new("RIBELLI_A_CAVALLO")
	cavalry.type_name = UnitType.CAVALRY
	cavalry.cost = 10
	cavalry.men = 40
	cavalry.factions = PackedStringArray(["FN_REBEL"])
	s.units.add(cavalry)
	t.assert_eq(ProvinceProcessor.rebel_unit(s, bassa).id, "PEASANTS", "ortodossa: contadini")
	t.assert_eq(ProvinceProcessor.rebel_unit(s, s.campaign.region("ID_MEZZA")).id, "MUSLIMPEASANTS", "musulmana")
	t.assert_eq(ProvinceProcessor.rebel_unit(s, s.campaign.region("ID_ALTA")).id, "PEASANTS", "cattolica: a parita' di costo la prima del file")
	t.assert_eq(ProvinceProcessor.rebel_unit(s, s.campaign.region("ID_SOLA")).id, "PEASANTS", "pagana: nessuna adatta, la piu' economica in assoluto")
	t.assert_true(ProvinceProcessor.rebel_unit(s, null) == null)
	# l'esercito nato usa le pile di quella truppa
	_force(s)
	_restive(s, "ID_BASSA")
	ProvinceProcessor.process_year(s)
	var rebels := _rebel_armies_in(s, "ID_BASSA")
	t.assert_eq(rebels.size(), 1)
	if rebels.size() == 1:
		t.assert_eq(rebels[0].stacks[0].unit_id, "PEASANTS")
		t.assert_eq(rebels[0].men_total(), 160, "150 uomini in pile da 80: due pile")


func test_ribelli_proporzionati_alla_rendita(t: TestContext) -> void:
	var s := _world()
	var bassa := s.province("ID_BASSA")
	t.assert_true(ProvinceProcessor.spawn_revolt(s, bassa, ""))
	t.assert_eq(s.armies[s.armies.size() - 1].men_total(), 200, "300 x 0,5 = 150 -> 2 pile")
	s.rules.province.rebels_per_income = 0.2
	ProvinceProcessor.spawn_revolt(s, bassa, "")
	t.assert_eq(s.armies[s.armies.size() - 1].men_total(), 100, "60 uomini: sale al minimo (una pila)")
	s.rules.province.rebels_per_income = 10.0
	ProvinceProcessor.spawn_revolt(s, bassa, "")
	t.assert_eq(s.armies[s.armies.size() - 1].men_total(), 600, "3000 uomini: limitati al massimo")
	s.rules.max_stacks = 3
	ProvinceProcessor.spawn_revolt(s, bassa, "")
	t.assert_eq(s.armies[s.armies.size() - 1].stack_count(), 3, "mai piu' pile del limite degli eserciti")
	s.rules.province.rebels_per_income = 0.5
	ProvinceProcessor.spawn_revolt(s, s.province("ID_MEZZA"), "")
	t.assert_eq(s.armies[s.armies.size() - 1].men_total(), 100, "rendita 200: una pila")


func test_tipi_di_ribelli(t: TestContext) -> void:
	var s := _world()
	var alta := s.province("ID_ALTA")
	alta.loyalty = 80
	t.assert_eq(ProvinceProcessor.rebel_type(s, alta), ProvinceProcessor.REBEL_PEASANTS, "stessa religione: contadini")
	alta.loyalty = 49
	t.assert_eq(ProvinceProcessor.rebel_type(s, alta), ProvinceProcessor.REBEL_BANDITS, "lealta' molto bassa: banditi")
	var region := s.campaign.region("ID_ALTA")
	region.culture = "MUSLIM_CULTURE"
	t.assert_eq(ProvinceProcessor.rebel_type(s, alta), ProvinceProcessor.REBEL_MUSLIMS)
	region.culture = "ORTHODOX_CULTURE"
	t.assert_eq(ProvinceProcessor.rebel_type(s, alta), ProvinceProcessor.REBEL_ORTHODOX)
	region.culture = "PAGAN_CULTURE"
	t.assert_eq(ProvinceProcessor.rebel_type(s, alta), ProvinceProcessor.REBEL_HERETICS)
	region.culture = "CATHOLIC_CULTURE"
	s.campaign.faction("FN_ALPHA").religion = "REL_ORTHODOX"
	t.assert_eq(ProvinceProcessor.rebel_type(s, alta), ProvinceProcessor.REBEL_CATHOLICS)


# --- propagazione -----------------------------------------------------------------------------------------


func test_la_rivolta_si_propaga_alle_province_deboli_confinanti(t: TestContext) -> void:
	var s := _world()
	_force(s)
	s.rules.province.spread_chance = 1.0
	_restive(s, "ID_BASSA")
	s.province("ID_ALTA").loyalty = 101     # dopo la deriva 106: sopra la soglia di rivolta, sotto quella di propagazione
	s.province("ID_MEZZA").loyalty = 125    # dopo la deriva 122: troppo salda
	s.events.clear()
	ProvinceProcessor.process_year(s)
	var spreads := _events_of(s, GameState.EV_REBELLION_SPREAD)
	t.assert_eq(_events_of(s, GameState.EV_REBELLION).size(), 1, "la rivolta di BASSA")
	t.assert_eq(spreads.size(), 1, "si estende solo ad ALTA")
	if spreads.size() == 1:
		var e := spreads[0]
		t.assert_eq(e["regione"], "ID_ALTA")
		t.assert_eq(e["provincia"], "ID_ALTA")
		t.assert_eq(e["origine"], "ID_BASSA")
		t.assert_eq(e["fazione"], "FN_ALPHA")
		t.assert_eq(e["uomini"], 200)
		t.assert_eq(e["lealta"], 106)
		t.assert_true(str(e["testo"]).contains("estende"))
	t.assert_eq(_rebel_armies_in(s, "ID_ALTA").size(), 1)
	t.assert_eq(_rebel_armies_in(s, "ID_MEZZA").size(), 0)
	t.assert_eq(int(s.province("ID_ALTA").counters["rivolte"]), 1)
	# l'ordine degli eventi: prima la rivolta, poi la propagazione
	var kinds: Array[String] = []
	for e in s.events:
		var kind := str(e["tipo"])
		if kind == GameState.EV_REBELLION or kind == GameState.EV_REBELLION_SPREAD:
			kinds.append(kind)
	t.assert_eq(kinds.size(), 2)
	if kinds.size() == 2:
		t.assert_eq(kinds[0], GameState.EV_REBELLION)
		t.assert_eq(kinds[1], GameState.EV_REBELLION_SPREAD)


func test_propagazione_spenta_o_sotto_soglia(t: TestContext) -> void:
	var off := _world()
	_force(off)
	off.rules.province.spread_chance = 0.0
	_restive(off, "ID_BASSA")
	off.province("ID_ALTA").loyalty = 101
	ProvinceProcessor.process_year(off)
	t.assert_eq(_events_of(off, GameState.EV_REBELLION).size(), 1)
	t.assert_eq(_events_of(off, GameState.EV_REBELLION_SPREAD).size(), 0, "p_propagazione 0")
	var low := _world()
	_force(low)
	low.rules.province.spread_chance = 1.0
	low.rules.province.spread_threshold = 105
	_restive(low, "ID_BASSA")
	low.province("ID_ALTA").loyalty = 101    # 106 dopo la deriva: non sotto 105
	ProvinceProcessor.process_year(low)
	t.assert_eq(_events_of(low, GameState.EV_REBELLION_SPREAD).size(), 0, "soglia di propagazione")
	# province dei ribelli e di altre fazioni: la propagazione colpisce chiunque sia sotto soglia
	var other := _world()
	_force(other)
	other.rules.province.spread_chance = 1.0
	_restive(other, "ID_BASSA")
	other.province("ID_MEZZA").loyalty = 105    # 106 dopo la deriva verso 109: MEZZA e' di BETA
	ProvinceProcessor.process_year(other)
	var spreads := _events_of(other, GameState.EV_REBELLION_SPREAD)
	var hit_mezza := false
	for e in spreads:
		if e["regione"] == "ID_MEZZA":
			hit_mezza = true
			t.assert_eq(e["fazione"], "FN_BETA")
	t.assert_true(hit_mezza, "si estende anche a una provincia di un'altra fazione")


# --- regole di guerra e reddito ------------------------------------------------------------------------------


func test_i_ribelli_assediano_il_castello_e_la_provincia_non_rende(t: TestContext) -> void:
	var s := _world()
	_force(s)
	s.rules.combat.forced_outcome = 1      # vince sempre l'attaccante (i ribelli, che non sono arrivati ma attaccano)
	_restive(s, "ID_BASSA")
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0, "anno 1 senza errori")
	t.assert_eq(_events_of(s, GameState.EV_REBELLION).size(), 1)
	var bassa := s.province("ID_BASSA")
	t.assert_true(Economy.is_contested(s, bassa), "con l'esercito ribelle la provincia e' contesa")
	t.assert_true(bool(bassa.last_income["conteso"]), "il reddito dell'anno e' calcolato dopo la rivolta")
	t.assert_eq(int(bassa.last_income["totale"]), 0, "una provincia in rivolta non produce reddito")
	# anno 2: i ribelli (in guerra con tutti) attaccano la guarnigione, che si ritira nel castello e viene assediata
	res = TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0, "anno 2 senza errori")
	var battles := _events_of(s, GameState.EV_BATTLE)
	var rebel_battle := false
	for e in battles:
		if e["regione"] == "ID_BASSA":
			rebel_battle = true
			t.assert_eq(e["fazione"], GameState.REBEL, "i ribelli attaccano")
	t.assert_true(rebel_battle, "battaglia a BASSA")
	var sieges := _events_of(s, GameState.EV_SIEGE_STARTED)
	t.assert_eq(sieges.size(), 1, "i ribelli assediano il castello")
	if sieges.size() == 1:
		t.assert_eq(sieges[0]["fazione"], GameState.REBEL)
		t.assert_eq(sieges[0]["regione"], "ID_BASSA")
	t.assert_true(s.is_besieged("ID_BASSA"))
	t.assert_eq(bassa.owner, "FN_ALPHA", "la provincia regge")
	t.assert_eq(int(bassa.last_income["totale"]), 0, "assediata: ancora niente reddito")


func test_una_provincia_sguarnita_cade_in_mano_ai_ribelli(t: TestContext) -> void:
	var s := _world()
	_force(s)
	var bassa := s.province("ID_BASSA")
	for a in s.armies_in("ID_BASSA"):
		s.remove_army(a)
	_restive(s, "ID_BASSA")
	var governor := s.governor_of("ID_BASSA")
	t.assert_true(governor != null)
	TurnProcessor.end_year(s)
	t.assert_eq(bassa.owner, "FN_ALPHA", "anno 1: nasce l'esercito ribelle")
	t.assert_eq(_rebel_armies_in(s, "ID_BASSA").size(), 1)
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0, "anno 2 senza errori")
	t.assert_eq(bassa.owner, GameState.REBEL, "anno 2: conquista con le regole di guerra")
	var captured := _events_of(s, GameState.EV_PROVINCE_CAPTURED)
	t.assert_eq(captured.size(), 1)
	if captured.size() == 1:
		t.assert_eq(captured[0]["fazione"], GameState.REBEL)
		t.assert_eq(captured[0]["precedente"], "FN_ALPHA")
	t.assert_true(s.governor_of("ID_BASSA") == null, "il governatore perde il titolo")
	TurnProcessor.end_year(s)
	t.assert_eq(bassa.former_owner, "FN_ALPHA", "i ribelli ricordano chi la possedeva")
	t.assert_eq(bassa.loyalty_owner, GameState.REBEL)
	t.assert_true(s.faction("FN_ALPHA").alive, "ALPHA ha ancora ALTA")


func test_rivolte_deterministiche_e_stato_coerente(t: TestContext) -> void:
	var states: Array[GameState] = []
	for run in 2:
		var s := _world(33)
		s.rules.province = ProvinceRules.new()
		for p in s.provinces:
			if p.owner != GameState.REBEL:
				p.tax_level = 4
		for i in 40:
			var res := TurnProcessor.end_year(s)
			t.assert_eq((res["errori"] as Array).size(), 0, "anno %d" % s.year)
		states.append(s)
	t.assert_eq(SaveGame.to_json(states[0]), SaveGame.to_json(states[1]), "stesso seme, stesse rivolte")
	var s0 := states[0]
	for p in s0.provinces:
		var owner_state := s0.faction(p.owner)
		t.assert_true(owner_state != null and (owner_state.alive or p.owner == GameState.REBEL), "%s: proprietario %s" % [p.id, p.owner])
	for a in s0.armies:
		if a.faction == GameState.REBEL:
			continue
		var c := s0.commander_of(a.id)
		t.assert_true(c != null and c.alive and c.faction == a.faction, "esercito %d: comandante" % a.id)
	for f in s0.factions:
		if f.alive and s0.has_dynasty(f.id):
			t.assert_true(s0.leader_of(f.id) != null, "%s: capo" % f.id)


# --- riemersione -----------------------------------------------------------------------------------------------------


## Estingue ALPHA nel modo normale: tutti i suoi personaggi muoiono, il fine anno non trova successori.
func _extinguish_alpha(s: GameState) -> void:
	for c in s.characters_of("FN_ALPHA"):
		DynastyProcessor.kill(s, c, s.year + 1, "vecchiaia", false)
	TurnProcessor.end_year(s)


func test_una_fazione_estinta_riemerge_in_una_provincia_ribelle(t: TestContext) -> void:
	var s := _world()
	s.rules.province.reemerge_chance = 1.0
	_extinguish_alpha(s)
	var alpha := s.faction("FN_ALPHA")
	t.assert_false(alpha.alive, "estinta")
	t.assert_eq(_events_of(s, GameState.EV_FACTION_EXTINCT).size(), 1)
	t.assert_eq(_events_of(s, GameState.EV_FACTION_REEMERGED).size(), 0, "non riemerge nello stesso anno")
	t.assert_eq(s.province("ID_ALTA").owner, GameState.REBEL)
	t.assert_eq(s.province("ID_ALTA").former_owner, "FN_ALPHA")
	t.assert_eq(s.province("ID_BASSA").former_owner, "FN_ALPHA")
	t.assert_eq(s.province("ID_MEZZA").former_owner, "", "BETA non e' estinta")
	t.assert_true(ProvinceProcessor.reemergence_site(s, "FN_ALPHA") != null, "BASSA (100) e' sotto 120")
	t.assert_true(ProvinceProcessor.reemergence_site(s, "FN_BETA") == null)
	var res := TurnProcessor.end_year(s)
	t.assert_eq((res["errori"] as Array).size(), 0)
	var events := _events_of(s, GameState.EV_FACTION_REEMERGED)
	t.assert_eq(events.size(), 1, "nell'anno dopo riemerge")
	if events.size() != 1:
		return
	var e := events[0]
	t.assert_true(alpha.alive)
	t.assert_eq(e["fazione"], "FN_ALPHA")
	t.assert_eq(e["provincia"], "ID_ALTA", "la prima provincia ribelle che possedeva, sotto 120")
	t.assert_eq(e["regione"], "ID_ALTA")
	t.assert_eq(e["uomini"], 300, "nessun ribelle da arruolare: tre pile da 100")
	t.assert_true(alpha.treasury >= s.rules.province.reemerge_treasury)
	var alta := s.province("ID_ALTA")
	t.assert_eq(alta.owner, "FN_ALPHA")
	t.assert_eq(alta.former_owner, "")
	t.assert_eq(alta.loyalty_owner, "FN_ALPHA")
	t.assert_eq(s.province("ID_BASSA").owner, GameState.REBEL, "le altre province restano ribelli")
	var leader := s.leader_of("FN_ALPHA")
	t.assert_true(leader != null, "un capo nuovo")
	if leader != null:
		t.assert_eq(leader.id, e["capo"])
		t.assert_true(leader.alive and leader.royal_blood and leader.male)
		t.assert_eq(leader.role, Character.ROLE_LEADER)
		t.assert_eq(leader.region, "ID_ALTA")
		t.assert_true(leader.numeral >= 1)
		t.assert_eq(leader.loyalty, s.rules.dynasty.max_attribute)
		t.assert_eq(leader.influence, s.rules.dynasty.successor_influence)
		t.assert_true(leader.age(s.year) >= s.rules.dynasty.start_age_min and leader.age(s.year) <= s.rules.dynasty.start_age_max)
	var army_ids: Array = e["eserciti"]
	t.assert_eq(army_ids.size(), 1)
	for army_id in army_ids:
		var army := s.army(int(army_id))
		t.assert_true(army != null and army.faction == "FN_ALPHA" and army.region == "ID_ALTA")
		if army != null:
			t.assert_eq(army.stack_count(), s.rules.province.reemerge_stacks)
			var commander := s.commander_of(army.id)
			t.assert_true(commander != null and commander.alive and commander.faction == "FN_ALPHA", "l'esercito ha un comandante")


func test_la_riemersione_arruola_i_ribelli_presenti(t: TestContext) -> void:
	var s := _world()
	s.rules.province.reemerge_chance = 1.0
	_extinguish_alpha(s)
	var spearmen := s.units.get_unit("Spearmen")
	var local := s.create_army(GameState.REBEL, "ID_ALTA", false)
	local.stacks.append(UnitStack.new(spearmen.id, 70, 0))
	var elsewhere := s.create_army(GameState.REBEL, "ID_BASSA", false)
	elsewhere.stacks.append(UnitStack.new(spearmen.id, 40, 0))
	var men_before := 0
	for a in s.armies:
		men_before += a.men_total()
	TurnProcessor.end_year(s)
	var events := _events_of(s, GameState.EV_FACTION_REEMERGED)
	t.assert_eq(events.size(), 1)
	if events.size() == 1:
		t.assert_eq(events[0]["uomini"], 0, "gli uomini c'erano gia': nessuno e' creato")
		t.assert_eq(events[0]["eserciti"], [local.id])
	t.assert_eq(local.faction, "FN_ALPHA", "i ribelli della provincia passano alla fazione")
	t.assert_eq(elsewhere.faction, GameState.REBEL, "gli altri restano ribelli")
	var men_after := 0
	for a in s.armies:
		men_after += a.men_total()
	t.assert_eq(men_after, men_before, "nessun uomo creato o perso")


func test_quando_la_riemersione_non_avviene(t: TestContext) -> void:
	# fazione del giocatore
	var s := _world()
	s.rules.province.reemerge_chance = 1.0
	s.faction("FN_ALPHA").is_player = true
	_extinguish_alpha(s)
	for i in 3:
		s.victory = VictoryState.new()   # fase 6b: la sconfitta del giocatore chiude la partita; qui si prova solo la riemersione
		TurnProcessor.end_year(s)
	t.assert_false(s.faction("FN_ALPHA").alive, "il giocatore non riemerge")
	# probabilita' zero
	var calm := _world()
	_extinguish_alpha(calm)
	for i in 3:
		TurnProcessor.end_year(calm)
	t.assert_false(calm.faction("FN_ALPHA").alive, "senza probabilita' non riemerge")
	# lealta' troppo alta (la deriva e' lenta: dopo un anno e' ancora sopra la soglia)
	var loyal := _world()
	loyal.rules.province.reemerge_chance = 1.0
	loyal.rules.province.reemerge_threshold = 50
	_extinguish_alpha(loyal)
	TurnProcessor.end_year(loyal)
	t.assert_false(loyal.faction("FN_ALPHA").alive, "lealta' sopra la soglia di riemersione")
	t.assert_true(ProvinceProcessor.reemergence_site(loyal, "FN_ALPHA") == null)
	# una fazione che non ha mai posseduto province ribelli (GAMMA non e' attiva) non riemerge
	var never := _world()
	never.rules.province.reemerge_chance = 1.0
	for i in 3:
		TurnProcessor.end_year(never)
	t.assert_false(never.faction("FN_GAMMA").alive)


func test_riemersione_e_estinzione_sono_coerenti_su_piu_anni(t: TestContext) -> void:
	var s := _world(5)
	s.rules.province = ProvinceRules.new()
	s.rules.province.reemerge_chance = 0.5
	_extinguish_alpha(s)
	for i in 30:
		var res := TurnProcessor.end_year(s)
		t.assert_eq((res["errori"] as Array).size(), 0, "anno %d" % s.year)
		for p in s.provinces:
			var owner_state := s.faction(p.owner)
			t.assert_true(owner_state != null and (owner_state.alive or p.owner == GameState.REBEL), "%s: proprietario non vivo" % p.id)
		for faction in s.factions:
			if not faction.alive or not s.has_dynasty(faction.id):
				continue
			var leaders := 0
			for c in s.characters_of(faction.id):
				if c.role == Character.ROLE_LEADER:
					leaders += 1
			t.assert_eq(leaders, 1, "%s: un solo capo" % faction.id)
		for a in s.armies:
			if a.faction != GameState.REBEL:
				var army_faction := s.faction(a.faction)
				t.assert_true(army_faction != null and army_faction.alive, "esercito %d di una fazione non viva" % a.id)
