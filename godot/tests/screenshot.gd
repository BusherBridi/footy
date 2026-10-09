extends Node
## Renders the game for a moment and saves a screenshot (needs a display, e.g. xvfb-run).
##   godot --path godot --rendering-driver opengl3 res://tests/screenshot.tscn -- --shot=/path/out.png [--wait=1.5] [--match --autoplay] [--card] [--pause] [--coach] [--look=NAME] [--looks: one frozen moment in every look, 2x2]

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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):
			main.look.apply(a.trim_prefix("--look="))
	if OS.get_cmdline_user_args().has("--looks"):
		await _look_sheet(main, out)
		get_tree().quit()
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()


## Freeze the match and render the same moment in each look, tiled into one image.
func _look_sheet(main: Node, out: String) -> void:
	main.session.paused = true
	var shots: Array[Image] = []
	for n in main.look.names():
		main.look.apply(n)
		main.event_label.text = main.look.label(n)
		main._event_time = 99.0
		for i in 3:
			await RenderingServer.frame_post_draw
		shots.append(get_viewport().get_texture().get_image())
	var w := shots[0].get_width() / 2
	var h := shots[0].get_height() / 2
	var cols := 2
	var rows := int(ceil(shots.size() / 2.0))
	var sheet := Image.create(w * cols, h * rows, false, shots[0].get_format())
	for i in shots.size():
		var img := shots[i]
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out)
	print("saved ", out)
