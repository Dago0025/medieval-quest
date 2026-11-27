class_name SiteLayer
extends Control
## Luoghi leggendari sulla mappa (richiesta di Federico del 26/11/2026): di norma un pallino discreto, che non disturba la
## vista di gioco; al passaggio del mouse il pallino diventa il medaglione del luogo (simbolo disegnato a codice,
## assets/luoghi/simboli) con il nome sotto. Si vedono solo i luoghi gia' scoperti dal giocatore. Sta sotto le pedine
## (stesso sistema di coordinate di ArmyLayer: mondo -> vista piatta -> prospettiva). Non riceve il mouse: lo interroga
## la mappa con `site_at`.

const DOT_RADIUS := 4.5                  ## raggio del pallino, in pixel dello schermo
const DOT_HIT := 11.0                     ## raggio cliccabile del pallino
const MEDALLION := 44.0                   ## diametro del medaglione al passaggio del mouse
const MEDALLION_HIT := 24.0
const MEDALLION_ALL := 34.0               ## medaglioni tutti aperti dalla bussola della minimappa
const LABEL_ALL := 11                     ## corpo dei nomi con i medaglioni tutti aperti
const RING := Color(0.86, 0.71, 0.36)
const OUTLINE := Color(0.12, 0.08, 0.04, 0.85)
const PENDING := Color(0.72, 0.10, 0.08)
const PLATE := Color(0.93, 0.88, 0.75, 0.95)
const PLATE_BORDER := Color(0.59, 0.44, 0.20)
const INK := Color(0.20, 0.13, 0.08)


class Entry:
	extends RefCounted
	var id := ""
	var world := Vector2.ZERO
	var category := ""
	var label := ""
	var texture: Texture2D = null
	var pending := false
	var inactive := false


var _entries: Array[Entry] = []
var _hovered := ""
var _show_all := false
var _center := Vector2.ZERO
var _zoom := 1.0
var _view := Vector2.ZERO
var _projection: MapProjection = null
var _tilt_seen := 0.0
var _screen_seen := Vector2.ZERO
var _textures := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Luoghi da mostrare: [{"id", "pos" (pixel del mondo), "categoria", "simbolo", "nome", "in_attesa", "inattivo"}].
func set_sites(list: Array[Dictionary]) -> void:
	_entries.clear()
	for d in list:
		var e := Entry.new()
		e.id = str(d["id"])
		e.world = d["pos"]
		e.category = str(d.get("categoria", ""))
		e.label = str(d.get("nome", ""))
		e.pending = bool(d.get("in_attesa", false))
		e.inactive = bool(d.get("inattivo", false))
		e.texture = _texture(str(d.get("simbolo", "")), e.category)
		_entries.append(e)
	if _hovered != "" and not has_site(_hovered):
		_hovered = ""
	queue_redraw()


func has_site(site_id: String) -> bool:
	for e in _entries:
		if e.id == site_id:
			return true
	return false


func site_count() -> int:
	return _entries.size()


## Bussola della minimappa: medaglioni e nomi di tutti i luoghi scoperti invece dei pallini.
func set_show_all(on: bool) -> void:
	if on == _show_all:
		return
	_show_all = on
	queue_redraw()


func show_all() -> bool:
	return _show_all


func hovered() -> String:
	return _hovered


func set_hovered(site_id: String) -> void:
	if site_id == _hovered:
		return
	_hovered = site_id
	queue_redraw()


static func texture_path(symbol: String, category: String) -> String:
	return "res://assets/luoghi/simboli/%s_%s.png" % [symbol, category]


func _texture(symbol: String, category: String) -> Texture2D:
	var path := texture_path(symbol, category)
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[path] = tex
	return tex


## Stessa vista di ArmyLayer.set_view.
func set_view(center: Vector2, zoom: float, view_size: Vector2, projection: MapProjection = null) -> void:
	var tilt := projection.tilt if projection != null else 1.0
	var screen := projection.screen_size if projection != null else view_size
	if center == _center and is_equal_approx(zoom, _zoom) and view_size == _view and projection == _projection and is_equal_approx(tilt, _tilt_seen) and screen == _screen_seen:
		return
	_center = center
	_zoom = zoom
	_view = view_size
	_projection = projection
	_tilt_seen = tilt
	_screen_seen = screen
	queue_redraw()


func _to_screen(world: Vector2) -> Vector2:
	var flat := (world - _center) * _zoom + _view / 2.0
	return _projection.flat_to_screen(flat) if _projection != null else flat


func _screen_size() -> Vector2:
	return _projection.screen_size if _projection != null else _view


