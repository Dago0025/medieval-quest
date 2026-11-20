extends Control
## Segnalini di eserciti e flotte e frecce dei movimenti, disegnati in coordinate dello
## schermo (testo e linee restano nitidi a ogni zoom) sopra la mappa. Non cattura il mouse:
## i clic arrivano a campaign_map.gd, che chiede `army_at` per sapere se è stato colpito un segnalino.
## Dalla fase 5a disegna anche i segnalini degli agenti (tondi, con l'iniziale del tipo e il valore).
## Dalla fase 5c un esercito crociato porta sopra il segnalino un distintivo: croce (crociata) o mezzaluna (jihad).
## Dal 2026-11-09 ogni provincia con un castello lo mostra (immagine dell'originale per grado), sotto le pedine.
## Dalla fase 8, quando c'e' l'immagine, eserciti, flotte e agenti sono le pedine dell'originale (PieceArt) con i piedi sul
## punto del segnalino, senza numero come nell'originale (scelta di Federico: le pile si vedono nel pannello dell'esercito);
## senza immagini restano i segnalini disegnati con il numero.
## Dal 2026-11-10 disegna il riquadro della selezione multipla e solleva insieme le pedine scelte quando se ne trascina una.
## Contiene solo il disegno; la disposizione sta in MarkerLayout.

const HALF := 11.0                      ## metà del lato del segnalino, in pixel dello schermo
const AGENT_RADIUS := 12.0              ## raggio del segnalino di un agente, in pixel dello schermo
const AGENT_FONT_SIZE := 12
const SLOT_SPACING := 24.0              ## distanza tra segnalini della stessa regione
const FONT_SIZE := 13
const SELECTED_COLOR := Color(1.0, 0.88, 0.25)
const ARROW_COLOR := Color(1.0, 0.95, 0.5, 0.95)
const ARROW_DIM_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const ARROW_HEAD := 12.0
const ATTACK_COLOR := Color(0.95, 0.15, 0.12, 0.95)
const ATTACK_DIM_COLOR := Color(0.85, 0.2, 0.18, 0.7)
const SIEGE_COLOR := Color(0.85, 0.1, 0.1)
const SIEGE_RADIUS := 8.0
const REACH_COLOR := Color(0.4, 0.85, 1.0, 0.85)    ## anello delle province raggiungibili via mare
const REACH_FILL := Color(0.4, 0.85, 1.0, 0.16)
const REACH_RADIUS := 15.0
const DASH_LENGTH := 11.0                           ## tratteggio della freccia del trasporto, in pixel dello schermo
const DASH_GAP := 7.0
const BADGE_RADIUS := 8.0                           ## distintivo dell'esercito crociato, in pixel dello schermo
const BADGE_LIFT := 12.0                            ## distanza del suo centro sopra il bordo alto del segnalino
const CRUSADE_BADGE_COLOR := Color(0.75, 0.1, 0.1)
const JIHAD_BADGE_COLOR := Color(0.1, 0.5, 0.25)
const BASE_HEIGHT := 60.0                           ## misura di riferimento della scala (castelli, porti, distanze tra pedine)
## Pedine piu' piccole (richiesta di Federico, 2026-11-10): l'esercito 46 invece di 60, l'agente 22 invece di 34 (la sua
## figura senza stendardo sembrava piu' grande di quella dell'esercito). Castelli e porti restano della misura di prima.
const PIECE_HEIGHT := 47.0                          ## altezza di una pedina (esercito, flotta), in pixel dello schermo (cornice 460 delle rifatte)
const CRUSADE_PIECE_SCALE := 1.25                  ## ADR-072, come nell'originale: la pedina di crociata e jihad e' piu' grande
const AGENT_PIECE_HEIGHT := 29.0                    ## altezza della pedina di un agente: cornice comune di 268 px con la base di
                                                    ## 148 per tutti (tools/prepara_pedine.py), base come prima (22 su 200 px)
