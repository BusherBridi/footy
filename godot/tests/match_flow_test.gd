extends Node
## Match flow: clock, halves, last-second try, sudden death, game over. Run headless:
##   godot --headless --path godot res://tests/match_flow_test.tscn
var s: NetSession
var f: PlayFlow
const DT := 1.0 / 30.0


func _ready():
	Tuning.data["accuracy"]["enabled"] = false     # exact throws: these cases test catching, not aim
	var root3d := Node3D.new()
	add_child(root3d)
	s = NetSession.new()
	s.athlete_parent = root3d
	add_child(s)
	s.start_host(7798)
	s.set_physics_process(false)
	s.set_process(false)
	s.start_match()
	s.sv_bots.clear()
	f = s.flow
	print("%-50s %s" % ["case", "result"])
	print("%-50s %s" % ["kickoff", _state()])
	_wait(3.0)
	print("%-50s %s" % ["3 s before the snap", _state()])
	_snap()
	_wait(2.0)
	print("%-50s %s" % ["2 s into the play", _state()])
	_tackle_at(25)
	print("%-50s %s" % ["tackled (+10): clock keeps running", _state()])
	_wait(3.0)
	_snap()
	_wait(0.5)
	s._sv_throw(f.qb_id, 0.2, 0.0 if f.dir() < 0 else 3.14159, false)
	_until_presnap()
	print("%-50s %s" % ["incomplete pass", _state()])
	_turnover_on_downs()
	print("%-50s %s" % ["turnover on downs: clock stops", _state()])
	_snap()
	_wait(1.0)
	print("%-50s %s" % ["next snap: clock runs again", _state()])

	# End of the 1st half: a play running at 0:00 is finished, then halftime.
	f.clock = 0.5
	_wait(1.0)
	print("%-50s %s" % ["clock hits 0:00 mid-play", _state()])
	_tackle_at(30)
	_until_presnap()
	print("%-50s %s" % ["after that play: halftime", _state()])

	# 2nd half: touchdown with 1 s left, the try is still played.
	f.score = [7, 0]
	f.clock = 1.0
	_snap()
	_wait(1.2)
	_td()
	_until_presnap()
	print("%-50s %s" % ["touchdown as time expires", _state()])
	_snap()
	_tackle_at(97)
	_until_presnap()
	print("%-50s %s" % ["try stopped, time's up, 7-6: game over?", _state() + " | game over: %s, winner %s" % [str(f.game_over), NetSession.TEAM_NAMES[maxi(f.winner, 0)]]])

	# Tied at the end: sudden death, first score wins, no try.
	f.redo_play()
	f.score = [6, 6]
	f.half = 2
	f.clock = 0.2
	f.try_points = 0
	f._setup_play()
	f.clock_running = true     # after a normal tackle the clock keeps running before the snap
	_wait(1.0)
	_until_presnap()
	print("%-50s %s" % ["tied 6-6 at 0:00", _state()])
	_wait(10.0)
	print("%-50s %s" % ["sudden death: no clock", _state()])
	_snap()
	_td()
	_until_dead()
	_wait(4.0)
	print("%-50s %s" % ["sudden death touchdown", _state() + " | game over: %s, winner %s" % [str(f.game_over), NetSession.TEAM_NAMES[maxi(f.winner, 0)]]])
	get_tree().quit()


func _state() -> String:
	return "%s half, %s%s, %s ball, %s, Orange %d - %d Blue, %s" % [["", "1st", "2nd", "OT"][f.half], f.clock_text(),
		"" if f.clock_running else " (stopped)", NetSession.TEAM_NAMES[f.offense], f.down_text(), f.score[0], f.score[1],
		["PRE_SNAP", "LIVE", "DEAD"][f.phase]]


func _step() -> void:
	s.sv_tick += 1
	s._ball_tick(DT)
	f.tick(DT)


func _wait(secs: float) -> void:
	for i in int(round(secs / DT)):
		_step()


func _until_presnap() -> void:
	for i in 600:
		_step()
		if f.phase == PlayFlow.Phase.PRE_SNAP or f.game_over:
			return


func _until_dead() -> void:
	for i in 600:
		_step()
		if f.phase == PlayFlow.Phase.DEAD:
			return


func _snap() -> void:
	f.phase_time = maxf(f.phase_time, 1.0)
	s._sv_take(f.qb_id)


func _tackle_at(yard_line: float) -> void:
	if f.phase != PlayFlow.Phase.LIVE:
		_snap()
	s._set_ball_down(Vector2(0, f._z_at_own_yard(f.offense, yard_line)))
	_until_presnap()


func _td() -> void:
	s.sv_players[f.qb_id].state.pos = Vector2(0, f.attack_goal_z(f.offense) + f.dir() * 1.0)


func _turnover_on_downs() -> void:
	f.down = 4
	_snap()
	s.dead_reason = "incomplete"
	s.ball_kind = NetSession.Ball.LOOSE
	_until_presnap()
