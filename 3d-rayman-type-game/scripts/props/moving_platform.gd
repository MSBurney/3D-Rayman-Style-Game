class_name MovingPlatform
extends AnimatableBody3D

## A platform that slides between two points and carries you with it.
##
## ─── WHY AnimatableBody3D, AND NOT StaticBody3D ──────────────────────────────
##
## `AnimatableBody3D` is a static body that expects to be moved, and with
## `sync_to_physics` on — set in the scene, not here — Godot works out how far it
## travelled this tick and hands that motion to whatever is standing on it.
##
## Move a plain `StaticBody3D` instead and a `CharacterBody3D` riding it gets
## left behind: the platform slides out from under the player, who looks like
## they are skating on the spot. That is the one thing to know about moving
## platforms in Godot, and it is invisible until something stands on one.
##
## It is moved in `_physics_process` by assigning `global_position`, and
## deliberately NOT with a Tween. A tween runs on the render clock, so it would
## be setting positions between physics ticks, and `sync_to_physics` would read
## a different distance every frame — which is what makes a ridden platform
## jitter.

## Starts off, so a socket can switch it on. Set true in the Inspector for an
## ordinary always-running platform.
@export var active: bool = false
## Hidden and non-colliding until activated, so it reads as having been created
## rather than as having always been there waiting.
@export var hide_until_active: bool = true
## Where it travels to, as an offset from wherever it starts.
@export var travel: Vector3 = Vector3(0, 11.4, 0)
@export var speed: float = 3.2
## How long it waits at each end. Without a pause, stepping on or off is a
## frame-perfect act at the exact moment it reverses.
@export var hold_time: float = 1.2
## How long the appear animation takes.
@export var appear_time: float = 0.35

signal activated

var _from: Vector3
var _from_set: bool = false
## Position along `travel`, from 0 at the start to 1 at the far end.
var _t: float = 0.0
var _dir: float = 1.0
var _wait: float = 0.0
var _layer: int = 0

@onready var visual: Node3D = $Visual
@onready var shape: CollisionShape3D = $Shape


func _ready() -> void:
	_layer = collision_layer
	if hide_until_active and not active:
		visible = false
		collision_layer = 0
		shape.disabled = true


func _physics_process(delta: float) -> void:
	# Captured on the first physics frame, not in _ready(): a platform spawned
	# from code is positioned a line after it enters the tree, and a start point
	# read too early sends the whole travel back to the level origin.
	if not _from_set:
		_from = global_position
		_from_set = true
	if not active:
		return
	if _wait > 0.0:
		_wait -= delta
		constant_linear_velocity = Vector3.ZERO
		return

	var span := travel.length()
	if span < 0.001:
		return
	_t += _dir * (speed / span) * delta
	if _t >= 1.0:
		_t = 1.0
		_dir = -1.0
		_wait = hold_time
	elif _t <= 0.0:
		_t = 0.0
		_dir = 1.0
		_wait = hold_time
	global_position = _from + travel * _t

	# What actually carries a rider, and the reason `sync_to_physics` is off.
	#
	# A CharacterBody3D standing on something asks that body how fast its surface
	# is moving, and for a static-style body the answer comes from here. Leave it
	# at zero and a VERTICAL platform still works by luck, because the player's
	# floor snapping keeps catching up with it — but one that travels sideways
	# slides out from under them and they skate on the spot.
	constant_linear_velocity = travel.normalized() * speed * _dir


## Switched on. Called by a SeedSocket, or by anything else that wants to.
func activate() -> void:
	if active:
		return
	active = true
	visible = true
	# Deferred because this is very likely being called from inside a physics
	# query — the socket checks for a seed during _physics_process, and changing
	# a body's shapes mid-query is exactly what Godot warns about.
	collision_layer = _layer
	shape.set_deferred(&"disabled", false)

	# The VISUAL is scaled, never the body. Scaling a physics body scales its
	# collision shape with it, so a pop-in animation would briefly give the
	# platform a shape a tenth of its size — and anything standing on it would
	# fall through.
	visual.scale = Vector3.ONE * 0.01
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3.ONE, appear_time) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	activated.emit()
