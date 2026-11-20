extends RefCounted
## Test della risoluzione automatica (Combat, BattleResult, CombatRules) sul mondo piccolo
## tests/fixtures/sim_*.txt. Le unita' di quel mondo non hanno statistiche (forza = uomini): per
## provare i termini della formula si aggiungono tipi di unita' con statistiche alla tabella.
## Tutti i valori attesi sono stati verificati con una replica Python delle formule (stesso ordine
## delle operazioni, parametri di data/regole/scontri.cfg):
##   pila 100 uomini (carica 5, mischia 0, difesa -1, armatura 1)      -> 100 x (1 + 0,05 x 4 + 0,05 x 1) = 125
##   con valore 2 (+0,14 x 2) = 153; con morale 4 (+0,02 x 4) = 133
##   nave con attacco 5: 1 x (1 + 0,15 x 5) = 1,75; capo Auror (9 stelle): x (1 + 0,05 x 9) = x 1,45
##   probabilita' Fa^2 / (Fa^2 + Fd^2): 2:1 -> 0,8
##   perdite pari forza: perdente 0,6, vincitore 0,3; 4:1 -> 0,78 e 0,0975; 1:4 -> 0,42 e 0,84
##   2000 contro 1000 x 1,15, vince l'attaccante: 392 e 681 uomini persi; vince il difensore: 1038 e 451

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const EPS := 1.0e-9


func _world(seed_value: int = 1) -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), seed_value)


## Aggiunge alla tabella un tipo di truppa con statistiche.
func _add_unit(s: GameState, id: String, type_name: String, charge: int, melee: int, defence: int, armour: int, moral: int) -> UnitType:
	var u := UnitType.new(id)
	u.type_name = type_name
	u.men = 100
	u.charge_bonus = charge
	u.melee_bonus = melee
	u.defence_bonus = defence
	u.armour_level = armour
	u.moral_bonus = moral
	s.units.add(u)
	return u


## Esercito di prova con una sola pila.
func _army(s: GameState, faction_id: String, region_id: String, unit_id: String, men: int, value: int = 0, fleet: bool = false) -> Army:
	var a := s.create_army(faction_id, region_id, fleet)
	a.stacks.append(UnitStack.new(unit_id, men, value))
	return a


func _list(armies: Array) -> Array[Army]:
	var out: Array[Army] = []
	for item in armies:
		var a: Army = item
		out.append(a)
	return out


func _near(t: TestContext, actual: float, expected: float, message: String) -> void:
	t.assert_true(absf(actual - expected) < EPS, "%s: atteso %s, ottenuto %s" % [message, str(expected), str(actual)])


# --- forza ------------------------------------------------------------------------------------


func test_forza_di_una_pila_di_terra(t: TestContext) -> void:
	var s := _world()
	_add_unit(s, "Prova", UnitType.INFANTRY, 5, 0, -1, 1, 0)
	_near(t, Combat.stack_strength(s, UnitStack.new("Prova", 100, 0)), 125.0, "valore 0")
	_near(t, Combat.stack_strength(s, UnitStack.new("Prova", 100, 2)), 153.0, "valore 2: +0,14 per livello")
	_near(t, Combat.stack_strength(s, UnitStack.new("Prova", 50, 0)), 62.5, "proporzionale agli uomini")
	_add_unit(s, "Morale", UnitType.INFANTRY, 5, 0, -1, 1, 4)
	_near(t, Combat.stack_strength(s, UnitStack.new("Morale", 100, 0)), 133.0, "morale 4: +0,02 per punto")
	_near(t, Combat.stack_strength(s, UnitStack.new("Spearmen", 80, 0)), 80.0, "senza statistiche: uomini x 1")
	_near(t, Combat.stack_strength(s, UnitStack.new("Sconosciuta", 70, 0)), 70.0, "tipo sconosciuto: uomini x 1")


