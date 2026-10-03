class_name PlayerAbilities
extends Node

## The things the player does that are not locomotion: the spin attack, and
## picking things up and throwing them.
##
## These live here rather than in player.gd because none of them touch the state
## machine — you can spin while running, jumping or falling, exactly as you can
## in Mario Galaxy. Keeping them out means player.gd stays about *movement*.
##
## ### What the spin replaced
##
## This used to be a Yoshi-style tongue, and before that a grapple hook and a
## swing. The spin took over from all of it on 2026-10-02. It is a better fit for
## the same reason the swing was a bad one: a grapple is a *traversal* system, so
## every level has to be designed around where you can and cannot hook. A spin is
## an *action* with a radius, so a level only has to care about what is standing
## near the player.
##
## ### One button, three outcomes
##
## `attack` does whatever makes sense for what you are holding:
##
##   • holding nothing  → spin. Hurts enemies, pulls carryables in, trips
##                        switches, and chains into a bigger spin if repeated.
##   • holding something → throw it.
##
## The player calls [method handle_input] once a frame from its own input step,
## rather than this node reading input on its own, so the order things happen in
## stays visible in one place.

## Emitted on every spin, with how far through the chain it is (1, 2 or 3) and
## the radius it actually used. The HUD and any effects can read it; nothing has
## to reach into this script.
signal spun(step: int, radius: float)

@export_group("Spin")
## How long one spin lasts. The hit lands at the start; this is how long the
## magnet keeps pulling and how long the visual runs for.
@export var spin_time: float = 0.34
## Press again inside this and the next spin is the bigger one. Measured from the
## START of the previous spin, so it has to clear the whole of `spin_time` plus
## `spin_cooldown` before the player gets any opportunity at all.
##
## At 0.5 with the other defaults that left about 0.06s of actual window, which
## is frame perfect and reads as the chain being broken. Keep it comfortably
## above `spin_time + spin_cooldown` (0.44) or chaining becomes a lottery.
@export var spin_combo_window: float = 0.9
## Dead time after a spin before another can start, so holding the button does
## not machine-gun.
@export var spin_cooldown: float = 0.1
## Reach of the first spin in a chain.
@export var spin_radius: float = 2.6
@export var spin_damage: int = 1
## How hard a spin shoves what it hits.
@export var spin_knockback: float = 7.0
## Reach and force of the second spin, as a multiple of the first.
@export var spin_second_scale: float = 1.25
## ...and the third, which is the big one. The user's words: "the third spin
## being the largest and most powerful".
@export var spin_third_scale: float = 1.7
## Extra damage on that third spin, on top of the scaling.
@export var spin_third_damage_bonus: int = 2
## The ring drawn at the spin's real radius — the same scene the ground pound
## uses. Without it the reach is invisible and the chain cannot be read at all.
@export var spin_fx: PackedScene

@export_subgroup("Air spin")
## Spinning in mid-air gives you a little lift, as in Mario Galaxy.
##
## It is applied as `min(velocity.y + boost, boost)`, which is two useful things
## in one line: falling slowly, you get a small hop; falling fast, you get your
## descent slowed but NOT cancelled. Deliberately not a plain assignment —
## wiping a 20 m/s fall would make the character feel weightless, and heaviness
## is the whole identity.
@export var spin_air_boost: float = 5.0
## Dead time after the third spin in a chain before you can spin again at all.
##
## This is the anti-abuse rule: three lifts per chain is a deliberate burst of
## extra airtime, but without a pause between chains you could spin your way
## upward for ever. Holding the button through the lockout does nothing.
@export var spin_chain_lockout: float = 0.85
## Colour of the puff thrown by an air spin, so the lift is visible as well as
## felt. Uses the same effect as the jumps — see Player.spawn_jump_fx.
@export var spin_boost_colour: Color = Color(0.8, 0.7, 1.0)

@export_group("Carry")
## Walk within this of a carryable and you pick it up, no button needed. The
## user asked for this directly: "the player can also auto-carry items by just
## walking towards the object and touching it".
@export var touch_carry_distance: float = 1.3
## A spin reaches further than your hands do, and anything carryable inside this
## gets dragged to you — the Mario Galaxy pull.
@export var magnet_radius: float = 5.0
## How fast the magnet drags it in.
@export var magnet_speed: float = 20.0
## Close enough to count as caught.
@export var magnet_catch_distance: float = 1.2
## Give up after this long; the target may be wedged on scenery.
@export var magnet_timeout: float = 1.6
## Blind spell after a throw, so the object you just threw is not instantly
## re-collected by the auto-carry while it is still next to you.
@export var regrab_delay: float = 0.45
## How far above horizontal a throw sets off, as rise over forward run. Only the
## DIRECTION is decided here — the speed belongs to the thrown object's own
## `Flight` node (see thrown_flight.gd), because a thrown thing rockets at a
## fixed pace and steers itself rather than being lobbed at a chosen strength.
@export var throw_rise: float = 0.22

