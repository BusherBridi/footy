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

enum Mode { NONE, HOST, CLIENT }

class SvPlayer:
	var state := AthleteState.new()
	var prev_pos := Vector2.ZERO
	var queue: Array = []        # entries: [seq, move, sprint]
	var last_seq := 0            # highest seq received
	var acked := 0               # last seq actually simulated
	var last_move := Vector2.ZERO
	var last_sprint := false

const SNAP_STRIDE := 11   # floats per player (id travels in a separate int array)

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
	return OK


func _on_connected() -> void:
	cl_connected = true
	local_id = multiplayer.get_unique_id()


func _on_lost() -> void:
	mode = Mode.NONE
	multiplayer.multiplayer_peer = null
	for a in athletes.values():
		a.queue_free()
	athletes.clear()
	disconnected.emit()


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


func _sample_input() -> Array:
	return input_provider.call() if input_provider.is_valid() else [Vector2.ZERO, false]


func _host_tick(dt: float) -> void:
	var inp := _sample_input()
	var me: SvPlayer = sv_players[1]
	me.last_seq += 1
	me.queue.append([me.last_seq, inp[0], inp[1]])

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
	var ids := PackedInt32Array()
	var data := PackedFloat32Array()
	for id in sv_players:
		var p: SvPlayer = sv_players[id]
		var s := p.state
		ids.append(id)
		data.append_array([s.pos.x, s.pos.y, s.heading.x, s.heading.y, s.speed, s.stamina,
			s.cut_timer, s.cut_cooldown, s.prev_dir.x, s.prev_dir.y, p.acked])
	for id in multiplayer.get_peers():
		var peer_id: int = id
		var tick := sv_tick
		_send(func(): if multiplayer.get_peers().has(peer_id): rpc_id(peer_id, "rpc_snapshot", tick, ids, data))


func _client_tick(dt: float) -> void:
	if cl_state == null:
		return
	var inp := _sample_input()
	var move: Vector2 = inp[0]
	var sprint: bool = inp[1]
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
func rpc_snapshot(tick: int, ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	if mode != Mode.CLIENT or tick <= latest_tick:
		return
	var players := {}
	for i in ids.size():
		players[ids[i]] = data.slice(i * SNAP_STRIDE, (i + 1) * SNAP_STRIDE)
	latest_tick = tick
	snap_buffer.append({"tick": tick, "players": players})
	if snap_buffer.size() == 1:
		render_tick = tick - float(_net()["interp_delay_ticks"])
	if players.has(local_id):
		_reconcile(players[local_id])
	for id in athletes.keys():
		if not players.has(id):
			_remove_athlete(id)


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
	return s


func _reconcile(a: PackedFloat32Array) -> void:
	var s := _state_from(a)
	var ack := int(a[10])
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

	if log_enabled and mode != Mode.NONE:
		_log_timer += delta
		if _log_timer >= 1.0:
			_log_timer = 0.0
			var st := local_state()
			print("[%s id=%d] players=%d rtt=%dms corr_last=%.3f corr_max=%.3f pos=(%.1f,%.1f) speed=%.1f" % [
				"host" if mode == Mode.HOST else "client", local_id, athletes.size(), int(rtt * 1000.0),
				last_correction, max_correction, st.pos.x, st.pos.y, st.speed])
			max_correction = 0.0


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
		_ensure_athlete(id).set_visual(p.prev_pos.lerp(p.state.pos, a), p.state.heading)


func _update_client_visuals(delta: float) -> void:
	correction *= exp(-float(_net()["correction_decay"]) * delta)
	var me := _ensure_athlete(local_id)
	me.set_visual(cl_prev_pos.lerp(cl_state.pos, _alpha()) + correction, cl_state.heading)

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
		if s0["players"].has(id):
			var a: PackedFloat32Array = s0["players"][id]
			var ah := Vector2(a[2], a[3])
			pos = Vector2(a[0], a[1]).lerp(pos, t)
			heading = ah.slerp(heading, t) if ah.dot(heading) > -0.99 else heading
		_ensure_athlete(id).set_visual(pos, heading)


func _ensure_athlete(id: int) -> Athlete:
	if athletes.has(id):
		return athletes[id]
	var a := Athlete.new()
	a.set_color(Color(0.9, 0.8, 0.2) if id == local_id else Color(0.3, 0.5, 0.95))
	athlete_parent.add_child(a)
	athletes[id] = a
	if id == local_id:
		local_ready.emit(a)
	return a


func _remove_athlete(id: int) -> void:
	if athletes.has(id):
		athletes[id].queue_free()
		athletes.erase(id)
