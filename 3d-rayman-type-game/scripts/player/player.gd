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
##   5. _do_<state>()     — one function per state. Want to change the helicopter?
##                          Go to _do_helicopter(). That is the whole trick.
##   6. helpers           — wall/ledge transitions, damage, plumbing
##
## ─── THE REST OF THE PLAYER ──────────────────────────────────────────────────
##
## Anything that is NOT movement lives in a child node with its own small script.
## Each one is a separate file you can read in a couple of minutes, and each has
## its own tuning values in the Inspector:
##
##   Abilities        player_abilities.gd  punching, grabbing and throwing
##   LedgeSensor      ledge_sensor.gd      "is there a ledge in front of me?"
##   GrappleTargeting grapple_targeting.gd "which anchor does the player mean?"
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
## into the others — a swing releases into a helicopter, a helicopter ends in a
## ledge grab, a wall run launches a grapple. If you add a state, make sure it
## has exits into the others rather than trapping the player inside it.
##
## The state machine is a plain enum plus a `match`, rather than Godot's node
## based approach, because these states share a lot of velocity maths and
## interrupt each other constantly. Keeping them in one file makes those
## hand-offs readable.

enum State {
	GROUND,
	AIR,
	HELICOPTER,
	WALL_RUN,
	WALL_SLIDE,
	LEDGE_HANG,
	GRAPPLE_PULL,
	SWING,
	HURT,
	DEAD,
}

signal state_changed(from: State, to: State)

@export_group("Run")
@export var max_speed: float = 7.5
@export var acceleration: float = 65.0
@export var deceleration: float = 75.0
## Used when the stick opposes current velocity. Higher = tighter turnarounds.
@export var turn_acceleration: float = 110.0
@export_range(0.0, 1.0) var air_control: float = 0.45
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

@export_group("Helicopter")
@export var helicopter_fall_speed: float = 2.2
## Air control while hovering is deliberately high — the helicopter is a
## positioning tool, not just a slow fall.
@export_range(0.0, 1.0) var helicopter_air_control: float = 0.9
@export_range(0.0, 1.0) var helicopter_speed_scale: float = 0.8
## 0 = unlimited, like Rayman 2. Give it a budget if you want gaps to bite.
@export var helicopter_max_time: float = 0.0
## When true you must release jump and press again to deploy, so it reads as a
## deliberate input instead of triggering on every held jump.
@export var helicopter_requires_repress: bool = true
@export var helicopter_spin_speed: float = 26.0

@export_group("Wall moves")
@export var wall_run_speed: float = 9.0
@export var wall_run_time: float = 1.1
## Gravity multiplier while wall running. Slightly above 0 so it always decays.
@export_range(0.0, 1.0) var wall_run_gravity_scale: float = 0.12
## Minimum horizontal speed needed to start a run rather than a slide.
@export var wall_run_min_speed: float = 4.5
@export var wall_slide_speed: float = 4.0
@export var wall_jump_up: float = 9.0
@export var wall_jump_push: float = 7.5
## Input is ignored briefly after a wall jump so it actually leaves the wall.
@export var wall_jump_lock: float = 0.16

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
@export var swing_stiffness: float = 22.0
## Tangential push from the stick — this is how you pump a swing higher.
@export var swing_input_force: float = 13.0
@export var swing_damping: float = 0.06
@export var swing_release_boost: float = 2.5
@export var swing_min_rope: float = 2.5
## Grace period after hooking on, before the grapple button can let go again.
## Without it the button press that attaches you is still "just pressed" when the
## swing/pull code runs later in the SAME frame, so you detach instantly.
@export var grapple_repress_delay: float = 0.2
## Hooking an anchor farther away than its max_rope reels you in at this speed
## instead of snapping the rope taut, which would fire the player like a slingshot.
@export var swing_reel_speed: float = 14.0

@export_group("Sounds")
## Placeholder blips, generated by tools/make_placeholder_sounds.gd. Drop real
## recordings onto these slots in the Inspector to replace them — no code change.
@export var sfx_jump: AudioStream
@export var sfx_land: AudioStream
@export var sfx_hurt: AudioStream
@export var sfx_grapple: AudioStream

