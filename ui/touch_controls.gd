class_name TouchControls
extends Control

const JOY_RADIUS := 90.0
const JOY_DEADZONE := 0.15
const LOOK_SCALE := 0.005
const EXIT_POS := Vector2(56, 56)
const EXIT_RADIUS := 34.0
# name, action, label, offset from bottom-right corner (x left, y up), radius
const BUTTONS := [
	{"id": "fire", "action": "fire", "label": "FUEGO", "off": Vector2(130, 150), "r": 70.0},
	{"id": "jump", "action": "jump", "label": "SALTO", "off": Vector2(290, 90), "r": 55.0},
	{"id": "reload", "action": "reload", "label": "RECARGAR", "off": Vector2(270, 230), "r": 55.0},
	{"id": "next", "action": "next_weapon", "label": "ARMA", "off": Vector2(120, 300), "r": 55.0},
]

# toggle button (APUNTAR): offset from bottom-right corner like BUTTONS
const AIM_OFF := Vector2(400, 160)
const AIM_R := 45.0
const SPRINT_STRENGTH := 0.95

var _aim_on := false
var _sprint_on := false
var _prev_emulate := true
var _fingers := {}      # finger index -> {"role": String, ...}
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _joy_active := false
var _pressed := {}      # button id -> true


func _ready() -> void:
	# already in the tree here: plain set_anchors_preset() would leave size at 0 and draw buttons off-screen
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prev_emulate = Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = false
	resized.connect(queue_redraw)
	queue_redraw()


func _exit_tree() -> void:
	Input.emulate_mouse_from_touch = _prev_emulate
	_release_all()


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)
	for b: Dictionary in BUTTONS:
		Input.action_release(b.action)
	Input.action_release("aim")
	Input.action_release("sprint")
	_aim_on = false
	_sprint_on = false


func _button_center(b: Dictionary) -> Vector2:
	return Vector2(size.x - b.off.x, size.y - b.off.y)


func _aim_center() -> Vector2:
	# keep it in the right half on narrow screens
	var x := maxf(size.x - AIM_OFF.x, size.x * 0.5 + AIM_R * 1.15 + 4.0)
	return Vector2(x, size.y - AIM_OFF.y)


func _toggle_aim() -> void:
	_aim_on = not _aim_on
	if _aim_on:
		Input.action_press("aim")
	else:
		Input.action_release("aim")


func _button_at(p: Vector2) -> int:
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		if p.distance_to(_button_center(b)) <= float(b.r) * 1.15:
			return i
	return -1


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position - global_position
		if event.pressed:
			_on_down(event.index, p)
		else:
			_on_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var p: Vector2 = event.position - global_position
		_on_drag(event.index, p, event.relative)
		get_viewport().set_input_as_handled()


func _on_down(idx: int, p: Vector2) -> void:
	if _fingers.has(idx):
		_on_up(idx)
	if p.distance_to(EXIT_POS) <= EXIT_RADIUS * 1.2:
		_fingers[idx] = {"role": "exit"}
		Game.leave()
		return
	if p.x < size.x * 0.5:
		if _joy_active:
			return
		_fingers[idx] = {"role": "joy"}
		_joy_active = true
		_joy_origin = p
		_joy_pos = p
		_apply_joy()
	else:
		var bi := _button_at(p)
		if p.distance_to(_aim_center()) <= AIM_R * 1.15:
			_fingers[idx] = {"role": "aim"}
			_toggle_aim()
		elif bi >= 0:
			var b: Dictionary = BUTTONS[bi]
			_fingers[idx] = {"role": "button", "id": b.id, "action": b.action}
			_pressed[b.id] = true
			Input.action_press(b.action)
		else:
			_fingers[idx] = {"role": "look"}
	queue_redraw()


func _on_up(idx: int) -> void:
	if not _fingers.has(idx):
		return
	var f: Dictionary = _fingers[idx]
	_fingers.erase(idx)
	match f.role:
		"joy":
			_joy_active = false
			_apply_joy()
		"button":
			_pressed.erase(f.id)
			Input.action_release(f.action)
	queue_redraw()


func _on_drag(idx: int, p: Vector2, rel: Vector2) -> void:
	if not _fingers.has(idx):
		return
	match _fingers[idx].role:
		"joy":
			_joy_pos = p
			_apply_joy()
			queue_redraw()
		"look":
			Game.touch_look += rel * LOOK_SCALE


func _joy_vector() -> Vector2:
	if not _joy_active:
		return Vector2.ZERO
	var d := _joy_pos - _joy_origin
	var v := d / JOY_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < JOY_DEADZONE:
		return Vector2.ZERO
	return v


func _apply_joy() -> void:
	var v := _joy_vector()   # x right+, y down+ (screen)
	_set_action("move_right", maxf(v.x, 0.0))
	_set_action("move_left", maxf(-v.x, 0.0))
	_set_action("move_back", maxf(v.y, 0.0))
	_set_action("move_forward", maxf(-v.y, 0.0))
	var want_sprint := v.length() > SPRINT_STRENGTH
	if want_sprint != _sprint_on:
		_sprint_on = want_sprint
		if want_sprint:
			Input.action_press("sprint")
		else:
			Input.action_release("sprint")


func _set_action(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# exit button
	draw_circle(EXIT_POS, EXIT_RADIUS, Color(0, 0, 0, 0.35))
	draw_arc(EXIT_POS, EXIT_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
	draw_string(font, EXIT_POS + Vector2(-8, 9), "X", HORIZONTAL_ALIGNMENT_CENTER, 16, 26, Color(1, 1, 1, 0.8))
	# buttons
	for b: Dictionary in BUTTONS:
		var c := _button_center(b)
		var on: bool = _pressed.has(b.id)
		var r: float = b.r
		draw_circle(c, r, Color(1, 1, 1, 0.35) if on else Color(0, 0, 0, 0.3))
		draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.55), 2.5)
		var fs := 18 if r > 60.0 else 14
		draw_string(font, c + Vector2(-r, fs * 0.35), b.label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 1, 1, 0.85))
	# aim toggle
	var ac := _aim_center()
	draw_circle(ac, AIM_R, Color(1, 1, 1, 0.4) if _aim_on else Color(0, 0, 0, 0.3))
	draw_arc(ac, AIM_R, 0, TAU, 40, Color(1, 0.9, 0.3, 0.9) if _aim_on else Color(1, 1, 1, 0.55), 3.5 if _aim_on else 2.5)
	draw_string(font, ac + Vector2(-AIM_R, 5), "APUNTAR", HORIZONTAL_ALIGNMENT_CENTER, AIM_R * 2.0, 14, Color(1, 1, 1, 0.9))
	# joystick
	if _joy_active:
		draw_circle(_joy_origin, JOY_RADIUS, Color(0, 0, 0, 0.25))
		draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 2.5)
		var d := _joy_pos - _joy_origin
		if d.length() > JOY_RADIUS:
			d = d.normalized() * JOY_RADIUS
		draw_circle(_joy_origin + d, 36.0, Color(1, 1, 1, 0.45))
