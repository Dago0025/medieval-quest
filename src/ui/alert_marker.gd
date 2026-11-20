class_name AlertMarker
extends Control
## Segnale pulsante sul luogo dell'avviso aperto (battaglia, assedio, conquista, disastro): due anelli d'oro che si allargano e
## un punto al centro. La mappa (campaign_map) lo sposta a ogni fotogramma sul punto dello schermo del luogo; da solo disegna
## soltanto, non intercetta il mouse.

const GOLD := Color("e9c46a")
const DARK := Color(0.08, 0.05, 0.02, 0.8)
const RADIUS := 34.0
const PERIOD := 1.4

var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2.ZERO


func _process(delta: float) -> void:
	if not visible:
		return
	_time = fmod(_time + delta, PERIOD * 100.0)
	queue_redraw()


func _draw() -> void:
	for i in 2:
		var phase := fmod(_time / PERIOD + i * 0.5, 1.0)
		var r := lerpf(RADIUS * 0.35, RADIUS * 1.25, phase)
		var a := 1.0 - phase
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(DARK, a * 0.7), 5.0, true)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(GOLD, a), 2.5, true)
	draw_circle(Vector2.ZERO, 7.0, DARK)
	draw_circle(Vector2.ZERO, 4.5, GOLD)
