class_name PlayFlow
extends RefCounted
## Server-side play loop for a match: two teams, formations, the snap, the rush timer,
## what ends a play, and spotting the ball for the next one. Downs and scoring come in
## step 4b. The session asks this object who may tackle and catch whom.

enum Phase { PRE_SNAP, LIVE, DEAD }

var s: NetSession
var phase := Phase.PRE_SNAP
var phase_time := 0.0
var play_no := 0
var offense := 0              # team with the ball this play
var base_dir := -1            # team 0 attacks toward this z sign; team 1 the other way
var los_z := 0.0
var qb_id := 0
var rush_left := 0.0
var possession_team := 0      # last team seen holding the ball this play
var result := ""
var slots := {}               # team -> Array of ids; slot 0 is the QB (offense) / linebacker (defense)
var routes := {}              # receiver id -> route name for this play
var snap_qb_pos := Vector2.ZERO

var _next_offense := 0
var _next_los_z := 0.0


func _init(session: NetSession) -> void:
	s = session


func _m() -> Dictionary:
	return Tuning.section("match")


func yard() -> float:
	return float(Tuning.section("field")["yard_m"])


func half_len() -> float:
	return float(Tuning.section("field")["length_yards"]) * 0.5 * yard()


func half_wid() -> float:
	return float(Tuning.section("field")["width_yards"]) * 0.5 * yard()


func endzone() -> float:
	return float(Tuning.section("field")["endzone_yards"]) * yard()


## The z direction a team attacks.
func team_dir(team: int) -> int:
	return base_dir if team == 0 else -base_dir


func dir() -> int:
	return team_dir(offense)


## z of a team's own goal line (the one they defend) and of the one they attack.
func own_goal_z(team: int) -> float:
	return -team_dir(team) * half_len()


func attack_goal_z(team: int) -> float:
	return team_dir(team) * half_len()


## Yards from the offense's own goal line to a z position (0..60).
func yards_from_own_goal(z: float, team: int) -> float:
	return (z - own_goal_z(team)) * team_dir(team) / yard()


func yard_line_text(z: float, team: int) -> String:
	var y := roundi(yards_from_own_goal(z, team))
	var mid := roundi(float(Tuning.section("field")["length_yards"]) * 0.5)
	if y == mid:
		return "midfield"
	return "own %d" % y if y < mid else "opponent %d" % (2 * mid - y)


func team_of(id: int) -> int:
	var p: NetSession.SvPlayer = s.sv_players.get(id)
	return p.team if p != null else -1


# ------------------------------------------------------------------ setup

func start() -> void:
	_assign_teams()
	offense = 0
	los_z = _z_at_own_yard(0, float(_m()["start_yard"]))
	_setup_play()


func _z_at_own_yard(team: int, y: float) -> float:
	return own_goal_z(team) + team_dir(team) * y * yard()


## Humans alternate between teams by join order (host first); bots fill both to team_size.
func _assign_teams() -> void:
	var humans: Array = []
	for id in s.sv_players:
		if id > 0:
			humans.append(id)
	humans.sort()
	for i in humans.size():
		s.sv_players[humans[i]].team = i % 2
	_refill_bots()


func _refill_bots() -> void:
	var size := int(_m()["team_size"])
	for team in [0, 1]:
		var members := _members(team)
		while members.size() > size:
			var bot := _last_bot(members)
			if bot == 0:
				break
			s.remove_bot(bot)
			members = _members(team)
		while members.size() < size:
			s.add_team_bot(team)
			members = _members(team)


func _members(team: int) -> Array:
	var out: Array = []
	for id in s.sv_players:
		if s.sv_players[id].team == team:
			out.append(id)
	return out


func _last_bot(members: Array) -> int:
	var worst := 0
	for id in members:
		if id < 0 and (worst == 0 or id < worst):
			worst = id
	return worst


