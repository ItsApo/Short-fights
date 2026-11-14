extends Node
## Game autoload: config, LAN (ENet), input map, shared helpers. See CLAUDE.md.

const PORT := 7777
const MAX_HUMANS := 2
const MAX_HEALTH := 100
const RESPAWN_TIME := 3.0
const MOUSE_SENS := 0.0025
const TEAM_COLORS := [Color(0.2, 0.45, 1), Color(1, 0.3, 0.25), Color(0.3, 0.9, 0.3), Color(1, 0.85, 0.2), Color(0.8, 0.4, 1), Color(0.2, 0.9, 0.9), Color(1, 0.6, 0.2), Color(0.9, 0.9, 0.9)]

enum Mode { TEAMS, FFA }

const DIFFICULTIES := ["Fácil", "Normal", "Difícil"]
var config := {"mode": Mode.TEAMS, "bots": 2, "map": 0, "kill_limit": 15, "difficulty": 1}
var loadouts := {}
var touch_look := Vector2.ZERO
var ready_peers := {}
var last_message := ""
var in_match := false

signal peers_changed
signal peer_ready(id: int)


func _ready() -> void:
	_register_inputs()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Test hooks for tools/check.sh: `-- --map=N --ffa --bots=N`.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="): config.map = int(a.get_slice("=", 1))
		elif a.begins_with("--bots="): config.bots = int(a.get_slice("=", 1))
		elif a.begins_with("--difficulty="): config.difficulty = clampi(int(a.get_slice("=", 1)), 0, 2)
		elif a == "--ffa": config.mode = Mode.FFA; config.kill_limit = 10
		elif a == "--host":
			host()
			peers_changed.connect(func() -> void: if humans().size() == MAX_HUMANS and not in_match: start_match())
		elif a.begins_with("--join="): join(a.get_slice("=", 1))


func team_color(team: int) -> Color:
	return TEAM_COLORS[team % TEAM_COLORS.size()]


func are_enemies(a: int, b: int) -> bool:
	return a != b


func humans() -> Array:
	var r: Array = [1]
	r.append_array(multiplayer.get_peers())
	return r


# ---------------------------------------------------------------- networking

func host() -> Error:
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	# ENet itself refuses a 3rd human: kicking after connect leaves a half-open peer that errors on every broadcast
	var err := peer.create_server(PORT, MAX_HUMANS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.refuse_new_connections = false
	loadouts.clear()
	ready_peers.clear()
	in_match = false
	peers_changed.emit()
	return OK


func join(ip: String) -> Error:
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	loadouts.clear()
	ready_peers.clear()
	in_match = false
	return OK


func leave() -> void:
	_close_peer()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	in_match = false
	loadouts.clear()
	ready_peers.clear()
	touch_look = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _close_peer() -> void:
	var p := multiplayer.multiplayer_peer
	if p != null and not (p is OfflineMultiplayerPeer):
		p.close()


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# peer list already includes the new peer: refuse a 3rd human or a mid-match join
	if in_match or multiplayer.get_peers().size() >= MAX_HUMANS:
		multiplayer.multiplayer_peer.disconnect_peer(id)  # fallback; normally refused earlier
		return
	peers_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	loadouts.erase(id)
	ready_peers.erase(id)
	peers_changed.emit()


func _on_server_disconnected() -> void:
	last_message = "El host se desconectó"
	leave()


# ---------------------------------------------------------------- match start

func start_match() -> void:
	if not multiplayer.is_server():
		return
	_load_match.rpc(config, loadouts)


@rpc("authority", "call_local", "reliable")
func _load_match(cfg: Dictionary, lo: Dictionary) -> void:
	config = cfg
	loadouts = lo
	ready_peers.clear()
	in_match = true
	multiplayer.refuse_new_connections = true  # no mid-match joins; reset in host()
	get_tree().change_scene_to_file("res://match/match.tscn")


@rpc("any_peer", "call_local", "reliable")
func _peer_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	ready_peers[id] = true
	peer_ready.emit(id)


@rpc("any_peer", "reliable")
func _set_loadout(primary: String) -> void:
	if not multiplayer.is_server():
		return
	if primary not in Weapons.PRIMARIES:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	loadouts[id] = primary


# ---------------------------------------------------------------- input map

func _register_inputs() -> void:
	var defs := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"reload": [KEY_R],
		"slot_1": [KEY_1],
		"slot_2": [KEY_2],
		"slot_3": [KEY_3],
		"slot_4": [KEY_4],
		"next_weapon": [KEY_Q],
		"fire": [],
		"aim": [],
		"sprint": [KEY_SHIFT],
	}
	for action in defs:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code in defs[action]:
			var k := InputEventKey.new()
			k.physical_keycode = code
			InputMap.action_add_event(action, k)
		if action == "fire":
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			InputMap.action_add_event(action, mb)
		elif action == "aim":
			var rmb := InputEventMouseButton.new()
			rmb.button_index = MOUSE_BUTTON_RIGHT
			InputMap.action_add_event(action, rmb)
		elif action == "next_weapon":
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			InputMap.action_add_event(action, wheel)