## Id del luogo sotto `screen` ("" se nessuno): il medaglione aperto ha un'area piu' grande del pallino.
func site_at(screen: Vector2) -> String:
	var best := ""
	var best_d := INF
	for e in _entries:
		var p := _to_screen(e.world)
		var radius := MEDALLION_HIT if e.id == _hovered else (MEDALLION_ALL * 0.55 if _show_all else DOT_HIT)
		var d := p.distance_to(screen)
		if d <= radius and d < best_d:
			best = e.id
			best_d = d
	return best


## Punto sullo schermo del luogo (per i test e per portare la mappa sul luogo).
func screen_point(site_id: String) -> Vector2:
	for e in _entries:
		if e.id == site_id:
			return _to_screen(e.world)
	return Vector2.INF


func _draw() -> void:
	var screen := _screen_size()
	var hovered_entry: Entry = null
	var shown: Array[Entry] = []
	for e in _entries:
		var p := _to_screen(e.world)
		if p.x < -60.0 or p.y < -60.0 or p.x > screen.x + 60.0 or p.y > screen.y + 60.0:
			continue
		if e.id == _hovered:
			hovered_entry = e
			continue
		if _show_all:
			shown.append(e)
			continue
		_draw_dot(p, e)
	if _show_all:
		# dall'alto in basso, cosi' il medaglione piu' in basso copre quello sopra; un nome che coprirebbe un altro gia'
		# scritto si salta (si legge col passaggio del mouse)
		shown.sort_custom(func(a: Entry, b: Entry) -> bool: return a.world.y < b.world.y)
		var plates: Array[Rect2] = []
		for e in shown:
			_draw_medallion(_to_screen(e.world), e, MEDALLION_ALL, LABEL_ALL, plates)
	if hovered_entry != null:
		_draw_medallion(_to_screen(hovered_entry.world), hovered_entry)


func _draw_dot(p: Vector2, e: Entry) -> void:
	var fill: Color = CampaignUiSites.CATEGORY_COLORS.get(e.category, Color(0.6, 0.45, 0.2))
	if e.inactive:
		fill = fill.lerp(Color(0.45, 0.45, 0.45), 0.7)
	draw_circle(p + Vector2(0.6, 1.0), DOT_RADIUS + 1.6, Color(0, 0, 0, 0.35))
	draw_circle(p, DOT_RADIUS + 1.6, OUTLINE)
	draw_circle(p, DOT_RADIUS + 0.8, RING)
	draw_circle(p, DOT_RADIUS - 0.4, fill)
	if e.pending:
		draw_circle(p + Vector2(DOT_RADIUS + 1.5, -DOT_RADIUS - 1.5), 2.6, PENDING)


func _draw_medallion(p: Vector2, e: Entry, diameter: float = MEDALLION, label_size: int = 13, plates = null) -> void:
	if e.texture != null:
		# l'immagine ha un margine per l'ombra e l'alone: il disco e' 88 px su (88 + 24)
		var full := diameter * float(e.texture.get_width()) / 88.0
		draw_texture_rect(e.texture, Rect2(p - Vector2(full, full) / 2.0, Vector2(full, full)), false)
	else:
		draw_circle(p, diameter / 2.0, OUTLINE)
		draw_circle(p, diameter / 2.0 - 2.0, RING)
	if e.pending:
		var c := p + Vector2(diameter * 0.38, -diameter * 0.38)
		draw_circle(c, 7.0, PENDING)
		var f := get_theme_default_font()
		draw_string(f, c + Vector2(-2.5, 4.5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.92, 0.8))
	if e.label != "":
		var font: Font = UiTheme.crisp_text_bold()
		var size := label_size
		var w := font.get_string_size(e.label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var box := Rect2(p + Vector2(-w / 2.0 - 8.0, diameter / 2.0 + 3.0), Vector2(w + 16.0, size + 9.0))
		if plates != null:
			for r in plates:
				if (r as Rect2).intersects(box):
					return
			plates.append(box)
		draw_style_box(_plate_box(), box)
		draw_string(font, Vector2(box.position.x + 8.0, box.position.y + size + 2.0), e.label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK)


var _plate: StyleBoxFlat = null


func _plate_box() -> StyleBoxFlat:
	if _plate == null:
		_plate = StyleBoxFlat.new()
		_plate.bg_color = PLATE
		_plate.border_color = PLATE_BORDER
		_plate.set_border_width_all(1)
		_plate.set_corner_radius_all(5)
		_plate.shadow_color = Color(0, 0, 0, 0.3)
		_plate.shadow_size = 3
	return _plate
