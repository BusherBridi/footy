class_name Athlete
extends Node3D
## One athlete on screen. Pure visual: the simulation state lives in AthleteState.
## With art.use_model it is the Quaternius mannequin, animated from the synced state
## (speed picks idle/walk/jog/sprint, status picks set/down/dive/truck/...); throws and
## stiff arms play as one-shots. Without it, the old capsule.

const TEAM_COLORS := [Color(0.95, 0.5, 0.15), Color(0.25, 0.45, 0.95)]

static var _extra_lib: AnimationLibrary = null

var _capsule := Node3D.new()
var _body_mat := StandardMaterial3D.new()
var _ring := MeshInstance3D.new()
var _arm := MeshInstance3D.new()
var _marker := MeshInstance3D.new()
var _team := -2
var _local := false

var _model: Node3D = null
var _anim: AnimationPlayer = null
var _model_mat: StandardMaterial3D = null
var _clip := ""
var _clip_cache := {}
var _oneshot_left := 0.0
var _last_fx := 0


func _init() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	cap.material = _body_mat
	body.mesh = cap
	body.position.y = 0.9
	_capsule.add_child(body)
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.25, 0.4)
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(0.1, 0.1, 0.1)
	box.material = nmat
	nose.mesh = box
	nose.position = Vector3(0, 1.4, -0.45)
	_capsule.add_child(nose)
	add_child(_capsule)

	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1, 1, 1, 0.18)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = rmat
	_ring.mesh = disc
	_ring.position.y = 0.04
	add_child(_ring)

	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.18, 0.18, 0.8)
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Color(0.95, 0.5, 0.2)
	arm_mesh.material = amat
	_arm.mesh = arm_mesh
	_arm.position = Vector3(0.0, 1.25, -0.85)
	_arm.visible = false
	add_child(_arm)

	_marker.visible = false
	add_child(_marker)

	if Tuning.section("art").get("use_model", false):
		_load_model()


func _load_model() -> void:
	var art := Tuning.section("art")
	var scene: PackedScene = load(String(art["model"]))
	if scene == null:
		return
	_model = scene.instantiate()
	_model.rotation.y = PI          # the glTF faces +z; our athletes face -z
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	# The second pack shares the skeleton: borrow its clips (throw, truck, ...) once.
	if _extra_lib == null and art.has("extra_clips"):
		var extra: PackedScene = load(String(art["extra_clips"]))
		if extra != null:
			var tmp := extra.instantiate()
			var ap: AnimationPlayer = tmp.find_child("AnimationPlayer", true, false)
			_extra_lib = ap.get_animation_library("")
			tmp.free()
	if _anim != null and _extra_lib != null and not _anim.has_animation_library("extra"):
		_anim.add_animation_library("extra", _extra_lib)
	# Tint only the main body material per athlete (the joints stay purple).
	var mi: MeshInstance3D = _model.find_child("Mannequin", true, false)
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D and (m.resource_name == "M_Main" or i == 0):
				_model_mat = m.duplicate()
				mi.set_surface_override_material(i, _model_mat)
				break
	_capsule.visible = false


func _process(delta: float) -> void:
	_oneshot_left -= delta


func set_color(c: Color) -> void:
	_body_mat.albedo_color = c
	if _model_mat != null:
		_model_mat.albedo_color = c


## Match colours: Orange (0) or Blue (1); your own athlete is a lighter shade.
func set_team(team: int, is_local: bool) -> void:
	if team == _team and is_local == _local:
		return
	_team = team
	_local = is_local
	if team >= 0:
		var c: Color = TEAM_COLORS[team]
		set_color(c.lightened(0.35) if is_local else c)


## Play a clip once over whatever the state would show (a throw, a stiff arm).
func play_oneshot(key: String, seek := 0.0) -> void:
	var clip := _resolve(key)
	if clip == "":
		return
	_anim.play(clip, 0.08)
	if seek > 0.0:
		_anim.seek(seek, true)
	_anim.speed_scale = 1.0
	_clip = clip
	_oneshot_left = (_anim.get_animation(clip).length - seek) * 0.9


## Map a clip key from tuning (art.clips) to an animation the player has. Handles
## importers that keep or strip the "_Loop" suffix, and clips from the second pack.
func _resolve(key: String) -> String:
	if _anim == null:
		return ""
	if _clip_cache.has(key):
		return _clip_cache[key]
	var clips: Dictionary = Tuning.section("art")["clips"]
	var base: String = clips.get(key, key)
	var found := ""
	for name in [base, base + "_Loop", "extra/" + base, "extra/" + base + "_Loop"]:
		if _anim.has_animation(name):
			found = name
			break
	_clip_cache[key] = found
	return found


