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
## Spawned rather than placed in the level, because the strike checks want a
## switch they can put exactly where the measurement needs it.
const SWITCH := preload("res://scenes/props/strike_switch.tscn")
const BLOCK := preload("res://scenes/props/breakable_block.tscn")
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
	await _carrying()
	# The plate runs BEFORE the giant, and the order is load-bearing: the plate
	# LATCHES, and the lift's travel can only be measured against the deck while
	# it is still sitting at its start. Let the giant stand on the plate first and
	# every check after it passes for the wrong reason.
	await _plate()
	await _giant()
	await _striking()
	await _skidding()
	await _no_death()
	await _grinding()
	await _transformations()
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


## The carry verb: automatic pickup, and the boost button throws.
##
## The interesting part is the conflict it had to resolve. Picking an object up
## on contact and ramming it on contact are the SAME input, so one of them had
## to lose — and `walk_speed` had already drawn the line between precise and
## committed. Both halves are checked here, because a rule you only test in one
## direction is half a rule.
func _carrying() -> void:
	print("  -- the carry verb, and what decides between lifting and ramming")
	var light := level.get_node_or_null("SeeSawCrate") as RigidBody3D
	var heavy := level.get_node_or_null("PlateCrate") as RigidBody3D
	var wall := level.get_node_or_null("ThrowWall") as BreakableBlock
	var see_saw := level.get_node_or_null("SeeSaw") as SeeSaw
	if light == null or heavy == null or wall == null or see_saw == null:
		_note("the carry fixtures exist", false, "a crate, the wall or the see-saw is missing")
		return

	# ── walking up to one lifts it ──
	await _hands_on(light, Vector3(-24, 0.15, -16))
	_note("walking up to a crate picks it up", player.carried == light,
		"carrying %s" % ("nothing" if player.carried == null else player.carried.name))

	# ── but not one heavier than you ──
	# The light one is parked back home FIRST. Pickup is automatic and the reset
	# helper puts whatever was carried down at the hold point, a metre in front of
	# the player â so leaving it there means they simply pick it straight back up
	# and the next check measures the wrong crate.
	await _put(light, Vector3(-24, 2.2, 9.6))
	await _place(Vector3(-24, 0.15, -16))
	await _put(heavy, Vector3(-24, 0.55, -14.9))
	for i in 40:
		await get_tree().physics_frame
	_note("but not one heavier than you can lift", player.carried == null,
		"it weighs %.0f against a limit of %.0f" % [heavy.mass, player.carry_max_mass])
	await _put(heavy, Vector3(16, 0.8, 18))

	# ── and a charge rams rather than lifts ──
	await _place(Vector3(-24, 0.15, -24))
	await _put(light, Vector3(-24, 0.55, -14))
	Input.action_press("attack")
	var rammed := 0.0
	for i in 300:
		await get_tree().physics_frame
		rammed = maxf(rammed, _flat_speed_of(light))
		if player.carried != null or rammed > 1.0:
			break
	Input.action_release("attack")
	await get_tree().physics_frame
	_note("charging into the same crate rams it instead",
		player.carried == null and rammed > 1.0,
		"it left at %.1f m/s, carried=%s" % [rammed, player.carried != null])

	# ── the throw inherits your momentum ──
	await _hands_on(light, Vector3(-24, 0.15, -16))
	player.facing = Vector3(0, 0, 1)
	await _tap("attack")
	var flew := _flat_speed_of(light)
	_note("the boost button throws it", player.carried == null and flew > 5.0,
		"it left at %.1f m/s" % flew)

	# ── and what it hits, it breaks ──
	await _hands_on(light, Vector3(-24, 0.15, -16))
	player.facing = Vector3(0, 0, 1)
	await _tap("attack")
	var opened := false
	for i in 180:
		await get_tree().physics_frame
		if wall.broken_open:
			opened = true
			break
	_note("a thrown crate breaks a block the hero could not", opened,
		"break_speed %.0f, broken_open=%s" % [wall.break_speed, opened])

	# ── THE PAY-OFF: a heavy arrival launches whoever is on the far end ──
	# Dropped from a height rather than thrown, because this measures the RULE.
	# In play the way you arrange it is to throw the crate up over the far end
	# and run to the near one while it is in the air — about 1.3 s of flight
	# against a 0.5 s run — but that is a sequence, not a rule, and a probe that
	# depended on it would be measuring the throw arc instead of rule 5.
	print("  -- and a heavy arrival launches whoever is on the far end")
	await _place(see_saw.to_global(Vector3(0, 0.6, -3.6)))
	await _put(light, see_saw.to_global(Vector3(0, 6.0, 3.6)))
	var lifted := 0.0
	for i in 150:
		await get_tree().physics_frame
		lifted = maxf(lifted, player.velocity.y)
	_note("a crate dropped on the far end throws YOU", lifted > 1.0,
		"launched at %.1f m/s, no slam involved" % lifted)
	await _put(light, Vector3(-24, 2.2, 9.6))


