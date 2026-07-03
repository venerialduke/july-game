class_name EnemyView
extends Node2D
## Visual for one enemy: red diamond with an hp ring once damaged.
## Main frees this view when the enemy dies.

const BODY_COLOR := Color(0.88, 0.3, 0.28)
const OUTLINE_COLOR := Color(0.12, 0.13, 0.16)
const HP_COLOR := Color(1.0, 0.5, 0.45)

var enemy: EnemyData
var hex_size: float = 48.0


func setup(p_enemy: EnemyData, p_hex_size: float) -> void:
	enemy = p_enemy
	hex_size = p_hex_size
	position = HexUtils.axial_to_pixel(enemy.coord, hex_size)


func _process(_delta: float) -> void:
	visible = MapSim.is_revealed(enemy.coord)
	position = HexUtils.axial_to_pixel(enemy.coord, hex_size)
	queue_redraw()


func _draw() -> void:
	var r: float = hex_size * 0.24
	var outer := PackedVector2Array([
		Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
	draw_colored_polygon(outer, OUTLINE_COLOR)
	var r2: float = r * 0.72
	var inner := PackedVector2Array([
		Vector2(0, -r2), Vector2(r2, 0), Vector2(0, r2), Vector2(-r2, 0)])
	draw_colored_polygon(inner, BODY_COLOR)
	if enemy.hp < enemy.max_hp:
		draw_arc(Vector2.ZERO, hex_size * 0.32, -PI / 2.0,
				-PI / 2.0 + TAU * (enemy.hp / enemy.max_hp), 24, HP_COLOR, 3.0)
