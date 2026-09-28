class_name LedgeSensor
extends Node3D

## Answers one question: "is there a ledge I could hang from, and where is it?"
##
## It only ever *looks*. It never moves the player — the player decides what to
## do with the answer. Keeping sensing separate from acting is why this is its
## own file, and it matches [GrappleTargeting], which does the same job for
## grapple points.
##
## How the probe works: two rays, like feeling for a windowsill in the dark.
##   1. A ray forward from chest height. Nothing hit → no wall. Something tilted
##      hit → that's a slope, not a wall, so reject it.
##   2. A ray straight DOWN, starting above and slightly beyond that wall hit.
##      If it lands on something flat, that flat thing is the top lip.
## Finally the lip has to sit inside the grabbable height band (see below).
##
## Godot note: this asks the physics world one-off questions through
## `direct_space_state` rather than using RayCast3D nodes. A RayCast3D is a node
## you place in the scene and read each frame, which suits a fixed direction;
## these rays point wherever the player happens to be facing, so a direct query
## is simpler than re-aiming a node every frame.

## How far forward the chest ray reaches.
@export var reach: float = 0.75
## Height above the feet that the forward ray is cast from.
@export var chest_height: float = 1.25
## The band, measured from the feet, in which a lip counts as grabbable.
##
## This matters more than it looks. A standing jump clears about 2.35 m, so any
## lip lower than roughly 3.3 m gets landed on instead — you never hang from it.
## Ledge grabbing is for lips ABOVE your jump, caught on the way back down.
@export var grab_min: float = 1.0
@export var grab_max: float = 2.3

## Set by the last successful [method find]. Only meaningful when it returned true.
var lip: Vector3 = Vector3.ZERO
## Outward-facing normal of the wall under the lip.
var normal: Vector3 = Vector3.ZERO

@onready var _body: CharacterBody3D = get_parent() as CharacterBody3D


## Looks for a ledge ahead of `origin` in the direction `forward`.
## Returns true and fills in [member lip] / [member normal] when it finds one.
func find(origin: Vector3, forward: Vector3) -> bool:
	var result := probe(origin, forward)
	if result.is_empty():
		return false
	normal = result["normal"]
	lip = result["lip"]
	return true


## Would there still be a ledge to hold if the player stood at `where`?
## Used while shimmying, so you can't slide off the end of a lip into thin air.
func still_valid_at(where: Vector3) -> bool:
	return not probe(where, -normal).is_empty()


## The raw probe. Returns {"lip": Vector3, "normal": Vector3}, or {} for "none".
func probe(origin: Vector3, forward: Vector3) -> Dictionary:
	var dir := _flatten(forward)
	if dir.length_squared() < 0.01 or _body == null:
		return {}
	var space := get_world_3d().direct_space_state
	# Don't let the rays hit the player's own collider.
	var exclude: Array[RID] = [_body.get_rid()]
	var mask := _body.collision_mask

	var chest := origin + Vector3.UP * chest_height
	var wall_query := PhysicsRayQueryParameters3D.create(
		chest, chest + dir * reach, mask, exclude
	)
	var wall: Dictionary = space.intersect_ray(wall_query)
	if wall.is_empty():
		return {}
	var wall_normal: Vector3 = wall["normal"]
	if absf(wall_normal.y) > 0.35:
		return {} # too tilted to be a wall

	var lip_from: Vector3 = wall["position"] + dir * 0.18 + Vector3.UP * 1.1
	var lip_query := PhysicsRayQueryParameters3D.create(
		lip_from, lip_from - Vector3.UP * 1.4, mask, exclude
	)
	var lip_hit: Dictionary = space.intersect_ray(lip_query)
	if lip_hit.is_empty():
		return {}
	var lip_normal: Vector3 = lip_hit["normal"]
	if lip_normal.y < 0.7:
		return {} # the top is sloped, not standable

	var lip_point: Vector3 = lip_hit["position"]
	var height := lip_point.y - origin.y
	if height < grab_min or height > grab_max:
		return {}
	return {"lip": lip_point, "normal": _flatten(wall_normal)}


## Flattens a direction onto the horizontal plane and normalises it.
func _flatten(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO
