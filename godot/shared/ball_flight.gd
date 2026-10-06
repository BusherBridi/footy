class_name BallFlight
extends RefCounted
## A throw is just launch point, aim yaw, charge and pass type. Every machine
## turns those into the same parabola, so only the launch needs to be synced.


## Returns {v0: Vector3, T: float, land: Vector3}. T is the time to reach the ground.
static func launch(p0: Vector3, yaw: float, charge: float, lob: bool, tuning: Dictionary) -> Dictionary:
	var t: Dictionary = tuning["throw"]
	var g: float = t["gravity"]
	var dist := lerpf(t["min_range"], t["max_range"], clampf(charge, 0.0, 1.0))
	var dir := Vector2(-sin(yaw), -cos(yaw))
	var speed: float = t["lob_speed"] if lob else t["bullet_speed"]
	var T := maxf(dist / speed, float(t["min_flight_time"]))
	var y1: float = t["ball_radius"]
	var vy := (y1 - p0.y + 0.5 * g * T * T) / T
	return {
		"v0": Vector3(dir.x * dist / T, vy, dir.y * dist / T),
		"T": T,
		"land": Vector3(p0.x + dir.x * dist, y1, p0.z + dir.y * dist),
	}


static func position_at(p0: Vector3, fl: Dictionary, g: float, time: float) -> Vector3:
	var tt := clampf(time, 0.0, fl["T"])
	return p0 + fl["v0"] * tt - Vector3(0.0, 0.5 * g * tt * tt, 0.0)


## Grenade-style aim: the further up you look, the further the throw.
static func charge_from_pitch(pitch_rad: float, tuning: Dictionary) -> float:
	var t: Dictionary = tuning["throw"]
	var x := inverse_lerp(float(t["aim_pitch_short_deg"]), float(t["aim_pitch_far_deg"]), rad_to_deg(pitch_rad))
	return pow(clampf(x, 0.0, 1.0), float(t["aim_curve"]))


## Sampled flight path for the aim preview.
static func arc_points(p0: Vector3, yaw: float, charge: float, lob: bool, tuning: Dictionary) -> PackedVector3Array:
	var fl := launch(p0, yaw, charge, lob, tuning)
	var pts := PackedVector3Array()
	var n: int = int(tuning["throw"]["arc_points"])
	for i in n + 1:
		pts.append(position_at(p0, fl, tuning["throw"]["gravity"], fl["T"] * i / float(n)))
	return pts


## Where the ball would land for a given charge, for the aim marker.
static func target_for(pos: Vector2, yaw: float, charge: float, tuning: Dictionary) -> Vector2:
	var t: Dictionary = tuning["throw"]
	var dist := lerpf(t["min_range"], t["max_range"], clampf(charge, 0.0, 1.0))
	return pos + Vector2(-sin(yaw), -cos(yaw)) * dist
