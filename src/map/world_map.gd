class_name WorldMap
extends LbmReader
## Mappa del mondo di Medieval Quest (ADR-077, richiesta di Federico del 15/11/2026: «espandere la mappa a tutto il mondo,
## con le stesse logiche; mantieni la divisione attuale dell'Europa»). Prende il posto di LukMap.Lbm quando i dati di
## `data/mappa_mondo/` ci sono.
##
## - `regioni.png`: bitmap delle regioni a 16 bit, indice = R + 256 G (0 = nessuna regione, terra 1.., mare `sea_first`..).
##   Una sola voce per regione: il gruppo della regione e' l'indice stesso (RegionMap in modalita' mondo).
## - `regioni_auror.png`, `plancia_auror.jpg`, `confini_auror.bin`: la stessa mappa con l'isola di Atlantide (ADR-078), solo
##   in modalita' Auror.
## - `mondo.json`: dimensioni, `sea_first` e per ogni regione id, indice, mare sì/no, `auror` (solo con l'isola) e `origin`
##   (punto interno, ancora delle zone di mare).
## - `plancia.jpg`: la plancia dipinta, alla stessa risoluzione della bitmap.
## - `confini.bin`: confini vettoriali precalcolati (BorderExtractor.load_world).
## - `startpos_mondo.txt`, `startpos_atlantide.txt`: righe dello startpos per la geometria del mondo (`startpos_text`).
## Tutto e' generato da tools/mondo/ (vedi tools/mondo/LEGGIMI.md).

const DIR := "res://data/mappa_mondo/"
const INFO_FILE := DIR + "mondo.json"
const STARTPOS_FILE := DIR + "startpos_mondo.txt"
const ATLANTIS_FILE := DIR + "startpos_atlantide.txt"
## Zone di mare dell'installazione unite ad altre sulla mappa del mondo (Mediterraneo meno frammentato, 16/11/2026).
const MERGED_SEAS_FILE := DIR + "mari_uniti.cfg"
const MAP_ID := "mondo"
## Larghezza / altezza della mappa del mondo (12960 x 5396): proporzioni della minimappa.
const ASPECT := 12960.0 / 5396.0
## Righe dello startpos originale che la geometria del mondo sostituisce.
const REPLACED_COMMANDS := ["SetNeighbours", "SetCastle", "SetOrigin", "SetPort", "SetBorderInfo"]

## false = mappa d'Europa originale anche se i dati del mondo ci sono (test).
static var enabled := true

var sea_first := 1024
var auror_variant := false
var index_of := {}     ## id della regione -> indice
var anchors := {}      ## id della regione -> Vector2 (centro di un pixel interno)
var sizes := {}        ## id della regione -> pixel della regione (corpo dei nomi, NameLayer)
var labels := {}       ## id della regione -> Vector2 del nome (lontano da bordi e castello, NameLayer)
var auror_only := {}   ## id delle regioni che esistono solo con l'isola
var _rg := PackedByteArray()


## Vero se la mappa del mondo e' in uso.
static func available() -> bool:
	return enabled and FileAccess.file_exists(INFO_FILE)


## Mappa dei salvataggi: "mondo" oppure "europa" (LukMap originale).
static func map_id() -> String:
	return MAP_ID if available() else "europa"


static func index_path(auror: bool) -> String:
	return DIR + ("regioni_auror.png" if auror else "regioni.png")


static func texture_path(auror: bool) -> String:
	return DIR + ("plancia_auror.jpg" if auror else "plancia.jpg")


static func borders_path(auror: bool) -> String:
	return DIR + ("confini_auror.bin" if auror else "confini.bin")


## Legge la mappa (con l'isola di Atlantide se `auror`). Controllare is_valid().
static func load_map(auror: bool) -> WorldMap:
	var m := WorldMap.new()
	m.auror_variant = auror
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INFO_FILE))
	if typeof(parsed) != TYPE_DICTIONARY:
		m.error = "Dati della mappa del mondo non leggibili: %s" % INFO_FILE
		return m
	var info: Dictionary = parsed
	m.sea_first = int(info.get("sea_first", 1024))
	for item in info.get("regions", []):
		var r: Dictionary = item
		var rid := str(r.get("id", "")).to_upper()
		if bool(r.get("auror", false)):
			m.auror_only[rid] = true
			if not auror:
				continue
		m.index_of[rid] = int(r.get("index", 0))
		var o: Array = r.get("origin", [0, 0])
		m.anchors[rid] = Vector2(float(o[0]) + 0.5, float(o[1]) + 0.5)
		m.sizes[rid] = int(r.get("pixels", 0))
		var l: Array = r.get("label", o)
		m.labels[rid] = Vector2(float(l[0]) + 0.5, float(l[1]) + 0.5)
	var img := _read_image(index_path(auror))
	if img == null:
		m.error = "Bitmap delle regioni del mondo non leggibile: %s" % index_path(auror)
		return m
	img.convert(Image.FORMAT_RG8)
	m.width = img.get_width()
	m.height = img.get_height()
	m.bit_planes = 16
	m._rg = img.get_data()
	if m.width != int(info.get("width", m.width)) or m.height != int(info.get("height", m.height)):
		m.error = "Dimensioni della bitmap del mondo diverse da mondo.json"
	return m


