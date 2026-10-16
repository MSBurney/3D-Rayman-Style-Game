extends Node

## THROWAWAY probe for the market yard. Delete once the level settles.
##
## The question it exists to answer is "is the chest alcove actually sealed, so
## the gate is the only way in" — because a gate you can walk round is not a
## decision, and a wall with a gap in it looks exactly like a wall.
##
## So most of these rays are HORIZONTAL, fired from inside the alcove outwards.
## A floor probe cannot tell you whether a room is enclosed.

const MAIN := preload("res://scenes/market_yard_main.tscn")

var failures: int = 0


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	print("\n==== MARKET YARD PROBE ====")
	_floor_at("floor, out in the open", 50.0, 50.0, 0.0)
	_floor_at("floor, the start plaza", 0.0, -44.0, 0.0)

	print("  -- the gate is too tall to jump over")
	# Dropped from well above the gate on to its top face. The whole decision
	# rests on this: a 4 m gate can be cleared with a triple jump, and then
	# paying 30 for it is something only an honest player does.
	_ray_down("gate top", Vector3(20, 12, 24), 8.0)

	print("  -- the alcove is sealed, so the gate is the only way in")
	# Fired from the middle of the alcove outwards. Each expected value is the
	# INNER face of the wall it should hit.
	var inside := Vector3(20, 4, 28)
	_ray("east wall", inside, Vector3.RIGHT, 24.0, "x")
	_ray("west wall", inside, Vector3.LEFT, 16.0, "x")
	_ray("north wall", inside, Vector3.FORWARD * -1.0, 32.0, "z")
	_ray("the gate itself", inside, Vector3.FORWARD, 24.3, "z")

	print("  -- and the chest is inside it")
	var chest := main.get_node_or_null("MarketYard/Chest") as Node3D
	if chest == null:
		failures += 1
		print("    chest MISSING *** WRONG ***")
	else:
		var p := chest.global_position
		var within := p.x > 16.0 and p.x < 24.0 and p.z > 24.3 and p.z < 32.0
		if not within:
			failures += 1
		print("    chest at (%.1f, %.1f, %.1f) inside the alcove=%s %s"
			% [p.x, p.y, p.z, within, "" if within else "*** WRONG ***"])

	print("---- %d wrong ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _compare(label: String, got: float, expected: float, tolerance: float) -> void:
	var ok := absf(got - expected) <= tolerance
	if not ok:
		failures += 1
	print("    %-22s expected %7.2f  got %7.2f  %s"
		% [label, expected, got, "" if ok else "*** WRONG ***"])


func _floor_at(label: String, x: float, z: float, expected: float) -> void:
	_ray_down(label, Vector3(x, expected + 1.5, z), expected)


func _ray_down(label: String, from: Vector3, expected: float) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var to := from + Vector3.DOWN * 20.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		failures += 1
		print("    %-22s expected %7.2f  got NOTHING  *** WRONG ***" % [label, expected])
		return
	_compare(label, hit["position"].y, expected, 0.1)


## Fires a horizontal ray and compares the named axis of whatever it hits.
func _ray(label: String, from: Vector3, dir: Vector3, expected: float, axis: String) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 30.0))
	if hit.is_empty():
		failures += 1
		print("    %-22s expected %7.2f  got NOTHING AT ALL — not sealed  *** WRONG ***"
			% [label, expected])
		return
	var at: Vector3 = hit["position"]
	_compare(label, at.x if axis == "x" else at.z, expected, 0.35)
