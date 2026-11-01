class_name BossWarden
extends CharacterBody3D

## The first boss, and an attempt at the thing Wario Land never solved.
##
## ─── WHAT IT IS FOR ──────────────────────────────────────────────────────────
##
## **You do not kill it. It has no health at all.** You beat it by taking the
## seed off it and delivering that seed to the socket, which is what raises the
## platform to the exit. So the boss is not a damage sponge with a key — the
## HOSTAGE SYSTEM IS ITS HEALTH BAR, and the fight ends on a specific act rather
## than on an accumulation of hits.
##
## That is the whole reason it exists. A boss is a gate, and until now it was
## only a gate in the story. This one is a gate mechanically: the exit is up
## there, the platform is the only way up, and the seed is in its hands.
##
## ─── WHY WARIO LAND'S BOSSES FAILED, AND THE RULE THAT FOLLOWS ───────────────
##
## No-death is only half of it. The deeper problem is that those bosses never
## told you what they wanted, so you flailed until something worked.
##
## So: **every refusal here says what WOULD work**, on `Events.boss_refused`,
## and the HUD prints it. A refused attack has to read as "wrong tool", never as
## "no effect" — the same rule that makes a refused `BreakableBlock` shake
## rather than sit there. Treat those hint strings as mechanics, not flavour; a
## phase without one is a phase the player has to brute-force.
##
## ─── THREE PHASES, THREE DIFFERENT VERBS ─────────────────────────────────────
##
## Each phase is a lock opened by a different thing the game already taught, and
## none of them is "hit it until it dies":
##
##   ARMOURED  it charges you in straight lines and refuses everything. Dodge so
##             it crashes into a pillar and stuns itself. Tests reading a
##             telegraph and using the arena.
##   STUNNED   only a GROUND POUND cracks it, and only with enough
##             `crack_power` — which means fall distance, so you have to already
##             be up high when you stun it. Tests the project's signature verb.
##   CRACKED   it drops the seed and turns into a very large snatcher. Get the
##             seed to the socket before it gets the seed back. Tests carrying
##             under pressure, throwing something to buy time, and momentum.
##
## **The spin never works on it.** That is deliberate: the player's default
## attack being useless is what forces the other three verbs to be learned, and
## it is only fair because every refusal announces the alternative.
##
## ─── THE FAIL STATE, WHICH IS NOT DEATH ──────────────────────────────────────
##
## Hit you and it takes money. Hit you while you are CARRYING THE SEED and it
## takes the seed back and re-armours — you lose a phase, not a life. No timer:
## WL4 bolted one onto its bosses as a patch and this project has said so since
## the transformations went in.

## A level marks the things a charge can stun the boss on by putting them in
## this group. See _hit_a_pillar().
const PILLAR_GROUP := &"pillar"

enum Phase {
	## Charging, invulnerable, holding the seed.
	ARMOURED,
	## Bonked itself on a pillar. The pound window.
	STUNNED,
	## Open, and racing you for the seed it just dropped.
	CRACKED,
	## Lost. The seed is spent, so it cannot re-arm.
	BEATEN,
}

@export_group("Charging")
@export var charge_speed: float = 11.0
## How long it stands still and tells you it is about to charge.
##
## The telegraph is the fight. Without it a charge is unreadable and the only
## way to learn the pattern is to be hit by it, which is the kind of boss this
## is trying not to be.
@export var windup_time: float = 0.9
## How long one charge lasts before it stops and lines up again.
@export var charge_time: float = 1.6
@export var turn_speed: float = 4.0
## How long it spends reversing out of something that was not a pillar. Without
## this the boss pins itself against a wall for ever — see `_bounce_off()`.
@export var recover_time: float = 0.9
## Fraction of `charge_speed` it backs off at. Deliberately well under 1: this
## should read as a stagger away from the wall, not a second charge.
@export var recover_speed_scale: float = 0.45
@export var gravity: float = 24.0

