class_name NetSession
extends Node
## Host (listen server) or client. The host runs the authoritative simulation at
## a fixed tick and sends snapshots. Clients send inputs with sequence numbers,
## predict their own athlete, reconcile against snapshots, and interpolate
## everyone else slightly behind real time.
##
## Kept free of UI so it can run as a headless dedicated server later.

signal local_ready(athlete: Athlete)
signal disconnected
signal event_text(text: String)

enum Mode { NONE, HOST, CLIENT }

class SvPlayer:
	var state := AthleteState.new()
	var prev_pos := Vector2.ZERO
	var queue: Array = []        # entries: [seq, move, sprint]
	var last_seq := 0            # highest seq received
	var acked := 0               # last seq actually simulated
	var last_move := Vector2.ZERO
	var last_sprint := false
	var tackle_cd := 0.0

enum Ball { LOOSE, HELD, FLIGHT }
enum ThrowMode { AIM, HOLD }   # AIM: pitch = launch angle, hold = power. HOLD: old charge-for-distance throw.

const SNAP_STRIDE := 13   # floats per player (id travels in a separate int array)

var mode := Mode.NONE
var local_id := 0
var input_provider: Callable          # () -> [Vector2 world move, bool sprint]
var athlete_parent: Node3D
var athletes := {}                    # peer id -> Athlete (visual)
var log_enabled := false

# Server side
var sv_players := {}                  # peer id -> SvPlayer
var sv_tick := 0
var _sv_next_spawn := 0
var sv_bots := {}                    # negative id -> BotBrain (host-side test bots)
var _next_bot_id := -1

# Ball (server truth; clients read it from snapshots)
var ball_kind := Ball.LOOSE
var ball_holder := 0
var ball_launch_tick := 0
var ball_p0 := Vector3.ZERO
var ball_yaw := 0.0
var ball_charge := 0.0
var ball_lob := false
var ball_angle := -1.0           # launch angle (radians) for angle+power throws, -1 for the old model
var ball_thrower := 0
var ball_loose := Vector3(0, 0.3, 0)
var ball_view: BallView = null

# Local throw control
var throw_charge := 0.0
var throw_charging := false
var aim_active := false
var aim_pos := Vector2.ZERO
var aim_lob := false
var aim_arc := PackedVector3Array()
var aim_angle := -1.0
var latest_holder := 0         # newest holder seen in a snapshot (undelayed)
var view_ball := {}            # what the delayed view currently shows (for logs/HUD)

# Client side
var cl_state: AthleteState = null
var cl_prev_pos := Vector2.ZERO
var cl_seq := 0
var cl_pending: Array = []            # entries: [seq, move, sprint]
var cl_sent_time := {}                # seq -> send time
var cl_connected := false
var correction := Vector2.ZERO        # decaying visual offset after reconciliation
var snap_buffer: Array = []           # entries: {tick, players: {id: Array}}
var latest_tick := -1
var render_tick := 0.0

# Stats
var rtt := 0.0
var last_correction := 0.0
var max_correction := 0.0
var _log_timer := 0.0

var _acc := 0.0
var _out_queue: Array = []            # fake-lag queue: [release time, Callable]


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _net() -> Dictionary:
	return Tuning.section("net")


func _tick_dt() -> float:
	return 1.0 / float(_net()["tick_hz"])


# ---------------------------------------------------------------- start / stop

func start_host(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, int(_net()["max_players"]))
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	mode = Mode.HOST
	_make_ball_view()
	local_id = 1
	_add_sv_player(1)
	_ensure_athlete(1)
	return OK


func start_client(ip: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_lost)
	multiplayer.server_disconnected.connect(_on_lost)
	mode = Mode.CLIENT
	_make_ball_view()
	return OK


func _make_ball_view() -> void:
	if ball_view == null:
		ball_view = BallView.new()
		athlete_parent.add_child(ball_view)


func _on_connected() -> void:
	cl_connected = true
	local_id = multiplayer.get_unique_id()


func _on_lost() -> void:
	mode = Mode.NONE
	multiplayer.multiplayer_peer = null
	for a in athletes.values():
		a.queue_free()
	athletes.clear()
	if ball_view:
		ball_view.queue_free()
		ball_view = null
	disconnected.emit()


## Dev helper: a receiver driven by the host itself. It uses the same movement
## code and input queue as a real player, but not the network connection.
func host_add_bot(role := "") -> void:
	if mode != Mode.HOST:
		return
	var id := _next_bot_id
	_next_bot_id -= 1
	_add_sv_player(id)
	var b := BotBrain.new()
	if role == "chase":
		b.role = "chase"
	else:
		b.route_name = "random"
	sv_bots[id] = b


func host_clear_bots() -> void:
	for id in sv_bots:
		sv_players.erase(id)
		_remove_athlete(id)
	sv_bots.clear()


func _on_peer_connected(id: int) -> void:
	_add_sv_player(id)


func _on_peer_disconnected(id: int) -> void:
	sv_players.erase(id)
	_remove_athlete(id)


func _add_sv_player(id: int) -> void:
	var p := SvPlayer.new()
	var n := _sv_next_spawn
	_sv_next_spawn += 1
	p.state.pos = Vector2(((n % 7) - 3) * 4.0, 15.0)
	p.prev_pos = p.state.pos
	sv_players[id] = p


# ------------------------------------------------------------------- the tick

func _physics_process(delta: float) -> void:
	if mode == Mode.NONE or (mode == Mode.CLIENT and not cl_connected):
		return
	var dt := _tick_dt()
	_acc += delta
	var guard := 0
	while _acc >= dt and guard < 8:
		_acc -= dt
		guard += 1
		if mode == Mode.HOST:
			_host_tick(dt)
		else:
			_client_tick(dt)


func _sample_input() -> Dictionary:
	if input_provider.is_valid():
		return input_provider.call()
	return {"move": Vector2.ZERO, "sprint": false}


func _host_tick(dt: float) -> void:
	var inp := _sample_input()
	_ball_input(inp, dt)
	if inp.get("tackle", false):
		_sv_tackle(1)
	var me: SvPlayer = sv_players[1]
	me.last_seq += 1
	me.queue.append([me.last_seq, inp["move"], inp["sprint"]])

	for id in sv_players:
		sv_players[id].tackle_cd = maxf(0.0, sv_players[id].tackle_cd - dt)
	for id in sv_bots:
		var bp: SvPlayer = sv_players[id]
		var ctx := {}
		if ball_kind == Ball.HELD and ball_holder != id and sv_players.has(ball_holder):
			var cs: AthleteState = sv_players[ball_holder].state
			ctx["carrier"] = cs.pos
			ctx["carrier_vel"] = cs.heading * cs.speed
		var bi: Dictionary = sv_bots[id].think(bp.state.pos, dt, Tuning.data, false, ctx)
		bp.last_seq += 1
		bp.queue.append([bp.last_seq, bi["move"], bi["sprint"]])
		if bi.get("tackle", false):
			_sv_tackle(id)

	var max_q: int = int(_net()["max_input_queue"])
	for id in sv_players:
		var p: SvPlayer = sv_players[id]
		p.prev_pos = p.state.pos
		while p.queue.size() > max_q:
			p.acked = p.queue.pop_front()[0]   # fell behind: skip ahead
		if not p.queue.is_empty():
			var e: Array = p.queue.pop_front()
			p.acked = e[0]
			p.last_move = e[1]
			p.last_sprint = e[2]
		# else: starved, repeat the last input
		Movement.step(p.state, p.last_move, p.last_sprint, dt, Tuning.data)

	sv_tick += 1
	_ball_tick(dt)
	var ids := PackedInt32Array()
	var data := PackedFloat32Array()
	for id in sv_players:
		var p: SvPlayer = sv_players[id]
		var s := p.state
		ids.append(id)
		data.append_array([s.pos.x, s.pos.y, s.heading.x, s.heading.y, s.speed, s.stamina,
			s.cut_timer, s.cut_cooldown, s.prev_dir.x, s.prev_dir.y, s.status, s.status_timer, p.acked])
	var ball_i := PackedInt32Array([ball_kind, ball_holder, ball_launch_tick])
	var ball_f := PackedFloat32Array([ball_p0.x, ball_p0.y, ball_p0.z, ball_yaw, ball_charge,
		1.0 if ball_lob else 0.0, ball_loose.x, ball_loose.y, ball_loose.z, ball_angle])
	for id in multiplayer.get_peers():
		var peer_id: int = id
		var tick := sv_tick
		_send(func(): if multiplayer.get_peers().has(peer_id): rpc_id(peer_id, "rpc_snapshot", tick, ids, data, ball_i, ball_f))


func _client_tick(dt: float) -> void:
	if cl_state == null:
		return
	var inp := _sample_input()
	_ball_input(inp, dt)
	if inp.get("tackle", false):
		_send(func(): if cl_connected: rpc_id(1, "rpc_tackle"))
	var move: Vector2 = inp["move"]
	var sprint: bool = inp["sprint"]
	cl_seq += 1
	cl_prev_pos = cl_state.pos
	Movement.step(cl_state, move, sprint, dt, Tuning.data)
	cl_pending.append([cl_seq, move, sprint])
	cl_sent_time[cl_seq] = _now()

	var n: int = mini(int(_net()["input_redundancy"]), cl_pending.size())
	var batch := PackedFloat32Array()
	for i in range(cl_pending.size() - n, cl_pending.size()):
		var e: Array = cl_pending[i]
		batch.append_array([e[0], e[1].x, e[1].y, 1.0 if e[2] else 0.0])
	_send(func(): if cl_connected: rpc_id(1, "rpc_inputs", batch))


# ------------------------------------------------------------------------ RPCs

@rpc("any_peer", "unreliable")
func rpc_inputs(batch: PackedFloat32Array) -> void:
	if mode != Mode.HOST:
		return
	var p: SvPlayer = sv_players.get(multiplayer.get_remote_sender_id())
	if p == null:
		return
	for i in range(0, batch.size() - 3, 4):
		var seq := int(batch[i])
		if seq <= p.last_seq:
			continue
		var move := Vector2(batch[i + 1], batch[i + 2])
		if move.length() > 1.0:
			move = move.normalized()
		p.last_seq = seq
		p.queue.append([seq, move, batch[i + 3] > 0.5])


@rpc("authority", "unreliable")
func rpc_snapshot(tick: int, ids: PackedInt32Array, data: PackedFloat32Array, ball_i: PackedInt32Array, ball_f: PackedFloat32Array) -> void:
	if mode != Mode.CLIENT or tick <= latest_tick:
		return
	var players := {}
	for i in ids.size():
		players[ids[i]] = data.slice(i * SNAP_STRIDE, (i + 1) * SNAP_STRIDE)
	latest_tick = tick
	snap_buffer.append({"tick": tick, "players": players, "ball_i": ball_i, "ball_f": ball_f})
	latest_holder = ball_i[1] if ball_i[0] == Ball.HELD else 0
	if snap_buffer.size() == 1:
		render_tick = tick - float(_net()["interp_delay_ticks"])
	if players.has(local_id):
		_reconcile(players[local_id])
	for id in athletes.keys():
		if not players.has(id):
			_remove_athlete(id)


