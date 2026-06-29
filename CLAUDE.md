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

## Architecture

Scene tree:

```
Main (Node2D)                      — scripts/main.gd (glue + turn flow)
 ├── HexGrid (Node2D)              — scripts/hex_grid.gd (tile dictionary, flood spread)
 │    ├── HexTile × N (Polygon2D)  — scripts/hex_tile.gd (coord, type, color, click)
 │    └── Player (Node2D)          — scripts/player.gd (position + draw)
 ├── GameState (Node)              — scripts/game_state.gd (state machine, clocks)
 └── UILayer (CanvasLayer)
      └── HUD (MarginContainer)    — scripts/hud.gd (labels, buttons, messages)
```

Key data-only scripts (no nodes):
- `scripts/hex_utils.gd` — pure hex math (registered via `class_name`, not autoload)
- `scripts/level_data.gd` — hardcoded level layout (tile type overrides, player start)

Signal flow: HexTile → HexGrid → Main → GameState → Main → HUD.
All signals connected in code (`_ready()`), none wired in the editor.

## Notes

- HUD uses a full-screen `MarginContainer` on a `CanvasLayer`. All non-button
  controls have `mouse_filter = IGNORE` so clicks pass through to the game
  layer. This is set recursively in `hud.gd._ready()`.
- `HexUtils` uses `class_name` (not autoload) because it has only static
  functions and doesn't extend Node.
- Desktop window override is 480×854 to fit on screen during development;
  the game viewport is 720×1280 (portrait, 9:16).

### Playtest notes (to address)

- Flood spreads too aggressively — "Fast" is essentially unusable because it
  drowns objectives immediately. Needs tuning (flood speed, level layout, or
  starting distances).
- Flooded objectives currently trigger instant game over. Design intent may be
  better served by making drowned objectives simply uncollectable (lost but
  not an immediate loss), so the player can still attempt the remaining ones.