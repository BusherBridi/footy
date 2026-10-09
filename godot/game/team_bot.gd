class_name TeamBot
extends RefCounted
## Match AI for one bot. Every tick the play flow hands it a picture of the field (see
## PlayFlow.bot_context) and it returns the same input dictionary a human produces,
## plus "pass_to" for throws. It plays whatever the situation calls for:
##   QB        drops back, reads the receivers, throws to the most open one or scrambles
##   receiver  runs a route, then finds space; runs to the ball when it's thrown to them
##   carrier   runs to daylight and uses stiff arms, jukes, trucks, spins and hurdles
##   defender  man coverage (the linebacker rushes once the timer ends), breaks on the
##             ball, swats or picks passes, pursues and tackles the carrier, joins wraps
##             and goes for strips

var rng := RandomNumberGenerator.new()
var _play := -1
var _snap_delay := 1.5
var _wp: Array = []
var _wp_i := 0
var _hold := 0.0
var _thrown := false
var _scramble := false
var _counter_wait := 0.0
var _juke_left := 0.0
var _juke_dir := Vector2.ZERO
var _dive_roll := -1
var _strip_roll := -1
var _lateral_roll := -1
var _cover_target := Vector2.ZERO
var _cover_timer := 0.0
var _try_decided := false
var _swat_throw := -1            # launch tick of the pass the swat decision below is for
var _swat_go := false
var _swat_lead := 0.0
var _reach_until := -1.0         # flight time until which we keep squared up to the ball


func _init() -> void:
	rng.randomize()


func think(ctx: Dictionary, dt: float, t: Dictionary) -> Dictionary:
	var out := {"move": Vector2.ZERO, "sprint": false}
	if int(ctx["play_no"]) != _play:
		_new_play(ctx, t)
	_counter_wait = maxf(0.0, _counter_wait - dt)
	_juke_left = maxf(0.0, _juke_left - dt)
	_cover_timer -= dt
	var phase := int(ctx["phase"])
	if phase == PlayFlow.Phase.PRE_SNAP:
		if ctx["offense"] and ctx["id"] == ctx["qb_id"]:
			if int(ctx["try_points"]) == 1 and not _try_decided:
				_try_decided = true
				if rng.randf() < float(t["ai"]["two_point_chance"]):
					out["try_pick"] = 2          # go for two
					return out
			if float(ctx["phase_time"]) >= _snap_delay:
				out["take"] = true
		return out
	if phase != PlayFlow.Phase.LIVE:
		return out

	var id: int = ctx["id"]
	var kind: int = ctx["ball_kind"]
	if kind == NetSession.Ball.HELD and int(ctx["ball_holder"]) == id:
		if id == int(ctx["qb_id"]) and not _thrown and not _scramble and _behind_los(ctx):
			_qb(out, ctx, dt, t)
		else:
			_carry(out, ctx, t)
	elif kind == NetSession.Ball.LOOSE and ctx["ball_live"]:
		var to: Vector2 = ctx["ball_loose"] - ctx["pos"]
		out["move"] = to.normalized()
		out["sprint"] = true
	elif kind == NetSession.Ball.FLIGHT:
		_ball_in_air(out, ctx, t)
	elif kind == NetSession.Ball.HELD and ctx.has("carrier"):
		if int(ctx["carrier_team"]) == int(ctx["team"]):
			_support(out, ctx, t)
		else:
			_defend(out, ctx, t)
	return out


func _new_play(ctx: Dictionary, t: Dictionary) -> void:
	_play = int(ctx["play_no"])
	var ai: Dictionary = t["ai"]
	_snap_delay = rng.randf_range(float(ai["snap_delay_min"]), float(ai["snap_delay_max"]))
	_hold = 0.0
	_thrown = false
	_scramble = false
	_dive_roll = -1
	_strip_roll = -1
	_lateral_roll = -1
	_cover_timer = 0.0
	if int(ctx.get("try_points", 0)) == 0:
		_try_decided = false
	_wp.clear()
	_wp_i = 0
	var route: String = ctx["route"]
	var routes: Dictionary = t["bot"]["routes_yards"]
	if route == "" or not routes.has(route):
		return
	# Route offsets are written for a team attacking -z with +x on the right. Turn them
	# to this team's direction, and mirror on the left side so "out" breaks to the sideline.
	var f := -float(ctx["dir"])
	var start: Vector2 = ctx["pos"]
	var mirror := -1.0 if start.x * f < 0.0 else 1.0
	var yard: float = t["field"]["yard_m"]
	for p in routes[route]:
		_wp.append(start + Vector2(float(p[0]) * mirror, float(p[1])) * f * yard)


