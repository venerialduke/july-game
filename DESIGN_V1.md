# july-game v1 — Depth & Danger

Successor to `NEW_DESIGN.md` (v0, complete). v0's verdict: the loop works
mechanically and deploys smoothly, but it's "OK", not yet fun. v1 exists to
find the fun across four pillars, with a working model built for fast design
iteration.

## Working model

- **Data-driven everything.** Tile types, enemy archetypes, generation
  parameters, and cultivation numbers live in plain data tables (one or two
  files). A design iteration is a table edit + playtest, not a systems
  rewrite. Alex can edit tables directly.
- **Engineering foundations first** (low design-risk): camera + procedural
  map + fog, then the enemy framework. Then repeated short design rounds.
- Same two-actor split and headless-test discipline as v0.

## Decisions (Alex, 2026-07-02)

1. **Enemies move continuously**, like the Leader — organic, threatening,
   not tick-quantized. (Linkers stay on the tick clock; the tick wheel keeps
   its meaning.)
2. **Map is seeded procedural**, radius ~10 (331 tiles), with tunable
   generation knobs. New seed = free new map. Fits the eventual
   extraction-session shape (fresh drop each run).
3. **Fog of war ships in v1, simple version**: tiles start hidden,
   permanently revealed within sight range as the Leader explores. No
   re-hiding.

---

## Pillar 1 — World: procedural map, camera, fog

**Generation** (`MapGen`, seeded RNG, all knobs in one table): hex disc of
`radius`; water lakes and mountain ridges grown as blobs/walks; forest
patches; a guaranteed-plains safe zone around the spawn; linkers placed with
a minimum spacing on reachable tiles; units and enemies placed on reachable
tiles with distance constraints (enemies never near spawn). Determinism is
tested: same seed → identical map.

**Camera**: follows the Leader (smoothed). Drag to pan (breaks follow);
tapping a move order re-engages follow. Mouse wheel / two-finger pinch to
zoom, clamped. Tap-vs-drag disambiguated by a slop threshold.

**Fog**: `MapSim` owns `revealed{}` + `sight_radius` (default 3). Revealing
happens on spawn and on each tile entered. Move orders can only target
revealed tiles (paths may cross unrevealed terrain — acceptable for now,
revisit if it feels like cheating). Terrain, linkers, units, enemies are
drawn only on revealed tiles.

Open questions:
- Entity visibility: v1 ships "anything on a revealed tile is visible
  forever". The menacing alternative — moving enemies visible only within
  current sight range — is a one-line view change; decide after playing.
- Should unrevealed tiles show as dim silhouettes instead of nothing?

## Pillar 2 — Enemies that feel dangerous

Movement: continuous, reusing the Leader's traversal machinery (a shared
"mover" — coord, path, edge progress, speed multiplier — advanced by
MapSim). Enemies respect `effective_type` and connector bridges like
everyone else, so linkers gate *their* movement too (freeze a bridge open
and something may follow you across it).

Archetypes are a data table; starting roster to tune:

| archetype | speed | hp | power | behavior |
|-----------|-------|----|-------|----------|
| DRIFTER   | slow  | low| low   | wanders randomly, ignores you |
| BRUTE     | slow  | high| high | patrols a small territory, chases briefly if you enter it |
| HUNTER    | medium| med| med   | acquires the Leader within `aggro_radius`, paths to you, re-paths on a timer, gives up beyond `leash_range` |

Behavior params (per archetype): `speed_mult`, `aggro_radius`,
`leash_range`, `repath_interval`, `wander_interval`. AI decisions happen on
sim-side timers (deterministic given a dt sequence, so still headless-
testable). Danger telegraphs: an `enemy_aggroed` signal for a visual flash
when a hunter acquires you.

Open questions: pack behavior? enemy dens/respawn? do enemies fight each
other? night/tick-linked aggression?

## Pillar 3 — Units are cultivated, not collected

Skeleton to iterate on (numbers all knobs):
- **Resource nodes** on the map (a new tile property or entity). The Leader
  collects by entering the tile. HUD shows a resource count.
- Collected units start weak (**Recruit**). Spending resources on a unit
  matures it through stages — Recruit → Fighter → Veteran — raising hp and
  power per a stage table. Feeding happens while stopped (a HUD action).
- Party slots still cap the party; cultivation makes each slot matter more
  than hoarding.
- Future tie-in: the deferred BOON linker type amplifies resource nodes its
  beam covers — this is where BOON finally gets something to modify.

Open questions: one resource or several? do unfed units decay? can units
die permanently (currently yes) and does maturation make that too punishing?
is feeding instant or over time?

## Pillar 4 — Tiles and linkers with identity

Terrain becomes a full data table: per type — move cost, attack multiplier,
defense multiplier, resource yield, color, and a one-line identity.
Candidate additions beyond plains/forest/mountain/water: SWAMP (slow, bad
for combat), CRYSTAL field (resource-rich, contested), RUINS (defensive
strongpoint). Combat reads attack AND defense mults through
`effective_type` (already the law of the codebase).

Linker depth, in rough order of leverage:
- Per-linker transmute terrain (this one makes hazards, that one makes
  boosts) — table-driven.
- Second link edge (`links = [0, 3]` — opposite beams) — already supported
  by the sim, just needs placing and tuning.
- Dead arcs (orientations where a linker emits nothing) — the design doc's
  "if the map feels overactive" knob.

## Build order

- **P1 (now): World** — MapGen + camera + fog, tests, playtest checkpoint.
- **P2: Enemies** — mover refactor, archetype framework, roster, telegraphs,
  tests, "does it feel dangerous?" checkpoint.
- **P3: Cultivation** — resources, feeding, stage tables, HUD, checkpoint.
- **P4+: Design rounds** — tile/linker/enemy/cultivation table iteration,
  several quick loops per session.
