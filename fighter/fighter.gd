class_name Fighter
extends CharacterBody3D
## Player / bot body. Built entirely in code. Only the authority simulates it.

const SPEED := 6.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 5.0
const PITCH_LIMIT := 1.5
const SYNC_DELAY := 0.5
const BASE_FOV := 80.0

var team := 0
var peer_id := 1
var is_bot := false
var primary := "rifle"
var display_name := ""

var health: int = 100:
	set(v):
		health = v
		if is_inside_tree() and is_local():
			var h = get_tree().get_first_node_in_group("hud")
			if h:
				h.set_health(v)
var alive := true
var yaw := 0.0
var pitch := 0.0
var slot := 0

var head: Node3D
var slots: Array = []
var mag := {}
var reserve := {}
var medkits := 0
var grenades := 0
var cooldown := 0.0
var reload_t := 0.0
var use_t := 0.0
var prev_fire := false

var last_shot_ms := 0  # Time.get_ticks_msec() of this fighter's last shot, on every peer (bots "hear" it)

var _model: FighterModel
var _view: ViewModel
var _camera: Camera3D
var _ai: BotAI
var _mouse_acc := Vector2.ZERO
var _alive_time := 0.0
var _sync_pos := Vector3.ZERO
var _has_sync := false
var _shown_slot := -1
var _hud_text := ""
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _aim := 0.0  # 0..1 ADS blend
var _aim_on := false
var _trauma := 0.0
var _recoil_debt := 0.0
var _step_t := 0.0
var _was_floor := true
var _rspeed := 0.0
var _rvy := 0.0
var _rfloor := true


func _enter_tree() -> void:
	add_to_group("fighters")
	collision_layer = 2 if alive else 0
	collision_mask = 3


func _ready() -> void:
	slots = [primary, "pistol", "medkit", "grenade"]
	_build_body()
	if is_bot:
		_ai = BotAI.new()
	_reset_weapons()
	health = Game.MAX_HEALTH
	if is_local():
		_camera.current = true
		_hud_text = ""
		_hud_sync()
	set_process(is_local())
	set_alive(alive)


func is_local() -> bool:
	return not is_bot and is_inside_tree() and peer_id == multiplayer.get_unique_id()


# ---------------------------------------------------------------- build

func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)

	head = Node3D.new()
	head.name = "Head"
	head.position.y = 1.6
	add_child(head)

	_camera = Camera3D.new()
	_camera.fov = BASE_FOV
	head.add_child(_camera)

	_model = FighterModel.new()
	_model.name = "Model"
	add_child(_model)
	_model.setup(team % 3, Game.team_color(team), is_local())

	if is_local():
		_view = ViewModel.new()
		_view.name = "ViewModel"
		_camera.add_child(_view)


func _rebuild_weapon_visual() -> void:
	_shown_slot = slot
	var id: String = slots[slot]
	if _model:
		_model.set_weapon(id)
	if _view:
		_view.set_weapon(id)


# ---------------------------------------------------------------- state API

func set_alive(v: bool) -> void:
	var was := alive
	alive = v
	collision_layer = 2 if v else 0
	set_physics_process(v)
	if _view:
		_view.visible = v  # no weapon on screen while dead
	if v:
		visible = true
		if not was and _model:
			_model.revive()
		_trauma = 0.0
	else:
		velocity = Vector3.ZERO
		prev_fire = false
		_aim = 0.0
		_recoil_debt = 0.0
		if was and is_inside_tree():
			# keep the body visible for the death animation, hide it afterwards
			if _model:
				_model.die()
			_snd("death")
			get_tree().create_timer(2.0).timeout.connect(_hide_if_dead)
			if is_local():
				_set_aim_hud(false)
				_aim_on = false
				var h = get_tree().get_first_node_in_group("hud")
				if h:
					h.show_message("Reapareces en 3 s", 3.0)
		elif not was:
			visible = false


