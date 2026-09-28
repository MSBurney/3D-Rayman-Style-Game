extends Control

## Health, lums, and the grapple reticle.
##
## The reticle is the important one: it's the only feedback telling the player
## which point the aim-assist has decided they mean, so the grapple never feels
## like a guess.

@export var heart_radius: float = 11.0
@export var heart_spacing: float = 30.0
@export var heart_origin: Vector2 = Vector2(34.0, 34.0)
@export var swing_colour: Color = Color(0.72, 0.45, 1.0)
@export var pull_colour: Color = Color(1.0, 0.72, 0.28)
@export var reticle_radius: float = 20.0

var _player: Player = null
var _health: int = 0
var _health_max: int = 0
var _lums: int = 0
var _debug: bool = false

@onready var lum_label: Label = $LumLabel
@onready var debug_label: Label = $DebugLabel
@onready var hint_label: Label = $HintLabel

func _ready() -> void:
	Events.player_health_changed.connect(_on_health_changed)
	Events.lum_total_changed.connect(_on_lums_changed)
	Events.debug_toggled.connect(_on_debug_toggled)
	debug_label.visible = false
	hint_label.text = _hint_text()

func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Player
		if _player != null:
			# The player announces its health in _ready(), which runs before this
			# HUD has connected to the bus, so that first broadcast is missed and
			# no hearts are ever drawn. Pull the current values once on pickup.
			_on_health_changed(_player.health.current, _player.health.max_health)
	if _debug and _player != null:
		debug_label.text = _format_debug(_player.debug_info())
	# Reticle and hearts are drawn, so they need a redraw every frame.
	queue_redraw()

func _draw() -> void:
	_draw_hearts()
	_draw_reticle()

func _draw_hearts() -> void:
	for i in _health_max:
		var centre := heart_origin + Vector2(heart_spacing * i, 0.0)
		var filled := i < _health
		if filled:
			draw_circle(centre, heart_radius, Color(1.0, 0.35, 0.4))
		draw_arc(centre, heart_radius, 0.0, TAU, 24, Color(0.1, 0.08, 0.12, 0.85), 2.5, true)

func _draw_reticle() -> void:
	if _player == null:
		return
	var target := _player.targeting.current
	if target == null:
		return
	var camera := _player.rig.camera
	if camera == null or camera.is_position_behind(target.global_position):
		return

	var at := camera.unproject_position(target.global_position)
	var colour := pull_colour if target.mode == GrapplePoint.Mode.PULL else swing_colour
	draw_arc(at, reticle_radius, 0.0, TAU, 32, colour, 2.5, true)
	# Four ticks so the ring reads as a target and not just a circle.
	for i in 4:
		var angle := TAU * 0.125 + TAU * 0.25 * i
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(at + dir * (reticle_radius - 6.0), at + dir * (reticle_radius + 5.0), colour, 2.5, true)

func _on_health_changed(current: int, maximum: int) -> void:
	_health = current
	_health_max = maximum

func _on_lums_changed(total: int) -> void:
	_lums = total
	lum_label.text = "Lums  %d" % _lums

func _on_debug_toggled(_on: bool) -> void:
	_debug = not _debug
	debug_label.visible = _debug

func _format_debug(info: Dictionary) -> String:
	return "\n".join([
		"state   %s" % info["state"],
		"speed   %.2f" % info["speed"],
		"vert    %.2f" % info["vy"],
		"floor   %s   wall %s" % [info["floor"], info["wall"]],
		"target  %s" % info["target"],
		"heli    %.2f" % info["heli"],
		"carry   %s" % info["carry"],
		"fps     %d" % Engine.get_frames_per_second(),
	])

func _hint_text() -> String:
	return "\n".join([
		"WASD move   Mouse look   Space jump",
		"Space again in air: HELICOPTER",
		"RMB: grapple the ringed target   Space mid-swing: fling",
		"LMB tap/hold: fist / charged fist   E: grab & throw",
		"Run into a wall with speed: wall run   Space: wall jump",
		"Fall beside a ledge: auto grab   Space: climb   S: drop",
		"F3 debug   R respawn   F5 restart   Esc free mouse",
	])
