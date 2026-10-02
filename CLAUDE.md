# Working on this project

A 3D platformer in Godot **4.7.2**, GL Compatibility renderer. The Godot project lives in
`3d-rayman-type-game/` — one level down from the repo root.

## Who this is for

This is a **learning project**. The people working on it can program but are **new to Godot**.
That changes what "good code" means here:

- **Clarity beats cleverness.** A longer, obvious function is better than a compact one that needs
  a paragraph to explain.
- **Explain Godot, not programming.** Assume the reader knows what a loop and a class are. Do not
  assume they know what `_physics_process`, `move_and_slide`, a signal, an `Area3D`, or a scene
  instance is. When you use one in a non-obvious way, say what it does in a comment.
- **Don't add abstractions nobody asked for.** No manager singletons, no inheritance hierarchies,
  no plugin systems. If a feature needs one, propose it first rather than building it.
- **Prefer exported variables over constants.** Anything that affects game feel should be an
  `@export` so it can be tuned in the Inspector without touching code. This is the main way the
  team learns what each number does.

## Before you change gameplay code

Run the smoke test. It drives the player through every ability and prints a PASS/FAIL table:

```
"<godot-binary>" --headless --path 3d-rayman-type-game res://tests/moveset_smoke_test.tscn
```

Exit code 0 means everything passed. It has caught several real bugs that idle testing missed, so
treat a new FAIL as a genuine regression, not a flaky test. If you add an ability, add a check.

The Godot binary is not on PATH. On the original author's machine it is the Steam build at
`C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`
— note the Godot-3-style filename, and that it is a GUI binary, so stdout must be redirected to a
file to be read.

## Layout

```
3d-rayman-type-game/
  scripts/
    game.gd          score, checkpoints, respawning
    events.gd        autoloaded signal bus, referred to in code as `Events`
    components/      health, thrown_flight (drop-in Nodes, no matching scene)
    player/          player.gd (movement), abilities (spin + carry), camera, visuals, ledge sensor
    enemies/         walker, turret, bullet
    props/           lum, throwable keg, checkpoint, hazard, crumbling floor, spin switch
    ui/              hud.gd
  scenes/            mirrors scripts/ — one scene per script
                     main.tscn (moveset showcase) and playground.tscn (momentum)
  tests/             moveset smoke test
  tools/             make_placeholder_sounds.gd, make_uids.gd (--script safe)
```

Every script has a matching scene in the same relative path, *except* `scripts/components/` —
those are plain Nodes you add as a child of something else, so they have no scene of their own.
`scenes/main.tscn` is what runs.

## Things that will bite you

These are real traps already hit once in this codebase. Comments in the code explain each at the
site, but they are worth knowing up front:

- **`Input.is_action_just_pressed()` stays true for the whole frame.** If one function reacts to a
  press by changing state, and the new state's code runs later in the *same* frame, it sees that
  same press and can immediately undo the change. The old grapple needed a short lock-out timer
  because of exactly this; `spin_cooldown` plays the same role now.
- **Wall and floor contact is only known after `move_and_slide()`.** `is_on_wall()` and
  `is_on_floor()` are meaningless before it. That is why `player.gd` has a separate
  `_after_move()` step for entering wall states.
- **Landing on something zeroes your velocity before an `Area3D` reports the overlap.** Stomping an
  enemy cannot check `velocity.y` in the area callback. `Player.descent_speed()` exists to give the
  speed from *before* collision resolution.
- **A `RigidBody3D` ignores a velocity set on the frame it unfreezes.** Thrown objects need the
  impulse applied deferred, or they just drop limply.
- **Tweening a node's `scale` to exactly zero** produces a singular transform and spams
  `Condition "det == 0" is true` errors. Shrink to `Vector3.ONE * 0.01` instead.
- **Sleeping `RigidBody3D`s are unreliable in `Area3D` overlap queries.** Grabbing a resting keg
  walks the `throwable` group by distance rather than using an area.
- **`--script` mode has no autoloads.** Running `--headless --script foo.gd` does *not* register
  `Events`, so every script mentioning it fails to compile, its node loads with a null script, and
  all its exported values read back as null — which looks exactly like broken data. Write throwaway
  checks as a tiny `.tscn` + script and run the scene instead. Only use `--script` for tools that
  touch no game code (see `tools/make_placeholder_sounds.gd`).
- **Freeing a node stops any sound it is playing.** A pickup that calls `queue_free()` immediately
  is silent. `lum.gd` and the enemies `await` the sound before freeing.
