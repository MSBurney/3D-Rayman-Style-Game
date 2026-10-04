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
    props/           coin, keg, checkpoint, hazard, crumbling floor, spin switch,
                     breakable block, treasure, level exit, transformer
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
- **Collision resolution zeroes your velocity before an `Area3D` reports the overlap** — and it
  happens in **both axes**, which caught this project twice. Stomping an enemy cannot check
  `velocity.y` in the area callback, and a breakable block cannot check horizontal speed there
  either: running into the block means `move_and_slide()` has already stopped you by the time the
  sensor fires, so it reads zero and refuses every hit however fast you arrived. Two accessors exist
  for this: **`Player.descent_speed()`** and **`Player.approach_velocity()`**, both giving the value
  from *before* collision resolution. If you write an `Area3D` callback that asks "how fast were
  they going", use one of them — never `velocity`. The same applies to WRITING: if you want the
  player to keep going through whatever they just broke, restore from `approach_velocity()` rather
  than scaling `velocity`, which keeps nothing because it is already zero.
- **GDScript lambdas capture local variables by VALUE.** Assigning to a captured local inside a
  closure writes to the lambda's own copy and the outer variable never changes — silently, with no
  warning. This bit the smoke test: a signal handler recording a measurement into a captured `float`
  always reported the initial value, which read as *"the signal never fired"* and sent me hunting a
  bug in the prop that was not there. Capture a **reference type** and mutate it (`var out: Array[float] = []`
  then `out.append(...)`), or use a member variable. The array captures elsewhere in that file work
  for exactly this reason, which makes the float version look like it should too.
- **A node spawned from code is positioned a line AFTER it enters the tree**, so anything `_ready()`
  caches about its own position is the position it had before it was placed. `breakable_block.gd`
  cached a rest position that way and its shake tween teleported refused blocks to the level origin.
  Scene instances are fine, which is what makes it so easy to miss. Read positions when you need
  them, not in `_ready()`.
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

### The mid-air lift

Spinning in the air gives you a little height, as in Galaxy. Two things about it are deliberate:

- **`min(velocity.y + boost, boost)`, not a plain assignment.** That makes it two useful things at
  once: falling slowly you get a small hop, falling fast your descent is *slowed but not cancelled*.
  Wiping a 20 m/s fall would make the character feel weightless, and heaviness is the identity.
- **Gated on `State.AIR`, not on `not is_on_floor()`.** So a spin cannot rescue you out of a ground
  pound, a wall cling or a ledge hang. Those are committed states and the spin has no business
  overriding them.
- **The third spin sets a `spin_chain_lockout`.** Three lifts per chain is a deliberate burst of
  airtime; without a pause between chains you could spin your way upward for ever.

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

## Jump effects are legibility, not polish

`jump_burst.gd`. Six moves now leave the ground and several share a button and a posture, so without
a tell the player cannot see which one fired — that complaint is what produced the file.

- **A plain jump gets NO puff, deliberately.** That is what makes the others stand out; adding one
  to it would undo the point.
- **Two tells, of different kinds:** colour (one per move, the primary) and the direction the dust is
  thrown (down for a double jump, sideways for a side flip, backwards for a backflip). The direction
  is what you notice before you have consciously read the colour.
- **Keep the colours far apart in hue.** Two moves in similar colours is the same as no tell.
- **`CPUParticles3D`, not GPU.** The project renders with GL Compatibility and CPU particles are the
  option guaranteed to work on it. A few dozen quads cost nothing.
- **The material needs `vertex_color_use_as_albedo`.** Without it `CPUParticles3D.color` does nothing
  and every puff comes out white — the colour tell silently stops working while still "running".

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

## Where this is going: a 3D Wario Land

**Stated 2026-10-02.** The target is *a 3D Wario Land* — the equivalent of Mario 64 or Odyssey for
the Wario games, taking heavy influence from Mario 64 DS's Wario. Not a Mario game with a heavy
character. That distinction is the thing to protect.

