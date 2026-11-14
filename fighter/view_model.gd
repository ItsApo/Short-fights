class_name ViewModel
extends Node3D
## First-person weapon, child of the Camera3D (looks down -Z). Models (measured): gun GLBs have the barrel at -X, up = +Y,
## so they are rotated -90 deg about Y; sized by longest dimension via TARGET_LENGTH.

const HIP := Vector3(0.22, -0.22, -0.45)
const ADS := Vector3(0.0, -0.12, -0.35)  # y is replaced per weapon by _ads_y (sights under the screen centre)
const SIGHT_GAP := 0.003  # how far the weapon's top edge sits below the camera line while aiming
const TARGET_LENGTH := {"rifle": 0.7, "shotgun": 0.8, "pistol": 0.3, "grenade": 0.13}

var _holders: Dictionary = {}  # id -> Node3D holder
var _muzzles: Dictionary = {}  # id -> Marker3D
var _ads_y: Dictionary = {}  # id -> ADS height that puts the weapon's top (its sights) just under the crosshair
var _id := ""
var _bob_t := 0.0
var _bob_amp := 0.0
var _sway := Vector2.ZERO
var _last_euler := Vector3.ZERO
var _have_last := false
var _kick := 0.0
var _reload_t := 0.0
var _reload_dur := 0.0
var _switch := 0.0


func set_weapon(id: String) -> void:
	if id == _id:
		return
	if not _holders.has(id):
		_build(id)
	for k in _holders:
		(_holders[k] as Node3D).visible = (k == id)
	_id = id
	_switch = 1.0
	_reload_dur = 0.0


func update(delta: float, aim: float, move_speed: float, on_floor: bool) -> void:
	delta = maxf(delta, 0.0001)
	aim = clampf(aim, 0.0, 1.0)
	var ads := Vector3(ADS.x, float(_ads_y.get(_id, ADS.y)), ADS.z)
	var pos := HIP.lerp(ads, aim)
	var rot := Vector3.ZERO

	# bob (walk cycle), weaker while aiming
	var moving := on_floor and move_speed > 0.5
	var amp_target := clampf(move_speed / 6.0, 0.0, 1.5) if moving else 0.0
	_bob_amp = lerpf(_bob_amp, amp_target, 1.0 - exp(-10.0 * delta))
	if moving:
		_bob_t += delta * (5.0 + move_speed * 0.9)
	var bob_scale := _bob_amp * (1.0 - 0.8 * aim)
	pos.x += sin(_bob_t) * 0.012 * bob_scale
	pos.y += absf(sin(_bob_t)) * 0.014 * bob_scale - 0.006 * bob_scale

	# sway from camera rotation delta
	var cam := get_parent() as Node3D
	if cam != null and cam.is_inside_tree():
		var e := cam.global_transform.basis.get_euler()
		if _have_last:
			var dyaw := wrapf(e.y - _last_euler.y, -PI, PI)
			var dpitch := wrapf(e.x - _last_euler.x, -PI, PI)
			var target := Vector2(-dyaw, dpitch) / delta * 0.004
			target = target.clamp(Vector2(-0.05, -0.05), Vector2(0.05, 0.05))
			_sway = _sway.lerp(target, 1.0 - exp(-14.0 * delta))
		_last_euler = e
		_have_last = true
	var sw := 1.0 - 0.6 * aim
	pos.x += _sway.x * sw
	pos.y += _sway.y * sw
	rot.y += _sway.x * 1.2 * sw
	rot.x += _sway.y * 1.2 * sw

	# recoil kick: back + up + muzzle rise, recovers fast
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-14.0 * delta))
	pos.z += _kick * 4.0
	pos.y += _kick * 0.6
	rot.x += _kick * 6.0

	# reload dip
	if _reload_dur > 0.0:
		_reload_t += delta
		var p := clampf(_reload_t / _reload_dur, 0.0, 1.0)
		var d := sin(p * PI)
		d = d * d * (3.0 - 2.0 * d)
		pos.y -= 0.16 * d
		pos.x += 0.03 * d
		rot.x -= 0.55 * d
		rot.z += 0.45 * d
		if p >= 1.0:
			_reload_dur = 0.0

	# weapon switch raise
	_switch = maxf(_switch - delta * 4.0, 0.0)
	var sd := _switch * _switch
	pos.y -= 0.25 * sd
	rot.x -= 0.5 * sd

	position = pos
	rotation = rot


