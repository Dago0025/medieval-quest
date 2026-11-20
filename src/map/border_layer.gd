class_name BorderLayer
extends Node2D
## Livello dei confini vettoriali della mappa della campagna: ogni polilinea di BorderExtractor con spessore costante in
## pixel dello schermo (lo spessore nel mondo e' px / zoom, ricalcolato quando cambia lo zoom).
##
## Sulla mappa del mondo (ADR-077) le polilinee sono circa 10.000 con quasi 600.000 punti: ridisegnarle tutte a ogni scatto
## della rotella rendeva lo zoom stentato (segnalazione di Federico del 16/11/2026). Per questo:
## - le polilinee sono spezzate in pezzi e divise in riquadri (BorderTile, un CanvasItem ciascuno); quando cambia lo zoom
##   si ridisegnano subito solo i riquadri nella vista, gli altri quando entrano nella vista (`set_view`);
## - ogni pezzo ha versioni semplificate (punti a distanza minima 2, 6, 18 pixel della mappa): con la mappa lontana si
##   disegna quella che a schermo non perde dettaglio (circa 2,5 pixel dello schermo tra un punto e l'altro);
## - la provincia scelta si evidenzia in un nodo a parte, sopra i riquadri.

const LAND_COLOR := Color(0.07, 0.04, 0.02, 0.85)      ## confine terra-terra
const COAST_COLOR := Color(0.04, 0.10, 0.20, 0.95)     ## costa (terra-mare, terra-nessuna regione)
const SEA_COLOR := Color(0.12, 0.25, 0.45, 0.28)       ## confine marino tenue
const HIGHLIGHT_COLOR := Color(1.0, 0.88, 0.25, 1.0)   ## provincia selezionata
const LAND_WIDTH := 1.5
const COAST_WIDTH := 1.8
const SEA_WIDTH := 1.0
const HIGHLIGHT_WIDTH := 3.5

const TILE := 1024.0                          ## lato di un riquadro in pixel della mappa
const PIECE_POINTS := 256                     ## punti massimi di un pezzo di polilinea
const LOD_STEPS := [0.0, 2.0, 6.0, 18.0]      ## distanza minima tra i punti di ogni versione (0 = tutti i punti)
const SCREEN_STEP := 2.5                      ## distanza a schermo sotto cui i punti in piu' non si notano
const VIEW_MARGIN := 0.15                     ## margine della vista (frazione) entro cui i riquadri si tengono aggiornati

var borders: Array[BorderExtractor.Border] = []
var zoom := 1.0
var selected_group := -1
var _by_group := {}     ## gruppo -> PackedInt32Array con gli indici delle polilinee che lo riguardano
var _tiles := {}        ## Vector2i -> BorderTile
var _view := Rect2()    ## rettangolo della mappa in vista (vuoto = sconosciuto: si ridisegna tutto)
var _highlight: Node2D


## Pezzo di polilinea con le sue versioni semplificate.
class Piece:
	var kind := 0
	var lods: Array[PackedVector2Array] = []


## Riquadro: disegna i suoi pezzi con lo spessore e la versione adatti allo zoom ricevuto.
class BorderTile extends Node2D:
	var pieces: Array = []
	var bounds := Rect2()
	var drawn_zoom := -1.0
	var draw_zoom := 1.0

	func refresh(z: float) -> void:
		if z != drawn_zoom:
			draw_zoom = z
			drawn_zoom = z
			queue_redraw()

	func _draw() -> void:
		var unit := 1.0 / draw_zoom
		var lod := BorderLayer.lod_for(draw_zoom)
		for p: BorderLayer.Piece in pieces:
			var pts: PackedVector2Array = p.lods[mini(lod, p.lods.size() - 1)]
			if pts.size() < 2:
				continue
			draw_polyline(pts, BorderLayer.color_for(p.kind), BorderLayer.width_for(p.kind) * unit, true)


## Evidenziazione della provincia scelta (polilinee intere, versione completa).
class Highlight extends Node2D:
	var layer: BorderLayer

	func _draw() -> void:
		if layer == null or layer.selected_group < 0:
			return
		var ids: PackedInt32Array = layer._by_group.get(layer.selected_group, PackedInt32Array())
		for i in ids:
			draw_polyline(layer.borders[i].points, BorderLayer.HIGHLIGHT_COLOR, BorderLayer.HIGHLIGHT_WIDTH / layer.zoom, true)


func _init() -> void:
	_highlight = Highlight.new()
	_highlight.name = "Highlight"
	(_highlight as Highlight).layer = self
	_highlight.z_index = 1
	add_child(_highlight)