const GHOST_ALPHA := 0.35                          ## pedina presa col mouse: l'ombra che resta al suo posto
const LIFT := 0.12                                  ## pedina sollevata: quanto sta sopra la sua ombra (frazione dell'altezza)
const LIFT_SCALE := 1.1
const PIECE_HALF_WIDTH := 9.0                      ## meta' larghezza dell'area cliccabile di una pedina (a dimensione base)
## Le pedine crescono con lo zoom (fase 8, Federico: «zoomando diventano minuscole»): altezza in pixel della bitmap, poi limitata.
const PIECE_WORLD_HEIGHT := 80.0
const PORT_HEIGHT := 27.6                           ## altezza dell'immagine del porto (fotogramma intero) a dimensione base: 46 dell'originale -40% col porto dipinto (Federico, 15/11/2026)
const CASTLE_HEIGHT := 39.6                         ## altezza del castello (con lo stendardo) a dimensione base: 66 -40% coi castelli dipinti (Federico, 15/11/2026)
const PIECE_MIN_SCALE := 0.75
const PIECE_MAX_SCALE := 2.6
## Castelli e porti continuano a crescere con lo zoom oltre il limite delle pedine (Federico, 15/11/2026: «zoomando sulle
## regioni i castelli diventano minuscoli»): -40% a zoom normale, ma da vicino crescono con la mappa fino a 8 volte (castello
## ~317 px, porto ~221 px allo zoom massimo; le pedine si fermano a 2,6).
const STRUCTURE_MAX_SCALE := 8.0
const BOX_FILL := Color(1.0, 0.88, 0.25, 0.12)      ## riquadro della selezione multipla (Alt + trascinamento)
const BOX_BORDER := Color(1.0, 0.88, 0.25, 0.9)


class Marker:
	var army_id := 0
	var anchor := Vector2.ZERO          ## punto della regione, coordinate del mondo (pixel della bitmap)
	var slot := Vector2.ZERO            ## scostamento in pixel dello schermo (segnalini affiancati)
	var color := Color.WHITE
	var text := ""
	var fleet := false
	var player := false
	var selected := false
	var badge := ""                     ## "" = esercito normale; CampaignUiPapacy.BADGE_CROSS o BADGE_CRESCENT (fase 5c)
	var piece: Texture2D = null         ## pedina dell'originale (fase 8), null = segnalino disegnato
	var hidden := false                 ## guarnigione nel castello: non si disegna ne' si clicca, ma si trascina dal castello


class AgentMarker:
	var agent_id := 0
	var anchor := Vector2.ZERO          ## punto della regione, coordinate del mondo
	var slot := Vector2.ZERO            ## scostamento in pixel dello schermo
	var color := Color.WHITE
	var text := ""                      ## iniziale del tipo e valore ("E3")
	var player := false
	var selected := false
	var piece: Texture2D = null         ## pedina dell'originale (fase 8), null = segnalino disegnato


class Arrow:
	var points := PackedVector2Array()  ## coordinate del mondo
	var selected := false
	var attack := false                 ## freccia rossa: la destinazione è ostile
	var dashed := false                 ## freccia tratteggiata: trasporto via mare


## Castello di una provincia (richiesta di Federico: come nell'originale): immagine del grado di castello con i piedi
## sull'ancora della regione, disegnata sotto pedine e simboli.
class CastleMark:
	var region_id := ""
	var anchor := Vector2.ZERO          ## punto della regione (SetCastle), coordinate del mondo
	var piece: Texture2D = null
	var scale := 1.0                    ## altezza rispetto agli altri castelli (la fortezza degli Auror e' piu' grande)


## Porto di una provincia (quando l'edificio PORT e' costruito), sulla costa nel punto di SetPort.
class PortMark:
	var anchor := Vector2.ZERO          ## coordinate del mondo
	var piece: Texture2D = null


class SiegeMark:
	var anchor := Vector2.ZERO          ## punto della regione, coordinate del mondo
	var slot := Vector2.ZERO            ## scostamento in pixel dello schermo
	var tooltip := ""


var _markers: Array[Marker] = []
var _agents: Array[AgentMarker] = []
var _arrows: Array[Arrow] = []
var _sieges: Array[SiegeMark] = []
var _castles: Array[CastleMark] = []
var _ports: Array[PortMark] = []
var _drag_from := Vector2.ZERO          ## linea della pedina trascinata (schermo); uguali = nessuna
var _drag_to := Vector2.ZERO
var _drag_kind := ""                    ## pedina presa col mouse (fase 8): "esercito", "agente" o "" = nessuna
var _drag_id := 0
var _drag_pos := Vector2.ZERO           ## puntatore (schermo)
var _drag_offset := Vector2.ZERO        ## piedi della pedina meno il punto in cui e' stata presa
var _followers := {}                    ## selezione multipla: id esercito -> piedi meno punto di presa (seguono la pedina presa)
var _box := Rect2()                     ## riquadro della selezione multipla (schermo); vuoto = nessuno
var _reach: PackedVector2Array = PackedVector2Array()   ## ancore (mondo) delle province raggiungibili via mare
var _center := Vector2.ZERO             ## punto del mondo al centro dello schermo
var _zoom := 1.0
var _view := Vector2(1280.0, 720.0)    ## vista piatta della camera (MapProjection.flat_size)
var _projection: MapProjection = null   ## null = vista dall'alto, schermo = vista piatta
var _tilt_seen := 1.0
var _screen_seen := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Svuota segnalini e frecce (prima di ricostruirli).
func clear_all() -> void:
	_markers.clear()
	_agents.clear()
	_arrows.clear()
	_sieges.clear()
	_castles.clear()
	_ports.clear()
	_reach.clear()


