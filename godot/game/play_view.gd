class_name PlayView
extends Node3D
## Field markings for a match: the line of scrimmage, and the rush timer as a ring
## around the QB that shrinks as the rush gets closer.

var _los := MeshInstance3D.new()
var _ring := MeshInstance3D.new()
var _ring_mat := StandardMaterial3D.new()


func _init() -> void:
	var line := BoxMesh.new()
	line.size = Vector3(1.0, 0.03, 0.35)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.2, 0.55, 1.0)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material = lm
	_los.mesh = line
	_los.visible = false
	add_child(_los)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(1.0, 0.3, 0.2)
	torus.material = _ring_mat
	_ring.mesh = torus
	_ring.visible = false
	add_child(_ring)


## view: from NetSession.get_play_view(); qb_pos: where the QB is drawn (or null).
func update_view(view: Dictionary, width_m: float, rush_time: float, qb_pos: Variant) -> void:
	if view.is_empty():
		_los.visible = false
		_ring.visible = false
		return
	_los.visible = true
	_los.position = Vector3(0.0, 0.06, float(view["los"]))
	_los.scale = Vector3(width_m, 1.0, 1.0)
	var rush := float(view["rush"])
	var live := int(view["phase"]) == PlayFlow.Phase.LIVE
	_ring.visible = live and rush > 0.0 and qb_pos != null
	if _ring.visible:
		var f := clampf(rush / maxf(rush_time, 0.01), 0.0, 1.0)
		var r := 0.8 + 2.2 * f
		_ring.position = Vector3(qb_pos.x, 0.08, qb_pos.z)
		_ring.scale = Vector3(r, 1.0, r)
		_ring_mat.albedo_color = Color(1.0, 0.3, 0.2).lerp(Color(1.0, 0.9, 0.2), f)
