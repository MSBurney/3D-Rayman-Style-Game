extends Node

## THROWAWAY probe for the warden fight. Delete once the boss settles.
##
## The geometry checks are the usual kind. The part that matters is the end:
## it drives the boss through all three phases in the real arena and asserts
## each transition, because "three locks, each opened by a different verb" is a
## claim about a SEQUENCE, and every piece of it can work while the sequence
## does not.
##
## It also measures what a drop from the pound deck is actually worth against
## `crack_power`, rather than trusting the arithmetic in the arena's comment.

const MAIN := preload("res://scenes/warden_arena_main.tscn")

var failures: int = 0
var level: Node3D = null
var player: HeavyPlayer = null
var boss: BossWarden = null


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	level = main.get_node("WardenArena")
	player = main.get_node("Player") as HeavyPlayer
	boss = level.get_node_or_null("Warden") as BossWarden

	print("\n==== WARDEN PROBE ====")
	_surfaces()
	await _softlock()
	await _pound_worth()
	await _fight()
	print("---- %d wrong ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _note(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("    %-34s %s  %s" % [label, detail, "" if ok else "*** WRONG ***"])


func _compare(label: String, got: float, expected: float, tolerance: float) -> void:
	_note(label, absf(got - expected) <= tolerance,
		"expected %.2f got %.2f" % [expected, got])


## The surface height at x,z, or NAN. Started just ABOVE the surface being
## asked about and given a short reach, because a ray cast from the sky reports
## whatever is topmost — so any deck with another deck above it reads back the
## wrong one.
func _ray_down(x: float, z: float, from_y: float) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var from := Vector3(x, from_y, z)
	var hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0))
	if hit.is_empty():
		return NAN
	return hit["position"].y


func _floor_at(label: String, x: float, z: float, expected: float) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var from := Vector3(x, expected + 1.5, z)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0))
	if hit.is_empty():
		_note(label, false, "expected %.2f got NOTHING" % expected)
		return
	_compare(label, hit["position"].y, expected, 0.1)


func _surfaces() -> void:
	print("  -- the arena")
	_floor_at("arena floor", 20.0, -20.0, 0.0)
	_floor_at("pound deck top", -30.0, 6.0, 8.0)
	_floor_at("exit deck top", 6.0, 38.0, 12.0)
	# The pillar beside the deck is what makes phase two reachable: you lure the
	# boss into it while you are already standing up high.
	_floor_at("pillar by the deck", -18.0, 0.0, 6.0)
	var platform := level.get_node_or_null("Platform") as MovingPlatform
	if platform == null:
		_note("platform", false, "MISSING")
		return
	var box := platform.shape.shape as BoxShape3D
	var top := platform.global_position.y + box.size.y * 0.5
	_compare("platform top at the apex", top + platform.travel.y, 12.0, 0.15)


