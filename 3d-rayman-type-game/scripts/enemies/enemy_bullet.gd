extends Area3D

## Slow, readable turret shot — slow enough to dodge or outrun on purpose.

@export var speed: float = 11.0
@export var damage: int = 1
@export var lifetime: float = 3.0

var _direction: Vector3 = Vector3.FORWARD
var _life: float = 0.0
var _spent: bool = false

func _ready() -> void:
	_life = lifetime
	body_entered.connect(_on_body_entered)

func launch(direction: Vector3) -> void:
	_direction = direction.normalized()

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_pop()
		return
	global_position += _direction * speed * delta

func _on_body_entered(body: Node3D) -> void:
	if _spent:
		return
	var player := body as Player
	if player != null:
		player.take_hit(damage, global_position)
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