@export_group("Combat")
## Punch and carry tuning lives on the PlayerAbilities child node instead.
@export var stomp_bounce: float = 11.0
@export var hurt_time: float = 0.45
@export var hurt_knockback: float = 7.0
@export var hurt_lift: float = 5.0

var state: State = State.AIR
## Horizontal facing of the body model, also used to aim ledge probes and punches.
var facing: Vector3 = Vector3.FORWARD
var wish_dir: Vector3 = Vector3.ZERO
var move_input: Vector2 = Vector2.ZERO

var _coyote: float = 0.0
var _jump_buffered: float = 0.0
var _jumping: bool = false
var _jump_released: bool = true
var _heli_time: float = 0.0
var _wall_time: float = 0.0
var _wall_normal: Vector3 = Vector3.ZERO
var _wall_dir: Vector3 = Vector3.ZERO
var _wall_lock: float = 0.0
var _ledge_lock: float = 0.0
var _grapple: GrapplePoint = null
var _rope: float = 0.0
var _rope_target: float = 0.0
var _grapple_lock: float = 0.0
var _hurt_left: float = 0.0
var _spawn: Transform3D
var _pre_move_vy: float = 0.0

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
		State.AIR: _do_air(delta)
		State.HELICOPTER: _do_helicopter(delta)
		State.WALL_RUN: _do_wall_run(delta)
		State.WALL_SLIDE: _do_wall_slide(delta)
		State.LEDGE_HANG: _do_ledge_hang(delta)
		State.GRAPPLE_PULL: _do_grapple_pull(delta)
		State.SWING: _do_swing(delta)
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
	_coyote = coyote_time if is_on_floor() else _coyote - delta
	_jump_buffered -= delta
	_wall_lock -= delta
	_ledge_lock -= delta
	_grapple_lock -= delta
	if state == State.HELICOPTER:
		_heli_time += delta


func _read_input() -> void:
	move_input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var basis := rig.flat_basis()
	wish_dir = (basis * Vector3(move_input.x, 0.0, move_input.y))
	if wish_dir.length_squared() > 1.0:
		wish_dir = wish_dir.normalized()

	if Input.is_action_just_pressed(&"jump"):
		_jump_buffered = jump_buffer
	if Input.is_action_just_released(&"jump"):
		_jump_released = true
		if _jumping and velocity.y > 0.0:
			velocity.y *= jump_cut
			_jumping = false

	if state != State.DEAD and state != State.HURT:
		_handle_grapple_input()
		abilities.handle_input(get_physics_process_delta_time())

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


func _apply_horizontal(delta: float, scale: float = 1.0, control: float = 1.0) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var wanted := wish_dir * max_speed * scale
	var rate := _accel_for(flat, wanted) * control * delta
	flat = flat.move_toward(wanted, rate)
	velocity.x = flat.x
	velocity.z = flat.z


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
func _try_jump() -> bool:
	if _jump_buffered <= 0.0:
		return false
	_jump_buffered = 0.0
	_coyote = 0.0
	_jumping = true
	_jump_released = false
	velocity.y = _jump_velocity()
	play_sfx(sfx_jump)
	return true


# ------------------------------------------------------------------------ states

func _do_ground(delta: float) -> void:
	_apply_horizontal(delta)
	velocity.y = minf(velocity.y, 0.0)
	_heli_time = 0.0

	if _try_jump():
		_set_state(State.AIR)
		return
	if not is_on_floor():
		_set_state(State.AIR)


func _do_air(delta: float) -> void:
	if _wall_lock <= 0.0:
		_apply_horizontal(delta, 1.0, air_control)
	_apply_gravity(delta)

	# Coyote jump: still allowed for a beat after walking off an edge.
	if _coyote > 0.0 and _try_jump():
		return

	if _wants_helicopter():
		_set_state(State.HELICOPTER)
		return
	if _ledge_lock <= 0.0 and velocity.y <= 0.5 and _find_ledge():
		_set_state(State.LEDGE_HANG)


func _wants_helicopter() -> bool:
	if not Input.is_action_pressed(&"jump"):
		return false
	if velocity.y > 0.5:
		return false
	if helicopter_requires_repress and not _jump_released:
		return false
	return true


