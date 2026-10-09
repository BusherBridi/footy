extends Node
## Playtesting aids: position pick, redo, bot difficulty, timing readouts, log marks.
##   godot --headless --path godot res://tests/qol_test.tscn
var s: NetSession
var coach: Array = []


func _ready():
	var root3d := Node3D.new()
	add_child(root3d)
	s = NetSession.new()
	s.athlete_parent = root3d
	add_child(s)
	s.start_host(7796)
	s.set_physics_process(false)
	s.set_process(false)
	s.coach_text.connect(func(t): coach.append(t))
	s.start_match()
	var f := s.flow
	print("%-48s %s" % ["case", "result"])
	print("%-48s %s" % ["default: you line up at", _spot(f)])
	s.set_position(1)
	f._setup_play()
	print("%-48s %s" % ["after picking receiver / cornerback", _spot(f)])
	f.offense = 1 - f.offense
	f._setup_play()
	print("%-48s %s" % ["  ... and on defense", _spot(f)])
	s.set_position(0)
	f._setup_play()
	print("%-48s %s" % ["back to QB / linebacker", _spot(f)])

	# Redo: gain some yards, then redo the next play.
	f.offense = 0
	f.los_z = f._z_at_own_yard(0, 15)
	f.down = 1
	f.gain_z = f._first_gain(0, f.los_z)
	f._setup_play()
	var before := "%s on the %s, %d-%d" % [f.down_text(), f.yard_line_text(f.los_z, f.offense), f.score[0], f.score[1]]
	f.phase_time = 1.0
	s._sv_take(f.qb_id)
	s._set_ball_down(Vector2(0, f._z_at_own_yard(0, 24)))
	for i in 200:
		s.sv_tick += 1
		f.tick(1.0 / 30.0)
		if f.phase == PlayFlow.Phase.PRE_SNAP:
			break
	var after := "%s on the %s" % [f.down_text(), f.yard_line_text(f.los_z, f.offense)]
	f.phase_time = 1.0
	s._sv_take(f.qb_id)
	s.redo_play()
	print("%-48s %s" % ["play started at", before])
	print("%-48s %s" % ["next play (after a 9-yard gain)", after])
	print("%-48s %s" % ["redo during that play puts it back to", "%s on the %s, phase %s" % [f.down_text(), f.yard_line_text(f.los_z, f.offense), ["PRE_SNAP", "LIVE", "DEAD"][f.phase]]])

	for level in ["easy", "normal", "hard"]:
		s.set_bot_difficulty(level)
		var ai: Dictionary = s._bot_tuning()["ai"]
		print("%-48s %s" % ["bots on %s" % level, "cover react %.2f s, swat chance %.2f, timing error %.2f s, throw error %.1f m" % [
			ai["cover_react_s"], ai["swat_chance"], ai["swat_error_s"], ai["throw_error_m"]]])
	print("%-48s %s" % ["the real tuning is untouched", "swat chance %.2f" % float(Tuning.section("ai")["swat_chance"])])

	# Timing readouts: a stiff arm 0.1 s before a side hit, and one far too early.
	print("%-48s %s" % ["stiff arm, then hit 0.1 s later", _stiff_case(3)])
	print("%-48s %s" % ["stiff arm, then hit 0.5 s later", _stiff_case(15)])
	var n := s.add_mark()
	var log_text := FileAccess.get_file_as_string(s.log_path())
	print("%-48s %s" % ["F9 mark", "mark %d is in %s: %s" % [n, s.log_path(), str(log_text.contains("MARK %d" % n))]])
	get_tree().quit()


func _spot(f: PlayFlow) -> String:
	var team := f.team_of(1)
	var slot: int = f.slots[team].find(1)
	if team == f.offense:
		return "QB" if slot == 0 else "receiver (slot %d)" % slot
	return "linebacker" if slot == 0 else "cornerback (slot %d)" % slot


func _stiff_case(ticks_later: int) -> String:
	var f := s.flow
	f.offense = 0
	f._setup_play()
	f.phase_time = 1.0
	s._sv_take(f.qb_id)
	var c: NetSession.SvPlayer = s.sv_players[1]
	c.state.pos = Vector2(0, 0)
	c.state.heading = Vector2(0, -1)
	c.state.speed = 6.0
	c.state.status = AthleteState.Status.OK
	c.counter_cd = 0.0
	s._sv_stiffarm(1, -1)
	s.sv_tick += ticks_later
	c.stiff_timer = maxf(0.0, c.stiff_timer - ticks_later / 30.0)
	var dfn: int = f.slots[1][1]
	var d: NetSession.SvPlayer = s.sv_players[dfn]
	d.state.pos = Vector2(-1.0, 0)
	d.state.heading = Vector2(1, 0)
	d.state.speed = 5.0
	coach.clear()
	s._resolve_tackle(dfn, 1)
	return " | ".join(coach)