## `badge`: distintivo dell'esercito crociato (fase 5c), "" per gli altri.
func add_marker(army_id: int, anchor: Vector2, slot: Vector2, color: Color, text: String, fleet: bool, player: bool, selected: bool, badge: String = "", piece: Texture2D = null) -> void:
	var m := Marker.new()
	m.army_id = army_id
	m.anchor = anchor
	m.slot = slot
	m.color = color
	m.text = text
	m.fleet = fleet
	m.player = player
	m.selected = selected
	m.badge = badge
	m.piece = piece
	_markers.append(m)


## Segnalino di un agente (fase 5a): tondo del colore della fazione con `text` (iniziale e valore).
func add_agent_marker(agent_id: int, anchor: Vector2, slot: Vector2, color: Color, text: String, player: bool, selected: bool, piece: Texture2D = null) -> void:
	var m := AgentMarker.new()
	m.agent_id = agent_id
	m.anchor = anchor
	m.slot = slot
	m.color = color
	m.text = text
	m.player = player
	m.selected = selected
	m.piece = piece
	_agents.append(m)


func add_arrow(points: PackedVector2Array, selected: bool, attack: bool = false, dashed: bool = false) -> void:
	var a := Arrow.new()
	a.points = points
	a.selected = selected
	a.attack = attack
	a.dashed = dashed
	_arrows.append(a)


## Evidenzia una provincia raggiungibile via mare (anello leggero sul suo castello).
func add_reach_mark(anchor: Vector2) -> void:
	_reach.append(anchor)


## Linea dalla pedina presa al puntatore mentre la si trascina (fase 8); due punti uguali la tolgono. Resta per i segnalini
## disegnati (senza esportazione delle immagini): le pedine vere seguono il puntatore (begin_drag).
func set_drag_line(from: Vector2, to: Vector2) -> void:
	_drag_from = from
	_drag_to = to
	queue_redraw()


## Prende la pedina (`kind` "esercito" o "agente") nel punto `grab` dello schermo: da qui segue il puntatore (move_drag),
## come nel gioco originale, e al suo posto resta un'ombra. Falso se la pedina non ha l'immagine dell'originale.
func begin_drag(kind: String, id: int, grab: Vector2) -> bool:
	var foot := Vector2.INF
	if kind == "agente":
		for am in _agents:
			if am.agent_id == id and am.piece != null:
				foot = _agent_center(am)
	else:
		for m in _markers:
			if m.army_id == id and m.piece != null:
				foot = _marker_center(m)
	if foot == Vector2.INF:
		return false
	_drag_kind = kind
	_drag_id = id
	_drag_offset = foot - grab
	_drag_pos = grab
	queue_redraw()
	return true


func move_drag(pos: Vector2) -> void:
	if _drag_kind == "":
		return
	_drag_pos = pos
	queue_redraw()


func end_drag() -> void:
	if _drag_kind == "" and _drag_from == _drag_to:
		return
	_drag_kind = ""
	_drag_id = 0
	_followers.clear()
	_drag_from = Vector2.ZERO
	_drag_to = Vector2.ZERO
	queue_redraw()


func is_dragging_piece() -> bool:
	return _drag_kind != ""


## Selezione multipla (2026-11-10): gli eserciti `ids` seguono la pedina presa (begin_drag), sollevati insieme a lei,
## ciascuno alla sua distanza; al loro posto resta l'ombra. Senza begin_drag riuscito non fa nulla.
func set_drag_followers(ids: Array[int]) -> void:
	_followers.clear()
	if _drag_kind != "esercito":
		return
	var grab := _drag_pos
	for m in _markers:
		if m.piece != null and m.army_id != _drag_id and ids.has(m.army_id):
			_followers[m.army_id] = _marker_center(m) - grab
	queue_redraw()


func follower_count() -> int:
	return _followers.size()


