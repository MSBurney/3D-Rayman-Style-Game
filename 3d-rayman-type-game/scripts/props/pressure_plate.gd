class_name PressurePlate
extends Node3D

## A pad that depresses under enough weight. **Universal weight rule 1** —
## surfaces have visible weight thresholds — and the build list's *"pressure
## plate requiring walk-mode precision"*.
##
## ─── WHAT MAKES IT WALK-MODE, WHICH IS THE WHOLE POINT ───────────────────────
##
## A plate you can trigger by charging over it is not a precision input, it is a
## tripwire. Two things stop that, and only one of them is code:
##
## - **`hold_time`.** The mass has to stay on the pad for a moment before it
##   latches. A charge at 20 m/s is inside a 1.8 m pad for about five physics
##   frames; the default hold is fifteen. So you have to *stop* here, and the
##   charge has no free brakes.
## - **The pad is small, and stopping is a mechanic with a cost.** That half
##   needs no code at all — it falls out of the charge properties.
##
## **`hold_time` is not an input delay and must not grow into one.** The
## cardinal rule is instant inputs, heavy body: the player's *input* is never
## delayed, and the pad starts visibly sinking on the first frame your weight is
## on it. What takes time is the pad, which is a thing in the world with mass of
## its own. If it ever reads as lag rather than as a stiff mechanism, the fix is
## a faster visual response, not a shorter hold.
##
## ─── TWO READOUTS, BECAUSE THERE ARE TWO WAYS TO FAIL ────────────────────────
##
## The pad **tints** with how close the weight on it is to `required_mass`, and
## **sinks** with how far through the hold it is. Those are deliberately
## separate: "I am not heavy enough" and "I did not stand still long enough" are
## different problems, and a single blended readout would make both of them look
## like the same shrug. Same rule as a refused breakable block shaking rather
## than sitting there.
##
## ─── IT HAS NO COLLISION AT ALL, AND THAT IS A BUG FIX ───────────────────────
##
## A `Node3D`, not a `StaticBody3D`. The first version was a solid pad standing
## 25 cm proud of the floor, and the probe caught what that actually is: **a
## kerb.** A charge aimed across it stopped dead against the side of it and
## crash-stunned, every time. A plate you cannot charge over is a wall with a
## light on it, and worse, the one input it is supposed to reward — arriving
## carefully on foot — was the only one that ever reached the top of it.
##
## So there is nothing solid here. The pad is a visual that sits a few
## centimetres proud of the floor it is set into, and the weight is measured as
## a VOLUME rather than as contact — which is `weight_sensor.gd`'s whole shape
## and means a plate does not care whether you are standing, sliding or falling
## through it. If you ever want one raised on a pedestal, the pedestal is a
## separate piece of level geometry.
##
## ─── IT REUSES `Events.switch_toggled` RATHER THAN ADDING A SIGNAL ───────────
##
## That signal's own documentation already explains how to wire a door to a
## switch without the two knowing about each other, and a pressure plate is a
## switch. Anything already listening for switches works with these for free.

## Mass needed to hold it down. Compare against `HeavyPlayer.mass`: below that
## and standing on it is enough, above it and you have to bring something.
##
## **A plate that needs more than you weigh is the more interesting one** — but
## note that nothing in the current verb set can carry or shove a crate, so for
## now those have to be placed by hand in the editor. See the note on momentum
## transfer in CLAUDE.md.
@export var required_mass: float = 8.0
## How long the weight has to stay on. This is what makes it walk-mode; see
## above before shortening it.
@export var hold_time: float = 0.25
## Stay down once pressed. A held plate and a latching plate are two different
## puzzle pieces: a latch opens a route you then walk away to use, a held plate
## asks you to leave something behind.
@export var stays_pressed: bool = false

