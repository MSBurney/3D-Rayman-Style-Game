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
	await _charge_survives_a_jump()
	await _boost_fade()
	await _see_saw()
	await _momentum_transfer()
	await _plate()
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
	# THE 14 m GAP IS NOT IN THIS LEVEL ANY MORE. `GroundSouth` is a single
	# 1000 x 1000 plane now, so there is nothing to fall into and the room is a
	# free-roam space to tune in. The assertion is inverted rather than deleted,
	# so if the gap ever comes back the probe says so instead of staying quiet
	# about a check that silently stopped meaning anything.
	_note("the gap at z=17 is filled in", not is_nan(_height_at(0, 17, 0.0)),
		"the ground is continuous")
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
	# Against `walk_speed` rather than a fixed number, because the whole point of
	# the charge is to be worth more than walking. The margin is the thing to
	# watch: a charge only a little faster than a walk is not a traversal verb,
	# it is a slower way to walk.
	_note("charge on the flat", flat_top > player.walk_speed * 1.2,
		"tops out at %.1f m/s, walking does %.1f" % [flat_top, player.walk_speed])

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

	# What a jump is WORTH, measured relatively. It used to be checked against
	# the 14 m gap, but that gap is no longer in the level, so there is no
	# absolute distance left to be right or wrong about - only the ratio, which
	# is what the doc actually cares about ("run-up planning is a constant
	# micro-decision"). A charge-jump has to be clearly worth the wind-up.
	print("  -- what a jump is worth")
	var walk_jump := await _jump_distance(false)
	var charge_jump := await _jump_distance(true)
	_note("a charge-jump goes clearly further", charge_jump > walk_jump * 1.25,
		"walking %.1f m, charging %.1f m" % [walk_jump, charge_jump])


## A jump must not end a charge you are still holding, and must end one you let
## go of. Both halves, because the second is what keeps the first honest - a
## charge that survived regardless would be a charge you could not get out of.
func _charge_survives_a_jump() -> void:
	print("  -- a jump does not end a charge")
	var before := await _charge_up()
	_note("charging before the jump", player.state == HeavyPlayer.State.CHARGE,
		"state %s at %.1f m/s" % [player.state_name(), before])

	await _tap("jump")
	await _until_airborne()
	_note("the jump takes off", player.state == HeavyPlayer.State.AIR,
		"state %s" % player.state_name())

	# Still holding all the way down.
	await _until_landed()
	_note("lands straight back into the charge",
		player.state == HeavyPlayer.State.CHARGE,
		"state %s" % player.state_name())
	_note("and does NOT wind up again", player._windup_left <= 0.0,
		"windup %.2f" % maxf(player._windup_left, 0.0))
	_note("with its speed intact", player.flat_speed() > before * 0.8,
		"%.1f m/s, was %.1f" % [player.flat_speed(), before])
	_release_all()
	await get_tree().physics_frame

	# The other half: let go in mid-air and the charge is over.
	await _charge_up()
	await _tap("jump")
	await _until_airborne()
	Input.action_release("attack")
	await _until_landed()
	_note("letting go in mid-air lands in WALK",
		player.state == HeavyPlayer.State.WALK,
		"state %s" % player.state_name())
	_release_all()
	await get_tree().physics_frame


## The boost has to FADE rather than compound. Reported from play as "after
## multiple jump boosts I can travel at ludicrously high speeds", which is the
## same shape as the long jump exploit this project already paid for once.
func _boost_fade() -> void:
	print("  -- the boost fades instead of compounding")
	_compare("full value at walk speed",
		_strength_at(player.walk_speed), player.boost_impulse, 0.01)
	_compare("still full at charge top speed",
		_strength_at(player.charge_top_speed), player.boost_impulse, 0.01)
	_compare("half way through the fade",
		_strength_at((player.charge_top_speed + player.boost_fade_speed) * 0.5),
		player.boost_impulse * 0.5, 0.05)
	_compare("nothing left at the fade speed",
		_strength_at(player.boost_fade_speed), 0.0, 0.01)

	# And the real thing, done the way it was reported: jump, tap the boost in
	# mid-air, land, jump again. One tap per airborne period, ten times.
	await _place(Vector3(40, 0.15, -52))
	player.velocity = Vector3(0, 0, player.walk_speed)
	var top := 0.0
	var taps := 0
	for cycle in 10:
		await _tap("jump")
		for i in 10:
			await get_tree().physics_frame
		await _tap("attack")
		taps += 1
		for i in 240:
			await get_tree().physics_frame
			top = maxf(top, player.flat_speed())
			if player.is_on_floor() and i > 12:
				break
	var uncapped: float = player.walk_speed + player.boost_impulse * taps
	_note("a chain of boosts converges", top <= player.boost_fade_speed + 0.5,
		"%d taps reached %.1f m/s, fade is %.1f, flat adding would give %.1f"
			% [taps, top, player.boost_fade_speed, uncapped])
	_release_all()
	await get_tree().physics_frame


