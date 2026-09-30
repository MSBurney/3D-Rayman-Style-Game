extends RigidBody3D

## A keg you can pick up and throw, Rayman 2 style. This is the other half of
## "grabbing": ledges are level geometry you grab, these are objects you grab.
## Thrown hard enough, it hurts whatever it lands on.

@export var damage: int = 2
## Below this impact speed it's just a crate bumping into things.
@export var min_impact_speed: float = 7.0
@export var break_on_impact: bool = true

@export_group("Being thrown")
## How far the burst at the end of a throw reaches.
@export var burst_radius: float = 2.6
## Ring drawn at the burst, the same scene the player's slam uses.
@export var burst_fx: PackedScene

var _carrier: Player = null
var _armed: bool = false
var _spent: bool = false
var _home: Transform3D
var _layer: int = 0
var _mask: int = 0
var _spin: Tween = null

## Drives us while we are in the air after a throw. See thrown_flight.gd.
@onready var flight: ThrownFlight = $Flight

func _ready() -> void:
	add_to_group(&"throwable")
	flight.exploded.connect(_on_flight_exploded)
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

## Launched. The keg becomes a homing, ricocheting projectile rather than a
## thrown physics object.
##
## Note it stays FROZEN for the whole flight. ThrownFlight sets our position
## every frame, and an unfrozen RigidBody3D would have the solver fighting it
## for control — the keg would sink, tumble and refuse to reflect cleanly. Only
## the direction of `impulse` is used; the flight owns the speed.
##
## (The old code unfroze here and set `linear_velocity` deferred, because a
## velocity assigned on the same frame a body unfreezes is discarded by the
## solver. That trap is gone with the velocity, but it is worth knowing: it
## still applies to `return_home`, and to any other body you unfreeze.)
func throw(impulse: Vector3) -> void:
	_carrier = null
	# Nothing to collide with while flying: the flight raycasts for surfaces
	# itself, and staying off every layer keeps us from shoving the thrower.
	collision_layer = 0
	collision_mask = 0
	_armed = false
	flight.launch(impulse)
	_spin_in_flight()


## Tumbles the keg as it flies. Pure decoration, but a projectile that holds one
## orientation for its whole arc looks switched off.
func _spin_in_flight() -> void:
	_spin = create_tween().set_loops()
	_spin.tween_property(self, "rotation", rotation + Vector3(TAU, TAU * 0.6, 0.0), 0.7)


## End of the flight: hurt everything in reach, then break apart.
func _on_flight_exploded(where: Vector3) -> void:
	if _spent:
		return
	global_position = where
	if _spin != null and _spin.is_valid():
		_spin.kill()
	_spawn_burst(where)

	# Groups rather than an Area3D, for the same reason grabbing a resting keg
	# walks the `throwable` group: an Area3D added and queried in the same frame
	# reports nothing, and a burst has to resolve immediately.
	#
	# `breakable` is the hook for props that are not enemies — put a Health child
	# on a crate and add it to that group and a thrown object will smash it.
	for group in [&"enemy", &"breakable"]:
		for node in get_tree().get_nodes_in_group(group):
			var other := node as Node3D
			if other == null:
				continue
			if other.global_position.distance_to(where) > burst_radius:
				continue
			var health := other.get_node_or_null(^"Health") as HealthComponent
			if health != null:
				health.damage(damage)

	if break_on_impact:
		_shatter()
	else:
		# Not a breakable one, so hand it back to the physics engine where it
		# landed and let it settle normally.
		collision_layer = _layer
		collision_mask = _mask
		set_deferred(&"freeze", false)


func _spawn_burst(where: Vector3) -> void:
	if burst_fx == null:
		return
	var ring := burst_fx.instantiate() as Node3D
	get_tree().current_scene.add_child(ring)
	ring.global_position = where
	if ring.has_method(&"play"):
		ring.call(&"play", burst_radius, flight.bounces_used > 0)

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
	# Might be called mid-flight, so stop the flight without letting it burst.
	flight.cancel()
	if _spin != null and _spin.is_valid():
		_spin.kill()
	freeze = false
	collision_layer = _layer
	collision_mask = _mask
	global_transform = _home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
