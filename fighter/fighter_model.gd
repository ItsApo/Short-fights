class_name FighterModel
extends Node3D
## Third-person animated character (Quaternius Toon Shooter GLB). Origin at feet, faces -Z, ~1.8 m tall.
## Measured: the GLBs face +Z, are ~2.0 m tall (head bone end y: soldier 2.008, enemy 2.062, hazmat 1.978), feet at y~0.

const SKINS := ["soldier", "enemy", "hazmat"]
const HEIGHTS := [2.008, 2.062, 1.978]  # measured head-top height of each GLB at scale 1
const TARGET_HEIGHT := 1.8
const PREFIX := "CharacterArmature|"
const LOOPED := ["Idle", "Run", "Run_Gun", "Idle_Shoot", "Jump_Idle"]
const WEAPON_NODES := ["AK", "Shotgun", "Pistol", "Revolver", "Revolver_Small", "SMG", "Sniper", "Sniper_2", "ShortCannon", "GrenadeLauncher", "RocketLauncher", "Shovel", "Knife_1", "Knife_2"]
const BLEND := 0.15
const MARKER_HEIGHT := 2.25

var _pivot: Node3D
var _marker: Node3D
var _anim: AnimationPlayer
var _weapons: Dictionary = {}  # node name -> Node3D
var _weapon_shown := false
var _cur := ""
var _dead := false
var _hit_left := 0.0
var _want := ""  # locomotion animation wanted (applied when not in a one-shot)
var _want_speed := 1.0
var _hide_for_local := false


func setup(skin: int, team_color: Color, hide_for_local: bool) -> void:
	_hide_for_local = hide_for_local
	skin = clampi(skin, 0, SKINS.size() - 1)
	var scene := load("res://assets/models/%s.glb" % SKINS[skin]) as PackedScene
	if scene == null:
		push_error("FighterModel: cannot load skin %d" % skin)
		return
	var inst := scene.instantiate() as Node3D
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	var s: float = TARGET_HEIGHT / float(HEIGHTS[skin])
	_pivot.scale = Vector3(s, s, s)
	_pivot.rotation.y = PI  # GLB faces +Z, Fighter forward is -Z
	add_child(_pivot)
	_pivot.add_child(inst)
	_anim = _find_player(inst)
	_collect_weapons(inst)
	set_weapon("rifle")
	_setup_animations()
	_build_marker(team_color)
	if hide_for_local:
		_marker.visible = false
		_shadows_only(self)
	_want = "Idle"
	_cur = ""
	if is_inside_tree():
		_apply_want(true)


func _ready() -> void:
	_apply_want(true)


func set_weapon(id: String) -> void:
	var node_name := ""
	if Weapons.DATA.has(id):
		node_name = String(Weapons.DATA[id].get("char_node", ""))
	_weapon_shown = node_name != ""
	for k in _weapons:
		(_weapons[k] as Node3D).visible = (k == node_name)


func set_motion(speed: float, on_floor: bool, shooting: bool) -> void:
	var anim := "Idle"
	var spd := 1.0
	if not on_floor:
		anim = "Jump_Idle"
	elif speed > 0.6:
		anim = "Run_Gun" if _weapon_shown else "Run"
		spd = clampf(speed / 5.0, 0.7, 1.8)
	elif shooting:
		anim = "Idle_Shoot"
	_want = anim
	_want_speed = spd
	if _dead or _hit_left > 0.0:
		return
	_apply_want(false)


func play_hit() -> void:
	if _dead or _anim == null:
		return
	var n := _anim_name("HitReact")
	if n == "":
		return
	_hit_left = _anim.get_animation(n).length
	_cur = "HitReact"
	_play(n, BLEND, 1.0)


func die() -> void:
	if _anim == null:
		return
	_dead = true
	_hit_left = 0.0
	var n := _anim_name("Death")
	if n == "":
		return
	_cur = "Death"
	_play(n, 0.1, 1.0)


func revive() -> void:
	_dead = false
	_hit_left = 0.0
	_want = "Idle"
	_want_speed = 1.0
	_cur = ""
	_apply_want(true)


func _process(delta: float) -> void:
	if _marker != null:
		_marker.rotation.y += delta * 1.6
		_marker.position.y = MARKER_HEIGHT + sin(Time.get_ticks_msec() * 0.003) * 0.04
	if _hit_left > 0.0:
		_hit_left -= delta
		if _hit_left <= 0.0 and not _dead:
			_cur = ""
			_apply_want(false)


func _apply_want(instant: bool) -> void:
	if _anim == null or not is_inside_tree() or _dead:
		return
	if _want == _cur:
		_anim.speed_scale = _want_speed
		return
	var n := _anim_name(_want)
	if n == "":
		return
	_cur = _want
	_play(n, 0.0 if instant else BLEND, _want_speed)


func _play(n: String, blend: float, speed: float) -> void:
	if _anim == null or not is_inside_tree():
		return
	_anim.speed_scale = speed
	_anim.play(n, blend)


func _anim_name(n: String) -> String:
	if _anim == null:
		return ""
	if _anim.has_animation(PREFIX + n):
		return PREFIX + n
	if _anim.has_animation(n):
		return n
	return ""


func _setup_animations() -> void:
	if _anim == null:
		return
	for n in _anim.get_animation_list():
		var short := String(n).replace(PREFIX, "")
		var a := _anim.get_animation(n)
		a.loop_mode = Animation.LOOP_LINEAR if short in LOOPED else Animation.LOOP_NONE


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null


func _collect_weapons(n: Node) -> void:
	if n is Node3D and String(n.name) in WEAPON_NODES:
		_weapons[String(n.name)] = n
	for c in n.get_children():
		_collect_weapons(c)


func _shadows_only(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for c in n.get_children():
		_shadows_only(c)


func _build_marker(color: Color) -> void:
	_marker = Node3D.new()
	_marker.name = "TeamMarker"
	_marker.position.y = MARKER_HEIGHT
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = false
	for i in 2:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.09
		cone.height = 0.13
		cone.radial_segments = 4
		cone.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = 0.065 if i == 0 else -0.065
		if i == 1:
			mi.rotation.x = PI
		_marker.add_child(mi)
	add_child(_marker)
