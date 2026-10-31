class_name Weight

## **The weight layer.** Every rule about mass, impact and momentum in the game
## lives in this one file, as static functions anything can call.
##
## ─── WHY THIS EXISTS, AND IT IS NOT TIDINESS ─────────────────────────────────
##
## The design doc attaches an engineering instruction to its six universal
## weight rules: they *"must behave identically everywhere, so they are built as
## ONE physics/interaction layer early — never as per-level scripts"*.
##
## The first version of the weight props missed that in a way that is worth
## understanding, because it is the trap this file exists to close. Nothing was
## written per-level — but **the props were written to a CHARACTER-SHAPED
## interface.** `breakable_block.gd` asked for `approach_speed()`,
## `crumbling_floor.gd` asked for `descent_speed()`, and those are methods only
## a `CharacterBody3D` with bespoke code has. So:
##
##   - a crate hurled at a breakable wall did nothing at all
##   - a crate dropped on a crumbling floor did nothing at all
##   - a see-saw answered only to `Events.slam_landed`, which only the player emits
##
## Every one of those is **rule 5 — enemies obey the same physics as the player**
## — broken, and each would have needed its own fix. That is the "we need extra
## physics calculations for every object and system" problem, and the cause was
## never the kinematic/rigid-body split. It was that props asked *who are you*
## instead of *how heavy are you and how fast were you going*.
##
## So the whole interface is two questions, and everything can answer them:
##
##   **`Weight.mass_of(node)`** and **`Weight.impact_velocity(node)`**
##
## A `RigidBody3D` answers both for free. A `CharacterBody3D` answers with a
## `mass` export and its pre-collision accessors. Anything new answers by having
## a mass, and no file in here needs editing. Same shape as the `spinnable`
## group, applied to physics instead of to attacks.
##
## ─── NOTHING HERE HOLDS STATE OR IS EVER INSTANTIATED ────────────────────────
##
## Static functions only — a namespaced library, deliberately not a manager
## singleton and not a base class to inherit from. Call it as
## `Weight.collide(...)` from anywhere.

## What something weighs when nothing says otherwise. A thing standing on a
## see-saw and weighing zero has never once been the behaviour anybody wanted.
const UNKNOWN_MASS := 1.0


## The mass of anything.
##
## Asked through `get()` by NAME rather than by checking the class, so a future
## prop, enemy or object only has to own a `mass` to be taken seriously.
## `RigidBody3D` already has one, which is why a crate needs no script at all.
static func mass_of(node: Node, unknown: float = UNKNOWN_MASS) -> float:
	if node == null:
		return unknown
	var value: Variant = node.get(&"mass")
	if value is float or value is int:
		return maxf(float(value), 0.0)
	return unknown


## How fast something was travelling, for the purposes of an impact.
##
## **From BEFORE collision resolution wherever that is available**, which is the
## trap this project has paid for four times now: `move_and_slide()` has already
## zeroed a character's velocity by the time anything can ask about the
## collision, so reading `velocity` sees a stationary player and every head-on
## hit measures zero. `approach_velocity()` exists on both controllers for
## exactly this, and a `RigidBody3D` needs no such thing because its
## `linear_velocity` is not clobbered.
static func impact_velocity(node: Node) -> Vector3:
	if node == null:
		return Vector3.ZERO
	if node.has_method(&"approach_velocity"):
		var flat: Vector3 = node.call(&"approach_velocity")
		if node.has_method(&"descent_speed"):
			# Both controllers keep the horizontal and vertical halves in separate
			# accessors, so the full pre-collision velocity is the two of them put
			# back together. Done here rather than by adding a third accessor to
			# each player, so neither of them had to change for this file to exist.
			return Vector3(flat.x, node.call(&"descent_speed"), flat.z)
		return flat
	var rigid := node as RigidBody3D
	if rigid != null:
		return rigid.linear_velocity
	var character := node as CharacterBody3D
	if character != null:
		return character.velocity
	var value: Variant = node.get(&"linear_velocity")
	if value is Vector3:
		return value
	return Vector3.ZERO


## Horizontal arrival speed — what a wall or a breakable block wants to know.
##
## Prefers the host's own `approach_speed()` where it has one, so the two
## controllers keep answering exactly as they did before this file existed.
static func impact_speed(node: Node) -> float:
	if node != null and node.has_method(&"approach_speed"):
		return node.call(&"approach_speed")
	var moving := impact_velocity(node)
	return Vector2(moving.x, moving.z).length()


## Vertical speed, NEGATIVE downwards — what a floor wants to know. Rule 4,
## falling mass scales with height, measured rather than guessed.
static func descent(node: Node) -> float:
	if node != null and node.has_method(&"descent_speed"):
		return node.call(&"descent_speed")
	return impact_velocity(node).y


## Adds velocity to anything that can accept it. Returns false if it cannot.
##
## The one place that knows a `RigidBody3D` takes an impulse and a
## `CharacterBody3D` takes a velocity, so nothing else has to care which it has.
## `contact` is a global point for an off-centre impulse, which is what makes a
## crate tumble rather than slide like a hovercraft; pass `Vector3.ZERO` for a
## central one.
static func add_velocity(node: Node, change: Vector3, contact: Vector3 = Vector3.ZERO) -> bool:
	if node == null or change.is_zero_approx():
		return false
	var rigid := node as RigidBody3D
	if rigid != null:
		# Woken first. A settled crate is a SLEEPING RigidBody3D and ignores an
		# impulse completely — and settled is exactly the state a crate on a
		# see-saw or a pressure plate is always in.
		rigid.sleeping = false
		var impulse := change * rigid.mass
		if contact.is_zero_approx():
			rigid.apply_central_impulse(impulse)
		else:
			rigid.apply_impulse(impulse, contact - rigid.global_position)
		return true
	var character := node as CharacterBody3D
	if character != null:
		character.velocity += change
		return true
	return false


