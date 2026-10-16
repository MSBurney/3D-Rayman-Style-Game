class_name ItemThief
extends Node

## Steals a carryable object and carries it over its head.
##
## Drop-in, like `coin_thief.gd`: add it as a child Node named `Snatcher` to any
## enemy. The difference between the two is the size of the stake. CoinThief
## takes money, which is a number you can go and earn again. This takes the
## object a level's progression depends on, which you cannot — so an enemy
## holding this is holding the **level** hostage, and that is the whole point of
## it existing.
##
## ─── THE SAFETY IS DELIBERATELY NOT IN HERE ──────────────────────────────────
##
## This drops what it holds when its host dies, but treat that as a convenience
## rather than the guarantee. The guarantee lives in `platform_seed.gd`, which
## notices its carrier has stopped existing and drops itself.
##
## That split is on purpose. **A component cannot be trusted to tidy up after
## its own host**, because there is more than one way for an enemy to stop
## existing — killed, thrown into a wall and burst, freed along with the level —
## and they do not all run the same code. The object is the thing that must
## survive, so the object owns its own rescue.
##
## Typed to `PlatformSeed` rather than to something generic. The `stealable`
## group is the extension point when there is a second kind of stealable thing;
## until there is, a concrete type is easier to read than an interface nobody
## else implements.

## Picked something up.
signal stole(item: PlatformSeed)
## Let go of it — killed, or it was taken off us.
signal dropped(item: PlatformSeed)

## How far away it notices a loose object.
##
## Bigger than CoinThief's, because there is normally exactly one of these in a
## level and an enemy that failed to notice it would make the whole mechanic
## look switched off.
@export var greed_radius: float = 20.0
## How close it has to get to pick the object up.
@export var grab_distance: float = 1.5
## How long after letting go before it can take anything again.
##
## Not optional, and this project's FOURTH encounter with the same trap after
## `ledge_cooldown`, the spin's `regrab_delay` and `grind_relatch_delay`. Drop
## something and you are standing right next to it, so without a blind spell the
## very next frame picks it straight back up. On a boss that is fatal to the
## whole fight: cracking it open dropped the seed and it re-swallowed it
## instantly, so the phase change was real and completely invisible.
##
## Assume anything that can let go of a thing needs one of these.
@export var relatch_delay: float = 1.5
@export var sfx_steal: AudioStream

## What it is carrying, or null.
var held: PlatformSeed = null

var _host: Node3D = null
var _health: HealthComponent = null
var _target: PlatformSeed = null
var _relatch: float = 0.0


func _ready() -> void:
	_host = get_parent() as Node3D
	if _host == null:
		push_warning("ItemThief needs a Node3D parent; on its own it steers nothing.")
		return
	_health = _host.get_node_or_null(^"Health") as HealthComponent
	if _health != null:
		# Connected from here, so adding this one node is the whole of making
		# something a snatcher. A child's _ready() runs before its parent's, so
		# this fires while the host is still a real node.
		_health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	_relatch -= delta
	if _host == null or not _can_act():
		return

	if held != null and not is_instance_valid(held):
		held = null
	if held != null:
		# Still ours? A socket consuming it, or the player magneting it away,
		# both clear the carrier without telling us.
		if held.carrier() != _host:
			held = null
		return

	# Blind for a moment after letting go. See relatch_delay.
	if _relatch > 0.0:
		_target = null
		return
	_target = _nearest_loose()
	if _target == null:
		return
	if _host.global_position.distance_to(_target.global_position) <= grab_distance:
		take(_target)
		_target = null


## What the host should walk towards, or null. Same contract as CoinThief:
## `enemy_walker.gd` steers, this only chooses.
##
## Returns nothing once it is carrying something, so a snatcher with the object
## goes back to behaving like an ordinary enemy — which means it comes after you
## with the level in its hands.
func target() -> Node3D:
	if held != null:
		return null
	if _target != null and not is_instance_valid(_target):
		_target = null
	return _target


func _can_act() -> bool:
	return _health == null or _health.is_alive()


func _nearest_loose() -> PlatformSeed:
	var best: PlatformSeed = null
	var best_distance := greed_radius
	for node in get_tree().get_nodes_in_group(PlatformSeed.STEALABLE):
		var item := node as PlatformSeed
		# `is_held()` is what stops it snatching the object out of the player's
		# hands, which would be impossible to react to.
		if item == null or item.spent() or item.is_held():
			continue
		var distance := _host.global_position.distance_to(item.global_position)
		if distance < best_distance:
			best_distance = distance
			best = item
	return best


## Takes `item` whether or not this thief went looking for it.
##
## Public because a boss takes the seed back off the player on contact rather
## than by walking over to it — see boss_warden.gd.
func take(item: PlatformSeed) -> void:
	item.pick_up(_host)
	held = item
	_play_steal()
	stole.emit(item)
	Events.item_stolen.emit(_host, item)


## Lets go of whatever it is carrying. Called when the host dies.
func drop_held() -> void:
	if held == null or not is_instance_valid(held):
		held = null
		return
	var item := held
	held = null
	_relatch = relatch_delay
	item.drop()
	dropped.emit(item)


func _on_died() -> void:
	drop_held()


func _play_steal() -> void:
	if sfx_steal == null or _host == null:
		return
	var speaker := _host.get_node_or_null(^"Sfx") as AudioStreamPlayer3D
	if speaker == null:
		return
	speaker.stream = sfx_steal
	speaker.play()
