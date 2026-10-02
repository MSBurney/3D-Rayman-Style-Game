class_name GrapplePoint
extends Node3D

## DEPRECATED: an anchor the player used to swing from.
##
## The grapple was replaced by the spin attack on 2026-10-02, so nothing reads
## these any more and they are decoration. The file is kept ONLY because Ian's
## scene_smilex.tscn instances six of them under a LevelGrappleHooks node, and
## deleting the scene would break his level. That needs a conversation with him
## rather than a unilateral delete.
##
## If you want them to do something again, the cheap option is to make them
## `spinnable` (see spin_switch.gd) so a spin can at least knock them.
##
## Original description follows.
##
## An anchor the player swings from.
##
## Anchors are bolted to the level, so hooking one moves the *player* — they are
## the pendulum half of the grapple. Enemies are the other way round: they get
## dragged to you. See `Player._do_swing` and `PlayerAbilities.tongue_grab`.
##
## Worth knowing when you place one: the rope is as long as the distance you
## hooked from, and nothing shortens it for you. So an anchor is only useful if
## there is room to swing *beneath* it — put them high, over the gap they are
## meant to cross, not level with the ledge you jump from.

const GROUP := "grapple_points"

@export var enabled: bool = true

## How high the player bounces off this anchor, as a multiple of the height
## their own `anchor_bounce_height_scale` gives. 1.0 is an ordinary anchor; raise
## it on one you want to act as a launcher for a long gap.
@export var bounce_scale: float = 1.0

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
