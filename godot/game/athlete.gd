class_name Athlete
extends Node3D
## Placeholder visual for one athlete: capsule plus a nose box showing facing.
## Pure visual; the simulation state lives in AthleteState.

var _body_mat := StandardMaterial3D.new()


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


func set_color(c: Color) -> void:
	_body_mat.albedo_color = c


func set_visual(pos: Vector2, heading: Vector2) -> void:
	position = Vector3(pos.x, 0.0, pos.y)
	rotation.y = atan2(-heading.x, -heading.y)
