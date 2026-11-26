extends RefCounted
## Ritratti per cultura delle fazioni nuove della mappa del mondo (ADR-087, Federico 16/11/2026: «produzione e
## applicazione dei ritratti delle nuove fazioni»). Serie in assets/ritratti/<cultura>/<ruolo>/, fazioni -> cultura in
## data/ritratti_culture.cfg; la serie della cultura viene prima di quella della religione.

const SERIE := {
	"japanese": {"king": 12, "general": 12, "prince": 8, "princess": 8, "emissary": 1, "spy": 1, "assassin": 1,
		"religious": 2, "admiral": 2},
	"chinese": {"king": 12, "general": 12, "prince": 8, "princess": 8, "emissary": 1, "spy": 1, "assassin": 1,
		"religious": 2, "admiral": 2},
	"aztec": {"king": 10, "general": 10, "prince": 6, "princess": 6, "emissary": 1, "spy": 1, "assassin": 1,
		"religious": 1, "admiral": 1},
	"inca": {"king": 10, "general": 10, "prince": 6, "princess": 6, "emissary": 1, "spy": 1, "assassin": 1,
		"religious": 1, "admiral": 1},
	"kanem": {"king": 10, "general": 10, "prince": 6, "princess": 6, "emissary": 1, "spy": 1, "assassin": 1,
		"religious": 1, "admiral": 1},
	"mississippian": {"king": 10, "general": 10, "prince": 6, "princess": 6, "emissary": 1, "spy": 1, "assassin": 1,
		"religious": 1, "admiral": 1},
	"korean": {"king": 4, "general": 4, "prince": 3, "princess": 3, "emissary": 1, "spy": 1, "assassin": 1,
		"religious": 1, "admiral": 1},
	"mongol": {"king": 4, "general": 4, "prince": 3, "princess": 3, "emissary": 1, "spy": 1, "assassin": 1,
		"religious": 2, "admiral": 1},
	"indian": {"king": 4, "general": 4, "prince": 3, "princess": 4, "emissary": 1, "spy": 1, "assassin": 1,
		"religious": 1, "admiral": 1},
	"southeast_asian": {"king": 4, "general": 4, "prince": 3, "princess": 4, "emissary": 1, "spy": 1,
		"assassin": 1, "religious": 1, "admiral": 1},
}

const FAZIONI := {
	"FN_JAPANESE": ["japanese", "REL_PAGAN"], "FN_CHINESE": ["chinese", "REL_PAGAN"], "FN_AZTECS": ["aztec", "REL_PAGAN"],
	"FN_INCA": ["inca", "REL_PAGAN"], "FN_KANEM": ["kanem", "REL_ISLAMIC"],
	"FN_MISSISSIPPIANS": ["mississippian", "REL_PAGAN"],
}

## ADR-088: fazioni create per usare le serie asiatiche (agenti e principesse, i Coreani anche l'ammiraglio). Re,
## generali e principi restano alla serie della religione finche' i set dei reali non sono completati: Coreani e
## Mongoli li hanno dal 22/11/2026, Chola e Khmer dal 23/11/2026 (REALI_ASIATICI).
const REALI_ASIATICI := ["korean", "mongol", "indian", "southeast_asian"]
const ASIATICHE := {"FN_KOREANS": "korean", "FN_MONGOLS": "mongol", "FN_GOLDEN_HORDE": "mongol", "FN_CHOLA": "indian",
	"FN_KHMER": "southeast_asian"}

const RUOLI := {"king": Character.ROLE_LEADER, "general": Character.ROLE_GENERAL, "prince": Character.ROLE_PRINCE,
	"princess": Character.ROLE_PRINCESS}


func _campaign() -> CampaignData:
	var c := CampaignData.new()
	for fid in FAZIONI:
		c.add_faction(fid).religion = FAZIONI[fid][1]
	for fid in ASIATICHE:
		c.add_faction(fid).religion = "REL_PAGAN"
	c.add_faction("FN_ENGLISH").religion = "REL_CATHOLIC"
	c.add_faction("FN_CUMANS").religion = "REL_PAGAN"
	return c


func test_le_serie_per_cultura(t: TestContext) -> void:
	PortraitArt.reset()
	for cult in SERIE:
		for role in SERIE[cult]:
			t.assert_eq(PortraitArt.series(cult, role).size(), SERIE[cult][role], "%s/%s" % [cult, role])


func test_la_cultura_di_ogni_fazione_nuova(t: TestContext) -> void:
	PortraitArt.reset()
	for fid in FAZIONI:
		t.assert_eq(PortraitArt.culture_of(fid), FAZIONI[fid][0], fid)
	t.assert_eq(PortraitArt.culture_of("FN_ENGLISH"), "", "le fazioni dell'originale restano alla religione")


