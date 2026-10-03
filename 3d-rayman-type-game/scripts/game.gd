extends Node

## Game rules: score, checkpoints, respawning. Listens to the event bus so it
## never has to reach into the level or the player.

@export var respawn_delay: float = 1.1
@export var player: Player

var money: int = 0
var _respawn: Transform3D
var _respawning: bool = false

func _ready() -> void:
	# Joined so anything needing the CURRENT total can pull it instead of waiting
	# for the next `money_changed`. A level exit created after some money was
	# already banked — or simply one whose _ready() ran after ours — otherwise
	# starts believing you have nothing. Same shape as the HUD pulling the
	# player.s health once on pickup.
	add_to_group(&"game")
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		_respawn = player.global_transform

	Events.money_collected.connect(_on_money_collected)
	Events.checkpoint_reached.connect(_on_checkpoint_reached)
	Events.player_died.connect(_on_player_died)
	Events.money_changed.emit(money)

func _unhandled_input(event: InputEvent) -> void:
	# Quick iteration aids for a sandbox project.
	if event.is_action_pressed(&"restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed(&"respawn"):
		_do_respawn()

func _on_money_collected(value: int) -> void:
	money += value
	Events.money_changed.emit(money)

func _on_checkpoint_reached(point: Node3D) -> void:
	_respawn = point.global_transform

func _on_player_died() -> void:
	if _respawning:
		return
	_respawning = true
	await get_tree().create_timer(respawn_delay).timeout
	_do_respawn()

func _do_respawn() -> void:
	_respawning = false
	if player == null:
		return
	# Put any carried or thrown kegs back where they started.
	for node in get_tree().get_nodes_in_group(&"throwable"):
		if node.has_method(&"return_home"):
			node.call(&"return_home")
	player.respawn_at(_respawn)
