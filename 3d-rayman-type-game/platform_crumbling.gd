extends AnimatableBody3D

# --- Tweakable Settings ---
@export var delay_before_drop: float = 1.0
@export var drop_speed: float = 15.0
@export var drop_distance: float = 20.0
@export var reset_delay: float = 3.0
@export var shake_intensity: float = 0.08

# --- Internal State ---
enum State { IDLE, SHAKING, FALLING, RESETTING }
var state: State = State.IDLE

var original_position: Vector3
var state_timer: float = 0.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var trigger_area: Area3D = $Area3D

func _ready():
	original_position = position
	# Connect the Area3D's body_entered signal instead
	trigger_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	# Only trigger if the player touches it and we are currently idle
	if state == State.IDLE and body is Player:
		state = State.SHAKING
		state_timer = 0.0

func _physics_process(delta: float):
	match state:
		State.IDLE:
			pass # Do nothing, wait for the player

		State.SHAKING:
			state_timer += delta
			# Shake the platform horizontally to warn the player
			position.x = original_position.x + randf_range(-shake_intensity, shake_intensity)
			position.z = original_position.z + randf_range(-shake_intensity, shake_intensity)

			if state_timer >= delay_before_drop:
				# Snap back to center before falling
				position.x = original_position.x
				position.z = original_position.z
				state = State.FALLING
				state_timer = 0.0

		State.FALLING:
			position.y -= drop_speed * delta

			# Once it has fallen far enough, start the reset timer
			if position.y <= original_position.y - drop_distance:
				state = State.RESETTING
				state_timer = 0.0
				visible = false
				collision_shape.set_deferred("disabled", true)

		State.RESETTING:
			state_timer += delta
			if state_timer >= reset_delay:
				# Teleport back to the start and reactivate
				position = original_position
				state = State.IDLE
				visible = true
				collision_shape.set_deferred("disabled", false)
