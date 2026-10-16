class_name VendingMachine
extends StaticBody3D

## Sells something for money, over and over. The second kind of sink, and the
## one that makes the economy feel live.
##
## A `PricedGate` is a one-off: it converts money into access and then stops
## being a choice at all. A machine keeps asking. That difference is the whole
## reason both exist — every time you walk past this thing you decide again
## whether what it sells is worth more to you than the exit is, and a decision
## you make repeatedly is worth more than a decision you make once.
##
## It dispenses an ordinary `Coin` set to `Kind.GARLIC`, so the healing path is
## the one that already exists — `coin.gd` heals on pickup for garlic — and this
## script contains no healing code whatsoever. Point `item_scene` at the coin
## scene and it sells money instead, which is a bad idea for obvious reasons but
## a useful thing to be able to try.
##
## Spun to buy, like the gate, and for the same reason: a till you can set off by
## brushing past is a till that robs you.

## What one item costs.
@export var price: int = 10
## How many it has. -1 means an endless supply.
##
## A finite stock turns the machine into a resource of its own: five garlic in
## the level is a thing you ration, where endless garlic at 10 is just a slow
## way of converting money into health.
@export var stock: int = 5
## Ignores further hits for this long, so one spin buys one item and a chain of
## three spins does not empty the machine.
@export var retrigger_delay: float = 0.5

@export_group("What it sells")
## The coin scene. Dispensed as garlic unless `sells_money` is on.
@export var item_scene: PackedScene
## Off: dispenses garlic, which heals. On: dispenses actual money, which only
## makes sense for testing.
@export var sells_money: bool = false
## Heal amount for garlic, or value for money.
@export var item_value: int = 1
## Where the item appears, relative to the machine. Far enough out that it does
## not spawn inside the machine's own collision.
@export var dispense_offset: Vector3 = Vector3(0, 1.1, 1.4)

@export_group("Look")
@export var stocked_colour: Color = Color(0.4, 0.62, 0.9)
@export var affordable_colour: Color = Color(0.45, 0.85, 0.52)
@export var empty_colour: Color = Color(0.42, 0.42, 0.46)

var _money: int = 0
var _locked: float = 0.0

@onready var visual: Node3D = $Visual
@onready var _body: MeshInstance3D = $Visual/Body
@onready var _material: StandardMaterial3D = _body.get_active_material(0).duplicate()


func _ready() -> void:
	add_to_group(&"spinnable")
	_body.material_override = _material
	# Same listen-plus-one-read as level_exit.gd and priced_gate.gd. See the
	# comment there for why the single read up front is not optional.
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
	_apply_look()


func sold_out() -> bool:
	return stock == 0


func shortfall() -> int:
	return maxi(price - _money, 0)


func spin_hit(_by: Node3D) -> void:
	if _locked > 0.0 or item_scene == null:
		return
	_locked = retrigger_delay

	if sold_out():
		# Announced as being nothing-short, which the HUD prints as "0 short".
		# Deliberate: an empty machine has to say something, or it reads as the
		# spin having missed.
		Events.purchase_refused.emit(self, 0)
		return
	if shortfall() > 0:
		Events.purchase_refused.emit(self, shortfall())
		var shake := create_tween()
		shake.tween_property(visual, "scale", Vector3.ONE * 1.08, 0.07)
		shake.tween_property(visual, "scale", Vector3.ONE, 0.16)
		return

	if stock > 0:
		stock -= 1
	Events.money_spent.emit(price)
	Events.purchase_made.emit(self, price)
	_dispense()
	_apply_look()


func _dispense() -> void:
	var item := item_scene.instantiate() as Coin
	if item == null:
		return
	item.kind = Coin.Kind.COIN if sells_money else Coin.Kind.GARLIC
	item.value = item_value
	# Parented to the level rather than to the machine, so it does not inherit
	# the machine's transform and is not freed with it.
	get_tree().current_scene.add_child(item)
	# Positioned AFTER entering the tree. coin.gd reads `position.y` in _ready()
	# for its idle bob, so a coin placed before that would bob around the level
	# origin — the breakable_block trap, in the one prop that still reads its own
	# position early.
	item.global_position = global_position + dispense_offset
	# NOT marked as spilled, which means CoinThief leaves it alone. An enemy
	# stealing the garlic out of the machine you just paid for would be a bridge
	# too far.


func _apply_look() -> void:
	var tint := empty_colour
	if not sold_out():
		tint = affordable_colour if shortfall() <= 0 else stocked_colour
	_material.albedo_color = tint
	_material.emission = tint
	_material.emission_energy_multiplier = 0.8 if shortfall() <= 0 and not sold_out() else 0.25
