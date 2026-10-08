extends Node3D
## Renders the Quaternius mannequin in a few clips side by side (needs a display, e.g. xvfb-run).
##   godot --path godot --rendering-driver opengl3 res://tests/model_preview.tscn -- --shot=out.png --clips=A,B,C --t=0.5

func _ready() -> void:
	var out := "user://preview.png"
	var clips := ["OverhandThrow", "Shield_Dash", "Hit_Knockback", "Slide_Loop"]
	var t := 0.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): out = a.trim_prefix("--shot=")
		elif a.begins_with("--clips="): clips = Array(a.trim_prefix("--clips=").split(","))
		elif a.begins_with("--t="): t = float(a.trim_prefix("--t="))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.7, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	add_child(ground)
	var scene: PackedScene = load("res://assets/quaternius/UAL2_Standard.glb")
	for i in clips.size():
		var m := scene.instantiate()
		m.position = Vector3((i - (clips.size() - 1) * 0.5) * 1.8, 0, 0)
		add_child(m)
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		ap.play(clips[i])
		ap.seek(t, true)
		ap.pause()
		var l := Label3D.new()
		l.text = clips[i]
		l.font_size = 48
		l.position = m.position + Vector3(0, 2.3, 0)
		add_child(l)
		if i == 0:
			var aabb := _aabb(m)
			print("model height %.2f m, aabb %s, clips %d" % [aabb.size.y, aabb, ap.get_animation_list().size()])
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 6.5)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	add_child(cam)
	cam.current = true
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()


func _aabb(n: Node) -> AABB:
	var box := AABB()
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		var b := mi.global_transform * mi.get_aabb()
		box = b if box.size == Vector3.ZERO else box.merge(b)
	return box
