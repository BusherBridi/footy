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
	print()
	print("%-46s %s" % ["juke cases", "result"])
	print("%-46s %s" % ["hard flick at run speed", flick(1.0)])
	print("%-46s %s" % ["hard flick with nearly empty stamina", flick(0.05)])
	print("%-46s %s" % ["dive at a carrier whose juke is live", dive(Vector2(0, -2.5), Vector2(0, 1), false, 0.3)])
	print("%-46s %s" % ["close tackle while juke is live (weak)", st(Vector2(0, -1.2), Vector2(0, 1), sprint, sprint, 1.0, false, 0.3)])
	print()
	print("%-46s %s" % ["passive momentum + new counters", "result"])
	print("%-46s %s" % ["standing defender vs sprinting carrier", t(Vector2(0, -1.2), Vector2(0, 1), 0.0, sprint)])
	print("%-46s %s" % ["jogging defender vs jogging carrier", t(Vector2(0, -1.2), Vector2(0, 1), run, run)])
	print("%-46s %s" % ["charging sprinter vs sprinting carrier", t(Vector2(0, -1.2), Vector2(0, 1), sprint, sprint)])
	print("%-46s %s" % ["TRUCK vs standing defender", cnt(AthleteState.Status.TRUCK, Vector2(0, -1.2), Vector2(0, 1), 0.0, sprint, 1.0)])
	print("%-46s %s" % ["TRUCK vs charging sprinter, head-on", cnt(AthleteState.Status.TRUCK, Vector2(0, -1.2), Vector2(0, 1), sprint, sprint, 1.0)])
	print("%-46s %s" % ["TRUCK vs hit from the side", cnt(AthleteState.Status.TRUCK, Vector2(1.2, 0), Vector2(-1, 0), sprint, run, 1.0)])
	print("%-46s %s" % ["TRUCK with empty stamina, head-on sprinter", cnt(AthleteState.Status.TRUCK, Vector2(0, -1.2), Vector2(0, 1), sprint, sprint, 0.05)])
	s.fumble_roll = 0.0
	print("%-46s %s" % ["tackled during a SPIN (dice forced to fumble)", cnt(AthleteState.Status.SPIN, Vector2(0, -1.2), Vector2(0, 1), sprint, run, 1.0, true)])
	s.fumble_roll = 1.0
	print("%-46s %s" % ["tackled during a SPIN (dice forced no fumble)", cnt(AthleteState.Status.SPIN, Vector2(0, -1.2), Vector2(0, 1), sprint, run, 1.0, true)])
	s.fumble_roll = 0.0
	print("%-46s %s" % ["tackled in the air on a HURDLE (forced fumble)", cnt(AthleteState.Status.HURDLE, Vector2(0, -1.2), Vector2(0, 1), 0.0, run, 1.0, true)])
	s.fumble_roll = 1.0
	print("%-46s %s" % ["plain clean tackle, no fumble chance", cnt(0, Vector2(0, -1.2), Vector2(0, 1), 0.0, 0.0, 1.0, true)])
	s.fumble_roll = -1.0
	print()
	print("%-46s %s" % ["spin pop + fumble recovery", "result"])
	print("%-46s %s" % ["spin, hold RIGHT, then pop", spin_pop(Vector2(1, 0))])
	print("%-46s %s" % ["spin, hold LEFT, then pop", spin_pop(Vector2(-1, 0))])
	print("%-46s %s" % ["spin, no stick, then pop", spin_pop(Vector2.ZERO)])
	print("%-46s %s" % ["fumble recovered by a nearby player", fumble_recovery()])
	print("%-46s %s" % ["HURDLE vs a tackler on their feet", cnt(AthleteState.Status.HURDLE, Vector2(0, -1.2), Vector2(0, 1), 0.0, run, 1.0)])
	print("%-46s %s" % ["HURDLE vs a dive", hurdle_dive()])
	print("%-46s %s" % ["counter cooldown (spin then truck at once)", counter_cd()])
	get_tree().quit()


## Carrier uses a counter, then the tackler presses tackle.
func cnt(kind: int, tp: Vector2, th: Vector2, tspeed: float, cspeed: float, stamina: float, all_events := false) -> String:
	reset(tp, th, tspeed, cspeed)
	var c: AthleteState = s.sv_players[2].state
	c.stamina = stamina
	var speed_before := c.speed
	s._sv_counter(2, kind)
	var out: Array = []
	var cb := func(x): out.append(x)
	s.event_text.connect(cb)
	if kind == 0:
		s.sv_players[2].state.status = 0
	s._sv_tackle(3)
	s.event_text.disconnect(cb)
	var shown: String = (" | ".join(out) if all_events else (out[0] if out.size() > 0 else "(none)"))
	shown = shown.replace("(player 3 ", "(")
	return "%s -> ball %s%s" % [shown, ["loose", "held", "flight"][s.ball_kind], " (LIVE)" if s.ball_live else ""]


func spin_pop(stick: Vector2) -> String:
	reset(Vector2(0, -9), Vector2(0, 1), 0.0, 7.0)
	var a: AthleteState = s.sv_players[2].state
	s._sv_counter(2, AthleteState.Status.SPIN)
	var start := a.pos
	var dt := 1.0 / 30.0
	var trace := ""
	for i in 20:
		Movement.step(a, stick, false, dt, Tuning.data)
		if i == 4 or i == 12 or i == 19:
			trace += " | t=%.2fs %s heading (%.2f, %.2f) speed %.1f" % [(i + 1) * dt, ["ok", "stumble", "down", "diving", "spin", "truck", "hurdle", "pop"][a.status], a.heading.x, a.heading.y, a.speed]
	return "moved (%.1f, %.1f)%s" % [a.pos.x - start.x, a.pos.y - start.y, trace]


