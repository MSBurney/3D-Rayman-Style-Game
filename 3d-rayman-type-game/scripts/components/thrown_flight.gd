class_name ThrownFlight
extends Node

## Turns a thrown object into a homing, ricocheting projectile.
##
## Add it as a child of anything throwable, call [method launch] from that
## object's `throw()`, and react to [signal exploded]. Both the keg and a
## tongue-grabbed enemy use it, which is why it lives here rather than in
## either of their scripts.
##
## Modelled on the Yoshi egg in Super Mario 64 DS: the throw is not a lob you
## aim, it is a rocket that picks a victim, and missing is interesting because
## the thing comes back off the walls looking for another one.
##
## ### Why it moves itself
##
## While this is flying it sets the parent's `global_position` directly, and the
## parent's own movement code must stand down. Neither of Godot's usual options
## works here:
##
##   - `move_and_slide()` STOPS at a wall and slides along it. A ricochet needs
##     the opposite: reflect off it and keep the speed.
##   - a `RigidBody3D` is moved by the solver, which fights a constant-speed
##     steer. A homing force would trade speed for turn, and the whole point of
##     the throw is that it stays fast.
##
## So each frame is one raycast along where we are about to move, then either a
## position set or a reflection. Collision layers are irrelevant while flying:
## the ray is the only collision this thing has.

## A surface was hit and we bounced off it. `normal` points away from it.
signal bounced(where: Vector3, normal: Vector3)
## The flight is over. Whatever owns this decides what "explode" means - the keg
## shatters, a thrown enemy bursts and dies.
signal exploded(where: Vector3)

@export_group("Flight")
## Metres per second. Deliberately high: the throw should read as a rocket, not
## a toss. This is the biggest single dial on how throwing feels.
@export var speed: float = 34.0
## How many surfaces it ricochets off before exploding. Every bounce re-aims at
## the nearest enemy, so a big number turns one throw into a room clearer.
@export var max_bounces: int = 4
## Fraction of the speed kept through each ricochet. Under 1.0 the object
## visibly runs out of steam, which makes the last bounce read as an ending
## rather than the projectile being switched off.
@export var bounce_energy: float = 0.92
## Explodes on its own after this long, so a throw into open sky cannot leave a
## projectile flying around forever.
@export var lifetime: float = 5.0
## Roughly the object's own radius. Used to stand it off whatever it hits - at
## zero it visibly sinks into the wall before bouncing.
@export var radius: float = 0.45
## Pulls the throw down while it has nothing to chase, so a miss arcs instead of
## flying flat forever. A locked-on throw ignores this: a rocket flies straight.
@export var gravity: float = 14.0
## What counts as a surface to bounce off. Layer 1 is the world.
@export_flags_3d_physics var surface_mask: int = 1

@export_group("Homing")
@export var homing: bool = true
## Only enemies inside this are considered. Keep it generous - the point of the
## throw is that you should not have to aim well.
@export var home_range: float = 20.0
## How fast it can turn, in radians per second. Too low and it curves lazily
## past everything; too high and it snaps onto the target, which loses the sense
## of a thing having been flung. Around 4-8 reads as "seeking".
@export var home_turn_rate: float = 5.5
## How far off the throw direction a target may be, as a dot product. Slightly
## negative allows a target a little behind, which is what makes a hard curving
## throw possible. At -1.0 the projectile would happily turn round and fly back
## past the player, which reads as a bug rather than as a homing attack.
@export var home_min_dot: float = -0.2
## How much of the throw is aimed straight at the target the instant it leaves
## your hands: 0 flies where you aimed and curves in, 1 leaves pointing dead at
## it. The Yoshi egg goes straight at its victim, so this sits near the top —
## the throw should read as a shot, not as a guided curve.
@export_range(0.0, 1.0) var home_launch_snap: float = 0.85
## Inside this distance the turn rate is scaled up as the gap closes.
##
## This is not a polish setting, it is what makes homing work at all. A constant
## turn rate means a minimum turn radius of speed / turn rate — about 6 m at the
## defaults — and a projectile physically cannot close on anything inside that
## radius. It just ORBITS the target until it times out and bursts in mid-air
## several metres away, which looks like the homing is broken rather than like a
## near miss. Tightening the turn as the gap closes is what lands the hit.
@export var home_tighten_range: float = 9.0
## Near enough to the target to count as a hit.
@export var hit_distance: float = 1.1

var flying: bool = false
## What we are chasing. Null while nothing suitable is in range.
var target: Node3D = null
## Ricochets used so far, so the owner can scale its burst by them if it wants.
var bounces_used: int = 0

var _body: Node3D = null
var _exclude: Array[RID] = []
var _velocity: Vector3 = Vector3.ZERO
var _bounces_left: int = 0
var _time_left: float = 0.0


func _ready() -> void:
	_body = get_parent() as Node3D
	# The ray must not hit the body it is cast from. get_rid() is the physics
	# server's handle for that body, and the query takes a list of handles to
	# ignore.
	var collider := _body as CollisionObject3D
	if collider != null:
		_exclude = [collider.get_rid()]
	set_physics_process(false)


