# Project Heavyweight — Vision & Movement Design

Oct 24, 2026 · @Mark Burney · *Working title — rename at will*

## Vision

**Your weight is the key: a heavy hero who solves a fragile world by moving through it deliberately.**

The pitch: *Wario Land in 3D* — a 3D puzzle-platformer where mass and momentum are the player's entire toolkit. The hero is big, heavy, and proud of it. The world is structural and fragile: it bears weight, breaks under it, pivots around it, and permanently reshapes as the player applies force with intent. Movement itself is the puzzle language — how fast you arrive, from how high, and whether the ground can take it.

**The logline: a bull in a china shop — where the bull learns exactly what to break.** The idiom means careless destruction; the game subverts it. Players start as the idiom (crashing into everything, cheap and funny) and become its contradiction (a deliberate, precise force). Always pitch both clauses together — the first half alone sounds like a pure action game, which this is not.

The movement identity in one line: **precise when slow, unstoppable when committed — and the transition between the two is the skill.**

Genre position: a *deliberate* game, not an action game. Spectacle (collapses, smashed walls, toppled giants) is the payoff for thinking, never the loop itself. Tone stays joyful and warm — deliberate does not mean dour.

Scope commitment: **strictly single-player.** No multiplayer mode is planned or designed for — the core systems (persistent personal world-sculpting, authored puzzle states, a told-tale framing) assume one player and one save.

## Design pillars

Every future idea is tested against these four. A feature that serves none of them is cut, no matter how cool.

1. **Committed movement.** Inputs respond instantly; the body takes time. Speed is earned, hard to steer, and expensive to stop. Mastery means planning motion, not reacting.
2. **Weight is a reasoning tool.** Mass, thresholds, pivots, and impact force are a consistent system the player thinks with — not a combat stat and not a gimmick.
3. **Destruction is legible and consequential.** The player can read what will break before committing. Breaking the wrong thing is a real mistake — and every mistake is recoverable.
4. **Joyful, not dour.** A warm, funny, confident game. The hero's bulk is competence and charm. Deliberate pacing never means grim tone.

Tiebreak rule: when two ideas conflict, the *deliberate/puzzle* reading wins over the *action/spectacle* reading. Spectacle is the reward for deliberate play.

## The hero

A large, heavy-set, big-hearted protagonist whose mass is their superpower. Design intent, stated so art and writing never drift from it: **the hero's weight is strength, skill, and charm — never the punchline.** The character is confident in their body; the world's fragility is the world's problem.

Personality lives in the animation: instant, eager responses to input (head turns, feet plant, body leans the moment the stick moves) with mass expressed through follow-through — long slides, heavy landings, ground that reacts. The character should read as *powerful and happy about it*, in the Wario tradition of an unflinching body played for warmth.

## Movement system

Movement is modal, not continuous: the hero has a precise mode and a committed mode, and switching between them deliberately is the core skill. This is the Wario Land architecture — walking Wario is unremarkable on purpose; ramming Wario is the game. One continuous system cannot serve both puzzle precision and momentum joy; a state machine serves both without compromise.

**Cardinal rule — instant inputs, heavy body.** Every input gets a same-frame response (animation starts, intent registers). The *mass* is what takes time: acceleration curves, braking slides, wide turn arcs, committed jump trajectories. Players read input latency as bad controls and momentum curves as weight. Never confuse the two; never add delay to feel heavy.

&#91;embedded content: movement state machine · 4 states, 7 transitions\]

Every arrow is a player decision except the landing; soft landings from Air return to Walk the same way. The Slam box is the accent because it is the signature verb and the bridge between modes.

### Steering authority: speed is purchased with control

Steering authority is a **continuous falling function of speed** — one curve, not a hard mode toggle. The movement identity in full: **the controls never stop working — they change meaning with speed.** There is no regime where the player is a passenger; each regime has its own grammar:

- **Slow — the stick commands.** Below the walk-speed threshold, control is exact and instant, non-negotiable. This anchor is what keeps puzzle execution blameless: a player stuck on a puzzle must never be able to blame the controls.
- **Fast — the stick influences, the boost steers.** At momentum speeds the stick is a nudge on a mass in flight. The real steering is the **boost**: a discrete impulse that redirects by *adding* momentum in the input direction — vector addition, never a velocity rewrite. Course correction makes you faster and more committed; that is the point. A cooldown or limited taps keeps boosting from being pulsed into full authority.
- **Stopping — the slam-brake.** Slamming from motion kills horizontal momentum by delivering it into the ground. Impact force scales with the speed being killed, so braking hard on fragile footing breaks it — rule 2 applied to yourself. The emergency brake is never free, always available, and doubles as a deliberate tool: brake on purpose to punch through a floor.

Two guardrails on this system:

- Low-speed engagement comes from the **world** — thresholds, slopes, fragile spans — never from loosened controls. Walk mode stays exact; the terrain supplies the tension.
- Crashing is the explicit learning curve, so **early crashes are cheap and funny**: bounce, dust cloud, get up. Stakes rise with world fragility across the game, never with the controls getting looser.

### The verb set

| Verb | State | What it does | How it expresses weight |
| --- | --- | --- | --- |
| Walk / Run | Walk | Slow, exact positioning: aiming, plates, pivots, ledges | Tight and responsive; deliberately unglamorous. The manipulation mode |
| Charge (roll/ram) | Charge | Wind-up, then committed high-speed travel. The traversal verb | Telegraphed launch, degraded steering, no free brakes, real impact force |
| Jump | Walk or Charge | Arc locked at takeoff; minimal air steering | Distance scales with ground speed — a charge-jump is a cannonball, a standing jump is a hop |
| Slam | Any airborne state | Aimed downward impact. Attack, breaker, pressure input, see-saw launcher — and the brake: kills horizontal momentum by delivering it into the ground | Force scales with drop height and carried speed — braking hard can break your own footing. The signature verb |
| Crash-stop / slide | Charge exit | Ending a charge: hit something, slide out, or cancel into slam | Stopping is itself a mechanic with a cost |
| Boost | Charge or Air | Discrete impulse in the stick direction — the steering vocabulary at speed; course-corrects a committed trajectory | Redirects by adding momentum, never rewriting it — correcting makes you faster and more committed; limited by a cooldown |

Build priority: **the slam is this game's A-press** — the most-used, most-satisfying verb and the bridge between modes (charge → slam converts horizontal speed into aimed impact). The controller is tuned around the fall feeling incredible before anything else.

### The four charge properties

The charge is a decision with a blast radius, not movement automation. It preserves the weight fantasy only if all four hold:

1. **A wind-up, not a cast.** A visible \~0.5 s plant-and-rear before launch. The time cost of mass is paid as a telegraphed decision, not smeared across sluggish throttle.
2. **Degraded steering.** Wide arcs or near-locked heading while charging. Aiming *before* committing is the skill; early loss of control is the mastery curve, not friction.
3. **No free brakes.** A charge ends by impact (payoff or bounce-stun), by long slide (sliding past the ledge is on you), or by canceling into the slam — the escape hatch is itself a weight expression and a puzzle input.
4. **The speed is real.** Charge velocity obeys the same conservation as everything else: slopes add or bleed it, impacts transfer it, jumps inherit it, struck objects and enemies receive it. The moment the charge becomes a scripted animation with special-cased speed, the system is betrayed.

Net effect: top speed is *higher* than an agile hero's, but it must be earned, aimed, and survived. The hero is only "slow" for the first two seconds of any plan.

### Momentum as earned resource

- Slow from a standstill; devastating once rolling. Weight gates speed, it never caps it.
- Downhill slopes are free acceleration — converting height into speed is the game's currency, in both directions (slam converts speed/height back into force).
- Jump distance scaling makes run-up planning a constant micro-decision.

### Tuning parameters (expose all of these in the inspector)

Walk speed · charge wind-up duration · charge acceleration curve · charge top speed · turn radius vs. speed curve · slide friction · jump speed-scaling factor · air-steer authority · slam drop acceleration · impact force scalar · crash-stun / recovery duration · slope accel/decel multipliers · steering-authority curve (control vs. speed) · boost impulse strength · boost cooldown / tap count · brake impact scalar. The design lives in these curves; expect most of prototype week to be spent here.

