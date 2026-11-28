class_name EventArt
extends RefCounted
## Illustrazioni delle finestre (fase 8b): la tavola seppia di campmap/EPIC.BIF per ogni evento storico e l'immagine della
## schermata di fine partita. Gli abbinamenti sono in data/ui/illustrazioni.cfg; le immagini vengono dall'esportazione PNG
## (AssetLibrary) e mancano senza di essa: le finestre allora restano di solo testo.

const TABLE := "res://data/ui/illustrazioni.cfg"
const EPIC_SIZE := Vector2(320, 240)
const END_SIZE := Vector2(640, 480)

## Serie proprie per tema (richiesta di Federico del 2026-11-20): assets/eventi/<tema>/01.png, 02.png... (1280x720, da
## tools/prepara_tavole.py). Se un tema ne ha, si sceglie solo tra quelle; altrimenti le tavole di illustrazioni.cfg [temi].
const OWN_DIR := "res://assets/eventi/"
const OWN_MAX := 30
## Vignetta propria di un evento storico (richiesta di Federico del 28/11/2026, eventi 1000-1086 e 1441-1700):
## assets/eventi/storici/<chiave>.png (1280x720, da tools/prepara_tavole.py, codice V_<CHIAVE>). Se manca vale la tavola
## di illustrazioni.cfg [storici] o del tema.
const HISTORICAL_DIR := "res://assets/eventi/storici/"

static var _cfg: ConfigFile = null
static var _own := {}


static func reset() -> void:
	_cfg = null
	_own.clear()


## Percorsi della serie propria del tema (vuota se non ce n'e'), nell'ordine dei numeri. Un tema senza cartella propria puo'
## prendere le scene di altri temi con illustrazioni.cfg [serie] (per esempio battaglia = vittorie e sconfitte campali).
static func own_paths(theme: String) -> PackedStringArray:
	if _own.has(theme):
		return _own[theme]
	var out := _folder_paths(theme)
	var cfg := _table()
	if out.is_empty() and cfg != null and cfg.has_section_key("serie", theme):
		for other in cfg.get_value("serie", theme, []):
			out.append_array(_folder_paths(str(other)))
	_own[theme] = out
	return out


static func _folder_paths(theme: String) -> PackedStringArray:
	var out := PackedStringArray()
	if theme != "":
		for n in range(1, OWN_MAX + 1):
			var path := "%s%s/%02d.png" % [OWN_DIR, theme, n]
			if not ResourceLoader.exists(path):
				break
			out.append(path)
	return out


## Tavola per il tema esatto della tabella ([temi] <tema>), poi per il tema contenuto nel nome; 0 se nessuna.
static func theme_exact_frame(theme: String, seed: String = "") -> int:
	var cfg := _table()
	if cfg == null or theme == "":
		return 0
	if cfg.has_section_key("temi", theme):
		var placeholders: Array = cfg.get_value("epic", "segnaposto", [])
		return _pick(cfg.get_value("temi", theme, []), seed if seed != "" else theme, placeholders)
	return theme_frame(theme, seed)


## Immagine di un tema: un elemento stabile della serie propria, o la tavola del tema; null se non c'e' nulla.
static func theme_texture(theme: String, seed: String = "") -> Texture2D:
	var own := own_paths(theme)
	if not own.is_empty():
		var tex := load(own[absi((seed if seed != "" else theme).hash()) % own.size()]) as Texture2D
		if tex != null:
			return tex
	return epic_texture(theme_exact_frame(theme, seed))


## Immagine di sfondo di una finestra di evento: il tema degli avvisi (CampaignUiAlerts) o la tavola dell'evento storico.
static func window_texture(w: Dictionary) -> Texture2D:
	# luoghi leggendari: la tavola dipinta del luogo, altrimenti una tavola generica scelta dal luogo (26/11/2026)
	var picture := str(w.get("immagine", ""))
	if picture != "" and ResourceLoader.exists(picture):
		return load(picture) as Texture2D
	if str(w.get("luogo_leggendario", "")) != "":
		return historical_texture(-1, "luogo_" + str(w["luogo_leggendario"]))
	var theme := str(w.get("tema", ""))
	if theme != "":
		return theme_texture(theme, "%s|%d" % [str(w.get("titolo", "")), int(w.get("anno", 0))])
	var own := historical_own_texture(str(w.get("chiave", "")))
	if own != null:
		return own
	return historical_texture(int(w.get("indice", -1)), str(w.get("chiave", "")))


## Percorso della vignetta propria dell'evento storico di chiave `key` ("" se non c'e').
static func historical_own_path(key: String) -> String:
	if key == "":
		return ""
	var path := HISTORICAL_DIR + key.to_lower() + ".png"
	return path if ResourceLoader.exists(path) else ""


static func historical_own_texture(key: String) -> Texture2D:
	var path := historical_own_path(key)
	return load(path) as Texture2D if path != "" else null


