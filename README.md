# Footy

An arcade, Rematch-style American football game made in Godot 4. Each player controls one athlete in online 5v5 tackle football.

Status: step 2 in progress. Host can press B to add a test bot receiver (V removes them). Built so far: movement, host/join, prediction, interpolation, fake lag, test bots, QB throw (look = angle, hold = power, arc preview, power reticle, landing marker, two QB cameras) are in `godot/`. Open that folder in Godot 4.3+ and press play. Host with the menu, or from a terminal: `godot --path godot -- --host`, `-- --join=IP`, add `--bot` (wander), `--route[=out]` (receiver) or `--qb` (takes the ball and throws) for test bots, `--lat=100 --loss=5` for fake lag.

- Design: [docs/design.md](docs/design.md), exported from the [live design doc](https://claude.ai/code/artifact/a197a1ec-4d9b-4d97-bd61-cf8181e77abd)
- Working rules for Claude Code: [CLAUDE.md](CLAUDE.md)
