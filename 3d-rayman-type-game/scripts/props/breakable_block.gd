class_name BreakableBlock
extends StaticBody3D

## A block you destroy by arriving fast, slamming it, or simply being too heavy.
##
## This is the Wario Land idea in its cheapest form: **Wario goes through a level
## rather than over it.** Mario respects the geometry; Wario removes it. A wall
## that only opens to a body travelling fast enough turns momentum from something
## you spend on distance into something you spend on *access*, which is what
## makes the slopes worth having beyond "wheee".
##
## ### Three ways in, and why each exists
##
## Each one answers a different question the player might ask:
##
##   • **Slam** — "can I open this from above?" `strike_momentum` decides how
##     hard; the slam shockwave's momentum falls off with distance, so landing
##     on top of it opens a heavier block than landing beside it does.
##   • **Impact speed** — "can I open this by arriving fast?" This is the Wario
##     one. Run, charge a ramp, charge-jump into it. Nothing else in the project
##     rewards raw speed with access.
##   • **Mass** — "am I simply too heavy to be stopped?" What makes a lured giant
##     a wall-breaker you aim, since a giant walks at 3 m/s and can never clear
##     a speed gate.
##
## There used to be a fourth, the SPIN, answering "can I open this from
## standing?" — and there is deliberately no replacement for it. The modal
## moveset has no standing attack, and the block already had two better-aimed
## questions than "did you press the button near me".
##
## A block that refuses you is supposed to be informative, not silent, so a
## refused hit still shakes it. "I need to hit this harder" has to be readable
## from one failed attempt.

## Emitted when this block is destroyed, for anything that counts them.
signal broken(at: Vector3)

@export_group("What opens it")
## Minimum speed a body must arrive at to smash through. The player runs at 7.5,
## reaches ~17 down a ramp and ~28 out of a long jump, so this sits above
## running pace on purpose: arriving fast has to be a choice.
@export var break_speed: float = 12.0
## Momentum a strike must bring to open it — rule 1, a visible threshold in the
## same currency as everything else that hits things. Zero or below means no
## strike ever opens it, however hard.
##
## In practice this is the SLAM gate, since the slam shockwave is the only thing
## in the moveset that strikes without touching. The measured scale, from
## `tests/greybox_probe.gd`:
##
##   a hop-stomp beside it         7, reaching 1.25 m
##   a drop from 4 m              48, reaching 3.45 m
##   a drop from 12 m            140, reaching 10 m
##   a drop from 12 m, charging  294, reaching 10 m
##
## 25 sits between a hop and a 4 m drop, which is where the
## `require_slam_power` 0.25 this replaced sat: it reads as "a real drop, not a
## hop". **Note it does NOT overlap `break_speed`:** a strike is what reaches
## you from above, `break_speed` is what arrives through you, and a block with
## `break_speed` 999 is still unreachable by any charge however fast.
@export var strike_momentum: float = 25.0

@export_group("Loot")
## Money dropped when it breaks. Smashing has to pay something, or breaking a
## wall is a chore you perform rather than a thing you want to do.
@export var coin_drop: PackedScene
@export_range(0, 12) var coin_count: int = 3
## How far the coins scatter. Kept small so they do not end up somewhere you
## cannot reach, which turns a reward into a tax.
@export var coin_scatter: float = 0.9

@export_group("Behaviour")
## Seconds until it comes back. Negative means it is gone for good, which is
## what you usually want for a wall guarding a route.
@export var reset_delay: float = -1.0
## Anything at least this heavy opens it by touching it, at any speed at all.
## Zero or below switches it off. The twin of `CrumblingFloor.break_mass`.
@export var break_mass: float = -1.0
## Lets the player keep going rather than stopping dead on the frame it breaks.
## Without it a smashed wall still costs you all your speed, which defeats the
## point of having arrived fast.
@export_range(0.0, 1.0) var speed_kept: float = 0.8

@export_group("Look")
@export var colour: Color = Color(0.72, 0.5, 0.38)
@export var shake_strength: float = 0.08
## Ring drawn where it breaks. The shockwave scene; nothing fancy.
@export var break_fx: PackedScene

var broken_open: bool = false

## The shake tween, kept so a second refused hit restarts it rather than
## fighting the first one half way through.
var _shake: Tween = null
var _reset_left: float = 0.0

@onready var shape: CollisionShape3D = $Shape
@onready var visual: Node3D = $Visual
## Notices the player arriving. An Area3D rather than a body collision, because
## by the time the body collision resolves the speed we want to measure is gone.
@onready var sensor: Area3D = $Sensor


func _ready() -> void:
	add_to_group(&"strikable")
	add_to_group(&"breakable")
	_apply_colour()
	sensor.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if not broken_open or reset_delay < 0.0:
		return
	_reset_left -= delta
	if _reset_left <= 0.0:
		_restore()


