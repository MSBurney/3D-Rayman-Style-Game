class_name SpinSwitch
extends StaticBody3D

## A switch the spin attack trips.
##
## This is the first user of the `spinnable` group, and it is deliberately small,
## because the interesting part is the pattern rather than the switch:
##
##   1. join the `spinnable` group
##   2. implement `spin_hit(by)`
##
## That is all anything needs to react to a spin. `PlayerAbilities` walks the
## group by distance and calls the method — so this prop holds no reference to
## the player, and the player has no idea switches exist. Anything else that
## should answer to a spin (a crate, a gate, a bell, a flower) does the same two
## things and needs no change anywhere else.
##
## It announces itself on `Events.switch_toggled` rather than reaching for
## whatever it is supposed to open. Wire a door to that signal and the two never
## have to know about each other — same shape as a coin and the score.

@export_group("Behaviour")
## Off: one hit turns it on and it stays on. On: every hit flips it.
@export var momentary: bool = false
## Ignores further hits for this long, so one spin cannot register twice and a
## chain of three spins does not flip a toggle three times.
@export var retrigger_delay: float = 0.35

@export_group("Look")
@export var off_colour: Color = Color(0.5, 0.52, 0.6)
@export var on_colour: Color = Color(0.45, 0.9, 0.55)
## How far the head sinks when struck. Pure feedback, but a switch that does not
## visibly move is indistinguishable from a switch that is not working.
@export var press_depth: float = 0.12

var on: bool = false

var _locked: float = 0.0
var _head_rest: float = 0.0

@onready var head: Node3D = $Visual/Head
@onready var _material := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group(&"spinnable")
	_head_rest = head.position.y
	# One material instance of our own, so two switches in a level can be in
	# different states without sharing a colour.
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for child in head.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = _material
	var head_mesh := head as MeshInstance3D
	if head_mesh != null:
		head_mesh.material_override = _material
	_apply_look()


func _process(delta: float) -> void:
	_locked -= delta


## Called by PlayerAbilities when a spin lands in range. The name is the whole
## contract — see the note at the top.
func spin_hit(_by: Node3D) -> void:
	if _locked > 0.0:
		return
	_locked = retrigger_delay

	on = not on if not momentary else true
	_apply_look()
	_punch()
	Events.switch_toggled.emit(self, on)

	if momentary:
		# A momentary switch springs back on its own, and announces that too, so
		# a door held open by it closes again.
		await get_tree().create_timer(retrigger_delay).timeout
		if is_instance_valid(self):
			on = false
			_apply_look()
			Events.switch_toggled.emit(self, on)


func _apply_look() -> void:
	var tint := on_colour if on else off_colour
	_material.albedo_color = tint
	_material.emission_enabled = on
	_material.emission = tint
	_material.emission_energy_multiplier = 1.6


## Sinks the head and lets it spring back.
func _punch() -> void:
	var tween := create_tween()
	tween.tween_property(head, "position:y", _head_rest - press_depth, 0.06)
	tween.tween_property(head, "position:y", _head_rest, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
