class_name PortraitArt
extends RefCounted
## Ritratti dei personaggi dall'originale (fase 8): campmap/Portraits/<religione>/<ruolo>/*.tga, esportati in PNG
## (AssetLibrary, ADR-007). Religione della fazione -> Catholic, Orthodox, Muslim o Pagan; ruolo -> King (capo), Prince (erede
## e principi), Princess, General. Ogni personaggio ha sempre lo stesso ritratto del suo ruolo (scelto dal suo id), cosi' non
## cambia da un anno all'altro; quando l'erede diventa re prende un ritratto da re, come nell'originale.

const BASE := "campmap/Portraits"
const SIZE := Vector2(96, 142)


static func religion_folder(religion: String) -> String:
	var r := religion.to_upper()
	if r.contains("MUSLIM") or r.contains("ISLAM"):   # nei dati REL_ISLAMIC: prima i musulmani prendevano ritratti cattolici
		return "Muslim"
	if r.contains("ORTHODOX"):
		return "Orthodox"
	if r.contains("PAGAN") or r.contains("DHARMA"):   # il Dharma non ha ritratti dell'originale: quelli pagani
		return "Pagan"
	return "Catholic"


static func role_folder(role: String) -> String:
	match role:
		Character.ROLE_LEADER:
			return "King"
		Character.ROLE_HEIR, Character.ROLE_PRINCE:
			return "Prince"
		Character.ROLE_PRINCESS:
			return "Princess"
	return "General"


## Serie nuova di ritratti di una religione e di un ruolo (ADR-044): `assets/ritratti/<religione>/<ruolo>/NN.png`,
## preparata da tools/prepara_serie_ritratti.py. Se la cartella ha ritratti, il sorteggio pesca solo da questi e non
## dall'installazione (Federico, 13/11/2026: 51 re cattolici nuovi al posto dei 94 dell'originale).
const SERIES_DIR := "res://assets/ritratti/"
static var _series := {}       ## "religione/ruolo" -> percorsi res:// ordinati
static var _textures := {}     ## percorso res:// -> Texture2D con le mipmap


static func series(religion_dir: String, role_dir: String) -> PackedStringArray:
	var key := "%s/%s" % [religion_dir.to_lower(), role_dir.to_lower()]
	if _series.has(key):
		return _series[key]
	var dir := SERIES_DIR + key + "/"
	var out := PackedStringArray()
	if DirAccess.dir_exists_absolute(dir):
		for f in ResourceLoader.list_directory(dir):   # anche nell'eseguibile, dove i PNG diventano risorse importate
			if f.get_extension().to_lower() == "png":
				out.append(dir + f)
	out.sort()
	_series[key] = out
	return out


static func reset() -> void:
	_series.clear()
	_textures.clear()
	_owners.clear()
	_owners_loaded = false
	_cultures.clear()
	_cultures_loaded = false


## Ritratti per cultura (ADR-087, Federico 16/11/2026): le fazioni di data/ritratti_culture.cfg prendono personaggi,
## agenti e ammiragli da `assets/ritratti/<cultura>/<ruolo>/` (tools/prepara_ritratti_culture.py) prima che dalla serie
## della religione; gli agenti religiosi usano la serie «religious». Senza la serie del ruolo resta la religione.
const CULTURE_TABLE := "res://data/ritratti_culture.cfg"
const RELIGIOUS_ROLES := ["bishop", "cardinal", "priest", "shaman", "monk", "mullah", "ulama", "inquisitor", "grand_inquisitor"]
static var _cultures := {}        ## fazione -> cultura
static var _cultures_loaded := false


## Serie esclusiva degli Auror (Federico 27/11/2026: «ritratti esclusivi per gli auror ... distinti dal resto degli
## occidentali»): `assets/ritratti/auror/<ruolo>/`, solo in modalita' Auror; i Danesi storici restano ai cattolici.
const AUROR_CULTURE := "auror"


## Cultura dei ritratti della fazione ("" = nessuna: decide la religione).
static func culture_of(faction_id: String) -> String:
	if Scenario.auror and SimUtil.norm(faction_id) == AUROR:
		return AUROR_CULTURE
	if not _cultures_loaded:
		_cultures_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(CULTURE_TABLE) == OK and cfg.has_section("fazioni"):
			for key in cfg.get_section_keys("fazioni"):
				_cultures[SimUtil.norm(str(key))] = str(cfg.get_value("fazioni", key, ""))
	return _cultures.get(SimUtil.norm(faction_id), "")


