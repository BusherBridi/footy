extends Node
## Sprinting carrier vs chaser bot, head-on, many trials. Run headless:
##   godot --headless --path godot res://tests/headon_test.tscn
var s: NetSession
var events: Array = []


func _ready():
	var root3d := Node3D.new()
	add_child(root3d)
	s = NetSession.new()
	s.athlete_parent = root3d
	add_child(s)
	s.start_host(7792)
	s.event_text.connect(func(x): events.append(x))
	s.input_provider = func(): return {"move": Vector2(0, -1), "sprint": true}
	for label in ["chaser sprinting (full stamina)", "chaser jogging (stamina empty)"]:
		var counts := {}
		for trial in 40:
			var res := run_trial(trial, label.contains("jogging"))
			counts[res] = counts.get(res, 0) + 1
		print("%-34s %s" % [label, counts])
	get_tree().quit()


func run_trial(trial: int, tired: bool) -> String:
	for id in s.sv_bots.keys():
		s.sv_players.erase(id)
	s.sv_bots.clear()
	s.host_add_bot("chase")
	var bid: int = s.sv_bots.keys()[0]
	var me: NetSession.SvPlayer = s.sv_players[1]
	me.state = AthleteState.new()
	me.state.pos = Vector2(0, 14)
	me.state.heading = Vector2(0, -1)
	me.state.speed = 8.75
	me.prev_pos = me.state.pos
	me.tackle_cd = 0.0
	var b: NetSession.SvPlayer = s.sv_players[bid]
	b.state.pos = Vector2((trial % 5 - 2) * 0.4, 0.0)      # lateral offsets -0.8 .. 0.8
	b.state.heading = Vector2(0, 1)
	b.state.speed = 0.0
	b.state.stamina = 0.0 if tired else 1.0
	s.ball_kind = NetSession.Ball.HELD
	s.ball_holder = 1
	events.clear()
	for i in 200:
		var pre_dist: float = b.state.pos.distance_to(me.state.pos)
		var pre_ang: float = rad_to_deg(absf(b.state.heading.angle_to(me.state.pos - b.state.pos)))
		var pre_status: int = b.state.status
		s._host_tick(1.0 / 30.0)
		if events.size() > 0:
			var e: String = events[0]
			if e.contains("whiffed"):
				if trial < 6:
					print("   whiff: dist %.2f m, angle %.0f deg, bot status %d, carrier speed %.1f, bot speed %.1f" % [pre_dist, pre_ang, pre_status, me.state.speed, b.state.speed])
				return "WHIFF"
			if e.begins_with("BIG"):
				return "BIG HIT"
			if e.begins_with("BROKEN"):
				return "BROKEN"
			return e.split(" ")[0]
	return "no tackle attempted"