## **Universal weight rule 5: enemies obey the same physics as the player.**
##
## The doc lists four things a room should be able to do with a heavy enemy, and
## every one of them is checked here — because "it is a puzzle noun" is a claim
## about four separate props agreeing with each other, and nothing but a test
## can tell you whether they do. None of it is code in `heavy_enemy.gd`.
func _giant() -> void:
	print("  -- weight rule 5: a heavy enemy is a puzzle noun")
	var giant := level.get_node_or_null("Giant") as HeavyEnemy
	var plate := level.get_node_or_null("Plate") as PressurePlate
	var slab := level.get_node_or_null("FragileSlab") as CrumblingFloor
	var wall := level.get_node_or_null("MassWall") as BreakableBlock
	if giant == null or plate == null or slab == null or wall == null:
		_note("the giant fixtures exist", false, "Giant, Plate, FragileSlab or MassWall missing")
		return

	_note("it weighs more than you do", giant.mass > player.mass,
		"%.0f against your %.0f" % [giant.mass, player.mass])

	# ── it holds a pressure plate down, so the crate is not the only answer ──
	# Put back up first: `_plate()` has already latched it with the crate, and a
	# plate that is still down proves nothing about who is standing on it.
	plate.reset()
	await _put(level.get_node_or_null("PlateCrate") as RigidBody3D, Vector3(16, 0.8, 18))
	await _place(Vector3(40, 0.15, -52))
	_put_giant(giant, Vector3(22, 0.1, 18))
	var held := false
	for i in 150:
		await get_tree().physics_frame
		if plate.down:
			held = true
			break
	_note("standing on the plate holds it down", held,
		"it wants %.0f and he brings %.0f" % [plate.required_mass, giant.mass])

	# ── a floor tuned between the two masses carries you and not him ──
	# The giant goes to the far side of the level for this one. He lures from 18 m
	# away, so parking him anywhere near the slab means he walks over and breaks
	# it himself — which is the right behaviour and the wrong measurement.
	_put_giant(giant, Vector3(40, 0.1, -60))
	# Put the slab back first. It has almost certainly been broken already by the
	# giant walking over it during an earlier check — which is the system working,
	# and would have this check measuring a hole in the ground instead of a floor.
	slab.reset()
	await _place(Vector3(28, 0.15, 20))
	for i in 90:
		await get_tree().physics_frame
	_note("the fragile floor carries YOU", slab.state == CrumblingFloor.State.WHOLE,
		"it breaks at %.0f and you weigh %.0f" % [slab.break_mass, player.mass])

	await _place(Vector3(40, 0.15, -52))
	slab.reset()
	_put_giant(giant, Vector3(28, 0.1, 20))
	var gave_way := false
	for i in 150:
		await get_tree().physics_frame
		if slab.state != CrumblingFloor.State.WHOLE:
			gave_way = true
			break
	_note("...and gives way under HIM", gave_way,
		"he weighs %.0f" % giant.mass)

	# ── a wall you can never open, which he walks through ──
	# The player stands BEYOND the wall. He walks towards whoever he can see, so
	# the only way to aim him at something is to stand behind it — which is also
	# exactly how the puzzle is solved in play.
	_put_giant(giant, Vector3(34, 0.1, 25))
	await _place(Vector3(34, 0.15, 34))
	var opened := false
	for i in 300:
		await get_tree().physics_frame
		if wall.broken_open:
			opened = true
			break
	_note("he opens a wall you cannot", opened,
		"break_speed %.0f, break_mass %.0f" % [wall.break_speed, wall.break_mass])

	# ── walking into him is not enough; a charge fells him ──
	# The threshold is MOMENTUM, so the hero brings 150 at walking pace and 200
	# charging, against a bar of 180. That one number is the whole difference
	# between the right tool and the wrong one.
	_put_giant(giant, Vector3(40, 0.1, -40))
	await _place(Vector3(40, 0.15, -46))
	player.velocity = Vector3(0, 0, player.walk_speed)
	for i in 90:
		await get_tree().physics_frame
		if giant.is_down():
			break
	_note("walking into him does NOT fell him", not giant.is_down(),
		"%.0f x %.1f = %.0f against a bar of %.0f"
			% [player.mass, player.walk_speed, player.mass * player.walk_speed,
			giant.topple_momentum])

	# ...BUT IT HAS TO VISIBLY DO SOMETHING. This is the check that exists
	# because the first version failed in play and not here: a hit under the bar
	# did nothing at all, no stagger and no dust, and it was reported as "I tried
	# to ram into the enemy, but there was no response". A refusal that looks
	# identical to a dropped input is the one outcome this project has a standing
	# rule against.
	var shrugs: Array[float] = []
	giant.shrugged_off.connect(func(_by: Node3D, share: float) -> void:
		# An ARRAY, never a captured float. A GDScript lambda captures locals by
		# VALUE, so assigning to a captured float updates the lambda's own copy
		# and reads back here as "the signal never fired".
		shrugs.append(share))
	_put_giant(giant, Vector3(40, 0.1, -40))
	await _place(Vector3(40, 0.15, -46))
	player.velocity = Vector3(0, 0, player.walk_speed)
	for i in 120:
		await get_tree().physics_frame
		if shrugs.size() > 0 or giant.is_down():
			break
	var shrug_detail := "nothing happened at all"
	if shrugs.size() > 0:
		shrug_detail = "shrugged it off at %.0f%% of the bar" % [shrugs[0] * 100.0]
	_note("a refused hit staggers him instead of being ignored",
		shrugs.size() > 0, shrug_detail)

	# ── and HE shoves YOU, which is the half that measured zero ──
	# A giant walking into a player standing perfectly still. The closing speed
	# is entirely his, so reading only the other body's velocity gave zero and
	# nothing happened — the other half of the same report.
	_put_giant(giant, Vector3(40, 0.1, -44))
	await _place(Vector3(40, 0.15, -40))
	player.velocity = Vector3.ZERO
	var pushed := 0.0
	for i in 150:
		await get_tree().physics_frame
		pushed = maxf(pushed, player.velocity.z)
		if pushed > 0.5:
			break
	_note("he shoves YOU when he walks into you", pushed > 0.5,
		"shoved at %.1f m/s while standing still" % pushed)

	_put_giant(giant, Vector3(40, 0.1, -30))
	await _place(Vector3(40, 0.15, -52))
	Input.action_press("attack")
	for i in 300:
		await get_tree().physics_frame
		if giant.is_down():
			break
	Input.action_release("attack")
	await get_tree().physics_frame
	_note("but a charge does", giant.is_down(), "state %s" % giant.state_name())

	# ── and a felled giant is something you can stand on ──
	# The point of felling one. A standing box tipped on its side would be a kerb
	# you cannot climb, so the felled collider is authored low and long and this
	# measures that it really is.
	var top := _height_at(giant.global_position.x, giant.global_position.z, 0.8)
	_note("a felled giant is a low platform", not is_nan(top) and top > 0.4 and top < 1.4,
		"its top is at %.2f" % top)
	_put_giant(giant, Vector3(34, 0.1, 20))


