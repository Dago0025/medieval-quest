class_name AssetLibrary
extends RefCounted
## Immagini dell'interfaccia originale per la fase 8 (ADR-007): si leggono i PNG che `export.py` di Federico ha estratto
## dall'installazione in `<gioco>/_ASSET_EXPORT`, mai i BIF o i TGA del gioco, e non entrano nel repository.
##
## Si cerca per percorso originale del gioco, senza distinguere maiuscole e minuscole («campmap/shields/colours/DENMARK_LGE.BIF»):
## l'indice viene da `_ASSET_EXPORT/_manifest.csv` (categoria;file_originale;png;larghezza;altezza;frame;formato). I BIF con piu'
## fotogrammi sono esportati come `nome.BIF__f01.png`, `__f02.png`... Una versione ingrandita nella cartella HD allo stesso
## percorso (`GameFiles.find_hd_image`) ha la precedenza. Le immagini mancanti restituiscono null e finiscono in `missing()`:
## l'interfaccia ripiega su stili disegnati a codice e dice una volta sola che manca l'esportazione.

const EXPORT_DIR := "_ASSET_EXPORT"
const MANIFEST := "_manifest.csv"
const DEFAULT_SHIELD_LARGE := "default_lge"
const DEFAULT_SHIELD_SMALL := "default_sml"

static var _export_root := ""
static var _hd_root := ""
static var _configured := false
static var _configured_explicitly := false
static var _index := {}        ## percorso originale in minuscolo -> {"png": percorso relativo, "frame": n. fotogrammi}
static var _cache := {}        ## chiave "percorso#fotogramma" -> Texture2D (o null se manca)
static var _missing := {}      ## percorsi originali cercati e non trovati -> true
static var _lists := {}        ## prefisso -> percorsi originali (in minuscolo, ordinati) che cominciano cosi'
static var _shield_names := {}  ## fazione -> [scudo grande, scudo piccolo] (SetShieldImage dello startpos, `use_campaign`)
static var _errors := PackedStringArray()


## Cartelle esplicite (test o impostazioni); senza chiamarla valgono `<gioco>/_ASSET_EXPORT` e `GameFiles.hd_dir()`.
static func configure(export_root: String, hd_root: String) -> void:
	reset()
	_export_root = export_root
	_hd_root = hd_root
	_configured = true
	_configured_explicitly = true   # test: il manifesto della cartella indicata, non l'indice del progetto


## Dimentica indice, immagini e configurazione (al prossimo uso si rilegge tutto).
static func reset() -> void:
	_export_root = ""
	_hd_root = ""
	_configured = false
	_configured_explicitly = false
	_index.clear()
	_lists.clear()
	_cache.clear()
	_missing.clear()
	_shield_names.clear()
	_errors.clear()


static func export_root() -> String:
	_ensure()
	return _export_root


## Vero se l'esportazione c'e' e il manifesto ha almeno una voce.
static func is_available() -> bool:
	_ensure()
	return not _index.is_empty()


## Problemi di lettura (manifesto assente o illeggibile), per il messaggio all'avvio.
static func errors() -> PackedStringArray:
	_ensure()
	return _errors


## Percorsi originali cercati senza trovare l'immagine, in ordine alfabetico.
static func missing() -> PackedStringArray:
	var out := PackedStringArray(_missing.keys())
	out.sort()
	return out


## Vero se il manifesto conosce il percorso originale.
static func has(original: String) -> bool:
	_ensure()
	return _index.has(_key(original))


## Percorsi originali (in minuscolo, in ordine) che cominciano con `prefix`, per esempio i ritratti di una cartella.
static func list(prefix: String) -> PackedStringArray:
	_ensure()
	var p := _key(prefix)
	if _lists.has(p):
		return _lists[p]
	var out := PackedStringArray()
	for k in _index:
		if str(k).begins_with(p):
			out.append(str(k))
	out.sort()
	_lists[p] = out
	return out


## Numero di fotogrammi dell'immagine (1 se sconosciuta).
static func frame_count(original: String) -> int:
	_ensure()
	return int((_index.get(_key(original), {}) as Dictionary).get("frame", 1))


## Immagine del percorso originale (fotogramma `frame`, da 1), o null se manca.
static func texture(original: String, frame: int = 1) -> Texture2D:
	_ensure()
	var key := _key(original)
	var cache_key := "%s#%d" % [key, frame]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var tex: Texture2D = remade(original, frame)
	var file := _file_for(key, original, frame) if tex == null else ""
	if file != "":
		var img := Image.load_from_file(file)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		_missing[original] = true
	_cache[cache_key] = tex
	return tex


## Immagine dell'originale rifatta (ADR-043): `assets/rifatti/<percorso originale in minuscolo>.png`, preparata da
## tools/prepara_rifatti.py, con le riduzioni intermedie perche' e' piu' grande della misura a schermo. Prende il posto
## dell'immagine dell'installazione ovunque la si chieda; null se non c'e'. Per le immagini a piu' fotogrammi il primo e'
## `<nome>.png`, gli altri `<nome>__fNN.png` (come l'esportazione: il porto ha un fotogramma per orientamento, ADR-061).
const REMADE_DIR := "res://assets/rifatti/"
static func remade_path(original: String, frame: int = 1) -> String:
	var suffix := "" if frame <= 1 else "__f%02d" % frame
	return REMADE_DIR + _key(original).get_basename() + suffix + ".png"


