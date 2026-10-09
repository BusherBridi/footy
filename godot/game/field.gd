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

	var margin: float = f.get("oob_margin_m", 0.0)
	var lt := Tuning.section("lighting")
	var grass: Texture2D = _grass_texture() if lt.get("grass_texture", false) else null
	var tpm := float(lt.get("grass_texels_per_m", 4.0))
	# The land around the field, out to the horizon.
	var around: Array = lt.get("surround", [0.09, 0.2, 0.1])
	_box(Vector3(600.0, 0.05, 600.0), Vector3(0, -0.12, 0), Color(around[0], around[1], around[2]))
	_box(Vector3(width + 2.0 * margin, 0.08, length + 2.0 * ez + 2.0 * margin), Vector3(0, -0.07, 0), Color(0.55, 0.62, 0.55), grass, tpm)
	# Mowed stripes across the field.
	var stripe := float(lt.get("stripe_yards", 5)) * yard
	var n := maxi(1, roundi(length / stripe))
	for i in n:
		var light := i % 2 == 0
		var z := -length * 0.5 + (i + 0.5) * length / n
		_box(Vector3(width, 0.1, length / n), Vector3(0, -0.05, z), Color(1, 1, 1) if light else Color(0.8, 0.86, 0.8), grass, tpm)
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


func _box(size: Vector3, pos: Vector3, color: Color, tex: Texture2D = null, texels_per_m := 4.0) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if tex != null:
		# World-space (triplanar) so every box lines up; nearest filtering keeps the pixels crisp.
		mat.albedo_texture = tex
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		var k := texels_per_m / float(tex.get_width())
		mat.uv1_scale = Vector3(k, k, k)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)


## A small tiling grass texture made in code: a few greens in a fixed random pattern.
func _grass_texture() -> ImageTexture:
	var size := 32
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	var greens := [Color(0.16, 0.4, 0.18), Color(0.17, 0.42, 0.19), Color(0.15, 0.38, 0.17), Color(0.18, 0.44, 0.2)]
	for y in size:
		for x in size:
			var r := rng.randf()
			img.set_pixel(x, y, greens[0] if r < 0.45 else (greens[1] if r < 0.75 else (greens[2] if r < 0.93 else greens[3])))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