**Engine note (Godot):** kinematic `CharacterBody3D` with hand-authored curves — fake the mass, never rigid-body-drive the hero. True simulated heavy controllers are notoriously miserable to make feel good; authored curves read as weight and play as a learnable system.

**Weight is 50% feedback.** Thud, screenshake, dust, crack decals, rumble, landing FOV kick, camera lag behind acceleration. Sluggish and weighty are the same numbers with different presentation — so placeholder juice goes in *during greybox*. For this game it is not polish; it is the mechanic.

## Universal weight rules

The BOTW lesson: don't bulletproof individual puzzles — ship a small set of globally consistent rules, state problems clearly, and let any rule-combination that works count as a win. These six rules apply everywhere, with **zero per-room exceptions**:

1. **Surfaces have visible weight thresholds.** Material and visual state (cracks, sag, creak) telegraph what a surface can bear before anyone steps on it.
2. **Momentum transfers on impact.** Speed × mass delivered into whatever is struck — walls, enemies, objects, pivots.
3. **The heavier side of a pivot wins.** See-saws, counterweights, hinged structures resolve by mass, always.
4. **Falling mass scales with height.** A slam from higher hits harder; drop height is a resource the player positions for.
5. **Enemies obey the same physics as the player.** Their weight breaks floors, tips pivots, and transfers momentum — which is what makes them puzzle material.
6. **Broken stays broken** (world scale). Destruction persists and only ever adds traversal options; discrete puzzle contraptions get local resets.

Engineering consequence: these rules must behave identically everywhere, so they are built as **one physics/interaction layer early** — never as per-level scripts. Systems amortize across the whole game; scripted content doesn't. This front-loads engineering and is the right trade for a small team.

## Destruction & puzzle design

Destruction is a **move**, not an outburst. In this blend, breaking the wrong thing is allowed to be a mistake — that's where tension and mastery live — under one non-negotiable rule:

**Every destruction consequence is previewable; every puzzle state is recoverable.** Players can read what will break before committing (thresholds, rule 1), and a botched setup always has a reset: respawning contraption pieces, room-reset levers, rebuild-on-reentry for discrete puzzles. At world scale, recoverability is structural instead: breaks only ever add options (rule 6), so no reachable sequence of destruction can strand the player. Irreversible mistakes with no reset produce rage-quits, not "aha."

**Unintended solutions stance: celebrate, with guardrails.** Rooms are stated as *problems*, not locks — any application of the weight rules that reaches the goal counts. Guardrails:

- **Goals are always legible**, even when solutions are open. Players forgive being stumped; they don't forgive being lost.
- **Cheese must cost effort or cleverness.** If "slam everything until it breaks" dominates, the fix is threshold tuning, never scripting.
- **Playtest for the degenerate solution, not the intended one.** Whatever lazy players find optimal is what the game *really is* — watch for it and tune it.

Technical rule: **author the physics, simulate the garnish.** Pre-fractured meshes with designed break points, topples along intended arcs with simulated wobble, thresholds as tuned numbers rather than true force integration. It reads as physics; it plays as a learnable system.

## Transformations — the food-attack system

Wario Land-style reaction transformations, resolved into one world rule: **still food is food; moving food is ammunition.** Transformation foods never sit in the world as pickups — they only arrive as *attacks*: thrown, dropped, launched, rolled, or chasing. Auto-eat is simply the hit reaction (Miri reflexively catches it in her mouth), and **standing into a telegraphed food-attack on purpose is the transformation input.** Dodge it: nothing happens. Accept it: you chose the tool. Player agency is preserved in both directions, with zero new controls.

The fiction: the pirates stole the harvest, so **their ammunition is the village's food** — they are perpetually arming the one creature who eats everything, and Miri eating incoming ordnance depletes their supply.

**Delivery taxonomy** (mapped to the draft crew):

- **Lobbed** — storks drop chili bombs and beehives from above
- **Launched** — tortoise-built food catapults and cannons: fixed emplacements that double as on-demand, renewable transformation dispensers beside the puzzles that need them (and are potentially re-aimable by Miri to deliver forms elsewhere)
- **Chasers** — feral produce animated by mishandled seed-magic; pursuing food marks pirate-held territory and doubles as a world-state readout
- **Rolling mass** — boulder-scale produce: hazard, transformation source, and weight object in one