func _hide_if_dead() -> void:
	if not alive:
		visible = false


func respawn(pos: Vector3) -> void:
	global_position = pos
	yaw = atan2(pos.x, pos.z)  # face the map center (maps are centered on the origin)
	pitch = 0.0
	rotation.y = yaw
	_sync_pos = pos
	_has_sync = false
	velocity = Vector3.ZERO
	_alive_time = 0.0
	_mouse_acc = Vector2.ZERO
	_aim = 0.0
	_recoil_debt = 0.0
	_rspeed = 0.0
	health = Game.MAX_HEALTH
	_reset_weapons()
	set_alive(true)


func _reset_weapons() -> void:
	mag.clear()
	reserve.clear()
	for id in [primary, "pistol"]:
		mag[id] = int(Weapons.DATA[id].mag)
		reserve[id] = int(Weapons.DATA[id].reserve)
	medkits = int(Weapons.DATA.medkit.count)
	grenades = int(Weapons.DATA.grenade.count)
	slot = 0
	cooldown = 0.0
	reload_t = 0.0
	use_t = 0.0
	prev_fire = false
	_rebuild_weapon_visual()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and is_local():
		_mouse_acc += event.relative


func _human_intent() -> Dictionary:
	var look := (-(_mouse_acc * Game.MOUSE_SENS) - Game.touch_look) * lerpf(1.0, 0.6, _aim)
	_mouse_acc = Vector2.ZERO
	Game.touch_look = Vector2.ZERO
	var sl := -1
	for i in 4:
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			sl = i
	var can_fire := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.is_touchscreen_available()
	return {
		"move": Input.get_vector("move_left", "move_right", "move_back", "move_forward"),
		"look": look,
		"jump": Input.is_action_pressed("jump"),
		"fire": can_fire and Input.is_action_pressed("fire"),
		"reload": Input.is_action_just_pressed("reload"),
		"slot": sl,
		"next": Input.is_action_just_pressed("next_weapon"),
		"aim": (can_fire and Input.is_action_pressed("aim")) or "--test-aim" in OS.get_cmdline_user_args(),
		"sprint": Input.is_action_pressed("sprint"),
	}


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_remote_step(delta)
		return

	var intent: Dictionary
	if is_bot:
		intent = _ai.think(self, delta)
	elif is_local():
		intent = _human_intent()
	else:
		return

	# look (+ recoil recovery)
	var look: Vector2 = intent.look
	if _recoil_debt > 0.0:
		var rec := _recoil_debt * (1.0 - exp(-delta / 0.1))
		_recoil_debt -= rec
		look.y -= rec
	yaw = wrapf(yaw + look.x, -PI, PI)
	pitch = clampf(pitch + look.y, -PITCH_LIMIT, PITCH_LIMIT)
	rotation.y = yaw
	head.rotation.x = pitch

	# aim / sprint state
	var mv: Vector2 = intent.move
	var fire_want: bool = intent.fire
	var aiming: bool = bool(intent.get("aim", false)) and slot <= 1 and reload_t <= 0.0
	var sprinting: bool = bool(intent.get("sprint", false)) and not aiming and not fire_want \
			and reload_t <= 0.0 and use_t <= 0.0 and mv.y > 0.1
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, delta * 8.0)
	if is_local() and aiming != _aim_on:
		_set_aim_hud(aiming)
	_aim_on = aiming

	# move
	var speed := SPEED
	if sprinting:
		mv = Vector2(0.0, 1.0)
		speed = SPRINT_SPEED
	elif aiming:
		speed = SPEED * 0.6
	var dir := (global_basis * Vector3(mv.x, 0.0, -mv.y))
	dir.y = 0.0
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * speed
	var accel := 12.0 if is_on_floor() else 3.0
	var k := minf(accel * delta, 1.0)
	velocity.x = lerpf(velocity.x, target.x, k)
	velocity.z = lerpf(velocity.z, target.z, k)
	var vy_before := velocity.y
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif intent.jump:
		velocity.y = JUMP_VELOCITY
		_snd("jump", -4.0)
	move_and_slide()
	var on_floor := is_on_floor()
	if on_floor and not _was_floor and vy_before < -4.0:
		_snd("land", -2.0)
	_was_floor = on_floor

	var hspeed := Vector2(velocity.x, velocity.z).length()
	_footsteps(delta, hspeed, on_floor)
	_weapons_step(intent, delta)
	if _model:
		_model.set_motion(hspeed, on_floor, Time.get_ticks_msec() - last_shot_ms < 300)

	_alive_time += delta
	if _alive_time > SYNC_DELAY:
		_sync.rpc(global_position, yaw, pitch, slot)
	if is_local():
		_hud_sync()


