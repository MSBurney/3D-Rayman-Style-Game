extends Node

## Smoke test for the whole moveset. Drives the player through every state and
## prints a PASS/FAIL table, so a tuning change that quietly breaks (say) the
## ledge grab gets caught without replaying the level by hand.
##
## Run it headless from the project root:
##   <godot> --headless --path . res://tests/moveset_smoke_test.tscn
## Exit code is 0 when everything passes, 1 otherwise.
##
## It reaches into a few private fields (_grapple, _rope) on purpose: the point
## is to put the controller into states that need a level around them, which is
## awkward to arrange through input alone.

const MAIN := preload("res://scenes/main.tscn")

## How many checks _run() should reach. A runtime error inside _run() silently
## aborts it, and without this guard the report would happily print "0 failures"
## having only run half the suite. Bump it when you add a check.
const EXPECTED_CHECKS := 33

var player: Player
var level: Node3D
var results: Array[String] = []
var failures: int = 0

func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	player = main.get_node("Player") as Player
	level = main.get_node("TestLevel") as Node3D
	if player == null:
		push_error("no player")
		get_tree().quit(1)
		return
	await _run()
	print("\n==== RESULTS ====")
	for line in results:
		print(line)
	if results.size() < EXPECTED_CHECKS:
		failures += 1
		print("FAIL suite truncated — ran %d of %d checks. Something errored inside"
			% [results.size(), EXPECTED_CHECKS])
		print("     _run(); scroll up for the GDScript backtrace.")
	print("==== %d failure(s) ====" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _step(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	var line := "%s %-30s %s" % ["PASS" if ok else "FAIL", label, detail]
	results.append(line)
	# Printed as it happens, not just in the summary: if the suite ever hangs,
	# the last line printed tells you which check it died on.
	print("  ", line)


## Teleports the player and clears everything a previous test might have left
## behind. The timers matter as much as the position: a leftover coyote window
## turns the next jump press into a late ground jump instead of a slam, and a
## stale combo count makes the chain tests read a tick that never happened.
func _place(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player._grapple = null
	player._ledge_lock = 0.0
	player._wall_lock = 0.0
	player._coyote = 0.0
	player._jump_buffered = 0.0
	player._grapple_buffered = 0.0
	player.slam_combo = 0
	player._set_state(Player.State.AIR)


func _release_all() -> void:
	# Movement actions must be in here too: a held move_right leaking out of the
	# wall-run test walks the player away from every later test's setup.
	for action in ["jump", "grapple", "grab", "drop",
			"move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(action)


func _run() -> void:
	# --- lands on the hub and settles into GROUND
	_place(Vector3(0, 3, 10))
	await _step(60)
	_check("lands on ground", player.state == Player.State.GROUND,
		"state=%s y=%.2f" % [player.state_name(), player.global_position.y])

	# --- jump leaves the floor
	Input.action_press("jump")
	await _step(4)
	_check("jump rises", player.velocity.y > 3.0, "vy=%.2f" % player.velocity.y)

	# --- falling is now plain falling: with the helicopter gone, a second jump
	# in mid-air must do nothing at all unless something is targetable.
	_release_all()
	await _step(4)
	_place(Vector3(0, 14, -21))
	await _step(20)
	_check("falls freely", player.velocity.y < -5.0, "vy=%.2f" % player.velocity.y)
	var before_vy: float = player.velocity.y
	Input.action_press("jump")
	await _step(2)
	_release_all()
	# Jump in mid-air now means SLAM. What it must never be is a second jump.
	_check("mid-air jump slams, never lifts",
		player.velocity.y < before_vy and player.state == Player.State.SLAM,
		"vy %.2f -> %.2f state=%s" % [before_vy, player.velocity.y, player.state_name()])
	await _step(40)

	# --- jump must NOT fire the grapple. It was briefly bound there; it is now
	# back on its own button so jump is free for weight-based air moves.
	_release_all()
	await _step(4)
	_place(Vector3(0, 4, 24))
	player.rig.yaw = 0.0
	player.rig.pitch = 0.55
	await _step(6)
	var had_target := player.targeting.current != null
	Input.action_press("jump")
	await _step(6)
	_release_all()
	# With a target in range and the grapple back on its own button, jump must
	# slam rather than hook.
	_check("jump slams instead of grappling",
		had_target and player.state == Player.State.SLAM,
		"target_present=%s state=%s" % [had_target, player.state_name()])
	await _step(10)

	# --- ground slam. Jump in mid-air drives you down, and the payoff scales
	# with how far you fell, which is what makes height worth going to get.
	#
	# Run on the zone B perch, not the hub. A slam kills whatever its shockwave
	# catches, and slamming near the hub quietly destroyed the walker the stomp
	# test needs hundreds of lines later. Freezing the walkers was not enough:
	# PROCESS_MODE_DISABLED stops them moving, not from being damaged. The perch
	# top is 12 m up with nothing within 15 m, which also gives a real drop.
	const PERCH_TOP := Vector3(48, 12, -7)

	_release_all()
	await _step(4)
	_place(PERCH_TOP + Vector3(0, 14, 0))
	await _step(10)
	Input.action_press("jump")
	await _step(3)
	_release_all()
	_check("jump in air starts a slam", player.state == Player.State.SLAM,
		"state=%s vy=%.2f" % [player.state_name(), player.velocity.y])

	var slam_power_high := 0.0
	var bounced_high := 0.0
	for i in 200:
		await get_tree().physics_frame
		if player.state == Player.State.SLAM:
			slam_power_high = player.slam_power()
		else:
			bounced_high = player.velocity.y
			break
	_check("big fall lands at full power", slam_power_high > 0.95,
		"power=%.2f" % slam_power_high)
	_check("slam bounces the player up", bounced_high > 0.0,
		"vy after impact=%.2f" % bounced_high)
	await _step(60)

	# A short hop must be worth much less than a tower drop, or height is not a
	# resource at all and the whole mechanic collapses into one flat move.
	_release_all()
	await _step(20)
	_place(PERCH_TOP + Vector3(0, 0.5, 0))
	await _step(40)
	Input.action_press("jump")
	await _step(6)
	_release_all()
	await _step(6)
	Input.action_press("jump")
	await _step(3)
	_release_all()
	var slam_power_low := 1.0
	for i in 90:
		await get_tree().physics_frame
		if player.state == Player.State.SLAM:
			slam_power_low = player.slam_power()
		elif slam_power_low < 1.0:
			break
	_check("small hop slams weakly", slam_power_low < slam_power_high * 0.6,
		"hop power=%.2f vs drop power=%.2f" % [slam_power_low, slam_power_high])
	await _step(30)

	# --- the combo: chained slams rebound to jump height, and every third one
	# throws you noticeably higher. Slamming from a standstill on flat ground,
	# so each bounce is identical apart from the combo.
	# A chain never touches the ground in between — the rebound keeps you
	# airborne, so each slam is just another press. No jumping involved.
	_release_all()
	await _step(20)
	_place(PERCH_TOP + Vector3(0, 6, 0))
	# Start from a known count. The earlier slam tests already advanced it, and
	# leaving it non-zero made the loop below "see" a combo tick on its first
	# frame and record a falling velocity as if it were a rebound.
	player.slam_combo = 0
	await _step(6)
	# Watch the combo counter rather than polling for the SLAM state. After a
	# bounce the player is only centimetres above the floor, so the next slam can
	# begin and finish inside a two-frame wait — any sampling that looks for the
	# state misses it. The counter ticking is the one unambiguous signal that an
	# impact just happened, so read the rebound on exactly that frame.
	var bounce_speeds: Array[float] = []
	for slam_index in 3:
		# Wait until properly airborne and falling, then press ONCE. Pressing on
		# every frame does not register at all — holding the button across frame
		# boundaries never produces a fresh just_pressed, so the slam never fires.
		for i in 200:
			await get_tree().physics_frame
			if player.state == Player.State.AIR and player.velocity.y < -1.0:
				break
		var before_combo := player.slam_combo
		Input.action_press("jump")
		await _step(3)
		_release_all()
		# The combo ticking is the unambiguous "an impact just happened" signal,
		# and the rebound is on the velocity that same frame.
		for i in 200:
			await get_tree().physics_frame
			if player.slam_combo > before_combo:
				bounce_speeds.append(player.velocity.y)
				break

	var plain_bounce := sqrt(2.0 * player.gravity_rise * player.jump_height)
	_check("slam rebounds to jump height",
		bounce_speeds.size() >= 2 and absf(bounce_speeds[0] - plain_bounce) < 1.0,
		"bounce=%.2f expected=%.2f" % [
			bounce_speeds[0] if bounce_speeds.size() > 0 else -1.0, plain_bounce])
	_check("every third slam bounces higher",
		bounce_speeds.size() == 3 and bounce_speeds[2] > bounce_speeds[0] + 1.0,
		"bounces=%s combo=%d" % [str(bounce_speeds), player.slam_combo])

	# Landing normally has to break the chain, or the combo would just tick up
	# forever and every third landing would randomly launch the player.
	_release_all()
	await _step(90)
	_check("landing resets the combo", player.slam_combo == 0,
		"combo=%d state=%s" % [player.slam_combo, player.state_name()])

	# --- the shockwave hits things standing nearby, not only underfoot.
	_release_all()
	await _step(10)
	# DWalker, not BWalker: the shockwave kills what it hits, and BWalker is the
	# fixture the dive test needs later on.
	var shock_enemy := level.get_node("DWalker") as Node3D
	var shock_health := shock_enemy.get_node("Health") as HealthComponent
	var shock_hp: int = shock_health.current
	# Land beside it, not on it, so a stomp cannot be what does the damage.
	_place(shock_enemy.global_position + Vector3(2.0, 16, 0))
	await _step(8)
	Input.action_press("jump")
	await _step(3)
	_release_all()
	await _step(90)
	var shock_gone := not is_instance_valid(shock_health)
	_check("slam shockwave reaches sideways",
		shock_gone or shock_health.current < shock_hp,
		"hp %d -> %s" % [shock_hp, "killed" if shock_gone else str(shock_health.current)])
	await _step(20)

	# --- ledge grab on the zone C terrace (lip at y=3.3, wall face at x=-15).
	# x must clear the capsule of the wall (> -14.6) but stay inside the 0.75 m
	# chest reach (<= -14.25); feet must sit 1.0-2.3 m below the lip.
	_place(Vector3(-14.45, 1.8, 0))
	player.facing = Vector3(-1, 0, 0)
	player.velocity = Vector3(0, -2.0, 0)
	await _step(25)
	_check("ledge grab", player.state == Player.State.LEDGE_HANG,
		"state=%s y=%.2f" % [player.state_name(), player.global_position.y])

	# --- climbing up from a hang
	if player.state == Player.State.LEDGE_HANG:
		Input.action_press("jump")
		await _step(3)
		_release_all()
		await _step(30)
		_check("ledge climb up", player.global_position.y > 3.0,
			"y=%.2f state=%s" % [player.global_position.y, player.state_name()])
	else:
		_check("ledge climb up", false, "skipped, never hung")

	# --- pull grapple: hook point sits ahead of the hub at (0, 7, -12)
	_place(Vector3(0, 1.5, 0))
	await _step(20)
	var pull_target := player.targeting.pick(player.rig.camera, player.global_position + Vector3.UP, [player.get_rid()])
	_check("finds a grapple target", pull_target != null,
		"target=%s" % (pull_target.name if pull_target != null else "none"))

	# Aim is camera-driven, so drive the state directly rather than fight the camera.
	var pull_point := level.get_node("HubPull") as GrapplePoint
	player._grapple = pull_point
	player._set_state(Player.State.GRAPPLE_DIVE)
	await _step(4)
	_check("dive moves player", player.velocity.length() > 5.0,
		"speed=%.2f" % player.velocity.length())
	await _step(60)
	_check("dive releases", player.state != Player.State.GRAPPLE_DIVE,
		"state=%s" % player.state_name())
	_release_all()

	# --- the tongue on an ENEMY: the enemy comes to the player, not the other
	# way round, and ends up carried. This is the half that makes it a Yoshi
	# tongue rather than a grapple.
	_release_all()
	await _step(10)
	var prey := level.get_node("HubWalkerB") as Node3D
	var prey_start := prey.global_position
	_place(prey_start + Vector3(0, 0.6, 7))
	await _step(40)
	var player_before := player.global_position
	player.abilities.tongue_grab(prey)
	for i in 150:
		await get_tree().physics_frame
		if player.abilities.carried != null:
			break
	var player_moved := player_before.distance_to(player.global_position)
	var prey_moved := prey_start.distance_to(prey.global_position)
	_check("tongue drags the enemy, not the player",
		player.abilities.carried == prey and prey_moved > player_moved,
		"enemy moved %.2f, player moved %.2f, carried=%s"
			% [prey_moved, player_moved,
				player.abilities.carried.name if player.abilities.carried else "none"])

	# Pressing grapple while holding something throws it.
	Input.action_press("grapple")
	await _step(3)
	_release_all()
	await _step(6)
	_check("grapple throws what you are carrying", player.abilities.carried == null,
		"carried=%s" % (player.abilities.carried.name if player.abilities.carried else "none"))
	await _step(60)

	# --- the tongue on an ANCHOR still pulls the player to it.
	_release_all()
	await _step(10)
	var anchor := level.get_node("HubPull") as GrapplePoint
	_place(Vector3(0, 2, 0))
	await _step(10)
	player._grapple = anchor
	player._set_state(Player.State.GRAPPLE_DIVE)
	await _step(4)
	_check("tongue pulls the player to an anchor", player.velocity.length() > 5.0,
		"speed=%.2f" % player.velocity.length())
	await _step(80)
	_release_all()

	# --- diving at an enemy: it takes damage and the player bounces off airborne,
	# which is what lets one dive chain into the next.
	_release_all()
	await _step(10)
	var dive_enemy := level.get_node("BWalker") as Node3D
	var dive_enemy_health := dive_enemy.get_node("Health") as HealthComponent
	var dive_enemy_hp: int = dive_enemy_health.current
	_place(dive_enemy.global_position + Vector3(0, 6, 0))
	player._grapple = dive_enemy
	player._set_state(Player.State.GRAPPLE_DIVE)
	await _step(40)
	var dive_enemy_gone := not is_instance_valid(dive_enemy_health)
	_check("dive damages an enemy",
		dive_enemy_gone or dive_enemy_health.current < dive_enemy_hp,
		"hp %d -> %s" % [dive_enemy_hp,
			"killed" if dive_enemy_gone else str(dive_enemy_health.current)])
	_check("dive bounces the player", player.state != Player.State.GRAPPLE_DIVE,
		"state=%s vy=%.2f" % [player.state_name(), player.velocity.y])
	await _step(20)

	# --- wall run along the tan wall in zone B (face at z=5, spans x 25..45).
	# Capsule edge starts 0.05 m off the face so contact happens immediately.
	_place(Vector3(26, 2.5, 4.55))
	player.velocity = Vector3(9.0, 0.0, 3.0)
	Input.action_press("move_right")
	await _step(12)
	var wall_state := player.state
	_release_all()
	_check("wall contact state", wall_state == Player.State.WALL_RUN or wall_state == Player.State.WALL_SLIDE,
		"state=%s" % player.state_name())
	await _step(20)

	# --- grab and throw a keg
	var keg := level.get_node("KegA") as RigidBody3D
	_place(keg.global_position + Vector3(0, 0.4, 1.0))
	await _step(25)
	Input.action_press("grab")
	await _step(3)
	Input.action_release("grab")
	await _step(5)
	# Whichever keg the grab area actually chose is the one to watch.
	var held := player.abilities.carried as RigidBody3D
	_check("grab picks up keg", held != null,
		"carried=%s" % (held.name if held != null else "none"))
	Input.action_press("grab")
	await _step(3)
	Input.action_release("grab")
	await _step(6)
	var thrown_speed := held.linear_velocity.length() if held != null else 0.0
	_check("throw releases keg", player.abilities.carried == null and thrown_speed > 3.0,
		"kegspeed=%.2f" % thrown_speed)
	await _step(20)

	# --- taking damage.
	# Run this on the zone D tower, not the hub: the hub walkers wander, and a
	# chasing one landing a contact hit mid-test knocks the player back into HURT
	# and makes the death checks below fail for reasons that have nothing to do
	# with what is being tested. The tower is 13 m up and out of their range.
	_place(Vector3(11, 14, 66))
	await _step(40)
	var before: int = player.health.current
	player.take_hit(1, player.global_position + Vector3(0, 0, 2))
	await _step(3)
	_check("take_hit damages", player.health.current == before - 1,
		"hp %d -> %d state=%s" % [before, player.health.current, player.state_name()])

	# --- invulnerability window blocks a second immediate hit
	var mid: int = player.health.current
	player.take_hit(1, player.global_position + Vector3(0, 0, 2))
	await _step(3)
	_check("invuln blocks rehit", player.health.current == mid, "hp=%d" % player.health.current)
	await _step(60)

	# --- death and respawn
	player.kill()
	await _step(5)
	_check("kill reaches DEAD", player.state == Player.State.DEAD, "state=%s" % player.state_name())
	await _step(120)
	_check("respawns alive", player.health.current > 0 and player.state != Player.State.DEAD,
		"hp=%d state=%s" % [player.health.current, player.state_name()])

	# --- pit plane kills (volume now spans y -130..-30, so fall into it)
	_place(Vector3(0, -20, 0))
	await _step(90)
	_check("pit plane kills", player.state == Player.State.DEAD or player.health.current < player.health.max_health,
		"state=%s hp=%d" % [player.state_name(), player.health.current])
	await _step(140)

	# --- stomping a walker
	var walker := level.get_node_or_null("HubWalkerA")
	if walker != null:
		var walker_health := walker.get_node("Health") as HealthComponent
		var hp_before: int = walker_health.current
		_place((walker as Node3D).global_position + Vector3(0, 3.0, 0))
		player.velocity = Vector3(0, -6, 0)
		await _step(30)
		# A stomp does 2 damage to a 2 HP walker, so the node is usually gone by
		# now — read health only while it's still valid.
		var killed := not is_instance_valid(walker_health)
		var hp_after := -1 if killed else walker_health.current
		_check("stomp hurts walker", killed or hp_after < hp_before,
			"hp %d -> %d%s" % [hp_before, hp_after, " (killed)" if killed else ""])
	else:
		_check("stomp hurts walker", false, "walker missing")

	# --- enemies and turrets survive a long idle without erroring
	await _step(120)
	_check("no crash after idle", is_instance_valid(player), "state=%s" % player.state_name())