@rpc("any_peer", "reliable")
func rpc_take_ball() -> void:
	if mode == Mode.HOST:
		_sv_take(multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func rpc_throw(charge: float, yaw: float, lob: bool, angle: float) -> void:
	if mode == Mode.HOST:
		_sv_throw(multiplayer.get_remote_sender_id(), charge, yaw, lob, angle)


@rpc("any_peer", "reliable")
func rpc_tackle() -> void:
	if mode == Mode.HOST:
		_sv_tackle(multiplayer.get_remote_sender_id())


@rpc("authority", "reliable")
func rpc_event(text: String) -> void:
	_log_event("(event received) " + text)
	event_text.emit(text)


func _announce(text: String) -> void:
	event_text.emit(text)
	_log_event(text)
	for id in multiplayer.get_peers():
		var peer_id: int = id
		_send(func(): if multiplayer.get_peers().has(peer_id): rpc_id(peer_id, "rpc_event", text))


# --------------------------------------------------------------------- tackling

## The referee for a close-tackle press. Only the ball carrier can be tackled; pressing
## it at anyone else (or at nothing) is a committed whiff.
func _sv_tackle(id: int) -> void:
	var p: SvPlayer = sv_players.get(id)
	if p == null or p.state.status == AthleteState.Status.DOWN or p.tackle_cd > 0.0:
		return
	var tk: Dictionary = Tuning.section("tackle")
	p.tackle_cd = tk["cooldown"]

	var target := 0
	if ball_kind == Ball.HELD and ball_holder != id and sv_players.has(ball_holder):
		var cpos: Vector2 = sv_players[ball_holder].state.pos
		var to := cpos - p.state.pos
		if to.length() <= float(tk["reach"]) and rad_to_deg(absf(p.state.heading.angle_to(to))) <= float(tk["arc_half_deg"]):
			target = ball_holder
	if target == 0:
		p.state.status = AthleteState.Status.STUMBLE
		p.state.status_timer = tk["whiff_stumble_time"]
		_announce("%s whiffed" % _name(id))
		return
	_resolve_tackle(id, target)


func _resolve_tackle(tackler_id: int, carrier_id: int) -> void:
	var tk: Dictionary = Tuning.section("tackle")
	var mv: Dictionary = Tuning.section("movement")
	var t: AthleteState = sv_players[tackler_id].state
	var c: AthleteState = sv_players[carrier_id].state

	var to_tackler := (t.pos - c.pos).normalized()
	var facing := c.heading.dot(to_tackler)      # +1: tackler is in front of the carrier
	var closing := maxf(0.0, (t.heading * t.speed).dot(-to_tackler))
	var behind: bool = facing <= float(tk["behind_cos"])
	var balance_factor := 1.0
	if behind:
		balance_factor = tk["behind_balance_factor"]
	elif facing < float(tk["front_cos"]):
		balance_factor = tk["side_balance_factor"]
	var weight: float = tk["weight"]
	var hit: float = weight * (float(tk["hit_base"]) + closing)
	var balance: float = weight * (float(tk["balance_base"]) + c.speed * balance_factor)
	var diff := hit - balance
	var angle_name := "from behind" if behind else ("head-on" if facing >= float(tk["front_cos"]) else "from the side")
	var detail := "%s hit %s: hit %.1f vs balance %.1f" % [_name(tackler_id), angle_name, hit, balance]

	var down_decel: float = float(mv["run_speed"]) / float(mv["down_stop_time"])
	if diff < float(tk["broken_margin"]):
		c.status = AthleteState.Status.STUMBLE
		c.status_timer = tk["broken_stumble_time"]
		c.speed *= tk["broken_speed_keep"]
		t.status = AthleteState.Status.STUMBLE
		t.status_timer = tk["defender_stumble_time"]
		_announce("BROKEN TACKLE (%s)" % detail)
		return

	var spot := c.pos
	if diff >= float(tk["clean_margin"]):
		var big: bool = diff >= float(tk["big_hit_margin"]) and not behind
		c.status = AthleteState.Status.DOWN
		c.status_timer = tk["down_time_big"] if big else tk["down_time"]
		_announce(("BIG HIT" if big else "TACKLE") + " (%s)" % detail)
	else:
		# Drag: a close contest. Closer to a broken tackle means a longer slide.
		var f := inverse_lerp(float(tk["clean_margin"]), float(tk["broken_margin"]), diff)
		var slide := lerpf(float(tk["drag_min_m"]), float(tk["drag_max_m"]), clampf(f, 0.0, 1.0))
		c.status = AthleteState.Status.DOWN
		c.status_timer = tk["down_time"]
		c.speed = sqrt(2.0 * down_decel * slide)
		spot = c.pos + c.heading * slide
		_announce("DRAG %.1f m (%s)" % [slide, detail])
	# Stand-in for the end of the play: the ball is set down where the carrier ends up.
	ball_kind = Ball.LOOSE
	ball_holder = 0
	ball_loose = Vector3(spot.x, float(Tuning.section("throw")["ball_radius"]), spot.y)


func _name(id: int) -> String:
	return "player %d" % id if id > 0 else "bot %d" % -id


# ------------------------------------------------------------------------ ball

## Temporary stand-in for the snap: the ball jumps into this player's hands.
func _sv_take(id: int) -> void:
	if not sv_players.has(id):
		return
	ball_kind = Ball.HELD
	ball_holder = id


func _sv_throw(id: int, charge: float, yaw: float, lob: bool, angle := -1.0) -> void:
	if ball_kind != Ball.HELD or ball_holder != id or not sv_players.has(id):
		return
	var pos: Vector2 = sv_players[id].state.pos
	ball_p0 = Vector3(pos.x, float(Tuning.section("throw")["release_height"]), pos.y)
	ball_yaw = yaw
	ball_charge = clampf(charge, 0.0, 1.0)
	ball_lob = lob
	ball_angle = angle if angle >= 0.0 else -1.0
	ball_launch_tick = sv_tick
	ball_thrower = id
	ball_kind = Ball.FLIGHT
	ball_holder = 0


func _ball_tick(dt: float) -> void:
	if ball_kind != Ball.FLIGHT:
		return
	var fl := BallFlight.launch(ball_p0, ball_yaw, ball_charge, ball_lob, Tuning.data, ball_angle)
	var c: Dictionary = Tuning.section("catch")
	var g: float = Tuning.section("throw")["gravity"]
	var t_now := (sv_tick - ball_launch_tick) * dt
	# Check three points along this tick so a fast ball can't skip through a zone.
	for k in 3:
		var ts := minf(maxf(0.0, t_now - dt * (2 - k) / 3.0), float(fl["T"]))
		var bpos := BallFlight.position_at(ball_p0, fl, g, ts)
		var cands: Array = []
		for id in sv_players:
			if id == ball_thrower and ts < float(c["thrower_grace"]):
				continue
			var p: SvPlayer = sv_players[id]
			var d := CatchRules.zone_distance(p.state.pos, p.state.speed, bpos, Tuning.data)
			if d >= 0.0:
				cands.append([d, id])
		if cands.is_empty():
			continue
		cands.sort()
		if cands.size() > 1 and cands[1][0] - cands[0][0] <= float(c["tie_margin"]):
			ball_kind = Ball.LOOSE      # contested tie: incomplete
			ball_loose = Vector3(bpos.x, float(Tuning.section("throw")["ball_radius"]), bpos.z)
			_log_event("incomplete: tie between %d and %d" % [cands[0][1], cands[1][1]])
		else:
			ball_kind = Ball.HELD
			ball_holder = cands[0][1]
			_log_event("catch by %d (%.2f m from the ball, %d in range)" % [ball_holder, cands[0][0], cands.size()])
		return
	if t_now >= float(fl["T"]):
		ball_kind = Ball.LOOSE
		ball_loose = fl["land"]
		_log_event("incomplete: ball hit the ground")


func _log_event(line: String) -> void:
	if log_enabled:
		_log("[server] " + line)


func local_has_ball() -> bool:
	if mode == Mode.HOST:
		return ball_kind == Ball.HELD and ball_holder == 1
	return mode == Mode.CLIENT and latest_holder == local_id and local_id != 0


## Aim, charge and release. Runs once per tick on whoever is playing locally.
## AIM mode: the camera pitch is the launch angle and holding the throw button sets
## power. HOLD mode: the old charge-for-distance throw.
func _ball_input(inp: Dictionary, dt: float) -> void:
	if inp.get("take", false):
		if mode == Mode.HOST:
			_sv_take(1)
		else:
			_send(func(): if cl_connected: rpc_id(1, "rpc_take_ball"))

	var th := Tuning.section("throw")
	var aiming: bool = inp.get("aiming", false) and local_has_ball()
	var yaw: float = inp.get("yaw", 0.0)
	var lob: bool = inp.get("lob", false)
	var holding: bool = aiming and inp.get("throw", false)
	var power_mode: bool = inp.get("mode", ThrowMode.HOLD) == ThrowMode.AIM
	var angle := -1.0
	var charge_time: float = th["charge_time"]
	if power_mode:
		angle = clampf(inp.get("pitch", 0.0), deg_to_rad(th["angle_min_deg"]), deg_to_rad(th["angle_max_deg"]))
		charge_time = th["power_charge_time"]

	if holding:
		throw_charge = minf(1.0, throw_charge + dt / charge_time)
		throw_charging = true
	elif throw_charging:
		if aiming:   # releasing aim first cancels the throw
			_do_throw(throw_charge, yaw, lob, angle)
		throw_charge = 0.0
		throw_charging = false
	elif aiming and power_mode and inp.get("throw_tap", false):
		_do_throw(0.0, yaw, lob, angle)   # a tap shorter than one tick
	elif not aiming:
		throw_charge = 0.0

	aim_active = aiming
	aim_angle = angle
	aim_lob = lob
	if aiming:
		var here := local_state().pos
		var p0 := Vector3(here.x, float(th["release_height"]), here.y)
		var fl := BallFlight.launch(p0, yaw, throw_charge, lob, Tuning.data, angle)
		aim_pos = Vector2(fl["land"].x, fl["land"].z)
		aim_arc = BallFlight.arc_points(p0, yaw, throw_charge, lob, Tuning.data, angle)
		if power_mode:
			aim_lob = rad_to_deg(angle) >= 30.0   # marker colour only


func _do_throw(charge: float, yaw: float, lob: bool, angle: float) -> void:
	if mode == Mode.HOST:
		_sv_throw(1, charge, yaw, lob, angle)
	else:
		_send(func(): if cl_connected: rpc_id(1, "rpc_throw", charge, yaw, lob, angle))


# -------------------------------------------------------------- reconciliation

func _state_from(a: PackedFloat32Array) -> AthleteState:
	var s := AthleteState.new()
	s.pos = Vector2(a[0], a[1])
	s.heading = Vector2(a[2], a[3])
	s.speed = a[4]
	s.stamina = a[5]
	s.cut_timer = a[6]
	s.cut_cooldown = a[7]
	s.prev_dir = Vector2(a[8], a[9])
	s.status = int(a[10])
	s.status_timer = a[11]
	return s


func _reconcile(a: PackedFloat32Array) -> void:
	var s := _state_from(a)
	var ack := int(a[12])
	if cl_state == null:
		cl_state = s
		cl_prev_pos = s.pos
		return
	while not cl_pending.is_empty() and cl_pending[0][0] <= ack:
		cl_pending.pop_front()
	if cl_sent_time.has(ack):
		rtt = _now() - cl_sent_time[ack]
	for k in cl_sent_time.keys():
		if k <= ack:
			cl_sent_time.erase(k)
	var dt := _tick_dt()
	for e in cl_pending:
		Movement.step(s, e[1], e[2], dt, Tuning.data)
	var shift := s.pos - cl_state.pos
	last_correction = shift.length()
	max_correction = maxf(max_correction, last_correction)
	if last_correction > float(_net()["snap_error_m"]):
		correction = Vector2.ZERO
	else:
		correction -= shift          # keeps what's on screen continuous
	cl_prev_pos += shift
	cl_state = s


# ------------------------------------------------------------------ fake lag

func _send(fn: Callable) -> void:
	var n := _net()
	if randf() * 100.0 < float(n["sim_loss_pct"]):
		return
	var delay := (float(n["sim_latency_ms"]) + randf() * float(n["sim_jitter_ms"])) / 1000.0
	if delay <= 0.0:
		fn.call()
	else:
		_out_queue.append([_now() + delay, fn])


# ---------------------------------------------------------------------- visuals

func _process(delta: float) -> void:
	var now := _now()
	var i := 0
	while i < _out_queue.size():
		if _out_queue[i][0] <= now:
			var fn: Callable = _out_queue[i][1]
			_out_queue.remove_at(i)
			fn.call()
		else:
			i += 1

	if mode == Mode.HOST:
		_update_host_visuals()
	elif mode == Mode.CLIENT and cl_state != null:
		_update_client_visuals(delta)
	if ball_view:
		ball_view.set_aim(aim_active, aim_pos, aim_lob, float(Tuning.section("throw")["marker_radius"]), aim_arc)

	if log_enabled and mode != Mode.NONE:
		_log_timer += delta
		if _log_timer >= 1.0:
			_log_timer = 0.0
			var st := local_state()
			_log("[%s id=%d] ball=%s players=%d rtt=%dms corr_last=%.3f corr_max=%.3f pos=(%.1f,%.1f) speed=%.1f" % [
				"host" if mode == Mode.HOST else "client", local_id, ["loose", "held", "flight"][int(view_ball.get("kind", 0))], athletes.size(), int(rtt * 1000.0),
				last_correction, max_correction, st.pos.x, st.pos.y, st.speed])
			max_correction = 0.0
			for bid in sv_bots:
				var bs: AthleteState = sv_players[bid].state
				_log("    bot %d pos=(%.1f,%.1f) speed=%.1f" % [bid, bs.pos.x, bs.pos.y, bs.speed])


func _log(line: String) -> void:
	print(line)
	var f := FileAccess.open("user://footy_log.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://footy_log.txt") else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)


