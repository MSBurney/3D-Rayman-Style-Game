extends Node

## Game rules: score, checkpoints, respawning. Listens to the event bus so it
## never has to reach into the level or the player.

@export var respawn_delay: float = 1.1
@export var player: Player

var lums: int = 0
var _respawn: Transform3D
var _respawning: bool = false

func _ready() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		_respawn = player.global_transform

	Events.lum_collected.connect(_on_lum_collected)
	Events.checkpoint_reached.connect(_on_checkpoint_reached)
	Events.player_died.connect(_on_player_died)
	Events.lum_total_changed.emit(lums)

func _unhandled_input(event: InputEvent) -> void:
	# Quick iteration aids for a sandbox project.
	if event.is_action_pressed(&"restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed(&"respawn"):
		_do_respawn()

func _on_lum_collected(value: int) -> void:
	lums += value
	Events.lum_total_changed.emit(lums)

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
