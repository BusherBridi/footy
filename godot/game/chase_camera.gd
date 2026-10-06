class_name ChaseCamera
extends Node3D
## Simple third-person camera orbiting behind the target. Mouse or right stick
## aims it; movement is camera-relative.

var yaw := 0.0
var pitch := 0.0
var target: Node3D
var cam := Camera3D.new()
var _pivot := Vector3.ZERO


func _ready() -> void:
	add_child(cam)
	pitch = deg_to_rad(Tuning.section("camera").get("pitch_deg", -18.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var c := Tuning.section("camera")
		yaw -= event.relative.x * c["mouse_sensitivity"]
		pitch -= event.relative.y * c["mouse_sensitivity"]
		_clamp_pitch(c)


func _process(delta: float) -> void:
	var c := Tuning.section("camera")
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var rate := deg_to_rad(c["stick_sensitivity_deg"]) * delta
	yaw -= look.x * rate
	pitch -= look.y * rate
	_clamp_pitch(c)

	if target:
		var goal := target.position + Vector3(0, c["height"], 0)
		_pivot = _pivot.lerp(goal, 1.0 - exp(-float(c["follow_smoothing"]) * delta))
	position = _pivot
	rotation = Vector3(pitch, yaw, 0)
	cam.position = Vector3(0, 0, c["distance"])


func _clamp_pitch(c: Dictionary) -> void:
	pitch = clampf(pitch, deg_to_rad(c["pitch_min_deg"]), deg_to_rad(c["pitch_max_deg"]))


## Camera-relative stick input -> world-plane direction (x, z).
func world_move(stick: Vector2) -> Vector2:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	return right * stick.x + fwd * -stick.y