static func remade(original: String, frame: int = 1) -> Texture2D:
	var path := remade_path(original, frame)
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	var img := tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		return tex
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Rettangoli di una pedina rifatta (tools/prepara_pedine.py): `<rifatta>.cfg` accanto al PNG, sezione [pedina] con
## stendardo, base e scudo come [x, y, larghezza, altezza] in pixel della rifatta; dizionario vuoto se non c'e'.
static func remade_layout(original: String) -> Dictionary:
	var path := remade_path(original).get_basename() + ".cfg"
	var key := "disposizione|" + path
	if _cache.has(key):
		return _cache[key]
	var out := {}
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(path) and cfg.load(path) == OK:
		for k in cfg.get_section_keys("pedina"):
			var v: Variant = cfg.get_value("pedina", k)
			if v is Array and (v as Array).size() == 4:
				out[k] = Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
			else:
				out[k] = v
	_cache[key] = out
	return out


## Ritaglio di un'immagine (per esempio il nastro del titolo di una pergamena), o null se l'immagine manca.
static func region(original: String, rect: Rect2, frame: int = 1) -> Texture2D:
	var tex := texture(original, frame)
	if tex == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = rect
	return atlas


## Carta dell'unita' (pannello dell'esercito): campmap/review_panel/Units/<id>.BIF, per le navi Ships, per gli agenti
## Agents. `culture` ("Muslim", "Pagan"; "" o "Christian" = comune) sceglie la variante di cultura delle carte degli agenti
## (Agents/MUSLIM, Agents/Pagan), come le pedine: lo sciamano c'e' solo in Agents/Pagan.
static func unit_card(unit_id: String, culture: String = "") -> Texture2D:
	var original := unit_card_path(unit_id, culture)
	if original != "":
		return texture(original)
	_missing["carta:" + unit_id] = true
	return null


## Percorso originale della carta dell'unita', "" se l'esportazione non ce l'ha.
static func unit_card_path(unit_id: String, culture: String = "") -> String:
	if culture != "" and culture != "Christian":
		var own_culture := "campmap/review_panel/Agents/%s/%s.BIF" % [culture, unit_id]
		if has(own_culture) or is_remade(own_culture):
			return own_culture
	for folder in ["Units", "Ships", "Agents"]:
		var original := "campmap/review_panel/%s/%s.BIF" % [folder, unit_id]
		if has(original):
			return original
	# carte d'agente che esistono solo in una cartella di cultura (Shaman in Agents/Pagan)
	for other in ["Pagan", "MUSLIM"]:
		var only_culture := "campmap/review_panel/Agents/%s/%s.BIF" % [other, unit_id]
		if has(only_culture) or is_remade(only_culture):
			return only_culture
	# ADR-074: le unita' esclusive degli Auror non hanno originale, solo la carta rifatta
	var own := "campmap/review_panel/Units/%s.BIF" % unit_id
	if is_remade(own):
		return own
	# ADR-076: finche' l'immagine non e' pronta, la carta del modello (la Fregata del Drago mostra la caracca)
	var model := str(AurorUnits.value(unit_id, "modello", ""))
	if model == "":
		model = CultureUnits.card_model(unit_id)   # ADR-116: segnaposto finche' le unita' delle fazioni nuove non hanno carta
	return unit_card_path(model) if model != "" and not AurorUnits.is_auror_unit(model) and not CultureUnits.is_culture_unit(model) else ""


## Vero se per il percorso originale c'e' un'immagine rifatta in assets/rifatti (ADR-043).
static func is_remade(original: String) -> bool:
	return original != "" and ResourceLoader.exists(remade_path(original))


## Illustrazione grande dell'unita' (scheda informativa): campmap/Info_Pics/Units/<id>.BIF, per le navi Ships.
static func unit_picture(unit_id: String) -> Texture2D:
	for folder in ["Units", "Ships", "Agents"]:
		var original := "campmap/Info_Pics/%s/%s.BIF" % [folder, unit_id]
		if has(original) or is_remade(original):   # ADR-074: unita' degli Auror senza originale
			return texture(original)
	var model := str(AurorUnits.value(unit_id, "modello", ""))
	if model == "":
		model = CultureUnits.card_model(unit_id)   # ADR-116
	if model != "" and not AurorUnits.is_auror_unit(model) and not CultureUnits.is_culture_unit(model):
		return unit_picture(model)   # ADR-076: immagine non ancora pronta, quella del modello
	_missing["illustrazione:" + unit_id] = true
	return null


## Scudi delle fazioni dallo startpos (`SetShieldImage`: "Denmark_lge", "Denmark_sml" in campmap/shields).
static func use_campaign(campaign: CampaignData) -> void:
	_shield_names.clear()
	if campaign == null:
		return
	for f in campaign.factions:
		if f.shield_large != "":
			_shield_names[f.id.to_upper()] = [f.shield_large, f.shield_small]


