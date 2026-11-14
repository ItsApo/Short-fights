class_name BotAI
extends RefCounted
## Bot brain: think(fighter, delta) returns a full intent dictionary.
## States: ENGAGE (shoot visible enemy), CHASE (go to last seen pos), INVESTIGATE (heard shots),
## RETREAT_HEAL (low health: break contact, then medkit), ROAM (wander toward the action).

enum State { ENGAGE, CHASE, INVESTIGATE, RETREAT_HEAL, ROAM }

const REACTION := [0.6, 0.35, 0.15]
const AIM_NOISE := [0.12, 0.06, 0.02]
const TURN_SPEED := [3.0, 5.0, 8.0]
const PATH_INTERVAL := 0.7
const PATH_RETARGET_DIST := 3.0
const WAYPOINT_DIST := 0.6
const HEAR_RANGE := 30.0
const HEAR_WINDOW_MS := 1000
const MEMORY_TIME := 8.0
const LOW_HEALTH := 35
const HEALED_HEALTH := 70

var state: State = State.ROAM
var target = null

var _retarget := 0.0
var _los := false
var _los_t := 0.0
var _seen_t := 0.0
var _strafe := 1.0
var _strafe_t := 1.0
var _noise := Vector2.ZERO
var _noise_t := 0.0
var _aim_h := 1.2
var _aim_h_t := 0.0
var _gren_t := 4.0
var _throwing := false
var _throw_t := 0.0
var _throw_pt := Vector3.ZERO
var _gren_before := 0
var _stuck_t := 0.0
var _unstick_t := 0.0

var _has_memory := false
var _last_seen := Vector3.ZERO
var _mem_age := 0.0
var _hear_t := 0.0
var _inv_t := 0.0
var _inv_pos := Vector3.ZERO
var _roam_goal := Vector3.ZERO
var _roam_t := 0.0
var _retreat_goal := Vector3.ZERO
var _retreat_t := 0.0
var _retreat_age := 0.0

var _path := PackedVector3Array()
var _path_i := 0
var _path_t := 0.0
var _path_goal := Vector3(INF, INF, INF)


