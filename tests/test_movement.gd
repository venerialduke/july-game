extends TestBase
## Headless deterministic tests for Leader movement: pathfinding through
## transient state, real-time traversal, stamina, and mid-walk blocking.
## Run:  Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/test_movement.gd


func run_tests() -> void:
	test_walk_timing_and_moved_signals()
	test_forest_doubles_traversal_time()
	test_path_avoids_water()
	test_unreachable_target_rejected()
	test_connector_bridge_crossing()
	test_bridge_closes_mid_walk()
	test_transmute_opens_mountain()
	test_fast_move_drains_stamina()
	test_zero_stamina_reverts_to_slow()
	test_stamina_regen_only_when_stopped()
	test_mid_walk_retarget_keeps_current_edge()


func test_walk_timing_and_moved_signals() -> void:
	begin("slow walk: 1.5s per plains tile, leader_moved once per tile")
	var sim: Node = make_disc_sim(3)
	sim.spawn_leader(Vector2i.ZERO)

	var moves: Array = []
	sim.leader_moved.connect(func(from: Vector2i, to: Vector2i) -> void:
		moves.append([from, to]))

	check(sim.request_move(Vector2i(3, 0)), "path to (3,0) found")
	check_eq(sim.leader.path.size(), 3, "path enters 3 tiles")
	sim.advance(1.5)
	check_eq(sim.leader.coord, Vector2i(1, 0), "one tile after 1.5s")
	sim.advance(0.75)
	check_approx(sim.leader.edge_progress, 0.5, "mid-edge halfway at +0.75s")
	sim.advance(2.25)
	check_eq(sim.leader.coord, Vector2i(3, 0), "arrived after 4.5s total")
	check(not sim.leader.is_moving(), "path consumed on arrival")
	check_eq(moves.size(), 3, "leader_moved fired exactly once per tile")
	sim.free()


func test_forest_doubles_traversal_time() -> void:
	begin("forest tile takes 2x plains time to enter")
	var sim: Node = make_disc_sim(2)
	sim.tiles[Vector2i(1, 0)].terrain = Terrain.Type.FOREST
	sim.spawn_leader(Vector2i.ZERO)
	sim.request_move(Vector2i(1, 0))
	sim.advance(2.9)
	check_eq(sim.leader.coord, Vector2i.ZERO, "not yet arrived at 2.9s")
	sim.advance(0.2)
	check_eq(sim.leader.coord, Vector2i(1, 0), "arrived after 3.0s (cost 2)")
	sim.free()


func test_path_avoids_water() -> void:
	begin("pathfinding routes around impassable water")
	var sim: Node = make_disc_sim(3)
	for coord: Vector2i in [Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1)]:
		sim.tiles[coord].terrain = Terrain.Type.WATER
	sim.spawn_leader(Vector2i.ZERO)

	check(sim.request_move(Vector2i(2, 0)), "target reachable around the wall")
	check(sim.leader.path.size() > 2, "detour is longer than the direct 2-tile line")
	for coord: Vector2i in sim.leader.path:
		check(sim.tiles[coord].terrain != Terrain.Type.WATER,
				"path never enters water (%s)" % coord)
	sim.advance(60.0)
	check_eq(sim.leader.coord, Vector2i(2, 0), "walks the detour to arrival")
	sim.free()


func test_unreachable_target_rejected() -> void:
	begin("request_move returns false for an unreachable target")
	var sim: Node = make_disc_sim(2)
	sim.tiles[Vector2i(1, 0)].terrain = Terrain.Type.WATER
	sim.spawn_leader(Vector2i.ZERO)
	check(not sim.request_move(Vector2i(1, 0)), "water tile with no bridge rejected")
	check(not sim.request_move(Vector2i(9, 9)), "off-map tile rejected")
	check(not sim.leader.is_moving(), "no path was set")
	sim.free()


func test_connector_bridge_crossing() -> void:
	begin("open connector bridges onto water at cost 1")
	var sim: Node = make_disc_sim(2)
	sim.tiles[Vector2i(1, 0)].terrain = Terrain.Type.WATER
	var bridge := LinkerData.new(Vector2i.ZERO, LinkerData.Type.CONNECTOR, 1, 0)
	bridge.frozen = true   # orientation 0 -> beam holds on (1, 0)
	sim.add_linker(bridge)
	sim.initialize_open_set()
	sim.spawn_leader(Vector2i.ZERO)

	check(sim.request_move(Vector2i(1, 0)), "water reachable across open bridge")
	sim.advance(1.5)
	check_eq(sim.leader.coord, Vector2i(1, 0), "crossed in 1.5s: bridge cost is 1")
	sim.free()


