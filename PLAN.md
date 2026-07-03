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

### M4 — Visual hex grid + linker rendering (both actors) ✅ DONE
- `HexGridView` (_draw-based tiles, beam rings, connector bridges),
  `LinkerView` (hub + arrow, rotation lerp), debug HUD tick counter.
- Verified by developer 2026-07-02: grid renders, linkers move, tile colors
  respond to beams. CONNECTOR + TRANSMUTE effects landed here too (the old
  M6 — they fell out of the sim core for free).

> **Re-plan 2026-07-02** (after first desktop playtest): validate the basic
> mechanics — Leader, stamina movement, Units, combat — before any tuning or
> design work. Tools come after movement (they complete the linker
> interaction loop and need tap-selection, which movement input establishes).
> `tick_len` raised 5s → 15s per playtest feedback.

### M5 — Leader + stamina movement ✅ DONE
Verified by developer 2026-07-02 ("working, feels ok"). Playtest
adjustments applied: sprint is press-and-hold (not toggle), stamina regens
only while the Leader is stopped, and a radial tick wheel in the HUD shows
time creeping toward the next tick.
- One Leader on the map, spawned at `LevelData.PLAYER_START`.
- Tap a tile → Dijkstra path over passable tiles; Leader walks it in real
  time (this is a real-time game, not turn-based).
- Two speeds: **slow move is free; fast move drains stamina**; stamina
  regens while not fast-moving; at 0 stamina fast reverts to slow.
- Terrain drives traversal time through `effective_type` (re-checked every
  edge crossing, never cached): plains 1×, forest 2×, mountain/water
  impassable.
- Linker interactions this unlocks: CONNECTOR beam = temporary bridge over
  water (crossable edge, cost 1); TRANSMUTE's BOOST override can make even
  a mountain briefly passable. A path is validated per-edge mid-walk — if a
  bridge closes ahead of you, the Leader halts (`leader_blocked`).
- Headless tests for pathfinding, timing, stamina, bridge close mid-walk.

### M6 — Freeze + Reverse tools 🔨 BUILT, awaiting playtest
- Tap a linker's tile to select (white ring); tap again to deselect; tap
  elsewhere to deselect and move. HUD Freeze/Unfreeze + Reverse buttons
  appear while selected. No range limit on tools yet — open design knob.

### M7 — Units: collect + follow 🔨 BUILT, awaiting playtest
- Neutral units (gray) on the map; Leader walks onto one to collect it.
- Party trails the Leader snake-style in collection order.

### M8 — Proximity auto-combat 🔨 BUILT, awaiting playtest
- Stationary dumb enemies (red diamonds). Continuous automatic combat on
  adjacency: all adjacent party members attack; the enemy strikes the
  first adjacent target, units before Leader (units tank).
- Terrain reads through `effective_type` per frame: an attacker standing
  on a BOOST tile deals 2x damage (`boost_attack_mult`).
- Knobs: leader 100hp/12dps, unit 40hp/8dps, enemy 60hp/10dps.
- Leader death: `leader_died` fires once, movement halts, HUD shows
  DEFEATED. No restart flow yet (relaunch the scene).

### M9 — Android deploy + 90-second playtest
- Export to phone, play for ~90 seconds.
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
