extends RigidBody3D

## A keg you can pick up and throw, Rayman 2 style. This is the other half of
## "grabbing": ledges are level geometry you grab, these are objects you grab.
## Thrown hard enough, it hurts whatever it lands on.

@export var damage: int = 2
## Below this impact speed it's just a crate bumping into things.
@export var min_impact_speed: float = 7.0
@export var break_on_impact: bool = true

var _carrier: Player = null
var _armed: bool = false
var _spent: bool = false
var _home: Transform3D
var _layer: int = 0
var _mask: int = 0

func _ready() -> void:
	add_to_group(&"throwable")
	_home = global_transform
	_layer = collision_layer
	_mask = collision_mask
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

func _physics_process(_delta: float) -> void:
	if _carrier == null:
		return
	var hold := _carrier.hold_point
	if hold == null:
		return
	global_position = hold.global_position
	rotation = _carrier.visual.rotation

func pick_up(by: Player) -> void:
	_carrier = by
	_armed = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	# Stop colliding with the world while held, or the carrier shoves it around.
	collision_layer = 0
	collision_mask = 0

func throw(impulse: Vector3) -> void:
	_carrier = null
	collision_layer = _layer
	collision_mask = _mask
	freeze = false
	_armed = true
	# A velocity set on the same frame the body unfreezes is discarded by the
	# solver, which turns a throw into a limp drop. Apply it once it's awake.
	_apply_throw.call_deferred(impulse)


func _apply_throw(impulse: Vector3) -> void:
	if _spent:
		return
	linear_velocity = impulse
	angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0), randf_range(-6.0, 6.0))

func _on_body_entered(body: Node) -> void:
	if not _armed or _spent:
		return
	if linear_velocity.length() < min_impact_speed:
		return
	var node := body as Node3D
	if node == null:
		return
	var health := node.get_node_or_null(^"Health") as HealthComponent
	if health != null:
		health.damage(damage)
		_armed = false
		if break_on_impact:
			_shatter()

func _shatter() -> void:
	if _spent:
		return
	_spent = true
	set_deferred(&"freeze", true)
	collision_layer = 0
	collision_mask = 0
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.15)
	tween.tween_callback(queue_free)

## Used when the player respawns while carrying something.
func return_home() -> void:
	_carrier = null
	_armed = false
	freeze = false
	collision_layer = _layer
	collision_mask = _mask
	global_transform = _home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
