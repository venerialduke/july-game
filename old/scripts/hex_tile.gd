class_name HexTile
extends Node2D
## A single hex tile on the grid. Stores its axial coordinate, tile type,
## and manages its own color. Emits tile_clicked when tapped/clicked.

enum TileType { NORMAL, OBJECTIVE, FLOODED, FLOOD_SOURCE }

signal tile_clicked(coord: Vector2i)

const BORDER_COLOR: Color = Color(0.3, 0.3, 0.3)
const HIGHLIGHT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.4)
const SELECTED_COLOR: Color = Color(0.2, 1.0, 0.4, 0.5)
const BORDER_WIDTH: float = 2.0

var coord: Vector2i
var tile_type: TileType = TileType.NORMAL
var highlighted: bool = false
var selected: bool = false
var _vertices: PackedVector2Array
var _fill_color: Color = Color(0.85, 0.85, 0.80)

@onready var _area: Area2D = $Area2D
@onready var _collision: CollisionPolygon2D = $Area2D/CollisionPolygon2D


func initialize(p_coord: Vector2i, hex_size: float, p_type: TileType) -> void:
	coord = p_coord
	tile_type = p_type
	_vertices = HexUtils.get_hex_vertices(hex_size)
	position = HexUtils.axial_to_pixel(p_coord, hex_size)
	_collision.polygon = _vertices
	_update_color()


func set_type(new_type: TileType) -> void:
	tile_type = new_type
	_update_color()


func _ready() -> void:
	_area.input_event.connect(_on_area_input_event)


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(coord)


func set_highlighted(on: bool) -> void:
	if highlighted == on:
		return
	highlighted = on
	queue_redraw()


func set_selected(on: bool) -> void:
	if selected == on:
		return
	selected = on
	queue_redraw()


func _draw() -> void:
	if _vertices.is_empty():
		return
	# Draw the filled hex.
	draw_colored_polygon(_vertices, _fill_color)
	# Draw highlight/selection overlay.
	if selected:
		draw_colored_polygon(_vertices, SELECTED_COLOR)
	elif highlighted:
		draw_colored_polygon(_vertices, HIGHLIGHT_COLOR)
	# Draw a closed outline around the hex.
	for i: int in range(_vertices.size()):
		var from: Vector2 = _vertices[i]
		var to: Vector2 = _vertices[(i + 1) % _vertices.size()]
		draw_line(from, to, BORDER_COLOR, BORDER_WIDTH, true)


func _update_color() -> void:
	match tile_type:
		TileType.NORMAL:
			_fill_color = Color(0.85, 0.85, 0.80)
		TileType.OBJECTIVE:
			_fill_color = Color(1.0, 0.84, 0.0)
		TileType.FLOODED:
			_fill_color = Color(0.25, 0.45, 0.80)
		TileType.FLOOD_SOURCE:
			_fill_color = Color(0.12, 0.22, 0.55)
	queue_redraw()
