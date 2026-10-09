extends Node
## Throw accuracy circle and the pump fake. Run headless:
##   godot --headless --path godot res://tests/accuracy_test.tscn


func _ready():
	var t := Tuning.data
	print("%-52s %s" % ["situation (25 m throw straight ahead)", "circle radius"])
	var none: Array = []
	print("%-52s %s" % ["set feet, fresh, nobody near", _r(0.0, 1.0, none, Vector2(0, -1))])
	print("%-52s %s" % ["jogging (5 m/s)", _r(5.0, 1.0, none, Vector2(0, -1))])
	print("%-52s %s" % ["sprinting (8.75 m/s)", _r(8.75, 1.0, none, Vector2(0, -1))])
	print("%-52s %s" % ["set feet, rusher 1.5 m away", _r(0.0, 1.0, [Vector2(1.5, 0)], Vector2(0, -1))])
	print("%-52s %s" % ["set feet, empty stamina", _r(0.0, 0.0, none, Vector2(0, -1))])
	print("%-52s %s" % ["jogging, throwing back across the body", _r(5.0, 1.0, none, Vector2(0, 1))])
	print("%-52s %s" % ["sprinting, rusher 1 m away, half stamina", _r(8.75, 0.5, [Vector2(1, 0)], Vector2(0, -1))])

	# The server roll: 200 throws, all inside the circle, spread over it.
	var root3d := Node3D.new()
	add_child(root3d)
	var s := NetSession.new()
	s.athlete_parent = root3d
	add_child(s)
	s.start_host(7799)
	s.set_physics_process(false)
	s.set_process(false)
	var me: NetSession.SvPlayer = s.sv_players[1]
	me.state.speed = 5.0
	var p0 := Vector3(0, float(t["throw"]["release_height"]), 0)
	var aim_charge := ThrowAccuracy.charge_for(p0, 0.0, false, deg_to_rad(15.0), 25.0, t)
	var aim: Vector3 = BallFlight.launch(p0, 0.0, aim_charge, false, t, deg_to_rad(15.0))["land"]
	var r: float = ThrowAccuracy.spread(me.state, Vector2(0, -1), 25.0, [], t)["radius"]
	var worst := 0.0
	var total := 0.0
	for i in 200:
		s.ball_kind = NetSession.Ball.HELD
		s.ball_holder = 1
		me.state.pos = Vector2.ZERO
		s._sv_throw(1, aim_charge, 0.0, false, deg_to_rad(15.0))
		var land: Vector3 = BallFlight.launch(s.ball_p0, s.ball_yaw, s.ball_charge, false, t, s.ball_angle)["land"]
		var off := Vector2(land.x - aim.x, land.z - aim.z).length()
		worst = maxf(worst, off)
		total += off
	print("%-52s %s" % ["200 jogging 25 m throws (circle %.2f m)" % r, "farthest %.2f m off, average %.2f m" % [worst, total / 200.0]])

	# Pump fake.
	s.ball_kind = NetSession.Ball.HELD
	s.ball_holder = 1
	s._sv_pump(1, 0.0)
	print("%-52s %s" % ["pump fake with the ball", "arm fx %d, pump #%d, ball still held: %s" % [me.fx, s.pump_id, str(s.ball_kind == NetSession.Ball.HELD)]])
	s._sv_pump(1, 0.0)
	print("%-52s %s" % ["pump again at once (cooldown)", "pump #%d" % s.pump_id])
	s.ball_holder = 0
	me.pump_cd = 0.0
	s._sv_pump(1, 0.0)
	print("%-52s %s" % ["pump without the ball", "pump #%d (ignored)" % s.pump_id])

	# A bot corner in the fake's path bites (with bite chance forced to 1).
	var bot := TeamBot.new()
	var ai: Dictionary = t["ai"].duplicate()
	ai["pump_bite_chance"] = 1.0
	var ctx := {"pump_id": 7, "pump_age": 0.05, "pump_from": Vector2(0, 0), "pump_dir": Vector2(0, -1), "pos": Vector2(1.0, -15.0)}
	var out := {}
	var bit := bot._bitten(out, ctx, ai)
	print("%-52s %s" % ["corner 15 m downfield, right in the fake's line", "bites: %s, breaks toward (%.1f, %.1f)" % [str(bit), bot._bite_to.x, bot._bite_to.y]])
	var bot2 := TeamBot.new()
	ctx["pos"] = Vector2(12.0, -10.0)
	print("%-52s %s" % ["corner way off to the side", "bites: %s" % str(bot2._bitten({}, ctx, ai))])
	get_tree().quit()


func _r(speed: float, stamina: float, opps: Array, dir: Vector2) -> String:
	var st := AthleteState.new()
	st.heading = Vector2(0, -1)
	st.speed = speed
	st.stamina = stamina
	var sp := ThrowAccuracy.spread(st, dir, 25.0, opps, Tuning.data)
	return "%.2f m  (%s)" % [sp["radius"], sp["why"]]