func _behind_los(ctx: Dictionary) -> bool:
	var pos: Vector2 = ctx["pos"]
	return (pos.y - float(ctx["los_z"])) * float(ctx["dir"]) < 0.0


func _nearest_opp(ctx: Dictionary) -> Dictionary:
	var best := {}
	var bd := INF
	var pos: Vector2 = ctx["pos"]
	for o in ctx["opps"]:
		var d: float = pos.distance_to(o["pos"])
		if d < bd:
			bd = d
			best = o
	if not best.is_empty():
		best["dist"] = bd
	return best


func _separation(p: Vector2, opps: Array) -> float:
	var bd := INF
	for o in opps:
		bd = minf(bd, p.distance_to(o["pos"]))
	return bd


# ------------------------------------------------------------------- QB

func _qb(out: Dictionary, ctx: Dictionary, dt: float, t: Dictionary) -> void:
	var ai: Dictionary = t["ai"]
	var d := float(ctx["dir"])
	var pos: Vector2 = ctx["pos"]
	_hold += dt
	if _hold < 0.6:
		out["move"] = Vector2(0.0, -d)        # drop back
	var los := float(ctx["los_z"])
	var best := {}
	var best_score := -INF
	for m in ctx["mates"]:
		var down: float = (m["pos"].y - los) * d
		if down < 1.0:
			continue
		var sep := _separation(m["pos"], ctx["opps"])
		var score := sep + clampf(down, 0.0, 25.0) * 0.15
		if score > best_score:
			best_score = score
			best = m
			best["sep"] = sep
	var near := _nearest_opp(ctx)
	var pressure: bool = not near.is_empty() and float(near["dist"]) < float(ai["pressure_m"])
	if pressure and _hold >= 0.6:
		out["move"] = (pos - Vector2(near["pos"])).normalized()     # step away from the rusher
	if not best.is_empty() and _hold >= float(ai["qb_min_hold"]):
		var sep: float = best["sep"]
		var go := sep >= float(ai["open_sep_m"])
		go = go or ((pressure or _hold >= float(ai["qb_max_hold"])) and sep >= float(ai["min_open_sep_m"]))
		if go:
			_throw_to(out, ctx, best, t)
			return
	if (pressure and _hold >= float(ai["qb_min_hold"])) or _hold >= float(ai["qb_max_hold"]) + 1.0:
		_scramble = true        # nobody open: tuck it and run


func _throw_to(out: Dictionary, ctx: Dictionary, r: Dictionary, t: Dictionary) -> void:
	var th: Dictionary = t["throw"]
	var ai: Dictionary = t["ai"]
	var pos: Vector2 = ctx["pos"]
	var target: Vector2 = r["pos"]
	var lob := false
	# Lead the receiver: guess the flight time, aim where they'll be, repeat once.
	for i in 2:
		var dist := pos.distance_to(target)
		lob = dist > float(ai["lob_min_dist"])
		var speed: float = th["lob_speed"] if lob else th["bullet_speed"]
		var T := maxf(dist / speed, float(th["min_flight_time"]))
		target = Vector2(r["pos"]) + Vector2(r["vel"]) * T
	var err := float(ai["throw_error_m"])
	target += Vector2(rng.randf_range(-err, err), rng.randf_range(-err, err))
	out["pass_to"] = target
	out["lob"] = lob
	_thrown = true


# --------------------------------------------------------------- carrier

