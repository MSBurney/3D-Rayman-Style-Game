class_name SeeSaw
extends AnimatableBody3D

## A plank on a pivot. **The heavier side wins** — universal weight rule 3.
##
## It is also the slam's fourth job: the verb table lists the slam as the
## "see-saw launcher", so whacking one end down flings whatever is on the other
## end into the air. That is the whole reason this prop is interesting rather
## than decorative — it converts your mass into someone else's altitude.
##
## ─── WHAT IT DOES NOT CONTAIN, WHICH IS THE BEST THING ABOUT IT ──────────────
##
## **No code anywhere in the player.** A tilted plank is a SLOPE, and slopes are
## already the whole momentum engine — `_slope_pull()` projects gravity onto
## whatever surface you are standing on and does not care that this one moves.
## So a see-saw automatically accelerates you down its low side, lets you charge
## up it, and bleeds your speed if you go the wrong way, all for free.
##
## That is what the doc means by one physics layer: the interesting behaviour is
## the *combination* of two systems that were each built for something else.
##
## ─── AUTHORED, NOT SIMULATED ─────────────────────────────────────────────────
##
## The tilt moves toward its target at a constant rate rather than being driven
## by torque with inertia and overshoot. A wobbling see-saw is more fun for
## about a minute and then it is a puzzle element you cannot predict, and the
## doc is explicit that *"unpredictable physics kills mastery"* and that puzzle
## states are authored. Same instinct as the hero being kinematic.
##
## An empty see-saw returns to LEVEL for the same reason. A real one rests on
## whichever side it last fell to, which looks better and means a player
## returning to a puzzle finds it in a state they have to undo first.

## Size of the plank, in metres — long axis along Z, pivoting about X. The scene
## is authored at 3 x 0.4 x 9 and this rescales the shape, the mesh, the end
## pads and the weight sensor together, so one scene covers every see-saw.
@export var size: Vector3 = Vector3(3.0, 0.4, 9.0)

@export_group("Tilt")
## How far each end can drop. Keep this modest: a crate resting on the plank
## stays put through static friction, and past about 40 degrees it starts to
## slide off and the counterweight puzzle quietly stops working.
@export var max_tilt_degrees: float = 14.0
## Degrees per second. Slow enough to read as a heavy plank swinging, fast
## enough that it is not a loading screen.
@export var tilt_speed: float = 34.0
## How decisive the imbalance has to be before it moves at all, in mass-metres
## (see `WeightSensor.moment`). Without a deadzone a see-saw with near-equal
## loads hunts back and forth for ever and reads as broken.
@export var balance_deadzone: float = 3.0

@export_group("The slam launcher")
## Minimum slam force that counts, on the scale `Events.slam_landed` carries.
## Above zero so that hopping on the spot is not a catapult.
@export var slam_power_needed: float = 0.2
## Metres per second of launch for each unit of slam force, at the very end of
## the plank. Scaled down toward the pivot, because leverage is the point.
##
## Worth knowing when tuning: slam force is NOT 0..1. It is drop plus delivered
## speed, multiplied by the player's `impact_force_scalar`, so at the current
## settings it reaches about 4. Read this number as "per unit", not "at most".
@export var launch_per_force: float = 6.0
## Safety rail, not a design cap — it exists so a mistuned `launch_per_force`
## cannot fire a crate out of the level. Raise it freely.
@export var launch_speed_max: float = 30.0
## How close to the pivot counts as "the middle". Slamming the middle of a
## see-saw should do nothing, and without this it does something arbitrary
## depending on which side of the exact centreline you landed.
@export var pivot_deadzone: float = 0.8

@export_group("Heavy arrivals")
## Anything that LANDS on an end faster than this launches the other end — not
## just the player's slam.
##
## **This is rule 5 (everything obeys the same physics), and without it the
## see-saw was broken in the most literal way.** The player's slam arrives
## through `Events.slam_landed`, and nothing else in the game emits that signal,
## so the plank answered to exactly one body in the world. A dropped crate, a
## thrown keg or a stomping enemy all have a mass and a downward speed, which is
## all this needs.
@export var arrival_speed: float = 6.0
## Seconds before another arrival counts, so one landing does not fire on three
## consecutive frames while the body is still settling onto the plank.
@export var arrival_cooldown: float = 0.4
## How much of an arriving body's momentum reaches the far end.
##
## **An arrival launches by transferring MOMENTUM, not through the
## `launch_per_force` curve the slam uses, and that is not a stylistic choice.**
## Going through the force curve lets a heavy crate launch a second crate faster
## than it arrived — so two crates on opposite ends play tennis with each other
## at increasing speed, for ever. Transferring momentum cannot amplify, so the
## loop damps out by construction rather than by a cap catching it.
@export var arrival_transfer: float = 0.8

