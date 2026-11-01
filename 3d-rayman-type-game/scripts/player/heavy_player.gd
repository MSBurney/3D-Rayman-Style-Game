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
	## On a rail. No steering, no gravity, and `move_and_slide()` does not run at
	## all — the rail sets the position itself.
	GRIND,
	## Set alight: sprinting the way you were facing with almost no steering,
	## until it burns out. A penalty AND a key.
	FLAMING,
	## Inflated: floating upward, weightless, unable to act. The vertical twin of
	## FLAMING.
	PUFFY,
	## Turning round the hard way: sliding one direction while already facing the
	## other. The doc's "crash-stop / slide", and the only immediate way to
	## reverse that the authority curve allows.
	SKID,
}

signal state_changed(from: State, to: State)
## A charge ended against something solid. Carries where, and the speed that was
## killed — which is what rule 2 (momentum transfers on impact) is made of.
signal crashed(at: Vector3, force: float)
## Picked something up, or threw it. A level can react without the player
## knowing what a level is.
signal picked_up(what: Node3D)
signal thrown(what: Node3D, aim: Vector3)

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

@export_group("Skid and side-jump")
## **The immediate turnaround, and the reason it is allowed to exist.**
##
## The authority curve deliberately will not let you turn at speed, which is
## correct and also means a heavy character has no answer at all to "I am going
## the wrong way". A skid is that answer without breaking the rule: it does not
## TURN you, it stops you — hard, over a visible slide, while your heading
## pivots ahead of your body. You pay in distance for the direction.
##
## The doc already has it: *"Crash-stop / slide — ending a charge: hit
## something, slide out, or cancel into slam. Stopping is itself a mechanic
## with a cost."*
##
## Minimum speed to be worth skidding. Below it, ordinary walk authority already
## turns you and a skid would just be a stutter.
@export var skid_min_speed: float = 8.0
## How far the stick has to be turned back against your travel, as a dot
## product. 0.4 is roughly 115 degrees or more.
@export_range(0.0, 1.0) var skid_turn_dot: float = 0.4
## How hard the slide brakes. This is the cost of the turn, so it is the number
## to tune if a skid feels either free or interminable.
@export var skid_friction: float = 26.0
## Drop below this and the skid is over, pointed the new way at this speed.
@export var skid_exit_speed: float = 2.5
## RADIANS PER SECOND that the heading swings round during the slide. Faster
## than the body, on purpose: facing the new way before travelling it is the
## whole read. At 9 a full reversal takes about a third of a second.
@export var skid_turn_speed: float = 9.0
@export var skid_colour: Color = Color(0.95, 0.88, 0.45)
## The skid cashed in for height — Mario 64's side flip. Jump during a skid.
##
## SETS velocity rather than adding to it, like every other move here. The long
## jump was the only additive one and was the only one that could be farmed.
@export var side_jump_speed: float = 11.0
@export var side_jump_rise: float = 13.0
@export var side_jump_colour: Color = Color(0.5, 0.95, 0.6)

@export_group("Taking a hit")
## **THERE IS NO DEATH.** A hit knocks you back and scatters the money you were
## carrying where you lost it, for you to scramble back — the doc's field-damage
## model, and every penalty is live and in-arena rather than travel time.
@export var hit_knockback: float = 12.0
## Blind spell after a hit, so one hazard cannot drain you in a single second.
@export var hurt_invuln: float = 0.9

@export_group("Rail grinding")
## Ported from `player.gd` along with the two bugs it took to get right — read
## the rail-grinding section of CLAUDE.md before touching any of this.
##
## **This is a verb the design doc's state diagram does not contain.** It was
## kept by an explicit decision rather than by the doc, so the document wants
## amending to say so.
@export var grind_snap_distance: float = 1.6
@export var grind_friction: float = 4.0
@export var grind_accel: float = 16.0
@export var grind_stall_speed: float = 1.2
@export var grind_jump_boost: float = 1.0
## Without it, jumping off re-attaches you on the very next frame because you
## are still well inside the snap distance, and the jump looks like it did
## nothing. The let-go law again.
@export var grind_relatch_delay: float = 0.35
## Divides drag AND the accelerator, so weight buys top speed and costs
## response — the same trade the rest of the character makes. Note that is the
## opposite sign from "heavy things grind slower".
@export var grind_weight: float = 1.6
@export var grind_jump_colour: Color = Color(0.35, 1.0, 0.8)

