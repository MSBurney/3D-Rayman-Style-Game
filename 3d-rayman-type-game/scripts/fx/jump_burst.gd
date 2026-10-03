extends Node3D

## The puff of dust that tells you which jump you just did.
##
## This is not decoration. The moveset now has six ways to leave the ground —
## jump, double, triple, side flip, backflip, long jump — and several of them
## start from the same button in the same posture, so without a tell the player
## cannot see which one fired. That was the complaint that produced this file:
## "it's hard to tell which jumps are being activated".
##
## There are two tells, and they are deliberately different kinds of thing so
## they survive being seen out of the corner of your eye:
##
##   • COLOUR — one per move, set by the caller. This is the primary tell.
##   • DIRECTION — where the dust is thrown. Down for a double jump (you pushed
##     off the air beneath you), sideways for a side flip, backwards for a
##     backflip. This is what you notice before you have consciously read the
##     colour.
##
## `CPUParticles3D`, not `GPUParticles3D`, because the project renders with GL
## Compatibility and CPU particles are the option that is guaranteed to work on
## it. There are a few dozen particles here; the CPU does not care.

## Falls back to these if `play()` is called with nothing. Mostly so the scene
## still does something visible when you hit Play on it on its own.
@export var default_tint: Color = Color(1.0, 0.95, 0.8)
@export var default_amount: int = 14
@export var default_speed: float = 5.0
## How long the node sticks around before freeing itself. Must outlast the
## particles' own lifetime or they get cut off mid-flight.
@export var linger: float = 1.2

@onready var particles: CPUParticles3D = $Particles


## Call straight after spawning.
##
## `burst_dir` is which way the dust is thrown — pass `Vector3.DOWN` for a
## straight-up jump, or a horizontal direction for a flip. It is normalised here,
## so callers can hand over a velocity without tidying it up first.
func play(tint: Color = default_tint, amount: int = default_amount,
		speed: float = default_speed, burst_dir: Vector3 = Vector3.DOWN) -> void:
	particles.amount = maxi(amount, 1)
	particles.color = tint

	var direction := burst_dir
	if direction.length_squared() < 0.0001:
		direction = Vector3.DOWN
	particles.direction = direction.normalized()
	particles.initial_velocity_min = speed * 0.55
	particles.initial_velocity_max = speed

	# one_shot means `emitting = true` fires exactly one batch and stops, rather
	# than running forever. Setting it after the config above so the particles
	# are created with the values we just set, not the scene's defaults.
	particles.restart()
	particles.emitting = true

	await get_tree().create_timer(linger).timeout
	queue_free()
