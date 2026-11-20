extends RefCounted
## Ammiragli al comando delle flotte (richiesta di Federico del 2026-11-13, ADR-056): ogni flotta nasce con un ammiraglio, le
## sue stelle valgono come quelle di comando, sale di stella vincendo le battaglie navali, unendo le flotte resta il migliore,
## gli Auror hanno sempre il massimo. Mondo di prova: sim_startpos.txt (ALPHA con una galea in MARE_NORD).

const STARTPOS := "res://tests/fixtures/sim_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"


func _world() -> GameState:
	var campaign := StartposLoader.load_file(STARTPOS)
	var units := UnitProdLoader.load_file(UNITS)
	var buildings := BuildingProdLoader.load_file(BUILDINGS)
	return GameSetup.new_game(campaign, units, buildings, Rules.new(), 1)


func _fleet(s: GameState, faction_id: String, zone: String, ships: int = 1) -> Army:
	var a := s.create_army(faction_id, zone, true)
	for i in ships:
		a.stacks.append(UnitStack.new("Galley", 1, 0))
	return a


func test_ogni_flotta_nasce_con_un_ammiraglio(t: TestContext) -> void:
	var s := _world()
	var f := _fleet(s, "FN_ALPHA", "ID_MARE_SUD")
	t.assert_false(f.admiral.is_empty(), "la flotta ha un ammiraglio")
	t.assert_true(str(f.admiral["nome"]) != "", "con un nome")
	t.assert_eq(int(f.admiral["stelle"]), 0, "nasce senza stelle")
	t.assert_eq([int(f.admiral["vinte"]), int(f.admiral["perse"])], [0, 0])
	var land := s.create_army("FN_ALPHA", "ID_ALTA", false)
	t.assert_true(land.admiral.is_empty(), "gli eserciti di terra no")
	for a in s.armies:
		if a.is_fleet:
			t.assert_false(a.admiral.is_empty(), "anche le flotte iniziali (%d)" % a.id)


func test_le_stelle_dell_ammiraglio_contano_in_battaglia(t: TestContext) -> void:
	var s := _world()
	var f := _fleet(s, "FN_ALPHA", "ID_MARE_SUD", 2)
	t.assert_eq(Combat.command_stars(s, f), 0)
	var weak := Combat.army_strength(s, f)
	f.admiral["stelle"] = 4
	t.assert_eq(Combat.command_stars(s, f), 4)
	t.assert_true(absf(Combat.army_strength(s, f) - weak * (1.0 + s.rules.combat.star_weight * 4.0)) < 0.001, "come le stelle di un generale")
	f.admiral["stelle"] = 99
	t.assert_eq(Combat.command_stars(s, f), s.rules.combat.admiral_max_stars, "mai oltre il massimo")


func test_gli_auror_hanno_sempre_il_massimo(t: TestContext) -> void:
	var s := _world()
	s.rules.max_admiral_factions = PackedStringArray(["FN_ALPHA"])
	var f := _fleet(s, "FN_ALPHA", "ID_MARE_SUD")
	t.assert_eq(int(f.admiral["stelle"]), s.rules.combat.admiral_max_stars, "nasce al massimo")
	f.admiral["stelle"] = 1
	t.assert_eq(Admirals.stars(s, f), s.rules.combat.admiral_max_stars, "e non scende mai")
	Admirals.ensure(s)
	t.assert_eq(int(f.admiral["stelle"]), s.rules.combat.admiral_max_stars, "riportato al massimo a fine anno")
	t.assert_true(Rules.load_file().max_admiral_factions.has("FN_DANISH"), "auror.cfg: gli Auror")


func test_sale_di_stella_vincendo(t: TestContext) -> void:
	var s := _world()
	var winner := _fleet(s, "FN_ALPHA", "ID_MARE_SUD")
	var loser := _fleet(s, "FN_BETA", "ID_MARE_SUD")
	var first := Admirals.after_battle(s, [winner] as Array[Army], [loser] as Array[Army])
	t.assert_true(first.is_empty(), "una vittoria non basta (vittorie_per_stella 2)")
	var second := Admirals.after_battle(s, [winner] as Array[Army], [loser] as Array[Army])
	t.assert_eq(second.size(), 1)
	t.assert_eq(int(winner.admiral["stelle"]), 1)
	t.assert_eq(int(winner.admiral["vinte"]), 2)
	t.assert_eq(int(loser.admiral["perse"]), 2)


func test_unendo_due_flotte_resta_l_ammiraglio_migliore(t: TestContext) -> void:
	var s := _world()
	var a := _fleet(s, "FN_ALPHA", "ID_MARE_SUD")
	var b := _fleet(s, "FN_ALPHA", "ID_MARE_SUD")
	b.admiral["stelle"] = 3
	var best_name := str(b.admiral["nome"])
	var r := GameCommands.merge_armies(s, "FN_ALPHA", b.id, a.id)
	t.assert_true(bool(r["ok"]), str(r))
	t.assert_eq(str(a.admiral["nome"]), best_name, "comanda chi ha piu' stelle")
	t.assert_eq(int(a.admiral["stelle"]), 3)


func test_salvataggio_e_salvataggi_vecchi(t: TestContext) -> void:
	var s := _world()
	var f := _fleet(s, "FN_ALPHA", "ID_MARE_SUD")
	f.admiral["vinte"] = 5
	var back := Army.from_dict(f.to_dict())
	t.assert_eq(back.admiral, f.admiral, "ammiraglio salvato e riletto")
	var old := f.to_dict()
	old.erase("ammiraglio")
	var bare := Army.from_dict(old)
	t.assert_true(bare.admiral.is_empty())
	s.armies[s.armies.find(f)] = bare
	Admirals.ensure(s)
	t.assert_false(bare.admiral.is_empty(), "le flotte dei salvataggi di prima ricevono un ammiraglio")


