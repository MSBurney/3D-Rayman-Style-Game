# Guided tour

For developers who can already program but are **new to Godot**. Work through it in order; each
section is a small change you actually make, not just something to read. Budget an hour or two.

You will need the project open in **Godot 4.7**: open `3d-rayman-type-game/project.godot`.

---

## 0. Run it first

There are two scenes, and which one you want depends on why you are here.

**`scenes/playground.tscn` is where the game currently is.** Open it and press **F6**. You start on
a shelf at the top of a long ramp, so just walk forward and let it happen. Things to try, in order:

1. Run to the bottom of the ramp and watch the `speed` line on the F3 readout. Running speed is 7.5;
   the ramp is worth more than double that, and nothing takes it off you at the bottom.
2. Keep going and jump the gap. At walking pace it is not crossable. With ramp speed it is.
3. Walk back **up** the ramp and notice how fast your speed disappears. That is the trade.
4. Cross the gap the slow way instead, over the three stone slabs — then come back and land on one
   from a height, or slam on it. Your own weight is what breaks them.
5. Take the steep orange ramp on the right. You cannot stand still on it at all.

**`scenes/main.tscn` is the original moveset showcase**, kept as a reference. Press **F5** for it.
You should be standing on a green plaza with two red enemies wandering nearby.

Fly around for five minutes before reading any code. Try to reach all four zones:

- **North** — hop the platforms, then dive across the gap using the two floating rings.
- **East** — sprint at the tan wall and keep going; you should run along it.
- **West** — jump at the tall pink terraces and you will grab the lip. Press jump again to climb up.
- **South** — a pit. ⚠️ This zone was built around grapple anchors and currently has no route
  across it at all; see the warning in the README. Try the playground instead.

Press **F3** for a live readout of your state, speed, jump chain and spin. Leave it on — it
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
| `Magnet Speed` → `3` | Abilities > Carry | Spin next to a keg and watch it crawl towards you. The magnet is easiest to understand at low speed |
| `Spin Third Scale` → `6` | Abilities > Spin | Chain three spins and the last one clears the whole plaza. Shows what the chain is scaling |
| `Spin Combo Window` → `0.45` | Abilities > Spin | Chaining becomes near-impossible. Shows why this has to clear `Spin Time + Spin Cooldown` with room to spare |
| `Slope Gravity` → `0` | Weight | Run down the big ramp in the playground. It becomes an ordinary floor, and you suddenly see how much of the game's speed was coming from it |
| `Momentum Friction` → `30` | Weight | Ramp speed evaporates the moment you reach the bottom. This is what a cap feels like, and why this number is low |
| `Acceleration` → `65` | Run | The old, light character. Try the ramps with it and notice that weight is what makes the speed feel earned |
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

Open `scripts/player/player.gd` and read the header comment. Then find `_do_slide()`.

Do **not** read the whole file. The structure exists so you do not have to: one `_do_<state>()`
function per thing the player can be doing, and `_physics_process` picks which one runs:

```gdscript
match state:
    State.GROUND: _do_ground(delta)
    State.CROUCH: _do_crouch(delta)
    State.SLIDE: _do_slide(delta)
    State.AIR: _do_air(delta)
    ...
```

`_do_slide()` has the shape every state function has — **move, then check whether we should be in a
different state.** It is about twenty lines, and three of the four `if`s at the bottom are exits: to
a long jump, to standing up, to crouching when you run out of speed. Count the exits in each
`_do_` function; a state with no way out is a bug.

Then read `_try_jump()`, which is where Mario's jump chain lives. Notice that the side flip is
handled there too, and the comment saying why: both are jumps, so keeping them in one function means
no state has to know the difference.

> **Try it:** on the playground, run down the big ramp holding `Ctrl` to slide, then press `Space` at
> the bottom. Watch the `speed` line on F3. The long jump **adds** its push to the speed the slope
> gave you, so the faster you arrive the further you go.

Now open `scripts/player/player_abilities.gd` and read `_spin()`. It is the other half of the
moveset and it is deliberately **not** a state — you can spin while running, jumping or falling,
so it has nothing to do with the state machine. Notice `_trip_switches()`: anything that joins the
`spinnable` group and implements `spin_hit()` reacts to a spin, with no change needed in the player.
That is the pattern to copy if you add a thing the spin should affect.


Two things in this file are worth understanding because they bite everyone:

**Order matters.** `is_on_floor()` and `is_on_wall()` only mean anything *after*
`move_and_slide()` — before it, they describe last frame. That is why the wall cling is entered in
`_after_move()`, not inside a state function.

**A button press lasts a whole frame.** `Input.is_action_just_pressed()` stays true for every
check within the same frame. If one function reacts to a press by changing state, and the new
state runs *later in the same frame*, it sees the same press and can undo the change immediately.
The old grapple needed a lock-out timer for exactly this: the press that fired it was still "just
pressed" when its own code ran a moment later, so it cancelled itself. `spin_cooldown` does the same
job for the spin.

> **Try it:** stand near a keg and press `F`. The spin drags it to you and you end up holding it;
> press `F` again to throw it. Same button, two outcomes, decided only by whether your hands are
> full. Read `handle_input()` in `player_abilities.gd` — the fork is three lines.
>
> **Then try throwing badly on purpose.** Spin next to a walker to pick it up, turn away from
> everything, and throw. The
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

55 checks, a few seconds. It has already caught several bugs that looked fine in play, including
the grapple problems above. If you add an ability, add a check for it in
`tests/moveset_smoke_test.gd` — copy an existing one, they are all the same shape.

---

## 7. Where things live

```
scripts/
  game.gd          score, checkpoints, respawning
  events.gd        the signal noticeboard (autoloaded as `Events`)
  player/          player.gd, abilities (spin + carry), camera, ledge sensor
  enemies/         walker, turret, bullet
  props/           lum, keg, checkpoint, hazard, crumbling floor, spin switch
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
