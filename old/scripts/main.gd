extends Node2D
## Top-level scene script. Wires together grid, player, game state, and HUD.

@onready var hex_grid: HexGrid = $HexGrid
@onready var player: Player = $HexGrid/Player
@onready var game_state: GameState = $GameState
@onready var hud: HUD = $UILayer/HUD

## Total number of objectives in the level (set once on start).
var _total_objectives: int = 0
## Currently highlighted (valid-move) tiles.
var _highlighted_coords: Array[Vector2i] = []


func _ready() -> void:
	# Place the player at the level start position.
	player.place(LevelData.PLAYER_START, hex_grid.hex_size)

	# Count objectives for the HUD tracker.
	_total_objectives = _count_remaining_objectives()

	# Initialize HUD.
	hud.update_clocks(game_state.personal_time, game_state.total_world_ticks)
	hud.update_objectives(_total_objectives, _total_objectives)

	# Wire signals.
	hex_grid.hex_clicked.connect(_on_hex_clicked)
	hud.speed_selected.connect(_on_speed_selected)
	hud.restart_pressed.connect(_restart)
	game_state.clocks_changed.connect(hud.update_clocks)
	game_state.phase_changed.connect(_on_phase_changed)
	game_state.turn_resolved.connect(_on_turn_resolved)
	game_state.game_ended.connect(_on_game_ended)

	# Show initial valid moves.
	_update_highlights()


# -- Input handling ----------------------------------------------------------

func _on_hex_clicked(coord: Vector2i) -> void:
	if game_state.current_phase == GameState.Phase.GAME_OVER:
		return

	var tile: HexTile = hex_grid.tiles.get(coord)
	if tile == null:
		return

	var neighbors: Array[Vector2i] = HexUtils.get_neighbors(player.current_coord)
	var is_adjacent: bool = coord in neighbors
	var is_walkable: bool = (
		tile.tile_type != HexTile.TileType.FLOODED
		and tile.tile_type != HexTile.TileType.FLOOD_SOURCE
	)

	if is_adjacent and is_walkable:
		if game_state.current_phase == GameState.Phase.AWAITING_SPEED \
				and game_state.selected_destination == coord:
			# Tapping the already-selected tile cancels.
			_clear_selection()
			game_state.cancel_destination()
		else:
			# Select this tile as destination.
			_clear_selection()
			_select_tile(coord)
			game_state.select_destination(coord)
	else:
		# Non-adjacent or non-walkable — cancel any selection.
		if game_state.current_phase == GameState.Phase.AWAITING_SPEED:
			_clear_selection()
			game_state.cancel_destination()


func _on_speed_selected(speed: GameState.Speed) -> void:
	game_state.select_speed(speed)


# -- Turn resolution --------------------------------------------------------

func _on_turn_resolved(destination: Vector2i, world_ticks: int) -> void:
	# 1. Spread flood before the player arrives (per DESIGN.md turn order).
	var objective_drowned: bool = hex_grid.spread_flood(world_ticks)

	# 2. Move the player.
	player.place(destination, hex_grid.hex_size)

	# 3. Clear objective if the player stepped on one (only if it wasn't just flooded).
	var tile: HexTile = hex_grid.tiles.get(destination)
	if tile and tile.tile_type == HexTile.TileType.OBJECTIVE:
		tile.set_type(HexTile.TileType.NORMAL)

	# Update objectives counter.
	hud.update_objectives(_count_remaining_objectives(), _total_objectives)

	# 4. Check lose: personal time.
	if game_state.check_personal_time():
		game_state.end_game(false, "Out of personal time!")
		return

	# 5. Check lose: player standing on a flooded tile.
	if tile and tile.tile_type == HexTile.TileType.FLOODED:
		game_state.end_game(false, "Swept away by the flood!")
		return

	# 6. Check lose: flood covered an uncleared objective.
	if objective_drowned:
		game_state.end_game(false, "Objective drowned by the flood!")
		return

	# 7. Check win: all objectives cleared.
	if _count_remaining_objectives() == 0:
		game_state.end_game(true, "All objectives cleared!")
		return

	# 8. Start next turn.
	_clear_selection()
	game_state.begin_next_turn()
	_update_highlights()


# -- Phase / game-over callbacks --------------------------------------------

func _on_phase_changed(phase: GameState.Phase) -> void:
	match phase:
		GameState.Phase.AWAITING_DESTINATION:
			hud.set_speed_buttons_enabled(false)
			hud.clear_message()
		GameState.Phase.AWAITING_SPEED:
			hud.set_speed_buttons_enabled(true)
			hud.show_message("Pick a speed")
		GameState.Phase.GAME_OVER:
			hud.set_speed_buttons_enabled(false)


func _on_game_ended(won: bool, reason: String) -> void:
	if won:
		hud.show_message("YOU WIN! " + reason)
	else:
		hud.show_message("GAME OVER: " + reason)
	_clear_highlights()


# -- Restart ----------------------------------------------------------------

func _restart() -> void:
	# Reset grid to original level layout.
	hex_grid.reset_tiles()
	# Reset game state (clocks, phase).
	game_state.reset()
	# Move player back to start.
	player.place(LevelData.PLAYER_START, hex_grid.hex_size)
	# Reset objectives counter.
	_total_objectives = _count_remaining_objectives()
	hud.update_objectives(_total_objectives, _total_objectives)
	hud.clear_message()
	# Show valid moves.
	_highlighted_coords.clear()
	_update_highlights()


# -- Helpers ----------------------------------------------------------------

func _select_tile(coord: Vector2i) -> void:
	var tile: HexTile = hex_grid.tiles.get(coord)
	if tile:
		tile.set_selected(true)


func _clear_selection() -> void:
	for coord: Vector2i in hex_grid.tiles:
		var tile: HexTile = hex_grid.tiles[coord]
		tile.set_selected(false)


func _update_highlights() -> void:
	_clear_highlights()
	for coord: Vector2i in HexUtils.get_neighbors(player.current_coord):
		var tile: HexTile = hex_grid.tiles.get(coord)
		if tile == null:
			continue
		if tile.tile_type == HexTile.TileType.FLOODED or tile.tile_type == HexTile.TileType.FLOOD_SOURCE:
			continue
		tile.set_highlighted(true)
		_highlighted_coords.append(coord)


func _clear_highlights() -> void:
	for coord: Vector2i in _highlighted_coords:
		var tile: HexTile = hex_grid.tiles.get(coord)
		if tile:
			tile.set_highlighted(false)
	_highlighted_coords.clear()


func _count_remaining_objectives() -> int:
	var count: int = 0
	for coord: Vector2i in hex_grid.tiles:
		if hex_grid.tiles[coord].tile_type == HexTile.TileType.OBJECTIVE:
			count += 1
	return count
