# july-game v0 — Handoff Brief

Repo: `github.com/venerialduke/july-game`
Engine: Godot 4.7, GDScript
Workflow: two-actor. Claude Code owns file-based work (data model, sim, tests). Alex owns the Godot editor, visual scenes, input, and device deployment.

This brief describes the long-term vision briefly, then specifies exactly what v0 must build and, just as importantly, what it must not. v0 exists to validate one thing: whether the spinning-linker loop is fun. Everything is scoped around answering that cheaply.

---

## 1. Game vision (long-term, context only — do not build)

A real-time (not turn-based) game on a hex map that blends three genres, each eventually owning one layer:

- Auto chess — how combat resolves mid-run (proximity-based, automatic).
- Extraction / battle royale — the session shape and risk curve (land, act under pressure, extract).
- Civ — mostly from a hex tile look, and maybe some tile + unit upgrades, but mostly style.

The player controls one or more Leaders (hero units) with stamina-style movement, who gather Units that follow them. All combat is automatic based on proximity.

The novel core hook — the thing that is actually ours and the thing v0 validates — is the **linker**: an object that lives on a hex tile, spins on a clock, and beams a transient effect onto an adjacent tile. Rotating linkers make the map a set of moving, readable "windows" the player positions around, and reaches into with tools.

None of the three genre layers are in v0. They are named only so architecture decisions do not paint us into a corner.

---

## 2. v0 scope

### In
- A hex map of tiles. Tiles have a location and properties (terrain, resources). Tiles do not spin.
- Linkers: first-class objects that live on a tile, spin on a global tick clock, and apply a transient effect to the tile they point at.
- One Leader as the player unit, with movement across the map.
- Units that follow the Leader.
- Automatic proximity combat against dumb AI enemies.
- Tile type affects Leader movement and combat.
- Two tools that let the player reach into linker spin: **freeze** and **reverse**.

### Out (explicitly deferred)
- No extraction / session-end / risk timer.
- No unit collection economy, no base, no meta layer, no upgrades.
- No persistence of any kind. All linker effects are transient (see section 6).
- No handshake between two linkers (removed — see section 5).
- No Resource Boon linker type yet (needs a collection mechanic that does not exist in v0).
- No `align` tool yet (freeze and reverse only).

### The validation question
Is standing near a spinning linker — waiting for its beam to swing onto a useful tile, or spending a freeze to hold it there — tense and satisfying for ~90 seconds? If yes, the design works and everything else is worth building. If it feels like watching a microwave, the tuning (tick length, effect payoff) needs to change before anything else gets built.

---

## 3. Architecture: central sim, dumb visual tiles

One autoload (`MapSim`) owns all game state as plain data objects and advances it in a single tick loop. Visual nodes read state and render it; they hold no authoritative state. The sim emits signals when linker windows open and close; the view and combat systems react to those signals and never compute geometry themselves.

Rationale:
- The simulation is a pure function of state plus elapsed time, with no dependency on the scene tree, so it can be written and unit-tested headlessly by Claude Code.
- The boundary maps exactly onto the two-actor split: Claude Code owns the sim, Alex owns the scenes downstream of the emitted signals.
- Save/load and any future networking reduce to serializing the state dictionaries.

Explicitly rejected: autonomous tile/linker nodes that self-rotate and query neighbors in `_process`. That entangles logic with the scene tree, blocks headless testing, and runs hundreds of per-node callbacks on a mobile target.

---

## 4. Rotation is discrete

A linker's gameplay orientation is an integer 0–5 and changes in 60-degree steps. The integer is the truth. The visual node may lerp/creep for juice, but logic reads the int only.

This makes alignment event-driven, not polled: a beam target can only change when a linker snaps to a new orientation, so neighbor resolution runs on that event and is never touched between snaps. No per-frame angular-overlap checks.

---

## 5. Single-linker beam model (no handshake)

A linker has one or more link edges. A link at logical edge `e`, on a linker with orientation `o`, points across physical direction `(e + o) % 6` at exactly one neighbor tile. As the linker spins, that active edge sweeps around its neighbors like a clock hand.

The effect applies to the two tiles flanking the active edge: the **host tile and the pointed-at neighbor**. There is no requirement for a second aligned linker.

Emergence is not lost, just not required: when two linkers happen to point at the same tile, that tile receives both effects at once — a transient stacking spot that arises from position and timing, with no matching rule needed.

---

## 6. Transient effects only

Nothing a linker does persists. An effect exists only while the beam points at a tile and reverts the instant the beam moves on. The sim stores no effect history; open-state is a pure function of current orientations.

Consequence that must be respected everywhere: because Transmute temporarily overrides a tile's type, and tile type drives movement and combat, **no system may cache a tile's type**. Everyone reads through a single `effective_type(coord)` function:

```
effective_type(coord):
    base = tiles[coord].terrain
    override = highest-priority active linker override pointing at coord, if any
    return override if present else base
```

Movement, combat, and rendering all query `effective_type` each step. Cache it anywhere and transient effects silently stop working.

---

## 7. Global tick clock

Time advances in discrete integer ticks. A tick is a small quantum (`tick_len`, start around 5s, fully tunable). Linker speed is expressed as `period` = number of ticks per rotation step. Period 1 is fastest (a step every tick), higher periods are slower.

