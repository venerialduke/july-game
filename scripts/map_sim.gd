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
## A neutral unit joined the party (Leader walked onto its tile).
signal unit_collected(id: int)
## A party unit died in combat and was removed.
signal unit_died(id: int)
## An enemy died in combat and was removed.
signal enemy_died(id: int)
## The Leader's hp reached zero. Fired once.
signal leader_died
## New tiles came out of the fog (Array[Vector2i]).
signal tiles_revealed(coords: Array)
## An enemy acquired the Leader and started chasing. For telegraphs.
signal enemy_aggroed(id: int)

## The terrain a TRANSMUTE beam temporarily applies to host + neighbor.
## Tuning knob — see NEW_DESIGN.md section 15.
var transmute_terrain: Terrain.Type = Terrain.Type.BOOST

# Movement tuning knobs (NEW_DESIGN.md section 15 spirit: knobs, not decisions).
var step_time_base: float = 1.5        ## Seconds to enter a move_cost-1 tile, slow speed.
var fast_multiplier: float = 2.0       ## Fast move is this many times quicker.
var stamina_max: float = 100.0
var stamina_drain_per_s: float = 20.0  ## Drains only while actually fast-moving.
var stamina_regen_per_s: float = 8.0   ## Regens only while the Leader is stopped.

# Combat tuning knobs. All damage is per second, continuous, adjacency-based.
var leader_max_hp: float = 100.0
var leader_power: float = 12.0
var unit_max_hp: float = 40.0
var unit_power: float = 8.0
var enemy_max_hp: float = 60.0
var enemy_power: float = 10.0
var boost_attack_mult: float = 2.0     ## Attacker standing on a BOOST tile.
var party_slots: int = 3               ## Units the Leader can house; they ride its tile.

# Fog of war (simple: permanent reveal as the Leader explores).
var fog_enabled: bool = true
var sight_radius: int = 3
var revealed: Dictionary[Vector2i, bool] = {}

## Sim-side RNG (enemy wander targets). Seeded by MapGen.generate so the
## whole sim stays deterministic: same seed + same dt sequence = same run.
var rng := RandomNumberGenerator.new()

var tiles: Dictionary[Vector2i, HexTileData] = {}
var linkers: Dictionary[int, LinkerData] = {}
var leader: LeaderData = null
var units: Dictionary[int, UnitData] = {}
var enemies: Dictionary[int, EnemyData] = {}
var party: Array[int] = []             ## Collected unit ids, in trail order.
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
var _next_unit_id: int = 0
var _next_enemy_id: int = 0
var _leader_death_emitted: bool = false


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
	_advance_enemies(dt)
	_advance_combat(dt)


## Fraction [0, 1) of the way to the next global tick. For the HUD wheel.
func tick_progress() -> float:
	return clampf(accum / tick_len, 0.0, 1.0)


## Advance exactly n ticks, ignoring wall time. For tests and debugging.
func step_ticks(n: int) -> void:
	for i: int in range(n):
		_tick()


## Reset all state and load a level via a callable that populates the sim.
func reset() -> void:
	tiles.clear()
	linkers.clear()
	leader = null
	units.clear()
	enemies.clear()
	party.clear()
	tick_count = 0
	accum = 0.0
	revealed.clear()
	_open_tiles.clear()
	_open_edges.clear()
	_next_linker_id = 0
	_next_unit_id = 0
	_next_enemy_id = 0
	_leader_death_emitted = false


func add_tile(coord: Vector2i, terrain: Terrain.Type = Terrain.Type.PLAINS) -> HexTileData:
	var tile := HexTileData.new(coord, terrain)
	tiles[coord] = tile
	return tile


func add_linker(linker: LinkerData) -> int:
	linker.id = _next_linker_id
	_next_linker_id += 1
	linkers[linker.id] = linker
	return linker.id


