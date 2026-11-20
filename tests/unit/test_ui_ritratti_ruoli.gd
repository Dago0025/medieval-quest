extends RefCounted
## Ritratti di agenti, ammiragli e pontefici (ADR-059, Federico 14/11/2026: «applica tutti i ritratti»).

const SERIE := {
	"catholic": {"emissary": 7, "spy": 7, "assassin": 7, "bishop": 6, "cardinal": 4, "priest": 3, "inquisitor": 4,
		"grand_inquisitor": 2, "pope": 15, "admiral": 9},
	"orthodox": {"emissary": 5, "spy": 3, "assassin": 3, "priest": 4, "bishop": 4, "admiral": 4},
	"muslim": {"emissary": 4, "spy": 3, "assassin": 3, "mullah": 4, "ulama": 4, "admiral": 4},
	"pagan": {"emissary": 3, "spy": 3, "assassin": 3, "shaman": 3, "admiral": 3},
}


func _campaign() -> CampaignData:
	var c := CampaignData.new()
	for pair in [["FN_DANISH", "REL_CATHOLIC"], ["FN_ENGLISH", "REL_CATHOLIC"], ["FN_CRUSADERS", "REL_CATHOLIC"],
			["FN_PAPIST", "REL_CATHOLIC"], ["FN_BYZANTINE", "REL_ORTHODOX"], ["FN_EGYPTIAN", "REL_ISLAMIC"],
			["FN_CUMANS", "REL_PAGAN"]]:
		c.add_faction(pair[0]).religion = pair[1]
	return c


func test_le_serie_dei_ruoli(t: TestContext) -> void:
	PortraitArt.reset()
	for rel in SERIE:
		for role in SERIE[rel]:
			t.assert_eq(PortraitArt.series(rel, role).size(), SERIE[rel][role], "%s/%s" % [rel, role])


func test_ritratti_scelti_per_fazione(t: TestContext) -> void:
	PortraitArt.reset()
	for seed in range(1, 60):
		t.assert_eq(PortraitArt.pick_for_faction("catholic", "emissary", "FN_DANISH", seed).get_file(), "01.png", "emissario Auror")
		t.assert_eq(PortraitArt.pick_for_faction("catholic", "emissary", "FN_ENGLISH", seed).get_file(), "02.png", "emissario inglese")
		t.assert_true(PortraitArt.pick_for_faction("catholic", "emissary", "FN_CRUSADERS", seed).get_file() != "01.png", "il ritratto Auror resta agli Auror")
		t.assert_true(PortraitArt.pick_for_faction("catholic", "admiral", "FN_DANISH", seed).get_file() in ["01.png", "02.png"], "ammiragli Auror")
	t.assert_eq(PortraitArt.owners_of("catholic", "emissary", "res://x/05.png"), PackedStringArray(["FN_ITALIAN", "FN_GENOANS", "FN_PAPIST"]))
	t.assert_eq(PortraitArt.owners_of("muslim", "assassin", "res://x/01.png"), PackedStringArray(["*"]), "nizarita per tutti")


func test_agenti_per_tipo_e_religione(t: TestContext) -> void:
	PortraitArt.reset()
	var campaign := _campaign()
	var cases := [["FN_CUMANS", "PRIEST", "pagan/shaman"], ["FN_BYZANTINE", "ORTHODOX_BISHOP", "orthodox/bishop"],
		["FN_EGYPTIAN", "MULLAH", "muslim/mullah"], ["FN_EGYPTIAN", "ULAMA", "muslim/ulama"],
		["FN_ENGLISH", "GRAND_INQUISITOR", "catholic/grand_inquisitor"], ["FN_BYZANTINE", "SPY", "orthodox/spy"],
		["FN_BYZANTINE", "CARDINAL", "catholic/cardinal"]]
	for i in cases.size():
		var a := AgentState.new(i + 1, cases[i][0], "", "", cases[i][1])
		var path := PortraitArt.agent_portrait_path(campaign, a)
		t.assert_true(path.begins_with("res://assets/ritratti/%s/" % cases[i][2]), "%s %s: %s" % [cases[i][0], cases[i][1], path])
	t.assert_eq(PortraitArt.agent_portrait_path(campaign, AgentState.new(9, "FN_ENGLISH", "", "", AgentState.PRINCESS)), "", "le principesse hanno il ritratto del personaggio")
	var tex := PortraitArt.agent_portrait(campaign, AgentState.new(3, "FN_ENGLISH", "", "", AgentState.EMISSARY))
	t.assert_true(tex != null and tex.get_size() == Vector2(384, 568), "ritratto dipinto")


func test_ammiraglio_e_papa(t: TestContext) -> void:
	PortraitArt.reset()
	var campaign := _campaign()
	var fleet := Army.new(7, "FN_EGYPTIAN", "", true)
	t.assert_true(PortraitArt.admiral_portrait_path(campaign, fleet).begins_with("res://assets/ritratti/muslim/admiral/"))
	t.assert_eq(PortraitArt.admiral_portrait_path(campaign, Army.new(8, "FN_EGYPTIAN", "", false)), "", "solo le flotte")
	var pope := Character.new(12)
	pope.faction = "FN_PAPIST"
	pope.role = Character.ROLE_LEADER
	t.assert_true(PortraitArt.portrait_path(campaign, pope).begins_with("res://assets/ritratti/catholic/pope/"), "il Papa")
	var king := Character.new(12)
	king.faction = "FN_ENGLISH"
	king.role = Character.ROLE_LEADER
	t.assert_true(PortraitArt.portrait_path(campaign, king).begins_with("res://assets/ritratti/catholic/king/"), "gli altri re no")
