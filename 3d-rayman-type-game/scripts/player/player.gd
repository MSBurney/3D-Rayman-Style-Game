class_name Player
extends CharacterBody3D

## Rayman-style 3D platformer controller.
##
## ─── START HERE ──────────────────────────────────────────────────────────────
##
## This file is about ONE thing: where the player is and how they move. It is
## still the longest file in the project, but you do not read it top to bottom.
## It goes:
##
##   1. enum State        — the list of things the player can be doing
##   2. @export variables — every tuning number, grouped as it appears in the
##                          Inspector. Change these first; you rarely need the code.
##   3. var declarations  — internal bookkeeping (timers, the current rope, etc.)
##   4. _physics_process  — the heartbeat. Read this to see the order of events.
##   5. _do_<state>()     — one function per state. Want to change the wall run?
##                          Go to _do_wall_slide(). That is the whole trick.
##   6. helpers           — wall/ledge transitions, damage, plumbing
##
## ─── THE REST OF THE PLAYER ──────────────────────────────────────────────────
##
## Anything that is NOT movement lives in a child node with its own small script.
## Each one is a separate file you can read in a couple of minutes, and each has
## its own tuning values in the Inspector:
##
##   Abilities        player_abilities.gd  grabbing and throwing objects
##   LedgeSensor      ledge_sensor.gd      "is there a ledge in front of me?"
##   GrappleTargeting grapple_targeting.gd "which target does the player mean?"
##   Visual           player_visuals.gd    the body meshes and which way they face
##   RopeLine         rope_line.gd         drawing the grapple rope
##   CameraRig        player_camera.gd     the third-person camera
##   Health           health.gd            hit points (shared with enemies)
##
## The pattern is: this script decides *what happens*, the child nodes handle
## *how it looks* or answer *questions about the world*. If you are adding
## something that does not change velocity, it probably belongs in a child node
## rather than in here.
##
## ─── GODOT CONCEPTS USED HERE ────────────────────────────────────────────────
##
## If you are new to Godot, these are the ones worth knowing before reading on:
##
## • CharacterBody3D — a physics body you move yourself, rather than one the
##   physics engine pushes around. You set `velocity`, then call move_and_slide()
##   and it handles sliding along walls and floors for you.
## • _physics_process(delta) — runs at a fixed rate (60x a second by default),
##   unlike _process which runs once per drawn frame. All movement lives here so
##   it behaves the same on fast and slow machines. `delta` is the seconds since
##   the last tick; multiplying by it is what makes speeds framerate-independent.
## • @export — exposes a variable in the Inspector so it can be tuned in the
##   editor without touching code. Almost every number below is one.
## • @onready var x = $Child — grabs a child node once the scene is fully built.
##   `$Name` is shorthand for get_node("Name").
## • signal — a message this node broadcasts without knowing who listens. Other
##   scripts connect to it. See `state_changed` below.
##
## ─── THE ONE DESIGN RULE ─────────────────────────────────────────────────────
##
## Abilities must *combine*, not take turns. Every state is written to hand off
## into the others — a swing releases into a dive, a dive bounces off an enemy
## into another dive, a wall run launches a grapple. If you add a state, make
## sure it has exits into the others rather than trapping the player inside it.
##
## The state machine is a plain enum plus a `match`, rather than Godot's node
## based approach, because these states share a lot of velocity maths and
## interrupt each other constantly. Keeping them in one file makes those
## hand-offs readable.

enum State {
	GROUND,
	## Ducked and still. The gateway to three moves rather than a move itself:
	## jump out of it for a backflip, build speed for a slide, and it is where
	## a ground pound lands.
	CROUCH,
	## Ducked and moving — the forward slide. Almost frictionless on purpose, so
	## slopes do the work.
	SLIDE,
	AIR,
	## Clinging to a wall, Mario-style, waiting for a wall kick. There used to be
	## a WALL_RUN as well; see the wall section for why it went.
	WALL_SLIDE,
	LEDGE_HANG,
	SWING,
	## The ground pound. Still called SLAM throughout — same move, and renaming
	## eleven exports would have been churn for nothing.
	SLAM,
	HURT,
	DEAD,
}

signal state_changed(from: State, to: State)

@export_group("Run")
## Top speed the stick alone will take you to. Note it is NOT a limit on how
## fast you can be going — slopes push you well past it, and nothing takes that
## away. See the Weight group.
@export var max_speed: float = 7.5
## The four numbers below are what make the character HEAVY.
##
## They used to be 65 / 75 / 110 / 0.45, which is a light, agile, twitchy
## character. Weight is only a trade if it costs you something, and what it
## costs here is *commitment*: you take about half a second to get going, slide
## a couple of metres before stopping, and cannot change your mind in mid-air.
## That cost is what makes the speed a slope gives you feel earned.
##
## If the character ever feels like treacle, these are the four to raise, and
## raise them together — they are one decision, not four.
@export var acceleration: float = 14.0
@export var deceleration: float = 12.0
## Used when the stick opposes current velocity. For a heavy character this is
## deliberately only a little above `acceleration`: a thing with mass does not
## get to reverse faster than it gets going.
@export var turn_acceleration: float = 18.0
@export_range(0.0, 1.0) var air_control: float = 0.15
## How fast the body model swings round to face the direction of travel (rad/s).
@export var visual_turn_speed: float = 14.0

@export_group("Jump")
@export var jump_height: float = 2.35
@export var gravity_rise: float = 22.0
@export var gravity_fall: float = 30.0
@export var max_fall_speed: float = 24.0
## Gravity is softened inside this vertical speed band around the apex, which is
## what makes a jump feel "hangy" and readable at the top.
@export var apex_threshold: float = 2.2
@export_range(0.0, 1.0) var apex_gravity_scale: float = 0.55
## Velocity kept when the jump button is released early.
@export_range(0.0, 1.0) var jump_cut: float = 0.42
@export var coyote_time: float = 0.12
@export var jump_buffer: float = 0.14

@export_subgroup("Jump chain")
## Mario's double and triple jump. Land and jump again inside this window and the
## next jump is the bigger one; let the window lapse and you are back to an
## ordinary jump. This is the one number that decides whether chaining feels
## generous or fiddly.
@export var jump_chain_window: float = 0.22
## Height of the second jump in a chain, as a multiple of `jump_height`.
@export var double_jump_scale: float = 1.35
## ...and the third, which is the payoff.
@export var triple_jump_scale: float = 1.85
## A triple jump needs you to actually be going somewhere, as Mario's does. Stops
## the biggest jump in the game being available while standing on the spot.
@export var triple_jump_min_speed: float = 3.0

