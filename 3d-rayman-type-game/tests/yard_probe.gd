extends Node

## THROWAWAY probe for the showcase yard. Delete once the level settles.
##
## It exists because of a rule this project has earned the hard way: **every
## single time geometry has been placed by hand here, something has been wrong
## in a way the eye could not see.** Two playground ramps tilted the wrong way,
## fixtures spawned off the edge of a pad, and two whole staircases in the tree
## fort that ran underneath the deck they were supposed to reach.
##
## So nothing in `heavy_yard.tscn` is believed until it is measured, and the
## probe STATES THE EXPECTED VALUE rather than printing readings to be eyeballed
## — twenty numbers you have to check yourself is not a test.
##
## Three rules this follows, all of them paid for:
##
##   - Start each ray just ABOVE the surface it asks about, with a short reach.
##     Casting from the sky reports whatever is topmost at that x,z, so any deck
##     with another deck above it reads back the wrong one.
##   - Never cast through the prop being asked about. A chest is a StaticBody3D
##     on the world layer, so a ray dropped on to it reports "the floor is one
##     metre up". Probe BESIDE it.
##   - Measure the design claims, not just the heights. A level whose surfaces
##     are all correct can still have a gap that the wrong verb clears.

const MAIN := preload("res://scenes/main.tscn")
## tan(15 degrees). The ramp's whole geometry is checked against this one line,
## because the basis was copied from the greybox and copying is exactly the kind
## of thing that silently goes wrong.
const RAMP_TAN := 0.26795