## Starts the flight. Only the DIRECTION of `aim` is used - its length is
## ignored, because [member speed] owns the pace. Callers can therefore keep
## passing the same impulse vector they always did.
func launch(aim: Vector3) -> void:
	if _body == null:
		return
	var direction := aim
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	_velocity = direction.normalized() * speed
	_bounces_left = max_bounces
	bounces_used = 0
	_time_left = lifetime
	flying = true
	_pick_target()
	if target != null and home_launch_snap > 0.0:
		_aim_at_target()
	set_physics_process(true)


## Swings the launch direction onto the target before the thing has travelled at
## all, by [member home_launch_snap] of the way. Steering alone cannot do this:
## a 90-degree turn takes a sixth of a second, by which time the throw has
## already gone ten metres the wrong way.
func _aim_at_target() -> void:
	var wanted := (target.global_position - _body.global_position).normalized()
	var aimed := _velocity.normalized().slerp(wanted, home_launch_snap)
	# slerp has no meaningful answer for two exactly opposite directions, and
	# returns something near zero. Throwing backwards at a target behind you is
	# rare but not impossible, so fall back to aiming straight at it.
	if aimed.length_squared() < 0.0001:
		aimed = wanted
	_velocity = aimed.normalized() * speed


## Stops the flight WITHOUT exploding, for when the object is removed some other
## way mid-air - the player respawning and everything being reset, say.
func cancel() -> void:
	flying = false
	target = null
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not flying or _body == null or not is_instance_valid(_body):
		return

	_time_left -= delta
	if _time_left <= 0.0:
		_finish()
		return

	if homing:
		_steer(delta)
	else:
		_velocity.y -= gravity * delta

	var from: Vector3 = _body.global_position

	# Arriving at the target is checked by distance, not by collision. A thrown
	# object drops its collision layers so it cannot shove the player on the way
	# out, which also means there is no contact for the engine to report.
	if target != null and is_instance_valid(target):
		if from.distance_to(target.global_position) <= hit_distance:
			_body.global_position = target.global_position
			_finish()
			return

	var step := _velocity * delta
	var travel := step.length()
	if travel <= 0.0:
		return

	# Cast our own radius further than we are about to move, so the bounce
	# happens at the surface rather than once we are already buried in it.
	var direction := step / travel
	var space := _body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		from, from + direction * (travel + radius), surface_mask, _exclude)
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		_body.global_position = from + step
		return

	_ricochet(hit["position"] as Vector3, hit["normal"] as Vector3)


## Reflects off a surface, then goes looking for something new to chase.
func _ricochet(where: Vector3, normal: Vector3) -> void:
	# Stand off the wall, or next frame's ray starts inside it and reflects
	# straight back in - the projectile sticks and buzzes against the surface.
	_body.global_position = where + normal * radius
	# Vector3.bounce() is a mirror reflection about the normal: the same maths as
	# light off a mirror, which is exactly what a ricochet is.
	_velocity = _velocity.bounce(normal) * bounce_energy
	_bounces_left -= 1
	bounces_used += 1
	bounced.emit(where, normal)

	if _bounces_left < 0:
		_finish()
		return

	# Re-aiming after every bounce is what makes ricochets worth having: the
	# throw that missed comes back off the wall for something else.
	_pick_target()


func _finish() -> void:
	if not flying:
		return
	var where: Vector3 = _body.global_position
	flying = false
	target = null
	set_physics_process(false)
	exploded.emit(where)


## Picks the nearest living enemy that is roughly the way we are already going.
## Skips ourselves, and anything already dead or dying.
func _pick_target() -> void:
	target = null
	if not homing:
		return

	var heading := _velocity.normalized()
	var here: Vector3 = _body.global_position
	var nearest := home_range

	for node in _body.get_tree().get_nodes_in_group(&"enemy"):
		var candidate := node as Node3D
		if candidate == null or candidate == _body or not is_instance_valid(candidate):
			continue
		var health := candidate.get_node_or_null(^"Health") as HealthComponent
		if health == null or health.current <= 0:
			continue
		var offset := candidate.global_position - here
		var distance := offset.length()
		if distance > nearest or distance < 0.01:
			continue
		if heading.dot(offset / distance) < home_min_dot:
			continue
		nearest = distance
		target = candidate


## Turns the velocity toward the target at a limited rate, keeping the SPEED the
## same. Rotating the direction rather than adding a steering force is what
## keeps a homing throw fast: a force would bleed speed into the turn.
func _steer(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		# Nothing to chase, so behave like a plain thrown object and fall.
		_velocity.y -= gravity * delta
		return

	var pace := _velocity.length()
	if pace < 0.01:
		return
	var offset := target.global_position - _body.global_position
	var gap := offset.length()
	if gap < 0.001:
		return

	# Turn harder the nearer it gets — see home_tighten_range for why this is
	# load-bearing and not a tweak.
	var allowance := home_turn_rate
	if gap < home_tighten_range:
		allowance *= home_tighten_range / maxf(gap, 0.6)

	var direction := _velocity / pace
	var wanted := offset / gap
	var angle := direction.angle_to(wanted)
	if angle > 0.0001:
		# Rotate about the axis perpendicular to both, by at most this frame's
		# allowance. That axis is degenerate when the two are exactly opposed,
		# hence the length check.
		var axis := direction.cross(wanted)
		if axis.length_squared() > 0.000001:
			direction = direction.rotated(axis.normalized(), minf(angle, allowance * delta))
	_velocity = direction * pace
