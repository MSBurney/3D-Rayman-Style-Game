extends Control

## Health, money, and the F3 debug readout.
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
var _money: int = 0
var _debug: bool = false
## A transient line shown over the HUD — the exit refusing you, a level cleared.
var _message: String = ""
var _message_left: float = 0.0

@onready var money_label: Label = $MoneyLabel
@onready var debug_label: Label = $DebugLabel
@onready var hint_label: Label = $HintLabel

func _ready() -> void:
	Events.player_health_changed.connect(_on_health_changed)
	Events.money_changed.connect(_on_money_changed)
	Events.exit_refused.connect(_on_exit_refused)
	Events.level_cleared.connect(_on_level_cleared)
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
	_message_left -= _delta
	if _debug and _player != null:
		debug_label.text = _format_debug(_player.debug_info())
	# Reticle and hearts are drawn, so they need a redraw every frame.
	queue_redraw()

func _draw() -> void:
	_draw_hearts()
	_draw_message()

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

func _on_money_changed(total: int) -> void:
	_money = total
	money_label.text = "20a1  %d" % _money

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

## One transient line, centred near the top. Drawn rather than put in a Label so
## it needs no extra node in the scene and cannot be left visible by accident.
func _draw_message() -> void:
	if _message_left <= 0.0 or _message.is_empty():
		return
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	var at := Vector2((size.x - text_size.x) * 0.5, 96.0)
	# Drawn twice, offset, so it stays readable over a bright sky.
	draw_string(font, at + Vector2(2, 2), _message,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.7))
	draw_string(font, at, _message,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.97, 0.85))


## The exit turned the player away. Saying how short they are matters: an exit
## that silently does nothing reads as broken rather than as expensive.
func _on_exit_refused(_exit: Node3D, short: int) -> void:
	_message = "The exit wants %d more" % short
	_message_left = 2.2


func _on_level_cleared(_exit: Node3D, taken: int) -> void:
	_message = "LEVEL CLEARED — took %d" % taken
	_message_left = 99.0


func _hint_text() -> String:
	return "\n".join([
		"WASD move    Mouse or arrow keys look    Space jump",
		"Space, land, Space again:  DOUBLE then TRIPLE jump",
		"At speed, flick the stick back + Space:  SIDE FLIP",
		"Ctrl crouch —  still + Space: BACKFLIP    running: SLIDE",
		"             sliding + Space: LONG JUMP    in the air: GROUND POUND",
		"F or LMB:  SPIN.  Press again to chain; the third is the big one",
		"             In the air it gives you a little lift",
		"             Walk into something to carry it, F to throw it",
		"Break blocks by arriving FAST, spinning, or pounding from a height",
		"Take money out and pay the exit to leave",
		"F3 debug    R respawn    F5 restart    Esc free the mouse",
	])
