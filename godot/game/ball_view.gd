class_name BallView
extends Node3D
## Placeholder ball, landing marker (everyone sees it) and aim marker (QB only).

var _ball := MeshInstance3D.new()
var _landing := MeshInstance3D.new()
var _aim := MeshInstance3D.new()
var _aim_mat := StandardMaterial3D.new()
var _arc := MeshInstance3D.new()
var _arc_mesh := ImmediateMesh.new()
var _arc_mat := StandardMaterial3D.new()


func _init() -> void:
	var sph := SphereMesh.new()
	var r: float = Tuning.section("art").get("ball_visual_radius", 0.3)
	sph.radius = r
	sph.height = r * 2.0
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.5, 0.28, 0.12)
	sph.material = bm
	_ball.mesh = sph
	_ball.scale = Vector3(0.7, 0.7, 1.3)
	add_child(_ball)

	_landing.mesh = _disc(Color(1, 0.9, 0.2, 0.55), null)
	_landing.visible = false
	add_child(_landing)
	_aim.mesh = _disc(Color.WHITE, _aim_mat)
	_aim.visible = false
	add_child(_aim)

	_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc.mesh = _arc_mesh
	_arc.visible = false
	add_child(_arc)


func _disc(color: Color, mat: StandardMaterial3D) -> CylinderMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.03
	var m := mat if mat else StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = m
	return cyl


func set_ball(pos: Vector3) -> void:
	_ball.position = pos


func set_landing(on: bool, pos: Vector3, radius: float) -> void:
	_landing.visible = on
	if on:
		_landing.position = Vector3(pos.x, 0.05, pos.z)
		_landing.scale = Vector3(radius, 1, radius)


## Aim marker: red for bullet, blue for lob.
func set_aim(on: bool, pos: Vector2, lob: bool, radius: float, arc: PackedVector3Array) -> void:
	_aim.visible = on
	_arc.visible = on and arc.size() > 1
	if _arc.visible:
		_arc_mat.albedo_color = Color(0.3, 0.5, 1.0) if lob else Color(1.0, 0.3, 0.25)
		_arc_mesh.clear_surfaces()
		_arc_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _arc_mat)
		for p in arc:
			_arc_mesh.surface_add_vertex(p)
		_arc_mesh.surface_end()
	if on:
		_aim.position = Vector3(pos.x, 0.07, pos.y)
		_aim.scale = Vector3(radius, 1, radius)
		_aim_mat.albedo_color = Color(0.3, 0.5, 1.0, 0.6) if lob else Color(1.0, 0.3, 0.25, 0.6)
