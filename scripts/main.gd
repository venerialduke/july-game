extends Node2D
## Glue: loads the level into MapSim, centers the map, and spawns one
## LinkerView per linker. All game logic lives in MapSim; all rendering
## lives in the view nodes.

const HEX_SIZE: float = 48.0

@onready var grid_view: Node2D = $HexGridView
@onready var linker_views: Node2D = $LinkerViews


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.08, 0.09, 0.12))

	MapSim.reset()
	LevelData.apply(MapSim)

	# Center the map on screen (the disc is centered on axial origin).
	var viewport_size: Vector2 = get_viewport_rect().size
	position = viewport_size / 2.0

	grid_view.hex_size = HEX_SIZE
	for linker: LinkerData in MapSim.linkers.values():
		var view := LinkerView.new()
		view.setup(linker, HEX_SIZE)
		linker_views.add_child(view)

	MapSim.spawn_leader(LevelData.PLAYER_START)
	var leader_view := LeaderView.new()
	leader_view.hex_size = HEX_SIZE
	add_child(leader_view)   # added last: draws above tiles and linkers

	# Emit initial open signals now that views are listening.
	MapSim.initialize_open_set()
	grid_view.queue_redraw()


## Tap/click a tile to walk there. Touch arrives as emulated mouse input
## (project default), so one handler covers desktop and Android.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var coord: Vector2i = HexUtils.pixel_to_axial(to_local(event.position), HEX_SIZE)
		if MapSim.tiles.has(coord):
			MapSim.request_move(coord)
