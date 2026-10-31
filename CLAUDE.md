# Working on this project

A 3D platformer in Godot **4.7.2**, GL Compatibility renderer. The Godot project lives in
`3d-rayman-type-game/` — one level down from the repo root.


## The design document governs (set 2026-10-26)

**There is now a design doc — *Project Heavyweight — Vision & Movement Design*, 2026-10-24 — and it
is the authority.** The experiment-sandbox phase described in the next section is over; read that
section, and everything dated before it, as the history that produced this one.

Its own closing line on its standing rules is the instruction to take most literally:

> *"These rules are standing: a proposal that violates one needs this document amended first, not
> an exception granted quietly."*

The short version of what it commits to:

- **Wario Land in 3D, as a deliberate PUZZLE-platformer**, not an action game. Spectacle is the
  payoff for thinking, never the loop. **Tiebreak: when two ideas conflict, the deliberate/puzzle
  reading wins over the action/spectacle one.**
- **Four pillars**, and a feature serving none of them is cut: committed movement · weight is a
  reasoning tool · destruction is legible and consequential · joyful, not dour.
- **Movement is modal** — Walk / Charge / Air / Slam — with **steering authority as a falling curve
  of speed**, and the cardinal rule *instant inputs, heavy body: never add delay to feel heavy.*
- **Six universal weight rules with zero per-room exceptions**, built as **one physics layer early,
  never as per-level scripts**.
- **There is no death.** Every penalty is live and in-arena, never travel time. A boss hit regresses
  your setup rather than hurting you, and ejection from an arena is banned.
- **Kinematic hero, always.** *"Fake the mass, never rigid-body-drive the hero."* Rigid bodies are
  for the garnish — debris, thrown objects — because unpredictable physics kills mastery.
- **Author the physics, simulate the garnish**, and **weight is 50% feedback** — juice ships with
  the greybox because it is the mechanic, not polish.

### What that means for what is already on disk

The doc is explicit: **"Scrap the ported Mario 64 verb set — an agility moveset made heavier can
only produce a worse Mario. Build the modal controller from scratch instead."** So `player.gd`'s
double/triple jump, side flip, backflip, long jump and wall kick are superseded, as is its
eleven-state machine, the spin (the **charge** is the traversal verb and the **boost** is the
steering verb at speed), and the open no-death question, which the doc closes.

