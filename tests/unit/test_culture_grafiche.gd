extends RefCounted
## Culture grafiche proprie (ADR-125, 22/11/2026): Aztechi, Inca e Kanem hanno pedine e figure degli agenti loro
## (campmap/pieces/.../Aztec|Inca|African), con ritorno alla cultura della religione per le figure che mancano.

const STATI := ["awaiting", "moving"]
const PEDINE := {
	"Aztec": ["shaman"],
	"Inca": ["shaman"],
	"African": ["mullah", "ulama"],
}
## Mississippiani (ADR-126) e Chola/Khmer (ADR-127): eserciti, capi e flotte propri. Le figure degli agenti sono tutte
## proprie: mississippiane dall'ADR-126, indiane e khmer (col monaco al posto dello sciamano) dall'ADR-130.
const SOLO_ARMATE := ["Mississippian", "Indian", "Khmer"]
const AGENTI_PROPRI := {
	"Mississippian": ["assassin", "emissary", "spy", "shaman", "princess"],
	"Indian": ["assassin", "emissary", "spy", "monk", "princess"],
	"Khmer": ["assassin", "emissary", "spy", "monk", "princess"],
}
## Carte degli agenti per cultura propria (ADR-126 Kanem e Mississippiani, ADR-130 Chola, Khmer, Aztechi e Inca).
const CARTE_AGENTI := {
	"African": ["mullah"], "Mississippian": ["shaman"], "Indian": ["monk"], "Khmer": ["monk"],
	"Aztec": ["shaman"], "Inca": ["shaman"],
}


func test_culture_proprie(t: TestContext) -> void:
	PieceArt.reset()
	t.assert_eq(PieceArt.own_culture("FN_AZTECS"), "Aztec")
	t.assert_eq(PieceArt.own_culture("fn_inca"), "Inca", "l'id non distingue maiuscole e minuscole")
	t.assert_eq(PieceArt.own_culture("FN_KANEM"), "African")
	t.assert_eq(PieceArt.own_culture("FN_MISSISSIPPIANS"), "Mississippian")
	t.assert_eq(PieceArt.own_culture("FN_CHOLA"), "Indian")
	t.assert_eq(PieceArt.own_culture("FN_KHMER"), "Khmer")
	t.assert_eq(PieceArt.own_culture("FN_ENGLISH"), "", "le fazioni storiche usano la cultura della religione")


func test_cultura_della_fazione(t: TestContext) -> void:
	PieceArt.reset()
	var f := CampaignData.Faction.new("FN_KANEM", 0)
	f.religion = "REL_MUSLIM"
	t.assert_eq(PieceArt.faction_culture(f), "African")
	f.id = "FN_EGYPTIAN"
	t.assert_eq(PieceArt.faction_culture(f), "Muslim", "senza cultura propria: quella della religione")
	t.assert_eq(PieceArt.faction_culture(null), "Christian")


func test_pedine_rifatte(t: TestContext) -> void:
	var base := PieceArt.BASE
	for culture in PEDINE:
		for state in STATI:
			for p in ["Units/%s/army_held_%s", "Units/%s/army_leader_held_%s", "Ships/%s/fleet_held_%s"]:
				var original: String = "%s/%s.BIF" % [base, p % [culture, state]]
				t.assert_true(AssetLibrary.is_remade(original), "pedina rifatta: " + original)
			var agents: Array = ["assassin", "emissary", "spy", "princess"] + PEDINE[culture]
			for a in agents:
				var original := "%s/Agents/%s/%s_held_%s.BIF" % [base, culture, a, state]
				t.assert_true(AssetLibrary.is_remade(original), "figura rifatta: " + original)
	for culture in SOLO_ARMATE:
		for state in STATI:
			for p in ["Units/%s/army_held_%s", "Units/%s/army_leader_held_%s", "Ships/%s/fleet_held_%s"]:
				var original: String = "%s/%s.BIF" % [base, p % [culture, state]]
				t.assert_true(AssetLibrary.is_remade(original), "pedina rifatta: " + original)
	for culture in AGENTI_PROPRI:
		for state in STATI:
			for a in AGENTI_PROPRI[culture]:
				var original := "%s/Agents/%s/%s_held_%s.BIF" % [base, culture, a, state]
				t.assert_true(AssetLibrary.is_remade(original), "figura propria: " + original)


func test_carte_degli_agenti_per_cultura_propria(t: TestContext) -> void:
	for culture in CARTE_AGENTI:
		for a in ["emissary", "spy", "assassin", "princess"] + CARTE_AGENTI[culture]:
			t.assert_true(AssetLibrary.is_remade("campmap/review_panel/Agents/%s/%s.BIF" % [culture, a]), "carta %s %s" % [culture, a])