func _footsteps(delta: float, hspeed: float, on_floor: bool) -> void:
	if on_floor and hspeed > 1.5:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.28 if hspeed > 7.0 else 0.38
			_snd("step", -8.0)
	else:
		_step_t = minf(_step_t, 0.1)


## Local fighter: 2D sound; everyone else: 3D at their position.
func _snd(id: String, vol := 0.0) -> void:
	if not is_inside_tree():
		return
	if is_local():
		Sfx.play(id, null, vol)
	else:
		Sfx.play(id, global_position, vol)


func _set_aim_hud(v: bool) -> void:
	var h = get_tree().get_first_node_in_group("hud")
	if h and h.has_method("set_aim"):
		h.set_aim(v)


func _remote_step(delta: float) -> void:
	var prev := global_position
	var snapped_pos := false
	if _has_sync:
		if global_position.distance_to(_sync_pos) > 5.0:
			global_position = _sync_pos
			snapped_pos = true
		else:
			global_position = global_position.lerp(_sync_pos, clampf(15.0 * delta, 0.0, 1.0))
	rotation.y = yaw
	head.rotation.x = pitch
	if slot != _shown_slot:
		_rebuild_weapon_visual()
		_snd("switch", -6.0)
	# speed / floor state from the synced position delta
	var d := global_position - prev
	if snapped_pos or delta <= 0.0:
		_rspeed = 0.0
		_rvy = 0.0
	else:
		var hv := Vector2(d.x, d.z).length() / delta
		_rspeed = lerpf(_rspeed, hv, clampf(10.0 * delta, 0.0, 1.0))
		_rvy = lerpf(_rvy, d.y / delta, clampf(10.0 * delta, 0.0, 1.0))
	var floor_now := absf(_rvy) < 1.5
	if _rfloor and _rvy > 3.0:
		_snd("jump", -4.0)
	_rfloor = floor_now
	_footsteps(delta, _rspeed, floor_now)
	if _model:
		_model.set_motion(_rspeed, floor_now, Time.get_ticks_msec() - last_shot_ms < 300)


## Local human only (set_process): fov, view model, camera shake.
func _process(delta: float) -> void:
	if not alive or _camera == null:
		return
	var fov := BASE_FOV
	if slot <= 1:
		fov = lerpf(BASE_FOV, float(Weapons.DATA[slots[slot]].ads_fov), _aim)
	_camera.fov = fov
	if _view:
		_view.update(delta, _aim, Vector2(velocity.x, velocity.z).length(), is_on_floor())
	if _trauma > 0.001:
		_trauma = maxf(_trauma - delta * 1.8, 0.0)
		var t2 := _trauma * _trauma
		_camera.position = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.06 * t2
		_camera.rotation.z = randf_range(-1.0, 1.0) * 0.04 * t2
	elif _camera.position != Vector3.ZERO:
		_camera.position = Vector3.ZERO
		_camera.rotation.z = 0.0


@rpc("authority", "unreliable_ordered")
func _sync(pos: Vector3, y: float, p: float, s: int) -> void:
	if not alive:
		return
	_sync_pos = pos
	yaw = y
	pitch = p
	slot = clampi(s, 0, 3)
	_has_sync = true


