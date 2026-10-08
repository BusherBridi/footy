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
	var dive_cd := 0.0
	var stiff_timer := 0.0       # >0: a stiff arm is active (the carrier's counter window)
	var wrap_holder := 0         # carrier side: who has hold of me (0 = nobody)
	var wrap_hit := 0.0          # hit power of that first tackle; a joiner adds it to theirs
	var wrap_local := Vector2.ZERO
	var wrap_of := 0             # holder side: whose carrier I'm holding
	var counter_cd := 0.0         # shared by every carrier counter
	var counter_weak := false    # a status counter (spin, truck, hurdle) thrown on an empty bar
	var stiff_weak := false      # fired with too little stamina
	var stiff_side := 0          # which flank the arm covers: -1 left, 0 either (weaker), +1 right
	var fx := 0                  # visual cue: 1 = stiff arm out
	var dodged := false          # this dive was already juked past (announce once)
	var fx_timer := 0.0
	var team := -1               # 0 or 1 in a match; -1 in the sandbox

	func reset_play_fields() -> void:
		tackle_cd = 0.0
		dive_cd = 0.0
		stiff_timer = 0.0
		wrap_holder = 0
		wrap_hit = 0.0
		wrap_of = 0
		counter_cd = 0.0
		counter_weak = false
		stiff_weak = false
		stiff_side = 0
		fx = 0
		fx_timer = 0.0
		dodged = false

enum Ball { LOOSE, HELD, FLIGHT }
enum ThrowMode { AIM, HOLD }   # AIM: pitch = launch angle, hold = power. HOLD: old charge-for-distance throw.

const SNAP_STRIDE := 18   # floats per player (id travels in a separate int array)

var mode := Mode.NONE
var local_id := 0
var input_provider: Callable          # () -> [Vector2 world move, bool sprint]
var athlete_parent: Node3D
var athletes := {}                    # peer id -> Athlete (visual)
var log_enabled := false

# Match (null in the sandbox)
var flow: PlayFlow = null
var autopilot := false                # the host's own athlete is played by the AI (spectate / tests)
var rng := RandomNumberGenerator.new()
var dead_reason := ""                 # set when the ball is ruled dead; the play flow reads it
var dead_spot := Vector2.ZERO
var dead_team := -1                   # team holding the ball when it was ruled dead
var play_view := {}                   # client: latest play state from the server
var team_view := {}                   # client: id -> team from the latest snapshot
var cl_team := -1

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
var ball_lateral := false         # a pitch: if nobody catches it, it stays live like a fumble
var ball_angle := -1.0           # launch angle (radians) for angle+power throws, -1 for the old model
var ball_thrower := 0
var ball_loose := Vector3(0, 0.3, 0)
var ball_live := false           # a fumble: loose, moving, and anyone nearby picks it up
var ball_vel := Vector2.ZERO
var ball_live_age := 0.0
var fumble_roll := -1.0          # tests: force the fumble dice (0 = always, 1 = never)
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
var cl_fx := 0
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


## Start a match on the host: two teams, bots in every empty slot, first play set up.
func start_match() -> void:
	if mode != Mode.HOST:
		return
	rng.randomize()
	host_clear_bots()
	flow = PlayFlow.new(self)
	flow.start()
	if autopilot:
		sv_bots[1] = TeamBot.new()


func add_team_bot(team: int) -> int:
	var id := _next_bot_id
	_next_bot_id -= 1
	_add_sv_player(id)
	sv_players[id].team = team
	sv_bots[id] = TeamBot.new()
	return id


func remove_bot(id: int) -> void:
	sv_players.erase(id)
	sv_bots.erase(id)
	_remove_athlete(id)


func announce(text: String) -> void:
	_announce(text)


func name_of(id: int) -> String:
	return _name(id)


func _live() -> bool:
	return flow == null or flow.is_live()


## Dev helper: a receiver driven by the host itself. It uses the same movement
## code and input queue as a real player, but not the network connection.
func host_add_bot(role := "") -> void:
	if mode != Mode.HOST or flow != null:
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
	if flow != null:
		return
	for id in sv_bots:
		if id == 1:
			continue
		sv_players.erase(id)
		_remove_athlete(id)
	sv_bots.clear()


func _on_peer_connected(id: int) -> void:
	_add_sv_player(id)
	if flow != null:
		flow.on_join(id)


