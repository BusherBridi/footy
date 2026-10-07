extends Node
## Referee checks with scripted players. Run headless:
##   godot --headless --path godot res://tests/tackle_test.tscn
var s: NetSession


func _ready():
	var root3d := Node3D.new()
	add_child(root3d)
	s = NetSession.new()
	s.athlete_parent = root3d
	add_child(s)
	s.start_host(7791)
	# Carrier (id 2) at the origin heading -z (north). Tackler (id 3) placed relative to them.
	var run := 7.0
	var sprint := 8.75
	print("%-46s %s" % ["case", "result"])
	print("%-46s %s" % ["head-on, both sprinting", t(Vector2(0, -1.2), Vector2(0, 1), sprint, sprint)])
	print("%-46s %s" % ["head-on, tackler standing, carrier running", t(Vector2(0, -1.2), Vector2(0, 1), 0.0, run)])
	print("%-46s %s" % ["head-on, tackler sprint, carrier standing", t(Vector2(0, -1.2), Vector2(0, 1), sprint, 0.0)])
	print("%-46s %s" % ["from the side, tackler sprinting", t(Vector2(1.2, 0), Vector2(-1, 0), sprint, run)])
	print("%-46s %s" % ["from the side, tackler standing", t(Vector2(1.2, 0), Vector2(-1, 0), 0.0, run)])
	print("%-46s %s" % ["from behind, tackler running", t(Vector2(0, 1.2), Vector2(0, -1), run, run)])
	print("%-46s %s" % ["from behind, tackler sprinting", t(Vector2(0, 1.2), Vector2(0, -1), sprint, run)])
	print("%-46s %s" % ["out of reach (3 m)", t(Vector2(0, -3.0), Vector2(0, 1), sprint, run)])
	print("%-46s %s" % ["facing away from the carrier", t(Vector2(0, -1.2), Vector2(0, -1), sprint, run)])
	print("%-46s %s" % ["tackle cooldown (second press)", t(Vector2(0, -1.2), Vector2(0, 1), sprint, run, true)])
	get_tree().quit()


## tp: tackler position relative to carrier, th: tackler heading.
func t(tp: Vector2, th: Vector2, tspeed: float, cspeed: float, twice := false) -> String:
	for id in s.sv_players.keys():
		if id != 1:
			s.sv_players.erase(id)
	s._add_sv_player(2)
	s._add_sv_player(3)
	var c: AthleteState = s.sv_players[2].state
	c.pos = Vector2(0, 0); c.heading = Vector2(0, -1); c.speed = cspeed; c.status = 0
	var d: AthleteState = s.sv_players[3].state
	d.pos = tp; d.heading = th; d.speed = tspeed; d.status = 0
	s.sv_players[3].tackle_cd = 0.0
	s.ball_kind = NetSession.Ball.HELD
	s.ball_holder = 2
	var out: Array = []
	s.event_text.connect(func(x): out.append(x), CONNECT_ONE_SHOT)
	s._sv_tackle(3)
	if twice:
		s.ball_kind = NetSession.Ball.HELD
		s.ball_holder = 2
		c.status = 0
		var n_before := out.size()
		s._sv_tackle(3)
		return "second press ignored: %s" % (s.sv_players[3].tackle_cd > 0.0 and out.size() == n_before)
	var res: String = out[0] if out.size() > 0 else "(no event)"
	var carrier_state: String = ["ok", "stumble", "down"][c.status]
	return "%s -> carrier %s, ball %s" % [res, carrier_state, ["loose", "held", "flight"][s.ball_kind]]
