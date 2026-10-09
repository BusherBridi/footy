extends Node
## Swats and interceptions with scripted timing. Run headless:
##   godot --headless --path godot res://tests/swat_test.tscn
var s: NetSession
var events: Array = []
var DT := 1.0 / 30.0


func _ready():
	Tuning.data["accuracy"]["enabled"] = false     # exact throws: these cases test catching, not aim
	var root3d := Node3D.new()
	add_child(root3d)
	s = NetSession.new()
	s.athlete_parent = root3d
	add_child(s)
	s.start_host(7795)
	s.set_physics_process(false)
	s.set_process(false)
	s.event_text.connect(func(x): events.append(x))
	s.start_match()
	DT = s._tick_dt()
	print("%-56s %s" % ["case (press = seconds before the ball reaches the hands)", "result"])
	print("%-56s %s" % ["nobody reaches: the receiver catches", _case(-1.0)])
	print("%-56s %s" % ["press 0.12 s early, facing the ball", _case(0.12)])
	print("%-56s %s" % ["press 0.02 s early (late)", _case(0.02)])
	print("%-56s %s" % ["press 0.28 s early", _case(0.28)])
	print("%-56s %s" % ["press 0.6 s early: the reach ends first (whiff)", _case(0.6)])
	print("%-56s %s" % ["press 0.12 s early, back to the ball", _case(0.12, {"away": true})])
	print("%-56s %s" % ["press 0.12 s early, receiver level with the defender", _case(0.12, {"rec_level": true})])
	print("%-56s %s" % ["press 0.12 s early, heard 150 ms late (lag)", _case(0.12, {"lag_s": 0.15})])
	print("%-56s %s" % ["press 0.12 s early, heard 400 ms late (too much lag)", _case(0.12, {"lag_s": 0.40})])
	print("%-56s %s" % ["the receiver's teammate can't swat", _case(0.12, {"teammate": true})])
	print()
	print("%-56s %s" % ["rules", "result"])
	print("%-56s %s" % ["pick, then tackled on the return", _pick_then_down(20.0)])
	print("%-56s %s" % ["pick, then downed in their own end zone", _pick_then_down(-3.0)])
	print("%-56s %s" % ["pick on a 2-point try", _pick_on_try()])
	print("%-56s %s" % ["swat: incomplete, line unchanged", _swat_result()])
	get_tree().quit()


func _drive(team: int, yard_line: float, try_pts := 0) -> void:
	var f := s.flow
	f.offense = team
	f.try_points = try_pts
	f.los_z = f._z_at_own_yard(team, yard_line)
	f.down = 1
	f.gain_z = f._first_gain(team, f.los_z)
	f._setup_play()
	f.phase_time = 1.0
	s._sv_take(f.qb_id)


## One pass 15 m downfield to a receiver, with a defender just in front of them.
## early < 0: the defender never presses. Returns what happened.
func _case(early: float, o := {}) -> String:
	_drive(0, 15, int(o.get("try", 0)))
	var f := s.flow
	var d := f.dir()
	var qb := f.qb_id
	var rec: int = f.slots[f.offense][1]
	var dfn: int = f.slots[f.offense][2] if o.get("teammate", false) else f.slots[1 - f.offense][1]
	var qpos: Vector2 = s.sv_players[qb].state.pos
	for id in s.sv_players:
		if id != qb and id != rec and id != dfn:
			s.sv_players[id].state.pos = Vector2(12.0, qpos.y - d * 8.0)     # out of the way
	var land := qpos + Vector2(0, d * 15.0)
	s.sv_players[rec].state.pos = land + (Vector2(0.5, -d * 0.6) if o.get("rec_level", false) else Vector2(0.9, 0))
	s.sv_players[dfn].state.pos = land + Vector2(-0.5, -d * 0.6)
	s.sv_players[dfn].state.heading = Vector2(0, d) if o.get("away", false) else Vector2(0, -d)
	for id in [rec, dfn]:
		s.sv_players[id].state.status = AthleteState.Status.OK
		s.sv_players[id].state.speed = 0.0
		s.sv_players[id].swat_cd = 0.0
	var th := Tuning.section("throw")
	var charge := inverse_lerp(float(th["min_range"]), float(th["max_range"]), 15.0)
	s._sv_throw(qb, charge, 0.0 if d < 0 else PI, false)
	# When does the ball reach the defender's hands?
	var fl := BallFlight.launch(s.ball_p0, s.ball_yaw, s.ball_charge, s.ball_lob, Tuning.data, s.ball_angle)
	var hands := -1.0
	var t := 0.0
	while t < float(fl["T"]):
		var b := BallFlight.position_at(s.ball_p0, fl, float(th["gravity"]), t)
		if CatchRules.zone_distance(s.sv_players[dfn].state.pos, 0.0, b, Tuning.data) >= 0.0:
			hands = t
			break
		t += 0.001
	var press_tick := float(s.ball_launch_tick) + (hands - early) / DT
	var heard_tick := press_tick + float(o.get("lag_s", 0.0)) / DT
	var pressed := early < 0.0
	s.last_swat_why = ""
	events.clear()
	var stumbled := false
	for i in 120:
		s.sv_tick += 1
		if not pressed and float(s.sv_tick) >= heard_tick:
			pressed = true
			s._sv_swat(dfn, press_tick)
		s._swat_timers(DT)
		s._ball_tick(DT)
		stumbled = stumbled or s.sv_players[dfn].state.status == AthleteState.Status.STUMBLE
		if s.ball_kind != NetSession.Ball.FLIGHT and pressed and s.sv_players[dfn].swat_from < 0.0:
			break
	var out := ""
	if s.ball_kind == NetSession.Ball.HELD:
		if o.get("teammate", false) and s.ball_holder == dfn:
			out = "caught like any receiver (the press was ignored)"
		else:
			out = "INTERCEPTED" if s.ball_holder == dfn else ("caught by the receiver" if s.ball_holder == rec else "held by %d" % s.ball_holder)
	else:
		if out == "":
			out = "SWATTED" if s.swat_note != "" else "ball on the ground"
	if stumbled:
		out += " (defender whiffed and stumbled)"
	var why := s.last_swat_why
	s.last_swat_why = ""
	return out + ("  (%s)" % why if why != "" else "")


func _pick_then_down(yards_from_own_goal: float) -> String:
	var res := _case(0.12)
	if not res.begins_with("INTERCEPTED"):
		return "no pick: " + res
	var f := s.flow
	var dfn := s.ball_holder
	var team := f.team_of(dfn)
	s._set_ball_down(Vector2(0, f.own_goal_z(team) + f.team_dir(team) * yards_from_own_goal * f.yard()))
	return _finish()


func _pick_on_try() -> String:
	_case(0.12, {"try": 2})
	return s.flow.result + " | next: %s ball" % NetSession.TEAM_NAMES[s.flow._next_offense]


func _swat_result() -> String:
	var los := s.flow.los_z
	var res := _case(0.28)
	return res.substr(0, 7) + " | " + _finish() + (" [line unchanged]" if is_equal_approx(los, s.flow.los_z) else " [LINE MOVED]")


func _finish() -> String:
	var f := s.flow
	var result := ""
	for i in 200:
		s.sv_tick += 1
		s._ball_tick(DT)
		f.tick(DT)
		if f.phase == PlayFlow.Phase.DEAD and result == "":
			result = f.result
		if f.phase == PlayFlow.Phase.PRE_SNAP:
			break
	return "%s | next: %s ball on the %s" % [result, NetSession.TEAM_NAMES[f.offense], f.yard_line_text(f.los_z, f.offense)]
