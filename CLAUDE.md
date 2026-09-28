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
    player/          player.gd (the big one), camera, grapple targeting, fist
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

Not built yet, on purpose: animation (the character is primitives moved by code), audio, swimming,
menus, saving. Ask before starting any of these.
