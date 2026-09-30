# 3D Rayman Style Game

A movement-first 3D platformer about being **heavy**. Started from Rayman 2 and 3 as a reference
point; now heading somewhere of its own.

> **New to the project?** Start with **[docs/GUIDED_TOUR.md](docs/GUIDED_TOUR.md)** — a hands-on
> walkthrough for developers who can code but haven't used Godot before. Then pick something from
> **[docs/TASKS.md](docs/TASKS.md)**.

The design bet: **abilities combine rather than take turns**, and **weight is a resource**. Height
becomes stored energy you spend on a slam; momentum carries between moves. Every state hands off into the
others — a slam bounce feeds the next slam, a tongue-grabbed enemy becomes a thrown weapon, a wall run
launches a grapple. Levels are meant to be solved by stringing the moveset together, not by
performing one scripted move per obstacle.

Godot **4.7.2**, GL Compatibility renderer. Open `3d-rayman-type-game/project.godot` and press F5.

## Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Move | `WASD` | Left stick |
| Look | Mouse or arrow keys | Right stick |
| Jump | `Space` | A |
| **Ground slam** | `Space` again in the air | A again |
| **Tongue** | `Q` or `RMB` — again to throw what you hold | RB |
| Grab & throw | `E` | B |
| Drop from a ledge | `Ctrl`, or steer away | LB |
| Debug readout | `F3` | — |
| Respawn / restart | `R` / `F5` | — |
| Release mouse | `Esc` | — |

Grapple and look have keyboard alternatives because right-click and precise mouse movement are
awkward on a laptop trackpad.

## The moveset

- **Run / jump** — acceleration-based, with coyote time, jump buffering, variable jump height and
  softened gravity at the apex.
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
  - **Anchor (purple ring)** — bolted to the level, so *you* are pulled to *it*, and then you
    **bounce off it to jump height**, like a trampoline bolted to the sky. The bounce is what makes
    the pull worth doing: it carries part of your inbound speed through, so you are thrown out past
    the anchor and into the next one rather than parked above it. Same rule as the slam — no ability
    should quietly cost you altitude.
  - **Enemy (red ring)** — not bolted down, so *it* is pulled to *you*, and you end up carrying it.
    Press `Q` again to throw it.
  - **A turret** cannot be dragged, so the tongue lashes it for damage instead.
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

  Modelled on Yoshi.s tongue and the Mario Galaxy 2 spin-grab rather than on a grapple hook — it is
  an attack and a way of rearranging the level, not a way of swinging around it.
- **Combat** — slam them, stomp them from above, or throw something at them.

Three things have been cut as the game found its own shape: the **thrown fist** and the
**helicopter** (2026-09-29), and the **grapple swing** (2026-09-30). The first two were the most
Rayman-specific moves in the set. The swing worked and was fully tested, but a pendulum is
sustained momentum management while a jump is a single impulse, and binding one to the other never
read right. Reframing the grapple as a tongue solved it by making it an *action*, not a *state*.

## Test level

One hub with four zones, each built around a mechanic:

| Direction | Zone | Teaches |
| --- | --- | --- |
| North | Rising platforms, then a gap with two anchors | Jumping, then **diving** across |
| East | Pit spanned by a tan wall, then a shaft | **Wall run**, then **wall jump** |
| West | Three terraces with 3.3 m lips | **Ledge grab** (too high to jump onto) |
| South | Chain of anchors over a pit, tower | **Tongue pulls** (nothing else crosses it) |

Tan surfaces are the runnable walls. Falling into a pit respawns you at the last checkpoint.

## Layout

```
scripts/
  game.gd              score, checkpoints, respawn
  events.gd            autoloaded signal bus (`Events`)
  player/              player.gd (state machine), camera, grapple targeting, ledge sensor
  enemies/             walker, turret, bullet
  components/          health, thrown_flight (homing + ricochet for anything thrown)
  props/               lum, grapple point, throwable keg, checkpoint, hazard
  ui/                  hud.gd (hearts, lums, grapple reticle, F3 debug)
scenes/                one scene per script, plus levels/test_level.tscn
tests/                 moveset smoke test
```

`player.gd` is a single enum + `match` state machine rather than a node tree, because these states
share a lot of velocity maths and constantly interrupt each other.

## Tuning

Every feel number is an `@export` on the player, grouped in the inspector (Run, Jump, Wall moves,
Ledge grab, Grapple, Slam, Combat, Sounds). Select the Player node and edit them there — no
code changes needed. Enemies, lums and grapple points expose their own knobs the same way.

## Smoke test

After changing movement numbers, run:

```
"<godot>" --headless --path 3d-rayman-type-game res://tests/moveset_smoke_test.tscn
```

It drives the player through all 37 behaviours (each state, damage, death, respawn, stomp, grab
and throw, plus the homing throw and its ricochets) and prints a PASS/FAIL table. Exit code 0
means everything passed. It caught several real bugs during the initial build and is worth
rerunning whenever the controller changes.

## Not done yet

Deliberately left out, since this is a sandbox to grow rather than a finished game: animation
(the character is primitives, moved procedurally), swimming, any kind of menu or save
system, and level content beyond the test blockout.
