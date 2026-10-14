extends Node

## THROWAWAY probe for the rail yard. Delete once the level settles.
##
## Follows tests/fort_probe.gd: it states the expected value and lets the probe
## do the comparing, because reading twenty numbers and trusting yourself is how
## the tree fort ended up with two staircases running under the deck.
##
## The rail checks matter more than the box checks. A rail's curve points are in
## the RAIL'S local space, so every rail question has a to_local/to_global in it
## (see grind_rail.gd), and getting one of those wrong puts the rail somewhere
## near the level origin while the data on disk looks perfectly correct.

const MAIN := preload("res://scenes/rail_yard_main.tscn")

var failures: int = 0


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	# Two frames: one for the tree to settle, one for CSG to build its meshes
	# and collision, which a ray needs to be able to hit.
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var level: Node3D = main.get_node("RailYard")
	print("\n==== RAIL YARD PROBE ====")

	_surfaces(level)
	_rails(level)
	_rail_meshes(level)

	print("  -- running off the deck on to each rail, for real")
	var player := main.get_node("Player") as Player
	if player != null:
		for pair in [["RailDownhill", -12.0], ["RailFlat", 0.0],
				["RailUphill", 12.0], ["RailCurved", 24.0]]:
			await _run_on(level, player, pair[0], pair[1])

	print("---- %d wrong ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Drops a short ray onto a surface and compares the height it finds.
##
## The ray starts just ABOVE the expected top and only reaches a little way
## down, deliberately: a ray cast from the sky reports whatever is topmost at
## that x,z, so anything with something else above it reads back the wrong one.
func _floor_at(label: String, x: float, z: float, expected: float) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var from := Vector3(x, expected + 1.5, z)
	var to := Vector3(x, expected - 1.5, z)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		failures += 1
		print("  %-26s expected %6.2f  got NOTHING          *** WRONG ***" % [label, expected])
		return
	var got: float = hit["position"].y
	_compare(label, got, expected, 0.05)


func _compare(label: String, got: float, expected: float, tolerance: float) -> void:
	var ok := absf(got - expected) <= tolerance
	if not ok:
		failures += 1
	print("  %-26s expected %7.2f  got %7.2f  %s"
		% [label, expected, got, "" if ok else "*** WRONG ***"])


func _point(label: String, got: Vector3, expected: Vector3, tolerance: float) -> void:
	var ok := got.distance_to(expected) <= tolerance
	if not ok:
		failures += 1
	print("  %-26s expected %-22s got %-22s %s"
		% [label, "(%.1f, %.1f, %.1f)" % [expected.x, expected.y, expected.z],
			"(%.1f, %.1f, %.1f)" % [got.x, got.y, got.z], "" if ok else "*** WRONG ***"])


func _surfaces(level: Node3D) -> void:
	print("  -- surfaces you stand on")
	# Probed well away from the stairs and the rails so nothing else is in the
	# way of the ray.
	_floor_at("ground", 60.0, 60.0, 0.0)
	_floor_at("start deck", 4.0, -47.0, 8.0)
	# Every step top, which should climb by exactly 0.8 and arrive at the deck.
	for i in 10:
		var top := 0.8 * float(i + 1)
		var x := -39.4 + 1.2 * float(i)
		_floor_at("step %d top" % i, x, -47.0, top)


func _rails(level: Node3D) -> void:
	print("  -- rails: world endpoints, length and grade")
	# `point_at` includes the rail's ride_height (0.5), because that is where the
	# player's feet go — so every expected y below is the curve's y plus 0.5.
	var cases := [
		["RailDownhill", Vector3(-12, 7.9, -42), Vector3(-12, 1.1, 0), 42.55, -0.160],
		["RailFlat", Vector3(0, 7.9, -42), Vector3(0, 7.9, 10), 52.0, 0.0],
		["RailUphill", Vector3(12, 7.9, -42), Vector3(12, 12.1, 0), 42.21, 0.099],
		["RailCurved", Vector3(24, 7.9, -42), Vector3(24, 3.1, 6), 49.81, -0.096],
	]
	for case in cases:
		var name: String = case[0]
		var rail := level.get_node_or_null(name) as GrindRail
		if rail == null:
			failures += 1
			print("  %-26s MISSING                                  *** WRONG ***" % name)
			continue
		_point("%s start" % name, rail.point_at(0.0), case[1], 0.1)
		_point("%s end" % name, rail.point_at(rail.length()), case[2], 0.15)
		_compare("%s length" % name, rail.length(), case[3], 0.4)
		# The grade halfway along, as the y part of the unit tangent. This is the
		# number _do_grind() multiplies by slope_gravity, so if it has the wrong
		# sign the rail accelerates the wrong way.
		var mid := rail.length() * 0.5
		_compare("%s grade at midpoint" % name, rail.tangent_at(mid).y, case[4], 0.03)

	print("  -- the deck edge is close enough to catch a rail")
	# The deck's far edge is z = -42, and the rails start there. Running off it
	# should put the player within grind_snap_distance of the rail almost at
	# once, or the grind simply never triggers and looks broken.
	var flat := level.get_node_or_null("RailFlat") as GrindRail
	if flat != null:
		var at_edge := Vector3(0, 8.0, -41.5)
		_compare("rail distance at deck edge", flat.distance_to_rail(at_edge), 0.1, 0.6)


## Actually runs the player off the deck on to each rail.
##
## The geometry checks above say the rails are where they should be; this says
## the handoff WORKS — that the gap between the deck edge and the rail is inside
## `grind_snap_distance` once you have fallen across it. That margin is the one
## number here that arithmetic on its own got close to wrong.
##
## Velocity is set directly rather than pressing move_forward, because which way
## "forward" is depends on where the camera happens to be looking, and a probe
## should not be able to fail for that reason.
func _run_on(level: Node3D, player: Player, rail_name: String, x: float) -> void:
	player.global_position = Vector3(x, 8.2, -44.0)
	player.velocity = Vector3(0, 0, 12)
	player._grind_lock = 0.0
	player._set_state(Player.State.GROUND)
	var caught := ""
	for i in 40:
		await get_tree().physics_frame
		if player.state == Player.State.GRIND and player._rail != null:
			caught = player._rail.name
			break
	if caught != rail_name:
		failures += 1
		print("  %-26s expected to catch %-14s got %-14s *** WRONG ***"
			% ["run on to " + rail_name, rail_name, caught if caught != "" else "nothing"])
		return
	var entry: float = absf(player._rail_speed)
	for i in 120:
		await get_tree().physics_frame
		if player.state != Player.State.GRIND:
			break
	var ended: float = absf(player._rail_speed)
	print("  %-26s caught it at %5.1f m/s, left at %5.1f m/s (%s)"
		% ["run on to " + rail_name, entry, ended, player.state_name()])


## Does the rail MODEL sit where the grind line is?
##
## Measured rather than eyeballed, and measured against the curve itself rather
## than against hand-typed numbers: the expected box is built by sampling the
## curve and converting each sample to world space, which is exactly what the
## player rides. So if these two boxes do not coincide, the thing you can see
## and the thing you can stand on are in different places.
func _rail_meshes(level: Node3D) -> void:
	print("  -- does the rail model sit on the grind line?")
	for rail_name in ["RailDownhill", "RailFlat", "RailUphill", "RailCurved"]:
		var rail := level.get_node_or_null(rail_name) as GrindRail
		if rail == null or rail.curve == null:
			failures += 1
			print("  %-26s MISSING *** WRONG ***" % rail_name)
			continue
		var mesh := rail.get_node_or_null("Visual") as CSGPolygon3D
		if mesh == null:
			failures += 1
			print("  %-26s has no Visual *** WRONG ***" % rail_name)
			continue
		var total := rail.length()
		var want := AABB(rail.to_global(rail.curve.sample_baked(0.0)), Vector3.ZERO)
		for i in 41:
			want = want.expand(rail.to_global(rail.curve.sample_baked(total * float(i) / 40.0)))
		var got := mesh.global_transform * mesh.get_aabb()
		var drift := got.get_center().distance_to(want.get_center())
		var ok := drift <= 0.5
		if not ok:
			failures += 1
		print("  %-26s line centre (%.1f, %.1f, %.1f)  model centre (%.1f, %.1f, %.1f)  off by %.1f m  %s"
			% [rail_name, want.get_center().x, want.get_center().y, want.get_center().z,
				got.get_center().x, got.get_center().y, got.get_center().z, drift,
				"" if ok else "*** WRONG ***"])
