class_name Hud
extends CanvasLayer

const FONT_SIZE := 26
const CROSS_NORMAL := Color(1, 1, 1, 0.9)
const CROSS_HIT := Color(1, 0.15, 0.1, 1.0)
const CROSS_HEAD := Color(1, 0.9, 0.1, 1.0)

var _health: Label
var _weapon: Label
var _score: Label
var _message: Label
var _msg_timer: Timer
var _cross_rects: Array[ColorRect] = []
var _hit_serial := 0
var _cross: Control
var _dot: ColorRect
var _aiming := false
var _feed_box: VBoxContainer
var _bonus: Label
var _bonus_tween: Tween
var _dmg: Control
var _dmg_hits: Array = []   # {"a": float angle, "t": float age}
var _vignette: TextureRect
var _health_val := 100
var _pulse_t := 0.0


func _enter_tree() -> void:
	add_to_group("hud")


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_vignette(root)
	_build_damage(root)
	_build_crosshair(root)

	_health = _make_label(root, HORIZONTAL_ALIGNMENT_LEFT)
	_health.anchor_left = 0.0
	_health.anchor_right = 0.5
	_health.anchor_top = 1.0
	_health.anchor_bottom = 1.0
	_health.offset_left = 20
	_health.offset_right = 0
	_health.offset_top = -64
	_health.offset_bottom = -16
	_health.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_health.text = "Vida: %d" % Game.MAX_HEALTH

	_weapon = _make_label(root, HORIZONTAL_ALIGNMENT_RIGHT)
	_weapon.anchor_left = 0.5
	_weapon.anchor_right = 1.0
	_weapon.anchor_top = 1.0
	_weapon.anchor_bottom = 1.0
	_weapon.offset_left = 0
	_weapon.offset_right = -20
	_weapon.offset_top = -64
	_weapon.offset_bottom = -16
	_weapon.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	_score = _make_label(root, HORIZONTAL_ALIGNMENT_CENTER)
	_score.anchor_left = 0.0
	_score.anchor_right = 1.0
	_score.anchor_top = 0.0
	_score.anchor_bottom = 0.0
	_score.offset_left = 80
	_score.offset_right = -80
	_score.offset_top = 10
	_score.offset_bottom = 60

	_message = _make_label(root, HORIZONTAL_ALIGNMENT_CENTER)
	_message.anchor_left = 0.0
	_message.anchor_right = 1.0
	_message.anchor_top = 0.5
	_message.anchor_bottom = 0.5
	_message.offset_left = 40
	_message.offset_right = -40
	_message.offset_top = -150
	_message.offset_bottom = -60
	_message.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.visible = false

	_bonus = _make_label(root, HORIZONTAL_ALIGNMENT_CENTER)
	_bonus.anchor_left = 0.5
	_bonus.anchor_right = 0.5
	_bonus.anchor_top = 0.5
	_bonus.anchor_bottom = 0.5
	_bonus.offset_left = -200
	_bonus.offset_right = 200
	_bonus.offset_top = 36
	_bonus.offset_bottom = 72
	_bonus.pivot_offset = Vector2(200, 18)
	_bonus.add_theme_font_size_override("font_size", 22)
	_bonus.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
	_bonus.visible = false

	_feed_box = VBoxContainer.new()
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_box.anchor_left = 1.0
	_feed_box.anchor_right = 1.0
	_feed_box.anchor_top = 0.0
	_feed_box.anchor_bottom = 0.0
	_feed_box.offset_left = -440
	_feed_box.offset_right = -14
	_feed_box.offset_top = 70
	_feed_box.offset_bottom = 70
	_feed_box.add_theme_constant_override("separation", 2)
	root.add_child(_feed_box)

	_msg_timer = Timer.new()
	_msg_timer.one_shot = true
	_msg_timer.timeout.connect(_on_msg_timeout)
	add_child(_msg_timer)


func _make_label(parent: Control, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l


func _build_crosshair(parent: Control) -> void:
	var c := Control.new()
	_cross = c
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = 0
	c.offset_bottom = 0
	parent.add_child(c)
	# left, right, top, bottom ticks around a small gap
	var rects := [Rect2(-12, -1, 8, 2), Rect2(4, -1, 8, 2), Rect2(-1, -12, 2, 8), Rect2(-1, 4, 2, 8)]
	for r: Rect2 in rects:
		var cr := ColorRect.new()
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.position = r.position
		cr.size = r.size
		cr.color = CROSS_NORMAL
		c.add_child(cr)
		_cross_rects.append(cr)
	_dot = ColorRect.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.position = Vector2(-2, -2)
	_dot.size = Vector2(4, 4)
	_dot.color = CROSS_NORMAL
	_dot.visible = false
	c.add_child(_dot)


func _build_vignette(parent: Control) -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.8, 0, 0, 0), Color(0.8, 0, 0, 0), Color(0.8, 0, 0, 0.85)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	_vignette = TextureRect.new()
	_vignette.texture = gt
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.modulate.a = 0.0
	_vignette.visible = false
	parent.add_child(_vignette)


