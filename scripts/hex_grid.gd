class_name HexGrid
extends Node2D
## Owns the hex tile grid. Generates tiles, stores them in a dictionary
## keyed by axial coordinate, and provides lookup functions.

signal hex_clicked(coord: Vector2i)

const HEX_TILE_SCENE: PackedScene = preload("res://scenes/HexTile.tscn")
const GRID_RADIUS: int = 3  ## Radius 3 gives a hexagonal grid with 37 tiles.

@export var hex_size: float = 40.0

## All tiles keyed by their axial coordinate.
var tiles: Dictionary = {}


func _ready() -> void:
	_generate_grid()


func _generate_grid() -> void:
	for q: int in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for r: int in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var s: int = -q - r
			if absi(s) > GRID_RADIUS:
				continue
			var coord := Vector2i(q, r)
			var tile: HexTile = HEX_TILE_SCENE.instantiate()
			add_child(tile)
			var tile_type: HexTile.TileType = LevelData.TILE_OVERRIDES.get(
				coord, HexTile.TileType.NORMAL
			)
			tile.initialize(coord, hex_size, tile_type)
			tile.tile_clicked.connect(_on_tile_clicked)
			tiles[coord] = tile


## Spread the flood outward by the given number of rings.
## Returns true if any objective tile was drowned during the spread.
func spread_flood(ticks: int) -> bool:
	var objective_drowned: bool = false
	for _i: int in range(ticks):
		if _spread_one_ring():
			objective_drowned = true
	return objective_drowned


## Flood one ring outward. Returns true if any objective was drowned.
func _spread_one_ring() -> bool:
	var to_flood: Array[Vector2i] = []
	for coord: Vector2i in tiles:
		var tile: HexTile = tiles[coord]
		if tile.tile_type == HexTile.TileType.FLOODED or tile.tile_type == HexTile.TileType.FLOOD_SOURCE:
			for neighbor: Vector2i in HexUtils.get_neighbors(coord):
				if tiles.has(neighbor):
					var n_tile: HexTile = tiles[neighbor]
					if n_tile.tile_type == HexTile.TileType.NORMAL or n_tile.tile_type == HexTile.TileType.OBJECTIVE:
						if neighbor not in to_flood:
							to_flood.append(neighbor)
	var drowned: bool = false
	for coord: Vector2i in to_flood:
		if tiles[coord].tile_type == HexTile.TileType.OBJECTIVE:
			drowned = true
		tiles[coord].set_type(HexTile.TileType.FLOODED)
	return drowned


## Reset all tiles to their original types from the level data.
func reset_tiles() -> void:
	for coord: Vector2i in tiles:
		var original_type: HexTile.TileType = LevelData.TILE_OVERRIDES.get(
			coord, HexTile.TileType.NORMAL
		)
		var tile: HexTile = tiles[coord]
		tile.set_type(original_type)
		tile.set_highlighted(false)
		tile.set_selected(false)


func _on_tile_clicked(coord: Vector2i) -> void:
	hex_clicked.emit(coord)