func _on_peer_disconnected(id: int) -> void:
	sv_players.erase(id)
	_remove_athlete(id)
	if flow != null:
		flow.on_leave(id)


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
	if not sv_bots.has(1):
		var inp := _sample_input()
		_ball_input(inp, dt)
		if inp.get("tackle", false):
			_sv_tackle(1, _stick_side(inp))
		if inp.get("dive", false):
			_sv_dive(1)
		if inp.get("lateral", false):
			_sv_lateral(1, inp.get("yaw", 0.0))
		if inp.get("strip", false):
			_sv_strip(1)
		if inp.get("truck", false):
			_sv_counter(1, AthleteState.Status.TRUCK)
		if inp.get("hurdle", false):
			_sv_counter(1, AthleteState.Status.HURDLE)
		if inp.get("try_pick", 0) > 0 and flow != null:
			flow.pick_try(1, int(inp["try_pick"]))
		var me: SvPlayer = sv_players[1]
		me.last_seq += 1
		me.queue.append([me.last_seq, inp["move"], inp["sprint"]])

	for id in sv_players:
		var q: SvPlayer = sv_players[id]
		q.tackle_cd = maxf(0.0, q.tackle_cd - dt)
		q.dive_cd = maxf(0.0, q.dive_cd - dt)
		q.counter_cd = maxf(0.0, q.counter_cd - dt)
		q.stiff_timer = maxf(0.0, q.stiff_timer - dt)
		q.fx_timer = maxf(0.0, q.fx_timer - dt)
		if q.fx_timer <= 0.0:
			q.fx = 0
	for id in sv_bots.keys():
		if sv_bots[id] is TeamBot:
			if flow != null and sv_players.has(id):
				_team_bot_tick(id, dt)
			continue
		var bp: SvPlayer = sv_players[id]
		var ctx := {"heading": bp.state.heading, "holding": bp.wrap_of != 0}
		if ball_kind == Ball.HELD and ball_holder != id and sv_players.has(ball_holder):
			ctx["carrier_wrapped"] = sv_players[ball_holder].wrap_holder != 0
			var cs: AthleteState = sv_players[ball_holder].state
			ctx["carrier"] = cs.pos
			ctx["carrier_vel"] = cs.heading * cs.speed
		var bi: Dictionary = sv_bots[id].think(bp.state.pos, dt, Tuning.data, false, ctx)
		bp.last_seq += 1
		bp.queue.append([bp.last_seq, bi["move"], bi["sprint"]])
		if bi.get("tackle", false):
			_sv_tackle(id)
		if bi.get("dive", false):
			_sv_dive(id)
		if bi.get("strip", false):
			_sv_strip(id)

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
		p.state.carrying = ball_kind == Ball.HELD and ball_holder == id
		Movement.step(p.state, p.last_move, p.last_sprint, dt, Tuning.data)

	_wrap_tick()
	_check_dives()
	sv_tick += 1
	_ball_tick(dt)
	if flow != null:
		flow.tick(dt)
	var ids := PackedInt32Array()
	var data := PackedFloat32Array()
	for id in sv_players:
		var p: SvPlayer = sv_players[id]
		var s := p.state
		ids.append(id)
		data.append_array([s.pos.x, s.pos.y, s.heading.x, s.heading.y, s.speed, s.stamina,
			s.cut_timer, s.cut_cooldown, s.prev_dir.x, s.prev_dir.y, s.status, s.status_timer, s.juke_timer, float(s.spin_side), p.fx, p.team, 1.0 if s.carrying else 0.0, p.acked])
	var ball_i := PackedInt32Array([ball_kind, ball_holder, ball_launch_tick])
	var ball_f := PackedFloat32Array([ball_p0.x, ball_p0.y, ball_p0.z, ball_yaw, ball_charge,
		1.0 if ball_lob else 0.0, ball_loose.x, ball_loose.y, ball_loose.z, ball_angle])
	var play_i := PackedInt32Array([-1, 0, 0, 0, 0, 0, 0, 0, 0])
	var play_f := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	if flow != null:
		var v := flow.view()
		play_i = PackedInt32Array([v["phase"], v["offense"], v["dir"], v["qb"], v["play_no"], v["down"], v["score0"], v["score1"], v["try"]])
		play_f = PackedFloat32Array([v["los"], v["rush"], v["phase_time"], v["gain"]])
	for id in multiplayer.get_peers():
		var peer_id: int = id
		var tick := sv_tick
		_send(func(): if multiplayer.get_peers().has(peer_id): rpc_id(peer_id, "rpc_snapshot", tick, ids, data, ball_i, ball_f, play_i, play_f))


## A match bot: build its picture of the field, run its brain, apply its inputs.
func _team_bot_tick(id: int, dt: float) -> void:
	var bp: SvPlayer = sv_players[id]
	var bi: Dictionary = sv_bots[id].think(flow.bot_context(id), dt, Tuning.data)
	bp.last_seq += 1
	bp.queue.append([bp.last_seq, bi["move"], bi["sprint"]])
	if bi.get("try_pick", 0) > 0:
		flow.pick_try(id, int(bi["try_pick"]))
	if bi.get("take", false):
		_sv_take(id)
	if bi.has("pass_to"):
		_bot_pass(id, bi["pass_to"], bi.get("lob", false))
	if bi.get("lateral", false):
		_sv_lateral(id, bi.get("yaw", 0.0))
	if bi.get("tackle", false):
		_sv_tackle(id, int(bi.get("side", 0)))
	if bi.get("dive", false):
		_sv_dive(id)
	if bi.get("strip", false):
		_sv_strip(id)
	if bi.get("truck", false):
		_sv_counter(id, AthleteState.Status.TRUCK)
	if bi.get("hurdle", false):
		_sv_counter(id, AthleteState.Status.HURDLE)


## Bots throw with the charge-for-distance model: it lands exactly where they aim.
func _bot_pass(id: int, target: Vector2, lob: bool) -> void:
	if not sv_players.has(id):
		return
	var th := Tuning.section("throw")
	var rel: Vector2 = target - sv_players[id].state.pos
	var dist := clampf(rel.length(), float(th["min_range"]), float(th["max_range"]))
	var yaw := atan2(-rel.x, -rel.y)
	_sv_throw(id, inverse_lerp(float(th["min_range"]), float(th["max_range"]), dist), yaw, lob, -1.0)


