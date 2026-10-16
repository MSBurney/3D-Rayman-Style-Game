class_name PricedGate
extends StaticBody3D

## A gate that charges money to open, and then gets out of the way.
##
## The point of it is not the door. It is that **money finally has somewhere to
## go before the exit.**
##
## Until now the exit was the only sink in the game, which made its price a
## binary gate: below the line nothing you collected mattered until you crossed
## it, and above the line nothing you collected mattered at all. In a game about
## hoarding, the next coin has to be worth something. A till in the middle of a
## level gives money an alternative use, so the question becomes "spend it here
## or save it for the way out" — and that question gets asked while you are still
## playing, instead of once at the end.
##
## **Price it so paying is a real decision, not a toll.** Put something behind it
## worth clearly more than it costs, and price the exit so that paying up dips
## you below what the exit wants for a while. The scary part is not the 30 you
## handed over, it is walking around at 100 with an exit that wants 110.
##
## ─── OPENED BY THE SPIN, NOT BY WALKING INTO IT ──────────────────────────────
##
## Two reasons. A sink you can trigger by accident is a terrible sink — being
## charged 30 for brushing against a door would be infuriating. And `spinnable`
## is already the documented extension point for precisely this: spin_switch.gd
## names "a gate" in its own list of things that should answer to a spin. So this
## does the same two things anything spinnable does, and needed no change at all
## in `player_abilities.gd`:
##
##   1. join the `spinnable` group
##   2. implement `spin_hit(by)`

## What it costs to open.
@export var price: int = 30
## Ignores further hits for this long, so one spin cannot pay twice and a chain
## of three spins is not charged three times. Same job as the switch's
## `retrigger_delay`.
@export var retrigger_delay: float = 0.4
## How long the panel takes to sink out of the way once paid.
@export var open_time: float = 0.45
## How far down it sinks. Must clear the player's height or they walk into the
## top of a gate they have already paid for.
@export var open_drop: float = 8.4

@export_group("Look")
@export var locked_colour: Color = Color(0.68, 0.33, 0.33)
## Used once you can afford it, so an openable gate reads from across the level
## rather than only when you are standing at it. Same idea as the exit.
@export var open_colour: Color = Color(0.45, 0.85, 0.52)

var paid: bool = false

var _money: int = 0
var _locked: float = 0.0

@onready var visual: Node3D = $Visual
@onready var shape: CollisionShape3D = $Shape
@onready var _panel: MeshInstance3D = $Visual/Panel
@onready var _material: StandardMaterial3D = _panel.get_active_material(0).duplicate()


func _ready() -> void:
	add_to_group(&"spinnable")
	_panel.material_override = _material
	# Tracked by listening, with one read up front — copied from level_exit.gd,
	# including the reason: `money_changed` only reports changes from now on, so
	# a till that waits for one believes you are broke with your pockets full.
	Events.money_changed.connect(_on_money_changed)
	_pull_money()
	_apply_look()


func _pull_money() -> void:
	var game := get_tree().get_first_node_in_group(&"game")
	if game != null and "money" in game:
		_money = game.money


func _process(delta: float) -> void:
	_locked -= delta


func _on_money_changed(total: int) -> void:
	_money = total
	if not paid:
		_apply_look()


## How much more is needed, or 0 when affordable.
func shortfall() -> int:
	return maxi(price - _money, 0)


func spin_hit(_by: Node3D) -> void:
	if paid or _locked > 0.0:
		return
	_locked = retrigger_delay

	if shortfall() > 0:
		# Refused LOUDLY. A gate that does nothing when you are poor is
		# indistinguishable from a gate that is not a gate.
		Events.purchase_refused.emit(self, shortfall())
		var shake := create_tween()
		shake.tween_property(visual, "scale", Vector3.ONE * 1.1, 0.07)
		shake.tween_property(visual, "scale", Vector3.ONE, 0.16)
		return

	paid = true
	# Game does the deducting, so it can clamp. See Events.money_spent.
	Events.money_spent.emit(price)
	Events.purchase_made.emit(self, price)
	_open()


func _open() -> void:
	# Collision off first and deferred, because this is very likely running from
	# inside a physics query — the spin walks the `spinnable` group during
	# _physics_process, and changing a body's shapes mid-query is exactly the
	# kind of thing Godot warns about.
	shape.set_deferred(&"disabled", true)
	set_deferred(&"collision_layer", 0)
	var tween := create_tween()
	tween.tween_property(visual, "position:y", visual.position.y - open_drop, open_time) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)


func _apply_look() -> void:
	var tint := open_colour if shortfall() <= 0 else locked_colour
	_material.albedo_color = tint
	_material.emission = tint
	_material.emission_energy_multiplier = 0.9 if shortfall() <= 0 else 0.3
