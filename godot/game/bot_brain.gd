class_name BotBrain
extends RefCounted
## Dev-only test driver. It feeds the normal input path, so a bot is just a
## client with no human. Modes:
##   wander  random walk with sprints and sharp turns
##   route   runs a receiver route from where it spawned, rests, jogs back, repeats
## With is_qb it also takes the ball and throws downfield now and then.

var lateral_chance := 0.0        # QB bots: chance to pitch it back instead of throwing
var role := ""                  # "chase": runs at the ball carrier and tackles
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
var _strip_roll := -1            # -1 = undecided, 0 tackle, 1 strip
var _dive_roll := -1            # -1 = undecided for this approach, 0 no, 1 yes
var _throw_wait := 2.0
var _phase := 0                 # 0 wait, 1 charging, 2 release
var _charge_left := 0.0
var _yaw := 0.0
var _lob := false


func _init() -> void:
	rng.randomize()


func think(pos: Vector2, dt: float, tuning: Dictionary, has_ball: bool, ctx := {}) -> Dictionary:
	var out := {"move": Vector2.ZERO, "sprint": false}
	if role == "chase":
		_chase(out, pos, tuning, ctx)
	elif route_name != "":
		_route(out, pos, dt, tuning)
	else:
		_wander(out, pos, dt, tuning["field"])
	if is_qb:
		_qb(out, dt, tuning, has_ball)
	return out


func _chase(out: Dictionary, pos: Vector2, tuning: Dictionary, ctx: Dictionary) -> void:
	if not ctx.has("carrier") or ctx.get("holding", false):
		return        # holding the carrier: hang on and wait for a teammate to finish him
	var cp: Vector2 = ctx["carrier"]
	var cv: Vector2 = ctx.get("carrier_vel", Vector2.ZERO)
	var dist := pos.distance_to(cp)
	# Lead the carrier, but ease the lead off as we close in so the aim point can never
	# end up behind us (that made the bot turn around mid-charge and whiff).
	var lead := float(tuning["bot"]["chase_lead_s"]) * clampf(dist / 6.0, 0.0, 1.0)
	var aim := cp + cv * lead
	out["move"] = (aim - pos).normalized()
	out["sprint"] = true
	var facing_ok := true
	if ctx.has("heading"):
		var h: Vector2 = ctx["heading"]
		facing_ok = rad_to_deg(absf(h.angle_to(cp - pos))) <= float(tuning["bot"]["chase_face_deg"])
	if dist <= float(tuning["bot"]["chase_trigger_m"]) and facing_ok:
		if ctx.get("carrier_wrapped", false):
			# Joining a wrap: sometimes go for the ball instead of the tackle.
			if _strip_roll < 0:
				_strip_roll = 1 if rng.randf() < float(tuning["bot"]["strip_chance"]) else 0
			if _strip_roll == 1:
				out["strip"] = true
			else:
				out["tackle"] = true
		else:
			out["tackle"] = true
	elif dist > float(tuning["bot"]["dive_trigger_m"]) + 2.0:
		_dive_roll = -1
		_strip_roll = -1
	elif dist <= float(tuning["bot"]["dive_trigger_m"]):
		if _dive_roll < 0:
			_dive_roll = 1 if rng.randf() < float(tuning["bot"]["dive_chance"]) else 0
		if _dive_roll == 1:
			out["dive"] = true


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
			if _throw_wait <= 0.0 and rng.randf() < lateral_chance:
				out["lateral"] = true
				out["yaw"] = PI + rng.randf_range(-0.5, 0.5)     # backward
				_throw_wait = rng.randf_range(2.0, 4.0)
				_take_cd = 3.0
			elif _throw_wait <= 0.0:
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
