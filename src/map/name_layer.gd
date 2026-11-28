class_name NameLayer
extends Node2D
## Nomi delle regioni scritti sulla mappa del mondo (ADR-077, segnalazione di Federico del 16/11/2026: «non vedo i nomi delle
## regioni»). La MapTex originale aveva i nomi dipinti; la plancia del mondo no, cosi' i nomi seguono la lingua scelta.
##
## Ogni nome sta nel punto della regione scelto da tools/mondo/etichette.py (WorldMap.labels), con un corpo in pixel della mappa che cresce con
## l'estensione della regione: le province piccole si leggono avvicinandosi, le grandi (Siberia, Sahara) anche da lontano.
## Sotto i MIN_PX pixel dello schermo un nome non si disegna, tra MIN_PX e FULL_PX sfuma. Il mare e' in maiuscolo e
## azzurro. Il livello legge da solo lo zoom della camera e si ridisegna quando cambia.

const MIN_PX := 7.0
const FULL_PX := 10.0
const MAX_LAND_PX := 28.0      ## corpo massimo sullo schermo: avvicinandosi i nomi non crescono oltre
const MAX_SEA_PX := 32.0
const BASE_SIZE := 32          ## corpo a cui si disegna, poi scalato (MSDF: nitido a ogni scala)
const LAND_COLOR := Color(0.20, 0.13, 0.06, 0.92)
const LAND_OUTLINE := Color(0.93, 0.88, 0.74, 0.75)
const SEA_COLOR := Color(0.12, 0.24, 0.36, 0.80)
const SEA_OUTLINE := Color(0.80, 0.86, 0.86, 0.55)

var camera: Camera2D
var shown := true
var _entries: Array[Dictionary] = []   ## {pos: Vector2, text: String, size: float, sea: bool}
var _font: Font
var _zoom := -1.0


## Nomi delle regioni di `campaign` nei punti di `map` (dimensione del corpo da `map.sizes`).
func set_regions(campaign: CampaignData, map: WorldMap) -> void:
	_entries.clear()
	if _font == null:
		_font = UiTheme.crisp_font(UiTheme.FONT_TITLE_CRISP)
	for r in campaign.regions:
		if not map.anchors.has(r.id):
			continue
		var name := RegionNames.shown(campaign, r.id)
		var area := float(map.sizes.get(r.id, 4000))
		var size := clampf(sqrt(area) / (9.0 if r.is_sea else 7.5), 15.0, 72.0)
		var text := name.to_upper() if r.is_sea else name
		var pos: Vector2 = map.labels.get(r.id, map.anchors[r.id])
		if r.is_sea:
			size = _fit_on_water(map, pos, text, size)
		_entries.append({"pos": pos, "text": text, "size": size, "sea": r.is_sea})
	queue_redraw()


## Corpo del nome di un mare ridotto finche' la scritta sta tutta sull'acqua (segnalazione di Federico del 28/11/2026: da
## lontano i nomi dei mari coprivano le terre, soprattutto nel Mediterraneo dalle zone unite): la larghezza libera e' quella
## dell'acqua a destra e a sinistra del punto, sulla riga del nome e sopra e sotto di essa.
func _fit_on_water(map: WorldMap, pos: Vector2, text: String, size: float) -> float:
	var base_w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BASE_SIZE).x / float(BASE_SIZE)
	for _i in 3:
		var half := 0.0
		for dy in [-0.4, 0.0, 0.4]:
			var y := int(pos.y + dy * size)
			var run := minf(_water_run(map, pos.x, y, -1.0), _water_run(map, pos.x, y, 1.0))
			half = run if dy == -0.4 else minf(half, run)
		var fit := (2.0 * half * 0.9) / maxf(base_w, 0.01)
		if fit >= size:
			break
		size = maxf(fit, 6.0)
	return size


## Pixel d'acqua contigui dal punto verso `dir` (-1 sinistra, +1 destra), a passi di 4, fino a 4000.
static func _water_run(map: WorldMap, x: float, y: int, dir: float) -> float:
	var d := 0.0
	while d < 4000.0:
		var xi := int(x + dir * (d + 4.0))
		if xi < 0 or xi >= map.width:
			xi = posmod(xi, map.width)   # il Pacifico si richiude sul bordo
		if map.index_at(xi, y) < map.sea_first:
			break
		d += 4.0
	return d


func set_shown(on: bool) -> void:
	shown = on
	queue_redraw()


func _process(_delta: float) -> void:
	if camera == null:
		return
	var z := camera.zoom.x
	if absf(z - _zoom) > maxf(_zoom, 0.0001) * 0.01:
		_zoom = z
		queue_redraw()


func _draw() -> void:
	if not shown or _font == null or _zoom <= 0.0:
		return
	for e in _entries:
		var size: float = e["size"]
		var sea: bool = e["sea"]
		var screen_px := size * _zoom
		if screen_px < MIN_PX:
			continue
		var cap := MAX_SEA_PX if sea else MAX_LAND_PX
		if screen_px > cap:
			size = cap / _zoom
		var alpha := clampf((screen_px - MIN_PX) / (FULL_PX - MIN_PX), 0.0, 1.0)
		var text: String = e["text"]
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BASE_SIZE).x
		var outline := SEA_OUTLINE if sea else LAND_OUTLINE
		var color := SEA_COLOR if sea else LAND_COLOR
		outline.a *= alpha
		color.a *= alpha
		var k := size / float(BASE_SIZE)
		draw_set_transform(e["pos"], 0.0, Vector2(k, k))
		var at := Vector2(-width / 2.0, BASE_SIZE * 0.35)
		draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, BASE_SIZE, 6, outline)
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, BASE_SIZE, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
