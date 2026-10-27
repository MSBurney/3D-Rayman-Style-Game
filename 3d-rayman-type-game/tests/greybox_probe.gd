extends Node

## THROWAWAY probe for the Milestone 1 greybox. Delete once it settles.
##
## Two jobs. The first is the usual one: a hand-rotated ramp has come out wrong
## every single time this project has built one, and it is invisible until you
## raycast it, so the slope is checked against a formula rather than by eye.
##
## The second is the one that matters: **measure what the slope is actually
## worth.** The doc's whole pass/fail test is "charging down the slope into the
## wall", and that is only a test if the slope is the difference between
## bouncing off the wall and going through it. So this charges on the flat,
## charges down the slope, and prints both against the wall's `break_speed`.

const MAIN := preload("res://scenes/greybox_main.tscn")
## The ramp's top surface, by construction: 15 degrees, passing through y = 4
## at z = -15. Everything about the ramp is checked against this one line.
const RAMP_TAN := 0.26795

var failures: int = 0
var level: Node3D = null
var player: HeavyPlayer = null


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	level = main.get_node("GreyboxRoom")
	player = main.get_node("Player") as HeavyPlayer

	print("\n==== GREYBOX PROBE ====")
	_surfaces()
	_authority()
	await _charges()
	print("---- %d wrong ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _note(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("    %-32s %s  %s" % [label, detail, "" if ok else "*** WRONG ***"])


func _compare(label: String, got: float, expected: float, tolerance: float) -> void:
	_note(label, absf(got - expected) <= tolerance,
		"expected %7.2f  got %7.2f" % [expected, got])


## Drops a short ray and returns the height it found, or NAN.
func _height_at(x: float, z: float, expected: float) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var from := Vector3(x, expected + 2.0, z)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0))
	if hit.is_empty():
		return NAN
	return hit["position"].y


func _surfaces() -> void:
	print("  -- the ground, and the gap")
	_compare("south ground", _height_at(30, -20, 0.0), 0.0, 0.1)
	_compare("north ground", _height_at(30, 40, 0.0), 0.0, 0.1)
	_note("the gap is actually a gap", is_nan(_height_at(0, 17, 0.0)),
		"nothing underfoot at z=17")
	_compare("slam tower top", _height_at(22, -4, 14.0), 14.0, 0.1)
	_compare("ramp landing", _height_at(-6, -30, 8.0), 8.0, 0.1)

	print("  -- the slope, against y = 4 - (z + 15) * tan(15)")
	# Typed explicitly: `z` comes out of an untyped Array as a Variant, so `:=`
	# cannot infer the result and the script refuses to load at all — which
	# presents as the probe hanging rather than as a typo.
	# z=-28 sits under the RampLanding rather than the ramp, so sample at -26.
	var samples: Array[float] = [-26.0, -22.0, -15.0, -8.0, -2.0]
	for z in samples:
		var expected: float = 4.0 - (z + 15.0) * RAMP_TAN
		_compare("ramp top at z=%.0f" % z, _height_at(0.0, z, expected), expected, 0.2)

	# And the direction it faces. A ramp tilted the wrong way still passes a
	# height check at its midpoint, so the normal is checked separately: this
	# one descends towards +Z, so its normal leans the same way.
	var space := get_viewport().world_3d.direct_space_state
	var from := Vector3(0, 6, -15)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0))
	if hit.is_empty():
		_note("ramp normal", false, "no surface to read")
	else:
		var normal: Vector3 = hit["normal"]
		_note("ramp leans downhill towards +Z", normal.z > 0.2 and normal.y > 0.9,
			"normal (%.2f, %.2f, %.2f)" % [normal.x, normal.y, normal.z])


func _authority() -> void:
	print("  -- the steering authority curve")
	player.velocity = Vector3.ZERO
	_compare("authority at a standstill", player.authority(), 1.0, 0.01)
	player.velocity = Vector3(0, 0, player.walk_speed)
	_compare("authority at walk speed", player.authority(), 1.0, 0.01)
	player.velocity = Vector3(0, 0, player.authority_zero_speed)
	_compare("authority at top speed", player.authority(), player.min_authority, 0.02)
	player.velocity = Vector3.ZERO


## Charges, and reports what each one is worth. This is the measurement the
## whole room exists for.
func _charges() -> void:
	print("  -- what a charge is worth")
	var wall := level.get_node_or_null("BreakWall") as BreakableBlock
	var needed: float = wall.break_speed if wall != null else 0.0

	var flat_top := await _charge_from(Vector3(0, 0.15, -52), 260, 100.0)
	_note("charge on the flat", flat_top > player.walk_speed * 2.0,
		"tops out at %.1f m/s" % flat_top)

	# Down the slope. Measured up to z = 2, which is just short of the wall at
	# z = 4, so the number is the speed it ARRIVES with rather than a peak
	# reached somewhere irrelevant.
	var slope_top := await _charge_from(Vector3(0, 8.15, -29), 260, 2.0)
	_note("charge down the slope", slope_top > flat_top + 1.0,
		"arrives at %.1f m/s (flat was %.1f)" % [slope_top, flat_top])

	# THE PASS/FAIL SHAPE. The wall has to be out of reach on the flat and in
	# reach down the slope, or the slope is decoration and the room is not
	# asking the doc's question.
	_note("the slope is the difference at the wall",
		flat_top < needed and slope_top >= needed,
		"need %.1f — flat %.1f (short), slope %.1f" % [needed, flat_top, slope_top])

	# And it actually opens.
	await _place(Vector3(0, 8.15, -29))
	Input.action_press("attack")
	var opened := false
	for i in 320:
		await get_tree().physics_frame
		if wall != null and wall.broken_open:
			opened = true
			break
	Input.action_release("attack")
	_note("the charge breaks the wall", opened, "broken_open=%s" % opened)
	await get_tree().physics_frame

	print("  -- the gap, which only a charge-jump crosses")
	var walk_jump := await _jump_distance(false)
	var charge_jump := await _jump_distance(true)
	_note("a walking jump cannot cross 14 m", walk_jump < 14.0,
		"%.1f m" % walk_jump)
	_note("a charge-jump can", charge_jump > 14.0,
		"%.1f m" % charge_jump)


## Charges from `at` towards +Z and returns the top speed reached before z
## passes `stop_z`.
func _charge_from(at: Vector3, frames: int, stop_z: float) -> float:
	await _place(at)
	# Pressed ONCE and held. Pressing every frame never produces a fresh
	# `just_pressed`, so the wind-up would never start — and holding is also
	# what the charge needs, since letting go stops it adding power.
	Input.action_press("attack")
	var best := 0.0
	for i in frames:
		await get_tree().physics_frame
		best = maxf(best, player.flat_speed())
		if player.global_position.z >= stop_z:
			break
	Input.action_release("attack")
	await get_tree().physics_frame
	return best


## How far a jump carries, from a standstill or out of a full charge.
func _jump_distance(charged: bool) -> float:
	await _place(Vector3(40, 0.15, -52))
	if charged:
		Input.action_press("attack")
		for i in 150:
			await get_tree().physics_frame
			if player.flat_speed() >= player.charge_top_speed * 0.92:
				break
	else:
		player.velocity = Vector3(0, 0, player.walk_speed)
	var from := player.global_position.z
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var landed := from
	for i in 240:
		await get_tree().physics_frame
		landed = player.global_position.z
		if player.is_on_floor() and i > 8:
			break
	Input.action_release("attack")
	await get_tree().physics_frame
	return landed - from


## Puts the player somewhere clean and waits for them to land.
##
## The timer resets are not optional, and they are the same lesson `_place()`
## learned in the old suite: leftover state turns the next measurement into a
## different one entirely. Here a crash-stun left over from the wall run made
## two jump measurements read 0.0 m, because `_do_walk` returns early while
## stunned and the jump simply never fired.
func _place(at: Vector3) -> void:
	_release_all()
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.facing = Vector3(0, 0, 1)
	player._stun_left = 0.0
	player._slam_recover_left = 0.0
	player._windup_left = 0.0
	player._charging = false
	player._charge_buffered = 0.0
	player._jump_buffered = 0.0
	player._boost_cool = 0.0
	player._boosts_left = player.boost_taps
	player._set_state(HeavyPlayer.State.WALK)
	# Let them actually touch down. A teleported body is airborne for a frame or
	# two, and `attack` pressed while in AIR is a BOOST rather than a charge —
	# correctly, because that is what the button means there. Pressing too early
	# spent the press on a boost and read as the charge being broken.
	for i in 14:
		await get_tree().physics_frame
		if player.is_on_floor():
			break


func _release_all() -> void:
	Input.action_release("attack")
	Input.action_release("jump")
	Input.action_release("crouch")