## Ritratto della serie della cultura della fazione per quel ruolo ("" se la fazione non ha cultura o la serie manca).
static func culture_pick(faction_id: String, role_dir: String, seed: int) -> String:
	var cult := culture_of(faction_id)
	if cult == "":
		return ""
	var files := series(cult, role_dir)
	if files.is_empty():
		return ""
	return files[absi(seed * 7919) % files.size()]


## Percorso del ritratto del personaggio: res:// della serie nuova se c'e', altrimenti il percorso originale
## dell'installazione; "" se non ce n'e' nessuno. I pagani senza la cartella del ruolo ripiegano sui cattolici.
static func portrait_path(campaign: CampaignData, c: Character) -> String:
	var look := c.look_faction()   # generale degli Auror nato da una truppa straniera: ritratto della fazione dell'unita'
	var f := campaign.faction(look) if campaign != null else null
	var religion := religion_folder(f.religion if f != null else "")
	var role := role_folder(c.role)
	if c.role == Character.ROLE_LEADER and SimUtil.norm(c.faction) == GameState.PAPAL:
		var popes := series("Catholic", "Pope")   # ADR-059: il capo dello Stato Pontificio e' il Papa
		if not popes.is_empty():
			return popes[(c.id * 7919) % popes.size()]
	var own := culture_pick(look, role.to_lower(), c.id)
	if own != "":
		return own
	var files := series(religion, role)
	if files.is_empty():
		files = AssetLibrary.list("%s/%s/%s/" % [BASE, religion, role])
	if files.is_empty():
		files = series("Catholic", role)
	if files.is_empty():
		files = AssetLibrary.list("%s/Catholic/%s/" % [BASE, role])
	if files.is_empty():
		return ""
	# indice stabile dal numero del personaggio (moltiplicatore primo: personaggi vicini, ritratti diversi)
	return files[(c.id * 7919) % files.size()]


## Ritratto proprio del personaggio dalla tabella delle fazioni ("" se non ne ha): oggi solo il capo indicato in
## `[ritratti]` di data/fazioni.cfg (Darkos I degli Auror).
static func custom_portrait_path(c: Character) -> String:
	if c == null or c.role != Character.ROLE_LEADER:
		return ""
	return FactionStyle.leader_portrait(c.faction, c.numeral)


static func portrait(campaign: CampaignData, c: Character) -> Texture2D:
	var own := custom_portrait_path(c)
	if own != "" and ResourceLoader.exists(own):
		return load(own) as Texture2D
	var p := portrait_path(campaign, c)
	if p.begins_with("res://"):
		return series_texture(p)
	return without_stone_frame(AssetLibrary.texture(p)) if p != "" else null


## Ritratto della serie nuova con le mipmap (384x568 mostrato molto piu' piccolo: senza sgranerebbe).
static func series_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var tex := load(path) as Texture2D if ResourceLoader.exists(path) else null
	var img := tex.get_image() if tex != null else null
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.generate_mipmaps()
		tex = ImageTexture.create_from_image(img)
	_textures[path] = tex
	return tex


## Il ritratto dell'originale senza la sua cornice di pietra (STONE_FRAME punti per lato su 96x142): tutti i ritratti
## ricevono la stessa cornice nuova da `UiTheme.portrait`. Altre misure restano come sono.
const STONE_FRAME := 8
static func without_stone_frame(tex: Texture2D) -> Texture2D:
	if tex == null or Vector2(tex.get_size()) != SIZE:
		return tex
	var inner := AtlasTexture.new()
	inner.atlas = tex
	inner.region = Rect2(STONE_FRAME, STONE_FRAME, SIZE.x - 2.0 * STONE_FRAME, SIZE.y - 2.0 * STONE_FRAME)
	return inner


## Ritratti di agenti, ammiragli e pontefici (ADR-059, Federico 14/11/2026): serie `assets/ritratti/<religione>/<ruolo>/`
## preparate da tools/prepara_ritratti_ruoli.py; `data/ritratti_fazioni.cfg` dice a quali fazioni spetta ogni ritratto.
const OWNERS_TABLE := "res://data/ritratti_fazioni.cfg"
const AUROR := "FN_DANISH"
const AGENT_ROLES := {
	"EMISSARY": "emissary", "SPY": "spy", "ASSASSIN": "assassin", "BISHOP": "bishop", "ORTHODOX_BISHOP": "bishop",
	"CARDINAL": "cardinal", "PRIEST": "priest", "SHAMAN": "shaman", "MONK": "monk", "MULLAH": "mullah", "ULAMA": "ulama",
	"INQUISITOR": "inquisitor", "GRAND_INQUISITOR": "grand_inquisitor",
}
static var _owners := {}          ## "religione/ruolo" -> {"NN": PackedStringArray fazioni}
static var _owners_loaded := false


