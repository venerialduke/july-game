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
## The Leader finished entering a new tile.
signal leader_moved(from: Vector2i, to: Vector2i)
## The Leader's path was blocked mid-walk (edge no longer traversable,
## e.g. a connector bridge closed ahead). Path is cleared.
signal leader_blocked(at: Vector2i)
## The Leader's path changed (new destination, cleared, or blocked).
signal leader_path_changed

## The terrain a TRANSMUTE beam temporarily applies to host + neighbor.
## Tuning knob — see NEW_DESIGN.md section 15.
var transmute_terrain: Terrain.Type = Terrain.Type.BOOST

# Movement tuning knobs (NEW_DESIGN.md section 15 spirit: knobs, not decisions).
var step_time_base: float = 1.5        ## Seconds to enter a move_cost-1 tile, slow speed.
var fast_multiplier: float = 2.0       ## Fast move is this many times quicker.
var stamina_max: float = 100.0
var stamina_drain_per_s: float = 20.0  ## Drains only while actually fast-moving.
var stamina_regen_per_s: float = 8.0   ## Regens only while fast mode is off.

var tiles: Dictionary[Vector2i, HexTileData] = {}
var linkers: Dictionary[int, LinkerData] = {}
var leader: LeaderData = null
var tick_count: int = 0
var tick_len: float = 15.0   ## Seconds per tick. Primary tuning knob.
                             ## (5s felt too short in playtest 1.)
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
## Leader movement is continuous, so it advances every call, not per tick.
func advance(dt: float) -> void:
	accum += dt
	while accum >= tick_len:
		accum -= tick_len
		_tick()
	_advance_leader(dt)


## Advance exactly n ticks, ignoring wall time. For tests and debugging.
func step_ticks(n: int) -> void:
	for i: int in range(n):
		_tick()


## Reset all state and load a level via a callable that populates the sim.
func reset() -> void:
	tiles.clear()
	linkers.clear()
	leader = null
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


# --- Leader movement -------------------------------------------------------

func spawn_leader(coord: Vector2i) -> LeaderData:
	leader = LeaderData.new(coord, stamina_max)
	return leader


## Sprint toggle: fast move drains stamina; slow move is free.
func set_fast(enabled: bool) -> void:
	if leader != null:
		leader.fast_mode = enabled


## Pathfind to `target` and start walking. Returns false if unreachable.
## Mid-walk retargeting keeps the edge currently being crossed.
func request_move(target: Vector2i) -> bool:
	if leader == null or not tiles.has(target):
		return false
	var mid_edge: bool = leader.is_moving() and leader.edge_progress > 0.0
	var start: Vector2i = leader.path[0] if mid_edge else leader.coord
	var new_path: Array[Vector2i] = find_path(start, target)
	if new_path.is_empty() and start != target:
		return false
	if mid_edge:
		var kept: Array[Vector2i] = [leader.path[0]]
		kept.append_array(new_path)
		leader.path = kept
	else:
		leader.path = new_path
		leader.edge_progress = 0.0
	leader_path_changed.emit()
	return true


## True if the from->to edge is walkable right now: the destination's
## effective type is passable, or a CONNECTOR beam bridges the edge.
## Transient by nature — callers re-check at every edge crossing.
func can_traverse(from: Vector2i, to: Vector2i) -> bool:
	if not tiles.has(to):
		return false
	return Terrain.is_passable(effective_type(to)) or is_connector_open(from, to)


## Dijkstra over the current transient state. The result is a plan, not a
## promise: edges are re-validated during the walk. Returns tiles to enter
## in order, excluding `start`; empty if unreachable.
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if start == goal or not tiles.has(start) or not tiles.has(goal):
		return empty

	var dist: Dictionary[Vector2i, float] = {start: 0.0}
	var prev: Dictionary[Vector2i, Vector2i] = {}
	var visited: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = [start]

	while not frontier.is_empty():
		# Pop the lowest-cost frontier coord. Map is tiny; linear scan is fine.
		var best_i: int = 0
		for i: int in range(1, frontier.size()):
			if dist[frontier[i]] < dist[frontier[best_i]]:
				best_i = i
		var current: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		if current == goal:
			break
		if visited.has(current):
			continue
		visited[current] = true
		for next: Vector2i in HexUtils.get_neighbors(current):
			if visited.has(next) or not can_traverse(current, next):
				continue
			var cost: float = dist[current] + _entry_cost(current, next)
			if cost < dist.get(next, INF):
				dist[next] = cost
				prev[next] = current
				frontier.append(next)

	if not prev.has(goal):
		return empty
	var path: Array[Vector2i] = [goal]
	var walk: Vector2i = goal
	while prev[walk] != start:
		walk = prev[walk]
		path.push_front(walk)
	return path


## Cost to enter `to` across the from->to edge. A connector bridge makes an
## otherwise-impassable tile cost 1 (the bridge is the cheap part).
func _entry_cost(from: Vector2i, to: Vector2i) -> float:
	var cost: int = Terrain.move_cost(effective_type(to))
	if cost >= 0:
		return float(cost)
	return 1.0 if is_connector_open(from, to) else INF


func _traversal_time(from: Vector2i, to: Vector2i, fast: bool) -> float:
	var t: float = step_time_base * _entry_cost(from, to)
	return t / fast_multiplier if fast else t


func _advance_leader(dt: float) -> void:
	if leader == null:
		return
	var remaining: float = dt
	while remaining > 0.0 and leader.is_moving():
		var next: Vector2i = leader.path[0]
		# Re-validate the edge every advance: transient effects mean a
		# bridge can close (or a transmuted mountain revert) mid-walk.
		if not can_traverse(leader.coord, next):
			leader.path.clear()
			leader.edge_progress = 0.0
			leader_path_changed.emit()
			leader_blocked.emit(next)
			break
		var fast: bool = leader.fast_mode and leader.stamina > 0.0
		var t: float = _traversal_time(leader.coord, next, fast)
		var time_to_finish: float = (1.0 - leader.edge_progress) * t
		if remaining >= time_to_finish:
			if fast:
				_drain_stamina(time_to_finish)
			remaining -= time_to_finish
			var from: Vector2i = leader.coord
			leader.coord = next
			leader.path.pop_front()
			leader.edge_progress = 0.0
			leader_moved.emit(from, next)
		else:
			if fast:
				_drain_stamina(remaining)
			leader.edge_progress += remaining / t
			remaining = 0.0
	if not leader.fast_mode:
		leader.stamina = minf(leader.stamina + stamina_regen_per_s * dt, stamina_max)


func _drain_stamina(seconds: float) -> void:
	leader.stamina = maxf(leader.stamina - stamina_drain_per_s * seconds, 0.0)


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