## Riquadro della selezione multipla tra due punti dello schermo (Alt + trascinamento su un punto vuoto).
func set_box(from: Vector2, to: Vector2) -> void:
	_box = Rect2(from, Vector2.ZERO).expand(to)
	queue_redraw()


func clear_box() -> void:
	if _box.has_area() or _box.position != Vector2.ZERO:
		_box = Rect2()
		queue_redraw()


## Eserciti del giocatore con la pedina nel riquadro `box` (schermo): conta il punto dei piedi o il centro della figura.
## Ordine di disegno (inserimento).
func armies_in_box(box: Rect2) -> Array[int]:
	var out: Array[int] = []
	for m in _markers:
		if not m.player or m.hidden:
			continue
		var foot := _marker_center(m)
		var middle := foot - Vector2(0.0, marker_height(m) * 0.5) if m.piece != null else foot
		if box.has_point(foot) or box.has_point(middle):
			out.append(m.army_id)
	return out


## Altezza sullo schermo della pedina `m` con lo zoom attuale: crociate e jihad `CRUSADE_PIECE_SCALE` volte le altre (ADR-072).
func marker_height(m: Marker) -> float:
	return PIECE_HEIGHT * piece_scale() * (CRUSADE_PIECE_SCALE if m.badge != "" else 1.0)


## Fattore di scala delle pedine con lo zoom attuale: 1 = dimensione base (PIECE_HEIGHT), entro i limiti.
func piece_scale() -> float:
	return clampf(PIECE_WORLD_HEIGHT * _zoom / BASE_HEIGHT, PIECE_MIN_SCALE, PIECE_MAX_SCALE)


## Fattore di scala di castelli e porti: come le pedine, ma con il limite piu' alto STRUCTURE_MAX_SCALE.
static func structure_scale_at(zoom: float) -> float:
	return clampf(PIECE_WORLD_HEIGHT * zoom / BASE_HEIGHT, PIECE_MIN_SCALE, STRUCTURE_MAX_SCALE)


func structure_scale() -> float:
	return structure_scale_at(_zoom)


func reach_count() -> int:
	return _reach.size()


func arrow_count() -> int:
	return _arrows.size()


## Vero se la freccia `index` (ordine di inserimento) e' tratteggiata.
func arrow_is_dashed(index: int) -> bool:
	return index >= 0 and index < _arrows.size() and _arrows[index].dashed


## Porto (immagine di PieceArt.port_piece) centrato sul punto `anchor` della mappa.
func add_port(anchor: Vector2, piece: Texture2D) -> void:
	if piece == null:
		return
	var p := PortMark.new()
	p.anchor = anchor
	p.piece = piece
	_ports.append(p)


func port_count() -> int:
	return _ports.size()


## Castello della regione `region_id` (immagine gia' colorata per il proprietario, PieceArt.castle_piece).
func add_castle(region_id: String, anchor: Vector2, piece: Texture2D, scale: float = 1.0) -> void:
	if piece == null:
		return
	var c := CastleMark.new()
	c.region_id = region_id
	c.anchor = anchor
	c.piece = piece
	c.scale = scale
	_castles.append(c)


## Regione del castello sotto `screen` ("" se nessuno): conta solo la parte dipinta dell'immagine, non il trasparente.
func castle_at(screen: Vector2) -> String:
	var castle_h := CASTLE_HEIGHT * structure_scale()
	for i in range(_castles.size() - 1, -1, -1):
		var cm := _castles[i]
		var ch := castle_h * cm.scale
		var cw := ch * float(cm.piece.get_width()) / float(cm.piece.get_height())
		var rect := Rect2(_to_screen(cm.anchor) - Vector2(cw * 0.5, ch * 0.9), Vector2(cw, ch))
		if not rect.has_point(screen):
			continue
		var img := cm.piece.get_image()
		if img == null:
			return cm.region_id
		var px := Vector2i(clampi(floori((screen.x - rect.position.x) / rect.size.x * img.get_width()), 0, img.get_width() - 1),
			clampi(floori((screen.y - rect.position.y) / rect.size.y * img.get_height()), 0, img.get_height() - 1))
		if img.get_pixelv(px).a > 0.4:
			return cm.region_id
	return ""


## La pedina dell'esercito `army_id` non si vede ne' si clicca (guarnigione nel castello); resta trascinabile con begin_drag.
func hide_marker(army_id: int) -> void:
	for m in _markers:
		if m.army_id == army_id:
			m.hidden = true


func castle_count() -> int:
	return _castles.size()