static func _load_owners() -> void:
	if _owners_loaded:
		return
	_owners_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(OWNERS_TABLE) != OK:
		return
	for section in cfg.get_sections():
		var table := {}
		for key in cfg.get_section_keys(section):
			table[str(key)] = PackedStringArray(str(cfg.get_value(section, key, "")).split(",", false))
		_owners[section.to_lower()] = table


## Fazioni a cui spetta il ritratto (vuoto = ritratto comune).
static func owners_of(religion_dir: String, role_dir: String, path: String) -> PackedStringArray:
	_load_owners()
	var table: Dictionary = _owners.get("%s/%s" % [religion_dir.to_lower(), role_dir.to_lower()], {})
	return table.get(path.get_file().get_basename(), PackedStringArray())


## Ritratto della serie per una fazione: prima quelli della fazione, poi quelli comuni o di tutti; i ritratti riservati
## ai soli Auror non escono per le altre fazioni. `seed` sceglie stabilmente (id dell'agente o della flotta).
static func pick_for_faction(religion_dir: String, role_dir: String, faction_id: String, seed: int) -> String:
	var files := series(religion_dir, role_dir)
	if files.is_empty():
		return ""
	var fid := SimUtil.norm(faction_id)
	var own := PackedStringArray()
	var common := PackedStringArray()
	for path in files:
		var who := owners_of(religion_dir, role_dir, path)
		var auror_only := who.size() == 1 and who[0] == AUROR
		if who.has(fid) and not (auror_only and not Scenario.auror):   # ADR-068: i Danesi storici non hanno quelli degli Auror
			own.append(path)
		elif who.is_empty() or who.has("*") or not auror_only:
			common.append(path)
	var pool := own if not own.is_empty() else common
	if pool.is_empty():
		pool = files
	return pool[absi(seed * 7919) % pool.size()]


static func _faction_religion(campaign: CampaignData, faction_id: String) -> String:
	var f := campaign.faction(faction_id) if campaign != null else null
	return religion_folder(f.religion if f != null else "")


## Ruolo della serie per il tipo di agente; i sacerdoti pagani usano la serie degli sciamani.
static func agent_role(type_name: String, religion_dir: String) -> String:
	var role: String = AGENT_ROLES.get(type_name.to_upper(), "")
	if role == "priest" and religion_dir == "Pagan":
		return "shaman"
	return role


## Percorso del ritratto dell'agente ("" se il suo ruolo non ha una serie: resta l'immagine dell'unita').
static func agent_portrait_path(campaign: CampaignData, agent: AgentState) -> String:
	if agent == null:
		return ""
	var religion := _faction_religion(campaign, agent.faction)
	var role := agent_role(agent.type_name, religion)
	if role == "":
		return ""
	var own := culture_pick(agent.faction, "religious" if role in RELIGIOUS_ROLES else role, agent.id)
	if own != "":
		return own
	var path := pick_for_faction(religion, role, agent.faction, agent.id)
	if path == "" and religion != "Catholic":
		path = pick_for_faction("Catholic", role, agent.faction, agent.id)   # per esempio vescovi o cardinali altrove
	return path


## Percorso del ritratto dell'ammiraglio della flotta.
static func admiral_portrait_path(campaign: CampaignData, army: Army) -> String:
	if army == null or not army.is_fleet:
		return ""
	var own := culture_pick(army.faction, "admiral", army.id)
	if own != "":
		return own
	var religion := _faction_religion(campaign, army.faction)
	var path := pick_for_faction(religion, "admiral", army.faction, army.id)
	if path == "":
		path = pick_for_faction("Catholic", "admiral", army.faction, army.id)
	return path


static func agent_portrait(campaign: CampaignData, agent: AgentState) -> Texture2D:
	var p := agent_portrait_path(campaign, agent)
	return series_texture(p) if p != "" else null


static func admiral_portrait(campaign: CampaignData, army: Army) -> Texture2D:
	var p := admiral_portrait_path(campaign, army)
	return series_texture(p) if p != "" else null
