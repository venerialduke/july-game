class_name Terrain
## Terrain types and their gameplay properties. Pure data, no nodes.
## Tile type drives movement (and later combat) — always read through
## MapSim.effective_type(), never cache (transient linker overrides).

enum Type {
	VOID,      ## Off-map / missing tile. Impassable.
	PLAINS,    ## Baseline. Cheap to cross.
	FOREST,    ## Slow to cross.
	MOUNTAIN,  ## Impassable.
	WATER,     ## Impassable.
	BOOST,     ## Transmute override terrain: fast + (later) combat bonus.
}

## Movement cost to enter a tile of this type. -1 = impassable.
const MOVE_COST: Dictionary[Type, int] = {
	Type.VOID: -1,
	Type.PLAINS: 1,
	Type.FOREST: 2,
	Type.MOUNTAIN: -1,
	Type.WATER: -1,
	Type.BOOST: 1,
}


static func move_cost(type: Type) -> int:
	return MOVE_COST[type]


static func is_passable(type: Type) -> bool:
	return MOVE_COST[type] >= 0
