class_name GrappleTargeting
extends Node3D

## Works out which grapple point the player *means*, so aiming is a camera
## gesture rather than a precision task. Preference order: near the centre of
## the screen first, near the player second.

@export var max_range: float = 24.0
## How far off-centre a point may be, as a dot product against camera forward.
## Lower = more forgiving, but more chance of grabbing something behind a corner.
@export_range(-1.0, 1.0, 0.01) var min_dot: float = 0.15
@export var require_line_of_sight: bool = true
## Screen-centre weight. Raise it to favour where you're looking over what's close.
@export var centre_bias: float = 4.0
@export_flags_3d_physics var occluder_mask: int = 1

var current: GrapplePoint = null

## `exclude` should carry the player's own collider RID so line-of-sight checks
## don't trip over the player.
func pick(cam: Camera3D, origin: Vector3, exclude: Array[RID] = []) -> GrapplePoint:
	current = null
	if cam == null:
		return null

	var best := -INF
	var cam_forward := -cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state

	for node in get_tree().get_nodes_in_group(GrapplePoint.GROUP):
		var point := node as GrapplePoint
		if point == null or not point.enabled:
			continue

		var offset := point.global_position - origin
		var distance := offset.length()
		if distance > max_range or distance < 0.1:
			continue

		var alignment := cam_forward.dot(offset / distance)
		if alignment < min_dot:
			continue

		if require_line_of_sight:
			var query := PhysicsRayQueryParameters3D.create(
				origin, point.global_position, occluder_mask, exclude
			)
			if not space.intersect_ray(query).is_empty():
				continue

		var score := alignment * centre_bias - distance / max_range
		if score > best:
			best = score
			current = point

	return current
