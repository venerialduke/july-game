extends TestBase
## Headless deterministic tests for procedural generation and fog of war.
## Run:  Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/test_worldgen.gd


func run_tests() -> void:
	test_generation_is_deterministic()
	test_different_seeds_differ()
	test_map_structure()
	test_placement_constraints()
	test_generated_map_survives_simulation()
	test_fog_reveals_around_spawn()
	test_fog_blocks_moves_into_the_unknown()
	test_fog_reveals_as_leader_explores()
	test_fog_disabled_bypasses_gating()


func _terrain_snapshot(sim: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	for coord: Vector2i in sim.tiles:
		snapshot[coord] = sim.tiles[coord].terrain
	return snapshot


func _linker_snapshot(sim: Node) -> Array:
	var snapshot: Array = []
	for id: int in sim.linkers:
		var linker: LinkerData = sim.linkers[id]
		snapshot.append([linker.host_coord, linker.type, linker.period,
				linker.phase_offset, linker.orientation, linker.spin_dir])
	return snapshot


func test_generation_is_deterministic() -> void:
	begin("same seed generates an identical map")
	var a: Node = make_sim()
	var b: Node = make_sim()
	MapGen.generate(a, 42)
	MapGen.generate(b, 42)
	check_eq(_terrain_snapshot(a), _terrain_snapshot(b), "terrain identical")
	check_eq(_linker_snapshot(a), _linker_snapshot(b), "linkers identical")
	check_eq(_coords_of(a.units), _coords_of(b.units), "unit spots identical")
	check_eq(_coords_of(a.enemies), _coords_of(b.enemies), "enemy spots identical")
	a.free()
	b.free()


func _coords_of(dict: Dictionary) -> Array:
	var coords: Array = []
	for id: int in dict:
		coords.append(dict[id].coord)
	return coords


func test_different_seeds_differ() -> void:
	begin("different seeds generate different maps")
	var a: Node = make_sim()
	var b: Node = make_sim()
	MapGen.generate(a, 42)
	MapGen.generate(b, 43)
	check(_terrain_snapshot(a) != _terrain_snapshot(b)
			or _linker_snapshot(a) != _linker_snapshot(b),
			"seed 42 and 43 maps are not identical")
	a.free()
	b.free()


func test_map_structure() -> void:
	begin("generated map has the right shape and safe spawn")
	var sim: Node = make_sim()
	MapGen.generate(sim, 7)
	var radius: int = MapGen.KNOBS["radius"]
	check_eq(sim.tiles.size(), 1 + 3 * radius * (radius + 1),
			"full hex disc tile count")
	check_eq(sim.linkers.size(), MapGen.KNOBS["linker_count"], "all linkers placed")
	check_eq(sim.units.size(), MapGen.KNOBS["unit_count"], "all units placed")
	check_eq(sim.enemies.size(), MapGen.KNOBS["enemy_count"], "all enemies placed")
	for coord: Vector2i in sim.tiles:
		if HexUtils.axial_distance(coord, MapGen.PLAYER_START) <= MapGen.KNOBS["safe_radius"]:
			check_eq(sim.tiles[coord].terrain, Terrain.Type.PLAINS,
					"safe zone tile %s is plains" % coord)
	sim.free()


func test_placement_constraints() -> void:
	begin("placement respects spacing and distance constraints")
	var sim: Node = make_sim()
	MapGen.generate(sim, 99)
	var hosts: Array = []
	for linker: LinkerData in sim.linkers.values():
		check(Terrain.is_passable(sim.tiles[linker.host_coord].terrain),
				"linker host %s passable" % linker.host_coord)
		hosts.append(linker.host_coord)
	for i: int in range(hosts.size()):
		for j: int in range(i + 1, hosts.size()):
			check(HexUtils.axial_distance(hosts[i], hosts[j]) >= MapGen.KNOBS["linker_spacing"],
					"linkers %s and %s spaced" % [hosts[i], hosts[j]])
	for enemy: EnemyData in sim.enemies.values():
		check(HexUtils.axial_distance(enemy.coord, MapGen.PLAYER_START)
				>= MapGen.KNOBS["enemy_min_dist"],
				"enemy at %s far from spawn" % enemy.coord)
		check(Terrain.is_passable(sim.tiles[enemy.coord].terrain),
				"enemy at %s on passable ground" % enemy.coord)
	for unit: UnitData in sim.units.values():
		check(Terrain.is_passable(sim.tiles[unit.coord].terrain),
				"unit at %s on passable ground" % unit.coord)
	sim.free()


func test_generated_map_survives_simulation() -> void:
	begin("generated map runs 60 ticks + movement without errors")
	var sim: Node = make_sim()
	MapGen.generate(sim, 5)
	sim.initialize_open_set()
	sim.spawn_leader(MapGen.PLAYER_START)
	sim.step_ticks(60)
	check_eq(sim.tick_count, 60, "sim survives 60 ticks")
	check(sim.request_move(Vector2i(1, 0)), "leader can move on generated map")
	sim.advance(10.0)
	check(not sim.leader.is_moving(), "movement completes")
	sim.free()


func test_fog_reveals_around_spawn() -> void:
	begin("spawning reveals a sight-radius disc")
	var sim: Node = make_disc_sim(6)
	var revealed_batches: Array = []
	sim.tiles_revealed.connect(func(coords: Array) -> void:
		revealed_batches.append(coords.size()))
	sim.spawn_leader(Vector2i.ZERO)
	check_eq(sim.revealed.size(), 37, "radius-3 disc = 37 tiles revealed")
	check_eq(revealed_batches, [37], "tiles_revealed fired once with the batch")
	check(sim.is_revealed(Vector2i(3, 0)), "sight edge revealed")
	check(not sim.is_revealed(Vector2i(4, 0)), "beyond sight still fogged")
	sim.free()


func test_fog_blocks_moves_into_the_unknown() -> void:
	begin("move orders cannot target fogged tiles")
	var sim: Node = make_disc_sim(6)
	sim.spawn_leader(Vector2i.ZERO)
	check(not sim.request_move(Vector2i(5, 0)), "fogged target rejected")
	check(sim.request_move(Vector2i(3, 0)), "revealed target accepted")
	sim.free()


func test_fog_reveals_as_leader_explores() -> void:
	begin("walking pushes back the fog, then the far target is orderable")
	var sim: Node = make_disc_sim(6)
	sim.spawn_leader(Vector2i.ZERO)
	sim.request_move(Vector2i(3, 0))
	sim.advance(4.5)   # arrive at (3,0); sight now covers (6,0)
	check(sim.is_revealed(Vector2i(6, 0)), "new ground revealed en route")
	check(sim.request_move(Vector2i(5, 0)), "previously fogged tile now orderable")
	var total: int = sim.revealed.size()
	sim.advance(3.0)
	check(sim.revealed.size() >= total, "reveal is permanent (never shrinks)")
	sim.free()


func test_fog_disabled_bypasses_gating() -> void:
	begin("fog_enabled=false exposes everything")
	var sim: Node = make_disc_sim(6)
	sim.fog_enabled = false
	sim.spawn_leader(Vector2i.ZERO)
	check(sim.is_revealed(Vector2i(6, 0)), "everything visible with fog off")
	check(sim.request_move(Vector2i(6, 0)), "any tile orderable with fog off")
	sim.free()
