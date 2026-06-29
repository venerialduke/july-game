class_name LevelData
## Hardcoded level layout for Game 0.
## Defines which tiles are objectives/flood sources and where the player starts.
##
## Layout rationale (see DESIGN.md "the trap to avoid"):
##   - Flood sources at the west edge.
##   - Objectives spread across the board, with at least one close to the
##     flood's natural path so rushing genuinely risks drowning it.
##   - Player starts in the center.

const PLAYER_START := Vector2i(0, 0)

## Tiles that aren't listed here default to NORMAL.
const TILE_OVERRIDES: Dictionary = {
	# Flood sources — west edge
	Vector2i(-3, 1): HexTile.TileType.FLOOD_SOURCE,
	Vector2i(-3, 2): HexTile.TileType.FLOOD_SOURCE,
	# Objectives — scattered, one deliberately in the flood's path
	Vector2i(-1, -1): HexTile.TileType.OBJECTIVE,  # northwest, near flood path
	Vector2i(1, -2): HexTile.TileType.OBJECTIVE,   # north
	Vector2i(2, 1): HexTile.TileType.OBJECTIVE,    # east
	Vector2i(0, 3): HexTile.TileType.OBJECTIVE,    # south
}
