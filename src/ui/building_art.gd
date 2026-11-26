class_name BuildingArt
extends RefCounted
## Icone degli edifici (fase 8d): le tessere 68x50 di campmap/review_panel/Buildings dell'originale, cercate per nome del
## livello del file prod («Armourers Workshop» -> armourers workshop.BIF), poi senza la cifra finale («Shipyard1» ->
## shipyard1, shipyard), poi per famiglia. Se esistono varianti in sottocartelle (culture) si preferisce quella della
## religione del giocatore: Catholic, Orthodox, Muslim, Pagan, e per cattolici e ortodossi poi Christian (corti, tenute,
## allevatori, locanda stanno solo li'). Diverse immagini della cartella principale sono segnaposto dello sviluppo (un
## paesaggio con il nome scritto: «baronial_estate», «church»), quindi una variante vince sempre su di esse.
## Null senza esportazione: il pannello usa allora il nome scritto.

const ROOT := "campmap/review_panel/buildings/"
const INFO_ROOT := "campmap/info_pics/buildings/"   ## illustrazioni grandi per la scheda dell'edificio
const ICON_SIZE := Vector2(68, 50)
const VARIANT_FOLDERS := ["catholic", "christian", "orthodox", "muslim", "pagan", "asian"]   ## sottocartelle delle varianti
## Edifici degli Auror (25/11/2026, prompt/edifici_auror.md): solo per il Culto Imperiale, mai come ripiego di altre religioni.
const AUROR_FOLDER := "auror"

static var _by_name := {}     ## nome del file in minuscolo senza estensione -> Array dei percorsi originali (tessere)
static var _info_by_name := {}   ## lo stesso per le illustrazioni di Info_Pics/Buildings
static var _cache := {}


static func reset() -> void:
	_by_name.clear()
	_info_by_name.clear()
	_cache.clear()


## Icona dell'edificio al livello `label` della famiglia, con la variante preferita per `religion` (CATHOLIC, MUSLIM...).
static func icon(label: String, family_id: String, religion: String = "") -> Texture2D:
	var key := "%s|%s|%s" % [label.to_lower(), family_id.to_lower(), religion.to_lower()]
	if _cache.has(key):
		return _cache[key]
	var path := icon_path(label, family_id, religion)
	var tex: Texture2D = AssetLibrary.texture(path) if path != "" else null
	_cache[key] = tex
	return tex


## Percorso originale dell'icona, "" se nessun nome corrisponde.
static func icon_path(label: String, family_id: String, religion: String = "") -> String:
	_ensure()
	var plain := label.strip_edges().to_lower()
	var no_digits := plain.rstrip("0123456789").strip_edges()
	var family := family_id.to_lower().replace("_", " ")
	for name in [plain, no_digits, family]:
		if name == "" or not _by_name.has(name):
			continue
		return choose(_by_name[name], religion)
	return ""


## Illustrazione grande dell'edificio per la scheda (Info_Pics/Buildings). Si cerca prima il nome della colonna «Strategy map
## infopic filename» del file prod (`infopic`, quello che usa l'originale: «Workshop Level 1» per l'armaiolo), poi il nome
## del livello e la famiglia, con le stesse regole delle tessere per le varianti di religione; le versioni «Coloured» solo
## se manca quella normale. Null se manca.
static func info_picture(label: String, family_id: String, religion: String = "", infopic: String = "") -> Texture2D:
	if not AssetLibrary.is_available():
		return null
	if _info_by_name.is_empty():
		for p in AssetLibrary.list(INFO_ROOT):
			var key := str(p).get_file().get_basename().to_lower()
			if not _info_by_name.has(key):
				_info_by_name[key] = []
			(_info_by_name[key] as Array).append(str(p))
	var plain := label.strip_edges().to_lower()
	var no_digits := plain.rstrip("0123456789").strip_edges()
	var family := family_id.to_lower().replace("_", " ")
	for name in [infopic.strip_edges().to_lower(), plain, no_digits, family]:
		if name == "" or not _info_by_name.has(name):
			continue
		var all: Array = _info_by_name[name]
		var normal: Array = all.filter(func(x: Variant) -> bool: return not str(x).contains("/coloured/"))
		var path := choose(normal if not normal.is_empty() else all, religion, INFO_ROOT)
		if path != "":
			return AssetLibrary.texture(path)
	return null


## Cartelle delle varianti da provare per la religione, nell'ordine (in minuscolo). Senza religione: come i cattolici.
static func religion_folders(religion: String) -> PackedStringArray:
	if religion.to_upper().contains("DHARMA"):
		return PackedStringArray(["asian", "pagan"])   # Dharma: icone proprie (asian), poi quelle dei pagani
	if religion.to_upper().contains("IMPERIAL"):
		return PackedStringArray([AUROR_FOLDER, "catholic", "christian"])   # Culto Imperiale: icone Auror, poi le cattoliche
	var folder := PortraitArt.religion_folder(religion if religion != "" else "CATHOLIC").to_lower()
	if folder == "catholic" or folder == "orthodox":
		return PackedStringArray([folder, "christian"])
	return PackedStringArray([folder])


## Percorso scelto tra le varianti dello stesso nome: la cartella della religione (poi Christian), poi le varianti delle
## altre religioni (una moschea vista da un cattolico, una chiesa da un musulmano), poi la cartella principale, poi la
## prima. Dove esistono varianti l'immagine della cartella principale e' quasi sempre un segnaposto.
static func choose(paths: Array, religion: String, root: String = ROOT) -> String:
	if paths.is_empty():
		return ""
	var order := religion_folders(religion)
	for other in VARIANT_FOLDERS:
		if not order.has(other):
			order.append(other)
	for folder in order:
		for p in paths:
			if str(p).to_lower().contains("/%s/" % folder):
				return str(p)
	for p in paths:
		if str(p).trim_prefix(root).find("/") < 0:
			return str(p)
	for p in paths:
		if not str(p).to_lower().contains("/%s/" % AUROR_FOLDER):
			return str(p)
	return str(paths[0])


static func _ensure() -> void:
	if not _by_name.is_empty() or not AssetLibrary.is_available():
		return
	for p in AssetLibrary.list(ROOT):
		var file := str(p).get_file()
		var name := file.get_basename().to_lower()
		if not _by_name.has(name):
			_by_name[name] = []
		(_by_name[name] as Array).append(str(p))
