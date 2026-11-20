extends RefCounted
## Test dell'interfaccia delle cariche di Stato (manuale p25): elenco per la corte, cariche della provincia, candidati,
## testo degli eventi e nota della pila del comandante. Mondo di prova: tests/fixtures/dynasty_*.txt (ALPHA ha una carica
## sul Castello, «Gran Maresciallo», +1 lealta' e +2 comando; Castle3 in ALTA, Castle in BASSA).

const STARTPOS := "res://tests/fixtures/dynasty_startpos.txt"
const UNITS := "res://tests/fixtures/sim_unit_prod.txt"
const BUILDINGS := "res://tests/fixtures/sim_build_prod.txt"
const HEROES := "res://tests/fixtures/dynasty_heroes.txt"


func _world() -> GameState:
	return GameSetup.new_game(StartposLoader.load_file(STARTPOS), UnitProdLoader.load_file(UNITS), BuildingProdLoader.load_file(BUILDINGS), Rules.new(), 7, HeroesLoader.load_file(HEROES))


func test_bonus_in_parole(t: TestContext) -> void:
	var s := _world()
	var def := s.campaign.office_for("FN_ALPHA", "castle")
	t.assert_eq(CampaignUiText.office_bonus_text(def), "comando +2 · lealtà +1")
	t.assert_eq(CampaignUiText.office_bonus_text(null), "")


func test_elenco_delle_cariche_per_la_corte(t: TestContext) -> void:
	var s := _world()
	var o := CampaignData.OfficeDef.new()
	o.faction = "FN_ALPHA"
	o.building = "admiralty"
	o.display_name = "Admiral of the Fleet"
	s.campaign.offices.append(o)
	var rows := CampaignUiText.office_rows(s, "FN_ALPHA")
	t.assert_eq(rows.size(), 2)
	t.assert_eq(rows[0]["edificio"], "castle")
	t.assert_eq(rows[0]["provincia"], "ID_ALTA")
	t.assert_true(int(rows[0]["titolare"]) > 0, "carica iniziale assegnata")
	t.assert_eq(rows[1]["nome"], "Ammiraglio della Flotta", "nome tradotto da data/cariche.cfg")
	t.assert_eq(rows[1]["provincia"], "", "ammiragliato da costruire")
	t.assert_eq(rows[1]["serve"], "Ammiragliato")
	t.assert_eq(int(rows[1]["titolare"]), 0)
	t.assert_eq(CampaignUiText.office_rows(s, "FN_BETA").size(), 0)


func test_cariche_della_provincia_e_candidati(t: TestContext) -> void:
	var s := _world()
	t.assert_eq(CampaignUiText.offices_seated_in(s, s.province("ID_ALTA")).size(), 1)
	t.assert_eq(CampaignUiText.offices_seated_in(s, s.province("ID_BASSA")).size(), 0, "la sede e' il castello piu' alto")
	var holder := DynastyProcessor.office_holder(s, "FN_ALPHA", "castle")
	for c in CampaignUiText.eligible_officers(s, "FN_ALPHA", "castle"):
		t.assert_true(c != holder, "chi la detiene non e' tra i candidati")
		t.assert_true(c.role != Character.ROLE_LEADER and c.role != Character.ROLE_PRINCESS)
	t.assert_true(CampaignUiText.office_option_text(s, holder).contains("lascia:"), CampaignUiText.office_option_text(s, holder))


