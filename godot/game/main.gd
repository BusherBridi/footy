extends Node3D
## Entry point: builds the placeholder world, then hosts or joins a match.
## Command line (after `--`): --match (play vs bots), --autoplay (the AI plays your
## athlete too), --host (sandbox), --join=IP, --port=N, --bot, --log,
## --lat=MS, --loss=PCT for fake lag. Bots: --bot (wander), --route[=go|out|in|curl|post]
## (receiver), --qb (takes the ball and throws; combine with --bot or --route).

var field := Field.new()
var camera := ChaseCamera.new()
var session := NetSession.new()
var brain: BotBrain = null
var hud := Label.new()
var reticle := PowerReticle.new()
var menu := Control.new()
var hint := Label.new()
var show_debug := false
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
var play_view := PlayView.new()
var fx := Fx.new()
var match_hud := Label.new()
var _seen_play := -1
var _event_time := 0.0
var _take_latch := false
var _try_pick := 0
var _spin_latch := false
var _stiff_side := 0             # -1 / +1: a stiff arm on that side is waiting to be sent
var _pop_side := 0               # -1 / +1: mid-spin, pop out that way
var _hand_first := 0             # chord detection: 1 = first hand button down, 2 = second, 0 = none
var _hand_timer := 0.0
var card := PanelContainer.new()
var _card_grid := GridContainer.new()
var _pad_mode := false           # the last input came from a controller (labels show pad buttons)


func _ready() -> void:
	InputSetup.register()
	_parse_args()
	_build_world()
	_build_ui()

	session.athlete_parent = self
	session.input_provider = _provide_input
	session.local_ready.connect(func(a: Athlete): camera.target = a)
	session.disconnected.connect(_on_disconnected)
	session.fx_event.connect(_on_fx)
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

	session.autopilot = args.has("autoplay")
	if args.has("match"):
		_host_match()
	elif args.has("host"):
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


## Hits shake the camera and pause the picture for a beat, more the closer you are.
func _on_fx(kind: String, pos: Vector3, strength: float) -> void:
	var f := Tuning.section("fx")
	if not f.get("enabled", true):
		return
	fx.spawn(kind, pos, strength)
	var near := 1.0
	if camera.target:
		near = clampf(1.0 - camera.target.position.distance_to(pos) / float(f["radius_m"]), 0.0, 1.0)
	if near <= 0.0:
		return
	match kind:
		"bighit":
			camera.add_shake(float(f["shake_bighit"]) * near)
			camera.add_fov_kick(float(f["fov_kick_deg"]) * near)
			session.freeze_visuals(float(f["hitstop_bighit"]))
		"hit", "fumble":
			camera.add_shake(float(f["shake_hit"]) * strength * near)
			session.freeze_visuals(float(f["hitstop_hit"]) * near)
		"touchdown":
			camera.add_shake(0.3)


func _host_match() -> void:
	_host()
	if session.mode == NetSession.Mode.HOST:
		session.start_match()


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
	var aiming := Input.is_action_pressed("aim") and session.local_can_pass()
	var take := _take_latch
	_take_latch = false
	var try_pick := _try_pick
	_try_pick = 0
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
	var spin := _spin_latch
	_spin_latch = false
	var side := _stiff_side
	_stiff_side = 0
	var pop := _pop_side
	_pop_side = 0
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
		"try_pick": try_pick,
		"tackle": tackle,
		"dive": dive,
		"truck": truck,
		"strip": strip,
		"lateral": lateral,
		"hurdle": hurdle,
		"spin": spin,
		"side": side,
		"spin_side": pop,
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
	add_child(play_view)
	add_child(fx)


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
	match_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	match_hud.position = Vector2(-500, 8)
	match_hud.custom_minimum_size = Vector2(1000, 0)
	match_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_hud.add_theme_font_size_override("font_size", 24)
	layer.add_child(match_hud)
	event_label.position.y = 120
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 18)
	hud.visible = false
	layer.add_child(hud)
	hint.text = "F1 / Start: controls   F3: debug   F11: fullscreen   Esc: free the mouse"
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(1, 1, 1, 0.7)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(16, -36)
	layer.add_child(hint)
	for l in [match_hud, event_label, hint, hud]:
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_build_menu(layer)
	_build_card(layer)


