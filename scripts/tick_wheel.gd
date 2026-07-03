class_name TickWheel
extends Control
## Radial progress ring that fills as the global clock creeps toward the
## next tick, so upcoming linker snaps are always anticipatable.

const RING_BG := Color(1.0, 1.0, 1.0, 0.15)
const RING_FG := Color(0.95, 0.88, 0.5)
const RING_WIDTH: float = 7.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = size / 2.0
	var radius: float = minf(size.x, size.y) * 0.38
	draw_arc(center, radius, 0.0, TAU, 48, RING_BG, RING_WIDTH)
	var progress: float = MapSim.tick_progress()
	if progress > 0.0:
		# Fills clockwise from 12 o'clock; snaps empty when the tick fires.
		draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * progress,
				48, RING_FG, RING_WIDTH)
