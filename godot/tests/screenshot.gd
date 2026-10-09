extends Node
## Renders the game for a moment and saves a screenshot (needs a display, e.g. xvfb-run).
##   godot --path godot --rendering-driver opengl3 res://tests/screenshot.tscn -- --shot=/path/out.png [--wait=1.5] [--match --autoplay] [--card] [--pause] [--coach]

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
		elif a == "--card":
			main.card.visible = true
	await get_tree().create_timer(wait).timeout
	if OS.get_cmdline_user_args().has("--pause"):
		main._set_paused(true)
	if OS.get_cmdline_user_args().has("--coach"):
		main.session.coach_text.emit("Swat, not a pick (0.06 s early): reached 0.24 s before the ball (pick window 0.06-0.18 s)")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