func on_join(id: int) -> void:
	var h0 := 0
	var h1 := 0
	for pid in s.sv_players:
		if pid > 0 and pid != id:
			if s.sv_players[pid].team == 0:
				h0 += 1
			else:
				h1 += 1
	s.sv_players[id].team = 0 if h0 <= h1 else 1
	_refill_bots()


func on_leave(_id: int) -> void:
	_refill_bots()


## Humans take slot 0 (QB / linebacker) first, then bots in a stable order.
func _order_team(team: int) -> Array:
	var members := _members(team)
	var humans: Array = []
	var bots: Array = []
	for id in members:
		if id > 0:
			humans.append(id)
		else:
			bots.append(id)
	humans.sort()
	bots.sort()
	bots.reverse()        # -1, -2, -3 ...
	return humans + bots


func _setup_play() -> void:
	play_no += 1
	phase = Phase.PRE_SNAP
	phase_time = 0.0
	rush_left = float(_m()["rush_time"])
	result = ""
	s.dead_reason = ""
	s.dead_team = -1
	var d := dir()
	var y := yard()
	var m := _m()
	slots = {0: _order_team(0), 1: _order_team(1)}
	var off: Array = slots[offense]
	var dfn: Array = slots[1 - offense]
	qb_id = off[0] if off.size() > 0 else 0
	var rx: Array = m["receiver_x_m"]
	routes.clear()
	var names: Array = Tuning.section("ai")["route_names"]
	for i in off.size():
		var pos: Vector2
		if i == 0:
			pos = Vector2(0.0, los_z - d * float(m["qb_back_y"]) * y)
		else:
			var x: float = rx[(i - 1) % rx.size()] * -d     # mirrored with the attack direction
			pos = Vector2(x, los_z - d * float(m["receiver_back_y"]) * y)
			routes[off[i]] = names[s.rng.randi() % names.size()]
		_place(off[i], pos, Vector2(0, d))
	for i in dfn.size():
		var pos: Vector2
		if i == 0:
			pos = Vector2(0.0, los_z + d * float(m["mlb_depth_y"]) * y)
		else:
			var x: float = rx[(i - 1) % rx.size()] * -d
			pos = Vector2(x, los_z + d * float(m["defense_depth_y"]) * y)
		_place(dfn[i], pos, Vector2(0, -d))
	# The ball sits on the line until the snap.
	s.ball_kind = NetSession.Ball.LOOSE
	s.ball_holder = 0
	s.ball_live = false
	s.ball_lateral = false
	s.ball_loose = Vector3(0.0, float(Tuning.section("throw")["ball_radius"]), los_z)
	possession_team = offense
	s.announce("Ball on the %s. %s" % [yard_line_text(los_z, offense), "Snap when ready" if qb_id > 0 else "Bot QB will snap"])


func _place(id: int, pos: Vector2, heading: Vector2) -> void:
	var p: NetSession.SvPlayer = s.sv_players[id]
	p.state = AthleteState.new()
	p.state.pos = pos
	p.state.heading = heading
	p.state.status = AthleteState.Status.SET
	p.state.status_timer = 9999.0
	p.prev_pos = pos
	p.queue.clear()
	p.last_move = Vector2.ZERO
	p.last_sprint = false
	p.reset_play_fields()


# ------------------------------------------------------------------- the snap

func request_snap(id: int) -> void:
	if phase != Phase.PRE_SNAP or id != qb_id or phase_time < float(_m()["min_set_time"]):
		return
	_snap()


func _snap() -> void:
	phase = Phase.LIVE
	phase_time = 0.0
	rush_left = float(_m()["rush_time"])
	for id in s.sv_players:
		var p: NetSession.SvPlayer = s.sv_players[id]
		if p.state.status == AthleteState.Status.SET:
			p.state.status = AthleteState.Status.OK
			p.state.status_timer = 0.0
	if s.sv_players.has(qb_id):
		s.ball_kind = NetSession.Ball.HELD
		s.ball_holder = qb_id
		s.ball_live = false
		snap_qb_pos = s.sv_players[qb_id].state.pos
	s.announce("Hike!")


