class_name Athlete
extends Node3D
## Placeholder visual for one athlete: capsule plus a nose box showing facing.
## Holds an AthleteState; movement is stepped from outside via Movement.step.

var state := AthleteState.new()


func _init() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.8, 0.2)
	cap.material = mat
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


func sync_visual() -> void:
	position = Vector3(state.pos.x, 0.0, state.pos.y)
	rotation.y = atan2(-state.heading.x, -state.heading.y)
