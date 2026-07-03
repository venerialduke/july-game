class_name LeaderView
extends Node2D
## Visual for the Leader. Reads MapSim.leader each frame and interpolates
## its pixel position from coord + edge_progress. Holds no state.

const BODY_COLOR := Color(0.95, 0.96, 1.0)
const SPRINT_COLOR := Color(1.0, 0.58, 0.2)
const OUTLINE_COLOR := Color(0.12, 0.13, 0.16)

var hex_size: float = 48.0


## The Leader's interpolated pixel position (between tiles while moving).
## Static so UnitView can cluster party units around the same point.
static func leader_pixel(leader: LeaderData, p_hex_size: float) -> Vector2:
	var from: Vector2 = HexUtils.axial_to_pixel(leader.coord, p_hex_size)
	if leader.is_moving():
		var to: Vector2 = HexUtils.axial_to_pixel(leader.path[0], p_hex_size)
		return from.lerp(to, leader.edge_progress)
	return from


func _process(_delta: float) -> void:
	var leader: LeaderData = MapSim.leader
	if leader == null:
		visible = false
		return
	visible = true
	position = leader_pixel(leader, hex_size)
	queue_redraw()


func _draw() -> void:
	var leader: LeaderData = MapSim.leader
	if leader == null:
		return
	var sprinting: bool = leader.fast_mode and leader.stamina > 0.0 and leader.is_moving()
	draw_circle(Vector2.ZERO, hex_size * 0.27, OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, hex_size * 0.20, SPRINT_COLOR if sprinting else BODY_COLOR)
