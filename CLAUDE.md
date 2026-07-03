# CLAUDE.md

Standing context for Claude Code on this project. Read at the start of every session.

## Project

A solo-developed, Android-first mobile game built in Godot 4.7. This is an
independent personal project (not work-related). Current phase: pipeline
validation — proving out the full build → test → run → deploy loop with a
minimal mechanic before committing to ongoing production.

## Environment & Stack

- **Engine:** Godot 4.7 (standard build, GDScript — NOT the .NET/C# build)
- **Language:** GDScript
- **Renderer:** Compatibility (chosen for broad Android device support)
- **Target platform:** Android first; other platforms later, not now
- **OS / shell:** Windows, PowerShell
- **Version control:** Git + GitHub (origin: github.com/venerialduke/july-game)

## Working Model

This is a two-actor workflow. Respect the division of labor:

**Claude Code handles (all file-shaped work):**
- Writing and editing GDScript (`.gd`)
- Authoring and editing scene (`.tscn`) and resource (`.tres`) files as text
- Project configuration (`project.godot`, input maps, export settings)
- Git operations, project structure, documentation

**The developer handles (everything requiring the Godot editor):**
- Visual node placement and scene tuning by eye
- Importing assets through the editor
- Running and play-testing the game
- The export wizard / device deployment

**Critical limitation:** Claude Code reads `.tscn` files as text but cannot
press play or observe live runtime behavior. Runtime errors (e.g. a renamed
node making an `@onready` reference null) are caught by the developer running
the game, not by Claude reading files. When a change could fail at runtime,
say so and ask the developer to run and report back.

## Project Structure

Convention (adjust as the project grows):

- `scenes/`   — `.tscn` scene files
- `scripts/`  — `.gd` script files
- `assets/`   — art, audio, fonts (imported via the editor)
- `addons/`   — third-party plugins

## Code Conventions

- Use static typing / type hints on variables, parameters, and return values.
- Prefer composition over inheritance (Godot's node model favors this).
- `snake_case` for variables, functions, and file names; `PascalCase` for
  class names, nodes, and scene files.
- Connect signals in code where practical, so wiring is visible in text and
  reviewable in Git rather than hidden in the editor.
- Keep scripts focused; one clear responsibility per node/script.

## Git Workflow

- Default branch: `main`.
- The `.godot/` cache directory is gitignored and must never be committed.
- Write small, focused commits with clear messages.
- Use `--force-with-lease` (never bare `--force`) if a force-push is ever needed.

## Architecture (v1)

Design in `DESIGN_V1.md` (v0 history: `NEW_DESIGN.md`), plan in `PLAN.md`.
Central-sim pattern: the
`MapSim` autoload (`scripts/map_sim.gd`) owns ALL game state as plain data
and advances it on a global tick clock. Visual nodes are dumb readers that
query the sim and react to its signals; they hold no authoritative state and
never compute hex geometry themselves.

Scene tree (view nodes are spawned by `main.gd`, only the skeleton is in
`Main.tscn`):

```
Main (Node2D)                      — scripts/main.gd (glue: gen map, spawn views, route taps)
 ├── HexGridView (Node2D)          — scripts/hex_grid_view.gd (_draw()s revealed tiles,
 │                                    beam rings, bridges, path dots; fog-aware)
 ├── LinkerViews (Node2D)
 │    └── LinkerView × N           — scripts/linker_view.gd (hub + arrow, rotation lerp)
 ├── LeaderView / UnitView / EnemyView — per-entity dumb readers
 ├── CameraController (Camera2D)   — scripts/camera_controller.gd (follow/pan/zoom,
 │                                    tap-vs-drag; emits tapped(world_pos))
 └── UILayer (CanvasLayer)
      └── HUD (MarginContainer)    — scripts/hud.gd (tick wheel, stamina, tool panel)
```

Autoload + data scripts:
- `scripts/map_sim.gd` — `MapSim` autoload. Tick loop, beam resolution,
  open-set diffing, `effective_type()`, movement + stamina, party/slots,
  combat, fog (`revealed{}`, `is_revealed`), freeze/reverse API. No
  `class_name` (would collide with the autoload name).
- `scripts/map_gen.gd` — `MapGen`: seeded procedural generation; all
  tuning in the `KNOBS` table. Same seed = identical map (tested).
- `scripts/terrain.gd` — `Terrain` enum + movement costs.
- `scripts/hex_tile_data.gd` — `HexTileData` (NOT `TileData`: built-in).
- `scripts/linker_data.gd`, `leader_data.gd`, `unit_data.gd`,
  `enemy_data.gd` — plain data classes.
- `scripts/hex_utils.gd` — pure hex math (`class_name`, not autoload).

Sim interface (the ONLY way downstream systems read linker state):
`link_opened`/`link_closed`/`edge_opened`/`edge_closed`/`linker_stepped`/
`tick_advanced` signals; `effective_type(coord)`, `is_connector_open(a, b)`,
`open_coords(effect)`, `open_connector_edges()`, `beam_target(linker, edge)`.
Never cache `effective_type` results — linker overrides are transient.

## Testing

Headless deterministic suites in `tests/` (`test_map_sim`, `test_movement`,
`test_party_combat`, `test_worldgen`), all extending `tests/test_base.gd`.
Claude Code runs them directly (no developer needed):

```
& C:\Godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/test_map_sim.gd
```

Run `--import` first if new `class_name` scripts were added. Tests
instantiate `map_sim.gd` via `load().new()`, not the autoload. Booting the
main scene headless (`--headless --quit-after 30`) smoke-tests `_ready()`.

## Notes

- HUD is a full-screen `MarginContainer` on a `CanvasLayer`; non-interactive
  controls use `mouse_filter = IGNORE` so touches reach the game layer.
- Desktop window override is 480×854 to fit on screen during development;
  the game viewport is 720×1280 (portrait, 9:16).
- Old flood-game files are parked in `old/` (has a `.gdignore`); delete once
  no longer useful as reference.