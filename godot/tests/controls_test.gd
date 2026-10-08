extends Node
## Bindings from controls.json and the hand buttons (chord, context). Run headless:
##   godot --headless --path godot res://tests/controls_test.tscn
var m: Node
const DT := 1.0 / 60.0


func _ready():
	m = load("res://game/main.tscn").instantiate()
	add_child(m)
	m.set_physics_process(false)      # we drive _hands() by hand
	m._host()
	m.session.set_process(false)
	m.session.set_physics_process(false)
	print("%-52s %s" % ["case", "result"])
	print("%-52s %s" % ["Shift+Q needs Shift", str(InputMap.action_get_events("lob_toggle")[0].shift_pressed)])
	print("%-52s %s" % ["left click is stiff_left, tackle and throw", "%s %s %s" % [_has("stiff_left"), _has("tackle"), _has("throw")]])
	print("%-52s %s" % ["card labels", "truck = %s / %s" % [InputSetup.label("stiff_left", false) + " + " + InputSetup.label("stiff_right", false), InputSetup.label("stiff_left", true) + " + " + InputSetup.label("stiff_right", true)]])
	print()
	print("%-52s %s" % ["defender (no ball)", "what gets sent"])
	print("%-52s %s" % ["tackle", await _run(["tackle"], [])])
	print("%-52s %s" % ["strip", await _run(["strip"], [])])
	print("%-52s %s" % ["tackle, strip 2 frames later", await _run(["tackle"], ["strip"])])
	m.session._sv_take(1)
	print("%-52s %s" % ["carrier", ""])
	print("%-52s %s" % ["left hand", await _run(["stiff_left"], [])])
	print("%-52s %s" % ["right hand", await _run(["stiff_right"], [])])
	print("%-52s %s" % ["both at once", await _run(["stiff_left", "stiff_right"], [])])
	Input.action_press("aim")
	print("%-52s %s" % ["passer holding aim: left click is the throw", await _run(["stiff_left"], [])])
	Input.action_release("aim")
	m.session.sv_players[1].state.status = AthleteState.Status.SPIN
	m.session.sv_players[1].state.status_timer = 1.0
	print("%-52s %s" % ["mid-spin: right hand picks the pop side", await _run(["stiff_right"], [])])
	m.session._host_tick(1.0 / 30.0)
	print("%-52s %s" % ["  server spin side", m.session.sv_players[1].state.spin_side])
	m.session.sv_players[1].state.status = AthleteState.Status.OK
	m.session.sv_players[1].counter_cd = 0.0
	await _run(["stiff_left"], [])
	m.session._host_tick(1.0 / 30.0)
	print("%-52s %s" % ["left stiff arm reaches the server", "stiff_side %d, timer %.2f" % [m.session.sv_players[1].stiff_side, m.session.sv_players[1].stiff_timer]])
	get_tree().quit()


func _has(action: String) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			return true
	return false


## Press `first` this frame, `second` three frames later, then step past the chord window.
## Real physics frames: "just pressed" only holds for the frame the press happened in.
func _run(first: Array, second: Array) -> String:
	_clear()
	await get_tree().physics_frame
	for a in first:
		Input.action_press(a)
	m._hands(DT)
	for a in first:
		Input.action_release(a)
	for i in 2:
		await get_tree().physics_frame
		m._hands(DT)
	await get_tree().physics_frame
	for a in second:
		Input.action_press(a)
	m._hands(DT)
	for a in second:
		Input.action_release(a)
	for i in 10:
		await get_tree().physics_frame
		m._hands(DT)
	return _latches()


func _clear() -> void:
	m._tackle_latch = false; m._strip_latch = false; m._dive_latch = false; m._truck_latch = false
	m._stiff_side = 0; m._pop_side = 0; m._hand_first = 0


func _latches() -> String:
	var out: Array[String] = []
	if m._tackle_latch: out.append("tackle" + ("" if m._stiff_side == 0 else (" side %d" % m._stiff_side)))
	if m._strip_latch: out.append("strip")
	if m._dive_latch: out.append("dive")
	if m._truck_latch: out.append("truck")
	if m._pop_side != 0: out.append("pop %d" % m._pop_side)
	return ",".join(out) if not out.is_empty() else "-"
