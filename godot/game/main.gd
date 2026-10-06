extends Node3D
## Entry point: builds the placeholder world, then hosts or joins a match.
## Command line (after `--`): --host, --join=IP, --port=N, --bot, --log,
## --lat=MS, --loss=PCT for fake lag.

var field := Field.new()
var camera := ChaseCamera.new()
var session := NetSession.new()
var brain: BotBrain = null
var hud := Label.new()
var menu := VBoxContainer.new()
var ip_edit := LineEdit.new()
var status := Label.new()
var args := {}


func _ready() -> void:
	InputSetup.register()
	_parse_args()
	_build_world()
	_build_ui()

	session.athlete_parent = self
	session.input_provider = _provide_input
	session.local_ready.connect(func(a: Athlete): camera.target = a)
	session.disconnected.connect(_on_disconnected)
	session.log_enabled = args.has("log")
	session.name = "NetSession"
	add_child(session)

	if args.has("bot"):
		brain = BotBrain.new()
	if args.has("lat"):
		Tuning.data["net"]["sim_latency_ms"] = float(args["lat"])
	if args.has("loss"):
		Tuning.data["net"]["sim_loss_pct"] = float(args["loss"])

	if args.has("host"):
		_host()
	elif args.has("join"):
		_join(String(args["join"]))


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var kv := s.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true


func _port() -> int:
	return int(args.get("port", Tuning.section("net")["port"]))


func _host() -> void:
	var err := session.start_host(_port())
	if err != OK:
		status.text = "Host failed: %s" % error_string(err)
		return
	menu.hide()


func _join(ip: String) -> void:
	var err := session.start_client(ip, _port())
	if err != OK:
		status.text = "Join failed: %s" % error_string(err)
		return
	status.text = "Connecting to %s..." % ip
	menu.hide()


func _on_disconnected() -> void:
	status.text = "Disconnected."
	menu.show()
	camera.target = null
	if args.has("bot"):
		get_tree().quit()


func _provide_input() -> Array:
	if brain:
		var dt := 1.0 / float(Tuning.section("net")["tick_hz"])
		return brain.think(session.local_state().pos, dt, Tuning.section("field"))
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return [camera.world_move(stick), Input.is_action_pressed("sprint")]


func _build_world() -> void:
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

	add_child(camera)
	camera.cam.current = true


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 18)
	layer.add_child(hud)

	menu.position = Vector2(12, 150)
	menu.custom_minimum_size = Vector2(260, 0)
	var host_btn := Button.new()
	host_btn.text = "Host"
	host_btn.pressed.connect(_host)
	ip_edit.text = "127.0.0.1"
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(func(): _join(ip_edit.text))
	for c in [host_btn, ip_edit, join_btn, status]:
		menu.add_child(c)
	layer.add_child(menu)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reload_tuning"):
		Tuning.reload()


func _process(_delta: float) -> void:
	var s := session.local_state()
	var n := Tuning.section("net")
	var role := "offline"
	if session.mode == NetSession.Mode.HOST:
		role = "HOST"
	elif session.mode == NetSession.Mode.CLIENT:
		role = "CLIENT rtt %d ms, correction %.2f m" % [int(session.rtt * 1000.0), session.last_correction]
	hud.text = "%s   players %d   tick %d Hz   fake lag %d ms / loss %d%%\nspeed %.1f m/s   stamina %d%%   cut %s\nWASD/left stick move, Shift/RT sprint, mouse/right stick look, F5 reload tuning" % [
		role, session.athletes.size(), int(n["tick_hz"]), int(n["sim_latency_ms"]), int(n["sim_loss_pct"]),
		s.speed, int(s.stamina * 100.0), "plant" if s.cut_timer > 0.0 else "-"]
