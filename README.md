# 3D Rayman Style Game

A movement-first 3D platformer in the spirit of Rayman 2, Rayman 3 and the cancelled Rayman 4.

The design bet: **abilities combine rather than take turns.** Every state hands off into the
others — a swing releases into a helicopter, a helicopter ends in a ledge grab, a wall run
launches a grapple. Levels are meant to be solved by stringing the moveset together, not by
performing one scripted move per obstacle.

Godot **4.7.2**, GL Compatibility renderer. Open `3d-rayman-type-game/project.godot` and press F5.

## Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Move | `WASD` | Left stick |
| Look | Mouse | Right stick |
| Jump | `Space` | A |
| **Helicopter** | `Space` again while falling | A again |
| **Grapple** | Hold `RMB` | Hold RB |
| Fling off a swing | `Space` mid-swing | A |
| Fist / charged fist | Tap / hold `LMB` | X |
| Grab & throw | `E` | B |
| Drop from a ledge | `Ctrl`, or steer away | LB |
| Debug readout | `F3` | — |
| Respawn / restart | `R` / `F5` | — |
| Release mouse | `Esc` | — |

## The moveset

- **Run / jump** — acceleration-based, with coyote time, jump buffering, variable jump height and
  softened gravity at the apex.
- **Helicopter** — hold jump while falling to hover down at a fixed slow speed with strong air
  control. By default it must be a *fresh* press, so it reads as deliberate
  (`helicopter_requires_repress`). Unlimited like Rayman 2; set `helicopter_max_time` above 0 to
  put it on a budget.
- **Ledge grab** — automatic when you fall past a grabbable lip. Shimmy sideways, `Space` to climb,
  steer away to drop. Note a standing jump clears 2.35 m, so **lips below ~3.3 m just get landed
  on** — grabbing is for lips *above* your jump, caught on the way down.
- **Wall run / wall jump** — run along a wall with enough speed and it carries you; jump off it to
  cross gaps or climb a shaft. Triggered by momentum, not by holding into the wall.
- **Grapple** — two kinds of anchor, told apart by colour:
  - **Purple = swing.** Attach and pendulum; steer along the arc to pump height; `Space` flings you
    off with everything you built. Hooking from beyond the rope length reels you in smoothly.
  - **Orange = pull.** Reels you straight to it and pops you loose with an upward kick, so pulls
    chain into jumps and further hooks.
  Aiming is camera-driven with assist: the ringed target is whatever is nearest the centre of the
  screen, in range and in line of sight.
- **Combat** — throw your fist (charged for triple damage), stomp enemies from above, or grab a keg
  and throw it at them.

## Test level

One hub with four zones, each built around a mechanic:

| Direction | Zone | Teaches |
| --- | --- | --- |
| North | Rising platforms, then a 14 m gap | Jumping, then **helicopter** (a plain jump falls short) |
| East | Pit spanned by a tan wall, then a shaft | **Wall run**, then **wall jump** |
| West | Three terraces with 3.3 m lips | **Ledge grab** (too high to jump onto) |
| South | Chain of anchors over a pit, tower | **Swing** and **pull** (nothing else crosses it) |

Tan surfaces are the runnable walls. Falling into a pit respawns you at the last checkpoint.

## Layout

```
scripts/
  game.gd              score, checkpoints, respawn
  events.gd            autoloaded signal bus (`Events`)
  player/              player.gd (state machine), camera, grapple targeting, fist
  enemies/             walker, turret, bullet
  props/               lum, grapple point, throwable keg, checkpoint, hazard
  ui/                  hud.gd (hearts, lums, grapple reticle, F3 debug)
scenes/                one scene per script, plus levels/test_level.tscn
tests/                 moveset smoke test
```

`player.gd` is a single enum + `match` state machine rather than a node tree, because these states
share a lot of velocity maths and constantly interrupt each other.

## Tuning

Every feel number is an `@export` on the player, grouped in the inspector (Run, Jump, Helicopter,
Wall moves, Ledge grab, Grapple, Combat, Carry). Select the Player node and edit them there — no
code changes needed. Enemies, lums and grapple points expose their own knobs the same way.

## Smoke test

After changing movement numbers, run:

```
"<godot>" --headless --path 3d-rayman-type-game res://tests/moveset_smoke_test.tscn
```

It drives the player through all 23 behaviours (each state, damage, death, respawn, stomp, grab
and throw) and prints a PASS/FAIL table. Exit code 0 means everything passed. It caught several
real bugs during the initial build and is worth rerunning whenever the controller changes.

## Not done yet

Deliberately left out, since this is a sandbox to grow rather than a finished game: animation
(the character is primitives, moved procedurally), audio, swimming, any kind of menu or save
system, and level content beyond the test blockout.