## heading here is the way the body faces (the locked stance direction when in stance).
## stance: 0 = no stance, 1 = shuffling forward or sideways, -1 = backpedalling.
func set_visual(pos: Vector2, heading: Vector2, speed := 0.0, status := 0, fx := 0, juke := false, stance := 0) -> void:
	var show: bool = Tuning.section("catch").get("show_ring", false)
	_ring.visible = show
	if show:
		var r := CatchRules.radius_for(speed, Tuning.data)
		_ring.scale = Vector3(r, 1, r)
	position = Vector3(pos.x, 0.0, pos.y)
	var yaw := atan2(-heading.x, -heading.y)
	if status == AthleteState.Status.SPIN:
		yaw += Time.get_ticks_msec() / 60.0     # a visible spin
	if _anim != null:
		var art := Tuning.section("art")
		_animate(speed, status, fx, stance)
		rotation = Vector3(0.0, yaw, 0.12 if juke else 0.0)
		# Neither pack has a head-first dive: tip the reaching "push" pose forward instead.
		var diving := status == AthleteState.Status.DIVING
		_model.rotation = Vector3(deg_to_rad(float(art["dive_tilt_deg"])) if diving else 0.0, PI, 0.0)
		if diving:
			position.y = float(art["dive_lift"])
		elif status == AthleteState.Status.HURDLE:
			position.y = float(art["hurdle_lift"])
		return

	# Capsule fallback.
	_arm.visible = fx >= 1 and fx <= 3
	_arm.position.x = 0.0 if fx == 1 else (-0.7 if fx == 2 else 0.7)
	_arm.position.z = -0.85 if fx == 1 else -0.35
	_arm.rotation.y = 0.0 if fx == 1 else (0.9 if fx == 2 else -0.9)
	var tilt := 0.0
	match status:
		AthleteState.Status.DOWN: tilt = -1.45
		AthleteState.Status.DIVING: tilt = -1.15
		AthleteState.Status.STUMBLE: tilt = -0.35
		AthleteState.Status.TRUCK: tilt = -0.55
		AthleteState.Status.HURDLE: tilt = -0.3
		AthleteState.Status.POP: tilt = -0.4
		AthleteState.Status.WRAPPED: tilt = -0.15
		AthleteState.Status.HOLDING: tilt = -0.45
	rotation = Vector3(tilt, yaw, 0.35 if juke else 0.0)
	if status == AthleteState.Status.HURDLE:
		position.y = 0.9


func _animate(speed: float, status: int, fx: int, stance := 0) -> void:
	var art := Tuning.section("art")
	if fx >= 1 and _last_fx == 0:
		play_oneshot("swat" if fx == 4 else "stiff_arm")
	_last_fx = fx
	var key := ""
	match status:
		AthleteState.Status.SET: key = "set"
		AthleteState.Status.DOWN: key = "down"
		AthleteState.Status.DIVING: key = "dive"
		AthleteState.Status.STUMBLE: key = "stumble"
		AthleteState.Status.TRUCK: key = "truck"
		AthleteState.Status.HURDLE: key = "hurdle"
		AthleteState.Status.WRAPPED: key = "wrapped"
		AthleteState.Status.HOLDING: key = "holding"
		AthleteState.Status.POP: key = "pop"
	# A one-shot (throw, stiff arm) keeps playing unless something bigger happens.
	if _oneshot_left > 0.0 and (key == "" or key == "pop"):
		return
	var scale := 1.0
	if key == "" and stance != 0:
		# Low and square: the crouch walk, run backwards when backpedalling.
		if speed < 0.25:
			key = "set"
		else:
			key = "stance"
			scale = clampf(speed / float(art["stance_speed"]), float(art["min_anim_scale"]), float(art["max_anim_scale"])) * float(stance)
	elif key == "":
		var native := 1.0
		if speed < 0.25:
			key = "idle"
		elif speed < float(art["walk_below"]):
			key = "walk"
			native = float(art["walk_speed"])
		elif speed < float(art["sprint_above"]):
			key = "jog"
			native = float(art["jog_speed"])
		else:
			key = "sprint"
			native = float(art["sprint_speed"])
		if key != "idle":
			scale = clampf(speed / native, float(art["min_anim_scale"]), float(art["max_anim_scale"]))
	var clip := _resolve(key)
	if clip == "":
		return
	if clip != _clip:
		_anim.play(clip, float(art["blend"]))
		_clip = clip
	_anim.speed_scale = scale