Much of what is already built lines up, which is why this is a direction rather than a fifth
rewrite: heavy committal handling, the ground pound (Wario's butt stomp), grab-carry-throw, slopes
and uncapped momentum, crumbling floors, and a near-frictionless `SLIDE` state.

**What is deliberately NOT yet Wario:**

- **The spin attack is the least Wario thing in the build.** Wario's signature ground move is the
  shoulder dash, and the mid-air spin lift pulls it further toward Mario Galaxy. It is there because
  it was asked for and it works; just know it is the piece that would look out of place if the Wario
  framing is pushed harder. A dash was offered and not taken yet.
- **Health.** Wario Land II onwards has **no health and no death** — damage *transforms* you, and
  each transformation is both a loss of control and a key to somewhere you could not otherwise
  reach. That is the single most distinctive idea in the series and the biggest available identity
  swing. It was offered and deferred in favour of the breakable world. If it is ever taken up: the
  transformations that translate to 3D are the **movement** ones (Flaming, Frozen, Puffy, Bouncy),
  not the geometry-access ones (Flat, Zombie). And it removes `HealthComponent` from the player, the
  HUD hearts, `take_hit`, `_do_hurt`, the respawn flow and about six smoke checks.
- **Treasure as the goal.** Lums are still lums; Wario Land's score is money you spend.

## Transformations, and the tools/threats split

**Built 2026-10-02.** Wario Land's best idea: getting hit does not hurt you, it **changes** you, and
the change is a penalty **and** a key to somewhere you could not otherwise reach. `State.FLAMING` and
`State.PUFFY`.

### Why health and death were KEPT

Wario Land II onwards paired transformations with immortality. **That pairing is the series' most
criticised decision** and the user named it before agreeing to any of this: a boss that cannot
threaten you can only inconvenience you, so WL4 bolted a timer onto its bosses as a patch.

**The two ideas are separable, and this project separates them.** Transformations only need "getting
hit does something interesting" — they do not need you to be immortal. So:

| | |
| --- | --- |
| a **tool** | transforms you, does **no** damage — `transformer.gd` |
| a **threat** | damages you and can kill you — `hazard.gd`, the walker, the turret, every boss |

That split is the load-bearing idea. It gives enemy design a real axis, it keeps bosses genuinely
dangerous, and **nothing in the transformation code touches hearts, damage or death.** If you ever do
want to remove health, that decision is still open and nothing here has foreclosed it.

### The synergy that makes FLAMING worth having

`flame_speed` (20) is **above every `BreakableBlock.break_speed` (12) on purpose.** Being set alight
therefore opens every speed-gated wall in the game, and it costs **no code in the block** — the block
already asks `approach_speed()`, and a flaming player simply arrives fast.

So the penalty *is* the key: you cannot steer once alight, which means you have to line yourself up
*before* touching the fire. That is the skill the penalty creates, and it is the reason this
transformation is interesting rather than annoying. Keep `flame_speed` above `break_speed` or the
whole point goes.

### Two rules for placing tools

- **Put a tool in front of the thing its transformation is FOR.** A fire jet with no speed-gated wall
  past it, or a spore puff with nothing above it, is purely an inconvenience — which is exactly the
  failure mode that earned Wario Land its criticism.
- **Every transformation must time out.** They are states with no exit but the clock (and `crouch` to
  pop PUFFY), so the timer is the only thing stopping them being a trap. `crouch` exists on PUFFY
  because deciding *when* to deflate is the one real choice the state offers; without it the state is
  pure waiting.

`PlayerAbilities` refuses the spin while `Player.is_transformed()` — a transformation you can attack
your way out of is not a penalty. `transform_into()` also drops whatever you were carrying, or it
would stay welded to the hold point.

## Money as stakes, and the no-death question

**Added 2026-10-02 as a deliberate first stage.** Getting hit by a threat knocks money out of you and
it lands on the floor where you can go back and collect it. **Health and death are still there** —
this was staged on purpose, so the feel of money-as-stakes can be judged before anything bets the
fail state on it.

### Why it is Hollow Knight's version and not Sonic's

The user proposed a Sonic hybrid: coins are your health, one coin means you live. Three problems with
that as a flat rule, all worth remembering:

1. **In a game about hoarding, a good player is always rich, so they can never die.** It recreates
   the exact Wario Land boss problem for precisely the players who would notice. The system protects
   whoever needs it least.
2. **Sonic's rings work because they scatter and you have ~2 seconds to grab them back.** That
   recovery scramble *is* the mechanic. Coins that simply vanish are a damage bar painted gold.
3. **Money here is the WIN CONDITION** (the exit charges you), which Sonic's rings are not. So a
   permanent loss can lock a player out of finishing: hit → poorer → cannot afford the exit → must
   stay in the dangerous level → hit again. **Design against that spiral.**

So: the money is **not destroyed, it is dropped where you lost it** — Hollow Knight's and Dark Souls'
answer. Immediate, real, recoverable, no lockout, and "my money is lying next to the thing that hit
me" is the most Wario sentence available.

### Two rules that make it work

- **`coin_cost` is per threat, not a flat rate.** A walker costs a few coins, a boss costs a lot.
  That one number is what stops a rich player being immune to everything, and it is why
  `Events.player_hurt` carries it rather than deriving it from damage.
- **A hit can never take more than you have** (`Game._on_player_hurt` clamps it). With money as the
  win condition, a hit that could push you negative is a lockout waiting to happen.
- **The money loss is gated on the hit LANDING**, because `take_hit` bails if `health.damage()`
  returns false. So invulnerability frames protect your wallet as well as your hearts, and you cannot
  be drained during the flash. Worth knowing when testing: `take_hit(0, ...)` does nothing at all —
  `damage(0)` is false — so a check that passes zero damage to "isolate the money" measures nothing.

The spill lives in **`game.gd`**, not the player, because Game owns the running total and so is the
only place that can clamp the loss. `coin.gd.spill()` handles the arc and a `pickup_delay` — without
that delay the coins are re-collected on the frame they appear, since the player is standing in the
middle of them, and the whole mechanic silently does nothing.

### If the no-death question comes back

**It is still open.** The staged order was chosen because of this project's history: the grapple was
rewritten four times because the ambitious version went in before anyone knew whether the core felt
good. If money-as-stakes feels right in play, removing hearts afterwards is easy *and the number
ranges will already be known*. See also [[transformations]] on why health was kept for bosses.

## Building levels by hand: probe the geometry

**Every single time this project has placed geometry by hand, something has been wrong in a way the
eye could not see.** Two playground ramps tilted the wrong way. Test fixtures spawned off the edge of
a pad. And on the tree fort's first draft, **two entire staircases ran underneath the deck they were
supposed to reach** — you would have climbed into the underside of the floor above.

So: when you hand-author a level, **write a throwaway probe scene that raycasts the geometry** and
run it before believing anything. `tests/fort_probe.gd` is the pattern (delete it once the level
settles). It takes a couple of minutes and it has never once come back clean on the first try.

Three things that make a probe actually useful:

- **Start each ray just ABOVE the surface it asks about, and give it a short reach.** Casting from
  the sky reports whatever is topmost at that x,z — so any deck with another deck above it reads
  back the wrong one. The fort's first probe did this and produced three nonsense readings that
  nearly sent me fixing the wrong thing.
- **Never cast through the prop you are asking about.** A chest is a `StaticBody3D` on the world
  layer, so a ray dropped onto it hits its own lid and reports "the floor is exactly one metre up"
  for every chest in the level. Probe *beside* it.
- **State the expected value and let the probe compare.** Printing measurements alone means reading
  twenty numbers and trusting yourself; printing `expected 4.0 got 9.00 *** WRONG ***` does not.

**Authoring rule that avoids half of it:** write planks as `origin y = top - size.y/2` and think in
TOP heights, because that is what the player stands on. A deck "at y=4" means `origin 3.7, size.y
0.6`. Stairs are a run of boxes whose tops rise by a fixed step — and for stairs resting on the
ground, `origin y = size.y/2` makes the top equal `size.y`, which is easy to read off.

**Headroom only matters below about 1.4 m** (the player's height). A step 0.8 m under a deck is a
head-bump; the same step 3.5 m under it is fine. That distinction is what decided where the fort's
top flight ended up.

## The money loop

**Built 2026-10-02, and it is the first thing in the project with a GOAL.** Before it there were
thirteen verbs and nothing to use them for: you could smash through a wall that took real skill to
open and find nothing behind it.

Wario Land's core loop, and the thing to design levels around: **see a suspicious wall → work out
which tool opens it → treasure → pay the exit.**

- **`coin.gd`** — was `lum.gd` until 2026-10-02, a Rayman fossil. `Kind.COIN` is money,
  `Kind.GARLIC` heals (Wario eats garlic to recover). One scene, tinted from `kind`.
- **`treasure.gd`** — a chest worth many coins, opened by a spin or a pound, **not** by walking into
  it. A chest you collect by brushing past is indistinguishable from a coin, and the reward has to
  read as bigger than the trail that led to it. It pays straight into the total rather than
  scattering fifty coins, which looks generous and is actually a chore.
- **`level_exit.gd`** — **charges you to leave.** Straight from Wario Land 1, where you literally buy
  the ending. That one rule is what makes every other system matter: the walls, the pound, the spin
  chain and the slopes all become ways of affording the way out. `price = 0` makes it a plain goal,
  which is useful while building.

**Price a level so one chest is not enough.** The playground's exit wants 120 against three 40-and-60
chests, each behind a wall needing a *different* tool — so the price cannot be paid by repeating one
trick. That is the actual level-design lever this gives you.

**The exit refuses loudly.** `Events.exit_refused` carries the shortfall and the HUD prints it. An
exit that silently does nothing when you are poor is indistinguishable from an exit that is broken.
It also brightens when you can afford it, so availability reads from across the level.

Money does **not** reset on death, and the exit tracks the total by listening to
`Events.money_changed` rather than reaching into `game.gd` — so both work in any scene.

## The breakable world

**Built 2026-10-02, and chosen as the first Wario experiment.** `breakable_block.gd`. The idea in one
line: **Wario goes THROUGH a level rather than over it.** Mario respects the geometry; Wario removes
it.

Why this one mattered more than it looks: it is the first thing in the project that spends momentum
on **access** rather than on distance. Before it, a ramp made you fast and that was the whole reward.
Now a ramp can be the only way through a wall.

Three ways in, and each answers a different question the player might ask:

| | |
| --- | --- |
| **spin** (`require_spin_step`) | "can I open this from standing?" At 3, only the super spin does — which gives the chain a reason to exist beyond damage |
| **pound** (`require_slam_power`) | "can I open this from above?" Scales with fall distance, so a drop is worth fetching |
| **speed** (`break_speed`) | "can I open this by arriving fast?" The Wario one. 12 sits above running pace (7.5) and below what a ramp gives (~16) |

Two details that are load-bearing:

- **A refused hit still shakes the block.** "I need to hit this harder" has to be readable from one
  failed attempt, or a block that is merely too tough is indistinguishable from a block that is
  broken.
- **`speed_kept` (0.8) preserves most of your momentum through the break.** Stopping you dead on the
  frame a wall gives way takes back the exact thing you spent to open it.

The sensor is an `Area3D` **wider than the block**, because by the time the solid collision resolves
the speed being measured is already gone.

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

  **But a flat addition compounds, and it got farmed.** Land, crouch, jump, repeat: you were 17 m/s
  faster every single time, and four in a row passed 60 m/s. The push now fades to nothing at
  `long_jump_fade_speed`, so a chain converges there instead of diverging.

  The distinction that matters, because it looks like a cap and is not one: **this caps the BONUS,
  not your speed.** Nothing about it touches what a slope can give you. It only declines to pay full
  price for the same button twice. If you ever need to make the long jump stronger, raise the fade
  speed rather than the push — raising the push makes the exploit worth doing again.

  Worth knowing: **every other move in the set SETS velocity rather than adding to it** (side flip,
  backflip, the spin's air lift is `min(v + boost, boost)`). The long jump was the only additive one,
  which is exactly why it was the only one that could be farmed. Apply the same suspicion to any new
  move whose impulse adds.

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
