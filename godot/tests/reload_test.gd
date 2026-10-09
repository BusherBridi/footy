extends Node
## Restart match and Back to title reload the scene; the match must come back up cleanly.
##   godot --headless --path godot res://tests/reload_test.tscn
static var round := 0


func _ready():
	var m: Node = load("res://game/main.tscn").instantiate()
	add_child(m)
	round += 1
	if round == 1:
		m._host_match()
	await get_tree().create_timer(1.0).timeout
	var s: NetSession = m.session
	print("round %d: mode %s, match %s, players %d, title menu %s, play %s" % [round,
		["NONE", "HOST", "CLIENT"][s.mode], str(s.flow != null), s.sv_players.size(), str(m.menu.visible),
		str(s.get_play_view().get("play_no", "-"))])
	match round:
		1: m._reload("match")
		2: m._reload("title")
		_: get_tree().quit()
