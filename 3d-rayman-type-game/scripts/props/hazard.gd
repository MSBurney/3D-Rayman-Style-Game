extends Area3D

## Hurt volume. Set `instant_kill` for the pit plane under the level; leave it
## off and set damage for spikes and the like.

@export var instant_kill: bool = false
@export var damage: int = 1
## Money this knocks out of the player. Negative uses the player.s default.
@export var coin_cost: int = -1
## Where knockback pushes from. Defaults to the hazard.s own centre.
@export var knockback_from_centre: bool = true

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if player == null:
		return
	if instant_kill:
		player.kill()
		return
	var from := global_position if knockback_from_centre else player.global_position - Vector3.UP
	player.take_hit(damage, from, coin_cost)