## What is a drop from the deck actually worth? slam_power() is fall/12.
func _pound_worth() -> void:
	# ── the ramps that replaced the stairs ──
	#
	# Checked against the line the scene comment states — y = 4 + 0.4 * (z + 30)
	# — at three separate z, because two points can agree by accident and three
	# cannot. A hand-authored rotation has come out wrong every single time this
	# project has written one, and a ramp tilted the wrong way looks completely
	# fine until something measures the surface.
	print("  -- the ramps up to the pound decks")
	for x: float in [-30.0, 26.28]:
		for z: float in [-38.0, -30.0, -22.0]:
			_floor_at("ramp at x %.0f, z %.0f" % [x, z], x, z,
				4.0 + 0.4 * (z + 30.0))

	# The ANGLE, which is the number that decides whether the ramp is usable at
	# all: over about 27 degrees the slope pull beats `deceleration` and you
	# slide back down standing still; under about 7 momentum stops building.
	var ramp_low := _ray_down(-30.0, -38.0, 3.0)
	var ramp_high := _ray_down(-30.0, -22.0, 10.0)
	if is_nan(ramp_low) or is_nan(ramp_high):
		_note("the ramp is climbable, not a slide", false, "could not measure it")
	else:
		var angle := rad_to_deg(atan((ramp_high - ramp_low) / 16.0))
		_note("the ramp is climbable, not a slide",
			angle < 27.0 and angle > 7.0,
			"%.1f degrees: under 27 where you would slide, over 7 where momentum stops building" % angle)

	print("  -- what the deck is worth")
	player.global_position = Vector3(-30, 8.4, 6)
	player.velocity = Vector3.ZERO
	player._set_state(HeavyPlayer.State.WALK)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Walk off the edge and read the power at the moment before landing.
	player.global_position = Vector3(-21, 8.4, 6)
	player.velocity = Vector3.ZERO
	player._set_state(HeavyPlayer.State.AIR)
	var best := 0.0
	for i in 60:
		await get_tree().physics_frame
		best = maxf(best, player.slam_power())
		if player.is_on_floor():
			break
	# **`slam_power()` is NOT what the boss compares against**, and reading it as
	# though it were is the same bug as the threshold being checked. It returns
	# the DROP half alone, on a 0..1 scale. What `Events.slam_landed` actually
	# carries is `(drop + horizontal delivered) * impact_force_scalar` — two
	# extra terms and a doubling.
	#
	# So the force is rebuilt here the way the controller builds it, and the
	# check states the DESIGN CLAIM rather than a number: a standing drop off
	# the deck is not enough, and a charge off it is. That is what keeps the
	# pound deck load-bearing instead of being beaten by a flat-ground charge.
	var standing := best * player.impact_force_scalar
	var charging := (best + player.charge_top_speed * player.brake_impact_scalar) \
		* player.impact_force_scalar
	_note("a standing drop off the deck is not enough",
		standing < boss.crack_power,
		"%.2f against crack_power %.2f" % [standing, boss.crack_power])
	_note("...but a charge off the deck cracks it",
		charging >= boss.crack_power,
		"%.2f against crack_power %.2f" % [charging, boss.crack_power])


## **A regression test for a reported softlock, and the reason it is worth one.**
##
## The boss ends a charge flush against a wall that is not a pillar, winds up
## again, and `_aim_at_player()` points straight back INTO the surface it is
## already touching — so it charges into the same wall for ever, from zero
## distance, never moving. Reported from play as "it gets stuck and constantly
## loops its charging state, but never moves and I can't kill it".
##
## And you cannot kill it, correctly: this boss is beaten by taking the seed,
## not by damage. But wedged like that it can never be lured into a pillar
## either, so phase one becomes unwinnable — a softlock in a fight whose entire
## design is "no death, no timer". `_bounce_off()` is the fix.
func _softlock() -> void:
	print("  -- a charge into something that is NOT a pillar")
	boss._set_phase(BossWarden.Phase.ARMOURED)
	# Pressed against the west outer wall at x = -44.5, with the player placed
	# BEYOND it so the aim points into the wall every single cycle. That is the
	# exact geometry that pinned it.
	boss.global_position = Vector3(-42.0, 1.0, 10.0)
	boss.velocity = Vector3.ZERO
	player.global_position = Vector3(-70.0, 1.0, 10.0)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var from := boss.global_position

	# Long enough for several wind-up-charge-crash cycles at the defaults.
	for i in 420:
		await get_tree().physics_frame
	var moved := boss.global_position.distance_to(from)
	_note("it backs off instead of pinning itself", moved > 3.0,
		"it travelled %.1f m in about 7 s of charging at a wall" % moved)
	_note("...and it is still in a phase that can be lured",
		boss.phase == BossWarden.Phase.ARMOURED,
		"phase=%s" % BossWarden.Phase.keys()[boss.phase])

	# It must NOT have stunned itself on the outer wall: only pillars do that,
	# or the boss does phase one for the player.
	_note("the outer wall still does not stun it",
		boss.phase != BossWarden.Phase.STUNNED,
		"phase=%s" % BossWarden.Phase.keys()[boss.phase])


