extends Node
## Procedural sound bank (no files). See CLAUDE.md > Sfx.

const RATE := 22050
const MAX_3D := 24
const MAX_2D := 8
const GUNS := ["rifle", "shotgun", "pistol"]

var _bank: Dictionary = {}
var _pool3d: Array = []
var _pool2d: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build()


## id: see CLAUDE.md list. pos: Vector3 => 3D sound there; null => 2D (UI / local player).
func play(id: String, pos: Variant = null, volume_db := 0.0) -> void:
	if not _bank.has(id):
		return
	var pitch := 1.0
	if id in GUNS:
		pitch = _rng.randf_range(0.93, 1.07)
	elif id == "step":
		pitch = _rng.randf_range(0.8, 1.2)
	else:
		pitch = _rng.randf_range(0.97, 1.03)
	if pos is Vector3:
		var p: AudioStreamPlayer3D = _get3d()
		if p == null:
			return
		var parent: Node = get_tree().current_scene if get_tree() and get_tree().current_scene else self
		if p.get_parent() != parent:
			if p.get_parent():
				p.get_parent().remove_child(p)
			parent.add_child(p)
		p.global_position = pos
		p.stream = _bank[id]
		p.pitch_scale = pitch
		p.volume_db = volume_db
		p.play()
	else:
		var q: AudioStreamPlayer = _get2d()
		if q == null:
			return
		q.stream = _bank[id]
		q.pitch_scale = pitch
		q.volume_db = volume_db
		q.play()


func _get3d() -> AudioStreamPlayer3D:
	var alive: Array = []
	for p in _pool3d:
		if is_instance_valid(p):
			alive.append(p)
	_pool3d = alive
	for p in _pool3d:
		if not p.playing:
			return p
	if _pool3d.size() >= MAX_3D:
		return null
	var n := AudioStreamPlayer3D.new()
	n.unit_size = 6.0
	n.max_distance = 60.0
	n.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	n.name = "Sfx3D%d" % _pool3d.size()
	_pool3d.append(n)
	return n


func _get2d() -> AudioStreamPlayer:
	for p in _pool2d:
		if not p.playing:
			return p
	if _pool2d.size() >= MAX_2D:
		return null
	var n := AudioStreamPlayer.new()
	add_child(n)
	_pool2d.append(n)
	return n


# ---------------------------------------------------------------- synthesis

func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


## Filtered noise. lp: one-pole coefficient 0..1 (higher = brighter), lp_end: value at end.
func _noise(b: PackedFloat32Array, start: float, dur: float, decay: float, lp: float, gain: float, attack := 0.0, lp_end := -1.0) -> void:
	var s0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - s0)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var a := lp if lp_end < 0.0 else lerpf(lp, lp_end, float(i) / maxf(n, 1))
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		var e := exp(-t * decay)
		if attack > 0.0:
			e *= minf(1.0, t / attack)
		b[s0 + i] += y * e * gain


## Sine with exponential decay and optional frequency glide f0 -> f1.
func _tone(b: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, decay: float, gain: float, attack := 0.002) -> void:
	var s0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - s0)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, minf(1.0, t / dur))
		ph += TAU * f / RATE
		b[s0 + i] += sin(ph) * exp(-t * decay) * minf(1.0, t / attack) * gain


