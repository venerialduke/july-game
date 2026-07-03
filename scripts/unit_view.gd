class_name UnitView
extends Node2D
## Visual for one Unit: gray while neutral, green once collected. Position
## eases toward the unit's tile so trail-following reads smoothly.
## Main frees this view when the unit dies.

const NEUTRAL_COLOR := Color(0.62, 0.62, 0.62)
const PARTY_COLOR := Color(0.55, 0.9, 0.55)
const OUTLINE_COLOR := Color(0.12, 0.13, 0.16)
const HP_COLOR := Color(0.4, 1.0, 0.4)

var id: int = -1
var unit: UnitData
var hex_size: float = 48.0


func setup(p_id: int, p_unit: UnitData, p_hex_size: float) -> void:
	id = p_id
	unit = p_unit
	hex_size = p_hex_size
	position = HexUtils.axial_to_pixel(unit.coord, hex_size)


func _process(delta: float) -> void:
	var target: Vector2
	if unit.collected and MapSim.leader != null:
		# Party units ride the Leader's tile: cluster in a ring around it,
		# each in a stable slot position.
		var slot: int = MapSim.party.find(id)
		var angle: float = TAU * float(maxi(slot, 0)) / float(maxi(MapSim.party_slots, 1)) - PI / 2.0
		target = LeaderView.leader_pixel(MapSim.leader, hex_size) \
				+ Vector2.from_angle(angle) * hex_size * 0.34
	else:
		target = HexUtils.axial_to_pixel(unit.coord, hex_size)
	position = position.lerp(target, minf(10.0 * delta, 1.0))
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, hex_size * 0.19, OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, hex_size * 0.14,
			PARTY_COLOR if unit.collected else NEUTRAL_COLOR)
	if unit.hp < unit.max_hp:
		draw_arc(Vector2.ZERO, hex_size * 0.24, -PI / 2.0,
				-PI / 2.0 + TAU * (unit.hp / unit.max_hp), 24, HP_COLOR, 3.0)