## Tavola (fotogramma da 1) per l'evento storico `index` di chiave `key`: l'abbinamento della tabella, poi un tema che compare
## nella chiave, poi una tavola generica scelta in modo stabile dalla chiave. Mai un segnaposto; 0 se la tabella manca.
static func historical_frame(index: int, key: String = "") -> int:
	var cfg := _table()
	if cfg == null:
		return 0
	var placeholders: Array = cfg.get_value("epic", "segnaposto", [])
	var fixed := int(cfg.get_value("storici", str(index), 0))
	if fixed > 0 and not placeholders.has(fixed):
		return fixed
	var seed := key if key != "" else str(index)
	var themed := theme_frame(key, seed)
	if themed > 0:
		return themed
	return _pick(cfg.get_value("epic", "generiche", []), seed, placeholders)


## Tavola del primo tema della tabella che compare in `text` (per esempio «peste» in «peste_nera_1347»), 0 se nessuno.
## I temi piu' lunghi vincono sui piu' corti («peste_nera» prima di «peste»).
static func theme_frame(text: String, seed: String = "") -> int:
	var cfg := _table()
	if cfg == null or text == "" or not cfg.has_section("temi"):
		return 0
	var placeholders: Array = cfg.get_value("epic", "segnaposto", [])
	var lower := text.to_lower()
	var best := ""
	for theme in cfg.get_section_keys("temi"):
		if lower.contains(theme) and theme.length() > best.length():
			best = theme
	if best == "":
		return 0
	return _pick(cfg.get_value("temi", best, []), seed if seed != "" else text, placeholders)


## Vero se il fotogramma e' una delle tavole segnaposto dell'originale.
static func is_placeholder(frame: int) -> bool:
	var cfg := _table()
	return cfg != null and (cfg.get_value("epic", "segnaposto", []) as Array).has(frame)


## Immagine della tavola, o null senza esportazione.
static func epic_texture(frame: int) -> Texture2D:
	var cfg := _table()
	if cfg == null or frame <= 0 or not AssetLibrary.is_available():
		return null
	return AssetLibrary.texture(str(cfg.get_value("epic", "immagine", "campmap/EPIC.BIF")), frame)


static func historical_texture(index: int, key: String = "") -> Texture2D:
	return epic_texture(historical_frame(index, key))


## Percorso originale dell'immagine di fine partita. `outcome` e' un VictoryState.*: la vittoria per dominio mostra la sala del
## trono della fazione (o quella scelta in tabella), la sconfitta la citta' in fiamme della sua religione, la fine per l'anno
## la sala del vincitore se e' il giocatore, altrimenti la citta' in fiamme.
static func end_picture_path(faction_id: String, religion: String, outcome: String, player_won: bool) -> String:
	var cfg := _table()
	if cfg == null:
		return ""
	var victory := outcome == VictoryState.DOMINATION or (outcome != VictoryState.DEFEAT and player_won)
	if victory:
		var custom := str(cfg.get_value("fine", "vittoria_%s" % faction_id, ""))
		if custom != "":
			return custom
		var own := "campmap/GameEnd/%s_WIN.BIF" % faction_id
		if AssetLibrary.has(own):
			return own
		return str(cfg.get_value("fine", "vittoria_generica", ""))
	var folder := PortraitArt.religion_folder(religion)
	return str(cfg.get_value("fine", "sconfitta_%s" % folder, cfg.get_value("fine", "sconfitta_Catholic", "")))


## Immagine di fine partita: la tavola unica assets/eventi/fine/01.png (richiesta di Federico del 2026-11-20: una sola per
## tutte le fazioni e tutti gli esiti), altrimenti quella dell'installazione scelta da end_picture_path.
static func end_texture(faction_id: String, religion: String, outcome: String, player_won: bool) -> Texture2D:
	var own := _folder_paths("fine")
	if not own.is_empty():
		var tex := load(own[0]) as Texture2D
		if tex != null:
			return tex
	if not AssetLibrary.is_available():
		return null
	var path := end_picture_path(faction_id, religion, outcome, player_won)
	return AssetLibrary.texture(path) if path != "" else null


## Nastro vuoto in cima alle immagini di fine partita (coordinate dell'immagine 640x480), dove va il titolo.
static func end_ribbon() -> Rect2:
	var cfg := _table()
	if cfg == null:
		return Rect2()
	return cfg.get_value("fine", "nastro", Rect2())


# --- interni ------------------------------------------------------------------------------------------------------


static func _table() -> ConfigFile:
	if _cfg == null:
		var c := ConfigFile.new()
		if c.load(TABLE) == OK:
			_cfg = c
	return _cfg


## Elemento stabile di `frames` (scartati i segnaposto) scelto dalla stringa `seed`; 0 se non resta nulla.
static func _pick(frames: Array, seed: String, placeholders: Array) -> int:
	var usable: Array[int] = []
	for f in frames:
		if not placeholders.has(int(f)):
			usable.append(int(f))
	if usable.is_empty():
		return 0
	return usable[absi(seed.hash()) % usable.size()]
