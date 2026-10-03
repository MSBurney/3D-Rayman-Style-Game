class_name Transformer
extends Area3D

## A volume that changes the player into something else. The **tool** half of
## Wario Land's enemy design.
##
## ### Tools and threats
##
## Enemies and hazards in this game split two ways, and the split is the whole
## reason the transformations work without removing health:
##
##   • a **tool** transforms you and does NO damage — this, a fire jet, a spore
##     puff. You walk into it deliberately, because the transformation is how you
##     get somewhere.
##   • a **threat** damages you and can kill you — `hazard.gd`, the walker, the
##     turret, and every boss.
##
## Wario Land II onwards made everything a tool by making Wario immortal, and
## that is the series' most criticised decision: a boss that cannot threaten you
## can only inconvenience you. Keeping the two categories apart gets the good
## idea without the bad one.
##
## ### Placing one
##
## Put it in front of whatever the transformation is *for*. A fire jet is only
## interesting if there is a speed-gated wall past it, and a spore puff is only
## interesting if there is something above it. A tool with nothing behind it is
## just an inconvenience, which is exactly the failure mode to avoid.

## What it turns you into. Values match `Player.State`, chosen in the Inspector.
enum Form { FLAMING, PUFFY }

@export var form: Form = Form.FLAMING
## Seconds the transformation lasts. Negative uses the player's own default for
## that form, which is usually what you want — tune it on the Player.
@export var duration: float = -1.0
## Ignores the player for this long after firing, so standing in the volume does
## not re-trigger every frame and lock them in it for ever.
@export var cooldown: float = 0.6

@export_group("Look")
@export var flame_colour: Color = Color(1.0, 0.52, 0.2)
@export var puff_colour: Color = Color(0.68, 0.85, 1.0)
@export var bob_height: float = 0.1
@export var bob_speed: float = 3.0

var _cool_left: float = 0.0
var _base_y: float = 0.0
var _t: float = 0.0

@onready var visual: Node3D = $Visual


func _ready() -> void:
	add_to_group(&"transformer")
	_base_y = visual.position.y
	_t = randf() * TAU
	body_entered.connect(_on_body_entered)
	_apply_look()


func _process(delta: float) -> void:
	_cool_left -= delta
	_t += delta * bob_speed
	visual.position.y = _base_y + sin(_t) * bob_height
	visual.rotate_y(delta * 1.4)


func _on_body_entered(body: Node3D) -> void:
	if _cool_left > 0.0:
		return
	var player := body as Player
	if player == null:
		return
	_cool_left = cooldown
	player.transform_into(_player_state(), duration)


## Maps our own enum onto the player's. Kept as a translation rather than
## exporting `Player.State` directly, so the Inspector shows only the two forms
## that make sense here instead of every state the player can be in.
func _player_state() -> Player.State:
	return Player.State.PUFFY if form == Form.PUFFY else Player.State.FLAMING


func _apply_look() -> void:
	var tint := puff_colour if form == Form.PUFFY else flame_colour
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 1.5
	for child in visual.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = material