func fumble_recovery() -> String:
	reset(Vector2(0, -1.2), Vector2(0, 1), 8.75, 7.0)
	s.fumble_roll = 0.0
	s.sv_players[2].state.status = AthleteState.Status.SPIN
	s.sv_players[2].state.status_timer = 0.3
	s._sv_tackle(3)
	s.fumble_roll = -1.0
	var line := ""
	for i in 40:
		s._host_tick(1.0 / 30.0)
		if s.ball_kind != NetSession.Ball.LOOSE:
			line = "recovered after %d ticks by player %d" % [i + 1, s.ball_holder]
			break
	if line == "":
		line = "ball popped free to (%.1f, %.1f), untouched while players stood off" % [s.ball_loose.x, s.ball_loose.z]
		s.sv_players[3].state.pos = Vector2(s.ball_loose.x + 0.5, s.ball_loose.z)    # a player runs onto it
		s.sv_players[3].state.speed = 0.0
		s._host_tick(1.0 / 30.0)
		line += "; then player %d walked up: %s" % [3, "picked it up" if s.ball_kind == NetSession.Ball.HELD and s.ball_holder == 3 else "NOT picked up"]
	return line


func hurdle_dive() -> String:
	reset(Vector2(0, -2.5), Vector2(0, 1), 7.0, 0.0)
	s.sv_players[2].state.speed = 7.0
	s._sv_counter(2, AthleteState.Status.HURDLE)
	s._sv_dive(3)
	var out: Array = []
	s.event_text.connect(func(x): out.append(x), CONNECT_ONE_SHOT)
	for i in 20:
		s._host_tick(1.0 / 30.0)
	return "%s" % (out[0] if out.size() > 0 else "(no event)")


func counter_cd() -> String:
	reset(Vector2(0, -5), Vector2(0, 1), 0.0, 7.0)
	s._sv_counter(2, AthleteState.Status.SPIN)
	var after_first: int = s.sv_players[2].state.status
	s.sv_players[2].state.status = 0     # pretend the spin ended at once
	s._sv_counter(2, AthleteState.Status.TRUCK)
	return "second counter ignored while cooling down: %s" % (s.sv_players[2].state.status == 0)


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


func st(tp: Vector2, th: Vector2, tspeed: float, cspeed: float, stamina: float, timed: bool, juke := 0.0) -> String:
	reset(tp, th, tspeed, cspeed)
	s.sv_players[2].state.juke_timer = juke
	var c: AthleteState = s.sv_players[2].state
	c.stamina = stamina
	s._sv_stiffarm(2)
	if not timed:
		s.sv_players[2].stiff_timer = 0.0     # window not open when contact happens
	var out: Array = []
	s.event_text.connect(func(x): out.append(x), CONNECT_ONE_SHOT)
	s._sv_tackle(3)
	return "%s -> carrier %s" % [out[0] if out.size() > 0 else "(none)", ["ok", "stumble", "down", "diving", "spin", "truck", "hurdle"][c.status]]


func stiff_twice() -> String:
	reset(Vector2(0, -5), Vector2(0, 1), 0.0, 7.0)
	s._sv_stiffarm(2)
	var cost1: float = 1.0 - s.sv_players[2].state.stamina
	s._sv_stiffarm(2)
	var cost2: float = 1.0 - s.sv_players[2].state.stamina
	return "stamina spent after press 1: %.2f, after press 2: %.2f (second ignored: %s)" % [cost1, cost2, is_equal_approx(cost1, cost2)]


func dive(tp: Vector2, th: Vector2, hits: bool, juke := 0.0) -> String:
	reset(tp, th, 7.0, 0.0)     # carrier standing still so the dive can reach
	s.sv_players[2].state.juke_timer = juke
	var d: AthleteState = s.sv_players[3].state
	var c: AthleteState = s.sv_players[2].state
	s._sv_dive(3)
	var out: Array = []
	s.event_text.connect(func(x): out.append(x), CONNECT_ONE_SHOT)
	var trace := ""
	for i in 60:
		s._host_tick(1.0 / 30.0)
		if i == 5 or i == 20 or i == 45:
			trace += " | t=%.1fs diver %s" % [(i + 1) / 30.0, ["ok", "stumble", "down", "diving", "spin", "truck", "hurdle"][d.status]]
	return "%s -> carrier %s%s" % [out[0] if out.size() > 0 else "(no hit)", ["ok", "stumble", "down", "diving", "spin", "truck", "hurdle"][c.status], trace]


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
	var carrier_state: String = ["ok", "stumble", "down", "diving", "spin", "truck", "hurdle"][c.status]
	return "%s -> carrier %s, ball %s" % [res, carrier_state, ["loose", "held", "flight"][s.ball_kind]]


func flick(stamina: float) -> String:
	var a := AthleteState.new()
	a.speed = 7.0
	a.heading = Vector2(0, -1)
	a.prev_dir = Vector2(0, -1)
	a.stamina = stamina
	Movement.step(a, Vector2(1, 0), false, 1.0 / 30.0, Tuning.data)
	return "cut=%s speed %.1f juke window %.2fs stamina %.2f" % [a.cut_timer > 0.0, a.speed, a.juke_timer, a.stamina]
