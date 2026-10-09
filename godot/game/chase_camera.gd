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
var sens_mult := 1.0            # player setting (pause menu), on top of the tuning value
var aiming := false
var _pivot := Vector3.ZERO
var _dist := 7.0
var _height := 2.2
var _shoulder := 0.0
var _trauma := 0.0
var _fov_kick := 0.0
var _base_fov := 75.0
var _shake_t := 0.0


func _ready() -> void:
	add_child(cam)
	_base_fov = cam.fov
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


## While aiming, the camera may tilt much further up (a long throw hides the field).
## Hit feedback: shake grows with the square of trauma, so small hits stay subtle.
func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func add_fov_kick(deg: float) -> void:
	_fov_kick = maxf(_fov_kick, deg)


func set_aiming(on: bool) -> void:
	if on != aiming:
		aiming = on
		if not on and qb:
			pitch = deg_to_rad(_profile()["pitch_deg"])


func cycle_style() -> void:
	qb_style = (qb_style + 1) % QB_PROFILES.size()
	if qb:
		pitch = deg_to_rad(_profile()["pitch_deg"])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var c := Tuning.section("camera")
		yaw -= event.relative.x * c["mouse_sensitivity"] * sens_mult
		pitch -= event.relative.y * c["mouse_sensitivity"] * sens_mult
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
	else:
		# Nothing to follow (title screen): slowly circle high above the field.
		yaw += delta * 0.05
		pitch = deg_to_rad(-28.0)
		_pivot = Vector3(0, 4.0, 0)
		_dist = 38.0
		_shoulder = 0.0
	position = _pivot
	rotation = Vector3(pitch, yaw, 0)
	cam.position = Vector3(_shoulder, 0, _dist)
	var fx := Tuning.section("fx")
	_shake_t += delta
	_trauma = maxf(0.0, _trauma - float(fx.get("shake_decay", 1.8)) * delta)
	var s := _trauma * _trauma
	var off := float(fx.get("shake_max_offset", 0.35)) * s
	cam.position += Vector3(sin(_shake_t * 61.0), sin(_shake_t * 47.0 + 1.3), 0.0) * off
	cam.rotation.z = deg_to_rad(float(fx.get("shake_max_roll_deg", 2.5))) * s * sin(_shake_t * 39.0)
	_fov_kick = maxf(0.0, _fov_kick - float(fx.get("fov_kick_decay", 6.0)) * _fov_kick * delta)
	cam.fov = _base_fov + _fov_kick


func _clamp_pitch(c: Dictionary) -> void:
	var hi: float = Tuning.section("throw")["aim_pitch_limit_deg"] if aiming else c["pitch_max_deg"]
	pitch = clampf(pitch, deg_to_rad(c["pitch_min_deg"]), deg_to_rad(hi))


## Camera-relative stick input -> world-plane direction (x, z).
func world_move(stick: Vector2) -> Vector2:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	return right * stick.x + fwd * -stick.y
