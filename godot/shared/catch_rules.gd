class_name CatchRules
extends RefCounted
## Catch zone maths shared by the server (to decide catches) and the visuals
## (to draw the ring). Deterministic: no dice, so every screen agrees.


## Sprinting shrinks the zone. Speed is used instead of an input flag so it works
## for any player seen in a snapshot.
static func radius_for(speed: float, tuning: Dictionary) -> float:
	var c: Dictionary = tuning["catch"]
	var r: float = c["radius"]
	if speed > float(tuning["movement"]["run_speed"]) * float(c["sprint_speed_factor"]):
		r *= float(c["sprint_radius_mult"])
	return r


## Distance from the player to the ball if the ball is inside their catch zone, else -1.
static func zone_distance(player_pos: Vector2, speed: float, ball: Vector3, tuning: Dictionary) -> float:
	var c: Dictionary = tuning["catch"]
	if ball.y < float(c["min_height"]) or ball.y > float(c["max_height"]):
		return -1.0
	var d := player_pos.distance_to(Vector2(ball.x, ball.z))
	return d if d <= radius_for(speed, tuning) else -1.0