# ------------------------------------------------------------------ each tick

func is_live() -> bool:
	return phase == Phase.LIVE


func can_tackle(tackler: int, carrier: int) -> bool:
	return team_of(tackler) != team_of(carrier)


## Passes and pitches are only caught by the thrower's team for now (swats and
## interceptions come later), and never by a player standing out of bounds.
func can_catch(id: int, thrower: int) -> bool:
	if team_of(id) != team_of(thrower):
		return false
	return not is_out(s.sv_players[id].state.pos)


func is_out(pos: Vector2) -> bool:
	return absf(pos.x) > half_wid() or absf(pos.y) > half_len() + endzone()


func tick(dt: float) -> void:
	phase_time += dt
	match phase:
		Phase.PRE_SNAP:
			if phase_time >= float(_m()["play_clock"]):
				_snap()        # the play clock ran out: the game snaps it (no delay penalties)
		Phase.LIVE:
			_live_tick(dt)
		Phase.DEAD:
			if phase_time >= float(_m()["dead_time"]):
				offense = _next_offense
				los_z = _next_los_z
				_setup_play()


func _live_tick(dt: float) -> void:
	var d := dir()
	# Rush timer: ends on time, when the QB crosses the line, or once the QB lets go of the ball.
	if rush_left > 0.0:
		rush_left = maxf(0.0, rush_left - dt)
		var qb_has_ball: bool = s.ball_kind == NetSession.Ball.HELD and s.ball_holder == qb_id
		if not qb_has_ball:
			rush_left = 0.0
		elif s.sv_players.has(qb_id) and (s.sv_players[qb_id].state.pos.y - los_z) * d > 0.0:
			rush_left = 0.0
	if rush_left > 0.0:
		# Defenders can't cross the line until the rush timer ends (enforced, no penalties).
		var margin := float(_m()["barrier_margin"])
		for id in s.sv_players:
			var p: NetSession.SvPlayer = s.sv_players[id]
			if p.team != offense and (p.state.pos.y - los_z) * d < margin:
				p.state.pos.y = los_z + d * margin

	if s.ball_kind == NetSession.Ball.HELD and s.sv_players.has(s.ball_holder):
		possession_team = team_of(s.ball_holder)
		var c: AthleteState = s.sv_players[s.ball_holder].state
		var cd := team_dir(possession_team)
		if (c.pos.y - attack_goal_z(possession_team)) * cd >= 0.0 and absf(c.pos.x) <= half_wid():
			_end_play("TOUCHDOWN by %s!" % s.name_of(s.ball_holder), 0.0, possession_team, true)
			return
		if is_out(c.pos):
			_end_play("%s ran out of bounds" % s.name_of(s.ball_holder), c.pos.y, possession_team)
			return
	if s.ball_kind == NetSession.Ball.LOOSE and s.ball_live and is_out(Vector2(s.ball_loose.x, s.ball_loose.z)):
		_end_play("Loose ball out of bounds", s.ball_loose.z, possession_team)
		return
	if s.dead_reason != "":
		var reason := s.dead_reason
		s.dead_reason = ""
		if reason == "incomplete":
			_end_play("Incomplete pass", los_z, offense)
		else:
			_end_play(reason, s.dead_spot.y, s.dead_team if s.dead_team >= 0 else possession_team)
		return
	if phase_time >= float(_m()["max_play_time"]):
		_end_play("Play stopped (time limit)", s.ball_loose.z, possession_team)