# ---------------------------------------------------------------- weapons

func _set_slot(s: int) -> void:
	s = clampi(s, 0, 3)
	if s == slot:
		return
	slot = s
	reload_t = 0.0
	use_t = 0.0
	_rebuild_weapon_visual()
	_snd("switch", -4.0)


func _start_reload(w: Dictionary) -> void:
	reload_t = float(w.reload_time)
	_snd("reload")
	if _view:
		_view.reload_anim(reload_t)


func _weapons_step(intent: Dictionary, delta: float) -> void:
	var want_slot: int = intent.slot
	if intent.next:
		_set_slot((slot + 1) % 4)
	elif want_slot >= 0:
		_set_slot(want_slot)

	cooldown = maxf(cooldown - delta, 0.0)
	var id: String = slots[slot]
	var w: Dictionary = Weapons.DATA[id]
	var fire_held: bool = intent.fire
	var pressed := fire_held and not prev_fire
	prev_fire = fire_held

	if slot <= 1:
		if reload_t > 0.0:
			reload_t -= delta
			if reload_t <= 0.0:
				reload_t = 0.0
				var take := mini(int(w.mag) - int(mag[id]), int(reserve[id]))
				mag[id] += take
				reserve[id] -= take
		else:
			if (intent.reload and mag[id] < int(w.mag) and reserve[id] > 0) or (mag[id] == 0 and reserve[id] > 0):
				_start_reload(w)
			elif cooldown <= 0.0 and mag[id] > 0 and fire_held and (bool(w.auto) or pressed):
				mag[id] -= 1
				cooldown = float(w.fire_rate)
				_shoot(id, w)
			elif pressed and mag[id] == 0 and reserve[id] == 0:
				cooldown = 0.3
				_snd("empty")
	elif slot == 2:
		if use_t > 0.0:
			use_t -= delta
			if use_t <= 0.0:
				use_t = 0.0
				medkits -= 1
				_snd("heal")
				var m = get_tree().get_first_node_in_group("match")
				if m:
					m.request_heal.rpc_id(1, String(name), int(w.heal))
		elif pressed and medkits > 0 and health < Game.MAX_HEALTH:
			use_t = float(w.use_time)
	else:
		if pressed and grenades > 0 and cooldown <= 0.0:
			grenades -= 1
			cooldown = 0.6
			_snd("throw")
			var fwd := -head.global_basis.z
			var m = get_tree().get_first_node_in_group("match")
			if m:
				m.spawn_grenade.rpc(head.global_position + fwd * 0.6, fwd * float(w.throw_speed) + velocity + Vector3.UP * 2.0, String(name))


func _shoot(id: String, w: Dictionary) -> void:
	var origin := head.global_position
	var hb := head.global_basis
	var fwd := -hb.z
	var space := get_world_3d().direct_space_state
	var spread := float(w.spread) * lerpf(1.0, float(w.ads_spread), _aim)
	var rng := float(w.range)
	var dmg := {}
	var heads := {}
	var ends := PackedVector3Array()
	var flesh := PackedByteArray()  # 0 wall, 1 fighter, 2 miss (no impact)
	for i in int(w.pellets):
		var a := randf() * TAU
		var r := spread * sqrt(randf())
		var dir := (fwd + hb.x * cos(a) * r + hb.y * sin(a) * r).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng, 3, [get_rid()])
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			ends.append(origin + dir * minf(rng, 100.0))
			flesh.append(2)
			continue
		ends.append(hit.position)
		var c = hit.collider
		flesh.append(1 if c is Fighter else 0)
		if c is Fighter and c.alive and Game.are_enemies(team, c.team):
			var hs: bool = float(hit.position.y) - c.global_position.y > Weapons.HEAD_HEIGHT
			var d := int(w.damage)
			if hs:
				d = int(round(d * Weapons.HEADSHOT_MULT))
				heads[c] = true
			dmg[c] = int(dmg.get(c, 0)) + d

	var from := origin + fwd * 0.6
	if _view:
		from = _view.muzzle_global()
	_shot_fx.rpc(from, ends, flesh, id)

	# recoil (humans only; bots aim by look deltas)
	var rc := float(w.recoil)
	if not is_bot:
		pitch = clampf(pitch + rc, -PITCH_LIMIT, PITCH_LIMIT)
		head.rotation.x = pitch
		yaw = wrapf(yaw + randf_range(-0.3, 0.3) * rc, -PI, PI)
		rotation.y = yaw
		_recoil_debt += rc * 0.6  # recovers over ~0.3 s
		if _view:
			_view.kick(rc)

	if dmg.is_empty():
		return
	var m = get_tree().get_first_node_in_group("match")
	var any_head := false
	for t in dmg:
		var hs2: bool = heads.has(t)
		any_head = any_head or hs2
		if m:
			m.request_damage.rpc_id(1, String(t.name), int(dmg[t]), String(name), hs2)
	if is_local():
		var h = get_tree().get_first_node_in_group("hud")
		if h:
			h.flash_hit(any_head)
		Sfx.play("headshot" if any_head else "hit")