func _carry(out: Dictionary, ctx: Dictionary, t: Dictionary) -> void:
	var ai: Dictionary = t["ai"]
	var pos: Vector2 = ctx["pos"]
	var heading: Vector2 = ctx["heading"]
	var stamina := float(ctx["stamina"])
	var status := int(ctx["status"])
	var goal := Vector2(0.0, float(ctx["dir"]))
	var avoid := Vector2.ZERO
	var r := float(ai["carrier_avoid_radius"])
	for o in ctx["opps"]:
		var to: Vector2 = Vector2(o["pos"]) - pos
		var dist := to.length()
		if dist < r and dist > 0.01 and to.dot(goal) > -2.0:
			avoid -= to.normalized() * (r - dist) / r * 1.6
	var hw := float(ctx["half_wid"])
	var side_m := float(ai["sideline_avoid_m"])
	if pos.x > hw - side_m:
		avoid.x -= 1.0
	elif pos.x < -hw + side_m:
		avoid.x += 1.0
	var mv := goal + avoid
	if mv.dot(goal) < 0.3:
		mv += goal * 0.6
	out["move"] = mv.normalized()
	out["sprint"] = stamina > float(ai["carrier_sprint_stamina"])
	if _juke_left > 0.0:
		out["move"] = _juke_dir

	var near := _nearest_opp(ctx)
	if status == AthleteState.Status.SPIN and not near.is_empty():
		# Pop out of the spin away from the nearest defender.
		var away: float = -heading.cross(Vector2(near["pos"]) - pos)
		out["move"] = heading.rotated(signf(away if away != 0.0 else 1.0) * deg_to_rad(80.0))
		return
	if status == AthleteState.Status.WRAPPED:
		if _counter_wait <= 0.0:
			_counter_wait = float(ai["counter_wait"])
			if _try_lateral(out, ctx, t):
				return
			if stamina >= float(t["tackle"]["spin_cost"]) and rng.randf() < 0.6:
				out["dive"] = true          # spin out of the hold
			else:
				out["tackle"] = true        # shove the holder off
		return
	if near.is_empty() or status != AthleteState.Status.OK or _counter_wait > 0.0:
		return
	var nd: float = near["dist"]
	if nd > float(ai["counter_range"]):
		_lateral_roll = -1
		return
	if _try_lateral(out, ctx, t):
		return
	var to_d: Vector2 = Vector2(near["pos"]) - pos
	var ang := rad_to_deg(absf(heading.angle_to(to_d)))
	_counter_wait = float(ai["counter_wait"])
	if int(near["status"]) == AthleteState.Status.DIVING:
		if stamina >= float(t["tackle"]["hurdle_cost"]) and rng.randf() < float(ai["hurdle_chance"]):
			out["hurdle"] = true
		else:
			_start_juke(out, heading, to_d)
	elif ang > 50.0 and ang < 130.0:
		out["tackle"] = true                # stiff arm toward the side he's coming from
		out["side"] = 1 if heading.cross(to_d) > 0.0 else -1
	elif ang <= 50.0:
		var roll := rng.randf()
		if stamina >= 0.35 and roll < float(ai["truck_chance"]):
			out["truck"] = true
		elif roll < float(ai["truck_chance"]) + float(ai["spin_chance"]) and stamina >= float(t["tackle"]["spin_cost"]):
			out["dive"] = true              # spin
		else:
			_start_juke(out, heading, to_d)


func _start_juke(out: Dictionary, heading: Vector2, to_d: Vector2) -> void:
	var side := -1.0 if heading.cross(to_d) > 0.0 else 1.0     # cut away from him
	_juke_dir = heading.rotated(side * deg_to_rad(70.0))
	_juke_left = 0.35
	out["move"] = _juke_dir


## Pitch it back to a trailing teammate when about to go down.
func _try_lateral(out: Dictionary, ctx: Dictionary, t: Dictionary) -> bool:
	var ai: Dictionary = t["ai"]
	if _lateral_roll < 0:
		_lateral_roll = 1 if rng.randf() < float(ai["lateral_chance"]) else 0
	if _lateral_roll != 1:
		return false
	var pos: Vector2 = ctx["pos"]
	var d := float(ctx["dir"])
	for m in ctx["mates"]:
		var rel: Vector2 = Vector2(m["pos"]) - pos
		if rel.y * d <= 0.5 and rel.length() <= float(ai["lateral_range_m"]) and rel.length() > 3.0:
			if _separation(m["pos"], ctx["opps"]) > 2.5:
				out["lateral"] = true
				out["yaw"] = atan2(-rel.x, -rel.y)
				_lateral_roll = 0
				return true
	return false


# --------------------------------------------------------------- offense