func _end_play(text: String, spot_z: float, team: int, touchdown := false) -> void:
	phase = Phase.DEAD
	phase_time = 0.0
	rush_left = 0.0
	var gained := (spot_z - los_z) * dir() / yard()
	if touchdown:
		_next_offense = 1 - team
		_next_los_z = _z_at_own_yard(_next_offense, float(_m()["start_yard"]))
		result = text
	else:
		_next_offense = team
		var margin := float(_m()["spot_margin_y"]) * yard()
		var td := team_dir(team)
		# Keep the next line of scrimmage between the goal lines.
		var lo := own_goal_z(team) + td * margin
		var hi := attack_goal_z(team) - td * margin
		_next_los_z = clampf(spot_z, minf(lo, hi), maxf(lo, hi))
		if team != offense:
			result = "%s. TURNOVER: the other team takes over on the %s" % [text, yard_line_text(_next_los_z, team)]
		elif text == "Incomplete pass":
			result = text
		else:
			result = "%s (%+d yards)" % [text, roundi(gained)]
	# A dead ball can't be picked up or played.
	if s.ball_kind == NetSession.Ball.HELD:
		var c: AthleteState = s.sv_players[s.ball_holder].state
		s.ball_loose = Vector3(c.pos.x, float(Tuning.section("throw")["ball_radius"]), c.pos.y)
	s.ball_kind = NetSession.Ball.LOOSE
	s.ball_holder = 0
	s.ball_live = false
	s.announce(result)


# ------------------------------------------------------------------ for the AI

## Everything a bot needs to decide what to do this tick.
func bot_context(id: int) -> Dictionary:
	var me: NetSession.SvPlayer = s.sv_players[id]
	var team := me.team
	var mates: Array = []
	var opps: Array = []
	for pid in s.sv_players:
		if pid == id:
			continue
		var p: NetSession.SvPlayer = s.sv_players[pid]
		var e := {"id": pid, "pos": p.state.pos, "vel": p.state.heading * p.state.speed,
			"status": p.state.status, "slot": slots.get(p.team, []).find(pid)}
		if p.team == team:
			mates.append(e)
		else:
			opps.append(e)
	var ctx := {
		"id": id, "pos": me.state.pos, "heading": me.state.heading, "speed": me.state.speed,
		"stamina": me.state.stamina, "status": me.state.status, "team": team,
		"slot": slots.get(team, []).find(id), "offense": team == offense,
		"phase": phase, "phase_time": phase_time, "play_no": play_no,
		"dir": team_dir(team), "los_z": los_z, "rush_left": rush_left, "qb_id": qb_id,
		"mates": mates, "opps": opps, "route": routes.get(id, ""),
		"half_wid": half_wid(), "holding": me.wrap_of != 0,
		"ball_kind": s.ball_kind, "ball_holder": s.ball_holder, "ball_live": s.ball_live,
		"ball_loose": Vector2(s.ball_loose.x, s.ball_loose.z), "thrower": s.ball_thrower,
	}
	if s.ball_kind == NetSession.Ball.HELD and s.sv_players.has(s.ball_holder):
		var c: NetSession.SvPlayer = s.sv_players[s.ball_holder]
		ctx["carrier"] = c.state.pos
		ctx["carrier_vel"] = c.state.heading * c.state.speed
		ctx["carrier_team"] = c.team
		ctx["carrier_wrapped"] = c.wrap_holder != 0
		ctx["carrier_status"] = c.state.status
	if s.ball_kind == NetSession.Ball.FLIGHT:
		var fl := BallFlight.launch(s.ball_p0, s.ball_yaw, s.ball_charge, s.ball_lob, Tuning.data, s.ball_angle)
		ctx["land"] = Vector2(fl["land"].x, fl["land"].z)
		ctx["thrower_team"] = team_of(s.ball_thrower)
	return ctx


## What clients need to show the play: phase, offense, direction, line, rush timer.
func view() -> Dictionary:
	return {"phase": phase, "offense": offense, "dir": dir(), "los": los_z, "rush": rush_left,
		"qb": qb_id, "play_no": play_no, "phase_time": phase_time}
