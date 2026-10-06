# Football Game Design Doc

Oct 4, 2026 · @Busher Bridi

## Vision

An arcade American football game in the spirit of Rematch, where every human controls exactly one athlete. It is fast and skill-driven, not a simulation, and every player matters on every play.

- Engine: Godot 4.
- Online multiplayer from the start. Bots are allowed (agreed Oct 2026): they drive test clients through the normal input path. Whether bots also fill empty slots in real matches is still open.
- Placeholder art only, and no AI-generated art. The prototype proves the core gameplay.

Everything in this doc is a starting point and subject to change after playtesting. The build keeps rules, numbers and modes swappable (tuning file, in-game toggles) so nothing is locked in.

## Format and rules

5v5 tackle football built on flag football's format, so there are no linemen who only block.

| Rule | Setting | Status |
| --- | --- | --- |
| Team size | 5v5 | Agreed |
| Contact | Full tackling: dives, stiff arms, big hits | Agreed |
| Rush timer | No rushing until it expires, then any defender can rush | Agreed |
| Timer length | About 3 seconds, shown as a ring around the QB | Proposed |
| Timer ends early | If the QB runs past the line of scrimmage | Proposed |
| Field | About 60 yards | Proposed |
| Downs | 4 downs to reach midfield, then 4 more to score | Proposed |
| Punting | None; failing on downs turns the ball over | Proposed |
| Laterals | Unlimited backward pitches | Proposed |
| Scoring | Touchdown is 6; then a live 1 point try from close or 2 point try from farther out | Proposed |

## Roles

There are no fixed positions apart from two rotating leaders, so everyone gets a turn running each side of the ball.

- **QB:** changes automatically at each new drive, going to whoever has had the fewest turns, and anyone can pass. When the offense reaches midfield, teammates vote to keep or switch the QB without knowing who would be next. A switch needs a majority (3 of the 4 teammates); a 2 to 2 tie keeps the current QB. The QB has the final call on offensive plays.
- **Defensive lead (middle linebacker):** changes by the same rules as the QB. They have the final call on the defense and can shift players before the snap.
- **Everyone else:** receivers on offense and defenders on defense. They take whichever play slot is nearest to where they're standing.

## Archetypes

Each player picks an archetype on a hero-style selection screen before the match. Teammates' picks are visible, so the team can see what it's building and fill gaps.

Players can swap archetypes at every change of possession, like changing personnel, during a short window of about 5 seconds. Picks then stay locked until the next change of possession, so plays aren't slowed down. Both teams see each other's lineups, so the defense can counter a heavy offense.

**Trading:** during the selection window, a player can offer to trade the QB or defensive lead role with a teammate. The trade goes through if the teammate accepts.

An archetype applies on both offense and defense, and also sets your QB style for when the rotation reaches you. That way QB subtypes exist without ending the rotating QB.

| Archetype | Offense | Defense | As QB | Status |
| --- | --- | --- | --- | --- |
| Speedster | Fastest, easiest to bring down | Cover corner | Scrambler: fast runner, average arm | Proposed |
| Bruiser | Breaks tackles, slower | Rusher, hardest hitter | Physical: runs over people, inaccurate | Proposed |
| Hands | Bigger catch range, wins jump balls | Best at swats and interceptions | Pocket passer: most accurate, slow | Proposed |
| Balanced | A bit of everything | A bit of everything | Balanced arm and legs | Proposed |

The first build gives everyone identical stats so the base feel can be tuned. Archetypes are added afterwards as multipliers in the tuning file.

## Plays and pre-snap

A small playbook keeps teams of strangers coordinated, and the pre-snap moment is a mind game between the QB and the defensive lead.

Each play runs in this order:

1. **Reset (about 3 seconds):** after a tackle, everyone moves to the new line. Players vote on a play from a radial wheel of 6 to 8 plays, and the QB sees the vote counts.
2. **Call:** the QB locks any play and picks 2 backup plays for audibles. If the QB doesn't choose, the top-voted play wins. The defense votes man, zone or blitz, and the linebacker has the final say.
3. **Line up:** routes are drawn on the field for each receiver, and the QB sees all of them. The defense's call is hidden from the offense.
4. **Pre-snap (play clock about 10 seconds):** the QB reads the defense. They may send one receiver in motion and audible once to a backup play. The linebacker may shift players or show a fake blitz.
5. **Snap:** the QB snaps whenever they choose, including mid-motion.

Motion rules:

- The QB picks any receiver and taps motion. That receiver gets a sound cue and a drawn path, and they run it themselves.
- While in motion, the receiver can only move sideways or backward. Their route redraws from wherever they end up.
- Only one player can be in motion. The game stops everyone else moving before the snap instead of calling penalties.
- Some plays have motion built in, with a fixed receiver and path.

