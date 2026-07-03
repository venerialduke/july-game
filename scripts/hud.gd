extends MarginContainer
## Minimal debug HUD for the linker prototype: tick counter and a legend.
## All controls ignore mouse so clicks fall through to the game layer
## (see LESSONS.md: full-screen UI eats input).

var _tick_label: Label


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


func _update_label(tick: int) -> void:
	_tick_label.text = "Tick %d" % tick
