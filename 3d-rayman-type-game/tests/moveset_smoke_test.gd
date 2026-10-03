extends Node

## Smoke test for the whole moveset. Drives the player through every state and
## prints a PASS/FAIL table, so a tuning change that quietly breaks (say) the
## ledge grab gets caught without replaying the level by hand.
##
## Run it headless from the project root:
##   <godot> --headless --path . res://tests/moveset_smoke_test.tscn
## Exit code is 0 when everything passes, 1 otherwise.
##
## It reaches into a few private fields (_chain_window, _slam_recover) on purpose:
## the point
## is to put the controller into states that need a level around them, which is
## awkward to arrange through input alone.

const MAIN := preload("res://scenes/main.tscn")
## Spawned fresh for the throw and stomp checks. The level's own walkers cannot
## be relied on any more: a homing throw kills whatever it finds, so by halfway
## through the suite there may be none left standing.
const WALKER := preload("res://scenes/enemies/enemy_walker.tscn")
## Spawned for the weight-acts-on-the-world checks. Only the momentum playground
## has these placed in it, and this suite runs on main.tscn.
const CRUMBLING := preload("res://scenes/props/crumbling_floor.tscn")
const SWITCH := preload("res://scenes/props/spin_switch.tscn")
const BLOCK := preload("res://scenes/props/breakable_block.tscn")
const TREASURE := preload("res://scenes/props/treasure.tscn")
const EXIT := preload("res://scenes/props/level_exit.tscn")
const KEG := preload("res://scenes/props/throwable_keg.tscn")

## How many checks _run() should reach. A runtime error inside _run() silently
## aborts it, and without this guard the report would happily print "0 failures"
## having only run half the suite. Bump it when you add a check.
const EXPECTED_CHECKS := 68

var player: Player
var level: Node3D
var results: Array[String] = []
var failures: int = 0
## Counted from ThrownFlight's `exploded` signal. It has to be recorded as it
## happens: a thrown walker frees itself when it bursts, so reading anything off
## its Flight node afterwards is an access to an already-freed object.
var bursts: int = 0

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
## turns the next jump press into a late ground jump instead of a pound, and a
## stale jump-chain count turns the next press into a double or triple jump.
func _place(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO


	player._ledge_lock = 0.0
	player._wall_lock = 0.0
	player._coyote = 0.0
	player._jump_buffered = 0.0

	player.jump_chain = 0
	player._chain_window = 0.0
	player._slam_recover = 0.0
	# Spin state too, for exactly the same reason as the jump chain: a chain left
	# half-finished by an earlier check turns the next press into the super spin,
	# or into nothing at all because of its lockout. That cost the lockout check
	# one of its three spins and looked like the chain being short.
	player.abilities.drop_everything()
	player._set_state(Player.State.AIR)


func _on_burst(_where: Vector3) -> void:
	bursts += 1


## Waits for the ground, jumps the instant we touch it, and returns the launch
## speed. Used three times in a row to drive Mario's jump chain.
##
## Pressing the moment we land matters: the chain only stays alive for
## `jump_chain_window` after touching down, so any fixed wait long enough to be
## safe is also long enough to lose the chain. And the launch speed has to be
## read BEFORE the button is released, or the jump-cut halves it on the way out.
func _chain_jump(max_wait: int = 240) -> float:
	for i in max_wait:
		await _step(1)
		if player.is_on_floor():
			break
	Input.action_press("jump")
	var launch := 0.0
	for i in 10:
		await _step(1)
		launch = maxf(launch, player.velocity.y)
	Input.action_release("jump")
	return launch


## Builds a slope in empty space and returns it, so the momentum checks do not
## need the test level to contain a ramp.
##
## `degrees` of 0 gives a flat pad. The rotation is about X, which puts the
## downhill direction along local +Z — the same convention the playground's ramps
## use. Worth knowing if you ever hand-write one of those in a .tscn: Godot
## serialises a Transform3D basis ROW by row, so the obvious column-major
## reading of those nine numbers gives you a ramp tilted the wrong way.
func _add_slope(at: Vector3, degrees: float, length: float, width: float = 12.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 2.0, length)
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	level.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(degrees)), at)
	return body


## Drops the player onto a slope at `from`, shoves them at `push`, and returns
## the fastest horizontal speed they reached.
func _roll_on(_slope: StaticBody3D, from: Vector3, push: Vector3, frames: int) -> float:
	_place(from)
	await _step(2)
	player.velocity = push
	var peak := 0.0
	for i in frames:
		await _step(1)
		peak = maxf(peak, Vector2(player.velocity.x, player.velocity.z).length())
	return peak