func add_unit(coord: Vector2i) -> int:
	var id: int = _next_unit_id
	_next_unit_id += 1
	units[id] = UnitData.new(coord, unit_max_hp)
	return id


## Empty archetype = legacy stationary dummy using the sim knobs.
func add_enemy(coord: Vector2i, archetype: StringName = &"") -> int:
	var id: int = _next_enemy_id
	_next_enemy_id += 1
	var enemy := EnemyData.new(coord, enemy_max_hp)
	enemy.power = enemy_power
	enemy.apply_archetype(archetype)
	enemies[id] = enemy
	return id


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


## The linker hosted on `coord`, or null. v0 assumes at most one per tile.
func linker_at(coord: Vector2i) -> LinkerData:
	for linker: LinkerData in linkers.values():
		if linker.host_coord == coord:
			return linker
	return null


## The tile a linker's link edge currently points at.
func beam_target(linker: LinkerData, edge: int) -> Vector2i:
	var phys: int = posmod(edge + linker.orientation, 6)
	return linker.host_coord + HexUtils.DIRECTIONS[phys]


# --- Leader movement -------------------------------------------------------

func spawn_leader(coord: Vector2i) -> LeaderData:
	leader = LeaderData.new(coord, stamina_max, leader_max_hp)
	_leader_death_emitted = false
	_reveal_around(coord)
	return leader


## True when the tile is out of the fog (or fog is off). Views draw only
## revealed tiles; move orders may only target revealed tiles.
func is_revealed(coord: Vector2i) -> bool:
	return not fog_enabled or revealed.get(coord, false)


func _reveal_around(center: Vector2i) -> void:
	var newly: Array[Vector2i] = []
	for q: int in range(-sight_radius, sight_radius + 1):
		for r: int in range(maxi(-sight_radius, -q - sight_radius),
				mini(sight_radius, -q + sight_radius) + 1):
			var coord: Vector2i = center + Vector2i(q, r)
			if tiles.has(coord) and not revealed.get(coord, false):
				revealed[coord] = true
				newly.append(coord)
	if not newly.is_empty():
		tiles_revealed.emit(newly)


## Sprint toggle: fast move drains stamina; slow move is free.
func set_fast(enabled: bool) -> void:
	if leader != null:
		leader.fast_mode = enabled


## Pathfind to `target` and start walking. Returns false if unreachable.
## Mid-walk retargeting keeps the edge currently being crossed.
func request_move(target: Vector2i) -> bool:
	if leader == null or leader.hp <= 0.0 or not tiles.has(target):
		return false
	if not is_revealed(target):
		return false   # can't order a move into the fog
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


## Seconds to cross the from->to edge at `speed_mult` (1.0 = Leader walk).
func _traversal_time(from: Vector2i, to: Vector2i, speed_mult: float) -> float:
	return step_time_base * _entry_cost(from, to) / speed_mult


func _advance_leader(dt: float) -> void:
	if leader == null or leader.hp <= 0.0:
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
		var t: float = _traversal_time(leader.coord, next,
				fast_multiplier if fast else 1.0)
		var time_to_finish: float = (1.0 - leader.edge_progress) * t
		if remaining >= time_to_finish:
			if fast:
				_drain_stamina(time_to_finish)
			remaining -= time_to_finish
			var from: Vector2i = leader.coord
			leader.coord = next
			leader.path.pop_front()
			leader.edge_progress = 0.0
			_sync_party()
			_collect_units_at(next)
			_reveal_around(next)
			leader_moved.emit(from, next)
		else:
			if fast:
				_drain_stamina(remaining)
			leader.edge_progress += remaining / t
			remaining = 0.0
	# Stamina regens only while stopped: `remaining` is exactly the portion
	# of dt the Leader spent standing still.
	if not leader.is_moving() and remaining > 0.0:
		leader.stamina = minf(leader.stamina + stamina_regen_per_s * remaining, stamina_max)


## Party units ride in the Leader's tile (slot model): every collected
## unit shares the Leader's coord and moves with it.
func _sync_party() -> void:
	for id: int in party:
		units[id].coord = leader.coord