**Standing rules:**

1. Every food-attack obeys the cartoon-telegraphy rule (readable at decision distance, staged like a gag) and the universal weight rules — a thrown melon is a mass with momentum like everything else.
2. **Forms end fast and diegetically** — water douses the fireball, a slam or sunlight shatters the ice, thorns pop the blimp — with a short timer as backstop. A mistaken transformation is a thirty-second joke, never a punishment; cure sources are placed as deliberately as attack sources, and that pairing *is* the puzzle vocabulary.
3. **Form cap: three or four.** Every form must pass the weight-grammar test — it alters mass, friction, or control authority, or it's cut:

| Form | Weight-grammar statement | Puzzle role |
| --- | --- | --- |
| Fireball | Destruction by other means | Burns rope, thatch, and timber that mass can't crack — a second material language |
| Ice block | Friction zero, authority zero | The authority curve at absolute bottom: pure committed momentum, aim before you freeze |
| Blimp | Mass zero | The inversion gag: reach heights, but thresholds and pivots stop answering to you |
| Honey (candidate) | Friction maxed | The anti-ice; stork-dropped hives |

## Enemies: fewer, larger, structural

A small pool of huge, weighty enemies — and they are **mobile puzzle elements first, combat targets second**. Because enemies obey the same physics as the player (rule 5), each one is a reusable puzzle noun:

- A felled giant is a **bridge** or a ramp.
- A lured heavy enemy is a **counterweight**, a **pressure-plate holder**, or a **wall-breaker** you aim.
- "The bigger they are, the harder they fall" is literal structural physics: toppling an enemy *onto* something is a solution verb.
- An enemy's own weight is a hazard the level exploits — floors that hold the player but not the giant chasing them.

This philosophy also fits the content budget: each enemy is a system that recombines across many rooms, not an encounter to balance. Design each one as a *moving mass with a behavior*, then ask what rooms can do with that mass.

## No-death & bosses

**There is no death.** Damage produces comedic reactions, never a life lost — consistent with cartoon logic, the fable register, and "early crashes are cheap and funny." The penalty design law that replaces it: **every penalty is live and in-arena — never travel time.**

- **Field damage:** reaction + knockback + the player's collected food *scatters* (recoverable scramble, Sonic-ring model). Enemies grab scattered food and flee — theft becomes **a chase you can win** (the pelican stuffing his pouch until the payload rule grounds him), converting punishment into gameplay.
- **Boss doctrine, in the lead's words:** *"The boss fight isn't who survives, but who gets away with the reward — nobody dies."* Bosses are folklore contests with physics: each is a multi-phase **structural puzzle** where the player spends a phase setting up a collapse (lure, break supports, load the counterweight). Getting hit never hurts Miri — it **regresses the setup**: weaver-bird riggers swoop in and repair what she broke while she recovers. Tension = defending work-in-progress, which is the correct tension for a puzzle game.
- **Bounds:** a hit undoes the current step, never the whole fight (full resets in a no-death game feel like death with extra steps). **Ejection from the arena is banned** — every reset is instant and in-place.
- Optional flavor: a boss opens by stealing something specific (a seed, the boost) so the fight is a retrieval with personal stakes.

## World design

Structure: **Mario 64 / Banjo-Kazooie playground worlds** — open, explorable, objectives scattered — with one adaptation: in those games the world is a stage for movement; here **the world itself is the puzzle**. The macro-structure is literally load-bearing: towers that fall particular ways, strata that crack open, see-saw geography, structures whose destruction order determines what's reachable. Each objective is a structural problem, not an obstacle course. Linear sequences are used only where a specific puzzle demands them.

**Persistent destruction is the progression system.** Worlds are re-entered repeatedly, and broken stays broken — every solved problem permanently reshapes the world: carved shortcuts, felled bridges, opened caverns. A late-game save file's world looks sculpted by that player's history. Design discipline this requires: author worlds so that no reachable sequence of breaks strands the player — at macro scale, destruction only ever adds traversal options. (This also delivers the havoc payoff: watching the world permanently deform under you, earned through deliberate play.)