@export_subgroup("Crouch moves")
## Below this speed, crouching ducks you on the spot; at or above it you slide.
@export var slide_min_speed: float = 3.5
## A slide ends when it drops below this, leaving you crouched.
@export var slide_stop_speed: float = 1.2
## Friction while sliding. Note what it has to beat is not `deceleration` but
## `momentum_friction` (3.5), which already preserves ground momentum above
## `max_speed` — so a slide set anywhere near that is barely different from just
## running, which is how this started out at 2.0 and read as nothing. Far lower
## than both, which is the point: a
## slide is for keeping speed and for letting a slope give you more.
@export var slide_friction: float = 1.0
## How much of the stick still steers a slide. Low — it is a commitment.
@export_range(0.0, 1.0) var slide_control: float = 0.12
## Backflip: crouch standing still, then jump. Goes up a long way and backwards.
@export var backflip_height: float = 4.2
@export var backflip_push: float = 5.0
## Long jump: crouch while running, then jump. Low and very long.
@export var long_jump_height: float = 1.5
@export var long_jump_push: float = 17.0
## Side flip: at speed, flick the stick back the way you came and jump.
##
## Triggered on the INPUT reversing, not on the velocity reversing. On a heavy
## character the velocity cannot turn round quickly by design, so waiting for it
## would mean the move never fires.
@export var side_flip_height: float = 3.6
@export var side_flip_push: float = 6.0
## How opposed the stick has to be to count, as a dot product against current
## travel. -0.5 is about a 120 degree flick.
@export var side_flip_dot: float = -0.5

@export_group("Wall moves")
## Mario's wall kick. There used to be a Rayman-style wall RUN here as well —
## run along a wall and it carries you — and it was removed when the moveset went
## Mario, because Mario has no equivalent and the two read as the same surface
## doing two different things.
@export var wall_slide_speed: float = 4.0
@export var wall_jump_up: float = 10.5
@export var wall_jump_push: float = 8.0
## Input is ignored briefly after a wall jump so it actually leaves the wall.
@export var wall_jump_lock: float = 0.16
## A wall only catches you if its face is this close to vertical.
@export var wall_cling_max_tilt: float = 0.4

@export_group("Ledge grab")
## Note: how a ledge is *detected* (reach, height band) is tuned on the
## LedgeSensor child node instead. These are about what the player does once
## one has been found.
## Where the body hangs below the lip.
@export var ledge_hang_drop: float = 1.55
@export var ledge_shimmy_speed: float = 2.4
@export var ledge_climb_up: float = 10.5
@export var ledge_climb_forward: float = 3.5
@export var ledge_cooldown: float = 0.28

@export_group("Grapple")
## Grace period after hooking on, before the grapple button can let go again.
## Without it the button press that attaches you is still "just pressed" when the
## swing code runs later in the SAME frame, so you detach instantly. It also
## means a quick tap still gets you a short swing rather than nothing.
@export var grapple_repress_delay: float = 0.2

@export_subgroup("Swing")
## Gravity while swinging.
##
## Its own number, and deliberately NOT routed through `_apply_gravity()` — that
## function softens gravity near the apex and clamps the fall to `max_fall_speed`,
## and both of those are caps. Nothing in the swing is allowed to cap speed; a
## pendulum that cannot wind up is not worth having.
@export var swing_gravity: float = 26.0
## How hard the stick accelerates you along the arc.
##
## There is NO speed limit on this, on purpose. Winding a swing up as far as you
## can be bothered to and spending it on one enormous jump IS the mechanic.
@export var swing_pump_accel: float = 26.0
## How fast `grab` shortens the rope and `drop` lets it out.
##
## Reeling in while moving fast is the main exploit the swing offers: the same
## angular rate on a shorter rope is a faster one, so rope length converts
## straight into speed. That is meant to be there.
@export var swing_reel_speed: float = 16.0
## Shortest the rope can get. Reach this and you are at the anchor itself, so you
## bounce off it — see the Anchor bounce settings below.
@export var swing_min_rope: float = 1.4
## Longest the rope can be let out to. A bound on the ROPE, not on your speed.
@export var swing_max_rope: float = 45.0
## Steering while the rope is SLACK, i.e. in free flight inside the arc or up
## over the top of the anchor. Added as acceleration rather than steering toward
## `max_speed`, because moving toward a target speed would brake a fast swing.
@export var swing_slack_accel: float = 14.0

@export_subgroup("Anchor bounce")
## Height of the bounce when you reel all the way in to the anchor, as a
## multiple of `jump_height`. At 1.0 arriving returns exactly as much height as a
## jump would, so it never costs altitude. Anchors can scale this themselves.
@export var anchor_bounce_height_scale: float = 1.0
## Fraction of your horizontal speed kept through that bounce. Arrive fast and
## you leave fast — the bounce reads as a launch rather than a full stop.
@export var anchor_bounce_keep: float = 0.6

@export_group("Slam")
## The GROUND POUND. Crouch in mid-air to drive yourself into the floor.
##
## It used to be on jump-in-air and it used to bounce you back up to jump height,
## with every third one in a chain throwing you 50% higher. All of that is gone:
## the bounce conflicted with Mario's double and triple jump, which need the jump
## button free in mid-air. A pound now simply ends on the ground, as Mario's does.
##
## What was kept is the fall-distance scaling, because that is the one part that
## carried the weight-is-a-resource idea: everything below scales with how far
## you fell, measured from the highest point since you last touched the ground. A
## short hop does very little; a drop from a tower does a lot. That is what makes
## height a resource worth going and fetching rather than just somewhere you are.
@export var slam_speed: float = 30.0
## The fall that counts as "full power". Longer falls do not add more.
@export var slam_power_height: float = 12.0
@export var slam_damage_min: int = 1
@export var slam_damage_max: int = 4
## Shockwave reach. Even the minimum is wider than the player, so a slam always
## catches what is standing next to you, not only directly underneath.
@export var slam_radius_min: float = 2.5
@export var slam_radius_max: float = 7.0
## How hard the shockwave shoves enemies away from the impact.
@export var slam_knockback: float = 9.0
## How long you are stuck on the floor after landing one. Mario's pound has a
## recovery; without one you can cancel straight out of it and it reads weightless.
@export var slam_recover_time: float = 0.22
## Horizontal speed kept during the drop. Low on purpose — committing to a slam
## should mean committing to where it lands.
@export_range(0.0, 1.0) var slam_air_control: float = 0.15
## The expanding ring drawn at each impact. Without it the shockwave is an
## invisible radius and the fall-distance scaling cannot be seen at all.
@export var shockwave_fx: PackedScene

@export_group("Sounds")
## Placeholder blips, generated by tools/make_placeholder_sounds.gd. Drop real
## recordings onto these slots in the Inspector to replace them — no code change.
@export var sfx_jump: AudioStream
@export var sfx_land: AudioStream
@export var sfx_hurt: AudioStream
@export var sfx_grapple: AudioStream
@export var sfx_slam: AudioStream

