class_name GameState
extends Node
## Turn loop state machine. Manages clocks, speed selection, and win/lose.

enum Speed { SLOW, NORMAL, FAST }
enum Phase { AWAITING_DESTINATION, AWAITING_SPEED, RESOLVING_TURN, GAME_OVER }

const SPEED_PERSONAL_COST: Array[int] = [3, 2, 1]
const SPEED_WORLD_TICKS: Array[int] = [1, 2, 3]
const STARTING_PERSONAL_TIME: int = 30

signal clocks_changed(personal_time: int, total_world_ticks: int)
signal phase_changed(phase: Phase)
signal turn_resolved(destination: Vector2i, world_ticks: int)
signal game_ended(won: bool, reason: String)

var personal_time: int = STARTING_PERSONAL_TIME
var total_world_ticks: int = 0
var current_phase: Phase = Phase.AWAITING_DESTINATION
var selected_destination: Vector2i


func select_destination(coord: Vector2i) -> void:
	if current_phase != Phase.AWAITING_DESTINATION:
		return
	selected_destination = coord
	current_phase = Phase.AWAITING_SPEED
	phase_changed.emit(current_phase)


func cancel_destination() -> void:
	if current_phase != Phase.AWAITING_SPEED:
		return
	current_phase = Phase.AWAITING_DESTINATION
	phase_changed.emit(current_phase)


func select_speed(speed: Speed) -> void:
	if current_phase != Phase.AWAITING_SPEED:
		return
	current_phase = Phase.RESOLVING_TURN

	# Deduct personal time.
	personal_time -= SPEED_PERSONAL_COST[speed]

	# Calculate world ticks for this move.
	var ticks: int = SPEED_WORLD_TICKS[speed]
	total_world_ticks += ticks

	clocks_changed.emit(personal_time, total_world_ticks)

	# Let main.gd handle flood spread, player movement, and win/lose checks.
	turn_resolved.emit(selected_destination, ticks)


func check_personal_time() -> bool:
	## Returns true if the player is out of time (lose condition).
	return personal_time <= 0


func end_game(won: bool, reason: String) -> void:
	current_phase = Phase.GAME_OVER
	phase_changed.emit(current_phase)
	game_ended.emit(won, reason)


func begin_next_turn() -> void:
	## Called after turn resolution and win/lose checks pass.
	current_phase = Phase.AWAITING_DESTINATION
	phase_changed.emit(current_phase)


func reset() -> void:
	personal_time = STARTING_PERSONAL_TIME
	total_world_ticks = 0
	current_phase = Phase.AWAITING_DESTINATION
	clocks_changed.emit(personal_time, total_world_ticks)
	phase_changed.emit(current_phase)
