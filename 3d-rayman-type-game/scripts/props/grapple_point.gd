class_name GrapplePoint
extends Node3D

## An anchor the player can pull themselves to with the tongue.
##
## Anchors are fixed to the level, so the tongue moves the player instead of the
## anchor. Enemies are the other way round — see PlayerAbilities.tongue_grab.

const GROUP := "grapple_points"

@export var enabled: bool = true

@export var pull_speed: float = 26.0
## How close counts as "arrived".
@export var arrive_distance: float = 1.2
## Upward kick on arrival so a pull can flow into a jump or a second hook.
@export var release_boost: float = 6.0

@export_group("Look")
@export var spin_speed: float = 1.5
@export var bob_height: float = 0.12
@export var bob_speed: float = 1.8
## All anchors behave the same now, so there is one colour.
@export var colour: Color = Color(0.72, 0.45, 1.0)

var _visual: Node3D
var _base_y: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	add_to_group(GROUP)
	_visual = get_node_or_null(^"Visual")
	_base_y = position.y
	_t = randf() * TAU
	_apply_tint()


func _apply_tint() -> void:
	if _visual == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 1.8
	for child in _visual.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = material

func _process(delta: float) -> void:
	_t += delta * bob_speed
	position.y = _base_y + sin(_t) * bob_height
	if _visual != null:
		_visual.rotate_y(delta * spin_speed)
