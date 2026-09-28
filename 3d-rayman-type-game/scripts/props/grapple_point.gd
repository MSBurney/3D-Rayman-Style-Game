class_name GrapplePoint
extends Node3D

## A thing the player can hook. Rayman 2's purple lums were swing anchors;
## the cancelled Rayman 4 pitched a hook shot that yanked you to the target.
## Both are here, chosen per-instance, because they combine differently:
## SWING preserves momentum, PULL creates it.

const GROUP := "grapple_points"

enum Mode {
	SWING, ## Attach and pendulum. Release to fling with whatever speed you built.
	PULL,  ## Reel the player straight in, then pop them loose to chain onward.
}

@export var mode: Mode = Mode.SWING
@export var enabled: bool = true

@export_group("Swing")
## Rope is the shorter of this and the distance at the moment you hook on,
## so hooking from far out gives a long, fast arc.
@export var max_rope: float = 9.0

@export_group("Pull")
@export var pull_speed: float = 26.0
## How close counts as "arrived".
@export var arrive_distance: float = 1.2
## Upward kick on arrival so a pull can flow into a jump or a second hook.
@export var release_boost: float = 6.0

@export_group("Look")
@export var spin_speed: float = 1.5
@export var bob_height: float = 0.12
@export var bob_speed: float = 1.8
## Swing and pull points must be tellable apart at a glance, so one scene tints
## itself from `mode` rather than needing two.
@export var swing_colour: Color = Color(0.72, 0.45, 1.0)
@export var pull_colour: Color = Color(1.0, 0.72, 0.28)

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
	var colour := pull_colour if mode == Mode.PULL else swing_colour
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
