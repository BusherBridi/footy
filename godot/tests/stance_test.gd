extends Node
## Stance: locked facing, speeds by direction, no sprint, hip flip on release. Run headless:
##   godot --headless --path godot res://tests/stance_test.tscn
const DT := 1.0 / 30.0


func _ready():
	var run: float = Tuning.section("movement")["run_speed"]
	print("%-46s %s" % ["case (facing -z, run speed %.1f m/s)" % run, "result"])
	for c in [["backpedal (+z)", Vector2(0, 1)], ["shuffle sideways", Vector2(1, 0)], ["forward", Vector2(0, -1)],
			["diagonal back", Vector2(1, 1).normalized()]]:
		var a := _fresh()
		_run(a, c[1], true, true, 2.0)
		print("%-46s %s" % [c[0], "speed %.1f m/s (%.0f%% of run), facing (%.2f, %.2f), sprint held" % [a.speed, a.speed / run * 100.0, a.facing().x, a.facing().y]])
	var b := _fresh()
	_run(b, Vector2(0, 1), false, false, 2.0)
	print("%-46s %s" % ["no stance, run backward", "speed %.1f, facing (%.2f, %.2f) (turned round)" % [b.speed, b.facing().x, b.facing().y]])

	# Release while backpedalling: hip flip.
	var f := _fresh()
	_run(f, Vector2(0, 1), false, true, 1.5)
	var line := ""
	var t := 0.0
	for i in 12:
		Movement.step(f, Vector2(0, 1), true, DT, Tuning.data, false)
		t += DT
		if i in [0, 2, 4, 6, 11]:
			line += "t=%.2f speed %.1f facing (%.2f, %.2f) flip %s | " % [t, f.speed, f.facing().x, f.facing().y, "yes" if f.hip_timer > 0.0 else "no"]
	print("%-46s %s" % ["let go while backpedalling, then sprint", line])
	var g := _fresh()
	_run(g, Vector2(0, -1), false, true, 1.5)
	Movement.step(g, Vector2(0, -1), true, DT, Tuning.data, false)
	print("%-46s %s" % ["let go while moving forward", "hip flip: %s" % ("yes" if g.hip_timer > 0.0 else "no")])

	# Turning the stick while in stance doesn't turn the body.
	var h := _fresh()
	_run(h, Vector2(1, 0), false, true, 0.5)
	_run(h, Vector2(-1, 0), false, true, 0.5)
	print("%-46s %s" % ["stance, left then right", "facing (%.2f, %.2f)" % [h.facing().x, h.facing().y]])
	var k := _fresh()
	k.carrying = true
	_run(k, Vector2(0, 1), false, true, 1.0)
	print("%-46s %s" % ["ball carrier holds stance", "ignored: %s" % str(k.stance_dir == Vector2.ZERO)])
	var d := _fresh()
	_run(d, Vector2(0, 1), false, true, 0.5)
	d.status = AthleteState.Status.STUMBLE
	d.status_timer = 0.3
	Movement.step(d, Vector2(0, 1), false, DT, Tuning.data, true)
	print("%-46s %s" % ["knocked off balance in stance", "stance dropped: %s" % str(d.stance_dir == Vector2.ZERO)])
	get_tree().quit()


func _fresh() -> AthleteState:
	var a := AthleteState.new()
	a.heading = Vector2(0, -1)
	return a


func _run(a: AthleteState, stick: Vector2, sprint: bool, stance: bool, secs: float) -> void:
	for i in int(secs / DT):
		Movement.step(a, stick, sprint, DT, Tuning.data, stance)
