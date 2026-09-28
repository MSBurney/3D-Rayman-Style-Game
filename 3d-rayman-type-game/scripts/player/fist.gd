extends Area3D

## Rayman's thrown fist. Flies out, hits one thing, disappears.
## A charged shot is bigger, faster and hits harder.

@export var speed: float = 22.0
@export var charged_speed: float = 28.0
@export var lifetime: float = 0.55
@export var knockback: float = 6.0

var _direction: Vector3 = Vector3.FORWARD
var _damage: int = 1
var _speed: float = 22.0
var _life: float = 0.0
var _spent: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func launch(direction: Vector3, damage: int, charged: bool) -> void:
	_direction = direction.normalized()
	_damage = damage
	_speed = charged_speed if charged else speed
	_life = lifetime
	if charged:
		scale = Vector3.ONE * 1.6
	look_at(global_position + _direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_pop()
		return
	global_position += _direction * _speed * delta
	rotate_z(delta * 18.0)

func _on_body_entered(body: Node3D) -> void:
	if _spent:
		return
	# Static geometry just stops the fist.
	var health := body.get_node_or_null(^"Health") as HealthComponent
	if health != null:
		health.damage(_damage)
		if body is CharacterBody3D:
			var push := _direction * knockback
			(body as CharacterBody3D).velocity += push
	_pop()

func _pop() -> void:
	if _spent:
		return
	_spent = true
	set_physics_process(false)
	set_deferred(&"monitoring", false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.08)
	tween.tween_callback(queue_free)