func _release_all() -> void:
	# Movement actions must be in here too: a held move_right leaking out of the
	# wall-run test walks the player away from every later test's setup.
	for action in ["jump", "grapple", "grab", "drop", "crouch", "attack",
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

	# ------------------------------------------------------------- Mario moveset
	#
	# All of it runs on a 60x60 pad built in empty space. The level's own flat
	# ground is the hub, and the hub has wandering walkers on it whose contact
	# knockback reads as a phantom 7 m/s of drift — which is exactly the sort of
	# thing these checks are measuring. Out here nothing can interfere, and there
	# is no edge within 30 m to walk off mid-measurement.
	var pad := _add_slope(Vector3(250, 20, 0), 0.0, 60.0, 60.0)
	const PAD_TOP := Vector3(250, 21, 0)
	await _step(4)

	# --- jump in mid-air must now do NOTHING. It used to start the bounce attack;
	# the double and triple jump need the button, so the pound moved to crouch.
	_place(PAD_TOP + Vector3(0, 14, 0))
	await _step(24)
	var air_vy: float = player.velocity.y
	Input.action_press("jump")
	await _step(2)
	_release_all()
	_check("mid-air jump does nothing",
		player.state == Player.State.AIR and player.velocity.y < air_vy,
		"vy %.2f -> %.2f state=%s" % [air_vy, player.velocity.y, player.state_name()])
	await _step(40)

	# --- crouch in mid-air IS the ground pound.
	_place(PAD_TOP + Vector3(0, 16, 0))
	await _step(10)
	Input.action_press("crouch")
	await _step(3)
	_release_all()
	_check("crouch in mid-air starts a pound", player.state == Player.State.SLAM,
		"state=%s vy=%.2f" % [player.state_name(), player.velocity.y])

	var pound_power_high := 0.0
	var pound_vy := 1.0
	for i in 200:
		await _step(1)
		if player.state == Player.State.SLAM:
			pound_power_high = player.slam_power()
		else:
			pound_vy = player.velocity.y
			break
	_check("big fall pounds at full power", pound_power_high > 0.95,
		"power=%.2f" % pound_power_high)
	# The headline change: a pound ends on the floor. It must not launch you.
	_check("a pound does not bounce you",
		pound_vy <= 0.0 and player.state == Player.State.CROUCH,
		"vy after impact=%.2f state=%s" % [pound_vy, player.state_name()])

	# And you are held there briefly, or the pound reads weightless.
	Input.action_press("jump")
	await _step(3)
	_release_all()
	_check("pound recovery holds you down",
		player.state == Player.State.CROUCH and player.velocity.y <= 0.1,
		"state=%s vy=%.2f recover=%.2f"
			% [player.state_name(), player.velocity.y, player._slam_recover])
	await _step(40)

	# A short hop must be worth much less than a long fall, or height is not a
	# resource and the whole thing collapses into one flat move.
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(40)
	Input.action_press("jump")
	await _step(6)
	_release_all()
	await _step(6)
	Input.action_press("crouch")
	await _step(3)
	_release_all()
	var pound_power_low := 1.0
	for i in 90:
		await _step(1)
		if player.state == Player.State.SLAM:
			pound_power_low = player.slam_power()
		elif pound_power_low < 1.0:
			break
	_check("a small hop pounds weakly", pound_power_low < pound_power_high * 0.6,
		"hop power=%.2f vs fall power=%.2f" % [pound_power_low, pound_power_high])
	await _step(50)

	# --- the jump chain: land and jump again quickly for the double, then the
	# triple. A direction is held throughout, because a triple jump has to be
	# earned by actually going somewhere.
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(40)
	Input.action_press("move_right")
	await _step(40)
	var chain: Array[float] = []
	for i in 3:
		chain.append(await _chain_jump())
	_release_all()
	await _step(40)

	_check("a double jump beats a single",
		chain.size() == 3 and chain[1] > chain[0] + 0.5,
		"launch speeds=%s" % str(chain))
	_check("a triple jump is the biggest",
		chain.size() == 3 and chain[2] > chain[1] + 0.5,
		"launch speeds=%s" % str(chain))

	# Standing still, the third jump must NOT be the big one — otherwise the
	# largest jump in the game is free from a standstill.
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(40)
	var still: Array[float] = []
	for i in 3:
		still.append(await _chain_jump())
	_check("a standing triple jump is refused",
		still.size() == 3 and still[2] < chain[2] - 0.5,
		"standing=%.2f vs moving=%.2f" % [still[2], chain[2]])
	await _step(40)

	# --- backflip: crouch still, then jump. Up a long way, and backwards.
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(40)
	player.facing = Vector3.FORWARD
	Input.action_press("crouch")
	await _step(10)
	var crouched := player.state
	Input.action_press("jump")
	await _step(3)
	_release_all()
	var plain_launch := sqrt(2.0 * player.gravity_rise * player.jump_height)
	_check("backflip goes higher than a jump, and backwards",
		crouched == Player.State.CROUCH
			and player.velocity.y > plain_launch + 1.0
			and player.velocity.z > 1.0,
		"crouched=%s vy=%.2f (a jump is %.2f), back=%.2f"
			% [Player.State.keys()[crouched], player.velocity.y, plain_launch,
				player.velocity.z])
	await _step(70)

	# --- slide and long jump: crouch at a run. The slide has to KEEP speed that
	# walking would brake away, and the long jump has to go far rather than high.
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(40)
	player.velocity = Vector3(0, 0, -11)
	Input.action_press("crouch")
	await _step(2)
	var sliding := player.state
	await _step(58)
	var slide_speed := Vector2(player.velocity.x, player.velocity.z).length()

	# The control case: the same 11 m/s with no crouch, which normal braking
	# pulls down much faster.
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(40)
	player.velocity = Vector3(0, 0, -11)
	await _step(60)
	var walk_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check("sliding keeps speed that walking brakes away",
		sliding == Player.State.SLIDE and slide_speed > walk_speed + 1.5,
		"slide kept %.1f, walking kept %.1f" % [slide_speed, walk_speed])

	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(40)
	player.velocity = Vector3(0, 0, -11)
	Input.action_press("crouch")
	await _step(8)
	var before_long := Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_press("jump")
	await _step(3)
	_release_all()
	var after_long := Vector2(player.velocity.x, player.velocity.z).length()
	_check("long jump goes far and low",
		after_long > before_long + 5.0 and player.velocity.y < plain_launch,
		"speed %.1f -> %.1f, vy=%.2f (a jump is %.2f)"
			% [before_long, after_long, player.velocity.y, plain_launch])
	await _step(70)

	# --- side flip: at speed, flick the stick back the way you came and jump.
	# Triggered on the INPUT reversing, not the velocity, because heavy handling
	# will not let velocity turn round quickly — see Player._wants_side_flip.
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(40)
	Input.action_press("move_right")
	await _step(60)
	var flip_before := Vector3(player.velocity.x, 0.0, player.velocity.z)
	Input.action_release("move_right")
	Input.action_press("move_left")
	await _step(2)
	Input.action_press("jump")
	await _step(2)
	_release_all()
	var flip_after := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var reversed := flip_before.length() > 0.1 and flip_after.length() > 0.1 \
		and flip_before.normalized().dot(flip_after.normalized()) < 0.0
	_check("side flip reverses you and lifts you",
		reversed and player.velocity.y > plain_launch * 0.8,
		"%.1f m/s -> %.1f m/s reversed=%s, vy=%.2f"
			% [flip_before.length(), flip_after.length(), reversed, player.velocity.y])
	await _step(70)

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

	# ------------------------------------------------------------- spin attack
	#
	# Replaced the grapple on 2026-10-02. Everything here runs on the flat pad
	# built for the Mario moves, with its own spawned fixtures, for the same
	# reason: nothing in a level survives this suite reliably.

	# --- a spin hurts what is standing next to you, and the chain scales.
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(40)
	var spin_prey := WALKER.instantiate() as Node3D
	level.add_child(spin_prey)
	spin_prey.global_position = PAD_TOP + Vector3(1.6, 0.2, 0)
	await _step(10)
	var spin_health := spin_prey.get_node("Health") as HealthComponent
	spin_health.max_health = 40
	spin_health.reset()
	var spin_hp: int = spin_health.current

	Input.action_press("attack")
	await _step(2)
	Input.action_release("attack")
	await _step(2)
	_check("a spin hurts what is next to you",
		spin_health.current < spin_hp and player.abilities.spin_step == 1,
		"hp %d -> %d, step=%d" % [spin_hp, spin_health.current, player.abilities.spin_step])

	# Freed before anything else runs. It has 40 HP so it survives the spin, which
	# means it then chases the player and lands contact hits — and a hit puts the
	# player in HURT, where `handle_input` is not called at all, so attack presses
	# are silently swallowed. That cost the chain check below two of its three
	# spins and looked exactly like the combo being broken.
	spin_prey.queue_free()
	await _step(10)

	# The third spin in a chain has to be the biggest. Measured by the radius the
	# spin reports, which is the same number the damage and knockback scale by.
	var radii: Array[float] = []
	player.abilities.spun.connect(func(_step: int, radius: float) -> void:
		radii.append(radius))
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(60)
	for i in 3:
		Input.action_press("attack")
		await _step(2)
		Input.action_release("attack")
		# Past the cooldown (0.44s = 27 frames) but inside the combo window (0.9s).
		# The chain is the thing being tested, so both bounds matter.
		await _step(32)
	_check("the third spin is the biggest",
		radii.size() == 3 and radii[1] > radii[0] and radii[2] > radii[1],
		"radii=%s" % str(radii))

	# And the chain resets after the third, so the big one is always the pay-off
	# for three presses rather than a lucky accident mid-string.
	_check("the chain resets after the third spin",
		player.abilities.spin_step == 0,
		"step=%d" % player.abilities.spin_step)
	await _step(40)

	# --- spinning in mid-air lifts you, and the chain locks out afterwards so it
	# cannot be ridden upward for ever.
	_release_all()
	_place(PAD_TOP + Vector3(0, 9, 0))
	await _step(24)
	var falling_vy := player.velocity.y
	Input.action_press("attack")
	await _step(2)
	Input.action_release("attack")
	_check("an air spin slows your fall", player.velocity.y > falling_vy + 1.0,
		"vy %.2f -> %.2f" % [falling_vy, player.velocity.y])

	# Three lifts per chain, then nothing until the lockout expires. Pressing
	# through it must do nothing at all.
	_release_all()
	# 60 m up, not 30: three spins plus their cooldowns take about 1.7 seconds, and
	# from 30 m the player reached the ground before the third one, so the check
	# counted two lifts and looked like the chain was short.
	_place(PAD_TOP + Vector3(0, 60, 0))
	await _step(10)
	var lifts := 0
	for i in 3:
		var before_lift := player.velocity.y
		Input.action_press("attack")
		await _step(2)
		Input.action_release("attack")
		if player.velocity.y > before_lift:
			lifts += 1
		await _step(30)
	# The chain is spent, so this press is inside the lockout.
	var locked_from := player.velocity.y
	Input.action_press("attack")
	await _step(2)
	Input.action_release("attack")
	var lifted_again := player.velocity.y > locked_from
	_check("the chain lockout stops an endless air spin",
		lifts == 3 and not lifted_again,
		"%d lifts in the chain, then lifted again=%s" % [lifts, lifted_again])
	_release_all()
	await _step(60)

	# --- a spin trips a switch. The `spinnable` group plus a `spin_hit` method is
	# the whole contract, and this is what makes it extensible.
	var switch := SWITCH.instantiate() as SpinSwitch
	level.add_child(switch)
	switch.global_position = PAD_TOP + Vector3(1.8, 0, 6)
	await _step(10)
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 6))
	await _step(40)
	var switch_before := switch.on
	Input.action_press("attack")
	await _step(3)
	Input.action_release("attack")
	await _step(3)
	_check("a spin trips a switch", switch.on != switch_before,
		"on %s -> %s" % [switch_before, switch.on])
	await _step(40)

	# --- the magnet: a spin drags a carryable to you from further than your
	# hands reach, and you end up holding it. Moving the OBJECT rather than the
	# player is the point — a spin rearranges the level around you.
	_release_all()
	var mag_keg := KEG.instantiate() as Node3D
	level.add_child(mag_keg)
	mag_keg.global_position = PAD_TOP + Vector3(3.4, 0.6, -6)
	await _step(20)
	var keg_start := mag_keg.global_position
	_place(PAD_TOP + Vector3(0, 0.4, -6))
	await _step(40)
	var player_at := player.global_position
	Input.action_press("attack")
	await _step(2)
	Input.action_release("attack")
	for i in 120:
		await _step(1)
		if player.abilities.carried != null:
			break
	var keg_moved := keg_start.distance_to(mag_keg.global_position)
	var player_moved := player_at.distance_to(player.global_position)
	_check("a spin magnets a carryable to you",
		player.abilities.carried == mag_keg and keg_moved > player_moved,
		"keg moved %.2f, player moved %.2f, carried=%s"
			% [keg_moved, player_moved,
				player.abilities.carried.name if player.abilities.carried else "none"])

	# --- attack while holding throws it.
	Input.action_press("attack")
	await _step(3)
	Input.action_release("attack")
	await _step(6)
	_check("attack while holding throws it", player.abilities.carried == null,
		"carried=%s" % (player.abilities.carried.name if player.abilities.carried else "none"))
	await _step(40)

	# --- auto-carry: walk into something and you are holding it, no button.
	_release_all()
	var walk_keg := KEG.instantiate() as Node3D
	level.add_child(walk_keg)
	walk_keg.global_position = PAD_TOP + Vector3(0, 0.6, -14)
	await _step(20)
	# Placed just inside `touch_carry_distance` rather than walked into, because
	# which way "forward" is depends on the camera.
	_place(walk_keg.global_position + Vector3(0.9, 0.0, 0))
	await _step(20)
	_check("walking into a carryable picks it up",
		player.abilities.carried == walk_keg,
		"carried=%s" % (player.abilities.carried.name if player.abilities.carried else "none"))
	player.abilities.throw_carried()
	await _step(40)

	# ------------------------------------------------------- the breakable world
	#
	# Wario goes THROUGH a level rather than over it. Three ways in, and the
	# interesting one is speed: this is the first thing in the project that spends
	# momentum on *access* rather than on distance.

	# Arriving slowly must NOT open it, or "arrive fast" means nothing.
	var wall := BLOCK.instantiate() as BreakableBlock
	level.add_child(wall)
	wall.global_position = PAD_TOP + Vector3(0, 1, -20)
	await _step(10)
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, -14))
	await _step(30)
	player.velocity = Vector3(0, 0, -6)
	await _step(25)
	_check("a slow walk does not break a block", not wall.broken_open,
		"broken=%s at %.1f m/s" % [wall.broken_open, 6.0])

	# Arriving fast does.
	#
	# The speed that survives is sampled from the `broken` signal, not read after
	# a fixed wait. The block restores the player's momentum inside that signal,
	# and the player's own ground handling gets a say on every frame afterwards —
	# so a later reading measures the two of them combined rather than whether
	# the block did its job.
	# An ARRAY, not a float, and appended to rather than assigned.
	#
	# GDScript lambdas capture locals **by value**. `kept_speed = ...` inside the
	# closure writes to the lambda's own copy and the outer variable never
	# changes — which read as "the signal never fired" and sent me looking for a
	# bug in the block that was not there. An Array is a reference, so mutating
	# it is visible outside. Same reason the `radii` capture above works.
	var kept: Array[float] = []
	wall.broken.connect(func(_at: Vector3) -> void:
		kept.append(Vector2(player.velocity.x, player.velocity.z).length()))
	_place(PAD_TOP + Vector3(0, 0.4, -14))
	await _step(20)
	player.velocity = Vector3(0, 0, -18)
	await _step(25)
	_check("arriving fast breaks a block", wall.broken_open,
		"broken=%s" % wall.broken_open)

	# And it does not cost you everything — the whole point of arriving fast is
	# that you keep going.
	_check("smashing through keeps most of your speed",
		kept.size() > 0 and kept[0] > 18.0 * 0.5,
		"%s m/s kept of 18.0" % ("none, the break never fired" if kept.is_empty()
			else "%.1f" % kept[0]))
	await _step(20)

	# A super-spin-only block: any spin must be refused until the third.
	var spin_wall := BLOCK.instantiate() as BreakableBlock
	level.add_child(spin_wall)
	spin_wall.global_position = PAD_TOP + Vector3(1.9, 1, -26)
	spin_wall.break_speed = 999.0
	spin_wall.require_spin_step = 3
	spin_wall.require_slam_power = -1.0
	await _step(10)
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, -26))
	await _step(40)
	Input.action_press("attack")
	await _step(3)
	Input.action_release("attack")
	await _step(4)
	var survived_first := not spin_wall.broken_open
	# Two more to reach the super spin.
	for i in 2:
		await _step(30)
		Input.action_press("attack")
		await _step(3)
		Input.action_release("attack")
	await _step(6)
	_check("only the super spin opens a spin-only block",
		survived_first and spin_wall.broken_open,
		"survived first=%s, open after three=%s"
			% [survived_first, spin_wall.broken_open])
	_release_all()
	await _step(60)

	# A pound-only block, which is what makes a drop worth fetching.
	var pound_wall := BLOCK.instantiate() as BreakableBlock
	level.add_child(pound_wall)
	pound_wall.global_position = PAD_TOP + Vector3(0, 1, -32)
	pound_wall.break_speed = 999.0
	pound_wall.require_spin_step = 0
	pound_wall.require_slam_power = 0.4
	await _step(10)
	_place(PAD_TOP + Vector3(0, 16, -32))
	await _step(10)
	Input.action_press("crouch")
	await _step(3)
	_release_all()
	await _step(70)
	_check("a hard pound opens a pound-only block", pound_wall.broken_open,
		"broken=%s" % pound_wall.broken_open)
	await _step(30)

	# ------------------------------------------------------- transformations
	#
	# Wario Land's best idea: getting hit changes you, and the change is a
	# penalty AND a key. These are a separate axis from health — nothing here
	# touches hearts, damage or death.

	# FLAMING: no steering, and fast enough to open a speed-gated wall for free.
	# That synergy is the whole point, so it is what gets checked rather than the
	# speed on its own.
	var fire_wall := BLOCK.instantiate() as BreakableBlock
	level.add_child(fire_wall)
	fire_wall.global_position = PAD_TOP + Vector3(0, 1, 12)
	await _step(10)
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 4))
	await _step(30)
	player.facing = Vector3(0, 0, 1)
	player.transform_into(Player.State.FLAMING)
	await _step(3)
	var flame_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check("catching fire sprints you without steering",
		player.state == Player.State.FLAMING and flame_speed > player.max_speed * 2.0,
		"state=%s at %.1f m/s (max_speed %.1f)"
			% [player.state_name(), flame_speed, player.max_speed])

	# Held AGAINST the stick, and the thing that matters is the HEADING, not the
	# speed. The first version of this check only watched the speed, so it passed
	# while the player quietly swerved a full 72 degrees off the wall — which is
	# what hid the per-frame steering bug. Measure what the penalty actually is.
	var heading_before := Vector2(player.velocity.x, player.velocity.z).normalized()
	Input.action_press("move_left")
	await _step(12)
	var heading_after := Vector2(player.velocity.x, player.velocity.z).normalized()
	var swerved := rad_to_deg(absf(heading_before.angle_to(heading_after)))
	_release_all()
	_check("a flaming sprint barely answers the stick", swerved < 15.0,
		"swerved %.1f degrees in 12 frames while steering away" % swerved)
	await _step(60)

	# The headline synergy, on its own run with no stick input at all: flame speed
	# is above every block's break_speed, so being alight opens a speed-gated wall
	# with NO code in the block. Checked separately because mixing it with the
	# steering check above is what made the failure ambiguous.
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 4))
	await _step(30)
	player.facing = Vector3(0, 0, 1)
	player.transform_into(Player.State.FLAMING)
	await _step(45)
	_check("being alight opens a speed-gated wall for free", fire_wall.broken_open,
		"broken=%s" % fire_wall.broken_open)

	# And it burns out on its own, or it would be a trap rather than a penalty.
	for i in 240:
		await _step(1)
		if player.state != Player.State.FLAMING:
			break
	_check("the fire burns out on its own",
		player.state != Player.State.FLAMING,
		"state=%s" % player.state_name())
	await _step(20)

	# PUFFY: rises whether you like it or not, and you cannot attack.
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 0))
	await _step(30)
	var puff_from := player.global_position.y
	player.transform_into(Player.State.PUFFY)
	await _step(30)
	_check("being inflated floats you upward",
		player.state == Player.State.PUFFY and player.global_position.y > puff_from + 1.0,
		"state=%s, rose %.2f m" % [player.state_name(), player.global_position.y - puff_from])

	# The spin has to be refused, or the transformation costs nothing.
	var step_before := player.abilities.spin_step
	Input.action_press("attack")
	await _step(3)
	Input.action_release("attack")
	_check("you cannot spin while transformed",
		player.abilities.spin_step == step_before,
		"spin_step %d -> %d" % [step_before, player.abilities.spin_step])

	# Crouch pops it early — the one real choice the state offers.
	Input.action_press("crouch")
	await _step(3)
	_release_all()
	_check("crouch pops you out of being inflated",
		player.state != Player.State.PUFFY and player.velocity.y < 0.0,
		"state=%s vy=%.2f" % [player.state_name(), player.velocity.y])
	await _step(40)

	# --------------------------------------------------------- the money loop
	#
	# Wario Land's core: see a suspicious wall, work out which tool opens it,
	# treasure. The blocks above were two thirds of that; these checks are the
	# third, and the exit is what makes any of it matter.

	# NOTE on the coordinates below: the pad is 60x60 centred on (250, 20, 0), so
	# anything placed outside z -30..+30 drops into the void. The first version of
	# these checks sat the chest at z=-38 and the exit at z=-44, and the player
	# simply fell past both — which read as the chest refusing to open.
	# Money has to actually accumulate, or nothing downstream of it can work.
	var money_seen: Array[int] = []
	Events.money_changed.connect(func(total: int) -> void: money_seen.append(total))
	var money_before := 0
	if not money_seen.is_empty():
		money_before = money_seen[-1]

	# A chest pays a lot more than a coin, which is the whole reason to go and
	# find one rather than hoovering the floor.
	var chest := TREASURE.instantiate() as Treasure
	level.add_child(chest)
	chest.global_position = PAD_TOP + Vector3(1.7, 0, 20)
	chest.worth = 40
	await _step(10)
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 20))
	await _step(40)
	Input.action_press("attack")
	await _step(3)
	Input.action_release("attack")
	await _step(8)
	var after_chest := money_seen[-1] if not money_seen.is_empty() else 0
	_check("a spin opens a chest and it pays",
		chest.open and after_chest >= money_before + 40,
		"open=%s, money %d -> %d" % [chest.open, money_before, after_chest])
	await _step(20)

	# The exit refuses you while you are short, and says by how much. An exit
	# that silently does nothing is indistinguishable from a broken one.
	var refusals: Array[int] = []
	Events.exit_refused.connect(func(_e: Node3D, short: int) -> void:
		refusals.append(short))
	var way_out := EXIT.instantiate() as LevelExit
	level.add_child(way_out)
	way_out.global_position = PAD_TOP + Vector3(0, 0, 26)
	way_out.price = after_chest + 500
	await _step(10)
	_release_all()
	_place(PAD_TOP + Vector3(0, 0.4, 26))
	await _step(25)
	_check("the exit refuses you when you are short and says how much",
		not way_out.cleared and refusals.size() > 0 and refusals[0] > 0,
		"cleared=%s, refused short by %s"
			% [way_out.cleared, "nothing" if refusals.is_empty() else str(refusals[0])])

	# And opens once you can afford it. Priced below what is already banked, then
	# re-entered — the money total is the only thing that changed.
	var cleared_with: Array[int] = []
	Events.level_cleared.connect(func(_e: Node3D, taken: int) -> void:
		cleared_with.append(taken))
	way_out.price = 1
	_place(PAD_TOP + Vector3(0, 0.4, 22))
	await _step(20)
	_place(PAD_TOP + Vector3(0, 0.4, 26))
	await _step(25)
	_check("the exit opens once you can afford it",
		way_out.cleared and cleared_with.size() > 0,
		"cleared=%s, left with %s" % [way_out.cleared,
			"nothing" if cleared_with.is_empty() else str(cleared_with[0])])
	await _step(20)

	# --- a thrown object is a homing, ricocheting rocket (thrown_flight.gd).
	#
	# Both walkers here are spawned rather than borrowed from the level, and set
	# far enough apart that one burst cannot reach the other's test.

	# First: it must actually ricochet, and the bounce count must be what ends
	# the flight. Homing is switched off so it has nothing to chase and has to
	# use the floor, and the rebound is weakened so the second hit comes quickly
	# instead of after a three-second lob.
	# The projectiles below all spawn inside the hub plaza, which is 30x30 centred
	# on the origin: x and z from -15 to 15, top face at y=0. Anything spawned
	# outside that drops into the pit volume, and the check then fails for that
	# reason rather than for the one it is testing.
	#
	# The player is parked on the zone D tower out of the way — these checks do
	# not involve them, and a hub walker wandering into them costs a heart that
	# the damage checks further down then have to account for.
	_place(Vector3(11, 14, 66))
	var bouncer := WALKER.instantiate() as Node3D
	level.add_child(bouncer)
	bouncer.global_position = Vector3(-11, 6, -10)
	await _step(4)
	var bouncer_flight := bouncer.get_node("Flight") as ThrownFlight
	bouncer_flight.homing = false
	bouncer_flight.max_bounces = 1
	bouncer_flight.bounce_energy = 0.15
	bursts = 0
	bouncer_flight.exploded.connect(_on_burst)
	bouncer.call(&"throw", Vector3.DOWN)
	await _step(20)
	_check("thrown object ricochets off a surface",
		bouncer_flight.bounces_used >= 1 and bouncer_flight.flying,
		"bounces=%d flying=%s" % [bouncer_flight.bounces_used, bouncer_flight.flying])
	await _step(120)
	_check("running out of ricochets bursts it", bursts == 1, "bursts=%d" % bursts)

	# Then: speed and homing. The missile is aimed 90 degrees away from its
	# victim on purpose — if it connects, that can only be the steering.
	var victim := WALKER.instantiate() as Node3D
	level.add_child(victim)
	victim.global_position = Vector3(11, 0.8, 11)
	await _step(4)
	var victim_health := victim.get_node("Health") as HealthComponent

	var missile := WALKER.instantiate() as Node3D
	level.add_child(missile)
	missile.global_position = Vector3(3, 2, 11)
	await _step(4)
	var missile_flight := missile.get_node("Flight") as ThrownFlight
	missile.call(&"throw", Vector3.FORWARD)
	await _step(2)
	var locked_on: bool = missile_flight.target == victim

	var was_at: Vector3 = missile.global_position
	await _step(1)
	var rocket_speed := was_at.distance_to(missile.global_position) * 60.0
	_check("thrown object rockets rather than lobs", rocket_speed > 20.0,
		"speed=%.1f m/s" % rocket_speed)
	_check("thrown object homes at an enemy", locked_on,
		"target=%s" % (missile_flight.target.name if missile_flight.target else "none"))

	await _step(100)
	var victim_gone := not is_instance_valid(victim_health)
	_check("homing throw reaches its target",
		victim_gone or victim_health.current < victim_health.max_health,
		"victim %s" % ("killed" if victim_gone else "hp %d" % victim_health.current))
	await _step(20)

	# --- the wall kick, against the tan wall in zone B (face at z=5, spans
	# x 25..45). Capsule edge starts 0.05 m off the face so contact is immediate.
	#
	# This used to accept WALL_RUN or WALL_SLIDE. There is no wall run any more —
	# a wall now always catches you and always offers a kick, which is the point:
	# the old version refused you based on a speed threshold you could not see.
	_place(Vector3(26, 3.5, 4.55))
	player.velocity = Vector3(0.0, -2.0, 3.0)
	await _step(12)
	var wall_state := player.state
	_check("a wall catches you for a kick", wall_state == Player.State.WALL_SLIDE,
		"state=%s" % Player.State.keys()[wall_state])

	# And the kick throws you off it, away from the face.
	Input.action_press("jump")
	await _step(3)
	_release_all()
	_check("the wall kick pushes off and up",
		player.state == Player.State.AIR
			and player.velocity.y > 2.0 and player.velocity.z < -2.0,
		"state=%s vy=%.2f away=%.2f"
			% [player.state_name(), player.velocity.y, player.velocity.z])
	await _step(20)

	# --- a thrown keg leaves at rocket speed.
	#
	# This block used to use the `grab` button for both halves. There is no grab
	# button any more: carrying is automatic on touch, and `attack` throws. The
	# pick-up and the throw each have their own check above; what is still worth
	# measuring here is the SPEED, because a flight that silently fails to start
	# looks identical to a successful throw until you read the number.
	var keg := level.get_node("KegA") as RigidBody3D
	_place(keg.global_position + Vector3(0, 0.4, 1.0))
	await _step(25)
	var held := player.abilities.carried as RigidBody3D
	_check("walking up to a keg carries it", held != null,
		"carried=%s" % (held.name if held != null else "none"))
	Input.action_press("attack")
	await _step(3)
	Input.action_release("attack")
	await _step(6)
	# A thrown keg is frozen and driven by its Flight node, but a kinematic
	# RigidBody3D still reports the velocity implied by its movement — so this
	# reads the rocket speed, and the threshold is set high enough to catch the
	# flight silently not starting and the keg just dropping.
	var thrown_speed := held.linear_velocity.length() if held != null else 0.0
	_check("throw releases keg", player.abilities.carried == null and thrown_speed > 20.0,
		"kegspeed=%.2f" % thrown_speed)
	await _step(20)

	# --- money spilled on a hit. Wario's sting plus Hollow Knight's recovery: the
	# money is not destroyed, it is lying on the floor where you lost it.
	_place(Vector3(11, 14, 66))
	await _step(40)
	var purse_before := 0
	if not money_seen.is_empty():
		purse_before = money_seen[-1]
	var coins_before := level.get_tree().get_nodes_in_group(&"coin").size()
	# A real hit, with damage. The first version of this passed `amount = 0` to
	# isolate the money from the health, and `health.damage(0)` returns false, so
	# take_hit() bailed before emitting anything and all three checks failed.
	#
	# Which confirms a design decision worth keeping: the money loss is gated on
	# the hit LANDING, so invulnerability frames protect your wallet as well as
	# your hearts. You cannot be drained during the flash.
	player.take_hit(1, player.global_position + Vector3(0, 0, 2), 6)
	await _step(4)
	var purse_after := money_seen[-1] if not money_seen.is_empty() else 0
	_check("a hit knocks money out of you", purse_after == purse_before - 6,
		"%d -> %d, expected -6" % [purse_before, purse_after])

	# And it is recoverable, which is the whole reason it is not just a damage
	# bar: the money has to physically exist on the floor afterwards.
	var coins_after := level.get_tree().get_nodes_in_group(&"coin").size()
	_check("the money lands on the floor to be collected",
		coins_after > coins_before,
		"%d coins in the level -> %d" % [coins_before, coins_after])

	# It must never take more than you have. With money as the win condition, a
	# hit that could push you negative would be a lockout waiting to happen.
	#
	# 70 frames, not 30: `invulnerable_time` on the player is 1.0s, so a second
	# hit inside that window is refused outright and this would measure nothing.
	await _step(70)
	var broke_from := money_seen[-1] if not money_seen.is_empty() else 0
	player.take_hit(1, player.global_position + Vector3(0, 0, 2), 99999)
	await _step(4)
	var broke_to := money_seen[-1] if not money_seen.is_empty() else 0
	_check("a hit cannot take more money than you have",
		broke_to == 0 and broke_from >= 0,
		"%d -> %d" % [broke_from, broke_to])
	await _step(40)

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

	# --- stomping a walker.
	#
	# Spawned, not borrowed from the level. This check used to read HubWalkerA
	# and started failing with "walker missing" the moment throws became homing:
	# an earlier check throws a walker, the throw seeks out and bursts on another
	# one, and nothing placed in the level is guaranteed to still be alive by the
	# time the suite gets here. Its own walker makes the check independent.
	var walker := WALKER.instantiate() as Node3D
	level.add_child(walker)
	walker.global_position = Vector3(-4, 0.2, 12)
	await _step(10)
	var walker_health := walker.get_node("Health") as HealthComponent
	var hp_before: int = walker_health.current
	_place(walker.global_position + Vector3(0, 3.0, 0))
	player.velocity = Vector3(0, -6, 0)
	await _step(30)
	# A stomp does 2 damage to a 2 HP walker, so the node is usually gone by
	# now — read health only while it's still valid.
	var killed := not is_instance_valid(walker_health)
	var hp_after := -1 if killed else walker_health.current
	_check("stomp hurts walker", killed or hp_after < hp_before,
		"hp %d -> %d%s" % [hp_before, hp_after, " (killed)" if killed else ""])

	# --- weight and momentum.
	#
	# The ramps are built here rather than read out of the level, for two
	# reasons: test_level.tscn is a moveset showcase with no slopes in it, and
	# the momentum playground is a separate scene this suite does not load.
	# Building them in empty space well away from everything also means no
	# wandering walker or stray keg can touch the measurement.

	var ramp := _add_slope(Vector3(120, 20, 0), 20.0, 40.0)
	await _step(4)

	# Downhill. Started above `max_speed` on purpose: that is the regime the
	# whole system is about. Below it the stick's own deceleration dominates and
	# a shallow slope correctly holds you still.
	var downhill_peak := await _roll_on(ramp, Vector3(120, 28.6, -17), Vector3(0, 0, 9), 150)
	_check("a slope builds speed past max_speed", downhill_peak > player.max_speed * 2.0,
		"9.0 -> %.1f m/s (max_speed %.1f)" % [downhill_peak, player.max_speed])

	# Uphill has to cost you, or weight is not a trade. 9 m/s should not survive
	# more than a few metres of climb.
	await _roll_on(ramp, Vector3(120, 15.0, 17), Vector3(0, 0, -9), 90)
	var uphill_left := Vector2(player.velocity.x, player.velocity.z).length()
	_check("uphill spends your momentum", uphill_left < 2.0,
		"9.0 -> %.1f m/s" % uphill_left)

	# Flat ground must never be a source of speed, only a slow drain of it.
	var flat_pad := _add_slope(Vector3(170, 20, 0), 0.0, 40.0)
	await _step(4)
	# Note `momentum_friction` only bleeds the surplus down TO `max_speed`; with
	# no stick input the ordinary `deceleration` then takes over and brings you
	# to a stop, which is why this does not assert a floor at `max_speed`.
	var flat_peak := await _roll_on(flat_pad, Vector3(170, 21.6, -10), Vector3(0, 0, 9), 40)
	var flat_left := Vector2(player.velocity.x, player.velocity.z).length()
	_check("flat ground never adds speed", flat_peak <= 9.2 and flat_left < 9.0,
		"9.0 -> peak %.1f -> %.1f m/s" % [flat_peak, flat_left])

	# The cost side of heaviness: getting going takes real time. Any direction
	# works, so this does not care where the camera is pointing.
	_place(Vector3(170, 21.6, 0))
	await _step(30)
	Input.action_press("move_right")
	var frames_to_speed := -1
	for i in 120:
		await _step(1)
		if Vector2(player.velocity.x, player.velocity.z).length() >= player.max_speed * 0.9:
			frames_to_speed = i
			break
	_release_all()
	_check("a heavy character takes time to get going", frames_to_speed > 12,
		"%d frames to reach 90%% of max_speed" % frames_to_speed)
	await _step(20)

	# --- weight acting on the world: a floor only a heavy impact breaks.
	# Placed well clear of the flat pad above. The first version of this check sat
	# the slab at (170, 19.5, 14), which is INSIDE the pad — so the player landed
	# on the pad every time, never touched the slab, and "standing on it does not
	# break it" passed for the wrong reason entirely.
	var slab := CRUMBLING.instantiate() as CrumblingFloor
	level.add_child(slab)
	slab.global_position = Vector3(210, 20, 0)
	await _step(4)
	# The slab's own top surface, which is where the player stands. The player's
	# origin is at its feet, so this is also the standing height.
	var slab_top: Vector3 = slab.global_position + Vector3(0, 0.5, 0)

	# Standing on it is not an impact, however heavy you are. Dropped from only
	# 0.3 m so the landing speed is nowhere near `break_fall_speed`.
	_place(slab_top + Vector3(0, 0.3, 0))
	await _step(45)
	_check("standing on a crumbling floor does not break it",
		slab.state == CrumblingFloor.State.WHOLE,
		"state=%s after a 0.3 m step down" % CrumblingFloor.State.keys()[slab.state])

	# Arriving fast is. Note it cracks first and gives way after `warn_time`, so
	# this waits long enough for both.
	_place(slab_top + Vector3(0, 3, 0))
	player.velocity = Vector3(0, -20, 0)
	await _step(60)
	_check("a heavy landing breaks a crumbling floor",
		slab.state != CrumblingFloor.State.WHOLE,
		"state=%s" % CrumblingFloor.State.keys()[slab.state])
	await _step(20)

	# --- enemies and turrets survive a long idle without erroring
	await _step(120)
	_check("no crash after idle", is_instance_valid(player), "state=%s" % player.state_name())