## Dimentica gli stemmi propri gia' resi (cambio di scenario, ADR-068: FN_DANISH passa dagli Auror ai Danesi).
static func forget_faction_shields() -> void:
	for key in _cache.keys():
		if str(key).begins_with("stemma|"):
			_cache.erase(key)


## Nome dell'immagine dello scudo della fazione (startpos; le fazioni senza scudo, come i ribelli, quello predefinito).
static func shield_name(faction_id: String, large: bool = true) -> String:
	var names: Array = _shield_names.get(faction_id.to_upper(), [])
	if names.size() == 2 and str(names[0 if large else 1]) != "":
		return str(names[0 if large else 1])
	return DEFAULT_SHIELD_LARGE if large else DEFAULT_SHIELD_SMALL


## Scudo della fazione, grande (34x40) o piccolo (18x20), o null se manca anche quello predefinito.
## Lo stemma proprio del remake (data/fazioni.cfg), nella misura grande, e' reso a SHIELD_DETAIL volte quella
## dell'originale con le riduzioni intermedie (mipmap): l'interfaccia lo mostra da 1,5 a 3 volte piu' grande di 34x40 e
## reso a 34x40 e poi ingrandito usciva sgranato (segnalazione di Federico dell'11/11). Chi lo mostra deve ignorare la
## misura della texture (UiTheme.picture, EXPAND_IGNORE_SIZE) e usare il filtro LINEAR_WITH_MIPMAPS.
const SHIELD_DETAIL := 4
static func faction_shield(faction_id: String, large: bool = true) -> Texture2D:
	var size := Vector2i(34, 40) * SHIELD_DETAIL if large else Vector2i(17, 20)
	var custom := FactionStyle.shield_image(faction_id, size)
	if custom != null:
		var key := "stemma|%s|%s" % [faction_id.to_upper(), large]
		if not _cache.has(key):
			if large:
				custom = custom.duplicate() as Image
				custom.generate_mipmaps()
			_cache[key] = ImageTexture.create_from_image(custom)
		return _cache[key]
	var tex := texture("campmap/shields/%s.BIF" % shield_name(faction_id, large))
	if tex == null:
		tex = texture("campmap/shields/%s.BIF" % (DEFAULT_SHIELD_LARGE if large else DEFAULT_SHIELD_SMALL))
	return tex


# --- interni ------------------------------------------------------------------------------------------------------


static func _key(original: String) -> String:
	return original.replace("\\", "/").to_lower()


static func _ensure() -> void:
	if not _configured:
		_export_root = GameFiles.path(EXPORT_DIR)
		_hd_root = GameFiles.hd_dir()
		_configured = true
	if _index.is_empty() and _errors.is_empty():
		_read_manifest()


## Indice delle immagini nel progetto (copia del manifesto dell'esportazione: solo percorsi, misure e fotogrammi, dal
## 18/11/2026): resta valido anche quando dalla cartella originale/ si tolgono le immagini non piu' usate.
const PROJECT_INDEX := "res://data/ui/indice_immagini.txt"


static func _read_manifest() -> void:
	var path := PROJECT_INDEX if FileAccess.file_exists(PROJECT_INDEX) and not _configured_explicitly else _export_root.path_join(MANIFEST)
	if not FileAccess.file_exists(path):
		_errors.append(Lang.t("Esportazione delle immagini non trovata: manca %s (va rifatta con export.py).") % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_errors.append(Lang.t("Manifesto delle immagini non leggibile: %s") % path)
		return
	var first := true
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if first:
			first = false
			continue   # intestazione (con BOM)
		if line == "":
			continue
		var cols := line.split(";")
		if cols.size() < 3:
			continue
		var frames := int(cols[5]) if cols.size() > 5 else 1
		_index[_key(cols[1])] = {"png": cols[2], "frame": maxi(frames, 1)}
	if _index.is_empty():
		_errors.append(Lang.t("Manifesto delle immagini vuoto: %s") % path)


## File da aprire: la versione HD se c'e' (solo per il primo fotogramma), altrimenti il PNG esportato del fotogramma.
static func _file_for(key: String, original: String, frame: int) -> String:
	if frame == 1 and _hd_root != "":
		var hd := GameFiles.find_hd_image(_hd_root, original)
		if hd != "":
			return hd
	if not _index.has(key):
		return ""
	var png := str((_index[key] as Dictionary)["png"])
	var path := _export_root.path_join(png)
	# multi-fotogramma: nome.BIF.png nel manifesto (o gia' nome.BIF__f01.png), nome.BIF__fNN.png sul disco
	var stem := path.trim_suffix(".png")
	var marker := stem.rfind("__f")
	if marker >= 0 and stem.substr(marker + 3).is_valid_int():
		stem = stem.substr(0, marker)
	var framed := stem + "__f%02d.png" % frame
	if FileAccess.file_exists(framed):
		return framed
	if frame == 1 and FileAccess.file_exists(path):
		return path
	return ""
