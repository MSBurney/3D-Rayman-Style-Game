class_name CrumblingFloor
extends StaticBody3D

## A floor slab that only a heavy impact breaks.
##
## This is weight as a KEY rather than a hammer: a route that behaves one way
## for a character with mass and another way for anything else. Walking across
## is fine. Landing on it from a height is not, and a slam anywhere near it
## certainly is not.
##
## It is also weight as a LIABILITY, which matters more than it sounds. If being
## heavy is only ever an advantage it stops being a constraint and quietly turns
## into a stat. A floor that your own mass destroys under you is the cheapest way
## to make the trade real.
##
## ### How it finds out about a slam
##
## It listens to `Events.slam_landed(at, force)`, which the player has emitted
## since the slam was built and which nothing used until now. That is the
## intended shape for this: the slab never holds a reference to the player, and
## the player has no idea slabs exist. Anything else that wants to react to a
## slam — a pressure plate, a shaking camera, a scoring rule — connects to the
## same signal and needs no changes anywhere else.

enum State {
	WHOLE,
	## Cracked and shaking, but still solid. A warning, not yet a hole.
	CRACKING,
	GONE,
}

@export_group("Shape")
## Size of the plank, in metres. The scene is authored at 5 x 1 x 5 and this
## rescales it, so one scene covers every plank in a tree fort instead of needing
## a variant per size.
@export var size: Vector3 = Vector3(5, 1, 5)

@export_group("What breaks it")
## Standing on it at all starts the collapse, which is the classic crumbling
## platform. Leave it off and only a real DROP breaks it — see break_fall_speed.
##
## `warn_time` is what makes this fair: the plank cracks and shakes first, so a
## quick player can still cross. At zero it is a trap rather than a mechanic.
@export var break_on_stand: bool = false
## A landing counts as heavy if the player was falling faster than this.
##
## For scale: a standing jump is 2.35 m and lands at about 7.6 m/s, so the
## default deliberately lets an ordinary jump through. You have to come down
## from somewhere to break it.
@export var break_fall_speed: float = 9.0
## A slam landing within this distance breaks it regardless of where it fell
## from. The slam is the heavy verb, so it always wins.
@export var slam_radius: float = 4.0
## ...as long as the slam was worth at least this much, on the same 0..1 scale as
## `Player.slam_power()`: a hop is about 0.08, a drop from the tower is 1.0.
## Above zero so that hopping on the spot does not clear a room of floors.
@export var slam_power_needed: float = 0.12

@export_group("Timing")
## Warning time between cracking and actually giving way, so a fast player can
## still get across. At zero the slab reads as a trap rather than a mechanic.
@export var warn_time: float = 0.35
## How far it rattles while cracking. Cosmetic, but a floor that vanishes with
## no tell at all feels unfair however fair it technically is.
@export var shake_strength: float = 0.07
## Seconds until it comes back. Negative means it is gone for good.
@export var reset_delay: float = 2.5

var state: State = State.WHOLE

var _home: Vector3
var _timer: float = 0.0
## Visual scale that matches `size`. Remembered because the break and restore
## tweens drive this property and would otherwise snap the plank back to the
## authored 5x5.
var _visual_scale: Vector3 = Vector3.ONE

@onready var shape: CollisionShape3D = $Shape
@onready var visual: Node3D = $Visual
## Detects the player touching down on us. An Area3D rather than a collision
## check because we need to know about the contact without blocking anything.
@onready var landing: Area3D = $Landing


func _ready() -> void:
	_home = position
	_apply_size()
	landing.body_entered.connect(_on_landing)
	Events.slam_landed.connect(_on_slam_landed)


## Rescales the plank to `size`.
##
## The shape and the mesh are DUPLICATED first. Sub-resources declared in a scene
## are shared by every instance of it, so resizing them in place would resize
## every other crumbling floor in the level at the same time — one of the easier
## ways to lose an afternoon in Godot.
func _apply_size() -> void:
	var box := (shape.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size = size
	shape.shape = box

	var sensor := landing.get_node(^"Shape") as CollisionShape3D
	var sensor_box := (sensor.shape as BoxShape3D).duplicate() as BoxShape3D
	# A touch narrower than the plank and a little taller, so standing anywhere on
	# it registers but brushing past the edge in mid-air does not.
	sensor_box.size = Vector3(size.x * 0.96, size.y + 0.4, size.z * 0.96)
	sensor.shape = sensor_box
	sensor.position.y = size.y * 0.4

	# One scale on the Visual covers the slab mesh and its crack decorations
	# together. Remembered because _break() and _restore() tween this property and
	# would otherwise snap the plank back to the authored 5x5.
	_visual_scale = size / Vector3(5.0, 1.0, 5.0)
	visual.scale = _visual_scale


func _physics_process(delta: float) -> void:
	match state:
		State.WHOLE:
			pass
		State.CRACKING:
			_timer -= delta
			# Rattle in place. Only x and z, so the surface stays where the
			# player's feet expect it to be.
			position.x = _home.x + randf_range(-shake_strength, shake_strength)
			position.z = _home.z + randf_range(-shake_strength, shake_strength)
			if _timer <= 0.0:
				_give_way()
		State.GONE:
			if reset_delay < 0.0:
				return
			_timer -= delta
			if _timer <= 0.0:
				_restore()


## The player touched down on us. Whether that matters depends on how fast they
## were falling.
func _on_landing(body: Node3D) -> void:
	var player := body as Player
	if player == null:
		return
	# Just being on it is enough, if this plank is the fragile kind.
	if break_on_stand:
		_crack()
		return
	# descent_speed(), NOT player.velocity.y. Landing on something zeroes the
	# vertical velocity during the same physics step that an Area3D reports the
	# overlap, so reading velocity.y here sees a stationary player and no landing
	# is ever heavy enough. descent_speed() exists to give the speed from before
	# the collision was resolved — its comment in player.gd explains the trap.
	if player.descent_speed() > -break_fall_speed:
		return
	_crack()


func _on_slam_landed(at: Vector3, force: float) -> void:
	if force < slam_power_needed:
		return
	# Measured from our centre, which is fine for a slab about as wide as
	# `slam_radius`. Make one much bigger than that and its far end will shrug
	# off a slam that visibly landed on it.
	if global_position.distance_to(at) > slam_radius:
		return
	_crack()


func _crack() -> void:
	if state != State.WHOLE:
		return
	state = State.CRACKING
	_timer = warn_time


func _give_way() -> void:
	state = State.GONE
	_timer = reset_delay
	position = _home
	# Deferred: disabling a collision shape from inside the physics step is not
	# allowed, and Godot will complain about flushing queries.
	shape.set_deferred(&"disabled", true)
	landing.set_deferred(&"monitoring", false)

	var tween := create_tween()
	# ONE * 0.01, never ZERO. A scale of exactly zero is a singular transform and
	# spams `Condition "det == 0" is true` every frame it is tweened through.
	tween.tween_property(visual, "scale", _visual_scale * 0.01, 0.18)


func _restore() -> void:
	state = State.WHOLE
	position = _home
	shape.set_deferred(&"disabled", false)
	landing.set_deferred(&"monitoring", true)
	var tween := create_tween()
	tween.tween_property(visual, "scale", _visual_scale, 0.18)