## Scostamento (pixel dello schermo a dimensione base, come gli slot) delle pedine fuori dal castello: a destra del
## castello, cosi' non lo coprono. Le pedine nel castello stanno davanti al castello (`garrison_slot`).
## `castle_ratio` = scala del castello / scala delle pedine (oltre il limite delle pedine il castello e' piu' grande).
static func castle_side_offset(castle_ratio: float = 1.0) -> Vector2:
	return Vector2(CASTLE_HEIGHT * 0.42 * castle_ratio + SLOT_SPACING * 0.5, 0.0)


static func garrison_slot(index: int) -> Vector2:
	return Vector2(-6.0 + float(index) * 9.0, 6.0 + float(index) * 3.0)


## Simbolo di provincia assediata (disegnato sul castello, sopra i segnalini).
func add_siege_mark(anchor: Vector2, slot: Vector2) -> void:
	var m := SiegeMark.new()
	m.anchor = anchor
	m.slot = slot
	_sieges.append(m)


func siege_mark_count() -> int:
	return _sieges.size()


## Colore di una freccia secondo selezione e attacco.
static func arrow_color(selected: bool, attack: bool) -> Color:
	if attack:
		return ATTACK_COLOR if selected else ATTACK_DIM_COLOR
	return ARROW_COLOR if selected else ARROW_DIM_COLOR


## Da chiamare dopo aver aggiunto segnalini e frecce.
func finish() -> void:
	queue_redraw()


## Posizione della camera: `center` = punto del mondo al centro, `zoom` = pixel della vista
## piatta per pixel di bitmap, `view_size` = vista piatta. Con `projection` i punti passano
## dalla prospettiva della plancia (segnalini e testo restano nitidi, in pixel dello schermo).
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


## Id dell'esercito il cui segnalino è sotto `screen` (coordinate dello schermo), 0 se nessuno.
func army_at(screen: Vector2, exclude: int = 0) -> int:
	# le pedine (fase 8) stanno sopra il punto: l'area cliccabile sale di mezza altezza; `exclude` = pedina da ignorare
	# (quella che si sta trascinando)
	for pass_piece in [true, false]:
		var centers := PackedVector2Array()
		var heights := PackedFloat32Array()
		var index_of: Array[int] = []
		for i in _markers.size():
			var m := _markers[i]
			if m.hidden or (m.piece != null) != pass_piece or (exclude > 0 and m.army_id == exclude):
				continue
			var c := _marker_center(m)
			var mh := marker_height(m)
			centers.append(c - Vector2(0.0, mh * 0.5) if pass_piece else c)
			heights.append(mh)
			index_of.append(i)
		var half := Vector2(PIECE_HALF_WIDTH, PIECE_HEIGHT * 0.5) * piece_scale() if pass_piece else Vector2(HALF, HALF)
		if pass_piece:
			# prima la figura (meta' bassa della pedina), poi lo stendardo; a parita' vince la pedina disegnata davanti
			for zone in [[0.0, 0.55], [0.55, 1.0]]:
				var best := -1
				for k in centers.size():
					var h := heights[k]
					var foot := centers[k] + Vector2(0.0, h * 0.5)
					var up := foot.y - screen.y
					if absf(screen.x - foot.x) <= half.x * h / (PIECE_HEIGHT * piece_scale()) and up >= h * float(zone[0]) - 6.0 and up <= h * float(zone[1]):
						if best < 0 or centers[k].y >= centers[best].y:
							best = k
				if best >= 0:
					return _markers[index_of[best]].army_id
			continue
		var hit := MarkerLayout.hit_index(centers, half, screen)
		if hit >= 0:
			return _markers[index_of[hit]].army_id
	return 0


## Id dell'agente il cui segnalino è sotto `screen`, 0 se nessuno (gli agenti stanno sopra gli eserciti).
func agent_at(screen: Vector2, exclude: int = 0) -> int:
	var centers := PackedVector2Array()
	var index_of: Array[int] = []
	for k in _agents.size():
		var m := _agents[k]
		if exclude > 0 and m.agent_id == exclude:
			continue
		var c := _to_screen(m.anchor) + m.slot * (piece_scale() if m.piece != null else 1.0)
		centers.append(c - Vector2(0.0, AGENT_PIECE_HEIGHT * piece_scale() * 0.5) if m.piece != null else c)
		index_of.append(k)
	var i := MarkerLayout.hit_index(centers, Vector2(AGENT_RADIUS, maxf(AGENT_RADIUS, AGENT_PIECE_HEIGHT * 0.5)) * piece_scale(), screen)
	if i < 0:
		return 0
	return _agents[index_of[i]].agent_id


