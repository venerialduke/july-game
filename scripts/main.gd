extends Node2D
## Glue: generates the map into MapSim, spawns view nodes, routes camera
## taps into move orders. The HUD tool panel appears automatically while
## the Leader stands on a linker's tile. Sprint = holding the "sprint"
## action (Space/Shift) or the touch button.

const HEX_SIZE: float = 48.0

## -1 = random seed each run (printed for repro); set >= 0 to fix the map.
const MAP_SEED: int = -1

@onready var grid_view: Node2D = $HexGridView
@onready var linker_views: Node2D = $LinkerViews
@onready var hud: MarginContainer = $UILayer/HUD

var camera: CameraController
var _linker_view_by_id: Dictionary[int, LinkerView] = {}
var _unit_view_by_id: Dictionary[int, UnitView] = {}
var _enemy_view_by_id: Dictionary[int, EnemyView] = {}
var _selected_linker_id: int = -1


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.08, 0.09, 0.12))

	var seed_value: int = MAP_SEED if MAP_SEED >= 0 else randi()
	print("MapGen seed: %d" % seed_value)
	MapSim.reset()
	MapGen.generate(MapSim, seed_value)

	grid_view.hex_size = HEX_SIZE
	for linker: LinkerData in MapSim.linkers.values():
		var view := LinkerView.new()
		view.setup(linker, HEX_SIZE)
		linker_views.add_child(view)
		_linker_view_by_id[linker.id] = view

	MapSim.spawn_leader(MapGen.PLAYER_START)
	var leader_view := LeaderView.new()
	leader_view.hex_size = HEX_SIZE
	add_child(leader_view)

	for id: int in MapSim.units:
		var unit_view := UnitView.new()
		unit_view.setup(id, MapSim.units[id], HEX_SIZE)
		add_child(unit_view)
		_unit_view_by_id[id] = unit_view
	for id: int in MapSim.enemies:
		var enemy_view := EnemyView.new()
		enemy_view.setup(MapSim.enemies[id], HEX_SIZE)
		add_child(enemy_view)
		_enemy_view_by_id[id] = enemy_view

	camera = CameraController.new()
	camera.hex_size = HEX_SIZE
	add_child(camera)
	camera.make_current()
	camera.snap_to_leader()
	camera.tapped.connect(_on_world_tapped)

	MapSim.unit_died.connect(_on_unit_died)
	MapSim.enemy_died.connect(_on_enemy_died)

	# Emit initial open signals now that views are listening.
	MapSim.initialize_open_set()
	grid_view.queue_redraw()


func _process(_delta: float) -> void:
	MapSim.set_fast(Input.is_action_pressed("sprint"))

	# Tool panel targets the linker under the Leader's feet, if any.
	var engaged: LinkerData = null
	if MapSim.leader != null:
		engaged = MapSim.linker_at(MapSim.leader.coord)
	var engaged_id: int = engaged.id if engaged != null else -1
	if engaged_id != _selected_linker_id:
		_selected_linker_id = engaged_id
		for linker_id: int in _linker_view_by_id:
			_linker_view_by_id[linker_id].selected = linker_id == engaged_id
		hud.set_selected_linker(engaged)


## Camera taps: after defeat any tap restarts; otherwise it's a move order,
## and an accepted order re-engages camera follow.
func _on_world_tapped(world_pos: Vector2) -> void:
	if MapSim.leader != null and MapSim.leader.hp <= 0.0:
		# _ready() resets MapSim and rebuilds every view from scratch.
		get_tree().reload_current_scene()
		return
	var coord: Vector2i = HexUtils.pixel_to_axial(world_pos, HEX_SIZE)
	if MapSim.tiles.has(coord) and MapSim.request_move(coord):
		camera.follow = true


func _on_unit_died(id: int) -> void:
	if _unit_view_by_id.has(id):
		_unit_view_by_id[id].queue_free()
		_unit_view_by_id.erase(id)


func _on_enemy_died(id: int) -> void:
	if _enemy_view_by_id.has(id):
		_enemy_view_by_id[id].queue_free()
		_enemy_view_by_id.erase(id)
