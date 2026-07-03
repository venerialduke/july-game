class_name EnemyData
extends RefCounted
## Plain data for one enemy. An empty archetype ("") is the legacy
## stationary dummy (stats from MapSim knobs, no AI). Typed archetypes
## get stats and behavior params from EnemyTypes.TABLE and move
## continuously like the Leader.

enum AIState { WANDER, CHASE, RETURN }

var coord: Vector2i
var hp: float
var max_hp: float
var power: float = 10.0

var archetype: StringName = &""
var speed_mult: float = 0.0        ## 0 = never moves (legacy dummy).
var aggro_radius: int = 0
var leash_range: int = 0
var repath_interval: float = 2.0
var wander_interval: float = 4.0
var wander_radius: int = 2

var home: Vector2i                 ## Patrol anchor (brute leash reference).
var state: AIState = AIState.WANDER
var path: Array[Vector2i] = []     ## Remaining tiles to enter, in order.
var edge_progress: float = 0.0     ## 0..1 across the edge toward path[0].
var repath_timer: float = 0.0
var wander_timer: float = 0.0


func _init(p_coord: Vector2i, p_hp: float) -> void:
	coord = p_coord
	home = p_coord
	hp = p_hp
	max_hp = p_hp


func is_moving() -> bool:
	return not path.is_empty()


func apply_archetype(p_archetype: StringName) -> void:
	var stats: Dictionary = EnemyTypes.stats(p_archetype)
	if stats.is_empty():
		return
	archetype = p_archetype
	hp = stats["hp"]
	max_hp = stats["hp"]
	power = stats["power"]
	speed_mult = stats["speed_mult"]
	aggro_radius = stats["aggro_radius"]
	leash_range = stats["leash_range"]
	repath_interval = stats["repath_interval"]
	wander_interval = stats["wander_interval"]
	wander_radius = stats["wander_radius"]
