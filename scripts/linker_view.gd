class_name LinkerView
extends Node2D
## Visual for one linker: a hub on its host tile and an arrow per link edge.
## The arrow lerps toward the true beam angle for juice, but the sim's
## integer orientation is the only truth — this node never writes state.

const LERP_SPEED: float = 8.0
const TYPE_COLORS: Dictionary[LinkerData.Type, Color] = {
	LinkerData.Type.TRANSMUTE: Color(0.95, 0.72, 0.15),
	LinkerData.Type.CONNECTOR: Color(0.30, 0.85, 0.90),
}
const FROZEN_COLOR := Color(0.65, 0.85, 1.0)

var linker: LinkerData
var hex_size: float = 48.0
## Displayed angle per link edge (radians), lerping toward the true angle.
var _display_angles: Array[float] = []


func setup(p_linker: LinkerData, p_hex_size: float) -> void:
	linker = p_linker
	hex_size = p_hex_size
	position = HexUtils.axial_to_pixel(linker.host_coord, hex_size)
	_display_angles.clear()
	for edge: int in linker.links:
		_display_angles.append(_true_angle(edge))


func _process(delta: float) -> void:
	for i: int in range(linker.links.size()):
		_display_angles[i] = lerp_angle(
				_display_angles[i], _true_angle(linker.links[i]), LERP_SPEED * delta)
	queue_redraw()


## The pixel-space angle from host center to the beam's current target.
func _true_angle(edge: int) -> float:
	var target: Vector2i = MapSim.beam_target(linker, edge)
	var offset: Vector2 = HexUtils.axial_to_pixel(target, hex_size) \
			- HexUtils.axial_to_pixel(linker.host_coord, hex_size)
	return offset.angle()


func _draw() -> void:
	var color: Color = TYPE_COLORS[linker.type]
	var beam_len: float = hex_size * 1.45   # reaches into the neighbor tile

	for angle: float in _display_angles:
		var tip := Vector2.from_angle(angle) * beam_len
		draw_line(Vector2.ZERO, tip, color, 6.0)
		# Arrowhead.
		var back := tip - Vector2.from_angle(angle) * hex_size * 0.3
		var side := Vector2.from_angle(angle + PI / 2.0) * hex_size * 0.16
		draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), color)

	# Hub. A pale ring marks a frozen linker.
	draw_circle(Vector2.ZERO, hex_size * 0.30, Color(0.12, 0.13, 0.16))
	draw_circle(Vector2.ZERO, hex_size * 0.22, color)
	if linker.frozen:
		draw_arc(Vector2.ZERO, hex_size * 0.38, 0.0, TAU, 32, FROZEN_COLOR, 4.0)