## Title screen: centred panel over the field, big buttons.
func _build_menu(layer: CanvasLayer) -> void:
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(menu)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.06, 0.1, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.18, 0.9)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	var title := Label.new()
	title.text = "FOOTY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "5v5 arcade football"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	sub.modulate = Color(1, 1, 1, 0.75)
	box.add_child(sub)
	box.add_child(_spacer(12))

	box.add_child(_menu_button("Play vs bots", _host_match))
	box.add_child(_menu_button("Host sandbox", _host))
	box.add_child(_spacer(8))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "Host IP"
	ip_edit.custom_minimum_size = Vector2(300, 64)
	ip_edit.add_theme_font_size_override("font_size", 26)
	join_row.add_child(ip_edit)
	var join_btn := _menu_button("Join", func(): _join(ip_edit.text))
	join_btn.custom_minimum_size = Vector2(160, 64)
	join_row.add_child(join_btn)
	box.add_child(join_row)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 20)
	box.add_child(status)


func _menu_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(472, 68)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(action)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5)
	var kbm := event is InputEventKey or event is InputEventMouseButton
	if (pad or kbm) and pad != _pad_mode:
		_pad_mode = pad


## Controls card (F1 / Start): every move with its keyboard-and-mouse and controller
## buttons, read from controls.json so it never goes stale.
func _build_card(layer: CanvasLayer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(28)
	card.add_theme_stylebox_override("panel", style)
	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(wrap)
	card.visible = false
	wrap.add_child(card)
	_card_grid.columns = 3
	_card_grid.add_theme_constant_override("h_separation", 40)
	_card_grid.add_theme_constant_override("v_separation", 4)
	card.add_child(_card_grid)
	_fill_card()


func _fill_card() -> void:
	for c in _card_grid.get_children():
		c.queue_free()
	var L := func(a: String, pad: bool) -> String: return InputSetup.label(a, pad)
	var both := func(a: String, b: String, pad: bool) -> String: return "%s + %s" % [L.call(a, pad), L.call(b, pad)]
	var rows: Array = [
		["CONTROLS", "Keyboard & mouse", "Controller"],
		["Move / look", "WASD / mouse", "Left stick / right stick"],
		["Sprint (hold)", L.call("sprint", false), L.call("sprint_trigger", true)],
		["WITH THE BALL"],
		["Stiff arm, left side", L.call("stiff_left", false), L.call("stiff_left", true)],
		["Stiff arm, right side", L.call("stiff_right", false), L.call("stiff_right", true)],
		["Truck", both.call("stiff_left", "stiff_right", false), both.call("stiff_left", "stiff_right", true)],
		["Spin (then a hand button = pop that side)", L.call("spin", false), L.call("spin", true)],
		["Hurdle", L.call("hurdle", false), L.call("hurdle", true)],
		["Lateral (where the camera points)", L.call("lateral", false), L.call("lateral", true)],
		["QB (one forward pass, from behind the line)"],
		["Snap", L.call("snap", false), L.call("snap", true)],
		["Aim (look up / down = angle)", L.call("aim", false), L.call("aim", true)],
		["Power: hold, release to throw", L.call("throw", false), L.call("throw", true)],
		["Cancel the throw", "let go of aim first", "let go of aim first"],
		["DEFENSE"],
		["Tackle (again: let go of a hold)", L.call("tackle", false), L.call("tackle", true)],
		["Strip (join a wrap)", L.call("strip", false), L.call("strip", true)],
		["Dive", both.call("tackle", "strip", false), both.call("tackle", "strip", true)],
		["OTHER"],
		["Pick the 1 / 2-point try", "%s / %s" % [L.call("try_one", false), L.call("try_two", false)], "%s / %s" % [L.call("try_one", true), L.call("try_two", true)]],
		["Camera style", L.call("cycle_camera", false), L.call("cycle_camera", true)],
		["Bullet / lob (old throw mode)", L.call("lob_toggle", false), L.call("lob_toggle", true)],
		["Old throw mode / debug / reload / fullscreen", "F2 / F3 / F5 / F11", "-"],
		["This card", L.call("controls_card", false), L.call("controls_card", true)],
	]
	for r in rows:
		var header: bool = r.size() == 1 or r[0] == "CONTROLS"
		for i in 3:
			var l := Label.new()
			l.text = r[i] if i < r.size() else ""
			l.add_theme_font_size_override("font_size", 26 if r[0] == "CONTROLS" else 19)
			if header:
				l.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
			if header and r.size() == 1 and i == 0:
				l.custom_minimum_size.y = 34
				l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			_card_grid.add_child(l)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The two hand buttons. With the ball: left / right stiff arm, both together truck, and
## mid-spin either one picks the pop side. Without: tackle / strip, both together dive.
## A QB who can still pass keeps them for aim and throw while aiming.
func _hands(delta: float) -> void:
	var carrier := session.local_has_ball()
	if carrier and session.local_can_pass() and Input.is_action_pressed("aim"):
		_hand_first = 0
		return
	var a := Input.is_action_just_pressed("stiff_left" if carrier else "tackle")
	var b := Input.is_action_just_pressed("stiff_right" if carrier else "strip")
	if carrier and session.local_state().status == AthleteState.Status.SPIN:
		if a or b:
			_pop_side = -1 if a else 1
		_hand_first = 0
		return
	var window := float(Tuning.section("input").get("chord_window_s", 0.0))
	var both := (a and b) or (_hand_first == 1 and b) or (_hand_first == 2 and a)
	var single := 0
	if both:
		_hand_first = 0
	elif _hand_first != 0:
		_hand_timer -= delta
		if _hand_timer <= 0.0:
			single = _hand_first
			_hand_first = 0
	elif a or b:
		_hand_first = 1 if a else 2
		_hand_timer = window
		if window <= 0.0:
			single = _hand_first
			_hand_first = 0
	if both:
		if carrier:
			_truck_latch = true
		else:
			_dive_latch = true
	elif single != 0:
		if carrier:
			_tackle_latch = true          # with the ball the tackle press is the stiff arm
			_stiff_side = -1 if single == 1 else 1
		elif single == 1:
			_tackle_latch = true
		else:
			_strip_latch = true


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reload_tuning"):
		Tuning.reload()
		InputSetup.register()
		_fill_card()
	if Input.is_action_just_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if Input.is_action_just_pressed("debug_hud"):
		show_debug = not show_debug
	if Input.is_action_just_pressed("controls_card"):
		card.visible = not card.visible
	_hands(_delta)
	if Input.is_action_just_pressed("lateral"):
		_lateral_latch = true
	if Input.is_action_just_pressed("hurdle"):
		_hurdle_latch = true
	if Input.is_action_just_pressed("spin"):
		_spin_latch = true
	if Input.is_action_just_pressed("snap") and not session.local_has_ball():
		_take_latch = true
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
	if Input.is_action_just_pressed("try_one"):
		_try_pick = 1
	if Input.is_action_just_pressed("try_two"):
		_try_pick = 2
	if Input.is_action_just_pressed("cycle_camera"):
		camera.cycle_style()


func _process(delta: float) -> void:
	_event_time -= delta
	event_label.visible = _event_time > 0.0
	_update_match_view()
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
	hud.visible = show_debug and not menu.visible
	hint.visible = not menu.visible
	hud.add_theme_font_size_override("font_size", 16)
	hud.position.y = 48
	hud.text = bot_tag + "%s   players %d   tick %d Hz   fake lag %d ms / loss %d%%\nspeed %.1f m/s   stamina %d%%   cut %s   status %s\nball: %s   pass: %s   throw mode: %s   power %d%%   camera: %s\nF1 controls card.  Sandbox host only: B add receiver bot, N add chaser bot, V remove bots, R take the ball" % [
		role, session.athletes.size(), int(n["tick_hz"]), int(n["sim_latency_ms"]), int(n["sim_loss_pct"]),
		s.speed, int(s.stamina * 100.0), "plant" if s.cut_timer > 0.0 else "-", ["ok", "STUMBLE", "DOWN", "DIVE", "SPIN", "TRUCK", "HURDLE", "POP", "WRAPPED", "HOLDING", "SET"][int(s.status)],
		["loose", "held", "in flight"][int(session.view_ball.get("kind", 0))], "n/a (angle decides)" if throw_mode == NetSession.ThrowMode.AIM else ("LOB" if lob else "BULLET"),
		"ANGLE+POWER (look = angle, hold = power)" if throw_mode == NetSession.ThrowMode.AIM else "HOLD (charge = distance)",
		int(session.throw_charge * 100.0), camera.profile_name()]


## Match HUD line, field markings, and turning the camera around for each new play.
func _update_match_view() -> void:
	var v := session.get_play_view()
	var f := Tuning.section("field")
	var width: float = float(f["width_yards"]) * float(f["yard_m"])
	var qb_pos: Variant = null
	if not v.is_empty() and session.athletes.has(int(v["qb"])):
		qb_pos = session.athletes[int(v["qb"])].position
	play_view.update_view(v, width, float(Tuning.section("match")["rush_time"]), qb_pos)
	if v.is_empty():
		match_hud.text = ""
		return
	var my_team := session.local_team()
	var on_offense := my_team == int(v["offense"])
	if int(v["play_no"]) != _seen_play and int(v["phase"]) == PlayFlow.Phase.PRE_SNAP:
		_seen_play = int(v["play_no"])
		# Face the way your athlete is lined up (downfield on offense, at the offense on defense).
		var h := session.local_state().heading
		camera.yaw = atan2(-h.x, -h.y)
	var team_name: String = NetSession.TEAM_NAMES[my_team] if my_team >= 0 else "?"
	var role := ""
	if on_offense:
		role = "OFFENSE (you're the QB)" if int(v["qb"]) == session.local_id else "OFFENSE"
	else:
		role = "DEFENSE (you're the linebacker)"
	var phase_text := ""
	var my_try := int(v["try"]) > 0 and int(v["qb"]) == session.local_id
	match int(v["phase"]):
		PlayFlow.Phase.PRE_SNAP:
			phase_text = ("Press %s to snap" % InputSetup.label("snap", _pad_mode)) if int(v["qb"]) == session.local_id else "Waiting for the snap"
			if my_try:
				phase_text += "  (%s / %s: pick the 1- or 2-point try)" % [InputSetup.label("try_one", _pad_mode), InputSetup.label("try_two", _pad_mode)]
		PlayFlow.Phase.LIVE:
			var rush := float(v["rush"])
			phase_text = ("Rush in %.1f" % rush) if rush > 0.0 else "LIVE"
		PlayFlow.Phase.DEAD:
			phase_text = "Play over"
	match_hud.text = "ORANGE %d  -  %d BLUE\n%s %s  |  ball on the %s\n%s %s  |  %s" % [
		int(v["score0"]), int(v["score1"]), NetSession.TEAM_NAMES[int(v["offense"])].to_upper(),
		_down_text(v), _spot_text(float(v["los"]), int(v["dir"])), team_name, role, phase_text]


## "2nd & 7 to midfield", "3rd & goal", "2-point try": from the play numbers alone.
func _down_text(v: Dictionary) -> String:
	if int(v["try"]) > 0:
		return "%d-point try" % int(v["try"])
	var f := Tuning.section("field")
	var yard: float = f["yard_m"]
	var half := float(f["length_yards"]) * 0.5 * yard
	var nth: String = ["", "1st", "2nd", "3rd", "4th"][clampi(int(v["down"]), 1, 4)]
	if is_equal_approx(float(v["gain"]), float(v["dir"]) * half):
		return "%s & goal" % nth
	return "%s & %d to midfield" % [nth, maxi(1, roundi(absf(float(v["gain"]) - float(v["los"])) / yard))]


func _spot_text(z: float, d: int) -> String:
	var f := Tuning.section("field")
	var yard: float = f["yard_m"]
	var length := float(f["length_yards"])
	var y := roundi((z + d * length * 0.5 * yard) * d / yard)
	var mid := roundi(length * 0.5)
	if y == mid:
		return "midfield"
	return "own %d" % y if y < mid else "opponent %d" % (2 * mid - y)
