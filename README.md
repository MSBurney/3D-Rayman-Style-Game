# 3D Rayman Style Game

**The target: a 3D Wario Land.** What Mario 64 and Odyssey were for Mario, for the Wario games —
heavy influence from Mario 64 DS's Wario. A movement-first 3D platformer about being **heavy**,
where the point is going *through* a level rather than over it.

The repo name is a fossil. It started from Rayman 2 and 3, became its own thing, and landed here.

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
slam, a spin-grabbed enemy becomes a thrown weapon, a long ramp feeds a jump across a gap nothing
else can cross.

Godot **4.7.2**, GL Compatibility renderer. Open `3d-rayman-type-game/project.godot` and press F5.

## Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Move | `WASD` | Left stick |
| Look | Mouse or arrow keys | Right stick |
| Jump | `Space` | A |
| **Double / triple jump** | `Space`, land, `Space` again quickly | A |
| **Side flip** | at speed, flick the stick back and `Space` | stick back + A |
| **Crouch** | `Ctrl` or `Shift` | LB |
| **Backflip** | crouch still, then `Space` | LB then A |
| **Forward slide** | crouch at a run | LB while moving |
| **Long jump** | crouch at a run, then `Space` | LB then A |
| **Ground pound** | **crouch in mid-air** | LB in mid-air |
| **Wall kick** | touch a wall falling, then `Space` | A |
| **Spin attack** | `F` or `LMB` — press again to chain | X |
| **Air spin (small lift)** | `F` or `LMB` in mid-air | X in mid-air |
| **Throw what you hold** | `F` or `LMB` | X |
| Pick something up | just walk into it | — |
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
- **The jump chain** — land and jump again quickly for a double jump, then again for a triple, as
  Mario 64 does. The triple has to be earned: you need to actually be moving, and letting the window
  lapse puts you back to an ordinary jump.
- **Crouch, and the three moves off it** — `Ctrl` ducks you, and what that unlocks depends on what
  you were doing:
  - **still** → **backflip**: straight up, higher than a jump, and backwards.
  - **at a run** → **forward slide**: almost frictionless, so a slope keeps adding to it.
  - **sliding or running, then jump** → **long jump**: low, and a very long way. The push is *added*
    to the speed you already had, so a long jump out of a fast slide down a ramp goes further than
    one off the flat. That is why this move and the slope system belong in the same game.
  - **in mid-air** → **ground pound**.
- **Side flip** — at speed, flick the stick back the way you came and jump. It fires on your *input*
  reversing rather than your velocity reversing, because heavy handling will not let velocity turn
  round quickly, so waiting for it would mean the move never happened.
- **Wall kick** — touch a wall while falling and you cling to it; jump to kick off. Deliberately
  unconditional: there used to be a Rayman-style wall *run* here too, and with both in, the same wall
  would sometimes carry you sideways and sometimes catch you, decided by a speed threshold the player
  could not see.
- **Ground pound** — crouch in mid-air to drive yourself into the floor, and stay there.

  Everything about it scales with how far you fell, measured from the highest point you reached
  since last touching the ground. Damage and shockwave radius both grow with the drop. A hop is
  worth almost nothing; a fall from a tower is worth a lot. That is the point: **height becomes a
  resource worth going and fetching**, not just a place you happen to be.

  The impact hits everything within the shockwave, not only what was underneath, and shoves it
  away. An expanding ring is drawn at the real radius that was used, so the scaling is visible
  rather than something you have to infer.

  It replaced a **bounce attack** that did the same thing and then threw you back up to jump height,
  with every third one in a chain going 50% higher. That needed the jump button in mid-air, which
  the double and triple jump now own — and a pound that launches you is not a pound. The fall-distance
  scaling was kept because it is the part that carried the weight-is-a-resource idea.