## Parks the giant somewhere, standing and unhurt.
##
## `_hit_left` has to be cleared too: it is the blind spell that stops one
## collision being counted on several frames, and a leftover one would make the
## next measurement look like the topple threshold had failed.
func _put_giant(giant: HeavyEnemy, at: Vector3) -> void:
	giant.global_position = at
	giant.velocity = Vector3.ZERO
	giant._hit_left = 0.0
	giant._home = at
	giant._home_set = true
	if giant.is_down():
		giant._stand_up()


## The strike contract, which replaced the spin's.
##
## **The slam shockwave is the only AoE left in the moveset**, so it is the only
## thing that can reach a switch, a till, a chest or a block without touching
## it. These checks are written the way the giant's bugs taught: one for the
## threshold being crossed, and one for what happens when it is NOT — because
## every check that only ever asked "did it fire" missed three bugs in a row.
func _striking() -> void:
	print("  -- the strike contract: what a slam reaches")

	var switch := SWITCH.instantiate() as StrikeSwitch
	level.add_child(switch)
	var switch_at := Vector3(44, 0.0, -52)
	switch.global_position = switch_at
	await get_tree().physics_frame

	# A hop-stomp beside it. Worth about 15 momentum at point blank against the
	# switch's 12, which is the "any deliberate stomp" band the switch is for.
	var before := switch.on
	await _stomp_at(switch_at + Vector3(1.1, 0.15, 0))
	_note("a stomp beside a switch trips it", switch.on != before,
		"on %s -> %s" % [before, switch.on])

	# ...and the SAME stomp from across the room does not, because the momentum
	# falls off to nothing at the edge of the shockwave. A radius with no falloff
	# would make "stand close" meaningless.
	var distant := SWITCH.instantiate() as StrikeSwitch
	level.add_child(distant)
	distant.global_position = Vector3(44, 0.0, -32)
	await get_tree().physics_frame
	var distant_before := distant.on
	await _stomp_at(switch_at + Vector3(1.1, 0.15, 0))
	_note("...and the same stomp 20 m away does not",
		distant.on == distant_before,
		"on %s, %.0f m off" % [distant.on,
			distant.global_position.distance_to(switch_at)])

	# A block wanting a REAL drop. 100 is out of reach of a hop (7) and inside
	# what a fall from height brings (140), so the same button gives two answers
	# depending on how far you fell — rule 4, as a single number.
	var block := BLOCK.instantiate() as BreakableBlock
	level.add_child(block)
	var block_at := Vector3(50, 1.0, -52)
	block.global_position = block_at
	block.break_speed = 999.0
	block.break_mass = -1.0
	block.strike_momentum = 100.0
	await get_tree().physics_frame

	await _stomp_at(block_at + Vector3(1.6, -0.85, 0))
	var shrugged := not block.broken_open
	_note("a hop-stomp will not open a block wanting a real drop", shrugged,
		"broken=%s against strike_momentum %.0f" % [block.broken_open,
			block.strike_momentum])

	# The same stomp, from 18 m up.
	await _place(block_at + Vector3(1.6, 17.0, 0))
	_tap("crouch")
	for i in 150:
		await get_tree().physics_frame
		if block.broken_open:
			break
	_note("...and dropping on it from 18 m does", block.broken_open,
		"broken=%s" % block.broken_open)
	_release_all()

	switch.queue_free()
	distant.queue_free()
	block.queue_free()
	await get_tree().physics_frame


