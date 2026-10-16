class_name PlatformSeed
extends RigidBody3D

## The object a level's progression hangs on.
##
## Carry it with the spin-carry system, throw it into a pit, and the `SeedSocket`
## down there turns it into a moving platform you can ride somewhere you could
## not otherwise reach. An `ItemThief` can take it and carry it over its head,
## and then you have to kill that enemy to get it back.
##
## That is the whole point: an enemy holding this is holding the **level**
## hostage, which is a far bigger stake than an enemy holding some coins. Money
## you lose is a number. This is the way up.
##
## ─── WHICH IS EXACTLY WHY IT CAN NEVER BE LOST ───────────────────────────────
##
## The money thief had a rule — a thief is a container, not a sink. This needs a
## stronger one, because the failure is worse. If this object ends up somewhere
## nothing can reach, the level is not harder and the player is not poorer: it
## is **unfinishable**. So the seed rescues ITSELF, two ways, and neither is
## optional:
##
##   • `respawn_below_y` — fall off the world and it goes back where it started.
##   • **If its carrier stops existing, it drops itself.** An enemy killed,
##     thrown or freed while holding this would otherwise leave it frozen in
##     mid-air on collision layer 0 — invisible to every query, impossible to
##     pick up, and the level quietly dead. A carrier cannot be trusted to tidy
##     up after itself, so this does not depend on it.
##
## ─── IT IS NOT A KEG, DELIBERATELY ───────────────────────────────────────────
##
## `throwable.gd` looks like the obvious thing to reuse and it is wrong here: a
## thrown keg becomes a HOMING projectile that steers at the nearest enemy. You
## need this to land where you aimed, so it is thrown ballistically instead —
## one impulse and ordinary gravity.

## Joined so an ItemThief will come for it. Separate from `throwable` on purpose:
## `throwable` means "the player can carry this", `stealable` means "an enemy
## wants it". A keg is the first but not the second.
const STEALABLE := &"stealable"

## How hard the player throws it.
@export var throw_force: float = 16.0
## How high above an enemy's origin it rides. Over the head, because that IS the
## tell — you have to be able to see which enemy is carrying the level.
@export var carry_height: float = 1.9
## Falls past this and it goes straight back to where it started.
##
## The last line of defence against an unfinishable level. Set it below anything
## the level legitimately contains, including the bottom of the pit the seed is
## supposed to be thrown into — a socket that has not caught it yet must get the
## chance first.
@export var respawn_below_y: float = -40.0
## Small upward nudge when it is dropped, so it lands clear of whatever dropped
## it instead of inside its feet.
@export var drop_kick: float = 3.5

## Fired when a socket uses it up. The socket does the platform; this is for
## anything else that wants to know.
signal consumed

var _carrier: Node3D = null
var _spent: bool = false
var _home: Transform3D
var _home_set: bool = false
var _layer: int = 0
var _mask: int = 0


func _ready() -> void:
	add_to_group(&"throwable")
	add_to_group(STEALABLE)
	_layer = collision_layer
	_mask = collision_mask


func _physics_process(_delta: float) -> void:
	# `_home` is captured on the first physics frame rather than in _ready(),
	# because a node spawned from code is positioned a line AFTER it enters the
	# tree — so _ready() would record wherever it was before being placed, and
	# every rescue would send it to the level origin. Scene instances are fine,
	# which is what makes that trap so easy to miss.
	if not _home_set:
		_home = global_transform
		_home_set = true

	if _spent:
		return

	if global_position.y < respawn_below_y:
		return_home()
		return

	if _carrier != null and not is_instance_valid(_carrier):
		# Carrier freed while holding us. See the header: this is the check that
		# stops a killed snatcher taking the level with it.
		drop()
		return

	if _carrier == null:
		# Nobody is holding us, and yet we are still frozen and off every collision
		# layer — which is exactly the state `pick_up()` leaves us in. So a carrier
		# went away without going through `drop()`, and doing nothing would leave us
		# hanging in mid-air for ever, invisible to every query.
		#
		# Written as an INVARIANT rather than as a reaction to one known cause, which
		# is the whole point: there turned out to be more than one way to lose a
		# carrier, and "not held but still frozen" is wrong however it happened.
		if freeze or collision_layer == 0:
			drop()
		return

	global_position = _hold_position()


func _hold_position() -> Vector3:
	# The player has a hold point in front of its chest, set up in player.tscn.
	# An enemy has no such thing, so it carries this over its head.
	if _carrier is Player:
		var hold: Node3D = (_carrier as Player).hold_point
		if hold != null:
			return hold.global_position
	return _carrier.global_position + Vector3.UP * carry_height


func is_held() -> bool:
	return _carrier != null and is_instance_valid(_carrier)


func carrier() -> Node3D:
	return _carrier if is_held() else null


func spent() -> bool:
	return _spent


## Picked up by anybody — the player through the spin-carry system, or an enemy
## through ItemThief. Typed Node3D rather than Player for exactly that reason.
func pick_up(by: Node3D) -> void:
	if _spent or by == null:
		return
	_carrier = by
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	# Off every layer while carried, so it cannot shove its carrier around and a
	# socket cannot mistake a carried seed for one that was thrown in.
	collision_layer = 0
	collision_mask = 0


## Thrown by the player. `aim` is a direction; the force is ours.
func throw(aim: Vector3) -> void:
	if _spent:
		return
	var direction := aim.normalized()
	if direction == Vector3.ZERO:
		direction = Vector3.UP
	_carrier = null
	_unfreeze()
	# DEFERRED, and this is not a style choice: a RigidBody3D discards a velocity
	# set on the same frame it unfreezes, and the seed just flops at your feet.
	set_deferred(&"linear_velocity", direction * throw_force)


## Let go of without being thrown — what a dying snatcher does.
func drop() -> void:
	if _spent:
		return
	_carrier = null
	_unfreeze()
	set_deferred(&"linear_velocity", Vector3.UP * drop_kick)


func _unfreeze() -> void:
	freeze = false
	collision_layer = _layer
	collision_mask = _mask


## Used up by a socket.
##
## Whoever was holding it is told to let go, because a player left "carrying" a
## freed node cannot pick anything else up and has no way to find out why.
func consume() -> void:
	if _spent:
		return
	_spent = true
	if _carrier is Player:
		var player := _carrier as Player
		if player.abilities != null and player.abilities.carried == self:
			player.abilities.carried = null
	_carrier = null
	collision_layer = 0
	collision_mask = 0
	freeze = true
	consumed.emit()
	var tween := create_tween()
	# 0.01 rather than 0: a scale of exactly zero is a singular transform and
	# spams `Condition "det == 0" is true`.
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.2)
	tween.tween_callback(queue_free)


## Back to where it started. Used by the rescues above, and by the player
## respawning while carrying it.
func return_home() -> void:
	if _spent or not _home_set:
		return
	_carrier = null
	_unfreeze()
	global_transform = _home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
