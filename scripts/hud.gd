extends MarginContainer
## HUD: tick counter (top), stamina bar + sprint toggle (bottom).
## Non-interactive controls ignore mouse so taps fall through to the game
## layer (see LESSONS.md: full-screen UI eats input). The sprint Button is
## the one control that must receive taps.

var _tick_label: Label
var _stamina_bar: ProgressBar
var _sprint_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("margin_left", 24)
	add_theme_constant_override("margin_top", 24)
	add_theme_constant_override("margin_right", 24)
	add_theme_constant_override("margin_bottom", 24)

	_tick_label = Label.new()
	_tick_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tick_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tick_label.add_theme_font_size_override("font_size", 28)
	add_child(_tick_label)
	_update_label(MapSim.tick_count)
	MapSim.tick_advanced.connect(_update_label)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_theme_constant_override("separation", 16)
	add_child(bottom)

	_stamina_bar = ProgressBar.new()
	_stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_bar.show_percentage = false
	_stamina_bar.custom_minimum_size = Vector2(0, 40)
	_stamina_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamina_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_stamina_bar)

	_sprint_button = Button.new()
	_sprint_button.text = "Sprint"
	_sprint_button.toggle_mode = true
	_sprint_button.custom_minimum_size = Vector2(150, 64)
	_sprint_button.add_theme_font_size_override("font_size", 26)
	_sprint_button.toggled.connect(func(on: bool) -> void: MapSim.set_fast(on))
	bottom.add_child(_sprint_button)


func _process(_delta: float) -> void:
	if MapSim.leader != null:
		_stamina_bar.max_value = MapSim.stamina_max
		_stamina_bar.value = MapSim.leader.stamina


func _update_label(tick: int) -> void:
	_tick_label.text = "Tick %d" % tick
