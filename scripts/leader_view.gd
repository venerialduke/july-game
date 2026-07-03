class_name LeaderView
extends Node2D
## Visual for the Leader. Reads MapSim.leader each frame and interpolates
## its pixel position from coord + edge_progress. Holds no state.

const BODY_COLOR := Color(0.95, 0.96, 1.0)
const SPRINT_COLOR := Color(1.0, 0.58, 0.2)
const OUTLINE_COLOR := Color(0.12, 0.13, 0.16)
const HP_COLOR := Color(0.4, 1.0, 0.4)
const HP_LOW_COLOR := Color(1.0, 0.35, 0.3)

var hex_size: float = 48.0


## Interpolated pixel position for anything with coord/path/edge_progress
## (LeaderData, EnemyData). Static + duck-typed so every view shares it.
static func mover_pixel(mover: RefCounted, p_hex_size: float) -> Vector2:
	var from: Vector2 = HexUtils.axial_to_pixel(mover.coord, p_hex_size)
	if mover.is_moving():
		var to: Vector2 = HexUtils.axial_to_pixel(mover.path[0], p_hex_size)
		return from.lerp(to, mover.edge_progress)
	return from


func _process(_delta: float) -> void:
	var leader: LeaderData = MapSim.leader
	if leader == null:
		visible = false
		return
	visible = true
	position = mover_pixel(leader, hex_size)
	queue_redraw()


func _draw() -> void:
	var leader: LeaderData = MapSim.leader
	if leader == null:
		return
	var sprinting: bool = leader.fast_mode and leader.stamina > 0.0 and leader.is_moving()
	draw_circle(Vector2.ZERO, hex_size * 0.27, OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, hex_size * 0.20, SPRINT_COLOR if sprinting else BODY_COLOR)
	if leader.hp < leader.max_hp:
		var fraction: float = leader.hp / leader.max_hp
		var color: Color = HP_COLOR if fraction > 0.35 else HP_LOW_COLOR
		draw_arc(Vector2.ZERO, hex_size * 0.34, -PI / 2.0,
				-PI / 2.0 + TAU * fraction, 24, color, 4.0)