func think(f, delta: float) -> Dictionary:
	var intent := {"move": Vector2.ZERO, "look": Vector2.ZERO, "jump": false, "fire": false, "reload": false, "slot": -1, "next": false, "aim": false, "sprint": false}
	var diff: int = clampi(int(Game.config.get("difficulty", 1)), 0, 2)
	var reaction: float = REACTION[diff]
	var noise_amp: float = AIM_NOISE[diff]
	var turn_speed: float = TURN_SPEED[diff]
	var pos: Vector3 = f.global_position
	var from: Vector3 = f.head.global_position

	# ---- target + line of sight
	_retarget -= delta
	if _retarget <= 0.0 or not is_instance_valid(target) or not target.alive:
		_retarget = 0.5
		var old = target
		target = _pick_target(f)
		if not is_instance_valid(old) or target != old:
			_los = false
			_los_t = 0.0
			_seen_t = 0.0
	if is_instance_valid(target):
		_los_t -= delta
		if _los_t <= 0.0:
			_los_t = 0.1
			_los = _can_see(f, from, target)
		_seen_t = _seen_t + delta if _los else 0.0
	else:
		_los = false
		_seen_t = 0.0
	var visible: bool = _los and _seen_t >= reaction

	# ---- memory + hearing
	if visible:
		_last_seen = target.global_position
		_has_memory = true
		_mem_age = 0.0
	else:
		_mem_age += delta
		if _mem_age > MEMORY_TIME:
			_has_memory = false
	_inv_t -= delta
	_hear_t -= delta
	if _hear_t <= 0.0:
		_hear_t = 0.2
		var heard = _listen(f)
		if heard != null and not visible:
			_inv_pos = heard + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			_inv_t = 6.0

	# ---- state selection
	var can_heal: bool = f.medkits > 0 and f.health < Game.MAX_HEALTH
	var in_heal := state == State.RETREAT_HEAL
	if in_heal:
		if f.use_t <= 0.0 and (f.health >= HEALED_HEALTH or not can_heal):
			in_heal = false
	elif f.health < LOW_HEALTH and can_heal:
		in_heal = true
	var new_state: State
	if in_heal:
		new_state = State.RETREAT_HEAL
	elif visible:
		new_state = State.ENGAGE
	elif _inv_t > 0.0:
		new_state = State.INVESTIGATE
	elif _has_memory:
		new_state = State.CHASE
	else:
		new_state = State.ROAM
	if new_state != state:
		state = new_state
		_path_t = 0.0
		_roam_t = 0.0
		_retreat_t = 0.0
		_retreat_age = 99.0
		if state != State.ENGAGE and state != State.CHASE:
			_throwing = false

	# ---- aim height / noise / strafe timers
	_aim_h_t -= delta
	if _aim_h_t <= 0.0:
		_aim_h_t = 1.0
		match diff:
			0:
				_aim_h = 1.15
			1:
				_aim_h = randf_range(1.2, 1.55)
			_:
				_aim_h = 1.55
	_noise_t -= delta
	if _noise_t <= 0.0:
		_noise_t = 0.4
		_noise = Vector2(randf_range(-noise_amp, noise_amp), randf_range(-noise_amp, noise_amp))
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.0, 2.0)
		_strafe = 1.0 if randf() < 0.5 else -1.0
	_unstick_t -= delta

	# ---- per-state: where to look, where to go
	var has_look := false
	var look_pt := Vector3.ZERO
	var noisy := false
	var wp_dir := Vector3.ZERO     # horizontal world direction to the next waypoint
	var lm := Vector2.ZERO         # local move: x right, y forward
	var goal_dist := 0.0
	var heal_now := false
	var aim_flat := 0.0

	match state:
		State.ENGAGE:
			look_pt = target.global_position + Vector3(0.0, _aim_h, 0.0)
			has_look = true
			noisy = true
			aim_flat = Vector2(look_pt.x - from.x, look_pt.z - from.z).length()
			lm.x = _strafe
			if aim_flat < 6.0:
				lm.y = -1.0
			elif aim_flat > 15.0:
				var wp := _follow(f, target.global_position, delta)
				wp_dir = _flat(wp - pos)
				lm = _local(f, wp_dir) + Vector2(_strafe * 0.3, 0.0)
			goal_dist = aim_flat
		State.CHASE:
			goal_dist = _flat(_last_seen - pos).length()
			if goal_dist < 1.5:
				_has_memory = false
			else:
				var wp := _follow(f, _last_seen, delta)
				wp_dir = _flat(wp - pos)
				lm = _local(f, wp_dir)
		State.INVESTIGATE:
			goal_dist = _flat(_inv_pos - pos).length()
			if goal_dist < 2.0:
				_inv_t = 0.0
			else:
				var wp := _follow(f, _inv_pos, delta)
				wp_dir = _flat(wp - pos)
				lm = _local(f, wp_dir)
		State.RETREAT_HEAL:
			_retreat_age += delta
			var threatened: bool = _los or (_has_memory and _mem_age < 1.0)
			if threatened:
				_retreat_t += delta
			if f.use_t > 0.0 or not threatened or _retreat_t > 4.0:
				heal_now = true
			else:
				if _retreat_age > 1.5:
					_retreat_age = 0.0
					_retreat_goal = _pick_retreat(f, pos)
					_path_t = 0.0
				goal_dist = _flat(_retreat_goal - pos).length()
				var wp := _follow(f, _retreat_goal, delta)
				wp_dir = _flat(wp - pos)
				lm = _local(f, wp_dir)
		_:
			_roam_t -= delta
			goal_dist = _flat(_roam_goal - pos).length()
			if _roam_t <= 0.0 or goal_dist < 2.0:
				_roam_t = 10.0
				_roam_goal = _pick_roam(f)
				_path_t = 0.0
				goal_dist = _flat(_roam_goal - pos).length()
			var wp := _follow(f, _roam_goal, delta)
			wp_dir = _flat(wp - pos)
			lm = _local(f, wp_dir)

	# ---- grenades
	_gren_t -= delta
	if _gren_t <= 0.0:
		_gren_t = 5.0
		if f.grenades > 0 and not _throwing and (state == State.ENGAGE or (state == State.CHASE and not _los)):
			var pt: Vector3 = target.global_position if state == State.ENGAGE else _last_seen
			var fl := _flat(pt - from).length()
			var chance := 0.25 if state == State.ENGAGE else 0.4
			if fl >= 8.0 and fl <= 20.0 and randf() < chance:
				_throwing = true
				_throw_t = 2.5
				_gren_before = f.grenades
				_throw_pt = pt
	if _throwing:
		_throw_t -= delta
		if state == State.ENGAGE:
			_throw_pt = target.global_position
		var tfl := _flat(_throw_pt - from).length()
		if _throw_t <= 0.0 or f.grenades < _gren_before or tfl < 7.0 or tfl > 21.0 or (state != State.ENGAGE and state != State.CHASE):
			_throwing = false
		else:
			look_pt = _throw_pt + Vector3(0.0, 0.5, 0.0)
			has_look = true
			noisy = true

	# ---- look
	var want_yaw: float = f.yaw
	var want_pitch := 0.0
	var tol := maxf(0.05, noise_amp * 1.2)
	if has_look:
		var d := look_pt - from
		var flat := Vector2(d.x, d.z).length()
		want_yaw = atan2(-d.x, -d.z)
		want_pitch = atan2(d.y, flat)
		if _throwing:
			# lob: ballistic angle at throw speed, minus the built-in upward kick
			var v: float = Weapons.DATA.grenade.throw_speed
			var s := clampf(9.8 * flat / (v * v), 0.0, 0.99)
			want_pitch += maxf(0.5 * asin(s) - 0.1, 0.0)
	elif wp_dir.length() > 0.05:
		want_yaw = atan2(-wp_dir.x, -wp_dir.z)
	var max_step: float = turn_speed * delta
	var yaw_err := angle_difference(f.yaw, want_yaw)
	var pitch_err: float = want_pitch - f.pitch
	var n := _noise if noisy else Vector2.ZERO
	var yaw_step := clampf(angle_difference(f.yaw, want_yaw + n.x), -max_step, max_step)
	var pitch_step := clampf(want_pitch + n.y - f.pitch, -max_step, max_step)
	intent.look = Vector2(yaw_step, pitch_step)
	var aimed: bool = has_look and absf(yaw_err) < tol and absf(pitch_err) < tol

	# ---- stuck detection (jump / swap strafe / replan)
	var hspeed := Vector2(f.velocity.x, f.velocity.z).length()
	if lm.length() > 0.1 and hspeed < 1.0:
		_stuck_t += delta
		if _stuck_t > 0.4:
			intent.jump = true
			_strafe = -_strafe
			_strafe_t = randf_range(1.0, 2.0)
			_stuck_t = 0.0
			_unstick_t = 0.6
			_path_t = 0.0
	else:
		_stuck_t = 0.0
	if _unstick_t > 0.0 and state != State.ENGAGE:
		lm.x += _strafe * 0.7
	intent.move = lm

	# ---- sprint / ADS
	var fwd_only := lm.y > 0.8 and absf(lm.x) < 0.4
	if fwd_only and not _throwing and not heal_now:
		match state:
			State.CHASE, State.INVESTIGATE:
				intent.sprint = goal_dist > 15.0
			State.RETREAT_HEAL:
				intent.sprint = true
			State.ROAM:
				intent.sprint = goal_dist > 25.0
	if state == State.ENGAGE and diff >= 1 and aim_flat > 15.0 and not _throwing and f.slot < 2:
		intent.aim = true

	# ---- slot choice + trigger
	var primary_ok := _ammo(f, f.primary) > 0
	var base := 0 if primary_ok else 1
	if not primary_ok and _ammo(f, "pistol") <= 0:
		base = 0
	var want := base
	if (heal_now or f.use_t > 0.0) and f.medkits > 0 and f.health < Game.MAX_HEALTH:
		want = 2
	elif _throwing:
		want = 3
	if f.slot != want:
		intent.slot = want
		intent.aim = false
	else:
		match want:
			2:
				if f.use_t <= 0.0:
					intent.fire = _pull(f, true, false)
			3:
				if aimed:
					intent.fire = _pull(f, true, false)
			_:
				var id: String = f.slots[want]
				var auto: bool = Weapons.DATA[id].auto
				if state == State.ENGAGE and aimed:
					intent.fire = _pull(f, true, auto)
				var mag: int = f.mag.get(id, 0)
				var full: int = Weapons.DATA[id].mag
				if mag == 0 or (not visible and mag < full / 2):
					intent.reload = true
	return intent


