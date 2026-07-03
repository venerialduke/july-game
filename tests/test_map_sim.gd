extends SceneTree
## Headless deterministic tests for MapSim.
## Run:  Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/test_map_sim.gd
## The sim is instantiated directly (not via autoload) so tests stay hermetic.

const MapSimScript := preload("res://scripts/map_sim.gd")

var _passed: int = 0
var _failed: int = 0
var _current_test: String = ""


func _initialize() -> void:
	test_tick_accumulator()
	test_period_and_phase_stepping()
	test_period_2_and_3_realign_every_6_ticks()
	test_phase_offset_staggers_same_period()
	test_freeze_holds_beam()
	test_reverse_walks_back()
	test_transmute_effective_type_override()
	test_signals_fire_once_per_transition()
	test_connector_edge_open_close()
	test_same_type_stacking_no_false_close()
	test_off_map_beam_safe()
	test_level_data_builds()

	print("")
	if _failed == 0:
		print("ALL TESTS PASSED (%d assertions)" % _passed)
	else:
		print("FAILED: %d failed, %d passed" % [_failed, _passed])
	quit(0 if _failed == 0 else 1)


# --- Helpers ---------------------------------------------------------------

func make_sim() -> Node:
	return MapSimScript.new()


## A sim with a hex disc of PLAINS tiles of the given radius.
func make_disc_sim(radius: int) -> Node:
	var sim: Node = make_sim()
	for q: int in range(-radius, radius + 1):
		for r: int in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			sim.add_tile(Vector2i(q, r))
	return sim


func check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL [%s]: %s" % [_current_test, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func begin(test_name: String) -> void:
	_current_test = test_name
	print("- " + test_name)


# --- Tests -----------------------------------------------------------------

func test_tick_accumulator() -> void:
	begin("tick accumulator converts elapsed time to whole ticks")
	var sim: Node = make_disc_sim(1)
	sim.tick_len = 5.0
	sim.advance(4.9)
	check_eq(sim.tick_count, 0, "no tick before tick_len elapses")
	sim.advance(0.1)
	check_eq(sim.tick_count, 1, "tick fires when accumulator reaches tick_len")
	sim.advance(12.5)
	check_eq(sim.tick_count, 3, "multiple whole ticks fire from one large dt")
	check(absf(sim.accum - 2.5) < 0.0001, "remainder stays in accumulator")
	sim.free()


func test_period_and_phase_stepping() -> void:
	begin("linkers step only on (tick - phase) % period == 0")
	var sim: Node = make_disc_sim(2)
	var fast := LinkerData.new(Vector2i.ZERO, LinkerData.Type.CONNECTOR, 1, 0)
	var slow := LinkerData.new(Vector2i(1, 0), LinkerData.Type.CONNECTOR, 3, 0)
	sim.add_linker(fast)
	sim.add_linker(slow)
	sim.step_ticks(6)
	check_eq(fast.orientation, 0, "period-1 linker made a full revolution in 6 ticks")
	check_eq(slow.orientation, 2, "period-3 linker stepped twice in 6 ticks (ticks 3 and 6)")
	sim.free()


func test_period_2_and_3_realign_every_6_ticks() -> void:
	begin("period-2 and period-3 linkers re-align every 6 ticks")
	var sim: Node = make_disc_sim(2)
	var l2 := LinkerData.new(Vector2i.ZERO, LinkerData.Type.CONNECTOR, 2, 0)
	var l3 := LinkerData.new(Vector2i(1, 0), LinkerData.Type.CONNECTOR, 3, 0)
	sim.add_linker(l2)
	sim.add_linker(l3)

	var steps_this_tick: Dictionary = {}   # tick -> Array of linker ids
	sim.linker_stepped.connect(func(id: int, _o: int) -> void:
		if not steps_this_tick.has(sim.tick_count):
			steps_this_tick[sim.tick_count] = []
		steps_this_tick[sim.tick_count].append(id))

	sim.step_ticks(12)
	check_eq(steps_this_tick.get(6, []).size(), 2, "both linkers snap together on tick 6")
	check_eq(steps_this_tick.get(12, []).size(), 2, "both linkers snap together on tick 12")
	check_eq(l2.orientation, 0, "period-2 back to start after 12 ticks (6 steps)")
	check_eq(l3.orientation, 4, "period-3 at orientation 4 after 12 ticks (4 steps)")
	sim.free()