func _build_damage(parent: Control) -> void:
	_dmg = Control.new()
	_dmg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dmg.draw.connect(_draw_damage)
	parent.add_child(_dmg)


func _draw_damage() -> void:
	var center := _dmg.size * 0.5
	var radius := minf(_dmg.size.x, _dmg.size.y) * 0.4
	for h: Dictionary in _dmg_hits:
		var alpha := clampf(1.0 - float(h.t), 0.0, 1.0)
		var theta: float = float(h.a) - PI * 0.5   # 0 = top, + = right (screen y is down)
		_dmg.draw_arc(center, radius, theta - 0.45, theta + 0.45, 24, Color(0.9, 0.05, 0.05, 0.35 * alpha), 44.0)
		_dmg.draw_arc(center, radius + 6.0, theta - 0.32, theta + 0.32, 20, Color(1.0, 0.1, 0.1, 0.65 * alpha), 24.0)


func _set_cross_color(col: Color) -> void:
	for cr in _cross_rects:
		cr.color = col
	if _dot:
		_dot.color = col


func set_health(v: int) -> void:
	_health_val = v
	if _health:
		_health.text = "Vida: %d" % v
	_update_vignette()


func _update_vignette() -> void:
	if not _vignette:
		return
	if _health_val < 35:
		var base := clampf((35.0 - float(_health_val)) / 35.0, 0.0, 1.0)
		var a := 0.3 + 0.5 * base
		a *= 0.85 + 0.15 * sin(_pulse_t * 6.0)
		_vignette.modulate.a = clampf(a, 0.0, 1.0)
		_vignette.visible = true
	else:
		_vignette.visible = false


func _process(delta: float) -> void:
	_pulse_t += delta
	if _health_val < 35:
		_update_vignette()
	if not _dmg_hits.is_empty():
		for h: Dictionary in _dmg_hits:
			h.t = float(h.t) + delta
		_dmg_hits = _dmg_hits.filter(func(h: Dictionary) -> bool: return float(h.t) < 1.0)
		_dmg.queue_redraw()


func set_weapon(weapon_name: String, ammo_text: String) -> void:
	if _weapon:
		_weapon.text = "%s  %s" % [weapon_name, ammo_text] if ammo_text != "" else weapon_name


func set_score(text: String) -> void:
	if _score:
		_score.text = text


func show_message(text: String, seconds: float) -> void:
	if not _message:
		return
	_message.text = text
	_message.visible = true
	_msg_timer.stop()
	if seconds > 0.0:
		_msg_timer.start(seconds)


func _on_msg_timeout() -> void:
	_message.visible = false


func kill_feed(text: String) -> void:
	if not _feed_box:
		return
	while _feed_box.get_child_count() >= 5:
		var old := _feed_box.get_child(0)
		_feed_box.remove_child(old)
		old.queue_free()
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	_feed_box.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_remove_feed_label.bind(l))


func _remove_feed_label(l: Label) -> void:
	if is_instance_valid(l):
		if l.get_parent():
			l.get_parent().remove_child(l)
		l.queue_free()


func show_bonus(text: String) -> void:
	if not _bonus:
		return
	if _bonus_tween and _bonus_tween.is_valid():
		_bonus_tween.kill()
	_bonus.text = text
	_bonus.visible = true
	_bonus.modulate.a = 1.0
	_bonus.scale = Vector2(1.3, 1.3)
	_bonus_tween = _bonus.create_tween()
	_bonus_tween.tween_property(_bonus, "scale", Vector2.ONE, 0.15)
	_bonus_tween.tween_interval(0.85)
	_bonus_tween.tween_property(_bonus, "modulate:a", 0.0, 0.2)
	_bonus_tween.tween_callback(_hide_bonus)


func _hide_bonus() -> void:
	_bonus.visible = false


func damage_from(angle: float) -> void:
	if not _dmg:
		return
	_dmg_hits.append({"a": angle, "t": 0.0})
	if _dmg_hits.size() > 8:
		_dmg_hits.pop_front()
	_dmg.queue_redraw()


func set_aim(aiming: bool) -> void:
	_aiming = aiming
	for cr in _cross_rects:
		cr.visible = not aiming
	if _dot:
		_dot.visible = aiming


func flash_hit(headshot := false) -> void:
	_hit_serial += 1
	var serial := _hit_serial
	_set_cross_color(CROSS_HEAD if headshot else CROSS_HIT)
	if _cross:
		_cross.scale = Vector2(1.7, 1.7) if headshot else Vector2.ONE
	await get_tree().create_timer(0.2 if headshot else 0.1).timeout
	if serial == _hit_serial:
		_set_cross_color(CROSS_NORMAL)
		if _cross:
			_cross.scale = Vector2.ONE
