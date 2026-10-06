extends Node
## Server-side catch checks with scripted players. Run headless:
##   godot --headless --path godot res://tests/catch_test.tscn
var s: NetSession


func _ready():
	var root3d := Node3D.new()
	add_child(root3d)
	s = NetSession.new()
	s.athlete_parent = root3d
	add_child(s)
	s.start_host(7790)
	var dt = 1.0 / 30.0
	var land = Vector3(0, 0, 15.0 - 28.0)   # charge 0.5 bullet from z=15 lands ~28 m downfield
	# case 1: lone receiver 0.5 m from the landing spot, standing
	print("1 standing, 0.5m off:   ", run([[2, Vector2(0.5, land.z), 0.0]]))
	# case 2: receiver sprinting, 1.0 m off -> zone shrunk to 0.9 m: no catch
	print("2 sprinting, 1.0m off:  ", run([[2, Vector2(1.0, land.z), 8.75]]))
	# case 3: same distance but standing -> catch
	print("3 standing, 1.0m off:   ", run([[2, Vector2(1.0, land.z), 0.0]]))
	# case 4: two receivers, one clearly closer
	print("4 closer wins:          ", run([[2, Vector2(0.9, land.z), 0.0], [3, Vector2(-0.3, land.z), 0.0]]))
	# case 5: exact tie
	print("5 tie:                  ", run([[2, Vector2(0.6, land.z), 0.0], [3, Vector2(-0.6, land.z), 0.0]]))
	# case 6: nobody there
	print("6 nobody:               ", run([]))
	# case 7: the thrower stands under their own pass at a short range (charge from low), within grace
	print("7 thrower grace:        ", run([], 0.0))
	get_tree().quit()


func run(others: Array, charge := 0.5) -> String:
	for id in s.sv_players.keys():
		if id != 1: s.sv_players.erase(id)
	s.sv_players[1].state.pos = Vector2(0, 15)
	s.sv_players[1].state.speed = 0.0
	for o in others:
		s._add_sv_player(o[0])
		s.sv_players[o[0]].state.pos = o[1]
		s.sv_players[o[0]].state.speed = o[2]
	s._sv_take(1)
	s._sv_throw(1, charge, 0.0, false)
	var dt = 1.0 / 30.0
	var n := 0
	for i in 200:
		n += 1
		s.sv_tick += 1
		s._ball_tick(dt)
		if s.ball_kind != NetSession.Ball.FLIGHT:
			break
	return "%s holder=%d after %d ticks" % [["loose", "held", "flight"][s.ball_kind], s.ball_holder, n]
