class_name HealthComponent
extends Node

## Drop-in health for anything that can be hurt. Players, enemies, breakables.

signal changed(current: int, maximum: int)
signal damaged(amount: int)
signal died

@export var max_health: int = 4
## Grace period after taking a hit. Enemies usually want 0, the player wants ~1s.
@export var invulnerable_time: float = 0.0

var current: int = 0

var _invuln: float = 0.0

func _ready() -> void:
	current = max_health

func _process(delta: float) -> void:
	if _invuln > 0.0:
		_invuln -= delta

func is_invulnerable() -> bool:
	return _invuln > 0.0

func is_alive() -> bool:
	return current > 0

## Returns true only if the hit actually landed, so callers can skip their
## own hit reactions (knockback, sfx) when the target was invulnerable.
func damage(amount: int = 1) -> bool:
	if amount <= 0 or not is_alive() or is_invulnerable():
		return false
	current = maxi(0, current - amount)
	_invuln = invulnerable_time
	damaged.emit(amount)
	changed.emit(current, max_health)
	if current == 0:
		died.emit()
	return true

func heal(amount: int = 1) -> void:
	if not is_alive() or amount <= 0:
		return
	current = mini(max_health, current + amount)
	changed.emit(current, max_health)

func reset() -> void:
	current = max_health
	_invuln = 0.0
	changed.emit(current, max_health)