func local_state() -> AthleteState:
	if mode == Mode.HOST:
		return sv_players[1].state
	return cl_state if cl_state != null else AthleteState.new()


func _alpha() -> float:
	return clampf(_acc / _tick_dt(), 0.0, 1.0)


func _update_host_visuals() -> void:
	var a := _alpha()
	for id in sv_players:
		var p: SvPlayer = sv_players[id]
		_ensure_athlete(id).set_visual(p.prev_pos.lerp(p.state.pos, a), p.state.heading, p.state.speed, p.state.status)
	_show_ball(ball_kind, ball_holder, ball_launch_tick, ball_p0, ball_yaw, ball_charge, ball_lob,
		ball_loose, ball_angle, sv_tick + a)


func _update_client_visuals(delta: float) -> void:
	correction *= exp(-float(_net()["correction_decay"]) * delta)
	var me := _ensure_athlete(local_id)
	me.set_visual(cl_prev_pos.lerp(cl_state.pos, _alpha()) + correction, cl_state.heading, cl_state.speed, cl_state.status)

	if latest_tick < 0:
		return
	var tick_hz := float(_net()["tick_hz"])
	var target := latest_tick - float(_net()["interp_delay_ticks"])
	render_tick += delta * tick_hz
	var err := target - render_tick
	if absf(err) > 2.0:
		render_tick = target
	else:
		render_tick += err * minf(1.0, delta * 2.0)

	while snap_buffer.size() > 2 and snap_buffer[1]["tick"] <= render_tick:
		snap_buffer.pop_front()
	var s0: Dictionary = snap_buffer[0]
	var s1: Dictionary = snap_buffer[snap_buffer.size() - 1] if snap_buffer.size() > 1 else s0
	if snap_buffer.size() > 1:
		s1 = snap_buffer[1]
	var span := float(s1["tick"] - s0["tick"])
	var t := clampf((render_tick - float(s0["tick"])) / span, 0.0, 1.0) if span > 0.0 else 1.0
	for id in s1["players"]:
		if id == local_id:
			continue
		var b: PackedFloat32Array = s1["players"][id]
		var pos := Vector2(b[0], b[1])
		var heading := Vector2(b[2], b[3])
		var spd: float = b[4]
		var st := int(b[10])
		if s0["players"].has(id):
			var a: PackedFloat32Array = s0["players"][id]
			var ah := Vector2(a[2], a[3])
			pos = Vector2(a[0], a[1]).lerp(pos, t)
			heading = ah.slerp(heading, t) if ah.dot(heading) > -0.99 else heading
			spd = lerpf(a[4], spd, t)
		_ensure_athlete(id).set_visual(pos, heading, spd, st)

	var bi: PackedInt32Array = s0["ball_i"]
	var bf: PackedFloat32Array = s0["ball_f"]
	_show_ball(bi[0], bi[1], bi[2], Vector3(bf[0], bf[1], bf[2]), bf[3], bf[4], bf[5] > 0.5,
		Vector3(bf[6], bf[7], bf[8]), bf[9], render_tick)


