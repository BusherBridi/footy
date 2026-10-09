class_name ThrowAccuracy
extends RefCounted
## How far from the aim point a pass can land. The ball lands somewhere inside a circle
## around the target; the circle grows with the throw's length and with pressure,
## throwing on the run, low stamina and throwing across your body, and shrinks with set
## feet. The server rolls the spot; the QB's screen draws the same circle (approximately:
## it uses the positions it can see).


## Returns {"radius": metres, "why": "pressure +1.2 m, on the run +0.6 m, set feet x0.6"}.
static func spread(st: AthleteState, dir: Vector2, dist: float, opp_positions: Array, t: Dictionary) -> Dictionary:
	var a: Dictionary = t["accuracy"]
	if not a.get("enabled", true):
		return {"radius": 0.0, "why": "accuracy off"}
	var m: Dictionary = t["movement"]
	var parts: Array[String] = []
	var frac: float = a["base"]
	var nearest := INF
	for p in opp_positions:
		nearest = minf(nearest, st.pos.distance_to(p))
	if nearest < float(a["pressure_radius_m"]):
		var pr: float = float(a["pressure"]) * (1.0 - nearest / float(a["pressure_radius_m"]))
		frac += pr
		parts.append("pressure +%.1f m" % (pr * dist))
	var run: float = float(a["on_the_run"]) * clampf(st.speed / (float(m["run_speed"]) * float(m["sprint_multiplier"])), 0.0, 1.0)
	if run * dist > 0.05:
		frac += run
		parts.append("on the run +%.1f m" % (run * dist))
	var tired: float = float(a["tired"]) * (1.0 - clampf(st.stamina, 0.0, 1.0))
	if tired * dist > 0.05:
		frac += tired
		parts.append("tired +%.1f m" % (tired * dist))
	# Across the body only counts on the move (rolling one way, throwing the other); standing,
	# you square up before you throw.
	var moving := st.speed >= float(a["set_feet_speed"])
	if moving and dir != Vector2.ZERO and rad_to_deg(absf(st.heading.angle_to(dir))) > float(a["across_deg"]):
		frac += float(a["across_body"])
		parts.append("across your body +%.1f m" % (float(a["across_body"]) * dist))
	if st.speed < float(a["set_feet_speed"]):
		frac *= float(a["set_feet_mult"])
		parts.append("set feet x%.1f" % float(a["set_feet_mult"]))
	var r := clampf(dist * frac, float(a["min_m"]), float(a["max_m"]))
	return {"radius": r, "why": ", ".join(parts) if not parts.is_empty() else "clean"}


## The charge that throws the same arc (yaw, lob, angle) a given distance. Range grows with
## charge in both throw models, so a bisection finds it.
static func charge_for(p0: Vector3, yaw: float, lob: bool, angle: float, dist: float, t: Dictionary) -> float:
	var lo := 0.0
	var hi := 1.0
	for i in 16:
		var mid := (lo + hi) * 0.5
		var land: Vector3 = BallFlight.launch(p0, yaw, mid, lob, t, angle)["land"]
		if Vector2(land.x - p0.x, land.z - p0.z).length() < dist:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5
