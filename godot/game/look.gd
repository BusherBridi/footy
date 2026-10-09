class_name Look
extends CanvasLayer
## The look lab: a full-screen retro pass over the 3D view, switchable between the looks in
## tuning.json ("look" section). The HUD sits on a higher layer, so it stays sharp.

var rect := ColorRect.new()
var mat := ShaderMaterial.new()
var current := ""


func _ready() -> void:
	layer = 0
	mat.shader = load("res://shaders/retro.gdshader")
	rect.material = mat
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	get_viewport().size_changed.connect(func(): apply(current))
	Tuning.reloaded.connect(func(): apply(current))


func names() -> Array:
	return Tuning.section("look").get("looks", {}).keys()


func label(look_name: String) -> String:
	return str(Tuning.section("look").get("looks", {}).get(look_name, {}).get("label", look_name))


func apply(look_name: String) -> void:
	var looks: Dictionary = Tuning.section("look").get("looks", {})
	if not looks.has(look_name):
		look_name = str(Tuning.section("look").get("default", "baseline"))
	current = look_name
	var l: Dictionary = looks.get(look_name, {})
	var res := float(l.get("res_height", 0.0))
	var h := get_viewport().get_visible_rect().size.y
	var px := maxf(1.0, roundf(h / res)) if res > 0.0 else 1.0
	# Nothing to do at full resolution with no grade: skip the pass entirely.
	rect.visible = px > 1.0 or float(l.get("levels", 0.0)) > 1.5 or float(l.get("saturation", 1.0)) != 1.0 \
		or float(l.get("contrast", 1.0)) != 1.0
	mat.set_shader_parameter("pixel_size", px)
	mat.set_shader_parameter("levels", float(l.get("levels", 0.0)))
	mat.set_shader_parameter("dither", float(l.get("dither", 0.0)))
	mat.set_shader_parameter("saturation", float(l.get("saturation", 1.0)))
	mat.set_shader_parameter("contrast", float(l.get("contrast", 1.0)))
	mat.set_shader_parameter("brightness", float(l.get("brightness", 0.0)))
	var t: Array = l.get("tint", [1.0, 1.0, 1.0])
	mat.set_shader_parameter("tint", Vector3(t[0], t[1], t[2]))


func cycle() -> String:
	var n := names()
	if n.is_empty():
		return ""
	apply(n[(n.find(current) + 1) % n.size()])
	return current