**Nothing has been deleted.** `heavy_player.gd` is the from-scratch replacement and it lives
alongside the old one until Milestone 1 is judged — see below. What survives essentially unchanged:
slopes-as-momentum, breakable blocks, crumbling floors, impact force scaling with fall height, the
thief/scramble systems (the doc's field-damage model almost exactly), and the warden boss, whose
"a hit regresses the setup, no ejection, the boss stole something so the fight is a retrieval"
doctrine matches the doc line for line.
## What this is for, right now

**Set 2026-10-11, and SUPERSEDED 2026-10-26 by the design document above.** Kept because the
working habits in it still apply to anything not covered by the doc, and because the experiment
records further down were written under it. This is **not** a game
in development. Nobody has settled on what the game is yet, and rather than commit to a design
before anyone is confident in one, the project is deliberately being used as **a series of
experiments in 3D platformer mechanics**.

That changes a few things about working here:

- **An experiment does not have to fit a bigger plan.** The question to ask about a new mechanic is
  "is it interesting, and did we learn something from building it?", not "does it serve the Wario
  framing?".
- **Do not defend a direction.** Everything from **The spin attack** onwards is a *record of an
  experiment that was run*: what it does, why each number is what it is, and what it cost to get
  working. All of that is still true about the code and still worth reading. None of it is a
  commitment. Where an entry says something "is the thing to protect", that means it was being
  protected while that experiment ran — not that it binds the next one.
- **Surface conflicts, do not quietly resolve them.** Two experiments are allowed to contradict
  each other and both stay in the repo. If a new one would undo an existing one, say so plainly and
  let the team decide, rather than picking for them.
- **Still unconditional:** everything in **Things that will bite you**, **Conventions**, **Layout**
  and **Before you change gameplay code**. Those are about Godot and about this codebase, not about
  what the game is, so no change of direction touches them. The smoke test in particular stays
  green — an experiment is allowed to be thrown away, but not to leave the build broken.

Read the older direction statements below as history. They are all dated.


## Milestone 1: the heavy controller (built 2026-10-26)

`scripts/player/heavy_player.gd` + `scenes/greybox_main.tscn`. The doc's own framing: **"the
greybox that proves or kills this"**, with a one-sentence pass/fail — *is charging down the slope
into the wall grin-inducing within a day of tuning?*

**It is built ALONGSIDE `player.gd`, not instead of it**, and that is deliberate rather than
timid. Scrapping the old controller in place breaks nine scenes, Ian's level and about eighty of
107 checks before anything has been proven — which is precisely the mistake that cost this project
four grapple rewrites. The greybox has its own scene, its own player and its own room. Retiring
`player.gd` is a separate, deliberate step once the milestone is judged.

### All sixteen tuning parameters are exposed

The doc lists them and says *"the design lives in these curves; expect most of prototype week to be
spent here"*, so every one is an `@export`: walk speed · charge wind-up · charge acceleration ·
charge top speed · turn rate vs speed · slide friction · jump speed-scaling · air-steer authority ·
slam drop acceleration · impact force scalar · crash-stun · slope accel/decel multipliers · the
steering-authority curve · boost impulse · boost cooldown and tap count · brake impact scalar.
One more exists that the doc does not list — `boost_fade_speed`, which the boost turned out to
need the moment it met a real player (see the tuning pass below).

### Measured in the greybox

Current, against the tuning pass below.

| | |
| --- | --- |
| walking | 15.0 m/s |
| charge on the flat | **20.0 m/s** |
| charge down the 15° slope | **26.0 m/s** |
| the wall's `break_speed` | **22.0** — short on the flat, through off the slope |
| jump at walking pace | 15.5 m |
| charge-jump | **21.2 m** |
| authority at walk speed / at top speed | 1.00 / 0.20 |
| a chain of ten jump-boosts | **28.0 m/s** (a flat +7 each would give 85) |
| a slam on a see-saw end | throws an 8-mass crate at **9.7 m/s** |
| walking into a 16-mass crate | it leaves at 3.7 m/s, you keep **5.1 of 15.0** |
| a slam beside a crate | throws it up at 4.6 m/s |
| a crate thrown at you at 18 m/s | shoves you at **6.7 m/s** |
| a thrown crate | leaves at **17.0 m/s** and breaks a `break_speed` 12 block |
| a crate dropped on the see-saw's far end | launches you at **7.2 m/s**, no slam |
| walking into the giant / charging it | 150 vs 200 against a bar of **180** — only the charge fells it |
| a felled giant's top | **0.45 m** — a step you can walk onto |
| a refused ram | staggers him, scaled — 72% of the bar reads as 72% |
| the giant walking into a standing player | shoves them at **2.4 m/s** |

**That `break_speed` row is the whole room.** The wall is deliberately out of reach of a charge on
flat ground, so the slope is not a shortcut to it — it is the only way through it. If the wall ever
becomes breakable without the ramp, the room has stopped asking the doc's question.

### Three bugs the probe found, all of them design bugs rather than typos

- **The charge capped total speed.** Written as a plain `move_toward(facing * charge_top_speed)`,
  the charge quietly dragged you back DOWN to 20 all the way down the ramp, so the slope was worth
  nothing and the flat and slope runs measured 20.0 and 20.1. `charge_top_speed` is what the engine
  reaches on the flat, **not a limit on how fast you can be going** — weight gates speed, it never
  caps it, and charge velocity obeys the same conservation as everything else. Above that speed the
  charge now only steers.
- **The charge cancelled whenever you left the ground.** The first version dropped to AIR the
  instant `is_on_floor()` went false, so charging over the lip of the ramp ended the charge — on
  exactly the terrain the game is made of. Per the state diagram the only way out of a charge into
  the air is a **charge-jump**, which is a decision; falling off a bump is not. A charge now keeps
  its heading and speed while briefly airborne, taking neither power nor friction.
- **A charge press made a frame before landing was silently thrown away**, because a wind-up can
  only start from the floor. That breaks the cardinal rule — every input gets a response — and an
  input that sometimes evaporates is read as bad controls, which is the one thing a heavy character
  cannot afford. Hence `charge_buffer`, the twin of `jump_buffer`.

### Choices worth knowing before you tune

- **`authority()` returns exactly 1.0 at or below `walk_speed`, and nothing is allowed to erode
  that.** It is the one promise the whole curve is built on: *"a player stuck on a puzzle must never
  be able to blame the controls"*. Note that it is `walk_speed` that sets how wide that window of
  full authority is, so raising `walk_speed` raises the speed at which you still have perfect
  steering — see the tuning pass below, where that turned out to matter more than it looks.
- **One button, two verbs.** `attack` HELD from walk winds up a charge; TAPPED while already
  charging or airborne it boosts. That is one of the two options the doc leaves open for the boost
  input, it adds no binding, and it is unambiguous because the two are reachable from different
  states. The other option — its own button — is still open.
- **The boost ADDS, never assigns.** A boost that rewrote the velocity would be free steering and
  would hand back all the authority the speed just took away. Adding is what makes correcting your
  course leave you faster and more committed.
- **But an addition compounds, so the boost FADES** — full value up to `charge_top_speed`, nothing
  at all by `boost_fade_speed` (28). This is the same exploit the long jump had and it was found the
  same way, in play: *"after multiple jump boosts I can travel at ludicrously high speeds"*. Jump,
  tap, land, repeat was +7 m/s every single time, and the probe measures ten taps reaching **28.0
  where a flat addition would give 85.0** — a chain now converges instead of diverging. **It caps
  the BONUS, not your speed:** nothing about it touches what a slope can give you, and the charge
  still keeps every bit of that. If the boost needs to be stronger, raise the fade speed rather than
  the impulse, exactly as with `long_jump_fade_speed`.
  **And a faded-out boost is refused OUTRIGHT rather than applied at zero length**, which is the
  half that is easy to miss: the boost snaps your `facing` onto the stick, so a zero-strength one
  would still hand you a free instant turn at top speed — worth more than the speed it replaced,
  and precisely the authority the design just took away. It still answers the press with a small
  puff, because a refused input must never look like a dropped one.
- **A JUMP DOES NOT END A CHARGE.** Hold `attack` through a charge-jump and you land straight back
  into the same charge with no second wind-up; the wind-up is the price of *starting* a charge and
  you pay it once. Reported from play as *"the charge is killed and I'm back to moving normally"* —
  jumping is how a charge crosses anything, so being dumped into WALK on the far side turned the
  move the room is built around into a punishment for using it. Three things keep it honest:
  letting go in mid-air ends it (so holding really is the whole condition), a **slam** ends it even
  if you never let go (the slam *is* the brake, and a brake you roll straight out of is not one),
  and a merely-held button does **not** start a charge on landing — it has to be a charge you were
  already in, or a crash would wind you back up while you were still mashing the button and fire
  you into the same wall. Carried in `_charge_through_air` rather than in `_charging`, because
  `_charging` means "on the ground adding power" and that is exactly what you are not doing.
- **The slam's impact has two halves**: how far you fell, plus how much horizontal speed you
  delivered into the floor (`brake_impact_scalar`). That second half is what makes the slam double
  as the brake — a flat-out charge cancelled into a slam hits hard with no drop at all, so braking
  on fragile footing breaks it.
- **An ordinary landing deliberately does NOT emit `Events.slam_landed`.** That signal means "a
  slam happened"; firing it on every touchdown would collapse crumbling floors under a hop. A heavy
  landing still breaks fragile ground through the floor's own `descent_speed()` check.
- **`breakable_block.gd` and `crumbling_floor.gd` are now duck-typed** rather than checking
  `body as Player`, so the whole prop library works with both controllers. What a prop needs is the
  pre-collision accessors, not a particular class.
- **`floor_snap_length` is 0.8 on the heavy player**, above the 0.6 the old one uses, because a
  charge tops 26 m/s on a slope and the surface falls away faster than a straight-line step follows.

### The weight layer: the see-saw and the plate (built 2026-10-30)

**The last two props on the doc's Milestone 1 build list**, which means the greybox can now be
asked the doc's *secondary* question as well as its primary one — *"everyone looping the
slope-and-wall means B-primary; everyone fiddling with the see-saw and plate means C-primary"*.

Three files, and the first one is the important one:

| | |
| --- | --- |
| **`components/weight_sensor.gd`** | a drop-in Node that answers "what is on me, and how heavy" |
| **`props/see_saw.gd`** | weight rule 3 — the heavier side of a pivot wins |
| **`props/pressure_plate.gd`** | weight rule 1 — surfaces have visible weight thresholds |

#### The sensor is shared because the doc says it has to be

Rules 1, 3 and 5 all need the same measurement, and the doc attaches an engineering instruction to
them: they *"must behave identically everywhere, so they are built as ONE physics/interaction layer
early — never as per-level scripts"*. **Rule 5 is what makes sharing non-optional** — "enemies obey
the same physics as the player" is a promise two props could easily break in different ways. A
see-saw and a plate that disagreed about how heavy the player is would be two bugs that only show
up in the one puzzle using both.

It is a component rather than a base class or a singleton because that is the pattern this project
already has: `health.gd`, `thrown_flight.gd`, `coin_thief.gd` and `item_thief.gd` are all drop-in
Nodes with no scene of their own.

#### `heavy` is the extension point, and `mass` is the whole interface

Anything with weight does exactly two things: joins a watched group (`heavy` is the general one,
alongside `player`, `enemy` and `throwable`), and has a `mass` property. Same shape as `spinnable`
before it, and the sensor never needs editing again.

**A `RigidBody3D` already has `mass`, so a crate needs no script at all** — the greybox's
`SeeSawCrate` is a bare `RigidBody3D` in the `heavy` group with `mass = 8.0`, and the weight layer
reads it for free. `HeavyPlayer` now declares `@export var mass: float = 10.0` for the same reason,
and it is asked for **by name through `get()`** rather than by checking the class. Note that the
player's `mass` does not touch the movement code at all and never should: the weight in the
handling is the authority curve and the charge (*"fake the mass"*), while this number is what the
WORLD weighs you at.

#### The sensor walks groups by position; it does not use an `Area3D`

Both reasons are traps already paid for in this codebase. **A sleeping `RigidBody3D` is unreliable
in an overlap query** — and a crate that has settled on a see-saw is exactly that, while also being
the single most important thing a see-saw needs to know about. And **an area moved and queried in
the same frame reports nothing**, which a see-saw does every physics frame. So the volume is
checked with maths in the host's local space instead.

A side effect worth knowing: because it is a position check and not a contact check, **a plate does
not care whether you are standing, sliding or falling through it.**

#### Leverage, not just mass

`WeightSensor.moment` is `Σ mass × local z`, so standing further out counts for more. That is how a
lever actually works, and it is the one thing about a see-saw a player can work out unaided. The
greybox is arranged to teach exactly that: the crate (8) is deliberately **lighter** than the
player (10) yet still wins from the middle, and only loses when you walk right out to the end.

```
  crate at z=+3.6, mass 8     moment +28.8
  player at z=-2.0, mass 10   moment -20.0  → crate wins, nothing happens
  player at z=-4.2, mass 10   moment -42.0  → you win, it tips
```

#### Two bugs the probe caught, and both were design bugs

- **The plate was a kerb.** The first version was a solid `StaticBody3D` standing 25 cm proud of
  the floor, and a charge aimed across it stopped dead against the side and crash-stunned — every
  time. A plate you cannot charge over is a wall with a light on it, and worse, the one input it
  exists to reward was the only one that ever reached the top of it. It is now a `Node3D` with **no
  collision at all**: a visual sitting 5 cm proud, with the weight measured as a volume.
- **The slam's "whack" swung the plank through its own passenger.** The verb table lists the slam as
  the "see-saw launcher", so the first version snapped the plank to full tilt on the slammed side.
  That lifts the far end UP through whatever is standing on it: the crate ended up a metre *below*
  the plank in a single frame, outside the sensor's box, so it was never launched — and had it been,
  it would have been fired into the plank's underside. **Any rotation that lifts an end sweeps
  through its passenger unless the passenger is carried, and carrying only works when the motion is
  gradual.** So the slam now contributes the impulse and nothing else, and the angle stays a pure
  function of what is standing where. The pay-off is the crate leaving at ~10 m/s, and the plank
  then tips toward you on its own because the crate is gone.

#### What makes the plate walk-mode, which is a claim and so is tested as one

`hold_time` (0.25 s). A charge at 20 m/s is inside a 1.8 m pad for about five physics frames
against a fifteen-frame hold, so it cannot be set off on the way past — and the charge has no free
brakes, so stopping on a small pad is a real act. `tests/greybox_probe.gd` charges across it and
asserts it does **not** fire.

**`hold_time` is not an input delay and must not grow into one.** The cardinal rule is instant
inputs, heavy body: the player's input is never delayed, and the pad starts visibly sinking on the
first frame your weight is on it. What takes time is the pad, which is a thing in the world. If it
ever reads as lag, the fix is a faster visual response, not a shorter hold.

The plate gives **two separate readouts, because there are two ways to fail**: it *tints* with how
close the weight on it is to `required_mass`, and *sinks* with how far through the hold it is. "I am
not heavy enough" and "I did not stand still long enough" are different problems, and one blended
readout would make both look like the same shrug.

It also reuses `Events.switch_toggled` rather than adding a signal, since that signal's own
documentation already explains how to wire a door to a switch without the two knowing about each
other — and a plate is a switch. `activates` is a **`NodePath`**, never a typed node export, for the
documented reason that a typed node export does not survive a path hand-written into a `.tscn`.

### Weight rule 2: momentum transfers on impact (built 2026-10-30)

**The props above shipped measuring weight and unable to deliver any, and in play that is exactly
how they felt** — the report was *"nothing really gets properly interacted with"*, and it was right.
This is the fix, and it is one rule rather than three broken props.

**A `CharacterBody3D` does not push a `RigidBody3D` in Godot. At all.** They are solved in separate
passes: the character treats a crate as a wall and the crate never hears about it. Walking the slide
collisions and applying the impulses by hand is the only way there is.

**That makes this a VERB, not a detail.** The doc's verb set is Walk · Charge · Jump · Slam · Boost,
with no grab and no carry, so ramming and stomping are the *only* ways the hero can put an object
anywhere. Three directions, all in `heavy_player.gd`:

| | |
| --- | --- |
| **`_shove_what_we_hit()`** | we ran into it — walks `get_slide_collision()` |
| **`_scatter_loose_objects()`** | a slam threw it — walks the `heavy`/`throwable` groups by distance |
| **`_on_hitbox_entered()`** | it ran into US — a persistent `Area3D` masked to layer 64 |

#### One formula, no special cases

Every impact resolves as a perfectly inelastic collision: both bodies end up travelling at
`m1·v / (m1 + m2)`. Ram a crate lighter than you and it flies while you barely slow; ram something
much heavier and you stop dead — **and the crash-stun then follows on its own out of
`_was_stopped_dead()`, with no code anywhere that knows what "heavy" means.**

That is the difference between mass as a reasoning tool and mass as a stat: a player can look at a
thing and predict what ramming it will do. Measured, hero 10 against a crate of 16 at walking pace:

```
  the crate leaves at   3.7 m/s
  you keep              5.1 m/s of 15.0
```

Note the consequence, because it is a design lever and not a bug: **a crate heavier than you
crash-stuns a charge, every time** (you keep under half your speed, which is what
`_was_stopped_dead()` asks). A charge is the wrong tool for a heavy crate; walking into it is the
right one, because `_was_stopped_dead()` only fires above `walk_speed`. Nobody designed that
distinction — it falls out of the formula.

#### Three things in it that are not arbitrary

- **It reads the PRE-MOVE velocity, never `velocity`.** The trap this project has now paid for
  three times: `move_and_slide()` has already zeroed your speed by the time you can ask about the
  collision, so a shove computed from `velocity` delivers nothing for exactly the head-on hits that
  should be hardest. Same reason `approach_velocity()` exists for props.
- **The reaction is SUBTRACTED from the post-slide velocity, not rebuilt from the incoming one.**
  Rebuilding would throw away the wall slide `move_and_slide()` just worked out, which matters the
  moment a crate is pinned against a wall. Subtracting composes with it: the solver already removed
  all of our speed into the surface, so this gives back only the part the crate did not absorb.
- **Layer 64 now means "loose heavy object"** — the layer the throwable keg already used. The
  player masks it, so ramming works through slide collisions, and the player's `Hitbox` masks
  **only** that layer, so level geometry never reaches the area at all.

#### The Area3D is the exception that proves the rule

`get_slide_collision()` only reports what **we** moved into, so a crate flying at a standing player
is invisible to it — and a `RigidBody3D` cannot push a `CharacterBody3D` either, so without the
hitbox a crate thrown by a see-saw passes straight through you. An `Area3D` is safe here where it
would be wrong for the spin: **this one lives in the scene and is never moved or re-added before
being queried.** The spin's problem was an area created and asked about in the same frame.

#### And the see-saw now obeys rule 5

`arrival_speed` / `arrival_transfer`. The plank used to answer *only* to `Events.slam_landed`, and
nothing but the player emits that signal — so a prop built to demonstrate "everything obeys the same
physics" responded to exactly one body in the world. A dropped crate, a thrown keg or a stomping
enemy all have a mass and a downward speed, which is all it needs.

**An arrival launches by transferring MOMENTUM, not through the `launch_per_force` curve the slam
uses, and that is load-bearing rather than tidy.** Through the force curve a heavy crate can launch a
second crate *faster than it arrived* — so two crates on opposite ends play tennis with each other at
increasing speed, for ever. Conserving momentum cannot amplify, so the loop damps out by
construction instead of by a cap catching it.

#### What this unlocked in the greybox, and what it did not

The plate now wants **14** against the hero's **10**, so standing on it is not enough and
`PlateCrate` (16) has to be shoved onto it — which is the interesting kind of plate, and it was
unsolvable before this.

**Still not reachable: the see-saw launching the PLAYER.** Something heavy has to land on the far end
while you stand on this one, and with no carry verb the only way to arrange that is to shove a crate
off a ledge and then outrun its fall — about 0.6 s from 6 m, which is not a thing a person can do.
The rule is implemented and correct, and an enemy or a timed drop will use it; the greybox has no
setup for it, deliberately rather than by omission.

### `weight.gd`: the actual physics layer (built 2026-10-30)

**Built because the props still played badly after rule 2 went in, and the diagnosis is the valuable
part.** The report was *"I'm nervous that we need to figure out additional physics calculations for
all objects and systems"* — and that worry was correct, but **the cause was never the
kinematic/rigid-body split.** It was this:

> **The props were written to a CHARACTER-SHAPED interface.** `breakable_block.gd` asked for
> `approach_speed()`. `crumbling_floor.gd` asked for `descent_speed()`. The see-saw listened to
> `Events.slam_landed`. Those are things only a hand-written `CharacterBody3D` has.

So a crate hurled at a breakable wall at 30 m/s did **nothing**, while the hero jogging into it at 22
opened it. A crate dropped on a crumbling floor did nothing. A see-saw answered to exactly one body
in the game. Each of those is rule 5 broken, each would have needed its own fix, and that is the
treadmill the worry was about.

**The props were asking *who are you* when the only honest question is *how heavy are you and how
fast were you going*.**

`scripts/weight.gd` — `class_name Weight`, static functions only, no state, never instantiated. Not
a manager singleton and not a base class: a namespaced library, called as `Weight.collide(...)` from
anywhere. The whole interface is two questions:

| | |
| --- | --- |
| **`Weight.mass_of(node)`** | asked by NAME through `get()`, so a `RigidBody3D` answers for free |
| **`Weight.impact_velocity(node)`** | pre-collision where that exists, `linear_velocity` otherwise |

and four verbs built on them: `impact_speed` (horizontal, for walls), `descent` (vertical, for
floors), `add_velocity` (the one place that knows an impulse from a velocity), `collide` (the
inelastic transfer), `launch`.

**The test of whether it worked: the diff.** Accepting objects cost `breakable_block.gd` and
`crumbling_floor.gd` *one line each* — `Weight.impact_speed(body)` in place of a `has_method` guard
plus a `call()`. The see-saw's launcher collapsed from a fifteen-line type switch to
`if Weight.launch(body, speed):`. **Nothing new needs a physics calculation of its own; it needs a
`mass`.** Same shape as the `spinnable` group, applied to physics instead of to attacks.

Two mechanical notes:

- **`impact_velocity()` reassembles the two halves.** Both controllers keep horizontal and vertical
  in separate accessors (`approach_velocity()` and `descent_speed()`), so the library puts them back
  together. Done there rather than by adding a third accessor to each player, so neither controller
  had to change at all.
- **Prop sensors needed their masks widened** to `66` — layer 2 (the player) *and* layer 64 (a loose
  heavy object). Without the 64 a block's `Area3D` never sees a crate, and no amount of shared
  arithmetic helps. If a prop ignores objects, check the mask before the code.

### The carry verb (built 2026-10-30)

**Specified by the user, and it closes the open question above:** approach an object and you carry it
automatically, press the boost button to throw it. No grab button.

**It had a real conflict with rule 2, because picking a thing up on contact and ramming it on contact
are the SAME input.** One of them had to lose — and the mode split had already drawn the line:

| | |
| --- | --- |
| **arrive at or below `walk_speed`** | you lift it |
| **arrive committed (charging)** | you ram it |

Nothing new decides that. `walk_speed` was already the border between precise and unstoppable, so
the vocabulary falls out of the existing authority curve instead of needing a button nobody asked
for. **And `carry_max_mass` gives a level two kinds of object from one number:** the greybox has an
8 you can carry and a 16 you cannot, so the heavy one can *only* be rammed.

Four things in it that are not arbitrary:

- **The throw happens on the frame of the press, with no hold-versus-tap timer anywhere near it.** A
  throw that waited to find out whether you meant a charge would be exactly the input latency the
  cardinal rule forbids. The cost is that you cannot wind up a charge with your hands full, which is
  a trade worth having rather than a limitation: carrying something takes your traversal verb away
  until you throw it.
- **The throw inherits your momentum.** Rule 2 and the same rule the jump obeys — a throw out of a
  charge goes much further than one from a standstill. A flat throw speed would make the hero the one
  object in the game that momentum does not apply to.
- **`carry_regrab_delay` is the FIFTH time this trap has appeared**, after `ledge_cooldown`, the
  spin's `regrab_delay`, `grind_relatch_delay` and `ItemThief.relatch_delay`. Pickup is automatic, so
  without it the thing you just threw is re-collected on the next frame while it is still a metre
  away. It also bit the probe, in the way the law predicts: the reset helper put a carried crate down
  at the hold point, and the next check silently measured the wrong object.
- **The velocity on release is applied DEFERRED.** A `RigidBody3D` ignores a velocity set on the
  frame it unfreezes, and the throw drops limply at your feet.

**And the carry verb is what finally makes the see-saw whole.** A heavy arrival on one end launches
whoever is on the other — measured at **7.2 m/s with no slam involved** — which was implemented but
unreachable, because something heavy has to land on the far end while you are already standing on
this one. In play: throw the crate up over the far end and run to the near one while it is in the
air, about 1.3 s of flight against a 0.5 s run.

**The one safety that is NOT in the object.** `platform_seed.gd` rescues itself precisely because a
carrier cannot be trusted to tidy up — but a bare scriptless crate has no script to do that with, so
`HeavyPlayer._exit_tree()` puts down whatever it is holding. That is a weaker guarantee than the
seed's and it is the right one here: losing a greybox crate is not an unfinishable level. Anything
the critical path depends on should still guard itself.

### The heavy enemy: rule 5, and the argument for the weight layer (built 2026-10-31)

`scripts/enemies/heavy_enemy.gd`. The doc's *"fewer, larger, structural"* enemy — **a mobile puzzle
element first and a combat target second**, and *"a system that recombines across many rooms, not an
encounter to balance."*

**It is also the test of whether `weight.gd` was worth building, and the answer is in the diff:
adding it required a change to exactly zero props.** The doc lists four things a room should be able
to do with a heavy enemy. All four work, and almost none of it is code in the enemy:

| the doc's claim | what makes it true |
| --- | --- |
| a **counterweight** | it has a `mass` and is in the `enemy` group, so `WeightSensor` counts it |
| a **pressure-plate holder** | the same two facts — 40 against the plate's 14 |
| a **wall-breaker you aim** | `BreakableBlock.break_mass`, new, below |
| a **bridge, once felled** | `_topple()` swaps to a low wide collider |
| a **hazard the level exploits** | `CrumblingFloor.break_mass`, new, below |

#### One number decides which of the hero's verbs works

`topple_momentum` is **180**, and it is momentum rather than speed: the hero at `mass` 10 brings
**150 at walking pace and 200 charging**. So **only a committed charge fells it** — the doc's
*"aiming before committing is the skill"* as a single threshold instead of a special case. A thrown
crate brings 136 and is the wrong tool; a slam within `slam_topple_radius` works because the
signature verb has to work on the signature enemy.

#### Two new thresholds, and both are rule 1

- **`BreakableBlock.break_mass`** — opened by anything at least this heavy, at any speed. Without it
  the doc's "wall-breaker you aim" is impossible: **a giant walks at 3 m/s and can never clear a
  speed gate**, so a wall meant for one has to ask about its weight. The greybox's `MassWall` has
  `break_speed` 999 and `break_mass` 30 — a wall the hero can never open and the giant strolls
  through.
- **`CrumblingFloor.break_mass`** — gives way under anything this heavy, however gently it arrived.
  This is *"floors that hold the player but not the giant chasing them"*, and it is the cleanest
  rule 1 there is: set the number between two masses and the surface becomes a filter for which body
  is allowed across it. The greybox's `FragileSlab` is 20, between the hero's 10 and the giant's 40.

#### The felled collider is authored, not rotated

A standing 3.4 m box tipped on its side is a **1.7 m kerb you cannot climb**, and the entire value of
felling a giant is that you can then walk over it. So there are two colliders and one is enabled at a
time: `Standing` (1.7 × 3.4 × 1.7) and `Felled` (1.7 × 0.8 × 3.4). Measured, a felled giant's top
sits at **0.45 m** — a step, not a wall. And `get_up_delay` below zero means felled for good, which
is rule 6 applied to an enemy: a giant you dropped across a gap is a bridge you built.

#### It is hit by a group walk, not an Area3D

Three reasons, and the third is the one that is easy to miss: an area moved and queried in the same
frame reports nothing, a settled `RigidBody3D` is asleep and unreliable in overlap queries, and
**`body_entered` only fires on ENTRY** — so a player already leaning against the giant who then
charges would never be noticed at all. `_take_incoming_hits()` walks `player`/`heavy`/`throwable` by
distance, with `hit_cooldown` as the blind spell.

#### Three bugs found in play, and only one of them was a number

Reported as *"I tried to ram into the enemy, but there was no response, and the enemy doesn't seem to
do anything to me, aside from walk towards me."* All three had passed the probe, which is the lesson
as much as the bugs are.

- **It measured only the OTHER body's velocity.** `closing` came from
  `Weight.impact_velocity(body)` alone, so **a giant walking into a player who was standing still
  registered a closing speed of zero** and did nothing whatever. Fixed with
  `Weight.closing_speed()`, which is relative. The probe had only ever charged *at* him, so the case
  where he is the one doing the moving was never measured — hence the new check that he shoves you
  while you stand still.
- **A refused hit did nothing at all.** No stagger, no dust, no sound — and that is this project's
  own standing rule broken: **a refused hit has to read as "wrong tool", never as "no effect"**, the
  same law that makes a refused `BreakableBlock` shake and makes the warden announce what would
  work. `_stagger()` now rocks him by an amount that **scales with how close the hit came**, so a
  near miss is obviously a near miss and a feeble bump obviously is not — the threshold made legible
  without a word of UI, exactly as a pressure plate tints as it fills.
- **`topple_momentum` was 180 and measured absolutely**, so a charge without a long run-up failed.
  It is **200** now and the speed is relative, which includes his own approach: against a giant
  walking at you the hero brings about **182 at walking pace and 232 charging**, so the two separate
  cleanly instead of overlapping.

**The honest reading of this: the probe tested the rule and not the interaction.** Every check was
about whether a threshold was crossed; not one asked whether anything happened when it was not. Both
new checks are written the other way round.

#### `collide()` and `deliver()` are not interchangeable, and making them so broke both

While fixing the above, `Weight.collide()` was changed to use a relative closing speed too. That is
wrong, and the way it is wrong is worth keeping:

| | |
| --- | --- |
| **`collide(mover, hit, …)`** | "I moved into it and the solver stopped me" — measures the **mover's own** approach, and gives the mover back what the impact leaves it |
| **`deliver(arriving, receiver, …)`** | "it came to me and nothing was stopped" — measures the **relative** approach, and gives each side its true change |

Measure `collide()` relatively and it starts firing for collisions the mover did not cause — a crate
running into a stationary hero — and then shoves that hero **towards** the crate, cancelling out the
correct push the hitbox had already given them. The symptom was a thrown crate moving the player at
0.0 m/s having previously worked, which reads as the hitbox breaking rather than as the other half
double-counting.

#### Not named after anything

`HeavyEnemy`, not any of the doc's crew — the tortoise, the storks, the pelican and the
weaver-birds sit under a section marked **"DRAFT, return to this"**. This is the mass and the
behaviour; the costume is a later decision and the file should not quietly make it.

### A consistency bug the giant would have exposed on sight

**`Weight.add_momentum()` and `Weight.launch_momentum()`.** The slam's shockwave and the see-saw's
launcher both handed out a *velocity*, which meant **a 40-mass giant would have been flung exactly as
fast as a 1-mass pebble.** Momentum is the right currency for anything delivering a fixed amount of
force; a plain velocity is right only for `collide()`, where the mass is already inside the formula.

`slam_scatter_power` is therefore **40** rather than 6, and `SeeSaw.launch_per_force` **48** rather
than 6 — the same impacts, read in momentum. Divide by a mass to read either as a speed.

### Two props can be put back now

`PressurePlate.reset()` and `CrumblingFloor.reset()`, both public. **Not test scaffolding** — the doc
makes it a non-negotiable law: *"every destruction consequence is previewable; every puzzle state is
recoverable… respawning contraption pieces, room-reset levers, rebuild-on-reentry for discrete
puzzles."* A latching plate and a permanently-gone slab are exactly the discrete contraptions that
law is about, and a room-reset lever had nothing to call.

**Worth knowing: rule 6 was already satisfied.** `BreakableBlock.reset_delay` defaults to **-1.0**,
so world-scale breaks are permanent already; the tree fort's 3.0 and 4.0 values are crumbling
floors, which the doc explicitly allows local resets for. Nothing needed changing.

### The first tuning pass (2026-10-27), and the two things it contradicts

**The user played it and brought back their own numbers, and those are now the script defaults** —
`walk_speed` 15, `walk_accel` 10, `walk_decel` 7.5, `face_turn_speed` 7.5, `charge_accel` 15,
`charge_turn_rate` 5.0, `slide_friction` 5.0, `crash_stun` 0.5, `crash_bounce` 12, `min_authority`
0.2, `authority_zero_speed` 20, `air_authority` 0.5, `boost_taps` 1. They were overrides on the
Player node in `greybox_main.tscn`; they were moved into the script and **removed from the scene**,
so there is one place to read a default from and the scene cannot quietly shadow it.

Two of them pull against what this file says above, and neither is a bug — they are the tuning
telling us something, and they are written down rather than reconciled:

- **Walking is now 75% of charging** (15 against `charge_top_speed` 20), where it used to be 30%.
  So the charge barely buys speed any more; what it buys is the wall, the jump distance and the
  slam. And because `authority()` is a flat 1.0 at or below `walk_speed`, **full steering authority
  now reaches 15 m/s and the entire authority curve operates in the 5 m/s band between 15 and 20**.
  The "mass in flight" feel the doc describes only exists inside that window. If the modal split is
  meant to read clearly, the lever is the GAP between these two numbers, not either one alone.
- **Walk mode is no longer instant** (`walk_accel` 46 → 10). The doc calls walk mode the precision
  anchor, and the cardinal rule is that mass may take time but *input* must not. Worth watching for
  whether it now reads as weight or as lag. One knock-on: `_tick_windup` brakes at `walk_decel * 2`,
  which is 15 m/s² against a 15 m/s walk, so **the plant takes about a second — twice
  `charge_windup`**, and the telegraph is a slow lean rather than the hard stop the comment there
  describes.

**The stomp was tuned on 2026-10-30**, and these are defaults now too:
`slam_drop_accel` 95 → **300**, `slam_max_speed` 42 → **130**, `impact_force_scalar` 1.0 → **2.0**.
The stomp is now a near-instant plummet that hits twice as hard, which is the doc's build priority
being taken seriously — *"the slam is this game's A-press… the controller is tuned around the fall
feeling incredible before anything else."*

Two consequences to carry around:

- **Slam force is no longer a 0..1 number.** `impact_force_scalar` multiplies it, so what
  `Events.slam_landed` carries now reaches about **4.2** (a full-height drop plus delivered speed,
  doubled). Anything with a force threshold is reading a different scale than it was tuned on:
  `CrumblingFloor.slam_power_needed` (0.12) is now cleared by almost any landing, and the shockwave
  ring's own `clampf(force, 0.0, 1.5)` is pinned at maximum every time. Neither is wrong, but
  neither was chosen.
- **130 m/s is 2.17 m per physics frame.** `move_and_slide` sweeps its shape so the player will not
  tunnel through a floor, but an `Area3D` sensor thinner than that can be stepped straight over
  between frames. The breakable block's sensor is deliberately wider than the block for a related
  reason; if a prop ever fails to notice a stomp that visibly hit it, this is the first thing to
  check.

**And the 14 m gap is no longer in the level.** `GroundSouth` in `greybox_room.tscn` is a single
1000 x 1000 plane now, which makes the room a free-roam space to tune in but also removes the doc's
*"a gap only a charge-jump crosses"* test — a walking jump covers 15.5 m on its own at these
numbers. The probe's two gap checks had nothing left to measure; the "is there a gap" one is
**inverted rather than deleted**, so if the gap ever comes back it says so instead of staying quiet
about a check that had silently stopped meaning anything.

`tests/greybox_probe.gd` is the measurement harness; it is also currently the only test the new
controller has, so do not delete it until either the controller is adopted and gets a suite, or
Milestone 1 kills it.
## Reunifying the project (started 2026-10-31)

**The project has been split in two since Milestone 1** — an old `player.gd` carrying nine scenes
and a 109-check suite, and a `heavy_player.gd` carrying one greybox. The decision is to **collapse
it to one**: the heavy controller keeps everything worth keeping, the old player goes, and the
levels and systems come with it.

Two calls were made deliberately and both are worth knowing:

- **Rail grinding is PORTED, not retired.** The design doc's state diagram has no grind, so this is
  a verb the document does not contain — kept by an explicit decision rather than by the doc. By the
  doc's own standing rules (*"a proposal that violates one needs this document amended first, not an
  exception granted quietly"*) **the document wants amending to say so.**
- **Health and death are being REMOVED**, per the doc's *"there is no death"*. A hit becomes
  knockback plus a collectible scatter you can scramble back, which is the doc's field-damage model
  and which `game.gd` already does half of.

### Ian's level sets the shape of the delete

`scene_smilex.tscn` instances `scenes/player/player.tscn` **directly**, along with
`grapple_point.tscn` and the HUD. CLAUDE.md has said since the grapple was deleted that this needs a
conversation with Ian rather than a unilateral delete, and that still holds. So:

**`player.gd` and `player.tscn` stay on disk, marked deprecated, referenced only by Ian's level.**
Everything of ours stops pointing at them. That unifies the project without breaking somebody else's
work, and leaves the actual delete as a conversation instead of a merge conflict.

### Stage A: the heavy controller can do everything the old one could (done)

`State.GRIND`, `State.FLAMING` and `State.PUFFY` are on `heavy_player.gd`, measured by
`tests/greybox_probe.gd` against a rail and a speed-gated wall now in the greybox.

Three things the port had to re-wire by hand, which is why it is tested rather than assumed:

- **`_physics_process` returns before `move_and_slide()` while grinding.** The rail sets
  `global_position` itself and letting the physics body also move you drags you off the line. The
  port also fills `_pre_move_flat`/`_pre_move_vy` before returning, which the old controller did
  not — so grinding into a breakable block used to measure the speed from before the grind began.
- **`attack` is the rail accelerator, so it must not also throw or boost.** The grind takes the
  button over for its duration. That is the same conflict the spin had with it on the old
  controller, and it resolves the same way.
- **PUFFY takes `mass` to zero.** The doc's weight grammar for that form is literally *"mass zero:
  thresholds and pivots stop answering to you"*, and it costs **one line** because `mass` is a real
  number the weight layer reads — an inflated player stops holding pressure plates down and stops
  tipping see-saws without either prop knowing the state exists. Restored in `_set_state` on the way
  out, and captured in `_ready()` rather than on transforming so transforming twice cannot capture
  the zero.

**`flame_damage` was deliberately not ported.** The old FLAMING hurt enemies it touched; the doc
frames this form as *"destruction by other means — burns rope, thatch and timber that mass cannot
crack"*, which is a material language rather than a damage number. Nothing tested it either.

### Stage B1: the props stopped naming `Player` (done)

Seventeen scripts named the class; none do now. The pattern throughout is **ask by method name, not by
class** — `has_method(&"take_hit")`, `is_in_group(&"player")`, `call(&"respawn_at", …)` — which is
the same shape `weight.gd` already uses for mass and the `spinnable` group uses for attacks.

**And Stage B3 fell out of it for free.** `HeavyPlayer.take_hit(damage, from, coin_cost)` exists,
accepts the damage number and **ignores it**:

> Every hazard, enemy, bullet and boss already calls exactly that signature, so the no-death model
> belongs in ONE place rather than in a change to each of them. They hand over a damage number; this
> controller is simply not interested in it.

What happens instead is the doc's field-damage model — a reaction, knockback, and the money you were
carrying scatters where you lost it for you to scramble back. Measured: a 99-damage hit throws you at
11.9 m/s, emits `player_hurt` with the cost, and a second hit inside `hurt_invuln` is refused.

Three consequences worth knowing, all of them deliberate:

- **A "lethal" hazard is no longer lethal.** `instant_kill` calls `kill()` if the body has one and
  otherwise lands the hardest ordinary hit it can. The doc bans ejection from an arena outright and
  requires every penalty to be live and in-arena rather than travel time.
- **Garlic is inert**, because `heal()` does not exist any more. That is the honest state of it
  rather than an oversight: the doc replaces health with food that scatters when you are hit, and
  that system is not built. Until it is, a garlic is a coin that pays nothing.
- **A transformer prop has no effect on the deprecated controller.** Transformations are now asked
  for by NAME (`transform_named(&"FLAMING")`) rather than by passing an enum value, because the old
  controller's `FLAMING` is a different number from the modal one's and an int handed between two
  enums is a bug waiting for either to gain a member. The old suite transforms by calling the player
  directly, so nothing regressed.

### The skid and the side-jump (built 2026-10-31)

**Asked for as "a more immediate means to turn around", and the interesting part is that the doc
already had it:** *"Crash-stop / slide — ending a charge: hit something, slide out, or cancel into
slam. Stopping is itself a mechanic with a cost."*

A skid is allowed to exist where free steering is not, because **it does not turn you, it stops
you** — hard, over a visible slide, while your heading pivots ahead of your body. You pay in
distance for the direction, so the authority curve is untouched. And it is **deliberately not
reachable from CHARGE**: a charge has no free brakes, and a skid out of one would be exactly the free
brake the verb is defined by not having.

- **Entry is on the INPUT reversing, never the velocity.** The old controller's side flip paid for
  this lesson: heavy handling will not let velocity turn round quickly *by design*, so a move that
  waited for the velocity to reverse would never fire at all.
- **The side-jump is the same turn cashed in for height** — Mario 64's side flip, and it earns its
  place for the same reason: the authority curve will not reverse you, so the set needs exactly one
  move that does. It **sets** velocity rather than adding to it, like everything else here; the long
  jump was the only additive move and was the only one that could be farmed.

Measured: a reversal from 12 m/s brakes to 7.7 in ten frames with the heading already swung 86°
ahead of the travel, and jumping out of it leaves at **13.0 m/s upward against a standing jump's
9.0**.

#### The bug in it, which is a Godot one worth remembering

**`Vector3.slerp` between exactly opposite vectors is degenerate.** A skid is very often a precise
180° reversal, and there is no defined axis to turn about — so slerp returned the start unchanged and
the heading never moved at all, while every other part of the skid worked. Rotate about `Vector3.UP`
by a clamped `signed_angle_to` instead, which is what the charge's steering already did.

### Stage B: what is left, in dependency order

1. ~~Decouple the props from the `Player` class.~~ **Done — B1 above.**
2. **Retire the spin's names along with the spin.** `spin_switch`, `priced_gate`,
   `vending_machine`, `treasure` and the breakable block's spin path all use the `spinnable` group
   and `spin_hit()` — and the heavy controller has no spin. The slam already broadcasts position and
   force, so a weight-based strike is the natural trigger; the group and method should stop saying
   "spin" once there is no spin.
3. ~~Remove health and death.~~ **Done, as a side effect of B1** — see the `take_hit` note above.
   The HUD hides its hearts when the player has no Health, hazards fall back to a hard hit, and
   `game.gd` only respawns through a duck-typed `respawn_at`. Enemies keep their own health; the doc
   only says the *player* does not die.
4. **Repoint the eight scenes** to `heavy_player.tscn`.
5. **Rewrite the suite.** About 50 of its 109 checks test verbs that are being deleted — the Mario
   moveset, the spin chain. It will get smaller before it grows back, and `_run()` should be split
   into per-system functions while it is being rewritten; it has hung twice on a local-name
   collision in that one enormous scope.

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
    weight.gd        THE weight layer: mass, impact and momentum, as static
                     functions anything can call. Read this before adding a prop
                     that reacts to being hit
    game.gd          score, checkpoints, respawning
    events.gd        autoloaded signal bus, referred to in code as `Events`
    components/      health, thrown_flight, coin_thief, item_thief, weight_sensor
                     (drop-in Nodes, no matching scene)
    player/          heavy_player.gd (the modal controller, Milestone 1),
                     player.gd (the old moveset), abilities, camera, visuals, ledge sensor
    enemies/         walker, turret, bullet, boss_warden,
                     heavy_enemy (the structural giant — a puzzle noun)
    props/           coin, keg, checkpoint, hazard, crumbling floor, spin switch,
                     breakable block, treasure, level exit, transformer, grind rail,
                     priced gate, vending machine, platform seed, seed socket,
                     moving platform, see-saw, pressure plate (the weight layer)
    ui/              hud.gd
  scenes/            mirrors scripts/ — one scene per script
                     main.tscn (moveset showcase), playground.tscn (momentum),
                     tree_fort_main.tscn, rail_yard_main.tscn and
                     thief_arena_main.tscn, market_yard_main.tscn and
                     hostage_pit_main.tscn and warden_arena_main.tscn (experiments),
                     greybox_main.tscn (Milestone 1 — the heavy controller)
  tests/             moveset smoke test, plus throwaway level probes (fort, rail,
                     market, pit, warden, greybox)
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
- **A `StandardMaterial3D` created in code takes its compiled shader with it when it dies.** Godot
  compiles one shader per distinct material *configuration* and frees that shader the moment the
  last material using that configuration is destroyed. So an effect that calls
  `StandardMaterial3D.new()` and then frees itself makes the **next** one recompile — measured at
  about **28 ms, two dropped frames at 60 fps**. `shockwave.gd` did exactly this, and because the
  ring is both the spin's effect and the ground pound's, nearly every press of either stuttered.
  It hid from three separate probes in a row, because spamming the button keeps two rings alive at
  once and one of them always holds the shader — it only reproduces at a *human* pace, with a gap
  longer than the ring's own 0.38 s life. The fix: keep the material in the `.tscn` and
  `duplicate()` it per instance. The scene's copy is never freed, so the shader compiles once, and
  colours are uniforms rather than part of what Godot keys a shader on, so the duplicates all
  still share it. `jump_burst.tscn` had always done it that way, which is why the puff never
  stuttered and was the control that identified this.
- **A shader is compiled on first DRAW, not on load.** So even with the material shared, that one
  compile lands on the first spin of the session rather than during loading. `Game.prewarm_scenes`
  draws each code-spawned effect once at 2% alpha as the level starts; a scene opts in by
  implementing `prewarm()`. Two things about warming that are not optional: do it at **full size
  and real particle counts** (a version that shrank them to 2 cm measured as having changed
  nothing at all), and do it **inside the camera frustum**, because an effect that gets culled is
  never drawn and the warm-up then silently does nothing.
- **A `CSGPolygon3D` in Path mode bakes the path in WORLD space unless you set `path_local = true`.**
  It turns the path it follows into its own vertices, and with `path_local` left at its default of
  false those vertices are the path's *global* positions. Make the polygon a CHILD of the `Path3D`,
  which is the obvious way to arrange it, and it then inherits the path's transform on top — so the
  offset is applied twice, the model is drawn at double its distance from the origin, and anything
  reading the curve directly stays where it should. In the rail yard that put the rail you could
  see 44 m from the rail you could grind, and it reads as the collision being broken rather than
  the mesh being misplaced. `tests/rail_probe.gd` measures the mesh AABB against the curve now,
  because there is no way to notice this without measuring.
- **A collision property written INSIDE a `[node ...]` header is silently ignored.** Only `name`,
  `type`, `parent`, `instance`, `groups` and `unique_id` belong in the header; everything else is a
  property and goes on its own line underneath. Write
  `[node name="X" type="RigidBody3D" collision_layer=64]` and the node keeps the engine default
  instead — no warning, clean import, and the value you can read back in the Inspector looks
  nothing like the file. It cost two bugs at once here: a seed on the wrong layer, and a pit hazard
  whose mask stayed at 1 so it never noticed the player at all — a lethal pit that was not lethal.
  If a hand-written scene behaves as though a collision setting was not applied, check this first,
  and print the property at runtime rather than reading the file.
- **`AnimatableBody3D.sync_to_physics` defaults to TRUE, and its own documentation says "do not use
  together with `_physics_process()`".** Both halves matter. A moving platform driven by assigning
  `global_position` in `_physics_process` needs it explicitly set to **false** — leaving the line
  out does not disable it. With it on, the collision shape lags behind the node, so the platform
  draws in one place and collides in another and **the player falls straight through a platform
  they are standing on**, with `is_on_floor()` false the whole way down. Set it false and set
  `constant_linear_velocity` instead: that is what a `CharacterBody3D` reads to know its floor is
  moving, and without it a sideways platform slides out from under the player even though a
  vertical one appears to work (floor snapping keeps catching up with it).
- **Anything that can LET GO of a thing needs a blind spell before it can take that thing again.**
  Four for four in this codebase now: `ledge_cooldown`, the spin's `regrab_delay`,
  `grind_relatch_delay`, and `ItemThief.relatch_delay`. The shape is always the same — you let go
  while standing right next to the thing, so the very next frame picks it straight back up, and the
  release looks like it did nothing at all. The boss was the worst case: cracking it open dropped
  the seed at its own feet and it re-swallowed it on the following frame, so the phase change was
  genuinely happening and completely invisible. Assume the next one needs a delay too, and give it
  one before testing rather than after.
- **Sleeping `RigidBody3D`s are unreliable in `Area3D` overlap queries.** Grabbing a resting keg
  walks the `throwable` group by distance rather than using an area.
- **A `CharacterBody3D` does not push a `RigidBody3D`, and a `RigidBody3D` cannot push a
  `CharacterBody3D`.** Neither direction does anything at all — they are solved in separate passes,
  so a character treats a crate as a wall and the crate never hears about it. There is no setting
  for this; both halves have to be written by hand, and they need two different mechanisms:
  - **Us into them:** walk `get_slide_collision()` after `move_and_slide()` and `apply_impulse()`.
    Read the velocity from BEFORE the move (`approach_velocity()` / `_pre_move_flat`), because the
    solver has already zeroed it — the same trap as the breakable block, and it makes a head-on hit
    deliver nothing at all. Wake the body first (`sleeping = false`) or a settled crate ignores the
    impulse.
  - **Them into us:** `get_slide_collision()` only reports what WE moved into, so a crate flying at
    a standing player is invisible to it. That half needs a persistent `Area3D` on the player. An
    area is fine HERE, unlike for the spin, because it lives in the scene and is never moved or
    re-added before being queried.

  It cost this project a whole set of props that measured weight and could not deliver any: a
  see-saw, a pressure plate and a weight sensor that all worked perfectly and played as though
  nothing in the level was connected to anything.
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






## The first boss (experiment, 2026-10-16)

**The thing every system so far was pointing at, and the historical sore point of the Wario Land
games.** `scripts/enemies/boss_warden.gd`, in `scenes/warden_arena_main.tscn`.

### Two claims, and the second one is the useful half

**It has NO health, and you do not kill it.** You beat it by taking the seed off it and delivering
that seed to the socket — so **the hostage system is its health bar**, and the fight ends on a
specific act rather than on an accumulation of hits. A boss is a gate; this one is a gate
mechanically rather than narratively, because the exit is up there and the platform is the only way
up and the seed is in its hands.

**And no-death was only half of why those bosses failed.** The deeper problem is that they never
told you what they wanted, so you flailed until something worked. So every refusal here goes out on
`Events.boss_refused` with a line saying what WOULD work, and the HUD prints it:

> *"Not hard enough — pound it from higher up"*

That near miss is the most valuable string in the fight: the move was right and only the height was
wrong, and a player told that goes looking for somewhere to fall from. **A refused attack has to
read as "wrong tool", never as "no effect"** — the same rule that makes a refused `BreakableBlock`
shake instead of sitting there. Treat the hints as mechanics, not flavour. A phase without one is a
phase the player has to brute-force.

### Three phases, three different verbs, and the spin never works

| phase | the lock | what opens it |
| --- | --- | --- |
| **ARMOURED** | charges in locked straight lines, refuses everything | dodge so it crashes into a **pillar** |
| **STUNNED** | a closing window | a **ground pound** with `slam_power` over `crack_power` |
| **CRACKED** | it drops the seed and races you for it | **carry it to the socket**, with a thrown keg to buy time |

**The spin is refused in all three**, deliberately. The player's default attack being useless is
what forces the other verbs to be learned, and it is only fair because every refusal announces the
alternative.

**The charge direction is LOCKED when the charge starts and never corrected.** A charge that steers
cannot be dodged, so the arena would stop being part of the fight — and the arena is the whole of
phase one.

**It only stuns on pillars, not on the outer walls.** It stunned on any wall in the first version,
which meant it did phase one for the player: it wandered into a wall on its own and nobody ever had
to dodge anything. A level marks what counts by putting it in the `pillar` group — and note the
collider is the internal `StaticBody3D` a `CSGBox3D` makes for its collision, so the group is
checked on the parent too.

### The fail state, and there is no timer anywhere in it

Hit you and it takes money (`contact_coin_cost` 25). Hit you **while you are carrying the seed** and
it takes the seed back and re-armours: **you lose a phase, not a life.** WL4 bolted a timer onto its
bosses as a patch and this file has said so since the transformations went in, so there is no clock
on the fight — only on each opening you make, because the stun window closes on its own.

### The arena is tuned, not decorated

`slam_power()` is `fall / 12`, so the measured numbers are:

| | |
| --- | --- |
| a standing hop | 0.21 |
| `crack_power` | **0.50** |
| a drop from the pound deck at y=8 | **0.70** |

The deck is the accessible route into phase two and a clean triple jump is the show-off route,
which is the shape to keep: **beatable by a player who has not mastered everything, faster by one
who has.** The pillar at `x=-18` sits hard against the deck's edge on purpose — luring the boss to
crash *there* is what lets you already be up high at the moment it stuns.

### What to watch for in play

- **Phase three is the one most likely to be wrong.** It is a straight race for the seed, and the
  boss moves at `charge_speed * 0.72`. If it always wins, the dial is that multiplier or
  `ItemThief.relatch_delay` (2.5 on the boss, 1.5 by default) rather than making it weaker.
- **Nothing yet uses the kegs**, so whether throwing one is actually worth the detour is unproven.
  If it is not, phase three is a footrace rather than a decision.
- **It cannot be killed at all**, which means a player who gives up has no way to clear the arena.
  That is deliberate, but it does mean the only exit from a bad attempt is to walk away or restart.
## Enemies that hold the level hostage (experiment, 2026-10-16)

**The user's idea, and it is the first version of "enemies steal things" with real stakes in it.**
Framing the theft as money was not enough, because money is a number you can go and earn again. So
the thing an enemy takes is now **the way up**.

Four pieces:

| | |
| --- | --- |
| **`platform_seed.gd`** | a carryable object, picked up by the existing spin-carry system |
| **`seed_socket.gd`** | sits at the bottom of a pit; a seed delivered to it raises a platform |
| **`moving_platform.gd`** | an `AnimatableBody3D` that slides between two points and carries you |
| **`item_thief.gd`** | takes the seed and carries it **over its head**, visibly |

The loop: carry the seed, throw it in the pit, ride the platform it manifests to somewhere you
otherwise cannot reach. Let a snatcher take it first and **the exit is simply not available** until
you kill that enemy. `scenes/hostage_pit_main.tscn` is arranged so the platform is the only route
to the exit, which is the whole claim — `tests/pit_probe.gd` checks that the deck really is 12 m
above a floor with nothing in between, and that the platform's travel arrives at exactly deck
height rather than near it.

### The guarantee, which is stronger than the money one and has to be

The money thief had a rule: a thief is a container, not a sink. This needs more, because the
failure is worse. Lose money and you are poorer; **lose this and the level is unfinishable.** So
the seed rescues ITSELF, two ways:

- **`respawn_below_y`** — falls off the world, goes back where it started.
- **"not held but still frozen" is always wrong.** `pick_up()` freezes the seed and takes it off
  every collision layer. So if nothing is holding it and it is still in that state, a carrier went
  away without going through `drop()`, and the seed drops itself. Written as an invariant rather
  than as a reaction to one known cause, which turned out to matter: the first version only checked
  `is_instance_valid(carrier)`, and there is more than one way to lose a carrier.

**The safety is in the OBJECT, not in `item_thief.gd`, on purpose.** A component cannot be trusted
to tidy up after its own host, because an enemy can stop existing more than one way — killed,
thrown into a wall and burst, freed with the level — and those do not all run the same code. The
smoke test kills a carrier with `queue_free()` specifically to skip the `died` signal and prove the
seed does not need it.

### The socket polls by position, and refuses rather than eats

**It does not use `body_entered`.** A carried seed is on collision layer 0, so an enemy that
wandered into the pit holding it would never trigger an area — it would just stand there with the
level in its hands and nothing the player did could fix it. Checking the whole pit volume by
position every frame covers the carried case, and has the nice side effect that carrying the seed
down there yourself works exactly as well as throwing it.

**And a socket with no platform refuses the seed instead of consuming it.** That is the important
half rather than a tidy-up: the first version consumed the seed and then did nothing, because
`@export var platform: MovingPlatform` does not survive a `NodePath` written into a `.tscn` by
hand — a typed NODE export is converted by the editor, and a hand-written path arrives as a
NodePath that never becomes a node. The seed was gone, the platform never appeared, and the level
was unwinnable with nothing to explain why. **Any till, socket or receptacle that consumes
something irreplaceable should refuse when it cannot deliver.**

### What to watch for in play

- **A snatcher carrying the seed goes back to behaving like an ordinary enemy**, which means it
  comes after you with the level in its hands. That reads well, but a snatcher that *fled* would be
  more interesting and is not built.
- **Two snatchers escalate**, because killing the one holding the seed drops it and the other can
  pick it up. That was not designed, it fell out, and it is the best thing about the level.
- **The pit hazard only ever touches the player**, so neither the seed nor a snatcher is destroyed
  down there. The socket covers the whole pit floor for that reason — anything that ends up in the
  pit counts as delivered.
## Money to spend mid-level (experiment, 2026-10-15)

**Built because collectibles did not feel like they meant anything**, and the diagnosis matters more
than the props do. Two structural reasons, neither of them a tuning problem:

1. **The container rule guarantees recovery, and that is why there were no stakes.** Money a thief
   takes never leaves the world, on purpose, so you cannot be locked out of affording the exit. But
   that is the same rule that turns a loss into a detour. **Lockout-safety and stakes trade directly
   against each other whenever the stake is the money itself.** So the answer is not to make money
   riskier — it is to make money more *useful*, so losing it costs an opportunity rather than a
   number.
2. **The exit was the only sink, so its price was a binary gate.** Below the line nothing you
   collected mattered until you crossed it; above the line nothing you collected mattered at all. In
   a game about hoarding, **the next coin has to be worth something.** This was the bigger flaw, and
   it had nothing to do with the thieves.

So: two tills, and they are two deliberately different *kinds* of sink.

| | |
| --- | --- |
| **`priced_gate.gd`** | a one-off. Converts money into access and then stops being a choice |
| **`vending_machine.gd`** | repeatable. Keeps asking, so you decide again every time you walk past |

That difference is the point of having both. A decision you make repeatedly is worth more than one
you make once, and a gate alone is just a toll.

### Both are opened by the SPIN, not by walking into them

Two reasons, and the first is not negotiable: **a sink you can trigger by accident is a terrible
sink.** Being charged 30 for brushing against a door would be infuriating. The second is that
`spinnable` was already the documented extension point for exactly this — `spin_switch.gd` names "a
gate" in its own list of things that should answer to a spin. So both props do the same two things
anything spinnable does, and `player_abilities.gd` needed no change at all.

**`retrigger_delay` is load-bearing on a till in a way it is not on a switch.** A spin chain is
three spins, so without it one chain would pay three times or empty a machine — a quiet way of
robbing the player. There is a check for it.

### Game does the deducting, never the till

Tills emit `Events.money_spent` and `game.gd` applies it, clamped at zero. Same reason the hit spill
lives there: Game owns the running total, so it is the only place that can see whether a spend is
affordable, and with money as the win condition a negative total is a lockout waiting to happen.

**Worth knowing: the level exit does NOT go through this.** It only ever gated on the total and never
actually deducted, which makes no observable difference because the level ends on the frame it opens
— but it does mean "the exit charges you" is a threshold rather than a payment. That matters the
moment anything happens *after* an exit.

### The pricing rule, which is the actual level-design lever

**Put something behind a gate worth clearly more than the gate costs, and price the exit so that
paying up dips you below what the exit wants.** The scary part is not the 30 you handed over, it is
walking around at 100 with an exit that wants 110.

And **a gate must guard something optional, never the critical path.** A gate on the only route is a
toll, not a decision.

`scenes/market_yard_main.tscn` is the worked example, and its arithmetic is the content:

```
  safe plaza coins      16 x 5  =  80
  coins among thieves   10 x 5  =  50
  total on the floor            = 130
  exit                          = 110
  priced gate                   =  30, with a 70 chest behind it
  garlic                        =  10 each, five in stock
```

Which gives three real plays instead of one: **hoard** (130 covers the 110 with 20 spare — tight
enough that two thief hits you fail to recover means you cannot leave), **invest** (pay 30, be
underfunded at 100 for a while, then the chest pays 70), or **survive** (garlic competes directly
with both).

### Two things found building it

- **Set `emission_enabled` in the `.tscn`, not in code.** Both tills tint a *duplicate* of the
  scene's material, and emission is a feature flag — part of what Godot keys a shader on. Switch it
  on in code and the duplicate needs its own shader compiled, which is the stall documented under
  **Things that will bite you**. Setting it in the scene keeps every duplicate on one shader.
- **`_run()` in the smoke test is a single enormous scope**, so every local in it must be unique
  against every other one in the whole function. A collision is a parse error, the script then fails
  to load, and the scene runs with a null script and **never quits** — so it presents as the suite
  hanging rather than as a typo. The suite is now 93 checks and about 110 seconds; if it keeps
  growing, splitting `_run()` into per-experiment functions would fix both problems at once.
## Enemies that steal your money (experiment, 2026-10-15)

**The user's idea, and it answers the no-death question better than anything previously proposed
here.** `scripts/components/coin_thief.gd` — a drop-in Node you add to any enemy, which goes after
the money the player dropped and hands every coin of it back when killed.

Two reasons it is worth keeping:

- **It supplies the half of money-as-stakes that was missing.** This file already diagnosed why
  Sonic's version works: *"Sonic's rings work because they scatter and you have ~2 seconds to grab
  them back. That recovery scramble **is** the mechanic."* Coins already scattered, but nothing
  competed with the player for them, so the stakes came to a short walk back. A thief makes it a
  race. The walker's `chase_speed` (4.4) being well under the player's `max_speed` is what keeps
  that race winnable, and it must stay that way.
- **It gives a boss something to be ABOUT.** The exit charges you to leave, so an enemy holding your
  money stands between you and the win condition *mechanically*. Not beating it means not leaving —
  **a fail state that does not need you to die**, which is precisely what Wario Land's no-death
  design could never produce.

### A thief is a container, not a sink

The load-bearing rule, and everything in the component serves it. Money a thief takes **never leaves
the world**: it drops the lot when killed, it never despawns while carrying, and it cannot walk out
of the level. Break any of those and you re-arm the spiral this file has warned about since the
money loop went in — hit, poorer, cannot afford the exit, forced to stay in the dangerous level, hit
again. As a container there is no permanent loss, only a deposit you have to fight for, which is the
same Hollow Knight answer the project already chose once.

**It is also conserved by construction:** takes N, drops N. So deliberately feeding an enemy and
then killing it is worth exactly zero and cannot be farmed. `take_silently()` on the coin exists for
this — going through the normal pickup path would credit the player for money just stolen from them.

**The level-design half of the same rule:** price an exit so the level is still finishable even if a
thief keeps everything it took. The thief arena has 120 in coins against a 90 exit for that reason.

### Three details that are not polish

- **The tint is the mechanic.** A thief drifts towards gold as it fills up, because an enemy that
  silently walks off with your coins is indistinguishable from the money having vanished. Same
  reason `exit_refused` prints a shortfall instead of the exit quietly doing nothing, and the same
  reason the jump puffs exist. `Events.money_stolen` carries who took it and how much, and the HUD
  names them.
- **Loot outranks chasing you**, in `enemy_walker.gd`. A thief that ignores the player while it goes
  for the coins is what gives you the chance to get there first.
- **`coin.pickup_delay` is the player's head start**, and a thief respects it too. Without that, a
  thief standing nearby takes the coins on the frame they appear and the scramble is impossible.

### Where the movement lives, and why it is not in the component

The component only answers **where to go** — `target()` returns a coin or null, and
`enemy_walker.gd` steers there in preference to patrolling or chasing. The component never writes
`velocity`. That is on purpose: exactly one script per enemy owning its movement is worth more here
than the component being completely self-contained, and it is the opposite choice from
`ThrownFlight`, which does take the body over. The difference is that a thrown object stops being an
enemy for the duration, while a thief is still just a walker that wants to be somewhere else.

### The two honest limits

- **The stakes evaporate at zero.** A broke player has nothing to steal, so a boss has no leverage
  over exactly the player who is already struggling — the mirror of the "a good player is always
  rich, so they can never die" problem noted under the money loop. `steal_placed_coins` is the dial
  for that: a boss that eats the level's own coins and chests has leverage over anybody. Left false
  on ordinary enemies, because one that hoovered up placed coins would change how every level is
  built.
- **It is economic tension, not survival tension.** A boss that cannot kill you still cannot
  threaten you moment to moment. This makes no-death *viable* for bosses rather than equal to
  death, and `contact_coin_cost` is what decides how much a hit stings.

**Health and death were KEPT, deliberately and again.** Staged the same way money-as-stakes was, and
for the same reason: the grapple was rewritten four times because the ambitious version went in
before anyone knew whether the core felt good. If this carries the fail state in play, removing
hearts afterwards is easy and the number ranges will already be known. `scenes/thief_arena_main.tscn`
is where to judge it: 24 coins, three thieves, and an exit that wants 90 of the 120 on the floor.
## Rail grinding (experiment, 2026-10-13)

**The first experiment after the project stopped aiming at a particular game.** Sonic Adventure 2's
rails, asked for as "exactly like that game": the rail's slope decides your speed, weight affects it,
and `attack` accelerates.

- **`scripts/props/grind_rail.gd`** — a `Path3D` that holds the shape and answers three questions:
  how far along me is this point, where am I at that distance, and which way do I run there. It
  contains no movement code at all.
- **`Player.State.GRIND` and `_do_grind()`** — the movement. Keeps one number, `_rail_offset`, and
  asks the rail where that is.
- **`scenes/levels/rail_yard.tscn`** — four rails off one deck: downhill, flat, uphill and an
  S-curve, with a coloured post at the head of each. `tests/rail_probe.gd` checks it.

**Why it was a good first experiment, and the thing to keep:** it is the only thing built so far
that *tests* the slope system rather than sitting beside it. A rail is a slope you cannot steer off,
so it asks the same question a ramp does with the steering taken away. It also reuses `slope_gravity`
rather than introducing a gravity of its own, which means a rail physically cannot disagree with a
ramp about which way is downhill.

### This one IS a state, unlike the spin

The spin deliberately is not a `State` because it does not change how you move. Grinding changes
*everything* about how you move: no steering, no gravity, and **`move_and_slide()` does not run at
all** — `_physics_process` returns before it. The rail sets `global_position` directly, and letting
the physics body also move you drags you straight off the line. Same reasoning as `ThrownFlight`,
which moves its parent itself for the same reason. If a grind ever stutters or sags off the rail,
something re-enabled that.

### Weight, and why the obvious version of it does nothing

`g·sin(angle)` has no mass term, so "being heavier" cannot make a descent faster. Weight has to act
on the things that genuinely depend on it, and `grind_weight` divides two of them: **drag**, so a
heavier grind holds its speed better, and **the accelerator**, so it takes longer to get going under
its own power. Weight therefore buys top speed and costs response — the same trade the rest of the
character makes.

**Note that is the opposite sign from "heavy things grind slower".** If that is the feel wanted, the
change is a division to a multiplication in `_do_grind()` and nothing else.

### `attack` is rebound while grinding, which is a real conflict

While in `GRIND`, `attack` is the accelerator and `PlayerAbilities.handle_input` refuses the spin —
so the spin experiment loses its button for the duration. Refusing it is also consistent with the
transformation rule: a committed state you can attack your way out of is not committed. Worth
knowing if the spin is ever revisited.

### Four things found building it

- **Curve points are in the RAIL's local space.** Every question has a `to_local`/`to_global` in it.
  Miss one and the rail answers as though it were at the level origin, which looks exactly like the
  curve data being wrong and is not.
- **Rails dodge the row-major `Transform3D` trap**, because a rail needs no rotation — its shape is
  in the curve data. That is why the rail yard probe came back clean on the first run, which had
  never previously happened in this project.
- **The speed is kept SIGNED**, not as a magnitude plus a direction. One line of slope maths then
  handles both ways along a rail correctly. Write it with absolute values and an uphill grind
  accelerates, which reads as the rail's data being backwards.
- **`grind_relatch_delay` is the third time this trap has appeared**, after `ledge_cooldown` and the
  spin's `regrab_delay`: without it, jumping off re-attaches you on the very next frame, because you
  are still well inside the snap distance, and the jump looks like it did nothing. Assume any new
  "let go of a thing" needs one. Note `_place()` in the smoke test has to clear it *after*
  `_set_state`, because leaving `GRIND` sets the lock on the way out.


### Two bugs that only showed up in play, and what they share

Both lived where the tests could not see them, because the first version of the suite only ever
jumped off the MIDDLE of a rail.

- **A clamped sampling window can collapse, and then a fallback lies to you.** `tangent_at()`
  sampled the curve 5 cm either side of an offset and subtracted the two. `_do_grind()` overshoots
  the end of a rail by however far it travelled that frame — 0.27 m at 16 m/s, so nearly always —
  so the exit asked for the tangent past the end, both samples clamped on to the same point, the
  subtraction came out zero, and the degenerate branch returned a hardcoded `Vector3.FORWARD`.
  Every rail in the yard runs towards +Z, so leaving one launched you at −Z at full speed. Reported
  as "I sometimes dash in the opposite direction I was grinding", where "sometimes" meant "whenever
  you ran off the end instead of jumping off the middle". The window now slides inward so it always
  spans real distance.
- **A direction remembered between uses is a direction from the LAST use.** `_rail_dir` exists so a
  momentary zero speed does not lose which way you are going. But landing on a flat rail out of a
  fall projects to about zero speed along it, so there was nothing in the velocity to read a
  direction from — and `_rail_dir` still held the previous rail's. The accelerator then pushed you
  whichever way the rail before happened to point. It now falls back to `facing`.

**The shared lesson, and the one worth keeping: a fallback that returns a plausible value hides the
bug that reached it.** Both of these would have been obvious instantly from an assertion, and both
survived a 79-check suite because a hardcoded default looked like an answer.

### Known, and a decision rather than a bug

**Landing on a FLAT rail with no speed along it drops you straight off again.** The projection gives
you nothing, `grind_stall_speed` sees a stalled grind, and it lets go on the next frame. On any
sloped rail you are fine, because the slope gives you speed at once. Sonic Adventure 2 starts you
grinding with whatever you arrive with, so if that is the feel wanted, the fix is a floor on the
entry speed in `_attach_to_rail()`. Offered, not taken yet.
### Measured, running off the deck at 12 m/s

| | |
| --- | --- |
| downhill (9.5°) | 11.9 → **16.5 m/s** |
| flat | 12.0 → 7.0 m/s in two seconds, so you need the accelerator |
| uphill (5.7°) | 11.6 → **0.0 and you fall off** — coasting cannot finish it |
| the accelerator, flat rail | coasting 4.4 m/s against **17.7 m/s** holding `attack` |
| weight, same 9.5° rail | 1.0 → 7.3 m/s, 3.0 → **11.5 m/s** |

The uphill rail being uncompletable without the accelerator is the design working rather than a bug,
but it does mean that rail is currently a dead end for a player who does not know about the button.
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

**Superseded 2026-10-11 — see "What this is for, right now" at the top.** Kept in full because the
systems described here are built and working, and the reasoning behind each number still explains
the code you will be reading. Read "the target is" below as "the target was, while this experiment
was running". Nothing here obliges a future experiment to be Wario-shaped.

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