@export_group("Weight")
## Gravity pulling you down a slope. This is the game's momentum engine.
##
## `move_and_slide()` does not do this for you: left alone it walks you up and
## down a ramp at whatever speed the stick asks for, which for a heavy character
## is exactly wrong. A ramp has to be free speed going down and a real cost going
## up, or it is just a differently-shaped floor.
##
## Momentum living in the LEVEL rather than in an ability is deliberate. A ramp
## is content, so each level decides how fast it is by where ramps are put —
## unlike a traversal ability, which every level then has to be built around.
##
## Two useful thresholds fall out of this number rather than needing their own
## settings, because the pull is scaled by the slope's steepness:
##   • steeper than about 27 degrees and the pull beats `deceleration`, so you
##     slide down even standing still
##   • steeper than about 7 degrees and it beats `momentum_friction`, so once
##     you are above `max_speed` you keep gaining
## Raise it and both thresholds get gentler.
@export var slope_gravity: float = 30.0
## Slopes shallower than this are treated as flat. Without it, floating-point
## noise in the floor normal gives a dead-flat surface a tiny permanent drift.
@export var slope_min_grade: float = 0.06
## How fast speed ABOVE `max_speed` bleeds away while you are on the ground.
##
## Low on purpose: a heavy thing keeps rolling. This is the ONLY place momentum
## decays, and it is a slow bleed rather than the hard brake the normal stick
## handling would apply. It never takes you below `max_speed`, so it cannot
## interfere with ordinary running.
@export var momentum_friction: float = 3.5

@export_group("Combat")
## Punch and carry tuning lives on the PlayerAbilities child node instead.
@export var stomp_bounce: float = 11.0
@export var hurt_time: float = 0.45
@export var hurt_knockback: float = 7.0
@export var hurt_lift: float = 5.0

var state: State = State.AIR
## Horizontal facing of the body model, also used to aim ledge probes and throws.
var facing: Vector3 = Vector3.FORWARD
var wish_dir: Vector3 = Vector3.ZERO
var move_input: Vector2 = Vector2.ZERO

var _coyote: float = 0.0
var _jump_buffered: float = 0.0
var _jumping: bool = false
var _jump_released: bool = true
## How many jumps of the current chain are already behind us: 0 means the next
## one is an ordinary jump, 1 a double, 2 a triple. Read by the HUD.
var jump_chain: int = 0
## How long the chain stays alive now that we are back on the ground. Set on
## landing, counted down while grounded, and when it runs out the chain is lost.
var _chain_window: float = 0.0
## Stuck-on-the-floor time left after a ground pound.
var _slam_recover: float = 0.0
var _wall_normal: Vector3 = Vector3.ZERO
var _wall_lock: float = 0.0
var _ledge_lock: float = 0.0
var _grapple: Node3D = null
## Current rope length while swinging. Set from the distance you hooked at, then
## changed only by reeling — see _do_swing.
var _rope_length: float = 0.0
## Whether the rope is pulling right now. False means slack, which means free
## flight: the rope only pulls, it never pushes. Read by the F3 readout.
var _rope_taut: bool = false
var _grapple_lock: float = 0.0
var _grapple_buffered: float = 0.0
var _hurt_left: float = 0.0
var _spawn: Transform3D
var _pre_move_vy: float = 0.0
## Highest point reached since last touching the ground. The slam measures its
## power against this, so a fall counts from wherever you actually came down from.
var _air_peak_y: float = 0.0



@onready var rig: PlayerCamera = $CameraRig
@onready var health: HealthComponent = $Health
@onready var targeting: GrappleTargeting = $GrappleTargeting
@onready var ledges: LedgeSensor = $LedgeSensor
@onready var abilities: PlayerAbilities = $Abilities
@onready var visual: PlayerVisuals = $Visual
@onready var hold_point: Node3D = $Visual/HoldPoint
@onready var rope_line: RopeLine = $RopeLine
@onready var sfx: AudioStreamPlayer3D = $Sfx


func _ready() -> void:
	_spawn = global_transform
	facing = -global_transform.basis.z
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	rope_line.visible = false
	Events.player_health_changed.emit(health.current, health.max_health)


## The heartbeat. Runs 60 times a second, and the ORDER here matters a lot.
##
## Each step only decides what `velocity` should be. Nothing actually moves until
## move_and_slide() near the bottom — that is the call that takes our velocity,
## slides the body along walls and floors, and stops it hitting things.
func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_read_input()

	# Run exactly one state's logic. `match` is GDScript's switch statement.
	# To change how an ability feels, edit its _do_ function below.
	match state:
		State.GROUND: _do_ground(delta)
		State.CROUCH: _do_crouch(delta)
		State.SLIDE: _do_slide(delta)
		State.AIR: _do_air(delta)
		State.WALL_SLIDE: _do_wall_slide(delta)
		State.LEDGE_HANG: _do_ledge_hang(delta)
		State.SWING: _do_swing(delta)
		State.SLAM: _do_slam(delta)
		State.HURT: _do_hurt(delta)
		State.DEAD: _do_dead(delta)

	# Remember how fast we were falling BEFORE the collision is resolved, because
	# move_and_slide() is about to zero it if we land on something. Enemies read
	# this to tell a stomp from a bump. See descent_speed().
	_pre_move_vy = velocity.y

	move_and_slide()

	# Only NOW do is_on_floor() and is_on_wall() mean anything — they report what
	# move_and_slide() just bumped into. Anything that depends on touching a
	# surface has to happen after this line, which is what _after_move() is for.
	_after_move(delta)

	_update_visual(delta)
	_update_rope()


# ---------------------------------------------------------------- input & timers

## Counts every timer down by `delta` (the seconds since the last tick).
##
## Two of these are standard platformer forgiveness tricks, and they are most of
## the reason the jump feels fair rather than fussy:
##
## • COYOTE TIME — after you walk off an edge you can still jump for a moment,
##   named after the cartoon pause before the fall. Without it, players who press
##   jump a frame or two late get no jump at all and blame the game.
## • JUMP BUFFER — if you press jump slightly before landing, the press is
##   remembered and fires the instant you touch down, instead of being dropped.
func _tick_timers(delta: float) -> void:
	# Refill coyote time while grounded; drain it once airborne.
	# Remember the high point of this flight; the slam spends it on impact.
	if is_on_floor():
		_air_peak_y = global_position.y
	else:
		_air_peak_y = maxf(_air_peak_y, global_position.y)

	_coyote = coyote_time if is_on_floor() else _coyote - delta
	_jump_buffered -= delta
	_wall_lock -= delta
	_ledge_lock -= delta
	_grapple_lock -= delta
	_grapple_buffered -= delta
	_slam_recover -= delta

	# The jump chain only decays on the ground. Let the window lapse without
	# jumping again and the chain is lost, which is what stops the triple jump
	# from being available any time you happen to touch down.
	if is_on_floor():
		_chain_window -= delta
		if _chain_window <= 0.0:
			jump_chain = 0