func test_phase_offset_staggers_same_period() -> void:
	begin("phase_offset staggers two same-period linkers")
	var sim: Node = make_disc_sim(2)
	var a := LinkerData.new(Vector2i.ZERO, LinkerData.Type.CONNECTOR, 3, 0)
	var b := LinkerData.new(Vector2i(1, 0), LinkerData.Type.CONNECTOR, 3, 1)
	var a_id: int = sim.add_linker(a)
	var b_id: int = sim.add_linker(b)

	var step_ticks_by_id: Dictionary = {a_id: [], b_id: []}
	sim.linker_stepped.connect(func(id: int, _o: int) -> void:
		step_ticks_by_id[id].append(sim.tick_count))

	sim.step_ticks(12)
	check_eq(step_ticks_by_id[a_id], [3, 6, 9, 12], "phase 0 steps on ticks 3,6,9,12")
	check_eq(step_ticks_by_id[b_id], [1, 4, 7, 10], "phase 1 steps on ticks 1,4,7,10")
	sim.free()


func test_freeze_holds_beam() -> void:
	begin("freeze holds beam target constant; unfreeze resumes")
	var sim: Node = make_disc_sim(2)
	var linker := LinkerData.new(Vector2i.ZERO, LinkerData.Type.CONNECTOR, 1, 0)
	var id: int = sim.add_linker(linker)
	sim.initialize_open_set()

	var target_before: Vector2i = sim.beam_target(linker, 0)
	sim.set_frozen(id, true)
	sim.step_ticks(5)
	check_eq(linker.orientation, 0, "frozen linker never steps")
	check_eq(sim.beam_target(linker, 0), target_before, "frozen beam target constant")
	sim.set_frozen(id, false)
	sim.step_ticks(1)
	check_eq(linker.orientation, 1, "unfrozen linker resumes stepping")
	sim.free()


func test_reverse_walks_back() -> void:
	begin("reverse flips spin_dir and walks the beam back")
	var sim: Node = make_disc_sim(2)
	var linker := LinkerData.new(Vector2i.ZERO, LinkerData.Type.CONNECTOR, 1, 0)
	var id: int = sim.add_linker(linker)

	sim.step_ticks(2)
	check_eq(linker.orientation, 2, "two steps forward")
	var target_at_2: Vector2i = sim.beam_target(linker, 0)
	sim.reverse(id)
	sim.step_ticks(1)
	check_eq(linker.orientation, 1, "one step back after reverse")
	sim.step_ticks(1)
	check_eq(linker.orientation, 0, "beam retraces its path")
	sim.reverse(id)
	sim.step_ticks(2)
	check_eq(sim.beam_target(linker, 0), target_at_2, "re-reversed beam returns to same target")
	check_eq(linker.orientation, 2, "orientation wraps with posmod, never negative")
	sim.free()


func test_transmute_effective_type_override() -> void:
	begin("effective_type returns override while beam points, reverts after")
	var sim: Node = make_disc_sim(2)
	var linker := LinkerData.new(Vector2i.ZERO, LinkerData.Type.TRANSMUTE, 1, 0)
	sim.add_linker(linker)
	sim.initialize_open_set()

	var first_target: Vector2i = sim.beam_target(linker, 0)
	check_eq(sim.effective_type(first_target), Terrain.Type.BOOST,
			"pointed-at neighbor takes the override")
	check_eq(sim.effective_type(Vector2i.ZERO), Terrain.Type.BOOST,
			"host tile takes the override too")
	sim.step_ticks(1)
	check_eq(sim.effective_type(first_target), Terrain.Type.PLAINS,
			"override reverts the instant the beam moves on")
	check_eq(sim.effective_type(sim.beam_target(linker, 0)), Terrain.Type.BOOST,
			"new target takes the override")
	check_eq(sim.effective_type(Vector2i(9, 9)), Terrain.Type.VOID,
			"missing tile reads as VOID")
	sim.free()


func test_signals_fire_once_per_transition() -> void:
	begin("link_opened/link_closed fire exactly once per transition")
	var sim: Node = make_disc_sim(2)
	var linker := LinkerData.new(Vector2i.ZERO, LinkerData.Type.TRANSMUTE, 1, 0)
	var id: int = sim.add_linker(linker)

	var opened: Dictionary = {}
	var closed: Dictionary = {}
	sim.link_opened.connect(func(coord: Vector2i, _e: int) -> void:
		opened[coord] = opened.get(coord, 0) + 1)
	sim.link_closed.connect(func(coord: Vector2i, _e: int) -> void:
		closed[coord] = closed.get(coord, 0) + 1)

	sim.initialize_open_set()
	check_eq(opened.get(Vector2i.ZERO, 0), 1, "host opens once at init")
	check_eq(opened.get(Vector2i(1, 0), 0), 1, "initial target opens once at init")

	sim.step_ticks(5)   # visits the 5 remaining neighbors, no wraparound yet
	check_eq(opened.get(Vector2i.ZERO, 0), 1, "host never re-opens while spinning")
	check_eq(closed.get(Vector2i.ZERO, 0), 0, "host never closes while a link exists")
	for dir: Vector2i in HexUtils.DIRECTIONS:
		check_eq(opened.get(dir, 0), 1, "neighbor %s opened exactly once" % dir)
	var total_closed: int = 0
	for coord: Vector2i in closed:
		total_closed += closed[coord]
	check_eq(total_closed, 5, "exactly one close per beam departure")

	# A frozen linker's tick must produce no transitions at all.
	opened.clear()
	closed.clear()
	sim.set_frozen(id, true)
	sim.step_ticks(3)
	check(opened.is_empty() and closed.is_empty(), "frozen ticks emit no signals")
	sim.free()


