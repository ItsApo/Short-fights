class_name Maps
extends RefCounted

const NAMES := ["Almacén", "Patio", "Torres"]


# Adds the map to parent (lights, environment, static boxes). Returns spawn points (y = 1).
static func build(parent: Node3D, index: int) -> Dictionary:
	if index < 0 or index >= NAMES.size():
		index = 0
	var layout := _layout(index)
	for b in layout["boxes"]:
		_box(parent, b[0], b[1], b[2], b[3] if b.size() > 3 else Vector3.ZERO)

	var sa: Array[Vector3] = []
	var sb: Array[Vector3] = []
	for p: Vector2 in layout["spawns"]:
		sa.append(Vector3(p.x, 1.0, p.y))
		sb.append(Vector3(p.x, 1.0, -p.y))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	parent.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	return {"spawns_a": sa, "spawns_b": sb}


static func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = bm
	body.add_child(mesh)

	parent.add_child(body)
	body.position = center
	body.rotation_degrees = rot


# Floor (top at y = 0) plus four 4 m walls around a square arena of half-size `half`.
static func _arena(half: float, floor_c: Color, wall_c: Color) -> Array:
	var w := half + 0.5
	var span := half * 2.0 + 2.0
	return [
		[Vector3(0, -0.5, 0), Vector3(half * 2.0, 1, half * 2.0), floor_c],
		[Vector3(0, 2, -w), Vector3(span, 4, 1), wall_c],
		[Vector3(0, 2, w), Vector3(span, 4, 1), wall_c],
		[Vector3(-w, 2, 0), Vector3(1, 4, span), wall_c],
		[Vector3(w, 2, 0), Vector3(1, 4, span), wall_c],
	]


static func _layout(index: int) -> Dictionary:
	match index:
		1:
			return _patio()
		2:
			return _torres()
	return _almacen()


# Spawn points are Vector2(x, z) on team A's side (negative z); team B is mirrored on z.
static func _almacen() -> Dictionary:
	var boxes: Array = _arena(20.0, Color(0.34, 0.33, 0.31), Color(0.48, 0.44, 0.38))
	var crate := Color(0.62, 0.48, 0.3)
	var shelf := Color(0.3, 0.4, 0.48)
	boxes.append_array([
		[Vector3(-7, 1, -5), Vector3(2, 2, 2), crate],
		[Vector3(7, 1, 5), Vector3(2, 2, 2), crate],
		[Vector3(5, 0.75, -2), Vector3(1.5, 1.5, 1.5), crate],
		[Vector3(-5, 0.75, 2), Vector3(1.5, 1.5, 1.5), crate],
		[Vector3(-12, 1, 0), Vector3(2, 2, 2), crate],
		[Vector3(12, 1, 0), Vector3(2, 2, 2), crate],
		[Vector3(12, 1, -10), Vector3(2, 2, 2), crate],
		[Vector3(-12, 1, 10), Vector3(2, 2, 2), crate],
		[Vector3(-3, 1.5, -10), Vector3(6, 3, 1), shelf],
		[Vector3(3, 1.5, 10), Vector3(6, 3, 1), shelf],
		[Vector3(4, 1.5, -6), Vector3(1, 3, 6), shelf],
		[Vector3(-4, 1.5, 6), Vector3(1, 3, 6), shelf],
	])
	var spawns: Array[Vector2] = [
		Vector2(-15, -16), Vector2(-9, -17), Vector2(-3, -16),
		Vector2(3, -17), Vector2(9, -16), Vector2(15, -17),
	]
	return {"boxes": boxes, "spawns": spawns}


static func _patio() -> Dictionary:
	var boxes: Array = _arena(20.0, Color(0.52, 0.56, 0.46), Color(0.68, 0.64, 0.54))
	var low := Color(0.6, 0.48, 0.38)
	var pillar := Color(0.78, 0.75, 0.7)
	boxes.append_array([
		[Vector3(0, 0.6, -6), Vector3(8, 1.2, 1), low],
		[Vector3(0, 0.6, 6), Vector3(8, 1.2, 1), low],
		[Vector3(-8, 0.6, 0), Vector3(1, 1.2, 6), low],
		[Vector3(8, 0.6, 0), Vector3(1, 1.2, 6), low],
		[Vector3(-5, 0.6, -12), Vector3(6, 1.2, 1), low],
		[Vector3(5, 0.6, 12), Vector3(6, 1.2, 1), low],
		[Vector3(-4, 1.5, -4), Vector3(1.5, 3, 1.5), pillar],
		[Vector3(4, 1.5, -4), Vector3(1.5, 3, 1.5), pillar],
		[Vector3(-4, 1.5, 4), Vector3(1.5, 3, 1.5), pillar],
		[Vector3(4, 1.5, 4), Vector3(1.5, 3, 1.5), pillar],
	])
	var spawns: Array[Vector2] = [
		Vector2(-14, -16), Vector2(-7, -17), Vector2(0, -16),
		Vector2(7, -17), Vector2(14, -16), Vector2(0, -18),
	]
	return {"boxes": boxes, "spawns": spawns}


static func _torres() -> Dictionary:
	var boxes: Array = _arena(25.0, Color(0.28, 0.31, 0.37), Color(0.4, 0.43, 0.5))
	var stone := Color(0.5, 0.53, 0.6)
	var ramp := Color(0.58, 0.52, 0.42)
	var crate := Color(0.36, 0.48, 0.44)
	var slope := 26.565  # atan(3 / 6): rise 3 m over run 6 m, under 30 degrees
	boxes.append_array([
		# raised platforms, left and right of center
		[Vector3(-14, 1.5, 0), Vector3(8, 3, 8), stone],
		[Vector3(14, 1.5, 0), Vector3(8, 3, 8), stone],
		# ramps: team A side (z < 0) rises toward +z, team B side mirrored
		[Vector3(-14, 1.5, -7), Vector3(4, 0.3, 6.708), ramp, Vector3(-slope, 0, 0)],
		[Vector3(14, 1.5, -7), Vector3(4, 0.3, 6.708), ramp, Vector3(-slope, 0, 0)],
		[Vector3(-14, 1.5, 7), Vector3(4, 0.3, 6.708), ramp, Vector3(slope, 0, 0)],
		[Vector3(14, 1.5, 7), Vector3(4, 0.3, 6.708), ramp, Vector3(slope, 0, 0)],
		# center bridge joining the platforms (top at y = 3)
		[Vector3(0, 2.75, 0), Vector3(20, 0.5, 4), stone],
		# ground cover
		[Vector3(0, 0.6, -8), Vector3(4, 1.2, 1), ramp],
		[Vector3(0, 0.6, 8), Vector3(4, 1.2, 1), ramp],
		[Vector3(-6, 1, -10), Vector3(2, 2, 2), crate],
		[Vector3(6, 1, 10), Vector3(2, 2, 2), crate],
	])
	var spawns: Array[Vector2] = [
		Vector2(-12, -20), Vector2(-4, -20), Vector2(4, -20),
		Vector2(12, -20), Vector2(-8, -17), Vector2(8, -17),
	]
	return {"boxes": boxes, "spawns": spawns}
