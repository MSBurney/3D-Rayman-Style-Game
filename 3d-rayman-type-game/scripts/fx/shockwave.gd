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
## The material the scene ships with. Never used as-is: each ring gets its own
## `duplicate()` of it, because each one fades its own alpha out. See play().
@onready var _base_material: StandardMaterial3D = \
	(_mesh.mesh as PrimitiveMesh).material as StandardMaterial3D


## Call straight after spawning. `radius` is the slam's real shockwave radius in
## metres, so the ring always matches what actually got hit.
func play(radius: float, combo: bool = false) -> void:
	position.y += ground_offset

	var tint := combo_colour if combo else colour

	# DUPLICATED from the scene's material — deliberately not
	# `StandardMaterial3D.new()`, and this line is a performance fix.
	#
	# It is the cause of a stutter that was reported as "the spin freezes the
	# game for a split second". Godot compiles one shader per distinct material
	# *configuration*, and frees that compiled shader the moment the last
	# material using it is destroyed. A ring deletes itself after `duration`, so
	# a material built here in code took the compiled shader down with it, and
	# the very next ring had to compile it all over again — about 28ms, which is
	# two dropped frames at 60fps, on every spin and every ground pound that had
	# a gap before it.
	#
	# Spamming the button HID it, because then two rings overlapped and one
	# always kept the shader alive. That is what made it look like an occasional
	# glitch rather than the rule, and why it survived several test runs.
	#
	# The scene's own copy is never freed, so the shader is compiled once and
	# stays compiled. A duplicate only changes `albedo_color`, and colours are
	# uniforms rather than part of what Godot keys a shader on, so every ring
	# goes on sharing that one shader.
	var material := _base_material.duplicate() as StandardMaterial3D
	material.albedo_color = tint
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


## Draws one ring, as near invisible as makes no difference, so its shader is
## compiled while the level loads instead of on the first spin of the game.
##
## Called by `Game` at startup — see `prewarm_scenes` there. Full size and real
## settings on purpose: warming with a tiny one does not do the same work, and
## so does not warm the same things. Measured at 2cm it changed nothing at all.
func prewarm() -> void:
	colour = Color(1.0, 1.0, 1.0, 0.02)
	combo_colour = colour
	play(1.0, false)
