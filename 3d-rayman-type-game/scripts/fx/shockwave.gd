extends Node3D

## The expanding ring drawn where a slam lands.
##
## This is not decoration. The slam's reach scales with how far you fell, and
## without something to see, that scaling is invisible — a big drop and a small
## hop look identical. The ring is drawn at the *actual* radius that was used,
## so its size teaches the mechanic every time it fires.

## How long the ring takes to expand and fade out.
@export var duration: float = 0.38
## Size it starts at, as a fraction of its final radius. Not zero, or the first
## frame is a dot that reads as a pop rather than a wave going out.
@export var start_fraction: float = 0.18
@export var colour: Color = Color(1.0, 0.86, 0.45)
## Used instead when the hit was a combo slam, so the bigger one is obvious.
@export var combo_colour: Color = Color(1.0, 0.45, 0.25)
## Lifted slightly off the floor, or the ring z-fights with the ground it is
## drawn on and flickers.
@export var ground_offset: float = 0.06

@onready var _mesh: MeshInstance3D = $Mesh


## Call straight after spawning. `radius` is the slam's real shockwave radius in
## metres, so the ring always matches what actually got hit.
func play(radius: float, combo: bool = false) -> void:
	position.y += ground_offset

	var tint := combo_colour if combo else colour
	var material := StandardMaterial3D.new()
	# Unshaded so the ring reads the same whatever the lighting is doing.
	#
	# Deliberately NOT additive: the game's palette is bright pastel, and an
	# additive ring saturates straight to white on it, which throws away the
	# colour that distinguishes a combo hit from an ordinary one.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = material

	# The mesh is built at radius 1, so scaling the node by `radius` makes it
	# exactly as wide as the damage check that just ran.
	scale = Vector3.ONE * (radius * start_fraction)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * radius, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(material, "albedo_color:a", 0.0, duration) \
		.set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
