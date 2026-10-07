extends Node3D
## Entry point: builds the placeholder world, then hosts or joins a match.
## Command line (after `--`): --host, --join=IP, --port=N, --bot, --log,
## --lat=MS, --loss=PCT for fake lag. Bots: --bot (wander), --route[=go|out|in|curl|post]
## (receiver), --qb (takes the ball and throws; combine with --bot or --route).

var field := Field.new()
var camera := ChaseCamera.new()
var session := NetSession.new()
var brain: BotBrain = null
var hud := Label.new()
var reticle := PowerReticle.new()
var menu := VBoxContainer.new()
var ip_edit := LineEdit.new()
var status := Label.new()
var args := {}
var lob := false
var throw_mode := NetSession.ThrowMode.AIM
var _throw_latch := false
var _tackle_latch := false
var _dive_latch := false
var _truck_latch := false
var _strip_latch := false
var _lateral_latch := false
var _hurdle_latch := false
var event_label := Label.new()
var _event_time := 0.0
var _take_latch := false


func _ready() -> void:
	InputSetup.register()
	_parse_args()
	_build_world()
	_build_ui()

	session.athlete_parent = self
	session.input_provider = _provide_input
	session.local_ready.connect(func(a: Athlete): camera.target = a)
	session.disconnected.connect(_on_disconnected)
	session.event_text.connect(func(t: String):
		event_label.text = t
		_event_time = 2.5)
	session.log_enabled = args.has("log")
	if args.has("log"):
		print("Footy started with args: ", OS.get_cmdline_user_args(), "  log file: ", ProjectSettings.globalize_path("user://footy_log.txt"))
	session.name = "NetSession"
	add_child(session)

	if args.has("bot") or args.has("route") or args.has("qb"):
		brain = BotBrain.new()
		brain.is_qb = args.has("qb")
		brain.aim_mode = args.has("aimmode")
		if args.has("lateral"):
			brain.lateral_chance = 0.5
		if args.has("route"):
			brain.route_name = "" if args["route"] is bool else String(args["route"])
			if brain.route_name == "":
				brain.route_name = "random"
	if args.has("lat"):
		Tuning.data["net"]["sim_latency_ms"] = float(args["lat"])
	if args.has("loss"):
		Tuning.data["net"]["sim_loss_pct"] = float(args["loss"])

	if args.has("host"):
		_host()
		for i in int(args.get("bots", 0)):
			session.host_add_bot()
		for i in int(args.get("chasers", 0)):
			session.host_add_bot("chase")
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
	if brain:
		get_tree().quit()


func _provide_input() -> Dictionary:
	if brain:
		var dt := 1.0 / float(Tuning.section("net")["tick_hz"])
		return brain.think(session.local_state().pos, dt, Tuning.data, session.local_has_ball())
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var aiming := Input.is_action_pressed("aim")
	var take := _take_latch
	_take_latch = false
	var tap := _throw_latch
	_throw_latch = false
	var tackle := _tackle_latch
	_tackle_latch = false
	var dive := _dive_latch
	_dive_latch = false
	var truck := _truck_latch
	_truck_latch = false
	var strip := _strip_latch
	_strip_latch = false
	var lateral := _lateral_latch
	_lateral_latch = false
	var hurdle := _hurdle_latch
	_hurdle_latch = false
	return {
		"move": camera.world_move(stick),
		"sprint": Input.is_action_pressed("sprint") or (Input.is_action_pressed("sprint_trigger") and not aiming),
		"aiming": aiming,
		"throw": aiming and Input.is_action_pressed("throw"),
		"yaw": camera.yaw,
		"lob": lob,
		"mode": throw_mode,
		"pitch": camera.pitch,
		"throw_tap": tap and aiming,
		"take": take,
		"tackle": tackle,
		"dive": dive,
		"truck": truck,
		"strip": strip,
		"lateral": lateral,
		"hurdle": hurdle,
	}


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
	reticle.visible = false
	layer.add_child(reticle)
	event_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	event_label.position = Vector2(-300, 60)
	event_label.custom_minimum_size = Vector2(600, 0)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(event_label)
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
	if Input.is_action_just_pressed("tackle"):
		_tackle_latch = true
	if Input.is_action_just_pressed("lateral"):
		_lateral_latch = true
	if Input.is_action_just_pressed("strip"):
		_strip_latch = true
	if Input.is_action_just_pressed("truck"):
		_truck_latch = true
	if Input.is_action_just_pressed("hurdle"):
		_hurdle_latch = true
	if Input.is_action_just_pressed("dive"):
		_dive_latch = true
	if Input.is_action_just_pressed("add_chaser"):
		session.host_add_bot("chase")
	if Input.is_action_just_pressed("add_bot"):
		session.host_add_bot()
	if Input.is_action_just_pressed("clear_bots"):
		session.host_clear_bots()
	if Input.is_action_just_pressed("throw_mode"):
		throw_mode = NetSession.ThrowMode.HOLD if throw_mode == NetSession.ThrowMode.AIM else NetSession.ThrowMode.AIM
	if Input.is_action_just_pressed("throw"):
		_throw_latch = true
	if Input.is_action_just_pressed("lob_toggle"):
		lob = not lob
	if Input.is_action_just_pressed("take_ball"):
		_take_latch = true
	if Input.is_action_just_pressed("cycle_camera"):
		camera.cycle_style()