- **Spin attack** — press `F` and the character spins, Mario Galaxy style. It hurts enemies in a
  radius, trips switches, and **drags anything carryable to you** so you end up holding it. Press
  again to chain: the second spin is wider, and the **third is the biggest and hardest-hitting**.
  After the third the chain resets, so the big one is always the pay-off for three presses rather
  than a lucky accident mid-string.

  Anything can answer to a spin by joining the `spinnable` group and implementing `spin_hit()` —
  that is two lines, and it is how "a variety of other interactions" is meant to grow. `spin_switch.gd`
  is the first user and is deliberately tiny.

  **It replaced the grapple**, which had been through four versions: a pendulum on the jump button,
  a pendulum with five caps, a pull-and-bounce, and finally an uncapped swing that was genuinely fun
  and still got shelved. The reason is the same one that made slopes a better bet than swinging — a
  grapple is a *traversal* system, so every level has to be designed around where you can hook. A
  spin is an *action with a radius*, so a level only has to care about what is standing near you.
  Spinning in **mid-air** gives you a little lift, as in Galaxy — enough to slow a fall or stretch a
  jump, never enough to cancel a long drop, because the character is heavy. Three lifts per chain,
  then a short lockout so it cannot be ridden upward for ever.
- **Carrying** — walk into something carryable and you are holding it, no button. A spin reaches
  further than your hands do and magnets things in from 5 m. Press the attack button while holding
  something to throw it.
- **Getting hit costs you money** — and the money lands on the floor where you lost it, so you can
  go back for it. Hollow Knight's answer rather than Sonic's: the loss is immediate and real but
  recoverable, which matters here because money is the *win condition* — a permanent loss could leave
  a level unfinishable. The cost is set **per threat**, so a walker takes a few coins and a boss takes
  a lot; that is what stops a rich player being immune to everything.

  Hearts and death are still here. This is deliberately the first stage of a bigger question — see
  below.
- **Transformations** — Wario Land's best idea: getting hit **changes** you, and the change is a
  penalty *and* a key.
  - **Flaming** — you sprint uncontrollably at 20 m/s and cannot steer. That is fast enough to smash
    through every speed-gated wall in the game, so catching fire is *how you get through them* — and
    because you cannot steer once alight, you have to line yourself up before you touch the fire.
    The penalty is the key.
  - **Puffy** — you float upward and cannot attack, reaching places you cannot jump to. `Ctrl` pops
    you early, which is the one real choice the state offers.

  **Health and death were kept, deliberately.** Wario Land II onwards paired transformations with
  immortality, and that is the series' most criticised decision — a boss that cannot threaten you can
  only inconvenience you, which is why Wario Land 4 bolted a timer onto its bosses. The two ideas are
  separable, so enemies split into **tools** (transform you, no damage) and **threats** (damage you,
  can kill you — including every boss). You keep your four hearts.
- **Breakable blocks** — three ways through a wall, and each one asks a different question. **Spin**
  it (and a block can demand the *super* spin, which gives the chain a reason beyond damage).
  **Pound** it from above, scaled by how far you fell. Or just **arrive fast** — above running pace
  and you go straight through, keeping most of your speed.

  That last one is the point: it is the first thing in the project that spends momentum on **access**
  rather than on distance. Before it, a ramp made you fast and that was the whole reward; now a ramp
  can be the only way through a wall. A block that refuses you still shakes, so "come back faster"
  is readable from one failed attempt.
- **Throwing** — a thrown object is not a lob, it is a **rocket**. Modelled on the Yoshi egg in
  Super Mario 64 DS: it picks the nearest enemy, sets off straight at it at 34 m/s, and steers to
  stay on it. You are not meant to aim well; you are meant to throw in roughly the right direction
  and watch it connect.

  If it misses, it **ricochets** — up to four surfaces, keeping most of its speed, and picking a
  fresh target after every bounce. That is what makes a miss interesting rather than a waste: the
  throw that sailed past comes back off the wall looking for someone else. Each bounce on the way
  also adds damage, so working the walls pays.

  It bursts at the end with a ring at its real radius, hurting everything in reach. Applies to
  anything throwable — a spin-magneted enemy and a keg you walked into use the same `ThrownFlight`
  component.

  Aiming is camera-driven with assist: the ringed target is whatever is nearest the centre of the
  screen, in range and in line of sight. Anchors win ties against enemies.

  Modelled on the Mario Galaxy spin-grab: an attack and a way
  of rearranging the level, not only a way of moving yourself.
- **Combat** — slam them, stomp them from above, or throw something at them.

Two moves have been cut as the game found its own shape: the **thrown fist** and the **helicopter**
(2026-09-29), the two most Rayman-specific moves in the set.