func _client_tick(dt: float) -> void:
	if cl_state == null:
		return
	var inp := _sample_input()
	_ball_input(inp, dt)
	if inp.get("tackle", false):
		var tk_side := _stick_side(inp)
		_send(func(): if cl_connected: rpc_id(1, "rpc_tackle", tk_side))
	if inp.get("dive", false):
		_send(func(): if cl_connected: rpc_id(1, "rpc_dive"))
	if inp.get("lateral", false):
		var lat_yaw: float = inp.get("yaw", 0.0)
		_send(func(): if cl_connected: rpc_id(1, "rpc_lateral", lat_yaw))
	if inp.get("strip", false):
		_send(func(): if cl_connected: rpc_id(1, "rpc_strip"))
	if inp.get("try_pick", 0) > 0:
		var pick := int(inp["try_pick"])
		_send(func(): if cl_connected: rpc_id(1, "rpc_try_pick", pick))
	if inp.get("truck", false):
		_send(func(): if cl_connected: rpc_id(1, "rpc_counter", AthleteState.Status.TRUCK))
	if inp.get("hurdle", false):
		_send(func(): if cl_connected: rpc_id(1, "rpc_counter", AthleteState.Status.HURDLE))
	var move: Vector2 = inp["move"]
	var sprint: bool = inp["sprint"]
	cl_seq += 1
	cl_prev_pos = cl_state.pos
	cl_state.carrying = local_has_ball()
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
func rpc_snapshot(tick: int, ids: PackedInt32Array, data: PackedFloat32Array, ball_i: PackedInt32Array, ball_f: PackedFloat32Array, play_i: PackedInt32Array, play_f: PackedFloat32Array) -> void:
	if mode != Mode.CLIENT or tick <= latest_tick:
		return
	var players := {}
	for i in ids.size():
		players[ids[i]] = data.slice(i * SNAP_STRIDE, (i + 1) * SNAP_STRIDE)
		team_view[ids[i]] = int(data[i * SNAP_STRIDE + 15])
	play_view = {} if play_i[0] < 0 else {"phase": play_i[0], "offense": play_i[1], "dir": play_i[2],
		"qb": play_i[3], "play_no": play_i[4], "down": play_i[5], "score0": play_i[6], "score1": play_i[7],
		"try": play_i[8], "los": play_f[0], "rush": play_f[1], "phase_time": play_f[2], "gain": play_f[3]}
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
func rpc_tackle(side: int) -> void:
	if mode == Mode.HOST:
		_sv_tackle(multiplayer.get_remote_sender_id(), clampi(side, -1, 1))


## Which flank the stick points to, relative to the way you're running (-1 left, 0 neither, +1 right).
func _stick_side(inp: Dictionary) -> int:
	var m: Dictionary = Tuning.section("movement")
	var mv: Vector2 = inp.get("move", Vector2.ZERO)
	if mv.length() < float(m["spin_side_input"]):
		return 0
	var cr := local_state().heading.cross(mv.normalized())
	if absf(cr) < float(m["spin_side_cross"]):
		return 0
	return 1 if cr > 0.0 else -1


