extends MarginContainer
## HUD: tick wheel + counter (top), linker tool panel and stamina/sprint
## row (bottom), defeat banner (center). Non-interactive controls ignore
## mouse so taps fall through to the game layer (see LESSONS.md); the
## Sprint/Freeze/Reverse buttons are the only controls that take input.

var _tick_label: Label
var _stamina_bar: ProgressBar
var _sprint_button: Button
var _tool_row: HBoxContainer
var _freeze_button: Button
var _reverse_button: Button
var _defeat_label: Label
var _selected: LinkerData = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		add_theme_constant_override("margin_" + side, 24)

	_build_top_row()
	_build_bottom_rows()
	_build_defeat_banner()

	MapSim.tick_advanced.connect(_update_tick_label)
	MapSim.leader_died.connect(func() -> void: _defeat_label.visible = true)
	_update_tick_label(MapSim.tick_count)


func _process(_delta: float) -> void:
	if MapSim.leader != null:
		_stamina_bar.max_value = MapSim.stamina_max
		_stamina_bar.value = MapSim.leader.stamina
	if _selected != null:
		_freeze_button.text = "Unfreeze" if _selected.frozen else "Freeze"


## Called by Main when the player taps a linker (null to deselect).
func set_selected_linker(linker: LinkerData) -> void:
	_selected = linker
	_tool_row.visible = linker != null


func _build_top_row() -> void:
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_theme_constant_override("separation", 12)
	add_child(top)

	var wheel := TickWheel.new()
	wheel.custom_minimum_size = Vector2(56, 56)
	top.add_child(wheel)

	_tick_label = Label.new()
	_tick_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tick_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tick_label.add_theme_font_size_override("font_size", 28)
	top.add_child(_tick_label)


func _build_bottom_rows() -> void:
	var bottom := VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_theme_constant_override("separation", 16)
	add_child(bottom)

	# Linker tool panel: hidden until a linker is selected.
	_tool_row = HBoxContainer.new()
	_tool_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool_row.add_theme_constant_override("separation", 16)
	_tool_row.alignment = BoxContainer.ALIGNMENT_END
	_tool_row.visible = false
	bottom.add_child(_tool_row)

	_freeze_button = _make_button("Freeze")
	_freeze_button.pressed.connect(func() -> void:
		if _selected != null:
			MapSim.set_frozen(_selected.id, not _selected.frozen))
	_tool_row.add_child(_freeze_button)

	_reverse_button = _make_button("Reverse")
	_reverse_button.pressed.connect(func() -> void:
		if _selected != null:
			MapSim.reverse(_selected.id))
	_tool_row.add_child(_reverse_button)

	# Stamina + sprint row.
	var stamina_row := HBoxContainer.new()
	stamina_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_row.add_theme_constant_override("separation", 16)
	bottom.add_child(stamina_row)

	_stamina_bar = ProgressBar.new()
	_stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_bar.show_percentage = false
	_stamina_bar.custom_minimum_size = Vector2(0, 40)
	_stamina_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamina_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stamina_row.add_child(_stamina_bar)

	# Press-and-hold: sprint lasts exactly as long as the button is held.
	_sprint_button = _make_button("Sprint")
	_sprint_button.button_down.connect(func() -> void: MapSim.set_fast(true))
	_sprint_button.button_up.connect(func() -> void: MapSim.set_fast(false))
	stamina_row.add_child(_sprint_button)


func _build_defeat_banner() -> void:
	_defeat_label = Label.new()
	_defeat_label.text = "DEFEATED"
	_defeat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_defeat_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_defeat_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_defeat_label.add_theme_font_size_override("font_size", 64)
	_defeat_label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	_defeat_label.visible = false
	add_child(_defeat_label)


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 64)
	button.add_theme_font_size_override("font_size", 26)
	return button


func _update_tick_label(tick: int) -> void:
	_tick_label.text = "Tick %d" % tick
