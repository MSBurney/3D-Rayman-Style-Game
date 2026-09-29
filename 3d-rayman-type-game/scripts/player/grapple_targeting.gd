class_name GrappleTargeting
extends Node3D

## Works out which thing the player *means* to grapple, so aiming is a camera
## gesture rather than a precision task.
##
## Two kinds of thing are targetable:
##   • anchors — [GrapplePoint] nodes placed in the level
##   • enemies — anything in the "enemy" group with a Health child
##
## Preference order: near the centre of the screen first, near the player second,
## and anchors beat enemies on a tie (see `anchor_bias`). That last rule is
## deliberate — this is a movement game first, so when you could plausibly mean
## either, getting flung onward beats stopping to fight.

@export var max_range: float = 24.0
## How far off-centre a target may be, as a dot product against camera forward.
## Lower = more forgiving, but more chance of grabbing something behind you.
@export_range(-1.0, 1.0, 0.01) var min_dot: float = 0.15
@export var require_line_of_sight: bool = true
## Screen-centre weight. Raise it to favour where you're looking over what's close.
@export var centre_bias: float = 4.0
## Added to an anchor's score so anchors win ties against enemies.
@export var anchor_bias: float = 0.6
@export var target_enemies: bool = true
@export_flags_3d_physics var occluder_mask: int = 1

## The chosen target, or null. May be a GrapplePoint or an enemy node.
var current: Node3D = null


## True when `node` is a level anchor rather than an enemy.
static func is_anchor(node: Node3D) -> bool:
	return node is GrapplePoint


## `exclude` should carry the player's own collider RID so line-of-sight checks
## don't trip over the player.
func pick(cam: Camera3D, origin: Vector3, exclude: Array[RID] = []) -> Node3D:
	current = null
	if cam == null:
		return null

	var best := -INF
	var cam_forward := -cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state

	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group(GrapplePoint.GROUP))
	if target_enemies:
		candidates.append_array(get_tree().get_nodes_in_group(&"enemy"))

	for node in candidates:
		var target := node as Node3D
		if target == null:
			continue

		var anchor := is_anchor(target)
		if anchor and not (target as GrapplePoint).enabled:
			continue
		if not anchor and not _enemy_is_alive(target):
			continue

		# Aim at an enemy's middle, not its feet, or tall ones read as "below" you.
		var point := target.global_position + (Vector3.ZERO if anchor else Vector3.UP * 0.8)
		var offset := point - origin
		var distance := offset.length()
		if distance > max_range or distance < 0.1:
			continue

		var alignment := cam_forward.dot(offset / distance)
		if alignment < min_dot:
			continue

		if require_line_of_sight:
			var query := PhysicsRayQueryParameters3D.create(origin, point, occluder_mask, exclude)
			if not space.intersect_ray(query).is_empty():
				continue

		var score := alignment * centre_bias - distance / max_range
		if anchor:
			score += anchor_bias
		if score > best:
			best = score
			current = target

	return current


## Dead enemies are mid-death-animation and must stop being targetable, or the
## player chains onto a corpse.
func _enemy_is_alive(enemy: Node3D) -> bool:
	var health := enemy.get_node_or_null(^"Health") as HealthComponent
	return health != null and health.is_alive()


## Where the player should aim for when diving at the current target.
func aim_point() -> Vector3:
	if current == null:
		return Vector3.ZERO
	return current.global_position + (Vector3.ZERO if is_anchor(current) else Vector3.UP * 0.8)
