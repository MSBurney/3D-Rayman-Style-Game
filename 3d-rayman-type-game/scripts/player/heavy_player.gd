class_name HeavyPlayer
extends CharacterBody3D

## The modal heavy controller, built to the Vision & Movement doc (2026-10-24).
##
## ─── IT LIVES ALONGSIDE player.gd, IT DOES NOT REPLACE IT YET ────────────────
##
## The doc says to scrap the ported Mario 64 verb set and build this from
## scratch, and it is right that the two cannot be merged — an agility moveset
## made heavier only produces a worse Mario. But it also frames this as
## **Milestone 1: the greybox that proves or kills this**, so this controller
## gets its own scene and its own test room, and the old one keeps nine levels
## and a 107-check suite working until the greybox passes. Retiring `player.gd`
## is a separate, deliberate step. (This project rewrote the grapple four times
## by shipping the ambitious version before the core was proven.)
##
## ─── THE SHAPE OF IT ─────────────────────────────────────────────────────────
##
## **Movement is modal, not continuous.** Four states, and switching between
## them deliberately is the whole skill:
##
##   WALK    precise, instant, slow. The manipulation mode — aiming, plates,
##           ledges. Deliberately unremarkable, exactly like walking Wario.
##   CHARGE  wind-up, then committed high-speed travel. The traversal verb.
##   AIR     arc locked at takeoff, minimal steering.
##   SLAM    aimed falling mass. Attack, breaker, pressure input, and the brake.
##
## **CARDINAL RULE: instant inputs, heavy body.** Every input gets a same-frame
## response. The *mass* is what takes time — acceleration curves, braking
## slides, wide turn arcs. Players read input latency as bad controls and
## momentum curves as weight. **Never add delay to make something feel heavy.**
##
## **Steering authority is a falling curve of speed, not a mode toggle.** The
## controls never stop working; they change meaning with speed. Below
## `walk_speed` the stick commands outright, which is what keeps puzzle
## execution blameless — a player stuck on a puzzle must never be able to blame
## the controls. Above it the stick only nudges, and the real steering is the
## BOOST.
##
## ─── KINEMATIC, AND THAT IS A DECISION ───────────────────────────────────────
##
## `CharacterBody3D` with hand-authored curves. The doc is explicit: *fake the
## mass, never rigid-body-drive the hero*, because a truly simulated heavy
## controller is miserable to make feel good and unpredictable physics kills
## mastery. Authored curves read as weight and play as a learnable system.
## Rigid bodies are for the garnish — debris, thrown objects — never for this.

enum State {
	## Precise and instant. Below `walk_speed` the stick is in complete command.
	WALK,
	## Committed. Wind-up, then high speed with degraded steering and no brakes.
	CHARGE,
	AIR,
	## Aimed falling mass, and the emergency brake. The signature verb.
	SLAM,
}

signal state_changed(from: State, to: State)
## A charge ended against something solid. Carries where, and the speed that was
## killed — which is what rule 2 (momentum transfers on impact) is made of.
signal crashed(at: Vector3, force: float)

@export_group("Walk")
## Top speed the stick alone reaches, and the threshold below which control is
## exact. NOT a speed limit: slopes, charges and charge-jumps all go far past it.
@export var walk_speed: float = 15.0
## Deliberately BRISK, unlike the old controller's committal 14.
##
## The weight in this design lives in the charge, not in the walk. Walk mode is
## the precision anchor, so making it sluggish would break the one promise that
## keeps puzzle execution blameless.
@export var walk_accel: float = 10.0
@export var walk_decel: float = 7.5
@export var face_turn_speed: float = 7.5

@export_group("Charge")
## The plant-and-rear before launch. A wind-up, NOT a cast.
##
## The time cost of mass is paid here, as one telegraphed decision, instead of
## being smeared across a sluggish throttle. You can still aim during it — that
## is the skill — but you cannot move.
@export var charge_windup: float = 0.5
@export var charge_top_speed: float = 20.0
@export var charge_accel: float = 15.0
## Radians per second the heading can be bent while charging, BEFORE the
## authority curve scales it down further. Wide arcs, near-locked heading.
##
## Aiming before committing is the skill; losing the ability to steer afterwards
## is the mastery curve, not friction.
@export var charge_turn_rate: float = 5.0
## How fast a charge bleeds once you stop feeding it. There are NO FREE BRAKES:
## letting go stops you adding power, it does not stop you.
@export var slide_friction: float = 5.0
## How long you are stunned after crashing into something at speed.
##
## Early crashes are meant to be cheap and funny — bounce, dust, get up — so
## this is the whole penalty. Stakes rise with world fragility, never with the
## controls getting meaner.
@export var crash_stun: float = 0.5
@export var crash_bounce: float = 12.0

@export_group("Steering authority")
## Authority at and above `authority_zero_speed`. Never 0: there is no regime
## where the player is a passenger, only regimes with their own grammar.
@export var min_authority: float = 0.2
## Speed at which authority has fallen all the way to `min_authority`.
@export var authority_zero_speed: float = 20.0
## Optional hand-drawn override, sampled across 0..`authority_zero_speed`. Left
## empty, the smoothstep in `authority()` is used instead.
@export var steering_curve: Curve
## How much of the already-reduced authority survives in mid-air. "Arc locked at
## takeoff" is what makes this small.
@export var air_authority: float = 0.5

@export_group("Boost")
## The steering vocabulary at speed: a discrete impulse that ADDS momentum in
## the stick direction — vector addition, never a velocity rewrite.
##
## So course-correcting makes you faster and more committed, which is the point
## rather than a side effect. The cooldown is what stops it being pulsed into
## full authority.
@export var boost_impulse: float = 7.0
@export var boost_cooldown: float = 0.75
## Taps before you have to touch the ground again. 0 means unlimited, and the
## cooldown is then the only limit.
@export var boost_taps: int = 1
## The speed at which a boost pays NOTHING at all.
##
## A FLAT ADDITION COMPOUNDS, and this project has already been bitten by
## exactly that once: the old long jump added a fixed push to whatever speed you
## already had, so land-crouch-jump-repeat was worth +17 m/s every single time
## and four in a row passed 60 m/s. The boost is the same shape - tap, land,
## tap, land, and you are travelling faster than you can read the level.
##
## So the impulse FADES: full value up to `charge_top_speed`, nothing by here.
## A chain of boosts then CONVERGES on this number instead of diverging.
##
## **It caps the BONUS, not your speed.** Nothing here touches what a slope can
## give you - a hill can still take you past this and the charge will keep every
## bit of it, because weight gates speed and never caps it. The boost only
## declines to pay full price for the same button twice. If the boost needs to
## be stronger, raise THIS rather than `boost_impulse`: raising the impulse
## makes the chain worth farming all over again.
@export var boost_fade_speed: float = 28.0

@export_group("Jump")
@export var jump_speed: float = 9.0
## Extra launch speed per m/s of ground speed. This is what makes a charge-jump
## a cannonball and a standing jump a hop, and why run-up planning is a constant
## micro-decision.
@export var jump_speed_scaling: float = 0.22
@export var jump_speed_max: float = 15.0
@export var gravity_rise: float = 22.0
@export var gravity_fall: float = 34.0
@export var max_fall_speed: float = 34.0
@export var coyote_time: float = 0.12
@export var jump_buffer: float = 0.12
## How long a charge press is remembered if you were not on the ground yet.
##
## Not optional. A wind-up can only begin from the floor, so without this a
## press landing a frame or two before touchdown is silently thrown away — and
## the cardinal rule is that EVERY input gets a response. An input that
## sometimes evaporates is read as bad controls, which is the one thing a
## heavy character cannot afford to be mistaken for.
@export var charge_buffer: float = 0.14

@export_group("Slam")
## How hard it drives you at the ground. The signature verb and the build
## priority: the fall is tuned before anything else in this file.
@export var slam_drop_accel: float = 300.0
@export var slam_max_speed: float = 130.0
## Drop height that counts as a full-power landing.
@export var slam_power_height: float = 12.0
## Scales the whole impact number props read off `Events.slam_landed`.
@export var impact_force_scalar: float = 2.0
## How much impact comes from HORIZONTAL speed killed rather than from the drop.
##
## This is the slam-brake. Stopping hard delivers your momentum into the floor,
## so braking on fragile footing breaks it — rule 2 applied to yourself. Never
## free, always available, and a deliberate tool: brake on purpose to punch
## through a floor.
@export var brake_impact_scalar: float = 0.055
@export var slam_recover: float = 0.25

@export_group("Weight")
## How heavy this body is, for anything that resolves by mass: see-saws,
## pressure plates, counterweights. **Universal weight rule 3** (the heavier
## side of a pivot wins) and **rule 5** (enemies obey the same physics as the
## player) both need the player's weight to be a number other things can read.
##
## A `RigidBody3D` already has a `mass` property, which is why a crate needs no
## script at all to sit on a see-saw. A `CharacterBody3D` has none, so this
## declares one with the same name — `weight_sensor.gd` asks for `mass` by name
## and does not care what class answered.
##
## It is NOT used by the movement code and changing it will not make the hero
## feel heavier: the weight in the handling is the authority curve and the
## charge, exactly as the doc says (*"fake the mass"*). This number is what the
## WORLD weighs you at.
@export var mass: float = 10.0

## ─── WEIGHT RULE 2: MOMENTUM TRANSFERS ON IMPACT ────────────────────────────
##
## How much of an ideal collision actually gets delivered, both ways. At 1.0 a
## hit is perfectly inelastic — you and the thing you rammed end up travelling
## at the same speed — which is the honest default. Lower it for mushier hits.
##
## **This is the whole vocabulary for moving an object.** The doc's verb set is
## Walk, Charge, Jump, Slam, Boost, with no carry and no grab, so ramming and
## stomping are the only ways the hero can put a thing somewhere. That makes
## these numbers a VERB, not a detail.
@export var push_transfer: float = 1.0
## Below this closing speed nothing is exchanged, which is what stops a body
## you are merely leaning against from being nudged every single frame.
@export var push_min_speed: float = 1.5
## How far a slam throws loose objects around it, at force 1.0. Scales with the
## force, so a hop barely rattles them and a tower drop clears the area.
@export var slam_scatter_radius: float = 5.0
## Metres per second given to a loose object right next to a slam of force 1.0.
@export var slam_scatter_power: float = 6.0
## How much of an incoming object's momentum lands on YOU. Rule 2 cuts both
## ways or it is not a rule — see `_on_hitbox_entered`.
@export var impact_take: float = 0.8

