extends Node
## Play-flow rules with scripted situations. Run headless:
##   godot --headless --path godot res://tests/play_test.tscn
var s: NetSession
var events: Array = []


func _ready():
	var root3d := Node3D.new()
	add_child(root3d)
	s = NetSession.new()
	s.athlete_parent = root3d
	add_child(s)
	s.start_host(7794)
	s.event_text.connect(func(x): events.append(x))
	s.start_match()
	var f := s.flow
	print("%-50s %s" % ["case", "result"])
	print("%-50s %s" % ["teams", "Orange %s, Blue %s" % [f._members(0).size(), f._members(1).size()]])
	print("%-50s %s" % ["first play", "offense %s, QB %s, ball on the %s, phase %s" % [
		NetSession.TEAM_NAMES[f.offense], s.name_of(f.qb_id), f.yard_line_text(f.los_z, f.offense), _phase()]])
	print("%-50s %s" % ["everyone is set before the snap", str(_all_set())])
	s._sv_take(f.slots[f.offense][1])
	print("%-50s %s" % ["a receiver can't snap", _phase()])
	f.phase_time = 1.0
	s._sv_take(f.qb_id)
	print("%-50s %s" % ["the QB snaps", "%s, ball held by %s" % [_phase(), s.name_of(s.ball_holder)]])

	# Rush barrier: drag a defender onto the offense's side of the line.
	var dfn: int = f.slots[1 - f.offense][0]
	var d := f.dir()
	s.sv_players[dfn].state.pos = Vector2(0, f.los_z - d * 3.0)
	f.tick(1.0 / 30.0)
	var t: float = (s.sv_players[dfn].state.pos.y - f.los_z) * d
	print("%-50s %s" % ["defender pushed back behind the line during rush", "%.2f m on the defense side" % t])
	f.rush_left = 0.0
	s.sv_players[dfn].state.pos = Vector2(0, f.los_z - d * 3.0)
	f.tick(1.0 / 30.0)
	t = (s.sv_players[dfn].state.pos.y - f.los_z) * d
	print("%-50s %s" % ["after the rush timer the defender may cross", "%.2f m (negative = crossed)" % t])

	# Team rules.
	var mate: int = f.slots[f.offense][1]
	s.sv_players[mate].state.pos = s.sv_players[f.qb_id].state.pos + Vector2(1.0, 0)
	s.sv_players[mate].state.heading = (s.sv_players[f.qb_id].state.pos - s.sv_players[mate].state.pos).normalized()
	s.sv_players[mate].tackle_cd = 0.0
	events.clear()
	s._sv_tackle(mate)
	print("%-50s %s" % ["a teammate pressing tackle on the QB", "ignored" if events.is_empty() and s.ball_holder == f.qb_id else str(events)])

	print("%-50s %s" % ["incomplete pass", _incomplete()])
	print("%-50s %s" % ["carrier runs out of bounds", _out_of_bounds()])
	print("%-50s %s" % ["defense recovers and is tackled (turnover)", _turnover()])
	print("%-50s %s" % ["touchdown", _touchdown()])
	print("%-50s %s" % ["only the thrower's team can catch", _catch_rule()])
	print()
	print("%-50s %s" % ["downs and scoring", "result"])
	_reset_drive(0, 15)
	print("%-50s %s" % ["start of a drive", _state()])
	print("%-50s %s" % ["gain 6 yards", _tackle_at(21)])
	print("%-50s %s" % ["gain 10 more: past midfield = first down", _tackle_at(31)])
	print("%-50s %s" % ["incomplete", _incomplete_now()])
	print("%-50s %s" % ["incomplete", _incomplete_now()])
	print("%-50s %s" % ["incomplete", _incomplete_now()])
	print("%-50s %s" % ["4th down incomplete: turnover on downs", _incomplete_now()])
	_reset_drive(0, 40)
	print("%-50s %s" % ["Orange touchdown", _td_now()])
	print("%-50s %s" % ["the QB picks the 2-point try", _pick(2)])
	print("%-50s %s" % ["2-point try scores", _td_now()])
	_reset_drive(1, 50)
	print("%-50s %s" % ["Blue touchdown", _td_now()])
	print("%-50s %s" % ["1-point try is stopped", _tackle_at(57)])
	_reset_drive(0, 3)
	print("%-50s %s" % ["Orange tackled in its own end zone", _tackle_at(-1)])
	get_tree().quit()


func _state() -> String:
	var f := s.flow
	return "%s ball, %s, on the %s, score Orange %d - %d Blue" % [NetSession.TEAM_NAMES[f.offense], f.down_text(),
		f.yard_line_text(f.los_z, f.offense), f.score[0], f.score[1]]


func _reset_drive(team: int, yard_line: float) -> void:
	var f := s.flow
	f.offense = team
	f.try_points = 0
	f.los_z = f._z_at_own_yard(team, yard_line)
	f.down = 1
	f.gain_z = f._first_gain(team, f.los_z)
	f._setup_play()