@export_group("Feel")
## How far the pad visibly sinks, in metres.
@export var press_depth: float = 0.07
## Colour at no load, and at full. Far apart in hue on purpose — two states in
## similar colours is the same as no tell at all.
@export var idle_colour: Color = Color(0.55, 0.5, 0.46)
@export var ready_colour: Color = Color(0.45, 0.95, 0.55)

@export_group("Wiring")
## What to switch on when this is pressed. Anything with an `activate()` method
## — a `MovingPlatform`, for one.
##
## A `NodePath` and not a typed node export, deliberately: a typed node export
## is converted by the editor and **does not survive a path written into a
## `.tscn` by hand** — it arrives as a NodePath that never becomes a node. That
## cost this project an unwinnable level once. See `seed_socket.gd`.
@export var activates: NodePath

signal pressed
signal released

var down: bool = false

var _held: float = 0.0
var _home_y: float = 0.0
var _target: Node = null
## A duplicate of the scene's material, so tinting this plate does not tint one
## every other one. Taken from the scene rather than made here: a material
## created in code takes its compiled shader with it when it dies, which is a
## measured two-frame stall. See CLAUDE.md.
var _material: StandardMaterial3D = null

@onready var pad: Node3D = $Pad
@onready var mesh: MeshInstance3D = $Pad/Mesh
## What is standing on us, and how heavy it is. See `weight_sensor.gd`.
@onready var sensor: WeightSensor = $Weight


func _ready() -> void:
	_home_y = pad.position.y
	_material = (mesh.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	mesh.material_override = _material
	_tint(0.0)

	if activates.is_empty():
		return
	_target = get_node_or_null(activates)
	if _target == null:
		# Said out loud rather than failing quietly, because a hand-written
		# NodePath that resolves to nothing looks exactly like a plate that does
		# not work.
		push_warning("PressurePlate %s: `activates` path '%s' resolves to nothing."
			% [name, activates])


func _physics_process(delta: float) -> void:
	sensor.scan()
	var load_fraction := clampf(sensor.total_mass / maxf(required_mass, 0.01), 0.0, 1.0)
	var enough := sensor.total_mass >= required_mass

	if enough:
		_held = minf(_held + delta, hold_time)
		if not down and _held >= hold_time:
			_press()
	else:
		# Reset rather than decay. A plate you can press by stepping on and off
		# it repeatedly is not asking for precision.
		_held = 0.0
		if down and not stays_pressed:
			_release()

	_tint(load_fraction)
	var sunk := 1.0 if down else _held / maxf(hold_time, 0.01)
	pad.position.y = _home_y - press_depth * sunk


## Tints with how close the load is to the threshold, so "not heavy enough"
## reads as a measurement rather than as nothing happening.
func _tint(load_fraction: float) -> void:
	var colour := idle_colour.lerp(ready_colour, load_fraction)
	_material.albedo_color = colour
	# `emission_enabled` is set in the SCENE, never here. Emission is a feature
	# flag and part of what Godot keys a shader on, so switching it on in code
	# makes this duplicate compile its own shader — the documented stall again.
	_material.emission = colour


func _press() -> void:
	down = true
	pressed.emit()
	Events.switch_toggled.emit(self, true)
	if _target != null and _target.has_method(&"activate"):
		_target.call(&"activate")


func _release() -> void:
	down = false
	_held = 0.0
	released.emit()
	Events.switch_toggled.emit(self, false)


## Puts it back up, whatever it is holding.
##
## **Public because the doc asks for it**, not as test scaffolding: *"every
## puzzle state is recoverable… respawning contraption pieces, room-reset
## levers, rebuild-on-reentry for discrete puzzles."* A latching plate is
## exactly the kind of discrete contraption that needs a lever behind it, and
## without this there was no way to put one back at all.
func reset() -> void:
	_held = 0.0
	if down:
		_release()


## For tests and HUD readouts: how far through the hold we are, 0..1.
func progress() -> float:
	if down:
		return 1.0
	return clampf(_held / maxf(hold_time, 0.01), 0.0, 1.0)