- **Every `.tscn` needs a `uid="uid://..."` in its `[gd_scene]` header.** The editor adds one
  automatically; a scene written as text by hand does not have one, and then references to it fall
  back to matching by file path. That logs `invalid UID ... using text path instead` in anyone
  else's scene that points at it, and the reference breaks outright if the file is ever moved.
  `ext_resource` lines should carry their target's `uid=` too. Generate a batch of them with
  `tools/make_uids.gd` (`--headless --script res://tools/make_uids.gd`), or inline with
  `ResourceUID.id_to_text(ResourceUID.create_id())`. Note the UID for a **script** is generated by
  Godot on import, into a `.gd.uid` file next to it — do not invent those, run `--import` and read
  the file.
- **`floor_snap_length` defaults to 0.1 m, which is too small for a fast slope.** Moving downhill,
  `move_and_slide()` travels in a straight line and the surface falls away underneath, so the body
  leaves the floor, `is_on_floor()` goes false, and anything keyed off standing on the ground stops
  happening. At 20 m/s on a 30° slope the per-frame drop is about 0.24 m, so with the default the
  player flickers between grounded and airborne all the way down. It cost the steep ramp half its
  speed (10.5 m/s where it should have reached 18) and looked exactly like the slope maths being
  wrong. It is set to **0.6** on the Player in `player.tscn`.
- **Godot serialises a `Transform3D` basis ROW by row in a `.tscn`.** Those nine numbers before the
  origin are rows, not the x/y/z axis columns. Read them as columns and you build a ramp tilted the
  wrong way — which is what happened to both ramps in the momentum playground on the first attempt,
  and it is invisible until you probe the surface normals. If you hand-write a rotation, verify it
  by raycasting onto the surface rather than by eye.
- **Deleting a scene leaves the UID cache stale.** After removing a `.tscn`, unrelated scenes start
  logging `invalid UID ... using text path instead` even though their headers are fine. It is the
  cache, not your files — delete `.godot/` and re-run `--import` before believing the warning.

## Conventions

- Static types on everything: `var speed: float = 5.0`, `func move(delta: float) -> void:`.
- `snake_case` for variables and functions, `PascalCase` for classes and node names.
- A leading underscore (`_thing`) means "internal to this script" — it is a convention, not
  enforced by the language.
- Use `@onready var thing: Type = $NodeName` for child node references.
- Use signals to talk *between* systems (`Events.lum_collected.emit(1)`), and direct calls
  *within* one.
- Levels are CSG boxes (`CSGBox3D`) so they can be reshaped by dragging in the editor. Keep it
  that way until there is real art.

## Scope

The renderer is deliberately **GL Compatibility**, not Forward+. Do not switch it without asking.

Not built yet, on purpose: animation (the character is primitives moved by code), swimming,
menus, saving. Ask before starting any of these.

## The spin attack

**Added 2026-10-02, and it replaced the whole grapple.** `attack` (F / LMB / gamepad X) does one of
two things depending on what you are holding:

- **holding nothing** → spin. Hurts enemies in a radius, drags carryables to you, trips switches,
  and chains into a bigger spin if repeated.
- **holding something** → throw it.

It lives in `player_abilities.gd` and is **not a `State`** — you can spin while running, jumping or
falling, as in Mario Galaxy. If you find yourself wanting to add `State.SPIN`, that is a sign
something is wrong: the spin does not change how the player moves.

**Why it was a better bet than the grapple**, and the reason worth keeping: a grapple is a
*traversal* system, so every level has to be designed around where you can and cannot hook. A spin
is an *action with a radius*, so a level only has to care about what is standing near the player.
Same argument as slopes-over-swinging in the weight section.

### The `spinnable` group is the extension point

Anything that should react to a spin does exactly two things:

1. joins the `spinnable` group
2. implements `spin_hit(by)`

`PlayerAbilities._trip_switches` walks the group by distance and calls the method. The prop holds no
reference to the player and the player has no idea the prop exists. `spin_switch.gd` is the first
user and is deliberately tiny — copy it. This is what "a variety of other interactions" means in
practice, and it needs no changes in `player_abilities.gd` ever.

### Three things that are the way they are for a reason

- **Hits are resolved by walking groups, not with an `Area3D`.** An area added and queried in the
  same frame reports nothing, and a spin has to land the instant it is pressed. The ground pound's
  shockwave does the same. For `throwable` there is a second reason: a keg at rest is a *sleeping*
  `RigidBody3D`, and sleeping bodies are unreliable in overlap queries.
- **The third spin ends the chain** rather than wrapping to the first, so the big one is always the
  pay-off for three presses and never a lucky accident in the middle of a longer string.
- **`regrab_delay` exists because of auto-carry.** Walking into a carryable picks it up with no
  button, so without a blind spell after a throw the object you just threw is instantly re-collected
  while it is still a metre away, and the throw looks like it did nothing.

### The grapple's remains

The grapple is gone from the player: no `State.SWING`, no tongue, no aim-assist, no rope, no HUD
reticle. `grapple_targeting.gd` and `rope_line.gd` are deleted.