@export_group("Transformations")
## A TOOL transforms you and does no damage; a THREAT damages you. That split is
## the load-bearing idea and nothing in here touches it — see `transformer.gd`.
##
## Every transformation must time out. They are states with no exit but the
## clock (and `crouch` to pop PUFFY), so the timer is the only thing stopping
## them from being a trap.
@export var flame_time: float = 2.2
## Above every `BreakableBlock.break_speed` on purpose, so being set alight
## opens every speed-gated wall in the game at no cost in code anywhere. Keep it
## above `break_speed` or the point of the transformation goes.
@export var flame_speed: float = 20.0
## Radians per second of steering while alight — nearly nothing. You have to
## line yourself up BEFORE touching the fire, and that is the skill the penalty
## creates rather than an annoyance it imposes.
@export var flame_turn_rate: float = 0.9
@export var flame_colour: Color = Color(1.0, 0.55, 0.15)
@export var puff_time: float = 3.0
@export var puff_rise: float = 3.4
@export_range(0.0, 1.0) var puff_control: float = 0.3
## Downward speed you pop out with, so deflating is a committed drop rather than
## a gentle stop.
@export var puff_pop_fall: float = -6.0
@export var puff_colour: Color = Color(0.6, 0.85, 1.0)

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
## MOMENTUM given to a loose object right next to a slam of force 1.0 — not a
## speed. So the same impact tosses a crate and barely rocks something huge,
## which is the only version that survives an enemy with a mass of 40 standing
## next to it. Divide by a mass to read it as a speed: 40 of this is 5 m/s to an
## 8-mass crate.
@export var slam_scatter_power: float = 70.0
## How much of an incoming object's momentum lands on YOU. Rule 2 cuts both
## ways or it is not a rule — see `_on_hitbox_entered`.
@export var impact_take: float = 0.8

@export_group("Carry")
## **The heaviest thing you can lift.** Above it, an object can only be rammed.
##
## That is a puzzle rather than a restriction, and it is the reason this number
## exists at all: a crate you cannot pick up is one you have to shove, so the
## same vocabulary gives a level two different kinds of object with one number.
## The greybox has an 8 you can carry and a 16 you cannot.
@export var carry_max_mass: float = 10.0
## How close you have to be for the automatic pickup.
@export var carry_reach: float = 1.9
## Where a carried thing is held, relative to us and to `facing`.
@export var carry_height: float = 1.95
@export var carry_forward: float = 0.9
## Blind spell after letting go, before the same object can be taken again.
##
## **Five for five in this codebase now**, after `ledge_cooldown`, the spin's
## `regrab_delay`, `grind_relatch_delay` and `ItemThief.relatch_delay`. Pickup
## here is automatic, so without it the thing you just threw is re-collected on
## the next frame while it is still a metre away, and the throw looks like it
## did nothing at all.
@export var carry_regrab_delay: float = 0.55
## Forward and upward speed added to a throw, on top of your own momentum.
@export var throw_speed: float = 17.0
@export var throw_lift: float = 6.5

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
## What we are carrying, or null. Public so a HUD or a test can read it.
var carried: Node3D = null
var _regrab: float = 0.0
var _carried_layer: int = 0
var _carried_mask: int = 0

var _rail: GrindRail = null
## How far along `_rail` we have travelled, in metres from its start.
var _rail_offset: float = 0.0
## SIGNED, not a magnitude plus a direction: one line of slope maths then
## handles both ways along a rail correctly.
var _rail_speed: float = 0.0
var _rail_dir: float = 1.0
var _grind_lock: float = 0.0

## Where the skid is pointing us. Held separately from `facing` because the
## heading chases it while the body is still sliding the other way.
var _skid_aim: Vector3 = Vector3.FORWARD
var _hurt_lock: float = 0.0
var _spawn: Transform3D

var _transform_left: float = 0.0
## Our mass with nothing done to us, so PUFFY can take it to zero and give it
## back. Captured in `_ready()` rather than on transforming, so transforming
## twice cannot capture the zero.
var _base_mass: float = 10.0
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
	_base_mass = mass
	_spawn = global_transform


