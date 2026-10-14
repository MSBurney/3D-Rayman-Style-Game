class_name GrindRail
extends Path3D

## A rail you can grind along, Sonic Adventure 2 style.
##
## ─── WHAT A Path3D IS ────────────────────────────────────────────────────────
##
## `Path3D` is a Godot node that holds a `Curve3D` — a list of points with a
## smooth line drawn through them. It draws nothing and does nothing on its own;
## it is purely a shape other things can ask questions about. That is exactly
## what a rail is, so this script adds no movement code at all. It just answers
## three questions for `Player._do_grind()`:
##
##   • how far along me is this point?   `closest_offset()`
##   • where am I at that distance?      `point_at()`
##   • which way do I run there?         `tangent_at()`
##
## "Offset" throughout means **metres travelled from the start of the rail**, so
## a rail 40 m long has offsets from 0.0 to 40.0. Godot calls this the "baked"
## offset because it measures along the flattened-out curve rather than along
## the control points.
##
## ─── THE TRAP THAT WILL GET YOU ──────────────────────────────────────────────
##
## **Curve points are in the rail's LOCAL space, not the world's.** Move the
## Path3D node and every point moves with it, but `curve.sample_baked()` keeps
## returning the same numbers. So every function here converts: `to_local()` on
## the way in, `to_global()` on the way out. Forget one and the player snaps to
## a rail floating somewhere near the level origin — which looks exactly like
## the curve data being wrong, and is not.
##
## Rails in this project are authored with the node sitting at the rail's first
## point and the curve points written relative to it, so you can drag the whole
## rail around in the editor without retyping anything.

## Joined so the player can find rails by walking the group. Same idea as
## `spinnable` and `throwable`: the rail holds no reference to the player and
## the player does not need to know this script exists.
const GROUP := &"grindable"

## How far above the curve the player's feet sit while grinding. The curve runs
## down the middle of the rail mesh, so without this the character stands with
## the rail through their ankles.
@export var ride_height: float = 0.5

## Multiplies how much this particular rail resists motion. Above 1 is a rusty
## rail you have to work at; below 1 is a fast one. Left at 1 the rail uses the
## player's own `grind_friction` unchanged.
##
## Here rather than on the player because it is a property of the RAIL — it lets
## one level have both a fast rail and a slow one without touching the character.
@export var friction_scale: float = 1.0


func _ready() -> void:
	add_to_group(GROUP)


## Total length of the rail in metres.
func length() -> float:
	if curve == null:
		return 0.0
	return curve.get_baked_length()


## How far along the rail the given WORLD point is, in metres from the start.
##
## Used when attaching: the player is somewhere near the rail, and this says
## where on it they landed.
func closest_offset(world_point: Vector3) -> float:
	if curve == null:
		return 0.0
	return curve.get_closest_offset(to_local(world_point))


## The WORLD position `offset` metres along the rail, with `ride_height` added
## so it is where the player's feet go rather than the middle of the mesh.
func point_at(offset: float) -> Vector3:
	if curve == null:
		return global_position
	var local := curve.sample_baked(clampf(offset, 0.0, length()))
	return to_global(local) + Vector3.UP * ride_height


## A unit vector pointing along the rail in the direction of INCREASING offset.
##
## Worked out by sampling two points a few centimetres apart and subtracting,
## rather than with `sample_baked_with_rotation()`. Both work, but the
## subtraction is obvious on sight and does not drag in the curve's up-vector
## and tilt settings, which are a separate source of confusion.
func tangent_at(offset: float) -> Vector3:
	var total := length()
	if total <= 0.0:
		return Vector3.FORWARD
	# Clamp the offset first, then SLIDE the sampling window so it always spans a
	# real distance inside the rail. Both of those matter.
	#
	# This is the fix for rails flinging you backwards off their far end.
	# _do_grind() overshoots the end by however far it travelled that frame —
	# 0.27 m at 16 m/s, so almost always — and then asked for the tangent at an
	# offset past the end. Clamping the two samples independently collapsed them
	# on to the SAME point, the subtraction came out zero, and the degenerate
	# branch below returned Vector3.FORWARD: a hardcoded direction with nothing
	# to do with this rail. Every rail in the rail yard runs towards +Z, so
	# leaving one launched you at -Z at full speed. It only happened on exits off
	# the END, which is exactly what made it look intermittent.
	var span := minf(0.05, total * 0.49)
	var at := clampf(offset, 0.0, total)
	var behind := clampf(at - span, 0.0, total - span * 2.0)
	var ahead := behind + span * 2.0
	var delta := point_at(ahead) - point_at(behind)
	if delta.length_squared() < 0.000001:
		# Only reachable now for a rail with two points in the same place. Still
		# worth a non-zero answer, because the caller normalises this and a zero
		# vector would come back as NaN and poison the player velocity.
		return Vector3.FORWARD
	return delta.normalized()


## How close the given WORLD point is to the rail, in metres. The player uses
## this to pick the nearest rail when several are in reach.
func distance_to_rail(world_point: Vector3) -> float:
	return world_point.distance_to(point_at(closest_offset(world_point)))
