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
	print()
	print("%-46s %s" % ["stiff arm + dive cases", "result"])
	print("%-46s %s" % ["head-on sprint, stiff arm timed", st(Vector2(0, -1.2), Vector2(0, 1), sprint, sprint, 1.0, true)])
	print("%-46s %s" % ["head-on sprint, stiff arm too early/late", st(Vector2(0, -1.2), Vector2(0, 1), sprint, sprint, 1.0, false)])
	print("%-46s %s" % ["side hit sprint, stiff arm timed", st(Vector2(1.2, 0), Vector2(-1, 0), sprint, run, 1.0, true)])
	print("%-46s %s" % ["head-on sprint, stiff arm with empty stamina", st(Vector2(0, -1.2), Vector2(0, 1), sprint, sprint, 0.05, true)])
	print("%-46s %s" % ["stiff arm twice (cooldown)", stiff_twice()])
	print("%-46s %s" % ["dive hits the carrier (2.5 m, head-on)", dive(Vector2(0, -2.5), Vector2(0, 1), true)])
	print("%-46s %s" % ["dive misses (carrier 8 m away)", dive(Vector2(0, -8.0), Vector2(0, 1), false)])
	get_tree().quit()


func reset(tp: Vector2, th: Vector2, tspeed: float, cspeed: float) -> void:
	for id in s.sv_players.keys():
		if id != 1:
			s.sv_players.erase(id)
	s._add_sv_player(2)
	s._add_sv_player(3)
	var c: AthleteState = s.sv_players[2].state
	c.pos = Vector2(0, 0); c.heading = Vector2(0, -1); c.speed = cspeed; c.status = 0; c.stamina = 1.0
	var d: AthleteState = s.sv_players[3].state
	d.pos = tp; d.heading = th; d.speed = tspeed; d.status = 0
	s.ball_kind = NetSession.Ball.HELD
	s.ball_holder = 2


func st(tp: Vector2, th: Vector2, tspeed: float, cspeed: float, stamina: float, timed: bool) -> String:
	reset(tp, th, tspeed, cspeed)
	var c: AthleteState = s.sv_players[2].state
	c.stamina = stamina
	s._sv_stiffarm(2)
	if not timed:
		s.sv_players[2].stiff_timer = 0.0     # window not open when contact happens
	var out: Array = []
	s.event_text.connect(func(x): out.append(x), CONNECT_ONE_SHOT)
	s._sv_tackle(3)
	return "%s -> carrier %s" % [out[0] if out.size() > 0 else "(none)", ["ok", "stumble", "down", "diving"][c.status]]


func stiff_twice() -> String:
	reset(Vector2(0, -5), Vector2(0, 1), 0.0, 7.0)
	s._sv_stiffarm(2)
	var cost1: float = 1.0 - s.sv_players[2].state.stamina
	s._sv_stiffarm(2)
	var cost2: float = 1.0 - s.sv_players[2].state.stamina
	return "stamina spent after press 1: %.2f, after press 2: %.2f (second ignored: %s)" % [cost1, cost2, is_equal_approx(cost1, cost2)]


func dive(tp: Vector2, th: Vector2, hits: bool) -> String:
	reset(tp, th, 7.0, 0.0)     # carrier standing still so the dive can reach
	var d: AthleteState = s.sv_players[3].state
	var c: AthleteState = s.sv_players[2].state
	s._sv_dive(3)
	var out: Array = []
	s.event_text.connect(func(x): out.append(x), CONNECT_ONE_SHOT)
	var trace := ""
	for i in 60:
		s._host_tick(1.0 / 30.0)
		if i == 5 or i == 20 or i == 45:
			trace += " | t=%.1fs diver %s" % [(i + 1) / 30.0, ["ok", "stumble", "down", "diving"][d.status]]
	return "%s -> carrier %s%s" % [out[0] if out.size() > 0 else "(no hit)", ["ok", "stumble", "down", "diving"][c.status], trace]


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
	var carrier_state: String = ["ok", "stumble", "down", "diving"][c.status]
	return "%s -> carrier %s, ball %s" % [res, carrier_state, ["loose", "held", "flight"][s.ball_kind]]