## Drives the whole fight: armoured, stunned, cracked, beaten.
func _fight() -> void:
	print("  -- the three phases, in order")
	var seed := level.get_node_or_null("Seed") as PlatformSeed
	var platform := level.get_node_or_null("Platform") as MovingPlatform
	if seed == null or platform == null:
		_note("seed / platform", false, "MISSING")
		return

	_note("starts armoured, holding the seed",
		boss.phase == BossWarden.Phase.ARMOURED and boss.snatcher.held == seed,
		"phase=%s held=%s" % [BossWarden.Phase.keys()[boss.phase], boss.snatcher.held != null])

	# --- a pound while armoured is refused, however hard, and says what to do.
	#
	# There used to be a check above this for the SPIN being refused. The spin
	# is gone with the old controller, and the boss deliberately does not join
	# the `strikable` group in its place — see the note in boss_warden.gd.
	var hints: Array[String] = []
	Events.boss_refused.connect(func(_b: Node3D, h: String) -> void: hints.append(h))
	Events.slam_landed.emit(boss.global_position, 3.6)
	await get_tree().physics_frame
	_note("a pound on the armour is refused",
		hints.size() == 1 and boss.phase == BossWarden.Phase.ARMOURED,
		"phase=%s hint=%s" % [BossWarden.Phase.keys()[boss.phase],
			hints[0] if hints.size() > 0 else "none"])

	# --- charge it into the pillar at x=-18, z=0. The boss locks its direction
	# at the start of a charge and never corrects, so standing the player on the
	# far side of a pillar is enough to make it crash.
	boss.global_position = Vector3(-18, 0.2, -10)
	player.global_position = Vector3(-18, 1.0, 10)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	# Re-entered so it picks a FRESH direction. Without this it is still part way
	# through the charge it began before being moved, running on an aim at where
	# the player used to be. That took a while to spot, because the boss was
	# behaving perfectly and the probe was not.
	boss._set_phase(BossWarden.Phase.ARMOURED)
	for i in 300:
		await get_tree().physics_frame
		if boss.phase == BossWarden.Phase.STUNNED:
			break
	_note("charging into a pillar stuns it",
		boss.phase == BossWarden.Phase.STUNNED,
		"phase=%s" % BossWarden.Phase.keys()[boss.phase])
	if boss.phase != BossWarden.Phase.STUNNED:
		return

	# --- a weak pound on the stunned boss is still refused: right move, wrong
	# height. That near miss is the most useful hint in the fight.
	hints.clear()
	Events.slam_landed.emit(boss.global_position, boss.crack_power * 0.4)
	await get_tree().physics_frame
	_note("a weak pound is refused, not ignored",
		hints.size() == 1 and boss.phase == BossWarden.Phase.STUNNED,
		"phase=%s hint=%s" % [BossWarden.Phase.keys()[boss.phase],
			hints[0] if hints.size() > 0 else "none"])

	# --- a proper pound cracks it, and it drops the seed.
	Events.slam_landed.emit(boss.global_position, 3.6)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_note("a hard pound cracks it open and the seed drops",
		boss.phase == BossWarden.Phase.CRACKED and boss.snatcher.held == null
			and not seed.is_held(),
		"phase=%s held=%s seed_held=%s" % [BossWarden.Phase.keys()[boss.phase],
			boss.snatcher.held != null, seed.is_held()])

	# --- deliver it. Beating this boss is a DELIVERY, not a kill: the hostage
	# system is its health bar.
	seed.global_position = Vector3(0, 1.2, 30)
	seed.linear_velocity = Vector3.ZERO
	for i in 120:
		await get_tree().physics_frame
		if boss.phase == BossWarden.Phase.BEATEN:
			break
	_note("delivering the seed beats it and raises the platform",
		boss.phase == BossWarden.Phase.BEATEN and platform.active,
		"phase=%s platform_active=%s" % [BossWarden.Phase.keys()[boss.phase],
			platform.active])