func test_i_personaggi_pescano_dalla_loro_cultura(t: TestContext) -> void:
	PortraitArt.reset()
	var campaign := _campaign()
	for fid in FAZIONI:
		var cult: String = FAZIONI[fid][0]
		for role in RUOLI:
			var seen := {}
			for id in range(1, 200):
				var c := Character.new(id)
				c.faction = fid
				c.role = RUOLI[role]
				var path := PortraitArt.portrait_path(campaign, c)
				t.assert_true(path.begins_with("res://assets/ritratti/%s/%s/" % [cult, role]), "%s %s %d: %s" % [fid, role, id, path])
				seen[path] = true
			t.assert_eq(seen.size(), SERIE[cult][role], "%s/%s: escono tutti" % [cult, role])


func test_le_fazioni_dell_originale_non_cambiano(t: TestContext) -> void:
	PortraitArt.reset()
	var campaign := _campaign()
	var c := Character.new(7)
	c.faction = "FN_CUMANS"
	c.role = Character.ROLE_LEADER
	t.assert_true(PortraitArt.portrait_path(campaign, c).begins_with("res://assets/ritratti/pagan/king/"))
	c.faction = "FN_ENGLISH"
	t.assert_true(PortraitArt.portrait_path(campaign, c).begins_with("res://assets/ritratti/catholic/king/"))


func test_agenti_e_ammiragli_della_cultura(t: TestContext) -> void:
	PortraitArt.reset()
	var campaign := _campaign()
	var cases := [["FN_JAPANESE", "PRIEST", "japanese/religious"], ["FN_JAPANESE", "SPY", "japanese/spy"],
		["FN_CHINESE", "SHAMAN", "chinese/religious"], ["FN_KANEM", "MULLAH", "kanem/religious"],
		["FN_KANEM", "ULAMA", "kanem/religious"], ["FN_AZTECS", "ASSASSIN", "aztec/assassin"],
		["FN_INCA", "EMISSARY", "inca/emissary"], ["FN_MISSISSIPPIANS", "PRIEST", "mississippian/religious"],
		["FN_CUMANS", "PRIEST", "pagan/shaman"]]
	for i in cases.size():
		var a := AgentState.new(i + 1, cases[i][0], "", "", cases[i][1])
		var path := PortraitArt.agent_portrait_path(campaign, a)
		t.assert_true(path.begins_with("res://assets/ritratti/%s/" % cases[i][2]), "%s %s: %s" % [cases[i][0], cases[i][1], path])
	for fid in FAZIONI:
		var path := PortraitArt.admiral_portrait_path(campaign, Army.new(3, fid, "", true))
		t.assert_true(path.begins_with("res://assets/ritratti/%s/admiral/" % FAZIONI[fid][0]), "%s: %s" % [fid, path])
	t.assert_eq(PortraitArt.agent_portrait_path(campaign, AgentState.new(9, "FN_JAPANESE", "", "", AgentState.PRINCESS)), "",
		"le principesse hanno il ritratto del personaggio")


func test_fazioni_dei_ritratti_asiatici(t: TestContext) -> void:
	PortraitArt.reset()
	var campaign := _campaign()
	for fid in ASIATICHE:
		var cult: String = ASIATICHE[fid]
		t.assert_eq(PortraitArt.culture_of(fid), cult, fid)
		var c := Character.new(5)
		c.faction = fid
		c.role = Character.ROLE_LEADER
		var king_folder := cult if cult in REALI_ASIATICI else "pagan"
		t.assert_true(PortraitArt.portrait_path(campaign, c).begins_with("res://assets/ritratti/%s/king/" % king_folder),
			"%s: il re dalla serie %s" % [fid, king_folder])
		c.role = Character.ROLE_PRINCESS
		t.assert_true(PortraitArt.portrait_path(campaign, c).begins_with("res://assets/ritratti/%s/princess/" % cult), fid)
		for role in [["SPY", "spy"], ["EMISSARY", "emissary"], ["ASSASSIN", "assassin"], ["SHAMAN", "religious"]]:
			var path := PortraitArt.agent_portrait_path(campaign, AgentState.new(4, fid, "", "", role[0]))
			t.assert_true(path.begins_with("res://assets/ritratti/%s/%s/" % [cult, role[1]]), "%s %s: %s" % [fid, role[0], path])
	var korean := PortraitArt.admiral_portrait_path(campaign, Army.new(3, "FN_KOREANS", "", true))
	t.assert_true(korean.begins_with("res://assets/ritratti/korean/admiral/"), korean)
	for fid in ["FN_CHOLA", "FN_KHMER"]:
		var adm := PortraitArt.admiral_portrait_path(campaign, Army.new(3, fid, "", true))
		t.assert_true(adm.begins_with("res://assets/ritratti/%s/admiral/" % ASIATICHE[fid]), "%s: %s" % [fid, adm])