@export_group("The pound window")
## How long it stays stunned after crashing. Generous on purpose: you have to
## get up somewhere high and come down on it, and a window that only a player
## who was already standing in the right place can use is not a test of skill.
## **7.0, up from 3.2, because the opening got harder to use rather than easier.**
##
## The modal controller cannot reach `crack_power` from a standing drop — it
## needs to be above the boss AND moving, which is a charge along the pound deck
## cancelled into a slam. That is a genuinely longer thing to arrange than the
## old controller's triple jump was, so a window tuned against the old moveset
## leaves this fight unopenable in practice.
##
## The window closing is still the only pressure in the fight; there is no clock
## on the fight itself.
@export var stun_time: float = 7.0
## Minimum `Player.slam_power()` that cracks it — 0 is a standing hop, 1 is a
## tower drop. Above what a hop gives, so height has to be earned.
## Force on `Events.slam_landed` needed to crack it open.
##
## **3.0 on the modal controller's scale, where this used to be 0.3 on the old
## one's.** That slam reports force in two halves — how far you fell plus how
## much horizontal speed you delivered into the floor — so, measured: a standing
## hop is 0.10, a drop from the pound deck 1.40, and a FLAT-OUT CHARGE cancelled
## into a slam 2.20 with no drop at all.
##
## Horizontal speed being worth more than the deck is why this number is 3.0 and
## not something between: at any lower threshold the answer to the boss is
## "charge at it on flat ground" and the pound deck stops existing, which deletes
## phase two. 3.0 needs both, so the opening is the charge-to-slam cancel.
@export var crack_power: float = 3.0
## How close the pound has to land.
@export var crack_radius: float = 4.5

@export_group("Contact")
@export var contact_damage: int = 1
## Money a hit knocks out of you. High, because that one number is what stops a
## rich player being immune to it.
@export var contact_coin_cost: int = 25
@export var hit_cooldown: float = 0.9

@export_group("Look")
@export var armoured_colour: Color = Color(0.46, 0.5, 0.58)
## Flashed during the wind-up, so the charge is visible as well as timed.
@export var windup_colour: Color = Color(1.0, 0.72, 0.25)
@export var stunned_colour: Color = Color(0.95, 0.95, 0.5)
@export var cracked_colour: Color = Color(0.85, 0.35, 0.35)
@export var beaten_colour: Color = Color(0.3, 0.28, 0.3)

@export_group("Wiring")
## The seed it starts out holding.
##
## A NodePath resolved by hand rather than a typed node export, because a typed
## one does not survive being written into a `.tscn` by hand — see
## seed_socket.gd, where that cost an hour and ate a level.
@export var seed_path: NodePath

var phase: Phase = Phase.ARMOURED

var _player: Node3D = null
var _seed: PlatformSeed = null
var _windup: float = 0.0
var _charge_left: float = 0.0
var _charge_dir: Vector3 = Vector3.FORWARD
var _stun_left: float = 0.0
## Set by `_bounce_off()`; while it runs the boss is reversing out of a wall.
var _recover_left: float = 0.0
var _recover_dir: Vector3 = Vector3.ZERO
var _hit_cooldown: float = 0.0

@onready var snatcher: ItemThief = $Snatcher
@onready var hurtbox: Area3D = $Hurtbox
@onready var visual: Node3D = $Visual
@onready var _shell: MeshInstance3D = $Visual/Shell
@onready var _material: StandardMaterial3D = _shell.get_active_material(0).duplicate()


func _ready() -> void:
	_shell.material_override = _material
	hurtbox.body_entered.connect(_on_hurtbox_entered)
	# The pound reaches it through the bus, which is how every prop in this
	# project hears about a slam. See crumbling_floor.gd.
	Events.slam_landed.connect(_on_slam_landed)
	# How it finds out it has lost, without holding a reference to the socket.
	Events.seed_delivered.connect(_on_seed_delivered)
	_seed = get_node_or_null(seed_path) as PlatformSeed
	# Deferred: a seed placed in the scene is where it should be by now, but one
	# spawned from code is positioned a line AFTER it enters the tree, and
	# grabbing it this frame would snap it to wherever it had not been put yet.
	call_deferred(&"_grab_seed")
	_set_phase(Phase.ARMOURED)


func _grab_seed() -> void:
	if _seed != null and not _seed.spent() and not _seed.is_held():
		snatcher.take(_seed)


