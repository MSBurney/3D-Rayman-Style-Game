class_name WeightSensor
extends Node

## Answers one question for its parent: **what is resting on me, and how heavy
## is it?**
##
## A drop-in Node, like `health.gd` and `coin_thief.gd` — add it as a child of a
## prop and the prop asks it for numbers. It never moves anything and it holds
## no opinion about what the answer means. A `SeeSaw` turns the answer into a
## tilt; a `PressurePlate` compares it against a threshold.
##
## ─── WHY THIS IS SHARED AND NOT A FUNCTION INSIDE EACH PROP ──────────────────
##
## The design doc's six universal weight rules come with an engineering
## instruction attached, and it is the reason this file exists: they *"must
## behave identically everywhere, so they are built as ONE physics/interaction
## layer early — never as per-level scripts"*.
##
## Three of those rules need this exact measurement:
##
##   rule 1  surfaces have visible weight thresholds   → PressurePlate
##   rule 3  the heavier side of a pivot wins          → SeeSaw
##   rule 5  enemies obey the same physics as the player
##
## Rule 5 is the one that makes sharing non-optional. A see-saw and a pressure
## plate that disagreed about how heavy the player is — or about whether an
## enemy counts at all — would be two bugs that only show up in the one puzzle
## that used both.
##
## ─── IT WALKS GROUPS BY POSITION, IT DOES NOT USE AN Area3D ──────────────────
##
## Two reasons, and both are traps this codebase has already paid for:
##
## - **A sleeping `RigidBody3D` is unreliable in an overlap query.** A crate that
##   has settled on a see-saw is precisely that — asleep, not moving — and it is
##   the single most important thing a see-saw needs to know about. The spin
##   attack walks the `throwable` group by distance for this same reason.
## - **An area that is added or moved and then queried in the same frame reports
##   nothing.** A see-saw moves every single physics frame.
##
## So the volume is checked with maths instead: take each candidate into the
## parent's LOCAL space and ask whether it is inside the box. Nothing can go
## stale, and it answers on the frame it is asked.
##
## ─── THE `heavy` GROUP IS THE EXTENSION POINT ────────────────────────────────
##
## Anything that should have weight here does exactly two things:
##
##   1. joins one of `watch_groups` — `heavy` is the general-purpose one
##   2. has a `mass` property
##
## A `RigidBody3D` **already has `mass`**, so a crate needs no script at all: a
## node in the `heavy` group with a mass set in the Inspector is a complete
## answer. A `CharacterBody3D` has no such property, which is why `HeavyPlayer`
## declares one of its own.
##
## Anything in a watched group with no mass at all counts as `unknown_mass`
## rather than being skipped, because "a thing is standing on the see-saw and
## weighs nothing" has never once been the behaviour anybody wanted.

## The box that counts as "on me", in the PARENT's local space, in metres.
##
## A prop that resizes itself should resize this to match — `see_saw.gd` does,
## from its own `size`.
@export var size: Vector3 = Vector3(3.0, 2.2, 9.0)
## Where that box sits relative to the parent's origin. The default lifts it so
## it rests ON TOP of a deck whose origin is its own centre, rather than being
## buried inside it.
@export var offset: Vector3 = Vector3(0.0, 1.1, 0.0)
## Which groups are allowed to have weight here. See the note above: `heavy` is
## the general one, and the other three are groups this project already uses.
@export var watch_groups: Array[StringName] = [
	&"player", &"enemy", &"heavy", &"throwable",
]
## What something in a watched group weighs when it has no `mass` of its own.
@export var unknown_mass: float = 1.0

## Filled by `scan()`: the bodies currently inside the box.
var riders: Array[Node3D] = []
## Filled by `scan()`: the total mass of everything inside the box.
var total_mass: float = 0.0
## Filled by `scan()`: the sum of `mass * local z` — the lever arm about the
## parent's X axis, which is the axis a see-saw pivots on. Positive means the
## +Z end is winning.
##
## **Leverage is deliberately part of this rather than a plain mass comparison.**
## Standing further out counts for more, because that is how a lever actually
## works, and "walk to the very end and it tips" is the most interesting thing
## a player can discover about one unaided.
var moment: float = 0.0

## The node whose local space the box is measured in.
@onready var host: Node3D = get_parent() as Node3D


## Recounts what is on the host, right now.
##
## Called by the host from its own `_physics_process` rather than running itself
## on a timer or in `_process`. That is deliberate and worth copying: a prop
## that acts on these numbers wants them measured at a moment it chose, not at
## whatever moment the engine happened to tick a child.
func scan() -> void:
	riders.clear()
	total_mass = 0.0
	moment = 0.0
	if host == null:
		return

	var half := size * 0.5
	for group in watch_groups:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or body == host:
				continue
			# A body can sit in two watched groups at once — a thief is in
			# `enemy` and could also be tagged `heavy` — and counting it twice
			# would make it twice as heavy as it is.
			if riders.has(body):
				continue

			var local := host.to_local(body.global_position) - offset
			if absf(local.x) > half.x or absf(local.y) > half.y or absf(local.z) > half.z:
				continue

			var mass := mass_of(body)
			riders.append(body)
			total_mass += mass
			moment += mass * local.z


## What a body weighs.
##
## `RigidBody3D.mass` answers this for free, `HeavyPlayer` declares its own, and
## anything else falls back to `unknown_mass`. Asked through `get()` rather than
## by checking the class, so a future prop or enemy only has to own a `mass` to
## be taken seriously — no edit here, exactly like the `strikable` group.
func mass_of(body: Node3D) -> float:
	return Weight.mass_of(body, unknown_mass)


## True if `body` was inside the box at the last `scan()`.
func is_carrying(body: Node3D) -> bool:
	return riders.has(body)