## Hands a body MOMENTUM rather than a velocity, so the speed it gains is
## divided by its own mass.
##
## **Use this and not `add_velocity` for anything that delivers a fixed amount
## of force** — a slam's shockwave, a launcher, an explosion. `add_velocity`
## gives every body the same change in speed whatever it weighs, which is right
## for `collide` (the mass is already in the formula) and wrong for everything
## else: it would fling a forty-mass giant exactly as fast as a one-mass pebble.
static func add_momentum(node: Node, momentum: Vector3) -> bool:
	return add_velocity(node, momentum / maxf(mass_of(node), 0.01))


## `launch()`, paid for in momentum instead of in speed. Same reason as above:
## one plank's worth of force should throw a crate further than a giant.
static func launch_momentum(node: Node, momentum: float) -> bool:
	return launch(node, momentum / maxf(mass_of(node), 0.01))


## How fast two things are approaching each other along `normal`, which points
## from `b` towards `a`.
##
## **RELATIVE, not absolute**, and this is the single most common way to get an
## impact wrong: measure only the body you think of as the attacker and you miss
## every case where the thing being hit is the one doing the moving. It cost
## this project a heavy enemy that could walk straight into the hero and
## deliver nothing, because the hero was standing still at the time.
static func closing_speed(a: Node, b: Node, normal: Vector3) -> float:
	return -(impact_velocity(a) - impact_velocity(b)).dot(normal)


## Something arrived at a body under its own steam, and nothing stopped it.
##
## **The twin of `collide()` and deliberately NOT the same arithmetic.**
## `collide()` is written for the body that just ran into something and had its
## velocity zeroed by `move_and_slide()`, so it gives that body back what the
## impact leaves it. Here nothing has been zeroed: the arriving body is still
## moving and the receiver may be standing perfectly still, so each side takes
## its true change — the receiver is shoved along the line of travel and the
## arriver slows by the mirror of it.
##
## Each change is scaled by the OTHER body's share of the mass, which is what
## makes a pebble bounce off a giant and a giant walk through a pebble.
##
## `normal` points from `receiver` towards `arriving`. Returns the speed the
## receiver gained.
static func deliver(arriving: Node, receiver: Node, normal: Vector3, contact: Vector3,
		transfer: float = 1.0, min_speed: float = 1.5) -> float:
	var closing := closing_speed(arriving, receiver, normal)
	if closing < min_speed:
		return 0.0
	var arriving_mass := mass_of(arriving)
	var receiver_mass := mass_of(receiver)
	var total := maxf(arriving_mass + receiver_mass, 0.01)

	var given := closing * (arriving_mass / total) * transfer
	if not add_velocity(receiver, -normal * given, contact):
		return 0.0
	add_velocity(arriving, normal * closing * (receiver_mass / total) * transfer)
	return given


## **Weight rule 2: momentum transfers on impact.** One impact, resolved as a
## perfectly inelastic collision — both bodies end up travelling at
## `m1 * v / (m1 + m2)`. Returns the speed that was delivered.
##
## `normal` points from `hit` towards `mover`, which is what
## `KinematicCollision3D.get_normal()` already gives you.
##
## **One formula, no special cases, and that is the whole point.** Ram something
## lighter than you and it flies while you barely slow; ram something much
## heavier and you stop dead. Nothing anywhere knows what "heavy" means, and a
## player can look at a thing and predict what hitting it will do — which is the
## difference between mass as a reasoning tool and mass as a stat.
##
## Both bodies receive the SAME change in velocity, which looks wrong for a
## second and is exactly right: that is what "they end up at the same speed"
## means. For the mover it is subtracted from whatever the solver left behind,
## so it composes with a wall slide instead of overwriting it.
static func collide(mover: Node, hit: Node, normal: Vector3, contact: Vector3,
		transfer: float = 1.0, min_speed: float = 1.5) -> float:
	# A graze delivers almost nothing, which is what the dot product buys:
	# scraping past a crate must not fling it across the room.
	#
	# THE MOVER'S OWN APPROACH, and deliberately not the relative one — which is
	# the opposite of what `deliver()` wants, and the difference is the whole
	# reason the two functions exist. This one's contract is "I moved into it":
	# measure the closing speed relatively and it also fires when something runs
	# into a STATIONARY mover, and then shoves that mover towards the thing that
	# hit them. It was tried, and it cancelled out the correct push a crate
	# thrown at the hero was already giving them.
	var closing := -impact_velocity(mover).dot(normal)
	if closing < min_speed:
		return 0.0

	var mover_mass := mass_of(mover)
	var hit_mass := mass_of(hit)
	var share := mover_mass / maxf(mover_mass + hit_mass, 0.01)
	var delivered := closing * share * transfer
	var change := -normal * delivered

	if not add_velocity(hit, change, contact):
		return 0.0
	add_velocity(mover, change)
	return delivered


## Throws something upwards without ever reducing what it already had.
##
## `maxf`, never an assignment: if a body is already rising faster than this, a
## see-saw or a launcher has nothing to add to it and must not take any away.
static func launch(node: Node, speed: float) -> bool:
	if node == null or speed <= 0.0:
		return false
	var rigid := node as RigidBody3D
	if rigid != null:
		rigid.sleeping = false
		rigid.linear_velocity.y = maxf(rigid.linear_velocity.y, speed)
		return true
	var character := node as CharacterBody3D
	if character != null:
		character.velocity.y = maxf(character.velocity.y, speed)
		return true
	return false
