class_name LeaderData
extends RefCounted
## Plain data for the player's Leader unit. MapSim owns and advances it;
## views read it. `coord` is the last tile fully entered; while moving,
## the Leader is `edge_progress` of the way toward `path[0]`.

var coord: Vector2i
var path: Array[Vector2i] = []   ## Remaining tiles to enter, in order.
var edge_progress: float = 0.0   ## 0..1 across the edge toward path[0].
var stamina: float = 0.0
var fast_mode: bool = false      ## Sprint held. Fast needs stamina > 0.
var hp: float = 100.0
var max_hp: float = 100.0


func _init(p_coord: Vector2i, p_stamina: float, p_hp: float = 100.0) -> void:
	coord = p_coord
	stamina = p_stamina
	hp = p_hp
	max_hp = p_hp


func is_moving() -> bool:
	return not path.is_empty()
