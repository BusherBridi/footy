class_name InputSetup
extends RefCounted
## Registers keyboard, mouse and controller actions from res://controls.json, so a
## layout can be tried without touching code. F5 reloads it along with the tuning.

const PATH := "res://controls.json"

const _MOUSE := {"MouseLeft": MOUSE_BUTTON_LEFT, "MouseRight": MOUSE_BUTTON_RIGHT, "MouseMiddle": MOUSE_BUTTON_MIDDLE,
	"Mouse4": MOUSE_BUTTON_XBUTTON1, "Mouse5": MOUSE_BUTTON_XBUTTON2,
	"WheelUp": MOUSE_BUTTON_WHEEL_UP, "WheelDown": MOUSE_BUTTON_WHEEL_DOWN}
const _PAD := {"A": JOY_BUTTON_A, "B": JOY_BUTTON_B, "X": JOY_BUTTON_X, "Y": JOY_BUTTON_Y,
	"LB": JOY_BUTTON_LEFT_SHOULDER, "RB": JOY_BUTTON_RIGHT_SHOULDER, "L3": JOY_BUTTON_LEFT_STICK,
	"R3": JOY_BUTTON_RIGHT_STICK, "Back": JOY_BUTTON_BACK, "Start": JOY_BUTTON_START,
	"DpadUp": JOY_BUTTON_DPAD_UP, "DpadDown": JOY_BUTTON_DPAD_DOWN, "DpadLeft": JOY_BUTTON_DPAD_LEFT,
	"DpadRight": JOY_BUTTON_DPAD_RIGHT}
const _AXES := {"LeftX": JOY_AXIS_LEFT_X, "LeftY": JOY_AXIS_LEFT_Y, "RightX": JOY_AXIS_RIGHT_X,
	"RightY": JOY_AXIS_RIGHT_Y}

## action -> {"keys": [...], "pad": [...]} as written in the file (for the controls card).
static var bindings: Dictionary = {}


static func register() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("actions"):
		push_error("InputSetup: %s is missing or not valid JSON, keeping the old bindings" % PATH)
		return
	bindings = parsed["actions"]
	for action in bindings:
		var events: Array = []
		var b: Dictionary = bindings[action]
		for name in b.get("keys", []):
			var e := _parse_key(str(name))
			if e != null:
				events.append(e)
		for name in b.get("pad", []):
			var e := _parse_pad(str(name))
			if e != null:
				events.append(e)
		_action(action, events)


## "Shift+Q" -> Q with Shift held. Mouse buttons by name.
static func _parse_key(name: String) -> InputEvent:
	if _MOUSE.has(name):
		var m := InputEventMouseButton.new()
		m.button_index = _MOUSE[name]
		return m
	var parts := name.split("+")
	var code := OS.find_keycode_from_string(parts[parts.size() - 1])
	if code == KEY_NONE:
		push_error("InputSetup: unknown key '%s'" % name)
		return null
	var e := InputEventKey.new()
	e.physical_keycode = code
	for i in parts.size() - 1:
		match parts[i].to_lower():
			"shift": e.shift_pressed = true
			"ctrl": e.ctrl_pressed = true
			"alt": e.alt_pressed = true
	return e


static func _parse_pad(name: String) -> InputEvent:
	if _PAD.has(name):
		var b := InputEventJoypadButton.new()
		b.button_index = _PAD[name]
		return b
	if name == "LT" or name == "RT":
		var t := InputEventJoypadMotion.new()
		t.axis = JOY_AXIS_TRIGGER_LEFT if name == "LT" else JOY_AXIS_TRIGGER_RIGHT
		t.axis_value = 1.0
		return t
	var stick := name.substr(0, name.length() - 1)
	if _AXES.has(stick) and (name.ends_with("-") or name.ends_with("+")):
		var a := InputEventJoypadMotion.new()
		a.axis = _AXES[stick]
		a.axis_value = -1.0 if name.ends_with("-") else 1.0
		return a
	push_error("InputSetup: unknown controller input '%s'" % name)
	return null


## How a binding reads on the controls card.
static func pretty(name: String) -> String:
	const NAMES := {"MouseLeft": "Left click", "MouseRight": "Right click", "MouseMiddle": "Middle click",
		"LeftX-": "L stick", "LeftX+": "L stick", "LeftY-": "L stick", "LeftY+": "L stick",
		"DpadLeft": "D-pad left", "DpadRight": "D-pad right", "DpadUp": "D-pad up", "DpadDown": "D-pad down"}
	return NAMES.get(name, name)


## The bindings of one action, e.g. "E" and "B".
static func label(action: String, pad: bool) -> String:
	var names: Array = bindings.get(action, {}).get("pad" if pad else "keys", [])
	var out: Array[String] = []
	for n in names:
		var p := pretty(str(n))
		if not out.has(p):
			out.append(p)
	return " / ".join(out) if not out.is_empty() else "-"


static func _action(name: String, events: Array) -> void:
	if InputMap.has_action(name):
		InputMap.erase_action(name)
	InputMap.add_action(name, 0.2)
	for e in events:
		InputMap.action_add_event(name, e)