## What we are currently holding, or null. Read by the HUD and the respawn code.
var carried: Node3D = null
## What the magnet is currently dragging in, or null. Not "carried" yet.
var magnetised: Node3D = null
## Seconds of spin left to run. Above zero means we are mid-spin, which the
## visuals read and which keeps the magnet pulling.
var spin_left: float = 0.0
## How far through a chain the current spin is: 1, 2 or 3. Zero between chains.
var spin_step: int = 0

var _combo_left: float = 0.0
var _cooldown: float = 0.0
var _magnet_time: float = 0.0
var _regrab_left: float = 0.0

@onready var _player: Player = get_parent() as Player


func handle_input(delta: float) -> void:
	_cooldown -= delta
	_combo_left -= delta
	_regrab_left -= delta
	spin_left -= delta

	# The chain lapses on its own, so a spin ages out of being part of one.
	if _combo_left <= 0.0:
		spin_step = 0

	_tick_magnet(delta)
	_auto_carry()

	if Input.is_action_just_pressed(&"attack"):
		if carried != null:
			throw_carried()
		else:
			_spin()


# ----------------------------------------------------------------- spin attack

## One spin. Resolves its whole hit immediately — damage, knockback, switches and
## starting the magnet all happen on the frame you press it.
##
## `spin_left` is only how long the spin is notionally still happening, for the
## F3 readout and for any visual to hang off. The magnet deliberately does NOT
## stop with it: once something is latched it keeps coming until it arrives or
## times out, because dropping an object half way for being slow is worse than
## waiting an extra moment for it.
func _spin() -> void:
	if _cooldown > 0.0:
		return

	spin_step = mini(spin_step + 1, 3)
	_combo_left = spin_combo_window
	_cooldown = spin_time + spin_cooldown
	spin_left = spin_time
	_magnet_time = 0.0

	var scale := 1.0
	var damage := spin_damage
	match spin_step:
		2:
			scale = spin_second_scale
		3:
			scale = spin_third_scale
			damage += spin_third_damage_bonus
	var radius := spin_radius * scale

	_spawn_spin_fx(radius)
	_hit_enemies(radius, damage, spin_knockback * scale)
	_trip_switches(radius)
	_grab_nearest_within(magnet_radius * scale)

	_air_lift()
	_player.play_sfx(_player.sfx_spin)
	spun.emit(spin_step, radius)

	# The third spin ends the chain rather than wrapping round to the first, so
	# the big one is always the pay-off for three presses and never a lucky
	# accident in the middle of a longer string. It also locks the spin out for
	# a moment, which is what stops the air lift being an infinite ladder.
	if spin_step >= 3:
		spin_step = 0
		_combo_left = 0.0
		_cooldown = maxf(_cooldown, spin_chain_lockout)


## A little lift for spinning in mid-air, as in Mario Galaxy.
##
## Gated on `State.AIR` rather than just `not is_on_floor()`, which matters: it
## means a spin cannot rescue you out of a ground pound, a wall cling or a ledge
## hang. Those are committed states and the spin has no business overriding them.
func _air_lift() -> void:
	if _player.state != Player.State.AIR:
		return
	# min(v + boost, boost): a slow fall becomes a small hop, a fast fall is
	# merely slowed. See spin_air_boost for why it is not a plain assignment.
	_player.velocity.y = minf(_player.velocity.y + spin_air_boost, spin_air_boost)
	_player.spawn_jump_fx(spin_boost_colour, 10, 4.0, Vector3.DOWN)


## Everything hostile in reach takes the hit and gets shoved away.
##
## Walks the `enemy` group by distance rather than using an Area3D, the same way
## the ground pound's shockwave does. An Area3D added and queried in the same
## frame reports nothing, and a spin has to resolve the instant it is pressed.
func _hit_enemies(radius: float, damage: int, knockback: float) -> void:
	var origin := _player.global_position + Vector3.UP * 0.7
	for node in _player.get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Node3D
		if enemy == null:
			continue
		var offset := enemy.global_position - origin
		if offset.length() > radius:
			continue
		var health := enemy.get_node_or_null(^"Health") as HealthComponent
		if health != null:
			health.damage(damage)
		var body := enemy as CharacterBody3D
		if body != null:
			var away := _flat(offset)
			if away == Vector3.ZERO:
				away = _flat(_player.facing)
			body.velocity += away * knockback + Vector3.UP * knockback * 0.3