## Universal weight rule 3, and the prop built to make it visible.
##
## Most of this measures `WeightSensor.moment` rather than waiting for the plank
## to finish moving, and that is deliberate: standing still on a 14-degree slope
## is a near-tie between `slope_gravity` and `walk_decel`, so a test that waited
## for the tilt to settle would be measuring the player creeping downhill as
## much as the rule. The moment is the rule; the tilt is its presentation.
func _see_saw() -> void:
	print("  -- weight rule 3: the heavier side of a pivot wins")
	var see_saw := level.get_node_or_null("SeeSaw") as SeeSaw
	var crate := level.get_node_or_null("SeeSawCrate") as RigidBody3D
	if see_saw == null or crate == null:
		_note("the see-saw is in the level", false, "SeeSaw / SeeSawCrate missing")
		return

	# Player parked well away, so only the crate is on the plank.
	await _teleport(Vector3(0, 0.15, -52))
	for i in 90:
		await get_tree().physics_frame
	_note("the crate alone tips its own end down", see_saw.leaning() == 1,
		"leaning %d at %.1f degrees" % [see_saw.leaning(), see_saw.tilt])

	# A scriptless RigidBody3D and a CharacterBody3D weighed by the same layer.
	# That is rule 5 — everything obeys the same physics — and the crate proving
	# it without a line of script is the whole point of the `heavy` group.
	await _teleport(see_saw.to_global(Vector3(0, 0.3, -2.0)))
	_note("the player and the crate both have weight",
		see_saw.sensor.riders.size() == 2,
		"%d riders, %.1f total" % [see_saw.sensor.riders.size(),
			see_saw.sensor.total_mass])
	_note("near the pivot the crate still wins", see_saw.sensor.moment > 0.0,
		"moment %+.1f" % see_saw.sensor.moment)

	# ...and THE SAME WEIGHT, FURTHER OUT, WINS. The lever is the lesson, and it
	# is the one thing here a player can work out unaided.
	await _teleport(see_saw.to_global(Vector3(0, 0.3, -4.2)))
	_note("the same weight further out wins", see_saw.sensor.moment < 0.0,
		"moment %+.1f" % see_saw.sensor.moment)

	print("  -- and the slam is the see-saw launcher")
	var thrown: Array[float] = []
	see_saw.launched.connect(func(_body: Node3D, speed: float) -> void:
		# Recorded into an ARRAY, never into a captured float. A GDScript lambda
		# captures a local by VALUE, so assigning to a captured float writes to
		# the lambda's own copy and the outer variable never changes — which
		# reads as "the signal never fired" and has already cost this project an
		# afternoon of hunting a bug that was not there.
		thrown.append(speed))

	# Dropped from 8 m onto one end, for real, rather than faking the signal.
	await _teleport(see_saw.to_global(Vector3(0, 8.0, -4.0)))
	# Long enough for WALK to notice there is no floor and hand over to AIR,
	# because `crouch` only becomes a slam from AIR or CHARGE.
	for i in 14:
		await get_tree().physics_frame
	Input.action_press("crouch")
	await get_tree().physics_frame
	Input.action_release("crouch")
	for i in 120:
		await get_tree().physics_frame
		if thrown.size() > 0:
			break
	var detail := "nothing was thrown"
	if thrown.size() > 0:
		detail = "threw %d, fastest %.1f m/s" % [thrown.size(), thrown.max()]
	_note("a slam on one end throws the other", thrown.size() > 0, detail)