## Gravity projected along the floor. Downhill is free acceleration, and
## converting height into speed is the game's currency.
@export var slope_gravity: float = 30.0
@export var slope_accel_mult: float = 1.0
@export var slope_decel_mult: float = 1.0
@export var slope_min_grade: float = 0.06
## The only place ground momentum decays, and it never takes you below
## `walk_speed`, so ordinary walking is untouched by it.
@export var momentum_friction: float = 3.0

@export_group("Juice")
## Weight is 50% feedback. These are NOT polish — sluggish and weighty are the
## same numbers with different presentation, which is why they are wired in from
## the first greybox instead of afterwards.
@export var jump_fx: PackedScene
@export var impact_fx: PackedScene
@export var charge_colour: Color = Color(1.0, 0.62, 0.2)
@export var crash_colour: Color = Color(1.0, 0.45, 0.3)
@export var boost_colour: Color = Color(0.4, 0.9, 1.0)
@export var land_shake: float = 0.3
@export var crash_shake: float = 0.5
@export var sfx_jump: AudioStream
@export var sfx_land: AudioStream
@export var sfx_charge: AudioStream

var state: State = State.WALK
## Which way the body is pointing. While charging this IS the heading.
var facing: Vector3 = Vector3.FORWARD
var move_input: Vector2 = Vector2.ZERO
var wish_dir: Vector3 = Vector3.ZERO

var _windup_left: float = 0.0
var _charging: bool = false
var _stun_left: float = 0.0
var _slam_recover_left: float = 0.0
var _coyote: float = 0.0
var _jump_buffered: float = 0.0
var _boost_cool: float = 0.0
var _charge_buffered: float = 0.0
var _boosts_left: int = 0
## True while a jump is carrying a charge through the air. See `_jump()`.
var _charge_through_air: bool = false
var _air_peak_y: float = 0.0
## Horizontal speed at the moment the slam began — the brake half of the impact.
var _slam_entry_speed: float = 0.0
## Velocity from BEFORE this frame's collision resolution. Props read these; see
## approach_velocity() for the trap they exist to work around.
var _pre_move_flat: Vector3 = Vector3.ZERO
var _pre_move_vy: float = 0.0

@onready var rig: PlayerCamera = $CameraRig
@onready var visual: Node3D = $Visual
@onready var sfx: AudioStreamPlayer3D = $Sfx
## Notices loose objects arriving under their own steam. See
## `_on_hitbox_entered` for why this half cannot be done with slide collisions.
@onready var hitbox: Area3D = $Hitbox


func _ready() -> void:
	facing = -global_transform.basis.z
	_boosts_left = boost_taps
	hitbox.body_entered.connect(_on_hitbox_entered)


func _physics_process(delta: float) -> void:
	_tick(delta)
	_read_input()

	match state:
		State.WALK: _do_walk(delta)
		State.CHARGE: _do_charge(delta)
		State.AIR: _do_air(delta)
		State.SLAM: _do_slam(delta)

	# Kept from BEFORE collision resolution, because move_and_slide() is about
	# to zero whichever axis we hit something on. Props ask for these rather
	# than for `velocity`; see approach_velocity().
	_pre_move_flat = Vector3(velocity.x, 0.0, velocity.z)
	_pre_move_vy = velocity.y

	move_and_slide()

	# Only now do is_on_floor() and is_on_wall() mean anything.
	_after_move(delta)
	_update_visual(delta)


func _tick(delta: float) -> void:
	_coyote = coyote_time if is_on_floor() else _coyote - delta
	_jump_buffered -= delta
	_charge_buffered -= delta
	_stun_left -= delta
	_slam_recover_left -= delta
	_boost_cool -= delta
	if is_on_floor():
		_air_peak_y = global_position.y
		_boosts_left = boost_taps
	else:
		_air_peak_y = maxf(_air_peak_y, global_position.y)


func _read_input() -> void:
	move_input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	wish_dir = rig.flat_basis() * Vector3(move_input.x, 0.0, move_input.y)
	if wish_dir.length_squared() > 1.0:
		wish_dir = wish_dir.normalized()

	if Input.is_action_just_pressed(&"jump"):
		_jump_buffered = jump_buffer

	# ONE BUTTON, TWO VERBS, which is one of the two options the doc leaves open
	# for the boost input: HOLD it from walk to wind up a charge, TAP it once
	# already moving to boost. Unambiguous because the two are only reachable
	# from different states, and it adds no new binding.
	if Input.is_action_just_pressed(&"attack"):
		if state == State.WALK:
			# Remembered rather than acted on, because a wind-up can only start
			# from the floor. See charge_buffer.
			_charge_buffered = charge_buffer
		elif state == State.CHARGE or state == State.AIR:
			_try_boost()

	if Input.is_action_just_pressed(&"crouch"):
		if state == State.AIR or state == State.CHARGE:
			_begin_slam()