## Anything that wants to react to a spin joins the `spinnable` group and
## implements `spin_hit(by)`.
##
## This is the extension point for "a variety of other interactions" — switches
## today, and whatever else later, with no change needed in here. A prop never
## needs a reference to the player and the player never needs to know the prop
## exists.
func _trip_switches(radius: float) -> void:
	var origin := _player.global_position + Vector3.UP * 0.7
	for node in _player.get_tree().get_nodes_in_group(&"spinnable"):
		var thing := node as Node3D
		if thing == null or not thing.has_method(&"spin_hit"):
			continue
		if origin.distance_to(thing.global_position) > radius:
			continue
		thing.call(&"spin_hit", _player)


func _spawn_spin_fx(radius: float) -> void:
	if spin_fx == null:
		return
	var ring := spin_fx.instantiate() as Node3D
	_player.get_tree().current_scene.add_child(ring)
	ring.global_position = _player.global_position + Vector3.UP * 0.5
	if ring.has_method(&"play"):
		# `combo` recolours the ring, so the third spin is visibly the big one.
		ring.call(&"play", radius, spin_step >= 3)


# ------------------------------------------------------------ carrying things

## Starts the magnet on the nearest carryable in reach, if we are free to hold
## something. Called by the spin, so a spin is also how you reach for things.
func _grab_nearest_within(radius: float) -> void:
	if carried != null or magnetised != null or _regrab_left > 0.0:
		return
	var best := _nearest_carryable(radius)
	if best == null:
		return
	magnetised = best
	_magnet_time = 0.0
	# Lets an enemy know to stop hurting the player while it is being dragged
	# in. Objects that do not care simply do not implement it.
	if best.has_method(&"being_pulled"):
		best.call(&"being_pulled", _player)


## Nearest thing in the `throwable` group, or null.
##
## Walks the group by distance rather than using an Area3D, because a keg that
## has come to rest is a SLEEPING RigidBody3D, and sleeping bodies are unreliable
## in area overlap queries — you would walk up to an untouched keg and find it
## stubbornly ungrabbable.
func _nearest_carryable(radius: float) -> Node3D:
	var best: Node3D = null
	var best_distance := radius * radius
	var origin := _player.global_position + Vector3.UP * 0.8
	for node in _player.get_tree().get_nodes_in_group(&"throwable"):
		var body := node as Node3D
		if body == null or not body.has_method(&"pick_up"):
			continue
		var d := origin.distance_squared_to(body.global_position)
		if d < best_distance:
			best_distance = d
			best = body
	return best


## Touch something carryable and you are carrying it. No button.
func _auto_carry() -> void:
	if carried != null or magnetised != null or _regrab_left > 0.0:
		return
	var touched := _nearest_carryable(touch_carry_distance)
	if touched == null:
		return
	carried = touched
	touched.call(&"pick_up", _player)


## Drags whatever the magnet caught toward the hold point. Moving the OBJECT
## rather than the player is the point: a spin rearranges the level around you,
## it does not move you around the level.
func _tick_magnet(delta: float) -> void:
	if magnetised == null:
		return
	if not is_instance_valid(magnetised) or carried != null:
		magnetised = null
		return

	_magnet_time += delta
	var hold := _player.hold_point
	var goal := hold.global_position if hold != null else _player.global_position
	var offset := goal - magnetised.global_position
	var distance := offset.length()

	if distance <= magnet_catch_distance:
		var caught := magnetised
		magnetised = null
		carried = caught
		caught.call(&"pick_up", _player)
		return

	if _magnet_time > magnet_timeout:
		magnetised = null
		return

	magnetised.global_position += offset / distance * magnet_speed * delta


func throw_carried() -> void:
	if carried == null:
		return
	var thrown := carried
	carried = null
	# Without this the auto-carry picks the thing straight back up while it is
	# still a metre away, and a throw looks like it did nothing.
	_regrab_left = regrab_delay
	if thrown.has_method(&"throw"):
		var aim := _flat(_player.facing) + Vector3.UP * throw_rise
		thrown.call(&"throw", aim)


## Used when respawning, so a keg is never left stuck to a dead player.
func drop_everything() -> void:
	carried = null
	magnetised = null
	spin_left = 0.0
	spin_step = 0
	_combo_left = 0.0
	_regrab_left = 0.0
	# The cooldown goes too. Respawning into a lockout left over from the spin you
	# were mid-chain on when you died would read as the button being broken.
	_cooldown = 0.0


func _flat(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO
