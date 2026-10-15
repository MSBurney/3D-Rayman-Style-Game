class_name CoinThief
extends Node

## Steals the money the player drops, and hands every coin of it back when it
## dies.
##
## Drop-in: add it as a child Node named `Thief` to any enemy. Same shape as
## `health.gd` and `thrown_flight.gd` — no scene of its own, and the enemy it
## hangs off needs to know almost nothing about it.
##
## ─── WHY IT EXISTS ───────────────────────────────────────────────────────────
##
## Getting hit already knocks money out of the player and leaves it on the floor
## (see `game.gd`), but nothing competed with them for it, so the "stakes" came
## to a short walk back. Sonic's rings work because there is a scramble to
## recover them, and the scramble IS the mechanic. This supplies the competitor.
##
## It also gives a boss something to be *about*. The level exit charges you to
## leave, so an enemy holding your money stands between you and the win
## condition — a fail state that does not need you to die. That is the thing
## Wario Land's no-death design could never produce.
##
## ─── THE RULE THAT KEEPS IT SAFE ─────────────────────────────────────────────
##
## **A thief is a container, not a sink.** Money it takes must never leave the
## world. It drops everything when killed, it never despawns while carrying, and
## it cannot walk out of the level. Break any of those and you get the spiral
## this project has warned about since the money loop went in: hit, poorer,
## cannot afford the exit, forced to stay in the dangerous level, hit again. As a
## container there is no permanent loss — only a deposit you have to fight for.
##
## It is conserved on purpose, too. It takes N and drops N, so letting an enemy
## rob you and then killing it is worth exactly zero and cannot be farmed.

## Picked up some money. Carries what that single coin was worth.
signal stole(worth: int)
## Died and gave it all back. Carries the total that hit the floor.
signal dropped(worth: int)

## How far away it notices loose money.
@export var greed_radius: float = 16.0
## How close it has to get to actually pick a coin up.
@export var grab_distance: float = 1.3
## Most it will carry. 0 means no limit.
@export var capacity: int = 0
## Whether it will also take coins PLACED in the level, rather than only money
## the player dropped.
##
## False for an ordinary enemy: one that hoovered up a level's own coins would
## change how every level has to be built, and could quietly empty a room the
## player had not reached yet. True is the interesting setting for a BOSS,
## because "the stakes evaporate when the player is broke" is this mechanic's
## real weak spot — and a boss that eats the level's money has leverage even
## over a player with nothing in their pocket.
@export var steal_placed_coins: bool = false

@export_group("Giving it back")
## Spawned when it dies. Use the ordinary coin scene.
@export var coin_scene: PackedScene
## Most coin nodes one death is split across, however much is owed. Mirrors
## `Game.max_spill_coins`: a boss holding 200 must not spawn 200 Area3Ds, and
## the remainder rides on the first coin so nothing is lost to rounding.
@export var max_drop_coins: int = 10
## How hard the coins are thrown out of the body.
@export var drop_force: float = 5.0

@export_group("The tell")
## Colour the host drifts towards as it fills up.
##
## Not polish. An enemy that silently walks off with your coins is
## indistinguishable from the money having vanished, which is the same reason
## `exit_refused` exists instead of the exit quietly doing nothing.
@export var carry_tint: Color = Color(1.0, 0.85, 0.3)
## How much money counts as "full" for the tint. Above this it just reads gold.
@export var tint_saturates_at: int = 30
@export var sfx_steal: AudioStream

## How much it is holding right now. Read by the tint and by the smoke test.
var carried: int = 0

var _host: Node3D = null
var _health: HealthComponent = null
var _target: Coin = null
## One duplicated material per mesh on the host, plus the colour it started at,
## so the tint can be mixed in without destroying the original.
var _tinted: Array[StandardMaterial3D] = []
var _base_colours: Array[Color] = []


func _ready() -> void:
	_host = get_parent() as Node3D
	if _host == null:
		push_warning("CoinThief needs a Node3D parent; on its own it steers nothing.")
		return
	_health = _host.get_node_or_null(^"Health") as HealthComponent
	if _health != null:
		# Connected from here rather than from the enemy, so that adding this one
		# node is the whole of making something a thief. A child's _ready() runs
		# BEFORE its parent's, so this handler fires before the host starts dying
		# and while it is still a real node we can read a position off.
		_health.died.connect(_on_died)
	_cache_materials(_host)
	_apply_tint()


func _physics_process(_delta: float) -> void:
	if _host == null or not _can_act():
		return
	_target = _nearest_loot()
	if _target == null:
		return
	if _host.global_position.distance_to(_target.global_position) <= grab_distance:
		_take(_target)
		_target = null


## The coin the host should be heading for right now, or null.
##
## This is the whole interface the enemy uses: `enemy_walker.gd` asks for it and
## steers there in preference to patrolling or chasing. Deliberately only the
## DESTINATION and not the movement, so exactly one script per enemy ever writes
## `velocity` — worth more here than this node being entirely self-contained.
func target() -> Node3D:
	if _target != null and not is_instance_valid(_target):
		_target = null
	return _target


func _can_act() -> bool:
	return _health == null or _health.is_alive()


func _nearest_loot() -> Coin:
	if capacity > 0 and carried >= capacity:
		return null
	var best: Coin = null
	var best_distance := greed_radius
	# Walks the `coin` group by distance, like everything else that has to find
	# things in this project. A loose coin is a small Area3D that may have been
	# spawned on this very frame, and an area queried on the frame it was added
	# reports nothing at all.
	for node in get_tree().get_nodes_in_group(&"coin"):
		var coin := node as Coin
		if coin == null or not coin.is_available():
			continue
		if not steal_placed_coins and not coin.spilled:
			continue
		var distance := _host.global_position.distance_to(coin.global_position)
		if distance < best_distance:
			best_distance = distance
			best = coin
	return best


func _take(coin: Coin) -> void:
	var worth := coin.take_silently()
	if worth <= 0:
		return
	carried += worth
	_apply_tint()
	_play_steal()
	stole.emit(worth)
	Events.money_stolen.emit(_host, worth)


## Gives everything back as real coins, on the floor, where it died.
##
## Parented to the LEVEL rather than to the host, because the host is about to
## free itself and would take the coins down with it.
func drop_all() -> void:
	if carried <= 0 or coin_scene == null:
		return
	var worth := carried
	carried = 0
	_apply_tint()

	var nodes := mini(max_drop_coins, worth)
	var each := worth / nodes
	var extra := worth % nodes
	var at := _host.global_position + Vector3.UP * 0.6
	for i in nodes:
		var coin := coin_scene.instantiate() as Coin
		if coin == null:
			continue
		get_tree().current_scene.add_child(coin)
		# Positioned AFTER entering the tree, and the coin reads nothing about
		# its own position in _ready() — which is the trap breakable_block.gd
		# fell into by caching a rest position one line too early.
		coin.global_position = at
		var angle := TAU * float(i) / float(nodes)
		var out := Vector3(cos(angle), 1.4, sin(angle)).normalized()
		coin.spill(out * drop_force, each + (extra if i == 0 else 0))
	dropped.emit(worth)


func _on_died() -> void:
	drop_all()


func _play_steal() -> void:
	if sfx_steal == null or _host == null:
		return
	var speaker := _host.get_node_or_null(^"Sfx") as AudioStreamPlayer3D
	if speaker == null:
		return
	speaker.stream = sfx_steal
	speaker.play()


## Collects one duplicated material per mesh on the host, so the tint has
## somewhere to live.
##
## DUPLICATED from each mesh's own material, never built with
## `StandardMaterial3D.new()`: Godot frees a material's compiled shader when the
## last material using it dies, so minting one here would take the host's shader
## down with it every time an enemy died, and the next enemy drawn would stall
## recompiling it. See shockwave.gd for the whole story. Done once here rather
## than per frame for the same reason.
func _cache_materials(node: Node) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		var base := mesh.get_active_material(0) as StandardMaterial3D
		if base != null:
			var mine := base.duplicate() as StandardMaterial3D
			mesh.material_override = mine
			_tinted.append(mine)
			_base_colours.append(mine.albedo_color)
	for child in node.get_children():
		_cache_materials(child)


func _apply_tint() -> void:
	var fill := clampf(float(carried) / maxf(float(tint_saturates_at), 1.0), 0.0, 1.0)
	for i in _tinted.size():
		# Stops short of a full replace so a stuffed thief still reads as
		# whatever it was: a gold walker and a gold turret have to stay tellable
		# apart from each other.
		_tinted[i].albedo_color = _base_colours[i].lerp(carry_tint, fill * 0.85)
