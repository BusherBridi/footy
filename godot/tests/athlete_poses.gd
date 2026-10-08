extends Node3D
## Renders a row of athletes, one per state, to check the animation mapping by eye.
##   xvfb-run godot --path godot --rendering-driver opengl3 res://tests/athlete_poses.tscn -- --shot=out.png [--t=0.6]

const CASES := [
	["idle", 0.0, 0], ["walk", 2.0, 0], ["jog", 6.0, 0], ["sprint", 8.7, 0],
	["set", 0.0, AthleteState.Status.SET], ["down", 0.0, AthleteState.Status.DOWN],
	["dive", 9.0, AthleteState.Status.DIVING], ["stumble", 3.0, AthleteState.Status.STUMBLE],
	["truck", 5.0, AthleteState.Status.TRUCK], ["hurdle", 7.0, AthleteState.Status.HURDLE],
	["wrapped", 2.0, AthleteState.Status.WRAPPED], ["holding", 2.0, AthleteState.Status.HOLDING],
]
var athletes: Array = []
var t := 0.6


func _ready() -> void:
	var out := "user://poses.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): out = a.trim_prefix("--shot=")
		elif a.begins_with("--t="): t = float(a.trim_prefix("--t="))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.7, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.5, 0.25)
	pm.material = gm
	ground.mesh = pm
	add_child(ground)
	for i in CASES.size():
		var a := Athlete.new()
		add_child(a)
		a.set_team(i % 2, false)
		athletes.append(a)
		var l := Label3D.new()
		l.text = CASES[i][0]
		l.font_size = 40
		l.position = _spot(i) + Vector3(0, 2.3, 0)
		add_child(l)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.2, 12.5)
	cam.rotation_degrees = Vector3(-10, 0, 0)
	cam.fov = 60
	add_child(cam)
	cam.current = true
	var shot_time := t
	while shot_time > 0.0:
		_pose()
		await get_tree().process_frame
		shot_time -= get_process_delta_time()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()


func _spot(i: int) -> Vector3:
	return Vector3((i % 6 - 2.5) * 2.4, 0, -4.0 if i < 6 else 0.5)


## Side-on heading (+x) so the poses read in profile.
func _pose() -> void:
	for i in athletes.size():
		var c: Array = CASES[i]
		var p := _spot(i)
		athletes[i].set_visual(Vector2(p.x, p.z), Vector2(1, 0), c[1], c[2], 0, false)
