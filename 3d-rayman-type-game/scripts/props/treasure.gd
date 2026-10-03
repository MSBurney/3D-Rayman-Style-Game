class_name Treasure
extends StaticBody3D

## A chest full of money. The thing that makes a wall worth breaking.
##
## This exists to close a loop that was two thirds built. Wario Land's core is:
## **see a suspicious wall → work out which tool opens it → treasure.** The
## breakable blocks gave us the first two steps, and there was nothing behind
## them, so the skill of opening one paid out nothing.
##
## It is deliberately NOT a pickup you walk into. You have to hit it, because a
## chest you collect by brushing past is indistinguishable from a coin, and the
## whole point is that the reward reads as bigger than the coins that led you to
## it. Spin it, or pound near it.
##
## Opening it does not spawn coins to collect — it pays straight into the total.
## Scattering fifty coins out of a chest looks generous and is actually a chore,
## and half of them end up down a hole.

## Emitted when opened, with what it paid. Anything counting treasures (a
## level-complete rule, a tally screen) listens to this rather than to the chest.
signal opened(worth: int)

@export_group("Worth")
## How much money this pays. Set it against the coins around it: a chest should
## be worth a visible detour, so several times a handful of coins rather than a
## few more of them.
@export var worth: int = 50
## Shown floating above the chest as it opens, so the payout is legible at the
## moment it happens rather than only in the corner of the screen.
@export var show_payout: bool = true

@export_group("What opens it")
## Which spin in a chain opens it: 1 any spin, 3 only the super spin, 0 never.
@export_range(0, 3) var require_spin_step: int = 1
## Ground pound strength needed, on `Player.slam_power()`'s 0..1 scale. Negative
## means a pound never opens it.
@export var require_slam_power: float = 0.1
@export var slam_radius: float = 3.0

@export_group("Look")
@export var closed_colour: Color = Color(0.58, 0.42, 0.26)
@export var lid_colour: Color = Color(0.95, 0.78, 0.3)
@export var burst_fx: PackedScene

var open: bool = false

@onready var lid: Node3D = $Visual/Lid
@onready var _sfx: AudioStreamPlayer3D = $Sfx


func _ready() -> void:
	add_to_group(&"spinnable")
	add_to_group(&"treasure")
	_tint($Visual/Body, closed_colour)
	_tint(lid, lid_colour)
	Events.slam_landed.connect(_on_slam_landed)


## The `spinnable` contract — see spin_switch.gd.
func spin_hit(by: Node3D) -> void:
	if open:
		return
	var player := by as Player
	var step := player.abilities.spin_step if player != null else 1
	# spin_step is zeroed the instant the third spin resolves, so the super spin
	# arrives here reading 0. Treat that as 3, not as "no spin".
	if step <= 0:
		step = 3
	if require_spin_step <= 0 or step < require_spin_step:
		return
	_open()


func _on_slam_landed(at: Vector3, force: float) -> void:
	if open or require_slam_power < 0.0:
		return
	if global_position.distance_to(at) > slam_radius:
		return
	if force < require_slam_power:
		return
	_open()


func _open() -> void:
	open = true
	Events.money_collected.emit(worth)
	opened.emit(worth)
	_spawn_burst()

	if _sfx.stream != null:
		_sfx.play()

	# The lid flies off and the body sinks, which reads as "emptied" rather than
	# as "disappeared".
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lid, "position",
		lid.position + Vector3(0.0, 1.6, -0.5), 0.45).set_ease(Tween.EASE_OUT)
	tween.tween_property(lid, "rotation",
		lid.rotation + Vector3(-2.2, 0.0, 0.0), 0.45)
	# Never to exactly ZERO — a singular transform spams `det == 0` every frame.
	tween.chain().tween_property(self, "scale", Vector3.ONE * 0.01, 0.2)
	tween.chain().tween_callback(queue_free)


func _spawn_burst() -> void:
	if burst_fx == null:
		return
	var ring := burst_fx.instantiate() as Node3D
	# Parented to the level, not to us: we are about to free ourselves, and
	# freeing a node takes its children with it.
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector3.UP * 0.5
	if ring.has_method(&"play"):
		ring.call(&"play", 2.6, true)


func _tint(node: Node3D, colour: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	var mesh := node as MeshInstance3D
	if mesh != null:
		mesh.material_override = material
	for child in node.get_children():
		var child_mesh := child as MeshInstance3D
		if child_mesh != null:
			child_mesh.material_override = material
