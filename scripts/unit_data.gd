class_name UnitData
extends RefCounted
## Plain data for a Unit: neutral on the map until the Leader walks onto
## it, then collected into the party and trailing the Leader.

var coord: Vector2i
var collected: bool = false
var hp: float
var max_hp: float


func _init(p_coord: Vector2i, p_hp: float) -> void:
	coord = p_coord
	hp = p_hp
	max_hp = p_hp
