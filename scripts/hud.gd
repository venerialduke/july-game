class_name HUD
extends MarginContainer
## UI overlay: clock readouts, speed buttons, and game messages.

signal speed_selected(speed: GameState.Speed)
signal restart_pressed()

@onready var _personal_time_label: Label = %PersonalTimeLabel
@onready var _world_tick_label: Label = %WorldTickLabel
@onready var _objectives_label: Label = %ObjectivesLabel
@onready var _message_label: Label = %MessageLabel
@onready var _slow_button: Button = %SlowButton
@onready var _normal_button: Button = %NormalButton
@onready var _fast_button: Button = %FastButton
@onready var _restart_button: Button = %RestartButton


func _ready() -> void:
	# Let clicks pass through the UI overlay to the game layer.
	# Only the buttons themselves should intercept input.
	_set_mouse_filter_recursive(self, MOUSE_FILTER_IGNORE)
	_slow_button.mouse_filter = MOUSE_FILTER_STOP
	_normal_button.mouse_filter = MOUSE_FILTER_STOP
	_fast_button.mouse_filter = MOUSE_FILTER_STOP
	_restart_button.mouse_filter = MOUSE_FILTER_STOP

	_slow_button.pressed.connect(_on_speed_pressed.bind(GameState.Speed.SLOW))
	_normal_button.pressed.connect(_on_speed_pressed.bind(GameState.Speed.NORMAL))
	_fast_button.pressed.connect(_on_speed_pressed.bind(GameState.Speed.FAST))
	_restart_button.pressed.connect(func() -> void: restart_pressed.emit())
	set_speed_buttons_enabled(false)


func _set_mouse_filter_recursive(node: Control, filter: MouseFilter) -> void:
	node.mouse_filter = filter
	for child: Node in node.get_children():
		if child is Control:
			_set_mouse_filter_recursive(child, filter)


func update_clocks(personal_time: int, world_ticks: int) -> void:
	_personal_time_label.text = "PT: %d" % personal_time
	_world_tick_label.text = "World: %d" % world_ticks


func update_objectives(remaining: int, total: int) -> void:
	_objectives_label.text = "Objectives: %d / %d" % [total - remaining, total]


func set_speed_buttons_enabled(enabled: bool) -> void:
	_slow_button.disabled = not enabled
	_normal_button.disabled = not enabled
	_fast_button.disabled = not enabled


func show_message(text: String) -> void:
	_message_label.text = text


func clear_message() -> void:
	_message_label.text = ""


func _on_speed_pressed(speed: GameState.Speed) -> void:
	speed_selected.emit(speed)
