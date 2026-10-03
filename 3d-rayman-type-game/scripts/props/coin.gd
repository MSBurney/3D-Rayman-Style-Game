extends Area3D

## A coin, or a clove of garlic.
##
## Money is the point of a Wario game, so the yellow one is currency: it adds to
## the running total that a level exit charges you. The red one is garlic, which
## is what Wario eats to recover, so it heals instead.
##
## One scene for both, tinted from `kind`, so there is no second scene to keep in
## sync. Was called a "lum" until 2026-10-02 — a Rayman fossil.

enum Kind { COIN, GARLIC }

@export var kind: Kind = Kind.COIN
@export var value: int = 1
@export var spin_speed: float = 2.0
@export var bob_height: float = 0.16
@export var bob_speed: float = 2.4
## Yellow is money, red is garlic (a heal).
@export var coin_colour: Color = Color(1.0, 0.88, 0.32)
@export var garlic_colour: Color = Color(1.0, 0.36, 0.42)
@export var coin_sfx: AudioStream
@export var garlic_sfx: AudioStream

var _base_y: float = 0.0
var _t: float = 0.0
var _taken: bool = false

@onready var _sfx: AudioStreamPlayer3D = $Sfx

func _ready() -> void:
	_base_y = position.y
	_t = randf() * TAU
	body_entered.connect(_on_body_entered)
	_apply_tint()


func _apply_tint() -> void:
	var colour := garlic_colour if kind == Kind.GARLIC else coin_colour
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	# Kept below 1 so the coin reads as yellow rather than saturating to white.
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
		Kind.GARLIC:
			player.heal(value)
		_:
			Events.money_collected.emit(value)

	set_deferred(&"monitoring", false)
	# Stop the idle bob, or it fights the tween below for control of position.y.
	set_process(false)

	var sound := garlic_sfx if kind == Kind.GARLIC else coin_sfx
	if sound != null:
		_sfx.stream = sound
		_sfx.play()

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.14)
	tween.parallel().tween_property(self, "position:y", position.y + 0.8, 0.14)

	# Wait for the sound before disappearing. Freeing a node kills any audio it
	# is playing, so queue_free()ing on pickup would make collection silent.
	await tween.finished
	if _sfx.playing:
		await _sfx.finished
	queue_free()