func _read_input() -> void:
	move_input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var basis := rig.flat_basis()
	wish_dir = (basis * Vector3(move_input.x, 0.0, move_input.y))
	if wish_dir.length_squared() > 1.0:
		wish_dir = wish_dir.normalized()

	if Input.is_action_just_pressed(&"jump"):
		_jump_buffered = jump_buffer
	if Input.is_action_just_pressed(&"grapple"):
		_grapple_buffered = jump_buffer
	if Input.is_action_just_released(&"jump"):
		_jump_released = true
		if _jumping and velocity.y > 0.0:
			velocity.y *= jump_cut
			_jumping = false

	if state != State.DEAD and state != State.HURT:
		_update_targeting()
		# `grab` doubles as reel-in while swinging, so hand-grabbing is switched
		# off for the duration. Without this, holding it to reel also tries to
		# pick up every keg you swing past.
		abilities.handle_input(get_physics_process_delta_time(), state != State.SWING)

	if Input.is_action_just_pressed(&"debug_toggle"):
		Events.debug_toggled.emit(true)


## The stick fights current velocity harder than it accelerates, so turnarounds
## are crisp but top speed still takes a moment to build.
func _accel_for(current: Vector3, wanted: Vector3) -> float:
	if wanted.length_squared() < 0.01:
		return deceleration
	if current.length_squared() > 1.0 and current.normalized().dot(wanted.normalized()) < 0.0:
		return turn_acceleration
	return acceleration


## Steers horizontal velocity toward what the stick is asking for.
##
## `keep_momentum` is what stops this function being a speed cap in disguise.
## Normally it moves your speed *toward* `max_speed`, which means it brakes you
## as readily as it accelerates you. That is wrong for anything that arrives
## going fast: speed earned on a slope, or carried out of a swing, gets quietly
## confiscated a moment after you earn it. Above `max_speed` the stick is allowed
## to REDIRECT your momentum but never to brake it away.
##
## `bleed` is how fast that surplus decays anyway, in metres per second per
## second. Zero in the air, a slow trickle on the ground. It can never take you
## below `max_speed`, so ordinary running is untouched by it.
##
## Note that turning hard still costs you, because `move_toward` on a reversed
## target passes through zero on the way. That is not a bug to route around: a
## heavy thing should not get to change its mind at speed for free.
func _apply_horizontal(delta: float, scale: float = 1.0, control: float = 1.0,
		keep_momentum: bool = false, bleed: float = 0.0) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var top := max_speed * scale
	var speed := flat.length()
	var wanted := wish_dir * top

	if keep_momentum and speed > top:
		var heading := flat / speed
		if wish_dir.length_squared() > 0.01:
			heading = wish_dir.normalized()
		wanted = heading * maxf(top, speed - bleed * delta)

	var rate := _accel_for(flat, wanted) * control * delta
	flat = flat.move_toward(wanted, rate)
	velocity.x = flat.x
	velocity.z = flat.z


## Gravity's pull along a slope, which is where all the game's speed comes from.
##
## The maths is the schoolbook one: take gravity, remove the part that pushes
## into the surface, and what is left points straight downhill with magnitude
## `g * sin(angle)`. Projecting it like this is what makes a gentle ramp gentle
## and a steep one brutal, with no per-slope tuning at all — and it comes out as
## exactly zero on flat ground, so there is nothing to switch off.
##
## Only the horizontal part is used. The vertical part is already handled, by
## gravity and by `move_and_slide()` keeping us on the floor, and adding it twice
## makes the body chatter on the surface.
func _slope_pull(delta: float) -> void:
	if not is_on_floor():
		return
	var normal := get_floor_normal()
	var downhill := Vector3.DOWN - normal * Vector3.DOWN.dot(normal)
	if downhill.length() < slope_min_grade:
		return
	velocity.x += downhill.x * slope_gravity * delta
	velocity.z += downhill.z * slope_gravity * delta


func _apply_gravity(delta: float, scale: float = 1.0) -> void:
	var g := gravity_rise if velocity.y > 0.0 else gravity_fall
	if absf(velocity.y) < apex_threshold:
		g *= apex_gravity_scale
	velocity.y = maxf(velocity.y - g * scale * delta, -max_fall_speed)


## How fast to launch upward to reach exactly `jump_height` metres.
##
## Derived rather than hand-tuned, so `jump_height` can be set in real metres and
## stays correct when gravity changes. From v² = 2·g·h, solve for v.
func _jump_velocity() -> float:
	return sqrt(2.0 * gravity_rise * jump_height)


## Jumps only if a press is waiting in the buffer. Returns whether it jumped, so
## callers can tell whether to change state.
##
## Handles Mario's jump chain: land and jump again quickly and you get the double
## jump, then the triple. `jump_chain` counts how many are already behind you
## and `_chain_window` is how long the chain stays alive once you are grounded.
##
## Also handles the side flip, because it is a jump too — just one that throws
## you the other way. Keeping both here means every exit from GROUND goes through
## one function and no state has to know the difference.
func _try_jump() -> bool:
	if _jump_buffered <= 0.0:
		return false
	_jump_buffered = 0.0
	_coyote = 0.0
	_jumping = true
	_jump_released = false

	if _wants_side_flip():
		_side_flip()
		return true

	var height := jump_height
	match jump_chain:
		1:
			height = jump_height * double_jump_scale
		2:
			# A triple jump has to be earned by going somewhere, as Mario's is.
			# Too slow and the chain quietly starts again from an ordinary jump.
			if _flat_speed() >= triple_jump_min_speed:
				height = jump_height * triple_jump_scale
			else:
				jump_chain = 0
	jump_chain = (jump_chain + 1) % 3

	velocity.y = sqrt(2.0 * gravity_rise * height)
	play_sfx(sfx_jump)
	return true


func _flat_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## True when the stick is pointed back the way we came while we still have speed.
## Read before the chain, so a side flip never consumes a double jump.
func _wants_side_flip() -> bool:
	var speed := _flat_speed()
	if speed < slide_min_speed or wish_dir.length_squared() < 0.04:
		return false
	var travel := Vector3(velocity.x, 0.0, velocity.z) / speed
	return wish_dir.normalized().dot(travel) <= side_flip_dot


## Mario's side somersault: straight up, and off the way you are now pointing.
func _side_flip() -> void:
	var away := wish_dir.normalized() * side_flip_push
	velocity.x = away.x
	velocity.z = away.z
	velocity.y = sqrt(2.0 * gravity_rise * side_flip_height)
	facing = wish_dir.normalized()
	# Not part of the chain: a side flip is its own answer to being at speed, and
	# letting it feed the triple jump would make the biggest jump too easy.
	jump_chain = 0
	play_sfx(sfx_jump)


## Backflip — crouch still, then jump. High, and backwards.
func _backflip() -> void:
	_jump_buffered = 0.0
	_jumping = true
	_jump_released = false
	var back := -_flatten(facing) * backflip_push
	velocity.x = back.x
	velocity.z = back.z
	velocity.y = sqrt(2.0 * gravity_rise * backflip_height)
	jump_chain = 0
	play_sfx(sfx_jump)
	_set_state(State.AIR)


