class_name StrikeSwitch
extends StaticBody3D

## A switch you hit to trip.
##
## **This was `SpinSwitch` until the spin was retired**, and it is still the
## first and smallest user of the contract, because the interesting part is the
## pattern rather than the switch:
##
##   1. join the `strikable` group
##   2. implement `struck(by, momentum) -> bool`
##
## That is all anything needs to react to being hit. The modal controller's slam
## shockwave walks the group by distance and hands over a momentum; so does the
## deprecated spin. The prop holds no reference to either, and neither controller
## knows switches exist. Anything else that should answer to a hit (a crate, a
## gate, a bell, a flower) does the same two things and needs no change anywhere.
##
## The one difference from the old `spin_hit(by)` is the whole reason for the
## change: **what arrives is a MOMENTUM, so the switch owns a threshold.** The
## spin handed over nothing but the attacker, which meant a prop had to reach
## into `by.abilities.spin_step` to find out how hard it had been hit — naming a
## class, naming a verb, and shutting out everything that was not the player.
##
## It announces itself on `Events.switch_toggled` rather than reaching for
## whatever it is supposed to open. Wire a door to that signal and the two never
## have to know about each other — same shape as a coin and the score.

@export_group("What trips it")
## Momentum needed to trip it. Rule 1: a visible threshold, in the same currency
## as everything else that hits things.
##
## The scale to judge it against — all of it MEASURED, in `tests/greybox_probe.gd`:
##
##   a hop-stomp beside it         7, reaching 1.25 m
##   a drop from 4 m              48, reaching 3.45 m
##   a drop from 12 m            140, reaching 10 m
##   a drop from 12 m, charging  294, reaching 10 m
##
## 5 is therefore "any deliberate stomp", which is what a switch should want —
## and note the REACH is what keeps a hop honest rather than the number: a weak
## shockwave only carries 1.25 m, so you have to stomp right beside it.
##
## A slam can never be pressed by accident, because it needs the air and a
## button, so the old rule that a trigger must not fire by brushing past is kept
## without the threshold having to do the work.
@export var strike_momentum: float = 5.0

@export_group("Behaviour")
## Off: one hit turns it on and it stays on. On: every hit flips it.
@export var momentary: bool = false
## Ignores further hits for this long, so one blow cannot register twice and a
## chain of three spins does not flip a toggle three times.
@export var retrigger_delay: float = 0.35

@export_group("Look")
@export var off_colour: Color = Color(0.5, 0.52, 0.6)
@export var on_colour: Color = Color(0.45, 0.9, 0.55)
## How far the head sinks when struck. Pure feedback, but a switch that does not
## visibly move is indistinguishable from a switch that is not working.
@export var press_depth: float = 0.12
## How far it rattles when a hit was too feeble. See `_rattle()`.
@export var rattle_strength: float = 0.05

var on: bool = false

var _locked: float = 0.0
var _head_rest: float = 0.0
var _rattle_tween: Tween = null

@onready var head: Node3D = $Visual/Head
@onready var _material := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group(&"strikable")
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


## The `strikable` contract — see the note at the top. Returns whether the blow
## was enough.
func struck(_by: Node3D, momentum: float) -> bool:
	if _locked > 0.0:
		return false
	if momentum < strike_momentum:
		# **A refused hit has to read as "not hard enough", never as "nothing
		# there".** This project's oldest feedback rule: the same one that makes
		# a refused breakable block shake and makes the warden announce what
		# would work instead. A switch that sat silent would be indistinguishable
		# from a switch that is broken.
		_rattle()
		return false
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
	return true


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


## Shivers without tripping. Deliberately a different motion from `_punch()`:
## the head sinking means "pressed", the whole post shaking means "not enough".
## One blended readout would make both look like the same shrug.
func _rattle() -> void:
	if _rattle_tween != null and _rattle_tween.is_valid():
		_rattle_tween.kill()
	# The rest position is read HERE rather than cached in _ready(), because a
	# node spawned from code is positioned a line AFTER it enters the tree, so
	# anything _ready() captured is where it was before it was placed — and
	# shaking "back" to that teleports it to the level origin. The breakable
	# block paid for this one.
	var base := position
	_rattle_tween = create_tween()
	_rattle_tween.tween_property(self, "position",
		base + Vector3(randf_range(-rattle_strength, rattle_strength), 0.0,
			randf_range(-rattle_strength, rattle_strength)), 0.04)
	_rattle_tween.tween_property(self, "position", base, 0.12)