- Deterministic: feeding a tick sequence yields exact orientations, which is what makes headless testing clean.
- Linkers of related periods re-synchronize on their least common multiple, so alignment is learnable rather than random.
- `phase_offset` staggers linkers of the same period so they do not all snap in lockstep. A linker steps when `(tick_count - phase_offset) % period == 0`.

`tick_len` is a knob to tune, not a fixed decision. It sets both time resolution and the fastest possible event, so keep it smaller than the slowest thing we want to feel.

---

## 8. Data model

```
TileData:            # static-ish, does not spin
    coord     : Vector2i      # axial q,r
    terrain   : enum          # drives movement + combat
    resources : ...           # placeholder for v0

LinkerData:          # first-class, lives on a tile
    host_coord   : Vector2i
    orientation  : int        # 0..5, logical truth
    period       : int        # steps every `period` ticks (1 fast .. N slow)
    phase_offset : int        # 0..period-1, staggers same-period linkers
    spin_dir     : int        # +1 or -1 (reverse flips this)
    frozen       : bool       # freeze tool
    type         : enum { TRANSMUTE, CONNECTOR }   # one per linker; BOON later
    links        : Array[int] # logical edges; start with 1. 2 = two beams

MapSim (autoload):
    tiles      : Dictionary   # coord -> TileData
    linkers    : Dictionary   # id -> LinkerData
    tick_count : int
    tick_len   : float        # the quantum
    accum      : float        # advance tick_count when >= tick_len
    DIR        : [Vector2i]   # 6 axial direction vectors, indexed by physical dir
```

`spin_accum` per linker is gone; the global tick replaces it.

---

## 9. Core loop

```
process(dt):
    accum += dt
    while accum >= tick_len:
        accum -= tick_len
        tick_count += 1
        step_linkers()

step_linkers():
    new_open = {}                       # (coord) -> effect, for this snapshot
    for L in linkers.values():
        if L.frozen: continue
        if (tick_count - L.phase_offset) % L.period != 0: continue
        L.orientation = (L.orientation + L.spin_dir + 6) % 6
    # after all snaps, recompute the live set from current orientations
    recompute_open_set()                # diff vs last set

recompute_open_set():
    current = compute_all_beams()       # {coord: type} from every linker's links
    for coord in current - last_open:   emit link_opened(coord, current[coord])
    for coord in last_open - current:   emit link_closed(coord, last_open[coord])
    last_open = current

compute_beam(L, edge):
    phys = (edge + L.orientation) % 6
    return L.host_coord + DIR[phys]     # the pointed-at neighbor
```

`recompute_open_set` can run only for linkers that actually stepped this tick, as an optimization, once correctness is proven.

---

## 10. Linker types (v0)

One type per linker; same rule (type selects effect) for all.

- **CONNECTOR** — while the beam points at the neighbor, the edge between host and neighbor becomes passable when it otherwise would not be, or cheaper to traverse. Acts on movement, which exists. Cleanest, safest, fully transient. This is the anchor type.
- **TRANSMUTE (stripped for v0)** — while the beam points at the neighbor, both host and neighbor tiles take a temporary type override (a single special terrain, e.g. a hazard or a boost). Not a full type-combination lookup table yet, and not persistent. Rides movement and combat via `effective_type`.
- **BOON** — deferred. Needs a collection mechanic to amplify; nothing to modify in v0.

Ship CONNECTOR and stripped TRANSMUTE so v0 visibly shows two different beam effects.

---

## 11. Tools

Both act on linker spin state; neither needs to know what the beam does.
- **Freeze** — set `frozen = true`; the linker is skipped on ticks, holding its current beam open. Unfreeze resumes.
- **Reverse** — flip `spin_dir`, swinging the beam back the other way.
- Align — deferred. On this grid it will be trivial later (snap orientation, optionally raise period to rest).

---

## 12. Interface between sim and everything else

The sim exposes:
- `signal link_opened(coord, type)`
- `signal link_closed(coord, type)`
- `func effective_type(coord) -> terrain`

The view listens to the signals to trigger open/close VFX. Combat and movement query `effective_type` each step. No downstream system computes hex geometry or reads linker orientation directly.

---

## 13. Ownership split

Claude Code:
- `TileData`, `LinkerData`, `MapSim` and the tick loop.
- Beam resolution, `effective_type`, open-set diffing, signal emission.
- Tool state effects (freeze, reverse).
- Headless deterministic tests.

Alex:
- Tile and linker visual scenes, rotation lerp, link-open/close VFX.
- Camera, input, Leader control.
- Device deployment.

---

## 14. Testing (headless, deterministic)

Because the sim is pure and tick-driven, tests feed a tick sequence and assert exact state:
- A period-2 and period-3 linker re-align every 6 ticks.
- `phase_offset` correctly staggers two same-period linkers.
- Freeze holds a beam target constant across ticks; reverse walks it back.
- `effective_type` returns the override while a Transmute beam points at a tile and reverts on `link_closed`.
- `link_opened` / `link_closed` fire exactly once per transition, not per tick.

---

## 15. Open tuning knobs (do not hardcode as decisions)

- `tick_len` — the base quantum / fastest event.
- Linker density — how many linkers, how spread. Directly controls map legibility.
- Per-linker `period` range and how much they vary.
- Whether a linker emits on every orientation or has dead arcs (only some orientations point/emit), if the map feels overactive.
- Transmute's chosen special terrain and its movement/combat magnitude.