## Collect neutral units on this tile, up to the Leader's free slots.
func _collect_units_at(coord: Vector2i) -> void:
	for id: int in units:
		if party.size() >= party_slots:
			return
		var unit: UnitData = units[id]
		if not unit.collected and unit.coord == coord:
			unit.collected = true
			party.append(id)
			unit_collected.emit(id)


func _drain_stamina(seconds: float) -> void:
	leader.stamina = maxf(leader.stamina - stamina_drain_per_s * seconds, 0.0)


# --- Enemy AI + movement ----------------------------------------------------

## Enemies move continuously through the same traversal rules as the
## Leader (effective_type, connector bridges). Decisions run on per-enemy
## timers; wander targets come from the seeded sim RNG, so runs stay
## deterministic. Archetype behavior:
##   drifter — wanders, never aggros.
##   hunter  — chases the Leader within aggro_radius, gives up beyond
##             leash_range (distance to Leader), re-paths on a timer.
##   brute   — patrols near home; chases inside aggro_radius but abandons
##             the chase beyond leash_range FROM HOME and walks back.
func _advance_enemies(dt: float) -> void:
	for id: int in enemies:
		var enemy: EnemyData = enemies[id]
		if enemy.speed_mult <= 0.0:
			continue   # legacy stationary dummy
		enemy.repath_timer -= dt
		enemy.wander_timer -= dt
		_update_enemy_ai(id, enemy)
		_advance_enemy_path(enemy, dt)


func _update_enemy_ai(id: int, enemy: EnemyData) -> void:
	var leader_alive: bool = leader != null and leader.hp > 0.0
	var dist_to_leader: int = HexUtils.axial_distance(enemy.coord, leader.coord) \
			if leader_alive else 9999

	# Acquire / give up. A brute outside its territory cannot re-acquire —
	# otherwise it oscillates at the leash edge forever instead of going home.
	if enemy.state != EnemyData.AIState.CHASE:
		var can_aggro: bool = leader_alive and enemy.aggro_radius > 0 \
				and dist_to_leader <= enemy.aggro_radius
		if can_aggro and enemy.archetype == &"brute":
			can_aggro = HexUtils.axial_distance(enemy.coord, enemy.home) <= enemy.leash_range
		if can_aggro:
			enemy.state = EnemyData.AIState.CHASE
			enemy.repath_timer = 0.0
			enemy_aggroed.emit(id)
	else:
		var give_up: bool = not leader_alive
		if enemy.archetype == &"brute":
			give_up = give_up or HexUtils.axial_distance(enemy.coord, enemy.home) > enemy.leash_range
		else:
			give_up = give_up or dist_to_leader > enemy.leash_range
		if give_up:
			enemy.path.clear()
			enemy.edge_progress = 0.0
			enemy.state = EnemyData.AIState.RETURN if enemy.archetype == &"brute" \
					else EnemyData.AIState.WANDER

	match enemy.state:
		EnemyData.AIState.CHASE:
			if dist_to_leader <= 1:
				# In combat range: stand and fight.
				enemy.path.clear()
				enemy.edge_progress = 0.0
			elif enemy.repath_timer <= 0.0:
				enemy.repath_timer = enemy.repath_interval
				if enemy.is_moving() and enemy.edge_progress > 0.0:
					# Keep the edge being crossed; re-plan from its far end.
					var kept: Array[Vector2i] = [enemy.path[0]]
					kept.append_array(find_path(enemy.path[0], leader.coord))
					enemy.path = kept
				else:
					enemy.path = find_path(enemy.coord, leader.coord)
		EnemyData.AIState.RETURN:
			if enemy.coord == enemy.home and not enemy.is_moving():
				enemy.state = EnemyData.AIState.WANDER
			elif not enemy.is_moving():
				enemy.path = find_path(enemy.coord, enemy.home)
				if enemy.path.is_empty():
					enemy.state = EnemyData.AIState.WANDER   # home unreachable
		EnemyData.AIState.WANDER:
			if not enemy.is_moving() and enemy.wander_timer <= 0.0:
				enemy.wander_timer = enemy.wander_interval
				var anchor: Vector2i = enemy.home if enemy.archetype == &"brute" \
						else enemy.coord
				var target: Vector2i = _random_tile_near(anchor, enemy.wander_radius)
				if target != enemy.coord:
					enemy.path = find_path(enemy.coord, target)


