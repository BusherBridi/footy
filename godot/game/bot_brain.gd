class_name BotBrain
extends RefCounted
## Dev-only test driver. It feeds the normal input path, so a bot is just a
## client with no human. Modes:
##   wander  random walk with sprints and sharp turns
##   route   runs a receiver route from where it spawned, rests, jogs back, repeats
## With is_qb it also takes the ball and throws downfield now and then.

var is_qb := false
var aim_mode := false           # throw with the look-up aim + tap instead of hold-to-charge
var _pitch := 0.0
var route_name := ""            # empty = wander
var target := Vector2.ZERO
var timer := 0.0
var sprint := false
var rng := RandomNumberGenerator.new()

var _origin := Vector2.ZERO
var _have_origin := false
var _wp: Array = []             # absolute waypoints
var _wp_i := 0
var _rest := 0.0
var _returning := false

var _take_cd := 0.0
var _throw_wait := 2.0
var _phase := 0                 # 0 wait, 1 charging, 2 release
var _charge_left := 0.0
var _yaw := 0.0
var _lob := false


func _init() -> void:
	rng.randomize()


func think(pos: Vector2, dt: float, tuning: Dictionary, has_ball: bool) -> Dictionary:
	var out := {"move": Vector2.ZERO, "sprint": false}
	if route_name != "":
		_route(out, pos, dt, tuning)
	else:
		_wander(out, pos, dt, tuning["field"])
	if is_qb:
		_qb(out, dt, tuning, has_ball)
	return out


func _wander(out: Dictionary, pos: Vector2, dt: float, field: Dictionary) -> void:
	timer -= dt
	var to := target - pos
	if timer <= 0.0 or to.length() < 2.0:
		var yard: float = field["yard_m"]
		var hw: float = field["width_yards"] * 0.5 * yard - 2.0
		var hl: float = field["length_yards"] * 0.5 * yard - 2.0
		target = Vector2(rng.randf_range(-hw, hw), rng.randf_range(-hl, hl))
		timer = rng.randf_range(1.5, 4.0)
		sprint = rng.randf() < 0.5
		to = target - pos
	out["move"] = to.normalized()
	out["sprint"] = sprint and to.length() > 6.0


func _route(out: Dictionary, pos: Vector2, dt: float, tuning: Dictionary) -> void:
	if not _have_origin:
		_have_origin = true
		_origin = pos
		var yard: float = tuning["field"]["yard_m"]
		var routes: Dictionary = tuning["bot"]["routes_yards"]
		if not routes.has(route_name):
			route_name = routes.keys()[rng.randi() % routes.size()]
		_wp.clear()
		for p in routes[route_name]:
			_wp.append(_origin + Vector2(p[0], p[1]) * yard)
		_wp_i = 0
	if _rest > 0.0:
		_rest -= dt
		return
	var goal: Vector2 = _origin if _returning else _wp[_wp_i]
	var to := goal - pos
	if to.length() < 1.5:
		if _returning:
			_returning = false
			_wp_i = 0
			_rest = float(tuning["bot"]["route_rest_seconds"])
		elif _wp_i < _wp.size() - 1:
			_wp_i += 1
		else:
			_returning = true
		return
	out["move"] = to.normalized()
	out["sprint"] = not _returning


func _qb(out: Dictionary, dt: float, tuning: Dictionary, has_ball: bool) -> void:
	_take_cd -= dt
	if not has_ball:
		_phase = 0
		if _take_cd <= 0.0:
			out["take"] = true
			_take_cd = 2.0
		return
	match _phase:
		0:  # wait, then start a throw
			_throw_wait -= dt
			if _throw_wait <= 0.0:
				_phase = 1
				var ct: float = tuning["throw"]["power_charge_time"] if aim_mode else tuning["throw"]["charge_time"]
				_charge_left = rng.randf_range(0.2, 1.0) * float(ct)
				_lob = rng.randf() < 0.5
				_yaw = rng.randf_range(-0.25, 0.25)   # 0 = straight downfield (-z)
				_pitch = deg_to_rad(rng.randf_range(float(tuning["throw"]["angle_min_deg"]), float(tuning["throw"]["angle_max_deg"])))
		1:  # hold aim + throw while charging
			out["aiming"] = true
			out["throw"] = true
			out["yaw"] = _yaw
			out["lob"] = _lob
			_aim_fields(out)
			_charge_left -= dt
			if _charge_left <= 0.0:
				_phase = 2
		2:  # release: aim still held, throw button let go
			out["aiming"] = true
			out["throw"] = false
			out["yaw"] = _yaw
			out["lob"] = _lob
			_aim_fields(out)
			_phase = 0
			_throw_wait = rng.randf_range(2.0, 4.0)
			_take_cd = 4.0   # let the ball fly before grabbing it again


func _aim_fields(out: Dictionary) -> void:
	if aim_mode:
		out["mode"] = 0   # NetSession.ThrowMode.AIM
		out["pitch"] = _pitch
