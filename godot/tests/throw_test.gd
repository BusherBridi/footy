extends Node
## Prints landing distance for angle/power combinations. Run headless:
##   godot --headless --path godot res://tests/throw_test.tscn


func _ready():
	var t: Dictionary = Tuning.data
	print("range in metres from release height (rows: launch angle, columns: power 0 / 25 / 50 / 75 / 100 %)")
	for deg in [3, 5, 10, 20, 30, 45, 55]:
		var row := "angle %2d deg:" % deg
		for pw in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var fl := BallFlight.launch(Vector3(0, 1.8, 0), 0.0, pw, false, t, deg_to_rad(deg))
			row += "  %5.1f m (%.2fs)" % [-fl["land"].z, fl["T"]]
		print(row)
	get_tree().quit()
