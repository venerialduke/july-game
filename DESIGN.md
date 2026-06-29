# DESIGN.md — Game 0

Design document for the first project (working title: `july-game`). This is a
**pipeline-validation pass**: the goal is to prove the full build → test → run →
deploy loop with a mechanic that is a real game, not a tech demo. Scope is kept
deliberately minimal.

---

## Concept

You move across a hex grid, clearing objective tiles, while flood water spreads
across the board. Every move, you choose a **speed**. Speed sets up an inverse
tradeoff between two clocks:

- **Going fast** spends less of your personal time, but advances the world more —
  the flood spreads further.
- **Going slow** keeps the flood tame, but bleeds your personal time faster.

You win by clearing all objective tiles before either clock undoes you.

This is a thematic take on the twin paradox: the faster traveler experiences less
time while the world races ahead. Game 0 models the *ratio* between the two clocks
directly with simple integers; the literal relativity curve (γ = 1/√(1−v²)) can be
swapped in later if we want the flavor to be exact rather than thematic.

---

## The core design principle

A single global "speed" setting is boring — there's one right tempo and you just
hold it. This design avoids that by making three things true at once:

1. **Speed is chosen per move, not once.** Every tile-crossing is a fresh decision.
2. **The flood is spatial, not a global timer.** "More world time" doesn't speed up
   the whole game — it means the flood spreads *further from where it currently is*.
   So the cost of going fast depends entirely on **where the flood is relative to
   where you're going**.
3. **The flood threatens objectives, not just the player.** If flood covers an
   uncleared objective tile before you reach it, that tile is lost.

Together these kill the dominant strategy:

- Go fast everywhere → you save personal time, but the flood drowns objective tiles
  before you arrive.
- Go slow everywhere → the flood stays tame, but your personal clock bleeds out.

The correct play is **mixed**: fast on legs heading into safe corridors or away from
the water, slow when threading near the flood's edge toward a threatened tile. Same
button, opposite correct choice depending on the board state. That is a decision,
not a setting.

### Why a player won't "just go slow" — and won't "just go fast"

Both pressures must be live at the same time, or one option silently becomes
dominant:

- **Why not always slow?** Slow is cheap on flood but expensive on your personal
  clock. Holding slow bleeds your Personal Time out before you finish clearing tiles.
- **Why not always fast?** Fast is cheapest on your personal clock, but it spreads
  the flood the most. Rushing a leg near the water can drown an objective tile you
  still needed, making the level unwinnable.

The clock cost answers "why not always slow." The flood-vs-objectives risk answers
"why not always fast." Both have to bite for the choice to matter.

### The trap to avoid

The clock tradeoff alone does **not** save the design. If the flood is too slow or
starts too far away, it never actually threatens objectives — and the moment that's
true, fast is always correct and the game collapses into "hold the fast button."

What makes the design work is **level layout**: objective tiles placed close enough
to the flood's path that rushing genuinely risks losing them. The numbers create the
tension; the map placement is what *triggers* it. Levels must be built deliberately,
not randomly. At least one objective tile should sit in the flood's likely path so
the player feels a real "if I rush this leg, I'll lose that tile" moment. If they
never feel that, retune flood speed or move the tile until they do.

---

## Core elements

- **Hex board** — a small fixed grid (target ~7×7, axial coordinates). Each tile is
  one of: `normal`, `objective`, `flooded`, or `flood-source`.
- **Player** — occupies one hex. Stepping onto an objective tile clears it.
- **Two clocks:**
  - **Personal Time** — your finite budget. Each move spends some; faster spends less.
  - **World advance** — each move ticks the world forward; faster ticks more, and the
    flood spreads one ring per world tick.
- **Flood** — spreads outward from source/flooded tiles, one ring per world tick.
- **Objective** — clear all objective tiles and survive.

---

## Turn loop

1. Player picks an adjacent hex to move to **and** a speed (Slow / Normal / Fast).
2. Deduct that speed's **personal cost** from Personal Time.
3. Advance the world by that speed's **world ticks** — flood spreads that many rings.
4. Player moves; if the destination is an objective tile, clear it.
5. Check win/lose.

---

## Win / lose conditions

- **Win:** all objective tiles cleared.
- **Lose** if any of:
  - Personal Time ≤ 0, or
  - the flood reaches the player's tile, or
  - the flood covers an uncleared objective tile (level now unwinnable).

---

## Starting numbers (all tunable by playtesting)

| Speed  | Personal cost | World ticks (flood rings) |
|--------|---------------|----------------------------|
| Slow   | 3             | 1                          |
| Normal | 2             | 2                          |
| Fast   | 1             | 3                          |

- The inverse relationship between personal cost and flood rings is the whole
  mechanic.
- Integer values keep Game 0 readable; the γ curve can replace them later.
- **Personal Time budget** starts around **30** — enough for roughly a dozen moves,
  tight enough that the cost of slow legs is felt. Tune by playing.

---

## Scope for Game 0

**Build:**
- One hardcoded level, built deliberately (see "the trap to avoid").
- Hex grid with axial coordinates and a fixed six-neighbor lookup.
- Three speed buttons (Slow / Normal / Fast).
- Two on-screen clock readouts (Personal Time, World advance).
- Flood-spread step (one ring per world tick).
- Clear-on-step for objective tiles.
- Win / lose detection.
- Plain colored hexes — no art, no sound, no animation.

**Defer:**
- Juice / animation / feedback polish.
- Multiple levels, level loading, menus.
- Art and audio assets.
- The literal γ relativity curve.

---

## Implementation notes

- Use **axial coordinates** with a fixed six-neighbor lookup table. Keeps both
  "spread one ring" and "move to adjacent" logic clean.
- "Spread one ring" = for every currently flooded tile, flood its non-flooded
  neighbors. Apply per world tick.
- Build the single level by hand so at least one objective sits in the flood's path.

---

## Status

- [x] Mechanic defined
- [x] Tradeoff validated on paper
- [x] Level laid out
- [x] Implemented in Godot
- [ ] Playtested and tuned
- [ ] Build → test → run loop validated
