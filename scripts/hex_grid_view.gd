extends Node2D
## Dumb renderer for the hex map. Holds no authoritative state: every redraw
## queries MapSim (effective_type, open_coords, open_connector_edges) and
## repaints. Uses _draw() rather than Polygon2D nodes — programmatic
## Polygon2D was invisible on Android/Adreno (see LESSONS.md).

const TERRAIN_COLORS: Dictionary[Terrain.Type, Color] = {
	Terrain.Type.PLAINS: Color(0.45, 0.62, 0.34),
	Terrain.Type.FOREST: Color(0.22, 0.42, 0.22),
	Terrain.Type.MOUNTAIN: Color(0.45, 0.43, 0.42),
	Terrain.Type.WATER: Color(0.23, 0.42, 0.65),
	Terrain.Type.BOOST: Color(0.93, 0.78, 0.25),
}
const OUTLINE_COLOR := Color(0.10, 0.11, 0.14)
const BEAM_TILE_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const BRIDGE_COLOR := Color(0.35, 0.9, 0.95, 0.75)
const PATH_COLOR := Color(1.0, 1.0, 1.0, 0.6)

var hex_size: float = 48.0


func _ready() -> void:
	# Named methods, not lambdas: method callables auto-disconnect when this
	# node is freed, so scene reloads (tap-to-restart) leave no stale
	# connections on the MapSim autoload.
	MapSim.tick_advanced.connect(_on_tick_advanced)
	MapSim.link_opened.connect(_on_link_changed)
	MapSim.link_closed.connect(_on_link_changed)
	MapSim.leader_path_changed.connect(queue_redraw)
	MapSim.leader_moved.connect(_on_leader_moved)
	MapSim.tiles_revealed.connect(_on_tiles_revealed)


func _on_tick_advanced(_tick: int) -> void:
	queue_redraw()


func _on_link_changed(_coord: Vector2i, _effect: int) -> void:
	queue_redraw()


func _on_leader_moved(_from: Vector2i, _to: Vector2i) -> void:
	queue_redraw()


func _on_tiles_revealed(_coords: Array) -> void:
	queue_redraw()


func _draw() -> void:
	var vertices: PackedVector2Array = HexUtils.get_hex_vertices(hex_size * 0.96)

	for coord: Vector2i in MapSim.tiles:
		if not MapSim.is_revealed(coord):
			continue   # fog: unrevealed tiles are just background darkness
		var center: Vector2 = HexUtils.axial_to_pixel(coord, hex_size)
		var points := PackedVector2Array()
		for v: Vector2 in vertices:
			points.append(center + v)
		draw_colored_polygon(points, TERRAIN_COLORS[MapSim.effective_type(coord)])
		points.append(points[0])
		draw_polyline(points, OUTLINE_COLOR, 2.0)

	# White ring on every beam-covered tile (both effect types).
	var covered: Dictionary[Vector2i, bool] = {}
	for effect: LinkerData.Type in LinkerData.Type.values():
		for coord: Vector2i in MapSim.open_coords(effect):
			covered[coord] = true
	for coord: Vector2i in covered:
		if not MapSim.is_revealed(coord):
			continue
		var center: Vector2 = HexUtils.axial_to_pixel(coord, hex_size)
		var ring := PackedVector2Array()
		for v: Vector2 in HexUtils.get_hex_vertices(hex_size * 0.82):
			ring.append(center + v)
		ring.append(ring[0])
		draw_polyline(ring, BEAM_TILE_COLOR, 3.0)

	# Cyan bridge line across every open connector edge (revealed only).
	for edge: Vector4i in MapSim.open_connector_edges():
		if not MapSim.is_revealed(Vector2i(edge.x, edge.y)) \
				or not MapSim.is_revealed(Vector2i(edge.z, edge.w)):
			continue
		var a: Vector2 = HexUtils.axial_to_pixel(Vector2i(edge.x, edge.y), hex_size)
		var b: Vector2 = HexUtils.axial_to_pixel(Vector2i(edge.z, edge.w), hex_size)
		draw_line(a, b, BRIDGE_COLOR, 10.0)

	# Leader path: dots along the route, ringed dot on the destination.
	var leader: LeaderData = MapSim.leader
	if leader != null and leader.is_moving():
		for i: int in range(leader.path.size()):
			var p: Vector2 = HexUtils.axial_to_pixel(leader.path[i], hex_size)
			if i == leader.path.size() - 1:
				draw_circle(p, 7.0, PATH_COLOR)
				draw_arc(p, 13.0, 0.0, TAU, 24, PATH_COLOR, 3.0)
			else:
				draw_circle(p, 5.0, PATH_COLOR)
