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
var player: Player = null
var boss: BossWarden = null


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	level = main.get_node("WardenArena")
	player = main.get_node("Player") as Player
	boss = level.get_node_or_null("Warden") as BossWarden

	print("\n==== WARDEN PROBE ====")
	_surfaces()
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
	print("  -- what the deck is worth")
	player.global_position = Vector3(-30, 8.4, 6)
	player.velocity = Vector3.ZERO
	player._set_state(Player.State.GROUND)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Walk off the edge and read the power at the moment before landing.
	player.global_position = Vector3(-21, 8.4, 6)
	player.velocity = Vector3.ZERO
	player._set_state(Player.State.AIR)
	var best := 0.0
	for i in 60:
		await get_tree().physics_frame
		best = maxf(best, player.slam_power())
		if player.is_on_floor():
			break
	_note("slam_power from the deck", best >= boss.crack_power,
		"%.2f against crack_power %.2f" % [best, boss.crack_power])


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

	# --- the spin is refused, and says so.
	var hints: Array[String] = []
	Events.boss_refused.connect(func(_b: Node3D, h: String) -> void: hints.append(h))
	boss.spin_hit(player)
	await get_tree().physics_frame
	_note("the spin is refused with a hint",
		hints.size() == 1 and hints[0].length() > 0 and boss.phase == BossWarden.Phase.ARMOURED,
		"hint=%s" % (hints[0] if hints.size() > 0 else "none"))

	# --- a pound while armoured is refused too, however hard.
	hints.clear()
	Events.slam_landed.emit(boss.global_position, 1.0)
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
	Events.slam_landed.emit(boss.global_position, 1.0)
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
