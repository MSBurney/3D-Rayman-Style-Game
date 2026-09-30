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
    player/          player.gd (movement), abilities, camera, grapple targeting, ledge sensor
    enemies/         walker, turret, bullet
    props/           lum, grapple point, throwable keg, checkpoint, hazard
    ui/              hud.gd
  scenes/            mirrors scripts/ — one scene per script
  tests/             moveset smoke test
```

Every script has a matching scene in the same relative path. `scenes/main.tscn` is what runs.

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
  `ext_resource` lines should carry their target's `uid=` too. Generate one with
  `ResourceUID.id_to_text(ResourceUID.create_id())`.
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

## Swing geometry

**The rule that matters most: inside a swing, use forces, not clamps.** Every hard clamp on
`velocity` is a discontinuity the player feels. An earlier version had five stacked in one
function — a spring, an outward-velocity cancel, drag, an apex clamp and a speed clamp — each
overriding the last, and it buzzed. Every one of them is now either a force that fades in, or the
single exact constraint below. If a swing ever feels rough again, look for a clamp before you look
for a number to tune.

Four constraints on the MOMENTUM swing that look arbitrary until you hit the bug they prevent:

- **The rope is capped by the anchor's clearance above the ground** (`_usable_rope`). A pendulum
  started level with its anchor swings down through almost a *full rope length* before the rope
  catches. So a rope longer than the anchor's height simply lands you, ending the swing the instant
  it starts. This is the single most confusing failure the swing can have.
- **The rope is enforced as an exact position correction, after the move, not as a spring before
  it** (`_constrain_to_rope`, called from `_after_move`). `move_and_slide()` travels in a straight
  line but a swing is an arc, so the body drifts off the circle every frame. A spring applied
  *before* the move is always a frame behind: drift out, get yanked back, drift out again — a 60 Hz
  buzz that gets worse the faster you go. Correcting the position afterwards makes the radius exact
  and there is nothing left to yank.
- **Only the rope's *length* changes over time, never its enforcement.** It starts at the distance
  you hooked from and tightens at `swing_reel_speed`, so the radius is continuous. There was once a
  separate reel-in phase routed through GRAPPLE_DIVE; it was removed because handing a
  straight-line dive over to an arc dumped all the inbound speed at a fixed radius, which read as
  slamming into a wall partway to the anchor.
- **A speed cap (`swing_max_speed`) holds the pace.** A pendulum with a pump input winds itself up
  without limit. This is the main dial for how fast the whole game feels.
- **The apex brakes, it does not clamp.** Upward speed is bled off over `swing_apex_band` below the
  anchor so the arc stalls and reverses on its own. Clamping to zero at the ceiling instead stops
  the player dead, which reads as an invisible shelf. The smoke test asserts the worst single-frame
  change stays under what gravity alone would do.

## Check which grapple style you are actually playing

`grapple_style` is an `@export` on the Player, so flipping it in the Inspector and saving the scene
writes `grapple_style = 1` into `scenes/main.tscn`. That has already happened once and cost a whole
round of debugging: an entire play session was spent judging "the momentum grapple" while actually
playing HOMING, where anchors are dives that stop you dead and no swinging happens at all.

Two ways to tell at a glance before reporting how a swing feels:

- **F3** shows a `style` line.
- **Reticle colour**: purple over an anchor means MOMENTUM, orange means HOMING. Red is an enemy.

The smoke test now sets the style explicitly for the same reason — otherwise every swing check
silently tests whatever the scene was last saved with.
