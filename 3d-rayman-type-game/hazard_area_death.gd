extends Area3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	# Only trigger if the player touches it and we are currently idle
	if body is Player:
		body.kill()
