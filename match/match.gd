extends Node3D
## Match root (contract in CLAUDE.md). Host-authoritative rules; every peer builds the same scene.

const TEAM_NAMES := ["Azul", "Rojo"]

@onready var _fighters: Node3D = $Fighters
@onready var _projectiles: Node3D = $Projectiles

var _hud = null  # Hud (untyped on purpose)
var _touch := false
var _spawns_a: Array = []
var _spawns_b: Array = []

# Host-only state
var _spawned := false
var _over := false
var _team_kills := [0, 0]
var _kills := {}  # fighter name -> kills (FFA)
var _names := {}  # fighter name -> display name (kept after the fighter is freed)


func _enter_tree() -> void:
	add_to_group("match")


func _ready() -> void:
	var maps: Dictionary = Maps.build(self, int(Game.config.map))
	if multiplayer.is_server():
		Nav.bake(self)  # bots only run on the host
	_spawns_a = maps["spawns_a"]
	_spawns_b = maps["spawns_b"]
	_hud = Hud.new()
	add_child(_hud)
	_touch = DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()
	if _touch:
		_hud.add_child(TouchControls.new())
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Game.peer_ready.connect(_on_peer_ready)
	Game._peer_ready.rpc_id(1)
	_try_spawn()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not _touch and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Game.leave()


# ---------------------------------------------------------------- spawning (host)

func _on_peer_ready(_id: int) -> void:
	_try_spawn()


func _try_spawn() -> void:
	if _spawned or not multiplayer.is_server():
		return
	var humans: Array = Game.humans()
	for id in humans:
		if not Game.ready_peers.has(id):
			return
	_spawned = true
	var teams_mode: bool = Game.config.mode == Game.Mode.TEAMS
	var bots: int = int(Game.config.bots)
	var entries: Array = []  # {name, display, team, peer, bot}
	var team_i := 0
	for i in humans.size():
		var id: int = humans[i]
		entries.append({"name": "H%d" % id, "display": "Jugador %d" % (i + 1),
				"team": (i % 2) if teams_mode else team_i, "peer": id, "bot": false})
		team_i += 1
	var bot_i := 0
	if teams_mode:
		for t in 2:
			for _k in bots:
				entries.append({"name": "B%d" % bot_i, "display": "Bot %d" % (bot_i + 1),
						"team": t, "peer": 1, "bot": true})
				bot_i += 1
	else:
		for _k in bots:
			entries.append({"name": "B%d" % bot_i, "display": "Bot %d" % (bot_i + 1),
					"team": team_i, "peer": 1, "bot": true})
			team_i += 1
			bot_i += 1
	var taken: Array = []
	for e in entries:
		var pool := _pool(e.team)
		var free: Array = pool.filter(func(p): return not taken.has(p))
		var pos: Vector3 = (free if not free.is_empty() else pool).pick_random()
		taken.append(pos)
		_names[e.name] = e.display
		_kills[e.name] = 0
		var primary: String = "rifle"
		if e.bot:
			primary = Weapons.PRIMARIES.pick_random()
		else:
			primary = str(Game.loadouts.get(e.peer, "rifle"))
		_spawn.rpc(e.name, e.display, e.team, e.peer, e.bot, primary, pos)
	print("[match] spawned %d fighters" % entries.size())
	_set_score.rpc(_score_text())


func _pool(team: int) -> Array:
	if Game.config.mode == Game.Mode.TEAMS:
		return _spawns_a if team == 0 else _spawns_b
	return _spawns_a + _spawns_b


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var f := _fighter("H%d" % id)
	if f:
		f.queue_free()


func _fighter(fname: String) -> Fighter:
	return _fighters.get_node_or_null(fname) as Fighter


# ---------------------------------------------------------------- rpcs: host -> all

@rpc("authority", "call_local", "reliable")
func _spawn(fname: String, display: String, team: int, peer_id: int, is_bot: bool, primary: String, pos: Vector3) -> void:
	var f := Fighter.new()
	f.name = fname
	f.display_name = display
	f.team = team
	f.peer_id = peer_id
	f.is_bot = is_bot
	f.primary = primary
	f.set_multiplayer_authority(1 if is_bot else peer_id)
	_fighters.add_child(f)
	f.respawn(pos)


@rpc("authority", "call_local", "reliable")
func _set_state(fname: String, health: int, alive: bool) -> void:
	var f := _fighter(fname)
	if f == null:
		return
	f.health = health
	f.set_alive(alive)


@rpc("authority", "call_local", "reliable")
func _respawn(fname: String, pos: Vector3) -> void:
	var f := _fighter(fname)
	if f:
		f.respawn(pos)


@rpc("authority", "call_local", "reliable")
func _set_score(text: String) -> void:
	if _hud:
		_hud.set_score(text)


@rpc("authority", "call_local", "reliable")
func _feed(text: String) -> void:
	if _hud:
		_hud.show_message(text, 2.0)
	print("[match] ", text)


