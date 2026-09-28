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

## Toggled by F3; the HUD listens and shows the movement debug readout.
signal debug_toggled(on: bool)
