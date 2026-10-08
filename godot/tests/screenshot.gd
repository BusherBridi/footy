extends Node
## Renders the game for a moment and saves a screenshot (needs a display, e.g. xvfb-run).
##   godot --path godot --rendering-driver opengl3 res://tests/screenshot.tscn -- --shot=/path/out.png [--wait=1.5] [--match --autoplay]

func _ready() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	add_child(main)
	var out := "user://shot.png"
	var wait := 1.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			out = a.trim_prefix("--shot=")
		elif a.begins_with("--wait="):
			wait = float(a.trim_prefix("--wait="))
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
