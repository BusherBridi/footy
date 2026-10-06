class_name ChaseCamera
extends Node3D
## Third-person camera orbiting behind the target. Mouse or right stick aims it;
## movement is camera-relative. While you hold the ball it switches to one of
## two QB profiles (toggle with C) so they can be compared in playtests.

const QB_PROFILES := ["qb_shoulder", "qb_high"]

var yaw := 0.0
var pitch := 0.0
var target: Node3D
var cam := Camera3D.new()
var qb := false
var qb_style := 0
var _pivot := Vector3.ZERO
var _dist := 7.0
var _height := 2.2
var _shoulder := 0.0


func _ready() -> void:
	add_child(cam)
	pitch = deg_to_rad(Tuning.section("camera").get("pitch_deg", -18.0))


func profile_name() -> String:
	return QB_PROFILES[qb_style] if qb else "chase"


func _profile() -> Dictionary:
	var c := Tuning.section("camera")
	if qb:
		return c[QB_PROFILES[qb_style]]
	return {"distance": c["distance"], "height": c["height"], "pitch_deg": c["pitch_deg"], "shoulder": 0.0}


func set_qb(on: bool) -> void:
	if on != qb:
		qb = on
		pitch = deg_to_rad(_profile()["pitch_deg"])


func cycle_style() -> void:
	qb_style = (qb_style + 1) % QB_PROFILES.size()
	if qb:
		pitch = deg_to_rad(_profile()["pitch_deg"])


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

	var prof := _profile()
	var k := 1.0 - exp(-float(c["profile_smoothing"]) * delta)
	_dist = lerpf(_dist, prof["distance"], k)
	_height = lerpf(_height, prof["height"], k)
	_shoulder = lerpf(_shoulder, prof["shoulder"], k)

	if target:
		var goal := target.position + Vector3(0, _height, 0)
		_pivot = _pivot.lerp(goal, 1.0 - exp(-float(c["follow_smoothing"]) * delta))
	position = _pivot
	rotation = Vector3(pitch, yaw, 0)
	cam.position = Vector3(_shoulder, 0, _dist)


func _clamp_pitch(c: Dictionary) -> void:
	pitch = clampf(pitch, deg_to_rad(c["pitch_min_deg"]), deg_to_rad(c["pitch_max_deg"]))


## Camera-relative stick input -> world-plane direction (x, z).
func world_move(stick: Vector2) -> Vector2:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	return right * stick.x + fwd * -stick.y
