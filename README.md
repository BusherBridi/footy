# Footy

An arcade, Rematch-style American football game made in Godot 4. Each player controls one athlete in online 5v5 tackle football.

Status: step 4 in progress. **Play vs bots** (menu, or `godot --path godot -- --match`) runs 5v5 plays against AI bots: snap (E), rush timer, line of scrimmage, tackles, turnovers and touchdowns. You are the QB on offense and the linebacker on defense. `--autoplay` lets the AI play your athlete too (watch mode). The old free-roam testing mode is **Host sandbox** (`--host`). Downs and scoring are in: 4 downs to reach midfield, then 4 to score, touchdowns (6) with a 1- or 2-point try (press 1 or 2 before the snap), safeties and turnovers on downs.

- Design: [docs/design.md](docs/design.md), exported from the [live design doc](https://claude.ai/code/artifact/a197a1ec-4d9b-4d97-bd61-cf8181e77abd)
- Working rules for Claude Code: [CLAUDE.md](CLAUDE.md)
