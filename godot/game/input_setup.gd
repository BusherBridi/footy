class_name InputSetup
extends RefCounted
## Registers keyboard + controller actions in code so both work from day one.


static func register() -> void:
	_action("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("move_forward", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action("move_back", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action("sprint", [_key(KEY_SHIFT)])
	_action("sprint_trigger", [_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	# QB: aim with RMB/LT, throw with LMB/RT while aiming (RT only sprints when not aiming).
	_action("aim", [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_action("throw", [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("throw_mode", [_key(KEY_F2)])
	_action("lob_toggle", [_key(KEY_Q), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_action("take_ball", [_key(KEY_E), _button(JOY_BUTTON_BACK)])   # temporary stand-in for the snap
	_action("cycle_camera", [_key(KEY_C), _button(JOY_BUTTON_LEFT_STICK)])
	_action("look_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_action("look_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_action("look_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_action("look_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_action("add_bot", [_key(KEY_B)])      # host only: dev test bot
	_action("clear_bots", [_key(KEY_V)])
	_action("reload_tuning", [_key(KEY_F5)])


static func _action(name: String, events: Array) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name, 0.2)
	for e in events:
		InputMap.action_add_event(name, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


static func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e