## Universal weight rule 1, and the build list's "pressure plate requiring
## walk-mode precision" — which is a claim, so it is tested as one.
func _plate() -> void:
	print("  -- weight rule 1: a visible weight threshold")
	var plate := level.get_node_or_null("Plate") as PressurePlate
	var lift := level.get_node_or_null("PlateLift") as MovingPlatform
	var deck := level.get_node_or_null("PlateDeck") as Node3D
	if plate == null or lift == null or deck == null:
		_note("the plate is in the level", false, "Plate / PlateLift / PlateDeck missing")
		return

	# Measured BEFORE the plate is pressed, while the lift is still at its start.
	# Does it ARRIVE at the deck, or merely near it? "Nearly" is a lip the player
	# trips on, and it is invisible until somebody measures it.
	var lift_top := lift.global_position.y + 0.3 + lift.travel.y
	var deck_top := deck.global_position.y + 0.4
	_compare("the lift arrives at deck height", lift_top, deck_top, 0.05)

	# THE DESIGN CLAIM, and it has to be tested before the standing one because
	# this plate latches. A charge at 20 m/s is inside a 1.8 m pad for about five
	# physics frames, against a fifteen-frame hold.
	await _place(Vector3(22, 0.15, 4))
	Input.action_press("attack")
	var crossed := false
	for i in 300:
		await get_tree().physics_frame
		if plate.down:
			break
		if player.global_position.z > 24.0:
			crossed = true
			break
	Input.action_release("attack")
	await get_tree().physics_frame
	_note("a charge across it does NOT set it off", crossed and not plate.down,
		"crossed=%s pressed=%s" % [crossed, plate.down])

	# Standing on it is NOT enough any more, which is the interesting kind of
	# plate: it wants 14 and the hero weighs 10. "Go and find something heavy"
	# only became a solvable instruction when weight rule 2 went in.
	await _place(Vector3(22, 0.45, 18))
	for i in 60:
		await get_tree().physics_frame
	_note("your own weight is not enough", not plate.down,
		"you weigh %.0f, it wants %.0f" % [player.mass, plate.required_mass])

	# ...but the crate is. Placed rather than rammed here: the shove has its own
	# section, and a six-metre push is not a repeatable measurement.
	var crate := level.get_node_or_null("PlateCrate") as RigidBody3D
	await _place(Vector3(40, 0.15, -52))
	await _put(crate, Vector3(22, 0.8, 18))
	var waited := 0.0
	for i in 150:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
		if plate.down:
			break
	_note("a heavy enough crate is", plate.down,
		"crate weighs %.0f, pressed after %.2f s" % [crate.mass, waited])
	_note("and it raises the lift", lift.active, "lift active=%s" % lift.active)


