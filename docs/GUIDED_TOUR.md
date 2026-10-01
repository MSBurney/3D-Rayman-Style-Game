# Guided tour

For developers who can already program but are **new to Godot**. Work through it in order; each
section is a small change you actually make, not just something to read. Budget an hour or two.

You will need the project open in **Godot 4.7**: open `3d-rayman-type-game/project.godot`.

---

## 0. Run it first

Press **F5**. You should be standing on a green plaza with two red enemies wandering nearby.

Fly around for five minutes before reading any code. Try to reach all four zones:

- **North** — hop the platforms, then dive across the gap using the two floating rings.
- **East** — sprint at the tan wall and keep going; you should run along it.
- **West** — jump at the tall pink terraces and you will grab the lip. Press jump again to climb up.
- **South** — a pit with floating rings over it. **Hold Q** (or right-click) to hook one and swing
  across. Hold a direction to pump the arc, `E` to reel the rope in, `Space` to launch off it.

Press **F3** for a live readout of your state, speed and current grapple target. Leave it on — it
is the single most useful thing for understanding what the code is doing.

---

## 1. Godot in five minutes

Enough to read this project. Four ideas:

**Nodes** are the building blocks — a mesh, a light, a collision shape, a plain container. Every
node has a type that decides what it can do, and they form a tree.

**Scenes** are a saved tree of nodes (a `.tscn` file). The player is a scene. So is a lum. A scene
can be *instanced* inside another scene, which is how the level contains 30 lums without 30 copies
of the work. Change `lum.tscn` and every lum in the game changes. Roughly: a scene is a class, an
instance is an object.

**Scripts** attach to a node and extend it. `extends CharacterBody3D` at the top of `player.gd`
means "this script IS a CharacterBody3D, plus what I add." So `velocity` and `move_and_slide()`
are available without declaring them — they come from the parent type.

**Signals** are Godot's events. A node shouts `died` without caring who listens; other code
connects to it. This keeps systems from having to know about each other.

Two functions run every frame, and mixing them up causes real bugs:

| | runs | use for |
| --- | --- | --- |
| `_process(delta)` | once per drawn frame, varies with FPS | visuals, UI |
| `_physics_process(delta)` | fixed 60x a second | movement, physics, anything with `velocity` |

`delta` is the seconds elapsed. Multiplying speeds by it is what makes movement run the same on a
fast and a slow machine.

---

## 2. Change a number (5 minutes)

The fastest way to understand a system is to break it.

1. In the **Scene** panel, click the `Player` node.
2. Look at the **Inspector** on the right. Everything is grouped: Run, Jump, Wall moves,
   Ledge grab, Grapple, Combat, Sounds.
3. Open **Jump** and set `Jump Height` to `6`.
4. Press F5 and jump.

You did not touch any code. Those groups exist because of `@export` in `player.gd`:

```gdscript
@export_group("Jump")
@export var jump_height: float = 2.35
```

`@export` publishes a variable to the Inspector. This is the main way to tune game feel, and the
main way to learn what each number does. **Go and break several of them.** Suggestions:

| Try | In group | What you should notice |
| --- | --- | --- |
| `Tongue Reel Speed` → `4` | Abilities node | Watch an enemy get dragged in slowly — the tongue is easiest to understand at low speed |
| `Swing Pump Accel` → `80` | Grapple > Swing | Hold a direction while swinging and you wind up absurdly fast. Nothing stops you, which is the point |
| `Swing Reel Speed` → `3` | Grapple > Swing | Makes it obvious what `E` and `Ctrl` do to the rope |
| `Air Control` → `0.0` | Run | You cannot steer at all mid-jump; feels awful, and shows why it exists |
| `Coyote Time` → `0.0` | Jump | Jumps off ledges start failing. This is the forgiveness you never notice until it is gone |
| `Max Speed` → `20` | Run | Fast, but you overshoot every platform |
| `Home Turn Rate` → `1.5` | `Flight` node inside `enemy_walker.tscn` | Grab an enemy, throw it, and watch the throw curve lazily past its victim and orbit it. That is the bug `Home Tighten Range` exists to stop — see the comment on it |
| `Max Bounces` → `12` | same `Flight` node | Throw into an empty corner and watch it work the walls for ages |

