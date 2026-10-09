class_name Movement
extends RefCounted
## Custom kinematic movement. Pure function of (state, input, dt, tuning):
## no nodes, no engine physics, so client and server run identical code.


static func step(s: AthleteState, move: Vector2, sprint: bool, dt: float, tuning: Dictionary, stance := false) -> void:
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
			elif s.status == AthleteState.Status.SPIN:
				# Pop out of the spin to the side chosen with the stick, with a burst of speed.
				s.heading = s.heading.rotated(s.spin_side * deg_to_rad(m["pop_angle_deg"]))
				s.speed = maxf(s.speed, run_speed * float(m["pop_speed_mult"]))
				s.status = AthleteState.Status.POP
				s.status_timer = m["pop_time"]
				s.spin_side = 0
			else:
				s.status = AthleteState.Status.OK
				s.status_timer = 0.0
	var stumbling := s.status == AthleteState.Status.STUMBLE
	var down := s.status == AthleteState.Status.DOWN
	var diving := s.status == AthleteState.Status.DIVING
	var spinning := s.status == AthleteState.Status.SPIN
	var popping := s.status == AthleteState.Status.POP
	var wrapped := s.status == AthleteState.Status.WRAPPED
	var holding := s.status == AthleteState.Status.HOLDING
	var blocked := s.status == AthleteState.Status.BLOCKED     # placed by the referee each tick
	if spinning and mag >= float(m["spin_side_input"]):
		# Hold left or right of your running direction to choose the pop side.
		var side := s.heading.cross(want)
		if absf(side) >= float(m["spin_side_cross"]):
			s.spin_side = 1 if side > 0.0 else -1
	if down:
		want = Vector2.ZERO
		mag = 0.0
	if s.status == AthleteState.Status.SET:
		# Lined up before the snap: nobody moves (the game enforces it, no penalties).
		s.speed = 0.0
		return

	var in_stance := _stance(s, stance, dt, m)
	var flipping := s.hip_timer > 0.0
	var sprint_ok := (s.status == AthleteState.Status.OK or s.status == AthleteState.Status.HURDLE) and not in_stance and not flipping
	var sprinting: bool = sprint and s.stamina > 0.0 and mag > 0.1 and sprint_ok
	var top: float = run_speed * (m["sprint_multiplier"] if sprinting else 1.0)
	if in_stance and want != Vector2.ZERO:
		# Shuffling: quickest going forward, slower sideways, slowest backpedalling.
		var d := s.stance_dir.dot(want)
		top = run_speed * (lerpf(m["stance_side_mult"], m["stance_forward_mult"], d) if d >= 0.0 \
			else lerpf(m["stance_side_mult"], m["stance_back_mult"], -d))
	elif flipping:
		top *= m["hip_flip_speed_mult"]
	if s.carrying:
		top *= m["carry_speed_mult"]
	if stumbling:
		top *= m["stumble_speed_mult"]
	elif s.status == AthleteState.Status.TRUCK:
		top *= m["truck_speed_mult"]
	elif wrapped:
		top *= m["wrap_speed_mult"]
	elif s.status == AthleteState.Status.BLOCKING:
		top *= float(tuning["block"]["drive_mult"])      # driving a defender: slow going

	# Cut: a hard stick flick makes a brief plant that keeps part of your speed.
	if m["cut_enabled"] and s.status == AthleteState.Status.OK and not in_stance and not flipping and s.cut_timer <= 0.0 and s.cut_cooldown <= 0.0 \
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
	elif diving or spinning or popping or holding or blocked:
		pass   # committed: heading and speed are locked until the move ends
	elif s.status == AthleteState.Status.BLOCKING:
		_drive(s, want, mag, top, dt, m, tuning["block"])
	else:
		_steer_and_accelerate(s, want, mag, top, dt, m, m["down_stop_time"] if down else m["stop_time"])

	# Stamina: sprinting drains, otherwise it refills (faster when standing).
	if wrapped:
		# Dragging a defender around burns stamina fast; at zero the carrier goes down.
		s.stamina = maxf(0.0, s.stamina - dt * float(m["wrap_drain"]))
	elif s.status == AthleteState.Status.BLOCKING:
		pass           # holding a block: no recovery (the referee drains it)
	elif sprinting:
		s.stamina = maxf(0.0, s.stamina - dt / float(m["sprint_seconds"]))
	else:
		var regen_s: float = m["stamina_regen_stand_seconds"] if s.speed < 0.5 else m["stamina_regen_jog_seconds"]
		s.stamina = minf(1.0, s.stamina + dt / regen_s)

	s.pos += s.heading * s.speed * dt
	_clamp_to_field(s, tuning["field"])


## Stance: hold it to keep facing where you faced when you pressed it. Letting go while
## moving well away from that facing costs a hip flip: a moment of slow running while the
## body turns round. Only on your feet and without the ball. Returns whether in stance.
static func _stance(s: AthleteState, held: bool, dt: float, m: Dictionary) -> bool:
	var able := s.status == AthleteState.Status.OK and not s.carrying
	if not able:
		s.stance_dir = Vector2.ZERO
		s.hip_timer = 0.0
		return false
	if held:
		if s.stance_dir == Vector2.ZERO:
			s.stance_dir = s.heading
		s.hip_timer = 0.0
		return true
	if s.stance_dir == Vector2.ZERO:
		return false
	if s.hip_timer <= 0.0:
		var turned := rad_to_deg(absf(s.stance_dir.angle_to(s.heading)))
		if s.speed > 0.5 and turned >= float(m["hip_flip_min_deg"]):
			s.hip_timer = m["hip_flip_time"]
		else:
			s.stance_dir = Vector2.ZERO
			return false
	# Flipping the hips: the body swings round to the running direction.
	var k := clampf(dt / s.hip_timer, 0.0, 1.0)
	s.stance_dir = s.stance_dir.rotated(s.stance_dir.angle_to(s.heading) * k).normalized()
	s.hip_timer -= dt
	if s.hip_timer <= 0.0:
		s.hip_timer = 0.0
		s.stance_dir = Vector2.ZERO
	return false


## Locked onto a defender: you only push forward (into them), steering slowly.
static func _drive(s: AthleteState, want: Vector2, mag: float, top: float, dt: float, m: Dictionary, bk: Dictionary) -> void:
	var target := 0.0
	if want != Vector2.ZERO:
		var max_turn := deg_to_rad(float(bk["turn_deg"])) * dt
		s.heading = s.heading.rotated(clampf(s.heading.angle_to(want), -max_turn, max_turn))
		target = top * mag * maxf(0.0, s.heading.dot(want))
	var run_speed: float = m["run_speed"]
	if s.speed < target:
		s.speed = minf(target, s.speed + (run_speed / m["accel_time"]) * dt)
	else:
		s.speed = maxf(target, s.speed - (run_speed / m["stop_time"]) * dt)


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
	var margin: float = f.get("oob_margin_m", 0.0)     # room to step out of bounds
	var half_len: float = (f["length_yards"] * 0.5 + f["endzone_yards"]) * yard + margin
	var half_wid: float = f["width_yards"] * 0.5 * yard + margin
	s.pos.x = clampf(s.pos.x, -half_wid, half_wid)
	s.pos.y = clampf(s.pos.y, -half_len, half_len)