func _show_ball(kind: int, holder: int, launch_tick: int, p0: Vector3, yaw: float, charge: float,
		lob: bool, loose: Vector3, angle: float, tick_f: float) -> void:
	var th := Tuning.section("throw")
	var pos := loose
	var landing_on := false
	var land := Vector3.ZERO
	if kind == Ball.HELD and athletes.has(holder):
		pos = athletes[holder].position + Vector3(0, float(th["held_height"]), 0)
	elif kind == Ball.FLIGHT:
		var fl := BallFlight.launch(p0, yaw, charge, lob, Tuning.data, angle)
		pos = BallFlight.position_at(p0, fl, float(th["gravity"]), (tick_f - launch_tick) * _tick_dt())
		landing_on = true
		land = fl["land"]
	if log_enabled and view_ball.get("kind", -1) != kind:
		_log("[id=%d] ball -> %s%s" % [local_id, ["loose", "held", "flight"][kind],
			(" land=(%.1f, %.1f) lob=%s" % [land.x, land.z, lob]) if landing_on else ""])
	view_ball = {"kind": kind, "holder": holder}
	if ball_view:
		ball_view.set_ball(pos)
		ball_view.set_landing(landing_on, land, float(th["marker_radius"]))


func _ensure_athlete(id: int) -> Athlete:
	if athletes.has(id):
		return athletes[id]
	var a := Athlete.new()
	a.set_color(Color(0.9, 0.8, 0.2) if id == local_id else (Color(0.75, 0.3, 0.75) if id < 0 else Color(0.3, 0.5, 0.95)))
	athlete_parent.add_child(a)
	athletes[id] = a
	if id == local_id:
		local_ready.emit(a)
	return a


func _remove_athlete(id: int) -> void:
	if athletes.has(id):
		athletes[id].queue_free()
		athletes.erase(id)
