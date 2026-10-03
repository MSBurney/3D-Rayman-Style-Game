class_name LevelExit
extends Area3D

## The way out, and it charges you.
##
## Straight from Wario Land 1, where you literally **buy the ending**: finishing
## the level is not reaching a flagpole, it is having taken enough out of the
## place. That one rule is what turns a level from a route into a job, and it is
## the cheapest way to make every other system in the project matter — the
## breakable walls, the pound, the spin chain and the slopes all become ways of
## affording the exit.
##
## Set `price` to 0 and it is an ordinary goal, which is useful while building.
##
## It refuses loudly rather than silently. An exit that does nothing when you are
## short is indistinguishable from an exit that is broken, so a refusal says how
## much you still need — see `Events.exit_refused`.

@export_group("Price")
## How much money you must have taken to leave. 0 makes it a plain goal.
@export var price: int = 0
## How long to ignore the player after refusing them, so standing in the doorway
## does not spam the message every frame.
@export var refuse_cooldown: float = 1.2

@export_group("Look")
@export var locked_colour: Color = Color(0.72, 0.36, 0.34)
@export var open_colour: Color = Color(0.45, 0.88, 0.5)
@export var spin_speed: float = 0.8

var cleared: bool = false

var _money: int = 0
var _refuse_left: float = 0.0

@onready var visual: Node3D = $Visual
@onready var _material := StandardMaterial3D.new()


func _ready() -> void:
	for child in visual.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = _material

	# Tracked by listening rather than by reaching into Game, so the exit works
	# in any scene and does not care who is counting.
	Events.money_changed.connect(_on_money_changed)
	body_entered.connect(_on_body_entered)
	_pull_money()
	_apply_look()


## Reads the current total once, rather than waiting for the next change.
##
## `money_changed` only tells you about money collected from now on, so an exit
## that misses the first broadcast — because Game.s _ready() ran before ours, or
## because this exit was added to the scene later — believes you are broke and
## refuses you with your pockets full.
func _pull_money() -> void:
	var game := get_tree().get_first_node_in_group(&"game")
	if game != null and "money" in game:
		_money = game.money


func _process(delta: float) -> void:
	_refuse_left -= delta
	visual.rotate_y(delta * spin_speed)


func _on_money_changed(total: int) -> void:
	_money = total
	_apply_look()


## How much more is needed, or 0 when affordable. Read by the HUD.
func shortfall() -> int:
	return maxi(price - _money, 0)


func _on_body_entered(body: Node3D) -> void:
	if cleared:
		return
	var player := body as Player
	if player == null:
		return

	if shortfall() > 0:
		if _refuse_left > 0.0:
			return
		_refuse_left = refuse_cooldown
		Events.exit_refused.emit(self, shortfall())
		var tween := create_tween()
		tween.tween_property(visual, "scale", Vector3.ONE * 1.18, 0.08)
		tween.tween_property(visual, "scale", Vector3.ONE, 0.18)
		return

	cleared = true
	Events.level_cleared.emit(self, _money)
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3.ONE * 1.6, 0.3) \
		.set_ease(Tween.EASE_OUT)


func _apply_look() -> void:
	var affordable := shortfall() <= 0
	var tint := open_colour if affordable else locked_colour
	_material.albedo_color = tint
	_material.emission_enabled = true
	_material.emission = tint
	# Brighter once you can afford it, so the exit becoming available is visible
	# from across the level rather than only on the HUD.
	_material.emission_energy_multiplier = 1.8 if affordable else 0.5
