class_name MapGen
## Seeded procedural map generation. Same seed + same knobs => identical
## map (deterministic, headless-tested). All tuning lives in KNOBS;
## generate() accepts overrides so tests and design iteration can vary
## single knobs without touching code.

const PLAYER_START := Vector2i.ZERO

const KNOBS: Dictionary[String, int] = {
	"radius": 10,           # hex disc radius (10 -> 331 tiles)
	"safe_radius": 2,       # plains guaranteed around spawn
	"lake_count": 4,
	"lake_size_min": 3,
	"lake_size_max": 7,
	"ridge_count": 3,
	"ridge_len_min": 4,
	"ridge_len_max": 8,
	"forest_count": 8,
	"forest_size_min": 2,
	"forest_size_max": 6,
	"linker_count": 10,
	"linker_spacing": 3,    # min hex distance between linkers
	"linker_period_max": 3,
	"unit_count": 6,
	"unit_min_dist": 2,     # from spawn
	"enemy_count": 5,
	"enemy_min_dist": 5,    # from spawn
}


## Populate a fresh sim with a generated map. Call sim.reset() first and
## sim.initialize_open_set() after (same contract LevelData had).
static func generate(sim: Node, seed_value: int, overrides: Dictionary = {}) -> void:
	var knobs: Dictionary = KNOBS.duplicate()
	knobs.merge(overrides, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	_place_disc(sim, knobs["radius"])
	for i: int in range(knobs["lake_count"]):
		_grow_blob(sim, rng, knobs, Terrain.Type.WATER,
				rng.randi_range(knobs["lake_size_min"], knobs["lake_size_max"]))
	for i: int in range(knobs["ridge_count"]):
		_carve_ridge(sim, rng, knobs)
	for i: int in range(knobs["forest_count"]):
		_grow_blob(sim, rng, knobs, Terrain.Type.FOREST,
				rng.randi_range(knobs["forest_size_min"], knobs["forest_size_max"]))
	_clear_safe_zone(sim, knobs["safe_radius"])

	# Everything interactive goes on tiles reachable from spawn, so no
	# linker/unit/enemy is stranded behind an unbroken wall or lake.
	var reachable: Array[Vector2i] = _reachable_from(sim, PLAYER_START)
	_place_linkers(sim, rng, knobs, reachable)
	_place_units(sim, rng, knobs, reachable)
	_place_enemies(sim, rng, knobs, reachable)


static func _place_disc(sim: Node, radius: int) -> void:
	for q: int in range(-radius, radius + 1):
		for r: int in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			sim.add_tile(Vector2i(q, r), Terrain.Type.PLAINS)


## Grow a connected blob of `terrain` by random-walking from a seed tile.
static func _grow_blob(sim: Node, rng: RandomNumberGenerator, knobs: Dictionary,
		terrain: Terrain.Type, size: int) -> void:
	var center: Vector2i = _random_far_tile(sim, rng, knobs["safe_radius"] + 2)
	var current: Vector2i = center
	for i: int in range(size):
		if sim.tiles.has(current):
			sim.tiles[current].terrain = terrain
		var step: Vector2i = HexUtils.DIRECTIONS[rng.randi_range(0, 5)]
		var next: Vector2i = current + step
		current = next if sim.tiles.has(next) else center


## Carve a mountain ridge: a mostly-straight walk with occasional kinks.
static func _carve_ridge(sim: Node, rng: RandomNumberGenerator, knobs: Dictionary) -> void:
	var current: Vector2i = _random_far_tile(sim, rng, knobs["safe_radius"] + 2)
	var dir_index: int = rng.randi_range(0, 5)
	var length: int = rng.randi_range(knobs["ridge_len_min"], knobs["ridge_len_max"])
	for i: int in range(length):
		if sim.tiles.has(current):
			sim.tiles[current].terrain = Terrain.Type.MOUNTAIN
		if rng.randf() < 0.3:
			dir_index = posmod(dir_index + (1 if rng.randf() < 0.5 else -1), 6)
		current += HexUtils.DIRECTIONS[dir_index]


static func _clear_safe_zone(sim: Node, safe_radius: int) -> void:
	for coord: Vector2i in sim.tiles:
		if HexUtils.axial_distance(coord, PLAYER_START) <= safe_radius:
			sim.tiles[coord].terrain = Terrain.Type.PLAINS


static func _place_linkers(sim: Node, rng: RandomNumberGenerator, knobs: Dictionary,
		reachable: Array[Vector2i]) -> void:
	var candidates: Array[Vector2i] = _shuffled(reachable, rng)
	var placed: Array[Vector2i] = []
	for coord: Vector2i in candidates:
		if placed.size() >= knobs["linker_count"]:
			break
		if HexUtils.axial_distance(coord, PLAYER_START) < 1:
			continue
		var too_close: bool = false
		for other: Vector2i in placed:
			if HexUtils.axial_distance(coord, other) < knobs["linker_spacing"]:
				too_close = true
				break
		if too_close:
			continue
		var type := LinkerData.Type.CONNECTOR if rng.randf() < 0.5 \
				else LinkerData.Type.TRANSMUTE
		var period: int = rng.randi_range(1, knobs["linker_period_max"])
		var linker := LinkerData.new(coord, type, period,
				rng.randi_range(0, period - 1), rng.randi_range(0, 5))
		linker.spin_dir = 1 if rng.randf() < 0.5 else -1
		sim.add_linker(linker)
		placed.append(coord)


static func _place_units(sim: Node, rng: RandomNumberGenerator, knobs: Dictionary,
		reachable: Array[Vector2i]) -> void:
	var spots: Array[Vector2i] = _pick_spots(sim, rng, reachable,
			knobs["unit_count"], knobs["unit_min_dist"])
	for coord: Vector2i in spots:
		sim.add_unit(coord)


static func _place_enemies(sim: Node, rng: RandomNumberGenerator, knobs: Dictionary,
		reachable: Array[Vector2i]) -> void:
	var spots: Array[Vector2i] = _pick_spots(sim, rng, reachable,
			knobs["enemy_count"], knobs["enemy_min_dist"])
	for coord: Vector2i in spots:
		sim.add_enemy(coord)


## Pick `count` distinct reachable tiles at least `min_dist` from spawn,
## avoiding linker host tiles so nothing spawns visually stacked.
static func _pick_spots(sim: Node, rng: RandomNumberGenerator,
		reachable: Array[Vector2i], count: int, min_dist: int) -> Array[Vector2i]:
	var hosts: Dictionary[Vector2i, bool] = {}
	for linker: LinkerData in sim.linkers.values():
		hosts[linker.host_coord] = true
	var spots: Array[Vector2i] = []
	for coord: Vector2i in _shuffled(reachable, rng):
		if spots.size() >= count:
			break
		if HexUtils.axial_distance(coord, PLAYER_START) < min_dist:
			continue
		if hosts.has(coord) or spots.has(coord):
			continue
		spots.append(coord)
	return spots


## BFS over passable base terrain from `start`. Beams are transient, so
## generation only trusts the static map.
static func _reachable_from(sim: Node, start: Vector2i) -> Array[Vector2i]:
	var visited: Dictionary[Vector2i, bool] = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for next: Vector2i in HexUtils.get_neighbors(current):
			if visited.has(next) or not sim.tiles.has(next):
				continue
			if not Terrain.is_passable(sim.tiles[next].terrain):
				continue
			visited[next] = true
			frontier.append(next)
	var result: Array[Vector2i] = []
	for coord: Vector2i in visited:
		result.append(coord)
	return result


## A random tile at least `min_dist` from spawn (feature seeds).
static func _random_far_tile(sim: Node, rng: RandomNumberGenerator,
		min_dist: int) -> Vector2i:
	var coords: Array[Vector2i] = []
	for coord: Vector2i in sim.tiles:
		if HexUtils.axial_distance(coord, PLAYER_START) >= min_dist:
			coords.append(coord)
	return coords[rng.randi_range(0, coords.size() - 1)]


## Deterministic Fisher-Yates using the seeded rng (Array.shuffle() would
## use the global RNG and break same-seed reproducibility).
static func _shuffled(source: Array[Vector2i], rng: RandomNumberGenerator) -> Array[Vector2i]:
	var result: Array[Vector2i] = source.duplicate()
	for i: int in range(result.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result
