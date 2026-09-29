# 3D Rayman Style Game

A movement-first 3D platformer in the spirit of Rayman 2, Rayman 3 and the cancelled Rayman 4.

> **New to the project?** Start with **[docs/GUIDED_TOUR.md](docs/GUIDED_TOUR.md)** — a hands-on
> walkthrough for developers who can code but haven't used Godot before. Then pick something from
> **[docs/TASKS.md](docs/TASKS.md)**.

The design bet: **abilities combine rather than take turns.** Every state hands off into the
others — a swing releases into a dive, a dive bounces off an enemy into another dive, a wall run
launches a grapple. Levels are meant to be solved by stringing the moveset together, not by
performing one scripted move per obstacle.

Godot **4.7.2**, GL Compatibility renderer. Open `3d-rayman-type-game/project.godot` and press F5.

## Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Move | `WASD` | Left stick |
| Look | Mouse or arrow keys | Right stick |
| Jump | `Space` | A |
| **Grapple / dive** | `Space` again in the air (also `RMB` or `Q`) | A again, or RB |
| Fling off a swing | `Space` mid-swing | A |
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
- **Grapple** — one verb for everything. Press jump again in the air and you go to the ringed
  target. What happens on arrival depends on what you hit, and that is the whole design:
  - **Enemy (red ring)** — you strike it and bounce off still airborne, so one dive chains straight
    into the next. This is the game's only ranged offence.
  - **Anchor (purple or orange ring)** — depends on the `Grapple Style` toggle on the Player.
    **MOMENTUM** turns anchors into a swing: pump the arc, `Space` flings you off with everything
    you built. **HOMING** dives at them like an enemy — you stop dead and pop off. Both are
    implemented; flip the toggle in the Inspector and play them to decide which the game wants.

  Aiming is camera-driven with assist: the ringed target is whatever is nearest the centre of the
  screen, in range and in line of sight. Anchors win ties against enemies, because this is a
  movement game first.
- **Combat** — dive at enemies, stomp them from above, or throw a keg at them.

The **thrown fist** and the **helicopter** were both removed on 2026-09-29 — they were the most
Rayman-specific parts of the moveset, and the game is moving toward its own identity. With the
helicopter gone there is no mid-air save: a second jump does nothing unless something is targetable,
so committing to an arc actually means something.

## Test level

One hub with four zones, each built around a mechanic:

| Direction | Zone | Teaches |
| --- | --- | --- |
| North | Rising platforms, then a gap with two anchors | Jumping, then **diving** across |
| East | Pit spanned by a tan wall, then a shaft | **Wall run**, then **wall jump** |
| West | Three terraces with 3.3 m lips | **Ledge grab** (too high to jump onto) |
| South | Chain of anchors over a pit, tower | **Grappling** (nothing else crosses it) |

Tan surfaces are the runnable walls. Falling into a pit respawns you at the last checkpoint.

## Layout

```
scripts/
  game.gd              score, checkpoints, respawn
  events.gd            autoloaded signal bus (`Events`)
  player/              player.gd (state machine), camera, grapple targeting, ledge sensor
  enemies/             walker, turret, bullet
  props/               lum, grapple point, throwable keg, checkpoint, hazard
  ui/                  hud.gd (hearts, lums, grapple reticle, F3 debug)
scenes/                one scene per script, plus levels/test_level.tscn
tests/                 moveset smoke test
```

`player.gd` is a single enum + `match` state machine rather than a node tree, because these states
share a lot of velocity maths and constantly interrupt each other.

## Tuning

Every feel number is an `@export` on the player, grouped in the inspector (Run, Jump, Wall moves,
Ledge grab, Grapple, Combat, Sounds). Select the Player node and edit them there — no
code changes needed. Enemies, lums and grapple points expose their own knobs the same way.

## Smoke test

After changing movement numbers, run:

```
"<godot>" --headless --path 3d-rayman-type-game res://tests/moveset_smoke_test.tscn
```

It drives the player through all 26 behaviours (each state, damage, death, respawn, stomp, grab
and throw) and prints a PASS/FAIL table. Exit code 0 means everything passed. It caught several
real bugs during the initial build and is worth rerunning whenever the controller changes.

## Not done yet

Deliberately left out, since this is a sandbox to grow rather than a finished game: animation
(the character is primitives, moved procedurally), swimming, any kind of menu or save
system, and level content beyond the test blockout.
