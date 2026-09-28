class_name RopeLine
extends Node3D

## Draws the grapple rope as a single cylinder stretched between two points.
##
## Godot has no built-in "thick line in 3D", so the usual trick is a cylinder
## mesh: put it halfway between the two ends, aim it at one of them, and set its
## height to the distance. That is all this does.
##
## This node is `top_level` in the scene, meaning it ignores its parent's
## transform and works in world space. That matters — otherwise the player's own
## position would be applied twice and the rope would fly off.

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	visible = false


## Stretch the rope between two world-space points.
func draw_between(from: Vector3, to: Vector3) -> void:
	var offset := to - from
	var length := offset.length()
	if length < 0.05:
		visible = false
		return
	visible = true
	global_position = from + offset * 0.5

	# look_at() fails if the direction is parallel to the "up" vector you give
	# it, and a rope to an anchor directly overhead is exactly that case. So pick
	# a different up vector when the rope is near-vertical.
	var up := Vector3.UP if absf(offset.normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	look_at(to, up)

	# The cylinder is built along its own Y axis and pre-rotated onto Z in the
	# scene file, so only its length changes here.
	var cylinder := _mesh.mesh as CylinderMesh
	if cylinder != null:
		cylinder.height = length


func clear() -> void:
	visible = false