## Long jump — crouch at a run, then jump. Low, and a very long way.
##
## The push is added to the speed already there rather than replacing it, so a
## long jump out of a fast slide down a ramp goes further than one off the flat.
## That is the whole reason this move and the slope system belong in the same
## game.
func _long_jump() -> void:
	_jump_buffered = 0.0
	_jumping = true
	_jump_released = false
	var forward := _flatten(facing)
	if forward == Vector3.ZERO:
		forward = _flatten(velocity)
	var flat := Vector3(velocity.x, 0.0, velocity.z) + forward * long_jump_push
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = sqrt(2.0 * gravity_rise * long_jump_height)
	jump_chain = 0
	play_sfx(sfx_jump)
	_set_state(State.AIR)


# ------------------------------------------------------------------------ states

func _do_ground(delta: float) -> void:
	# Order matters: the slope adds speed, then the stick steers what is there.
	_slope_pull(delta)
	# keep_momentum with a slow bleed, so speed earned on a ramp is not taken
	# away the instant you stop steering — but does not last for ever either.
	_apply_horizontal(delta, 1.0, 1.0, true, momentum_friction)
	# Stop gravity accumulating into a huge downward number while grounded.
	velocity.y = minf(velocity.y, 0.0)

	if _try_jump():
		_set_state(State.AIR)
		return
	# Crouching forks on how fast you are going, which is how one button covers
	# four moves: duck on the spot, or slide.
	if Input.is_action_pressed(&"crouch"):
		_set_state(State.SLIDE if _flat_speed() >= slide_min_speed else State.CROUCH)
		return
	# The grapple is usable from standing too, now that it has its own button.
	if _try_grapple():
		return
	if not is_on_floor():
		_set_state(State.AIR)


