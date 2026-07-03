class_name CameraController
extends Camera2D
## Camera for the big map: smooth-follows the Leader, drag to pan (which
## breaks follow), mouse wheel or two-finger pinch to zoom. Distinguishes
## taps from drags with a slop threshold and emits `tapped` with the world
## position — Main turns taps into move orders (which re-engage follow).
##
## Touch is handled natively (ScreenTouch/ScreenDrag); the emulated mouse
## events Godot synthesizes from touch are ignored here so nothing fires
## twice. Real desktop mice are unaffected.

signal tapped(world_pos: Vector2)

const ZOOM_MIN: float = 0.35
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 1.15
const TAP_SLOP_PX: float = 18.0
const FOLLOW_LERP: float = 5.0

var hex_size: float = 48.0
var follow: bool = true

var _mouse_dragging: bool = false
var _drag_moved: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _touches: Dictionary[int, Vector2] = {}   # active touch index -> screen pos
var _pinch_dist: float = 0.0
var _multi_touched: bool = false   # a pinch happened; suppress the release-tap


func _process(delta: float) -> void:
	if follow and MapSim.leader != null:
		var target: Vector2 = LeaderView.mover_pixel(MapSim.leader, hex_size)
		position = position.lerp(target, minf(FOLLOW_LERP * delta, 1.0))


func snap_to_leader() -> void:
	follow = true
	if MapSim.leader != null:
		position = LeaderView.mover_pixel(MapSim.leader, hex_size)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return   # synthesized from touch; the touch branch handles it
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_at(ZOOM_STEP, event.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_at(1.0 / ZOOM_STEP, event.position)
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_mouse_dragging = true
				_drag_moved = false
				_press_pos = event.position
			else:
				if _mouse_dragging and not _drag_moved:
					tapped.emit(_screen_to_world(event.position))
				_mouse_dragging = false


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _mouse_dragging:
		return
	if not _drag_moved and (event.position - _press_pos).length() > TAP_SLOP_PX:
		_drag_moved = true
		follow = false
	if _drag_moved:
		position -= event.relative / zoom.x


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_press_pos = event.position
			_drag_moved = false
			_multi_touched = false
		elif _touches.size() == 2:
			_pinch_dist = _touch_distance()
			_multi_touched = true
	else:
		if _touches.size() == 1 and event.index in _touches \
				and not _drag_moved and not _multi_touched:
			tapped.emit(_screen_to_world(event.position))
		_touches.erase(event.index)
		_pinch_dist = 0.0


func _handle_touch_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		# Pinch zoom around the midpoint of the two touches.
		var dist: float = _touch_distance()
		if _pinch_dist > 0.0 and dist > 0.0:
			var keys: Array = _touches.keys()
			var midpoint: Vector2 = (_touches[keys[0]] + _touches[keys[1]]) / 2.0
			_zoom_at(dist / _pinch_dist, midpoint)
		_pinch_dist = dist
	else:
		if not _drag_moved and (event.position - _press_pos).length() > TAP_SLOP_PX:
			_drag_moved = true
			follow = false
		if _drag_moved:
			position -= event.relative / zoom.x


## Zoom keeping the world point under `screen_pos` fixed on screen.
func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var before: Vector2 = _screen_to_world(screen_pos)
	var new_zoom: float = clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(new_zoom, new_zoom)
	var after: Vector2 = _screen_to_world(screen_pos)
	position += before - after


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


func _touch_distance() -> float:
	var keys: Array = _touches.keys()
	return (_touches[keys[0]] - _touches[keys[1]]).length()
