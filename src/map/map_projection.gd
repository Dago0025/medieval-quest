class_name MapProjection
extends RefCounted
## Vista in prospettiva della plancia: la mappa piatta è vista da una camera inclinata,
## come una plancia da tavolo guardata da sud. Il nord (in alto) si allontana: in alto lo
## schermo mostra una striscia di mappa più larga, in basso una più stretta e ingrandita.
##
## La mappa viene disegnata "piatta" in una vista intermedia (SubViewport) grande
## `flat_size()`; lo shader `perspective_view.gdshader` la proietta sullo schermo e questa
## classe fa la stessa trasformazione per il mouse e per i segnalini.
##
## Proiezione (omografia di un piano inclinato), coordinate normalizzate 0..1:
##   schermo (sx, sy) -> piatta (u, v):  d = 1 + (k - 1) * sy
##                                       u = 0.5 + (sx - 0.5) / d,  v = k * sy / d
## k = `tilt` è il rapporto tra la larghezza della striscia in alto e quella in basso:
## k = 1 è la vista dall'alto (identità). In basso al centro un pixel della vista piatta
## vale un pixel dello schermo, perché la vista piatta è grande k volte lo schermo.
## Logica pura, senza nodi: la usano campaign_map.gd, army_layer.gd e i test.

const MIN_TILT := 1.0
const MAX_TILT := 2.4
## Oltre questo limite (in pixel) la vista piatta viene disegnata a risoluzione ridotta.
const MAX_FLAT_SIDE := 6144.0

var screen_size := Vector2(1280.0, 720.0)
var tilt := 1.0


func _init(screen: Vector2 = Vector2(1280.0, 720.0), k: float = 1.0) -> void:
	screen_size = screen
	tilt = clampf(k, MIN_TILT, MAX_TILT)


func is_flat() -> bool:
	return tilt <= MIN_TILT + 0.0001


## Dimensione logica della vista piatta (pixel in cui lavora la Camera2D).
func flat_size() -> Vector2:
	return screen_size * tilt


## Fattore di risoluzione con cui disegnare la vista piatta (1 = piena), per non superare
## MAX_FLAT_SIDE sugli schermi molto grandi.
func render_scale() -> float:
	var f := flat_size()
	var side := maxf(f.x, f.y)
	return 1.0 if side <= MAX_FLAT_SIDE else MAX_FLAT_SIDE / side


## Larghezza della vista piatta visibile sul bordo basso dello schermo (la più stretta).
func bottom_width() -> float:
	return flat_size().x / tilt


func screen_to_flat(screen: Vector2) -> Vector2:
	var f := flat_size()
	if is_flat():
		return screen
	var sx := screen.x / screen_size.x
	var sy := screen.y / screen_size.y
	var d := 1.0 + (tilt - 1.0) * sy
	if d < 0.01:
		d = 0.01
	return Vector2((0.5 + (sx - 0.5) / d) * f.x, (tilt * sy / d) * f.y)


func flat_to_screen(flat: Vector2) -> Vector2:
	if is_flat():
		return flat
	var f := flat_size()
	var u := flat.x / f.x
	var v := flat.y / f.y
	var den := tilt - (tilt - 1.0) * v
	if den < 0.01:
		# Dietro la camera (molto sotto lo schermo): lontanissimo, fuori vista.
		return Vector2(screen_size.x * 0.5, screen_size.y * 100.0)
	var sy := v / den
	var d := 1.0 + (tilt - 1.0) * sy
	return Vector2((0.5 + (u - 0.5) * d) * screen_size.x, sy * screen_size.y)
