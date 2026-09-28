extends StaticBody3D

## Stationary shooter. Forces the player to keep moving or break line of sight,
## which is exactly the pressure that makes the movement toys worth using.

@export var bullet: PackedScene
@export var fire_interval: float = 1.4
@export var range_limit: float = 18.0
@export var aim_speed: float = 4.0
@export var muzzle_height: float = 1.1
## Fires a burst of this many shots, then waits a full interval.
@export var burst: int = 1
@export var burst_spacing: float = 0.16
@export var lum_drop: PackedScene

var _player: Player = null
var _cooldown: float = 0.0
var _dead: bool = false

@onready var health: HealthComponent = $Health
@onready var visual: Node3D = $Visual
@onready var muzzle: Node3D = $Visual/Muzzle

func _ready() -> void:
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	_cooldown = randf() * fire_interval

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Player
		if _player == null:
			return

	var to_player := _player.global_position + Vector3.UP * 0.6 - _muzzle_origin()
	var distance := to_player.length()
	var can_see := distance <= range_limit and _has_line_of_sight()

	if can_see:
		var wanted := atan2(to_player.x, to_player.z)
		visual.rotation.y = rotate_toward(visual.rotation.y, wanted, aim_speed * delta)

	_cooldown -= delta
	if can_see and _cooldown <= 0.0:
		_cooldown = fire_interval
		_fire_burst(to_player.normalized())

func _muzzle_origin() -> Vector3:
	return global_position + Vector3.UP * muzzle_height

func _has_line_of_sight() -> bool:
	var space := get_world_3d().direct_space_state
	var to := _player.global_position + Vector3.UP * 0.6
	var query := PhysicsRayQueryParameters3D.create(_muzzle_origin(), to, 1, [get_rid()])
	return space.intersect_ray(query).is_empty()

func _fire_burst(direction: Vector3) -> void:
	for i in burst:
		if i > 0:
			await get_tree().create_timer(burst_spacing).timeout
		if _dead or not is_inside_tree():
			return
		_fire_one(direction)

func _fire_one(direction: Vector3) -> void:
	if bullet == null:
		return
	var shot := bullet.instantiate()
	get_tree().current_scene.add_child(shot)
	var origin := muzzle.global_position if muzzle != null else _muzzle_origin()
	shot.global_position = origin
	if shot.has_method(&"launch"):
		shot.call(&"launch", direction)

func _on_damaged(_amount: int) -> void:
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3(1.2, 0.8, 1.2), 0.05)
	tween.tween_property(visual, "scale", Vector3.ONE, 0.12)

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	collision_layer = 0
	Events.enemy_died.emit(self)
	if lum_drop != null:
		var lum := lum_drop.instantiate() as Node3D
		get_parent().add_child(lum)
		lum.global_position = global_position + Vector3.UP * 1.0
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3.ONE * 0.01, 0.25)
	tween.tween_callback(queue_free)