func _stream(b: PackedFloat32Array, peak := 0.9) -> AudioStreamWAV:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	var k := peak / m
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in b.size():
		var v := clampf(b[i] * k, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _add(id: String, b: PackedFloat32Array, peak := 0.9) -> void:
	_bank[id] = _stream(b, peak)


func _click(b: PackedFloat32Array, at: float, f: float) -> void:
	_noise(b, at, 0.03, 160.0, 0.9, 1.0)
	_tone(b, at, 0.05, f, f * 0.7, 90.0, 0.7, 0.0005)
	_tone(b, at, 0.04, f * 0.45, f * 0.4, 110.0, 0.5, 0.0005)


func _build() -> void:
	var b: PackedFloat32Array
	# Guns: crack + body noise + low thump.
	b = _buf(0.14)
	_noise(b, 0, 0.14, 38.0, 0.75, 1.0)
	_noise(b, 0, 0.02, 200.0, 1.0, 0.8)
	_tone(b, 0, 0.14, 150.0, 55.0, 30.0, 0.9)
	_add("rifle", b, 0.8)
	b = _buf(0.38)
	_noise(b, 0, 0.38, 11.0, 0.4, 1.0)
	_noise(b, 0, 0.03, 120.0, 0.9, 0.9)
	_tone(b, 0, 0.38, 95.0, 35.0, 12.0, 1.2)
	_add("shotgun", b, 1.0)
	b = _buf(0.16)
	_noise(b, 0, 0.16, 30.0, 0.55, 1.0)
	_noise(b, 0, 0.02, 180.0, 0.95, 0.6)
	_tone(b, 0, 0.16, 190.0, 80.0, 26.0, 0.9)
	_add("pistol", b, 0.75)
	# Explosion: low-passed rumble + sub.
	b = _buf(1.2)
	_noise(b, 0, 1.2, 3.2, 0.07, 2.2, 0.004, 0.025)
	_noise(b, 0, 0.12, 25.0, 0.5, 0.5)
	_tone(b, 0, 1.2, 60.0, 28.0, 3.0, 1.0, 0.005)
	_add("explosion", b, 1.0)
	# Movement.
	b = _buf(0.09)
	_tone(b, 0, 0.09, 220.0, 100.0, 55.0, 0.8, 0.0005)
	_noise(b, 0, 0.04, 140.0, 0.6, 0.35)
	_add("bounce", b, 0.7)
	b = _buf(0.09)
	_tone(b, 0, 0.09, 90.0, 55.0, 40.0, 1.0, 0.003)
	_noise(b, 0, 0.06, 60.0, 0.15, 0.5)
	_add("step", b, 0.35)
	b = _buf(0.14)
	_tone(b, 0, 0.14, 180.0, 320.0, 20.0, 0.6, 0.01)
	_noise(b, 0, 0.14, 25.0, 0.2, 0.3, 0.02)
	_add("jump", b, 0.4)
	b = _buf(0.16)
	_tone(b, 0, 0.16, 110.0, 50.0, 28.0, 1.0, 0.002)
	_noise(b, 0, 0.1, 40.0, 0.2, 0.5)
	_add("land", b, 0.5)
	# Weapon handling.
	b = _buf(0.4)
	_click(b, 0.0, 2000.0)
	_click(b, 0.22, 1400.0)
	_add("reload", b, 0.7)
	b = _buf(0.07)
	_click(b, 0.0, 2600.0)
	_add("empty", b, 0.55)
	b = _buf(0.16)
	_noise(b, 0, 0.16, 18.0, 0.25, 1.0, 0.03, 0.8)
	_tone(b, 0.1, 0.05, 1500.0, 1000.0, 90.0, 0.5, 0.0005)
	_add("switch", b, 0.55)
	# Feedback.
	b = _buf(0.07)
	_tone(b, 0, 0.07, 2600.0, 2400.0, 70.0, 1.0, 0.0005)
	_tone(b, 0, 0.07, 1300.0, 1200.0, 80.0, 0.4, 0.0005)
	_add("hit", b, 0.6)
	b = _buf(0.2)
	_tone(b, 0, 0.08, 3400.0, 3200.0, 60.0, 1.0, 0.0005)
	_tone(b, 0.07, 0.12, 4600.0, 4400.0, 45.0, 1.0, 0.0005)
	_tone(b, 0.07, 0.12, 2300.0, 2200.0, 50.0, 0.4, 0.0005)
	_add("headshot", b, 0.7)
	b = _buf(0.6)
	_tone(b, 0, 0.6, 880.0, 880.0, 6.0, 0.8, 0.004)
	_tone(b, 0, 0.6, 1760.0, 1760.0, 9.0, 0.15, 0.004)
	_tone(b, 0.12, 0.48, 1318.0, 1318.0, 6.0, 0.8, 0.004)
	_tone(b, 0.12, 0.48, 2636.0, 2636.0, 9.0, 0.15, 0.004)
	_add("kill", b, 0.65)
	b = _buf(0.22)
	_tone(b, 0, 0.22, 120.0, 65.0, 14.0, 1.0, 0.003)
	_noise(b, 0, 0.2, 18.0, 0.06, 1.2)
	_add("hurt", b, 0.8)
	b = _buf(0.55)
	_tone(b, 0.0, 0.55, 523.0, 523.0, 7.0, 0.7, 0.02)
	_tone(b, 0.09, 0.46, 659.0, 659.0, 7.0, 0.7, 0.02)
	_tone(b, 0.18, 0.37, 784.0, 784.0, 7.0, 0.7, 0.02)
	_tone(b, 0.18, 0.37, 1568.0, 1568.0, 12.0, 0.12, 0.02)
	_add("heal", b, 0.5)
	b = _buf(0.45)
	_noise(b, 0, 0.45, 5.0, 0.12, 1.0, 0.12, 0.6)
	_add("throw", b, 0.55)
	b = _buf(1.0)
	_tone(b, 0, 1.0, 320.0, 45.0, 3.0, 1.0, 0.01)
	_tone(b, 0, 1.0, 160.0, 40.0, 4.0, 0.5, 0.01)
	_noise(b, 0, 0.5, 8.0, 0.05, 0.6)
	_add("death", b, 0.8)
