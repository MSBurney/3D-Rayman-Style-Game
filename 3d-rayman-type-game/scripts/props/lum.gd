extends Area3D

## Collectible lum. Yellow counts, red heals.

enum Kind { YELLOW, RED }

@export var kind: Kind = Kind.YELLOW
@export var value: int = 1
@export var spin_speed: float = 2.0
@export var bob_height: float = 0.16
@export var bob_speed: float = 2.4
## One scene, tinted from `kind`, so there's no second lum scene to keep in sync.
@export var yellow_colour: Color = Color(1.0, 0.88, 0.32)
@export var red_colour: Color = Color(1.0, 0.36, 0.42)

var _base_y: float = 0.0
var _t: float = 0.0
var _taken: bool = false

func _ready() -> void:
	_base_y = position.y
	_t = randf() * TAU
	body_entered.connect(_on_body_entered)
	_apply_tint()


func _apply_tint() -> void:
	var colour := red_colour if kind == Kind.RED else yellow_colour
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	# Kept below 1 so the lum reads as yellow rather than saturating to white.
	material.emission_energy_multiplier = 0.9
	for child in get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = material

func _process(delta: float) -> void:
	_t += delta * bob_speed
	position.y = _base_y + sin(_t) * bob_height
	rotate_y(delta * spin_speed)

func _on_body_entered(body: Node3D) -> void:
	if _taken:
		return
	var player := body as Player
	if player == null:
		return
	_taken = true
	match kind:
		Kind.RED:
			player.heal(value)
		_:
			Events.lum_collected.emit(value)
	set_deferred(&"monitoring", false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.14)
	tween.parallel().tween_property(self, "position:y", position.y + 0.8, 0.14)
	tween.tween_callback(queue_free)
