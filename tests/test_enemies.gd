extends TestBase
## Headless deterministic tests for the enemy AI framework: archetypes,
## wander, aggro/chase/leash, continuous movement, combat integration.
## Run:  Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/test_enemies.gd


func run_tests() -> void:
	test_legacy_dummy_stays_put()
	test_archetype_stats_applied()
	test_drifter_wanders_but_never_aggros()
	test_hunter_acquires_and_closes_in()
	test_hunter_gives_up_beyond_leash()
	test_brute_leashes_to_home()
	test_chase_stops_at_adjacency_and_fights()
	test_enemy_movement_is_deterministic()
	test_enemy_respects_terrain()


func test_legacy_dummy_stays_put() -> void:
	begin("archetype-less enemy never moves (v0 behavior preserved)")
	var sim: Node = make_disc_sim(4)
	sim.spawn_leader(Vector2i.ZERO)
	var id: int = sim.add_enemy(Vector2i(3, 0))
	sim.advance(20.0)
	check_eq(sim.enemies[id].coord, Vector2i(3, 0), "dummy still on its spawn tile")
	sim.free()


func test_archetype_stats_applied() -> void:
	begin("archetype stats come from the EnemyTypes table")
	var sim: Node = make_disc_sim(3)
	var id: int = sim.add_enemy(Vector2i(2, 0), &"hunter")
	var enemy: EnemyData = sim.enemies[id]
	var stats: Dictionary = EnemyTypes.stats(&"hunter")
	check_eq(enemy.hp, stats["hp"], "hp from table")
	check_eq(enemy.power, stats["power"], "power from table")
	check_eq(enemy.aggro_radius, stats["aggro_radius"], "aggro radius from table")
	check_eq(enemy.home, Vector2i(2, 0), "home anchored at spawn")
	sim.free()


func test_drifter_wanders_but_never_aggros() -> void:
	begin("drifter wanders on the seeded RNG and never enters CHASE")
	var sim: Node = make_disc_sim(4)
	sim.rng.seed = 7
	var id: int = sim.add_enemy(Vector2i.ZERO, &"drifter")   # no leader: pure wander

	var aggros: Array = []
	sim.enemy_aggroed.connect(func(eid: int) -> void: aggros.append(eid))

	var start: Vector2i = sim.enemies[id].coord
	var moved: bool = false
	for i: int in range(40):   # 40s of sim in 1s steps
		sim.advance(1.0)
		if sim.enemies[id].coord != start:
			moved = true
	check(moved, "drifter eventually wandered off its spawn tile")
	check(aggros.is_empty(), "aggro_radius 0 means no aggro, ever")
	check_eq(sim.enemies[id].state, EnemyData.AIState.WANDER, "still wandering")
	sim.free()


func test_hunter_acquires_and_closes_in() -> void:
	begin("hunter aggros within radius, signals once, and closes distance")
	var sim: Node = make_disc_sim(6)
	sim.rng.seed = 7
	sim.spawn_leader(Vector2i.ZERO)
	var id: int = sim.add_enemy(Vector2i(4, 0), &"hunter")   # inside aggro 5

	var aggros: Array = []
	sim.enemy_aggroed.connect(func(eid: int) -> void: aggros.append(eid))

	sim.advance(0.1)
	check_eq(aggros, [id], "aggro signal fired once on acquisition")
	check_eq(sim.enemies[id].state, EnemyData.AIState.CHASE, "state is CHASE")
	var start_dist: int = HexUtils.axial_distance(sim.enemies[id].coord, Vector2i.ZERO)
	advance_time(sim, 4.0)
	var now_dist: int = HexUtils.axial_distance(sim.enemies[id].coord, Vector2i.ZERO)
	check(now_dist < start_dist, "hunter closed distance (%d -> %d)" % [start_dist, now_dist])
	advance_time(sim, 2.0)   # short: long enough to park, not enough to kill anyone
	check_eq(aggros, [id], "no repeat aggro signal while chase continues")
	check_eq(HexUtils.axial_distance(sim.enemies[id].coord, Vector2i.ZERO), 1,
			"hunter parks adjacent to fight")
	sim.free()