## Immagine da un file del progetto (anche dentro il pacchetto esportato: i file di data/mappa_mondo non sono importati).
static func _read_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match path.get_extension().to_lower():
		"png":
			err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
	return img if err == OK and not img.is_empty() else null


## Plancia dipinta del mondo (con l'isola se `auror`).
static func load_texture_image(auror: bool) -> Image:
	return _read_image(texture_path(auror))


func is_valid() -> bool:
	return error == "" and width > 0 and _rg.size() == width * height * 2


func index_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	var i := (y * width + x) * 2
	return _rg[i] | (_rg[i + 1] << 8)


## Immagine a due canali (FORMAT_RG8): lo shader ricompone l'indice come R + 256 G.
func to_image() -> Image:
	if not is_valid():
		return null
	return Image.create_from_data(width, height, false, Image.FORMAT_RG8, _rg)


## Startpos per la geometria del mondo: toglie da `text` confinanti, castelli, origini, porti e punti di confine
## dell'originale e aggiunge le righe di startpos_mondo.txt (regioni nuove, posizioni, confinanti) e, con `auror`,
## quelle dell'isola di Atlantide. Le righe in `extra` (gli Auror spostati sull'isola) vanno in fondo, dopo le regioni nuove.
static func startpos_text(text: String, auror: bool, extra: String = "") -> String:
	var out := PackedStringArray()
	var aliases := merged_seas()
	for line in text.replace("\r", "").split("\n"):
		var s := line.strip_edges()
		var cmd := s.get_slice("::", 0).strip_edges() if s.contains("::") else ""
		if cmd in REPLACED_COMMANDS:
			continue
		if cmd == "DeclareSeaRegion" and aliases.has(s.get_slice("::", 1).strip_edges().trim_prefix("\"").trim_suffix("\"").to_upper()):
			continue   # zona unita a un'altra (mari_uniti.cfg)
		out.append(_replace_merged(line, aliases))
	out.append(TextIO.read_latin1(STARTPOS_FILE).replace("\r", ""))
	if auror and FileAccess.file_exists(ATLANTIS_FILE):
		out.append(TextIO.read_latin1(ATLANTIS_FILE).replace("\r", ""))
	if extra != "":
		out.append(_replace_merged(extra, aliases))
	return "\n".join(out)


static var _merged := {}
static var _merged_loaded := false


## Zone di mare unite (data/mappa_mondo/mari_uniti.cfg, sezione [uniti]): zona tolta -> zona che la assorbe. Richiesta di
## Federico del 16/11/2026: «il Mediterraneo e' fin troppo frammentato, riduci i segmenti di mare» (da 22 zone a 10).
static func merged_seas() -> Dictionary:
	if not _merged_loaded:
		_merged_loaded = true
		var cfg := ConfigFile.new()
		if FileAccess.file_exists(MERGED_SEAS_FILE) and cfg.load(MERGED_SEAS_FILE) == OK and cfg.has_section("uniti"):
			for key in cfg.get_section_keys("uniti"):
				_merged[key.to_upper()] = str(cfg.get_value("uniti", key)).to_upper()
	return _merged


## Zona che ha preso il posto di `region_id` (la stessa se non e' stata unita a un'altra).
static func merged_id(region_id: String) -> String:
	return str(merged_seas().get(region_id, region_id))


## `text` con le zone unite sostituite da quelle che le assorbono (parole intere).
static func _replace_merged(text: String, aliases: Dictionary) -> String:
	if aliases.is_empty() or not text.contains("ID_"):
		return text
	var out := text
	for old in aliases:
		if out.contains(old):
			var re := RegEx.create_from_string("\\b%s\\b" % old)
			out = re.sub(out, str(aliases[old]), true)
	return out
