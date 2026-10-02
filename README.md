# 3D Rayman Style Game

A movement-first 3D platformer about being **heavy**. Started from Rayman 2 and 3 as a reference
point; now heading somewhere of its own.

> **New to the project?** Start with **[docs/GUIDED_TOUR.md](docs/GUIDED_TOUR.md)** — a hands-on
> walkthrough for developers who can code but haven't used Godot before. Then pick something from
> **[docs/TASKS.md](docs/TASKS.md)**.

The design bet: **weight is a resource, and momentum lives in the level.** The character is heavy,
which costs you the ability to change your mind — slow to start, slow to stop, hard to turn in the
air. In exchange, height becomes stored energy you spend on a slam, and slopes become somewhere to
build speed that nothing then takes away from you.

Momentum being *level geometry* rather than a player ability is deliberate. A ramp is content, so a
level has speed where you put a ramp in it and a level with no ramps has none — which means each
level sets its own pace. Abilities still combine rather than take turns: a slam bounce feeds the next
slam, a tongue-grabbed enemy becomes a thrown weapon, a long ramp feeds a jump across a gap nothing
else can cross.

Godot **4.7.2**, GL Compatibility renderer. Open `3d-rayman-type-game/project.godot` and press F5.

## Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Move | `WASD` | Left stick |
| Look | Mouse or arrow keys | Right stick |
| Jump | `Space` | A |
| **Ground slam** | `Space` again in the air | A again |
| **Tongue / swing** | `Q` or `RMB` — **hold** on an anchor to swing | RB |
| **Jump off the rope** | `Space` while swinging | A |
| **Reel rope in / out** | `E` / `Ctrl` while swinging | B / LB |
| Grab & throw | `E` | B |
| Drop from a ledge | `Ctrl`, or steer away | LB |
| Debug readout | `F3` | — |
| Respawn / restart | `R` / `F5` | — |
| Release mouse | `Esc` | — |

Grapple and look have keyboard alternatives because right-click and precise mouse movement are
awkward on a laptop trackpad.

## The moveset

- **Run / jump** — acceleration-based, with coyote time, jump buffering, variable jump height and
  softened gravity at the apex. Deliberately **heavy**: about half a second to get up to speed, a
  couple of metres to stop, and very little steering once you are in the air. That commitment is the
  price of everything below.
- **Slopes** — the momentum engine. Downhill is free speed and nothing takes it back off you; uphill
  spends it fast. There are no new buttons for this, it is just gravity along the floor.

  Measured, starting at 9 m/s: a **12° ramp takes you to 16.6 m/s**, a **30° ramp to 17.7**, flat
  ground bleeds you back to walking pace, and running **uphill kills all 9 m/s in under 3 metres**.
  Running speed is 7.5, so a good ramp is worth more than double it.

  Two thresholds fall out of one number (`slope_gravity`) rather than needing their own settings:
  past about **7°** a slope beats friction, so speed keeps growing; past about **27°** it beats your
  own braking, so you slide down it standing still.
- **Crumbling floors** — slabs your own weight destroys. Walking over one is fine; landing on it from
  a height, or slamming near it, drops it out from under you. If being heavy were only ever an
  advantage it would stop being a constraint and quietly become a stat.
- **Ledge grab** — automatic when you fall past a grabbable lip. Shimmy sideways, `Space` to climb,
  steer away to drop. Note a standing jump clears 2.35 m, so **lips below ~3.3 m just get landed
  on** — grabbing is for lips *above* your jump, caught on the way down.
- **Wall run / wall jump** — run along a wall with enough speed and it carries you; jump off it to
  cross gaps or climb a shaft. Triggered by momentum, not by holding into the wall.
- **Ground slam** — press jump again in mid-air to drive yourself into the ground. This is the
  character's defining move, because the character is **heavy**, and the slam is what turns that
  weight into something useful.

  Everything about it scales with how far you fell, measured from the highest point you reached
  since last touching the ground. Damage, shockwave radius and rebound height all grow with the
  drop. A hop is worth almost nothing; a fall from a tower is worth a lot. That is the point:
  **height becomes a resource worth going and fetching**, not just a place you happen to be.

  The impact hits everything within the shockwave, not only what was underneath, and shoves it
  away. An expanding ring is drawn at the real radius that was used, so the scaling is visible
  rather than something you have to infer.

  **The rebound always returns you to jump height**, so a slam never costs you ground. Height is
  gained from the *combo* instead: every third slam in an unbroken chain throws you 50% higher than
  a jump and hits harder with a wider, red-tinted shockwave. Touching down without slamming resets
  the chain, so a run of slams is something you sustain rather than something that just happens.
- **Tongue** — press `Q` and it reaches for the ringed target. One button, and what happens depends
  on whether the target can be moved:
  - **Anchor (purple ring)** — bolted to the level, so *you* are the one that moves: you **swing**
    from it. See below.
  - **Enemy (red ring)** — not bolted down, so *it* is pulled to *you*, and you end up carrying it.
    Press `Q` again to throw it.
  - **A turret** cannot be dragged, so the tongue lashes it for damage instead.