static func color_for(kind: int) -> Color:
	match kind:
		BorderExtractor.KIND_COAST, BorderExtractor.KIND_LAND_NONE:
			return COAST_COLOR
		BorderExtractor.KIND_SEA_SEA, BorderExtractor.KIND_SEA_NONE:
			return SEA_COLOR
	return LAND_COLOR


static func width_for(kind: int) -> float:
	match kind:
		BorderExtractor.KIND_COAST, BorderExtractor.KIND_LAND_NONE:
			return COAST_WIDTH
		BorderExtractor.KIND_SEA_SEA, BorderExtractor.KIND_SEA_NONE:
			return SEA_WIDTH
	return LAND_WIDTH


## Versione da disegnare allo zoom `z`: la piu' semplificata i cui punti distano a schermo meno di SCREEN_STEP.
static func lod_for(z: float) -> int:
	var best := 0
	for i in range(1, LOD_STEPS.size()):
		if float(LOD_STEPS[i]) * z <= SCREEN_STEP:
			best = i
	return best


## Punti a distanza minima `step` (il primo e l'ultimo restano sempre).
static func decimate(points: PackedVector2Array, step: float) -> PackedVector2Array:
	if step <= 0.0 or points.size() <= 2:
		return points
	var out := PackedVector2Array([points[0]])
	var last := points[0]
	var step2 := step * step
	for i in range(1, points.size() - 1):
		if points[i].distance_squared_to(last) >= step2:
			out.append(points[i])
			last = points[i]
	out.append(points[points.size() - 1])
	return out


func set_borders(list: Array[BorderExtractor.Border]) -> void:
	borders = list
	_by_group.clear()
	for t in _tiles.values():
		(t as Node).queue_free()
	_tiles.clear()
	for i in range(borders.size()):
		var b := borders[i]
		for g in [b.group_a, b.group_b]:
			var ids: PackedInt32Array = _by_group.get(g, PackedInt32Array())
			ids.append(i)
			_by_group[g] = ids
		_add_pieces(b)
	for t in _tiles.values():
		(t as BorderTile).drawn_zoom = -1.0
	_refresh_tiles()
	_highlight.queue_redraw()


func _add_pieces(b: BorderExtractor.Border) -> void:
	var n := b.points.size()
	if n < 2:
		return
	var start := 0
	while start < n - 1:
		var end := mini(start + PIECE_POINTS, n - 1)
		var pts := b.points.slice(start, end + 1)
		var p := Piece.new()
		p.kind = b.kind
		for step in LOD_STEPS:
			p.lods.append(decimate(pts, float(step)))
		var key := Vector2i(floori(pts[0].x / TILE), floori(pts[0].y / TILE))
		var tile: BorderTile = _tiles.get(key)
		if tile == null:
			tile = BorderTile.new()
			tile.name = "Tile_%d_%d" % [key.x, key.y]
			tile.bounds = Rect2(pts[0], Vector2.ZERO)
			_tiles[key] = tile
			add_child(tile)
			move_child(tile, 0)   # sotto l'evidenziazione
		tile.pieces.append(p)
		for q in pts:
			tile.bounds = tile.bounds.expand(q)
		start = end


func set_zoom(new_zoom: float) -> void:
	# Evita di ricostruire la geometria per variazioni impercettibili.
	if absf(new_zoom - zoom) > zoom * 0.002:
		zoom = new_zoom
		_refresh_tiles()
		_highlight.queue_redraw()


## Rettangolo della mappa in vista (coordinate della mappa): i riquadri che vi entrano si aggiornano allo zoom attuale.
func set_view(rect: Rect2) -> void:
	if rect.is_equal_approx(_view):
		return
	_view = rect
	_refresh_tiles()


func set_selected_group(group: int) -> void:
	if group != selected_group:
		selected_group = group
		_highlight.queue_redraw()


func _refresh_tiles() -> void:
	var view := _view.grow_individual(_view.size.x * VIEW_MARGIN, _view.size.y * VIEW_MARGIN,
		_view.size.x * VIEW_MARGIN, _view.size.y * VIEW_MARGIN)
	for t in _tiles.values():
		var tile := t as BorderTile
		if _view.has_area() and not view.intersects(tile.bounds.grow(4.0)):
			continue
		tile.refresh(zoom)


## Riquadri (per i test): numero totale e quanti sono aggiornati allo zoom attuale.
func tile_counts() -> Vector2i:
	var fresh := 0
	for t in _tiles.values():
		if is_equal_approx((t as BorderTile).drawn_zoom, zoom):
			fresh += 1
	return Vector2i(_tiles.size(), fresh)