func test_connector_edge_open_close() -> void:
	begin("connector edge opens/closes as the beam sweeps")
	var sim: Node = make_disc_sim(2)
	var linker := LinkerData.new(Vector2i.ZERO, LinkerData.Type.CONNECTOR, 1, 0)
	sim.add_linker(linker)

	var edge_events: Array = []
	sim.edge_opened.connect(func(a: Vector2i, b: Vector2i, _e: int) -> void:
		edge_events.append(["open", a, b]))
	sim.edge_closed.connect(func(a: Vector2i, b: Vector2i, _e: int) -> void:
		edge_events.append(["close", a, b]))

	sim.initialize_open_set()
	check(sim.is_connector_open(Vector2i.ZERO, Vector2i(1, 0)), "edge open toward initial target")
	check(sim.is_connector_open(Vector2i(1, 0), Vector2i.ZERO), "edge is undirected")
	check_eq(edge_events.size(), 1, "one edge_opened at init")

	sim.step_ticks(1)
	check(not sim.is_connector_open(Vector2i.ZERO, Vector2i(1, 0)), "old edge closed after step")
	check(sim.is_connector_open(Vector2i.ZERO, Vector2i(1, -1)), "new edge open after step")
	check_eq(edge_events.size(), 3, "one open + one close per step")
	sim.free()


func test_same_type_stacking_no_false_close() -> void:
	begin("two same-type beams on one tile: no false close when one departs")
	var sim: Node = make_disc_sim(2)
	# Both TRANSMUTE beams point at (1, 0): one from the west (frozen), one
	# from the east (spins away on tick 1).
	var holder := LinkerData.new(Vector2i.ZERO, LinkerData.Type.TRANSMUTE, 1, 0)
	holder.frozen = true   # orientation 0 -> DIR[0] = (1, 0)
	var leaver := LinkerData.new(Vector2i(2, 0), LinkerData.Type.TRANSMUTE, 1, 0, 3)
	# orientation 3 -> DIR[3] = (-1, 0) -> target (1, 0)
	sim.add_linker(holder)
	sim.add_linker(leaver)

	var closed_at: Array = []
	sim.link_closed.connect(func(coord: Vector2i, _e: int) -> void:
		closed_at.append(coord))

	sim.initialize_open_set()
	check_eq(sim.effective_type(Vector2i(1, 0)), Terrain.Type.BOOST, "stacked tile overridden")
	sim.step_ticks(1)   # leaver swings off; holder still covers (1, 0)
	check(not closed_at.has(Vector2i(1, 0)), "no link_closed while another beam still covers")
	check_eq(sim.effective_type(Vector2i(1, 0)), Terrain.Type.BOOST, "override survives")
	sim.free()


func test_off_map_beam_safe() -> void:
	begin("beam pointing off-map affects only the host, no ghost signals")
	var sim: Node = make_sim()
	sim.add_tile(Vector2i.ZERO)   # a single lonely tile; all neighbors missing
	var linker := LinkerData.new(Vector2i.ZERO, LinkerData.Type.TRANSMUTE, 1, 0)
	sim.add_linker(linker)

	var opened_coords: Array = []
	sim.link_opened.connect(func(coord: Vector2i, _e: int) -> void:
		opened_coords.append(coord))

	sim.initialize_open_set()
	sim.step_ticks(6)
	check_eq(opened_coords, [Vector2i.ZERO], "only the host ever opened")
	check_eq(sim.effective_type(Vector2i.ZERO), Terrain.Type.BOOST, "host still overridden")
	sim.free()


func test_level_data_builds() -> void:
	begin("LevelData populates a coherent v0 map")
	var sim: Node = make_sim()
	LevelData.apply(sim)
	sim.initialize_open_set()
	check_eq(sim.tiles.size(), 61, "radius-4 disc has 61 tiles")
	check_eq(sim.linkers.size(), 4, "four linkers placed")
	check(Terrain.is_passable(sim.effective_type(LevelData.PLAYER_START)),
			"player start is passable")
	for linker: LinkerData in sim.linkers.values():
		check(sim.tiles.has(linker.host_coord), "linker %d hosted on a real tile" % linker.id)
		check(Terrain.is_passable(sim.tiles[linker.host_coord].terrain),
				"linker %d host is passable terrain" % linker.id)
	sim.step_ticks(60)   # smoke: a minute of ticks without errors
	check_eq(sim.tick_count, 60, "sim survives 60 ticks")
	sim.free()
