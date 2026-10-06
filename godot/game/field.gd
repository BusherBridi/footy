class_name Field
extends Node3D
## Placeholder field: green plane, yard lines, end zones. Built from tuning.


func build(f: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	var yard: float = f["yard_m"]
	var length: float = f["length_yards"] * yard
	var width: float = f["width_yards"] * yard
	var ez: float = f["endzone_yards"] * yard

	_box(Vector3(width, 0.1, length + 2.0 * ez), Vector3(0, -0.05, 0), Color(0.15, 0.45, 0.2))
	for side in [-1.0, 1.0]:
		_box(Vector3(width, 0.11, ez), Vector3(0, -0.05, side * (length + ez) * 0.5), Color(0.15, 0.3, 0.55) if side < 0 else Color(0.55, 0.2, 0.2))

	# Line every 5 yards across the playing field (goal lines at the ends).
	var yards: int = int(f["length_yards"])
	for i in range(0, yards + 1, 5):
		var z := -length * 0.5 + i * yard
		var thick := 0.35 if (i == 0 or i == yards) else 0.15
		_box(Vector3(width, 0.12, thick), Vector3(0, -0.04, z), Color.WHITE)
	# Midfield marker.
	_box(Vector3(width, 0.13, 0.5), Vector3(0, -0.035, 0), Color(1, 1, 1))


func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