@rpc("any_peer", "reliable")
func rpc_dive() -> void:
	if mode == Mode.HOST:
		_sv_dive(multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func rpc_lateral(yaw: float) -> void:
	if mode == Mode.HOST:
		_sv_lateral(multiplayer.get_remote_sender_id(), yaw)


@rpc("any_peer", "reliable")
func rpc_try_pick(points: int) -> void:
	if mode == Mode.HOST and flow != null:
		flow.pick_try(multiplayer.get_remote_sender_id(), points)


@rpc("any_peer", "reliable")
func rpc_strip() -> void:
	if mode == Mode.HOST:
		_sv_strip(multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func rpc_counter(kind: int) -> void:
	if mode == Mode.HOST:
		_sv_counter(multiplayer.get_remote_sender_id(), kind)


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
func _sv_tackle(id: int, side := 0) -> void:
	var p: SvPlayer = sv_players.get(id)
	if p == null or p.state.status == AthleteState.Status.DOWN or p.tackle_cd > 0.0 or not _live():
		return
	if p.state.status == AthleteState.Status.DIVING:
		return        # mid-dive you're committed: the dive itself is your tackle
	if flow != null and ball_kind == Ball.HELD and ball_holder != id and not flow.can_tackle(id, ball_holder):
		return        # the carrier is a teammate (blocking comes later)
	var tk: Dictionary = Tuning.section("tackle")
	if p.wrap_of != 0:
		# Holding a carrier: pressing tackle again lets go.
		if p.tackle_cd <= 0.0:
			p.tackle_cd = tk["cooldown"]
			_end_wrap(p.wrap_of, false)
			_announce("%s lets go" % _name(id))
		return
	if ball_kind == Ball.HELD and ball_holder == id:
		_sv_stiffarm(id, side)       # same button: with the ball it's a stiff arm
		return
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


func _resolve_tackle(tackler_id: int, carrier_id: int, dive := false) -> void:
	var tk: Dictionary = Tuning.section("tackle")
	var mv: Dictionary = Tuning.section("movement")
	var t: AthleteState = sv_players[tackler_id].state
	var c: AthleteState = sv_players[carrier_id].state

	var to_tackler := (t.pos - c.pos).normalized()
	var facing := c.heading.dot(to_tackler)      # +1: tackler is in front of the carrier
	var closing := maxf(0.0, (t.heading * t.speed).dot(-to_tackler))
	var behind: bool = facing <= float(tk["behind_cos"])
	var balance_factor: float = tk["head_on_balance_factor"]
	if behind:
		balance_factor = tk["behind_balance_factor"]
	elif facing < float(tk["front_cos"]):
		balance_factor = tk["side_balance_factor"]
	var weight: float = tk["weight"]
	var hit: float = weight * (float(tk["hit_base"]) + closing)
	if dive:
		hit *= float(tk["dive_hit_factor"])
	var balance: float = weight * (float(tk["balance_base"]) + c.speed * balance_factor)
	var cp: SvPlayer = sv_players[carrier_id]
	var counter_note := ""
	var fumble_chance := 0.0
	# A second defender joining a wrap adds the first tackler's hit power to theirs.
	var joined: bool = cp.wrap_holder != 0 and cp.wrap_holder != tackler_id
	if joined:
		hit += cp.wrap_hit * float(tk["join_hit_factor"])
		counter_note += " + first tackler %.1f" % cp.wrap_hit
	if not dive and c.juke_timer > 0.0:
		# A juke is weak against a close tackle: the plant leaves you off balance.
		balance -= float(tk["juke_close_penalty"])
		counter_note += " - juke %.1f" % float(tk["juke_close_penalty"])
	if not dive and cp.stiff_timer > 0.0:
		# A well-timed stiff arm adds balance against a close tackle (not a dive), at full
		# strength from the side, and weaker still with an empty stamina bar.
		var bonus: float = tk["stiff_bonus"]
		if cp.stiff_weak:
			bonus *= float(tk["counter_weak_mult"])
		# The arm goes out to the side: it answers a tackler coming at your flank.
		if behind:
			bonus *= float(tk["stiff_behind_mult"])
		elif facing >= float(tk["front_cos"]):
			bonus *= float(tk["stiff_front_mult"])
		else:
			# On the flank: full strength if the arm is out on the tackler's side, a little
			# if it's out on the other side, and in between if no side was chosen.
			bonus *= float(tk["stiff_side_mult"])
			var tackler_side := 1 if c.heading.cross(to_tackler) > 0.0 else -1
			if cp.stiff_side == 0:
				bonus *= float(tk["stiff_unset_mult"])
			elif cp.stiff_side != tackler_side:
				bonus *= float(tk["stiff_far_side_mult"])
		balance += bonus
		counter_note += " + stiff arm %.1f" % bonus
		cp.stiff_timer = 0.0
	var is_front: bool = facing >= float(tk["front_cos"])
	var weak_mult: float = tk["counter_weak_mult"] if cp.counter_weak else 1.0
	match c.status:
		AthleteState.Status.TRUCK:
			# Beats close tackles and head-on hits. A big bonus from the front, easy to hit from the side.
			var b: float = float(tk["truck_bonus"]) * weak_mult
			if behind:
				b = 0.0
			elif not is_front:
				b *= float(tk["truck_side_mult"])
			balance += b
			counter_note += " + truck %.1f" % b
		AthleteState.Status.SPIN:
			# Spinning leaves you wide open: a huge balance loss, and a likely fumble.
			balance -= float(tk["spin_balance_penalty"])
			fumble_chance = maxf(fumble_chance, float(tk["spin_fumble_chance"]))
			counter_note += " - spin %.1f" % float(tk["spin_balance_penalty"])
		AthleteState.Status.HURDLE:
			# Hit in the air by a defender on their feet: a big hit.
			if not dive:
				fumble_chance = maxf(fumble_chance, float(tk["hurdle_fumble_chance"]))
				balance -= float(tk["hurdle_close_penalty"])
				counter_note += " - hurdle %.1f" % float(tk["hurdle_close_penalty"])
	var diff := hit - balance
	var angle_name := "from behind" if behind else ("head-on" if facing >= float(tk["front_cos"]) else "from the side")
	var detail := "%s %s %s: hit %.1f vs balance %.1f%s" % [_name(tackler_id), "dove" if dive else "hit", angle_name, hit, balance, counter_note]

	# A tackler needs some speed to put a carrier down alone. Without it (or in a close
	# contest) the best they can do is wrap him up and wait for help or for him to tire.
	# A carrier caught mid-spin or mid-hurdle is defenceless, so even a standing tackler drops him.
	var defenceless: bool = c.status == AthleteState.Status.SPIN or c.status == AthleteState.Status.HURDLE
	var can_takedown: bool = closing >= float(tk["takedown_speed"]) or joined or defenceless
	if diff < float(tk["broken_margin"]):
		c.status = AthleteState.Status.STUMBLE
		c.status_timer = tk["broken_stumble_time"]
		c.speed *= tk["broken_speed_keep"]
		t.status = AthleteState.Status.STUMBLE
		t.status_timer = tk["defender_stumble_time"]
		_end_wrap(carrier_id, false)
		_announce("BROKEN TACKLE (%s)" % detail)
		_after_dive(t, dive)
		return
	if diff < float(tk["clean_margin"]) or not can_takedown:
		_start_wrap(tackler_id, carrier_id, hit)
		_announce("WRAPPED UP (%s)" % detail)
		return

	var big: bool = diff >= float(tk["big_hit_margin"]) and not behind
	c.status = AthleteState.Status.DOWN
	c.status_timer = tk["down_time_big"] if big else tk["down_time"]
	_end_wrap(carrier_id, false)
	_announce(("BIG HIT" if big else "TACKLE") + " (%s)" % detail)
	if big:
		fumble_chance = maxf(fumble_chance, float(tk["big_hit_fumble_chance"]))
	var roll: float = fumble_roll if fumble_roll >= 0.0 else randf()
	if roll < fumble_chance:
		_fumble(carrier_id, c.pos)
	else:
		_set_ball_down(c.pos)
	_after_dive(t, dive)


## Stand-in for the end of the play: the ball is set down where the carrier ended up.
func _set_ball_down(spot: Vector2, reason := "Tackled") -> void:
	dead_reason = reason
	dead_spot = spot
	dead_team = sv_players[ball_holder].team if ball_kind == Ball.HELD and sv_players.has(ball_holder) else -1
	ball_kind = Ball.LOOSE
	ball_holder = 0
	ball_live = false
	ball_loose = Vector3(spot.x, float(Tuning.section("throw")["ball_radius"]), spot.y)


func _start_wrap(holder_id: int, carrier_id: int, hit: float) -> void:
	var tk: Dictionary = Tuning.section("tackle")
	var h: SvPlayer = sv_players[holder_id]
	var c: SvPlayer = sv_players[carrier_id]
	var rel := h.state.pos - c.state.pos
	if rel.length() < 0.1:
		rel = -c.state.heading
	c.wrap_holder = holder_id
	c.wrap_hit = hit
	c.wrap_local = rel.normalized().rotated(-c.state.heading.angle())
	h.wrap_of = carrier_id
	c.state.status = AthleteState.Status.WRAPPED
	c.state.status_timer = tk["wrap_max_time"]
	c.state.cut_timer = 0.0
	h.state.status = AthleteState.Status.HOLDING
	h.state.status_timer = tk["wrap_max_time"]
	h.state.speed = c.state.speed


## Let go: the holder is freed (stumbling if the carrier shook them off).
func _end_wrap(carrier_id: int, stumble_holder: bool) -> void:
	var c: SvPlayer = sv_players.get(carrier_id)
	if c == null or c.wrap_holder == 0:
		return
	var tk: Dictionary = Tuning.section("tackle")
	var h: SvPlayer = sv_players.get(c.wrap_holder)
	if h != null:
		h.wrap_of = 0
		if h.state.status == AthleteState.Status.HOLDING:
			h.state.status = AthleteState.Status.STUMBLE if stumble_holder else AthleteState.Status.OK
			h.state.status_timer = tk["defender_stumble_time"] if stumble_holder else 0.0
	if c.state.status == AthleteState.Status.WRAPPED:
		c.state.status = AthleteState.Status.OK
		c.state.status_timer = 0.0
	c.wrap_holder = 0
	c.wrap_hit = 0.0


## Each tick: keep the holder attached, and drop a carrier who has run out of stamina.
func _wrap_tick() -> void:
	var tk: Dictionary = Tuning.section("tackle")
	for cid in sv_players.keys():
		var c: SvPlayer = sv_players[cid]
		if c.wrap_holder == 0:
			continue
		var h: SvPlayer = sv_players.get(c.wrap_holder)
		if h == null or c.state.status != AthleteState.Status.WRAPPED \
				or h.state.status != AthleteState.Status.HOLDING \
				or ball_kind != Ball.HELD or ball_holder != cid:
			_end_wrap(cid, false)
			continue
		if c.state.stamina <= 0.0:
			c.state.status = AthleteState.Status.DOWN
			c.state.status_timer = tk["down_time"]
			var holder_id := c.wrap_holder
			_end_wrap(cid, false)
			_set_ball_down(c.state.pos, "Worn down")
			_announce("WORN DOWN: %s ran out of stamina with %s hanging on" % [_name(cid), _name(holder_id)])
			continue
		h.state.pos = c.state.pos + c.wrap_local.rotated(c.state.heading.angle()) * float(tk["wrap_offset"])
		var to_c := c.state.pos - h.state.pos
		if to_c.length() > 0.01:
			h.state.heading = to_c.normalized()
		h.state.speed = c.state.speed


func _after_dive(t: AthleteState, dive: bool) -> void:
	if dive:
		var tk: Dictionary = Tuning.section("tackle")
		t.status = AthleteState.Status.DOWN
		t.status_timer = tk["dive_hit_ground_time"]


func _sv_dive(id: int) -> void:
	var p: SvPlayer = sv_players.get(id)
	if p == null or p.state.status != AthleteState.Status.OK or not _live():
		return
	if ball_kind == Ball.HELD and ball_holder == id:
		_sv_counter(id, AthleteState.Status.SPIN)     # same button: with the ball it's a spin
		return
	if p.dive_cd > 0.0:
		return
	var tk: Dictionary = Tuning.section("tackle")
	p.dive_cd = tk["dive_cooldown"]
	p.dodged = false
	p.state.status = AthleteState.Status.DIVING
	p.state.status_timer = tk["dive_time"]
	p.state.speed = maxf(p.state.speed * float(tk["dive_speed_mult"]), float(tk["dive_min_speed"]))
	p.state.cut_timer = 0.0


## A diver connects with the carrier if they get within the hit radius while airborne.
func _check_dives() -> void:
	if ball_kind != Ball.HELD or not sv_players.has(ball_holder):
		return
	var tk: Dictionary = Tuning.section("tackle")
	var carrier: SvPlayer = sv_players[ball_holder]
	for id in sv_players:
		var p: SvPlayer = sv_players[id]
		if id == ball_holder or p.state.status != AthleteState.Status.DIVING:
			continue
		if flow != null and not flow.can_tackle(id, ball_holder):
			continue
		if p.state.pos.distance_to(carrier.state.pos) <= float(tk["dive_hit_radius"]):
			var hurdled: bool = carrier.state.status == AthleteState.Status.HURDLE and not carrier.counter_weak
			if carrier.state.juke_timer > 0.0 or hurdled:
				# A well-timed juke or hurdle beats a dive: the diver sails through and hits the ground.
				if not p.dodged:
					p.dodged = true
					_announce("%s! %s dove past %s" % ["HURDLED" if hurdled else "JUKED", _name(id), _name(ball_holder)])
				continue
			_resolve_tackle(id, ball_holder, true)
			return


## A joining defender rips at the ball instead of adding hit power. The more tired the
## carrier, the better the odds. A failed strip does nothing (their hit never counts).
func _sv_strip(id: int) -> void:
	var p: SvPlayer = sv_players.get(id)
	if p == null or p.state.status == AthleteState.Status.DOWN or p.tackle_cd > 0.0 or not _live():
		return
	if ball_kind != Ball.HELD or ball_holder == id or not sv_players.has(ball_holder):
		return
	if flow != null and not flow.can_tackle(id, ball_holder):
		return
	var cp: SvPlayer = sv_players[ball_holder]
	var tk: Dictionary = Tuning.section("tackle")
	if cp.wrap_holder == 0 or cp.wrap_holder == id:
		return        # only a joiner, and only on a carrier who is already wrapped up
	if p.state.pos.distance_to(cp.state.pos) > float(tk["strip_reach"]):
		return
	p.tackle_cd = tk["strip_cooldown"]
	var chance := lerpf(float(tk["strip_chance_empty"]), float(tk["strip_chance_full"]), clampf(cp.state.stamina, 0.0, 1.0))
	var roll: float = fumble_roll if fumble_roll >= 0.0 else randf()
	if roll < chance:
		var cid := ball_holder
		_end_wrap(cid, false)
		cp.state.status = AthleteState.Status.STUMBLE
		cp.state.status_timer = tk["strip_carrier_stumble"]
		_announce("STRIPPED! %s rips it from %s (%d%% chance)" % [_name(id), _name(cid), int(chance * 100.0)])
		_fumble(cid, cp.state.pos)
	else:
		_announce("%s tried to strip it and failed (%d%% chance)" % [_name(id), int(chance * 100.0)])


## Carrier counters that put you in a movement state: spin, truck, hurdle.
func _sv_counter(id: int, kind: int) -> void:
	var p: SvPlayer = sv_players.get(id)
	if p == null or p.counter_cd > 0.0 or not _live():
		return
	var wrapped_now: bool = p.state.status == AthleteState.Status.WRAPPED
	if p.state.status != AthleteState.Status.OK and not (wrapped_now and (kind == AthleteState.Status.SPIN or kind == AthleteState.Status.TRUCK)):
		return
	if ball_kind != Ball.HELD or ball_holder != id:
		return
	var tk: Dictionary = Tuning.section("tackle")
	var name := ""
	var time := 0.0
	var cost := 0.0
	match kind:
		AthleteState.Status.SPIN:
			name = "spin"; time = tk["spin_time"]; cost = tk["spin_cost"]
		AthleteState.Status.TRUCK:
			name = "truck"; time = tk["truck_time"]; cost = tk["truck_cost"]
		AthleteState.Status.HURDLE:
			name = "hurdle"; time = tk["hurdle_time"]; cost = tk["hurdle_cost"]
		_:
			return
	p.counter_cd = tk["counter_cooldown"]
	p.counter_weak = p.state.stamina < cost
	p.state.stamina = maxf(0.0, p.state.stamina - cost)
	if wrapped_now:
		# Break the hold. A spin always slips out; a truck only if it out-muscles the holder.
		var power := float(tk["truck_bonus"]) * (float(tk["counter_weak_mult"]) if p.counter_weak else 1.0)
		if kind == AthleteState.Status.TRUCK and power < p.wrap_hit:
			_announce("%s tried to truck out of the hold and couldn't" % _name(id))
			return
		_end_wrap(id, true)
		_announce("%s breaks the hold with a %s" % [_name(id), name])
	p.state.status = kind
	p.state.status_timer = time
	p.state.cut_timer = 0.0
	if kind == AthleteState.Status.SPIN:
		p.state.speed *= float(Tuning.section("movement")["spin_speed_mult"])
		p.state.spin_side = 0
	_log_event("%s: %s%s" % [_name(id), name, " (weak)" if p.counter_weak else ""])


func _sv_stiffarm(id: int, side := 0) -> void:
	var p: SvPlayer = sv_players.get(id)
	var wrapped_now: bool = p != null and p.state.status == AthleteState.Status.WRAPPED
	if p == null or p.counter_cd > 0.0 or (p.state.status != AthleteState.Status.OK and not wrapped_now):
		return
	var tk: Dictionary = Tuning.section("tackle")
	if wrapped_now:
		# Shove the holder off: costs stamina, fails if you're too tired to shove.
		p.counter_cd = tk["counter_cooldown"]
		var weak: bool = p.state.stamina < float(tk["stiff_cost"])
		p.state.stamina = maxf(0.0, p.state.stamina - float(tk["stiff_cost"]))
		p.fx = 1
		p.fx_timer = tk["stiff_fx_time"]
		if weak:
			_announce("%s was too tired to shove the holder off" % _name(id))
		else:
			_end_wrap(id, true)
			_announce("%s shoves the holder off" % _name(id))
		return
	p.counter_cd = tk["counter_cooldown"]
	p.stiff_timer = tk["stiff_window"]
	p.stiff_side = side
	p.stiff_weak = p.state.stamina < float(tk["stiff_cost"])
	p.state.stamina = maxf(0.0, p.state.stamina - float(tk["stiff_cost"]))
	p.fx = 1 if side == 0 else (2 if side < 0 else 3)     # 1 forward, 2 left arm, 3 right arm
	p.fx_timer = tk["stiff_fx_time"]


const TEAM_NAMES := ["Orange", "Blue"]


func _name(id: int) -> String:
	var n := "player %d" % id if id > 0 else "bot %d" % -id
	if flow != null and sv_players.has(id) and sv_players[id].team >= 0:
		n += " (%s)" % TEAM_NAMES[sv_players[id].team]
	return n


# ------------------------------------------------------------------------ ball

## Temporary stand-in for the snap: the ball jumps into this player's hands.
func _sv_take(id: int) -> void:
	if not sv_players.has(id):
		return
	if flow != null:
		flow.request_snap(id)       # in a match, E is the snap
		return
	ball_kind = Ball.HELD
	ball_holder = id
	ball_live = false


func _sv_throw(id: int, charge: float, yaw: float, lob: bool, angle := -1.0) -> void:
	if ball_kind != Ball.HELD or ball_holder != id or not sv_players.has(id) or not _live():
		return
	var pos: Vector2 = sv_players[id].state.pos
	ball_p0 = Vector3(pos.x, float(Tuning.section("throw")["release_height"]), pos.y)
	ball_yaw = yaw
	ball_charge = clampf(charge, 0.0, 1.0)
	ball_lob = lob
	ball_angle = angle if angle >= 0.0 else -1.0
	ball_live = false
	ball_lateral = false
	ball_launch_tick = sv_tick
	ball_thrower = id
	ball_kind = Ball.FLIGHT
	ball_holder = 0


## A pitch: a short, flat toss that may only go backward or sideways (upfield is -z).
func _sv_lateral(id: int, yaw: float) -> void:
	var p: SvPlayer = sv_players.get(id)
	if p == null or ball_kind != Ball.HELD or ball_holder != id or p.state.status == AthleteState.Status.DOWN or not _live():
		return
	var th: Dictionary = Tuning.section("throw")
	var dir := Vector2(-sin(yaw), -cos(yaw))
	var upfield := Vector2(0.0, -1.0) if flow == null else Vector2(0.0, float(flow.team_dir(p.team)))
	if dir.dot(upfield) > sin(deg_to_rad(float(th["lateral_forward_slack_deg"]))):
		_announce("%s can't pitch the ball forward" % _name(id))
		return
	ball_p0 = Vector3(p.state.pos.x, float(th["lateral_release_height"]), p.state.pos.y)
	ball_yaw = yaw
	ball_charge = inverse_lerp(float(th["min_range"]), float(th["max_range"]), float(th["lateral_range"]))
	ball_lob = false
	ball_angle = -1.0
	ball_live = false
	ball_lateral = true
	ball_launch_tick = sv_tick
	ball_thrower = id
	ball_kind = Ball.FLIGHT
	ball_holder = 0
	_log_event("%s pitches it back" % _name(id))


func _ball_tick(dt: float) -> void:
	if ball_kind == Ball.LOOSE and ball_live:
		_fumble_tick(dt)
		return
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
		if ball_lateral and Vector2(bpos.x - ball_p0.x, bpos.z - ball_p0.z).length() < float(Tuning.section("throw")["lateral_min_travel"]):
			continue       # a pitch can't be grabbed right at the thrower's hands
		var cands: Array = []
		for id in sv_players:
			if id == ball_thrower and ts < float(c["thrower_grace"]):
				continue
			if flow != null and not flow.can_catch(id, ball_thrower):
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
			_loose_after_flight()
			_log_event("incomplete: tie between %d and %d" % [cands[0][1], cands[1][1]])
		else:
			ball_kind = Ball.HELD
			ball_holder = cands[0][1]
			ball_live = false
			var cpos: Vector2 = sv_players[ball_holder].state.pos
			var open_by := INF
			for oid in sv_players:
				if sv_players[oid].team != sv_players[ball_holder].team:
					open_by = minf(open_by, sv_players[oid].state.pos.distance_to(cpos))
			var depth := 0.0
			if flow != null:
				depth = (cpos.y - flow.los_z) * flow.dir() / flow.yard()
			_log_event("catch by %s (%.2f m from the ball, %d in range) %.0f yards downfield, nearest defender %.1f m" % [_name(ball_holder), cands[0][0], cands.size(), depth, open_by])
		return
	if t_now >= float(fl["T"]):
		ball_kind = Ball.LOOSE
		ball_loose = fl["land"]
		_loose_after_flight()
		_log_event("lateral hit the ground (live ball)" if ball_lateral else "incomplete: ball hit the ground")


## An incomplete forward pass is dead; a dropped lateral is a live ball anyone can recover.
func _loose_after_flight() -> void:
	ball_live = ball_lateral
	if not ball_lateral:
		dead_reason = "incomplete"
	ball_vel = Vector2.ZERO
	ball_live_age = 0.0


## A live loose ball slides to a stop; anyone on their feet who gets close picks it up.
func _fumble_tick(dt: float) -> void:
	var tk: Dictionary = Tuning.section("tackle")
	var speed := ball_vel.length()
	if speed > 0.0:
		speed = maxf(0.0, speed - float(tk["fumble_friction"]) * dt)
		ball_vel = ball_vel.normalized() * speed
		var f: Dictionary = Tuning.section("field")
		var yard: float = f["yard_m"]
		var margin: float = f.get("oob_margin_m", 0.0)
		var hl: float = (float(f["length_yards"]) * 0.5 + float(f["endzone_yards"])) * yard + margin
		var hw: float = float(f["width_yards"]) * 0.5 * yard + margin
		ball_loose.x = clampf(ball_loose.x + ball_vel.x * dt, -hw, hw)
		ball_loose.z = clampf(ball_loose.z + ball_vel.y * dt, -hl, hl)
	ball_live_age += dt
	if ball_live_age < float(tk["fumble_pickup_delay"]):
		return        # the ball is still popping free
	var best := 0
	var best_d := float(tk["fumble_pickup_radius"])
	for id in sv_players:
		var p: SvPlayer = sv_players[id]
		if p.state.status == AthleteState.Status.DOWN:
			continue
		var d := p.state.pos.distance_to(Vector2(ball_loose.x, ball_loose.z))
		if d <= best_d:
			best_d = d
			best = id
	if best != 0:
		ball_kind = Ball.HELD
		ball_holder = best
		ball_live = false
		_announce("%s recovers the fumble" % _name(best))


func _fumble(carrier_id: int, at: Vector2) -> void:
	var tk: Dictionary = Tuning.section("tackle")
	var ang := randf() * TAU
	ball_kind = Ball.LOOSE
	ball_holder = 0
	ball_live = true
	ball_live_age = 0.0
	ball_vel = Vector2(cos(ang), sin(ang)) * float(tk["fumble_pop_speed"])
	ball_loose = Vector3(at.x, float(Tuning.section("throw")["ball_radius"]), at.y)
	_announce("FUMBLE! %s drops the ball" % _name(carrier_id))


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
	s.juke_timer = a[12]
	s.spin_side = int(a[13])
	s.carrying = a[16] > 0.5
	return s


func _reconcile(a: PackedFloat32Array) -> void:
	var s := _state_from(a)
	var ack := int(a[17])
	cl_fx = int(a[14])
	cl_team = int(a[15])
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


## Play state for the HUD and field markings (empty outside a match).
func get_play_view() -> Dictionary:
	if mode == Mode.HOST:
		return flow.view() if flow != null else {}
	return play_view


func team_of_id(id: int) -> int:
	if mode == Mode.HOST:
		return sv_players[id].team if sv_players.has(id) else -1
	return cl_team if id == local_id else int(team_view.get(id, -1))


func local_team() -> int:
	return team_of_id(local_id)


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
		var ath := _ensure_athlete(id)
		ath.set_team(p.team, id == local_id)
		ath.set_visual(p.prev_pos.lerp(p.state.pos, a), p.state.heading, p.state.speed, p.state.status, p.fx, p.state.juke_timer > 0.0)
	_show_ball(ball_kind, ball_holder, ball_launch_tick, ball_p0, ball_yaw, ball_charge, ball_lob,
		ball_loose, ball_angle, sv_tick + a)


func _update_client_visuals(delta: float) -> void:
	correction *= exp(-float(_net()["correction_decay"]) * delta)
	var me := _ensure_athlete(local_id)
	me.set_team(cl_team, true)
	me.set_visual(cl_prev_pos.lerp(cl_state.pos, _alpha()) + correction, cl_state.heading, cl_state.speed, cl_state.status, cl_fx, cl_state.juke_timer > 0.0)

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
		var fx := int(b[14])
		var jk: bool = b[12] > 0.0
		if s0["players"].has(id):
			var a: PackedFloat32Array = s0["players"][id]
			var ah := Vector2(a[2], a[3])
			pos = Vector2(a[0], a[1]).lerp(pos, t)
			heading = ah.slerp(heading, t) if ah.dot(heading) > -0.99 else heading
			spd = lerpf(a[4], spd, t)
		var ath := _ensure_athlete(id)
		ath.set_team(int(b[15]), false)
		ath.set_visual(pos, heading, spd, st, fx, jk)

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
