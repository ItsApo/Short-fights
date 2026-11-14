extends Control
## Main menu, built entirely in code. See CLAUDE.md.

var _mode: OptionButton
var _bots: SpinBox
var _bots_label: Label
var _map: OptionButton
var _diff: OptionButton
var _weapon: OptionButton
var _status: Label
var _solo_btn: Button
var _host_btn: Button
var _join_btn: Button
var _ip_edit: LineEdit
var _start_btn: Button
var _cancel_btn: Button
var _hosting := false
var _joined := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var th := Theme.new()
	th.default_font_size = 28
	theme = th

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.11, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "Short Fights"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)

	if Game.last_message != "":
		var msg := Label.new()
		msg.text = Game.last_message
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		msg.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
		box.add_child(msg)
		Game.last_message = ""

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	grid.add_child(_label("Modo"))
	_mode = OptionButton.new()
	_mode.add_item("Equipos", Game.Mode.TEAMS)
	_mode.add_item("Todos contra todos", Game.Mode.FFA)
	_mode.select(Game.config.mode)
	_fit(_mode)
	grid.add_child(_mode)

	_bots_label = _label("Bots por equipo")
	grid.add_child(_bots_label)
	_bots = SpinBox.new()
	_bots.min_value = 0
	_bots.max_value = 6
	_bots.step = 1
	_bots.value = Game.config.bots
	_bots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bots.custom_minimum_size = Vector2(0, 60)
	grid.add_child(_bots)

	grid.add_child(_label("Mapa"))
	_map = OptionButton.new()
	for i in Maps.NAMES.size():
		_map.add_item(Maps.NAMES[i], i)
	_map.select(clampi(Game.config.map, 0, Maps.NAMES.size() - 1))
	_fit(_map)
	grid.add_child(_map)

	grid.add_child(_label("Dificultad bots"))
	_diff = OptionButton.new()
	for i in Game.DIFFICULTIES.size():
		_diff.add_item(Game.DIFFICULTIES[i], i)
	_diff.select(Game.config.difficulty)
	_fit(_diff)
	grid.add_child(_diff)

	grid.add_child(_label("Arma primaria"))
	_weapon = OptionButton.new()
	for i in Weapons.PRIMARIES.size():
		_weapon.add_item(Weapons.DATA[Weapons.PRIMARIES[i]].name, i)
	_fit(_weapon)
	grid.add_child(_weapon)

	_solo_btn = _button("Jugar solo")
	box.add_child(_solo_btn)
	_host_btn = _button("Crear partida")
	box.add_child(_host_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	box.add_child(join_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "IP del host"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.custom_minimum_size = Vector2(0, 64)
	join_row.add_child(_ip_edit)
	_join_btn = _button("Unirse")
	_join_btn.size_flags_horizontal = Control.SIZE_FILL
	join_row.add_child(_join_btn)

	_start_btn = _button("Empezar")
	_start_btn.visible = false
	box.add_child(_start_btn)
	_cancel_btn = _button("Cancelar")
	_cancel_btn.visible = false
	box.add_child(_cancel_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	_mode.item_selected.connect(_on_mode_selected)
	_bots.value_changed.connect(func(_v: float) -> void: _apply_config())
	_map.item_selected.connect(func(_i: int) -> void: _apply_config())
	_diff.item_selected.connect(func(_i: int) -> void: _apply_config())
	_weapon.item_selected.connect(_on_weapon_selected)
	_solo_btn.pressed.connect(_on_solo)
	_host_btn.pressed.connect(_on_host)
	_join_btn.pressed.connect(_on_join)
	_start_btn.pressed.connect(_on_start)
	_cancel_btn.pressed.connect(func() -> void: Game.leave())

	Game.peers_changed.connect(_update_status)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)

	_on_mode_selected(_mode.selected)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _fit(o: OptionButton) -> void:
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size = Vector2(0, 60)


func _button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 68)
	return b


func _primary() -> String:
	return Weapons.PRIMARIES[_weapon.selected]


func _on_mode_selected(_i: int) -> void:
	var ffa := _mode.selected == Game.Mode.FFA
	_bots_label.text = "Bots totales" if ffa else "Bots por equipo"
	_apply_config()


func _apply_config() -> void:
	Game.config.mode = _mode.selected
	Game.config.kill_limit = 10 if _mode.selected == Game.Mode.FFA else 15
	Game.config.bots = int(_bots.value)
	Game.config.map = _map.selected
	Game.config.difficulty = _diff.selected


func _on_weapon_selected(_i: int) -> void:
	if _joined and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		Game._set_loadout.rpc_id(1, _primary())


func _on_solo() -> void:
	_apply_config()
	Game.loadouts[1] = _primary()
	Game.start_match()


func _set_busy(on: bool) -> void:
	_solo_btn.disabled = on
	_host_btn.disabled = on
	_join_btn.disabled = on
	_ip_edit.editable = not on
	_cancel_btn.visible = on


func _on_host() -> void:
	_apply_config()
	var err := Game.host()
	if err != OK:
		_status.text = "No se pudo crear la partida (%s)" % error_string(err)
		return
	Game.loadouts[1] = _primary()
	_hosting = true
	_set_busy(true)
	_start_btn.visible = true
	_update_status()


func _on_start() -> void:
	_apply_config()
	Game.loadouts[1] = _primary()
	Game.start_match()


func _on_join() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip == "":
		_status.text = "Escribe la IP del host"
		return
	var err := Game.join(ip)
	if err != OK:
		_status.text = "No se pudo unir (%s)" % error_string(err)
		return
	_status.text = "Conectando…"
	_set_busy(true)


func _on_connected() -> void:
	_joined = true
	Game._set_loadout.rpc_id(1, _primary())
	_mode.disabled = true
	_bots.editable = false
	_map.disabled = true
	_diff.disabled = true
	_status.text = "Conectado. Esperando al host…"


func _on_connection_failed() -> void:
	Game.last_message = "No se pudo conectar"
	Game.leave()


func _update_status() -> void:
	if not _hosting:
		return
	_status.text = "Esperando jugador…  Jugadores: %d/%d\nTu IP: %s" % [Game.humans().size(), Game.MAX_HUMANS, "\n".join(_lan_ips())]


## Usable LAN IPv4s as "Adapter: ip". Drops loopback, link-local 169.254.* (adapter without network) and
## virtual adapters (VMs, WSL, Docker) so only the real Wi-Fi/Ethernet address is shown.
func _lan_ips() -> Array[String]:
	var virtual := RegEx.create_from_string("(?i)virtualbox|vmware|vethernet|hyper-v|wsl|docker|loopback|bluetooth|npcap")
	var real: Array[String] = []
	var other: Array[String] = []
	for iface in IP.get_local_interfaces():
		var label: String = iface.get("friendly", iface.get("name", ""))
		for a: String in iface.get("addresses", []):
			if ":" in a or a.begins_with("127.") or a.begins_with("169.254."):
				continue
			# shortcut: 192.168.56.* is VirtualBox's default host-only net (Windows names it "Ethernet 2"); a real LAN on that subnet would be hidden
			if virtual.search(label) or a.begins_with("192.168.56."):
				other.append(a)
			elif label.to_lower().contains("wi-fi") or label.to_lower().contains("wlan"):
				real.push_front("%s: %s" % [label, a])
			else:
				real.append("%s: %s" % [label, a] if label != "" else a)
	return real if not real.is_empty() else other
