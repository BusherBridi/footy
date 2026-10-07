extends Node
## Lateral (pitch) checks. Run headless:
##   godot --headless --path godot res://tests/lateral_test.tscn
var s: NetSession


func _ready():
	var root3d := Node3D.new()
	add_child(root3d)
	s = NetSession.new()
	s.athlete_parent = root3d
	add_child(s)
	s.start_host(7793)
	print("%-48s %s" % ["case", "result"])
	print("%-48s %s" % ["pitch straight back (yaw 180 deg)", run(PI, [])])
	print("%-48s %s" % ["pitch sideways (yaw 90 deg)", run(PI / 2.0, [])])
	print("%-48s %s" % ["pitch forward (yaw 0) is refused", run(0.0, [])])
	print("%-48s %s" % ["pitch 4 deg forward (inside the 5 deg slack)", run(deg_to_rad(86.0), [])])
	print("%-48s %s" % ["pitch 10 deg forward (refused)", run(deg_to_rad(80.0), [])])
	print("%-48s %s" % ["teammate waiting 10 m back catches it", run(PI, [[4, Vector2(0, 25.0)]])])
	print("%-48s %s" % ["nobody there: live ball on the ground", run(PI, [])])
	print("%-48s %s" % ["down carrier can't pitch", run(PI, [], true)])
	print("%-48s %s" % ["pitching out of a wrap ends the wrap", wrapped_pitch()])
	get_tree().quit()


func setup(extra: Array, down := false) -> void:
	for id in s.sv_players.keys():
		if id != 1:
			s.sv_players.erase(id)
	var me: AthleteState = s.sv_players[1].state
	me.pos = Vector2(0, 15)
	me.heading = Vector2(0, -1)
	me.speed = 0.0
	me.status = AthleteState.Status.DOWN if down else AthleteState.Status.OK
	s.sv_players[1].queue.clear()
	for e in extra:
		s._add_sv_player(e[0])
		s.sv_players[e[0]].state.pos = e[1]
		s.sv_players[e[0]].state.speed = 0.0
	s.ball_kind = NetSession.Ball.HELD
	s.ball_holder = 1
	s.ball_live = false
	s.ball_lateral = false


func run(yaw: float, extra: Array, down := false) -> String:
	setup(extra, down)
	var out: Array = []
	var cb := func(x): out.append(x)
	s.event_text.connect(cb)
	s._sv_lateral(1, yaw)
	s.event_text.disconnect(cb)
	if s.ball_kind != NetSession.Ball.FLIGHT:
		return "refused%s" % ((" (" + str(out[0]) + ")") if out.size() > 0 else "")
	var fl := BallFlight.launch(s.ball_p0, s.ball_yaw, s.ball_charge, s.ball_lob, Tuning.data)
	var land: Vector3 = fl["land"]
	var n := 0
	for i in 200:
		n += 1
		s.sv_tick += 1
		s._ball_tick(1.0 / 30.0)
		if s.ball_kind != NetSession.Ball.FLIGHT:
			break
	var res := "flew %.1f m to (%.1f, %.1f) in %.2fs; " % [Vector2(land.x, land.z).distance_to(Vector2(0, 15)), land.x, land.z, n / 30.0]
	if s.ball_kind == NetSession.Ball.HELD:
		res += "CAUGHT by player %d" % s.ball_holder
	else:
		res += "loose, %s" % ("LIVE" if s.ball_live else "dead")
	return res


func wrapped_pitch() -> String:
	setup([[3, Vector2(0.9, 15.0)]])
	var c: NetSession.SvPlayer = s.sv_players[1]
	c.state.pos = Vector2(0, 15)
	s._start_wrap(3, 1, 6.0)
	var before: String = ["ok", "stumble", "down", "diving", "spin", "truck", "hurdle", "pop", "wrapped", "holding"][c.state.status]
	s._sv_lateral(1, PI)
	s._host_tick(1.0 / 30.0)
	var after: String = ["ok", "stumble", "down", "diving", "spin", "truck", "hurdle", "pop", "wrapped", "holding"][c.state.status]
	var h: String = ["ok", "stumble", "down", "diving", "spin", "truck", "hurdle", "pop", "wrapped", "holding"][s.sv_players[3].state.status]
	return "carrier %s -> %s, holder -> %s, ball %s" % [before, after, h, ["loose", "held", "flight"][s.ball_kind]]