func test_hunter_gives_up_beyond_leash() -> void:
	begin("hunter abandons the chase when the leader escapes the leash")
	var sim: Node = make_disc_sim(12)
	sim.rng.seed = 7
	sim.fog_enabled = false
	sim.spawn_leader(Vector2i.ZERO)
	var id: int = sim.add_enemy(Vector2i(4, 0), &"hunter")
	sim.advance(0.1)
	check_eq(sim.enemies[id].state, EnemyData.AIState.CHASE, "chasing")
	# Teleport the leader far beyond leash_range (9).
	sim.leader.coord = Vector2i(-8, 0)
	sim.leader.path.clear()
	sim.advance(0.1)
	check_eq(sim.enemies[id].state, EnemyData.AIState.WANDER, "gave up, wandering")
	sim.free()


func test_brute_leashes_to_home() -> void:
	begin("brute chases inside its territory, then walks back home")
	var sim: Node = make_disc_sim(12)
	sim.rng.seed = 7
	sim.fog_enabled = false
	sim.spawn_leader(Vector2i(3, 0))   # within brute aggro (2) of (2,0)? dist=1
	var id: int = sim.add_enemy(Vector2i(2, 0), &"brute")
	var enemy: EnemyData = sim.enemies[id]
	sim.advance(0.1)
	check_eq(enemy.state, EnemyData.AIState.CHASE, "brute aggroed at distance 1")
	# Drag the fight far from home: teleport leader; brute chases until its
	# distance from HOME exceeds leash 4.
	sim.leader.coord = Vector2i(9, 0)
	sim.leader.path.clear()
	# Brute must abandon: leader now 7 from brute, > leash-from-home logic
	# kicks in as soon as it strays; force a few decision frames.
	sim.advance(0.2)
	check(enemy.state != EnemyData.AIState.CHASE or
			HexUtils.axial_distance(enemy.coord, enemy.home) <= enemy.leash_range,
			"brute never chases beyond its leash from home")
	advance_time(sim, 30.0)
	check(HexUtils.axial_distance(enemy.coord, enemy.home) <= enemy.leash_range,
			"brute ends up back inside its territory")
	sim.free()


func test_chase_stops_at_adjacency_and_fights() -> void:
	begin("a chasing hunter parks at adjacency and combat engages")
	var sim: Node = make_disc_sim(6)
	sim.rng.seed = 7
	sim.spawn_leader(Vector2i.ZERO)
	var id: int = sim.add_enemy(Vector2i(3, 0), &"hunter")
	advance_time(sim, 6.0)   # closes from distance 3 (~2.6s) + a bit of combat
	check_eq(HexUtils.axial_distance(sim.enemies[id].coord, Vector2i.ZERO), 1,
			"hunter adjacent, not stacked on the leader")
	check(sim.leader.hp < sim.leader_max_hp, "leader is taking damage")
	check(sim.enemies[id].hp < sim.enemies[id].max_hp, "hunter is taking damage back")
	sim.free()


func test_enemy_movement_is_deterministic() -> void:
	begin("same seed + same dt sequence = identical enemy positions")
	var runs: Array = []
	for run: int in range(2):
		var sim: Node = make_disc_sim(6)
		sim.rng.seed = 1234
		sim.spawn_leader(Vector2i.ZERO)
		sim.add_enemy(Vector2i(4, 0), &"drifter")
		sim.add_enemy(Vector2i(0, 4), &"hunter")
		sim.add_enemy(Vector2i(-4, 0), &"brute")
		var trace: Array = []
		for i: int in range(30):
			sim.advance(0.7)
			for eid: int in sim.enemies:
				trace.append(sim.enemies[eid].coord)
		runs.append(trace)
		sim.free()
	check_eq(runs[0], runs[1], "both runs produced identical movement traces")


func test_enemy_respects_terrain() -> void:
	begin("enemies cannot cross impassable terrain without a bridge")
	var sim: Node = make_disc_sim(4)
	sim.rng.seed = 7
	# Water moat fully separating east from west at q=1.
	for coord: Vector2i in sim.tiles.keys():
		if coord.x == 1:
			sim.tiles[coord].terrain = Terrain.Type.WATER
	sim.spawn_leader(Vector2i.ZERO)
	var id: int = sim.add_enemy(Vector2i(3, 0), &"hunter")   # across the moat
	sim.advance(20.0)
	check(sim.enemies[id].coord.x > 1, "hunter stuck on its side of the moat")
	check_approx(sim.leader.hp, sim.leader_max_hp, "leader untouched behind the moat")
	sim.free()