func _support(out: Dictionary, ctx: Dictionary, t: Dictionary) -> void:
	var carrier: Vector2 = ctx["carrier"]
	var qb_in_pocket: bool = int(ctx["ball_holder"]) == int(ctx["qb_id"]) and \
		(carrier.y - float(ctx["los_z"])) * float(ctx["dir"]) < 0.0
	if qb_in_pocket:
		_run_route(out, ctx)
		return
	# Someone else is running with it: get out ahead of the carrier.
	var d := float(ctx["dir"])
	var slot := int(ctx["slot"])
	var target := carrier + Vector2((slot % 2 * 2 - 1) * 4.0, d * 5.0)
	out["move"] = (target - Vector2(ctx["pos"])).normalized()
	out["sprint"] = true


func _run_route(out: Dictionary, ctx: Dictionary) -> void:
	var pos: Vector2 = ctx["pos"]
	if _wp_i < _wp.size():
		var to: Vector2 = _wp[_wp_i] - pos
		if to.length() < 1.2:
			_wp_i += 1
		else:
			out["move"] = to.normalized()
			out["sprint"] = true
			return
	# Route done: find space away from the closest defender.
	var near := _nearest_opp(ctx)
	if not near.is_empty() and float(near["dist"]) < 4.0:
		var away: Vector2 = (pos - Vector2(near["pos"])).normalized()
		var hw := float(ctx["half_wid"])
		if absf(pos.x + away.x * 2.0) > hw - 1.0:
			away.x = -away.x
		out["move"] = away
		out["sprint"] = false


func _ball_in_air(out: Dictionary, ctx: Dictionary, t: Dictionary) -> void:
	var land: Vector2 = ctx["land"]
	var pos: Vector2 = ctx["pos"]
	var my_team := int(ctx["team"])
	var throwing_team := int(ctx.get("thrower_team", -1))
	if my_team != throwing_team:
		_try_swat(out, ctx, t)
		if out.has("hold_move"):
			out.erase("hold_move")
			return
	# Am I the closest player on my team (other than the thrower) to where it's coming down?
	var me_d := pos.distance_to(land)
	var closest := true
	for m in ctx["mates"]:
		if int(m["id"]) != int(ctx["thrower"]) and Vector2(m["pos"]).distance_to(land) < me_d:
			closest = false
			break
	if closest:
		out["move"] = (land - pos).normalized() if me_d > 0.4 else Vector2.ZERO
		out["sprint"] = me_d > 4.0
		return
	if my_team == throwing_team:
		_run_route(out, ctx)
	else:
		_cover(out, ctx, t)


## Reach for a pass in the air: look ahead along the flight and press when the ball is
## about _swat_lead seconds from reaching us. The lead carries a random error, so bots
## sometimes pick it off, sometimes only get a hand on it, sometimes whiff.
func _try_swat(out: Dictionary, ctx: Dictionary, t: Dictionary) -> void:
	var ai: Dictionary = t["ai"]
	var sw: Dictionary = t["swat"]
	if int(ctx["launch_tick"]) != _swat_throw:
		_swat_throw = int(ctx["launch_tick"])
		_swat_go = rng.randf() < float(ai["swat_chance"])
		_swat_lead = float(ai["swat_lead_s"]) + rng.randfn(0.0, float(ai["swat_error_s"]))
		_reach_until = -1.0
	var f: Dictionary = ctx["flight"]
	var ball_now := BallFlight.position_at(f["p0"], f["fl"], float(f["g"]), float(f["t"]))
	if float(f["t"]) <= _reach_until:
		out["move"] = (Vector2(ball_now.x, ball_now.z) - Vector2(ctx["pos"])).normalized()
		out["sprint"] = false
		out["hold_move"] = true
		return
	if not _swat_go:
		return
	var fl: Dictionary = f["fl"]
	var pos: Vector2 = ctx["pos"]
	var vel: Vector2 = Vector2(ctx["heading"]) * float(ctx["speed"])
	var ahead := 0.0
	while ahead <= float(ai["swat_look_ahead_s"]):
		var tt := minf(float(f["t"]) + ahead, float(fl["T"]))
		var b := BallFlight.position_at(f["p0"], fl, float(f["g"]), tt)
		var me := pos + vel * ahead
		if b.y >= float(sw["min_height"]) and b.y <= float(sw["max_height"]) \
				and me.distance_to(Vector2(b.x, b.z)) <= float(sw["radius"]) * 0.9:
			if ahead <= _swat_lead:
				out["swat"] = true
				_swat_go = false
				_reach_until = float(f["t"]) + float(sw["window_s"])
				out["move"] = (Vector2(ball_now.x, ball_now.z) - pos).normalized()
				out["sprint"] = false
				out["hold_move"] = true
			elif ahead <= _swat_lead + float(ai["swat_turn_s"]):
				# Turn back to the ball so the reach can be a pick, not just a deflection.
				out["move"] = (Vector2(ball_now.x, ball_now.z) - pos).normalized()
				out["sprint"] = false
				out["hold_move"] = true
			return
		if tt >= float(fl["T"]):
			return
		ahead += 1.0 / 60.0