func kick(amount: float) -> void:
	# amount = weapon recoil in rad (rifle 0.012, shotgun 0.06): back = amount*4 m, rise = amount*6 rad
	_kick = minf(_kick + amount, 0.08)


func reload_anim(time: float) -> void:
	_reload_dur = maxf(time, 0.1)
	_reload_t = 0.0


func muzzle_global() -> Vector3:
	var m := _muzzles.get(_id) as Marker3D
	if m != null and m.is_inside_tree():
		return m.global_position
	return global_position


func _build(id: String) -> void:
	var holder := Node3D.new()
	holder.name = "W_" + id
	add_child(holder)
	var bounds := AABB()
	var model: Node3D = null
	var path = Weapons.DATA[id].get("model") if Weapons.DATA.has(id) else null
	if path != null and path != "":
		var scene := load(String(path)) as PackedScene
		if scene != null:
			model = scene.instantiate() as Node3D
	if model != null:
		var is_gun: bool = Weapons.DATA[id].has("pellets")
		var inner := Node3D.new()  # rotated/scaled wrapper
		inner.add_child(model)
		if is_gun:
			inner.rotation.y = -PI * 0.5  # barrel -X -> -Z
		var raw := _mesh_bounds(model, model)
		var longest := maxf(raw.size.x, maxf(raw.size.y, raw.size.z))
		var s: float = float(TARGET_LENGTH.get(id, 0.4)) / maxf(longest, 0.001)
		inner.scale = Vector3(s, s, s)
		holder.add_child(inner)
		var b := inner.transform * raw
		# centre on x/y; rear of the weapon near z = +0.02, grenade centred
		var off := Vector3(-(b.position.x + b.size.x * 0.5), -(b.position.y + b.size.y * 0.5), 0.0)
		off.z = (0.02 - (b.position.z + b.size.z)) if is_gun else -(b.position.z + b.size.z * 0.5)
		inner.position = off
		bounds = AABB(b.position + off, b.size)
	else:
		bounds = _build_medkit(holder)
	_disable_shadows(holder)
	var mz := Marker3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(bounds.position.x + bounds.size.x * 0.5, bounds.position.y + bounds.size.y * 0.55, bounds.position.z)
	holder.add_child(mz)
	_holders[id] = holder
	_muzzles[id] = mz
	_ads_y[id] = -bounds.end.y - SIGHT_GAP
	holder.visible = false


func _build_medkit(holder: Node3D) -> AABB:
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.16, 0.09)
	box.mesh = bm
	box.material_override = _flat(Color(0.95, 0.95, 0.95))
	holder.add_child(box)
	var red := _flat(Color(0.85, 0.08, 0.08))
	for sz in [Vector3(0.13, 0.04, 0.004), Vector3(0.04, 0.11, 0.004)]:
		var c := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = sz
		c.mesh = cm
		c.material_override = red
		c.position = Vector3(0, 0, 0.046)  # +Z face, towards the player
		holder.add_child(c)
	holder.rotation.y = 0.35
	return AABB(Vector3(-0.125, -0.08, -0.045), Vector3(0.25, 0.16, 0.09))


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m


## Bounds of all meshes under n, expressed in the local space of `root`.
func _mesh_bounds(n: Node, root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var xf := Transform3D.IDENTITY
			var p: Node = cur
			while p != root and p != null:
				if p is Node3D:
					xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var bb: AABB = xf * (cur as MeshInstance3D).get_aabb()
			result = bb if first else result.merge(bb)
			first = false
		for c in cur.get_children():
			stack.push_back(c)
	return result


func _disable_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_disable_shadows(c)