Routes guide players but don't lock them in. Anyone can break off a route, and the QB can throw anywhere.

## Controls and camera

The QB throws with free aim: point the camera at a spot on the field and hold to set power, like shooting in Rematch. The controller layout below is a starting point to tune in playtesting.

| Button | Defense | Ball carrier |
| --- | --- | --- |
| RT | Sprint | Sprint |
| X | Close tackle (jam at the line) | Stiff arm |
| B | Dive | Spin |
| Y | Play the ball: tap to swat, hold to intercept | Truck |
| A | Jump | Hurdle |
| LB | Ping | Lateral |

- **Cutting and jukes:** automatic with a hard stick flick.
- **QB before the throw:** LT aims, RT throws (hold for power), RB toggles lob or bullet, plus pump fake and fake handoff buttons.
- **Tackles only connect with the ball carrier.** Pressing tackle near anyone else is a committed whiff with a stumble, so fake handoffs and pump fakes can make defenders miss.
- **Jam:** within about 5 yards of the line just after the snap, the close tackle button jams a receiver instead.
- **No penalties or flags.** The game enforces the rules: defenders can't cross the line before the rush timer ends, nobody can move early, and interference can't happen.

The camera sits third-person behind your own athlete. The QB camera is undecided, so the prototype will include several switchable QB camera modes to compare in playtesting.

## Mechanics

Movement is momentum-based with quick plants, and sprint uses stamina.

- **Weight:** top speed takes a moment to reach, and a hard cut costs speed. A quick plant lets you change direction sharply, so jukes and pursuit angles take skill.
- **Sprint:** a stamina meter that refills between plays. Players choose when to burst, for example on a route break or a breakaway.

Movement details (starting values to tune):

- **Acceleration:** about 1 second from standing to top speed.
- **Sprint:** about 25% faster than a run. A full bar lasts about 4 seconds of sprinting, refills fully during the reset and slowly while jogging. With an empty bar you can't sprint, counters get weaker and fumble chance rises.
- **Turning:** the faster you go, the wider you turn.
- **Cutting:** automatic when you flick the stick hard. A sharp cut is a brief plant (about 0.15 seconds) that keeps around 60% of your speed.
- **Ball carrying:** the carrier runs about 5% slower, so pursuit angles work.
- **Backpedal:** defenders can backpedal facing the QB, slower than running forward. Turning to run with a receiver takes a moment, which receivers can attack.

Throwing has two types, chosen with a modifier button. Hold time sets power for both.

- **Bullet:** fast and flat, beats tight coverage.
- **Lob:** high and slower, goes over defenders.
- **Landing marker:** once the ball is in the air, everyone sees a marker where it will land. Receivers know where to run, and defenders can break on the ball for contested catches.

Passing details:

- **Aim:** holding LT puts a target on the field. Leading a receiver is the QB's skill; there's no auto-lead.
- **Accuracy:** the ball lands inside a circle around the target. It grows with nearby rushers, throwing on the run, throwing across your body and low stamina, and shrinks with set feet. QB style sets the base size.
- **Power:** two modes, switchable in-game for playtesting. *Sweet spot meter:* the sweet spot moves with target distance; early release falls short, late sails long. *Simple hold:* hold longer to throw farther, and the game picks the arc. Deep throws take longer to charge either way.
- **Throw away and sacks:** the QB can throw out of bounds; a tackle behind the line with the ball loses yards.

Catching:

- Mostly automatic when the ball arrives within catch range; Hands has a bigger range.
- Contested catches go to better position and jump timing; a tie is incomplete.
- Defenders choose to swat (safe) or go for the interception (risky, a miss leaves the receiver open).
- Catching while sprinting or being hit lowers the success chance.

Tackling is a timed counter system, so every contact is a quick mind game.

| Defender move | Strength | Weakness |
| --- | --- | --- |
| Close tackle | Reliable | Short reach |
| Dive | Long reach | On the ground for about 1 second if it misses |
| Arm tackle from the side | Quick | Weak hold |

| Carrier move | Beats | Cost | Risk |
| --- | --- | --- | --- |
| Juke | Dive | Stamina, loses speed in the plant | Weak against a close tackle |
| Hurdle | Dive (leap over it, keeping speed) | Stamina | Hit in the air by a standing defender = big hit, higher fumble chance |
| Spin | Arm tackle from the side | Stamina | Brief loss of vision and speed |
| Stiff arm | Close tackle | Stamina | Weak against hits from the side |
| Truck | Close tackles and head-on hits (large balance bonus) | Heavy stamina, slows you down | Easy target for side hits and gang tackles |