## Punto dei piedi della pedina trascinata se il puntatore e' in `screen` (dove la si posa), o `screen` senza trascinamento.
func drag_foot(screen: Vector2) -> Vector2:
	return screen + _drag_offset if _drag_kind != "" else screen


func marker_count() -> int:
	return _markers.size()


## Distintivo del segnalino `index` (ordine di inserimento), per i test; "" fuori intervallo o senza distintivo.
func marker_badge(index: int) -> String:
	if index < 0 or index >= _markers.size():
		return ""
	return _markers[index].badge


## Centro del distintivo di un segnalino, in coordinate dello schermo (sopra il segnalino).
static func badge_center(marker_center: Vector2) -> Vector2:
	return marker_center + Vector2(0.0, -(HALF + BADGE_LIFT))


## Distintivo: disco bianco con bordo del colore del genere e, dentro, una croce o una mezzaluna.
func _draw_badge(center: Vector2, badge: String) -> void:
	var tone := JIHAD_BADGE_COLOR if badge == CampaignUiPapacy.BADGE_CRESCENT else CRUSADE_BADGE_COLOR
	draw_circle(center, BADGE_RADIUS + 1.5, Color.WHITE)
	draw_circle(center, BADGE_RADIUS, tone)
	if badge == CampaignUiPapacy.BADGE_CRESCENT:
		var r := BADGE_RADIUS * 0.62
		draw_circle(center, r, Color.WHITE)
		draw_circle(center + Vector2(r * 0.45, -r * 0.1), r * 0.82, tone)
	else:
		var k := BADGE_RADIUS * 0.6
		draw_line(center + Vector2(0.0, -k), center + Vector2(0.0, k), Color.WHITE, 2.5, true)
		draw_line(center + Vector2(-k * 0.8, -k * 0.25), center + Vector2(k * 0.8, -k * 0.25), Color.WHITE, 2.5, true)


func agent_marker_count() -> int:
	return _agents.size()


## Testo del segnalino `index` (ordine di inserimento), per i test; "" fuori intervallo.
func agent_marker_text(index: int) -> String:
	if index < 0 or index >= _agents.size():
		return ""
	return _agents[index].text


func _to_screen(world: Vector2) -> Vector2:
	var flat := (world - _center) * _zoom + _view / 2.0
	return _projection.flat_to_screen(flat) if _projection != null else flat


## Dimensione dello schermo, per scartare ciò che è fuori vista.
func _screen_size() -> Vector2:
	return _projection.screen_size if _projection != null else _view


func _agent_center(am: AgentMarker) -> Vector2:
	return _to_screen(am.anchor) + am.slot * (piece_scale() if am.piece != null else 1.0)


func _marker_center(m: Marker) -> Vector2:
	# con le pedine anche la distanza tra quelle della stessa regione cresce con lo zoom
	return _to_screen(m.anchor) + m.slot * (piece_scale() if m.piece != null else 1.0)