**The terrain must talk back.** Deliberate movement stays engaging only when the ground constantly demands micro-decisions — thresholds, slopes, pivots, fragile spans everywhere. A heavy hero on flat empty ground is boring by definition; density of weight-reactive terrain is the level-design KPI.

**Scope:** fewer, denser worlds. Target **3–4 playground worlds** absolutely packed with structural interaction — on the order of 40–60 strong puzzle setups total — rather than many sparse ones. Handcrafted puzzle content is slow; the fewer-but-larger philosophy applies to the level count too.

### Mission structure — worlds as operations

Each world is a **pirate operation to dismantle** (the Sly Cooper spine): the hare scouts it; a mandatory mission chain sabotages it stage by stage; and **each story mission authors a major permanent destruction event** — collapse their crane, sink the loading dock, drop the cliffside onto the tunnels. Story progress is *legible as rubble*: the persistent-destruction system and the narrative structure are the same system. Around the spine, the playground stays fully open (seeds, food routes, transformation puzzles, side quests seeded by rescued captives). **No ejection, ever** — collect and keep playing. The village is the recovering hub. Open: what gates world-to-world progression (story missions, seed counts, or both) — the only law is diegetic justification.

### Post-game: revival is the reward

Collected-out worlds feel dead because collectibles are *subtractive* — every pickup taken removes a reason to exist. This game inverts the arc: each world's lifecycle is **occupied → liberated → rehabilitated**. After liberation, worlds repopulate — captives come home, markets reopen, wildlife returns, kids play in the rubble you made — and **replanted seeds visibly grow**: crops, groves, and canopy bloom across the world, leaving it *fuller* than it ever was mid-campaign. The living, restored, bustling world is itself the endgame reward — seeing it is the point. Seasoning stays light and optional — the hare's traversal races through the reshaped terrain, renewable harvest runs, a few mini-games — never a post-game chore list. Scope honesty: restoration states are mostly art dressing plus NPC placement on the persistence state machine the game already requires.

## Creative direction — DRAFT, return to this

> **Status: provisional.** This section records the creative brainstorm so far. Items marked **agreed** have team/lead sign-off in principle; everything else is a working draft to be challenged, fleshed out, and ratified before art or writing production starts. Characters and story in particular need a dedicated pass.

### Setting — agreed

A fantastical world inspired by the **Swahili coast and Eastern/Southern Africa** — dhow-age maritime culture, coast-to-highland geography (baobabs, termite-mound towers, kopje boulder stacks, rift escarpments, rope-and-timber architecture: structural, breakable terrain). Narrative register is the region's **animal-fable tradition** — trickster tales, clever-vs-strong morality stories — which structurally matches the game's "outsmart the bigger mass" design. The society is **mixed-species** (one village, many animals), which keeps conflicts about choices rather than kinds.

**Inspired-by rule (standing):** anchor in the region but build invented places, spirits, and figures that *rhyme* with the source — never depict real peoples' sacred figures or practices. Spiritual elements tie to invented land-features (the Great Baobab), not borrowed deities. Budget research time; plan a cultural-consultant pass before commercial release. Keep the pirate aesthetic firmly in the folkloric fable register.

### Miri, the hero — draft, return to

Young adult elephant girl; the village layabout. **Wrong for the job in spirit, the only right one in fact:** lazy, irreverent, food-obsessed — and physically the only creature on the coast who can do this. A **lazy genius whose full competence activates only when food is at stake**; every heroic feat gets reframed by her as food logistics.

- Inciting incident (draft): she slept through the pirate raid after the harvest feast; the able-bodied who gave chase were captured. She quests for the worst reason, loudly.
- The MacGuffin: the pirates stole the **magical seeds** — not the food, the *source* of all future food.
- Arc rule: she **never reforms the appetite**; the circle of it quietly widens from "me" to "us." Key beat: the captain offers her his version of her dream (eat like royalty, stop caring) and she refuses — her appetite eats *with* people, his takes *from* them. Ending: saves everyone, immediately devours half the victory feast.
- **Hard character law (standing, extends the Hero section):** the comedy comes from her *priorities*, never her *body*. Her size is competence and the win condition of every room; the world never shames it. Write this into the art brief before concepting.