# ---------------------------------------------------------------- helpers

func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## World horizontal direction -> fighter-local move (x right+, y forward+), unit length.
func _local(f, dir: Vector3) -> Vector2:
	if dir.length() < 0.01:
		return Vector2.ZERO
	var l: Vector3 = Basis(Vector3.UP, f.yaw).inverse() * dir.normalized()
	return Vector2(l.x, -l.z)


func _can_see(f, from: Vector3, o) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, o.head.global_position, 1)
	return f.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Next waypoint toward goal (recomputes the path every PATH_INTERVAL or when the goal moves).
func _follow(f, goal: Vector3, delta: float) -> Vector3:
	_path_t -= delta
	if _path_t <= 0.0 or goal.distance_to(_path_goal) > PATH_RETARGET_DIST:
		_path_t = PATH_INTERVAL
		_path_goal = goal
		_path = Nav.path(f.get_world_3d(), f.global_position, goal)
		_path_i = 1 if _path.size() > 1 else 0
	if _path.is_empty():
		return goal
	var pos: Vector3 = f.global_position
	while _path_i < _path.size() - 1:
		var w := _path[_path_i]
		if Vector2(w.x - pos.x, w.z - pos.z).length() < WAYPOINT_DIST:
			_path_i += 1
		else:
			break
	return _path[mini(_path_i, _path.size() - 1)]


