extends Node

## Global event bus (autoloaded as `Events`).
##
## Gameplay nodes fire these and never look each other up, so the HUD, the score
## and the respawn rules can all be rewritten without touching the player.

## A lum was picked up. `value` is how much that single lum was worth.
signal lum_collected(value: int)
## Running total, re-emitted by Game after it accumulates lums.
signal lum_total_changed(total: int)

signal player_health_changed(current: int, maximum: int)
signal player_died
signal player_respawned

signal checkpoint_reached(point: Node3D)
signal enemy_died(enemy: Node3D)

## The player ground-pounded. `force` runs 0..1 with how far they fell, so
## breakable floors and pressure plates can require a genuinely big drop rather
## than any old landing. `crumbling_floor.gd` listens.
signal slam_landed(at: Vector3, force: float)

## A spin attack tripped a switch. Wire a door to this and the door and the
## switch never have to know about each other.
##
## Note the switch is passed along, so a listener can tell *which* one it was —
## check `switch.name`, or give your door an `@export var opened_by: SpinSwitch`
## and compare. Reacting to any switch at all is almost never what you want once
## a level has two of them.
signal switch_toggled(switch: Node3D, on: bool)

## Toggled by F3; the HUD listens and shows the movement debug readout.
signal debug_toggled(on: bool)