### The captain — agreed in concept

A **hippo pirate captain**, Miri's dark mirror: extractive appetite vs. her communal one. The heaviest creature in the game — unbeatable by force, defeated by *structure* (draft finale: his own hoard-laden deck collapsed under him). Regional folklore of the hippo's appetite supports the casting.

### The hare — draft, return to

The village's **actual celebrated champion** — fast, clever, adored, the one this story "should" belong to (the regional trickster-hare tradition made literal). He pursued the pirates first and **lost to the tortoise first mate** — a deliberate inversion of the fable — which wounds his identity and explains his early mockery of Miri. Arc: contempt → grudging scout/intel partner → respect → the one who tells *her* tale. Thesis beat: *fast finds the problem; heavy solves it.* Open: captured (rescue objective) vs. humiliated-and-home (earlier party member); exact role depth. Flagged as needing more time.

### The elder — draft

A **pangolin elder** who keeps the Great Baobab (the seeds' source): armored, ancient, deliberate — the living thesis of "heavy and careful wins." Natural tutorializer for the authority curve.

### The pirate crew — draft roster, return to

Each character is a **weight behavior first** — a puzzle noun with a folklore source and a crew job. Two governing rules (standing, pending ratification with the team):

- **Flight rule: nothing is exempt from weight.** Every flier has a "ground it" answer — the universal one is *payload* (flight has a weight limit). A flier that can never be grounded is forbidden.
- **Water rule: Miri doesn't swim — she sinks.** Seafloor walking with her trunk as snorkel; underwater, weight logic inverts (buoyancy pulls up, floats are inverted platforms, currents replace slopes). Water is a second weight grammar, not a new movement system.

| Animal | Crew role | Weight behavior | Note |
| --- | --- | --- | --- |
| Tortoise (first mate) | The brains; crew engineers | Unflippable until slammed, then dome/ramp/platform; their contraptions are mid-game puzzle spaces | The schemer who beat the hare |
| Moles | Sappers | Undermine floors and footings from below | Attack the player's own physics |
| Hyenas | The muscle | Reckless chargers — momentum with no authority curve; demolish their own structures when dodged | What the player was in hour one; folklore's greedy fool |
| Marabou storks | Lookouts, bombers | Aimed dropped weights — her verb used against her; grounded via payload rule |  |
| Weaver birds | Riggers | Rebuild what Miri breaks — tempo pressure on destruction inside pirate territory only | Never violates broken-stays-broken elsewhere |
| Pelican | Quartermaster | Pouch = variable cargo mass; full means grounded; stealing the loot back re-arms him | Payload rule embodied |
| Crocodile (lieutenant) | Water boss | Ambusher where she's slowest; death-roll torques structures | First cut candidate if scope bites — reduce to one set-piece |

Scope note: not all seven are required. If cutting: keep hyenas (folklore-essential) and weaver birds + pelican (most mechanically novel) longest.

### Collectibles & village revival — parked, revisit

Draft economy: **food is the universal pickup**, with one standing tension — **eat it now** (heal/fuel, immediate and personal) vs. **bank it at home** (the village recovers as it's fed: vendors, mini-games, returning NPCs, the hub visibly rebuilding — permanent and communal). The me-vs-us arc, mechanized; per the character law, *neither choice is ever shamed*, and a fed village ultimately feeds Miri better than hoarding would. Draft roster (cap at four, each diegetically wanted): **Seeds** (progression — restoring them is the quest) · **Food** (economy + health) · **Legendary ingredients/recipes** (the rare "treasure" layer; cooking mini-game) · **Pourquoi tale scrolls** (lore system). Standing rule: **no collectible-count wall without diegetic justification.** Village-system scope tiers to choose later: *cosmetic* (visual recovery — nearly free, hub states exist anyway) / *functional* (recovery unlocks vendors and mini-games) / *systemic* (Chao-Garden-depth management — flagged as a scope trap for a four-person team).

### Lore system — draft, low priority

Collectible **pourquoi tales** in the regional tradition ("Why the Hippo Lives in the River"), told per world/boss — each secretly a gameplay hint about that creature's weight behavior. Natural assignment for the team's writer; possibly the hare's redemption vehicle (the storyteller learns to tell someone else's tale).

### Visual & audio direction — agreed in principle

Tex Avery / Looney Tunes energy **fused with coastal East African aesthetics** — not a cartoon set in Africa: the cartoon language itself is sourced regionally, at every layer.

- **Art keystone: Tingatinga.** A cel-shaded 3D interpretation of Tanzanian Tingatinga painting — saturated color, bold outlines, flat surfaces, playful exaggerated animals, decorative pattern fills: a parallel indigenous cartoon tradition, inherently bright, instantly distinctive. Supporting vocabulary: kanga/kitenge textile patterns (kanga cloths carry printed proverbs — a diegetic channel for hints and flavor), Makonde carving forms, Swahili coral-stone architecture, carved doors, and dhows.
- **Storytelling frame: hadithi.** The whole game framed as a told tale (the Swahili call-and-response opening; the elder — later perhaps the hare — as narrator). This makes the fourth wall *diegetic*: Miri mugs at the story's audience; narrator interjections replace tutorial text; the pourquoi scrolls become the game's native format.
- **Sound: a regional gag language.** Ngoma drums, mbira/kalimba, taarab strings, and call-response vocals as the stinger-and-impact vocabulary — a kalimba glissando is the slide whistle, a ngoma hit the timpani. The weight-feedback layer ("juice is the mechanic") carries culture instead of being culture-neutral.
- **Comedy register: trickster logic.** Gags resolve the way the region's fables do — small outwits strong, hubris falls to cleverness, schemers caught in their own schemes (the hyenas' charges; the captain felled by his own hoard).
- **Standing rules:** *exaggerate the presentation, never the rules* — squash, stretch, smear, and mug, but the mass numbers underneath stay honest (the animation lies; the simulation never does). *Cartoon acting is the telegraphy system* — failing surfaces sweat, creak, and wince: threshold readout, joke, and art direction in one. *Don Bluth darkness is a dial* — intensity through atmosphere, scale, and stakes, never cruelty to Miri or a broken fable register.
- **Performance (the real meaning of "pared down"): run on broad hardware.** The correct art direction is also the cheap one: flat/cel shading (no PBR), minimal lighting, low-poly models behind chunky silhouettes, stepped/smear animation (fewer frames reading as *more* cartoon), cartoon SFX as the cheapest juice. Godot's Compatibility renderer is available if maximum reach is wanted; set a low hardware floor early and test against it from the first greybox. The true performance budget is **physics and persistence** — fracture debris counts, body sleeping/merging, despawn policy, world-state serialization — so the art savings are spent there. Engineering line-item, not an afterthought.

