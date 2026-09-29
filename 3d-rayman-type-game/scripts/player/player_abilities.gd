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
## How close you must be to pick something up.
@export var grab_radius: float = 2.2
@export var throw_speed: float = 16.0
## Upward part of a throw, so objects arc instead of skidding along the floor.
@export var throw_lift: float = 4.0

## What we are currently holding, or null. Read by the HUD and the respawn code.
var carried: Node3D = null

@onready var _player: Player = get_parent() as Player


func handle_input(_delta: float) -> void:
	_handle_grab()


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
		var aim := _flat(_player.facing) * throw_speed + Vector3.UP * throw_lift
		thrown.call(&"throw", aim)


## Used when respawning, so a keg is never left stuck to a dead player.
func drop_everything() -> void:
	carried = null


func _flat(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO
