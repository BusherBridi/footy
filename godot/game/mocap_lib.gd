class_name MocapLib
extends RefCounted
## CMU mocap clips (godot/assets/mocap_clips, retargeted onto the humanoid profile at import)
## made ready for our mannequin: the hips' travel across the ground is removed (our code
## moves the athletes) while their height is kept, in metres.

## CMU's length unit, for the subjects recorded in it (see clip()).
const CMU_SCALE := 0.45

static var _cache := {}


static func clip(id: String) -> Animation:
	if _cache.has(id):
		return _cache[id]
	var path := "res://assets/mocap_clips/%s.fbx" % id
	if not ResourceLoader.exists(path):
		push_error("MocapLib: no clip " + path)
		return null
	var scene: Node = (load(path) as PackedScene).instantiate()
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var a: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
	scene.free()
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D and str(a.track_get_path(i)).ends_with(":Hips"):
			# Most CMU subjects come in the database's old units (1/0.45 of a metre once
			# retargeted): a standing hip height near 2. Those are scaled to metres.
			var ys: Array = []
			for k in a.track_get_key_count(i):
				ys.append(a.track_get_key_value(i, k).y)
			ys.sort()
			var s := CMU_SCALE if ys[ys.size() / 2] > 1.4 else 1.0
			for k in a.track_get_key_count(i):
				var p: Vector3 = a.track_get_key_value(i, k)
				a.track_set_key_value(i, k, Vector3(0.0, p.y * s, 0.0))
	var sp := span(a)
	a.length = sp.y
	_cache[id] = a
	return a


## First and last key time across all tracks (the files carry a long empty timeline).
static func span(a: Animation) -> Vector2:
	var lo := INF
	var hi := 0.0
	for i in a.get_track_count():
		var n := a.track_get_key_count(i)
		if n > 0:
			lo = minf(lo, a.track_get_key_time(i, 0))
			hi = maxf(hi, a.track_get_key_time(i, n - 1))
	return Vector2(lo if lo < INF else 0.0, hi)


## A piece of a clip, ready to play: keys between from and to (seconds) resampled at 30 fps
## and shifted to start at 0. align "start" / "end" turns the whole move so the body faces
## forward (+z, like the mannequin's rest pose) at that end; "none" leaves it. ground: true
## sets the hip height each frame so the lowest joint of skel (our mannequin) stays on the
## floor, for takes whose height doesn't fit (on the ground, getting up).
static func segment(spec: Dictionary, skel: Skeleton3D = null) -> Animation:
	var src := clip(str(spec["mocap"]))
	if src == null:
		return null
	var sp := span(src)
	var t0 := clampf(float(spec.get("from", sp.x)), sp.x, sp.y)
	var t1 := clampf(float(spec.get("to", sp.y)), t0 + 0.05, sp.y)
	var fps := 30.0
	var out := Animation.new()
	out.length = t1 - t0
	out.loop_mode = Animation.LOOP_LINEAR if spec.get("loop", false) else Animation.LOOP_NONE
	var align := str(spec.get("align", "start"))
	var turn := Quaternion.IDENTITY
	for i in src.get_track_count():
		if src.track_get_type(i) == Animation.TYPE_ROTATION_3D and str(src.track_get_path(i)).ends_with(":Hips") and align != "none":
			var q: Quaternion = src.rotation_track_interpolate(i, t1 if align == "end" else t0)
			var fwd := q * Vector3(0, 0, 1)
			turn = Quaternion(Vector3.UP, -atan2(fwd.x, fwd.z))
	for i in src.get_track_count():
		var ty := src.track_get_type(i)
		if ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_SCALE_3D:
			continue
		var path := src.track_get_path(i)
		var hips := str(path).ends_with(":Hips")
		var ti := out.add_track(ty)
		out.track_set_path(ti, path)
		var n := int(ceil((t1 - t0) * fps))
		for k in n + 1:
			var t := minf(t0 + k / fps, t1)
			match ty:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(ti, t - t0, src.position_track_interpolate(i, t))
				Animation.TYPE_ROTATION_3D:
					var q: Quaternion = src.rotation_track_interpolate(i, t)
					out.rotation_track_insert_key(ti, t - t0, (turn * q) if hips else q)
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(ti, t - t0, src.scale_track_interpolate(i, t))
	if spec.get("ground", false) and skel != null:
		_ground(out, skel)
	return out


## Keep the lowest joint at its rest-pose height (the toes on the floor) frame by frame,
## by moving the hips up or down. Forward kinematics on skel's rest lengths.
static func _ground(a: Animation, skel: Skeleton3D) -> void:
	var rot_track := {}
	var hips_pos := -1
	for i in a.get_track_count():
		var bone := skel.find_bone(str(a.track_get_path(i)).get_slice(":", 1))
		if bone < 0:
			continue
		if a.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			rot_track[bone] = i
		elif a.track_get_type(i) == Animation.TYPE_POSITION_3D and a.track_get_path(i).get_subname(0) == "Hips":
			hips_pos = i
	if hips_pos < 0:
		return
	var hips := skel.find_bone("Hips")
	var floor_y := _lowest(skel, hips, skel.get_bone_rest(hips).origin, {})
	for k in a.track_get_key_count(hips_pos):
		var t := a.track_get_key_time(hips_pos, k)
		var p: Vector3 = a.track_get_key_value(hips_pos, k)
		var rots := {}
		for b in rot_track:
			rots[b] = a.rotation_track_interpolate(rot_track[b], t)
		var low := _lowest(skel, hips, p * skel.motion_scale, rots)
		a.track_set_key_value(hips_pos, k, Vector3(p.x, p.y + (floor_y - low) / skel.motion_scale, p.z))


## Lowest joint height in skeleton space for a pose: hips at hips_origin, bones turned
## by rots (bone -> Quaternion), the rest pose elsewhere.
static func _lowest(skel: Skeleton3D, hips: int, hips_origin: Vector3, rots: Dictionary) -> float:
	var glob := {}
	var low := INF
	for b in skel.get_bone_count():
		var rest := skel.get_bone_rest(b)
		var local := Transform3D(Basis(rots[b]) if rots.has(b) else rest.basis, hips_origin if b == hips else rest.origin)
		var parent := skel.get_bone_parent(b)
		if b != hips and not glob.has(parent):
			continue       # above the hips (the root at the origin) or another branch
		var g: Transform3D = glob[parent] * local if b != hips else local
		glob[b] = g
		low = minf(low, g.origin.y)
	return low


## Playback speed so a segment spec lasts "fit" seconds (or its own "speed", default 1).
static func speed_of(spec: Dictionary) -> float:
	if spec.has("fit"):
		var len := float(spec.get("to", 1.0)) - float(spec.get("from", 0.0))
		return maxf(0.05, len / maxf(0.05, float(spec["fit"])))
	return float(spec.get("speed", 1.0))