## Something arrived. Fast enough and it goes through; too slow and it only
## rattles, which is the hint.
func _on_body_entered(body: Node3D) -> void:
	if broken_open:
		return
	# ANYTHING WITH A MASS AND A SPEED, not just a player — **rule 5, enemies
	# obey the same physics.** This used to require a CharacterBody3D with
	# `approach_speed()`, which meant a crate hurled at a wall at 30 m/s did
	# absolutely nothing while the hero jogging into it at 22 opened it. That is
	# the shape of bug the weight layer exists to stop: the block was asking
	# *who are you* when the only honest question is *how fast were you going*.
	if body == null:
		return
	# approach_speed(), NOT player.velocity. Running into the block means
	# move_and_slide() has already zeroed the horizontal velocity by the time this
	# callback runs, in the same physics step — so reading `velocity` here sees a
	# stationary player and refuses every hit however fast they arrived. This is
	# the horizontal twin of the stomp trap that descent_speed() exists for; the
	# comment on both functions in player.gd explains it.
	#
	# Horizontal only, deliberately: a block in a wall should not care that you
	# were also falling, or a plain drop would open a wall you barely touched.
	# Too heavy to be resisted, however gently it arrived. **This is what makes
	# the doc's "a lured heavy enemy is a wall-breaker you aim" true** — a giant
	# walks at 3 m/s and can therefore never clear a speed gate, so a wall meant
	# for one has to ask about its mass instead. Rule 1 again: the threshold is a
	# number, so a level can set it between two masses and the wall becomes a
	# filter for which body is allowed through it.
	if break_mass > 0.0 and Weight.mass_of(body) >= break_mass:
		_break(body)
		return
	var speed := Weight.impact_speed(body)
	if speed < break_speed:
		_refuse()
		return
	_break(body)


## The `strikable` contract — see strike_switch.gd. Returns whether it opened.
##
## `_break(null)` rather than `_break(by)`, deliberately: `_break` exists to give
## a body back the momentum it spent arriving, and a strike is not something you
## were travelling through. Hand the slammer over here and a stomp beside the
## block would fling you sideways out of it on whatever `_pre_move_flat` happened
## to hold.
func struck(_by: Node3D, momentum: float) -> bool:
	if broken_open or strike_momentum <= 0.0:
		return false
	if momentum < strike_momentum:
		_refuse()
		return false
	_break(null)
	return true


## Opens up. `through` is whoever did it, so their momentum can be preserved.
func _break(through: Node3D) -> void:
	broken_open = true
	_reset_left = reset_delay
	shape.set_deferred(&"disabled", true)
	sensor.set_deferred(&"monitoring", false)

	var character := through as CharacterBody3D
	if character != null:
		# Restored from the PRE-COLLISION velocity, not scaled from `velocity`.
		# Same trap as reading the speed: by the time this runs, move_and_slide()
		# has already stopped the player dead against the block, so `velocity` is
		# zero and scaling it keeps nothing. The whole reason for arriving fast is
		# that you get to keep going, so it has to be put back explicitly.
		var kept := Weight.impact_velocity(character) * speed_kept
		character.velocity.x = kept.x
		character.velocity.z = kept.z
	# A RigidBody3D needs no such repair: nothing zeroed its velocity, so it
	# carries straight on through under its own momentum.

	_spawn_break_fx()
	_drop_coins()
	broken.emit(global_position)

	var tween := create_tween()
	# ONE * 0.01, never ZERO — a scale of exactly zero is a singular transform
	# and spams `Condition "det == 0" is true` for every frame it is tweened to.
	tween.tween_property(visual, "scale", Vector3.ONE * 0.01, 0.14)


## Rattles without opening. The whole point is that a refusal is informative:
## one failed attempt should tell you to come back faster.
func _refuse() -> void:
	# The rest position is read HERE rather than cached in _ready(). A block
	# spawned from code is added to the tree first and positioned a line later, so
	# anything _ready() captures is the position it had before it was placed — and
	# shaking "back" to that teleported refused blocks to the level origin.
	if _shake != null and _shake.is_valid():
		_shake.kill()
	var base := position
	_shake = create_tween()
	_shake.tween_property(self, "position",
		base + Vector3(randf_range(-shake_strength, shake_strength), 0.0,
			randf_range(-shake_strength, shake_strength)), 0.04)
	_shake.tween_property(self, "position", base, 0.1)


func _restore() -> void:
	broken_open = false
	shape.set_deferred(&"disabled", false)
	sensor.set_deferred(&"monitoring", true)
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3.ONE, 0.16)


## Scatters a little money where the block was.
func _drop_coins() -> void:
	if coin_drop == null:
		return
	for i in coin_count:
		var coin := coin_drop.instantiate() as Node3D
		# Parented to the level, not to us — we are about to shrink to nothing,
		# and children shrink with their parent.
		get_tree().current_scene.add_child(coin)
		coin.global_position = global_position + Vector3(
			randf_range(-coin_scatter, coin_scatter), 0.3,
			randf_range(-coin_scatter, coin_scatter))


func _spawn_break_fx() -> void:
	if break_fx == null:
		return
	var ring := break_fx.instantiate() as Node3D
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position
	if ring.has_method(&"play"):
		ring.call(&"play", 2.2, false)


func _apply_colour() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	for child in visual.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = material
