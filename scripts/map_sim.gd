extends Node
## MapSim — central simulation autoload. Owns all game state as plain data
## and advances it in a single tick loop. Visual nodes read state and render
## it; they hold no authoritative state and never compute hex geometry.
##
## No class_name: this is registered as the `MapSim` autoload, and
## class_name + autoload of the same name conflict (see LESSONS.md).
## Tests instantiate this script directly with load(...).new().
##
## Effects are transient: open-state is a pure function of current
## orientations. Nothing here stores effect history.

## A beam now covers `coord` with `effect` (LinkerData.Type). Fired once per
## transition, not per tick.
signal link_opened(coord: Vector2i, effect: LinkerData.Type)
## A beam no longer covers `coord` with `effect`.
signal link_closed(coord: Vector2i, effect: LinkerData.Type)
## The a<->b edge gained an active beam of `effect`. Undirected: a/b are in
## normalized order, not host/target order.
signal edge_opened(a: Vector2i, b: Vector2i, effect: LinkerData.Type)
## The a<->b edge lost its active beam of `effect`.
signal edge_closed(a: Vector2i, b: Vector2i, effect: LinkerData.Type)
## A linker snapped to a new orientation (for view rotation lerp).
signal linker_stepped(id: int, orientation: int)
## The global clock advanced one tick.
signal tick_advanced(tick: int)

## The terrain a TRANSMUTE beam temporarily applies to host + neighbor.
## Tuning knob — see NEW_DESIGN.md section 15.
var transmute_terrain: Terrain.Type = Terrain.Type.BOOST

var tiles: Dictionary[Vector2i, HexTileData] = {}
var linkers: Dictionary[int, LinkerData] = {}
var tick_count: int = 0
var tick_len: float = 5.0    ## Seconds per tick. Primary tuning knob.
var accum: float = 0.0

## coord -> {LinkerData.Type: count}. Counts matter: two beams of the same
## type on one tile must not close the effect when only one moves off.
var _open_tiles: Dictionary[Vector2i, Dictionary] = {}
## Vector4i edge key (normalized) -> {LinkerData.Type: count}.
var _open_edges: Dictionary[Vector4i, Dictionary] = {}
var _next_linker_id: int = 0


func _process(delta: float) -> void:
	advance(delta)


## Advance the clock by dt seconds, firing whole ticks as they accumulate.
func advance(dt: float) -> void:
	accum += dt
	while accum >= tick_len:
		accum -= tick_len
		_tick()


## Advance exactly n ticks, ignoring wall time. For tests and debugging.
func step_ticks(n: int) -> void:
	for i: int in range(n):
		_tick()


## Reset all state and load a level via a callable that populates the sim.
func reset() -> void:
	tiles.clear()
	linkers.clear()
	tick_count = 0
	accum = 0.0
	_open_tiles.clear()
	_open_edges.clear()
	_next_linker_id = 0


func add_tile(coord: Vector2i, terrain: Terrain.Type = Terrain.Type.PLAINS) -> HexTileData:
	var tile := HexTileData.new(coord, terrain)
	tiles[coord] = tile
	return tile


func add_linker(linker: LinkerData) -> int:
	linker.id = _next_linker_id
	_next_linker_id += 1
	linkers[linker.id] = linker
	return linker.id


## Call after populating tiles/linkers so initial beams emit their
## link_opened signals and the open set is coherent before the first tick.
func initialize_open_set() -> void:
	_recompute_open_set()


# --- Reads (the only interface downstream systems may use) ---------------

## The tile's current gameplay type: base terrain unless a TRANSMUTE beam
## covers it right now. Movement, combat, and rendering all read through
## this every step — never cache the result (see NEW_DESIGN.md section 6).
func effective_type(coord: Vector2i) -> Terrain.Type:
	if not tiles.has(coord):
		return Terrain.Type.VOID
	var effects: Dictionary = _open_tiles.get(coord, {})
	if effects.get(LinkerData.Type.TRANSMUTE, 0) > 0:
		return transmute_terrain
	return tiles[coord].terrain


## True while a CONNECTOR beam is active across the a<->b edge.
func is_connector_open(a: Vector2i, b: Vector2i) -> bool:
	var effects: Dictionary = _open_edges.get(_edge_key(a, b), {})
	return effects.get(LinkerData.Type.CONNECTOR, 0) > 0


## All edges currently crossed by a CONNECTOR beam, as normalized coord
## pairs (x,y = tile a, z,w = tile b). For rendering bridges.
func open_connector_edges() -> Array[Vector4i]:
	var result: Array[Vector4i] = []
	for key: Vector4i in _open_edges:
		if _open_edges[key].get(LinkerData.Type.CONNECTOR, 0) > 0:
			result.append(key)
	return result


## All coords currently covered by at least one beam of `effect`.
func open_coords(effect: LinkerData.Type) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord: Vector2i in _open_tiles:
		if _open_tiles[coord].get(effect, 0) > 0:
			result.append(coord)
	return result


## The tile a linker's link edge currently points at.
func beam_target(linker: LinkerData, edge: int) -> Vector2i:
	var phys: int = posmod(edge + linker.orientation, 6)
	return linker.host_coord + HexUtils.DIRECTIONS[phys]


# --- Tools (act on spin state; never touch what the beam does) ------------

## Freeze holds the linker's current beam open: it is skipped on ticks.
func set_frozen(id: int, frozen: bool) -> void:
	if linkers.has(id):
		linkers[id].frozen = frozen


## Reverse flips spin direction, swinging the beam back the other way.
func reverse(id: int) -> void:
	if linkers.has(id):
		linkers[id].spin_dir *= -1


# --- Tick internals --------------------------------------------------------

func _tick() -> void:
	tick_count += 1
	_step_linkers()
	_recompute_open_set()
	tick_advanced.emit(tick_count)


func _step_linkers() -> void:
	for linker: LinkerData in linkers.values():
		if linker.frozen:
			continue
		if posmod(tick_count - linker.phase_offset, linker.period) != 0:
			continue
		linker.orientation = posmod(linker.orientation + linker.spin_dir, 6)
		linker_stepped.emit(linker.id, linker.orientation)


## Recompute the full open set from current orientations and diff it against
## the previous set, emitting open/close signals exactly once per transition.
func _recompute_open_set() -> void:
	var current_tiles: Dictionary[Vector2i, Dictionary] = {}
	var current_edges: Dictionary[Vector4i, Dictionary] = {}

	for linker: LinkerData in linkers.values():
		for edge: int in linker.links:
			var target: Vector2i = beam_target(linker, edge)
			# The effect flanks the active edge: host tile AND pointed-at
			# neighbor. Beams pointing off-map only affect the host.
			_bump(current_tiles, linker.host_coord, linker.type)
			if tiles.has(target):
				_bump(current_tiles, target, linker.type)
				_bump(current_edges, _edge_key(linker.host_coord, target), linker.type)

	_diff_tiles(current_tiles)
	_diff_edges(current_edges)
	_open_tiles = current_tiles
	_open_edges = current_edges


func _diff_tiles(current: Dictionary[Vector2i, Dictionary]) -> void:
	for coord: Vector2i in current:
		for effect: LinkerData.Type in current[coord]:
			if _open_tiles.get(coord, {}).get(effect, 0) == 0:
				link_opened.emit(coord, effect)
	for coord: Vector2i in _open_tiles:
		for effect: LinkerData.Type in _open_tiles[coord]:
			if current.get(coord, {}).get(effect, 0) == 0:
				link_closed.emit(coord, effect)


func _diff_edges(current: Dictionary[Vector4i, Dictionary]) -> void:
	for key: Vector4i in current:
		for effect: LinkerData.Type in current[key]:
			if _open_edges.get(key, {}).get(effect, 0) == 0:
				edge_opened.emit(Vector2i(key.x, key.y), Vector2i(key.z, key.w), effect)
	for key: Vector4i in _open_edges:
		for effect: LinkerData.Type in _open_edges[key]:
			if current.get(key, {}).get(effect, 0) == 0:
				edge_closed.emit(Vector2i(key.x, key.y), Vector2i(key.z, key.w), effect)


static func _bump(dict: Dictionary, key: Variant, effect: LinkerData.Type) -> void:
	if not dict.has(key):
		dict[key] = {}
	dict[key][effect] = dict[key].get(effect, 0) + 1


## Normalized undirected edge key: smaller coord first so (a,b) == (b,a).
static func _edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)
