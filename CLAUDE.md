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
    player/          player.gd (movement), abilities, camera, grapple targeting, ledge sensor
    enemies/         walker, turret, bullet
    props/           lum, grapple point, throwable keg, checkpoint, hazard, crumbling floor
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
  same press and can immediately undo the change. The grapple needed a short lock-out timer
  (`grapple_repress_delay`) because of exactly this.
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

## The tongue

The grapple is a **Yoshi-style tongue**: an attack and a way of moving things, not a way of moving
yourself. One button, and what happens depends on whether the target can be moved:

- **Anchor** (fixed to the level) — the player **swings** from it. `State.SWING` in `player.gd`.
- **Enemy** (not fixed) — it is pulled to the player and ends up carried. `PlayerAbilities.tongue_grab`.
  Press the button again to throw it. See **Thrown objects** below for what a throw does.
- **Target with no `pick_up()`** (a turret, bolted down) — lashed for damage instead, so such
  enemies stay killable rather than being immune.

A grabbed enemy exposes the same `pick_up()` / `throw()` pair the throwable keg does, so the carry
code treats it like any other held object and knows nothing about enemies.

## The swing: do not cap it

**Read this before touching `_do_swing`.** The swing has been built three times and cut twice, and
both times it was cut for the same reason dressed differently:

1. **A pendulum on the jump button.** Wrong *kind* of input — a pendulum is sustained momentum
   management, a jump is one impulse. Several rounds went into smoothing feel before anyone noticed
   the ability was simply bound to the wrong button.
2. **A pendulum with five caps in one function** — a speed limit, an apex clamp, drag, an
   outward-velocity cancel and a spring. Each was added to answer a feel complaint, and together
   they removed the only reason to use a swing.

The author's own diagnosis, and it is the one to keep: *"the fun part WAS the ability to mess with
the physics of the grapple and exploiting it to make high jumps and far jumps — removing all of
that with the caps killed the fun of the mechanic."*

So: **nothing in the swing caps speed.** Not the pump, not gravity, not the release, not the top of
the arc. Four places enforce that, and each will look like an oversight until you know why:

- **`swing_gravity` is its own number and does not go through `_apply_gravity()`.** That helper
  softens gravity near the apex and clamps the fall to `max_fall_speed`. Both are caps.
- **`_apply_horizontal` takes a `keep_momentum` flag, and `_do_air` passes it.** Normally it steers
  speed *toward* `max_speed`, which brakes as readily as it accelerates — so a 22 m/s release decayed
  back to walking pace in about half a second. Above `max_speed` the stick may now redirect momentum
  but never brake it. **This one is easy to reintroduce by accident**, because it does not live in
  the swing at all.
- **The swing-jump sets `_jumping = false`.** A normal jump is cut short when you release the
  button, and you *have* to release the button to let go of the rope — so a cuttable swing-jump
  halved itself every single time.
- **The slack-rope push is added acceleration, never `move_toward(max_speed)`.** Same cap wearing a
  disguise.

Three geometry rules that look arbitrary until you hit the bug they prevent:

- **The rope is an exact position correction applied AFTER the move** (`_constrain_to_rope`, called
  from `_after_move`), not a spring applied before it. `move_and_slide()` travels in a straight line
  but a swing is an arc, so the body drifts off the circle every frame. A spring before the move is
  always a frame behind: drift out, get yanked back, drift out again — a 60 Hz buzz that gets worse
  the faster you go, and that buzz was most of why version two felt rough. The smoke test asserts
  the radius error stays under 0.15 m; it currently measures 0.002 m.
- **The rope is ONE-SIDED.** It pulls, it never pushes: closer to the anchor than the rope is long
  and it does nothing at all. That is what lets you swing over the top of the anchor and loop around
  it. Being pinned below the anchor was half of what made the old swing feel like a cage.
- **The constraint removes only the OUTWARD velocity**, never speed in general. A rope cannot
  stretch, so the component along it goes to zero and everything along the arc is untouched — so the
  constraint itself takes no energy out of the swing.

**Only the rope's *length* changes over time, never its enforcement**, which is what keeps the
radius continuous. It starts at the distance you hooked from and is then the player's to change with
`grab` / `drop`. Reeling in while moving fast is the main exploit on offer: the same angular rate on
a shorter rope is a faster one. Reel all the way in and you arrive at the anchor and bounce off it,
at *at least* `jump_height` — same rule as the slam's rebound, **no ability should quietly cost you
altitude.** An earlier version gave a flat 6 m/s kick, less than a jump, so arriving set you down
lower than you started.

Note `grab` doubles as reel-in, so `player.gd` passes `allow_grab = false` to
`PlayerAbilities.handle_input` while swinging — otherwise reeling also tries to pick up every keg
you pass.

**There is no cap on rope length relative to the anchor's height above the ground, on purpose.**
That means hooking an anchor level with you swings you down into the floor. The old code capped it
and that cap is gone with the rest. The answer is level design — put anchors *high*, over the gap
they are meant to cross — and the reel.

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

**The lesson from the two cut versions**, worth more than the mechanic itself: when a feel complaint
survives two or three rounds of tuning, stop tuning. Ask instead whether the ability is on the right
*kind* of input (sustained vs impulse, held vs tapped) and whether the thing being "smoothed" is the
thing that made it fun. Both times the swing was fixed by taking something away, never by adding a
number.

## Weight and momentum

**The current direction, as of 2026-10-02.** The character is heavy, and the game is about building
momentum and spending it. The swing is shelved (see above) — not because it worked badly in the end,
but because an uncapped traversal ability is an open-ended design commitment, and every level then
has to be built around it.

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
floor that `momentum_friction` bleeds down to. Slopes and swings take you far past it. Anything that
clamps total speed to it is a bug — see the cap list in the swing section, which applies here too.

**Weight has to be a liability somewhere**, or it stops being a constraint and turns into a stat.
`crumbling_floor.gd` is the first piece of that: a slab a heavy landing destroys under you. It
listens to `Events.slam_landed(at, force)`, which is the intended way for a prop to react to a slam —
the prop holds no reference to the player and the player does not know props exist.

## Slam and combo

- **Fall distance is the currency.** Damage, shockwave radius and the *visible ring* all scale with
  how far you fell, measured from the highest point since last grounded (`Player.slam_power()`).
  A hop is worth ~0.08, a tower drop 1.00.
- **The rebound is fixed at jump height, not scaled.** Letting fall distance drive the bounce too
  made one blurry reward; separating them keeps both legible. Height is gained from the combo.
- **Every third slam in an unbroken chain** bounces 50% higher with a wider, red shockwave.
  Touching the ground without slamming resets the count, in `_enter_state(State.GROUND)`.
- **A slam impact clears `_coyote`.** The landing touches the floor for a frame, which refills the
  coyote window, and a press in the next tenth of a second would then read as a late ground jump
  rather than the next slam — silently breaking every chain.
- **The shockwave ring is not additive.** The palette is bright pastel and additive blending
  saturates straight to white, throwing away the colour that distinguishes a combo hit.

### Testing input in the smoke test

`Input.action_press()` on **every** frame never produces a fresh `just_pressed` — holding across
frame boundaries registers nothing at all, so the move simply never fires and the test looks like a
gameplay bug. Press **once**, wait, then release. And `_place()` resets the timers (`_coyote`,
`_jump_buffered`, `slam_combo`) for the same reason: leftover state from a previous check turns the
next press into a different move entirely.