## How much of the stick actually reaches the body, from 1.0 at walking pace
## down to `min_authority` at speed.
##
## This single curve IS the movement identity. Below `walk_speed` it returns
## exactly 1.0 and nothing is allowed to erode that: a player stuck on a puzzle
## must never be able to blame the controls. Above it the stick becomes a nudge
## on a mass in flight, and the boost becomes the real steering.
func authority() -> float:
	var speed := flat_speed()
	if speed <= walk_speed:
		return 1.0
	if steering_curve != null:
		return steering_curve.sample_baked(
			clampf(speed / maxf(authority_zero_speed, 0.01), 0.0, 1.0))
	var t := clampf((speed - walk_speed) / maxf(authority_zero_speed - walk_speed, 0.01),
		0.0, 1.0)
	# Smoothstep rather than linear, so authority sags away instead of stepping.
	return lerpf(1.0, min_authority, t * t * (3.0 - 2.0 * t))


func flat_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# ──────────────────────────────────────────────────────────── the four states

func _do_walk(delta: float) -> void:
	if _stun_left > 0.0 or _slam_recover_left > 0.0:
		# Bounced off something, or still planting a slam. Recovery is the whole
		# penalty for a crash, and it is deliberately short and funny.
		_brake(delta, walk_decel * 1.5)
		_apply_gravity(delta)
		return
	if _windup_left > 0.0:
		_tick_windup(delta)
		return
	if _charge_buffered > 0.0 and is_on_floor():
		_charge_buffered = 0.0
		_begin_windup()
		return

	_steer_ground(delta)
	_slope_pull(delta)
	_apply_gravity(delta)

	if _jump_buffered > 0.0 and _coyote > 0.0:
		_jump()


## Stick handling on the ground, and the place the authority curve earns itself.
func _steer_ground(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()

	if speed > walk_speed:
		# Above the threshold you are a mass in flight. The stick BENDS the
		# direction and is never allowed to cancel the speed; only
		# `momentum_friction` bleeds it, and only down to `walk_speed`, so a
		# slope's gift decays slowly while ordinary walking is untouched.
		if wish_dir != Vector3.ZERO:
			flat += wish_dir * walk_accel * authority() * delta
			flat = flat.limit_length(speed)
		flat = flat.move_toward(flat.normalized() * walk_speed, momentum_friction * delta)
	elif wish_dir == Vector3.ZERO:
		flat = flat.move_toward(Vector3.ZERO, walk_decel * delta)
	else:
		# Below it the stick simply commands, at full authority, instantly.
		flat = flat.move_toward(wish_dir * walk_speed, walk_accel * delta)

	velocity.x = flat.x
	velocity.z = flat.z
	if flat.length_squared() > 0.25:
		facing = flat.normalized()


## Committed travel. Wind-up is over; from here the arena decides how it ends.
func _do_charge(delta: float) -> void:
	# DEGRADED STEERING. The heading bends at a fixed rate scaled down further
	# by the authority curve, which is what produces wide arcs instead of turns.
	# Aiming before committing is the skill; this is the mastery curve.
	if wish_dir != Vector3.ZERO:
		var max_turn := charge_turn_rate * authority() * delta
		var angle := facing.signed_angle_to(wish_dir, Vector3.UP)
		facing = facing.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn)).normalized()

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if is_on_floor():
		if _charging:
			var rolling := flat.length()
			if rolling < charge_top_speed:
				flat = flat.move_toward(facing * charge_top_speed, charge_accel * delta)
			else:
				# ALREADY faster than the charge can push, which means a slope gave
				# it to you — so keep every bit of it and only steer.
				#
				# `charge_top_speed` is what the ENGINE reaches on the flat, NOT a
				# limit on how fast you can be going. Weight gates speed, it never
				# caps it, and charge velocity obeys the same conservation as
				# everything else — slopes add to it, impacts transfer it, jumps
				# inherit it. Written with a plain `move_toward` the charge quietly
				# dragged you back down to 20 the whole way down the ramp, so the
				# slope was worth exactly nothing.
				flat = facing * rolling
		else:
			# NO FREE BRAKES. Letting go only stops you adding power — the slide
			# is what ends a charge, and sliding past the ledge is on you.
			flat = flat.move_toward(Vector3.ZERO, slide_friction * delta)
	# Airborne mid-charge gets neither power nor friction: you cannot push off
	# thin air, and nothing should be taken away either. A charge is NOT
	# cancelled by leaving the ground — only a jump, a crash or sliding out ends
	# one. The first version dropped to AIR the instant `is_on_floor()` went
	# false, which meant charging over the lip of the ramp cancelled the charge:
	# useless on exactly the kind of terrain this game is made of.
	velocity.x = flat.x
	velocity.z = flat.z

	_slope_pull(delta)
	_apply_gravity(delta)

	if not Input.is_action_pressed(&"attack"):
		_charging = false
	if not _charging and is_on_floor() and flat_speed() < walk_speed:
		_set_state(State.WALK)
		return
	if _jump_buffered > 0.0 and (_coyote > 0.0 or is_on_floor()):
		_jump()