## Richiesta di Federico del 20/11/2026: sala del consiglio con il re al centro e le cariche ai lati, le prime accanto al trono.
func test_sala_del_consiglio(t: TestContext) -> void:
	var s := _world()
	for b in ["admiralty", "chancellery", "cathedral"]:
		var o := CampaignData.OfficeDef.new()
		o.faction = "FN_ALPHA"
		o.building = b
		o.display_name = b
		s.campaign.offices.append(o)
	var hall := CampaignUiText.council_seats(s, "FN_ALPHA")
	t.assert_eq(int(hall["capo"]), s.leader_of("FN_ALPHA").id, "il re al centro")
	var left: Array = hall["sinistra"]
	var right: Array = hall["destra"]
	t.assert_eq(left.size(), 2)
	t.assert_eq(right.size(), 2)
	t.assert_eq(str(left[1]["edificio"]), "castle", "la prima carica accanto al trono, a sinistra")
	t.assert_eq(int(left[1]["vicinanza"]), 1)
	t.assert_eq(str(right[0]["edificio"]), "admiralty", "la seconda accanto al trono, a destra")
	t.assert_eq(str(left[0]["edificio"]), "chancellery", "la terza all'esterno a sinistra")
	t.assert_eq(int(left[0]["vicinanza"]), 2)
	t.assert_eq(str(right[1]["edificio"]), "cathedral")
	t.assert_true(int(left[1]["titolare"]) > 0, "il titolare iniziale della carica del castello")
	var empty := CampaignUiText.council_seats(s, "FN_BETA")
	t.assert_true((empty["sinistra"] as Array).is_empty() and (empty["destra"] as Array).is_empty())


func _general(s: GameState, region: String, forename: String) -> Character:
	var c := s.create_character("FN_ALPHA")
	c.role = Character.ROLE_GENERAL
	c.forename = forename
	c.birth_year = 960
	c.loyalty = 6
	c.region = region
	return c


## Richiesta di Federico del 20/11/2026: anche per le cariche prima i presenti nella provincia, in blu chi ne ha gia' una.
func test_scelte_della_carica_prima_i_presenti(t: TestContext) -> void:
	var s := _world()
	var here := _general(s, "ID_ALTA", "Presente")
	var busy := _general(s, "ID_ALTA", "Occupato")
	busy.office = "admiralty"
	var away := _general(s, "ID_BASSA", "Lontano")
	var choices := CampaignUiText.office_choices(s, "FN_ALPHA", "castle", "ID_ALTA")
	var ids: Array = []
	for ch in choices:
		ids.append((ch["personaggio"] as Character).id)
	t.assert_eq(ids.size(), CampaignUiText.eligible_officers(s, "FN_ALPHA", "castle").size(), "tutti gli idonei")
	t.assert_true(ids.find(here.id) < ids.find(busy.id), "chi e' libero prima di chi ha gia' una carica")
	t.assert_true(bool(choices[ids.find(busy.id)]["titolato"]) and not bool(choices[ids.find(here.id)]["titolato"]))
	t.assert_true(str(choices[ids.find(here.id)]["testo"]).begins_with(here.full_name()))
	var last_here := -1
	var first_away := ids.size()
	for i in choices.size():
		if bool(choices[i]["qui"]):
			last_here = i
		else:
			first_away = mini(first_away, i)
	t.assert_false(bool(choices[ids.find(away.id)]["qui"]))
	t.assert_true(last_here < first_away, "prima tutti i presenti, poi chi sta altrove")


func test_testo_degli_eventi_della_carica(t: TestContext) -> void:
	var s := _world()
	var holder := DynastyProcessor.office_holder(s, "FN_ALPHA", "castle")
	GameCommands.revoke_office(s, "FN_ALPHA", holder.id)
	var found := false
	for e in s.events:
		if str(e["tipo"]) == GameState.EV_OFFICE_CHANGED:
			var text := CampaignUiText.format_event(s, e)
			t.assert_true(text.contains("revocata") and text.contains(holder.full_name()), text)
			found = true
	t.assert_true(found)


func test_la_nota_della_pila_nomina_la_carica(t: TestContext) -> void:
	var s := _world()
	var holder := DynastyProcessor.office_holder(s, "FN_ALPHA", "castle")
	var a := s.create_army("FN_ALPHA", "ID_ALTA", false)
	a.stacks.append(UnitStack.new("Spearmen", 60, 0))
	holder.army = a.id
	var note := CampaignUiText.commander_stack_note(s, a)
	t.assert_true(note.begins_with("Unità del") and note.contains(CampaignUiText.office_name(s, holder)), note)