## Universal weight rule 2: momentum transfers on impact. All three directions,
## because until this went in the hero could MEASURE weight everywhere and
## deliver it nowhere — which is exactly how the props played.
func _momentum_transfer() -> void:
	print("  -- weight rule 2: momentum transfers on impact")
	var crate := level.get_node_or_null("PlateCrate") as RigidBody3D
	if crate == null:
		_note("there is a crate to shove", false, "PlateCrate missing")
		return

	# ── the hero pushes an object, and takes the reaction ──
	# At walking pace rather than in a charge, deliberately: `_was_stopped_dead()`
	# only fires above `walk_speed`, so this measures the shove instead of
	# measuring a crash. Ramming this crate IN a charge crash-stuns you, which is
	# correct — it outweighs you 16 to 10.
	await _put(crate, Vector3(40, 0.55, -44))
	await _place(Vector3(40, 0.15, -48))
	player.velocity = Vector3(0, 0, player.walk_speed)
	var shifted := 0.0
	var kept := player.walk_speed
	for i in 120:
		await get_tree().physics_frame
		# HORIZONTAL speed only. Watching the whole vector triggered on the 5 cm
		# the crate settles through under gravity, several frames before the
		# player arrived — so the check passed while measuring nothing but the
		# crate falling, and reported the player at full speed because they had
		# not touched it yet.
		var sideways := Vector2(crate.linear_velocity.x, crate.linear_velocity.z).length()
		if sideways > 0.5:
			shifted = sideways
			kept = player.flat_speed()
			break
	_note("ramming a crate moves it", shifted > 1.0,
		"it left at %.1f m/s" % shifted)
	# The half that makes mass a reasoning tool rather than a stat.
	_note("and the crate takes speed off YOU", kept < player.walk_speed * 0.8,
		"kept %.1f of %.1f m/s" % [kept, player.walk_speed])

	# ── a slam scatters what is lying around it ──
	await _put(crate, Vector3(40, 0.55, -44))
	await _teleport(Vector3(40, 9.0, -46))
	# Long enough for WALK to notice there is no floor: `crouch` is only a slam
	# from AIR or CHARGE.
	for i in 14:
		await get_tree().physics_frame
	Input.action_press("crouch")
	await get_tree().physics_frame
	Input.action_release("crouch")
	var lifted := 0.0
	for i in 120:
		await get_tree().physics_frame
		lifted = maxf(lifted, crate.linear_velocity.y)
	_note("a slam throws loose objects around it", lifted > 1.0,
		"the crate went up at %.1f m/s" % lifted)

	# ── and something arriving under its own steam moves the HERO ──
	# The direction `get_slide_collision()` cannot see, because it only reports
	# what WE moved into. A standing player is invisible to it.
	await _put(crate, Vector3(40, 0.55, -48))
	await _place(Vector3(40, 0.15, -44))
	crate.linear_velocity = Vector3(0, 0, 18)
	var shoved := 0.0
	for i in 90:
		await get_tree().physics_frame
		shoved = maxf(shoved, player.velocity.z)
		if shoved > 1.0:
			break
	_note("a crate thrown at you moves YOU", shoved > 1.0,
		"shoved at %.1f m/s" % shoved)
	await _put(crate, Vector3(16, 0.8, 18))


## Parks a loose object somewhere, stopped.
##
## All four lines are needed. A `RigidBody3D` keeps its velocity, its spin AND
## its sleep state across a teleport, so without clearing them the next
## measurement begins with the last one's leftovers — and a sleeping body
## ignores the impulse that the next check is trying to measure.
func _put(body: RigidBody3D, at: Vector3) -> void:
	if body == null:
		return
	body.global_position = at
	body.rotation = Vector3.ZERO
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = false
	await get_tree().physics_frame


## Puts the player somewhere and lets one physics frame pass, WITHOUT waiting
## for them to land.
##
## Right for the weight checks and wrong for everything else: `weight_sensor.gd`
## measures a volume, so a hovering player is weighed exactly like a standing
## one — which is also what lets a carried or falling body count, and is why it
## is a position check rather than a floor check.
func _teleport(at: Vector3) -> void:
	_release_all()
	player.global_position = at
	player.velocity = Vector3.ZERO
	player._stun_left = 0.0
	player._slam_recover_left = 0.0
	player._windup_left = 0.0
	player._charging = false
	player._charge_through_air = false
	player._charge_buffered = 0.0
	player._jump_buffered = 0.0
	player._set_state(HeavyPlayer.State.WALK)
	await get_tree().physics_frame


## What a boost would be worth at a given speed. Reads the real function rather
## than re-deriving the curve, so a change to one cannot pass a test of the other.
func _strength_at(speed: float) -> float:
	player.velocity = Vector3(0, 0, speed)
	return player.boost_strength()


## Winds up a charge on open flat ground and returns the speed it got to.
func _charge_up() -> float:
	await _place(Vector3(40, 0.15, -52))
	Input.action_press("attack")
	for i in 200:
		await get_tree().physics_frame
		if (player.state == HeavyPlayer.State.CHARGE
				and player.flat_speed() >= player.charge_top_speed * 0.9):
			break
	return player.flat_speed()


## Press and release across two frames. Pressing on EVERY frame never produces a
## fresh `just_pressed`, so the move simply never fires - which reads as a
## gameplay bug rather than as a test that cannot press a button.
func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func _until_airborne() -> void:
	for i in 30:
		await get_tree().physics_frame
		if not player.is_on_floor():
			return


func _until_landed() -> void:
	for i in 300:
		await get_tree().physics_frame
		if player.is_on_floor() and player.state != HeavyPlayer.State.AIR:
			return


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
	player._charge_through_air = false
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
