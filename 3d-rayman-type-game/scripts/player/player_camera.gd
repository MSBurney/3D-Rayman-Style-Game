class_name PlayerCamera
extends Node3D

## Third-person orbit rig.
##
## It sits under the player in the scene tree for packaging convenience but runs
## as `top_level`, so the player's physics stepping never shows up as camera
## jitter. It follows in _process with exponential smoothing instead.

@export var target: Node3D
@export var follow_height: float = 1.3
## Higher = snappier follow. Exponential, so it is framerate independent.
@export var follow_lag: float = 14.0
@export var distance: float = 6.5

@export_group("Look")
@export var mouse_sensitivity: float = 0.0024
@export var stick_sensitivity: float = 2.6
@export var pitch_min: float = -1.15
@export var pitch_max: float = 0.55
@export var invert_y: bool = false

@export_group("Feel")
## Extra FOV at full speed, which does a lot of the work of selling velocity.
@export var speed_fov_bonus: float = 8.0
@export var speed_fov_reference: float = 14.0
@export var base_fov: float = 75.0

var yaw: float = 0.0
var pitch: float = -0.15

@onready var arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

func _ready() -> void:
	top_level = true
	if target == null:
		target = get_parent() as Node3D
	arm.spring_length = distance
	camera.fov = base_fov
	if target != null:
		global_position = target.global_position + Vector3.UP * follow_height
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * mouse_sensitivity
		var dy := motion.relative.y * mouse_sensitivity
		pitch += dy if invert_y else -dy
	elif event.is_action_pressed(&"ui_cancel"):
		# Release the mouse so the editor/desktop is reachable again.
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

func _process(delta: float) -> void:
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look.length_squared() > 0.0:
		yaw -= look.x * stick_sensitivity * delta
		var dy := look.y * stick_sensitivity * delta
		pitch += dy if invert_y else -dy
	pitch = clampf(pitch, pitch_min, pitch_max)

	if target != null:
		var wanted := target.global_position + Vector3.UP * follow_height
		# exp() keeps the smoothing identical at any framerate
		global_position = global_position.lerp(wanted, 1.0 - exp(-follow_lag * delta))

		var body := target as CharacterBody3D
		var speed := 0.0
		if body != null:
			speed = Vector2(body.velocity.x, body.velocity.z).length()
		var t := clampf(speed / speed_fov_reference, 0.0, 1.0)
		camera.fov = lerpf(camera.fov, base_fov + speed_fov_bonus * t, 1.0 - exp(-6.0 * delta))

	rotation = Vector3(pitch, yaw, 0.0)

## Yaw-only basis. The player uses this so stick directions mean what they look
## like on screen, which is the whole reason a 3D platformer camera exists.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)
