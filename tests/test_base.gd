class_name TestBase
extends SceneTree
## Shared harness for headless deterministic test suites. Subclasses
## override run_tests(). Run a suite with:
##   Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/<suite>.gd

const MapSimScript := preload("res://scripts/map_sim.gd")

var _passed: int = 0
var _failed: int = 0
var _current_test: String = ""


func _initialize() -> void:
	run_tests()
	print("")
	if _failed == 0:
		print("ALL TESTS PASSED (%d assertions)" % _passed)
	else:
		print("FAILED: %d failed, %d passed" % [_failed, _passed])
	quit(0 if _failed == 0 else 1)


## Override in each suite.
func run_tests() -> void:
	push_error("TestBase.run_tests() not overridden")
	_failed += 1


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


func begin(test_name: String) -> void:
	_current_test = test_name
	print("- " + test_name)


func check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL [%s]: %s" % [_current_test, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func check_approx(actual: float, expected: float, message: String,
		tolerance: float = 0.001) -> void:
	check(absf(actual - expected) <= tolerance,
			"%s (expected ~%s, got %s)" % [message, expected, actual])
