class_name MocapLib
extends RefCounted
## CMU mocap clips (godot/assets/mocap_clips, retargeted onto the humanoid profile at import)
## made ready for our mannequin: the hips' travel across the ground is removed (our code
## moves the athletes) while their height is kept.

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
			var first: Vector3 = a.track_get_key_value(i, 0)
			for k in a.track_get_key_count(i):
				var p: Vector3 = a.track_get_key_value(i, k)
				a.track_set_key_value(i, k, Vector3(first.x, p.y, first.z))
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