func _fx_parent() -> Node:
	var m = get_tree().get_first_node_in_group("match")
	if m and m.has_node("Projectiles"):
		return m.get_node("Projectiles")
	return get_tree().current_scene


@rpc("authority", "call_local", "unreliable")
func _shot_fx(from: Vector3, ends: PackedVector3Array, flesh: PackedByteArray, weapon: String) -> void:
	last_shot_ms = Time.get_ticks_msec()
	if not is_inside_tree():
		return
	var parent := _fx_parent()
	if parent == null:
		return
	var d := -head.global_basis.z
	if ends.size() > 0 and ends[0].distance_to(from) > 0.01:
		d = (ends[0] - from).normalized()
	Fx.muzzle(parent, from, d)
	if is_local():
		Sfx.play(weapon)
	else:
		Sfx.play(weapon, from)
	for i in ends.size():
		Fx.tracer(parent, from, ends[i])
		var f := int(flesh[i]) if i < flesh.size() else 0
		if f != 2:
			var n := (from - ends[i]).normalized()
			Fx.impact(parent, ends[i], n, f == 1)


func _hud_sync() -> void:
	var id: String = slots[slot]
	var w: Dictionary = Weapons.DATA[id]
	var text: String
	if slot <= 1:
		text = "%d/%d" % [mag[id], reserve[id]]
	elif slot == 2:
		text = "x%d" % medkits
	else:
		text = "x%d" % grenades
	var key := "%s|%s" % [w.name, text]
	if key == _hud_text:
		return
	_hud_text = key
	var h = get_tree().get_first_node_in_group("hud")
	if h:
		h.set_weapon(w.name, text)


# ---------------------------------------------------------------- hurt / shake (called by Match / Fx on all peers)

func on_hurt(from: Vector3, headshot: bool) -> void:
	if _model:
		_model.play_hit()
	if not is_local() or not is_inside_tree():
		return
	var d := from - global_position
	d.y = 0.0
	if d.length() > 0.01:
		var f := -global_basis.z
		f.y = 0.0
		var rt := global_basis.x
		rt.y = 0.0
		var angle := atan2(d.dot(rt.normalized()), d.dot(f.normalized()))
		var h = get_tree().get_first_node_in_group("hud")
		if h and h.has_method("damage_from"):
			h.damage_from(angle)
	Sfx.play("hurt")
	_trauma = minf(_trauma + (0.45 if headshot else 0.3), 1.0)


func shake(origin: Vector3, strength: float) -> void:
	if not is_local() or not alive:
		return
	var k := clampf(1.0 - global_position.distance_to(origin) / 30.0, 0.0, 1.0)
	_trauma = minf(_trauma + strength * k, 1.0)
