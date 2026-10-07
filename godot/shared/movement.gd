class_name Movement
extends RefCounted
## Custom kinematic movement. Pure function of (state, input, dt, tuning):
## no nodes, no engine physics, so client and server run identical code.


static func step(s: AthleteState, move: Vector2, sprint: bool, dt: float, tuning: Dictionary) -> void:
	var m: Dictionary = tuning["movement"]
	var mag := clampf(move.length(), 0.0, 1.0)
	var want := move.normalized() if mag > 0.001 else Vector2.ZERO
	var run_speed: float = m["run_speed"]

	s.cut_cooldown = maxf(0.0, s.cut_cooldown - dt)
	s.juke_timer = maxf(0.0, s.juke_timer - dt)

	# Referee-imposed states: stumbling is slow and clumsy, being down means no control.
	if s.status != AthleteState.Status.OK:
		s.status_timer -= dt
		if s.status_timer <= 0.0:
			if s.status == AthleteState.Status.DIVING:
				# A dive that connects is resolved by the referee first; otherwise you hit the ground.
				s.status = AthleteState.Status.DOWN
				s.status_timer = tuning["tackle"]["dive_ground_time"]
			else:
				s.status = AthleteState.Status.OK
				s.status_timer = 0.0
	var stumbling := s.status == AthleteState.Status.STUMBLE
	var down := s.status == AthleteState.Status.DOWN
	var diving := s.status == AthleteState.Status.DIVING
	if down:
		want = Vector2.ZERO
		mag = 0.0

	var sprinting: bool = sprint and s.stamina > 0.0 and mag > 0.1 and s.status == AthleteState.Status.OK
	var top: float = run_speed * (m["sprint_multiplier"] if sprinting else 1.0)
	if stumbling:
		top *= m["stumble_speed_mult"]

	# Cut: a hard stick flick makes a brief plant that keeps part of your speed.
	if m["cut_enabled"] and s.status == AthleteState.Status.OK and s.cut_timer <= 0.0 and s.cut_cooldown <= 0.0 \
			and mag >= m["cut_min_input"] and s.prev_dir != Vector2.ZERO \
			and s.speed >= m["cut_min_speed"]:
		var flick := rad_to_deg(absf(s.prev_dir.angle_to(want)))
		if flick >= m["cut_min_angle_deg"] and rad_to_deg(absf(s.heading.angle_to(want))) >= m["cut_min_angle_deg"]:
			s.heading = want
			s.speed *= m["cut_speed_keep"]
			s.cut_timer = m["cut_plant_time"]
			s.cut_cooldown = m["cut_cooldown"]
			# A juke costs stamina. With too little left the cut still happens, but it
			# no longer fools anyone (no juke window).
			var cost: float = m["cut_stamina_cost"]
			if s.stamina >= cost:
				s.juke_timer = m["juke_window"]
			s.stamina = maxf(0.0, s.stamina - cost)
	s.prev_dir = want

	if s.cut_timer > 0.0:
		# Planted: no turning or acceleration for the plant duration.
		s.cut_timer = maxf(0.0, s.cut_timer - dt)
	elif diving:
		pass   # committed: heading and speed are locked until the dive ends
	else:
		_steer_and_accelerate(s, want, mag, top, dt, m, m["down_stop_time"] if down else m["stop_time"])

	# Stamina: sprinting drains, otherwise it refills (faster when standing).
	if sprinting:
		s.stamina = maxf(0.0, s.stamina - dt / float(m["sprint_seconds"]))
	else:
		var regen_s: float = m["stamina_regen_stand_seconds"] if s.speed < 0.5 else m["stamina_regen_jog_seconds"]
		s.stamina = minf(1.0, s.stamina + dt / regen_s)

	s.pos += s.heading * s.speed * dt
	_clamp_to_field(s, tuning["field"])


static func _steer_and_accelerate(s: AthleteState, want: Vector2, mag: float, top: float, dt: float, m: Dictionary, stop_time: float) -> void:
	var run_speed: float = m["run_speed"]
	var target := 0.0

	if want != Vector2.ZERO:
		if s.speed < m["snap_speed"]:
			s.heading = want
		else:
			# The faster you go, the wider you turn.
			var frac := clampf(s.speed / (run_speed * m["sprint_multiplier"]), 0.0, 1.0)
			var turn_deg := lerpf(m["turn_rate_slow_deg"], m["turn_rate_fast_deg"], frac)
			var max_turn := deg_to_rad(turn_deg) * dt
			var angle := s.heading.angle_to(want)
			s.heading = s.heading.rotated(clampf(angle, -max_turn, max_turn))
		# Pointing away from where you're going costs speed.
		var align := maxf(0.0, s.heading.dot(want))
		target = top * mag * lerpf(m["misaligned_speed_floor"], 1.0, align)

	if s.speed < target:
		s.speed = minf(target, s.speed + (run_speed / m["accel_time"]) * dt)
	else:
		s.speed = maxf(target, s.speed - (run_speed / stop_time) * dt)


static func _clamp_to_field(s: AthleteState, f: Dictionary) -> void:
	var yard: float = f["yard_m"]
	var half_len: float = (f["length_yards"] * 0.5 + f["endzone_yards"]) * yard
	var half_wid: float = f["width_yards"] * 0.5 * yard
	s.pos.x = clampf(s.pos.x, -half_wid, half_wid)
	s.pos.y = clampf(s.pos.y, -half_len, half_len)