## Fired when the plank throws something, so a level can react without the
## see-saw knowing what a level is.
signal launched(body: Node3D, speed: float)

## Current tilt in degrees. Positive means the +Z end is down.
var tilt: float = 0.0

var _arrival_left: float = 0.0

@onready var shape: CollisionShape3D = $Shape
@onready var visual: Node3D = $Visual
@onready var plank: MeshInstance3D = $Visual/Plank
@onready var pad_north: MeshInstance3D = $Visual/PadNorth
@onready var pad_south: MeshInstance3D = $Visual/PadSouth
## What is standing on us, and how heavy it is. See `weight_sensor.gd`.
@onready var sensor: WeightSensor = $Weight


func _ready() -> void:
	_apply_size()
	Events.slam_landed.connect(_on_slam_landed)


## Rescales everything from `size`.
##
## The shape and the meshes are DUPLICATED first. A sub-resource declared in a
## scene is shared by every instance of that scene, so resizing one in place
## resizes every other see-saw in the level at the same time.
func _apply_size() -> void:
	var box := (shape.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size = size
	shape.shape = box

	var mesh := (plank.mesh as BoxMesh).duplicate() as BoxMesh
	mesh.size = size
	plank.mesh = mesh

	# The end pads are the legibility: the two ends have to be tellable apart at
	# a glance, or a tilting plank just looks like a bug in the floor. They get a
	# mesh each rather than sharing one, because a shared mesh means a shared
	# material and the two ends would come out the same colour.
	var pad_size := Vector3(size.x, size.y * 0.5, size.z * 0.16)
	var north := (pad_north.mesh as BoxMesh).duplicate() as BoxMesh
	north.size = pad_size
	pad_north.mesh = north
	var south := (pad_south.mesh as BoxMesh).duplicate() as BoxMesh
	south.size = pad_size
	pad_south.mesh = south

	var end := size.z * 0.5 - pad_size.z * 0.5
	pad_north.position = Vector3(0.0, size.y * 0.5, end)
	pad_south.position = Vector3(0.0, size.y * 0.5, -end)

	# The sensor watches a box the size of the plank, standing on top of it.
	# Its BOTTOM is flush with the plank's surface rather than a hair above it:
	# a CharacterBody3D's origin is at its feet, so a player standing here sits
	# exactly on that plane and a box starting any higher would miss them.
	sensor.size = Vector3(size.x, 2.4, size.z)
	sensor.offset = Vector3(0.0, size.y * 0.5 + 1.2, 0.0)


func _physics_process(delta: float) -> void:
	sensor.scan()
	_arrival_left -= delta
	_check_arrivals()

	var wanted := 0.0
	if absf(sensor.moment) > balance_deadzone:
		wanted = max_tilt_degrees * signf(sensor.moment)

	var before := tilt
	tilt = move_toward(tilt, wanted, tilt_speed * delta)
	# Positive rotation about X drops the +Z end, which is what a positive
	# `moment` means. (Verified against the greybox ramp, whose +15 degrees about
	# X descends towards +Z — see tests/greybox_probe.gd.)
	rotation.x = deg_to_rad(tilt)

	# WHAT ACTUALLY CARRIES A RIDER, and the reason `sync_to_physics` is off in
	# the scene — see the note in `moving_platform.tscn` for the full trap.
	#
	# A CharacterBody3D standing on a static-style body asks that body how fast
	# its surface is moving. For a rotating plank the answer is angular, not
	# linear: Godot combines this with where the rider stands, so someone out at
	# the end is carried further than someone near the pivot, which is correct
	# and would be fiddly to work out by hand.
	var rate := deg_to_rad(tilt - before) / maxf(delta, 0.0001)
	constant_angular_velocity = global_basis.x.normalized() * rate


## A slam landed somewhere in the level. If it was on one of our ends, that end
## goes straight down and the far end throws its passenger.
func _on_slam_landed(at: Vector3, force: float) -> void:
	if force < slam_power_needed:
		return

	var local := to_local(at)
	var half := size * 0.5
	if absf(local.x) > half.x or absf(local.z) > half.z or absf(local.y) > 2.0:
		return
	# Slamming the middle of a see-saw should do nothing, rather than something
	# arbitrary decided by which side of the exact centreline you came down on.
	if absf(local.z) < pivot_deadzone:
		return

	var hit_side := signf(local.z)
	# THE TILT IS DELIBERATELY NOT TOUCHED HERE, and the first version got this
	# wrong in an instructive way. It snapped the plank to full tilt on the
	# slammed side, as a whack — which swings the far end UP through whatever is
	# standing on it. The crate ended up a metre BELOW the plank in one frame,
	# outside the weight sensor's box, so it was not launched at all, and had it
	# been it would have been fired into the plank's own underside.
	#
	# Any rotation that lifts an end sweeps through its passenger unless the
	# passenger is carried, and carrying only works when the motion is gradual.
	# So the slam contributes the IMPULSE and nothing else; the angle stays a
	# pure function of what is standing where, which is also what keeps the
	# prop's state predictable. The visible pay-off is the crate leaving, and
	# the plank then tips toward you on its own because the crate is gone.
	_launch_from_force(-hit_side, force)


## Did something heavy just LAND on one of our ends?
func _check_arrivals() -> void:
	if _arrival_left > 0.0:
		return
	for body in sensor.riders:
		var rigid := body as RigidBody3D
		if rigid == null:
			continue
		var falling := -rigid.linear_velocity.y
		if falling < arrival_speed:
			continue
		var local := to_local(rigid.global_position)
		if absf(local.z) < pivot_deadzone:
			continue
		_arrival_left = arrival_cooldown
		_launch_from_momentum(-signf(local.z), rigid.mass * falling * arrival_transfer)
		return


## The player's slam: a force on the scale `Events.slam_landed` carries, run
## through the `launch_per_force` curve. A slam has no momentum left to transfer
## by the time it lands — it has just delivered all of it into the floor — so the
## force number is the only honest proxy for how hard it hit.
func _launch_from_force(side: float, force: float) -> void:
	sensor.scan()
	for body in sensor.riders:
		var arm := _arm_of(body, side)
		if arm <= 0.0:
			continue
		_apply_launch(body, minf(launch_per_force * force * arm, launch_speed_max))


## A falling body: its momentum, shared out to whatever is on the far end. See
## `arrival_transfer` for why this one cannot go through the force curve.
func _launch_from_momentum(side: float, momentum: float) -> void:
	sensor.scan()
	for body in sensor.riders:
		var arm := _arm_of(body, side)
		if arm <= 0.0:
			continue
		var their_mass := sensor.mass_of(body)
		var speed := momentum / maxf(their_mass, 0.01) * arm
		_apply_launch(body, minf(speed, launch_speed_max))


## How much leverage `body` has, if it is on `side` at all — 0.0 if it is not.
##
## Leverage once more: the far end of a plank throws harder than a point next to
## the pivot does.
func _arm_of(body: Node3D, side: float) -> float:
	var local := to_local(body.global_position)
	if signf(local.z) != side:
		return 0.0
	return clampf(absf(local.z) / maxf(size.z * 0.5, 0.01), 0.0, 1.0)


func _apply_launch(body: Node3D, speed: float) -> void:
	if speed <= 0.0:
		return
	if body is RigidBody3D:
		var rigid := body as RigidBody3D
		# Woken first: a sleeping body ignores an impulse, and a crate that has
		# been sitting on a see-saw is always asleep.
		rigid.sleeping = false
		rigid.apply_central_impulse(Vector3.UP * speed * rigid.mass)
	elif body is CharacterBody3D:
		var character := body as CharacterBody3D
		# maxf, never an assignment: if they were already going up faster than
		# this, the plank has nothing to add and must not take any away.
		character.velocity.y = maxf(character.velocity.y, speed)
	else:
		return
	launched.emit(body, speed)


## For tests and for a HUD readout: which way it is leaning, -1, 0 or 1.
func leaning() -> int:
	if absf(tilt) < 0.5:
		return 0
	return int(signf(tilt))
