class_name Player
extends Node2D
## Player token. Sits on a hex tile, draws a simple circle marker.

const PLAYER_COLOR: Color = Color(0.9, 0.35, 0.1)
const PLAYER_RADIUS: float = 14.0

var current_coord: Vector2i


func _ready() -> void:
	z_index = 10


func place(coord: Vector2i, hex_size: float) -> void:
	current_coord = coord
	position = HexUtils.axial_to_pixel(coord, hex_size)


func _draw() -> void:
	draw_circle(Vector2.ZERO, PLAYER_RADIUS, PLAYER_COLOR)
