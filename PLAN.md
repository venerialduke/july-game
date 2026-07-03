# Implementation Plan — v0 (Linker Prototype)

Based on `NEW_DESIGN.md`. Goal: validate whether the spinning-linker loop is
fun in ~90 seconds of play.

## Decision log

- **Keep this repo** — Android export, HexUtils, project settings, and
  directory conventions carry over. Replace flood-game files as we go.
- **Architecture** — central `MapSim` autoload owns all state as plain data.
  Visual nodes are dumb readers. This maps onto the two-actor split: Claude
  Code owns the sim, developer owns the scenes.
- **Claude Code can run headless tests itself** — Godot lives at
  `C:\Godot\Godot_v4.7-stable_win64_console.exe`. Tests run via
  `--headless --script res://tests/test_map_sim.gd --path .`, so M1–M3 need
  no developer involvement. The developer checkpoint moves to M4 (visuals).
- **`TileData` is a Godot built-in class** (TileMap API) — our tile data
  class is named `HexTileData` to avoid the collision.
- **Old flood-game files live in `old/`** with a `.gdignore` so the editor
  ignores them (prevents duplicate `class_name` errors). Git history also
  preserves them; `old/` can be deleted whenever.
- **Tests instantiate `map_sim.gd` directly** (`load(...).new()`) rather than
  relying on the autoload singleton, so the sim stays testable outside the
  scene tree.

## Architecture

```
MapSim (Autoload, extends Node)     — scripts/map_sim.gd
 └── Owns: tiles{}, linkers{}, tick clock, beam resolution
 └── Emits: link_opened, link_closed, linker_stepped
 └── Exposes: effective_type(coord), freeze/reverse tool API

Main (Node2D)
 ├── HexGridView (Node2D)           — visual tile rendering (reads MapSim)
 │    └── TileView × N              — listens to link_opened/closed for VFX
 ├── LinkerView × N (Node2D)        — visual linker, rotation lerp
 ├── Leader (Node2D)                — player unit, movement
 ├── Units (Node2D)                 — followers
 └── UILayer (CanvasLayer)
      └── HUD                       — freeze/reverse buttons, debug info
```

## Milestones

### M1 — MapSim data model + tick loop (headless, Claude Code)
- Define `TileData` and `LinkerData` as plain data classes.
- `MapSim` autoload with `tiles{}`, `linkers{}`, `tick_count`, `tick_len`,
  `accum`.
- `_process(dt)` accumulates time and fires `step_linkers()`.
- `step_linkers()` respects `period`, `phase_offset`, `frozen`, `spin_dir`.
- No visual scenes — pure logic.

### M2 — Beam resolution + open-set diffing + signals (headless, Claude Code)
- `compute_all_beams()` resolves every linker's links into target coords.
- `recompute_open_set()` diffs current vs previous, emits `link_opened` and
  `link_closed` exactly once per transition.
- `effective_type(coord)` returns override terrain if any beam points at coord,
  else base terrain.

### M3 — Headless tests (Claude Code writes AND runs)
- Period-2 and period-3 linkers re-align every 6 ticks.
- `phase_offset` correctly staggers same-period linkers.
- Freeze holds beam target constant; reverse walks it back.
- `effective_type` returns override while beam points, reverts on close.
- Signals fire exactly once per transition, not per tick.

### M4 — Visual hex grid + linker rendering (both actors)
- Claude Code: `HexGridView` scene/script that reads `MapSim.tiles` and
  renders colored hex tiles. `LinkerView` scene/script that shows beam
  direction and lerps rotation.
- Developer: run in editor, tune visual placement, report what looks off.

### M5 — Leader movement (both actors)
- Tap-to-move across hex tiles.
- Movement cost varies by `effective_type(coord)`.
- Claude Code: movement logic and pathfinding.
- Developer: input handling, camera, visual feel.

### M6 — CONNECTOR + TRANSMUTE effects (Claude Code + visual tuning)
- CONNECTOR: beam makes an impassable edge passable while active.
- TRANSMUTE: beam overrides host + neighbor tile type temporarily.
- Both visible on map via `link_opened`/`link_closed` signals.

### M7 — Freeze + Reverse tools (both actors)
- Tap a linker to select it; UI buttons to freeze or reverse.
- Freeze sets `frozen = true`, linker skips ticks, beam holds.
- Reverse flips `spin_dir`.

### M8 — Proximity combat (Claude Code + visual tuning)
- Dumb AI enemies placed on the map.
- Auto-combat when Leader/units are adjacent to enemies.
- `effective_type` affects combat (terrain bonuses/penalties).

### M9 — Android deploy + playtest
- Export to phone, play for 90 seconds.
- Answer the validation question: is the linker loop fun?
- If yes: proceed to extraction/session layer.
- If no: tune `tick_len`, linker density, effect magnitude before adding scope.

## Files to keep from flood game
- `scripts/hex_utils.gd` — axial math (reuse directly)
- `CLAUDE.md` — workflow and conventions (update architecture section)
- `LESSONS.md` — reference
- `project.godot` — viewport, renderer, Android export settings

## Files to remove or replace
- `scripts/hex_tile.gd`, `hex_grid.gd`, `game_state.gd`, `player.gd`,
  `main.gd`, `hud.gd`, `level_data.gd`
- `scenes/HexTile.tscn`, `HexGrid.tscn`, `Main.tscn`, `Player.tscn`,
  `HUD.tscn`
- `DESIGN.md` (superseded by `NEW_DESIGN.md`)