func _pick_roam(f) -> Vector3:
	var nm: RID = f.get_world_3d().navigation_map
	var p := Vector3.ZERO
	if is_instance_valid(target) and randf() < 0.6:
		p = target.global_position + Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
	else:
		if NavigationServer3D.map_get_iteration_id(nm) != 0:
			p = NavigationServer3D.map_get_random_point(nm, 1, true)
		if p == Vector3.ZERO:
			p = Vector3(randf_range(-15.0, 15.0), 0.0, randf_range(-15.0, 15.0))
	return _snap(nm, p)


func _snap(nm: RID, p: Vector3) -> Vector3:
	if NavigationServer3D.map_get_iteration_id(nm) == 0:
		return p
	var s := NavigationServer3D.map_get_closest_point(nm, p)
	return s if s != Vector3.ZERO else p


func _pick_retreat(f, pos: Vector3) -> Vector3:
	var threat := _last_seen
	if is_instance_valid(target):
		threat = target.global_position
	var away := _flat(pos - threat)
	if away.length() < 0.1:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	var p := pos + away.normalized() * 12.0
	var nm: RID = f.get_world_3d().navigation_map
	return _snap(nm, p)


## Position of the nearest enemy that fired recently within hearing range, or null.
func _listen(f) -> Variant:
	var now := Time.get_ticks_msec()
	var best: Variant = null
	var best_d := HEAR_RANGE
	for o in f.get_tree().get_nodes_in_group("fighters"):
		if o == f or not o.alive or not Game.are_enemies(f.team, o.team):
			continue
		var t: int = o.last_shot_ms
		if t <= 0 or now - t > HEAR_WINDOW_MS:
			continue
		var d: float = f.global_position.distance_to(o.global_position)
		if d < best_d:
			best_d = d
			best = o.global_position
	return best


func _pull(f, want: bool, auto: bool) -> bool:
	if not want:
		return false
	if f.prev_fire and not auto:
		return false
	return true


func _ammo(f, id: String) -> int:
	return int(f.mag.get(id, 0)) + int(f.reserve.get(id, 0))


## Nearest visible enemy, else nearest enemy.
func _pick_target(f):
	var best = null
	var best_d := INF
	var best_vis = null
	var best_vis_d := INF
	var from: Vector3 = f.head.global_position
	for o in f.get_tree().get_nodes_in_group("fighters"):
		if o == f or not o.alive or not Game.are_enemies(f.team, o.team):
			continue
		var dist: float = f.global_position.distance_squared_to(o.global_position)
		if dist < best_d:
			best_d = dist
			best = o
		if dist < best_vis_d and _can_see(f, from, o):
			best_vis_d = dist
			best_vis = o
	return best_vis if best_vis != null else best
