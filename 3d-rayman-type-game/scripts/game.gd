extends Node

## Game rules: score, checkpoints, respawning. Listens to the event bus so it
## never has to reach into the level or the player.

@export var respawn_delay: float = 1.1
@export var player: Player

@export_group("Money spilled on a hit")
## Getting hit knocks money out of you and it lands on the floor, where you can
## go and pick it back up.
##
## Hollow Knight's answer rather than Sonic's, and the difference matters: the
## money is not destroyed, it is **lying where you lost it**. So the loss is
## immediate and real, but it is recoverable — which is what stops a bad run
## locking you out of affording the exit. Sonic's version only works because
## rings are score; here money is the win condition, so a permanent loss could
## make a level unfinishable.
@export var coin_scene: PackedScene
## How many coin nodes a spill is split across, regardless of the amount. A boss
## costing 60 must not spawn 60 nodes, so the value is divided between these.
@export var max_spill_coins: int = 10
## How hard they are thrown out. Enough to scatter, not enough to lose.
@export var spill_force: float = 4.5

@export_group("Effect warm-up")
## Effects drawn once, invisibly, as the level starts. Fixes a stutter.
##
## Godot compiles a material's shader the first time it is actually DRAWN, not
## when it is loaded, and that compile costs around 28ms — two dropped frames at
## 60fps. For a prop standing in the level it happens while the level loads and
## nobody notices. For something that only appears when you press a button it
## happens on the first press, and reads as that move freezing the game.
##
## So the effects spawned from code get drawn once here, at 2% alpha, to get the
## compile over with before play starts. A scene opts in by implementing a
## `prewarm()` method; anything listed here without one is skipped.
##
## Worth keeping this list short: it is for effects the player cannot see until
## they do something, which is jump_burst and shockwave.
@export var prewarm_scenes: Array[PackedScene] = []

var money: int = 0
var _respawn: Transform3D
var _respawning: bool = false

func _ready() -> void:
	# Joined so anything needing the CURRENT total can pull it instead of waiting
	# for the next `money_changed`. A level exit created after some money was
	# already banked — or simply one whose _ready() ran after ours — otherwise
	# starts believing you have nothing. Same shape as the HUD pulling the
	# player.s health once on pickup.
	add_to_group(&"game")
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		_respawn = player.global_transform

	Events.money_collected.connect(_on_money_collected)
	Events.checkpoint_reached.connect(_on_checkpoint_reached)
	Events.player_died.connect(_on_player_died)
	Events.player_hurt.connect(_on_player_hurt)
	Events.money_changed.emit(money)
	_prewarm_effects()


## See `prewarm_scenes`. Deliberately NOT awaited by _ready(): it waits a couple
## of frames itself, because the camera has not been placed yet when _ready()
## runs, and these have to be drawn somewhere the camera can actually see them.
func _prewarm_effects() -> void:
	if prewarm_scenes.is_empty():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Three metres in front of the camera. It has to be inside the view: an
	# effect that gets culled is never drawn, so its shader is never compiled
	# and the whole warm-up silently does nothing. A version of this that put
	# them there but shrank them to 2cm measured as having changed nothing.
	var at := cam.global_position - cam.global_transform.basis.z * 3.0
	for scene in prewarm_scenes:
		if scene == null:
			continue
		var fx := scene.instantiate() as Node3D
		if fx == null:
			continue
		if not fx.has_method(&"prewarm"):
			fx.free()
			continue
		add_child(fx)
		fx.global_position = at
		# Each effect frees itself when it finishes, so there is nothing to
		# clean up here.
		fx.call(&"prewarm")


func _unhandled_input(event: InputEvent) -> void:
	# Quick iteration aids for a sandbox project.
	if event.is_action_pressed(&"restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed(&"respawn"):
		_do_respawn()

func _on_money_collected(value: int) -> void:
	money += value
	Events.money_changed.emit(money)

## A threat landed a hit. Knock money out of the player and scatter it on the
## floor for them to come back for.
##
## Done here rather than in the player because Game owns the running total, so
## this is the only place that can clamp the loss to what they actually have.
func _on_player_hurt(at: Vector3, coin_cost: int) -> void:
	var lost := mini(coin_cost, money)
	if lost <= 0:
		return
	money -= lost
	Events.money_changed.emit(money)
	_spill_coins(at, lost)


## Scatters `worth` of money as coins around `at`.
##
## The amount is split across at most `max_spill_coins` nodes rather than one
## node per unit: a boss hit costing 60 would otherwise spawn sixty Area3Ds, and
## the remainder goes on the first coin so no money is lost to rounding.
func _spill_coins(at: Vector3, worth: int) -> void:
	if coin_scene == null:
		return
	var count := mini(worth, maxi(max_spill_coins, 1))
	var each := worth / count
	var remainder := worth % count
	for i in count:
		var coin := coin_scene.instantiate() as Node3D
		get_tree().current_scene.add_child(coin)
		coin.global_position = at + Vector3.UP * 0.6
		var angle := TAU * float(i) / float(count) + randf() * 0.4
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var impulse := out * spill_force * randf_range(0.6, 1.0) + Vector3.UP * spill_force
		if coin.has_method(&"spill"):
			coin.call(&"spill", impulse, each + (remainder if i == 0 else 0))


func _on_checkpoint_reached(point: Node3D) -> void:
	_respawn = point.global_transform

func _on_player_died() -> void:
	if _respawning:
		return
	_respawning = true
	await get_tree().create_timer(respawn_delay).timeout
	_do_respawn()

func _do_respawn() -> void:
	_respawning = false
	if player == null:
		return
	# Put any carried or thrown kegs back where they started.
	for node in get_tree().get_nodes_in_group(&"throwable"):
		if node.has_method(&"return_home"):
			node.call(&"return_home")
	player.respawn_at(_respawn)