### Creative open questions

- [ ] Miri's full characterization pass — voice, design brief, the character law applied
- [ ] The hare: captured vs. humiliated; depth of his role
- [ ] Naming register: fable role-names vs. Swahili-rooted personal names — pick one convention, never mix
- [ ] Final crew list and scope cuts
- [ ] Village cast beyond the elder; village structure and culture
- [ ] Story outline beat-by-beat (divergence scene placement, finale staging)
- [ ] Cultural research plan and consultant budget

* [ ] Final transformation roster — three or four forms, each passing the weight-grammar test
* [ ] World-gating decision: story missions, seed counts, or both (diegetic justification required)
* [ ] Village revival scope tier: cosmetic / functional / systemic

## Known traps & the standing rules that contain them

| Trap | Standing rule |
| --- | --- |
| Irreversible destruction soft-locks progress | Previewable + recoverable; at world scale, breaks only add paths |
| Emergent physics is unpredictable → no mastery | Author the physics, simulate the garnish; kinematic hero, pre-fractured meshes, tuned thresholds |
| Heavy reads as sluggish → "bad controls" | Instant inputs, heavy body; juice ships with greybox, not polish |
| Slam-everything cheese dominates | Tune thresholds, never script exceptions; playtest the lazy path |
| Handcrafted puzzle content burns the budget | 3–4 dense worlds; systemic rules + reusable enemy nouns amortize |
| Puzzle precision fights momentum fun | Modal movement: walk state for precision, charge state for traversal |
| Vision drifts back toward pure action | Pillar tiebreak: deliberate wins; spectacle is the reward, not the loop |

