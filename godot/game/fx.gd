class_name Fx
extends Node3D
## One-shot particle bursts: dust on hits and cuts, a puff on catches, confetti on
## touchdowns. Purely visual, spawned on each machine.

const DUST := Color(0.55, 0.47, 0.35)


func spawn(kind: String, pos: Vector3, strength: float) -> void:
	match kind:
		"hit", "bighit", "fumble", "dust", "cut":
			_burst(pos, DUST, int(6 + 18 * strength), 0.25 + 0.35 * strength, 2.5 + 3.0 * strength, 0.09)
		"catch":
			_burst(pos + Vector3(0, 1.2, 0), Color(1, 1, 1, 0.9), 8, 0.3, 2.0, 0.05)
		"touchdown":
			for c in [Color(1.0, 0.55, 0.15), Color(0.25, 0.5, 1.0), Color(1, 1, 1), Color(1.0, 0.9, 0.2)]:
				_burst(pos + Vector3(0, 1.5, 0), c, 22, 1.4, 7.0, 0.07, -4.0)


func _burst(pos: Vector3, color: Color, amount: int, life: float, speed: float, size: float, gravity := -9.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	p.mesh = m
	p.position = pos + Vector3(0, 0.15, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)