The grapple went through four versions and was then deleted outright, and the record is worth
keeping: a pendulum on the jump button (wrong kind of input), then a capped pendulum (the caps were
the bug, not the pendulum), then a pull-and-bounce (worked exactly as specified and was dull), then
an uncapped swing that was genuinely fun — and still got shelved, because an open-ended traversal
ability means every level has to be built around it. The **spin attack** replaced it on 2026-10-02.
The grab-and-throw half survived all five versions unchanged.

## Three scenes

**`scenes/playground.tscn` is where the current direction is.** A momentum playground built for one
question — does weight-and-momentum feel right? — and nothing else. A 12° ramp down into a plaza, a
30° ramp you cannot stand still on, a 12 m gap only crossable with ramp speed, and three crumbling
slabs bridging it that your own landing destroys. It contains **no grapple anchors**, on purpose: a
scene with every mechanic in it cannot answer a question about one of them.

**`scenes/tree_fort_main.tscn` is the first proper level** — a grassy plain with a three-level
bokoblin-style fort built around one tree, after the camps in Breath of the Wild. Climb it, loot it,
pay the exit to leave. Roughly half the decks crumble when you stand on them, and the exit wants 150
against 215 in chests, so you can leave one behind but only one.

**`scenes/main.tscn` is the original moveset showcase**, left untouched as a reference.

## Test level

The showcase level in `main.tscn`: one hub with four zones, each built around a mechanic:

| Direction | Zone | Teaches |
| --- | --- | --- |
| North | Rising platforms, then a gap (anchors removed) | Jumping, then a **long jump** across  |
| East | Pit spanned by a tan wall, then a shaft | **Wall kick** — ⚠️ see below |
| West | Three terraces with 3.3 m lips | **Ledge grab** (too high to jump onto) |
| South | A pit and a tower (anchors removed) | ⚠️ needs rebuilding, see below |

Tan surfaces are the climbable walls. Falling into a pit respawns you at the last checkpoint.

> ⚠️ **Two zones of this level are now stale, and both need rebuilding or deleting.**
>
> **East** was built around the wall *run*: its pit was meant to be crossed by running along the tan
> wall, and nothing crosses it now. The shaft above still works, because a shaft is what wall *kicks*
> are for.
>
> **North and South** were built around grapple anchors, which have been removed from this level with
> the grapple itself. South in particular was a chain of anchors over a pit and now has no route at
> all.
>
> `scenes/playground.tscn` is the level that matches the current moveset; this one is kept as a
> reference and as a stress test for the suite.

## Layout

```
scripts/
  game.gd              score, checkpoints, respawn
  events.gd            autoloaded signal bus (`Events`)
  player/              player.gd (state machine), abilities (spin + carry), camera, ledge sensor
  enemies/             walker, turret, bullet
  components/          health, thrown_flight (homing + ricochet for anything thrown)
  fx/                  shockwave ring, jump burst
  props/               coin, keg, checkpoint, hazard, crumbling floor, spin switch,
                       breakable block, treasure, level exit, transformer
  ui/                  hud.gd (hearts, money, F3 debug)
scenes/                one scene per script, plus the two levels
                       playground.tscn  momentum playground (current direction)
                       main.tscn        moveset showcase (reference)
tests/                 moveset smoke test
```

`player.gd` is a single enum + `match` state machine rather than a node tree, because these states
share a lot of velocity maths and constantly interrupt each other.

## Tuning

Every feel number is an `@export` on the player, grouped in the inspector (Run, Jump, Wall moves,
Ledge grab, Weight, Slam, Combat, Sounds; Jump has Jump chain and Crouch moves subgroups; the
Abilities child node owns Spin and Carry). Select the Player node and edit them there — no
code changes needed. Enemies, coins, kegs, chests and switches expose their own knobs the same way.

## Smoke test

After changing movement numbers, run:

```
"<godot>" --headless --path 3d-rayman-type-game res://tests/moveset_smoke_test.tscn
```

It drives the player through all 55 behaviours (each state, damage, death, respawn, stomp, grab
and throw, plus every Mario move, the spin and its combo, breakable blocks, slopes, crumbling floors, the homing throw) and prints a PASS/FAIL table. Exit code 0
means everything passed. It caught several real bugs during the initial build and is worth
rerunning whenever the controller changes.

## Not done yet

Deliberately left out, since this is a sandbox to grow rather than a finished game: animation
(the character is primitives, moved procedurally), swimming, any kind of menu or save
system, and level content beyond the test blockout.
