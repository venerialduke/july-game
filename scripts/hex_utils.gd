class_name HexUtils
## Pure hex-math utility functions. No nodes, no state.
## Uses axial coordinates (q, r) with flat-top hexagons.
## Registered as an autoload so any script can call HexUtils.function_name().

## The six axial direction vectors for flat-top hex neighbors.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


## Convert an axial coordinate to a pixel position (flat-top layout).
static func axial_to_pixel(coord: Vector2i, hex_size: float) -> Vector2:
	var x: float = hex_size * (3.0 / 2.0 * coord.x)
	var y: float = hex_size * (sqrt(3.0) / 2.0 * coord.x + sqrt(3.0) * coord.y)
	return Vector2(x, y)


## Convert a pixel position back to the nearest axial coordinate (flat-top).
static func pixel_to_axial(pixel: Vector2, hex_size: float) -> Vector2i:
	var q: float = (2.0 / 3.0 * pixel.x) / hex_size
	var r: float = (-1.0 / 3.0 * pixel.x + sqrt(3.0) / 3.0 * pixel.y) / hex_size
	return axial_round(Vector2(q, r))


## Round fractional axial coordinates to the nearest hex.
static func axial_round(frac: Vector2) -> Vector2i:
	var s: float = -frac.x - frac.y
	var q_round: int = roundi(frac.x)
	var r_round: int = roundi(frac.y)
	var s_round: int = roundi(s)

	var q_diff: float = absf(q_round - frac.x)
	var r_diff: float = absf(r_round - frac.y)
	var s_diff: float = absf(s_round - s)

	if q_diff > r_diff and q_diff > s_diff:
		q_round = -r_round - s_round
	elif r_diff > s_diff:
		r_round = -q_round - s_round
	# else: s_round adjusts, but we only store q and r

	return Vector2i(q_round, r_round)


## Return the six neighbor coordinates of a given axial coordinate.
static func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for dir: Vector2i in DIRECTIONS:
		neighbors.append(coord + dir)
	return neighbors


## Manhattan distance between two axial coordinates (cube-based).
static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = absi(a.x - b.x)
	var dr: int = absi(a.y - b.y)
	var ds: int = absi((-a.x - a.y) - (-b.x - b.y))
	return maxi(dq, maxi(dr, ds))


## Return the vertices of a flat-top hexagon centered at the origin.
static func get_hex_vertices(hex_size: float) -> PackedVector2Array:
	var vertices := PackedVector2Array()
	for i: int in range(6):
		var angle_deg: float = 60.0 * i
		var angle_rad: float = deg_to_rad(angle_deg)
		vertices.append(Vector2(hex_size * cos(angle_rad), hex_size * sin(angle_rad)))
	return vertices
