extends Node3D
## Step 1, piece 1: one local athlete on the placeholder field.
## Networking, other players and the AI test client come in later pieces.

var field := Field.new()
var athlete := Athlete.new()
var camera := ChaseCamera.new()
var hud := Label.new()


func _ready() -> void:
	InputSetup.register()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.7, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)

	add_child(field)
	field.build(Tuning.section("field"))
	Tuning.reloaded.connect(func(): field.build(Tuning.section("field")))

	add_child(athlete)
	athlete.state.pos = Vector2(0, 20)
	camera.target = athlete
	add_child(camera)
	camera.cam.current = true

	var layer := CanvasLayer.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 18)
	layer.add_child(hud)
	add_child(layer)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reload_tuning"):
		Tuning.reload()
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move := camera.world_move(stick)
	Movement.step(athlete.state, move, Input.is_action_pressed("sprint"), delta, Tuning.data)
	athlete.sync_visual()


func _process(_delta: float) -> void:
	var s := athlete.state
	hud.text = "speed %.1f m/s   stamina %d%%   cut %s\nWASD/left stick move, Shift/RT sprint, mouse/right stick look, F5 reload tuning\nClick to capture mouse, Esc to release" % [
		s.speed, int(s.stamina * 100.0), "plant" if s.cut_timer > 0.0 else "-"]