func test_fattore_minimo_della_pila(t: TestContext) -> void:
	var s := _world()
	_add_unit(s, "Debole", UnitType.INFANTRY, -20, 0, 0, 1, 0)   # 1 - 1 + 0,05 = 0,05 -> minimo 0,1
	_near(t, Combat.stack_strength(s, UnitStack.new("Debole", 100, 0)), 10.0, "fattore minimo 0,1")


func test_forza_delle_navi(t: TestContext) -> void:
	var s := _world()
	_near(t, Combat.stack_strength(s, UnitStack.new("Galley", 1, 0)), 1.75, "una galea, attacco navale 5")
	_near(t, Combat.stack_strength(s, UnitStack.new("Galley", 4, 0)), 7.0, "quattro galee")
	_near(t, Combat.stack_strength(s, UnitStack.new("Galley", 4, 3)), 7.0, "il valore non conta per le navi")


func test_forza_dell_esercito_e_stelle_dei_auror(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(s.rules.combat.command_stars("FN_DANISH"), 9, "comando_fisso di auror.cfg")
	t.assert_eq(s.rules.combat.command_stars("FN_ALPHA"), 0)
	_near(t, Combat.army_strength(s, s.army(1)), 160.0, "ALPHA: nessuna stella")
	var danish := _army(s, "FN_DANISH", "ID_ALTA", "Spearmen", 160)
	_near(t, Combat.army_strength(s, danish), 232.0, "160 x (1 + 0,05 x 9)")
	_near(t, Combat.side_strength(s, _list([s.army(1), s.army(3)])), 240.0, "somma degli eserciti")


# --- probabilita' e perdite --------------------------------------------------------------------


func test_probabilita_di_vittoria(t: TestContext) -> void:
	_near(t, Combat.win_probability(100.0, 100.0), 0.5, "pari")
	_near(t, Combat.win_probability(200.0, 100.0), 0.8, "2:1 = 4/5")
	_near(t, Combat.win_probability(100.0, 200.0), 0.2, "1:2")
	_near(t, Combat.win_probability(100.0, 0.0), 1.0, "difensore a zero")
	_near(t, Combat.win_probability(0.0, 100.0), 0.0, "attaccante a zero")
	_near(t, Combat.win_probability(0.0, 0.0), 0.5, "entrambi a zero")


func test_frazioni_di_perdita(t: TestContext) -> void:
	var rules := CombatRules.new()
	var even := Combat.loss_fractions(100.0, 100.0, rules)
	_near(t, even["perdente"], 0.6, "pari: 0,3 + 0,6 x 0,5")
	_near(t, even["vincitore"], 0.3, "pari: 0,6 x 1 x 0,5")
	var strong := Combat.loss_fractions(400.0, 100.0, rules)
	_near(t, strong["perdente"], 0.78, "4:1")
	_near(t, strong["vincitore"], 0.0975, "4:1: 0,78 x 0,25 x 0,5")
	var upset := Combat.loss_fractions(100.0, 400.0, rules)
	_near(t, upset["perdente"], 0.42, "vittoria del piu' debole")
	_near(t, upset["vincitore"], 0.84, "il vincitore debole perde molto")
	var extreme := Combat.loss_fractions(10.0, 1000.0, rules)
	_near(t, extreme["vincitore"], 0.9, "al massimo perdita_max")
	var zero := Combat.loss_fractions(0.0, 0.0, rules)
	_near(t, zero["perdente"], 0.6, "forze nulle: rapporto pari")
	_near(t, zero["vincitore"], 0.0, "forze nulle: il vincitore non perde")


func test_perdite_distribuite_sulle_pile(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, "FN_ALPHA", "ID_ALTA", "Spearmen", 100)
	a.stacks.append(UnitStack.new("Archers", 60, 0))
	var armies := _list([a])
	t.assert_eq(Combat.apply_losses(armies, 0.0), 0)
	t.assert_eq(a.men_total(), 160)
	t.assert_eq(Combat.apply_losses(armies, 0.5), 80)
	t.assert_eq(a.stacks[0].men, 50)
	t.assert_eq(a.stacks[1].men, 30)
	var b := _army(s, "FN_ALPHA", "ID_ALTA", "Spearmen", 100)
	b.stacks.append(UnitStack.new("Archers", 60, 0))
	t.assert_eq(Combat.apply_losses(_list([b]), 0.333), 53, "round(160 x 0,333) = 53, il resto maggiore va ad Archers")
	t.assert_eq(b.stacks[0].men, 67)
	t.assert_eq(b.stacks[1].men, 40)
	t.assert_eq(Combat.apply_losses(_list([b]), 1.0), 107, "frazione 1: annientato")
	t.assert_eq(b.stacks.size(), 0, "le pile vuote spariscono")
	t.assert_eq(Combat.apply_losses(_list([b]), 0.5), 0, "esercito vuoto")


func test_perdite_delle_navi_una_alla_volta(t: TestContext) -> void:
	var s := _world()
	var fleet := s.create_army("FN_ALPHA", "ID_MARE_NORD", true)
	for i in 10:
		fleet.stacks.append(UnitStack.new("Galley", 1, 0))
	t.assert_eq(Combat.apply_losses(_list([fleet]), 0.37), 4, "round(10 x 0,37) = 4 navi")
	t.assert_eq(fleet.stacks.size(), 6, "le prime quattro pile (stesso resto) sono affondate")
	t.assert_eq(fleet.men_total(), 6)


func test_perdite_su_piu_eserciti_conservano_gli_uomini(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, "FN_ALPHA", "ID_ALTA", "Spearmen", 37)
	var b := _army(s, "FN_ALPHA", "ID_ALTA", "Spearmen", 91)
	b.stacks.append(UnitStack.new("Archers", 13, 0))
	var before := 37 + 91 + 13
	for frac: float in [0.07, 0.25, 0.333, 0.61, 0.9]:
		var lost := Combat.apply_losses(_list([a, b]), frac)
		var left := a.men_total() + b.men_total()
		t.assert_eq(before - lost, left, "frazione %s: uomini conservati" % str(frac))
		t.assert_eq(lost, mini(before, roundi(float(before) * frac)), "perdita totale = round(uomini x frazione)")
		before = left
		for army in [a, b]:
			for st in (army as Army).stacks:
				t.assert_true(st.men >= 1, "nessuna pila vuota")


# --- risoluzione -------------------------------------------------------------------------------


func test_risoluzione_con_esito_forzato_e_perdite(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.rules.combat.valour_chance = 0.0
	var attackers := _army(s, "FN_ALPHA", "ID_MEZZA", "Spearmen", 2000)
	var defenders := _army(s, "FN_BETA", "ID_MEZZA", "Nizari", 1000)
	var r := Combat.resolve(s, "ID_MEZZA", _list([attackers]), _list([defenders]), BattleResult.KIND_FIELD, Combat.defender_multiplier(s, BattleResult.KIND_FIELD, 0))
	t.assert_true(r.attacker_won)
	t.assert_eq(r.winner_faction(), "FN_ALPHA")
	t.assert_eq(r.loser_faction(), "FN_BETA")
	_near(t, r.attacker_strength, 2000.0, "forza attaccante")
	_near(t, r.defender_base_strength, 1000.0, "forza difensore senza bonus")
	_near(t, r.defender_strength, 1150.0, "forza difensore con il bonus 1,15")
	_near(t, r.attacker_win_probability, 4000000.0 / (4000000.0 + 1322500.0), "Fa^2 / (Fa^2 + Fd^2)")
	t.assert_eq(r.attacker_losses, 392, "vincitore: 2000 x 0,19577")
	t.assert_eq(r.defender_losses, 681, "perdente: 1000 x 0,68095")
	t.assert_eq(attackers.men_total(), 1608)
	t.assert_eq(defenders.men_total(), 319)
	t.assert_eq(r.losses_of("FN_ALPHA"), 392)
	t.assert_eq(r.losses_of("FN_BETA"), 681)
	t.assert_eq(r.losses_of("FN_GAMMA"), 0)
	t.assert_false(r.to_dict().has("tipo"), "la chiave tipo e' riservata all'evento")
	# stesso scontro, vince il difensore
	var s2 := _world()
	s2.rules.combat.forced_outcome = -1
	var a2 := _army(s2, "FN_ALPHA", "ID_MEZZA", "Spearmen", 2000)
	var d2 := _army(s2, "FN_BETA", "ID_MEZZA", "Nizari", 1000)
	var r2 := Combat.resolve(s2, "ID_MEZZA", _list([a2]), _list([d2]), BattleResult.KIND_FIELD, 1.15)
	t.assert_false(r2.attacker_won)
	t.assert_eq(r2.attacker_losses, 1038, "perdente: 2000 x 0,51905")
	t.assert_eq(r2.defender_losses, 451, "vincitore: 1000 x 0,45135")
	t.assert_eq(a2.men_total(), 962)
	t.assert_eq(d2.men_total(), 549)


func test_rapporti_di_forza_estremi_hanno_un_esito_certo(t: TestContext) -> void:
	var s := _world()
	var strong := _army(s, "FN_ALPHA", "ID_MEZZA", "Spearmen", 5000000)
	var weak := _army(s, "FN_BETA", "ID_MEZZA", "Nizari", 1)
	var r := Combat.resolve(s, "ID_MEZZA", _list([strong]), _list([weak]), BattleResult.KIND_FIELD, 1.15)
	t.assert_true(r.attacker_win_probability > 0.99999999)
	t.assert_true(r.attacker_won, "il piu' forte vince")
	t.assert_true(weak.stacks.is_empty(), "un uomo con perdita del 90%: annientato")
	t.assert_false(s.armies.has(weak), "l'esercito vuoto esce dallo stato")
	t.assert_true(s.armies.has(strong))
	var s2 := _world()
	var small := _army(s2, "FN_ALPHA", "ID_MEZZA", "Spearmen", 1)
	var big := _army(s2, "FN_BETA", "ID_MEZZA", "Nizari", 5000000)
	var r2 := Combat.resolve(s2, "ID_MEZZA", _list([small]), _list([big]), BattleResult.KIND_FIELD, 1.15)
	t.assert_false(r2.attacker_won, "il difensore molto piu' forte vince")
	t.assert_false(s2.armies.has(small))


func test_il_moltiplicatore_del_castello_entra_nella_forza(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = -1
	var besiegers := _army(s, "FN_ALPHA", "ID_MEZZA", "Spearmen", 100)
	var garrison := _army(s, "FN_BETA", "ID_MEZZA", "Nizari", 60)
	var mult := Combat.defender_multiplier(s, BattleResult.KIND_ASSAULT, 7)
	_near(t, mult, 2.5, "Castle (livelli 7-9)")
	var r := Combat.resolve(s, "ID_MEZZA", _list([besiegers]), _list([garrison]), BattleResult.KIND_ASSAULT, mult)
	_near(t, r.defender_strength, 150.0, "60 x 2,5")
	_near(t, r.defender_multiplier, 2.5, "moltiplicatore registrato")
	t.assert_eq(r.kind, "assalto")


func test_guarnigione_sconfitta_e_annientata(t: TestContext) -> void:
	# assalto vinto (assalto_annienta) e sortita persa: la guarnigione perde il 100%
	var s := _world()
	s.rules.combat.forced_outcome = 1
	var besiegers := _army(s, "FN_ALPHA", "ID_MEZZA", "Spearmen", 100)
	var garrison := _army(s, "FN_BETA", "ID_MEZZA", "Nizari", 60)
	var r := Combat.resolve(s, "ID_MEZZA", _list([besiegers]), _list([garrison]), BattleResult.KIND_ASSAULT, 1.5)
	t.assert_eq(r.defender_losses, 60)
	t.assert_false(s.armies.has(garrison))
	var s2 := _world()
	s2.rules.combat.forced_outcome = -1
	var b2 := _army(s2, "FN_ALPHA", "ID_MEZZA", "Spearmen", 100)
	var g2 := _army(s2, "FN_BETA", "ID_MEZZA", "Nizari", 200)
	var sally := Combat.resolve(s2, "ID_MEZZA", _list([g2]), _list([b2]), BattleResult.KIND_SALLY, 1.15)
	t.assert_false(sally.attacker_won, "la guarnigione e' l'attaccante della sortita")
	t.assert_eq(sally.attacker_losses, 200)
	t.assert_false(s2.armies.has(g2))
	t.assert_true(s2.armies.has(b2))
	# con assalto_annienta = false la guarnigione perde solo la frazione normale
	var s3 := _world()
	s3.rules.combat.forced_outcome = 1
	s3.rules.combat.assault_annihilates = false
	var b3 := _army(s3, "FN_ALPHA", "ID_MEZZA", "Spearmen", 100)
	var g3 := _army(s3, "FN_BETA", "ID_MEZZA", "Nizari", 60)
	var r3 := Combat.resolve(s3, "ID_MEZZA", _list([b3]), _list([g3]), BattleResult.KIND_ASSAULT, 1.5)
	t.assert_true(r3.defender_losses < 60 and r3.defender_losses > 0)


func test_il_valore_cresce_solo_per_i_vincitori_sopravvissuti(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1
	s.rules.combat.valour_chance = 1.0
	var winners := _army(s, "FN_ALPHA", "ID_MEZZA", "Spearmen", 1000, 3)
	winners.stacks.append(UnitStack.new("Archers", 500, 9))
	var losers := _army(s, "FN_BETA", "ID_MEZZA", "Nizari", 400, 1)
	Combat.resolve(s, "ID_MEZZA", _list([winners]), _list([losers]), BattleResult.KIND_FIELD, 1.15)
	t.assert_eq(winners.stacks[0].value, 4, "+1 con probabilita' 1")
	t.assert_eq(winners.stacks[1].value, 9, "il massimo e' 9")
	t.assert_eq(losers.stacks[0].value, 1, "chi perde non guadagna valore")
	var s2 := _world()
	s2.rules.combat.forced_outcome = 1
	s2.rules.combat.valour_chance = 0.0
	var w2 := _army(s2, "FN_ALPHA", "ID_MEZZA", "Spearmen", 1000, 3)
	var l2 := _army(s2, "FN_BETA", "ID_MEZZA", "Nizari", 400)
	Combat.resolve(s2, "ID_MEZZA", _list([w2]), _list([l2]), BattleResult.KIND_FIELD, 1.15)
	t.assert_eq(w2.stacks[0].value, 3, "probabilita' 0: nessun guadagno")


func test_ordine_dei_numeri_casuali(t: TestContext) -> void:
	# un tiro per l'esito + un tiro per ogni pila sopravvissuta del vincitore
	var s := _world(777)
	s.rules.combat.forced_outcome = 1
	var winners := _army(s, "FN_ALPHA", "ID_MEZZA", "Spearmen", 1000)
	winners.stacks.append(UnitStack.new("Archers", 500, 0))
	var losers := _army(s, "FN_BETA", "ID_MEZZA", "Nizari", 400)
	var r := Combat.resolve(s, "ID_MEZZA", _list([winners]), _list([losers]), BattleResult.KIND_FIELD, 1.15)
	var mirror := RandomNumberGenerator.new()
	mirror.seed = 777
	t.assert_eq(r.roll, mirror.randf(), "il primo numero e' il tiro dell'esito")
	mirror.randf()
	mirror.randf()
	t.assert_eq(s.rng.state, mirror.state, "in tutto 3 numeri: esito + 2 pile")
	# stesso seme, stessa battaglia: stesso esito e stesso stato del generatore
	var s2 := _world(777)
	var w2 := _army(s2, "FN_ALPHA", "ID_MEZZA", "Spearmen", 1000)
	w2.stacks.append(UnitStack.new("Archers", 500, 0))
	var l2 := _army(s2, "FN_BETA", "ID_MEZZA", "Nizari", 400)
	s2.rules.combat.forced_outcome = 1
	var r2 := Combat.resolve(s2, "ID_MEZZA", _list([w2]), _list([l2]), BattleResult.KIND_FIELD, 1.15)
	t.assert_eq(r2.roll, r.roll)
	t.assert_eq(s2.rng.state, s.rng.state)
	t.assert_eq(w2.stacks[0].value, winners.stacks[0].value)
	t.assert_eq(w2.stacks[1].value, winners.stacks[1].value)


func test_moltiplicatori_e_gradi_del_castello(t: TestContext) -> void:
	var s := _world()
	var c := s.rules.combat
	t.assert_eq(c.castle_tier(0), -1, "senza castello")
	t.assert_eq(c.castle_tier(1), 0)
	t.assert_eq(c.castle_tier(3), 0, "Fort: livelli 1-3")
	t.assert_eq(c.castle_tier(4), 1, "Keep: 4-6")
	t.assert_eq(c.castle_tier(7), 2, "Castle: 7-9")
	t.assert_eq(c.castle_tier(10), 3, "Citadel: 10-12")
	t.assert_eq(c.castle_tier(13), 4, "Fortress: 13-15")
	t.assert_eq(c.castle_tier(99), 4, "oltre la tabella: l'ultimo grado")
	var expected_mult := {0: 1.0, 1: 1.5, 3: 1.5, 4: 2.0, 7: 2.5, 10: 3.0, 13: 4.0, 15: 4.0, 99: 4.0}
	for level in expected_mult:
		_near(t, Combat.defender_multiplier(s, BattleResult.KIND_ASSAULT, int(level)), float(expected_mult[level]), "assalto, castello %d" % int(level))
	var expected_years := {0: 0, 1: 1, 4: 2, 7: 3, 10: 4, 13: 5, 15: 5}
	for level in expected_years:
		t.assert_eq(c.starve_after(int(level)), int(expected_years[level]), "anni di fame, castello %d" % int(level))
	_near(t, Combat.defender_multiplier(s, BattleResult.KIND_FIELD, 7), 1.15, "campo: bonus del difensore")
	_near(t, Combat.defender_multiplier(s, BattleResult.KIND_SALLY, 7), 1.15, "sortita: bonus del difensore")
	_near(t, Combat.defender_multiplier(s, BattleResult.KIND_NAVAL, 7), 1.0, "mare: nessun bonus")
	t.assert_eq(Combat.castle_level(s, "ID_ALTA"), 3)
	t.assert_eq(Combat.castle_level(s, "ID_SOLA"), 0, "senza castello")
	t.assert_eq(Combat.castle_level(s, "ID_MARE_NORD"), 0, "il mare non ha castelli")


func test_peso_della_guarnigione_con_la_cavalleria(t: TestContext) -> void:
	var s := _world()
	var a := _army(s, "FN_BETA", "ID_MEZZA", "Nizari", 60)
	a.stacks.append(UnitStack.new("Knights", 40, 0))
	a.stacks.append(UnitStack.new("Knights", 40, 0))
	t.assert_eq(Combat.garrison_weight(s, a), 5, "una pila di fanteria + due di cavalleria (2 + 2)")
	t.assert_eq(Combat.garrison_load(s, "ID_MEZZA"), 0, "nessuno nel castello")
	a.in_castle = true
	t.assert_eq(Combat.garrison_load(s, "ID_MEZZA"), 5, "solo gli eserciti nel castello contano")
	s.army(4).in_castle = true
	t.assert_eq(Combat.garrison_load(s, "ID_MEZZA"), 6, "guarnigione di 5 + esercito 4 di peso 1")
	t.assert_eq(Combat.years_to_starve(s, SiegeState.new("ID_MEZZA", "FN_ALPHA", 0)), 1, "Castle2: 1 anno")
	t.assert_eq(Combat.years_to_starve(s, SiegeState.new("ID_MEZZA", "FN_ALPHA", 5)), 0, "mai negativo")


# --- regole da file ---------------------------------------------------------------------------


func test_regole_degli_scontri_predefinite_uguali_al_file(t: TestContext) -> void:
	var from_file := CombatRules.load_file()
	t.assert_eq(from_file.errors, PackedStringArray(), "errori di lettura di scontri.cfg e auror.cfg")
	t.assert_eq(from_file.to_dict(), CombatRules.new().to_dict(), "il file e i valori predefiniti devono coincidere")
	var rules := Rules.load_file()
	t.assert_eq(rules.errors, PackedStringArray())
	t.assert_eq(rules.combat.to_dict(), CombatRules.new().to_dict(), "Rules espone le regole degli scontri")
	t.assert_eq(rules.to_dict(), Rules.new().to_dict(), "Rules.to_dict comprende gli scontri")


func test_regole_degli_scontri_valori_iniziali(t: TestContext) -> void:
	var c := CombatRules.new()
	_near(t, c.attack_weight, 0.05, "a")
	_near(t, c.armour_weight, 0.05, "b")
	_near(t, c.valour_weight, 0.14, "c = 2a + 2d")
	_near(t, c.morale_weight, 0.02, "d")
	_near(t, c.naval_weight, 0.15, "e")
	_near(t, c.star_weight, 0.05, "f = a")
	_near(t, c.defender_bonus, 0.15, "g")
	_near(t, c.sally_threshold, 2.0, "soglia della sortita")
	_near(t, c.loss_min, 0.30, "perdita minima")
	_near(t, c.loss_max, 0.90, "perdita massima")
	_near(t, c.winner_loss_factor, 0.5, "fattore del vincitore")
	t.assert_eq(c.garrison_max, 16)
	t.assert_eq(c.cavalry_garrison_weight, 2)
	t.assert_eq(c.forced_outcome, 0, "in produzione l'esito non e' forzato")
	t.assert_eq(Array(c.starve_years), [1, 2, 3, 4, 5])
	t.assert_eq(Array(c.castle_multipliers), [1.5, 2.0, 2.5, 3.0, 4.0])


func test_regole_degli_scontri_file_mancante_e_parziale(t: TestContext) -> void:
	var missing := CombatRules.load_file("res://data/regole/non_esiste.cfg")
	t.assert_eq(missing.errors.size(), 1, "un errore di lettura")
	_near(t, missing.defender_bonus, 0.15, "valori predefiniti")
	var path := "user://test_sim_scontri.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("campo", "bonus_difensore", 0.4)
	cfg.set_value("castello", "anni_fame", [2, 4])
	cfg.set_value("castello", "famiglia", "keep")
	cfg.set_value("prova", "esito_forzato", 1)
	t.assert_eq(cfg.save(path), OK, "scrittura del file di prova")
	var partial := CombatRules.load_file(path, "")
	DirAccess.remove_absolute(path)
	t.assert_eq(partial.errors, PackedStringArray())
	_near(t, partial.defender_bonus, 0.4, "chiave letta")
	_near(t, partial.attack_weight, 0.05, "chiave assente = valore predefinito")
	t.assert_eq(partial.castle_family, "KEEP", "maiuscolo")
	t.assert_eq(partial.forced_outcome, 1)
	t.assert_eq(partial.starve_after(1), 2)
	t.assert_eq(partial.starve_after(13), 4, "oltre la tabella: l'ultimo valore")
	var bad_path := "user://test_sim_scontri2.cfg"
	var bad := ConfigFile.new()
	bad.set_value("perdite", "perdita_min", 0.95)
	bad.set_value("castello", "moltiplicatore_assalto", [])
	t.assert_eq(bad.save(bad_path), OK)
	var checked := CombatRules.load_file(bad_path, "")
	DirAccess.remove_absolute(bad_path)
	t.assert_eq(checked.errors.size(), 2, "perdite incoerenti e tabella vuota")
	_near(t, checked.loss_min, 0.30, "ripristinato")
	t.assert_eq(checked.castle_multipliers.size(), 5)
