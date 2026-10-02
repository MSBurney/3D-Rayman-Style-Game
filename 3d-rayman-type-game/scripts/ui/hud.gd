extends Control

## Health, lums, and the F3 debug readout.
##
## There used to be a reticle here, drawn over whatever the grapple aim-assist
## had picked. It went with the grapple: the spin attack is a radius around the
## player rather than something aimed at a target, so there is nothing for a
## reticle to point at. The spin draws a ring at its own real radius instead,
## which is better feedback anyway because it shows the reach that was used.

@export var heart_radius: float = 11.0
@export var heart_spacing: float = 30.0
@export var heart_origin: Vector2 = Vector2(34.0, 34.0)

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

func _draw_hearts() -> void:
	for i in _health_max:
		var centre := heart_origin + Vector2(heart_spacing * i, 0.0)
		var filled := i < _health
		if filled:
			draw_circle(centre, heart_radius, Color(1.0, 0.35, 0.4))
		draw_arc(centre, heart_radius, 0.0, TAU, 24, Color(0.1, 0.08, 0.12, 0.85), 2.5, true)

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
		"pound   %s" % info["slam"],
		# Jump chain: 0 means the next jump is an ordinary one, 1 a double, 2 a
		# triple. The window is how long you have left to keep it alive.
		"chain   %s" % info["chain"],
		"carry   %s" % info["carry"],
		"spin    %s" % info["spin"],
		"magnet  %s" % info["magnet"],
		"fps     %d" % Engine.get_frames_per_second(),
	])

func _hint_text() -> String:
	return "\n".join([
		"WASD move    Mouse or arrow keys look    Space jump",
		"Space again in the air:  SLAM down — the further you fall, the harder",
		"Q or RMB:  TONGUE.  Purple target: you are pulled to it",
		"             Red target: the enemy is pulled to YOU, then carried",
		"             Press Q again to throw what you are holding",
		"E:  grab and throw a keg     Land on an enemy to stomp it",
		"Run at a tan wall with speed:  wall run     Space:  wall jump",
		"Jump at a high ledge:  auto grab     Space:  climb     Ctrl:  drop",
		"F3 debug    R respawn    F5 restart    Esc free the mouse",
	])
