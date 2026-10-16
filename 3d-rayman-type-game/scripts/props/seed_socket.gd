class_name SeedSocket
extends Node3D

## The hole at the bottom of a pit that turns a thrown `PlatformSeed` into a
## moving platform.
##
## ─── IT POLLS BY POSITION, IT DOES NOT USE body_entered ──────────────────────
##
## An `Area3D` with `body_entered` would miss the case that matters most. A seed
## being carried sits on collision layer 0 — that is how it avoids shoving its
## carrier around — so an enemy that wandered into the pit holding the seed
## would never trigger the area. It would simply stand there with the level in
## its hands, out of reach, and **nothing the player did could fix it.**
##
## So this asks every frame whether any seed is inside its volume, carried or
## not, by position. Which has a nice side effect: carrying the seed down there
## yourself works exactly as well as throwing it in.
##
## Walking a group by position is how everything in this project finds things
## anyway, for the usual reason — an area queried on the frame something entered
## it reports nothing.

## The platform this switches on. It does not have to be anywhere near the
## socket, and usually is not — the socket sits at the bottom of the pit while
## the platform waits at the lip.
##
## A `NodePath` resolved by hand rather than `@export var platform: Platform`,
## which looks tidier and does not work: a typed NODE export is stored as a
## NodePath and converted by the editor, so a path written into a `.tscn` by
## hand arrives as a NodePath that never becomes a node, and the socket silently
## has no platform. Cost an hour, and the symptom was far worse than null — see
## the refusal in _physics_process.
@export var platform_path: NodePath
## The accepting volume, centred on this node. Make it cover the WHOLE pit
## floor: "throw it in the pit" should mean anywhere in the pit, or the player
## is really being asked to hit a target they cannot see from above.
@export var size: Vector3 = Vector3(120, 6, 10)

signal filled(by: PlatformSeed)

var _used: bool = false
var _warned: bool = false

## Resolved once in _ready(). Not exported — see `platform_path`.
var platform: MovingPlatform = null


func _ready() -> void:
	platform = get_node_or_null(platform_path) as MovingPlatform


func _physics_process(_delta: float) -> void:
	# REFUSES to take the seed when there is no platform to switch on, and this
	# is the important half of the fix rather than a tidy-up.
	#
	# With the path broken, the first version consumed the seed and then did
	# nothing: the object the level depends on was gone, the platform never
	# appeared, and the level was unwinnable with no way to tell why. A socket
	# that cannot deliver must leave the seed on the floor, where the player can
	# at least still pick it up.
	if _used:
		return
	if platform == null:
		# Complained about from here rather than from _ready(), and once only.
		# _ready() is too early to judge: something may legitimately wire the
		# platform up straight after adding the socket to the tree, which is what
		# the smoke test does, and warning then is just noise.
		if not _warned:
			_warned = true
			push_warning("SeedSocket has no platform, so it will refuse the seed " +
				"rather than eat it. Check `platform_path`.")
		return
	var seed := _seed_inside()
	if seed == null:
		return
	_used = true
	seed.consume()
	if platform != null:
		platform.activate()
	filled.emit(seed)
	# Announced on the bus as well as locally, so a boss can learn it has lost
	# without either of them holding a reference to the other.
	Events.seed_delivered.emit(self, seed)


func used() -> bool:
	return _used


func _seed_inside() -> PlatformSeed:
	var half := size * 0.5
	for node in get_tree().get_nodes_in_group(PlatformSeed.STEALABLE):
		var seed := node as PlatformSeed
		if seed == null or seed.spent():
			continue
		var local := to_local(seed.global_position)
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return seed
	return null