func _physics_process(delta: float) -> void:
	_hit_cooldown -= delta
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Node3D

	var wanted := Vector3.ZERO
	match phase:
		Phase.ARMOURED:
			wanted = _do_armoured(delta)
		Phase.STUNNED:
			_stun_left -= delta
			if _stun_left <= 0.0:
				# Recovered. The window closing is the pressure — there is no
				# clock on the fight itself, only on each opening you make.
				_set_phase(Phase.ARMOURED)
		Phase.CRACKED:
			wanted = _do_cracked()
		Phase.BEATEN:
			pass

	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(wanted, 30.0 * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

	move_and_slide()

	# Only NOW does is_on_wall() mean anything — it reports what move_and_slide()
	# just bumped into. Checking before it would always read false and the boss
	# could never stun itself.
	if phase == Phase.ARMOURED and _charge_left > 0.0 and is_on_wall():
		if _hit_a_pillar():
			_set_phase(Phase.STUNNED)
		else:
			# Ran into something that is not a pillar. The charge ends and does
			# not stun — only pillars stun it, because a boss that knocked itself
			# out on the outer wall would be doing phase one for the player.
			#
			# **BUT IT HAS TO BACK OFF, and not doing so was a softlock.**
			# Reported from play as "it gets stuck and constantly loops its
			# charging state, but never moves and I can't kill it". Exactly that:
			# it ends the charge flush against the wall, winds up again, and
			# `_aim_at_player()` points straight back INTO the surface it is
			# touching — so it charges into the same wall for ever, from zero
			# distance, never moving.
			#
			# And you cannot kill it, correctly: you beat this boss by taking the
			# seed, not by damage. But wedged like that it can never be lured
			# into a pillar either, so phase one becomes unwinnable. A softlock
			# in a fight whose whole design is "no death, no timer".
			_charge_left = 0.0
			_windup = windup_time
			_bounce_off()
	_face_travel(delta)


## Walks away from whatever it just crashed into.
##
## Uses the wall normal `move_and_slide()` has already worked out, which is the
## one direction guaranteed to be out of the surface. Falls back to reversing the
## charge if there is no usable normal — a corner can report a near-vertical one.
func _bounce_off() -> void:
	var away := get_wall_normal()
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -_charge_dir
	_recover_dir = away.normalized()
	_recover_left = recover_time


## Lines up, tells you about it, then charges in a straight line.
##
## The direction is LOCKED when the charge starts and never corrected. A charge
## that steers is unavoidable, so it cannot be dodged, so the arena stops being
## part of the fight — and the arena is the whole of phase one.
func _do_armoured(delta: float) -> Vector3:
	# Backing away from a surface it just bounced off. This has to come FIRST:
	# while it runs, the boss is not winding up and not charging, so the loop
	# that used to pin it against a wall cannot form.
	if _recover_left > 0.0:
		_recover_left -= delta
		_tint(armoured_colour)
		return _recover_dir * charge_speed * recover_speed_scale

	if _charge_left > 0.0:
		_charge_left -= delta
		if _charge_left <= 0.0:
			_windup = windup_time
		return _charge_dir * charge_speed

	_windup -= delta
	# Flashes while it lines up. The telegraph has to be visible as well as timed.
	_tint(windup_colour if fmod(_windup, 0.2) > 0.1 else armoured_colour)
	if _windup <= 0.0:
		_charge_left = charge_time
		_charge_dir = _aim_at_player()
		_tint(armoured_colour)
	return Vector3.ZERO


## Cracked: it wants the seed back, and failing that it wants to hit you.
##
## `snatcher.target()` is the loose seed if there is one, which is the same
## interface enemy_walker.gd steers by. If the player has already picked the
## seed up, the target goes null and it comes for the player instead — which is
## what makes the delivery a race rather than a walk.
func _do_cracked() -> Vector3:
	if snatcher.held != null:
		# Got it back. That is the fail state landing: a phase lost, not a life.
		_set_phase(Phase.ARMOURED)
		return Vector3.ZERO
	var goal: Node3D = snatcher.target()
	if goal == null:
		goal = _player
	if goal == null:
		return Vector3.ZERO
	var to_goal := goal.global_position - global_position
	to_goal.y = 0.0
	if to_goal.length_squared() < 0.04:
		return Vector3.ZERO
	return to_goal.normalized() * charge_speed * 0.72


func _aim_at_player() -> Vector3:
	if _player == null:
		return -global_transform.basis.z
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.04:
		return -global_transform.basis.z
	return to_player.normalized()


func _face_travel(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() < 0.05:
		return
	var wanted := atan2(flat.x, flat.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, wanted, turn_speed * delta)


# --------------------------------------------------------------- being attacked
#
# **It is deliberately NOT in the `strikable` group.** It used to answer the
# spin — refusing it in every phase, which was the point: the player's default
# attack being useless is what forced the other verbs to be learned. The modal
# moveset has no such throwaway attack, so there is nothing left to refuse, and
# joining the strike group would hand it a SECOND slam path beside the one
# below. The refusals that carry the fight's hints all live in `_on_slam_landed`
# now, which is the only verb that ever cracked it open anyway.

## A ground pound landed somewhere. The only thing that cracks it open.
##
## Heard on the bus rather than through an Area3D, which is how every prop in
## this project reacts to a slam — the boss holds no reference to the player and
## the player has no idea bosses exist.
func _on_slam_landed(at: Vector3, force: float) -> void:
	if phase == Phase.BEATEN:
		return
	if at.distance_to(global_position) > crack_radius:
		return
	if phase != Phase.STUNNED:
		Events.boss_refused.emit(self, _wrong_phase_hint())
		_clang()
		return
	if force < crack_power:
		# The near miss is the most important hint in the fight: the move was
		# right and only the height was wrong, and a player told "not hard
		# enough" goes looking for somewhere to fall from.
		Events.boss_refused.emit(self, "Not hard enough — pound it from higher up")
		_clang()
		return
	_set_phase(Phase.CRACKED)


## What to do INSTEAD, and it has to differ by phase.
##
## The spin used to carry a hint per phase, and when the spin was retired this
## refusal inherited a single hardcoded string — which told a player in CRACKED
## to "crash it into a pillar", advice that is not merely unhelpful but wrong:
## the armour is already open and what they should be doing is racing for the
## seed. **Treat the hints as mechanics, not flavour.** A phase whose refusal
## does not name the right verb is a phase the player has to brute-force, which
## is the exact failure this fight exists to avoid.
func _wrong_phase_hint() -> String:
	match phase:
		Phase.CRACKED:
			return "No time for that — get the seed to the socket"
		_:
			return "Armour holds — dodge, and let it crash into a pillar"


func _on_hurtbox_entered(body: Node3D) -> void:
	var player := body as Node3D
	if player == null or not player.has_method(&"take_hit"):
		return
	if player == null or phase == Phase.BEATEN or _hit_cooldown > 0.0:
		return
	_hit_cooldown = hit_cooldown
	# Read BEFORE take_hit, because being hit may well let go of what you are
	# carrying, and then there would be nothing left to take back.
	var had_seed := (_seed != null and is_instance_valid(_seed)
		and _seed.carrier() == player)
	player.call(&"take_hit", contact_damage, global_position, contact_coin_cost)
	if not had_seed:
		return
	# THE FAIL STATE. Caught carrying the seed: it goes straight back and the
	# fight loses a phase. You lost ground, not a life — which is the whole
	# point of the exercise, and why there is no timer anywhere in here.
	# Takes it back out of your hands, whichever controller is holding it.
	if player.has_method(&"drop_carried"):
		player.call(&"drop_carried", _seed)
	snatcher.take(_seed)
	Events.boss_phase.emit(self, "It took the seed back", "Crack it open again")
	_set_phase(Phase.ARMOURED)


func _on_seed_delivered(_socket: Node3D, _delivered: Node3D) -> void:
	if phase == Phase.BEATEN:
		return
	# Beaten by the seed reaching the socket, not by damage. It cannot re-arm,
	# because a spent seed is gone for good.
	_set_phase(Phase.BEATEN)


# ------------------------------------------------------------------ phase plumbing

func _set_phase(next: Phase) -> void:
	phase = next
	_charge_left = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	match next:
		Phase.ARMOURED:
			_windup = windup_time
			_tint(armoured_colour)
			Events.boss_phase.emit(self, "Armoured",
				"dodge, and let it crash into a pillar")
		Phase.STUNNED:
			_stun_left = stun_time
			_tint(stunned_colour)
			Events.boss_phase.emit(self, "Stunned",
				"ground pound it from up high, quickly")
		Phase.CRACKED:
			snatcher.drop_held()
			_tint(cracked_colour)
			Events.boss_phase.emit(self, "Cracked open",
				"get the seed to the socket before it does")
		Phase.BEATEN:
			_tint(beaten_colour)
			hurtbox.set_deferred(&"monitoring", false)
			Events.boss_phase.emit(self, "Beaten", "the platform is up")
			var slump := create_tween()
			slump.tween_property(visual, "position:y", visual.position.y - 1.1, 0.7) \
				.set_ease(Tween.EASE_IN)


func _tint(colour: Color) -> void:
	_material.albedo_color = colour
	_material.emission = colour


func _clang() -> void:
	# A refused hit still shakes it, for the same reason a refused breakable
	# block does: "that did nothing" and "that was the wrong move" have to look
	# different from each other.
	var shake := create_tween()
	shake.tween_property(visual, "scale", Vector3.ONE * 1.08, 0.06)
	shake.tween_property(visual, "scale", Vector3.ONE, 0.14)


## Did this charge just run into a PILLAR, as opposed to anything else?
##
## Deliberately not simply `is_on_wall()`. The arena has outer walls, and a boss
## that stunned itself on those would play phase one for the player: it would
## wander into a wall on its own and nobody would ever have to dodge anything.
## Only pillars count, which is what makes the arena something you USE rather
## than something that happens around you.
##
## The collider is the internal `StaticBody3D` that a `CSGBox3D` creates to hold
## its collision, not the CSGBox3D itself — so the group has to be checked on
## the parent as well as on the collider. A level marks its pillars by putting
## them in the `pillar` group.
func _hit_a_pillar() -> bool:
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider() as Node
		if collider == null:
			continue
		if collider.is_in_group(PILLAR_GROUP):
			return true
		var holder := collider.get_parent()
		if holder != null and holder.is_in_group(PILLAR_GROUP):
			return true
	return false