var failures: int = 0
var level: Node3D = null
var player: HeavyPlayer = null


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	level = main.get_node_or_null("HeavyYard") as Node3D
	player = main.get_node_or_null("Player") as HeavyPlayer

	print("\n==== HEAVY YARD PROBE ====")
	if level == null or player == null:
		_note("main.tscn loads the yard and the modal player", false,
			"HeavyYard=%s Player=%s" % [level != null, player != null])
		print("---- %d wrong ----" % failures)
		get_tree().quit(1)
		return

	_surfaces()
	_the_ramp()
	_the_holes()
	_the_gap()
	_the_rail()
	_the_tower_chain()
	_the_thresholds()
	_the_money()
	print("---- %d wrong ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _note(label: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("    %-46s %s %s" % [label, detail, "" if ok else "  *** WRONG ***"])


func _compare(label: String, got: float, expected: float, tolerance: float) -> void:
	var ok := absf(got - expected) <= tolerance
	if not ok:
		failures += 1
	print("  %-34s expected %7.2f  got %7.2f %s"
		% [label, expected, got, "" if ok else "  *** WRONG ***"])


## Drops a short ray on to whatever is at x,z and returns the surface height, or
## NAN for nothing there. `from_y` starts the ray just above the surface being
## asked about, which is what stops an upper deck answering for a lower one.
func _height_at(x: float, z: float, from_y: float = 3.0) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, from_y, z)
	var to := Vector3(x, from_y - 14.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


func _surface(label: String, x: float, z: float, expected: float,
		from_y: float = 3.0) -> void:
	var got := _height_at(x, z, from_y)
	if is_nan(got):
		failures += 1
		print("  %-34s expected %7.2f  got nothing   *** WRONG ***"
			% [label, expected])
		return
	_compare(label, got, expected, 0.06)


## Every slab is authored as a TOP height, so every one of them is asked for by
## that number. `origin y = top - size.y / 2` is the authoring rule and this is
## the only thing that proves it was followed.
func _surfaces() -> void:
	print("  -- the surfaces you stand on")
	_surface("ground, at the spawn", 0.0, 10.0, 0.0)
	_surface("ground, west", -50.0, 0.0, 0.0)
	_surface("ground, east", 50.0, 0.0, 0.0)
	_surface("ground, north edge", 0.0, -43.0, 0.0)
	_surface("ground north, across the trench", 0.0, -80.0, 0.0)
	_surface("the south island", 0.0, 70.0, 0.0)
	_surface("the ramp deck", -20.0, -36.0, 8.0, 11.0)
	_surface("the tower top", 24.0, -10.0, 14.0, 17.0)
	_surface("the tower landing", 29.5, -10.0, 14.0, 17.0)
	# Probed BESIDE each vault, never through it: a chest and a breakable block
	# are both StaticBody3D on the world layer and would answer for the floor.
	_surface("inside the ramp vault", -20.0, 11.0, 0.0, 2.4)
	_surface("inside the mass vault", -40.0, -90.0, 0.0, 2.4)


## The one piece of hand-authored rotation in the level, and the only thing in
## this file that could be wrong in a way nothing else would reveal.
##
## Godot serialises a Transform3D basis ROW by row, so a basis read as columns
## builds a ramp tilted the wrong way — and it looks completely fine until you
## measure the surface. Checked at three separate z against the formula, because
## two points can agree by accident and three cannot.
func _the_ramp() -> void:
	print("  -- the ramp: 15 degrees, y = 4 at z = -15")
	for z in [-5.0, -15.0, -25.0]:
		var expected := 4.0 + RAMP_TAN * (-15.0 - z)
		_surface("ramp top at z = %.0f" % z, -20.0, z, expected, expected + 3.0)

	# The ramp has to MEET the ground and the deck, not stop short of either. A
	# lip at the bottom stops a charge dead, which would delete problem 1.
	var foot := _height_at(-20.0, 0.5, 3.0)
	_note("the ramp meets the ground at its foot",
		not is_nan(foot) and absf(foot) < 0.25, "%.2f m at z = 0.5" % foot)
	var crest := _height_at(-20.0, -30.5, 11.0)
	_note("the ramp meets the deck at its crest",
		not is_nan(crest) and absf(crest - 8.0) < 0.3,
		"%.2f m against the deck's 8.0" % crest)


## **No death means no bottomless anything.** Every hole gets a floor and a
## staircase, or falling in is travel time rather than a live penalty — which
## the doc bans outright.
func _the_holes() -> void:
	print("  -- every hole has a floor and a way out")
	_surface("the trench floor", 0.0, -57.0, -6.0, -3.0)
	_surface("the gap floor", 0.0, 44.0, -6.0, -3.0)

	# Walked as a sequence, because a staircase whose steps are individually
	# correct can still have one step too tall to climb. 0.8 m is the step; the
	# player is 1.4 m, so anything over about 1.0 stops being a step.
	for pair in [["the trench stairs", 50.0, -45.75, -1.5],
			["the gap stairs", 25.0, 35.75, 1.5]]:
		var label: String = pair[0]
		var x: float = pair[1]
		var z0: float = pair[2]
		var step_z: float = pair[3]
		var worst := 0.0
		var last := 0.0
		var missing := -1
		for i in 7:
			var h := _height_at(x, z0 + step_z * float(i), 2.0)
			if is_nan(h):
				missing = i
				break
			worst = maxf(worst, absf(h - last))
			last = h
		if missing >= 0:
			_note(label, false, "step %d is not there" % (missing + 1))
		else:
			_note(label, worst <= 1.0 and absf(last - (-5.6)) < 0.3,
				"biggest rise %.2f m, bottom step at %.2f" % [worst, last])

	# The span's tops have to be FLUSH with the ground. A crumbling slab standing
	# proud is a kerb, and a kerb across a bridge is where a charge dies.
	for z in [-47.5, -52.5, -57.5, -62.5, -67.5]:
		_surface("span slab at z = %.1f" % z, -40.0, z, 0.0)


## Problem 2, stated as the measurement that makes it a problem at all.
func _the_gap() -> void:
	print("  -- the gap: wider than a walking jump, inside a charge-jump")
	# Found by walking south until the floor runs out, rather than trusting the
	# numbers in the scene file — the whole point of a probe.
	var near := NAN
	for i in 200:
		var z := 30.0 + float(i) * 0.25
		if is_nan(_height_at(0.0, z, 3.0)):
			near = z
			break
	var far := NAN
	if not is_nan(near):
		for i in 400:
			var z := near + float(i) * 0.25
			if not is_nan(_height_at(0.0, z, 3.0)):
				far = z
				break
	if is_nan(near) or is_nan(far):
		_note("there is a gap at all", false,
			"near edge %.1f, far edge %.1f" % [near, far])
		return
	var width := far - near
	_compare("the gap's width", width, 18.0, 0.6)
	# The two numbers it has to sit between, both measured in the greybox.
	_note("a walking jump cannot clear it", width > 15.5,
		"%.1f m against a walking jump's 15.5" % width)
	_note("a charge-jump can", width < 21.2,
		"%.1f m against a charge-jump's 21.2" % width)

	# And the trench must be out of reach of BOTH, or the span is decoration.
	var t_near := NAN
	for i in 200:
		var z := -40.0 - float(i) * 0.25
		if is_nan(_height_at(0.0, z, 3.0)):
			t_near = z
			break
	var t_far := NAN
	if not is_nan(t_near):
		for i in 400:
			var z := t_near - float(i) * 0.25
			if not is_nan(_height_at(0.0, z, 3.0)):
				t_far = z
				break
	var trench := absf(t_far - t_near) if not is_nan(t_far) else NAN
	_note("the trench is wider than any jump",
		not is_nan(trench) and trench > 21.2,
		"%.1f m against a charge-jump's 21.2" % trench)


## The rail's head has to be catchable from the deck, and its mesh has to sit on
## the line you actually grind — a CSGPolygon3D in Path mode bakes the path in
## WORLD space unless `path_local` is true, which once put the rail you could
## see 44 m from the rail you could grind.
func _the_rail() -> void:
	print("  -- the rail: catchable from the deck, and drawn where it is")
	var rail := level.get_node_or_null("Rail") as GrindRail
	if rail == null:
		_note("the rail is in the level", false, "Rail missing")
		return
	var head := rail.point_at(0.0)
	var tail := rail.point_at(rail.length())
	_compare("the rail's head height", head.y, 7.9, 0.1)
	_compare("the rail drops this far", head.y - tail.y, 4.5, 0.1)

	# The deck edge, measured rather than assumed. The rail yard's working value
	# for this distance is 0.10 m.
	var edge := Vector3(-13.0, 8.0, -36.0)
	var gap := rail.distance_to_rail(edge)
	_note("the deck edge can catch the rail", gap < 1.2,
		"%.2f m from the deck edge to the line" % gap)

	var mesh_centre := Vector3.INF
	for child in rail.get_children():
		var m := child as GeometryInstance3D
		if m != null:
			mesh_centre = m.global_transform * m.get_aabb().get_center()
			break
	if mesh_centre != Vector3.INF:
		var line_centre := rail.point_at(rail.length() * 0.5)
		_note("the rail model sits on the grind line",
			mesh_centre.distance_to(line_centre) < 2.0,
			"model %.1f m from the line" % mesh_centre.distance_to(line_centre))


## Problem 3 is the only three-step one, so it is the only one where the pieces
## have to line up with each other rather than just exist.
func _the_tower_chain() -> void:
	print("  -- ram, ride, slam: the three pieces have to meet")
	var plate := level.get_node_or_null("Plate") as PressurePlate
	var lift := level.get_node_or_null("PlateLift") as MovingPlatform
	var crate := level.get_node_or_null("PlateCrate") as RigidBody3D
	var lid := level.get_node_or_null("SealedLid") as BreakableBlock
	if plate == null or lift == null or crate == null or lid == null:
		_note("the four pieces are in the level", false,
			"plate=%s lift=%s crate=%s lid=%s" % [plate != null, lift != null,
				crate != null, lid != null])
		return

	# The crate is the ONLY answer to the plate, and that is two numbers: it has
	# to be heavier than the plate wants, and heavier than the hero can lift.
	_note("the plate wants more than the hero weighs",
		plate.required_mass > player.mass,
		"plate %.0f against the hero's %.0f" % [plate.required_mass, player.mass])
	_note("the crate is heavy enough to hold it",
		crate.mass >= plate.required_mass,
		"crate %.0f against the plate's %.0f" % [crate.mass, plate.required_mass])
	_note("...and too heavy to carry, so it must be rammed",
		crate.mass > player.carry_max_mass,
		"crate %.0f against carry_max_mass %.0f"
			% [crate.mass, player.carry_max_mass])

	# A lift that arrives NEARLY at the tower top is a lip you fall off. This is
	# the check the greybox's plate deck earned.
	var lift_top := lift.global_position.y + 0.3 + lift.travel.y
	_compare("the lift arrives at tower-top height", lift_top, 14.0, 0.1)
	var landing := _height_at(29.5, -10.0, 17.0)
	_note("and it arrives on to something",
		not is_nan(landing) and absf(landing - 14.0) < 0.1,
		"the landing is at %.2f" % landing)
	# Across, not up: the lift has to be close enough to the tower that stepping
	# off is a step rather than a jump.
	var across := absf(lift.global_position.x - 28.0)
	_note("the lift is beside the tower, not stranded",
		across <= 4.0, "%.1f m from the tower's east face" % across)

	# And the drop has to be worth more than the lid asks. 14 m gives a force of
	# 2.0, which at slam_scatter_power 70 is 140 of momentum.
	var from_tower: float = 70.0 * 2.0
	_note("a slam from the tower beats the lid's threshold",
		from_tower > lid.strike_momentum,
		"%.0f of momentum against the lid's %.0f"
			% [from_tower, lid.strike_momentum])
	_note("...and a hop-stomp does not", 7.0 < lid.strike_momentum,
		"a hop is worth 7 against %.0f" % lid.strike_momentum)


## Each problem is one threshold, and a threshold that does not separate the two
## verbs either side of it is not a problem — it is a wall or a door.
func _the_thresholds() -> void:
	print("  -- every threshold separates two verbs")
	var ramp_wall := level.get_node_or_null("RampWall") as BreakableBlock
	var mass_wall := level.get_node_or_null("MassWall") as BreakableBlock
	var giant := level.get_node_or_null("Giant") as HeavyEnemy
	if ramp_wall == null or mass_wall == null or giant == null:
		_note("the walls and the giant are in the level", false,
			"ramp=%s mass=%s giant=%s" % [ramp_wall != null, mass_wall != null,
				giant != null])
		return

	# THE ROOM'S WHOLE CLAIM: short on the flat, through off the ramp.
	_note("the flat charge is short of the ramp wall",
		ramp_wall.break_speed > 20.0,
		"break_speed %.0f against a flat charge's 20" % ramp_wall.break_speed)
	_note("...and the ramp carries you through it",
		ramp_wall.break_speed < 26.0,
		"break_speed %.0f against the ramp's 26" % ramp_wall.break_speed)
	_note("and no slam opens it either", ramp_wall.strike_momentum <= 0.0,
		"strike_momentum %.0f" % ramp_wall.strike_momentum)

	# The giant walks at 3 m/s, so a speed gate can never be his; only his mass
	# can. That is what makes him a tool rather than an obstacle.
	_note("the hero can never open the mass wall",
		mass_wall.break_speed > 26.0 and mass_wall.break_mass > player.mass,
		"break_speed %.0f, break_mass %.0f against the hero's %.0f"
			% [mass_wall.break_speed, mass_wall.break_mass, player.mass])
	_note("...but the giant strolls through it",
		giant.mass >= mass_wall.break_mass,
		"the giant is %.0f against break_mass %.0f"
			% [giant.mass, mass_wall.break_mass])

	# Rule 1 as a filter, and the span is only a filter if the number is BETWEEN
	# the two masses. Either side of both and it is just a floor, or just a trap.
	var span := level.get_node_or_null("SpanC") as CrumblingFloor
	if span != null:
		_note("the span holds the hero but not the giant",
			span.break_mass > player.mass and span.break_mass <= giant.mass,
			"break_mass %.0f, between the hero's %.0f and the giant's %.0f"
				% [span.break_mass, player.mass, giant.mass])

	# One carryable and one not, from a single number, which is what gives a
	# level two kinds of object for free.
	var light := level.get_node_or_null("SeeSawCrate") as RigidBody3D
	if light != null:
		_note("the see-saw crate can be carried",
			light.mass <= player.carry_max_mass,
			"%.0f against carry_max_mass %.0f"
				% [light.mass, player.carry_max_mass])
		_note("...and it is lighter than you, so leverage decides the see-saw",
			light.mass < player.mass,
			"crate %.0f against the hero's %.0f" % [light.mass, player.mass])


## The money arithmetic IS the level design: price the exit low and nothing you
## collect past the threshold matters, price it too high and the level is a
## grind. This checks the shape rather than the exact numbers.
func _the_money() -> void:
	print("  -- the money loop")
	var floor_total := 0
	var chests := 0
	for node in level.get_children():
		var chest := node as Treasure
		if chest != null:
			floor_total += chest.worth
			chests += 1
			continue
		if node.is_in_group(&"collectible") or node.name.begins_with("Coin"):
			var coin: Variant = node.get(&"value")
			floor_total += int(coin) if coin != null else 5

	var exit_node := level.get_node_or_null("Exit")
	if exit_node == null:
		_note("there is an exit", false, "Exit missing")
		return
	var price: Variant = exit_node.get(&"price")
	var want := int(price) if price != null else 0

	_note("there are four chests, one per problem", chests == 4,
		"%d chests worth %d between them" % [chests, floor_total])
	_note("the exit costs less than everything on the floor",
		want < floor_total, "%d against %d available" % [want, floor_total])
	# Tight enough that the next coin is worth something. The market yard runs
	# at 85% and the thief arena at 75%; under about half and the price stops
	# being a decision at all.
	var share := float(want) / maxf(float(floor_total), 1.0)
	_note("...but tightly enough to matter", share > 0.6,
		"the exit wants %.0f%% of the floor" % (share * 100.0))