func _physics_process(delta: float) -> void:
	_tick(delta)
	_read_input()

	match state:
		State.WALK: _do_walk(delta)
		State.CHARGE: _do_charge(delta)
		State.AIR: _do_air(delta)
		State.SLAM: _do_slam(delta)
		State.SKID: _do_skid(delta)
		State.FLAMING: _do_flaming(delta)
		State.PUFFY: _do_puffy(delta)
		State.GRIND:
			_do_grind(delta)
			# Kept honest even though nothing moves us with it, because it is
			# what `approach_velocity()` hands a breakable block you grind
			# into. The old controller left these stale here, so a rail into a
			# block measured the speed from before the grind began.
			_pre_move_flat = Vector3(velocity.x, 0.0, velocity.z)
			_pre_move_vy = velocity.y
			_update_visual(delta)
			# RETURNS BEFORE `move_and_slide()`, and that is a requirement rather
			# than an optimisation: the rail sets `global_position` itself, and
			# letting the physics body also move us drags us straight off the
			# line. If a grind ever stutters or sags off a rail, something
			# re-enabled this.
			return

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
	_regrab -= delta
	_grind_lock -= delta
	_hurt_lock -= delta
	_carry_tick()
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
		if state == State.GRIND:
			# `attack` is the rail ACCELERATOR while grinding, read directly by
			# `_do_grind()` as a held button — so the press must not also throw or
			# boost. The grind takes the button over for its duration, which is a
			# real conflict and the same one the spin had with it on the old
			# controller.
			pass
		elif is_transformed():
			# A transformation you can act your way out of is not a penalty.
			pass
		elif carried != null:
			# CARRYING REPLACES WHAT THE BUTTON MEANS, and the throw happens on
			# the frame of the press with no hold-versus-tap timer anywhere near
			# it. A throw that waited to find out whether you actually meant a
			# charge would be precisely the input latency the cardinal rule
			# forbids — and latency is the one thing a heavy character cannot
			# afford to be mistaken for.
			#
			# The cost is that you cannot wind up a charge with your hands full.
			# That is a trade worth having rather than a limitation: carrying
			# something takes your traversal verb away until you throw it, which
			# is the most Wario sentence in the file.
			_throw()
		elif state == State.WALK:
			# Remembered rather than acted on, because a wind-up can only start
			# from the floor. See charge_buffer.
			_charge_buffered = charge_buffer
		elif state == State.CHARGE or state == State.AIR:
			_try_boost()

	if Input.is_action_just_pressed(&"crouch"):
		if state == State.PUFFY:
			# Deciding WHEN to deflate is the one real choice the state offers.
			# Without it, PUFFY is pure waiting.
			_pop_puffy()
		elif state == State.AIR or state == State.CHARGE:
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

	# Checked before steering, so the frame you ask to turn round is the frame it
	# starts, rather than being spent fighting `_steer_ground` first.
	if _wants_skid():
		_begin_skid()
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

	# Catching a rail. Checked from the AIR only, so you have to jump or fall on
	# to one rather than walking sideways into it.
	if _grind_lock <= 0.0:
		var rail := _find_rail()
		if rail != null:
			_attach_to_rail(rail)
			return

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
		State.SKID:
			if not is_on_floor() and _coyote <= 0.0:
				_set_state(State.AIR)
		State.FLAMING, State.PUFFY:
			# Nothing. A transformation ends on its own clock and on nothing else,
			# which is what makes it a state you have to plan around rather than
			# one you can scrub off against the first wall you find.
			pass


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
	# One body can be reported several times across move_and_slide's iterations,
	# and shoving it twice in a frame is twice the momentum out of nowhere.
	var done: Array[RigidBody3D] = []
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider() as RigidBody3D
		if body == null or body == carried or done.has(body):
			continue
		done.append(body)
		# The formula lives in `weight.gd` and nothing about it is player-specific.
		# That is the point: when an enemy needs to shove crates, it is these four
		# lines and not a second copy of the arithmetic to drift out of step.
		Weight.collide(self, body, hit.get_normal(), hit.get_position(),
			push_transfer, push_min_speed)



## How far the shockwave carries. Rule 4 — it grows with the force, so a drop
## from a height reaches things a hop does not. Shared by BOTH halves of the
## shockwave (loose objects and strikable props) so a crate and a switch
## standing side by side are reached by one radius and one falloff rather than
## by two that can drift apart.
func _slam_reach(force: float) -> float:
	return slam_scatter_radius * clampf(force, 0.25, 2.0)


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
	var reach := _slam_reach(force)
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
			if body == carried:
				continue
			done.append(body)
			# Mostly outward with a lift in it, so things leave the ground and
			# the impact reads as a shockwave rather than as a floor sweep.
			var away := (offset / gap + Vector3.UP * 0.9).normalized()
			var momentum := slam_scatter_power * force * (1.0 - gap / reach)
			Weight.add_momentum(body, away * momentum)


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
	if rigid == null or rigid == carried:
		return
	var offset := rigid.global_position - global_position
	if offset.length_squared() < 0.0001:
		return
	# `deliver` and not `collide`, because nothing stopped this: the crate came
	# to US and our own velocity was never zeroed by the solver. See the note on
	# the two in `weight.gd` — using the wrong one pushes the receiver TOWARDS
	# the thing that hit them.
	var normal := offset.normalized()
	var delivered := Weight.deliver(rigid, self, normal, rigid.global_position,
		impact_take, push_min_speed)
	if delivered <= 0.0:
		return
	_spawn_puff(crash_colour, 10, 3.5, normal)
	_shake(clampf(delivered * 0.03, 0.0, crash_shake))
	play_sfx(sfx_land)


