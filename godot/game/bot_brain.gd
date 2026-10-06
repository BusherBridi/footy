class_name BotBrain
extends RefCounted
## Dev-only test driver: wanders the field with random sprints and sharp turns.
## It feeds the normal input path, so a bot is just a client with no human.

var target := Vector2.ZERO
var timer := 0.0
var sprint := false
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


## Returns [world-plane move Vector2, sprint bool].
func think(pos: Vector2, dt: float, field: Dictionary) -> Array:
	timer -= dt
	var to := target - pos
	if timer <= 0.0 or to.length() < 2.0:
		var yard: float = field["yard_m"]
		var hw: float = field["width_yards"] * 0.5 * yard - 2.0
		var hl: float = field["length_yards"] * 0.5 * yard - 2.0
		target = Vector2(rng.randf_range(-hw, hw), rng.randf_range(-hl, hl))
		timer = rng.randf_range(1.5, 4.0)
		sprint = rng.randf() < 0.5
		to = target - pos
	return [to.normalized(), sprint and to.length() > 6.0]