func _draw() -> void:
	var screen := _screen_size()
	for a in _arrows:
		if a.points.size() < 2:
			continue
		var pts := PackedVector2Array()
		for p in a.points:
			pts.append(_to_screen(p))
		var col := arrow_color(a.selected, a.attack)
		var width := 3.5 if a.selected else 2.0
		if a.dashed:
			for piece in MarkerLayout.dashed_segments(pts, DASH_LENGTH, DASH_GAP):
				draw_polyline(piece, col, width, true)
		else:
			draw_polyline(pts, col, width, true)
		var head := MarkerLayout.arrow_head(pts[pts.size() - 2], pts[pts.size() - 1], ARROW_HEAD)
		if not head.is_empty():
			draw_colored_polygon(head, col)
	for world in _reach:
		var rc := _to_screen(world)
		if rc.x < -40.0 or rc.y < -40.0 or rc.x > screen.x + 40.0 or rc.y > screen.y + 40.0:
			continue
		draw_circle(rc, REACH_RADIUS, REACH_FILL)
		draw_arc(rc, REACH_RADIUS, 0.0, TAU, 32, REACH_COLOR, 2.0, true)
	var port_h := PORT_HEIGHT * structure_scale()
	for pm in _ports:
		var pc := _to_screen(pm.anchor)
		if pc.x < -port_h or pc.y < -port_h or pc.x > screen.x + port_h or pc.y > screen.y + port_h:
			continue
		var pw := port_h * float(pm.piece.get_width()) / float(pm.piece.get_height())
		draw_texture_rect(pm.piece, Rect2(pc - Vector2(pw * 0.5, port_h * 0.5), Vector2(pw, port_h)), false)
	var castle_h := CASTLE_HEIGHT * structure_scale()
	for cm in _castles:
		var cc := _to_screen(cm.anchor)
		var ch := castle_h * cm.scale
		if cc.x < -ch or cc.y < -40.0 or cc.x > screen.x + ch or cc.y > screen.y + ch:
			continue
		var cw := ch * float(cm.piece.get_width()) / float(cm.piece.get_height())
		# piedi del castello sull'ancora: la base delle mura e' nella parte bassa dell'immagine
		draw_texture_rect(cm.piece, Rect2(cc - Vector2(cw * 0.5, ch * 0.9), Vector2(cw, ch)), false)
	for sm in _sieges:
		var sc := _to_screen(sm.anchor) + sm.slot
		if sc.x < -40.0 or sc.y < -40.0 or sc.x > screen.x + 40.0 or sc.y > screen.y + 40.0:
			continue
		# Cerchio rosso con una croce bianca: castello assediato.
		draw_circle(sc, SIEGE_RADIUS + 1.5, Color.WHITE)
		draw_circle(sc, SIEGE_RADIUS, SIEGE_COLOR)
		var k := SIEGE_RADIUS * 0.5
		draw_line(sc + Vector2(-k, -k), sc + Vector2(k, k), Color.WHITE, 2.0, true)
		draw_line(sc + Vector2(-k, k), sc + Vector2(k, -k), Color.WHITE, 2.0, true)
	var font: Font = ThemeDB.fallback_font
	# fase 8: le pedine si disegnano dall'alto in basso dello schermo, cosi' quelle davanti coprono quelle dietro
	var order: Array[int] = []
	for i in _markers.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _marker_center(_markers[a]).y < _marker_center(_markers[b]).y)
	for idx in order:
		var m := _markers[idx]
		if m.hidden:
			continue   # nel castello: la pedina sparisce dalla mappa (richiesta di Federico, 2026-11-10)
		var c := _marker_center(m)
		if c.x < -40.0 or c.y < -40.0 or c.x > screen.x + 40.0 or c.y > screen.y + PIECE_HEIGHT + 40.0:
			continue
		if m.piece != null:
			var ghost := _drag_kind == "esercito" and (_drag_id == m.army_id or _followers.has(m.army_id))
			_draw_piece(m.piece, c, marker_height(m), m.selected and not ghost, m.player, "", font, GHOST_ALPHA if ghost else 1.0)   # niente numero (scelta di Federico)
			continue
		var border := Color.WHITE if m.player else Color.BLACK
		var border_width := 2.0
		if m.selected:
			border = SELECTED_COLOR
			border_width = 3.5
		if m.fleet:
			var r := HALF + 3.0
			var diamond := PackedVector2Array([c + Vector2(0.0, -r), c + Vector2(r, 0.0), c + Vector2(0.0, r), c + Vector2(-r, 0.0)])
			draw_colored_polygon(diamond, m.color)
			var outline := PackedVector2Array()
			for p in diamond:
				outline.append(p)
			outline.append(diamond[0])
			draw_polyline(outline, border, border_width, true)
		else:
			var rect := Rect2(c - Vector2(HALF, HALF), Vector2(HALF * 2.0, HALF * 2.0))
			draw_rect(rect, m.color, true)
			draw_rect(rect, border, false, border_width)
		var text_color := Color.BLACK if m.color.get_luminance() > 0.55 else Color.WHITE
		draw_string(font, Vector2(c.x - HALF, c.y + FONT_SIZE * 0.35), m.text, HORIZONTAL_ALIGNMENT_CENTER, HALF * 2.0, FONT_SIZE, text_color)
		if m.badge != "":
			_draw_badge(badge_center(c), m.badge)
	for am in _agents:
		var ac := _agent_center(am)
		if ac.x < -40.0 or ac.y < -40.0 or ac.x > screen.x + 40.0 or ac.y > screen.y + 40.0:
			continue
		if am.piece != null:
			var agent_ghost := _drag_kind == "agente" and _drag_id == am.agent_id
			_draw_piece(am.piece, ac, AGENT_PIECE_HEIGHT * piece_scale(), am.selected and not agent_ghost, am.player, "", font, GHOST_ALPHA if agent_ghost else 1.0)
			continue
		var agent_border := Color.WHITE if am.player else Color.BLACK
		var agent_border_width := 2.0
		if am.selected:
			agent_border = SELECTED_COLOR
			agent_border_width = 3.5
		draw_circle(ac, AGENT_RADIUS, am.color)
		draw_arc(ac, AGENT_RADIUS, 0.0, TAU, 32, agent_border, agent_border_width, true)
		var agent_text_color := Color.BLACK if am.color.get_luminance() > 0.55 else Color.WHITE
		draw_string(font, Vector2(ac.x - AGENT_RADIUS, ac.y + AGENT_FONT_SIZE * 0.35), am.text, HORIZONTAL_ALIGNMENT_CENTER, AGENT_RADIUS * 2.0, AGENT_FONT_SIZE, agent_text_color)
	_draw_drag_line()
	_draw_box()
	_draw_dragged_piece()