## A random passable tile within `radius` of `anchor` (seeded RNG).
func _random_tile_near(anchor: Vector2i, radius: int) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for q: int in range(-radius, radius + 1):
		for r: int in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			var coord: Vector2i = anchor + Vector2i(q, r)
			if tiles.has(coord) and Terrain.is_passable(tiles[coord].terrain):
				candidates.append(coord)
	if candidates.is_empty():
		return anchor
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## Same edge-traversal loop as the Leader, minus stamina/party/fog.
func _advance_enemy_path(enemy: EnemyData, dt: float) -> void:
	var remaining: float = dt
	while remaining > 0.0 and enemy.is_moving():
		var next: Vector2i = enemy.path[0]
		if not can_traverse(enemy.coord, next):
			enemy.path.clear()
			enemy.edge_progress = 0.0
			break   # bridge closed / terrain reverted; AI re-decides next frame
		var t: float = _traversal_time(enemy.coord, next, enemy.speed_mult)
		var time_to_finish: float = (1.0 - enemy.edge_progress) * t
		if remaining >= time_to_finish:
			remaining -= time_to_finish
			enemy.coord = next
			enemy.path.pop_front()
			enemy.edge_progress = 0.0
		else:
			enemy.edge_progress += remaining / t
			remaining = 0.0


# --- Combat (automatic, proximity-based, continuous) -----------------------

## Every adjacent party member (units and Leader) attacks each enemy; the
## enemy strikes back at the first adjacent target, units before Leader
## (units tank). Attack power reads terrain through effective_type — a
## BOOST tile under an attacker multiplies their damage. No caching.
func _advance_combat(dt: float) -> void:
	if leader == null:
		return
	for enemy: EnemyData in enemies.values():
		var attack_power: float = 0.0
		var target: Variant = null   # UnitData or LeaderData
		for id: int in party:
			var unit: UnitData = units[id]
			if HexUtils.axial_distance(unit.coord, enemy.coord) <= 1:
				attack_power += unit_power * _attack_mult(unit.coord)
				if target == null:
					target = unit
		if leader.hp > 0.0 and HexUtils.axial_distance(leader.coord, enemy.coord) <= 1:
			attack_power += leader_power * _attack_mult(leader.coord)
			if target == null:
				target = leader
		if target == null:
			continue   # nobody engaged this enemy
		enemy.hp -= attack_power * dt
		target.hp -= enemy.power * dt
	_resolve_deaths()


func _attack_mult(coord: Vector2i) -> float:
	return boost_attack_mult if effective_type(coord) == Terrain.Type.BOOST else 1.0


func _resolve_deaths() -> void:
	var dead_enemies: Array[int] = []
	for id: int in enemies:
		if enemies[id].hp <= 0.0:
			dead_enemies.append(id)
	for id: int in dead_enemies:
		enemies.erase(id)
		enemy_died.emit(id)

	var dead_units: Array[int] = []
	for id: int in party:
		if units[id].hp <= 0.0:
			dead_units.append(id)
	for id: int in dead_units:
		party.erase(id)
		units.erase(id)
		unit_died.emit(id)

	if leader.hp <= 0.0 and not _leader_death_emitted:
		_leader_death_emitted = true
		leader.hp = 0.0
		leader.path.clear()
		leader.edge_progress = 0.0
		leader_path_changed.emit()
		leader_died.emit()


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
