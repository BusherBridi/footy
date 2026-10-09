extends Node3D
## Moves through the real Athlete code: each row a move, left to right across its duration.
## "old" rows use the clip the move had before the mocap clips. Needs a display:
##   xvfb-run godot --path godot --rendering-driver opengl3 res://tests/moves_sheet.tscn -- --shot=out.png [--moves=spin,catch]

# key, how it's triggered, the old clip ("" = none), status for status-driven moves
const MOVES := [
	["spin", "oneshot", "", 0], ["juke_right", "oneshot", "", 0], ["juke_left", "oneshot", "", 0],
	["catch", "oneshot", "Spell_Simple_Shoot", 0], ["hurdle", "status", "NinjaJump_Idle", AthleteState.Status.HURDLE],
	["down", "status", "", AthleteState.Status.DOWN], ["getup", "status", "", AthleteState.Status.DOWN], ["blocking", "status", "Push", AthleteState.Status.BLOCKING],
	["stance", "stance", "Crouch_Fwd", 0],
]
const COLS := 6


func _ready() -> void:
	var out := "user://moves.png"
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): out = a.trim_prefix("--shot=")
		elif a.begins_with("--moves="): only = Array(a.trim_prefix("--moves=").split(","))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	add_child(sun)
	var rows: Array = []
	for m in MOVES:
		if not only.is_empty() and not only.has(m[0]):
			continue
		rows.append([m, false])
		if m[2] != "" and str(Tuning.section("art")["clips"].get(m[0])) != m[2]:
			rows.append([m, true])
	var gap_x := 1.6
	var gap_y := 2.3
	var clips: Dictionary = Tuning.section("art")["clips"]
	for r in rows.size():
		var m: Array = rows[r][0]
		var old: bool = rows[r][1]
		var key: String = m[0]
		var spec = clips.get(key)
		var dur := float(spec.get("fit", 1.2)) if spec is Dictionary else 1.0
		if spec is Dictionary and spec.get("loop", false):
			dur = (float(spec["to"]) - float(spec["from"]))
		var row_y := (rows.size() - 1 - r) * gap_y
		for c in COLS:
			var t := dur * c / float(COLS - 1)
			if old:
				clips[key] = m[2]
			var ath := Athlete.new()
			add_child(ath)
			ath.set_team(r % 2, false)
			ath.position = Vector3((c - (COLS - 1) * 0.5) * gap_x, row_y, 0)
			_pose(ath, m, t)
			if old:
				clips[key] = spec
			ath.position = Vector3((c - (COLS - 1) * 0.5) * gap_x, row_y, 0)
			ath.rotation.y = -PI * 0.5      # side on
			var l := Label3D.new()
			l.text = "%s%s  %.2fs" % [key, " (old)" if old else "", t]
			l.font_size = 26
			l.outline_size = 8
			l.position = ath.position + Vector3(0, 2.0, 0.6)
			add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows.size() * gap_y + 0.4
	cam.position = Vector3(0, (rows.size() - 1) * gap_y * 0.5 + 1.0, 20.0)
	add_child(cam)
	cam.current = true
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()


func _pose(ath: Athlete, m: Array, t: float) -> void:
	var key: String = m[0]
	var ap: AnimationPlayer = ath._anim
	match m[1]:
		"oneshot":
			ath.set_visual(Vector2.ZERO, Vector2(0, -1), 6.0)
			ath.play_oneshot(key)
		"status":
			var left := 0.5 if key == "getup" else 9.0
			ath.set_visual(Vector2.ZERO, Vector2(0, -1), 4.0, m[3], 0, false, 0, left)
		"stance":
			ath.set_visual(Vector2.ZERO, Vector2(0, -1), 3.0, 0, 0, false, 1)
	# Step like the game does: one big advance right after a blended play() keeps the old pose.
	var step := 1.0 / 60.0
	var done := 0.0
	ap.advance(0.0)
	while done + step < t:
		ap.advance(step)
		done += step
	ap.advance(t - done)
	ap.pause()
