extends Node

## THROWAWAY probe for the hostage pit. Delete once the level settles.
##
## The claim this level rests on is "the upper deck is reachable ONLY by the
## platform". If that is wrong the whole experiment is meaningless, because an
## enemy holding the seed would not be holding anything. So most of this is
## about that: how far up the deck is, that nothing is in between, and that the
## platform's travel actually arrives at deck height rather than near it.
##
## The last section drops the seed in the pit for real and watches the platform
## rise, because arithmetic agreeing with itself is not the same as the thing
## working.

const MAIN := preload("res://scenes/hostage_pit_main.tscn")

var failures: int = 0


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var level: Node3D = main.get_node("HostagePit")
	print("\n==== HOSTAGE PIT PROBE ====")
	_surfaces()
	_unreachable(level)
	await _delivery(level)
	print("---- %d wrong ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _compare(label: String, got: float, expected: float, tolerance: float) -> void:
	var ok := absf(got - expected) <= tolerance
	if not ok:
		failures += 1
	print("    %-30s expected %7.2f  got %7.2f  %s"
		% [label, expected, got, "" if ok else "*** WRONG ***"])


func _floor_at(label: String, x: float, z: float, expected: float) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var from := Vector3(x, expected + 1.5, z)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0))
	if hit.is_empty():
		failures += 1
		print("    %-30s expected %7.2f  got NOTHING  *** WRONG ***" % [label, expected])
		return
	_compare(label, hit["position"].y, expected, 0.1)


func _surfaces() -> void:
	print("  -- surfaces")
	_floor_at("south floor", 0.0, -20.0, 0.0)
	_floor_at("north floor", 0.0, 20.0, 0.0)
	_floor_at("pit floor", 0.0, 0.0, -5.0)
	# Probed off to the side of the chest and the exit, so the ray does not land
	# on a prop and report its lid as the floor.
	_floor_at("upper deck", 7.0, 20.0, 12.0)


func _unreachable(level: Node3D) -> void:
	print("  -- the deck is only reachable by the platform")
	# Straight up from the north floor, directly under the deck. Anything in the
	# way would be a shortcut, and the gap is what the platform has to cover.
	var space := get_viewport().world_3d.direct_space_state
	var from := Vector3(7, 0.5, 20)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 30.0))
	if hit.is_empty():
		failures += 1
		print("    nothing overhead at all  *** WRONG ***")
	else:
		# 11, not 12: a ray cast UPWARDS hits the deck's UNDERSIDE, and the deck is
		# 1 m thick. The walkable top is at 12, which the floor probe above checks
		# separately. Getting this wrong first time is why the probe states its
		# expectations instead of printing numbers to be eyeballed.
		_compare("deck underside overhead", hit["position"].y, 11.0, 0.1)

	# The platform's travel has to ARRIVE at deck height. Computed from the real
	# nodes rather than from the numbers I typed into the scene, so a change to
	# either one is caught.
	var platform := level.get_node_or_null("Platform") as MovingPlatform
	if platform == null:
		failures += 1
		print("    platform MISSING  *** WRONG ***")
		return
	var box := (platform.shape.shape as BoxShape3D)
	var top_now := platform.global_position.y + box.size.y * 0.5
	_compare("platform top, parked", top_now, 0.6, 0.05)
	_compare("platform top, at the apex", top_now + platform.travel.y, 12.0, 0.1)
	# And it must be off until the seed arrives, or there is no hostage to take.
	if platform.active:
		failures += 1
	print("    platform starts inactive=%s %s"
		% [not platform.active, "" if not platform.active else "*** WRONG ***"])


func _delivery(level: Node3D) -> void:
	print("  -- dropping the seed in the pit for real")
	var seed := level.get_node_or_null("Seed") as PlatformSeed
	var platform := level.get_node_or_null("Platform") as MovingPlatform
	if seed == null or platform == null:
		failures += 1
		print("    seed or platform MISSING  *** WRONG ***")
		return
	# Put it straight over the trench and let go.
	# Recorded from the signal as it fires. A consumed seed shrinks and frees
	# itself, so asking it anything afterwards is an "Invalid call ... on a base
	# object of type 'previously freed'" — the same trap as reading a thrown
	# walker after it bursts. An Array is captured rather than a bool because
	# GDScript lambdas capture locals by VALUE.
	var eaten: Array[bool] = []
	seed.consumed.connect(func() -> void: eaten.append(true))
	seed.global_position = Vector3(0, 2, 0)
	seed.linear_velocity = Vector3.ZERO
	for i in 90:
		await get_tree().physics_frame
		if platform.active:
			break
	if not platform.active or eaten.is_empty():
		failures += 1
	print("    platform activated=%s, seed consumed=%s %s"
		% [platform.active, not eaten.is_empty(),
			"" if platform.active and not eaten.is_empty() else "*** WRONG ***"])

	# Then watch it actually climb to the deck.
	var high := platform.global_position.y
	for i in 420:
		await get_tree().physics_frame
		high = maxf(high, platform.global_position.y)
	var box := (platform.shape.shape as BoxShape3D)
	_compare("highest top it reached", high + box.size.y * 0.5, 12.0, 0.25)
