class_name Athlete
extends Node3D
## Placeholder visual for one athlete: capsule plus a nose box showing facing.
## Pure visual; the simulation state lives in AthleteState.

var _body_mat := StandardMaterial3D.new()
var _ring := MeshInstance3D.new()
var _arm := MeshInstance3D.new()


func _init() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	cap.material = _body_mat
	body.mesh = cap
	body.position.y = 0.9
	add_child(body)

	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.25, 0.4)
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(0.1, 0.1, 0.1)
	box.material = nmat
	nose.mesh = box
	nose.position = Vector3(0, 1.4, -0.45)
	add_child(nose)

	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1, 1, 1, 0.18)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = rmat
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.18, 0.18, 0.8)
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Color(0.95, 0.5, 0.2)
	arm_mesh.material = amat
	_arm.mesh = arm_mesh
	_arm.position = Vector3(0.0, 1.25, -0.85)
	_arm.visible = false
	add_child(_arm)
	_ring.mesh = disc
	_ring.position.y = 0.04
	add_child(_ring)


func set_color(c: Color) -> void:
	_body_mat.albedo_color = c


func set_visual(pos: Vector2, heading: Vector2, speed := 0.0, status := 0, fx := 0, juke := false) -> void:
	_arm.visible = fx == 1
	var show: bool = Tuning.section("catch").get("show_ring", false)
	_ring.visible = show
	if show:
		var r := CatchRules.radius_for(speed, Tuning.data)
		_ring.scale = Vector3(r, 1, r)
	position = Vector3(pos.x, 0.0, pos.y)
	var tilt := 0.0
	if status == AthleteState.Status.DOWN:
		tilt = -1.45          # lying flat, head along the direction of travel
	elif status == AthleteState.Status.DIVING:
		tilt = -1.15
	elif status == AthleteState.Status.STUMBLE:
		tilt = -0.35
	rotation = Vector3(tilt, atan2(-heading.x, -heading.y), 0.35 if juke else 0.0)
