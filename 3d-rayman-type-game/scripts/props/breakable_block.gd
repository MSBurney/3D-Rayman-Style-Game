class_name BreakableBlock
extends StaticBody3D

## A block you destroy by running into it, spinning it, or pounding it.
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
##   • **Spin** — "can I open this from standing?" Yes, but only with the chain.
##     `require_spin_step` decides how far in; at 3 only the super spin does it,
##     which makes a block a reason to use the chain on purpose.
##   • **Ground pound** — "can I open this from above?" Scales with fall distance,
##     so a tall drop opens heavier blocks. Reuses `Events.slam_landed`.
##   • **Impact speed** — "can I open this by arriving fast?" This is the Wario
##     one. Run, slide a ramp, long jump into it. Nothing else in the project
##     rewards raw speed with access.
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
## Which spin in a chain opens it: 1 any spin, 3 only the super spin, 0 never.
@export_range(0, 3) var require_spin_step: int = 2
## Ground pound strength needed, on the same 0..1 scale as `Player.slam_power()`
## — a hop is about 0.08, a drop from the tower is 1.0. Negative means a pound
## never opens it.
@export var require_slam_power: float = 0.25
## How far a pound can reach. Wider than the block so landing beside it counts.
@export var slam_radius: float = 3.0

@export_group("Behaviour")
## Seconds until it comes back. Negative means it is gone for good, which is
## what you usually want for a wall guarding a route.
@export var reset_delay: float = -1.0
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
	add_to_group(&"spinnable")
	add_to_group(&"breakable")
	_apply_colour()
	sensor.body_entered.connect(_on_body_entered)
	Events.slam_landed.connect(_on_slam_landed)


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
	var player := body as Player
	if player == null:
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
	var speed := player.approach_speed()
	if speed < break_speed:
		_refuse()
		return
	_break(player)


## Called by PlayerAbilities when a spin lands in range — see spin_switch.gd for
## the `spinnable` contract.
func spin_hit(by: Node3D) -> void:
	if broken_open:
		return
	var player := by as Player
	var step := player.abilities.spin_step if player != null else 1
	# spin_step is zeroed the moment the third spin resolves, so the super spin
	# arrives here reading 0. Treat that as 3 rather than as "no spin".
	if step <= 0:
		step = 3
	if require_spin_step <= 0 or step < require_spin_step:
		_refuse()
		return
	_break(player)


func _on_slam_landed(at: Vector3, force: float) -> void:
	if broken_open or require_slam_power < 0.0:
		return
	if global_position.distance_to(at) > slam_radius:
		return
	if force < require_slam_power:
		_refuse()
		return
	_break(null)


## Opens up. `through` is whoever did it, so their momentum can be preserved.
func _break(through: Player) -> void:
	broken_open = true
	_reset_left = reset_delay
	shape.set_deferred(&"disabled", true)
	sensor.set_deferred(&"monitoring", false)

	if through != null:
		# Restored from approach_velocity(), NOT scaled from `velocity`. Same trap
		# as reading the speed: by the time this runs, move_and_slide() has
		# already stopped the player dead against the block, so `velocity` is zero
		# and scaling it keeps nothing. The whole reason for arriving fast is that
		# you get to keep going, so the speed has to be put back explicitly.
		var kept := through.approach_velocity() * speed_kept
		through.velocity.x = kept.x
		through.velocity.z = kept.z

	_spawn_break_fx()
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