func _run_to_next_play() -> String:
	var f := s.flow
	var result := ""
	for i in 200:
		s.sv_tick += 1
		s._ball_tick(1.0 / 30.0)
		f.tick(1.0 / 30.0)
		if f.phase == PlayFlow.Phase.DEAD and result == "":
			result = f.result
		if f.phase == PlayFlow.Phase.PRE_SNAP:
			break
	return "%s  =>  %s" % [result, _state()]


## The carrier is tackled at this yard line (measured from the offense's own goal).
func _tackle_at(yard_line: float) -> String:
	_snap_now()
	var f := s.flow
	s._set_ball_down(Vector2(0, f._z_at_own_yard(f.offense, yard_line)))
	return _run_to_next_play()


func _incomplete_now() -> String:
	_snap_now()
	s.dead_reason = "incomplete"
	s.ball_kind = NetSession.Ball.LOOSE
	return _run_to_next_play()


func _td_now() -> String:
	_snap_now()
	var f := s.flow
	s.sv_players[f.qb_id].state.pos = Vector2(0, f.attack_goal_z(f.offense) + f.dir() * 1.0)
	return _run_to_next_play()


func _pick(points: int) -> String:
	var f := s.flow
	f.phase_time = 1.0
	f.pick_try(f.qb_id, points)
	return _state()


func _snap_now() -> void:
	var f := s.flow
	f.phase_time = 1.0
	s._sv_take(f.qb_id)


func _phase() -> String:
	return ["PRE_SNAP", "LIVE", "DEAD"][s.flow.phase]


func _all_set() -> bool:
	for id in s.sv_players:
		if s.sv_players[id].state.status != AthleteState.Status.SET:
			return false
	return true


func _fresh_live() -> void:
	var f := s.flow
	f._setup_play()
	f.phase_time = 1.0
	s._sv_take(f.qb_id)


func _finish() -> String:
	var f := s.flow
	var before_offense := f.offense
	var result := ""
	for i in 200:
		s.sv_tick += 1
		s._ball_tick(1.0 / 30.0)
		f.tick(1.0 / 30.0)
		if f.phase == PlayFlow.Phase.DEAD and result == "":
			result = f.result
		if f.phase == PlayFlow.Phase.PRE_SNAP:
			break
	return "%s | next: %s on offense, ball on the %s%s" % [result, NetSession.TEAM_NAMES[f.offense],
		f.yard_line_text(f.los_z, f.offense), " (possession changed)" if f.offense != before_offense else ""]


func _incomplete() -> String:
	_fresh_live()
	var f := s.flow
	var los_before := f.los_z
	s._sv_throw(f.qb_id, 0.3, 0.0 if f.dir() < 0 else PI, false)     # thrown to nobody
	var res := _finish()
	return res + (" [line unchanged]" if is_equal_approx(los_before, f.los_z) else " [LINE MOVED]")


func _out_of_bounds() -> String:
	_fresh_live()
	var f := s.flow
	var qb: AthleteState = s.sv_players[f.qb_id].state
	qb.pos = Vector2(f.half_wid() + 0.5, f.los_z + f.dir() * 8.0 * f.yard())
	return _finish()


func _turnover() -> String:
	_fresh_live()
	var f := s.flow
	var defender: int = f.slots[1 - f.offense][1]
	s.ball_holder = defender
	s.sv_players[defender].state.pos = Vector2(0, f.los_z)
	s._set_ball_down(Vector2(0, f.los_z - f.dir() * 2.0 * f.yard()))
	return _finish()


func _touchdown() -> String:
	_fresh_live()
	var f := s.flow
	var qb: AthleteState = s.sv_players[f.qb_id].state
	qb.pos = Vector2(0, f.attack_goal_z(f.offense) + f.dir() * 1.0)
	return _finish()


func _catch_rule() -> String:
	_fresh_live()
	var f := s.flow
	var qb: AthleteState = s.sv_players[f.qb_id].state
	var d := f.dir()
	var land := qb.pos + Vector2(0, d * 20.0)
	var mate: int = f.slots[f.offense][1]
	var opp: int = f.slots[1 - f.offense][1]
	s.sv_players[opp].state.pos = land + Vector2(0.3, 0)     # defender right on the spot
	s.sv_players[mate].state.pos = land + Vector2(-0.9, 0)   # receiver a bit further
	var th := Tuning.section("throw")
	var charge := inverse_lerp(float(th["min_range"]), float(th["max_range"]), 20.0)
	s._sv_throw(f.qb_id, charge, 0.0 if d < 0 else PI, false)
	for i in 60:
		s.sv_tick += 1
		s._ball_tick(1.0 / 30.0)
		if s.ball_kind != NetSession.Ball.FLIGHT:
			break
	if s.ball_kind == NetSession.Ball.HELD:
		return "caught by %s (the defender on the spot was ignored)" % s.name_of(s.ball_holder) if s.ball_holder == mate else "caught by %s" % s.name_of(s.ball_holder)
	return "not caught"
