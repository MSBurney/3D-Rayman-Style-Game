# Starter tasks

Jobs sized for one person each, roughly easiest first. Every one lists where to look and how to
tell when it works.

**Before your first task:** play the game and work through
[GUIDED_TOUR.md](GUIDED_TOUR.md). Most of these assume you have done the tour's bounce pad exercise.

**Before you push anything that touches the player:** run the smoke test.

```
"<path-to-godot>" --headless --path 3d-rayman-type-game res://tests/moveset_smoke_test.tscn
```

If you add an ability, add a check to `tests/moveset_smoke_test.gd` and bump `EXPECTED_CHECKS` (currently 48).

---

## Tier 1 — get comfortable

### 0. Build a ramp and find out what it is worth
The game's speed comes from slopes, so the most useful thing to understand first is what a given
slope is actually worth.

- Open `scenes/levels/momentum_playground.tscn`, select `GentleRamp`, and duplicate it.
- Change its angle. **Do not type numbers into `transform`** — use the rotation fields in the
  Inspector, or the rotate gizmo. The nine numbers in a `.tscn` transform are the basis *rows*, and
  hand-writing them gets the tilt backwards. (It did, for both of the ramps that are in there.)
- Run it, hold F3, and write down the speed you reach at the bottom of each angle you try.

*Watch out:* below about 7° a slope does not build speed at all, and below about 27° you can stand
still on it. Both of those thresholds come out of `Slope Gravity` on the player — see the Weight
group and the note in CLAUDE.md.

*Done when:* you can say what angle gives a fun amount of speed, and add a row to this file saying so.

---

### 1. Tune the feel and write down what you learn
No code. Select the Player, change values in the Inspector, play, repeat. Then add a short section
to this file describing what three of them actually do to the feel.

Good candidates: `Air Control`, `Coyote Time`, `Jump Cut`, `Apex Gravity Scale`, `Max Speed`.

*Done when:* you can explain to someone else why `Coyote Time` exists.

---

### 2. Moving platform
A platform that slides between two points, carrying the player.

- New scene: `AnimatableBody3D` root (**not** StaticBody3D — that one does not carry riders
  properly), a `CollisionShape3D`, and a `MeshInstance3D`.
- Script it to move between its start position and a `@export var offset: Vector3` over
  `@export var duration: float`, ping-ponging. A `Tween` set to loop is the easy way.
- Put one over the pit in zone D.

*Watch out:* move it in `_physics_process`, not `_process`, or the player will judder while riding.

*Done when:* you can stand on it and get carried across without sliding off.

---

### 3. Sound effects for the wall run and the tongue
There is an audio system already — see `play_sfx()` in `player.gd` and the `Sounds` group in the
Inspector. Nothing plays for wall running, or for grabbing and throwing with the tongue.

- Add new `@export var sfx_*: AudioStream` slots and call `play_sfx()` from the right state.
- Generate new placeholder blips by editing the recipe list in
  `tools/make_placeholder_sounds.gd` and re-running it, or drop in real `.wav` files.

*Watch out:* a wall run is continuous, not a one-shot. You will need a looping sound that starts on
entering `WALL_RUN` and stops on leaving, rather than one blip per frame.

*Done when:* wall running and the tongue both sound like something is happening.

---

### 4. Make the HUD show the current state
`hud.gd` already reads `player.debug_info()` for the F3 overlay. Show a small, always-visible label
naming the current state.

*Done when:* the label reads GROUND / AIR / SLAM / SWING etc. as you move, without F3.

---

## Tier 2 — real features

### 5. A collectible that opens a door
Teaches counting, signals and reacting to game state.

- A `Door` scene that slides or scales away when opened.
- Listen for `Events.lum_total_changed` and open at a threshold, or add a new
  `signal door_key_collected` to `events.gd` and a special pickup that emits it.
- `game.gd` is where the lum total is kept.

*Done when:* collecting enough lums visibly opens a door somewhere in the level.

---

### 6. A second enemy type
Copy `enemy_walker.gd` and change how it moves — a hopper, a charger that winds up and rushes, or a
flyer that ignores gravity.

Reuse `HealthComponent`, `Hurtbox` and `Stompbox` exactly as the walker does, so it can be killed by
keg and stomp without extra work.

*Watch out:* read `Player.descent_speed()` for stomp checks, never `player.velocity.y`. The comment
on that function explains why.

*Done when:* it threatens the player differently from the walker, and both kill methods work.

---

### 7. Breakable crates
A prop that shatters when hit by a thrown keg.

A thrown object bursts at the end of its flight and damages everything nearby in the `enemy` or
`breakable` groups that has a child node named `Health`. So a crate needs three things: a `Health`
child, `add_to_group(&"breakable")` in its `_ready()`, and a reaction to `Health`'s `died` signal.

*Watch out:* a throw **homes at enemies only**, so it will not seek out your crate — you have to
throw at it, or catch it in the burst of a throw aimed at something else. Making throws home at
breakables too means adding `breakable` to `_pick_target()` in `thrown_flight.gd`; try it and see
whether it makes aiming better or just noisier.

*Done when:* a thrown keg destroys it but walking into it does not.

---

### 8. Second level
Duplicate `test_level.tscn` and build something that demands *combining* moves — a gap you can only
clear by swinging off an anchor, slamming for height, and catching a ledge.

That combination is the whole point of the project. Read the design rule at the top of `player.gd`.

*Done when:* there is at least one route that needs three abilities in sequence.

---

## Tier 3 — bigger, take one only when you are comfortable

### 9. Replace the placeholder character with an animated model
Currently the character is spheres moved by code in `player_visuals.gd`.

- Import a rigged model (Mixamo is free and works with Godot).
- Add an `AnimationTree` and drive it from the player's `state_changed` signal, which already fires
  on every transition and nobody listens to yet.
- Keep the collision capsule as it is; only the `Visual` node's contents change.

This is deliberately isolated: `player.gd` should need no edits at all. If you find yourself
editing it, the split is wrong — say so.

---

### 10. Pause menu and a settings screen
Mouse sensitivity and volume at minimum. `PlayerCamera` owns sensitivity; audio buses handle volume.

*Watch out:* `get_tree().paused = true` stops `_process` and `_physics_process` on most nodes. Your
menu needs its `process_mode` set to `Always` or it will freeze with everything else.

---

### 11. Swimming
A water volume (`Area3D`) that switches the player into a `SWIM` state with different gravity,
drag and controls.

Add it as a new state in the enum and a new `_do_swim()`. Follow the design rule — make sure it has
exits into the other states rather than trapping the player.

---

## Things deliberately not built

Do not start these without agreeing it first: saving/loading, multiplayer, procedural level
generation, a custom physics engine. They are large, and none of them is what this project is for.
