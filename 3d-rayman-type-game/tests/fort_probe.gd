extends Node

## Throwaway: is the tree fort actually climbable, and is every surface where the
## layout comment says it is?
##
## Hand-placed geometry is where this project keeps getting caught — two ramps
## tilted the wrong way, fixtures spawned off the edge of a pad, and on the first
## draft of this fort two whole staircases running underneath the deck they were
## supposed to reach. So every deck and every step gets raycast.
##
## The important detail: each ray starts just ABOVE the surface it is asking
## about and only reaches down a little way. Casting from the sky instead reports
## whatever is topmost at that x,z, so any deck with another deck above it reads
## back the wrong one — which is how the first version of this probe produced
## three nonsense readings and nearly sent me fixing the wrong thing.

const FORT := preload("res://scenes/tree_fort_main.tscn")

var level: Node3D
var faults: int = 0

func _ready() -> void:
	var main: Node = FORT.instantiate()
	add_child(main)
	await get_tree().process_frame
	level = main.get_node("TreeFort") as Node3D

	print("\n--- decks (expected -> measured) ---")
	for p in [
		["plain, at spawn", Vector2(0, 28), 0.0],
		["deck 1 north", Vector2(0, -4.5), 4.0],
		["deck 1 east", Vector2(6, 0), 4.0],
		["deck 1 south (crumbles)", Vector2(0, 5.5), 4.0],
		["deck 1 west (crumbles)", Vector2(-6, 0), 4.0],
		["deck 2 west", Vector2(-3.25, 0), 8.0],
		["deck 2 north", Vector2(0, -3.25), 8.0],
		["deck 2 east (crumbles)", Vector2(3.25, 0), 8.0],
		["deck 2 gantry (crumbles)", Vector2(-6.5, 0), 8.0],
		["deck 3 lookout", Vector2(3, 0), 12.0],
	]:
		_at(p[0], p[1], p[2])

	print("\n--- stairs: measured top of every step ---")
	_flight("ground -> deck 1", -4.5, true,
		[11.6, 10.2, 8.8, 7.4, 6.0], [0.8, 1.6, 2.4, 3.2, 4.0])
	_flight("deck 1 -> deck 2", -5.75, false,
		[-4.0, -2.0, 0.0, 2.0, 4.0], [4.8, 5.6, 6.4, 7.2, 8.0])
	_flight("deck 2 -> deck 3", 5.2, true,
		[-4.0, -2.5, -1.0, 0.5, 2.0], [8.8, 9.6, 10.4, 11.2, 12.0])

	# Probed BESIDE each chest, never through it. A chest is a StaticBody on the
	# world layer, so a ray dropped onto it from above hits its own lid and
	# cheerfully reports "the floor is exactly one metre up" for every one.
	print("\n--- chests must sit ON something ---")
	for entry in [
		["ChestHut", Vector3(10, 1.0, 5.4), 0.0],
		["ChestDeck1", Vector3(-5, 5.0, -5.7), 4.0],
		["ChestGantry", Vector3(-8.3, 9.0, 0), 8.0],
		["ChestLookout", Vector3(1.2, 13.0, -3), 12.0],
	]:
		var chest := level.get_node_or_null(entry[0]) as Node3D
		if chest == null:
			print("  %-14s MISSING" % entry[0])
			faults += 1
			continue
		var floor_y := _surface(entry[1])
		var ok := floor_y != -999.0 and absf(floor_y - entry[2]) < 0.2 \
			and absf(chest.global_position.y - entry[2]) < 0.2
		if not ok:
			faults += 1
		print("  %-14s chest y=%5.2f, deck beside it y=%s%s"
			% [entry[0], chest.global_position.y,
				"none" if floor_y == -999.0 else "%.2f" % floor_y,
				"" if ok else "   *** FLOATING OR BURIED ***"])

	print("\n==== %d fault(s) ====" % faults)
	get_tree().quit(1 if faults > 0 else 0)


## Probes one spot, starting a metre above where the surface should be.
func _at(label: String, xz: Vector2, expected: float) -> void:
	var y := _surface(Vector3(xz.x, expected + 1.0, xz.y))
	var ok := y != -999.0 and absf(y - expected) < 0.15
	if not ok:
		faults += 1
	print("  %-26s expected %5.1f   got %s%s"
		% [label, expected, "nothing" if y == -999.0 else "%6.2f" % y,
			"" if ok else "   *** WRONG ***"])


## Height of the first solid thing under `from`, searching down 2.5 m only.
func _surface(from: Vector3) -> float:
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.5, 1)
	var hit := space.intersect_ray(q)
	return -999.0 if hit.is_empty() else (hit["position"] as Vector3).y


## Walks a staircase. `along_x` says which axis the steps march down; `fixed` is
## the other one. A jump clears 2.35 m, so any rise above that is a step you
## cannot use, and the last step must meet the deck it is climbing to.
func _flight(label: String, fixed: float, along_x: bool,
		coords: Array, expected: Array) -> void:
	var got: Array[float] = []
	for i in coords.size():
		var p := Vector3(coords[i], expected[i] + 0.9, fixed) if along_x \
			else Vector3(fixed, expected[i] + 0.9, coords[i])
		got.append(_surface(p))

	var worst := 0.0
	var missing := false
	for i in got.size():
		if got[i] == -999.0:
			missing = true
			continue
		if absf(got[i] - expected[i]) > 0.15:
			missing = true
		if i > 0 and got[i - 1] != -999.0:
			worst = maxf(worst, got[i] - got[i - 1])
	if missing or worst > 2.35:
		faults += 1
	print("  %-18s %s   biggest rise %.2f m%s"
		% [label, str(got.map(func(h): return "%.1f" % h)), worst,
			"" if not missing and worst <= 2.35 else "   *** BROKEN RUN ***"])