## Stands at `at`, hops, and stomps. The shockwave goes out from wherever the
## player lands, so what the strike is worth is decided by where they stood.
func _stomp_at(at: Vector3) -> void:
	await _place(at)
	_tap("jump")
	await _until_airborne()
	for i in 8:
		await get_tree().physics_frame
	_tap("crouch")
	for i in 70:
		await get_tree().physics_frame
		if player.is_on_floor():
			break
	_release_all()
	await get_tree().physics_frame


## The skid and the side-jump: the immediate turnaround.
##
## The direction the stick means depends on where the camera is looking, so
## rather than guessing, this presses a key, reads back what `wish_dir` became,
## and then sets the velocity the OTHER way. Deterministic whatever the rig is
## doing, which a hardcoded axis would not be.
func _skidding() -> void:
	print("  -- skidding, and the side-jump out of it")

	var entered := await _start_skid()
	_note("reversing the stick at speed starts a skid", entered,
		"state %s" % player.state_name())
	if not entered:
		_release_all()
		return

	var aim := player._skid_aim
	var entry := player.flat_speed()
	for i in 10:
		await get_tree().physics_frame
		if player.state != HeavyPlayer.State.SKID:
			break
	_note("the slide brakes you hard", player.flat_speed() < entry - 2.0,
		"%.1f m/s, entered at %.1f" % [player.flat_speed(), entry])
	# The heading pivots AHEAD of the body, which is what makes a slide read as a
	# decision rather than as losing control.
	#
	# Compared against where the body is actually TRAVELLING rather than against
	# a fixed angle: the heading leading the travel is the claim, and an absolute
	# threshold would only be measuring how many frames the check waited.
	var going := Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
	_note("...while you already face the new way",
		player.facing.dot(aim) > going.dot(aim) + 0.5,
		"heading is %.2f towards it, travel is still %.2f"
			% [player.facing.dot(aim), going.dot(aim)])

	# Out the far side, pointed the other way.
	for i in 60:
		await get_tree().physics_frame
		if player.state != HeavyPlayer.State.SKID:
			break
	_note("and it leaves you walking the other way",
		player.state == HeavyPlayer.State.WALK and player.facing.dot(aim) > 0.9,
		"state %s, facing dot aim %.2f" % [player.state_name(), player.facing.dot(aim)])
	_release_all()
	await get_tree().physics_frame

	# ── the side-jump: the same turn, cashed in for height ──
	entered = await _start_skid()
	if not entered:
		_note("a skid can be jumped out of", false, "the skid never started")
		_release_all()
		return
	aim = player._skid_aim
	# `_tap` and not a press-and-check: a press needs a frame to be seen, and
	await _tap("jump")
	_note("jumping out of a skid reverses you", player.state == HeavyPlayer.State.AIR
		and Vector3(player.velocity.x, 0.0, player.velocity.z).normalized().dot(aim) > 0.9,
		"state %s" % player.state_name())
	_note("...and throws you higher than a standing jump",
		player.velocity.y > player.jump_speed,
		"%.1f m/s up against a jump of %.1f" % [player.velocity.y, player.jump_speed])
	_release_all()
	await get_tree().physics_frame


