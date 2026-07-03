class_name HexTileData
extends RefCounted
## Plain data for one hex tile. Static-ish: tiles do not spin.
## Named HexTileData because TileData is a Godot built-in (TileMap API).

var coord: Vector2i          ## Axial (q, r).
var terrain: Terrain.Type    ## Base terrain. Read through MapSim.effective_type().


func _init(p_coord: Vector2i, p_terrain: Terrain.Type = Terrain.Type.PLAINS) -> void:
	coord = p_coord
	terrain = p_terrain
