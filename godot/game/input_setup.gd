class_name InputSetup
extends RefCounted
## Registers keyboard + controller actions in code so both work from day one.


static func register() -> void:
	_action("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("move_forward", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action("move_back", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action("sprint", [_key(KEY_SHIFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("look_left", [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_action("look_right", [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_action("look_up", [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_action("look_down", [_axis(JOY_AXIS_RIGHT_Y, 1.0)])
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
