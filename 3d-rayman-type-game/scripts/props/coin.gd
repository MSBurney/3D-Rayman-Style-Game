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

@export_group("Spilled")
## Spilled coins cannot be picked up for this long.
##
## Without it the coins you just dropped are re-collected on the same frame they
## appear, because you are standing in the middle of them — so being hit would
## cost you nothing and the whole mechanic would silently do nothing.
@export var pickup_delay: float = 0.55
## Gravity applied to a coin in flight, so a spill arcs and settles instead of
## sliding away flat.
@export var spill_gravity: float = 18.0

var _base_y: float = 0.0
var _t: float = 0.0
var _taken: bool = false
## Set while a dropped coin is still in the air. See spill().
var _spilling: bool = false
var _spill_velocity: Vector3 = Vector3.ZERO
var _no_pickup: float = 0.0

@onready var _sfx: AudioStreamPlayer3D = $Sfx
@onready var _mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	# Grouped so a spill can be counted (and so anything else can find loose
	# money), which the smoke test uses to prove a hit really does put coins on
	# the floor rather than just decrementing a number.
	add_to_group(&"coin")
	_base_y = position.y
	_t = randf() * TAU
	body_entered.connect(_on_body_entered)
	_apply_tint()


func _apply_tint() -> void:
	var colour := garlic_colour if kind == Kind.GARLIC else coin_colour

	# Duplicated from the scene's own material rather than built with
	# `StandardMaterial3D.new()`, for exactly the reason spelled out in
	# shockwave.gd's `play()` — worth reading there once. Short version: Godot
	# frees a material's compiled shader when the last material using it is
	# destroyed, so a coin that mints its own takes that shader with it when it
	# is collected, and the next coin has to compile it again mid-play. Coins
	# are spawned at runtime by a spill, so that is a stall at the exact moment
	# you get hit.
	var base := (_mesh.mesh as PrimitiveMesh).material as StandardMaterial3D
	if base == null:
		return
	var material := base.duplicate() as StandardMaterial3D
	material.albedo_color = colour
	material.emission = colour
	# Kept below 1 so the coin reads as yellow rather than saturating to white.
	material.emission_energy_multiplier = 0.9
	for child in get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = material

## Thrown out of the player when they are hit. Hollow Knight.s answer rather than
## Sonic.s: the money is not destroyed, it is lying on the floor where you lost
## it, and you have to go back and pick it up.
func spill(impulse: Vector3, worth: int) -> void:
	value = worth
	_spilling = true
	_spill_velocity = impulse
	_no_pickup = pickup_delay

func _process(delta: float) -> void:
	_no_pickup -= delta
	rotate_y(delta * spin_speed)

	if _spilling:
		_spill_velocity.y -= spill_gravity * delta
		position += _spill_velocity * delta
		# Landed. An Area3D does not collide with anything, so "landed" means
		# "back down to the height it was thrown from" — good enough, and it means
		# a coin always comes to rest somewhere the player can stand.
		if position.y <= _base_y and _spill_velocity.y < 0.0:
			position.y = _base_y
			_spilling = false
			_t = 0.0
		return

	_t += delta * bob_speed
	position.y = _base_y + sin(_t) * bob_height

func _on_body_entered(body: Node3D) -> void:
	if _taken or _no_pickup > 0.0:
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