func _process(delta: float) -> void:
	_event_time -= delta
	event_label.visible = _event_time > 0.0
	camera.set_qb(session.local_has_ball())
	camera.set_aiming(session.aim_active)
	reticle.visible = session.aim_active
	reticle.power = session.throw_charge
	reticle.show_hint = session.throw_charging
	reticle.angle_deg = rad_to_deg(session.aim_angle) if session.aim_angle >= 0.0 else rad_to_deg(camera.pitch)
	var s := session.local_state()
	var n := Tuning.section("net")
	var role := "offline"
	if session.mode == NetSession.Mode.HOST:
		role = "HOST"
	elif session.mode == NetSession.Mode.CLIENT:
		role = "CLIENT rtt %d ms, correction %.2f m" % [int(session.rtt * 1000.0), session.last_correction]
	var bot_tag := ""
	if brain:
		bot_tag = "[BOT %s%s]  " % ["route=" + brain.route_name if brain.route_name != "" else "wander", " + QB" if brain.is_qb else ""]
	hud.text = bot_tag + "%s   players %d   tick %d Hz   fake lag %d ms / loss %d%%\nspeed %.1f m/s   stamina %d%%   cut %s   status %s\nball: %s   pass: %s   throw mode: %s   power %d%%   camera: %s\nWASD/left stick move, Shift/RT sprint, mouse/right stick look, F5 reload tuning\nHost only: B add receiver bot, N add chaser bot, V remove bots\nDefence: F/X tackle, G/B dive, R/Y strip (help a wrap).  Z/LB lateral: pitch it backward or sideways, in the camera direction.  With the ball: F/X stiff arm, G/B spin (hold left/right to pop out that way), T/Y truck, Space/A hurdle\nE take ball (temp snap), hold RMB/LT aim, look up/down = angle, hold LMB/RT = power, release to throw (let go of aim first to cancel), C camera, F2 throw mode, Q/RB bullet-lob (hold mode only)" % [
		role, session.athletes.size(), int(n["tick_hz"]), int(n["sim_latency_ms"]), int(n["sim_loss_pct"]),
		s.speed, int(s.stamina * 100.0), "plant" if s.cut_timer > 0.0 else "-", ["ok", "STUMBLE", "DOWN", "DIVE", "SPIN", "TRUCK", "HURDLE", "POP", "WRAPPED", "HOLDING"][int(s.status)],
		["loose", "held", "in flight"][int(session.view_ball.get("kind", 0))], "n/a (angle decides)" if throw_mode == NetSession.ThrowMode.AIM else ("LOB" if lob else "BULLET"),
		"ANGLE+POWER (look = angle, hold = power)" if throw_mode == NetSession.ThrowMode.AIM else "HOLD (charge = distance)",
		int(session.throw_charge * 100.0), camera.profile_name()]