## Gets a skid going and returns whether it started.
func _start_skid() -> bool:
	await _place(Vector3(40, 0.15, -52))
	Input.action_press("move_forward")
	await get_tree().physics_frame
	var aim := player.wish_dir
	if aim == Vector3.ZERO:
		return false
	# Travelling the opposite way to the stick, fast enough to be worth skidding.
	player.velocity = -aim * (player.skid_min_speed + 4.0)
	for i in 20:
		await get_tree().physics_frame
		if player.state == HeavyPlayer.State.SKID:
			return true
	return false


## **There is no death**, so a hit has to do something else instead.
func _no_death() -> void:
	print("  -- taking a hit, in a game with no death")
	var hurts: Array[int] = []
	Events.player_hurt.connect(func(_at: Vector3, cost: int) -> void:
		# An ARRAY, never a captured int. A lambda captures locals by VALUE.
		hurts.append(cost))

	await _place(Vector3(40, 0.15, -52))
	player.velocity = Vector3.ZERO
	var from := player.global_position + Vector3(0, 0, -2)
	var landed := player.take_hit(99, from, 7)
	await get_tree().physics_frame
	# 99 damage, and it is simply ignored: the controller has no health to take
	# it off. Every caller in the project still hands a number over, which is
	# exactly why the no-death model lives in `take_hit` and not in each of them.
	_note("a hit lands and does not kill you",
		landed and is_instance_valid(player), "state %s" % player.state_name())
	_note("it throws you away from whatever hit you", player.velocity.z > 1.0,
		"thrown at %.1f m/s" % player.velocity.z)
	_note("and scatters your money where you lost it", hurts.size() > 0,
		"player_hurt carried a cost of %s"
			% ("nothing" if hurts.is_empty() else str(hurts[0])))
	_note("a second hit inside the blind spell is refused",
		not player.take_hit(99, from, 7),
		"invuln is %.2f s" % player.hurt_invuln)
	_release_all()
	await get_tree().physics_frame