Each ball carrier counter costs stamina and needs good timing, so mashing buttons doesn't work.

Fumbles are rare and happen only on big hits, such as a side hit on a sprinting carrier. Low stamina raises the fumble chance, so a tired carrier is easier to strip. The detailed fumble rules come later.

**Tackle resolution:** every collision compares the defender's **hit power** (speed toward the carrier × archetype weight) with the carrier's **balance** (speed in their own direction × weight, plus a bonus for a well-timed counter).

- **Head-on:** both players' momentum counts fully, giving the biggest hits and the most broken tackles.
- **From the side:** the carrier's forward speed barely helps. This is the best angle for a defender and where fumbles happen.
- **From behind:** almost always a tackle, never a big hit.

| Outcome | When | Result |
| --- | --- | --- |
| Clean tackle | Hit power clearly wins | Carrier goes down on the spot |
| Drag | Close contest | Carrier falls forward 1 to 3 yards; a second defender ends it and their hit power adds up |
| Broken tackle | Balance wins | Carrier stumbles and loses some speed but keeps going; defender is briefly off balance |
| Big hit | Hit power wins by a lot, from the front or side | Small fumble chance |

**Gang tackles:**

- A defender joining within about 0.5 seconds of first contact adds hit power: the second adds 100%, the third 50%. At most 3 players can be in one collision.
- Any joining defender ends a drag immediately.
- After a broken tackle the carrier stumbles briefly, and a defender hitting during the stumble gets a bonus.
- **Strip:** a joining defender can try to rip the ball out instead of adding hit power. Success depends on the carrier's stamina. If it fails, their hit power doesn't count.
- Pushing the pile (carrier's teammates adding balance) is planned for later, not the first version.

**Blocking:**

- Any offensive player without the ball can block while a teammate carries it, including downfield on runs and after catches.
- X is block when you don't have the ball: tap for a quick shove that slows a defender, hold for a sustained block.
- Blocks use the same weight and speed math as tackling, so Bruisers block best and Speedsters worst.
- Defenders escape with a timed shed or a spin, both costing stamina. Every block lasts at most about 1.5 seconds.
- You can only engage from the front or side, so blocks in the back can't happen.
- Some plays let a receiver stay in to block for the QB before the throw: one fewer target, more time after the rush timer.

## Match structure

The first playtest uses a 6 minute match made of two 3 minute halves.

- There are no huddles or menu screens. Play resets in about 3 seconds after each tackle.
- The clock keeps running except after scores and turnovers.
- A tied game goes to sudden death, where the first score wins.

A **possession** is a whole drive: every play a team runs from getting the ball until it scores, turns it over (interception, lost fumble, failing on downs), or the half ends.

## Engineering and physics

Gameplay is driven by our own predictable code rather than the physics engine, and one machine decides every outcome, so play stays fair online.

- **Movement:** athletes are moved by custom code for acceleration, top speed, cut sharpness and momentum, not physics bodies. Movement stays predictable, tunable and easy to sync.
- **Ball:** a throw is a launch point, direction and power, and the arc is calculated. Every screen computes the same flight from those three values.
- **Tackles:** decided by rules (speed, angle, dive or stiff arm timing), then animated. Ragdoll can be added later for looks only.
- **Referee:** one authoritative machine decides tackles, catches and fumbles. Your own athlete responds instantly on your screen, and other players are smoothed slightly behind real time.
- **Hosting:** a player hosts for now, which is free and simple for playtests. The code will run as a headless dedicated server later without changes.
- **Tuning:** every gameplay number lives in one tuning file, so the feel can change between playtests without code edits.

The biggest risk is lag, especially a tackle between two players with poor connections.

## Build order and open questions

Networking comes first, since it was chosen first, and each step adds one piece of the play loop:

1. Two or more players running around a field online, with movement tuned until it feels good.
2. Free-aim throwing and catching.
3. Tackling, stiff arms, jukes and laterals.
4. A full play: snap, rush timer, downs and scoring.
5. Playbook, voting, motion and audibles.
6. Match flow: clock, halves and sudden death.

Open questions:

- [ ] Which QB camera mode feels best? To be settled in playtesting.
- [ ] Confirm the proposed numbers in Format and rules.
- [ ] Which 6 to 8 plays go in the first playbook?
- [ ] Should playtests allow fewer than 5 per side, such as 3v3, when not enough people are online?
- [ ] Should bots fill empty slots in real matches, or only drive test clients?
- [x] Controller and keyboard+mouse both supported (decided during step 1).
