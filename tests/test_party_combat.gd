extends TestBase
## Headless deterministic tests for Units (collect + trail-follow) and
## proximity auto-combat.
## Run:  Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/test_party_combat.gd


func run_tests() -> void:
	test_collect_on_walkover()
	test_party_trails_leader()
	test_combat_kills_adjacent_enemy()
	test_no_combat_at_distance()
	test_units_tank_before_leader()
	test_boost_tile_attack_bonus()
	test_leader_death()


func test_collect_on_walkover() -> void:
	begin("walking onto a neutral unit collects it; others stay neutral")
	var sim: Node = make_disc_sim(3)
	sim.spawn_leader(Vector2i.ZERO)
	var near_id: int = sim.add_unit(Vector2i(1, 0))
	var far_id: int = sim.add_unit(Vector2i(0, -2))

	var collected: Array = []
	sim.unit_collected.connect(func(id: int) -> void: collected.append(id))

	sim.request_move(Vector2i(1, 0))
	sim.advance(1.5)
	check_eq(collected, [near_id], "exactly the walked-over unit collected")
	check(sim.units[near_id].collected, "unit flagged collected")
	check_eq(sim.party, [near_id], "unit joined the party")
	check(not sim.units[far_id].collected, "distant unit untouched")
	sim.free()


func test_party_trails_leader() -> void:
	begin("party follows the leader's trail in collection order")
	var sim: Node = make_disc_sim(3)
	sim.spawn_leader(Vector2i.ZERO)
	var first: int = sim.add_unit(Vector2i(1, 0))
	var second: int = sim.add_unit(Vector2i(2, 0))

	sim.request_move(Vector2i(3, 0))
	sim.advance(4.5)   # collects both en route
	check_eq(sim.leader.coord, Vector2i(3, 0), "leader arrived")
	check_eq(sim.party, [first, second], "party in collection order")
	check_eq(sim.units[first].coord, Vector2i(2, 0), "first unit right behind leader")
	check_eq(sim.units[second].coord, Vector2i(1, 0), "second unit behind the first")
	sim.free()


func test_combat_kills_adjacent_enemy() -> void:
	begin("adjacent leader and enemy exchange damage until the enemy dies")
	var sim: Node = make_disc_sim(2)
	sim.spawn_leader(Vector2i.ZERO)
	var enemy_id: int = sim.add_enemy(Vector2i(1, 0))

	var deaths: Array = []
	sim.enemy_died.connect(func(id: int) -> void: deaths.append(id))

	for i: int in range(4):
		sim.advance(1.0)
	check_approx(sim.enemies[enemy_id].hp, 12.0, "enemy at 60 - 4*12 hp")
	check_approx(sim.leader.hp, 60.0, "leader at 100 - 4*10 hp")
	sim.advance(1.0)   # enemy hits 0 exactly at t=5
	check_eq(deaths, [enemy_id], "enemy_died fired once")
	check(not sim.enemies.has(enemy_id), "dead enemy removed")
	check_approx(sim.leader.hp, 50.0, "leader stopped taking damage at the kill")
	sim.advance(3.0)
	check_approx(sim.leader.hp, 50.0, "no further damage after combat ends")
	sim.free()


func test_no_combat_at_distance() -> void:
	begin("no damage is exchanged beyond adjacency")
	var sim: Node = make_disc_sim(3)
	sim.spawn_leader(Vector2i.ZERO)
	var enemy_id: int = sim.add_enemy(Vector2i(3, 0))
	sim.advance(5.0)
	check_approx(sim.enemies[enemy_id].hp, sim.enemy_max_hp, "distant enemy untouched")
	check_approx(sim.leader.hp, sim.leader_max_hp, "distant leader untouched")
	sim.free()


func test_units_tank_before_leader() -> void:
	begin("an adjacent unit tanks; leader untouched until the unit dies")
	var sim: Node = make_disc_sim(3)
	sim.spawn_leader(Vector2i.ZERO)   # distance 2 from the enemy: out of combat
	var unit_id: int = sim.add_unit(Vector2i(1, 0))
	sim.units[unit_id].collected = true
	sim.party.append(unit_id)
	var enemy_id: int = sim.add_enemy(Vector2i(2, 0))

	var unit_deaths: Array = []
	sim.unit_died.connect(func(id: int) -> void: unit_deaths.append(id))

	for i: int in range(4):
		sim.advance(1.0)   # unit dies at t=4: 40 hp / 10 dps
	check_eq(unit_deaths, [unit_id], "unit died tanking")
	check(sim.party.is_empty(), "dead unit removed from party")
	check_approx(sim.enemies[enemy_id].hp, 28.0, "unit dealt 8/s for 4s before dying")
	check_approx(sim.leader.hp, sim.leader_max_hp, "leader never touched at distance 2")
	sim.advance(3.0)
	check_approx(sim.enemies[enemy_id].hp, 28.0, "combat over once no one is adjacent")
	sim.free()


func test_boost_tile_attack_bonus() -> void:
	begin("attacker on a BOOST tile deals boosted damage, read per-frame")
	var sim: Node = make_disc_sim(2)
	# Frozen transmute covers its host (0,0) and target (1,0) with BOOST.
	var beam := LinkerData.new(Vector2i.ZERO, LinkerData.Type.TRANSMUTE, 1, 0)
	beam.frozen = true
	sim.add_linker(beam)
	sim.initialize_open_set()

	sim.spawn_leader(Vector2i(1, 0))   # standing in the beam
	var enemy_id: int = sim.add_enemy(Vector2i(2, 0))
	sim.advance(2.0)
	check_approx(sim.enemies[enemy_id].hp, 12.0, "2x power: 60 - 2*24 hp")
	sim.advance(0.5)   # dead at exactly 2.5s
	check(not sim.enemies.has(enemy_id), "boosted leader kills in 2.5s")
	check_approx(sim.leader.hp, 75.0, "leader took 10/s for the 2.5s fight")
	sim.free()


func test_leader_death() -> void:
	begin("leader death fires once, halts movement, rejects new orders")
	var sim: Node = make_disc_sim(2)
	sim.spawn_leader(Vector2i.ZERO)
	sim.leader.hp = 10.0
	sim.add_enemy(Vector2i(1, 0))

	var death_count: Array = []
	sim.leader_died.connect(func() -> void: death_count.append(true))

	sim.advance(1.0)   # 10 damage: dead exactly now
	check_eq(death_count.size(), 1, "leader_died fired")
	check_approx(sim.leader.hp, 0.0, "hp clamped at zero")
	check(not sim.request_move(Vector2i(0, 1)), "dead leader rejects move orders")
	sim.advance(2.0)
	check_eq(death_count.size(), 1, "leader_died never fires twice")
	sim.free()