## Rail grinding, ported from `player.gd` onto the modal controller.
##
## Checked because a port is exactly the kind of change that compiles and then
## does nothing: the state machine, the input fork and the early return before
## `move_and_slide()` all had to be re-wired by hand.
func _grinding() -> void:
	print("  -- rail grinding, ported to the heavy controller")
	var rail := level.get_node_or_null("Rail") as GrindRail
	if rail == null:
		_note("there is a rail", false, "Rail missing")
		return

	# Dropped on to the head of the rail. A rail is caught from the AIR only, so
	# this has to be a fall and not a walk.
	var caught := await _catch_rail(rail)
	_note("you catch a rail in mid-air", caught,
		"state %s" % player.state_name())
	if not caught:
		return

	# Downhill, so coasting alone has to build speed: the slope maths reuses
	# `slope_gravity`, which means a rail physically cannot disagree with a ramp
	# about which way is downhill.
	var entry := absf(player._rail_speed)
	for i in 70:
		await get_tree().physics_frame
		if player.state != HeavyPlayer.State.GRIND:
			break
	_note("a downhill rail builds speed on its own",
		absf(player._rail_speed) > entry + 1.0 or player.state != HeavyPlayer.State.GRIND,
		"entered at %.1f, reached %.1f m/s" % [entry, absf(player._rail_speed)])

	# Jumping off keeps what you earned, which is the one rule that makes a rail
	# traversal instead of scenery.
	caught = await _catch_rail(rail)
	for i in 50:
		await get_tree().physics_frame
		if player.state != HeavyPlayer.State.GRIND:
			break
	var before := absf(player._rail_speed)
	await _tap("jump")
	_note("jumping off keeps your speed",
		player.state == HeavyPlayer.State.AIR and player.flat_speed() > before * 0.5,
		"left at %.1f of %.1f m/s, state %s"
			% [player.flat_speed(), before, player.state_name()])
	_note("and you do not re-catch the rail you just left",
		player.state != HeavyPlayer.State.GRIND,
		"relatch lock %.2f" % maxf(player._grind_lock, 0.0))
	_release_all()
	await get_tree().physics_frame


