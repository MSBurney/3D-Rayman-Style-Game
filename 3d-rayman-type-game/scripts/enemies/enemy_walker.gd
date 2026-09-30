extends CharacterBody3D

## Ground patroller. Walks a line until it notices the player, then closes in.
## Killable by a stomp on the head or by a thrown object.

@export var walk_speed: float = 2.2
@export var chase_speed: float = 4.4
@export var acceleration: float = 14.0
## Half-length of the patrol line, along the enemy's own local X at spawn.
@export var patrol_distance: float = 4.0
@export var detect_range: float = 11.0
@export var lose_range: float = 16.0
@export var contact_damage: int = 1
@export var turn_speed: float = 9.0
@export var gravity: float = 24.0
## Dropped on death so combat feeds back into collection.
@export var lum_drop: PackedScene
@export var sfx_hit: AudioStream
@export var sfx_die: AudioStream

@export_group("Being thrown")
## Damage this does to whatever it lands on when thrown by the player.
@export var thrown_damage: int = 2
## How far that damage reaches from the landing point.
@export var thrown_radius: float = 3.0

var _origin: Vector3
var _patrol_axis: Vector3 = Vector3.RIGHT
var _direction: float = 1.0
var _player: Player = null
var _chasing: bool = false
var _dead: bool = false
## Set while the player.s tongue is dragging us in — the player owns our
## position during that, so our own movement code stands down.
var _tethered: bool = false
var _held: bool = false
var _thrown: bool = false
var _carrier: Player = null

@onready var health: HealthComponent = $Health
@onready var visual: Node3D = $Visual
@onready var hurtbox: Area3D = $Hurtbox
@onready var stompbox: Area3D = $Stompbox
@onready var _sfx: AudioStreamPlayer3D = $Sfx

func _ready() -> void:
	_origin = global_position
	_patrol_axis = global_transform.basis.x.normalized()
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	hurtbox.body_entered.connect(_on_hurtbox_entered)
	stompbox.body_entered.connect(_on_stomp)

func _physics_process(delta: float) -> void:
	# Being reeled in by the tongue: the player is moving us, so do nothing and
	# do not fight it.
	if _tethered:
		return

	# Held: ride the carrier's hold point.
	if _held:
		if _carrier != null and is_instance_valid(_carrier):
			var hold := _carrier.hold_point
			if hold != null:
				global_position = hold.global_position
		return

	# Thrown: fly until we hit something, then burst.
	if _thrown:
		velocity.y -= gravity * delta
		move_and_slide()
		if get_slide_collision_count() > 0 or is_on_floor() or is_on_wall():
			_land_thrown()
		return

	if _dead:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		velocity.y -= gravity * delta
		move_and_slide()
		return

	_update_awareness()

	var wanted := Vector3.ZERO
	if _chasing and _player != null:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.04:
			wanted = to_player.normalized() * chase_speed
	else:
		wanted = _patrol_axis * _direction * walk_speed
		# Turn round at the ends of the line, or when something blocks the way.
		var travelled := (global_position - _origin).dot(_patrol_axis)
		if absf(travelled) > patrol_distance and signf(travelled) == signf(_direction):
			_direction = -_direction
		elif is_on_wall():
			_direction = -_direction

	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(wanted, acceleration * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	move_and_slide()
	_face_travel(delta)

func _update_awareness() -> void:
	if _player == null:
		var found := get_tree().get_first_node_in_group(&"player")
		_player = found as Player
	if _player == null:
		return
	var distance := global_position.distance_to(_player.global_position)
	if _chasing:
		if distance > lose_range:
			_chasing = false
	elif distance < detect_range and _has_line_of_sight():
		_chasing = true

func _has_line_of_sight() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.8
	var to := _player.global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return space.intersect_ray(query).is_empty()

func _face_travel(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() < 0.05:
		return
	var wanted := atan2(flat.x, flat.z)
	visual.rotation.y = rotate_toward(visual.rotation.y, wanted, turn_speed * delta)

func _on_hurtbox_entered(body: Node3D) -> void:
	if _dead:
		return
	var player := body as Player
	if player == null:
		return
	# A falling player landing on top is a stomp, not a collision — let the
	# stompbox have it rather than trading damage.
	if player.descent_speed() < -1.0 and player.global_position.y > global_position.y + 0.6:
		return
	player.take_hit(contact_damage, global_position)

func _on_stomp(body: Node3D) -> void:
	if _dead:
		return
	var player := body as Player
	if player == null:
		return
	# descent_speed(), not velocity.y — see Player.descent_speed(). Also require
	# the player to actually be overhead, so brushing the box sideways is not a stomp.
	if player.descent_speed() > -1.0:
		return
	if player.global_position.y < global_position.y + 0.8:
		return
	player.bounce()
	health.damage(2)

func _on_damaged(_amount: int) -> void:
	_play(sfx_hit)
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3(1.25, 0.75, 1.25), 0.05)
	tween.tween_property(visual, "scale", Vector3.ONE, 0.12)

func _on_died() -> void:
	if _dead:
		return
	_dead = true
	hurtbox.set_deferred(&"monitoring", false)
	stompbox.set_deferred(&"monitoring", false)
	collision_layer = 0
	Events.enemy_died.emit(self)
	if lum_drop != null:
		var lum := lum_drop.instantiate() as Node3D
		get_parent().add_child(lum)
		lum.global_position = global_position + Vector3.UP * 0.8
	_play(sfx_die)
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3.ONE * 0.01, 0.22)
	tween.parallel().tween_property(visual, "position:y", 1.2, 0.22)
	# Outlive the death sound — freeing the node would cut it off mid-blip.
	await tween.finished
	if _sfx.playing:
		await _sfx.finished
	queue_free()


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	_sfx.stream = stream
	_sfx.play()


# ------------------------------------------------------- being grabbed & thrown
#
# These four methods are the same interface the throwable keg exposes, so the
# player's carry code treats a grabbed enemy exactly like any other object it
# picked up. Nothing in player_abilities.gd knows this is an enemy.

## The tongue has latched on and is dragging us in.
func tongue_pulled(_by: Player) -> void:
	if _dead:
		return
	_tethered = true
	_stop_hurting_the_player()


## We reached the player and are now being carried.
func pick_up(by: Player) -> void:
	if _dead:
		return
	_tethered = false
	_held = true
	_carrier = by
	velocity = Vector3.ZERO
	_stop_hurting_the_player()


## Launched. We fly until we hit something, then burst and damage the area.
func throw(impulse: Vector3) -> void:
	_held = false
	_tethered = false
	_carrier = null
	_thrown = true
	velocity = impulse
	# Collide with the world again so there is something to land on, but stay
	# off the player's layer so we do not shove them as we leave.
	collision_layer = 0
	collision_mask = 1


## Landing after a throw: hurt whatever is nearby, then die.
func _land_thrown() -> void:
	if _dead:
		return
	_thrown = false
	for node in get_tree().get_nodes_in_group(&"enemy"):
		var other := node as Node3D
		if other == null or other == self:
			continue
		if other.global_position.distance_to(global_position) > thrown_radius:
			continue
		var other_health := other.get_node_or_null(^"Health") as HealthComponent
		if other_health != null:
			other_health.damage(thrown_damage)
	health.damage(health.current)


## Hitboxes off. A grabbed enemy must not damage the player it is stuck to.
func _stop_hurting_the_player() -> void:
	hurtbox.set_deferred(&"monitoring", false)
	stompbox.set_deferred(&"monitoring", false)
	collision_layer = 0
	collision_mask = 0
