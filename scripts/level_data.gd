class_name LevelData
## Hardcoded v0 level layout. Pure static data/builder, no nodes.
##
## Design intent: a small readable disc where each linker demonstrates its
## effect — a CONNECTOR on the lake shore (bridge over water), a CONNECTOR
## at the mountain ridge (gap through the wall), and TRANSMUTEs in the open
## (visible tile-type flips). Periods 2 and 3 re-align every 6 ticks so
## alignment is learnable (NEW_DESIGN.md section 7).

const MAP_RADIUS: int = 4
const PLAYER_START: Vector2i = Vector2i(0, 2)

## Neutral units to collect, placed so gathering them tours the map.
const UNIT_SPAWNS: Array[Vector2i] = [
	Vector2i(-1, 2), Vector2i(2, 1), Vector2i(-2, 0), Vector2i(1, -2),
]

## Enemies guard interesting spots: across the lake, and near the north
## forest. Stationary dumb AI in v0.
const ENEMY_SPAWNS: Array[Vector2i] = [
	Vector2i(4, -2), Vector2i(-1, -2),
]

## Terrain overrides; every other coord in the disc is PLAINS.
const TERRAIN_OVERRIDES: Dictionary[Vector2i, Terrain.Type] = {
	# East lake — crossable only via the shore CONNECTOR's beam.
	Vector2i(2, -1): Terrain.Type.WATER,
	Vector2i(2, 0): Terrain.Type.WATER,
	Vector2i(3, -1): Terrain.Type.WATER,
	Vector2i(3, -2): Terrain.Type.WATER,
	# West mountain ridge — a wall with no natural gap.
	Vector2i(-3, 0): Terrain.Type.MOUNTAIN,
	Vector2i(-3, 1): Terrain.Type.MOUNTAIN,
	Vector2i(-3, 2): Terrain.Type.MOUNTAIN,
	Vector2i(-2, -1): Terrain.Type.MOUNTAIN,
	# Forest patches — slow going, gives Transmute's BOOST contrast.
	Vector2i(0, -2): Terrain.Type.FOREST,
	Vector2i(1, -3): Terrain.Type.FOREST,
	Vector2i(-1, 3): Terrain.Type.FOREST,
	Vector2i(-1, -1): Terrain.Type.FOREST,
	Vector2i(1, 2): Terrain.Type.FOREST,
}


## Populate a fresh MapSim with the v0 map. Call sim.reset() first and
## sim.initialize_open_set() after.
static func apply(sim: Node) -> void:
	# Hex disc of MAP_RADIUS around origin.
	for q: int in range(-MAP_RADIUS, MAP_RADIUS + 1):
		for r: int in range(maxi(-MAP_RADIUS, -q - MAP_RADIUS),
				mini(MAP_RADIUS, -q + MAP_RADIUS) + 1):
			var coord := Vector2i(q, r)
			sim.add_tile(coord, TERRAIN_OVERRIDES.get(coord, Terrain.Type.PLAINS))

	# Lake-shore CONNECTOR: its beam periodically bridges onto the water.
	sim.add_linker(LinkerData.new(Vector2i(1, 0), LinkerData.Type.CONNECTOR, 2, 0))
	# Ridge CONNECTOR: periodically opens a path toward the mountain wall.
	sim.add_linker(LinkerData.new(Vector2i(-2, 1), LinkerData.Type.CONNECTOR, 3, 0))
	# Center TRANSMUTE: visible type flips in the open, offset from the others.
	sim.add_linker(LinkerData.new(Vector2i(0, 0), LinkerData.Type.TRANSMUTE, 3, 1))
	# North TRANSMUTE: faster spinner near the forest patch.
	sim.add_linker(LinkerData.new(Vector2i(0, -3), LinkerData.Type.TRANSMUTE, 2, 1))

	for coord: Vector2i in UNIT_SPAWNS:
		sim.add_unit(coord)
	for coord: Vector2i in ENEMY_SPAWNS:
		sim.add_enemy(coord)
