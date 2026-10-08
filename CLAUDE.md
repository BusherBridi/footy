# Footy: working notes for Claude Code

Footy is an arcade, Rematch-style American football game. Each human controls exactly one athlete. It should feel fast and skill-driven, not like a sim.

## Working rules

- **Discuss before building.** Busher wants to be involved in every step. Propose the next piece, agree on it, then build only that piece. Don't start the next step on your own.
- **Nothing is locked in.** Every rule, number and mode may change after playtesting.
  - Every gameplay number goes in one tuning file, never hard-coded.
  - Alternatives that are still undecided (QB camera modes, sweet-spot vs simple-hold throw power) are built as in-game toggles so they can be compared.
- **Art.** Simple shapes and primitives, plus free CC0 models and animations (agreed Oct 2026; currently the Quaternius Universal Animation Library in `godot/assets/quaternius/`). No AI-generated art, and no real NFL teams, logos, players or Rematch assets.

## Design

- `docs/design.md` is an export of the design doc. The live doc is the source of truth: https://claude.ai/code/artifact/a197a1ec-4d9b-4d97-bd61-cf8181e77abd
- Design discussion happens in the Claude project. If a design question comes up while coding, raise it with Busher rather than deciding it silently, and note any agreed change so the doc can be updated.

## Engineering decisions

- Godot 4.
- Online multiplayer from the start. Bots are allowed (agreed Oct 2026): they drive test clients through the normal input path. Whether bots also fill empty slots in real matches is still open.
- One server-authoritative "referee" decides tackles, catches and fumbles.
  - For now a player hosts (listen server).
  - Keep the code able to run as a headless dedicated server later.
- Your own athlete responds instantly on your screen (client prediction). Other players are interpolated slightly behind real time.
- Player movement is custom kinematic code, not physics bodies.
- A ball flight is a calculated arc from launch point, direction and power, so every client computes the same flight.
- Tackles are resolved by rules (speed, angle, counter timing) and then animated.

## Build order

1. Two or more players running around a field online, with movement tuned until it feels good.
2. Free-aim throwing and catching.
3. Tackling, stiff arms, jukes and laterals.
4. A full play: snap, rush timer, downs and scoring.
5. Playbook, voting, motion and audibles.
6. Match flow: clock, halves and sudden death.

The first build gives every athlete identical stats. Archetypes come later as multipliers in the tuning file.