These rules are standing: a proposal that violates one needs this document amended first, not an exception granted quietly.

## Open questions

- [ ] **Charge renewability.** Starting stance: wind-up is the only cost; tune its length until pulsing the charge for short distances feels dumb. Fallbacks if that fails: recovery delay after crash-stops, or charge only initiates from near-standstill.
- [ ] **B-primary or C-primary** (momentum-mastery lean vs. puzzle-logic lean). Decided by the greybox playtest, not by discussion: watch what the team gravitates to.
- [ ] **Team alignment check.** Each member independently writes their one signature trailer moment before reading this doc's vision; compare against it. This blend is the farthest from the group's original "cause havoc" language — confirm it was chosen, not deferred to.
- [ ] **Hero identity** — name, species/design, art direction. Constraint from the Hero section: weight is competence and charm, never the joke.
- [ ] **Working title.** "Project Heavyweight" is a placeholder.
- [ ] **Unintended-solutions stance ratification.** Celebrate-with-guardrails is the recommendation written here; the team should explicitly agree or push back.

* [ ] **Boost economy and input.** Impulse strength, cooldown or tap count, ground vs. air availability — tuned so boosting can't be pulsed into full authority. Also decide the input: its own button, or the charge input tapped while already at speed?

- [ ] **Swimming & water physics — major design pass needed.** The game needs strong swimming mechanics and water-based physics; this is flagged as important and deliberately unresolved. It must be reconciled with the draft water rule in Creative Direction (sink-and-walk, trunk snorkel, inverted weight grammar): decide whether Miri swims, sinks, or both — and how water carries the weight system. Dedicated session before any aquatic world is designed.

## Milestone 1: the greybox that proves or kills this

Scrap the ported Mario 64 verb set — an agility moveset made heavier can only produce a worse Mario. Build the modal controller from scratch instead. Budget: roughly a weekend to a week, most of it spent in the tuning parameters.

**Build list**

- [ ] Kinematic `CharacterBody3D` controller: walk state, charge state (all four properties), momentum-scaled jump, aimed slam, charge→slam cancel
- [ ] All tuning parameters exposed in the inspector
- [ ] Placeholder juice wired in from day one: landing thud SFX, screenshake, dust puff, ground-crack decal, FOV kick, camera lag
- [ ] Test room with reactive props: a slope to build speed · a breakable wall at its bottom · a gap clearable only by charge-jump · a pressure plate requiring walk-mode precision · a crumble-floor with a weight threshold · a see-saw · a tall platform to slam from

**Pass/fail test:** with zero objectives and zero enemies, is charging down the slope into the wall grin-inducing within a day of tuning wind-up, steering, and impact numbers? If yes — the vision holds; everything else in this document builds on proven ground. If no after honest tuning effort — the problem is curve shapes or missing juice before it is the design; fix those first, then re-judge.

**Secondary read:** what the team actually plays with answers the B-vs-C lean. Everyone looping the slope-and-wall → B-primary. Everyone fiddling with the see-saw and plate → C-primary.

## References & market position

| Reference | What to take from it |
| --- | --- |
| Wario Land series (esp. II / 4) | The template: modal heavy hero, body as multitool, charm in bulk, walking deliberately unremarkable |
| Mario 64 / Banjo-Kazooie | Playground world structure, scattered objectives, re-entered worlds; Banjo proves puzzle-platforming works in them |
| Breath of the Wild / Tears of the Kingdom | Globally consistent rules, multiple-solution problems, legible goals, celebrate lateral thinking |
| Death Stranding | Deliberate movement stays fun when terrain constantly talks back |
| Donkey Kong Bananza (2025) | The anti-reference: joyful heavy smashing at AAA scale. The pure-action lane is owned |

**Differentiation:** Bananza is unconstrained smashing; this game is **mass as a reasoning tool** — thresholds, structural logic, enemies as physics material, destruction you plan. A deliberate puzzle-platformer with a heavy hero is a lane the action giants deliberately aren't in, and the smaller puzzle-platformer audience rewards exactly this kind of distinctiveness.