func test_la_vittoria_navale_promuove_e_finisce_nel_resoconto(t: TestContext) -> void:
	var s := _world()
	s.rules.combat.forced_outcome = 1   # vince sempre l'attaccante
	s.declare_war("FN_ALPHA", "FN_BETA")
	var attacker := _fleet(s, "FN_ALPHA", "ID_MARE_SUD", 3)
	attacker.admiral["vinte"] = 1
	attacker.arrived_year = s.year
	_fleet(s, "FN_BETA", "ID_MARE_SUD", 1)
	WarProcessor.field_battles(s)
	t.assert_eq(int(attacker.admiral["vinte"]), 2, "una vittoria in piu'")
	t.assert_eq(int(attacker.admiral["stelle"]), 1, "seconda vittoria: una stella")
	var promoted := 0
	for e in s.events:
		if str(e["tipo"]) == GameState.EV_ADMIRAL_PROMOTED:
			promoted += 1
	t.assert_eq(promoted, 1, "evento della promozione")
	var report := "\n".join(CampaignUiText.year_report(s, "FN_ALPHA", {}))
	t.assert_true(report.contains("sale a 1 stella"), report)


func test_righe_della_flotta(t: TestContext) -> void:
	var s := _world()
	var f := _fleet(s, "FN_ALPHA", "ID_MARE_SUD", 2)
	f.admiral["stelle"] = 2
	f.admiral["vinte"] = 4
	f.admiral["perse"] = 1
	var lines := CampaignUiText.admiral_lines(s, f)
	t.assert_eq(lines[0], "Ammiraglio %s con 2 navi" % str(f.admiral["nome"]), "come nell'originale: «Ammiraglio X con N navi»")
	t.assert_eq(lines[1], "Stelle: 2 stelle · battaglie navali vinte 4, perse 1")
	t.assert_eq(CampaignUiText.commander_caption(s, f), "ammiraglio %s ★★" % str(f.admiral["nome"]))
	t.assert_true(CampaignUiText.describe_army(s, f).contains(lines[0]))


## Nave dell'ammiraglio (richiesta di Federico del 2026-11-14, ADR-062): la piu' forte, poi la piu' costosa, poi la prima; il suo
## pennacchio sulla carta della barra; gli Auror sempre a 10 stelle anche nella nota del pennacchio.
func test_la_nave_dell_ammiraglio_e_la_piu_forte(t: TestContext) -> void:
	var s := _world()
	var f := _fleet(s, "FN_ALPHA", "ID_MARE_SUD", 3)
	t.assert_eq(Admirals.flagship(s, f), 0, "navi uguali: la prima")
	var pricey := "Knights"   # nel mondo di prova c'e' una sola nave: per la regola basta un tipo che costi di piu'
	var galley := s.units.get_unit("Galley")
	s.units.get_unit(pricey).ship_attack = galley.ship_attack
	s.units.get_unit(pricey).cost = galley.cost + 100
	f.stacks.insert(2, UnitStack.new(pricey, 1, 0))
	t.assert_eq(Admirals.flagship(s, f), 2, "stesso attacco navale: la piu' costosa")
	s.units.get_unit(pricey).cost = galley.cost - 100
	s.units.get_unit(pricey).ship_attack = galley.ship_attack + 1
	t.assert_eq(Admirals.flagship(s, f), 2, "piu' forte anche se costa meno (la caracca degli Auror)")
	f.stacks.remove_at(2)
	t.assert_eq(Admirals.flagship(s, f), 0, "persa quella, l'ammiraglio passa alla migliore che resta")
	var land := s.create_army("FN_ALPHA", "ID_ALTA", false)
	land.stacks.append(UnitStack.new("Spearmen", 1, 0))
	t.assert_eq(Admirals.flagship(s, land), -1, "gli eserciti di terra non hanno ammiraglio")


func test_pennacchio_della_nave_dell_ammiraglio(t: TestContext) -> void:
	var s := _world()
	s.rules.max_admiral_factions = PackedStringArray(["FN_ALPHA"])
	var f := _fleet(s, "FN_ALPHA", "ID_MARE_SUD", 2)
	var badge := CampaignUiText.commander_badge(s, f, 0)
	t.assert_eq(str(badge.get("immagine", "")), CampaignUiText.ADMIRAL_PENNANT, "pennacchio sulla nave dell'ammiraglio")
	t.assert_true(str(badge.get("nota", "")).contains("★".repeat(s.rules.combat.admiral_max_stars)), "Auror: 10 stelle nella nota")
	t.assert_true(CampaignUiText.commander_badge(s, f, 1).is_empty(), "le altre navi senza pennacchio")
	t.assert_eq(CampaignUiText.card_character(s, f, 0), 0, "la scheda e' quella dell'ammiraglio, non di un personaggio")


func test_il_dipinto_del_pennacchio_dell_ammiraglio(t: TestContext) -> void:
	var tex := OriginalHud.painted_texture("pennacchio_admiral")
	t.assert_true(tex != null, "assets/ui/veste/pennacchio_admiral.png")
	if tex != null:
		t.assert_eq(tex.get_size(), Vector2(112, 248), "come gli altri pennacchi")