@rpc("authority", "call_local", "reliable")
func _end(text: String) -> void:
	if _hud:
		_hud.show_message(text, 0)
	print("[match] ", text)
	get_tree().create_timer(5.0).timeout.connect(Game.leave)


# ---------------------------------------------------------------- rpcs: any peer -> host

@rpc("any_peer", "call_local", "reliable")
func request_damage(target: String, amount: int, attacker: String, headshot: bool = false) -> void:
	if not multiplayer.is_server() or _over:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var a := _fighter(attacker)
	var t := _fighter(target)
	if a == null or t == null:
		return
	if a.get_multiplayer_authority() != sender:
		return
	amount = mini(amount, Weapons.max_shot_damage())
	if amount <= 0 or not a.alive:
		return
	if not Game.are_enemies(a.team, t.team):
		return
	_damage(t, a, amount, a.global_position, headshot)


@rpc("any_peer", "call_local", "reliable")
func request_heal(target: String, amount: int) -> void:
	if not multiplayer.is_server() or _over:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var t := _fighter(target)
	if t == null or t.get_multiplayer_authority() != sender or not t.alive:
		return
	amount = mini(amount, int(Weapons.DATA.medkit.heal))
	if amount <= 0:
		return
	_set_state.rpc(target, mini(Game.MAX_HEALTH, t.health + amount), true)


@rpc("any_peer", "call_local", "reliable")
func spawn_grenade(pos: Vector3, vel: Vector3, thrower: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var f := _fighter(thrower)
	if f == null or f.get_multiplayer_authority() != sender:
		return
	var g := Grenade.new()
	_projectiles.add_child(g)
	g.setup(pos, vel, thrower)


# ---------------------------------------------------------------- host rules

## Called by Grenade on the host when its fuse ends.
func apply_explosion(pos: Vector3, thrower: String) -> void:
	if not multiplayer.is_server() or _over:
		return
	var a := _fighter(thrower)
	if a == null:
		return
	var radius: float = Weapons.DATA.grenade.radius
	var dmg: float = Weapons.DATA.grenade.damage
	for f in _fighters.get_children():
		var t := f as Fighter
		if t == null or not t.alive or not Game.are_enemies(a.team, t.team):
			continue
		var d := pos.distance_to(t.global_position + Vector3.UP * 0.9)
		if d >= radius:
			continue
		var amt := int(round(dmg * (1.0 - d / radius)))
		if amt > 0:
			_damage(t, a, amt, pos)


func _damage(t: Fighter, a: Fighter, amount: int, from: Vector3, headshot := false) -> void:
	if _over or not t.alive:
		return
	_hurt.rpc(t.name, from, headshot)
	var hp := maxi(0, t.health - amount)
	if hp > 0:
		_set_state.rpc(t.name, hp, true)
		return
	_set_state.rpc(t.name, 0, false)
	_kill.rpc(a.name, t.name, headshot)
	var limit := int(Game.config.kill_limit)
	var winner := ""
	if Game.config.mode == Game.Mode.TEAMS:
		_team_kills[a.team] += 1
		if _team_kills[a.team] >= limit:
			winner = "Equipo " + TEAM_NAMES[a.team]
	else:
		_kills[a.name] = int(_kills.get(a.name, 0)) + 1
		if _kills[a.name] >= limit:
			winner = a.display_name
	_set_score.rpc(_score_text())
	if winner != "":
		_over = true
		_end.rpc("Gana " + winner)
		return
	get_tree().create_timer(Game.RESPAWN_TIME).timeout.connect(_do_respawn.bind(String(t.name)))


func _do_respawn(fname: String) -> void:
	if _over:
		return
	var f := _fighter(fname)
	if f == null or f.alive:
		return
	_respawn.rpc(fname, _pool(f.team).pick_random())


func _score_text() -> String:
	if Game.config.mode == Game.Mode.TEAMS:
		return "Azul %d  -  %d Rojo" % [_team_kills[0], _team_kills[1]]
	var keys: Array = _kills.keys()
	keys.sort_custom(func(x, y): return _kills[x] > _kills[y])
	var parts: Array[String] = []
	for k in keys.slice(0, 3):
		parts.append("%s %d" % [_names.get(k, k), _kills[k]])
	return " · ".join(parts)


# ---------------------------------------------------------------- feedback rpcs (host -> all)

@rpc("authority", "call_local", "reliable")
func _hurt(fname: String, from: Vector3, headshot: bool) -> void:
	var f := _fighter(fname)
	if f:
		f.on_hurt(from, headshot)


@rpc("authority", "call_local", "reliable")
func _kill(killer: String, victim: String, headshot: bool) -> void:
	var k := _fighter(killer)
	var v := _fighter(victim)
	var text := "%s eliminó a %s%s" % [k.display_name if k else killer, v.display_name if v else victim, " (cabeza)" if headshot else ""]
	print("[match] ", text)
	if _hud == null:
		return
	_hud.kill_feed(text)
	if k and k.is_local():
		Sfx.play("kill")
		_hud.show_bonus("¡Disparo a la cabeza! +1" if headshot else "+1")
