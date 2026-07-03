class_name LeaderData
extends RefCounted
## Plain data for the player's Leader unit. MapSim owns and advances it;
## views read it. `coord` is the last tile fully entered; while moving,
## the Leader is `edge_progress` of the way toward `path[0]`.

var coord: Vector2i
var path: Array[Vector2i] = []   ## Remaining tiles to enter, in order.
var edge_progress: float = 0.0   ## 0..1 across the edge toward path[0].
var stamina: float = 0.0
var fast_mode: bool = false      ## Sprint toggle. Fast needs stamina > 0.


func _init(p_coord: Vector2i, p_stamina: float) -> void:
	coord = p_coord
	stamina = p_stamina


func is_moving() -> bool:
	return not path.is_empty()
