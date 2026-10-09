extends Node3D
## Contact sheet for the CMU mocap clips on our mannequin: one row per clip, a few moments
## across it, root motion removed (hips stay put, height kept). Needs a display:
##   xvfb-run godot --path godot --rendering-driver opengl3 res://tests/mocap_preview.tscn -- --shot=out.png --clips=78_13,33_01:0.2-0.4 [--frames=6] [--from=0 --to=1]

var clips: Array = ["78_13", "78_17"]
var frames := 6
var t_from := 0.0
var t_to := 1.0


func _ready() -> void:
	var out := "user://mocap.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): out = a.trim_prefix("--shot=")
		elif a.begins_with("--clips="): clips = Array(a.trim_prefix("--clips=").split(","))
		elif a.begins_with("--frames="): frames = int(a.trim_prefix("--frames="))
		elif a.begins_with("--from="): t_from = float(a.trim_prefix("--from="))
		elif a.begins_with("--to="): t_to = float(a.trim_prefix("--to="))
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
	var ual: PackedScene = load("res://assets/quaternius/UAL1_Standard.glb")
	var gap_x := 1.6
	var gap_y := 2.4
	for r in clips.size():
		# "id" or "id:from-to" (fractions of the clip) per row.
		var spec := str(clips[r])
		var id := spec.get_slice(":", 0)
		var f0 := t_from
		var f1 := t_to
		var secs := spec.contains("@")       # "id@1.2-1.8": seconds instead of fractions
		if spec.contains(":") or secs:
			var r2 := spec.get_slice("@" if secs else ":", 1)
			id = spec.get_slice("@", 0) if secs else id
			f0 = float(r2.get_slice("-", 0))
			f1 = float(r2.get_slice("-", 1))
		var anim := MocapLib.clip(id)
		if anim == null:
			continue
		var span := MocapLib.span(anim)
		var to_t := func(u: float) -> float: return u if secs else lerpf(span.x, span.y, u)
		var row_y := (clips.size() - 1 - r) * gap_y
		for c in frames:
			var m: Node3D = ual.instantiate()
			m.position = Vector3((c - (frames - 1) * 0.5) * gap_x, row_y, 0)
			m.rotation.y = PI * 0.5       # side on: the clip's "forward" points right
			add_child(m)
			var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
			var lib := AnimationLibrary.new()
			lib.add_animation("clip", anim)
			ap.add_animation_library("mocap", lib)
			var t: float = to_t.call(lerpf(f0, f1, c / maxf(1.0, frames - 1.0)))
			ap.play("mocap/clip")
			ap.seek(t, true)
			ap.pause()
			var l := Label3D.new()
			l.text = "%s  %.2fs" % [id, t]
			l.font_size = 28
			l.outline_size = 8
			l.position = m.position + Vector3(0, 2.05, 0.5)
			add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = clips.size() * gap_y + 0.4
	cam.position = Vector3(0, (clips.size() - 1) * gap_y * 0.5 + 1.0, 20.0)
	add_child(cam)
	cam.current = true
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