## Ducked and still. A junction rather than a move: jump out of it to backflip,
## get moving to slide, let go to stand up.
func _do_crouch(delta: float) -> void:
	_slope_pull(delta)
	# No stick authority at all while ducked, so a crouch is a real stop. The
	# slope can still drag you, which is what turns a steep ramp into a slide.
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(
		Vector3.ZERO, deceleration * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = minf(velocity.y, 0.0)

	# Recovering from a ground pound: nothing gets you out of it early. A pound
	# you can cancel instantly out of has no weight to it.
	if _slam_recover > 0.0:
		_jump_buffered = 0.0
		return

	if _jump_buffered > 0.0:
		_backflip()
		return
	if not Input.is_action_pressed(&"crouch"):
		_set_state(State.GROUND)
		return
	if _flat_speed() >= slide_min_speed:
		_set_state(State.SLIDE)
		return
	if not is_on_floor():
		_set_state(State.AIR)


## The forward slide. Nearly frictionless on purpose: the slide is for keeping
## the speed you have and letting a slope add to it, so the only thing taking
## speed off you is `slide_friction`, which is a sixth of normal braking.
func _do_slide(delta: float) -> void:
	_slope_pull(delta)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var steer := wish_dir * max_speed
	# Steering is weak and never braking: a slide you can stop out of is just
	# walking.
	if wish_dir.length_squared() > 0.04:
		flat = flat.move_toward(
			steer.normalized() * flat.length(), acceleration * slide_control * delta)
	flat = flat.move_toward(Vector3.ZERO, slide_friction * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = minf(velocity.y, 0.0)

	if _jump_buffered > 0.0:
		_long_jump()
		return
	if not Input.is_action_pressed(&"crouch"):
		_set_state(State.GROUND)
		return
	if _flat_speed() < slide_stop_speed:
		_set_state(State.CROUCH)
		return
	if not is_on_floor():
		_set_state(State.AIR)


func _do_air(delta: float) -> void:
	if _wall_lock <= 0.0:
		# keep_momentum: speed brought in from a slope or a long jump is not
		# braked away by the air control. See _apply_horizontal.
		_apply_horizontal(delta, 1.0, air_control, true)
	_apply_gravity(delta)

	# Coyote jump: still allowed for a beat after walking off an edge.
	if _coyote > 0.0 and _try_jump():
		return

	# Crouch in mid-air is the ground pound. It used to be jump-in-air, which the
	# double and triple jump now need.
	if Input.is_action_just_pressed(&"crouch"):
		_jump_buffered = 0.0
		_set_state(State.SLAM)
		return

	if _try_grapple():
		return

	if _ledge_lock <= 0.0 and velocity.y <= 0.5 and _find_ledge():
		_set_state(State.LEDGE_HANG)


## Driving into the ground. Committed: barely any steering, no cancelling.
## The landing itself is handled in _after_move, where is_on_floor() is valid.
func _do_slam(delta: float) -> void:
	_apply_horizontal(delta, 1.0, slam_air_control)
	velocity.y = -slam_speed


## How much stored height this slam is worth, as 0..1.
##
## Measured from the highest point reached since last touching the ground, so it
## counts the whole descent — a jump that peaked high, or a walk off a tower,
## both pay out. This is the number that makes height worth fetching.
func slam_power() -> float:
	var fall := maxf(0.0, _air_peak_y - global_position.y)
	return clampf(fall / maxf(slam_power_height, 0.01), 0.0, 1.0)


## The landing: shockwave out, and you stay down.
##
## No rebound and no combo count. Both were removed when the moveset went Mario:
## the bounce needed the jump button in mid-air, which the double and triple jump
## now own, and a pound that launches you is not a pound.
func _slam_impact() -> void:
	var power := slam_power()
	var at := global_position

	var radius: float = lerpf(slam_radius_min, slam_radius_max, power)
	var damage := int(roundf(lerpf(float(slam_damage_min), float(slam_damage_max), power)))

	_spawn_shockwave(at, radius, false)

	# Everything standing in the shockwave takes the hit, not just whatever was
	# directly underneath — that is what makes a slam feel like weight rather
	# than a precise stomp.
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Node3D
		if enemy == null:
			continue
		var offset := enemy.global_position - at
		if offset.length() > radius:
			continue
		var health := enemy.get_node_or_null(^"Health") as HealthComponent
		if health != null:
			health.damage(damage)
		var body := enemy as CharacterBody3D
		if body != null:
			var away := _flatten(offset)
			if away == Vector3.ZERO:
				away = -_flatten(facing)
			body.velocity += away * slam_knockback + Vector3.UP * slam_knockback * 0.35

	play_sfx(sfx_slam)
	# Breakable floors and pressure plates will listen for this. `power` lets
	# them demand a real drop rather than firing on any landing.
	Events.slam_landed.emit(at, power)

	velocity = Vector3.ZERO
	_air_peak_y = at.y
	_jumping = false
	_jump_released = true
	# A pound must not feed the jump chain. Without this, pounding and then
	# jumping out of the recovery would hand you a double jump for free, and the
	# chain is supposed to be earned by landing three jumps cleanly.
	jump_chain = 0
	# Eat anything buffered during the drop, so a jump held on the way down does
	# not fire the instant you land and cancel the recovery.
	_jump_buffered = 0.0
	_coyote = 0.0
	_slam_recover = slam_recover_time
	_set_state(State.CROUCH)


## Draws the ring showing how far the shockwave actually reached.
func _spawn_shockwave(at: Vector3, radius: float, combo: bool) -> void:
	if shockwave_fx == null:
		return
	var ring := shockwave_fx.instantiate() as Node3D
	# Parented to the level, not the player, so it stays where it went off
	# instead of riding along on the bounce.
	get_tree().current_scene.add_child(ring)
	ring.global_position = at
	if ring.has_method(&"play"):
		ring.call(&"play", radius, combo)


## Clinging to a wall, waiting for a kick off it.
##
## This is the whole wall game now. There used to be a WALL_RUN as well, which
## carried you along a surface at a fixed clip if you hit it with enough speed —
## a good Rayman move and a bad Mario one. With both in, the same tan wall would
## sometimes carry you sideways and sometimes catch you, decided by a speed
## threshold the player could not see, which made every wall a coin toss.
func _do_wall_slide(delta: float) -> void:
	_apply_horizontal(delta, 1.0, air_control)
	_apply_gravity(delta)
	velocity.y = maxf(velocity.y, -wall_slide_speed)

	if _jump_buffered > 0.0:
		_wall_jump()
		return
	if not is_on_wall():
		_set_state(State.AIR)
	elif is_on_floor():
		_set_state(State.GROUND)


func _wall_jump() -> void:
	_jump_buffered = 0.0
	_jumping = true
	_jump_released = false
	velocity = _wall_normal * wall_jump_push + Vector3.UP * wall_jump_up
	_wall_lock = wall_jump_lock
	facing = _flatten(_wall_normal)
	_set_state(State.AIR)


func _do_ledge_hang(delta: float) -> void:
	velocity = Vector3.ZERO

	# Climb up, or drop off by holding back/down.
	if _jump_buffered > 0.0:
		_jump_buffered = 0.0
		var forward := -ledges.normal
		velocity = forward * ledge_climb_forward + Vector3.UP * ledge_climb_up
		# Deliberately NOT flagged as a jump: the climb is a committed motion with
		# exactly one job, getting you onto the ledge. Letting the jump-cut trim it
		# to 42% means a quick tap leaves you dangling, which just reads as broken.
		_jumping = false
		_jump_released = false
		_ledge_lock = ledge_cooldown
		_set_state(State.AIR)
		return
	if Input.is_action_pressed(&"drop") or wish_dir.dot(ledges.normal) > 0.55:
		_ledge_lock = ledge_cooldown
		_set_state(State.AIR)
		return

	# Shimmy: only move if there's still wall and lip beside us.
	var side := ledges.normal.cross(Vector3.UP).normalized()
	var lateral := wish_dir.dot(side)
	if absf(lateral) > 0.25:
		var step := side * signf(lateral) * ledge_shimmy_speed * delta
		if ledges.still_valid_at(global_position + step):
			global_position += step


## Swinging on an anchor.
##
## ─── THE RULE THAT MATTERS ───────────────────────────────────────────────────
##
## **Nothing in here caps your speed.** Not the pump, not gravity, not the
## release, not the top of the arc. That is not an oversight, it is the whole
## design, and it is the second thing this mechanic has been through:
##
##   • Version one was a pendulum on the JUMP button. Wrong input: a pendulum is
##     sustained momentum management, a jump is one impulse. Cut.
##   • Version two had five caps stacked in one function — a speed limit, an
##     apex clamp, drag, an outward-velocity cancel and a spring. Each one was
##     added to smooth a complaint, and together they removed the only reason to
##     use a swing at all. Cut.
##
## The fun is in *exploiting* the physics: wind the arc up, reel in to trade rope
## for speed, and spend the lot on one absurd jump. A cap is the mechanic
## apologising for itself. If a swing ever feels wrong again, do NOT reach for a
## limit — check the rope geometry below first.
##
## ─── HOW IT WORKS ────────────────────────────────────────────────────────────
##
##   hold grapple  stay attached; let go and you keep every bit of speed
##   stick         pumps along the arc (uncapped) — push the way you are going
##   grab / drop   reel the rope in and out
##   jump          leave the rope with a jump added ON TOP of the swing's speed
##
## Reel all the way in and you arrive at the anchor and bounce off it.
func _do_swing(delta: float) -> void:
	# The anchor can be freed under us, so re-check every frame.
	if _grapple == null or not is_instance_valid(_grapple):
		_release_swing()
		return

	# Letting go. No release penalty and no exit cap — what you wound up, you
	# keep. The repress lock is why a quick tap still gets a short swing: without
	# it the press that attached you is still held on the very next frame and
	# nothing would ever latch.
	if _grapple_lock <= 0.0 and not Input.is_action_pressed(&"grapple"):
		_release_swing()
		return

	# Jump off the rope. Added to the swing's velocity rather than replacing it,
	# so a wound-up swing plus a jump is bigger than either — this is the "far
	# jump / high jump" the whole thing exists to produce.
	if _jump_buffered > 0.0:
		_jump_buffered = 0.0
		velocity.y += _jump_velocity()
		# NOT marked as a live jump, so the jump-cut cannot touch it. A normal
		# jump is cut short when you release the button early, which is good for
		# a jump and wrong here: you have to release the button to let go of the
		# rope, so a cuttable swing-jump would halve itself every single time.
		_jumping = false
		_jump_released = true
		play_sfx(sfx_jump)
		_release_swing()
		return

	# Rope length is the player's to control, and the only thing about the rope
	# that changes over time. Its *enforcement* never changes, which is what
	# keeps the radius continuous — see _constrain_to_rope.
	if Input.is_action_pressed(&"grab"):
		_rope_length -= swing_reel_speed * delta
	elif Input.is_action_pressed(&"drop"):
		_rope_length += swing_reel_speed * delta
	_rope_length = clampf(_rope_length, swing_min_rope, swing_max_rope)

	var to_anchor := _grapple.global_position - global_position
	var distance := to_anchor.length()

	# Reeled all the way in: we have arrived at the anchor, so bounce off it.
	if distance <= swing_min_rope:
		_bounce_off_anchor()
		return

	# Raw gravity: no apex softening, no fall-speed clamp. See swing_gravity.
	velocity.y -= swing_gravity * delta

	var rope_dir := to_anchor / distance
	if distance >= _rope_length - 0.05:
		# Taut. Push along the ARC, not through the rope: the part of the stick
		# pointing along the rope would only fight the constraint and get thrown
		# away, so it is removed first. What is left is tangential, and
		# tangential force is exactly what pumps a swing.
		var push := wish_dir - rope_dir * wish_dir.dot(rope_dir)
		velocity += push * swing_pump_accel * delta
	else:
		# Slack: free flight, which is how you get above the anchor and over the
		# top of it. Plain added acceleration, never steering toward `max_speed`,
		# because moving *toward* a target speed would brake a fast swing — that
		# is a cap wearing a disguise.
		velocity += wish_dir * swing_slack_accel * delta


## Lets go of the rope. Keeps the velocity exactly as it is, deliberately.
func _release_swing() -> void:
	_grapple = null
	_rope_taut = false
	_set_state(State.AIR)


## The rope itself, enforced as an exact position correction AFTER the move.
##
## Three things here each prevent a specific failure, and all three have been
## got wrong in this file before:
##
## 1. **After the move, not before, and as a position correction rather than a
##    spring.** `move_and_slide()` travels in a straight line, but a swing is an
##    arc, so the body drifts off the circle every single frame. A spring applied
##    *before* the move is always a frame behind: drift out, get yanked back,
##    drift out again — a 60 Hz buzz that gets worse the faster you go, which is
##    what made version two feel rough. Correcting the position afterwards makes
##    the radius exact and leaves nothing to yank.
##
## 2. **One-sided.** A rope pulls, it does not push. Closer to the anchor than
##    the rope is long and it does nothing at all. That is what lets you swing up
##    over the top of the anchor and loop around it, instead of being pinned
##    below it — and being pinned below it was half of what made the old swing
##    feel like a cage.
##
## 3. **It removes only the OUTWARD velocity, never speed in general.** A rope
##    cannot stretch, so the component along it goes to zero; everything along
##    the arc is left completely untouched. So the constraint takes no energy out
##    of the swing. This is the one hard assignment to `velocity` in the whole
##    mechanic, and it is allowed because it is geometry, not tuning.
func _constrain_to_rope() -> void:
	if _grapple == null or not is_instance_valid(_grapple):
		return

	var anchor_position := _grapple.global_position
	var offset := global_position - anchor_position
	var distance := offset.length()

	if distance <= _rope_length or distance < 0.001:
		_rope_taut = false
		return

	_rope_taut = true
	var out_dir := offset / distance
	global_position = anchor_position + out_dir * _rope_length
	var outward := velocity.dot(out_dir)
	if outward > 0.0:
		velocity -= out_dir * outward


## Reeled all the way in to the anchor, so bounce off it like a trampoline
## bolted to the sky.
##
## The bounce is at least `jump_height`, for the same reason the slam's rebound
## is: an ability should never quietly cost you altitude. An earlier version
## added a flat 6 m/s kick, which is *less* than a jump, so arriving set you down
## lower than you started.
func _bounce_off_anchor() -> void:
	var anchor := _grapple as GrapplePoint
	var height := jump_height * anchor_bounce_height_scale
	if anchor != null:
		height *= anchor.bounce_scale

	# Keep some of the speed you arrived with, so coming in fast launches you
	# hard instead of being flattened to the same hop every time.
	velocity.x *= anchor_bounce_keep
	velocity.z *= anchor_bounce_keep
	_rope_taut = false
	play_sfx(sfx_grapple)

	# maxf, not a plain assignment: reeling in while already flying upward must
	# not be slower than arriving at a standstill.
	var kick := sqrt(2.0 * gravity_rise * height)
	# bounce() is what enemies call when you stomp them. It sets the upward
	# speed, clears the grapple, puts us back in AIR, and marks the jump as
	# already released so holding the button cannot cut the bounce short.
	bounce(maxf(velocity.y, kick))


func _do_hurt(delta: float) -> void:
	_hurt_left -= delta
	_apply_gravity(delta)
	if _hurt_left <= 0.0:
		_set_state(State.GROUND if is_on_floor() else State.AIR)


func _do_dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
	_apply_gravity(delta)


# ------------------------------------------------------- post-move transitions

## Wall contact is only known after move_and_slide, so wall states are entered here.
func _after_move(_delta: float) -> void:
	match state:
		State.AIR:
			if is_on_floor():
				_set_state(State.GROUND)
				return
			if is_on_wall() and _wall_lock <= 0.0:
				_try_enter_wall()
		State.GROUND:
			if not is_on_floor() and velocity.y <= 0.0:
				pass # handled next frame via coyote time
		State.SWING:
			# The rope has to be applied here, after the straight-line move has
			# already pulled us off the arc. _constrain_to_rope explains why.
			_constrain_to_rope()
		State.SLAM:
			# Landing is only knowable after move_and_slide().
			if is_on_floor():
				_slam_impact()


## Catches a wall on the way past, Mario-style.
##
## Deliberately unconditional beyond "is it a wall and am I falling". The old
## version demanded either enough speed along the surface or the stick held into
## it, which meant a wall you were clearly touching would sometimes refuse you
## for reasons invisible from the outside. A wall kick has to be reliable or
## nobody builds a route out of it.
func _try_enter_wall() -> void:
	var normal := get_wall_normal()
	if absf(normal.y) > wall_cling_max_tilt:
		return
	if velocity.y > 0.0:
		return
	_wall_normal = _flatten(normal)
	_set_state(State.WALL_SLIDE)


# ------------------------------------------------------------------ ledge grab

## Asks the LedgeSensor child whether something is grabbable in front of us.
func _find_ledge() -> bool:
	return ledges.find(global_position, facing)


## Snaps the body into the hanging pose once a ledge is found.
func _snap_to_ledge() -> void:
	var radius := 0.42
	var wall_point := Vector3(ledges.lip.x, 0.0, ledges.lip.z)
	var target := wall_point + ledges.normal * radius
	global_position = Vector3(target.x, ledges.lip.y - ledge_hang_drop, target.z)
	facing = -ledges.normal
	velocity = Vector3.ZERO
	_jumping = false


# ------------------------------------------------------------------- grapple

## Refreshes the aim every frame so the HUD reticle is always live. Does not
## fire anything — [method _try_grapple] does that.
func _update_targeting() -> void:
	# Do not re-aim mid-swing: the reticle sweeping onto a new anchor while you
	# are attached to one is noise, and the swing does not read it anyway.
	if state == State.SWING:
		return
	targeting.pick(rig.camera, global_position + Vector3.UP * 1.0, [get_rid()])


## Fires the tongue if a target is locked and the player asked for it.
## Returns whether it started, so the caller knows to stop processing this frame.
##
## One verb with two outcomes, decided by whether the target can be moved:
##
##   • an **anchor** is bolted to the world, so the player swings from it
##   • an **enemy** is not, so it is pulled to the player, and ends up carried
##
## Both halves matter and they came from opposite directions. The enemy half is
## Yoshi's tongue: an attack and a way of rearranging the level. The anchor half
## is a swing, which was cut twice and brought back, because the thing that makes
## a grapple worth having is being able to abuse its physics — see _do_swing.
func _try_grapple() -> bool:
	if _grapple_buffered <= 0.0:
		return false

	# Already holding something? The button throws it. Checked before targeting
	# so you are never stuck holding an enemy because something else is in view.
	if abilities.carried != null:
		_grapple_buffered = 0.0
		_grapple_lock = grapple_repress_delay
		abilities.throw_carried()
		return true

	var target := targeting.current
	if target == null or not is_instance_valid(target):
		return false

	_grapple_buffered = 0.0
	_grapple_lock = grapple_repress_delay
	play_sfx(sfx_grapple)

	if GrappleTargeting.is_anchor(target):
		# Fixed to the level, so the player is the one that moves: attach and
		# swing. The rope starts at exactly the distance you hooked from, which
		# is why it is already taut and why the radius is continuous from the
		# first frame.
		_grapple = target
		_rope_length = clampf(
			global_position.distance_to(target.global_position),
			swing_min_rope, swing_max_rope)
		_set_state(State.SWING)
		return true

	# An enemy comes to you. Handing this to PlayerAbilities keeps player.gd
	# about movement — reeling something in does not move the player at all, so
	# it does not belong in the state machine.
	abilities.tongue_grab(target)
	return true


# -------------------------------------------------------------- damage & death

## Called by enemy hurtboxes and hazards.
func take_hit(amount: int, from: Vector3) -> void:
	if state == State.DEAD or not health.damage(amount):
		return
	var away := _flatten(global_position - from)
	if away.length_squared() < 0.01:
		away = -_flatten(facing)
	play_sfx(sfx_hurt)
	velocity = away.normalized() * hurt_knockback + Vector3.UP * hurt_lift
	_hurt_left = hurt_time
	_grapple = null
	_set_state(State.HURT)


## Plays a one-shot sound from the player's position.
##
## There is a single AudioStreamPlayer3D, so a new sound cuts off the previous
## one. For short blips that is fine and it keeps the scene simple; if you start
## needing overlapping sounds, add a second player rather than a queue.
func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	sfx.stream = stream
	sfx.play()


## Vertical speed as it was *before* this frame's collision resolution.
##
## Enemies must use this rather than `velocity.y` for stomp checks: landing on an
## enemy means landing on its body collider, which zeroes velocity.y in the same
## physics step that its stomp Area3D reports the overlap. Reading velocity.y
## there sees a stationary player and the stomp silently never registers.
func descent_speed() -> float:
	return _pre_move_vy


## Called by an enemy that was stomped, so the player bounces off it.
func bounce(force: float = -1.0) -> void:
	velocity.y = stomp_bounce if force < 0.0 else force
	_jumping = true
	_jump_released = true
	_grapple = null
	if state != State.DEAD:
		_set_state(State.AIR)


func heal(amount: int) -> void:
	health.heal(amount)


func kill() -> void:
	if state != State.DEAD:
		health.damage(health.current)


func respawn_at(where: Transform3D) -> void:
	global_transform = where
	velocity = Vector3.ZERO
	_grapple = null
	_rope_taut = false
	abilities.drop_everything()
	_hurt_left = 0.0
	jump_chain = 0
	_chain_window = 0.0
	_slam_recover = 0.0
	_ledge_lock = 0.0
	_wall_lock = 0.0
	health.reset()
	_set_state(State.AIR)
	Events.player_respawned.emit()


func spawn_transform() -> Transform3D:
	return _spawn


func _on_health_changed(current: int, maximum: int) -> void:
	Events.player_health_changed.emit(current, maximum)


func _on_died() -> void:
	_set_state(State.DEAD)
	Events.player_died.emit()


# ---------------------------------------------------------------- presentation
#
# Both of these just hand facts to the visual nodes and let them decide how to
# look. Nothing here touches a mesh directly.

## Works out which way the body should face, then lets PlayerVisuals turn it.
func _update_visual(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if state == State.LEDGE_HANG:
		facing = -ledges.normal      # hanging: always face into the wall
	elif flat.length_squared() > 0.6:
		facing = flat.normalized()   # moving: face where we are actually going
	elif wish_dir.length_squared() > 0.01:
		facing = wish_dir.normalized()  # stood still: face where we are steering

	visual.tick(delta, facing)


## Shows the rope while hooked on, hides it otherwise.
func _update_rope() -> void:
	# Drawn to whatever we are attached to: the anchor we are swinging from, or
	# the enemy we are dragging in.
	var tip: Node3D = null
	if state == State.SWING and _grapple != null and is_instance_valid(_grapple):
		tip = _grapple
	elif abilities.tethered != null and is_instance_valid(abilities.tethered):
		tip = abilities.tethered

	if tip != null:
		rope_line.draw_between(global_position + Vector3.UP * 1.0, tip.global_position)
	else:
		rope_line.clear()


# ------------------------------------------------------------------- plumbing

## The only way the state should ever change. Always call this rather than
## assigning `state` directly, or the enter/exit setup below gets skipped.
func _set_state(next: State) -> void:
	if state == next:
		return
	var previous := state
	_exit_state(previous)
	state = next
	_enter_state(next)
	# Broadcast for anyone who cares (animations, sound, UI). Emitting a signal
	# costs nothing if nobody is listening, and it keeps this script from needing
	# to know those systems exist.
	state_changed.emit(previous, next)


func _enter_state(which: State) -> void:
	match which:
		State.GROUND:
			# Only a real fall makes a landing noise — otherwise every tiny step
			# down a slope would thud.
			if _pre_move_vy < -4.0:
				play_sfx(sfx_land)
			# Landing opens the window for the next jump in the chain. Set here
			# rather than when jumping, because it is the LANDING that has to be
			# followed up quickly.
			_chain_window = jump_chain_window
		State.LEDGE_HANG:
			_snap_to_ledge()
		State.DEAD:
			velocity = Vector3.ZERO
		_:
			pass


func _exit_state(which: State) -> void:
	match which:
		State.LEDGE_HANG:
			_ledge_lock = maxf(_ledge_lock, ledge_cooldown)
		State.SWING:
			_rope_taut = false
		_:
			pass


func _flatten(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO


func state_name() -> String:
	return State.keys()[state]


## Feeds the F3 debug readout. Keeping it here means the HUD needs no knowledge
## of the controller's internals.
func debug_info() -> Dictionary:
	var target := targeting.current
	return {
		"state": state_name(),
		"speed": Vector2(velocity.x, velocity.z).length(),
		"vy": velocity.y,
		"floor": is_on_floor(),
		"wall": is_on_wall(),
		"target": target.name if target != null else "-",
		"kind": ("anchor" if GrappleTargeting.is_anchor(target) else "enemy") if target != null else "-",
		"slam": "power %.2f" % slam_power(),
		"chain": "%d (window %.2f)" % [jump_chain, maxf(_chain_window, 0.0)],
		"rope": ("%.1f m %s" % [_rope_length, "taut" if _rope_taut else "slack"]) if state == State.SWING else "-",
		"carry": abilities.carried.name if abilities.carried != null else "-",
		"tongue": abilities.tethered.name if abilities.tethered != null else "-",
	}