func _do_air(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()
	if wish_dir != Vector3.ZERO:
		flat += wish_dir * walk_accel * authority() * air_authority * delta
		# The arc is LOCKED at takeoff. Steering may bend it; it can never make
		# it faster, or a charge-jump would be steerable into free distance.
		flat = flat.limit_length(maxf(speed, walk_speed))
	velocity.x = flat.x
	velocity.z = flat.z
	_apply_gravity(delta)

	# LETTING GO IN MID-AIR ends it, so holding really is the whole condition and
	# the charge is never resumed by surprise. This is also why tapping for a
	# boost up here gives up the charge: you cannot tap without releasing, so you
	# chose one or the other, which is a decision rather than a trap.
	if _charge_through_air and not Input.is_action_pressed(&"attack"):
		_charge_through_air = false


## Aimed falling mass. The signature verb, and also the brake.
func _do_slam(delta: float) -> void:
	# Horizontal is killed HARD rather than decaying, because it is not being
	# lost — it is being delivered into the ground. See brake_impact_scalar.
	velocity.x = move_toward(velocity.x, 0.0, slam_drop_accel * delta)
	velocity.z = move_toward(velocity.z, 0.0, slam_drop_accel * delta)
	velocity.y = maxf(velocity.y - slam_drop_accel * delta, -slam_max_speed)


func _after_move(_delta: float) -> void:
	# Before the state machine, because a shove can take enough speed off a
	# charge to turn the next line into a crash — and it should.
	_shove_what_we_hit()
	match state:
		State.WALK:
			if not is_on_floor() and _coyote <= 0.0:
				_set_state(State.AIR)
		State.CHARGE:
			# A crash is the ONLY thing here. Deliberately no "fell off something,
			# go to AIR" branch: per the state diagram the only way out of a charge
			# into the air is a charge-jump, which is a decision rather than an
			# accident of the ground.
			if is_on_wall() and _was_stopped_dead():
				_crash()
		State.AIR:
			if is_on_floor():
				_land()
		State.SLAM:
			if is_on_floor():
				_slam_impact()


# ──────────────────────────────── weight rule 2: momentum transfers on impact

## Pushes anything dynamic we just ran into, and takes the reaction ourselves.
##
## **A `CharacterBody3D` does not push a `RigidBody3D` in Godot. At all.** They
## are solved in separate passes, so the character treats a crate as a wall and
## the crate never hears about it. Walking the slide collisions and applying the
## impulses by hand is the only way, and until this existed the greybox had
## props that could measure weight and nothing that could deliver any — which is
## exactly how it played.
func _shove_what_we_hit() -> void:
	# THE PRE-MOVE VELOCITY, never `velocity`. This is the trap this project has
	# now paid for three times: `move_and_slide()` has already zeroed the speed
	# by the time you can ask about the collision, so a shove computed from
	# `velocity` is a shove of nothing at all for exactly the head-on hits that
	# should be hardest. Same reason `approach_velocity()` exists for props.
	var incoming := Vector3(_pre_move_flat.x, _pre_move_vy, _pre_move_flat.z)
	if incoming.length() < push_min_speed:
		return
	# One body can be reported several times across move_and_slide's iterations,
	# and shoving it twice in a frame is twice the momentum out of nowhere.
	var done: Array[RigidBody3D] = []
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider() as RigidBody3D
		if body == null or done.has(body):
			continue
		done.append(body)
		_shove(body, hit.get_normal(), hit.get_position(), incoming)


## One impact, resolved as a perfectly inelastic collision: both bodies would
## end up travelling at `m1 * v / (m1 + m2)`.
##
## **One formula, no special cases, and that is the point.** Ram a crate lighter
## than you and it flies while you barely slow. Ram something much heavier and
## you stop dead — and the crash-stun then follows on its own out of
## `_was_stopped_dead()`, with no code anywhere that knows what "heavy" means.
## A player can look at a thing and predict what ramming it will do, which is
## the difference between mass as a reasoning tool and mass as a stat.
func _shove(body: RigidBody3D, normal: Vector3, contact: Vector3, incoming: Vector3) -> void:
	# Speed delivered INTO the surface. A graze delivers almost nothing, which is
	# what the dot product buys: scraping past a crate must not fling it.
	var closing := -incoming.dot(normal)
	if closing < push_min_speed:
		return

	var share := mass / maxf(mass + body.mass, 0.01)
	var given := closing * share * push_transfer
	# Woken first: a settled crate is a SLEEPING RigidBody3D and ignores an
	# impulse. Applied off-centre at the contact point so it tumbles instead of
	# sliding like a hovercraft — the one place the doc's "simulate the garnish"
	# gets to apply here.
	body.sleeping = false
	body.apply_impulse(-normal * given * body.mass, contact - body.global_position)

	# ...and we keep exactly what the collision leaves us.
	#
	# SUBTRACTED from the post-slide velocity rather than rebuilt from
	# `incoming`, which matters when a crate is pinned against a wall: rebuilding
	# would throw away the wall slide that `move_and_slide()` just worked out and
	# shove us into the wall instead. Subtracting composes with it — the solver
	# already removed all of our speed into the surface, so this gives back only
	# the part the crate did not absorb.
	velocity -= normal * given


## Rule 2 and rule 4 together: an impact that big has to move what is lying
## around it, or the slam reads as a sound effect with a decal on it.
##
## Walked by GROUP and distance rather than with an `Area3D`, for the two
## reasons the spin established: an area added and queried in the same frame
## reports nothing, and a settled crate is a sleeping body that overlap queries
## are unreliable about. `weight_sensor.gd` walks groups for the same reasons.
func _scatter_loose_objects(force: float) -> void:
	if force <= 0.0:
		return
	var reach := slam_scatter_radius * clampf(force, 0.25, 2.0)
	var done: Array[RigidBody3D] = []
	for group in [&"heavy", &"throwable"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as RigidBody3D
			# A crate can be in both groups, and kicking it twice is free energy.
			if body == null or done.has(body):
				continue
			var offset := body.global_position - global_position
			var gap := offset.length()
			if gap > reach or gap < 0.01:
				continue
			done.append(body)
			# Mostly outward with a lift in it, so things leave the ground and
			# the impact reads as a shockwave rather than as a floor sweep.
			var away := (offset / gap + Vector3.UP * 0.9).normalized()
			var speed := slam_scatter_power * force * (1.0 - gap / reach)
			body.sleeping = false
			body.apply_central_impulse(away * speed * body.mass)


## Something loose hit US, under its own steam.
##
## This half cannot be done with slide collisions: `get_slide_collision()` only
## reports what WE moved into, so a crate flying at a standing player is
## invisible to it — and a `RigidBody3D` cannot push a `CharacterBody3D` either,
## so without this a crate thrown by a see-saw passes straight through you.
##
## An `Area3D` is safe here where it would not be for the spin, because this one
## lives in the scene and is never moved or re-added before being queried. It is
## masked to the loose-object layer alone, so level geometry never reaches it.
func _on_hitbox_entered(body: Node3D) -> void:
	var rigid := body as RigidBody3D
	if rigid == null:
		return
	var offset := global_position - rigid.global_position
	if offset.length_squared() < 0.0001:
		return
	var toward := offset.normalized()
	# Only what is actually coming AT us counts. A crate we are walking past, or
	# one we just shoved away, delivers nothing.
	var closing := rigid.linear_velocity.dot(toward)
	if closing < push_min_speed:
		return
	# Their momentum, over our mass. Heavy and fast moves us; light and fast
	# barely does, and it is the same arithmetic as `_shove` read backwards.
	var delivered := rigid.mass * closing / maxf(mass, 0.01) * impact_take
	velocity += toward * delivered
	_spawn_puff(crash_colour, 10, 3.5, -toward)
	_shake(clampf(delivered * 0.03, 0.0, crash_shake))
	play_sfx(sfx_land)


## Did that wall actually STOP us, or did we go through it?
##
## Compared before-and-after rather than just asking `is_on_wall()`, and that
## difference is load-bearing: a breakable block hands your speed back when it
## gives way (see `speed_kept` in breakable_block.gd), so a charge that smashed
## THROUGH something is still fast afterwards and must not also be punished
## with a crash-stun. Grazing a wall at a shallow angle survives for the same
## reason — you only crash if the wall won.
func _was_stopped_dead() -> bool:
	var before := _pre_move_flat.length()
	return before > walk_speed and flat_speed() < before * 0.5


# ───────────────────────────────────────────────────────────────── the verbs

func _begin_windup() -> void:
	if not is_on_floor():
		return
	_windup_left = charge_windup
	play_sfx(sfx_charge)


## The plant-and-rear. You can still AIM during it — that is the skill — but
## you cannot move, and the stop is immediate so the telegraph is unmistakable.
func _tick_windup(delta: float) -> void:
	_windup_left -= delta
	_brake(delta, walk_decel * 2.0)
	_apply_gravity(delta)
	if wish_dir != Vector3.ZERO:
		facing = wish_dir
	if not Input.is_action_pressed(&"attack"):
		# Let go early and it is simply cancelled. A wind-up you cannot back out
		# of would make the press a commitment before the decision was made.
		_windup_left = 0.0
		return
	if _windup_left <= 0.0:
		_charging = true
		_set_state(State.CHARGE)


func _jump() -> void:
	_jump_buffered = 0.0
	_coyote = 0.0
	# DISTANCE SCALES WITH GROUND SPEED, and it is the launch speed that is
	# scaled rather than the horizontal push — a higher arc buys air time, and
	# air time is what turns speed into distance. A charge-jump is a cannonball;
	# a standing jump is a hop; planning your run-up is a constant decision.
	var speed := flat_speed()
	velocity.y = minf(jump_speed + speed * jump_speed_scaling, jump_speed_max)
	# A JUMP DOES NOT END A CHARGE. Jumping is how a charge crosses a gap, so
	# being dumped back into WALK on the far side - and made to plant and wind up
	# all over again while still holding the button - turns the one move the room
	# is built around into a punishment for using it.
	#
	# Noted here rather than left in `_charging`, because `_charging` means "I am
	# on the ground adding power to a charge" and that is exactly what you are
	# not doing in mid-air. `_set_state` clears it on the way out, so the intent
	# has to be remembered separately. Resumed in `_land()`.
	_charge_through_air = _charging
	_set_state(State.AIR)
	play_sfx(sfx_jump)
	if speed > walk_speed:
		_spawn_puff(charge_colour, 14, 5.0, Vector3.DOWN)


## What a boost would be worth right now: the full `boost_impulse` up to
## `charge_top_speed`, fading away to nothing by `boost_fade_speed`.
##
## The fade is deliberately ZERO through the charge's whole normal range, because
## the boost is the steering vocabulary at speed and a weak boost is no steering
## at all. It only starts buying itself out ABOVE the speed the charge engine
## itself reaches - which is to say, once you are already going faster than the
## game ever promised you.
func boost_strength() -> float:
	var speed := flat_speed()
	var free_until := minf(charge_top_speed, boost_fade_speed)
	if speed <= free_until:
		return boost_impulse
	if speed >= boost_fade_speed:
		return 0.0
	var into_fade := (speed - free_until) / maxf(boost_fade_speed - free_until, 0.01)
	return boost_impulse * (1.0 - into_fade)


func _try_boost() -> void:
	if _boost_cool > 0.0:
		return
	if boost_taps > 0 and _boosts_left <= 0:
		return
	var power := boost_strength()
	if power <= 0.0:
		# Faded out entirely. Nothing is spent - no tap, no cooldown - so the
		# boost comes back by itself as friction brings you under the fade speed,
		# rather than being quietly eaten at the one moment it could not work.
		#
		# And refusing OUTRIGHT rather than applying a zero-length impulse is the
		# load-bearing half: the `facing = dir` below would otherwise still snap
		# your heading for free, which hands back the exact authority the speed
		# just took away. A free turn at top speed is the hole the fade opens if
		# you are not careful, and it is worth more than the speed was.
		#
		# Still answers the press, in the only language available. A refused input
		# that looks identical to a DROPPED input is the thing to avoid - same rule
		# as a refused breakable block shaking instead of sitting there.
		_spawn_puff(boost_colour, 4, 2.0, Vector3.UP)
		return
	var dir := wish_dir if wish_dir != Vector3.ZERO else facing
	# ADDED, never assigned. A boost that rewrote the velocity would be free
	# steering, and would hand back all the authority the speed just took away.
	# Adding means course-correcting leaves you FASTER and more committed, which
	# is the point of the verb rather than a side effect of it.
	velocity += dir * power
	_boost_cool = boost_cooldown
	if boost_taps > 0:
		_boosts_left -= 1
	if state == State.CHARGE:
		facing = dir
	# Sized by what the boost was actually WORTH, so a fading one looks like it
	# is fading rather than looking broken.
	var fraction := power / maxf(boost_impulse, 0.01)
	_spawn_puff(boost_colour, int(round(4.0 + 8.0 * fraction)), 5.0, -dir)
	_shake(0.12 * fraction)


func _begin_slam() -> void:
	# Remembered now, because _do_slam is about to destroy it and the impact is
	# owed that speed. This is the difference between a drop and a brake.
	_slam_entry_speed = flat_speed()
	velocity.y = minf(velocity.y, 0.0)
	# A SLAM ENDS A CHARGE even if you never let go, because the slam IS the
	# brake - that is the whole reason it exists as well as being the attack.
	# Landing one and rolling straight back off into a charge would take the
	# brake away and leave the move with nothing to stop you with.
	_charge_through_air = false
	_set_state(State.SLAM)


func _slam_impact() -> void:
	var drop := maxf(0.0, _air_peak_y - global_position.y)
	# TWO HALVES, and the second is the whole reason the slam doubles as a
	# brake: force comes from how far you fell AND from how much horizontal
	# speed you just delivered into the floor. So a flat-out charge cancelled
	# into a slam hits hard with no drop at all, and braking on fragile footing
	# breaks it — rule 2 turned back on yourself.
	var from_drop := clampf(drop / maxf(slam_power_height, 0.01), 0.0, 1.0)
	var from_brake := _slam_entry_speed * brake_impact_scalar
	var force := (from_drop + from_brake) * impact_force_scalar

	velocity = Vector3.ZERO
	_slam_recover_left = slam_recover
	_slam_entry_speed = 0.0
	_set_state(State.WALK)

	# The bus is how every prop in this project hears about an impact; the
	# player holds no reference to crumbling floors or breakable blocks.
	Events.slam_landed.emit(global_position, force)
	# Props hear about this through the bus; loose objects are not props and have
	# no script to listen with, so they are kicked directly.
	_scatter_loose_objects(force)
	_spawn_ring(2.4 + 4.0 * clampf(force, 0.0, 1.5), force > 0.8)
	_spawn_puff(crash_colour, 16, 4.0, Vector3.DOWN)
	_shake(land_shake + force * 0.6)
	play_sfx(sfx_land)


func _crash() -> void:
	var force := _pre_move_flat.length()
	_charging = false
	_stun_left = crash_stun
	# Bounce, dust, get up. Early crashes are meant to be cheap and funny, so
	# the penalty is this stun and nothing else.
	var back := -_pre_move_flat.normalized()
	velocity = back * crash_bounce + Vector3.UP * crash_bounce * 0.35
	_set_state(State.WALK)
	crashed.emit(global_position, force)
	_spawn_puff(crash_colour, 20, 6.5, -back)
	_shake(crash_shake)
	play_sfx(sfx_land)


func _land() -> void:
	var fell := _pre_move_vy
	# Still holding, and this jump came out of a charge? Then you are still in
	# the SAME charge - straight back to CHARGE with no second wind-up. The
	# wind-up is the price of STARTING a charge, and you only pay it once.
	#
	# Note what is NOT done here: a held button alone does not start a charge on
	# landing. It has to be a charge you were already in. Otherwise a crash,
	# which dumps you into WALK while you are very likely still mashing the
	# button, would wind you straight back up and fire you into the same wall.
	if _charge_through_air and Input.is_action_pressed(&"attack"):
		_charging = true
		_set_state(State.CHARGE)
	else:
		_set_state(State.WALK)
	_charge_through_air = false
	if fell > -5.0:
		return
	# An ordinary landing does juice only. It deliberately does NOT emit
	# `slam_landed`: that signal means "a slam happened", and firing it on every
	# touchdown would have crumbling floors collapsing under a hop. A heavy
	# landing still breaks fragile ground, through the floor's own
	# `descent_speed()` check — see crumbling_floor.gd.
	_spawn_puff(Color(0.85, 0.82, 0.76), 10, 3.0, Vector3.DOWN)
	_shake(land_shake * clampf(-fell / max_fall_speed, 0.0, 1.0))
	play_sfx(sfx_land)


# ──────────────────────────────────────────────────────────────── the basics

func _brake(delta: float, rate: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


## Gravity projected onto the floor plane: `g * sin(angle)` straight downhill
## and exactly zero on the flat, with no per-slope tuning anywhere.
##
## Downhill slopes are free acceleration, and converting height into speed is
## the game's currency — in both directions, since the slam converts it back
## into force. The two multipliers exist so the gift and the cost can be tuned
## apart, which is what the doc's "slope accel/decel multipliers" means.
func _slope_pull(delta: float) -> void:
	if not is_on_floor():
		return
	var normal := get_floor_normal()
	var downhill := Vector3.DOWN - normal * Vector3.DOWN.dot(normal)
	if downhill.length() < slope_min_grade:
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var with_it := flat.length_squared() < 0.01 or downhill.dot(flat) >= 0.0
	var mult := slope_accel_mult if with_it else slope_decel_mult
	velocity.x += downhill.x * slope_gravity * mult * delta
	velocity.z += downhill.z * slope_gravity * mult * delta


func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = minf(velocity.y, 0.0)
		return
	var g := gravity_rise if velocity.y > 0.0 else gravity_fall
	velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)


# ──────────────────────────────────────────── what props are allowed to ask

## Horizontal velocity from BEFORE this frame's collision resolution.
##
## Props must read this rather than `velocity`. Running into a block means
## `move_and_slide()` has already zeroed the horizontal velocity by the time the
## block's Area3D reports the overlap, in the same physics step — so reading
## `velocity` there sees a stationary player and refuses every hit however fast
## you arrived. The same trap exists on the vertical axis; see descent_speed().
func approach_velocity() -> Vector3:
	return _pre_move_flat


func approach_speed() -> float:
	return _pre_move_flat.length()


## Vertical speed from before collision resolution. The twin of the above, and
## the reason a stomp or a heavy landing can be detected at all.
func descent_speed() -> float:
	return _pre_move_vy


## How much a slam landing right now would be worth, 0 to 1, from drop alone.
func slam_power() -> float:
	var drop := maxf(0.0, _air_peak_y - global_position.y)
	return clampf(drop / maxf(slam_power_height, 0.01), 0.0, 1.0)


func is_charging() -> bool:
	return state == State.CHARGE


func state_name() -> String:
	return State.keys()[state]


# ─────────────────────────────────────────────────────────────────── juice

## Weight is 50% feedback: sluggish and weighty are the same numbers with
## different presentation. None of this is polish, which is why it is here in
## the first greybox rather than scheduled for later.
func _spawn_puff(tint: Color, amount: int, speed: float, burst_dir: Vector3) -> void:
	if jump_fx == null:
		return
	var puff := jump_fx.instantiate() as Node3D
	get_tree().current_scene.add_child(puff)
	# Parented to the level rather than to us, so the dust stays where it
	# happened instead of riding along.
	puff.global_position = global_position + Vector3.UP * 0.25
	if puff.has_method(&"play"):
		puff.call(&"play", tint, amount, speed, burst_dir)


func _spawn_ring(radius: float, big: bool) -> void:
	if impact_fx == null:
		return
	var ring := impact_fx.instantiate() as Node3D
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position
	if ring.has_method(&"play"):
		ring.call(&"play", radius, big)


func _shake(amount: float) -> void:
	if rig != null:
		rig.shake(amount)


func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	sfx.stream = stream
	sfx.play()


func _update_visual(delta: float) -> void:
	if facing.length_squared() < 0.01:
		return
	var wanted := atan2(facing.x, facing.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, wanted, face_turn_speed * delta)
	# A visible lean into the charge. Presentation exaggerates; the numbers
	# underneath stay honest.
	var lean := 0.18 if (state == State.CHARGE or _charge_through_air) else 0.0
	if _windup_left > 0.0:
		lean = -0.22
	visual.rotation.x = lerp_angle(visual.rotation.x, lean, 8.0 * delta)


func _set_state(next: State) -> void:
	if state == next:
		return
	var previous := state
	state = next
	if next != State.CHARGE:
		_charging = false
	state_changed.emit(previous, next)


## Feeds the F3 readout. Keeping it here means the HUD needs to know nothing
## about the controller's internals.
func debug_info() -> Dictionary:
	return {
		"state": state_name(),
		"speed": flat_speed(),
		"authority": "%.2f" % authority(),
		"vy": velocity.y,
		"floor": is_on_floor(),
		"windup": "%.2f" % maxf(_windup_left, 0.0),
		"boosts": "%d (cool %.2f, worth %.1f)" % [
			_boosts_left, maxf(_boost_cool, 0.0), boost_strength()],
		"charge held": _charge_through_air,
		"slam": "power %.2f" % slam_power(),
	}