# --------------------------------------------------------------- defense

func _defend(out: Dictionary, ctx: Dictionary, t: Dictionary) -> void:
	var carrier: Vector2 = ctx["carrier"]
	var od := -float(ctx["dir"])            # the offense's direction
	var qb_in_pocket: bool = int(ctx["ball_holder"]) == int(ctx["qb_id"]) and \
		(carrier.y - float(ctx["los_z"])) * od < 0.0
	if qb_in_pocket:
		if int(ctx["slot"]) == 0:
			if float(ctx["rush_left"]) > 0.0:
				# Wait on the line for the rush timer.
				var spot := Vector2(carrier.x, float(ctx["los_z"]) + od * 1.0)
				var to := spot - Vector2(ctx["pos"])
				out["move"] = to.normalized() if to.length() > 0.5 else Vector2.ZERO
			else:
				_chase(out, ctx, t)
			return
		_cover(out, ctx, t)
		return
	_chase(out, ctx, t)


## Man coverage: stay a little deeper than my receiver, between him and the goal. A
## defender only re-reads his man every cover_react_s, so a sharp cut buys separation.
func _cover(out: Dictionary, ctx: Dictionary, t: Dictionary) -> void:
	var ai: Dictionary = t["ai"]
	var slot := int(ctx["slot"])
	var man := {}
	for o in ctx["opps"]:
		if int(o["slot"]) == slot:
			man = o
			break
	if man.is_empty():
		return
	var od := -float(ctx["dir"])
	if _cover_timer <= 0.0:
		_cover_timer = float(ai["cover_react_s"])
		_cover_target = Vector2(man["pos"]) + Vector2(man["vel"]) * float(ai["cover_lead_s"]) \
			+ Vector2(0.0, od * float(ai["cover_cushion_m"]))
	var to := _cover_target - Vector2(ctx["pos"])
	out["move"] = to.normalized() if to.length() > 0.4 else Vector2.ZERO
	out["sprint"] = Vector2(ctx["pos"]).distance_to(man["pos"]) > float(ai["cover_sprint_gap_m"])


## Pursue and tackle the carrier; join a wrap with a tackle or a strip; dive at range.
func _chase(out: Dictionary, ctx: Dictionary, t: Dictionary) -> void:
	if not ctx.has("carrier") or ctx["holding"]:
		return        # holding the carrier: hang on and wait for a teammate
	var b: Dictionary = t["bot"]
	var pos: Vector2 = ctx["pos"]
	var cp: Vector2 = ctx["carrier"]
	var cv: Vector2 = ctx.get("carrier_vel", Vector2.ZERO)
	var dist := pos.distance_to(cp)
	var lead := float(b["chase_lead_s"]) * clampf(dist / 6.0, 0.0, 1.0)
	out["move"] = (cp + cv * lead - pos).normalized()
	out["sprint"] = true
	var h: Vector2 = ctx["heading"]
	var facing_ok := rad_to_deg(absf(h.angle_to(cp - pos))) <= float(b["chase_face_deg"])
	if dist <= float(b["chase_trigger_m"]) and facing_ok:
		if ctx.get("carrier_wrapped", false):
			if _strip_roll < 0:
				_strip_roll = 1 if rng.randf() < float(b["strip_chance"]) else 0
			out["strip" if _strip_roll == 1 else "tackle"] = true
		else:
			out["tackle"] = true
	elif dist > float(b["dive_trigger_m"]) + 2.0:
		_dive_roll = -1
		_strip_roll = -1
	elif dist <= float(b["dive_trigger_m"]) and facing_ok:
		if _dive_roll < 0:
			_dive_roll = 1 if rng.randf() < float(b["dive_chance"]) else 0
		if _dive_roll == 1:
			out["dive"] = true
