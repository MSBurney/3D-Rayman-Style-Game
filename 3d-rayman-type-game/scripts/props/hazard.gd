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
	# Duck-typed, never `body as Player`. That class is deprecated and the modal
	# controller is not one of them; what a hazard needs is something that can
	# be hit, which is a method and not a class.
	var player := body as Node3D
	if player == null or not player.has_method(&"take_hit"):
		return
	if instant_kill:
		if player.has_method(&"kill"):
			player.call(&"kill")
		else:
			# **There is no death.** Against a controller that cannot die, a
			# "lethal" hazard becomes the worst kind of ordinary hit: the doc bans
			# ejection from an arena outright, and every penalty has to be live and
			# in-arena rather than travel time.
			player.call(&"take_hit", damage, global_position, coin_cost)
		return
	var from := global_position if knockback_from_centre else player.global_position - Vector3.UP
	player.take_hit(damage, from, coin_cost)