# ──────────────────────────────────────────────────── carrying and throwing

## Where a carried thing rides: in front of the face, clear of the capsule so
## that letting go does not drop it inside us.
func hold_position() -> Vector3:
	return global_position + Vector3.UP * carry_height + facing * carry_forward


## Keeps a carried thing with us, and looks for one to pick up if we have none.
func _carry_tick() -> void:
	if carried != null:
		if not is_instance_valid(carried):
			carried = null
			return
		carried.global_position = hold_position()
		return
	_try_pick_up()


## Automatic pickup, no button: walk into a carryable thing and you have it.
##
## **WALK MODE ONLY, and that is the resolution of a real conflict rather than a
## restriction.** Picking things up on contact and ramming things on contact are
## the same input, so one of them had to lose — and the mode split had already
## drawn the line. Arrive slowly and you lift it; arrive committed and you hit
## it. `walk_speed` was already the border between precise and unstoppable, so
## the whole vocabulary falls out of the existing curve instead of needing a
## button nobody asked for.
func _try_pick_up() -> void:
	if _regrab > 0.0 or state == State.CHARGE or _windup_left > 0.0:
		return
	if flat_speed() > walk_speed:
		return

	var best: Node3D = null
	var closest := carry_reach
	# **BOTH groups, and leaving `throwable` out was a real bug.**
	#
	# `carryable` is the greybox's name and `throwable` is the older one for the
	# same idea — "a thing you can pick up and throw". Walking only `carryable`
	# meant the only liftable objects in the entire game were four crates written
	# by hand into two level files: the keg, the platform seed and anything else
	# using `throwable.gd` were all invisible to the carry verb.
	#
	# That made `hostage_pit_main` UNWINNABLE the moment it was repointed at this
	# controller, because the whole level is "carry the seed to the socket" and
	# the seed could not be carried. The smoke suite is what caught it.
	#
	# Honouring both rather than re-tagging every prop: a group is a published
	# extension point, and `throwable` is the one the props already use.
	var seen: Array[Node] = []
	for group in [&"carryable", &"throwable"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			# A prop can legitimately be in both, and measuring it twice is
			# harmless but picking the wrong one is not.
			if body == null or seen.has(body):
				continue
			seen.append(body)
			# ALREADY IN SOMEBODY ELSE'S HANDS. Without this the player can lift
			# the seed straight off a boss or a snatcher that is carrying it,
			# because the pickup is a position check and a held object is still
			# sitting at its carrier's hold point.
			if body.has_method(&"is_held") and body.call(&"is_held"):
				continue
			# Too heavy to lift, so it has to be rammed instead. See
			# `carry_max_mass`.
			if Weight.mass_of(body) > carry_max_mass:
				continue
			var gap := body.global_position.distance_to(
				global_position + Vector3.UP * 0.9)
			if gap < closest:
				closest = gap
				best = body
	if best != null:
		_pick_up(best)


func _pick_up(what: Node3D) -> void:
	carried = what
	# **ASK THE PROP FIRST, and not asking was a real bug.**
	#
	# `throwable.gd` and `platform_seed.gd` both implement `pick_up(by)`, and
	# this controller used to skip it and do the RigidBody3D handling itself.
	# That works for a bare scriptless crate and is wrong for everything with a
	# script, because a prop's `pick_up` is where it records WHO is holding it.
	#
	# The seed was the worst case: `is_held()` stayed false, so its own
	# invariant — "not held but still frozen is always wrong" — fired and it
	# rescued itself straight out of the player's hands. And because nothing in
	# the world knew it was held, a snatcher or the boss could take it at the
	# same time. The smoke suite caught all four of those at once.
	if what.has_method(&"pick_up"):
		what.call(&"pick_up", self)
		what.global_position = hold_position()
		picked_up.emit(what)
		return
	var rigid := what as RigidBody3D
	if rigid != null:
		# Frozen and taken off every layer for the duration. Leave it solid and it
		# fights the body it is riding on; leave it simulating and gravity drags
		# it out of our hands.
		_carried_layer = rigid.collision_layer
		_carried_mask = rigid.collision_mask
		rigid.freeze = true
		rigid.linear_velocity = Vector3.ZERO
		rigid.angular_velocity = Vector3.ZERO
		rigid.collision_layer = 0
		rigid.collision_mask = 0
	what.global_position = hold_position()
	picked_up.emit(what)


## Throws it, inheriting our own momentum.
##
## Rule 2 once more, and the same rule the jump obeys: a throw out of a charge
## goes much further than one from a standstill, and what you threw arrives
## somewhere carrying real speed. A flat throw speed that ignored your motion
## would make the hero the one object in the game that momentum does not apply
## to.
func _throw() -> void:
	var aim := facing * throw_speed + Vector3.UP * throw_lift
	aim += Vector3(velocity.x, 0.0, velocity.z)
	var what := carried
	_release(aim)
	if what != null:
		_spawn_puff(boost_colour, 12, 4.5, -aim.normalized())
		thrown.emit(what, aim)


## Hands it back to the world with `aim` as its new velocity.
func _release(aim: Vector3) -> void:
	var what := carried
	carried = null
	_regrab = carry_regrab_delay
	if what == null or not is_instance_valid(what):
		return
	# The other half of the protocol. A prop that took `pick_up` must be given
	# `throw` or `drop`, or it stays frozen and layer-less for ever believing it
	# is still being carried.
	if what.has_method(&"throw"):
		what.call(&"throw", aim)
		return
	if what.has_method(&"drop"):
		what.call(&"drop")
		Weight.add_velocity(what, aim)
		return
	var rigid := what as RigidBody3D
	if rigid == null:
		Weight.add_velocity(what, aim)
		return
	rigid.collision_layer = _carried_layer
	rigid.collision_mask = _carried_mask
	rigid.freeze = false
	# DEFERRED, and this is not optional: a RigidBody3D ignores a velocity set on
	# the frame it unfreezes, and the throw drops limply at your feet instead.
	rigid.set_deferred(&"linear_velocity", aim)
	rigid.set_deferred(&"sleeping", false)


## Put down whatever we are holding before we stop existing.
##
## A frozen, layer-less object with nothing holding it is the "not held but
## still frozen" state `platform_seed.gd` treats as always wrong — and the seed
## rescues itself precisely because a carrier cannot be trusted to tidy up. A
## bare scriptless crate has no such safety net, so the carrier is the only
## thing that can, and it does it here rather than in any one code path.
func _exit_tree() -> void:
	if carried != null:
		_release(Vector3.ZERO)




# ───────────────────────────────────────────────── skidding and the side-jump

## Has the stick been turned back against the way we are actually travelling?
##
## Measured on the INPUT and never on the velocity, and that is the one lesson
## the old controller's side flip paid for: heavy handling will not let velocity
## turn round quickly BY DESIGN, so a move that waited for the velocity to
## reverse would simply never fire.
##
## Deliberately not reachable from CHARGE. A charge has **no free brakes** — it
## ends by impact, by sliding out, or by cancelling into a slam — and a skid out
## of one would be the free brake the whole verb is defined by not having.
func _wants_skid() -> bool:
	if wish_dir == Vector3.ZERO or not is_on_floor():
		return false
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < skid_min_speed:
		return false
	return wish_dir.dot(flat.normalized()) < -skid_turn_dot


func _begin_skid() -> void:
	_skid_aim = wish_dir
	_set_state(State.SKID)
	_spawn_puff(skid_colour, 14, 3.5, -wish_dir)
	play_sfx(sfx_land)


func _do_skid(delta: float) -> void:
	# The heading pivots while the body keeps sliding, which IS the read: you are
	# visibly facing the new way before you are travelling it, so the slide looks
	# like a decision rather than like losing control.
	if wish_dir != Vector3.ZERO:
		_skid_aim = wish_dir
	# ROTATED about UP by a clamped angle, never `slerp`. A skid is very often an
	# exact 180-degree reversal, and `Vector3.slerp` between opposite vectors is
	# DEGENERATE — there is no defined axis to turn about, so it returns the start
	# unchanged and the heading never moves at all. The charge's steering already
	# uses this pattern for the same reason.
	var swing := skid_turn_speed * delta
	var angle := facing.signed_angle_to(_skid_aim, Vector3.UP)
	facing = facing.rotated(Vector3.UP, clampf(angle, -swing, swing)).normalized()

	_brake(delta, skid_friction)
	_slope_pull(delta)
	_apply_gravity(delta)

	if _jump_buffered > 0.0 and (_coyote > 0.0 or is_on_floor()):
		_side_jump()
		return
	if flat_speed() <= skid_exit_speed:
		# Out of the far side pointed the new way, at walking pace. The slide was
		# the cost; the direction is what it bought.
		velocity.x = _skid_aim.x * skid_exit_speed
		velocity.z = _skid_aim.z * skid_exit_speed
		facing = _skid_aim
		_set_state(State.WALK)


## A skid cashed in for height, and the reason it earns a place: the authority
## curve will not turn you at speed, so the set needs ONE move that reverses you
## outright. Mario 64 spends its side flip on exactly this.
func _side_jump() -> void:
	_jump_buffered = 0.0
	_coyote = 0.0
	facing = _skid_aim
	velocity.x = _skid_aim.x * side_jump_speed
	velocity.z = _skid_aim.z * side_jump_speed
	velocity.y = side_jump_rise
	_set_state(State.AIR)
	play_sfx(sfx_jump)
	# Thrown BACKWARDS, against the new heading. The direction dust is thrown is
	# what you read before you have consciously registered the colour.
	_spawn_puff(side_jump_colour, 16, 5.5, -_skid_aim)


# ───────────────────────────────────────── taking a hit, with no death in it

## **THERE IS NO DEATH, so `damage` is accepted and ignored.**
##
## Deliberately still named and shaped like the old controller's `take_hit`:
## every hazard, enemy, bullet and boss in the project already calls exactly
## this, so the no-death model belongs HERE, in one place, rather than in a
## change to each of them. They hand over a damage number; this controller is
## simply not interested in it.
##
## What happens instead is the doc's field-damage model: a reaction, knockback,
## and **the money you were carrying scatters where you lost it** for you to
## scramble back. Every penalty is live and in-arena, never travel time.
func take_hit(_damage: int, from: Vector3, coin_cost: int = 0) -> bool:
	if _hurt_lock > 0.0:
		return false
	_hurt_lock = hurt_invuln

	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -facing
	away = away.normalized()
	velocity.x = away.x * hit_knockback
	velocity.z = away.z * hit_knockback
	velocity.y = maxf(velocity.y, hit_knockback * 0.45)
	_stun_left = maxf(_stun_left, crash_stun)
	_charging = false
	_charge_through_air = false
	if carried != null:
		_release(Vector3.ZERO)

	# Game owns the running total and is therefore the only thing that can clamp
	# the loss to what you actually have, which is why the scatter lives there.
	Events.player_hurt.emit(global_position, coin_cost)
	_set_state(State.AIR)
	_spawn_puff(crash_colour, 16, 5.0, away)
	_shake(crash_shake)
	play_sfx(sfx_land)
	return true


## Bounced off something we landed on — an enemy stomp calls this.
func bounce(force: float = -1.0) -> void:
	velocity.y = jump_speed if force < 0.0 else force
	_set_state(State.AIR)


## Put back, without having died. There is no death here, so this is only ever
## "you fell off the world" or a checkpoint — never a penalty in itself.
func respawn_at(where: Transform3D) -> void:
	global_transform = where
	velocity = Vector3.ZERO
	if carried != null:
		_release(Vector3.ZERO)
	_stun_left = 0.0
	_slam_recover_left = 0.0
	_windup_left = 0.0
	_charging = false
	_charge_through_air = false
	_transform_left = 0.0
	_rail = null
	_grind_lock = 0.0
	_hurt_lock = 0.0
	mass = _base_mass
	_set_state(State.AIR)
	Events.player_respawned.emit()


## Puts down what we are holding, if it is `what` — or whatever we have, if
## `what` is null. Public so a boss can take something back out of your hands
## without naming this controller, and so `platform_seed.gd` can insist on
## being let go.
func drop_carried(what: Node3D = null) -> void:
	if carried == null:
		return
	if what != null and carried != what:
		return
	_release(Vector3.ZERO)


func spawn_transform() -> Transform3D:
	return _spawn


## Transforms us by NAME rather than by a `State` value.
##
## The old controller's `FLAMING` is a different number from this one's, so a
## prop that passed an enum value between them would be a bug waiting for the
## next time either enum gained a member. A name cannot drift.
func transform_named(form: StringName, seconds: float = -1.0) -> void:
	match form:
		&"FLAMING":
			transform_into(State.FLAMING, seconds)
		&"PUFFY":
			transform_into(State.PUFFY, seconds)


# ──────────────────────────────────────────────────────────────── grinding

## On a rail. Ported from `player.gd`; the comments there earned their keep.
func _do_grind(delta: float) -> void:
	if _rail == null:
		_leave_rail(false)
		return

	var tangent := _rail.tangent_at(_rail_offset)

	# Gravity along the rail, and the one line worth reading twice. `tangent`
	# always points towards the rail's far end, so `tangent.y` IS the grade in
	# that direction. Because the speed is SIGNED, the same line correctly slows
	# you when you are running the other way along the same rail. Write it with
	# absolute values and an uphill grind accelerates.
	_rail_speed += -tangent.y * slope_gravity * delta

	var weight := maxf(grind_weight, 0.01)
	# The accelerator pushes along the way we are already going, never backwards.
	if Input.is_action_pressed(&"attack"):
		_rail_speed += _rail_dir * (grind_accel / weight) * delta

	# Drag opposes travel, and is CLAMPED rather than simply subtracted: without
	# the clamp, the frame that takes your last 0.1 m/s carries on and pushes you
	# gently backwards up the rail you just stopped on.
	var shed := (grind_friction * _rail.friction_scale / weight) * delta
	if absf(_rail_speed) <= shed:
		_rail_speed = 0.0
	else:
		_rail_speed -= signf(_rail_speed) * shed

	if absf(_rail_speed) > 0.01:
		_rail_dir = signf(_rail_speed)

	_rail_offset += _rail_speed * delta
	velocity = tangent * _rail_speed

	# Ran out of rail. The speed is KEPT: flying off the end fast is the whole
	# pay-off for taking the rail fast.
	if _rail_offset <= 0.0 or _rail_offset >= _rail.length():
		_rail_offset = clampf(_rail_offset, 0.0, _rail.length())
		_leave_rail(false)
		return

	# Jumping off. Read from the BUFFER rather than the raw button, as everywhere
	# else, and eaten so it cannot fire again the moment we land.
	if _jump_buffered > 0.0:
		_jump_buffered = 0.0
		_leave_rail(true)
		return

	# Ground to a halt without trying to recover, so fall off.
	if absf(_rail_speed) < grind_stall_speed and not Input.is_action_pressed(&"attack"):
		_leave_rail(false)
		return

	global_position = _rail.point_at(_rail_offset)
	facing = _flatten(tangent * _rail_dir)


## The nearest rail within `grind_snap_distance`, or null.
##
## Walks the `grindable` group by distance rather than using an `Area3D`, for the
## usual reason plus one specific to rails: a rail is a thin line tens of metres
## long, so an area shaped like it would be a chain of little boxes, and "how far
## along it are you" would still need the curve.
func _find_rail() -> GrindRail:
	var best: GrindRail = null
	var best_distance := grind_snap_distance
	for node in get_tree().get_nodes_in_group(GrindRail.GROUP):
		var rail := node as GrindRail
		if rail == null or rail.curve == null:
			continue
		var distance := rail.distance_to_rail(global_position)
		if distance < best_distance:
			best_distance = distance
			best = rail
	return best


## Locks on, carrying in the speed we arrived with — PROJECTED on to the rail,
## not our total speed. So crossing a rail at right angles gives you almost
## nothing and running along its line gives you everything, which is what makes
## a ramp leading into a rail worth building.
func _attach_to_rail(rail: GrindRail) -> void:
	_rail = rail
	_rail_offset = rail.closest_offset(global_position)
	var tangent := rail.tangent_at(_rail_offset)
	_rail_speed = velocity.dot(tangent)
	if absf(_rail_speed) > 0.01:
		_rail_dir = signf(_rail_speed)
	else:
		# Landed with no speed ALONG the rail, which is what dropping on to a flat
		# one out of a fall looks like. `_rail_dir` survives between grinds, so
		# without this branch it still holds the LAST rail's direction and the
		# accelerator pushes you whichever way that happened to be.
		_rail_dir = 1.0 if facing.dot(tangent) >= 0.0 else -1.0
	global_position = rail.point_at(_rail_offset)
	_set_state(State.GRIND)


## Lets go. Either way you keep the speed you had, pointed along the rail —
## that one rule is what makes rails traversal instead of scenery.
func _leave_rail(jumped: bool) -> void:
	var launch := Vector3.ZERO
	if _rail != null:
		launch = _rail.tangent_at(_rail_offset) * _rail_speed
	velocity = launch
	if jumped:
		# SET rather than added, and note this throws away the vertical part of
		# `launch`, which is the point: jumping off a steep downhill rail should
		# send you UP, not slightly less down.
		var along := absf(_rail_speed)
		velocity.y = minf(jump_speed + along * jump_speed_scaling, jump_speed_max) \
			+ grind_jump_boost
		play_sfx(sfx_jump)
		_spawn_puff(grind_jump_colour, 14, 5.0, -_flatten(launch))
	_rail = null
	_rail_speed = 0.0
	_set_state(State.AIR)


# ──────────────────────────────────────────────────────────── transformations

## A TOOL did this to us. Does NO damage — that is the whole tools/threats split.
func transform_into(which: State, seconds: float = -1.0) -> void:
	if which != State.FLAMING and which != State.PUFFY:
		return
	# Whatever we were holding is let go, or it stays welded to the hold point.
	if carried != null:
		_release(Vector3.ZERO)
	_charging = false
	_charge_through_air = false
	_windup_left = 0.0
	if which == State.FLAMING:
		_transform_left = seconds if seconds > 0.0 else flame_time
	else:
		_transform_left = seconds if seconds > 0.0 else puff_time
		# MASS ZERO while inflated — the doc's weight grammar for this form is
		# exactly "mass zero: thresholds and pivots stop answering to you". It
		# costs one line because `mass` is a real number the weight layer reads,
		# so a puffy player stops holding pressure plates down and stops tipping
		# see-saws without either prop knowing this state exists.
		mass = 0.0
	_set_state(which)
	_spawn_puff(flame_colour if which == State.FLAMING else puff_colour,
		16, 4.0, Vector3.UP)


## Sprinting the way you were facing, with almost no steering.
##
## The penalty IS the key: `flame_speed` is above every block's `break_speed`,
## so being alight opens every speed-gated wall — and you cannot steer, so you
## have to line yourself up before touching the fire.
func _do_flaming(delta: float) -> void:
	_transform_left -= delta
	if wish_dir != Vector3.ZERO:
		# A fixed ANGULAR allowance per second, not a slerp fraction: a slerp
		# turns fastest when the gap is widest, which is exactly when you must
		# not be able to turn.
		var allowance := flame_turn_rate * delta
		var angle := facing.signed_angle_to(wish_dir, Vector3.UP)
		facing = facing.rotated(Vector3.UP,
			clampf(angle, -allowance, allowance)).normalized()
	velocity.x = facing.x * flame_speed
	velocity.z = facing.z * flame_speed
	_apply_gravity(delta)
	if _transform_left <= 0.0:
		_set_state(State.WALK if is_on_floor() else State.AIR)


## Rising whether you like it or not, and weightless while you do.
func _do_puffy(delta: float) -> void:
	_transform_left -= delta
	if wish_dir != Vector3.ZERO:
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		flat = flat.move_toward(wish_dir * walk_speed * puff_control,
			walk_accel * delta)
		velocity.x = flat.x
		velocity.z = flat.z
	velocity.y = puff_rise
	if _transform_left <= 0.0:
		_pop_puffy()


## Deflates — by the clock, or by `crouch`.
func _pop_puffy() -> void:
	_set_state(State.AIR)
	velocity.y = puff_pop_fall
	_spawn_puff(puff_colour, 12, 4.5, Vector3.DOWN)


## True while a transformation has us. Props ask this rather than comparing
## states, so a third form needs no edits outside this file.
func is_transformed() -> bool:
	return state == State.FLAMING or state == State.PUFFY


func _flatten(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO


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
	# **THE SHOCKWAVE IS THIS GAME'S ONLY AoE, now that the spin is gone.**
	#
	# A switch, a till, a chest and a breakable block used to be reachable by a
	# spin from standing; the modal moveset has no such verb, so the slam is the
	# one thing that can strike something it is not touching.
	#
	# Same reach and same strength as the loose-object half above, but with NO
	# distance falloff — see `Weight.strike_around` for why a force and a
	# threshold want opposite treatment there. Measured, at `slam_scatter_power`
	# 70:
	#
	#   a hop-stomp         force 0.10   momentum   7    reach  1.25 m
	#   a drop from 4 m     force 0.69   momentum  48    reach  3.45 m
	#   a drop from 12 m    force 2.00   momentum 140    reach 10.00 m
	#   the same, charging  force 4.20   momentum 294    reach 10.00 m
	Weight.strike_around(self, global_position, slam_scatter_power * force,
		_slam_reach(force))
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
	if previous == State.GRIND:
		# Dropped HERE and not only in `_leave_rail()`, because plenty of things
		# can knock us out of this state without going through it. Leave `_rail`
		# set through one of those and the next `_do_grind()` drives us along a
		# rail we are no longer anywhere near.
		_rail = null
		_grind_lock = maxf(_grind_lock, grind_relatch_delay)
	if previous == State.PUFFY:
		mass = _base_mass
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
		"carry": carried.name if carried != null else "-",
		"rail": ("%s at %.1fm, %.1f m/s" % [_rail.name, _rail_offset, _rail_speed]
			if _rail != null else "-"),
		"form": ("%s %.2fs" % [state_name(), maxf(_transform_left, 0.0)]
			if is_transformed() else "-"),
		"slam": "power %.2f" % slam_power(),
	}