func _do_helicopter(delta: float) -> void:
	_apply_horizontal(delta, helicopter_speed_scale, helicopter_air_control)
	# Ease down to hover speed rather than snapping, so deploying mid-fall reads
	# as the helicopter catching the player.
	if velocity.y < -helicopter_fall_speed:
		velocity.y = move_toward(velocity.y, -helicopter_fall_speed, 45.0 * delta)
	else:
		_apply_gravity(delta, 0.35)
		velocity.y = maxf(velocity.y, -helicopter_fall_speed)

	var expired := helicopter_max_time > 0.0 and _heli_time >= helicopter_max_time
	if expired or not Input.is_action_pressed(&"jump"):
		_set_state(State.AIR)
		return
	if is_on_floor():
		_set_state(State.GROUND)
		return
	if _ledge_lock <= 0.0 and _find_ledge():
		_set_state(State.LEDGE_HANG)


func _do_wall_run(delta: float) -> void:
	_wall_time -= delta
	# Ride the wall tangent at a fixed clip; the point is to cover ground.
	var along := _wall_dir * wall_run_speed
	velocity.x = along.x
	velocity.z = along.z
	_apply_gravity(delta, wall_run_gravity_scale)

	if _jump_buffered > 0.0:
		_wall_jump()
		return
	if _wall_time <= 0.0 or not is_on_wall() or is_on_floor():
		_set_state(State.AIR if not is_on_floor() else State.GROUND)


func _do_wall_slide(delta: float) -> void:
	_apply_horizontal(delta, 1.0, air_control)
	_apply_gravity(delta)
	velocity.y = maxf(velocity.y, -wall_slide_speed)

	if _jump_buffered > 0.0:
		_wall_jump()
		return
	if _wants_helicopter():
		_set_state(State.HELICOPTER)
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


func _do_grapple_pull(_delta: float) -> void:
	if _grapple == null:
		_set_state(State.AIR)
		return

	var offset := _grapple.global_position - global_position
	var distance := offset.length()
	if distance <= _grapple.arrive_distance:
		# Pop loose with upward kick, keeping some inbound speed so pulls chain.
		velocity = offset.normalized() * _grapple.pull_speed * 0.25
		velocity.y = maxf(velocity.y, _grapple.release_boost)
		_grapple = null
		_set_state(State.AIR)
		return

	velocity = offset / distance * _grapple.pull_speed
	# Bail out if we slam into geometry on the way.
	if is_on_wall() and absf(velocity.normalized().dot(get_wall_normal())) > 0.7:
		_grapple = null
		_set_state(State.AIR)
		return
	# Same one-frame trap as the swing: the press that started the pull is still
	# "just pressed" when this runs, so it must be locked out briefly.
	var cancel := Input.is_action_just_pressed(&"jump")
	if _grapple_lock <= 0.0 and Input.is_action_just_pressed(&"grapple"):
		cancel = true
	if cancel:
		_jump_buffered = 0.0
		velocity.y = maxf(velocity.y, _jump_velocity() * 0.8)
		_grapple = null
		_set_state(State.AIR)


func _do_swing(delta: float) -> void:
	if _grapple == null:
		_set_state(State.AIR)
		return

	var anchor := _grapple.global_position
	var to_anchor := anchor - global_position
	var distance := to_anchor.length()
	if distance < 0.05:
		_release_swing(false)
		return
	var inward := to_anchor / distance

	_rope = move_toward(_rope, _rope_target, swing_reel_speed * delta)

	_apply_gravity(delta)

	# Tangential input: pushing along the arc is what builds height.
	if wish_dir.length_squared() > 0.01:
		var tangent := wish_dir - inward * wish_dir.dot(inward)
		if tangent.length_squared() > 0.001:
			velocity += tangent.normalized() * swing_input_force * delta

	# Rope constraint: pull back toward the sphere, then kill outward velocity.
	var error := distance - _rope
	if error > 0.0:
		velocity += inward * error * swing_stiffness * delta
	var outward_speed := velocity.dot(-inward)
	if outward_speed > 0.0 and error > -0.05:
		velocity += inward * outward_speed

	velocity *= 1.0 - swing_damping * delta

	if Input.is_action_just_pressed(&"jump"):
		_release_swing(true)
		return
	# Press again to let go — deliberately not "let go of the button to let go".
	# Holding would mean an ordinary click attaches and detaches on consecutive
	# frames, which reads as the grapple simply not working.
	if _grapple_lock <= 0.0 and Input.is_action_just_pressed(&"grapple"):
		_release_swing(false)
		return
	if is_on_floor():
		_release_swing(false)


