extends Node

## Global event bus (autoloaded as `Events`).
##
## Gameplay nodes fire these and never look each other up, so the HUD, the score
## and the respawn rules can all be rewritten without touching the player.

## Money was picked up. `value` is how much that single pickup was worth.
signal money_collected(value: int)
## Running total, re-emitted by Game after it accumulates money.
signal money_changed(total: int)

signal player_health_changed(current: int, maximum: int)
signal player_died
signal player_respawned

## The player took a hit from a THREAT. `coin_cost` is how much money the hit
## should knock out of them, which Game turns into coins on the floor.
##
## Scaled per threat on purpose: a walker costs a few coins, a boss costs a lot.
## That is what stops a rich player being immune to everything, which is the
## flaw in "coins are your health" as a flat rule.
signal player_hurt(at: Vector3, coin_cost: int)

signal checkpoint_reached(point: Node3D)
signal enemy_died(enemy: Node3D)

## The player ground-pounded. `force` runs 0..1 with how far they fell, so
## breakable floors and pressure plates can require a genuinely big drop rather
## than any old landing. `crumbling_floor.gd` listens.
signal slam_landed(at: Vector3, force: float)

## The player reached the exit with enough money and the level is done.
## `taken` is what they left with, for a tally.
signal level_cleared(exit: Node3D, taken: int)
## ...and they reached it without enough. `short` is how much more they need.
##
## Emitted rather than handled on the spot because a refusal has to be *said*:
## an exit that silently does nothing when you are poor is indistinguishable
## from an exit that is broken. The HUD listens and shows the shortfall.
signal exit_refused(exit: Node3D, short: int)

## An enemy picked up money the player dropped. Carries who took it and how
## much, so the HUD can say so.
##
## Emitted because an enemy quietly walking off with your coins is
## indistinguishable from the money having vanished — the same reason
## `exit_refused` exists rather than the exit just doing nothing.
signal money_stolen(thief: Node3D, worth: int)

## Something charged the player. `Game` is the only listener, because it owns the
## running total and is therefore the only place that can clamp a spend to what
## you actually have — the same reason the hit spill lives there. A till emits
## this rather than reaching into Game itself.
signal money_spent(amount: int)
## An enemy took the object a level's progression depends on — see
## `item_thief.gd`. Carries who has it so the HUD can name them, because an
## enemy wandering off with the way up has to be identifiable or the level just
## appears to be broken.
signal item_stolen(thief: Node3D, item: Node3D)
## A purchase went through. Carries what sold it and what it cost.
signal purchase_made(what: Node3D, cost: int)
## A purchase was refused, and by how much you were short.
##
## Exists for the same reason `exit_refused` does: a till that silently does
## nothing when you cannot afford it is indistinguishable from a broken one.
signal purchase_refused(what: Node3D, short: int)

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