Set them back afterwards (or just don't save the scene).

---

## 3. Follow one lum from pickup to screen (15 minutes)

This teaches how the project's parts talk. Open three files side by side:

**`scripts/props/lum.gd`** — the collectible. It is an `Area3D`, a node that detects overlaps
without blocking anything. In `_ready()` it connects the built-in `body_entered` signal:

```gdscript
body_entered.connect(_on_body_entered)
```

When the player walks in, `_on_body_entered` runs and does the important line:

```gdscript
Events.lum_collected.emit(value)
```

It does not know the score exists. It just announces what happened.

**`scripts/events.gd`** — a list of signals and nothing else. It is an *autoload*: registered in
Project Settings, so it exists everywhere as `Events` with no setup. It is a noticeboard.

**`scripts/game.gd`** — subscribes in `_ready()`, keeps the running total, and re-announces it:

```gdscript
Events.lum_collected.connect(_on_lum_collected)
```

**`scripts/ui/hud.gd`** — listens for the total and updates the label.

So the chain is: **lum → Events → game → Events → HUD.** Four files, none of which holds a direct
reference to another. That is the point: you can rewrite the HUD without opening `lum.gd`.

> **Try it:** make lums worth 5. You could edit `lum.gd`, but you don't have to — select a lum in
> the level and change its `Value` in the Inspector. Only that lum changes. That is per-instance
> override, and it is a big part of why Godot scenes are useful.

---

## 4. Read one ability (20 minutes)

Open `scripts/player/player.gd` and read the header comment. Then find `_do_swing()`.

Do **not** read the whole file. The structure exists so you don't have to: one `_do_<state>()`
function per thing the player can be doing, and `_physics_process` picks which one runs:

```gdscript
match state:
    State.GROUND: _do_ground(delta)
    State.AIR: _do_air(delta)
    State.SWING: _do_swing(delta)
    ...
```

`_do_swing()` has that shape every state function has — **move, then check whether we should be in
a different state.** It is also the most commented function in the project, because almost
everything in it is there to stop someone helpfully adding a limit back. Read the comment block at
the top before the code: the swing has been built three times, and twice it was cut because a feel
complaint got answered with a cap.

Then read `_constrain_to_rope()`, which is where the actual rope lives. Three things to notice:

1. It runs from `_after_move()`, not from the state function. `move_and_slide()` travels in a
   straight line and a swing is an arc, so the body drifts off the circle every frame and is put
   back afterwards. Doing it the obvious way — a spring applied *before* the move — is always a
   frame behind and buzzes at 60 Hz.
2. It is **one-sided**: closer to the anchor than the rope is long and it does nothing. A rope pulls,
   it does not push. That one `if` is what lets you loop over the top of the anchor.
3. It removes only the velocity pointing *along* the rope, never speed in general.

> **Try it:** hold `Q` on a purple anchor from somewhere high, do nothing else, and watch the
> `speed` line on the F3 readout. A free drop through the arc reaches about 22 m/s — `Max Speed`,
> the number that governs running, is 7.5. Then let go at the bottom and see that you keep it.

Two things in this file are worth understanding because they bite everyone:

**Order matters.** `is_on_floor()` and `is_on_wall()` only mean anything *after*
`move_and_slide()` — before it, they describe last frame. That is why wall-running is entered in
`_after_move()`, not inside a state function.

**A button press lasts a whole frame.** `Input.is_action_just_pressed()` stays true for every
check within the same frame. If one function reacts to a press by changing state, and the new
state runs *later in the same frame*, it sees the same press and can undo the change immediately.
The grapple needed `grapple_repress_delay` for exactly this: the press that fired the tongue was
still "just pressed" when the tongue code ran, so it cancelled itself.

> **Try it:** find a walker and press `Q` at it, then press `Q` again to throw it. Then aim at a
> purple anchor and press `Q`. Same button, opposite outcomes — you move, or the target moves.
> Read `_try_grapple()` in `player.gd` to see where that fork is made, and `tongue_grab()` in
> `player_abilities.gd` for the half that drags enemies.
>
> **Then try throwing badly on purpose.** Grab a walker, turn away from everything, and throw. The
> object picks its own victim and rockets at it; if there is nothing to chase it ricochets off the
> walls a few times and bursts. That is `scripts/components/thrown_flight.gd`, and it is a good
> example of a **component**: a plain `Node` you add as a child of something to give it a
> behaviour. The keg and the walker both have one, and neither script knows the other exists.

---

## 5. Make something new (30 minutes)

Build a **bounce pad** that launches the player upward. It is the smallest change that touches
scenes, scripts, signals and physics at once.

1. **New scene** → `Node3D` as root → rename it `BouncePad` → save as
   `scenes/props/bounce_pad.tscn`.
2. Add a child **`Area3D`**, and give *that* a child **`CollisionShape3D`**. In the Inspector set
   its Shape to a new **BoxShape3D**, size roughly `(3, 0.5, 3)`.
3. Add a **`MeshInstance3D`** so you can see it — a **BoxMesh** of the same size.
4. Select the `Area3D` and set **Collision → Mask** so only layer **2** (`player`) is ticked. Layers
   are how Godot decides what notices what; the names are set in Project Settings.
5. Attach a script to the root, `scripts/props/bounce_pad.gd`:

```gdscript
extends Node3D

## Launches the player upward on contact.

@export var bounce_force: float = 16.0

func _ready() -> void:
	# $Area3D is shorthand for get_node("Area3D").
	$Area3D.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# `as Player` gives null if it was not the player, so this is both a type
	# check and a cast. Enemies and thrown kegs hit this too — ignore them.
	var player := body as Player
	if player == null:
		return
	player.bounce(bounce_force)
```

6. Open `scenes/levels/test_level.tscn`, drag `bounce_pad.tscn` from the FileSystem panel into the
   viewport, and position it on the plaza.
7. Press F5 and jump on it.

`bounce()` already existed — it is what enemies call when you stomp them. Reusing it is why this
script is nine lines. **Before writing new behaviour, check whether the player already exposes it.**

---

## 6. Don't break the moveset

There is an automated test that drives the player through every ability and prints a PASS/FAIL
table. Run it after changing anything in `player.gd`:

```
"<path-to-godot>" --headless --path 3d-rayman-type-game res://tests/moveset_smoke_test.tscn
```

42 checks, a few seconds. It has already caught several bugs that looked fine in play, including
the grapple problem above. If you add an ability, add a check for it in
`tests/moveset_smoke_test.gd` — copy an existing one, they are all the same shape.

---

## 7. Where things live

```
scripts/
  game.gd          score, checkpoints, respawning
  events.gd        the signal noticeboard (autoloaded as `Events`)
  player/          player.gd, camera, grapple targeting, ledge sensor, abilities
  enemies/         walker, turret, bullet
  props/           lum, grapple point, keg, checkpoint, hazard
  ui/              hud.gd
scenes/            mirrors scripts/ — one scene per script
```

Every script has a scene at the matching path. `scenes/main.tscn` is what runs: it holds the
level, the player and the HUD.

Levels are built from **CSG boxes** — primitive shapes you drag and resize directly in the editor.
Select any platform in `test_level.tscn` and change its `Size`. No modelling software required,
which is the right trade while the game is still being designed.

---

## 8. Glossary

| Term | Meaning |
| --- | --- |
| **Node** | One object in the scene tree. Has a type that decides its abilities. |
| **Scene** | A saved tree of nodes (`.tscn`). Instance it to reuse it. |
| **Instance** | A copy of a scene placed in another scene. Edits to the original propagate. |
| **Autoload** | A script loaded once, reachable from anywhere by name. Ours is `Events`. |
| **Signal** | An event a node emits. Others `connect()` to it. |
| **`delta`** | Seconds since the last frame. Multiply speeds by it. |
| **`@export`** | Makes a variable editable in the Inspector. |
| **`@onready`** | Waits until the node's children exist before assigning. |
| **Collision layer** | What a body *is*. |
| **Collision mask** | What a body *looks for*. Both must line up for two things to interact. |
| **`CharacterBody3D`** | A body you move yourself via `velocity` + `move_and_slide()`. |
| **`Area3D`** | Detects overlaps without blocking movement. Pickups, triggers, hitboxes. |
| **`RigidBody3D`** | A body the physics engine moves for you. The kegs. |
| **CSG** | Constructive Solid Geometry — editor-built primitive shapes, used for the blockout. |

---

## What to build next

Good first tasks, roughly in order of difficulty:

1. A **moving platform** (a `Node3D` with a script that lerps between two points).
2. A **collectible that unlocks a door** — needs counting, and a signal.
3. A **new enemy** — copy `enemy_walker.gd` and change how it moves.
4. **Sound effects** — there are none yet. `AudioStreamPlayer3D` on the lum is a good start.
5. **Animation** — the character is spheres moved by code in `_update_visual()`. Replacing that
   with a real rigged model and an `AnimationTree` is the biggest single upgrade available.
