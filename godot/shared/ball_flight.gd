class_name BallFlight
extends RefCounted
## A throw is just launch point, aim yaw, charge and pass type. Every machine
## turns those into the same parabola, so only the launch needs to be synced.


## Returns {v0: Vector3, T: float, land: Vector3, g: float}. T is the time to reach the ground.
## angle < 0 uses the old model (charge = distance, lob picks the arc). angle >= 0 is the
## angle-and-power throw: pitch sets the launch angle (radians) and charge sets the speed.
static func launch(p0: Vector3, yaw: float, charge: float, lob: bool, tuning: Dictionary, angle := -1.0) -> Dictionary:
	if angle >= 0.0:
		return _launch_power(p0, yaw, angle, charge, tuning)
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
		"g": g,
	}


static func _launch_power(p0: Vector3, yaw: float, angle: float, power: float, tuning: Dictionary) -> Dictionary:
	var t: Dictionary = tuning["throw"]
	var g: float = t["power_gravity"]
	var v := lerpf(t["power_speed_min"], t["power_speed_max"], clampf(power, 0.0, 1.0))
	var a := clampf(angle, deg_to_rad(t["angle_min_deg"]), deg_to_rad(t["angle_max_deg"]))
	var vy := v * sin(a)
	var vh := v * cos(a)
	var y1: float = t["ball_radius"]
	var T := (vy + sqrt(vy * vy + 2.0 * g * (p0.y - y1))) / g
	var dir := Vector2(-sin(yaw), -cos(yaw))
	return {
		"v0": Vector3(dir.x * vh, vy, dir.y * vh),
		"T": T,
		"land": Vector3(p0.x + dir.x * vh * T, y1, p0.z + dir.y * vh * T),
		"g": g,
	}


static func position_at(p0: Vector3, fl: Dictionary, g: float, time: float) -> Vector3:
	var tt := clampf(time, 0.0, fl["T"])
	var gg: float = fl.get("g", g)
	return p0 + fl["v0"] * tt - Vector3(0.0, 0.5 * gg * tt * tt, 0.0)


## Sampled flight path for the aim preview.
static func arc_points(p0: Vector3, yaw: float, charge: float, lob: bool, tuning: Dictionary, angle := -1.0) -> PackedVector3Array:
	var fl := launch(p0, yaw, charge, lob, tuning, angle)
	var pts := PackedVector3Array()
	var n: int = int(tuning["throw"]["arc_points"])
	for i in n + 1:
		pts.append(position_at(p0, fl, tuning["throw"]["gravity"], fl["T"] * i / float(n)))
	return pts
