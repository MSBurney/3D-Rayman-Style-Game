class_name PlayerVisuals
extends Node3D

## Everything about how the player *looks*, kept away from how the player moves.
##
## This node is the character's body: the meshes are its children, and it turns
## to face the direction of travel. The player controller never touches meshes
## directly, it just calls [method tick] once a frame and lets this decide what
## to show. That separation means you can replace these primitive spheres with a
## real animated model without opening player.gd at all.

## How fast the body swings round to face the way you are going, in radians/sec.
## Low values look heavy and sluggish; very high values snap and look robotic.
@export var turn_speed: float = 14.0
@onready var hold_point: Node3D = $HoldPoint


## Called every physics frame by the player.
##
## `facing` is a flat world-space direction. Note this node rotates so its +Z
## points along `facing`, which is why child meshes (the nose, the hold point)
## are placed on the +Z side.
func tick(delta: float, facing: Vector3) -> void:
	if facing.length_squared() > 0.01:
		# atan2(x, z) gives the Y rotation that points +Z along `facing`.
		# rotate_toward eases towards it instead of snapping, so turns have weight.
		var wanted := atan2(facing.x, facing.z)
		rotation.y = rotate_toward(rotation.y, wanted, turn_speed * delta)