func _draw_box() -> void:
	if not _box.has_area():
		return
	draw_rect(_box, BOX_FILL, true)
	draw_rect(_box, BOX_BORDER, false, 1.5)


## La pedina presa, disegnata sotto il puntatore con la sua ombra a terra, sopra tutte le altre.
func _draw_dragged_piece() -> void:
	if _drag_kind == "":
		return
	var foot := _drag_pos + _drag_offset
	if _drag_kind == "agente":
		for am in _agents:
			if am.agent_id == _drag_id and am.piece != null:
				_draw_lifted(am.piece, foot, AGENT_PIECE_HEIGHT * piece_scale())
				return
	else:
		# prima i compagni della selezione multipla (dietro), poi la pedina presa
		for m in _markers:
			if _followers.has(m.army_id) and m.piece != null:
				_draw_lifted(m.piece, _drag_pos + Vector2(_followers[m.army_id]), marker_height(m))
		for m in _markers:
			if m.army_id == _drag_id and m.piece != null:
				_draw_lifted(m.piece, foot, marker_height(m))
				return


## Pedina sollevata: ombra scura ai piedi e figura un po' piu' grande e piu' in alto, come presa in mano.
func _draw_lifted(tex: Texture2D, foot: Vector2, height: float) -> void:
	var w := height * float(tex.get_width()) / float(tex.get_height())
	var shadow := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		shadow.append(foot + Vector2(cos(a) * w * 0.5, sin(a) * height * 0.08))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	var lift := height * LIFT
	var h := height * LIFT_SCALE
	var lw := w * LIFT_SCALE
	draw_texture_rect(tex, Rect2(foot - Vector2(lw * 0.5, h * 0.93 + lift), Vector2(lw, h)), false)


## Linea tratteggiata dalla pedina trascinata al puntatore, con un anello all'arrivo.
func _draw_drag_line() -> void:
	if _drag_from == _drag_to:
		return
	for piece in MarkerLayout.dashed_segments(PackedVector2Array([_drag_from, _drag_to]), DASH_LENGTH, DASH_GAP):
		draw_polyline(piece, ARROW_COLOR, 3.0, true)
	draw_arc(_drag_to, 10.0, 0.0, TAU, 24, ARROW_COLOR, 2.5, true)


## Pedina dell'originale con i piedi in `foot` (schermo), alta `height`; ellisse dorata sotto se selezionata, chiara se del
## giocatore; `text` (numero di pile) in un cartiglio sotto la base.
func _draw_piece(tex: Texture2D, foot: Vector2, height: float, selected: bool, player: bool, text: String, font: Font, alpha: float = 1.0) -> void:
	var w := height * float(tex.get_width()) / float(tex.get_height())
	var ring := Vector2(w * 0.55, height * 0.09)
	if selected:
		_draw_ellipse(foot, ring * 1.25, Color(SELECTED_COLOR, 0.95), 3.0)
	elif player and alpha >= 1.0:
		_draw_ellipse(foot, ring * 1.15, Color(1, 1, 1, 0.55), 1.5)
	draw_texture_rect(tex, Rect2(foot - Vector2(w * 0.5, height * 0.93), Vector2(w, height)), false, Color(1, 1, 1, alpha))
	if text != "":
		var box := Rect2(foot + Vector2(-10.0, 3.0), Vector2(20.0, 14.0))
		draw_rect(box, Color(0.94, 0.89, 0.78, 0.92), true)
		draw_rect(box, Color(0.42, 0.29, 0.16), false, 1.0)
		draw_string(font, Vector2(box.position.x, box.position.y + 11.5), text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 11, Color(0.18, 0.12, 0.07))


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * float(i) / 32.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_polyline(pts, color, width, true)
