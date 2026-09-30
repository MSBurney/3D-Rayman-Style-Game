class_name PlayerAbilities
extends Node

## The things the player does that are not locomotion.
##
## Right now that is only picking up and throwing objects. These live here rather
## than in player.gd because they do not touch velocity or the state machine at
## all — you can grab while running, falling or swinging. Keeping them separate
## means player.gd stays about *movement*.
##
## The player calls [method handle_input] once a frame from its own input step,
## rather than this node reading input on its own, so the order things happen in
## stays visible in one place.

@export_group("Carry")
## How close you must be to pick something up by hand.
@export var grab_radius: float = 2.2
## How far above horizontal a throw sets off, as rise over forward run. Only the
## DIRECTION is decided here — the speed belongs to the thrown object's own
## `Flight` node (see thrown_flight.gd), because a thrown thing rockets at a
## fixed pace and steers itself rather than being lobbed at a chosen strength.
@export var throw_rise: float = 0.22

@export_group("Tongue")
## How fast a grabbed enemy is dragged toward the player.
@export var tongue_reel_speed: float = 22.0
## How close it has to get before it counts as caught.
@export var tongue_catch_distance: float = 1.2
## Give up if it takes longer than this — the target may be stuck on geometry.
@export var tongue_timeout: float = 2.0
## Damage dealt instead, when a target is too fixed to drag (a turret).
@export var tongue_lash_damage: int = 1

## What we are currently holding, or null. Read by the HUD and the respawn code.
var carried: Node3D = null
## The enemy currently being reeled in, or null. It is not "carried" yet.
var tethered: Node3D = null

var _tongue_time: float = 0.0

@onready var _player: Player = get_parent() as Player


func handle_input(delta: float) -> void:
	_tick_tongue(delta)
	_handle_grab()


## Starts dragging an enemy toward the player. Targets that cannot be picked up
## are lashed for damage instead — a turret is bolted down, so the tongue hurts
## it rather than moving it, which keeps such enemies killable.
func tongue_grab(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method(&"pick_up"):
		var health := target.get_node_or_null(^"Health") as HealthComponent
		if health != null:
			health.damage(tongue_lash_damage)
		return
	tethered = target
	_tongue_time = 0.0
	if target.has_method(&"tongue_pulled"):
		target.call(&"tongue_pulled", _player)


## Drags the tethered enemy in. Moving the *target* rather than the player is
## the whole point of this version of the grapple.
func _tick_tongue(delta: float) -> void:
	if tethered == null:
		return
	if not is_instance_valid(tethered) or carried != null:
		tethered = null
		return

	_tongue_time += delta
	var hold := _player.hold_point
	var goal := hold.global_position if hold != null else _player.global_position
	var offset := goal - tethered.global_position
	var distance := offset.length()

	if distance <= tongue_catch_distance:
		var caught := tethered
		tethered = null
		carried = caught
		caught.call(&"pick_up", _player)
		return

	# Give up rather than dragging something forever if it is wedged on scenery.
	if _tongue_time > tongue_timeout:
		tethered = null
		return

	tethered.global_position += offset / distance * tongue_reel_speed * delta


func _handle_grab() -> void:
	if not Input.is_action_just_pressed(&"grab"):
		return
	if carried != null:
		throw_carried()
		return

	# Nearest throwable within reach wins. This walks the "throwable" group by
	# distance rather than using an Area3D, because a keg that has come to rest
	# is a *sleeping* RigidBody3D, and sleeping bodies are unreliable in area
	# overlap queries — you would walk up to an untouched keg and find it
	# stubbornly ungrabbable.
	var best: Node3D = null
	var best_distance := grab_radius * grab_radius
	var origin := _player.global_position + Vector3.UP * 0.8
	for node in _player.get_tree().get_nodes_in_group(&"throwable"):
		var body := node as Node3D
		if body == null:
			continue
		var d := origin.distance_squared_to(body.global_position)
		if d < best_distance:
			best_distance = d
			best = body

	if best != null and best.has_method(&"pick_up"):
		carried = best
		best.call(&"pick_up", _player)


func throw_carried() -> void:
	if carried == null:
		return
	var thrown := carried
	carried = null
	if thrown.has_method(&"throw"):
		var aim := _flat(_player.facing) + Vector3.UP * throw_rise
		thrown.call(&"throw", aim)


## Used when respawning, so a keg is never left stuck to a dead player.
func drop_everything() -> void:
	carried = null


func _flat(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO
