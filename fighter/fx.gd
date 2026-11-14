class_name Fx
## Visual effects, all static, self-freeing (< 1 s). Unshaded and cheap for mobile.


static func _unshaded(col: Color, alpha: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func tracer(parent: Node, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var len := d.length()
	if len < 0.1:
		return
	var dir := d / len
	var mid := (from + to) * 0.5
	var mat := _unshaded(Color(1.0, 1.0, 0.8), true)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.02, len)
	bm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	parent.add_child(mi)
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	mi.look_at_from_position(mid, mid + dir, up)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.06)
	tw.tween_callback(mi.queue_free)


static func muzzle(parent: Node, pos: Vector3, dir: Vector3) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	sm.material = _unshaded(Color(1.0, 0.65, 0.15))
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	if dir.length() > 0.001:
		mi.position = dir.normalized() * 0.1
	root.add_child(mi)
	var light := OmniLight3D.new()
	light.omni_range = 4.0
	light.light_energy = 2.0
	root.add_child(light)
	var tw := root.create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(root.queue_free)


static func impact(parent: Node, pos: Vector3, normal: Vector3, flesh: bool) -> void:
	var n := normal.normalized() if normal.length() > 0.001 else Vector3.UP
	var col := Color(0.7, 0.05, 0.05) if flesh else Color(0.45, 0.4, 0.33)
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.material = _unshaded(col)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 8
	p.lifetime = 0.3
	p.direction = n
	p.spread = 45.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.mesh = sm
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := p.get_tree().create_timer(0.6)
	t.timeout.connect(p.queue_free)


static func explosion(parent: Node, pos: Vector3, radius: float) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos

	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	var mat := _unshaded(Color(1.0, 0.55, 0.1), true)
	sm.material = mat
	var ball := MeshInstance3D.new()
	ball.mesh = sm
	ball.scale = Vector3.ONE * 0.2
	root.add_child(ball)

	var light := OmniLight3D.new()
	light.omni_range = radius * 2.0
	light.light_energy = 4.0
	root.add_child(light)

	var smoke_sm := SphereMesh.new()
	smoke_sm.radius = 0.12
	smoke_sm.height = 0.24
	smoke_sm.material = _unshaded(Color(0.5, 0.5, 0.5))
	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.explosiveness = 1.0
	smoke.amount = 16
	smoke.lifetime = 0.8
	smoke.direction = Vector3.UP
	smoke.spread = 180.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 3.0
	smoke.gravity = Vector3(0.0, 1.0, 0.0)
	smoke.mesh = smoke_sm
	root.add_child(smoke)
	smoke.emitting = true

	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * radius, 0.25)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_property(light, "light_energy", 0.0, 0.25)

	root.get_tree().call_group("fighters", "shake", pos, 1.0)
	var t := root.get_tree().create_timer(1.0)
	t.timeout.connect(root.queue_free)