**`grapple_point.gd` and its scene are still on disk, deliberately.** Ian's `scene_smilex.tscn`
instances six of them under a `LevelGrappleHooks` node, including an animated one, so deleting the
scene would break his level. The script is marked deprecated at the top. **This needs a conversation
with Ian, not a unilateral delete.** The anchors in `test_level.tscn` were removed, since that level
is ours.

## Thrown objects

A throw is a **rocket, not a lob** (Yoshi egg, Super Mario 64 DS). `ThrownFlight`
(`scripts/components/thrown_flight.gd`) is a drop-in child Node that owns the whole flight; both
the walker and the keg add one and just react to its `exploded` signal. Four things in it look like
arbitrary choices and are actually requirements:

- **It moves the parent itself, by raycast and `global_position`.** Neither normal option works:
  `move_and_slide()` *stops* at a wall and slides along it, which is the opposite of a ricochet, and
  a `RigidBody3D`'s solver fights a constant-speed steer. So the keg stays **frozen for its whole
  flight** and the walker's own `_physics_process` returns early while `_thrown`. If a thrown object
  ever stutters or sinks into the floor, something re-enabled its normal movement.
- **A constant turn rate cannot hit anything.** Turn radius is `speed / turn_rate` — about 6 m at
  the defaults — and a projectile physically *orbits* any target inside that radius until it times
  out and bursts several metres away. That reads as the homing being broken, not as a near miss.
  `home_tighten_range` is the fix: scale the turn rate up as the gap closes.
- **Steering alone cannot aim the throw.** A 90° turn takes about a sixth of a second, by which
  time the object has gone ten metres the wrong way. `home_launch_snap` swings the direction onto
  the target *before* it has travelled at all, which is what makes the throw read as a shot.
- **After a bounce, stand the body off the surface by its own radius.** Otherwise next frame's ray
  starts inside the wall and reflects straight back into it — the projectile sticks and buzzes
  against the surface instead of leaving it.

Two more that bite in the *test*, not in the game:

- **A thrown walker frees itself when it bursts**, taking its `Flight` child with it. Read anything
  off that node afterwards and you get `Invalid access ... on a base object of type 'previously
  freed'`. Record what you need from the `exploded` signal as it happens instead.
- **Homing throws kill things all over the level**, so no enemy placed in a scene can be assumed
  alive later in the suite. The stomp check used to read `HubWalkerA` and began reporting "walker
  missing" the moment throws started homing; it now spawns its own walker. Note the hub plaza is
  only 30x30 centred on the origin (x and z from -15 to 15, top face at y=0) — spawn a test object
  outside that and it drops into the pit, and the check then fails for a reason that has nothing to
  do with what it is testing.

### The lesson from the grapple, worth more than any of its three versions

The grapple was a pendulum on the jump button (wrong input), then a pendulum with five caps (the
caps were the bug), then a pull-and-bounce (worked exactly as specified and was dull), then an
uncapped swing (fun, and shelved for scope), and finally deleted in favour of the spin. When a feel
complaint
survives two or three rounds of tuning, stop tuning. Ask instead whether the ability is on the right
*kind* of input (sustained vs impulse, held vs tapped) and whether the thing being "smoothed" is the
thing that made it fun. Both times the swing was fixed by taking something away, never by adding a
number. And when a mechanic survives four rewrites without settling, question whether it belongs
in the game at all — that is what finally resolved it.

## Weight and momentum

**The current direction, as of 2026-10-02.** The character is heavy, and the game is about building
momentum and spending it. The grapple is gone (see **The spin attack**) — not because it worked
badly, but because an uncapped traversal ability is an open-ended design commitment, and every level
then has to be built around it.

**So momentum lives in the LEVEL, not in an ability.** A slope is content. A level has momentum where
you put a ramp in it, and a level with no ramps has none, so each level sets its own pace. That is
the whole reason this is a better bet than the grapple was, and it is worth protecting: be suspicious
of any proposal that makes speed something the player can summon anywhere.

Three pieces, all in `player.gd`:

- **`_slope_pull()`** is the engine. Gravity projected onto the floor plane, which comes out as
  `g * sin(angle)` straight downhill and exactly zero on flat ground. No per-slope tuning.
- **Commitment is the cost.** `acceleration`, `deceleration`, `turn_acceleration` and `air_control`
  were dropped from 65 / 75 / 110 / 0.45 to **14 / 12 / 18 / 0.15**. Weight is only a trade if it
  costs you something, and what it costs is the ability to change your mind. Treat those four as one
  decision, not four.
- **`momentum_friction` (3.5) is the only place momentum decays**, and it never takes you below
  `max_speed`, so ordinary running is untouched.

Two thresholds fall out of `slope_gravity` (30) rather than needing settings of their own, and the
playground's two ramps are chosen either side of them:

| | |
| --- | --- |
| steeper than ~**7°** | beats `momentum_friction`, so speed above `max_speed` keeps growing |
| steeper than ~**27°** | beats `deceleration`, so you slide down even standing still |

Measured, on the playground's ramps, starting at 9 m/s: **12° takes you to 16.6 m/s, 30° to 17.7,
flat bleeds you back to 7.5, and uphill eats all 9 m/s in under 3 metres.**

**`max_speed` (7.5) is not a speed limit.** It is the top speed *the stick alone* will reach, and the
floor that `momentum_friction` bleeds down to. Slopes and long jumps take you far past it. Anything
that clamps total speed to it is a bug.

**Weight has to be a liability somewhere**, or it stops being a constraint and turns into a stat.
`crumbling_floor.gd` is the first piece of that: a slab a heavy landing destroys under you. It
listens to `Events.slam_landed(at, force)`, which is the intended way for a prop to react to a slam —
the prop holds no reference to the player and the player does not know props exist.

## The Mario moveset

**Added 2026-10-02.** The moveset is Mario 64 / Odyssey shaped: double and triple jump, side flip,
backflip, long jump, forward slide, ground pound, wall kick. Two things were removed to make room,
both deliberately:

- **The bounce attack.** The old slam threw you back up to jump height, with every third one in a
  chain going 50% higher. It needed the jump button in mid-air, which the double and triple jump now
  own. The fall-distance scaling and the shockwave ring were kept; the bounce and the combo are gone.
- **The wall run.** A good Rayman move and a bad Mario one. With both in, the same wall would
  sometimes carry you sideways and sometimes catch you, decided by a speed threshold the player could
  not see. A wall now always catches you and always offers a kick.

**One button, four moves.** `crouch` (Ctrl) forks on what you were doing, which is how Mario 64 gets
so much out of Z: still → backflip, at a run → slide, slide-or-run then jump → long jump, in mid-air
→ ground pound. If you add a fifth crouch move, add it to that fork rather than to a new button.

### The tension to keep naming

**Mario's moveset assumes Mario is agile; this character is deliberately heavy.** The user was told
this and chose to keep it heavy, so the resolution is: **the moveset is where the agility lives.**
Base handling stays committal (`acceleration` 14, `air_control` 0.15) and each Mario move buys one
specific kind of motion you cannot get by steering. That is consistent with weight being a trade you
control — but it means the moves have to carry more weight than they do in Mario, so be suspicious of
any of them being made weaker "for balance".

Two consequences already baked in, and both will look wrong if you don't know why:

- **The side flip triggers on the INPUT reversing, not the velocity reversing** (`_wants_side_flip`).
  Heavy handling will not let velocity turn round quickly by design, so waiting for it would mean the
  move never fires at all.
- **The long jump ADDS its push to the speed you already had** rather than replacing it. So a long
  jump out of a fast slide down a ramp goes much further than one off the flat. That is the one place
  the Mario moveset and the slope system reinforce each other, and it is worth protecting.

### `slide_friction` has to beat the wrong number

A slide feels like nothing if you tune it against `deceleration` (12). What it actually has to beat
is **`momentum_friction` (3.5)**, because that already preserves ground momentum above `max_speed` —
so the ordinary run is far less draggy than it looks. `slide_friction` started at 2.0 and measured a
0.7 m/s advantage over just running, which is invisible. It is **1.0**.

## The ground pound

Still called `SLAM` throughout the code — same move, and renaming eleven exports would have been
churn for nothing.

- **Fall distance is the currency.** Damage, shockwave radius and the *visible ring* all scale with
  how far you fell, measured from the highest point since last grounded (`Player.slam_power()`).
  A hop is worth ~0.08, a tower drop 1.00. This is the part of the old bounce attack worth keeping,
  because it is what carried the weight-is-a-resource idea.
- **It does not bounce, and it does not combo.** Both went with the Mario moveset; see above.
- **A pound clears `jump_chain` and eats `_jump_buffered`.** Otherwise a jump held on the way down
  fires the instant you land and cancels the recovery, and pounding then jumping would hand you a
  free double jump — the chain is supposed to be earned by landing three jumps cleanly.
- **It lands in `CROUCH`, not `GROUND`,** and `_slam_recover` locks you there briefly. A pound you
  can cancel straight out of reads weightless.
- **The shockwave ring is not additive.** The palette is bright pastel and additive blending
  saturates straight to white, throwing away the colour the ring is drawn in.

### Testing input in the smoke test

`Input.action_press()` on **every** frame never produces a fresh `just_pressed` — holding across
frame boundaries registers nothing at all, so the move simply never fires and the test looks like a
gameplay bug. Press **once**, wait, then release. And `_place()` resets the timers (`_coyote`,
`_jump_buffered`, `jump_chain`, `_chain_window`, `_slam_recover`) for the same reason: leftover
state from a previous check turns the next press into a different move entirely.
