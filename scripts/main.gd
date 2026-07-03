extends Node2D
## Glue: loads the level into MapSim, spawns view nodes, routes input.
## Tap a linker's tile to select it (tools in the HUD act on it); tap any
## other tile to deselect and walk there. All game logic lives in MapSim.

const HEX_SIZE: float = 48.0

@onready var grid_view: Node2D = $HexGridView
@onready var linker_views: Node2D = $LinkerViews
@onready var hud: MarginContainer = $UILayer/HUD

var _linker_view_by_id: Dictionary[int, LinkerView] = {}
var _unit_view_by_id: Dictionary[int, UnitView] = {}
var _enemy_view_by_id: Dictionary[int, EnemyView] = {}
var _selected_linker_id: int = -1


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.08, 0.09, 0.12))

	MapSim.reset()
	LevelData.apply(MapSim)

	# Center the map on screen (the disc is centered on axial origin).
	position = get_viewport_rect().size / 2.0

	grid_view.hex_size = HEX_SIZE
	for linker: LinkerData in MapSim.linkers.values():
		var view := LinkerView.new()
		view.setup(linker, HEX_SIZE)
		linker_views.add_child(view)
		_linker_view_by_id[linker.id] = view

	MapSim.spawn_leader(LevelData.PLAYER_START)
	var leader_view := LeaderView.new()
	leader_view.hex_size = HEX_SIZE
	add_child(leader_view)

	for id: int in MapSim.units:
		var unit_view := UnitView.new()
		unit_view.setup(MapSim.units[id], HEX_SIZE)
		add_child(unit_view)
		_unit_view_by_id[id] = unit_view
	for id: int in MapSim.enemies:
		var enemy_view := EnemyView.new()
		enemy_view.setup(MapSim.enemies[id], HEX_SIZE)
		add_child(enemy_view)
		_enemy_view_by_id[id] = enemy_view

	MapSim.unit_died.connect(_on_unit_died)
	MapSim.enemy_died.connect(_on_enemy_died)

	# Emit initial open signals now that views are listening.
	MapSim.initialize_open_set()
	grid_view.queue_redraw()


## Tap/click routing. Touch arrives as emulated mouse input (project
## default), so one handler covers desktop and Android.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var coord: Vector2i = HexUtils.pixel_to_axial(to_local(event.position), HEX_SIZE)
		if not MapSim.tiles.has(coord):
			return
		var linker: LinkerData = MapSim.linker_at(coord)
		if linker != null:
			# Tap a linker to select it; tap it again to deselect.
			_select_linker(-1 if linker.id == _selected_linker_id else linker.id)
		else:
			_select_linker(-1)
			MapSim.request_move(coord)


func _select_linker(id: int) -> void:
	_selected_linker_id = id
	for linker_id: int in _linker_view_by_id:
		_linker_view_by_id[linker_id].selected = linker_id == id
	hud.set_selected_linker(MapSim.linkers.get(id))


func _on_unit_died(id: int) -> void:
	if _unit_view_by_id.has(id):
		_unit_view_by_id[id].queue_free()
		_unit_view_by_id.erase(id)


func _on_enemy_died(id: int) -> void:
	if _enemy_view_by_id.has(id):
		_enemy_view_by_id[id].queue_free()
		_enemy_view_by_id.erase(id)
