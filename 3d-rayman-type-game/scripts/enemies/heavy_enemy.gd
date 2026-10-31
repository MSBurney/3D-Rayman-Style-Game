class_name HeavyEnemy
extends CharacterBody3D

## A big, slow mass that walks. **A mobile puzzle element first and a combat
## target second** — the doc's "fewer, larger, structural" enemy.
##
## ─── IT IS A PUZZLE NOUN, AND THE LEVEL SUPPLIES THE VERBS ───────────────────
##
## The doc asks each enemy to be *"a system that recombines across many rooms,
## not an encounter to balance"*, and lists what rooms should be able to do with
## one. Every item on that list already works, and **almost none of it is code
## in this file** — it falls out of having a `mass` and being in the `enemy`
## group, because `weight.gd` is what every prop asks:
##
##   - **a counterweight** — it tips a `SeeSaw`, through `WeightSensor`
##   - **a pressure-plate holder** — it holds a `PressurePlate` down, same way
##   - **a wall-breaker you aim** — lure it into a `BreakableBlock` and its own
##     momentum opens it, because the block asks how heavy and how fast
##   - **a hazard the level exploits** — it falls through a `CrumblingFloor`
##     whose `break_mass` sits between its weight and the hero's
##   - **a bridge, once felled** — see `_topple()`
##
## That list is the argument for the weight layer in one paragraph. Adding this
## enemy needed no change to a single prop.
##
## ─── NOT NAMED AFTER ANYTHING ────────────────────────────────────────────────
##
## The doc's crew (a tortoise, storks, a pelican, weaver-birds) sits under a
## section marked **"DRAFT, return to this"**, so this is `HeavyEnemy` and not
## any of them. It is the mass and the behaviour; the costume is a later
## decision that this file should not quietly make.

enum State {
	WALKING,
	## Felled. Lying down, inert, still heavy — and walkable.
	TOPPLED,
}

@export_group("Weight")
## Heavy enough that the hero cannot out-push it, light enough that a committed
## charge still fells it. Everything else about this enemy is downstream of this
## number, which is the point.
@export var mass: float = 40.0

@export_group("Movement")
@export var walk_speed: float = 3.2
@export var accel: float = 5.0
## It comes after you inside this range and ignores you outside it. **Being
## lurable is the whole interface a puzzle needs** — every structural use of
## this enemy is "get it to stand somewhere", so the room is solved by walking.
@export var lure_range: float = 18.0
## It gives up and goes home past this. Without it a single enemy can be walked
## across the entire level and no room can rely on where it is.
@export var leash_range: float = 34.0
@export var gravity: float = 30.0
@export var turn_speed: float = 4.0

@export_group("Toppling")
## MOMENTUM needed to fell it — mass times closing speed, not speed alone.
##
## The bar sits above what a walk delivers and below a charge. Note that the
## speed is RELATIVE, so his own approach counts towards it: against a giant
## walking at you, the hero at `mass` 10 brings about **182 at walking pace and
## 232 charging**. **So only a committed charge fells him**, which is the doc's
## "aiming before committing is the skill" expressed as one number rather than
## as a special case.
##
## The first version read 180 and measured the hero's speed alone, so a charge
## without a long run-up quietly failed — and failed SILENTLY, which is the
## worse half. See `_stagger()`.
@export var topple_momentum: float = 200.0
## A slam landing this close and this hard fells it too — the signature verb has
## to work on the signature enemy.
@export var slam_topple_force: float = 0.8
@export var slam_topple_radius: float = 4.5
## How long it stays down. **Negative means felled for good**, which is rule 6
## (broken stays broken) applied to an enemy: a giant you dropped across a gap
## is a bridge you built, and it should still be there when you come back.
@export var get_up_delay: float = 7.0
## Seconds of blindness after being hit, so one collision is not counted on
## several consecutive frames while the two bodies are still overlapping.
@export var hit_cooldown: float = 0.4

@export_group("Contact")
## How much of an impact is exchanged when it walks into something, and when
## something walks into it. Rule 2 both ways, through `Weight.collide`.
@export var push_transfer: float = 1.0
@export var push_min_speed: float = 1.5
## Groups it checks for incoming impacts. Everything that can hurt a giant is
## something with a mass and a speed.
@export var hit_groups: Array[StringName] = [&"player", &"heavy", &"throwable"]
## How close an impact has to be to count, measured centre to centre.
@export var hit_radius: float = 1.6

@export_group("Juice")
@export var topple_fx: PackedScene
@export var topple_colour: Color = Color(0.85, 0.7, 0.35)
## Dust on a hit he shrugged off. Far from `topple_colour` in hue, because two
## outcomes in the same colour is the same as no tell at all.
@export var stagger_colour: Color = Color(0.55, 0.65, 0.95)

signal toppled(at: Vector3, by: Node3D)
signal got_up
## A hit that was not enough, and HOW not enough: `share` is the fraction of
## `topple_momentum` that arrived. A HUD could turn that into a hint.
signal shrugged_off(by: Node3D, share: float)