- **Swing** — hold `Q` on an anchor and you are on a rope. **Nothing about it is capped**, and that
  is the entire point: the fun of a grapple is abusing its physics to get somewhere you have no
  business being.

  | | |
  | --- | --- |
  | hold `Q` | stay attached; let go and you keep **every bit** of the speed you built |
  | stick | pumps along the arc, with no speed limit at all |
  | `E` / `Ctrl` | reel the rope in and out |
  | `Space` | leave the rope with a jump added **on top of** the swing's speed |

  A free drop through the arc already reaches about 22 m/s — three times running speed — and the
  pump has no ceiling above that. The rope is **one-sided**: it pulls but never pushes, so with
  enough speed you go clean over the top of the anchor and loop around it. Reeling in while moving
  fast trades rope for speed, which is the main exploit on offer. Reel all the way in and you arrive
  at the anchor and bounce off it at jump height.

  This is the mechanic's third version. The first put the pendulum on the jump button — wrong kind
  of input. The second had five caps stacked in one function, each added to answer a feel complaint,
  and between them they removed the only reason to use a swing at all. If it ever feels wrong again,
  the fix is to take something away.
- **Throwing** — a thrown object is not a lob, it is a **rocket**. Modelled on the Yoshi egg in
  Super Mario 64 DS: it picks the nearest enemy, sets off straight at it at 34 m/s, and steers to
  stay on it. You are not meant to aim well; you are meant to throw in roughly the right direction
  and watch it connect.

  If it misses, it **ricochets** — up to four surfaces, keeping most of its speed, and picking a
  fresh target after every bounce. That is what makes a miss interesting rather than a waste: the
  throw that sailed past comes back off the wall looking for someone else. Each bounce on the way
  also adds damage, so working the walls pays.

  It bursts at the end with a ring at its real radius, hurting everything in reach. Applies to
  anything throwable — a tongue-grabbed enemy and a hand-grabbed keg use the same `ThrownFlight`
  component.

  Aiming is camera-driven with assist: the ringed target is whatever is nearest the centre of the
  screen, in range and in line of sight. Anchors win ties against enemies.

  The enemy half is modelled on Yoshi's tongue and the Mario Galaxy 2 spin-grab: an attack and a way
  of rearranging the level, not only a way of moving yourself.
- **Combat** — slam them, stomp them from above, or throw something at them.

Two moves have been cut as the game found its own shape: the **thrown fist** and the **helicopter**
(2026-09-29), the two most Rayman-specific moves in the set.

The grapple is the thing that has been reworked most, and the record is worth keeping. It was a
pendulum on the jump button (wrong kind of input, cut), then a capped pendulum (five limits in one
function, cut), then a pull-and-bounce with no swing at all — which worked exactly as specified and
was dull, because **the caps were what was wrong, not the pendulum.** It is now a swing again with
nothing capped. The enemy-grabbing half survived all of it unchanged.

## Two scenes

**`scenes/playground.tscn` is where the current direction is.** A momentum playground built for one
question — does weight-and-momentum feel right? — and nothing else. A 12° ramp down into a plaza, a
30° ramp you cannot stand still on, a 12 m gap only crossable with ramp speed, and three crumbling
slabs bridging it that your own landing destroys. It contains **no grapple anchors**, on purpose: a
scene with every mechanic in it cannot answer a question about one of them.

**`scenes/main.tscn` is the original moveset showcase**, left untouched as a reference.

## Test level

The showcase level in `main.tscn`: one hub with four zones, each built around a mechanic:

| Direction | Zone | Teaches |
| --- | --- | --- |
| North | Rising platforms, then a gap with two anchors | Jumping, then **swinging** across |
| East | Pit spanned by a tan wall, then a shaft | **Wall run**, then **wall jump** |
| West | Three terraces with 3.3 m lips | **Ledge grab** (too high to jump onto) |
| South | Chain of anchors over a pit, tower | **Swinging** (nothing else crosses it) |

Tan surfaces are the runnable walls. Falling into a pit respawns you at the last checkpoint.

## Layout

```
scripts/
  game.gd              score, checkpoints, respawn
  events.gd            autoloaded signal bus (`Events`)
  player/              player.gd (state machine), camera, grapple targeting, ledge sensor
  enemies/             walker, turret, bullet
  components/          health, thrown_flight (homing + ricochet for anything thrown)
  props/               lum, grapple point, throwable keg, checkpoint, hazard, crumbling floor
  ui/                  hud.gd (hearts, lums, grapple reticle, F3 debug)
scenes/                one scene per script, plus the two levels
                       playground.tscn  momentum playground (current direction)
                       main.tscn        moveset showcase (reference)
tests/                 moveset smoke test
```

`player.gd` is a single enum + `match` state machine rather than a node tree, because these states
share a lot of velocity maths and constantly interrupt each other.

## Tuning

Every feel number is an `@export` on the player, grouped in the inspector (Run, Jump, Wall moves,
Ledge grab, Grapple, Weight, Slam, Combat, Sounds). Select the Player node and edit them there — no
code changes needed. Enemies, lums and grapple points expose their own knobs the same way.

## Smoke test

After changing movement numbers, run:

```
"<godot>" --headless --path 3d-rayman-type-game res://tests/moveset_smoke_test.tscn
```

It drives the player through all 48 behaviours (each state, damage, death, respawn, stomp, grab
and throw, plus slopes, crumbling floors, the homing throw and its ricochets) and prints a PASS/FAIL table. Exit code 0
means everything passed. It caught several real bugs during the initial build and is worth
rerunning whenever the controller changes.

## Not done yet

Deliberately left out, since this is a sandbox to grow rather than a finished game: animation
(the character is primitives, moved procedurally), swimming, any kind of menu or save
system, and level content beyond the test blockout.
