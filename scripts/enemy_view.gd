class_name EnemyView
extends Node2D
## Visual for one enemy: a diamond colored and sized by archetype, hp ring
## when damaged, and a pulsing ring while chasing the Leader (telegraph).
## Position interpolates along the enemy's path. Main frees this view when
## the enemy dies.

const OUTLINE_COLOR := Color(0.12, 0.13, 0.16)
const HP_COLOR := Color(1.0, 0.5, 0.45)
const CHASE_COLOR := Color(1.0, 0.25, 0.2)

const BODY_COLORS: Dictionary[StringName, Color] = {
	&"": Color(0.88, 0.3, 0.28),          # legacy dummy
	&"drifter": Color(0.75, 0.55, 0.5),
	&"brute": Color(0.62, 0.16, 0.16),
	&"hunter": Color(1.0, 0.3, 0.22),
}
const BODY_SCALE: Dictionary[StringName, float] = {
	&"": 1.0, &"drifter": 0.8, &"brute": 1.35, &"hunter": 1.0,
}

var enemy: EnemyData
var hex_size: float = 48.0


func setup(p_enemy: EnemyData, p_hex_size: float) -> void:
	enemy = p_enemy
	hex_size = p_hex_size
	position = HexUtils.axial_to_pixel(enemy.coord, hex_size)


func _process(_delta: float) -> void:
	visible = MapSim.is_revealed(enemy.coord)
	position = LeaderView.mover_pixel(enemy, hex_size)
	queue_redraw()


func _draw() -> void:
	var r: float = hex_size * 0.24 * BODY_SCALE[enemy.archetype]
	var outer := PackedVector2Array([
		Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
	draw_colored_polygon(outer, OUTLINE_COLOR)
	var r2: float = r * 0.72
	var inner := PackedVector2Array([
		Vector2(0, -r2), Vector2(r2, 0), Vector2(0, r2), Vector2(-r2, 0)])
	draw_colored_polygon(inner, BODY_COLORS[enemy.archetype])

	if enemy.state == EnemyData.AIState.CHASE:
		# Pulsing telegraph: this thing has your scent.
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		var chase := CHASE_COLOR
		chase.a = 0.35 + 0.55 * pulse
		draw_arc(Vector2.ZERO, r + hex_size * 0.14, 0.0, TAU, 32, chase, 4.0)

	if enemy.hp < enemy.max_hp:
		draw_arc(Vector2.ZERO, hex_size * 0.32, -PI / 2.0,
				-PI / 2.0 + TAU * (enemy.hp / enemy.max_hp), 24, HP_COLOR, 3.0)