## The two transformations, ported.
##
## The PUFFY mass check is the one worth having: it is the doc's weight grammar
## for that form ("mass zero: thresholds and pivots stop answering to you"), and
## it only works because `mass` is a real number the weight layer reads.
func _transformations() -> void:
	print("  -- transformations, ported to the heavy controller")
	var wall := level.get_node_or_null("FireWall") as BreakableBlock
	var plate := level.get_node_or_null("Plate") as PressurePlate
	if wall == null or plate == null:
		_note("the transformation fixtures exist", false, "FireWall or Plate missing")
		return

	# ── FLAMING: sprints you, and the stick barely answers ──
	await _place(Vector3(-40, 0.15, 4))
	player.facing = Vector3(0, 0, 1)
	player.transform_into(HeavyPlayer.State.FLAMING)
	for i in 10:
		await get_tree().physics_frame
	_note("catching fire sprints you", player.flat_speed() > player.walk_speed + 2.0,
		"%.1f m/s against a walk of %.1f" % [player.flat_speed(), player.walk_speed])
	_note("...and you cannot act while transformed", player.is_transformed(),
		"state %s" % player.state_name())

	# ── being alight opens a speed-gated wall for free ──
	# `flame_speed` is above every `break_speed` on purpose, and the block asks
	# how fast you arrived without knowing the state exists.
	var opened := false
	for i in 150:
		await get_tree().physics_frame
		if wall.broken_open:
			opened = true
			break
	_note("being alight opens a speed-gated wall for free", opened,
		"break_speed %.0f against flame_speed %.0f" % [wall.break_speed, player.flame_speed])

	# ── and it burns out on its own ──
	await _place(Vector3(-40, 0.15, -14))
	player.transform_into(HeavyPlayer.State.FLAMING, 0.3)
	for i in 90:
		await get_tree().physics_frame
		if not player.is_transformed():
			break
	_note("the fire burns out on its own", not player.is_transformed(),
		"state %s" % player.state_name())

	# ── PUFFY: rises, and weighs nothing while it does ──
	plate.reset()
	await _put(level.get_node_or_null("PlateCrate") as RigidBody3D, Vector3(16, 0.8, 18))
	await _place(Vector3(22, 0.45, 18))
	var base := player.mass
	player.transform_into(HeavyPlayer.State.PUFFY)
	await get_tree().physics_frame
	_note("being inflated takes your mass to zero", is_zero_approx(player.mass),
		"mass %.1f, was %.1f" % [player.mass, base])
	var rose := player.global_position.y
	for i in 30:
		await get_tree().physics_frame
	_note("...and floats you upward", player.global_position.y > rose + 0.5,
		"rose %.2f m" % [player.global_position.y - rose])

	# ── crouch pops it, and the mass comes back ──
	await _tap("crouch")
	_note("crouch pops you out of it", not player.is_transformed(),
		"state %s" % player.state_name())
	_note("and your mass comes back", is_equal_approx(player.mass, base),
		"mass %.1f" % player.mass)
	_release_all()
	await get_tree().physics_frame


## Drops the player on to the head of `rail` and waits for the catch.
func _catch_rail(rail: GrindRail) -> bool:
	await _place(Vector3(-40, 7.0, -26))
	player._grind_lock = 0.0
	# Just above and just past the rail's head, falling, with some speed along it
	# so the entry projection has something to work with.
	player.global_position = rail.point_at(1.5) + Vector3.UP * 1.2
	player.velocity = Vector3(0, -2.0, 6.0)
	player.facing = Vector3(0, 0, 1)
	player._set_state(HeavyPlayer.State.AIR)
	for i in 40:
		await get_tree().physics_frame
		if player.state == HeavyPlayer.State.GRIND:
			return true
	return false


## Horizontal speed of a loose object. Watching the whole velocity vector picks
## up the metre-per-second a crate gains just settling onto the floor.
func _flat_speed_of(body: RigidBody3D) -> float:
	return Vector2(body.linear_velocity.x, body.linear_velocity.z).length()


## Puts the player at `at` with `what` close enough to be picked up, and waits
## until it is in their hands.
func _hands_on(what: RigidBody3D, at: Vector3) -> void:
	await _place(at)
	await _put(what, at + Vector3(0, 0.4, 1.1))
	for i in 60:
		await get_tree().physics_frame
		if player.carried != null:
			return


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
	_empty_hands()
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
	_empty_hands()
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


## Pickup is AUTOMATIC, so a crate left in the player's hands rides along into
## the next measurement and quietly changes its mass. Both reset helpers call
## this for the same reason they clear the timers.
func _empty_hands() -> void:
	var held := player.carried
	if held != null:
		player._release(Vector3.ZERO)
	player._regrab = 0.0
	var rigid := held as RigidBody3D
	if rigid != null:
		# PARKED out of the way, not merely dropped. `_release` leaves it at the
		# hold point, a metre in front of the player, and pickup is automatic with
		# the regrab delay cleared — so dropping it there means it is collected
		# again on the next frame and the following check measures a crate it was
		# never given. Teleporting it while it was still held does not work
		# either: `_carry_tick()` puts a carried object back on the hold point
		# every single frame.
		rigid.global_position = Vector3(0, 0.6, -70)
		rigid.linear_velocity = Vector3.ZERO
		rigid.angular_velocity = Vector3.ZERO
		rigid.sleeping = false


func _release_all() -> void:
	Input.action_release("attack")
	Input.action_release("jump")
	Input.action_release("crouch")
