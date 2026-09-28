extends Area3D

## Sets the respawn point. Keeps a movement sandbox from punishing experiments.

@export var only_once: bool = true

var _used: bool = false

@onready var _visual: Node3D = get_node_or_null(^"Visual")

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _visual != null and _used:
		_visual.rotate_y(delta * 2.0)

func _on_body_entered(body: Node3D) -> void:
	if _used and only_once:
		return
	if body is not Player:
		return
	_used = true
	Events.checkpoint_reached.emit(self)
	if _visual != null:
		var tween := create_tween()
		tween.tween_property(_visual, "scale", Vector3.ONE * 1.4, 0.12)
		tween.tween_property(_visual, "scale", Vector3.ONE, 0.18)
