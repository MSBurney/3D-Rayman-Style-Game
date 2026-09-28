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
	print("==== %d failure(s) ====" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _step(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	results.append("%s %-26s %s" % ["PASS" if ok else "FAIL", label, detail])


func _place(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player._grapple = null
	player._ledge_lock = 0.0
	player._wall_lock = 0.0
	player._set_state(Player.State.AIR)


func _release_all() -> void:
	# Movement actions must be in here too: a held move_right leaking out of the
	# wall-run test walks the player away from every later test's setup.
	for action in ["jump", "punch", "grapple", "grab", "drop",
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

	# --- helicopter: tested over the zone A pillar, clear of any walker that
	# would otherwise get stomped mid-descent and bounce the player upward.
	_release_all()
	await _step(4)
	_place(Vector3(0, 14, -21))
	await _step(20)
	_check("falls freely", player.velocity.y < -5.0, "vy=%.2f" % player.velocity.y)
	Input.action_press("jump")
	await _step(15)
	_check("helicopter deploys", player.state == Player.State.HELICOPTER,
		"state=%s vy=%.2f" % [player.state_name(), player.velocity.y])
	await _step(20)
	_check("helicopter clamps fall",
		player.velocity.y > -3.0 and player.state == Player.State.HELICOPTER,
		"vy=%.2f state=%s" % [player.velocity.y, player.state_name()])
	_release_all()
	await _step(40)

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
	player._set_state(Player.State.GRAPPLE_PULL)
	await _step(4)
	_check("pull moves player", player.velocity.length() > 5.0,
		"speed=%.2f" % player.velocity.length())
	await _step(60)
	_check("pull releases", player.state != Player.State.GRAPPLE_PULL,
		"state=%s" % player.state_name())
	_release_all()

	# --- swing: rope constraint should hold the player near rope length.
	# Swinging is hold-to-hang, so the button must be down or the first
	# just_released drops the rope instantly.
	await _step(5)
	var swing_point := level.get_node("DSwing1") as GrapplePoint
	_place(swing_point.global_position + Vector3(0, -6, -4))
	Input.action_press("grapple")
	player._grapple = swing_point
	player._rope = player.global_position.distance_to(swing_point.global_position)
	player._rope_target = player._rope
	player._set_state(Player.State.SWING)
	await _step(50)
	var rope_error: float = absf(player.global_position.distance_to(swing_point.global_position) - player._rope)
	_check("swing holds rope length", rope_error < 2.5 and player.state == Player.State.SWING,
		"err=%.2f state=%s" % [rope_error, player.state_name()])

	# --- releasing a swing with jump should fling, not drop
	Input.action_press("jump")
	await _step(3)
	_release_all()
	_check("swing release flings", player.state == Player.State.AIR,
		"state=%s vy=%.2f" % [player.state_name(), player.velocity.y])
	await _step(10)

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

	# --- punch spawns a fist
	_place(Vector3(0, 1.2, 10))
	await _step(90)
	Input.action_press("punch")
	await _step(3)
	Input.action_release("punch")
	await _step(3)
	_check("punch spawns fist", _count_nodes("Fist") > 0, "fists=%d" % _count_nodes("Fist"))
	await _step(40)

	# --- grab and throw a keg
	var keg := level.get_node("KegA") as RigidBody3D
	_place(keg.global_position + Vector3(0, 0.4, 1.0))
	await _step(25)
	Input.action_press("grab")
	await _step(3)
	Input.action_release("grab")
	await _step(5)
	# Whichever keg the grab area actually chose is the one to watch.
	var held := player.carried as RigidBody3D
	_check("grab picks up keg", held != null,
		"carried=%s" % (held.name if held != null else "none"))
	Input.action_press("grab")
	await _step(3)
	Input.action_release("grab")
	await _step(6)
	var thrown_speed := held.linear_velocity.length() if held != null else 0.0
	_check("throw releases keg", player.carried == null and thrown_speed > 3.0,
		"kegspeed=%.2f" % thrown_speed)
	await _step(20)

	# --- taking damage
	_place(Vector3(0, 1.2, 10))
	await _step(25)
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


func _count_nodes(prefix: String) -> int:
	var total := 0
	for node in get_tree().current_scene.get_children():
		if node.name.begins_with(prefix):
			total += 1
	return total
