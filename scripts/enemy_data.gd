class_name EnemyData
extends RefCounted
## Plain data for a dumb AI enemy. v0: stationary; fights automatically
## when Leader or party units are adjacent.

var coord: Vector2i
var hp: float
var max_hp: float


func _init(p_coord: Vector2i, p_hp: float) -> void:
	coord = p_coord
	hp = p_hp
	max_hp = p_hp