var state: State = State.WALKING
var facing: Vector3 = Vector3.FORWARD

var _down_left: float = 0.0
var _hit_left: float = 0.0
var _home: Vector3
var _home_set: bool = false
var _pre_move_flat: Vector3 = Vector3.ZERO
var _pre_move_vy: float = 0.0
var _lean: Tween = null

@onready var standing_shape: CollisionShape3D = $Standing
## Low and long, enabled only while felled. Two shapes rather than one rotated
## shape, because a toppled giant has to be something you can WALK ON, and a
## standing box turned on its side is a 1.6 m kerb rather than a bridge.
@onready var felled_shape: CollisionShape3D = $Felled
@onready var visual: Node3D = $Visual


func _ready() -> void:
	add_to_group(&"enemy")
	# Also `heavy`, so a slam's shockwave and anything else that walks the loose
	# -object groups can reach it. The momentum it receives is divided by its own
	# mass, so being in the group costs it almost nothing — see
	# `Weight.add_momentum`.
	add_to_group(&"heavy")
	facing = -global_transform.basis.z
	felled_shape.disabled = true
	Events.slam_landed.connect(_on_slam_landed)


func _physics_process(delta: float) -> void:
	# Captured on the first physics frame rather than in _ready(): a node spawned
	# from code is positioned a line AFTER it enters the tree, so a home read too
	# early is the level origin.
	if not _home_set:
		_home = global_position
		_home_set = true

	_hit_left -= delta
	_take_incoming_hits()

	match state:
		State.WALKING:
			_walk(delta)
		State.TOPPLED:
			_lie_still(delta)

	_pre_move_flat = Vector3(velocity.x, 0.0, velocity.z)
	_pre_move_vy = velocity.y
	move_and_slide()
	_shove_what_we_hit()
	_update_visual(delta)


func _walk(delta: float) -> void:
	var wanted := Vector3.ZERO
	var player := _nearest_player()
	if player != null:
		var gap := global_position.distance_to(player.global_position)
		if gap < leash_range:
			wanted = (player.global_position - global_position)
		elif global_position.distance_to(_home) > 1.0:
			# Lost interest. Walks home rather than stopping where it was left,
			# so a room can rely on finding it where it was placed.
			wanted = _home - global_position

	wanted.y = 0.0
	if wanted.length_squared() > 0.01:
		wanted = wanted.normalized()
		facing = facing.slerp(wanted, clampf(turn_speed * delta, 0.0, 1.0)).normalized()
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		flat = flat.move_toward(wanted * walk_speed, accel * delta)
		velocity.x = flat.x
		velocity.z = flat.z
	else:
		velocity.x = move_toward(velocity.x, 0.0, accel * delta)
		velocity.z = move_toward(velocity.z, 0.0, accel * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _lie_still(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, accel * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, accel * 2.0 * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if get_up_delay < 0.0:
		return
	_down_left -= delta
	if _down_left <= 0.0:
		_stand_up()


## Only the nearest player, and only if there is one. Walked by group rather
## than held as a reference, so this enemy works in any scene without wiring.
func _nearest_player() -> Node3D:
	var best: Node3D = null
	var closest := lure_range
	for node in get_tree().get_nodes_in_group(&"player"):
		var body := node as Node3D
		if body == null:
			continue
		var gap := global_position.distance_to(body.global_position)
		if gap < closest:
			closest = gap
			best = body
	return best


# ────────────────────────────────────────────────── being hit, and going down

## Looks for anything arriving at us hard enough to matter.
##
## Walked by GROUP and distance rather than with an `Area3D`, for the three
## reasons this project keeps running into: an area moved and queried in the
## same frame reports nothing, a settled `RigidBody3D` is asleep and unreliable
## in overlap queries, and `body_entered` only fires on ENTRY — so a player
## already leaning on us who then charges would never be noticed at all.
func _take_incoming_hits() -> void:
	if _hit_left > 0.0:
		return
	for group in hit_groups:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or body == self:
				continue
			var offset := global_position - body.global_position
			var gap := offset.length()
			if gap > hit_radius or gap < 0.01:
				continue

			var normal := -offset / gap
			# RELATIVE closing speed. Measuring only the other body's velocity
			# meant that a giant walking into a player who was standing still
			# registered zero and did nothing whatsoever — reported from play,
			# accurately, as "the enemy doesn't seem to do anything to me".
			var closing := Weight.closing_speed(body, self, normal)
			if closing < push_min_speed:
				continue
			_hit_left = hit_cooldown

			# MOMENTUM, not speed: a fast pebble is not a felled giant. This one
			# number is the whole difference between the right tool and the
			# wrong one, and `deliver` rather than `collide` because nothing
			# here was stopped by the solver — see `weight.gd` on the two.
			var share := Weight.mass_of(body) * closing / maxf(topple_momentum, 0.01)
			if share >= 1.0:
				# They won, so the reaction is light: you plough on through the
				# thing you just felled rather than bouncing off it.
				Weight.deliver(body, self, normal, global_position,
					push_transfer * 0.3, push_min_speed)
				_topple(body)
			else:
				Weight.deliver(body, self, normal, global_position,
					push_transfer, push_min_speed)
				_stagger(share, body)
			return


func _on_slam_landed(at: Vector3, force: float) -> void:
	if state == State.TOPPLED or force < slam_topple_force:
		return
	if global_position.distance_to(at) > slam_topple_radius:
		return
	_topple(null)


## Down it goes.
##
## **A felled giant is a bridge** — the doc's first example of an enemy as a
## puzzle noun. So the standing collider is swapped for a low, long one rather
## than being rotated: a 3.5 m box tipped on its side is a kerb you cannot climb,
## and the whole value of toppling one is that you can now walk over it.
## A hit that was not enough.
##
## **A refused hit has to read as "wrong tool", never as "no effect".** It is the
## same law that makes a refused `BreakableBlock` shake instead of sitting there
## and makes the warden boss announce what would work — and the first version of
## this enemy broke it outright. Anything under the bar did absolutely nothing,
## and it came back from play as *"I tried to ram into the enemy, but there was
## no response."* That report was correct, and it was about the missing feedback
## at least as much as about the threshold.
##
## The stagger SCALES with how close the hit came, so a near miss rocks him hard
## and a feeble bump barely moves him. That makes the threshold legible without
## a word of UI — the same trick as a pressure plate tinting as it fills.
func _stagger(share: float, by: Node3D) -> void:
	var strength := clampf(share, 0.15, 1.0)
	if _lean != null and _lean.is_valid():
		_lean.kill()
	_lean = create_tween()
	_lean.tween_property(visual, "rotation:x", -deg_to_rad(16.0) * strength, 0.07) \
		.set_ease(Tween.EASE_OUT)
	_lean.tween_property(visual, "rotation:x", 0.0, 0.3) \
		.set_trans(Tween.TRANS_ELASTIC)
	_puff(stagger_colour, int(round(4.0 + 10.0 * strength)), 2.5 + 3.5 * strength)
	shrugged_off.emit(by, share)


func _topple(by: Node3D) -> void:
	if state == State.TOPPLED:
		return
	state = State.TOPPLED
	# Killed, or the stagger it was in the middle of fights the fall and he ends
	# up standing back up on his own.
	if _lean != null and _lean.is_valid():
		_lean.kill()
	_down_left = get_up_delay
	# Deferred: swapping collision shapes inside a physics query is exactly what
	# Godot warns about, and `_take_incoming_hits` runs mid-step.
	standing_shape.set_deferred(&"disabled", true)
	felled_shape.set_deferred(&"disabled", false)

	var tween := create_tween()
	tween.tween_property(visual, "rotation:x", -PI * 0.5, 0.35) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	_puff(topple_colour, 18, 5.0)
	toppled.emit(global_position, by)


func _stand_up() -> void:
	state = State.WALKING
	standing_shape.set_deferred(&"disabled", false)
	felled_shape.set_deferred(&"disabled", true)
	var tween := create_tween()
	tween.tween_property(visual, "rotation:x", 0.0, 0.4) \
		.set_ease(Tween.EASE_OUT)
	got_up.emit()


# ───────────────────────────────────────────────────────────── the basics

## Pushes whatever it walked into. **The "six lines" the weight layer promised:**
## the arithmetic is shared with the hero, so a giant shouldering a crate out of
## the way can never disagree with the hero doing it.
func _shove_what_we_hit() -> void:
	var done: Array[RigidBody3D] = []
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider() as RigidBody3D
		if body == null or done.has(body):
			continue
		done.append(body)
		Weight.collide(self, body, hit.get_normal(), hit.get_position(),
			push_transfer, push_min_speed)


func _update_visual(delta: float) -> void:
	if state == State.TOPPLED or facing.length_squared() < 0.01:
		return
	var wanted := atan2(facing.x, facing.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, wanted, turn_speed * delta)


func _puff(tint: Color, amount: int, speed: float) -> void:
	if topple_fx == null:
		return
	var puff := topple_fx.instantiate() as Node3D
	get_tree().current_scene.add_child(puff)
	puff.global_position = global_position + Vector3.UP * 1.4
	if puff.has_method(&"play"):
		puff.call(&"play", tint, amount, speed, Vector3.UP)


# ─────────────────────────────────────────── what props are allowed to ask

## Horizontal velocity from BEFORE collision resolution — the same contract both
## player controllers honour, so `Weight.impact_velocity()` reads this enemy
## exactly as it reads them. Without it a giant lured into a breakable wall
## would arrive measuring zero, because `move_and_slide()` stops it against the
## block in the same step the block's sensor fires.
func approach_velocity() -> Vector3:
	return _pre_move_flat


func approach_speed() -> float:
	return _pre_move_flat.length()


func descent_speed() -> float:
	return _pre_move_vy


func is_down() -> bool:
	return state == State.TOPPLED


func state_name() -> String:
	return State.keys()[state]
