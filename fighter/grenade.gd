class_name Grenade
extends RigidBody3D
## Thrown grenade. Every peer simulates its own copy; only the host applies damage.

const MODEL := "res://assets/models/grenade.glb"
const MODEL_SIZE := 0.15          # longest side of the model, metres
const BOUNCE_GAP_MS := 150

var thrower := ""
var _fuse: float = float(Weapons.DATA.grenade.fuse)
var _radius: float = float(Weapons.DATA.grenade.radius)
var _mesh: Node3D
var _exploded := false
var _last_bounce_ms: int = -1000


func _init() -> void:
	collision_layer = 4
	collision_mask = 1
	mass = 0.4
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.6
	physics_material_override = pm


func setup(pos: Vector3, vel: Vector3, thrower_name: String) -> void:
	thrower = thrower_name
	if is_inside_tree():
		global_position = pos
	else:
		position = pos
	linear_velocity = vel


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.12
	shape.shape = sph
	add_child(shape)

	_mesh = Node3D.new()
	add_child(_mesh)
	var ps = load(MODEL)
	if ps is PackedScene:
		_mesh.add_child((ps as PackedScene).instantiate())
		var ab := _model_aabb(_mesh)
		var longest := maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
		if longest > 0.0001:
			var s := MODEL_SIZE / longest
			_mesh.scale = Vector3.ONE * s
			_mesh.position = -ab.get_center() * s
	else:
		# Model missing: plain sphere so the grenade stays visible.
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		_mesh.add_child(mi)

	body_entered.connect(_on_body_entered)


## Bounding box of all MeshInstance3D under `holder`, expressed in holder space.
func _model_aabb(holder: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var inv := holder.global_transform.affine_inverse()
	var stack: Array = [holder]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var ab: AABB = (inv * mi.global_transform) * mi.get_aabb()
			if first:
				result = ab
				first = false
			else:
				result = result.merge(ab)
		for c in n.get_children():
			stack.append(c)
	return result


func _on_body_entered(_body: Node) -> void:
	if _exploded:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bounce_ms < BOUNCE_GAP_MS:
		return
	_last_bounce_ms = now
	Sfx.play("bounce", global_position, -6.0)


func _process(delta: float) -> void:
	if _exploded:
		return
	_fuse -= delta
	if _fuse <= 0.0:
		_explode()


func _explode() -> void:
	_exploded = true
	if multiplayer.is_server():
		var m = get_tree().get_first_node_in_group("match")
		if m:
			m.apply_explosion(global_position, thrower)
	Fx.explosion(get_parent(), global_position, _radius)
	Sfx.play("explosion", global_position)
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	queue_free()
