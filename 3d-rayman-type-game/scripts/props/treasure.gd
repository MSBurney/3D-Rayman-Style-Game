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
## it. **Stomp beside it** — the slam shockwave is what reaches it.
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
## Momentum a strike must bring. Rule 1, and in the same currency as everything
## else that hits things — see strike_switch.gd for the measured scale. 5 is
## "any deliberate stomp", which is what a chest in the open should want; put a
## higher number on one you mean to be a puzzle.
@export var strike_momentum: float = 5.0

@export_group("Look")
@export var closed_colour: Color = Color(0.58, 0.42, 0.26)
@export var lid_colour: Color = Color(0.95, 0.78, 0.3)
@export var burst_fx: PackedScene

var open: bool = false

## The rattle tween, kept so a second feeble hit restarts it rather than
## fighting the first one half way through.
var _shake: Tween = null

@onready var lid: Node3D = $Visual/Lid
@onready var _sfx: AudioStreamPlayer3D = $Sfx


func _ready() -> void:
	add_to_group(&"strikable")
	add_to_group(&"treasure")
	_tint($Visual/Body, closed_colour)
	_tint(lid, lid_colour)


## The `strikable` contract — see strike_switch.gd.
func struck(_by: Node3D, momentum: float) -> bool:
	if open or strike_momentum <= 0.0:
		return false
	if momentum < strike_momentum:
		# A refused hit RATTLES rather than sitting silent. The old version of
		# this just returned, which is the one thing a chest must not do: a
		# chest that needs a harder hit and a chest that is scenery look exactly
		# the same if neither moves.
		_rattle()
		return false
	_open()
	return true


## Shivers without opening. See the breakable block for the same idea, and for
## why `position` is read here rather than cached in `_ready()`.
func _rattle() -> void:
	if _shake != null and _shake.is_valid():
		_shake.kill()
	var base := position
	_shake = create_tween()
	_shake.tween_property(self, "position",
		base + Vector3(randf_range(-0.05, 0.05), 0.0,
			randf_range(-0.05, 0.05)), 0.04)
	_shake.tween_property(self, "position", base, 0.12)


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