func _release_swing(boosted: bool) -> void:
	_grapple = null
	if boosted:
		velocity += Vector3.UP * swing_release_boost
		# Same reasoning as the ledge climb: most of this velocity is momentum the
		# player earned on the arc, so the jump-cut must not shave it off.
		_jumping = false
		_jump_released = false
		_jump_buffered = 0.0
	_set_state(State.GROUND if is_on_floor() else State.AIR)


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
		State.AIR, State.HELICOPTER:
			if is_on_floor():
				_set_state(State.GROUND)
				return
			if is_on_wall() and _wall_lock <= 0.0:
				_try_enter_wall()
		State.GROUND:
			if not is_on_floor() and velocity.y <= 0.0:
				pass # handled next frame via coyote time
		State.WALL_RUN:
			if is_on_wall():
				_wall_normal = get_wall_normal()


func _try_enter_wall() -> void:
	var normal := get_wall_normal()
	if absf(normal.y) > 0.4:
		return
	_wall_normal = _flatten(normal)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var side := _wall_normal.cross(Vector3.UP).normalized()
	var along := flat.dot(side)
	var pulling_away := wish_dir.dot(-_wall_normal) < -0.25

	# A wall run is earned with momentum, not by holding into the wall — when you
	# run along a wall your stick points along it, not at it. So speed along the
	# surface starts the run, and only actively steering away refuses it.
	if absf(along) >= wall_run_min_speed and not pulling_away:
		_wall_dir = side * signf(along)
		_wall_time = wall_run_time
		_set_state(State.WALL_RUN)
	elif wish_dir.dot(-_wall_normal) > 0.2 and velocity.y < 0.0:
		# Pressing into the wall with no speed is a cling, not a run.
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

func _handle_grapple_input() -> void:
	if state == State.GRAPPLE_PULL or state == State.SWING:
		return
	var target := targeting.pick(rig.camera, global_position + Vector3.UP * 1.0, [get_rid()])
	if target == null or not Input.is_action_just_pressed(&"grapple"):
		return
	_grapple = target
	_grapple_lock = grapple_repress_delay
	play_sfx(sfx_grapple)
	match target.mode:
		GrapplePoint.Mode.PULL:
			_set_state(State.GRAPPLE_PULL)
		_:
			# Start the rope at whatever length it actually is and let it reel in,
			# so hooking something far away is a smooth pull rather than a snap.
			var distance := global_position.distance_to(target.global_position)
			_rope = maxf(distance, swing_min_rope)
			_rope_target = clampf(distance, swing_min_rope, target.max_rope)
			_set_state(State.SWING)


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
	abilities.drop_everything()
	_hurt_left = 0.0
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

	visual.tick(delta, facing, state == State.HELICOPTER)


## Shows the rope while hooked on, hides it otherwise.
func _update_rope() -> void:
	var anchored := _grapple != null and (state == State.SWING or state == State.GRAPPLE_PULL)
	if anchored:
		rope_line.draw_between(global_position + Vector3.UP * 1.0, _grapple.global_position)
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
		State.HELICOPTER:
			_heli_time = 0.0
			_jumping = false
		State.LEDGE_HANG:
			_snap_to_ledge()
		State.SWING:
			_jumping = false
		State.DEAD:
			velocity = Vector3.ZERO
		_:
			pass


func _exit_state(which: State) -> void:
	match which:
		State.WALL_RUN:
			_wall_time = 0.0
		State.LEDGE_HANG:
			_ledge_lock = maxf(_ledge_lock, ledge_cooldown)
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
		"heli": _heli_time,
		"carry": abilities.carried.name if abilities.carried != null else "-",
	}