func test_bridge_closes_mid_walk() -> void:
	begin("bridge closing mid-walk blocks the leader and clears the path")
	var sim: Node = make_disc_sim(2)
	sim.tiles[Vector2i(1, 0)].terrain = Terrain.Type.WATER
	var bridge := LinkerData.new(Vector2i.ZERO, LinkerData.Type.CONNECTOR, 1, 0)
	sim.add_linker(bridge)   # not frozen: swings away on the next tick
	sim.initialize_open_set()
	sim.spawn_leader(Vector2i.ZERO)

	var blocked_at: Array = []
	sim.leader_blocked.connect(func(at: Vector2i) -> void: blocked_at.append(at))

	sim.request_move(Vector2i(1, 0))
	sim.advance(0.75)
	check_approx(sim.leader.edge_progress, 0.5, "halfway across the bridge")
	sim.step_ticks(1)   # beam swings off (1, 0); the bridge vanishes
	sim.advance(0.1)
	check_eq(blocked_at, [Vector2i(1, 0)], "leader_blocked fired for the lost edge")
	check_eq(sim.leader.coord, Vector2i.ZERO, "leader falls back to the host side")
	check(not sim.leader.is_moving(), "path cleared on block")
	sim.free()


func test_transmute_opens_mountain() -> void:
	begin("transmute override makes a mountain temporarily passable")
	var sim: Node = make_disc_sim(2)
	sim.tiles[Vector2i(1, 0)].terrain = Terrain.Type.MOUNTAIN
	sim.spawn_leader(Vector2i(-1, 0))
	check(not sim.request_move(Vector2i(1, 0)), "mountain impassable without beam")

	var beam := LinkerData.new(Vector2i.ZERO, LinkerData.Type.TRANSMUTE, 1, 0)
	beam.frozen = true   # holds BOOST on (1, 0)
	sim.add_linker(beam)
	sim.initialize_open_set()
	check(sim.request_move(Vector2i(1, 0)), "mountain enterable while transmuted")
	sim.advance(3.0)   # two tiles at BOOST/plains cost
	check_eq(sim.leader.coord, Vector2i(1, 0), "leader stands on the transmuted mountain")
	sim.free()


func test_fast_move_drains_stamina() -> void:
	begin("fast move halves time and drains stamina; slow move is free")
	var sim: Node = make_disc_sim(3)
	sim.spawn_leader(Vector2i.ZERO)
	sim.set_fast(true)
	sim.request_move(Vector2i(2, 0))
	sim.advance(1.5)
	check_eq(sim.leader.coord, Vector2i(2, 0), "two plains tiles in 1.5s at 2x speed")
	check_approx(sim.leader.stamina, 70.0, "drained 20/s for 1.5s of sprinting")
	sim.set_fast(false)
	sim.request_move(Vector2i.ZERO)
	var stamina_before: float = sim.leader.stamina
	sim.advance(3.0)
	check_eq(sim.leader.coord, Vector2i.ZERO, "walked back slow in 3.0s")
	check(sim.leader.stamina >= stamina_before, "slow move never drains stamina")
	sim.free()


func test_zero_stamina_reverts_to_slow() -> void:
	begin("fast mode with zero stamina moves at slow speed")
	var sim: Node = make_disc_sim(2)
	sim.spawn_leader(Vector2i.ZERO)
	sim.leader.stamina = 0.0
	sim.set_fast(true)
	sim.request_move(Vector2i(1, 0))
	sim.advance(1.4)
	check_eq(sim.leader.coord, Vector2i.ZERO, "not arrived at 1.4s (slow speed applies)")
	sim.advance(0.2)
	check_eq(sim.leader.coord, Vector2i(1, 0), "arrived on the slow schedule")
	sim.free()


func test_stamina_regen_only_when_stopped() -> void:
	begin("stamina regens at 8/s only while the leader is stopped")
	var sim: Node = make_disc_sim(3)
	sim.spawn_leader(Vector2i.ZERO)
	sim.leader.stamina = 40.0
	sim.advance(2.0)   # standing still: regen
	check_approx(sim.leader.stamina, 56.0, "regens 8/s while stopped")
	sim.request_move(Vector2i(2, 0))
	sim.advance(1.5)   # walking slow: no drain, but no regen either
	check_approx(sim.leader.stamina, 56.0, "no regen while moving, even slow")
	sim.advance(1.0)   # still mid-second-edge at t=2.5
	check_approx(sim.leader.stamina, 56.0, "no regen while mid-edge")
	sim.advance(1.0)   # arrives at 3.0s total; regen covers the 0.5s idle tail
	check_approx(sim.leader.stamina, 60.0, "regen resumes the instant movement stops")
	sim.advance(60.0)
	check_approx(sim.leader.stamina, sim.stamina_max, "regen clamps at max")
	sim.free()


func test_mid_walk_retarget_keeps_current_edge() -> void:
	begin("retargeting mid-edge finishes the current edge first")
	var sim: Node = make_disc_sim(3)
	sim.spawn_leader(Vector2i.ZERO)
	sim.request_move(Vector2i(2, 0))
	sim.advance(0.5)
	check_approx(sim.leader.edge_progress, 1.0 / 3.0, "one third across the first edge")
	check(sim.request_move(Vector2i(0, 1)), "retarget accepted mid-edge")
	check_eq(sim.leader.path[0], Vector2i(1, 0), "current edge kept as path head")
	check_approx(sim.leader.edge_progress, 1.0 / 3.0, "edge progress preserved")
	sim.advance(60.0)
	check_eq(sim.leader.coord, Vector2i(0, 1), "arrives at the new target")
	sim.free()
