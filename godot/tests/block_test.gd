extends Node
## Blocking: shove, pancake, sustained block, drive, shed timing, spin out. Run headless:
##   godot --headless --path godot res://tests/block_test.tscn
var s: NetSession
var coach: Array = []
var R := 0          # offensive blocker (a receiver)
var D := 0          # defender
const DT := 1.0 / 30.0


func _ready():
	var root3d := Node3D.new()
	add_child(root3d)
	s = NetSession.new()
	s.athlete_parent = root3d
	add_child(s)
	s.start_host(7797)
	s.set_physics_process(false)
	s.set_process(false)
	s.start_match()
	s.sv_bots.clear()               # nobody thinks: the test moves everyone
	s.local_id = 999                # send every coach line through the log hook below
	s.coach_text.connect(func(t): coach.append(t))
	print("%-52s %s" % ["case", "result"])
	print("%-52s %s" % ["standing blocker, standing defender", _shove({})])
	print("%-52s %s" % ["blocker at 7 m/s, standing defender", _shove({"b_speed": 7.0})])
	print("%-52s %s" % ["blocker at 7 m/s, defender anchored in stance", _shove({"b_speed": 7.0, "d_stance": true})])
	print("%-52s %s" % ["set-feet blocker (stance), defender jogging at them", _shove({"b_stance": true, "d_speed": 7.0})])
	print("%-52s %s" % ["blocker comes from behind the defender", _shove({"behind": true})])
	print("%-52s %s" % ["defense tries to block (offense has the ball)", _shove({"defense": true})])
	print("%-52s %s" % ["hold 2 s (max 1.5 s)", _hold(2.0, Vector2.ZERO)])
	print("%-52s %s" % ["tap: let go after 0.1 s", _hold(0.1, Vector2.ZERO)])
	print("%-52s %s" % ["hold 1 s and drive forward", _hold(1.0, Vector2(0, 1))])
	print("%-52s %s" % ["shed 0.1 s in (early)", _shed([0.1])])
	print("%-52s %s" % ["shed 0.1 s in, then 0.4 s after that", _shed([0.1, 0.4])])
	print("%-52s %s" % ["shed 0.4 s in", _shed([0.4])])
	print("%-52s %s" % ["spin out", _spin_out()])
	print("%-52s %s" % ["blocked defender presses tackle on the carrier", _blocked_tackle()])
	get_tree().quit()


## Snap, then put the receiver 1 m from a defender facing each other near the line.
func _setup(o: Dictionary) -> void:
	var f := s.flow
	f.offense = 0
	f._setup_play()
	f.phase_time = 1.0
	s._sv_take(f.qb_id)
	R = f.slots[f.offense][1]
	D = f.slots[1 - f.offense][1]
	for id in s.sv_players:
		var p: NetSession.SvPlayer = s.sv_players[id]
		p.last_move = Vector2.ZERO
		p.last_block = false
		p.last_stance = false
		p.block_prev = false
		p.state.status = AthleteState.Status.OK
		if id != R and id != D and id != f.qb_id:
			p.state.pos = Vector2(12, 0)
	var r: NetSession.SvPlayer = s.sv_players[R]
	var d: NetSession.SvPlayer = s.sv_players[D]
	r.state.pos = Vector2(0, 0)
	r.state.heading = Vector2(0, -1)
	r.state.speed = float(o.get("b_speed", 0.0))
	d.state.pos = Vector2(0, -1.0)
	d.state.heading = Vector2(0, -1) if o.get("behind", false) else Vector2(0, 1)
	d.state.speed = float(o.get("d_speed", 0.0))
	if o.get("b_stance", false):
		r.state.stance_dir = Vector2(0, -1)
	if o.get("d_stance", false):
		d.state.stance_dir = d.state.heading
	coach.clear()


func _shove(o: Dictionary) -> String:
	_setup(o)
	var who := D if o.get("defense", false) else R
	if o.get("defense", false):
		# Swap: the defender (blue) faces the receiver and presses block.
		s.sv_players[D].state.heading = Vector2(0, 1)
	s.sv_players[who].last_block = true
	s._block_tick(DT)
	var r: NetSession.SvPlayer = s.sv_players[R]
	var d: NetSession.SvPlayer = s.sv_players[D]
	var st := ["ok", "STUMBLE", "DOWN", "DIVE", "SPIN", "TRUCK", "HURDLE", "POP", "WRAPPED", "HOLDING", "SET", "BLOCKED", "BLOCKING"]
	return "blocker %s, defender %s%s" % [st[r.state.status], st[d.state.status], ("  [" + " | ".join(coach) + "]") if not coach.is_empty() else ""]


func _tick(secs: float) -> void:
	for i in int(round(secs / DT)):
		s._host_tick(DT)


func _hold(secs: float, stick: Vector2) -> String:
	_setup({})
	var r: NetSession.SvPlayer = s.sv_players[R]
	var d: NetSession.SvPlayer = s.sv_players[D]
	var start_d := d.state.pos
	var stam := r.state.stamina
	r.last_block = true
	r.last_move = -stick if stick != Vector2.ZERO else Vector2.ZERO     # "forward" = toward the defender (-z)
	var held := 0.0
	for i in int(round(secs / DT)):
		s._host_tick(DT)
		if d.state.status == AthleteState.Status.BLOCKED:
			held += DT
	r.last_block = false
	s._host_tick(DT)
	return "locked %.2f s, defender moved %.1f m, blocker stamina %d%% -> %d%%, now %s" % [held, start_d.distance_to(d.state.pos),
		int(stam * 100.0), int(r.state.stamina * 100.0), "free" if d.state.status != AthleteState.Status.BLOCKED else "still blocked"]


func _shed(presses: Array) -> String:
	_setup({})
	var r: NetSession.SvPlayer = s.sv_players[R]
	var d: NetSession.SvPlayer = s.sv_players[D]
	r.last_block = true
	s._host_tick(DT)
	var out: Array[String] = []
	for wait in presses:
		_tick(float(wait))
		s._sv_tackle(D)
		out.append("%s" % ("FREE" if d.state.status != AthleteState.Status.BLOCKED else "blocked"))
	return "%s, blocker %s  [%s]" % [" -> ".join(out), "stumbling" if r.state.status == AthleteState.Status.STUMBLE else "ok/blocking",
		coach.filter(func(c): return c.begins_with("Shed")).back() if coach.any(func(c): return c.begins_with("Shed")) else ""]


func _spin_out() -> String:
	_setup({})
	var r: NetSession.SvPlayer = s.sv_players[R]
	var d: NetSession.SvPlayer = s.sv_players[D]
	r.last_block = true
	s._host_tick(DT)
	var stam := d.state.stamina
	s._sv_swat(D, float(s.sv_tick))
	return "defender %s, stamina %d%% -> %d%%" % ["free (staggered)" if d.state.status == AthleteState.Status.STUMBLE else "status %d" % d.state.status,
		int(stam * 100.0), int(d.state.stamina * 100.0)]


func _blocked_tackle() -> String:
	_setup({})
	var r: NetSession.SvPlayer = s.sv_players[R]
	var d: NetSession.SvPlayer = s.sv_players[D]
	r.last_block = true
	s._host_tick(DT)
	s.sv_players[s.flow.qb_id].state.pos = d.state.pos + Vector2(0.8, 0)
	var holder := s.ball_holder
	s._sv_tackle(D)
	return "ball still held by the QB: %s, defender %s" % [str(s.ball_holder == holder and s.ball_kind == NetSession.Ball.HELD),
		"blocked" if d.state.status == AthleteState.Status.BLOCKED else "free"]
